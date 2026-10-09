/* The check phase: design sections 4, 6.1, 9 and 12.
 *
 * One iterative walk with an explicit container stack checks that the input
 * is well-formed MessagePack within the limits, that every str is UTF-8,
 * that every timestamp is one of the three legal layouts, and that no map
 * has the same key twice; and it records each container's element count for
 * the build phase. Nothing here allocates an R object, and no R API is used
 * but scratch memory and the interrupt check, both behind zmp_check.h: built
 * with -DZMP_STANDALONE, they are the fuzz harness's.
 *
 * Every security check is marked with a single-line GUARD comment, so that
 * tools/run-mutation-check can disable each in turn and show its hostile
 * input stops being refused. */

#include <math.h>
#include <string.h>

#include <zufast/utf8.h>

#include "zmp_check.h"
#include "zmp_head.h"

#define ZMP_INTERRUPT_EVERY 65536u

/* Map keys are compared by value (design section 6.1). Keys of different
 * kinds are never equal: the integer 1 and the float 1.0 are different
 * MessagePack values, and so are a str and a bin with the same bytes. */
enum { KEY_NIL, KEY_BOOL, KEY_INT, KEY_FLOAT, KEY_STR, KEY_BIN, KEY_EXT, KEY_ENCODED };

typedef struct {
    const uint8_t *ptr;     /* payload, or a container key's encoded bytes */
    size_t len;
    uint64_t u;             /* integer magnitude, boolean, double bits */
    size_t offset;          /* where the key starts */
    uint8_t kind;
    uint8_t negative;
    int8_t ext_type;
} zmp_key;

typedef struct {
    uint64_t remaining;     /* elements still to walk (keys and values) */
    uint64_t count;         /* elements walked */
    size_t slot;            /* this container's plan->counts index */
    size_t key_base;        /* this map's first key descriptor */
    size_t start;           /* offset of the container's head */
    uint8_t is_map;
} zmp_frame;

typedef struct {
    const uint8_t *buf;
    size_t len, pos;
    const zmp_check_opts *opt;
    zmp_fault *fault;
    zmp_plan *plan;
    zmp_frame *frames;
    int sp;
    uint64_t items;
    zmp_key *keys;
    size_t n_keys, cap_keys;
    zmp_key *sort_tmp;      /* merge-sort buffer, reused across maps */
    size_t sort_cap;
} zmp_walker;

/* ---- faults ------------------------------------------------------------------ */

static int fail(zmp_walker *w, const char *status, const char *detail, size_t at)
{
    w->fault->status = status;
    w->fault->detail = detail;
    w->fault->offset = (double) at;
    w->fault->limit = NULL;
    w->fault->limit_value = ZMP_NO_OFFSET;
    return 1;
}

static int fail_limit(zmp_walker *w, const char *status, const char *limit,
                      double value, size_t at)
{
    fail(w, status, NULL, at);
    w->fault->limit = limit;
    w->fault->limit_value = value;
    return 1;
}

/* ---- scratch ----------------------------------------------------------------- */

/* Growth by doubling into fresh scratch blocks. The old block stays until
 * the .Call ends, so the waste is bounded by the final size. */
static void *grow(void *old, size_t used, size_t *cap, size_t size)
{
    size_t newcap = *cap ? *cap * 2 : 64;
    void *p = zmp_scratch(newcap, size);
    if (used)
        memcpy(p, old, used * size);
    *cap = newcap;
    return p;
}

static int count_item(zmp_walker *w, size_t at)
{
    w->items++;
    if (w->items > w->opt->max_items)  /* GUARD: items */
        return fail_limit(w, ZMP_ERR_ITEM_LIMIT, "max_items",
                          (double) w->opt->max_items, at);
    if (w->items % ZMP_INTERRUPT_EVERY == 0)
        zmp_interrupt_check();
    return 0;
}

/* ---- duplicate keys ------------------------------------------------------------ */

static int bytes_cmp(const uint8_t *a, size_t na, const uint8_t *b, size_t nb)
{
    size_t n = na < nb ? na : nb;
    int r = n ? memcmp(a, b, n) : 0;
    if (r)
        return r;
    return na < nb ? -1 : (na > nb ? 1 : 0);
}

