/* R to MessagePack, deterministically: design sections 7 and 8.
 *
 * One pass into a zubin buffer owned by a finalized external pointer
 * (zb_r_buf_new()), so an error raised from anywhere -- an unsupported type
 * deep in a list, an as_msgpack() method, an interrupt -- frees it (design
 * section 13); the result is one copy into a RAWSXP of exactly the right
 * size, after which the buffer is freed eagerly. A map's non-str keys are
 * each encoded once into a buffer of their own, owned the same way, then
 * merge-sorted by their bytes and checked for duplicates before the map is
 * written (design section 8, rule 4).
 *
 * Every multi-byte field is written big-endian through zubin's puts, byte
 * by byte, so a big-endian host writes the same bytes. */

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <zufast/utf8.h>
#include <zubin.h>
#include <zubin-r.h>

#include "zmp.h"
#include "zmp_encode.h"

typedef struct {
    const uint8_t *key;
    size_t key_len;
    R_xlen_t index;
} zmp_entry;

/* ---- faults ------------------------------------------------------------------ */

void zmp_fail_encode(zmp_encoder *e, const char *status, const char *detail)
{
    zmp_fault f;
    f.status = status;
    f.detail = detail;
    f.offset = NA_REAL;
    f.limit = NULL;
    f.limit_value = NA_REAL;
    if (strcmp(status, ZMP_ERR_DEPTH_LIMIT) == 0) {
        f.limit = "max_depth";
        f.limit_value = e->max_depth;
    }
    zmp_raise(&f, e->call);
}

/* ---- output ------------------------------------------------------------------ */

static void check(zmp_encoder *e, zb_status st)
{
    if (st)
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "not enough memory for the encoding");
}

void zmp_put(zmp_encoder *e, const void *p, size_t n)
{
    check(e, zb_put_bytes(e->out, p, n));
}

void zmp_put_byte(zmp_encoder *e, uint8_t b)
{
    check(e, zb_put_u8(e->out, b));
}

/* A head byte followed by a big-endian field of 1, 2, 4 or 8 bytes. */
static void put_head(zmp_encoder *e, uint8_t byte, int width, uint64_t v)
{
    zmp_put_byte(e, byte);
    switch (width) {
    case 1: check(e, zb_put_u8(e->out, (uint8_t) v)); break;
    case 2: check(e, zb_put_u16be(e->out, (uint16_t) v)); break;
    case 4: check(e, zb_put_u32be(e->out, (uint32_t) v)); break;
    case 8: check(e, zb_put_u64be(e->out, v)); break;
    default: break;
    }
}

/* ---- integers (design section 8, rule 1) --------------------------------------- */

/* The smallest form of a non-negative integer: positive fixint, then the
 * unsigned family. */
static void put_uint(zmp_encoder *e, uint64_t v)
{
    if (v <= 0x7f)
        zmp_put_byte(e, (uint8_t) v);
    else if (v <= 0xff)
        put_head(e, 0xcc, 1, v);
    else if (v <= 0xffff)
        put_head(e, 0xcd, 2, v);
    else if (v <= 0xffffffffu)
        put_head(e, 0xce, 4, v);
    else
        put_head(e, 0xcf, 8, v);
}

/* The smallest form of the negative integer -1 - raw (raw < 2^63):
 * negative fixint, then the signed family. */
static void put_negative(zmp_encoder *e, uint64_t raw)
{
    if (raw < 32)
        zmp_put_byte(e, (uint8_t) (0xe0 | (31 - raw)));      /* -1 is 0xff */
    else if (raw < 128)
        put_head(e, 0xd0, 1, (uint64_t) (uint8_t) (0xff - raw));
    else if (raw < 32768)
        put_head(e, 0xd1, 2, (uint64_t) (uint16_t) (0xffff - raw));
    else if (raw < UINT64_C(2147483648))
        put_head(e, 0xd2, 4, (uint64_t) (uint32_t) (0xffffffffu - raw));
    else
        put_head(e, 0xd3, 8, UINT64_MAX - raw);
}

void zmp_put_int(zmp_encoder *e, int negative, uint64_t raw)
{
    if (negative)
        put_negative(e, raw);
    else
        put_uint(e, raw);
}

/* ---- floats (design section 8, rule 2) ------------------------------------------ */

/* float 64 by default; float 32 under floats = "shortest" when it holds d
 * exactly. Every NaN is written as one canonical quiet NaN: R's NaN has a
 * sign bit on x86 and none on ARM, and bytes must not depend on the host.
 * (NA_real_ is not a float: it is nil.) */
