/* Extension objects both ways: the timestamp extension (type -1, design
 * sections 6.1 and 8 rule 5), extension handlers on decode (6.3), and
 * as_msgpack() on encode (7.1). */

#include <math.h>
#include <string.h>

#include <zufast/bits.h>

#include "zmp_build.h"
#include "zmp_encode.h"

/* ---- decoding ------------------------------------------------------------------ */

static SEXP posixct(double secs)
{
    SEXP out = PROTECT(Rf_ScalarReal(secs));
    SEXP klass = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(klass, 0, Rf_mkChar("POSIXct"));
    SET_STRING_ELT(klass, 1, Rf_mkChar("POSIXt"));
    Rf_setAttrib(out, R_ClassSymbol, klass);
    SEXP tz = PROTECT(Rf_mkString("UTC"));
    Rf_setAttrib(out, Rf_install("tzone"), tz);
    UNPROTECT(3);
    return out;
}

/* The instant of a timestamp payload the check has accepted: 4, 8 or 12
 * bytes, nanoseconds below 10^9. A double holds microseconds comfortably
 * but not nanoseconds; a "-1" handler keeps the fields (design 18 Q1). */
static double timestamp_seconds(const uint8_t *p, size_t n)
{
    if (n == 4)
        return (double) zuf_load_be32(p);
    if (n == 8) {
        uint64_t v = zuf_load_be64(p);
        return (double) (v & ((UINT64_C(1) << 34) - 1)) + (double) (v >> 34) / 1e9;
    }
    uint32_t nanos = zuf_load_be32(p);
    uint64_t u = zuf_load_be64(p + 4);
    /* Two's complement without implementation-defined conversion. */
    int64_t secs = u > (uint64_t) INT64_MAX ? -(int64_t) (~u) - 1 : (int64_t) u;
    return (double) secs + (double) nanos / 1e9;
}

/* zmp_run_handler(handler, data, type, call) in R, which wraps an error as
 * zumsgpack_handler_error. User code runs here, in the middle of the build:
 * that is safe because everything the build holds is PROTECTed or
 * R_alloc()ed (design section 13), and the input was checked whole before
 * the first handler ran. The arguments are bound in a fresh environment,
 * so nothing is evaluated twice. */
static SEXP run_handler(zmp_builder *b, SEXP handler, int type, SEXP data)
{
    PROTECT(data);
    SEXP env = PROTECT(R_NewEnv(b->ns, FALSE, 4));
    SEXP s_handler = Rf_install("handler"), s_data = Rf_install("data");
    SEXP s_type = Rf_install("type"), s_call = Rf_install("call");
    Rf_defineVar(s_handler, handler, env);
    Rf_defineVar(s_data, data, env);
    SEXP t = PROTECT(Rf_ScalarInteger(type));
    Rf_defineVar(s_type, t, env);
    Rf_defineVar(s_call, b->call, env);
    SEXP expr = PROTECT(Rf_lang5(Rf_install("zmp_run_handler"), s_handler, s_data, s_type, s_call));
    SEXP out = Rf_eval(expr, env);
    UNPROTECT(4);
    return out;
}

static SEXP make_ext(int type, const uint8_t *p, size_t n)
{
    const char *names[] = {"type", "data", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_ScalarInteger(type));
    SEXP data = Rf_allocVector(RAWSXP, (R_xlen_t) n);
    SET_VECTOR_ELT(out, 1, data);
    if (n)
        memcpy(RAW(data), p, n);
    SEXP klass = PROTECT(Rf_mkString("msgpack_ext"));
    Rf_setAttrib(out, R_ClassSymbol, klass);
    UNPROTECT(2);
    return out;
}

/* An extension object (design section 6.3): the caller's handler for its
 * type if there is one, else a timestamp under ext = "convert", else a
 * msgpack_ext. A handler's result is kind "other" in the lattice. */
SEXP zmp_build_ext(zmp_builder *b, int type, const uint8_t *p, size_t n, size_t at, int *kind)
{
    (void) at;
    SEXP handler = b->handlers ? b->handlers[type + 128] : R_NilValue;
    if (handler != R_NilValue) {
        SEXP data = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) n));
        if (n)
            memcpy(RAW(data), p, n);
        *kind = ZMP_KIND_OTHER;
        SEXP out = run_handler(b, handler, type, data);
        UNPROTECT(1);
        return out;
    }
    if (type == -1 && b->ext_convert) {
        *kind = ZMP_KIND_POSIXCT;
        return posixct(timestamp_seconds(p, n));
    }
    *kind = ZMP_KIND_OTHER;
    return make_ext(type, p, n);
}

/* ---- encoding timestamps ----------------------------------------------------------- */