static int key_cmp(const zmp_key *a, const zmp_key *b)
{
    if (a->kind != b->kind)
        return a->kind < b->kind ? -1 : 1;
    switch (a->kind) {
    case KEY_NIL:
        return 0;
    case KEY_INT:
        if (a->negative != b->negative)
            return a->negative < b->negative ? -1 : 1;
        /* fall through */
    case KEY_BOOL:
    case KEY_FLOAT:
        return a->u < b->u ? -1 : (a->u > b->u ? 1 : 0);
    case KEY_EXT:
        if (a->ext_type != b->ext_type)
            return a->ext_type < b->ext_type ? -1 : 1;
        /* fall through */
    default:
        return bytes_cmp(a->ptr, a->len, b->ptr, b->len);
    }
}

/* Bottom-up merge sort: O(n log n) on any input. A library qsort() may be
 * quadratic on an adversarial order, and the keys are the adversary's.
 * Small maps take an insertion sort in place; larger ones share one buffer,
 * grown as needed, rather than allocating per map. */
static void sort_keys(zmp_walker *w, zmp_key *a, size_t n)
{
    if (n <= 16) {
        for (size_t i = 1; i < n; i++) {
            zmp_key k = a[i];
            size_t j = i;
            while (j > 0 && key_cmp(&k, &a[j - 1]) < 0) {
                a[j] = a[j - 1];
                j--;
            }
            a[j] = k;
        }
        return;
    }
    if (n > w->sort_cap) {
        w->sort_cap = n < 2 * w->sort_cap ? 2 * w->sort_cap : n;
        w->sort_tmp = (zmp_key *) zmp_scratch(w->sort_cap, sizeof(zmp_key));
    }
    zmp_key *src = a, *dst = w->sort_tmp;
    for (size_t width = 1; width < n; width *= 2) {
        for (size_t lo = 0; lo < n; lo += 2 * width) {
            size_t mid = lo + width < n ? lo + width : n;
            size_t hi = lo + 2 * width < n ? lo + 2 * width : n;
            size_t i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                dst[k++] = key_cmp(&src[j], &src[i]) < 0 ? src[j++] : src[i++];
            while (i < mid)
                dst[k++] = src[i++];
            while (j < hi)
                dst[k++] = src[j++];
        }
        zmp_key *t = src;
        src = dst;
        dst = t;
    }
    if (src != a)
        memcpy(a, src, n * sizeof(zmp_key));
}

static int check_duplicates(zmp_walker *w, size_t base)
{
    size_t n = w->n_keys - base;
    if (n < 2)
        return 0;               /* and w->keys may still be NULL */
    zmp_key *k = w->keys + base;
    sort_keys(w, k, n);
    for (size_t i = 1; i < n; i++) {
        int dup = key_cmp(&k[i - 1], &k[i]) == 0;
        if (dup) {  /* GUARD: duplicate-keys */
            size_t later = k[i].offset > k[i - 1].offset ? k[i].offset : k[i - 1].offset;
            return fail(w, ZMP_ERR_DUPLICATE_KEY, NULL, later);
        }
    }
    return 0;
}

/* Nonzero if the element about to be walked, or just closed, is a map key
 * that must be recorded for duplicate detection. */
static int at_key(const zmp_walker *w)
{
    if (w->opt->duplicate_keys || w->sp == 0)
        return 0;
    const zmp_frame *p = &w->frames[w->sp - 1];
    return p->is_map && p->count % 2 == 0;
}

static zmp_key *push_key(zmp_walker *w, size_t start, uint8_t kind)
{
    if (w->n_keys == w->cap_keys)
        w->keys = (zmp_key *) grow(w->keys, w->n_keys, &w->cap_keys, sizeof(zmp_key));
    zmp_key *k = &w->keys[w->n_keys++];
    memset(k, 0, sizeof *k);
    k->offset = start;
    k->kind = kind;
    return k;
}

static uint64_t double_bits(double d)
{
    uint64_t u;
    if (isnan(d))
        return UINT64_C(0x7ff8000000000000);   /* every NaN is one key */
    memcpy(&u, &d, sizeof u);
    return u;
}

/* A scalar or ext key, by value: an integer in any width or signedness, a
 * float 32 and the float 64 it widens to, a fixext and an ext 8 with the
 * same type and payload are each one key. */
