test_that("the first object is decoded and the bytes it used reported", {
  r <- msgpack_decode_prefix(hex_raw("92 01 02 de ad be ef"))
  expect_identical(r, list(value = 1:2, consumed = 3))
  # Trailing valid MessagePack is not read either.
  expect_identical(msgpack_decode_prefix(hex_raw("01 02 03")), list(value = 1L, consumed = 1))
  # An object exactly filling the input.
  expect_identical(msgpack_decode_prefix(hex_raw("a1 61")), list(value = "a", consumed = 2))
})

test_that("nothing after the object is read, whatever it is", {
  junk <- list("c1", "dd ff ff ff ff", "a2 c0 80", "91 91 91", "82 01 c0 01 c0",
               "d7 ff ee 6b 28 00 00 00 00 00")
  for (j in junk) {
    r <- msgpack_decode_prefix(c(hex_raw("81 a1 61 c3"), hex_raw(j)),
                               max_depth = 1L, max_items = 3)
    expect_identical(r, list(value = list(a = TRUE), consumed = 4), info = j)
  }
})

test_that("an empty or cut-short input is a parse error", {
  expect_error(msgpack_decode_prefix(raw()), class = "zumsgpack_parse_error")
  expect_error(msgpack_decode_prefix(hex_raw("92 01")), class = "zumsgpack_parse_error")
})

test_that("every suite encoding with random bytes appended decodes as itself", {
  set.seed(42)
  s <- suite()
  ok <- vapply(s$hex, function(h) {
    b <- hex_raw(h)
    r <- msgpack_decode_prefix(c(b, as.raw(sample.int(256, 5, TRUE) - 1L)))
    r$consumed == length(b) && identical(r$value, msgpack_decode(b))
  }, logical(1))
  expect_true(all(ok), info = paste(s$hex[!ok], collapse = "; "))
})

test_that("options and limits apply as in msgpack_decode()", {
  expect_identical(msgpack_decode_prefix(hex_raw("d6 ff 00 00 00 01 ff"), ext = "keep")$value,
                   msgpack_ext(-1, as.raw(c(0, 0, 0, 1))))
  expect_error(msgpack_decode_prefix(hex_raw("93 01 02 03 00"), max_items = 2),
               class = "zumsgpack_item_limit")
  expect_error(msgpack_decode_prefix(hex_raw("01 02"), max_size = 1),
               class = "zumsgpack_size_limit")
})
