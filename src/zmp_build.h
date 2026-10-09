#ifndef ZMP_BUILD_H
#define ZMP_BUILD_H

/* The build phase's state, shared by zmp_build.c and, from Stage 4, the
 * extension conversions. R-bound: it runs only after zmp_check() passed. */

#include "zmp.h"

enum { ZMP_SIMPLIFY_PRESERVE, ZMP_SIMPLIFY_NONE };
enum { ZMP_KEYS_AUTO, ZMP_KEYS_MAP, ZMP_KEYS_STRING };
enum { ZMP_BIG_BIGINT, ZMP_BIG_DOUBLE, ZMP_BIG_ERROR };

/* What an element is, for the array lattice (design section 6.2). A float
 * and an integer-valued double are different kinds even though both are R
 * doubles: the lattice must not decide from a value's magnitude what type
 * its neighbours become. */
enum {
    ZMP_KIND_NULL, ZMP_KIND_LGL, ZMP_KIND_INT, ZMP_KIND_INTDBL, ZMP_KIND_FLOAT,
    ZMP_KIND_BIGINT, ZMP_KIND_STR, ZMP_KIND_POSIXCT, ZMP_KIND_OTHER, ZMP_KIND_COUNT
};

typedef struct {
    const uint8_t *buf;
    size_t len, pos;
    const zmp_plan *plan;
    size_t next_count;
    int simplify, map_keys, big_integers, duplicate_keys;
    int ext_convert;            /* ext = "convert": type -1 is a POSIXct */
    SEXP *handlers;             /* 256 slots by type + 128, or NULL */
    SEXP call;
    SEXP ns;                    /* where zmp_run_handler() is called from */
    uint64_t items;
} zmp_builder;

SEXP zmp_build_value(zmp_builder *b, int *kind);
SEXP zmp_build_ext(zmp_builder *b, int type, const uint8_t *p, size_t n, size_t at, int *kind);
SEXP zmp_mkchar(zmp_builder *b, const char *s, size_t n, size_t at);
void zmp_fail_build(zmp_builder *b, const char *status, const char *detail, size_t at);
void zmp_format_double(double d, char *buf);     /* buf >= 32 bytes */

#endif
