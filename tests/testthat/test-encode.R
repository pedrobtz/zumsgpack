# One test per row of design section 7.1, then the rules of section 8.

test_that("NULL and NA of every type are nil", {
  expect_msgpack(NULL, "c0")
  expect_msgpack(NA, "c0")
  expect_msgpack(NA_integer_, "c0")
  expect_msgpack(NA_real_, "c0")
  expect_msgpack(NA_character_, "c0")
  expect_msgpack(c(1L, NA), "92 01 c0")
  expect_msgpack(c(1.5, NA), "92 cb 3f f8 00 00 00 00 00 00 c0")
})

test_that("logicals are true and false", {
  expect_msgpack(TRUE, "c3")
  expect_msgpack(FALSE, "c2")
  expect_msgpack(c(TRUE, FALSE, NA), "93 c3 c2 c0")
})

test_that("integers take the smallest form", {
  cases <- list(
    list(0L, "00"), list(127L, "7f"), list(128L, "cc 80"), list(255L, "cc ff"),
    list(256L, "cd 01 00"), list(65535L, "cd ff ff"), list(65536L, "ce 00 01 00 00"),
    list(.Machine$integer.max, "ce 7f ff ff ff"),
    list(-1L, "ff"), list(-32L, "e0"), list(-33L, "d0 df"), list(-128L, "d0 80"),
    list(-129L, "d1 ff 7f"), list(-32768L, "d1 80 00"), list(-32769L, "d2 ff ff 7f ff"),
    list(-.Machine$integer.max, "d2 80 00 00 01"))
  for (c in cases) expect_msgpack(c[[1]], c[[2]])
})

test_that("whole doubles in range are integers, in the smallest form", {
  expect_msgpack(1, "01")
  expect_msgpack(-7, "f9")
  expect_msgpack(2^31, "ce 80 00 00 00")
  expect_msgpack(2^32, "cf 00 00 00 01 00 00 00 00")
  expect_msgpack(-2^31 - 1, "d3 ff ff ff ff 7f ff ff ff")
  expect_msgpack(-2^63, "d3 80 00 00 00 00 00 00 00")
  expect_msgpack(2^64 - 2048, "cf ff ff ff ff ff ff f8 00")
  # Outside -2^63 .. 2^64 - 1, and -0: floats.
  expect_msgpack(2^64, "cb 43 f0 00 00 00 00 00 00")
  expect_msgpack(-2^63 - 2048, "cb c3 e0 00 00 00 00 00 01")
  expect_msgpack(neg_zero(), "cb 80 00 00 00 00 00 00 00")
  expect_identical(msgpack_encode(1L), msgpack_encode(1))
})

test_that("other doubles are float 64, NaN canonical", {
  expect_msgpack(1.5, "cb 3f f8 00 00 00 00 00 00")
  expect_msgpack(Inf, "cb 7f f0 00 00 00 00 00 00")
  expect_msgpack(-Inf, "cb ff f0 00 00 00 00 00 00")
  expect_msgpack(NaN, "cb 7f f8 00 00 00 00 00 00")
  # A NaN with the sign bit and a payload, as x86 makes 0/0: still canonical.
  odd_nan <- f64("fff8000000001234")
  expect_true(is.nan(odd_nan))
  expect_msgpack(odd_nan, "cb 7f f8 00 00 00 00 00 00")
})

test_that("floats = \"shortest\" writes float 32 when it is exact", {
  expect_msgpack(0.5, "ca 3f 00 00 00", floats = "shortest")
  expect_msgpack(Inf, "ca 7f 80 00 00", floats = "shortest")
  expect_msgpack(NaN, "ca 7f c0 00 00", floats = "shortest")
  expect_msgpack(f32("3dcccccd"), "ca 3d cc cc cd", floats = "shortest")
  expect_msgpack(f64("3fb999999999999a"), "cb 3f b9 99 99 99 99 99 9a", floats = "shortest")
  expect_msgpack(f64("7e37e43c8800759c"), "cb 7e 37 e4 3c 88 00 75 9c", floats = "shortest")
  # Whole doubles are integers either way.
  expect_msgpack(2, "02", floats = "shortest")
})

test_that("character is str with the smallest head, UTF-8", {
  expect_msgpack("", "a0")
  expect_msgpack("a", "a1 61")
  expect_msgpack(strrep("x", 31), paste("bf", strrep("78", 31)))
  expect_msgpack(strrep("x", 32), paste("d9 20", strrep("78", 32)))
  expect_msgpack(strrep("x", 256), paste("da 01 00", strrep("78", 256)))
  expect_msgpack(strrep("x", 65536), paste("db 00 01 00 00", strrep("78", 65536)))
  expect_msgpack("€", "a3 e2 82 ac")
  latin1 <- iconv("é", "UTF-8", "latin1")
  expect_identical(Encoding(latin1), "latin1")
  expect_msgpack(latin1, "a2 c3 a9")
  bytes <- "\xff"
  Encoding(bytes) <- "bytes"
  expect_error(msgpack_encode(bytes), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_encode(stats::setNames(list(1), bytes)), class = "zumsgpack_invalid_argument")
})

