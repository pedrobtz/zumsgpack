/* zumsgpack_info()'s entry point, and the proof that both providers link
 * (roadmap Stage 0): one function from each header is called, so a broken
 * LinkingTo fails here rather than in the first stage that needs it. */
#include <zufast.h>
#include <zubin.h>
#include <zubin-r.h>

#include "zmp.h"

/* Loads a big-endian word with zufast, writes it back with zubin into a
 * buffer owned by an external pointer, and checks the bytes survive. */
static int providers_link(void)
{
    static const uint8_t word[4] = {0xde, 0xad, 0xbe, 0xef};
    zb_status st;
    SEXP ptr = PROTECT(zb_r_buf_new(0, 0, &st));
    int ok = 0;
    if (st == ZB_OK) {
        zb_buf *b = zb_r_buf_get(ptr);
        ok = zuf_load_be32(word) == 0xdeadbeefu &&
             zb_put_u32be(b, zuf_load_be32(word)) == ZB_OK &&
             b->len == 4 && memcmp(b->data, word, 4) == 0;
        zb_r_buf_free(ptr);
    }
    UNPROTECT(1);
    return ok;
}

SEXP zmp_build_info(void)
{
    const char *names[] = {"zufast_version", "zubin_version", "max_depth_cap",
                           "providers_ok", ""};
    SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
    SET_VECTOR_ELT(out, 0, Rf_mkString(ZUFAST_VERSION));
    SET_VECTOR_ELT(out, 1, Rf_mkString(ZUBIN_VERSION));
    SET_VECTOR_ELT(out, 2, Rf_ScalarInteger(ZMP_MAX_DEPTH_CAP));
    SET_VECTOR_ELT(out, 3, Rf_ScalarLogical(providers_link()));
    UNPROTECT(1);
    return out;
}
