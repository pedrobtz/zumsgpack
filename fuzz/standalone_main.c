/* Drives a libFuzzer target over files, for compilers with no libFuzzer
 * runtime (Apple's): build with ASan and UBSan alone, then each named file
 * runs once, and with ZMP_MUTATE=n also n random mutations of each (bit
 * flips, byte changes, insertions, deletions, truncations, splices of two
 * inputs) from a fixed seed, so a replay is repeatable. tools/run-fuzz
 * --replay uses it. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

static uint64_t rng = 0x9e3779b97f4a7c15u;

static uint64_t next(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

static uint8_t *slurp(const char *path, size_t *n)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    uint8_t *buf = NULL;
    size_t cap = 0;
    int c;
    *n = 0;
    while ((c = fgetc(f)) != EOF) {
        if (*n == cap) {
            cap = cap ? cap * 2 : 4096;
            uint8_t *nb = realloc(buf, cap);
            if (!nb) {
                free(buf);
                fclose(f);
                return NULL;
            }
            buf = nb;
        }
        buf[(*n)++] = (uint8_t) c;
    }
    fclose(f);
    return buf ? buf : malloc(1);
}

static void mutate(const uint8_t *in, size_t n, const uint8_t *other, size_t on)
{
    size_t cap = n + 64;
    uint8_t *m = malloc(cap);
    if (!m)
        abort();
    memcpy(m, in, n);
    size_t len = n;
    int rounds = 1 + (int) (next() % 4);
    for (int r = 0; r < rounds; r++) {
        switch (next() % 6) {
        case 0: if (len) m[next() % len] ^= (uint8_t) (1u << (next() % 8)); break;
        case 1: if (len) m[next() % len] = (uint8_t) next(); break;
        case 2: if (len < cap) { size_t at = len ? next() % (len + 1) : 0;
                    memmove(m + at + 1, m + at, len - at); m[at] = (uint8_t) next(); len++; } break;
        case 3: if (len) { size_t at = next() % len; memmove(m + at, m + at + 1, len - at - 1); len--; } break;
        case 4: if (len) len = next() % len; break;
        default: if (on && len < cap) { size_t take = next() % (on + 1);
                    if (take > cap - len) take = cap - len;
                    memcpy(m + len, other, take); len += take; } break;
        }
    }
    LLVMFuzzerTestOneInput(m, len);
    free(m);
}

int main(int argc, char **argv)
{
    const char *env = getenv("ZMP_MUTATE");
    long rounds = env ? strtol(env, NULL, 10) : 0;
    size_t total = 0;
    uint8_t **bufs = calloc((size_t) argc, sizeof *bufs);
    size_t *lens = calloc((size_t) argc, sizeof *lens);
    for (int i = 1; i < argc; i++) {
        bufs[i] = slurp(argv[i], &lens[i]);
        if (!bufs[i]) {
            perror(argv[i]);
            return 2;
        }
        LLVMFuzzerTestOneInput(bufs[i], lens[i]);
        total++;
    }
    for (long r = 0; r < rounds; r++) {
        for (int i = 1; i < argc; i++) {
            int j = 1 + (int) (next() % (uint64_t) (argc - 1));
            mutate(bufs[i], lens[i], bufs[j], lens[j]);
            total++;
        }
    }
    printf("replayed %zu inputs\n", total);
    return 0;
}
