# One test per row of design section 6.1, then the lattice (6.2), maps and
# the suite.

test_that("every integer form decodes to integer, double or msgpack_bigint", {
  expect_identical(dec("00"), 0L)
  expect_identical(dec("7f"), 127L)
  expect_identical(dec("ff"), -1L)
  expect_identical(dec("e0"), -32L)
  expect_identical(dec("cc ff"), 255L)
  expect_identical(dec("cd ff ff"), 65535L)
  expect_identical(dec("d0 80"), -128L)
  expect_identical(dec("d1 80 00"), -32768L)
  expect_identical(dec("d0 05"), 5L)                      # positive in a signed form
  # R's integer range: NA_integer_ is -2^31, so -2^31 is a double.
  expect_identical(dec("ce 7f ff ff ff"), 2147483647L)
  expect_identical(dec("ce 80 00 00 00"), 2147483648)
  expect_identical(dec("d2 80 00 00 01"), -2147483647L)
  expect_identical(dec("d2 80 00 00 00"), -2147483648)
  # Exact up to 2^53, then big_integers.
  expect_identical(dec("cf 00 20 00 00 00 00 00 00"), 2^53)
  expect_identical(dec("d3 ff e0 00 00 00 00 00 01"), -(2^53 - 1))
  expect_identical(dec("cf 00 20 00 00 00 00 00 01"), msgpack_bigint("9007199254740993"))
  expect_identical(dec("d3 ff e0 00 00 00 00 00 00"), -2^53)
  expect_identical(dec("d3 ff df ff ff ff ff ff ff"), msgpack_bigint("-9007199254740993"))
})

test_that("the 64-bit boundaries are exact as msgpack_bigint", {
  expect_identical(dec("cf ff ff ff ff ff ff ff ff"), msgpack_bigint("18446744073709551615"))
  expect_identical(dec("cf 80 00 00 00 00 00 00 00"), msgpack_bigint("9223372036854775808"))
  expect_identical(dec("d3 7f ff ff ff ff ff ff ff"), msgpack_bigint("9223372036854775807"))
  expect_identical(dec("d3 80 00 00 00 00 00 00 00"), msgpack_bigint("-9223372036854775808"))
})

test_that("big_integers chooses between bigint, double and an error", {
  x <- "cf ff ff ff ff ff ff ff ff"
  expect_identical(dec(x, big_integers = "double"), 2^64)
  expect_identical(dec("d3 80 00 00 00 00 00 00 00", big_integers = "double"), -2^63)
  e <- expect_error(dec(x, big_integers = "error"), class = "zumsgpack_unrepresentable")
  expect_identical(e$status, "ZMP_ERR_BIG_INTEGER")
  expect_identical(e$offset, 0)
  # 2^53 itself is exact whatever big_integers says.
  expect_identical(dec("cf 00 20 00 00 00 00 00 00", big_integers = "error"), 2^53)
})

test_that("floats decode exactly, float 32 widened", {
  expect_identical(dec("cb 3f f8 00 00 00 00 00 00"), 1.5)
  expect_identical(dec("ca 3d cc cc cd"), f32("3d cc cc cd"))
  expect_false(identical(dec("ca 3d cc cc cd"), f64("3f b9 99 99 99 99 99 9a")))
  expect_identical(dec("cb 7f f0 00 00 00 00 00 00"), Inf)
  expect_identical(dec("ca ff 80 00 00"), -Inf)
  expect_true(is.nan(dec("cb 7f f8 00 00 00 00 00 00")))
  z <- dec("cb 80 00 00 00 00 00 00 00")
  expect_identical(z, 0)
  expect_identical(1 / z, -Inf)
  # A whole-valued float stays a double, never an integer.
  expect_identical(dec("cb 3f f0 00 00 00 00 00 00"), 1)
})

test_that("every float 64 NaN payload is kept, so NA_real_ survives", {
  na <- dec("cb 7f f0 00 00 00 00 07 a2")    # R's NA_real_ bits
  expect_identical(na, NA_real_)
  expect_false(is.nan(na))
  payload <- dec("cb 7f f8 00 00 00 00 12 34")
  expect_identical(writeBin(payload, raw(), endian = "big"), hex_raw("7f f8 00 00 00 00 12 34"))
})

