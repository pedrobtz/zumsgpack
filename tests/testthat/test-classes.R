test_that("msgpack_map() pairs keys and values", {
  m <- msgpack_map(list(1L, "a"), list(TRUE, NULL))
  expect_s3_class(m, "msgpack_map")
  expect_length(m, 2L)
  expect_identical(unclass(m)$keys, list(1L, "a"))
  expect_error(msgpack_map(list(1), list()), class = "zumsgpack_invalid_argument")
  expect_output(print(m), "<msgpack_map: 2 entries>")
})

test_that("msgpack_ext() checks its type and data", {
  e <- msgpack_ext(-1, as.raw(1:4))
  expect_identical(unclass(e), list(type = -1L, data = as.raw(1:4)))
  expect_identical(format(e), "ext(-1, h'01020304')")
  for (bad in list(128, -129, 1.5, NA, "1", c(1, 2)))
    expect_error(msgpack_ext(bad), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_ext(1, 1:3), class = "zumsgpack_invalid_argument")
  expect_output(print(e), "<msgpack_ext type -1, 4 bytes>")
})

test_that("msgpack_bigint() keeps canonical decimal text", {
  b <- msgpack_bigint(c("18446744073709551615", "-0", NA))
  expect_identical(as.character(b), c("18446744073709551615", "0", NA))
  expect_identical(msgpack_bigint(2^53), msgpack_bigint("9007199254740992"))
  expect_identical(as.numeric(msgpack_bigint("12")), 12)
  expect_identical(b[1], msgpack_bigint("18446744073709551615"))
  for (bad in list("01", "1.0", "+1", 2^53 + 2, 1.5, TRUE))
    expect_error(msgpack_bigint(bad), class = "zumsgpack_invalid_argument")
  expect_output(print(b), "<msgpack_bigint\\[3\\]>")
})