test_that("raw is one bin with the smallest head", {
  expect_msgpack(raw(), "c4 00")
  expect_msgpack(as.raw(1), "c4 01 01")
  expect_msgpack(as.raw(0:255), paste("c5 01 00", raw_hex(as.raw(0:255))))
  big <- as.raw(rep(7, 65536))
  expect_identical(msgpack_encode(big)[1:5], hex_raw("c6 00 01 00 00"))
  expect_msgpack(list(as.raw(1), as.raw(2)), "92 c4 01 01 c4 01 02")
})

test_that("factors are their labels", {
  expect_msgpack(factor(c("b", "a", NA)), "93 a1 62 a1 61 c0")
  expect_msgpack(factor("a"), "a1 61")
})

test_that("msgpack_bigint is an integer within 64 bits, refused beyond", {
  expect_msgpack(msgpack_bigint("18446744073709551615"), "cf ff ff ff ff ff ff ff ff")
  expect_msgpack(msgpack_bigint("-9223372036854775808"), "d3 80 00 00 00 00 00 00 00")
  expect_msgpack(msgpack_bigint("5"), "05")
  expect_msgpack(msgpack_bigint(c("-1", NA)), "92 ff c0")
  for (b in c("18446744073709551616", "-9223372036854775809", strrep("9", 40))) {
    e <- expect_error(msgpack_encode(msgpack_bigint(b)), class = "zumsgpack_unrepresentable")
    expect_identical(e$status, "ZMP_ERR_UNREPRESENTABLE")
  }
})

test_that("msgpack_ext is fixext or the smallest ext", {
  expect_msgpack(msgpack_ext(1, as.raw(9)), "d4 01 09")
  expect_msgpack(msgpack_ext(1, raw(2)), "d5 01 00 00")
  expect_msgpack(msgpack_ext(1, raw(4)), "d6 01 00 00 00 00")
  expect_msgpack(msgpack_ext(1, raw(8)), paste("d7 01", strrep("00", 8)))
  expect_msgpack(msgpack_ext(1, raw(16)), paste("d8 01", strrep("00", 16)))
  expect_msgpack(msgpack_ext(-2, raw()), "c7 00 fe")
  expect_msgpack(msgpack_ext(1, raw(3)), "c7 03 01 00 00 00")
  expect_msgpack(msgpack_ext(-128, raw(17)), paste("c7 11 80", strrep("00", 17)))
  expect_identical(msgpack_encode(msgpack_ext(1, raw(256)))[1:4], hex_raw("c8 01 00 01"))
  expect_identical(msgpack_encode(msgpack_ext(1, raw(65536)))[1:6], hex_raw("c9 00 01 00 00 01"))
})

test_that("unnamed lists and vectors are arrays, with the smallest head", {
  expect_msgpack(list(), "90")
  expect_msgpack(logical(), "90")
  expect_msgpack(1:3, "93 01 02 03")
  expect_msgpack(list(1L, "a", NULL), "93 01 a1 61 c0")
  expect_msgpack(as.list(1:15), paste("9f", raw_hex(as.raw(1:15))))
  expect_msgpack(as.list(1:16), paste("dc 00 10", raw_hex(as.raw(1:16))))
  expect_identical(msgpack_encode(rep(0L, 65536))[1:5], hex_raw("dd 00 01 00 00"))
  # A matrix is a flat array in column-major order.
  expect_msgpack(matrix(1:4, 2), "94 01 02 03 04")
})

test_that("length-one vectors are scalars unless I() or auto_unbox = FALSE", {
  expect_msgpack(1L, "01")
  expect_msgpack(I(1L), "91 01")
  expect_msgpack(1L, "91 01", auto_unbox = FALSE)
  expect_msgpack(list(1L), "91 01")
})

test_that("fully named lists and vectors are maps with sorted str keys", {
  expect_msgpack(list(b = 1L, a = 2L), "82 a1 61 02 a1 62 01")
  expect_msgpack(c(b = 1L, a = 2L), "82 a1 61 02 a1 62 01")
  # Shorter str keys sort first: their heads are smaller.
  expect_msgpack(list(aa = 1L, b = 2L), "82 a1 62 02 a2 61 61 01")
  key32 <- strrep("k", 32)
  x <- stats::setNames(list(1L, 2L), c(key32, "z"))
  expect_msgpack(x, paste("82 a1 7a 02 d9 20", strrep("6b", 32), "01"))
  expect_msgpack(structure(list(), names = character()), "80")
  expect_identical(msgpack_encode(stats::setNames(as.list(1:16), letters[1:16]))[1:3],
                   hex_raw("de 00 10"))
})

test_that("names that cannot be keys are refused", {
  expect_error(msgpack_encode(list(a = 1, 2)), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_encode(stats::setNames(list(1, 2), c("a", NA))),
               class = "zumsgpack_invalid_argument")
  e <- expect_error(msgpack_encode(list(a = 1, a = 2)), class = "zumsgpack_duplicate_key")
  expect_identical(e$status, "ZMP_ERR_DUPLICATE_KEY")
})

