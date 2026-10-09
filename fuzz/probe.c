/* The check phase without R: prints the status of each file named, or "ok",
 * under the default limits. Options: --seq, --prefix, --stream for the other
 * modes, --dup to accept duplicate keys, --depth N and --items N for the
 * limits. Used by tools/run-mutation-check and the standalone gate. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zmp_check.h"

void zmp_arena_reset(void);

static unsigned char *slurp(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    unsigned char *buf = NULL;
    size_t cap = 0;
    int c;
    *n = 0;
    while ((c = fgetc(f)) != EOF) {
        if (*n == cap) {
            cap = cap ? cap * 2 : 4096;
            unsigned char *nb = realloc(buf, cap);
            if (!nb) {
                free(buf);
                fclose(f);
                return NULL;
            }
            buf = nb;
        }
        buf[(*n)++] = (unsigned char) c;
    }
    fclose(f);
    return buf ? buf : malloc(1);
}

int main(int argc, char **argv)
{
    zmp_check_opts opt = {256, 1000000, 0, ZMP_MODE_ONE};
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--seq") == 0) { opt.mode = ZMP_MODE_SEQ; continue; }
        if (strcmp(argv[i], "--prefix") == 0) { opt.mode = ZMP_MODE_PREFIX; continue; }
        if (strcmp(argv[i], "--stream") == 0) { opt.mode = ZMP_MODE_STREAM; continue; }
        if (strcmp(argv[i], "--dup") == 0) { opt.duplicate_keys = 1; continue; }
        if (strcmp(argv[i], "--depth") == 0 && i + 1 < argc) { opt.max_depth = atoi(argv[++i]); continue; }
        if (strcmp(argv[i], "--items") == 0 && i + 1 < argc) { opt.max_items = strtoull(argv[++i], NULL, 10); continue; }
        size_t n;
        unsigned char *buf = slurp(argv[i], &n);
        if (!buf) {
            perror(argv[i]);
            return 2;
        }
        zmp_plan plan;
        zmp_fault fault;
        if (zmp_check(buf, n, &opt, &plan, &fault))
            printf("%s %s %.0f\n", argv[i], fault.status, fault.offset);
        else
            printf("%s ok %zu %zu\n", argv[i], plan.n_items, plan.consumed);
        zmp_arena_reset();
        free(buf);
    }
    return 0;
}