static void record_scalar_key(zmp_walker *w, size_t start, const zmp_head *h)
{
    const uint8_t *payload = w->buf + start + h->hlen;
    zmp_key *k;
    switch (h->kind) {
    case ZMP_K_NIL:
        push_key(w, start, KEY_NIL);
        break;
    case ZMP_K_FALSE:
    case ZMP_K_TRUE:
        push_key(w, start, KEY_BOOL)->u = h->kind == ZMP_K_TRUE;
        break;
    case ZMP_K_UINT:
    case ZMP_K_INT:
        k = push_key(w, start, KEY_INT);
        k->u = h->u;
        k->negative = h->negative;
        break;
    case ZMP_K_F32:
    case ZMP_K_F64:
        push_key(w, start, KEY_FLOAT)->u = double_bits(h->d);
        break;
    case ZMP_K_STR:
    case ZMP_K_BIN:
    case ZMP_K_EXT:
        k = push_key(w, start, h->kind == ZMP_K_STR ? KEY_STR :
                               h->kind == ZMP_K_BIN ? KEY_BIN : KEY_EXT);
        k->ptr = payload;
        k->len = h->len;
        k->ext_type = h->ext_type;
        break;
    default:
        break;
    }
}

/* ---- the walk ------------------------------------------------------------------- */

static void element_done(zmp_walker *w)
{
    if (w->sp) {
        zmp_frame *p = &w->frames[w->sp - 1];
        p->count++;
        p->remaining--;
    }
}

/* Closes every container whose last element has just been walked. A closed
 * container is itself a complete element of its parent, and when it is a
 * map key it is compared by its encoded bytes, as zucbor compares one. */
static int close_finished(zmp_walker *w)
{
    while (w->sp > 0 && w->frames[w->sp - 1].remaining == 0) {
        zmp_frame *f = &w->frames[w->sp - 1];
        if (f->is_map && !w->opt->duplicate_keys) {
            if (check_duplicates(w, f->key_base))
                return 1;
            w->n_keys = f->key_base;
        }
        if (w->plan)
            w->plan->counts[f->slot] = (size_t) (f->is_map ? f->count / 2 : f->count);
        size_t start = f->start;
        w->sp--;
        if (at_key(w)) {
            zmp_key *k = push_key(w, start, KEY_ENCODED);
            k->ptr = w->buf + start;
            k->len = w->pos - start;
        }
        element_done(w);
    }
    return 0;
}

/* Timestamp extension (type -1), design section 6.1: a payload of 4, 8 or
 * 12 bytes, and nanoseconds within a second in the two layouts that carry
 * them. */
static int check_timestamp(zmp_walker *w, const uint8_t *p, uint32_t n, size_t at)
{
    int length_ok = n == 4 || n == 8 || n == 12;
    if (!length_ok)  /* GUARD: timestamp-length */
        return fail(w, ZMP_ERR_TIMESTAMP_LENGTH,
                    "a timestamp (ext -1) payload must be 4, 8 or 12 bytes", at);
    uint32_t nanos = n == 8 ? (uint32_t) (zuf_load_be64(p) >> 34)
                   : n == 12 ? zuf_load_be32(p) : 0;
    if (nanos > 999999999u)  /* GUARD: timestamp-nanos */
        return fail(w, ZMP_ERR_TIMESTAMP_NANOS,
                    "timestamp nanoseconds above 999999999", at);
    return 0;
}

