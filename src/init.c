#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "zmp.h"

static const R_CallMethodDef CallEntries[] = {
    {"zmp_build_info", (DL_FUNC) &zmp_build_info, 0},
    {NULL, NULL, 0}
};

/* The one symbol the shared object exports (design section 14). */
void attribute_visible R_init_zumsgpack(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