/* POSIXct seconds, or Date days at midnight UTC, as the smallest of the
 * three timestamp encodings that holds the instant (design section 8,
 * rule 5). The instant is first fixed to whole nanoseconds by one rule,
 * so every host writes the same bytes: whole seconds by floor(), the
 * fraction rounded to the nearest nanosecond (half away from zero), a
 * carry at 10^9. floor(), the subtraction (exact, by Sterbenz's lemma, for
 * |x| < 2^52), the product and round() are each correctly rounded IEEE
 * operations. A double near 2026 resolves about 2^-22 s, so nanoseconds
 * are kept only to double precision (design section 7.2). */
void zmp_put_time(zmp_encoder *e, SEXP x, double v, int depth)
{
    if (ISNAN(v)) {
        zmp_put_byte(e, 0xc0);
        return;
    }
    double secs = zmp_is_class(x, "Date") ? v * 86400.0 : v;
    if (!R_FINITE(secs) || secs < -9223372036854775808.0 || secs >= 9223372036854775808.0)
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE,
                        "a time outside what a timestamp's 64-bit seconds hold");
    double whole = floor(secs);
    double nanos = round((secs - whole) * 1e9);
    if (nanos >= 1e9) {
        whole += 1;
        nanos = 0;
    }
    if (whole >= 9223372036854775808.0)
        zmp_fail_encode(e, ZMP_ERR_UNREPRESENTABLE,
                        "a time outside what a timestamp's 64-bit seconds hold");
    uint32_t ns = (uint32_t) nanos;
    zmp_check_depth(e, depth);
    uint8_t buf[12];
    if (ns == 0 && whole >= 0 && whole < 4294967296.0) {
        zuf_store_be32(buf, (uint32_t) whole);
        zmp_put_ext(e, -1, buf, 4, depth);
    } else if (whole >= 0 && whole < 17179869184.0) {
        zuf_store_be64(buf, ((uint64_t) ns << 34) | (uint64_t) whole);
        zmp_put_ext(e, -1, buf, 8, depth);
    } else {
        int64_t s = (int64_t) whole;
        zuf_store_be32(buf, ns);
        zuf_store_be64(buf + 4, (uint64_t) s);
        zmp_put_ext(e, -1, buf, 12, depth);
    }
}

/* ---- as_msgpack() ------------------------------------------------------------------ */

/* Classes msgpack_encode() writes itself, or refuses itself. "AsIs" only
 * marks a value as not to be unboxed, so it neither counts as known nor
 * asks for a conversion. */
static const char *const known_classes[] = {
    "POSIXct", "Date", "factor", "msgpack_bigint", "msgpack_ext",
    "msgpack_map", "data.frame", "POSIXlt", NULL
};

static int wants_conversion(SEXP x)
{
    if (!Rf_isObject(x))
        return 0;
    SEXP klass = Rf_getAttrib(x, R_ClassSymbol);
    if (TYPEOF(klass) != STRSXP)
        return 0;
    int unknown = 0;
    for (R_xlen_t i = 0; i < XLENGTH(klass); i++) {
        const char *c = CHAR(STRING_ELT(klass, i));
        for (const char *const *k = known_classes; *k; k++)
            if (strcmp(c, *k) == 0)
                return 0;
        if (strcmp(c, "AsIs") != 0)
            unknown = 1;
    }
    return unknown;
}

/* as_msgpack(x), evaluated in a fresh environment whose parent is the
 * namespace: S3 dispatch finds methods registered by any package and those
 * in the global environment, and x is bound by name, so a method's error
 * shows `x`, not the deparsed value. */
static SEXP convert(zmp_encoder *e, SEXP x)
{
    SEXP env = PROTECT(R_NewEnv(e->ns, FALSE, 1));
    SEXP sym = Rf_install("x");
    Rf_defineVar(sym, x, env);
    SEXP expr = PROTECT(Rf_lang2(Rf_install("as_msgpack"), sym));
    SEXP out = Rf_eval(expr, env);
    UNPROTECT(2);
    return out;
}

/* An object of a class this encoder does not know goes through
 * as_msgpack() once (design section 7.1, zucbor section 7.5): the method's
 * result is not converted again, though its elements are, so no chain of
 * methods can loop. Returns nonzero when it has written x. */
int zmp_convert_hook(zmp_encoder *e, SEXP *x, int depth)
{
    if (!wants_conversion(*x))
        return 0;
    SEXP y = PROTECT(convert(e, *x));
    if (y == *x) {
        UNPROTECT(1);
        return 0;
    }
    SEXP kx = PROTECT(Rf_getAttrib(*x, R_ClassSymbol));
    SEXP ky = PROTECT(Rf_getAttrib(y, R_ClassSymbol));
    if (R_compute_identical(kx, ky, 16))
        zmp_fail_encode(e, ZMP_ERR_UNSUPPORTED_TYPE,
                        "as_msgpack() returned an object of the class it was given");
    UNPROTECT(2);
    zmp_encode_converted(e, y, depth);
    UNPROTECT(1);
    return 1;
}
