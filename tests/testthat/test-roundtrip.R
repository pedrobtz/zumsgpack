test_that("every suite encoding in section 8 form is a fixed point", {
  # For each case, the encoding of the decoded value is one of the case's
  # listed encodings, and decoding that again gives the same value. Floats
  # are the exception the design states: a float 32 input re-encodes as
  # float 64 (section 7.2), and a whole float as an integer.
  s <- suite()
  s <- s[s$type != "timestamp", ]                # test-timestamp.R
  cases <- split(s, paste(s$group, s$case))
  missing <- character()
  for (cs in cases) {
    first <- hex_raw(cs$hex[1])
    v <- msgpack_decode(first)
    e <- raw_hex(msgpack_encode(v))
    if (!e %in% vapply(cs$hex, function(h) raw_hex(hex_raw(h)), "")) {
      if (!cs$type[1] %in% c("number", "bignum")) missing <- c(missing, cs$hex[1])
      next
    }
    expect_identical(msgpack_encode(msgpack_decode(hex_raw(e))), hex_raw(e))
  }
  expect_identical(missing, character())
})

test_that("encoding then decoding gives the value back", {
  values <- list(
    1:3, c(1.5, NaN, Inf, -Inf), c("a", NA, "水"), c(TRUE, NA), as.raw(0:255),
    list(a = 1L, b = list(c = "x", d = logical())), list(1L, "a", NULL, I(TRUE)),
    msgpack_bigint(c("18446744073709551615", "-9007199254740993")),
    msgpack_map(list(1L, "k"), list(-7L, as.raw(1:3))), msgpack_ext(6, as.raw(1)),
    structure(list(), names = character()), logical(), I(2.5), c(2^31, 1)
  )
  for (v in values) {
    expect_identical(msgpack_decode(msgpack_encode(v)), v, info = paste(deparse(v), collapse = ""))
  }
  expect_identical(1 / msgpack_decode(msgpack_encode(neg_zero())), -Inf)
})

test_that("R values that do not survive R -> MessagePack -> R are the documented ones", {
  # design section 7.2
  expect_identical(msgpack_decode(msgpack_encode(list(1L))), I(1L))      # list(1L) -> [1]
  expect_identical(msgpack_decode(msgpack_encode(list())), logical())    # list() -> []
  expect_identical(msgpack_decode(msgpack_encode(2)), 2L)                # whole double
  expect_identical(msgpack_decode(msgpack_encode(NA_real_)), NULL)       # typed NA
  expect_identical(msgpack_decode(msgpack_encode(factor("a"))), "a")     # factor
})

test_that("every encoding is repeatable and a fixed point of decode -> encode", {
  set.seed(5005)
  gen <- function(depth) {
    k <- sample.int(if (depth > 3) 6 else 10, 1)
    switch(k,
      sample.int(1e6, 1) - 5e5,
      stats::runif(1) * 10^sample(-5:5, 1),
      paste(sample(letters, sample.int(5, 1)), collapse = ""),
      sample(c(TRUE, FALSE, NA), 1),
      as.raw(sample.int(256, sample.int(5, 1)) - 1L),
      NULL,
      lapply(seq_len(sample.int(4, 1)), function(i) gen(depth + 1)),
      stats::setNames(lapply(1:3, function(i) gen(depth + 1)), sample(letters, 3)),
      msgpack_map(list(sample.int(100, 1), paste0("k", sample.int(100, 1))),
                  list(gen(depth + 1), gen(depth + 1))),
      msgpack_ext(sample(-128:127, 1), as.raw(sample.int(256, sample(0:20, 1), TRUE) - 1L))
    )
  }
  ok <- vapply(1:300, function(i) {
    v <- gen(0)
    a <- msgpack_encode(v)
    identical(msgpack_encode(v), a) &&                     # repeatable
      msgpack_validate(a) &&                               # valid
      identical(msgpack_encode(msgpack_decode(a)), a)      # decode -> encode is a fixed point
  }, NA)
  expect_true(all(ok), info = paste(which(!ok), collapse = " "))
})

test_that("floats = \"shortest\" output is a fixed point with the same option", {
  set.seed(7)
  x <- c(0.5, 0.1, 1e-10, 3.4e38, f32("3dcccccd"), NaN, Inf)
  for (v in x) {
    b <- msgpack_encode(v, floats = "shortest")
    expect_identical(msgpack_encode(msgpack_decode(b), floats = "shortest"), b)
  }
})