test_that("msgpack_map keys are sorted by their encoded bytes", {
  m <- msgpack_map(list("a", 1L, -1L, as.raw(0), list(1L)), list(1L, 2L, 3L, 4L, 5L))
  # 01 < 91 01 < a1 61 < c4 01 00 < ff
  expect_msgpack(m, "85 01 02 91 01 05 a1 61 01 c4 01 00 04 ff 03")
  expect_error(msgpack_encode(msgpack_map(list(1L, 1), list(1, 2))),
               class = "zumsgpack_duplicate_key")
  expect_msgpack(msgpack_map(), "80")
})

test_that("map order is the same whatever order the entries come in", {
  set.seed(1)
  keys <- c(letters, paste0(letters, letters), strrep("q", 40))
  for (i in 1:20) {
    k <- sample(keys)
    x <- stats::setNames(as.list(seq_along(k)), k)
    expect_identical(msgpack_encode(x),
                     msgpack_encode(x[order(nchar(names(x)), names(x))]))
  }
})

test_that("values with no MessagePack form are refused", {
  bad <- list(1i, function(x) x, globalenv(), as.POSIXlt("2026-01-01", tz = "UTC"),
              quote(a + b), as.name("a"))
  for (b in bad) expect_error(msgpack_encode(b), class = "zumsgpack_unsupported_type")
  expect_error(msgpack_encode(list(a = list(b = 1i))), class = "zumsgpack_unsupported_type")
})

test_that("POSIXct, Date and data frames are refused until their stages", {
  expect_error(msgpack_encode(Sys.time()), class = "zumsgpack_unsupported_type")
  expect_error(msgpack_encode(as.Date("2026-01-01")), class = "zumsgpack_unsupported_type")
  expect_error(msgpack_encode(data.frame(a = 1)), class = "zumsgpack_unsupported_type")
})

test_that("the encoder never writes what the decoder refuses at the same max_depth", {
  leaves <- list(1L, msgpack_ext(5, raw(1)), list(1L), c(a = 1L), msgpack_map(list(1L), list(2L)),
                 msgpack_ext(5, raw(20)))
  wrap <- function(x, n) {
    for (i in seq_len(n)) x <- list(x)
    x
  }
  for (leaf in leaves) for (n in 0:4) {
    x <- wrap(leaf, n)
    bytes <- tryCatch(msgpack_encode(x, max_depth = 4), zumsgpack_depth_limit = function(e) NULL)
    decodable <- msgpack_validate(msgpack_encode(x, max_depth = 20), max_depth = 4)
    expect_identical(!is.null(bytes), decodable, info = paste(n, class(leaf)[1]))
  }
  e <- expect_error(msgpack_encode(wrap(1L, 3), max_depth = 2), class = "zumsgpack_depth_limit")
  expect_identical(e$limit, "max_depth")
  expect_identical(e$limit_value, 2)
  expect_error(msgpack_encode(1, max_depth = 0), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_encode(1, max_depth = 1024), class = "zumsgpack_invalid_argument")
})

test_that("msgpack_encode_seq() writes one object per element", {
  expect_msgpack_seq <- function(x, hex) expect_identical(msgpack_encode_seq(x), hex_raw(hex))
  expect_msgpack_seq(list(1L, "a", TRUE), "01 a1 61 c3")
  expect_msgpack_seq(list(), "")
  expect_error(msgpack_encode_seq(1:3), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_encode_seq(msgpack_map()), class = "zumsgpack_invalid_argument")
})

test_that("arguments are checked", {
  expect_error(msgpack_encode(1, auto_unbox = NA), class = "zumsgpack_invalid_argument")
  expect_error(msgpack_encode(1, floats = "half"), class = "zumsgpack_invalid_argument")
})

test_that("an error deep in a map leaves no buffer behind and the next call works", {
  # The output and every key buffer are owned by external pointers, so the
  # longjmp of the error frees them at the next collection; ASan checks it
  # in the sanitizer job, and gctorture here.
  bad <- msgpack_map(list(list(1L, 2L), "b"), list(1L, list(x = 1i)))
  for (i in 1:20) {
    expect_error(msgpack_encode(bad), class = "zumsgpack_unsupported_type")
    expect_identical(msgpack_encode(list(a = 1L)), hex_raw("81 a1 61 01"))
  }
})

test_that("the cross-platform fixture is byte-identical", {
  # A checked-in encoding of mixed_value(), which exercises every encoder
  # path of Stage 3. Every CI platform must produce exactly these bytes:
  # determinism across machines, not only across calls.
  want <- readLines(test_path("fixtures", "encode-stage3.hex"))
  got <- raw_hex(msgpack_encode(mixed_value()))
  expect_identical(got, paste(want, collapse = " "))
  expect_identical(msgpack_encode(mixed_value()), msgpack_encode(mixed_value()))
})
