/* Every status a fault can carry, without R: the check phase reports them by
 * name, and R maps each name to a condition class (design section 11).
 * test-conditions.R fails if R's class map misses one. */
#include "zmp_check.h"

static const char *const statuses[] = {
    ZMP_ERR_TRUNCATED,
    ZMP_ERR_RESERVED,
    ZMP_ERR_TRAILING,
    ZMP_ERR_INVALID_UTF8,
    ZMP_ERR_TIMESTAMP_LENGTH,
    ZMP_ERR_TIMESTAMP_NANOS,
    ZMP_ERR_DUPLICATE_KEY,
    ZMP_ERR_DEPTH_LIMIT,
    ZMP_ERR_ITEM_LIMIT,
    ZMP_ERR_SIZE_LIMIT,
    ZMP_ERR_CELL_LIMIT,
    ZMP_ERR_NUL_IN_STR,
    ZMP_ERR_STRING_TOO_LONG,
    ZMP_ERR_BIG_INTEGER,
    ZMP_ERR_KEY_COLLISION,
    ZMP_ERR_UNSUPPORTED_TYPE,
    ZMP_ERR_UNREPRESENTABLE,
    ZMP_ERR_INVALID_VALUE,
};

size_t zmp_status_count(void)
{
    return sizeof statuses / sizeof statuses[0];
}

const char *zmp_status_at(size_t i)
{
    return i < zmp_status_count() ? statuses[i] : NULL;
}
