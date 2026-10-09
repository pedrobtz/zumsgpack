/* Faults as R values, for R's zmp_raise_fault() (design section 11). */
#include "zmp.h"
#include "zmp_head.h"

/* Every status a fault can carry, for the test that R's class map is
 * complete. */
SEXP zmp_status_names(void)
{
    size_t n = zmp_status_count();
    SEXP out = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++)
        SET_STRING_ELT(out, (R_xlen_t) i, Rf_mkChar(zmp_status_at(i)));
    UNPROTECT(1);
    return out;
}

/* The head table as a data frame's columns, for test-head.R. */
SEXP zmp_head_table(void)
{
    const char *names[] = {"kind", "hlen", "width", "fixlen", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    for (int j = 0; j < 4; j++)
        SET_VECTOR_ELT(out, j, Rf_allocVector(INTSXP, 256));
    for (int b = 0; b < 256; b++) {
        INTEGER(VECTOR_ELT(out, 0))[b] = zmp_fmt_table[b].kind;
        INTEGER(VECTOR_ELT(out, 1))[b] = zmp_fmt_table[b].hlen;
        INTEGER(VECTOR_ELT(out, 2))[b] = zmp_fmt_table[b].width;
        INTEGER(VECTOR_ELT(out, 3))[b] = zmp_fmt_table[b].fixlen;
    }
    UNPROTECT(1);
    return out;
}

/* A fault as the list R's zmp_raise_fault() takes. */
SEXP zmp_fault_sexp(const zmp_fault *fault)
{
    const char *names[] = {"status", "detail", "offset", "limit", "limit_value", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(fault->status));
    SET_VECTOR_ELT(out, 1, fault->detail ? Rf_mkString(fault->detail)
                                         : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 2, Rf_ScalarReal(fault->offset));
    SET_VECTOR_ELT(out, 3, fault->limit ? Rf_mkString(fault->limit)
                                        : Rf_ScalarString(NA_STRING));
    SET_VECTOR_ELT(out, 4, Rf_ScalarReal(fault->limit ? fault->limit_value : NA_REAL));
    SEXP cls = PROTECT(Rf_mkString("zmp_fault"));
    Rf_setAttrib(out, R_ClassSymbol, cls);
    UNPROTECT(2);
    return out;
}
