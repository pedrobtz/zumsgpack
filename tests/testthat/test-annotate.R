# The hex column of an annotation, joined, is the input: every byte exactly once.
annotated_bytes <- function(a) {
  # offset, two spaces, hex pairs separated by single spaces, then padding.
  hex <- sub("^\\s*[0-9]+  ((?:[0-9a-f]{2} ?)+).*$", "\\1", unclass(a), perl = TRUE)
  hex_raw(paste(hex, collapse = " "))
}

test_that("every suite encoding annotates with each byte exactly once", {
  s <- suite()
  ok <- vapply(s$hex, function(h) {
    b <- hex_raw(h)
    identical(annotated_bytes(msgpack_annotate(b)), b)
  }, NA)
  expect_true(all(ok), info = paste(s$hex[!ok], collapse = "; "))
})

test_that("Python's objects annotate with each byte exactly once", {
  p <- python_fixtures()
  for (i in seq_len(nrow(p))) {
    b <- hex_raw(p$hex[i])
    seq <- p$name[i] == "fluentd forward stream"
    expect_identical(annotated_bytes(msgpack_annotate(b, sequence = seq)), b, info = p$name[i])
  }
})

test_that("lines say what each head is, indented by depth", {
  a <- unclass(msgpack_annotate(msgpack_encode(list(a = 300L, b = list(-1L, "xy", NULL)))))
  expect_identical(a, c(
    " 0  82        fixmap(2)",
    " 1  a1          fixstr(1) \"a\"",
    " 2  61",
    " 3  cd 01 2c    uint 16 300",
    " 6  a1          fixstr(1) \"b\"",
    " 7  62",
    " 8  93          fixarray(3)",
    " 9  ff            fixint -1",
    "10  a2            fixstr(2) \"xy\"",
    "11  78 79",
    "13  c0            nil"))
  expect_output(print(msgpack_annotate(hex_raw("c3"))), "0  c3  true", fixed = TRUE)
})

test_that("timestamps, exts, floats and long payloads are described", {
  a <- unclass(msgpack_annotate(hex_raw("d7 ff a1 dc d7 c8 5a 4a f6 a5")))
  expect_match(a[1], "timestamp 64: 1514862245 s 678901234 ns", fixed = TRUE)
  a <- unclass(msgpack_annotate(hex_raw("c7 0c ff 3b 9a c9 ff ff ff ff ff ff ff ff ff")))
  expect_match(a[1], "timestamp 96: -1 s 999999999 ns", fixed = TRUE)
  expect_match(unclass(msgpack_annotate(hex_raw("c7 03 05 01 02 03")))[1], "ext 8(3) type 5", fixed = TRUE)
  expect_match(unclass(msgpack_annotate(hex_raw("ca 3f c0 00 00")))[1], "float 32 1.5", fixed = TRUE)
  expect_match(unclass(msgpack_annotate(hex_raw("cb 3f f0 00 00 00 00 00 00")))[1], "float 64 1.0", fixed = TRUE)
  long <- msgpack_encode(strrep("é", 40))
  a <- unclass(msgpack_annotate(long))
  expect_match(a[1], "str 8(80) \"", fixed = TRUE)
  expect_match(a[1], "...$")
  expect_length(a, 1L + 5L)          # head, then 80 bytes in rows of 16
  expect_identical(Encoding(a[1]), "UTF-8")
})

test_that("input is checked before it is annotated", {
  expect_error(msgpack_annotate(hex_raw("92 01")), class = "zumsgpack_parse_error")
  expect_error(msgpack_annotate(hex_raw("82 01 c0 01 c0")), class = "zumsgpack_duplicate_key")
  expect_error(msgpack_annotate(hex_raw("91 91 c0"), max_depth = 1L), class = "zumsgpack_depth_limit")
  expect_length(msgpack_annotate(raw(), sequence = TRUE), 0L)
  expect_length(msgpack_annotate(hex_raw("01 02"), sequence = TRUE), 2L)
})

test_that("deep nesting is indented at most 16 levels", {
  x <- c(rep(as.raw(0x91), 40), as.raw(0xc0))
  a <- unclass(msgpack_annotate(x))
  # Line k is at depth k - 1: the nil at depth 40 lines up with depth 16.
  expect_identical(as.integer(regexpr("nil", a[41])), as.integer(regexpr("fixarray", a[17])))
  expect_gt(as.integer(regexpr("fixarray", a[17])), as.integer(regexpr("fixarray", a[16])))
})