/* Walks one top-level object from w->pos. */
static int walk_object(zmp_walker *w)
{
    for (;;) {
        size_t start = w->pos;
        if (start >= w->len)
            return fail(w, ZMP_ERR_TRUNCATED, "the input ends inside an object", start);
        int is_key = at_key(w);
        zmp_head h;
        int st = zmp_read_head(w->buf + start, w->len - start, &h);
        if (st == ZMP_HEAD_RESERVED)  /* GUARD: reserved */
            return fail(w, ZMP_ERR_RESERVED, "byte 0xc1 is never used", start);
        if (st == ZMP_HEAD_TRUNCATED)
            return fail(w, ZMP_ERR_TRUNCATED, "the input ends inside a head", start);
        if (count_item(w, start))
            return 1;
        size_t avail = w->len - start - h.hlen;
        const uint8_t *payload = w->buf + start + h.hlen;

        switch (h.kind) {
        case ZMP_K_STR:
        case ZMP_K_BIN:
        case ZMP_K_EXT:
            /* Checked against the bytes left before the payload is read. */
            if (h.len > avail)  /* GUARD: length-headers */
                return fail(w, ZMP_ERR_TRUNCATED, "a length is longer than the input", start);
            if (h.kind == ZMP_K_STR && !zuf_utf8_valid((const char *) payload, h.len))  /* GUARD: utf8 */
                return fail(w, ZMP_ERR_INVALID_UTF8, "a str is not valid UTF-8", start);
            if (h.kind == ZMP_K_EXT) {
                /* An ext is one level of depth, as a tag is in zucbor. */
                if (w->sp + 1 > w->opt->max_depth)  /* GUARD: depth-ext */
                    return fail_limit(w, ZMP_ERR_DEPTH_LIMIT, "max_depth",
                                      w->opt->max_depth, start);
                if (h.ext_type == -1 && check_timestamp(w, payload, h.len, start))
                    return 1;
            }
            w->pos = start + h.hlen + h.len;
            break;
        case ZMP_K_ARRAY:
        case ZMP_K_MAP: {
            int is_map = h.kind == ZMP_K_MAP;
            /* Every element costs at least one byte, so a count the rest of
             * the input cannot hold is truncation, found before anything is
             * sized from it. */
            if (h.len > (is_map ? avail / 2 : avail))  /* GUARD: container-count */
                return fail(w, ZMP_ERR_TRUNCATED, "a count is larger than the input", start);
            if (w->sp + 1 > w->opt->max_depth)  /* GUARD: depth */
                return fail_limit(w, ZMP_ERR_DEPTH_LIMIT, "max_depth",
                                  w->opt->max_depth, start);
            zmp_frame *f = &w->frames[w->sp];
            memset(f, 0, sizeof *f);
            f->is_map = (uint8_t) is_map;
            f->remaining = (uint64_t) h.len * (is_map ? 2u : 1u);
            f->key_base = w->n_keys;
            f->start = start;
            if (w->plan) {
                if (w->plan->n == w->plan->cap)
                    w->plan->counts = (size_t *) grow(w->plan->counts, w->plan->n,
                                                      &w->plan->cap, sizeof(size_t));
                f->slot = w->plan->n++;
            }
            w->sp++;
            w->pos = start + h.hlen;
            if (close_finished(w))      /* an empty container closes at once */
                return 1;
            if (w->sp == 0)
                return 0;
            continue;
        }
        default:
            w->pos = start + h.hlen;
            break;
        }

        if (is_key)
            record_scalar_key(w, start, &h);
        element_done(w);
        if (close_finished(w))
            return 1;
        if (w->sp == 0)
            return 0;
    }
}

int zmp_check(const uint8_t *buf, size_t len, const zmp_check_opts *opt,
              zmp_plan *plan, zmp_fault *fault)
{
    zmp_walker w;
    memset(&w, 0, sizeof w);
    w.buf = buf;
    w.len = len;
    w.opt = opt;
    w.fault = fault;
    w.plan = plan;
    /* Sized from max_depth, so the depth guard is also what keeps the stack
     * in bounds. */
    w.frames = (zmp_frame *) zmp_scratch((size_t) opt->max_depth + 1, sizeof(zmp_frame));
    fault->status = NULL;
    if (plan) {
        plan->counts = NULL;
        plan->n = plan->cap = 0;
        plan->n_items = 0;
        plan->consumed = 0;
    }
    int many = opt->mode == ZMP_MODE_SEQ || opt->mode == ZMP_MODE_STREAM;

    if (len == 0) {
        if (many)
            return 0;
        return fail(&w, ZMP_ERR_TRUNCATED, "the input is empty", 0);
    }

    while (w.pos < len) {
        size_t object_start = w.pos;
        size_t plan_mark = plan ? plan->n : 0;
        /* In a stream each object is checked on its own: max_items is per
         * object (design section 12). */
        if (opt->mode == ZMP_MODE_STREAM)
            w.items = 0;
        if (walk_object(&w)) {
            /* A stream stops, without a fault, before an object the input
             * ends inside; anything else is a fault (design section 4). */
            if (opt->mode == ZMP_MODE_STREAM && strcmp(fault->status, ZMP_ERR_TRUNCATED) == 0) {
                fault->status = NULL;
                if (plan)
                    plan->n = plan_mark;
                w.pos = object_start;
                break;
            }
            return 1;
        }
        if (plan) {
            plan->n_items++;
            plan->consumed = w.pos;
        }
        /* A prefix stops here: whatever follows is the caller's framing,
         * and it has not been read. */
        if (opt->mode == ZMP_MODE_PREFIX)
            return 0;
        if (opt->mode == ZMP_MODE_ONE && w.pos < len)  /* GUARD: trailing-bytes */
            return fail(&w, ZMP_ERR_TRAILING, "bytes after the object", w.pos);
    }
    return 0;
}
