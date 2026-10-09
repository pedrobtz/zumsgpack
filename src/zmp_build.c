/* The build phase: MessagePack to R, design section 6.
 *
 * It runs only after zmp_check() has accepted the whole input, and trusts
 * nothing but what the check established: the input is well-formed and
 * valid, no deeper than max_depth, and plan->counts holds every container's
 * element count in preorder, which is the order this recursion meets them.
 * So no count is read from a head for allocation here, and the recursion
 * depth is bounded by max_depth (at most ZMP_MAX_DEPTH_CAP).
 *
 * Faults the check cannot see -- values R cannot hold -- are raised from
 * here through zmp_raise_fault() in R, which longjmps. That is safe because
 * everything held is either PROTECTed or R_alloc()ed (design section 13). */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zufast/hex.h>
#include <zufast/number.h>

#include "zmp.h"
#include "zmp_build.h"
#include "zmp_head.h"

#define ZMP_INTERRUPT_EVERY 65536u

/* ---- faults ------------------------------------------------------------------ */

void zmp_fail_build(zmp_builder *b, const char *status, const char *detail, size_t at)
{
    zmp_fault f;
    f.status = status;
    f.detail = detail;
    f.offset = (double) at;
    f.limit = NULL;
    f.limit_value = NA_REAL;
    zmp_raise(&f, b->call);
}

/* Raises a fault through R's zmp_raise_fault(), with the user's call. */
void zmp_raise(const zmp_fault *f, SEXP call)
{
    SEXP fault = PROTECT(zmp_fault_sexp(f));
    SEXP name = PROTECT(Rf_mkString("zumsgpack"));
    SEXP ns = PROTECT(R_FindNamespace(name));
    /* The call is data: quote it so evaluating the expression cannot run it
     * (zucbor Stage 3). */
    SEXP quoted = PROTECT(Rf_lang2(Rf_install("quote"), call));
    SEXP expr = PROTECT(Rf_lang3(Rf_install("zmp_raise_fault"), fault, quoted));
    Rf_eval(expr, ns);
    UNPROTECT(5);
    Rf_error("zumsgpack: zmp_raise_fault() returned");
}

static void tick(zmp_builder *b)
{
    if (++b->items % ZMP_INTERRUPT_EVERY == 0)
        R_CheckUserInterrupt();
}

/* ---- scalars ------------------------------------------------------------------- */

/* The only place a CHARSXP is made from MessagePack text, so values, names
 * and keys share the two guards (the zujson invariant). */
SEXP zmp_mkchar(zmp_builder *b, const char *s, size_t n, size_t at)
{
    if (n > INT_MAX)
        zmp_fail_build(b, ZMP_ERR_STRING_TOO_LONG, "a str longer than an R string can be", at);
    if (n && memchr(s, 0, n))
        zmp_fail_build(b, ZMP_ERR_NUL_IN_STR, "a str contains U+0000", at);
    return Rf_mkCharLenCE(s, (int) n, CE_UTF8);
}

static void set_class(SEXP x, const char *cls)
{
    SEXP klass = PROTECT(Rf_mkString(cls));
    Rf_setAttrib(x, R_ClassSymbol, klass);
    UNPROTECT(1);
}

static SEXP scalar_bigint(const char *dec)
{
    SEXP out = PROTECT(Rf_mkString(dec));
    set_class(out, "msgpack_bigint");
    UNPROTECT(1);
    return out;
}

/* The decimal text of (negative ? -1 - raw : raw). */
static void decimal(uint64_t raw, int negative, char *dec)
{
    char *end;
    if (negative) {
        dec[0] = '-';
        if (raw == UINT64_MAX) {
            memcpy(dec + 1, "18446744073709551616", 21);
            return;
        }
        end = zuf_write_u64(dec + 1, raw + 1);
    } else {
        end = zuf_write_u64(dec, raw);
    }
    *end = '\0';
}

/* An integer of value (negative ? -1 - raw : raw), design section 6.1:
 * integer if R's integer holds it, double up to 2^53, then big_integers. */