static void put_float(zmp_encoder *e, double d)
{
    if (isnan(d)) {
        if (e->floats_shortest)
            put_head(e, 0xca, 4, UINT32_C(0x7fc00000));
        else
            put_head(e, 0xcb, 8, UINT64_C(0x7ff8000000000000));
        return;
    }
    if (e->floats_shortest) {
        float f = (float) d;
        if ((double) f == d) {
            uint32_t u;
            memcpy(&u, &f, 4);
            put_head(e, 0xca, 4, u);
            return;
        }
    }
    uint64_t u;
    memcpy(&u, &d, 8);
    put_head(e, 0xcb, 8, u);
}

/* A double: an integer when it is whole, within -2^63 .. 2^64 - 1 and not
 * -0 (design section 7.1, D6), else a float. */
void zmp_put_double(zmp_encoder *e, double d)
{
    const double two63 = 9223372036854775808.0, two64 = 18446744073709551616.0;
    if (R_FINITE(d) && d == trunc(d) && d >= -two63 && d < two64 && !(d == 0 && signbit(d))) {
        if (d >= 0)
            put_uint(e, (uint64_t) d);
        else
            put_negative(e, (uint64_t) (-d) - 1);   /* -d <= 2^63 */
        return;
    }
    put_float(e, d);
}

/* ---- str, bin ------------------------------------------------------------------ */

static void put_str_head(zmp_encoder *e, size_t n)
{
    if (n <= 31)
        zmp_put_byte(e, (uint8_t) (0xa0 | n));
    else if (n <= 0xff)
        put_head(e, 0xd9, 1, n);
    else if (n <= 0xffff)
        put_head(e, 0xda, 2, n);
    else if ((uint64_t) n <= 0xffffffffu)
        put_head(e, 0xdb, 4, n);
    else
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "a string longer than MessagePack's 2^32 - 1 bytes");
}

/* A CHARSXP as UTF-8 bytes, valid or refused. Allocates in R_alloc(); the
 * caller restores vmax when done with the bytes. */
static const char *utf8_of(zmp_encoder *e, SEXP s, size_t *n)
{
    if (Rf_getCharCE(s) == CE_BYTES)
        zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "a string marked as \"bytes\" has no text encoding");
    const char *u = Rf_translateCharUTF8(s);
    *n = strlen(u);
    if (!zuf_utf8_valid(u, *n))
        zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "a string is not valid UTF-8");
    return u;
}

void zmp_put_str(zmp_encoder *e, SEXP s)
{
    const void *vmax = vmaxget();
    size_t n;
    const char *u = utf8_of(e, s, &n);
    put_str_head(e, n);
    zmp_put(e, u, n);
    vmaxset(vmax);
}

static void put_bin(zmp_encoder *e, const uint8_t *p, size_t n)
{
    if (n <= 0xff)
        put_head(e, 0xc4, 1, n);
    else if (n <= 0xffff)
        put_head(e, 0xc5, 2, n);
    else if ((uint64_t) n <= 0xffffffffu)
        put_head(e, 0xc6, 4, n);
    else
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "a raw vector longer than MessagePack's 2^32 - 1 bytes");
    zmp_put(e, p, n);
}

/* ---- ext ----------------------------------------------------------------------- */

/* fixext for payloads of 1, 2, 4, 8 and 16 bytes, else the smallest ext 8,
 * 16 or 32. depth is the ext's level: an ext is a level, as the decoder
 * counts it. */
void zmp_put_ext(zmp_encoder *e, int type, const uint8_t *p, size_t n, int depth)
{
    zmp_check_depth(e, depth);
    if (type < -128 || type > 127)
        zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "an ext type is not from -128 to 127");
    uint8_t t = (uint8_t) (type & 0xff);
    switch (n) {
    case 1: zmp_put_byte(e, 0xd4); break;
    case 2: zmp_put_byte(e, 0xd5); break;
    case 4: zmp_put_byte(e, 0xd6); break;
    case 8: zmp_put_byte(e, 0xd7); break;
    case 16: zmp_put_byte(e, 0xd8); break;
    default:
        if (n <= 0xff)
            put_head(e, 0xc7, 1, n);
        else if (n <= 0xffff)
            put_head(e, 0xc8, 2, n);
        else if ((uint64_t) n <= 0xffffffffu)
            put_head(e, 0xc9, 4, n);
        else
            zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "an ext payload longer than 2^32 - 1 bytes");
    }
    zmp_put_byte(e, t);
    zmp_put(e, p, n);
}

