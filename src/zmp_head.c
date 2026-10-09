/* The head table (design section 9). test-head.R compares every entry with
 * an independent table written from the spec's format list. */
#include "zmp_head.h"

/* Each repeat takes a row macro's name and calls it, so the commas inside a
 * row are never seen as macro argument separators. */
#define ZMP_R4(m)   m(), m(), m(), m()
#define ZMP_R16(m)  ZMP_R4(m), ZMP_R4(m), ZMP_R4(m), ZMP_R4(m)
#define ZMP_R32(m)  ZMP_R16(m), ZMP_R16(m)
#define ZMP_R128(m) ZMP_R32(m), ZMP_R32(m), ZMP_R32(m), ZMP_R32(m)

#define ZMP_ROW_POSFIX() ZMP_F(ZMP_K_UINT, 1, 0, 0)
#define ZMP_ROW_FIXMAP() ZMP_F(ZMP_K_MAP, 1, 0, 0)
#define ZMP_ROW_FIXARR() ZMP_F(ZMP_K_ARRAY, 1, 0, 0)
#define ZMP_ROW_FIXSTR() ZMP_F(ZMP_K_STR, 1, 0, 0)
#define ZMP_ROW_NEGFIX() ZMP_F(ZMP_K_INT, 1, 0, 0)

const zmp_fmt zmp_fmt_table[256] = {
    ZMP_R128(ZMP_ROW_POSFIX),   /* 00..7f positive fixint */
    ZMP_R16(ZMP_ROW_FIXMAP),    /* 80..8f fixmap */
    ZMP_R16(ZMP_ROW_FIXARR),    /* 90..9f fixarray */
    ZMP_R32(ZMP_ROW_FIXSTR),    /* a0..bf fixstr */
    ZMP_FMT_C0_ROWS,            /* c0..df */
    ZMP_R32(ZMP_ROW_NEGFIX)     /* e0..ff negative fixint */
};