static SEXP integer_value(zmp_builder *b, uint64_t raw, int negative, int *kind, size_t at)
{
    if (!negative ? raw <= (uint64_t) INT_MAX : raw <= (uint64_t) INT_MAX - 1) {
        *kind = ZMP_KIND_INT;
        return Rf_ScalarInteger(negative ? -1 - (int) raw : (int) raw);
    }
    const uint64_t two53 = UINT64_C(1) << 53;
    if (!negative ? raw <= two53 : raw <= two53 - 1) {
        *kind = ZMP_KIND_INTDBL;
        return Rf_ScalarReal(negative ? -1.0 - (double) raw : (double) raw);
    }
    if (b->big_integers == ZMP_BIG_ERROR)
        zmp_fail_build(b, ZMP_ERR_BIG_INTEGER,
                       "an integer beyond 2^53 with big_integers = \"error\"", at);
    if (b->big_integers == ZMP_BIG_DOUBLE) {
        *kind = ZMP_KIND_INTDBL;
        return Rf_ScalarReal(negative ? -1.0 - (double) raw : (double) raw);
    }
    char dec[24];
    decimal(raw, negative, dec);
    *kind = ZMP_KIND_BIGINT;
    return scalar_bigint(dec);
}

static SEXP read_bytes(const uint8_t *p, size_t n)
{
    SEXP out = Rf_allocVector(RAWSXP, (R_xlen_t) n);
    if (n)
        memcpy(RAW(out), p, n);
    return out;
}

/* ---- arrays ------------------------------------------------------------------ */

/* Marks a one-element array that simplified to a vector with I(), so that
 * msgpack_encode() writes it back as an array rather than unboxing it:
 * MessagePack -> R -> MessagePack is then a fixed point (design 6.2). */
static SEXP as_is(SEXP x)
{
    if (XLENGTH(x) != 1)
        return x;
    PROTECT(x);
    /* Reachable through x, but PROTECTed anyway: rchk cannot see
     * reachability through an attribute. */
    SEXP old = PROTECT(Rf_getAttrib(x, R_ClassSymbol));
    R_xlen_t n = old == R_NilValue ? 0 : XLENGTH(old);
    SEXP klass = PROTECT(Rf_allocVector(STRSXP, n + 1));
    SET_STRING_ELT(klass, 0, Rf_mkChar("AsIs"));
    for (R_xlen_t i = 0; i < n; i++)
        SET_STRING_ELT(klass, i + 1, STRING_ELT(old, i));
    Rf_setAttrib(x, R_ClassSymbol, klass);
    UNPROTECT(3);
    return x;
}

/* An array's elements, staged. Scalars go into C buffers and cost no R
 * allocation; containers, exts and bins are built as R values into `list`.
 * Most arrays simplify to an atomic vector (design section 6.2), so most
 * never need a SEXP per element: zucbor's Stage 8 measured that as the
 * largest cost of decoding. */
typedef struct {
    R_xlen_t n;
    int *kinds;
    double *num;            /* INT, INTDBL, FLOAT (exact for all three) */
    int *lgl;               /* LGL */
    SEXP strs;              /* STR, as CHARSXPs; allocated on first use */
    SEXP list;              /* elements built as R values; allocated on first use */
    char *built;            /* nonzero: element i is in list */
} zmp_stage;

static SEXP stage_scalar(const zmp_stage *st, R_xlen_t i)
{
    switch (st->kinds[i]) {
    case ZMP_KIND_INT:
        return Rf_ScalarInteger((int) st->num[i]);
    case ZMP_KIND_INTDBL:
    case ZMP_KIND_FLOAT:
        return Rf_ScalarReal(st->num[i]);
    case ZMP_KIND_LGL:
        return Rf_ScalarLogical(st->lgl[i]);
    case ZMP_KIND_STR:
        return Rf_ScalarString(STRING_ELT(st->strs, i));
    default:
        return R_NilValue;
    }
}

static double stage_num(const zmp_stage *st, R_xlen_t i)
{
    if (!st->built[i])
        return st->num[i];
    SEXP e = VECTOR_ELT(st->list, i);
    return TYPEOF(e) == INTSXP ? (double) INTEGER(e)[0] : REAL(e)[0];
}

