#ifndef ZMP_ENCODE_H
#define ZMP_ENCODE_H

/* The encoder's state and the pieces later stages build on (timestamps,
 * as_msgpack(), data frames). */

#include <zubin/buf.h>

#include "zmp.h"

typedef struct {
    zb_buf *out;
    int max_depth;
    int auto_unbox;
    int floats_shortest;    /* floats = "shortest" */
    SEXP call;
    SEXP ns;                /* the namespace, where as_msgpack() is called from */
} zmp_encoder;

void zmp_fail_encode(zmp_encoder *e, const char *status, const char *detail);
void zmp_put(zmp_encoder *e, const void *p, size_t n);
void zmp_put_byte(zmp_encoder *e, uint8_t b);
void zmp_put_int(zmp_encoder *e, int negative, uint64_t raw);
void zmp_put_double(zmp_encoder *e, double d);
void zmp_put_str(zmp_encoder *e, SEXP s);
void zmp_put_ext(zmp_encoder *e, int type, const uint8_t *p, size_t n, int depth);
void zmp_put_array_head(zmp_encoder *e, R_xlen_t n);
void zmp_put_map(zmp_encoder *e, SEXP keys, SEXP names, SEXP values, R_xlen_t n, int depth);
void zmp_check_depth(zmp_encoder *e, int depth);
int zmp_is_class(SEXP x, const char *cls);
void zmp_encode_value(zmp_encoder *e, SEXP x, int depth);
void zmp_encode_element(zmp_encoder *e, SEXP x, R_xlen_t i, int depth);

/* Filled by later stages. */
void zmp_put_time(zmp_encoder *e, SEXP x, double v, int depth);
int zmp_convert_hook(zmp_encoder *e, SEXP *x, int depth);
void zmp_encode_data_frame(zmp_encoder *e, SEXP x, int depth);

#endif