test_that("true, false and nil", {
  expect_identical(dec("c3"), TRUE)
  expect_identical(dec("c2"), FALSE)
  expect_null(dec("c0"))
})

test_that("bin is raw in every head", {
  expect_identical(dec("c4 00"), raw())
  expect_identical(dec("c4 02 00 ff"), as.raw(c(0, 255)))
  expect_identical(dec("c5 00 02 00 ff"), as.raw(c(0, 255)))
  expect_identical(dec("c6 00 00 00 02 00 ff"), as.raw(c(0, 255)))
})

test_that("str is UTF-8 character in every head", {
  expect_identical(dec("a0"), "")
  expect_identical(dec("a1 61"), "a")
  expect_identical(dec("d9 01 61"), "a")
  expect_identical(dec("da 00 01 61"), "a")
  expect_identical(dec("db 00 00 00 01 61"), "a")
  s <- dec("a3 e2 82 ac")
  expect_identical(s, "€")
  expect_identical(Encoding(s), "UTF-8")
  long <- strrep("x", 300)
  expect_identical(dec(paste("da 01 2c", raw_hex(charToRaw(long)))), long)
})

test_that("a str holding U+0000 is unrepresentable, wherever it is", {
  for (h in c("a3 61 00 62", "91 a1 00", "81 a1 00 01", "81 01 a1 00")) {
    e <- expect_error(dec(h), class = "zumsgpack_unrepresentable")
    expect_identical(e$status, "ZMP_ERR_NUL_IN_STR", info = h)
  }
  # But it validates: the bytes are valid MessagePack.
  expect_true(msgpack_validate(hex_raw("a3 61 00 62")))
  e <- expect_error(dec("92 01 a1 00"), class = "zumsgpack_unrepresentable")
  expect_identical(e$offset, 2)
})

test_that("an ext is msgpack_ext, reserved types included", {
  expect_identical(dec("d4 05 01"), msgpack_ext(5, as.raw(1)))
  expect_identical(dec("c7 00 07"), msgpack_ext(7, raw()))
  expect_identical(dec("c7 03 fe 01 02 03"), msgpack_ext(-2, as.raw(1:3)))
  expect_identical(dec(paste("d8 80", strrep("00", 16))), msgpack_ext(-128, raw(16)))
})

test_that("arrays simplify by the lattice", {
  expect_identical(dec("92 01 02"), 1:2)
  expect_identical(dec("92 01 cb 40 04 00 00 00 00 00 00"), c(1, 2.5))
  expect_identical(dec("92 01 c0"), c(1L, NA))
  expect_identical(dec("92 cb 3f f8 00 00 00 00 00 00 c0"), c(1.5, NA))
  expect_identical(dec("92 c3 c0"), c(TRUE, NA))
  expect_identical(dec("92 a1 61 c0"), c("a", NA))
  expect_identical(dec("92 c0 c0"), c(NA, NA))
  expect_identical(dec("90"), logical(0))
  # Integers beyond R's range join as doubles.
  expect_identical(dec("92 01 ce 80 00 00 00"), c(1, 2147483648))
})

test_that("booleans and numbers do not mix, nor anything with a list kind", {
  expect_identical(dec("92 c2 cb 3f f8 00 00 00 00 00 00"), list(FALSE, 1.5))
  expect_identical(dec("92 c3 01"), list(TRUE, 1L))
  expect_identical(dec("92 01 a1 61"), list(1L, "a"))
  expect_identical(dec("92 01 c4 01 00"), list(1L, as.raw(0)))
  expect_identical(dec("92 90 90"), list(logical(0), logical(0)))
  expect_identical(dec("92 01 d4 05 00"), list(1L, msgpack_ext(5, raw(1))))
})

test_that("wide integers and integer-valued numbers combine to msgpack_bigint", {
  x <- dec("93 cf ff ff ff ff ff ff ff ff 01 c0")
  expect_identical(x, msgpack_bigint(c("18446744073709551615", "1", NA)))
  expect_identical(dec("92 cf ff ff ff ff ff ff ff ff ff"),
                   msgpack_bigint(c("18446744073709551615", "-1")))
  # ... but a float with them is a list: the float may not be integral.
  expect_type(dec("92 cf ff ff ff ff ff ff ff ff cb 3f f8 00 00 00 00 00 00"), "list")
  # A 2^53-range double joins too, exactly.
  expect_identical(dec("92 cf ff ff ff ff ff ff ff ff cf 00 20 00 00 00 00 00 00"),
                   msgpack_bigint(c("18446744073709551615", "9007199254740992")))
})