static SEXP stage_charsxp(const zmp_stage *st, R_xlen_t i)
{
    return st->built[i] ? STRING_ELT(VECTOR_ELT(st->list, i), 0) : STRING_ELT(st->strs, i);
}

static SEXP decimal_of(const zmp_stage *st, R_xlen_t i)
{
    if (st->kinds[i] == ZMP_KIND_BIGINT)
        return STRING_ELT(VECTOR_ELT(st->list, i), 0);
    double v = stage_num(st, i);   /* integer-valued, |v| <= 2^53 */
    char dec[24];
    if (v < 0)
        decimal((uint64_t) (-v) - 1, 1, dec);
    else
        decimal((uint64_t) v, 0, dec);
    return Rf_mkChar(dec);
}

/* The staged elements as a list: every element an R value. */
static SEXP stage_list(zmp_stage *st)
{
    if (st->list == R_NilValue)
        st->list = Rf_allocVector(VECSXP, st->n);
    PROTECT(st->list);
    for (R_xlen_t i = 0; i < st->n; i++)
        if (!st->built[i] && st->kinds[i] != ZMP_KIND_NULL)
            SET_VECTOR_ELT(st->list, i, stage_scalar(st, i));
    UNPROTECT(1);
    return st->list;
}

/* The array lattice, design section 6.2 (zucbor section 6.3): an atomic
 * vector when the elements agree, the list otherwise. R_NilValue means
 * "a list". */
static SEXP simplify_staged(const zmp_stage *st)
{
    R_xlen_t n = st->n;
    const int *kinds = st->kinds;
    int has[ZMP_KIND_COUNT] = {0};
    for (R_xlen_t i = 0; i < n; i++)
        has[kinds[i]] = 1;

    if (n == 0)
        return Rf_allocVector(LGLSXP, 0);
    if (has[ZMP_KIND_OTHER])
        return R_NilValue;

    /* Logical is a kind of its own: [false, 1.5] is a list, not c(0, 1.5),
     * since a boolean is not a number in MessagePack (zucbor Stage 4). */
    int numeric = has[ZMP_KIND_INT] || has[ZMP_KIND_INTDBL] || has[ZMP_KIND_FLOAT];
    int others = has[ZMP_KIND_LGL] + has[ZMP_KIND_BIGINT] + has[ZMP_KIND_STR] +
                 has[ZMP_KIND_POSIXCT];
    SEXP out;

    if (!numeric && !others) {                          /* all nil */
        out = Rf_allocVector(LGLSXP, n);
        for (R_xlen_t i = 0; i < n; i++)
            LOGICAL(out)[i] = NA_LOGICAL;
        return out;
    }
    if (has[ZMP_KIND_LGL] && !numeric && others == 1) {
        out = Rf_allocVector(LGLSXP, n);
        for (R_xlen_t i = 0; i < n; i++)
            LOGICAL(out)[i] = kinds[i] == ZMP_KIND_NULL ? NA_LOGICAL
                              : st->built[i] ? LOGICAL(VECTOR_ELT(st->list, i))[0] : st->lgl[i];
        return out;
    }
    if (numeric && !others) {
        int real = has[ZMP_KIND_INTDBL] || has[ZMP_KIND_FLOAT];
        out = Rf_allocVector(real ? REALSXP : INTSXP, n);
        for (R_xlen_t i = 0; i < n; i++) {
            if (real)
                REAL(out)[i] = kinds[i] == ZMP_KIND_NULL ? NA_REAL : stage_num(st, i);
            else
                INTEGER(out)[i] = kinds[i] == ZMP_KIND_NULL ? NA_INTEGER : (int) stage_num(st, i);
        }
        return out;
    }
    /* Integer-valued items and at least one wide integer: all exact. */
    if (has[ZMP_KIND_BIGINT] && !has[ZMP_KIND_FLOAT] && others == 1) {
        out = PROTECT(Rf_allocVector(STRSXP, n));
        for (R_xlen_t i = 0; i < n; i++)
            SET_STRING_ELT(out, i, kinds[i] == ZMP_KIND_NULL ? NA_STRING : decimal_of(st, i));
        set_class(out, "msgpack_bigint");
        UNPROTECT(1);
        return out;
    }
    if (numeric || others != 1)
        return R_NilValue;
    if (has[ZMP_KIND_STR]) {
        out = PROTECT(Rf_allocVector(STRSXP, n));
        for (R_xlen_t i = 0; i < n; i++)
            SET_STRING_ELT(out, i, kinds[i] == ZMP_KIND_NULL ? NA_STRING : stage_charsxp(st, i));
        UNPROTECT(1);
        return out;
    }
    /* POSIXct: always built; keep the first's attributes. */
    SEXP proto = R_NilValue;
    out = PROTECT(Rf_allocVector(REALSXP, n));
    for (R_xlen_t i = 0; i < n; i++) {
        if (kinds[i] == ZMP_KIND_POSIXCT) {
            REAL(out)[i] = REAL(VECTOR_ELT(st->list, i))[0];
            if (proto == R_NilValue)
                proto = VECTOR_ELT(st->list, i);
        } else {
            REAL(out)[i] = NA_REAL;
        }
    }
    DUPLICATE_ATTRIB(out, proto);
    UNPROTECT(1);
    return out;
}

