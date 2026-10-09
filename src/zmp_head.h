#ifndef ZMP_HEAD_H
#define ZMP_HEAD_H

/* The MessagePack head reader (design section 9), shared by the check
 * phase, the build phase and the annotator. R-free.
 *
 * A 256-entry constant table indexed by the first byte gives every format's
 * kind, its head length, the width of the big-endian field that follows the
 * first byte, and for fixext the fixed payload length. The ranges that share
 * a row (fixint, fixmap, fixarray, fixstr, negative fixint) are repeated by
 * macro, and the 32 single-byte formats from 0xc0 to 0xdf have a row each
 * (zmp_head.c). */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <zufast/bits.h>

enum {
    ZMP_K_NIL, ZMP_K_FALSE, ZMP_K_TRUE, ZMP_K_UINT, ZMP_K_INT, ZMP_K_F32,
    ZMP_K_F64, ZMP_K_STR, ZMP_K_BIN, ZMP_K_ARRAY, ZMP_K_MAP, ZMP_K_EXT,
    ZMP_K_RESERVED
};

typedef struct {
    uint8_t kind;
    uint8_t hlen;       /* bytes in the head, the ext type byte included */
    uint8_t width;      /* bytes of the big-endian field after byte 0, or 0 */
    uint8_t fixlen;     /* fixext payload length, else 0 */
} zmp_fmt;

#define ZMP_F(k, h, w, f) {(uint8_t)(k), (uint8_t)(h), (uint8_t)(w), (uint8_t)(f)}

/* 0xc0 .. 0xdf, one row each. */
#define ZMP_FMT_C0_ROWS \
    ZMP_F(ZMP_K_NIL, 1, 0, 0),      /* c0 nil */ \
    ZMP_F(ZMP_K_RESERVED, 1, 0, 0), /* c1 never used */ \
    ZMP_F(ZMP_K_FALSE, 1, 0, 0),    /* c2 false */ \
    ZMP_F(ZMP_K_TRUE, 1, 0, 0),     /* c3 true */ \
    ZMP_F(ZMP_K_BIN, 2, 1, 0),      /* c4 bin 8 */ \
    ZMP_F(ZMP_K_BIN, 3, 2, 0),      /* c5 bin 16 */ \
    ZMP_F(ZMP_K_BIN, 5, 4, 0),      /* c6 bin 32 */ \
    ZMP_F(ZMP_K_EXT, 3, 1, 0),      /* c7 ext 8 */ \
    ZMP_F(ZMP_K_EXT, 4, 2, 0),      /* c8 ext 16 */ \
    ZMP_F(ZMP_K_EXT, 6, 4, 0),      /* c9 ext 32 */ \
    ZMP_F(ZMP_K_F32, 5, 4, 0),      /* ca float 32 */ \
    ZMP_F(ZMP_K_F64, 9, 8, 0),      /* cb float 64 */ \
    ZMP_F(ZMP_K_UINT, 2, 1, 0),     /* cc uint 8 */ \
    ZMP_F(ZMP_K_UINT, 3, 2, 0),     /* cd uint 16 */ \
    ZMP_F(ZMP_K_UINT, 5, 4, 0),     /* ce uint 32 */ \
    ZMP_F(ZMP_K_UINT, 9, 8, 0),     /* cf uint 64 */ \
    ZMP_F(ZMP_K_INT, 2, 1, 0),      /* d0 int 8 */ \
    ZMP_F(ZMP_K_INT, 3, 2, 0),      /* d1 int 16 */ \
    ZMP_F(ZMP_K_INT, 5, 4, 0),      /* d2 int 32 */ \
    ZMP_F(ZMP_K_INT, 9, 8, 0),      /* d3 int 64 */ \
    ZMP_F(ZMP_K_EXT, 2, 0, 1),      /* d4 fixext 1 */ \
    ZMP_F(ZMP_K_EXT, 2, 0, 2),      /* d5 fixext 2 */ \
    ZMP_F(ZMP_K_EXT, 2, 0, 4),      /* d6 fixext 4 */ \
    ZMP_F(ZMP_K_EXT, 2, 0, 8),      /* d7 fixext 8 */ \
    ZMP_F(ZMP_K_EXT, 2, 0, 16),     /* d8 fixext 16 */ \
    ZMP_F(ZMP_K_STR, 2, 1, 0),      /* d9 str 8 */ \
    ZMP_F(ZMP_K_STR, 3, 2, 0),      /* da str 16 */ \
    ZMP_F(ZMP_K_STR, 5, 4, 0),      /* db str 32 */ \
    ZMP_F(ZMP_K_ARRAY, 3, 2, 0),    /* dc array 16 */ \
    ZMP_F(ZMP_K_ARRAY, 5, 4, 0),    /* dd array 32 */ \
    ZMP_F(ZMP_K_MAP, 3, 2, 0),      /* de map 16 */ \
    ZMP_F(ZMP_K_MAP, 5, 4, 0)       /* df map 32 */