/* ---- msgpack_bigint ---------------------------------------------------------- */

/* A canonical decimal (checked by the constructor, and again here) within
 * -2^63 .. 2^64 - 1, as its smallest integer form; beyond, there is no
 * MessagePack integer to write (design section 7.1). */
static void put_bigint(zmp_encoder *e, SEXP s)
{
    if (s == NA_STRING) {
        zmp_put_byte(e, 0xc0);
        return;
    }
    const char *p = CHAR(s);
    int negative = *p == '-';
    p += negative;
    size_t n = strlen(p);
    if (n == 0 || (n > 1 && p[0] == '0'))
        zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "a msgpack_bigint is not a canonical decimal integer");
    uint64_t v = 0;
    int over = 0;
    for (size_t i = 0; i < n; i++) {
        if (p[i] < '0' || p[i] > '9')
            zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "a msgpack_bigint is not a canonical decimal integer");
        unsigned d = (unsigned) (p[i] - '0');
        if (v > (UINT64_MAX - d) / 10)
            over = 1;
        else
            v = v * 10 + d;
    }
    if (negative && v == 0)
        zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "a msgpack_bigint is \"-0\"");
    if (over || (negative && v > (UINT64_C(1) << 63)))
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE,
                        "a msgpack_bigint outside -2^63 .. 2^64 - 1 has no MessagePack form");
    zmp_put_int(e, negative, negative ? v - 1 : v);
}

/* ---- maps ---------------------------------------------------------------------- */

static int entry_cmp(const zmp_entry *a, const zmp_entry *b)
{
    size_t n = a->key_len < b->key_len ? a->key_len : b->key_len;
    int r = n ? memcmp(a->key, b->key, n) : 0;
    if (r)
        return r;
    return a->key_len < b->key_len ? -1 : (a->key_len > b->key_len ? 1 : 0);
}

/* str keys by UTF-8 length, then bytes: the bytewise order of their
 * encodings, since a str head grows with the length (0xa0 + n below 32,
 * then 0xd9 n, 0xda nn, 0xdb nnnn), so no key needs encoding to be sorted. */
static int text_cmp(const zmp_entry *a, const zmp_entry *b)
{
    if (a->key_len != b->key_len)
        return a->key_len < b->key_len ? -1 : 1;
    return a->key_len ? memcmp(a->key, b->key, a->key_len) : 0;
}

/* Merge sort: deterministic, and O(n log n) on any key order. Input already
 * in order is detected in one pass and left alone. */
static void sort_entries(zmp_entry *a, R_xlen_t n, int (*cmp)(const zmp_entry *, const zmp_entry *))
{
    R_xlen_t run = 1;
    while (run < n && cmp(&a[run - 1], &a[run]) < 0)
        run++;
    if (run >= n)
        return;
    zmp_entry *tmp = (zmp_entry *) R_alloc((size_t) n, sizeof(zmp_entry));
    zmp_entry *src = a, *dst = tmp;
    for (R_xlen_t width = 1; width < n; width *= 2) {
        for (R_xlen_t lo = 0; lo < n; lo += 2 * width) {
            R_xlen_t mid = lo + width < n ? lo + width : n;
            R_xlen_t hi = lo + 2 * width < n ? lo + 2 * width : n;
            R_xlen_t i = lo, j = mid, k = lo;
            while (i < mid && j < hi)
                dst[k++] = cmp(&src[j], &src[i]) < 0 ? src[j++] : src[i++];
            while (i < mid)
                dst[k++] = src[i++];
            while (j < hi)
                dst[k++] = src[j++];
        }
        zmp_entry *t = src;
        src = dst;
        dst = t;
    }
    if (src != a)
        memcpy(a, src, (size_t) n * sizeof(zmp_entry));
}

/* Encodes one key on its own, once, into a zubin buffer owned by an
 * external pointer, and returns a copy of its bytes in R_alloc() memory. A
 * key may hold a class with an as_msgpack() method, which must run once
 * (zucbor Stage 10). */
static const uint8_t *encode_key(zmp_encoder *e, SEXP key, int depth, size_t *len)
{
    zb_status st;
    SEXP owner = PROTECT(zb_r_buf_new(0, 0, &st));
    if (st)
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "not enough memory for the encoding");
    zmp_encoder sub = *e;
    sub.out = zb_r_buf_get(owner);
    zmp_encode_value(&sub, key, depth);
    size_t n = sub.out->len;
    uint8_t *buf = (uint8_t *) R_alloc(n ? n : 1, 1);
    if (n)
        memcpy(buf, sub.out->data, n);
    zb_r_buf_free(owner);
    UNPROTECT(1);
    *len = n;
    return buf;
}

