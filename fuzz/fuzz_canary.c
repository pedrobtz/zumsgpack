/* The canary (roadmap Stage 7): the same check, the same build, and a
 * planted crash on any input it accepts. tools/run-fuzz requires it to
 * crash before any real target runs, so a harness that never reaches the
 * check phase -- a broken build, a sanitizer that is not linked, seeds that
 * are never fed -- cannot pass for a clean run. */
#include <stdint.h>
#include <stdlib.h>

#include "zmp_check.h"

void zmp_arena_reset(void);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    zmp_check_opts o = {64, 10000, 0, ZMP_MODE_ONE};
    zmp_plan plan;
    zmp_fault fault;
    int r = zmp_check(data, size, &o, &plan, &fault);
    zmp_arena_reset();
    if (r == 0)
        __builtin_trap();
    return 0;
}