/* The table itself, in zmp_head.c. Exposed for the test that compares it,
 * entry by entry, with an independent table written from the spec. */
extern const zmp_fmt zmp_fmt_table[256];

/* A decoded head. */
typedef struct {
    uint8_t kind;           /* ZMP_K_* */
    uint8_t hlen;           /* bytes in the head */
    int8_t ext_type;        /* ZMP_K_EXT */
    uint8_t negative;       /* ZMP_K_INT and the value is below zero */
    uint64_t u;             /* ZMP_K_UINT value; ZMP_K_INT magnitude when
                             * negative is 0, else -(value + 1) */
    int64_t i;              /* ZMP_K_INT value */
    double d;               /* ZMP_K_F32 (widened exactly), ZMP_K_F64 */
    uint32_t len;           /* str/bin/ext payload length, array/map count */
} zmp_head;

enum { ZMP_HEAD_OK = 0, ZMP_HEAD_TRUNCATED = 1, ZMP_HEAD_RESERVED = 2 };

/* Reads the head at p, with avail bytes available (at least one). Never
 * reads past p + avail. The payload is not checked: that is the caller's
 * length guard. */
static inline int zmp_read_head(const uint8_t *p, size_t avail, zmp_head *h)
{
    const zmp_fmt *f = &zmp_fmt_table[p[0]];
    uint64_t v = 0;
    uint8_t b = p[0];
    h->kind = f->kind;
    h->hlen = f->hlen;
    h->ext_type = 0;
    h->negative = 0;
    h->u = 0;
    h->i = 0;
    h->d = 0;
    h->len = 0;
    if (f->kind == ZMP_K_RESERVED)
        return ZMP_HEAD_RESERVED;
    if (avail < f->hlen)
        return ZMP_HEAD_TRUNCATED;
    switch (f->width) {
    case 1: v = p[1]; break;
    case 2: v = zuf_load_be16(p + 1); break;
    case 4: v = zuf_load_be32(p + 1); break;
    case 8: v = zuf_load_be64(p + 1); break;
    default:
        if (b <= 0x7f) v = b;
        else if (b <= 0x9f) v = b & 0x0fu;      /* fixmap, fixarray */
        else if (b <= 0xbf) v = b & 0x1fu;      /* fixstr */
        else v = f->fixlen;                     /* fixext; nil, bool: 0 */
        break;
    }
    switch (f->kind) {
    case ZMP_K_UINT:
        h->u = v;
        break;
    case ZMP_K_INT: {
        int64_t s;
        if (f->width == 0) s = (int8_t) b;                  /* negative fixint */
        else if (f->width == 1) s = (int8_t) (uint8_t) v;
        else if (f->width == 2) s = (int16_t) (uint16_t) v;
        else if (f->width == 4) s = (int32_t) (uint32_t) v;
        else {
            /* Two's complement without implementation-defined conversion. */
            s = v > (uint64_t) INT64_MAX ? -(int64_t) (~v) - 1 : (int64_t) v;
        }
        h->i = s;
        h->negative = s < 0;
        h->u = s < 0 ? (uint64_t) (-(s + 1)) : (uint64_t) s;
        break;
    }
    case ZMP_K_F32: {
        uint32_t bits = (uint32_t) v;
        float x;
        memcpy(&x, &bits, sizeof x);
        h->d = (double) x;
        break;
    }
    case ZMP_K_F64: {
        memcpy(&h->d, &v, sizeof h->d);
        break;
    }
    case ZMP_K_EXT:
        h->len = (uint32_t) v;
        h->ext_type = (int8_t) p[f->hlen - 1];
        break;
    case ZMP_K_STR: case ZMP_K_BIN: case ZMP_K_ARRAY: case ZMP_K_MAP:
        h->len = (uint32_t) v;
        break;
    default:
        break;
    }
    return ZMP_HEAD_OK;
}

#endif