static void put_map_head(zmp_encoder *e, R_xlen_t n)
{
    if (n <= 15)
        zmp_put_byte(e, (uint8_t) (0x80 | n));
    else if (n <= 0xffff)
        put_head(e, 0xde, 2, (uint64_t) n);
    else if ((uint64_t) n <= 0xffffffffu)
        put_head(e, 0xdf, 4, (uint64_t) n);
    else
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "a map with more than 2^32 - 1 entries");
}

void zmp_put_array_head(zmp_encoder *e, R_xlen_t n)
{
    if (n <= 15)
        zmp_put_byte(e, (uint8_t) (0x90 | n));
    else if (n <= 0xffff)
        put_head(e, 0xdc, 2, (uint64_t) n);
    else if ((uint64_t) n <= 0xffffffffu)
        put_head(e, 0xdd, 4, (uint64_t) n);
    else
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE, "an array with more than 2^32 - 1 elements");
}

/* A map from keys (a list, or R_NilValue with str names) and values, in
 * the bytewise order of the encoded keys, with no duplicates. depth is the
 * map's entries' level. The entry array is R_alloc()ed per map and released
 * with the map's own vmax mark, so no pool outlives the map that made it:
 * zucbor's per-depth pools once let a nested map write into a released
 * block (zucbor Stage 10). */
void zmp_put_map(zmp_encoder *e, SEXP keys, SEXP names, SEXP values, R_xlen_t n, int depth)
{
    const void *vmax = vmaxget();
    zmp_entry *entries = (zmp_entry *) R_alloc((size_t) n + 1, sizeof(zmp_entry));
    int text = keys == R_NilValue;
    for (R_xlen_t i = 0; i < n; i++) {
        if (text)
            entries[i].key = (const uint8_t *) utf8_of(e, STRING_ELT(names, i), &entries[i].key_len);
        else
            entries[i].key = encode_key(e, VECTOR_ELT(keys, i), depth, &entries[i].key_len);
        entries[i].index = i;
    }
    int (*cmp)(const zmp_entry *, const zmp_entry *) = text ? text_cmp : entry_cmp;
    sort_entries(entries, n, cmp);
    for (R_xlen_t i = 1; i < n; i++)
        if (cmp(&entries[i - 1], &entries[i]) == 0)
            zmp_fail_encode(e, ZMP_ERR_DUPLICATE_KEY, "two map keys encode identically");
    put_map_head(e, n);
    for (R_xlen_t i = 0; i < n; i++) {
        if (text)
            put_str_head(e, entries[i].key_len);
        zmp_put(e, entries[i].key, entries[i].key_len);
        if (TYPEOF(values) == VECSXP)
            zmp_encode_value(e, VECTOR_ELT(values, entries[i].index), depth);
        else
            zmp_encode_element(e, values, entries[i].index, depth);
    }
    vmaxset(vmax);
}

/* Names that can be map keys: present on every element, not NA, not "". */
static int check_names(zmp_encoder *e, SEXP names, R_xlen_t n)
{
    if (names == R_NilValue)
        return 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(names, i);
        if (s == NA_STRING || CHAR(s)[0] == '\0')
            zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE,
                            "names must be all present and non-empty, or absent");
    }
    return 1;
}

/* ---- vectors ------------------------------------------------------------------- */

/* Rf_inherits(), not OBJECT(): the latter is non-API in current R. */
int zmp_is_class(SEXP x, const char *cls)
{
    return Rf_inherits(x, cls);
}

void zmp_check_depth(zmp_encoder *e, int depth)
{
    if (depth > e->max_depth)
        zmp_fail_encode(e, ZMP_ERR_DEPTH_LIMIT, NULL);
}

/* One element of an atomic vector, or of a classed one. depth is the level
 * an ext would take, for the classes that write one. */