static size_t next_count(zmp_builder *b, size_t at)
{
    if (b->next_count >= b->plan->n)
        zmp_fail_build(b, ZMP_ERR_INVALID_VALUE, "internal: container plan exhausted", at);
    return b->plan->counts[b->next_count++];
}

static SEXP build_array(zmp_builder *b, const zmp_head *h, size_t at, int *kind)
{
    zmp_stage st;
    (void) h;
    st.n = (R_xlen_t) next_count(b, at);
    size_t m = (size_t) st.n + 1;
    st.kinds = (int *) R_alloc(m, sizeof(int));
    st.num = (double *) R_alloc(m, sizeof(double));
    st.lgl = (int *) R_alloc(m, sizeof(int));
    st.built = (char *) R_alloc(m, 1);
    memset(st.built, 0, m);
    st.strs = R_NilValue;
    st.list = R_NilValue;
    PROTECT_INDEX strs_ix, list_ix;
    PROTECT_WITH_INDEX(st.strs, &strs_ix);
    PROTECT_WITH_INDEX(st.list, &list_ix);

    for (R_xlen_t i = 0; i < st.n; i++) {
        size_t el = b->pos;
        zmp_head e;
        zmp_read_head(b->buf + el, b->len - el, &e);
        int staged = 1;
        switch (e.kind) {
        case ZMP_K_UINT:
        case ZMP_K_INT: {
            const uint64_t two53 = UINT64_C(1) << 53;
            int neg = e.negative;
            if (!neg ? e.u <= (uint64_t) INT_MAX : e.u <= (uint64_t) INT_MAX - 1) {
                st.kinds[i] = ZMP_KIND_INT;
                st.num[i] = neg ? -1.0 - (double) e.u : (double) e.u;
            } else if (!neg ? e.u <= two53 : e.u <= two53 - 1) {
                st.kinds[i] = ZMP_KIND_INTDBL;
                st.num[i] = neg ? -1.0 - (double) e.u : (double) e.u;
            } else {
                staged = 0;         /* wide: big_integers decides, in build() */
            }
            break;
        }
        case ZMP_K_F32:
        case ZMP_K_F64:
            st.kinds[i] = ZMP_KIND_FLOAT;
            st.num[i] = e.d;
            break;
        case ZMP_K_FALSE:
        case ZMP_K_TRUE:
            st.kinds[i] = ZMP_KIND_LGL;
            st.lgl[i] = e.kind == ZMP_K_TRUE;
            break;
        case ZMP_K_NIL:
            st.kinds[i] = ZMP_KIND_NULL;
            break;
        case ZMP_K_STR: {
            if (st.strs == R_NilValue) {
                st.strs = Rf_allocVector(STRSXP, st.n);
                REPROTECT(st.strs, strs_ix);
            }
            SET_STRING_ELT(st.strs, i, zmp_mkchar(b, (const char *) b->buf + el + e.hlen,
                                                  e.len, el));
            st.kinds[i] = ZMP_KIND_STR;
            break;
        }
        default:
            staged = 0;
        }
        if (staged) {
            b->pos = el + e.hlen + (e.kind == ZMP_K_STR ? e.len : 0);
            tick(b);
            continue;
        }
        if (st.list == R_NilValue) {
            st.list = Rf_allocVector(VECSXP, st.n);
            REPROTECT(st.list, list_ix);
        }
        SET_VECTOR_ELT(st.list, i, zmp_build_value(b, &st.kinds[i]));
        st.built[i] = 1;
    }

    SEXP out = b->simplify == ZMP_SIMPLIFY_PRESERVE ? simplify_staged(&st) : R_NilValue;
    if (out == R_NilValue)
        out = stage_list(&st);
    else
        out = as_is(out);
    *kind = ZMP_KIND_OTHER;
    UNPROTECT(2);
    return out;
}