test_that("a one-element array that simplifies is marked I()", {
  expect_identical(dec("91 01"), I(1L))
  expect_identical(dec("91 a1 61"), I("a"))
  expect_identical(dec("91 c0"), I(NA))
  expect_identical(dec("91 cf ff ff ff ff ff ff ff ff"), I(msgpack_bigint("18446744073709551615")))
  # A list is never marked: it is already an array.
  expect_identical(dec("91 90"), list(logical(0)))
  expect_identical(dec("92 01 02"), 1:2)
})

test_that("simplify = \"none\" makes every array a list", {
  expect_identical(dec("92 01 02", simplify = "none"), list(1L, 2L))
  expect_identical(dec("92 01 c0", simplify = "none"), list(1L, NULL))
  expect_identical(dec("90", simplify = "none"), list())
})

test_that("maps with non-empty unique str keys are named lists", {
  expect_identical(dec("82 a1 61 01 a1 62 c3"), list(a = 1L, b = TRUE))
  expect_identical(dec("80"), structure(list(), names = character()))
  expect_identical(dec("81 a1 61 92 01 02"), list(a = 1:2))
  nested <- dec("81 a1 61 81 a1 62 c0")
  expect_identical(nested, list(a = list(b = NULL)))
})

test_that("any other map is a msgpack_map", {
  expect_identical(dec("81 01 d0 f9"), msgpack_map(list(1L), list(-7L)))
  expect_identical(dec("82 a1 61 01 01 02"), msgpack_map(list("a", 1L), list(1L, 2L)))
  expect_identical(dec("81 a0 01"), msgpack_map(list(""), list(1L)))
  expect_identical(dec("81 c4 01 00 01"), msgpack_map(list(as.raw(0)), list(1L)))
  expect_identical(dec("81 91 01 c0"), msgpack_map(list(I(1L)), list(NULL)))
})

test_that("map_keys = \"map\" always gives a msgpack_map", {
  expect_identical(dec("81 a1 61 01", map_keys = "map"), msgpack_map(list("a"), list(1L)))
  expect_identical(dec("80", map_keys = "map"), msgpack_map())
})

test_that("map_keys = \"string\" names every key", {
  x <- dec(paste("88 01 c0 cb 3f f0 00 00 00 00 00 00 c0 c0 c0 c3 c0 c4 02 00 ff c0",
                 "d4 05 01 c0 92 01 a1 61 c0 81 a1 61 c2 c0"), map_keys = "string")
  expect_identical(names(x), c("1", "1.0", "nil", "true", "h'00ff'", "ext(5, h'01')",
                               "[1, \"a\"]", "{\"a\": false}"))
  expect_identical(dec("81 ff 01", map_keys = "string"), list("-1" = 1L))
  expect_identical(dec("81 a1 61 01", map_keys = "string"), list(a = 1L))
  # Keys that collide once named are refused, whatever duplicate_keys says.
  e <- expect_error(dec("82 01 c0 a1 31 c0", map_keys = "string"),
                    class = "zumsgpack_duplicate_key")
  expect_identical(e$status, "ZMP_ERR_KEY_COLLISION")
  expect_error(dec("82 01 c0 a1 31 c0", map_keys = "string", duplicate_keys = TRUE),
               class = "zumsgpack_duplicate_key")
})

test_that("duplicate keys are refused by default, and kept in a msgpack_map when allowed", {
  expect_error(dec("82 a1 61 01 a1 61 02"), class = "zumsgpack_duplicate_key")
  expect_identical(dec("82 a1 61 01 a1 61 02", duplicate_keys = TRUE),
                   msgpack_map(list("a", "a"), list(1L, 2L)))
  expect_identical(dec("82 01 01 cc 01 02", duplicate_keys = TRUE),
                   msgpack_map(list(1L, 1L), list(1L, 2L)))
})

