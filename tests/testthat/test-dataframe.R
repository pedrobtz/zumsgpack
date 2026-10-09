# Data frames, design section 6.4 (decoding) and 7.1 (encoding).

records <- function(...) msgpack_encode(list(...))

test_that("an array of str-keyed maps becomes a data frame with data_frame = TRUE", {
  x <- records(list(a = 1L, b = "x"), list(b = "y", c = TRUE), list(a = 2.5))
  df <- msgpack_decode(x, data_frame = TRUE)
  expect_identical(df, data.frame(a = c(1, NA, 2.5), b = c("x", "y", NA), c = c(NA, TRUE, NA)))
  # Without the option, the same bytes are a list of named lists.
  expect_type(msgpack_decode(x), "list")
  expect_null(attr(msgpack_decode(x), "class"))
})

test_that("each column simplifies by the lattice, mixed kinds giving a list column", {
  x <- records(list(v = 1L), list(v = "a"), list(v = NULL))
  df <- msgpack_decode(x, data_frame = TRUE)
  expect_identical(df$v, list(1L, "a", NULL))
  x <- records(list(t = msgpack_ext(-1, as.raw(c(0, 0, 0, 1))), n = msgpack_bigint("18446744073709551615")),
               list(t = NULL, n = 1L))
  df <- msgpack_decode(x, data_frame = TRUE)
  expect_identical(df$t, utc(c(1, NA)))
  expect_identical(df$n, msgpack_bigint(c("18446744073709551615", "1")))
  expect_identical(msgpack_decode(x, data_frame = TRUE, simplify = "none")$n,
                   list(msgpack_bigint("18446744073709551615"), 1L))
})

test_that("arrays of any other shape decode as without the option", {
  for (x in list(records(list(a = 1L), 2L), records(list(a = 1L), list(1L)),
                 msgpack_encode(list()), msgpack_encode(1:3),
                 hex_raw("92 81 01 02 81 a1 61 01"),           # an int key
                 hex_raw("91 81 a0 01"))) {                     # an empty key
    expect_false(is.data.frame(msgpack_decode(x, data_frame = TRUE)), info = raw_hex(x))
  }
  # A key twice in one row is not a frame, with duplicate_keys = TRUE.
  x <- hex_raw("91 82 a1 61 01 a1 61 02")
  expect_false(is.data.frame(msgpack_decode(x, data_frame = TRUE, duplicate_keys = TRUE)))
})

test_that("frames nest, and empty rows give rows with no columns", {
  x <- records(list(id = 1L, items = list(list(k = "a"), list(k = "b"))))
  df <- msgpack_decode(x, data_frame = TRUE)
  expect_identical(df$items[[1]], data.frame(k = c("a", "b")))
  df <- msgpack_decode(hex_raw("92 80 80"), data_frame = TRUE)
  expect_identical(dim(df), c(2L, 0L))
})

test_that("the cell budget refuses a quadratic input before allocating", {
  # n rows that share no keys: n * n cells from about 8n bytes. 4000 rows
  # is 16 million cells, from 36 kB.
  wide <- function(n) msgpack_encode(lapply(seq_len(n), function(i)
    stats::setNames(list(1L), sprintf("k%05d", i))))
  x <- wide(4000L)
  expect_lt(length(x), 40000)
  e <- expect_error(msgpack_decode(x, data_frame = TRUE), class = "zumsgpack_cell_limit")
  expect_s3_class(e, "zumsgpack_limit_error")
  expect_identical(e$limit, "max_cells")
  expect_identical(e$limit_value, 1e7)
  expect_identical(e$offset, 0)
  n <- 50L
  expect_error(msgpack_decode(wide(n), data_frame = TRUE, max_cells = n * n - 1),
               class = "zumsgpack_cell_limit")
  expect_identical(dim(msgpack_decode(wide(n), data_frame = TRUE, max_cells = n * n)), c(n, n))
  expect_error(msgpack_decode(x, data_frame = TRUE, max_cells = 0),
               class = "zumsgpack_invalid_argument")
})

test_that("a data frame encodes as an array of maps, one per row", {
  df <- data.frame(n = c(2L, NA), s = c("a", "b"))
  expect_msgpack(df, "92 82 a1 6e 02 a1 73 a1 61 82 a1 6e c0 a1 73 a1 62")
  # Keys in the deterministic order, whatever the column order.
  expect_identical(msgpack_encode(df[c("s", "n")]), msgpack_encode(df))
  expect_msgpack(data.frame(), "90")
  expect_msgpack(data.frame(a = integer()), "90")
  expect_msgpack(data.frame(row.names = 1:2), "92 80 80")
})

test_that("data frame cells follow the ordinary mapping", {
  df <- data.frame(f = factor(c("lo", "hi")), t = utc(c(1, NA)), d = c(1.5, NaN))
  df$l <- list(1:2, NULL)
  b <- msgpack_encode(df)
  back <- msgpack_decode(b, data_frame = TRUE)
  expect_identical(back$f, c("lo", "hi"))
  expect_identical(back$t, utc(c(1, NA)))
  expect_identical(back$d, c(1.5, NaN))
  expect_identical(back$l, list(1:2, NULL))
})

test_that("data frames round-trip modulo the documented losses", {
  # Losses: row names, factor levels and column order (design section 7.2).
  df <- data.frame(a = c(1L, 2L), b = c("x", NA), c = c(TRUE, FALSE), row.names = c("r1", "r2"))
  back <- msgpack_decode(msgpack_encode(df), data_frame = TRUE)
  expect_identical(back, data.frame(a = 1:2, b = c("x", NA), c = c(TRUE, FALSE)))
  expect_identical(msgpack_encode(back), msgpack_encode(df))
})

test_that("data frames that cannot be encoded are refused", {
  df <- data.frame(a = 1:2)
  df$m <- matrix(1:4, 2)
  expect_error(msgpack_encode(df), class = "zumsgpack_unsupported_type")
  bad <- data.frame(a = 1, b = 2)
  names(bad) <- c("a", "a")
  expect_error(msgpack_encode(bad), class = "zumsgpack_duplicate_key")
  names(bad) <- c("a", "")
  expect_error(msgpack_encode(bad), class = "zumsgpack_invalid_argument")
})

test_that("a data frame charges depth as the decoder does", {
  df <- data.frame(a = 1L)
  expect_error(msgpack_encode(df, max_depth = 1), class = "zumsgpack_depth_limit")
  expect_identical(msgpack_encode(df, max_depth = 2), hex_raw("91 81 a1 61 01"))
  expect_true(msgpack_validate(hex_raw("91 81 a1 61 01"), max_depth = 2L))
})