/* ---- map keys as names ---------------------------------------------------------- */

typedef struct {
    char *p;
    size_t n, cap;
} zmp_text;

static void text_put(zmp_text *t, const char *s, size_t n)
{
    if (t->n + n > t->cap) {
        size_t cap = t->cap ? t->cap : 64;
        while (cap < t->n + n)
            cap *= 2;
        char *p = (char *) R_alloc(cap, 1);
        if (t->n)
            memcpy(p, t->p, t->n);
        t->p = p;
        t->cap = cap;
    }
    memcpy(t->p + t->n, s, n);
    t->n += n;
}

static void text_puts(zmp_text *t, const char *s)
{
    text_put(t, s, strlen(s));
}

static void text_hex(zmp_text *t, const uint8_t *p, size_t n)
{
    text_puts(t, "h'");
    for (size_t i = 0; i < n; i++) {
        char hx[2];
        zuf_hex_encode(p + i, 1, hx, 2, false);
        text_put(t, hx, 2);
    }
    text_puts(t, "'");
}

/* A float as its shortest round-trip decimal, with ".0" on whole values so
 * that a float key never reads as an integer one. */
void zmp_format_double(double d, char *buf)
{
    size_t n;
    if (isnan(d)) {
        memcpy(buf, "NaN", 4);
        return;
    }
    if (isinf(d)) {
        memcpy(buf, d > 0 ? "Infinity" : "-Infinity", d > 0 ? 9 : 10);
        return;
    }
    n = zuf_format_f64_opt(buf, ZUF_F64_MAX_CHARS, d, ZUF_FMT_TRAILING_ZERO);
    buf[n] = '\0';
}

/* Writes the object at *pos as text, advancing *pos past it: a str as is at
 * the top and quoted inside a container, numbers in decimal, nil and the
 * booleans by name, a bin as h'..', an ext as ext(type, h'..'), arrays and
 * maps as [..] and {k: v, ..}. MessagePack has no notation of its own; this
 * is zumsgpack's, for map_keys = "string" (design section 2). The input has
 * been checked, so every head is complete and the nesting is bounded. */
