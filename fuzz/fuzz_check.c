/* libFuzzer target over the R-free check phase (roadmap Stage 7), with
 * zucbor's invariants rather than "no crash" alone:
 *
 *   - relaxing an option never rejects what the stricter one accepted;
 *   - an input that passes as one object passes as a prefix consuming every
 *     byte, and as a sequence and a stream of one object;
 *   - a prefix consuming n bytes passes as one object over those n;
 *   - a stream stops on an object boundary: what it consumed passes as a
 *     sequence, and an input that passes as a sequence is consumed whole;
 *   - every proper prefix of an object that passes is truncation;
 *   - a pass never reports more containers than there are input bytes.
 *
 * An invariant that fails aborts, which libFuzzer reports as a crash. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "zmp_check.h"

void zmp_arena_reset(void);

static int check(const uint8_t *d, size_t n, int mode, int dup, int depth,
                 uint64_t items, zmp_plan *plan, zmp_fault *fault)
{
    zmp_check_opts o;
    o.mode = mode;
    o.duplicate_keys = dup;
    o.max_depth = depth;
    o.max_items = items;
    zmp_plan scratch_plan;
    int r = zmp_check(d, n, &o, plan ? plan : &scratch_plan, fault);
    return r;
}

#define REQUIRE(c) do { if (!(c)) abort(); } while (0)

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    zmp_plan plan;
    zmp_fault fault;

    int strict = check(data, size, ZMP_MODE_ONE, 0, 64, 10000, &plan, &fault);
    if (strict == 0) {
        REQUIRE(plan.n_items == 1 && plan.consumed == size);
        REQUIRE(plan.n <= size);
        REQUIRE(check(data, size, ZMP_MODE_ONE, 1, ZMP_MAX_DEPTH_CAP, UINT64_MAX, NULL, &fault) == 0);
        REQUIRE(check(data, size, ZMP_MODE_PREFIX, 0, 64, 10000, &plan, &fault) == 0);
        REQUIRE(plan.consumed == size);
        REQUIRE(check(data, size, ZMP_MODE_SEQ, 0, 64, 10000, &plan, &fault) == 0);
        REQUIRE(plan.n_items == 1);
        REQUIRE(check(data, size, ZMP_MODE_STREAM, 0, 64, 10000, &plan, &fault) == 0);
        REQUIRE(plan.n_items == 1 && plan.consumed == size);
        /* Every proper prefix is truncation, nothing else. Bounded, so a
         * large input does not make one execution quadratic. */
        size_t step = size > 64 ? size / 64 : 1;
        for (size_t k = 0; k < size; k += step) {
            REQUIRE(check(data, k, ZMP_MODE_ONE, 0, 64, 10000, NULL, &fault) == 1);
            REQUIRE(strcmp(fault.status, ZMP_ERR_TRUNCATED) == 0);
        }
    }
    zmp_arena_reset();

    if (check(data, size, ZMP_MODE_PREFIX, 0, 64, 10000, &plan, &fault) == 0) {
        size_t used = plan.consumed;
        REQUIRE(used >= 1 && used <= size);
        REQUIRE(check(data, used, ZMP_MODE_ONE, 0, 64, 10000, NULL, &fault) == 0);
    }
    zmp_arena_reset();

    if (check(data, size, ZMP_MODE_SEQ, 0, 64, 10000, &plan, &fault) == 0) {
        size_t items = plan.n_items;
        REQUIRE(check(data, size, ZMP_MODE_SEQ, 1, ZMP_MAX_DEPTH_CAP, UINT64_MAX, NULL, &fault) == 0);
        REQUIRE(check(data, size, ZMP_MODE_STREAM, 0, 64, 10000, &plan, &fault) == 0);
        REQUIRE(plan.consumed == size && plan.n_items == items);
    }
    zmp_arena_reset();

    if (check(data, size, ZMP_MODE_STREAM, 0, 64, 10000, &plan, &fault) == 0) {
        size_t used = plan.consumed;
        REQUIRE(used <= size);
        REQUIRE(check(data, used, ZMP_MODE_SEQ, 0, 64, UINT64_MAX, NULL, &fault) == 0);
    }
    zmp_arena_reset();
    return 0;
}
