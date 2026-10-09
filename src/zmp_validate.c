/* msgpack_validate()'s entry point: the check phase alone (zmp_walk.c). */
#include "zmp.h"

SEXP zmp_check_raw(SEXP x, SEXP mode, SEXP duplicate_keys, SEXP max_depth,
                   SEXP max_items)
{
    if (TYPEOF(x) != RAWSXP)
        Rf_error("zmp_check_raw: x must be a raw vector");
    zmp_check_opts opt;
    opt.mode = Rf_asInteger(mode);
    opt.duplicate_keys = Rf_asLogical(duplicate_keys) == TRUE;
    opt.max_depth = Rf_asInteger(max_depth);
    double mi = Rf_asReal(max_items);
    if (opt.max_depth < 1 || opt.max_depth > ZMP_MAX_DEPTH_CAP || ISNAN(mi) || mi < 1 ||
        opt.mode < ZMP_MODE_ONE || opt.mode > ZMP_MODE_STREAM)
        Rf_error("zmp_check_raw: arguments must be validated in R");
    opt.max_items = R_FINITE(mi) ? (uint64_t) mi : UINT64_MAX;

    zmp_fault fault;
    if (zmp_check(RAW(x), (size_t) XLENGTH(x), &opt, NULL, &fault))
        return zmp_fault_sexp(&fault);
    return R_NilValue;
}