static void key_text(zmp_builder *b, size_t *pos, zmp_text *t, int top)
{
    zmp_head h;
    char num[40];
    zmp_read_head(b->buf + *pos, b->len - *pos, &h);
    const uint8_t *payload = b->buf + *pos + h.hlen;
    *pos += h.hlen;
    switch (h.kind) {
    case ZMP_K_NIL: text_puts(t, "nil"); break;
    case ZMP_K_FALSE: text_puts(t, "false"); break;
    case ZMP_K_TRUE: text_puts(t, "true"); break;
    case ZMP_K_UINT:
    case ZMP_K_INT:
        decimal(h.u, h.negative, num);
        text_puts(t, num);
        break;
    case ZMP_K_F32:
    case ZMP_K_F64:
        zmp_format_double(h.d, num);
        text_puts(t, num);
        break;
    case ZMP_K_STR:
        if (top) {
            text_put(t, (const char *) payload, h.len);
        } else {
            text_puts(t, "\"");
            for (uint32_t i = 0; i < h.len; i++) {
                if (payload[i] == '"' || payload[i] == '\\')
                    text_puts(t, "\\");
                text_put(t, (const char *) payload + i, 1);
            }
            text_puts(t, "\"");
        }
        *pos += h.len;
        break;
    case ZMP_K_BIN:
        text_hex(t, payload, h.len);
        *pos += h.len;
        break;
    case ZMP_K_EXT:
        snprintf(num, sizeof num, "ext(%d, ", (int) h.ext_type);
        text_puts(t, num);
        text_hex(t, payload, h.len);
        text_puts(t, ")");
        *pos += h.len;
        break;
    case ZMP_K_ARRAY:
        text_puts(t, "[");
        for (uint32_t i = 0; i < h.len; i++) {
            if (i)
                text_puts(t, ", ");
            key_text(b, pos, t, 0);
        }
        text_puts(t, "]");
        break;
    case ZMP_K_MAP:
        text_puts(t, "{");
        for (uint32_t i = 0; i < h.len; i++) {
            if (i)
                text_puts(t, ", ");
            key_text(b, pos, t, 0);
            text_puts(t, ": ");
            key_text(b, pos, t, 0);
        }
        text_puts(t, "}");
        break;
    default:
        break;
    }
}

/* ---- maps ---------------------------------------------------------------------- */

