/* msgpack_annotate(): an annotated hex dump (design section 5).
 *
 * Runs only on input the check phase has accepted, so every head is
 * complete and every count is within the input. One line per head, showing
 * its offset, its bytes and what they are, indented by depth; a str, bin
 * or ext payload follows its head in rows of 16 bytes, so every byte of the
 * input appears in the hex column exactly once (zucbor Stage 13). Previews
 * stop at 32 bytes and indentation at 16 levels, so the output is bounded
 * by a constant multiple of the input. The walk is iterative: a stack of
 * the elements each open container still owes. */

#include <stdio.h>
#include <string.h>

#include <zufast/bits.h>
#include <zufast/hex.h>
#include <zufast/number.h>

#include "zmp.h"
#include "zmp_build.h"
#include "zmp_head.h"

#define ZMP_PREVIEW 32

typedef struct {
    double *offset;
    const char **hex;
    int *depth;
    const char **text;
    R_xlen_t n, cap;
} zmp_lines;

static char *scratch_str(const char *s, size_t n)
{
    char *p = (char *) R_alloc(n + 1, 1);
    memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

static void add_line(zmp_lines *l, size_t offset, const uint8_t *bytes, size_t nbytes,
                     int depth, const char *text)
{
    if (l->n == l->cap)
        Rf_error("zmp_annotate: internal: more lines than bytes");
    char hex[16 * 3];
    size_t k = 0;
    for (size_t i = 0; i < nbytes; i++) {
        if (i)
            hex[k++] = ' ';
        zuf_hex_encode(bytes + i, 1, hex + k, 2, false);
        k += 2;
    }
    l->offset[l->n] = (double) offset;
    l->hex[l->n] = scratch_str(hex, k);
    l->depth[l->n] = depth;
    l->text[l->n] = text ? scratch_str(text, strlen(text)) : "";
    l->n++;
    if (l->n % 65536 == 0)
        R_CheckUserInterrupt();
}

/* A str's first bytes, quoted, cut at a character boundary. */
static void preview(char *out, size_t cap, const uint8_t *p, uint32_t n)
{
    size_t k = 0, take = n < ZMP_PREVIEW ? n : ZMP_PREVIEW;
    /* Back off to the start of a UTF-8 character. */
    while (take < n && take > 0 && (p[take] & 0xc0) == 0x80)
        take--;
    out[k++] = '"';
    for (size_t i = 0; i < take && k + 8 < cap; i++) {
        uint8_t c = p[i];
        if (c == '"' || c == '\\') {
            out[k++] = '\\';
            out[k++] = (char) c;
        } else if (c < 0x20 || c == 0x7f) {
            k += (size_t) snprintf(out + k, cap - k, "\\x%02x", c);
        } else {
            out[k++] = (char) c;
        }
    }
    out[k++] = '"';
    if (take < n && k + 4 < cap) {
        memcpy(out + k, "...", 3);
        k += 3;
    }
    out[k] = '\0';
}

static const char *width_name(uint8_t b)
{
    switch (b) {
    case 0xc4: case 0xc7: case 0xcc: case 0xd0: case 0xd9: return "8";
    case 0xc5: case 0xc8: case 0xcd: case 0xd1: case 0xda: case 0xdc: case 0xde: return "16";
    case 0xc6: case 0xc9: case 0xce: case 0xd2: case 0xdb: case 0xdd: case 0xdf: case 0xca: return "32";
    default: return "64";
    }
}

/* What the head at p is, in words. */
static void describe(char *out, size_t cap, const uint8_t *p, const zmp_head *h)
{
    uint8_t b = p[0];
    char num[40];
    char pv[ZMP_PREVIEW * 4 + 16];
    switch (h->kind) {
    case ZMP_K_NIL: snprintf(out, cap, "nil"); break;
    case ZMP_K_FALSE: snprintf(out, cap, "false"); break;
    case ZMP_K_TRUE: snprintf(out, cap, "true"); break;
    case ZMP_K_UINT:
    case ZMP_K_INT: {
        char *end;
        if (h->negative) {
            num[0] = '-';
            end = zuf_write_u64(num + 1, h->u + 1);   /* never 2^64: int 64 */
        } else {
            end = zuf_write_u64(num, h->u);
        }
        *end = '\0';
        if (h->hlen == 1)
            snprintf(out, cap, "fixint %s", num);
        else
            snprintf(out, cap, "%s %s %s", h->kind == ZMP_K_UINT ? "uint" : "int",
                     width_name(b), num);
        break;
    }
    case ZMP_K_F32:
    case ZMP_K_F64:
        zmp_format_double(h->d, num);
        snprintf(out, cap, "float %s %s", h->kind == ZMP_K_F32 ? "32" : "64", num);
        break;
    case ZMP_K_STR:
        preview(pv, sizeof pv, p + h->hlen, h->len);
        if (h->hlen == 1)
            snprintf(out, cap, "fixstr(%u) %s", (unsigned) h->len, pv);
        else
            snprintf(out, cap, "str %s(%u) %s", width_name(b), (unsigned) h->len, pv);
        break;
    case ZMP_K_BIN:
        snprintf(out, cap, "bin %s(%u)", width_name(b), (unsigned) h->len);
        break;
    case ZMP_K_ARRAY:
        if (h->hlen == 1)
            snprintf(out, cap, "fixarray(%u)", (unsigned) h->len);
        else
            snprintf(out, cap, "array %s(%u)", width_name(b), (unsigned) h->len);
        break;
    case ZMP_K_MAP:
        if (h->hlen == 1)
            snprintf(out, cap, "fixmap(%u)", (unsigned) h->len);
        else
            snprintf(out, cap, "map %s(%u)", width_name(b), (unsigned) h->len);
        break;
    case ZMP_K_EXT: {
        char head[32];
        if (b >= 0xd4 && b <= 0xd8)
            snprintf(head, sizeof head, "fixext %u", (unsigned) h->len);
        else
            snprintf(head, sizeof head, "ext %s(%u)", width_name(b), (unsigned) h->len);
        if (h->ext_type == -1) {
            const uint8_t *q = p + h->hlen;
            if (h->len == 4) {
                snprintf(out, cap, "%s type -1, timestamp 32: %u s", head,
                         (unsigned) zuf_load_be32(q));
            } else if (h->len == 8) {
                uint64_t v = zuf_load_be64(q);
                snprintf(out, cap, "%s type -1, timestamp 64: %llu s %u ns", head,
                         (unsigned long long) (v & ((UINT64_C(1) << 34) - 1)),
                         (unsigned) (v >> 34));
            } else {
                uint64_t u = zuf_load_be64(q + 4);
                long long s = u > (uint64_t) INT64_MAX ? -(long long) (~u) - 1 : (long long) u;
                snprintf(out, cap, "%s type -1, timestamp 96: %lld s %u ns", head, s,
                         (unsigned) zuf_load_be32(q));
            }
        } else {
            snprintf(out, cap, "%s type %d", head, (int) h->ext_type);
        }
        break;
    }
    default:
        snprintf(out, cap, "?");
    }
}

/* x: checked input. sequence: whether to go on after the first object. */
SEXP zmp_annotate_raw(SEXP x, SEXP sequence, SEXP max_depth)
{
    if (TYPEOF(x) != RAWSXP)
        Rf_error("zmp_annotate_raw: arguments must be validated in R");
    const uint8_t *buf = RAW(x);
    size_t len = (size_t) XLENGTH(x);
    int seq = Rf_asLogical(sequence) == TRUE;
    int maxd = Rf_asInteger(max_depth);
    if (maxd < 1 || maxd > ZMP_MAX_DEPTH_CAP)
        Rf_error("zmp_annotate_raw: arguments must be validated in R");

    zmp_lines l;
    l.cap = (R_xlen_t) len + 1;     /* every line covers at least one byte */
    l.n = 0;
    l.offset = (double *) R_alloc((size_t) l.cap, sizeof(double));
    l.hex = (const char **) R_alloc((size_t) l.cap, sizeof(char *));
    l.depth = (int *) R_alloc((size_t) l.cap, sizeof(int));
    l.text = (const char **) R_alloc((size_t) l.cap, sizeof(char *));
    uint64_t *owed = (uint64_t *) R_alloc((size_t) maxd + 2, sizeof(uint64_t));

    size_t pos = 0;
    int depth = 0;
    char text[512];
    while (pos < len) {
        zmp_head h;
        if (zmp_read_head(buf + pos, len - pos, &h) != ZMP_HEAD_OK)
            Rf_error("zmp_annotate_raw: internal: unchecked input");
        describe(text, sizeof text, buf + pos, &h);
        add_line(&l, pos, buf + pos, h.hlen, depth, text);
        pos += h.hlen;
        if (h.kind == ZMP_K_STR || h.kind == ZMP_K_BIN || h.kind == ZMP_K_EXT) {
            for (size_t done = 0; done < h.len; done += 16) {
                size_t k = h.len - done < 16 ? h.len - done : 16;
                add_line(&l, pos + done, buf + pos + done, k, depth + 1, NULL);
            }
            pos += h.len;
        }
        int opened = (h.kind == ZMP_K_ARRAY || h.kind == ZMP_K_MAP) && h.len > 0;
        if (opened) {
            if (depth + 1 > maxd)
                Rf_error("zmp_annotate_raw: internal: deeper than checked");
            depth++;
            owed[depth] = (uint64_t) h.len * (h.kind == ZMP_K_MAP ? 2u : 1u);
            continue;
        }
        /* An element is complete: settle every container it completes. */
        while (depth > 0) {
            owed[depth]--;
            if (owed[depth])
                break;
            depth--;
        }
        if (depth == 0 && !seq)
            break;
    }

    const char *names[] = {"offset", "hex", "depth", "text", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_allocVector(REALSXP, l.n));
    SET_VECTOR_ELT(out, 1, Rf_allocVector(STRSXP, l.n));
    SET_VECTOR_ELT(out, 2, Rf_allocVector(INTSXP, l.n));
    SET_VECTOR_ELT(out, 3, Rf_allocVector(STRSXP, l.n));
    for (R_xlen_t i = 0; i < l.n; i++) {
        REAL(VECTOR_ELT(out, 0))[i] = l.offset[i];
        SET_STRING_ELT(VECTOR_ELT(out, 1), i, Rf_mkChar(l.hex[i]));
        INTEGER(VECTOR_ELT(out, 2))[i] = l.depth[i];
        SET_STRING_ELT(VECTOR_ELT(out, 3), i, Rf_mkCharCE(l.text[i], CE_UTF8));
    }
    UNPROTECT(1);
    return out;
}
