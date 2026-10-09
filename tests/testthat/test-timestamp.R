# The timestamp extension, design sections 6.1, 7.1 and 8 rule 5.

ts_value <- function(sec, nsec) utc(sec + nsec / 1e9)

test_that("every suite timestamp decodes to its instant, in UTC", {
  s <- suite()
  s <- s[s$type == "timestamp", ]
  expect_gt(nrow(s), 15L)
  for (i in seq_len(nrow(s))) {
    v <- eval(str2lang(s$value[i]))
    got <- msgpack_decode(hex_raw(s$hex[i]))
    expect_identical(got, ts_value(as.numeric(v[[1]]), as.numeric(v[[2]])), info = s$hex[i])
  }
})

test_that("ext = \"keep\" leaves a timestamp as msgpack_ext", {
  expect_identical(dec("d6 ff 00 00 00 01", ext = "keep"), msgpack_ext(-1, as.raw(c(0, 0, 0, 1))))
  # ... and other exts are msgpack_ext either way.
  expect_identical(dec("d4 05 00"), msgpack_ext(5, raw(1)))
})

test_that("timestamps in an array simplify to POSIXct", {
  x <- dec("93 d6 ff 00 00 00 01 c0 d6 ff 00 00 00 02")
  expect_identical(x, utc(c(1, NA, 2)))
  expect_identical(dec("91 d6 ff 00 00 00 01"), I(utc(1)))
  expect_identical(dec("92 d6 ff 00 00 00 01 01"), list(utc(1), 1L))
})

test_that("POSIXct encodes as the smallest timestamp that holds it", {
  expect_msgpack(utc(0), "d6 ff 00 00 00 00")
  expect_msgpack(utc(2^32 - 1), "d6 ff ff ff ff ff")
  expect_msgpack(utc(2^32), "d7 ff 00 00 00 01 00 00 00 00")
  expect_msgpack(utc(0.25), "d7 ff 3b 9a ca 00 00 00 00 00")
  expect_msgpack(utc(2^34 - 1), "d7 ff 00 00 00 03 ff ff ff ff")
  expect_msgpack(utc(2^34), "c7 0c ff 00 00 00 00 00 00 00 04 00 00 00 00")
  expect_msgpack(utc(-1), "c7 0c ff 00 00 00 00 ff ff ff ff ff ff ff ff")
  # Before 1970: seconds floor, nanoseconds are never negative.
  expect_msgpack(utc(-1.5), "c7 0c ff 1d cd 65 00 ff ff ff ff ff ff ff fe")
  expect_msgpack(utc(NA_real_), "c0")
  expect_msgpack(utc(c(0, NA)), "92 d6 ff 00 00 00 00 c0")
  # Integer-typed POSIXct, as some packages make.
  expect_msgpack(structure(1L, class = c("POSIXct", "POSIXt")), "d6 ff 00 00 00 01")
})

test_that("nanoseconds round to the nearest and carry at a second", {
  # 1 - 2^-40 is within half a nanosecond of 1: it is the whole second 1.
  expect_msgpack(utc(1 - 2^-40), "d6 ff 00 00 00 01")
  # 2^-31 s is 0.4656... ns: rounds to 0.
  expect_msgpack(utc(2^-31), "d6 ff 00 00 00 00")
  expect_msgpack(utc(2^-29), "d7 ff 00 00 00 08 00 00 00 00")     # 1.86 ns -> 2
})

test_that("Date is a timestamp at midnight UTC and reads back as POSIXct", {
  expect_msgpack(as.Date("1970-01-02"), "d6 ff 00 01 51 80")      # 86400 s
  expect_msgpack(as.Date(NA), "c0")
  expect_identical(msgpack_decode(msgpack_encode(as.Date("2024-02-29"))),
                   utc(as.numeric(as.Date("2024-02-29")) * 86400))
  expect_msgpack(as.Date("1900-01-01"), "c7 0c ff 00 00 00 00 ff ff ff ff 7c 55 81 80")
})

test_that("an instant beyond 64-bit seconds is unrepresentable", {
  for (v in c(Inf, -Inf, 2^63, -2^63 - 2^11)) {
    e <- expect_error(msgpack_encode(utc(v)), class = "zumsgpack_unrepresentable")
    expect_identical(e$status, "ZMP_ERR_UNREPRESENTABLE")
  }
  expect_msgpack(utc(-2^63), "c7 0c ff 00 00 00 00 80 00 00 00 00 00 00 00")
})

test_that("a timestamp is one level of depth, as on decode", {
  expect_error(msgpack_encode(list(utc(1)), max_depth = 1), class = "zumsgpack_depth_limit")
  expect_identical(msgpack_encode(list(utc(1)), max_depth = 2), hex_raw("91 d6 ff 00 00 00 01"))
  expect_identical(msgpack_encode(utc(1), max_depth = 1), hex_raw("d6 ff 00 00 00 01"))
})

test_that("suite timestamps whose instant a double holds are fixed points", {
  # Nanoseconds survive a double only where the seconds are small enough;
  # the rest is the documented loss of design section 7.2.
  s <- suite()
  s <- s[s$type == "timestamp", ]
  fixed <- vapply(seq_len(nrow(s)), function(i) {
    b <- hex_raw(s$hex[i])
    identical(msgpack_encode(msgpack_decode(b)), b)
  }, logical(1))
  v <- lapply(s$value, function(t) eval(str2lang(t)))
  whole <- vapply(v, function(t) t[[2]] == 0, logical(1))
  expect_true(all(fixed[whole]), info = paste(s$hex[whole & !fixed], collapse = "; "))
  # Of the cases with nanoseconds, those near the epoch survive too.
  small <- vapply(v, function(t) abs(as.numeric(t[[1]])) < 2^20, logical(1))
  expect_true(all(fixed[small]), info = paste(s$hex[small & !fixed], collapse = "; "))
})

test_that("a \"-1\" handler keeps nanoseconds exactly", {
  fields <- function(data) {
    if (length(data) == 12L) {
      c(sec = sum(as.numeric(data[5:12]) * 256^(7:0)) - if (data[5] >= 0x80) 2^64 else 0,
        nsec = sum(as.numeric(data[1:4]) * 256^(3:0)))
    } else if (length(data) == 8L) {
      hi <- sum(as.numeric(data[1:4]) * 256^(3:0))
      lo <- sum(as.numeric(data[5:8]) * 256^(3:0))
      c(sec = (hi %% 4) * 2^32 + lo, nsec = hi %/% 4)
    } else c(sec = sum(as.numeric(data) * 256^(3:0)), nsec = 0)
  }
  got <- dec("d7 ff a1 dc d7 c8 5a 4a f6 a5", ext_handlers = list("-1" = fields))
  expect_identical(got, c(sec = 1514862245, nsec = 678901234))
})
