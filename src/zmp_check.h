#ifndef ZMP_CHECK_H
#define ZMP_CHECK_H

/* The check phase's interface (design sections 4 and 12), with no SEXP in
 * sight, so it builds without R for fuzzing: compile with -DZMP_STANDALONE
 * and link a harness that provides zmp_scratch(). Built that way from the
 * first commit (roadmap, principle 2), which is also what makes "no R object
 * before the check passes" structural. */

#include <stddef.h>
#include <stdint.h>

/* Scratch memory, released as a whole: R_alloc() in the package, which R
 * frees when the .Call returns or unwinds (design section 13); an arena the
 * harness resets after each input in the standalone build. */
#ifdef ZMP_STANDALONE
#include <math.h>
void *zmp_scratch(size_t n, size_t size);
#define zmp_interrupt_check() ((void) 0)
#define ZMP_NO_OFFSET NAN
#else
#include <R_ext/Arith.h>
#include <R_ext/Memory.h>
#include <R_ext/Utils.h>
#define zmp_scratch(n, size) ((void *) R_alloc((n), (int) (size)))
#define zmp_interrupt_check() R_CheckUserInterrupt()
#define ZMP_NO_OFFSET NA_REAL
#endif

/* The hard ceiling on max_depth (design section 12). */
#define ZMP_MAX_DEPTH_CAP 1023

/* What the check accepts (design section 4). */
enum {
    ZMP_MODE_ONE = 0,       /* exactly one object */
    ZMP_MODE_SEQ = 1,       /* zero or more objects back to back */
    ZMP_MODE_PREFIX = 2,    /* the first object; what follows is not read */
    ZMP_MODE_STREAM = 3     /* as SEQ, but stop without a fault before an
                             * object the input ends inside (Stage 5) */
};

typedef struct {
    int max_depth;          /* 1 .. ZMP_MAX_DEPTH_CAP */
    uint64_t max_items;     /* UINT64_MAX for Inf */
    int duplicate_keys;     /* nonzero: accept them */
    int mode;               /* ZMP_MODE_* */
} zmp_check_opts;

/* Why a check failed. status is one of the ZMP_ERR_* names below; R maps it
 * to a condition class by name (design section 11). */
typedef struct {
    const char *status;     /* NULL: no fault */
    const char *detail;     /* a short English detail, or NULL */
    double offset;          /* 0-based byte offset, ZMP_NO_OFFSET when unknown */
    const char *limit;      /* the limit argument's name, or NULL */
    double limit_value;
} zmp_fault;

/* What the build phase needs from the check phase: the element count of
 * every container, in the order the walk met them (preorder; maps count
 * pairs), so the build allocates from the plan and never from a length
 * header (design section 4). */
typedef struct {
    size_t *counts;
    size_t n, cap;
    size_t n_items;         /* top-level objects found */
    size_t consumed;        /* bytes the objects used */
} zmp_plan;

/* Runs the whole check phase over buf. Returns 0 and fills plan (which may
 * be NULL), or returns 1 and fills fault. Never raises. */
int zmp_check(const uint8_t *buf, size_t len, const zmp_check_opts *opt,
              zmp_plan *plan, zmp_fault *fault);

/* zumsgpack's own statuses (design section 11). Every one a fault can carry
 * is listed in zmp_status.c, and test-conditions.R checks R maps each. */
#define ZMP_ERR_TRUNCATED           "ZMP_ERR_TRUNCATED"
#define ZMP_ERR_RESERVED            "ZMP_ERR_RESERVED"
#define ZMP_ERR_TRAILING            "ZMP_ERR_TRAILING"
#define ZMP_ERR_INVALID_UTF8        "ZMP_ERR_INVALID_UTF8"
#define ZMP_ERR_TIMESTAMP_LENGTH    "ZMP_ERR_TIMESTAMP_LENGTH"
#define ZMP_ERR_TIMESTAMP_NANOS     "ZMP_ERR_TIMESTAMP_NANOS"
#define ZMP_ERR_DUPLICATE_KEY       "ZMP_ERR_DUPLICATE_KEY"
#define ZMP_ERR_DEPTH_LIMIT         "ZMP_ERR_DEPTH_LIMIT"
#define ZMP_ERR_ITEM_LIMIT          "ZMP_ERR_ITEM_LIMIT"
#define ZMP_ERR_SIZE_LIMIT          "ZMP_ERR_SIZE_LIMIT"
#define ZMP_ERR_CELL_LIMIT          "ZMP_ERR_CELL_LIMIT"
#define ZMP_ERR_NUL_IN_STR          "ZMP_ERR_NUL_IN_STR"
#define ZMP_ERR_STRING_TOO_LONG     "ZMP_ERR_STRING_TOO_LONG"
#define ZMP_ERR_BIG_INTEGER         "ZMP_ERR_BIG_INTEGER"
#define ZMP_ERR_KEY_COLLISION       "ZMP_ERR_KEY_COLLISION"
#define ZMP_ERR_UNSUPPORTED_TYPE    "ZMP_ERR_UNSUPPORTED_TYPE"
#define ZMP_ERR_UNREPRESENTABLE     "ZMP_ERR_UNREPRESENTABLE"
#define ZMP_ERR_INVALID_VALUE       "ZMP_ERR_INVALID_VALUE"

/* zmp_status.c: every status a fault can carry, for R's class map. */
size_t zmp_status_count(void);
const char *zmp_status_at(size_t i);

#endif