void zmp_encode_element(zmp_encoder *e, SEXP x, R_xlen_t i, int depth)
{
    switch (TYPEOF(x)) {
    case LGLSXP: {
        int v = LOGICAL(x)[i];
        zmp_put_byte(e, v == NA_LOGICAL ? 0xc0 : v ? 0xc3 : 0xc2);
        return;
    }
    case INTSXP: {
        int v = INTEGER(x)[i];
        if (zmp_is_class(x, "POSIXct") || zmp_is_class(x, "Date")) {
            zmp_put_time(e, x, v == NA_INTEGER ? NA_REAL : (double) v, depth);
        } else if (v == NA_INTEGER) {
            zmp_put_byte(e, 0xc0);
        } else if (zmp_is_class(x, "factor")) {
            SEXP levels = Rf_getAttrib(x, R_LevelsSymbol);
            if (TYPEOF(levels) != STRSXP || v < 1 || v > LENGTH(levels))
                zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "a factor code has no level");
            zmp_put_str(e, STRING_ELT(levels, v - 1));
        } else {
            zmp_put_int(e, v < 0, v < 0 ? (uint64_t) (-1 - (int64_t) v) : (uint64_t) v);
        }
        return;
    }
    case REALSXP: {
        double v = REAL(x)[i];
        if (zmp_is_class(x, "POSIXct") || zmp_is_class(x, "Date"))
            zmp_put_time(e, x, v, depth);
        else if (ISNA(v))
            zmp_put_byte(e, 0xc0);      /* NA_real_; NaN is a float */
        else
            zmp_put_double(e, v);
        return;
    }
    case STRSXP: {
        SEXP s = STRING_ELT(x, i);
        if (zmp_is_class(x, "msgpack_bigint"))
            put_bigint(e, s);
        else if (s == NA_STRING)
            zmp_put_byte(e, 0xc0);
        else
            zmp_put_str(e, s);
        return;
    }
    default:
        zmp_fail_encode(e, ZMP_ERR_UNSUPPORTED_TYPE, "a vector of this type has no MessagePack form");
    }
}

static int unboxed(const zmp_encoder *e, SEXP x)
{
    return e->auto_unbox && XLENGTH(x) == 1 && !zmp_is_class(x, "AsIs");
}

/* depth is the level of the container x would be; a scalar is no level. */
void zmp_encode_value(zmp_encoder *e, SEXP x, int depth)
{
    if (zmp_convert_hook(e, &x, depth))
        return;
    zmp_encode_converted(e, x, depth);
}

/* x as it is, with no as_msgpack() call for x itself: an as_msgpack()
 * method's result comes here, so its class is not converted again, though
 * its elements are. */
void zmp_encode_converted(zmp_encoder *e, SEXP x, int depth)
{
    switch (TYPEOF(x)) {
    case NILSXP:
        zmp_put_byte(e, 0xc0);
        return;
    case RAWSXP:
        put_bin(e, RAW(x), (size_t) XLENGTH(x));
        return;
    case LGLSXP:
    case INTSXP:
    case REALSXP:
    case STRSXP: {
        if (zmp_is_class(x, "POSIXlt"))
            zmp_fail_encode(e, ZMP_ERR_UNSUPPORTED_TYPE,
                            "POSIXlt has no MessagePack form; use as.POSIXct()");
        R_xlen_t n = XLENGTH(x);
        /* PROTECTed although reachable through x: rchk cannot see that. */
        SEXP names = PROTECT(Rf_getAttrib(x, R_NamesSymbol));
        if (check_names(e, names, n)) {
            zmp_check_depth(e, depth);
            zmp_put_map(e, R_NilValue, names, x, n, depth + 1);
            UNPROTECT(1);
            return;
        }
        UNPROTECT(1);
        if (unboxed(e, x)) {
            zmp_encode_element(e, x, 0, depth);
            return;
        }
        zmp_check_depth(e, depth);
        zmp_put_array_head(e, n);
        for (R_xlen_t i = 0; i < n; i++)
            zmp_encode_element(e, x, i, depth + 1);
        return;
    }
    case VECSXP: {
        if (zmp_is_class(x, "msgpack_ext")) {
            SEXP type = VECTOR_ELT(x, 0), data = VECTOR_ELT(x, 1);
            if (XLENGTH(x) != 2 || (TYPEOF(type) != INTSXP && TYPEOF(type) != REALSXP) ||
                XLENGTH(type) != 1 || TYPEOF(data) != RAWSXP)
                zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE,
                                "a msgpack_ext needs a type from -128 to 127 and raw data");
            double t = Rf_asReal(type);
            if (!(t >= -128 && t <= 127 && t == trunc(t)))
                zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE, "an ext type is not from -128 to 127");
            zmp_put_ext(e, (int) t, RAW(data), (size_t) XLENGTH(data), depth);
            return;
        }
        if (zmp_is_class(x, "msgpack_map")) {
            SEXP keys = VECTOR_ELT(x, 0), values = VECTOR_ELT(x, 1);
            if (TYPEOF(keys) != VECSXP || TYPEOF(values) != VECSXP ||
                XLENGTH(keys) != XLENGTH(values))
                zmp_fail_encode(e, ZMP_ERR_INVALID_VALUE,
                                "a msgpack_map needs keys and values lists of equal length");
            zmp_check_depth(e, depth);
            zmp_put_map(e, keys, R_NilValue, values, XLENGTH(keys), depth + 1);
            return;
        }
        if (zmp_is_class(x, "data.frame")) {
            zmp_encode_data_frame(e, x, depth);
            return;
        }
        if (zmp_is_class(x, "POSIXlt"))
            zmp_fail_encode(e, ZMP_ERR_UNSUPPORTED_TYPE,
                            "POSIXlt has no MessagePack form; use as.POSIXct()");
        R_xlen_t n = XLENGTH(x);
        SEXP names = PROTECT(Rf_getAttrib(x, R_NamesSymbol));
        zmp_check_depth(e, depth);
        if (check_names(e, names, n)) {
            zmp_put_map(e, R_NilValue, names, x, n, depth + 1);
            UNPROTECT(1);
            return;
        }
        UNPROTECT(1);
        zmp_put_array_head(e, n);
        for (R_xlen_t i = 0; i < n; i++)
            zmp_encode_value(e, VECTOR_ELT(x, i), depth + 1);
        return;
    }
    default:
        zmp_fail_encode(e, ZMP_ERR_UNSUPPORTED_TYPE,
                        TYPEOF(x) == CPLXSXP ? "complex numbers have no MessagePack form"
                        : TYPEOF(x) == CLOSXP || TYPEOF(x) == BUILTINSXP || TYPEOF(x) == SPECIALSXP
                            ? "functions have no MessagePack form"
                        : TYPEOF(x) == ENVSXP ? "environments have no MessagePack form"
                        : TYPEOF(x) == EXTPTRSXP ? "external pointers have no MessagePack form"
                        : TYPEOF(x) == S4SXP ? "S4 objects have no MessagePack form"
                        : "this R type has no MessagePack form");
    }
}

