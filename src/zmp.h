#ifndef ZMP_H
#define ZMP_H

/* The R-facing half of the package: every .Call entry point is declared
 * here and registered in init.c. The check phase has its own header,
 * zmp_check.h, with no R in it (design section 4). */

#include <stddef.h>
#include <stdint.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

/* ZMP_MAX_DEPTH_CAP, in zmp_check.h, is the hard ceiling on max_depth
 * (design section 12): the build phase and the encoder recurse once per
 * level, so the ceiling keeps the C stack bounded. 1023, as in zucbor, so a
 * limit valid for one package is valid for both. */
#include "zmp_check.h"

/* ---- .Call entry points, registered in init.c ----------------------------- */

SEXP zmp_build_info(void);
SEXP zmp_status_names(void);
SEXP zmp_head_table(void);
SEXP zmp_check_raw(SEXP x, SEXP mode, SEXP duplicate_keys, SEXP max_depth,
                   SEXP max_items);
SEXP zmp_decode_raw(SEXP x, SEXP opts, SEXP max_items, SEXP call);

/* ---- zmp_cond.c ------------------------------------------------------------- */

SEXP zmp_fault_sexp(const zmp_fault *fault);

#endif