static int charsxp_cmp(const void *a, const void *b)
{
    SEXP x = *(const SEXP *) a, y = *(const SEXP *) b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

/* R caches CHARSXPs, so equal UTF-8 names are the same pointer. The
 * pointers are R's, not the input's, so qsort()'s worst case is not the
 * adversary's to choose. */
static int any_duplicated(SEXP names, R_xlen_t n)
{
    if (n < 2)
        return 0;
    SEXP *p = (SEXP *) R_alloc((size_t) n, sizeof(SEXP));
    for (R_xlen_t i = 0; i < n; i++)
        p[i] = STRING_ELT(names, i);
    qsort(p, (size_t) n, sizeof(SEXP), charsxp_cmp);
    for (R_xlen_t i = 1; i < n; i++)
        if (p[i] == p[i - 1])
            return 1;
    return 0;
}

static SEXP make_map(SEXP keys, SEXP values)
{
    const char *names[] = {"keys", "values", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, keys);
    SET_VECTOR_ELT(out, 1, values);
    set_class(out, "msgpack_map");
    UNPROTECT(1);
    return out;
}

static SEXP build_map(zmp_builder *b, size_t at, int *kind)
{
    R_xlen_t n = (R_xlen_t) next_count(b, at);
    SEXP values = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
    /* The keys as R values, needed only for a msgpack_map: built the first
     * time a key is not a str (or always, under map_keys = "map"). Plain str
     * keys, the common case, go straight into names. */
    SEXP keys = R_NilValue;
    PROTECT_INDEX keys_ix;
    PROTECT_WITH_INDEX(keys, &keys_ix);
    int faithful = b->map_keys != ZMP_KEYS_MAP;
    int key_kind, value_kind;
    for (R_xlen_t i = 0; i < n; i++) {
        size_t key_start = b->pos;
        zmp_head h;
        zmp_read_head(b->buf + key_start, b->len - key_start, &h);
        if (keys == R_NilValue && b->map_keys != ZMP_KEYS_MAP && h.kind == ZMP_K_STR) {
            tick(b);
            SET_STRING_ELT(names, i, zmp_mkchar(b, (const char *) b->buf + key_start + h.hlen,
                                                h.len, key_start));
            b->pos = key_start + h.hlen + h.len;
            if (h.len == 0)
                faithful = 0;       /* R reads "" as no name */
        } else {
            if (keys == R_NilValue) {
                keys = Rf_allocVector(VECSXP, n);
                REPROTECT(keys, keys_ix);
                for (R_xlen_t k = 0; k < i; k++)
                    SET_VECTOR_ELT(keys, k, Rf_ScalarString(STRING_ELT(names, k)));
            }
            SEXP key = zmp_build_value(b, &key_kind);
            SET_VECTOR_ELT(keys, i, key);
            if (key_kind == ZMP_KIND_STR) {
                SET_STRING_ELT(names, i, STRING_ELT(key, 0));
                if (LENGTH(STRING_ELT(key, 0)) == 0)
                    faithful = 0;
            } else if (b->map_keys == ZMP_KEYS_STRING) {
                zmp_text t = {NULL, 0, 0};
                size_t p = key_start;
                key_text(b, &p, &t, 1);
                SET_STRING_ELT(names, i, zmp_mkchar(b, t.p ? t.p : "", t.n, key_start));
            } else {
                faithful = 0;
            }
        }
        SET_VECTOR_ELT(values, i, zmp_build_value(b, &value_kind));
    }
    *kind = ZMP_KIND_OTHER;

    if (b->map_keys == ZMP_KEYS_STRING) {
        /* Naming may make distinct keys equal: "1" and 1 both become the
         * name "1". That is refused whatever duplicate_keys says, since a
         * named list cannot say which entry was which (zucbor section 6.4). */
        if (any_duplicated(names, n))
            zmp_fail_build(b, ZMP_ERR_KEY_COLLISION, NULL, at);
    } else if (faithful && b->duplicate_keys && any_duplicated(names, n)) {
        faithful = 0;
    }

    SEXP out;
    if (faithful || b->map_keys == ZMP_KEYS_STRING) {
        Rf_setAttrib(values, R_NamesSymbol, names);
        out = values;
    } else {
        if (keys == R_NilValue) {       /* every key was a str, but not faithful */
            keys = Rf_allocVector(VECSXP, n);
            REPROTECT(keys, keys_ix);
            for (R_xlen_t k = 0; k < n; k++)
                SET_VECTOR_ELT(keys, k, Rf_ScalarString(STRING_ELT(names, k)));
        }
        out = make_map(keys, values);
    }
    UNPROTECT(3);
    return out;
}

/* ---- dispatch -------------------------------------------------------------------- */

SEXP zmp_build_value(zmp_builder *b, int *kind)
{
    size_t at = b->pos;
    zmp_head h;
    zmp_read_head(b->buf + at, b->len - at, &h);
    tick(b);
    b->pos = at + h.hlen;
    const uint8_t *payload = b->buf + b->pos;

    switch (h.kind) {
    case ZMP_K_ARRAY:
        return build_array(b, &h, at, kind);
    case ZMP_K_MAP:
        return build_map(b, at, kind);
    case ZMP_K_STR: {
        SEXP out = PROTECT(Rf_allocVector(STRSXP, 1));
        SET_STRING_ELT(out, 0, zmp_mkchar(b, (const char *) payload, h.len, at));
        b->pos += h.len;
        *kind = ZMP_KIND_STR;
        UNPROTECT(1);
        return out;
    }
    case ZMP_K_BIN:
        b->pos += h.len;
        *kind = ZMP_KIND_OTHER;
        return read_bytes(payload, h.len);
    case ZMP_K_EXT:
        b->pos += h.len;
        return zmp_build_ext(b, h.ext_type, payload, h.len, at, kind);
    case ZMP_K_UINT:
    case ZMP_K_INT:
        return integer_value(b, h.u, h.negative, kind, at);
    case ZMP_K_F32:
    case ZMP_K_F64:
        *kind = ZMP_KIND_FLOAT;
        return Rf_ScalarReal(h.d);
    case ZMP_K_FALSE:
    case ZMP_K_TRUE:
        *kind = ZMP_KIND_LGL;
        return Rf_ScalarLogical(h.kind == ZMP_K_TRUE);
    case ZMP_K_NIL:
        *kind = ZMP_KIND_NULL;
        return R_NilValue;
    default:
        zmp_fail_build(b, ZMP_ERR_INVALID_VALUE, "internal: an unexpected head", at);
        return R_NilValue;
    }
}

/* ---- entry point --------------------------------------------------------------- */

/* opts: mode (0 one object, 1 a sequence, 2 a prefix), duplicate_keys,
 * max_depth, simplify, map_keys, big_integers, ext (integer codes,
 * validated in R). handlers: NULL, or list(types, functions, namespace)
 * from R. Returns list(fault, value, consumed): a check-phase fault is
 * returned for R to raise with the user's call; a build-phase one is
 * raised here. */
SEXP zmp_decode_raw(SEXP x, SEXP opts, SEXP max_items, SEXP call, SEXP handlers)
{
    if (TYPEOF(x) != RAWSXP || TYPEOF(opts) != INTSXP || XLENGTH(opts) != 7)
        Rf_error("zmp_decode_raw: arguments must be validated in R");
    if (handlers != R_NilValue
        && (TYPEOF(handlers) != VECSXP || XLENGTH(handlers) != 3
            || TYPEOF(VECTOR_ELT(handlers, 0)) != INTSXP
            || TYPEOF(VECTOR_ELT(handlers, 1)) != VECSXP
            || XLENGTH(VECTOR_ELT(handlers, 0)) != XLENGTH(VECTOR_ELT(handlers, 1))
            || TYPEOF(VECTOR_ELT(handlers, 2)) != ENVSXP))
        Rf_error("zmp_decode_raw: arguments must be validated in R");
    const int *o = INTEGER(opts);
    zmp_check_opts opt;
    if (o[0] < ZMP_MODE_ONE || o[0] > ZMP_MODE_PREFIX)
        Rf_error("zmp_decode_raw: arguments must be validated in R");
    opt.mode = o[0];
    opt.duplicate_keys = o[1];
    opt.max_depth = o[2];
    double mi = Rf_asReal(max_items);
    if (opt.max_depth < 1 || opt.max_depth > ZMP_MAX_DEPTH_CAP || ISNAN(mi) || mi < 1)
        Rf_error("zmp_decode_raw: limits must be validated in R");
    opt.max_items = R_FINITE(mi) ? (uint64_t) mi : UINT64_MAX;

    const uint8_t *buf = RAW(x);
    size_t len = (size_t) XLENGTH(x);
    zmp_plan plan;
    zmp_fault fault;
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
    if (zmp_check(buf, len, &opt, &plan, &fault)) {
        SET_VECTOR_ELT(out, 0, zmp_fault_sexp(&fault));
        UNPROTECT(1);
        return out;
    }

    zmp_builder b;
    memset(&b, 0, sizeof b);
    b.buf = buf;
    b.len = len;
    b.plan = &plan;
    b.duplicate_keys = opt.duplicate_keys;
    b.simplify = o[3];
    b.map_keys = o[4];
    b.big_integers = o[5];
    b.ext_convert = o[6] == 0;
    b.call = call;
    if (handlers != R_NilValue) {
        /* A slot per type; the functions stay protected through handlers,
         * which the caller holds. */
        const int *types = INTEGER(VECTOR_ELT(handlers, 0));
        SEXP fns = VECTOR_ELT(handlers, 1);
        b.handlers = (SEXP *) R_alloc(256, sizeof(SEXP));
        for (int k = 0; k < 256; k++)
            b.handlers[k] = R_NilValue;
        for (R_xlen_t k = 0; k < XLENGTH(fns); k++) {
            if (types[k] < -128 || types[k] > 127)
                Rf_error("zmp_decode_raw: arguments must be validated in R");
            b.handlers[types[k] + 128] = VECTOR_ELT(fns, k);
        }
        b.ns = VECTOR_ELT(handlers, 2);
    }

    int kind;
    if (opt.mode != ZMP_MODE_SEQ) {
        SET_VECTOR_ELT(out, 1, zmp_build_value(&b, &kind));
    } else {
        SEXP items = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) plan.n_items));
        SET_VECTOR_ELT(out, 1, items);
        for (size_t i = 0; i < plan.n_items; i++)
            SET_VECTOR_ELT(items, (R_xlen_t) i, zmp_build_value(&b, &kind));
        UNPROTECT(1);
    }
    SET_VECTOR_ELT(out, 2, Rf_ScalarReal((double) plan.consumed));
    UNPROTECT(1);
    return out;
}