/* ---- the parts later stages fill ------------------------------------------------- */

/* Data frames (Stage 6): refused, so a data frame never falls through to
 * the named-list path and comes out as a map of columns. */
void zmp_encode_data_frame(zmp_encoder *e, SEXP x, int depth)
{
    (void) x;
    (void) depth;
    zmp_fail_encode(e, ZMP_ERR_UNSUPPORTED_TYPE,
                    "data frames are not encoded in this version; convert to a list");
}

/* ---- entry point ------------------------------------------------------------------ */

/* opts: sequence, auto_unbox, max_depth, floats (0 double, 1 shortest). */
SEXP zmp_encode_raw(SEXP x, SEXP opts, SEXP call, SEXP ns)
{
    if (TYPEOF(opts) != INTSXP || XLENGTH(opts) != 4 || TYPEOF(ns) != ENVSXP)
        Rf_error("zmp_encode_raw: arguments must be validated in R");
    const int *o = INTEGER(opts);
    int sequence = o[0];
    zmp_encoder e;
    memset(&e, 0, sizeof e);
    e.auto_unbox = o[1];
    e.max_depth = o[2];
    e.floats_shortest = o[3];
    e.call = call;
    e.ns = ns;
    if (e.max_depth < 1 || e.max_depth > ZMP_MAX_DEPTH_CAP)
        Rf_error("zmp_encode_raw: limits must be validated in R");
    if (sequence && TYPEOF(x) != VECSXP)
        Rf_error("zmp_encode_raw: arguments must be validated in R");

    zb_status st;
    SEXP owner = PROTECT(zb_r_buf_new(0, 0, &st));
    if (st)
        zmp_fail_encode(&e, ZMP_ERR_UNREPRESENTABLE, "not enough memory for the encoding");
    e.out = zb_r_buf_get(owner);

    R_xlen_t items = sequence ? XLENGTH(x) : 1;
    for (R_xlen_t i = 0; i < items; i++)
        zmp_encode_value(&e, sequence ? VECTOR_ELT(x, i) : x, 1);
    if (e.out->len > (size_t) R_XLEN_T_MAX)
        zmp_fail_encode(&e, ZMP_ERR_UNREPRESENTABLE, "the encoding is longer than an R vector can be");
    SEXP out = PROTECT(zb_r_buf_to_raw(e.out));
    zb_r_buf_free(owner);
    UNPROTECT(2);
    return out;
}
