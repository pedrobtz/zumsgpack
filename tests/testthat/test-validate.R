test_that("every encoding in the test suite validates", {
  s <- suite()
  inputs <- lapply(s$hex, hex_raw)
  expect_all_class(inputs, "ok", label = "suite encoding")
  expect_gt(length(inputs), 200L)
})

test_that("every proper prefix of every suite encoding is a parse error", {
  s <- suite()
  prefixes <- unlist(lapply(s$hex, function(h) {
    b <- hex_raw(h)
    lapply(seq_len(length(b)) - 1L, function(n) b[seq_len(n)])
  }), recursive = FALSE)
  expect_all_class(prefixes, "zumsgpack_parse_error", label = "prefix")
  statuses <- unique(vapply(prefixes, function(p) fault_of(p)$status, ""))
  expect_identical(statuses, "ZMP_ERR_TRUNCATED")
})

test_that("bytes after the object are a parse error at their offset", {
  e <- fault_of(hex_raw("c0 c0"))
  expect_s3_class(e, "zumsgpack_parse_error")
  expect_identical(e$status, "ZMP_ERR_TRAILING")
  expect_identical(e$offset, 1)
  expect_true(msgpack_validate(hex_raw("c0 c0"), sequence = TRUE))
})

test_that("an empty input is truncation, and an empty sequence is valid", {
  expect_identical(fault_of(raw())$status, "ZMP_ERR_TRUNCATED")
  expect_true(msgpack_validate(raw(), sequence = TRUE))
})

test_that("a sequence must end on an object boundary", {
  expect_true(msgpack_validate(hex_raw("01 a1 61 92 01 02"), sequence = TRUE))
  e <- fault_of(hex_raw("01 a1 61 92 01"), sequence = TRUE)
  expect_s3_class(e, "zumsgpack_parse_error")
  expect_identical(e$offset, 3)
})

test_that("every str must be UTF-8, whatever its head", {
  bad <- list(
    "c0 80",          # overlong NUL
    "e0 80 80",       # overlong
    "ed a0 80",       # surrogate U+D800
    "ed bf bf",       # surrogate U+DFFF
    "f4 90 80 80",    # above U+10FFFF
    "f8 88 80 80 80", # five-byte form
    "80",             # lone continuation
    "e2 82",          # truncated sequence
    "ff", "fe", "c1 bf", "f5 80 80 80"
  )
  heads <- list(
    function(n) as.raw(0xa0 + n),
    function(n) as.raw(c(0xd9, n)),
    function(n) as.raw(c(0xda, 0, n)),
    function(n) as.raw(c(0xdb, 0, 0, 0, n))
  )
  inputs <- unlist(lapply(bad, function(h) {
    b <- hex_raw(h)
    lapply(heads, function(head) c(head(length(b)), b))
  }), recursive = FALSE)
  expect_all_class(inputs, "zumsgpack_invalid_error", label = "str")
  e <- fault_of(hex_raw("92 01 a2 c0 80"))
  expect_identical(e$status, "ZMP_ERR_INVALID_UTF8")
  expect_identical(e$offset, 2)
  # The same bytes in a bin are just bytes.
  expect_true(msgpack_validate(hex_raw("c4 02 c0 80")))
  # Valid UTF-8 up to the four-byte forms.
  valid("a4 f0 9f 98 80")
  valid("a3 e2 82 ac")
})

test_that("timestamps must have one of the three layouts", {
  valid("d6 ff 00 00 00 00")                                   # timestamp 32
  valid("d7 ff 00 00 00 00 00 00 00 00")                       # timestamp 64
  valid("c7 0c ff 00 00 00 00 00 00 00 00 00 00 00 00")        # timestamp 96
  for (n in c(0, 1, 2, 3, 5, 7, 9, 11, 13, 16)) {
    x <- c(hex_raw("c7"), as.raw(n), hex_raw("ff"), as.raw(rep(0, n)))
    expect_identical(fault_of(x)$status, "ZMP_ERR_TIMESTAMP_LENGTH", info = n)
  }
  expect_s3_class(fault_of(hex_raw("d5 ff 00 00")), "zumsgpack_invalid_error")
  expect_s3_class(fault_of(hex_raw("d8 ff", strrep("00", 16))), "zumsgpack_invalid_error")
  # Other ext types take any payload length, the reserved ones included
  # (design section 18 Q2: read, not refused).
  valid("c7 05 05 01 02 03 04 05")
  valid("c7 05 fe 01 02 03 04 05")
  valid("d4 80 00")
})

test_that("timestamp nanoseconds above 999,999,999 are invalid", {
  # timestamp 64: nanoseconds in the upper 30 bits; 999999999 << 2 and
  # 10^9 << 2 in the first four bytes.
  valid("d7 ff ee 6b 27 fc 00 00 00 00")
  e <- fault_of(hex_raw("d7 ff ee 6b 28 00 00 00 00 00"))
  expect_identical(e$status, "ZMP_ERR_TIMESTAMP_NANOS")
  # timestamp 96: nanoseconds in the first four bytes.
  valid("c7 0c ff 3b 9a c9 ff 00 00 00 00 00 00 00 00")
  e <- fault_of(hex_raw("c7 0c ff 3b 9a ca 00 00 00 00 00 00 00 00 00"))
  expect_identical(e$status, "ZMP_ERR_TIMESTAMP_NANOS")
  expect_s3_class(e, "zumsgpack_invalid_error")
})

test_that("arguments are checked", {
  expect_error(msgpack_validate("c0"), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_validate(NULL), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_validate(raw(1), sequence = NA), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_validate(raw(1), error = 1), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_validate(raw(1), duplicate_keys = "no"),
               class = "zumsgpack_invalid_argument")
  e <- tryCatch(msgpack_validate(1:3), error = identity)
  expect_identical(e$arg, "x")
})

test_that("error = TRUE returns TRUE invisibly", {
  expect_invisible(msgpack_validate(hex_raw("c0"), error = TRUE))
  expect_true(msgpack_validate(hex_raw("c0"), error = TRUE))
})