test_that("a sequence decodes to a list, one element per object", {
  expect_identical(msgpack_decode_seq(hex_raw("01 a1 61 92 01 02")), list(1L, "a", 1:2))
  expect_identical(msgpack_decode_seq(raw()), list())
  expect_error(msgpack_decode(hex_raw("01 02")), class = "zumsgpack_parse_error")
  expect_error(msgpack_decode_seq(hex_raw("01 92")), class = "zumsgpack_parse_error")
})

test_that("every suite case decodes to its value, in every encoding", {
  s <- suite()
  s <- s[!s$type %in% c("timestamp"), ]   # Stage 4
  got <- lapply(s$hex, function(h) msgpack_decode(hex_raw(h)))
  want <- lapply(seq_len(nrow(s)), function(i) {
    v <- eval(str2lang(s$value[i]))
    switch(s$type[i],
      binary = hex_raw(v),
      bignum = as.numeric(v),
      ext = list(ext = as.numeric(v[[1]]), data = hex_raw(v[[2]])),
      v)
  })
  same <- vapply(seq_along(got), function(i) {
    g <- got[[i]]
    if (s$type[i] == "bignum" && inherits(g, "msgpack_bigint"))
      return(identical(as.character(g), eval(str2lang(s$value[i]))))
    isTRUE(all.equal(json_shape(g), json_shape(want[[i]]), tolerance = 0))
  }, logical(1))
  expect(all(same), paste("differ:", paste(s$group[!same], s$hex[!same], collapse = "; ")))
  expect_gt(length(got), 200L)
})

test_that("integer types follow the head, not the suite's JSON", {
  # A float form of a whole number is still a double, an integer form an
  # integer: the head decides the kind (design section 6.2).
  s <- suite()
  num <- s[s$type == "number", ]
  for (i in seq_len(nrow(num))) {
    b <- hex_raw(num$hex[i])
    v <- msgpack_decode(b)
    if (b[1] %in% as.raw(c(0xca, 0xcb))) expect_type(v, "double")
  }
})

test_that("arguments are checked", {
  x <- hex_raw("c0")
  expect_error(msgpack_decode(x, simplify = "all"), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_decode(x, map_keys = NA), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_decode(x, big_integers = c("double", "error")),
               class = "zumsgpack_invalid_argument")
  expect_error(msgpack_decode(x, duplicate_keys = NA), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_decode("c0"), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_decode(hex_raw("93 01 02 03"), max_size = 3),
               class = "zumsgpack_size_limit")
})

test_that("limits apply to decoding as to validation", {
  expect_error(msgpack_decode(hex_raw("91 91 c0"), max_depth = 1L),
               class = "zumsgpack_depth_limit")
  expect_error(msgpack_decode(hex_raw("93 01 02 03"), max_items = 3),
               class = "zumsgpack_item_limit")
  e <- tryCatch(msgpack_decode(hex_raw("dd ff ff ff ff")), error = identity)
  expect_s3_class(e, "zumsgpack_parse_error")
  expect_identical(e$call[[1]], quote(msgpack_decode))
})

test_that("decoding is clean under gctorture", {
  skip_heavy()
  inputs <- c("93 01 a1 61 c3", "82 a1 61 92 01 c0 a1 62 81 01 02",
              "92 cf ff ff ff ff ff ff ff ff 01", "81 c4 01 00 d4 05 01",
              "93 c2 cb 3f f8 00 00 00 00 00 00 90")
  plain <- lapply(inputs, function(h) dec(h))
  gctorture(TRUE)
  tortured <- lapply(inputs, function(h) dec(h))
  failed <- tryCatch(dec("92 01 a1 00"), error = function(e) class(e)[1])
  gctorture(FALSE)
  expect_identical(tortured, plain)
  expect_identical(failed, "zumsgpack_unrepresentable")
})

test_that("failing and succeeding decodes interleave fifty times", {
  # zujson's memory-model check: a fault raised from the middle of a build
  # must leave nothing that breaks the next call.
  ok <- hex_raw("82 a1 61 92 01 02 a1 62 a3 61 62 63")
  bad <- hex_raw("82 a1 61 92 01 02 a1 62 a3 61 00 63")
  want <- list(a = 1:2, b = "abc")
  for (i in 1:50) {
    expect_error(msgpack_decode(bad), class = "zumsgpack_unrepresentable")
    expect_identical(msgpack_decode(ok), want)
  }
})
