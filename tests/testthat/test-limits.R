test_that("length headers claiming more than the input are truncation at offset 0", {
  # Hostile inputs of design section 15, each a permanent regression.
  for (h in c("dd ff ff ff ff", "df ff ff ff ff", "db ff ff ff ff 61 62",
              "c6 ff ff ff ff 00", "c9 ff ff ff ff 01 00", "dc ff ff", "de ff ff 01")) {
    e <- fault_of(hex_raw(h))
    expect_s3_class(e, "zumsgpack_parse_error")
    expect_identical(e$status, "ZMP_ERR_TRUNCATED", info = h)
    expect_identical(e$offset, 0, info = h)
  }
})

test_that("a map count is checked against two bytes per pair", {
  # One pair needs two bytes: 0x81 with one byte left is truncated before
  # anything is walked.
  e <- fault_of(hex_raw("81 01"))
  expect_identical(e$offset, 0)
  valid("81 01 02")
})

test_that("a million nested arrays fail at the depth limit, not the C stack", {
  x <- c(rep(as.raw(0x91), 1e6), as.raw(0xc0))
  e <- fault_of(x)
  expect_s3_class(e, "zumsgpack_depth_limit")
  expect_s3_class(e, "zumsgpack_limit_error")
  expect_identical(e$limit, "max_depth")
  expect_identical(e$limit_value, 256)
  expect_identical(e$offset, 256)
  expect_s3_class(fault_of(x, max_depth = 1023L), "zumsgpack_depth_limit")
})

test_that("max_depth counts arrays, maps and exts, and 1023 is the ceiling", {
  nest <- function(n, byte = 0x91) c(rep(as.raw(byte), n), as.raw(0xc0))
  expect_true(msgpack_validate(nest(1023), max_depth = 1023L))
  expect_s3_class(fault_of(nest(1024), max_depth = 1023L), "zumsgpack_depth_limit")
  expect_error(msgpack_validate(nest(1), max_depth = 1024L),
               class = "zumsgpack_invalid_argument")
  expect_true(msgpack_validate(nest(3), max_depth = 3L))
  expect_s3_class(fault_of(nest(4), max_depth = 3L), "zumsgpack_depth_limit")
  # Maps: {nil: {nil: nil}} is two levels.
  expect_true(msgpack_validate(hex_raw("81 c0 81 c0 c0"), max_depth = 2L))
  expect_s3_class(fault_of(hex_raw("81 c0 81 c0 c0"), max_depth = 1L),
                  "zumsgpack_depth_limit")
  # An ext is one level, as a tag is in zucbor.
  expect_true(msgpack_validate(hex_raw("d4 05 00"), max_depth = 1L))
  expect_true(msgpack_validate(hex_raw("91 d4 05 00"), max_depth = 2L))
  expect_s3_class(fault_of(hex_raw("91 d4 05 00"), max_depth = 1L),
                  "zumsgpack_depth_limit")
})

test_that("max_items counts every object", {
  x <- hex_raw("93 01 02 03")     # four objects
  expect_true(msgpack_validate(x, max_items = 4))
  e <- fault_of(x, max_items = 3)
  expect_s3_class(e, "zumsgpack_item_limit")
  expect_identical(e$limit, "max_items")
  expect_identical(e$limit_value, 3)
  expect_identical(e$offset, 3)
  # A map's keys and values are each an object: {1: 2} is three.
  expect_true(msgpack_validate(hex_raw("81 01 02"), max_items = 3))
  expect_s3_class(fault_of(hex_raw("81 01 02"), max_items = 2), "zumsgpack_item_limit")
  # In a sequence the count runs across the objects.
  expect_s3_class(fault_of(hex_raw("01 02 03"), sequence = TRUE, max_items = 2),
                  "zumsgpack_item_limit")
})

test_that("max_size is checked before the walk", {
  e <- fault_of(hex_raw("93 01 02 03"), max_size = 3)
  expect_s3_class(e, "zumsgpack_size_limit")
  expect_identical(e$limit, "max_size")
  expect_identical(e$limit_value, 3)
  expect_true(msgpack_validate(hex_raw("93 01 02 03"), max_size = 4))
})

test_that("limits must be positive whole numbers", {
  x <- hex_raw("c0")
  for (bad in list(0, -1, 1.5, NA, NaN, "1", c(1, 2), NULL)) {
    expect_error(msgpack_validate(x, max_items = bad), class = "zumsgpack_invalid_argument")
    expect_error(msgpack_validate(x, max_depth = bad), class = "zumsgpack_invalid_argument")
    expect_error(msgpack_validate(x, max_size = bad), class = "zumsgpack_invalid_argument")
  }
  expect_error(msgpack_validate(x, max_depth = Inf), class = "zumsgpack_invalid_argument")
  expect_true(msgpack_validate(x, max_items = Inf, max_size = Inf))
})

test_that("the reserved byte 0xc1 is a parse error wherever it appears", {
  for (h in c("c1", "91 c1", "81 c1 c0", "81 c0 c1")) {
    e <- fault_of(hex_raw(h))
    expect_identical(e$status, "ZMP_ERR_RESERVED", info = h)
    expect_s3_class(e, "zumsgpack_parse_error")
  }
})
