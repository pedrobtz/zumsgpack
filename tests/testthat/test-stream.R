# msgpack_read_seq(each =): design section 10 and roadmap Stage 5.

stream_of <- function(bytes, chunk, each = function(v) NULL, ...) {
  con <- rawConnection(bytes)
  on.exit(close(con))
  args <- list(...)
  zmp_read_stream(con, each, max_size = args$max_size %||% (64 * 1024^2),
                  args[setdiff(names(args), "max_size")], call = NULL, chunk = chunk)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

collect <- function(bytes, chunk, ...) {
  out <- list()
  n <- stream_of(bytes, chunk, function(v) out[[length(out) + 1L]] <<- list(v), ...)
  list(n = n, values = lapply(out, `[[`, 1L))
}

test_that("every suite encoding, fed in blocks of 1, 2, 3 and 7 bytes, is itself", {
  s <- suite()
  bytes <- unlist(lapply(s$hex, hex_raw))
  whole <- msgpack_decode_seq(bytes)
  for (chunk in c(1L, 2L, 3L, 7L, 65536L)) {
    got <- collect(bytes, chunk)
    expect_identical(got$n, as.numeric(length(whole)), info = paste("chunk", chunk))
    expect_identical(got$values, whole, info = paste("chunk", chunk))
  }
})

test_that("every proper prefix of a suite encoding ends the stream inside an object", {
  s <- suite()
  for (h in s$hex[seq(1, nrow(s), by = 5)]) {
    b <- hex_raw(h)
    for (n in seq_len(length(b) - 1L)) {
      e <- tryCatch(stream_of(c(hex_raw("c0"), b[seq_len(n)]), 1L), error = identity)
      expect_s3_class(e, "zumsgpack_parse_error")
      expect_identical(e$offset, 1, info = h)
    }
  }
})

test_that("a malformed object stops the read with its offset in the stream", {
  bytes <- hex_raw("01 02 a1 61 c1 03")
  got <- list()
  e <- tryCatch(stream_of(bytes, 2L, function(v) got[[length(got) + 1L]] <<- v),
                error = identity)
  expect_s3_class(e, "zumsgpack_parse_error")
  expect_identical(e$status, "ZMP_ERR_RESERVED")
  expect_identical(e$offset, 4)
  expect_identical(got, list(1L, 2L, "a"))
  # Invalid, not malformed: the same.
  e <- tryCatch(stream_of(hex_raw("01 82 01 c0 01 c0"), 3L), error = identity)
  expect_s3_class(e, "zumsgpack_duplicate_key")
  expect_identical(e$offset, 4)
})

test_that("limits apply to each object, not the stream", {
  one <- msgpack_encode(1:9)                 # ten items
  bytes <- rep(one, 50)
  expect_identical(stream_of(bytes, 7L, max_items = 10), 50)
  expect_error(stream_of(bytes, 7L, max_items = 9), class = "zumsgpack_item_limit")
  expect_identical(stream_of(bytes, 7L, max_size = length(one)), 50)
  e <- expect_error(stream_of(c(one, msgpack_encode(1:20)), 7L, max_size = length(one)),
                    class = "zumsgpack_size_limit")
  expect_identical(e$offset, as.numeric(length(one)))
  expect_error(stream_of(hex_raw("91 91 c0"), 1L, max_depth = 1L), class = "zumsgpack_depth_limit")
})

test_that("a head claiming 4 GiB is refused at max_size, not read to the end", {
  con <- rawConnection(c(hex_raw("db ff ff ff ff"), as.raw(rep(0x61, 1e5))))
  on.exit(close(con))
  e <- expect_error(zmp_read_stream(con, function(v) NULL, max_size = 1000, list(), NULL),
                    class = "zumsgpack_size_limit")
  expect_identical(e$offset, 0)
})

test_that("msgpack_read_seq() reads paths and connections both ways", {
  path <- withr::local_tempfile(fileext = ".msgpack")
  writeBin(msgpack_encode_seq(list(1L, list(a = "x"), NULL)), path)
  expect_identical(msgpack_read_seq(path), list(1L, list(a = "x"), NULL))
  got <- list()
  n <- msgpack_read_seq(path, each = function(v) got[[length(got) + 1L]] <<- list(v))
  expect_identical(n, 3)
  expect_identical(lapply(got, `[[`, 1), list(1L, list(a = "x"), NULL))
  expect_invisible(msgpack_read_seq(path, each = identity))
  con <- file(path)
  expect_identical(msgpack_read_seq(con, map_keys = "map", each = identity), 3)
  expect_error(isOpen(con))
  expect_identical(msgpack_read_seq(withr::local_tempfile(), each = identity) |>
                     tryCatch(error = function(e) class(e)[1]), "zumsgpack_invalid_argument")
})

test_that("decoding options pass through to each object", {
  path <- withr::local_tempfile(fileext = ".msgpack")
  writeBin(hex_raw("d6 ff 00 00 00 01 81 01 02"), path)
  got <- list()
  msgpack_read_seq(path, ext = "keep", map_keys = "string",
                   each = function(v) got[[length(got) + 1L]] <<- v)
  expect_identical(got, list(msgpack_ext(-1, as.raw(c(0, 0, 0, 1))), list("1" = 2L)))
  expect_error(msgpack_read_seq(path, each = identity, simplify = "no"),
               class = "zumsgpack_invalid_argument")
  expect_error(msgpack_read_seq(path, each = 1), class = "zumsgpack_invalid_argument")
})

test_that("an error in each propagates unchanged", {
  path <- withr::local_tempfile(fileext = ".msgpack")
  writeBin(hex_raw("01 02 03"), path)
  e <- expect_error(msgpack_read_seq(path, each = function(v) if (v == 2L) stop("stop at 2")),
                    "stop at 2")
  expect_false(inherits(e, "zumsgpack_error"))
})

test_that("an empty stream reads nothing", {
  expect_identical(stream_of(raw(), 1L), 0)
  expect_identical(collect(raw(), 3L)$values, list())
})

test_that("a million objects are read in memory bounded by the largest", {
  skip_heavy()
  # 10^6 small maps from a connection: nothing accumulates, so the count
  # comes back without the stream ever being held as R values.
  one <- msgpack_encode(list(t = "x", v = 1L))
  bytes <- rep(one, 1e6)
  con <- rawConnection(bytes)
  on.exit(close(con))
  seen <- 0
  n <- zmp_read_stream(con, function(v) seen <<- seen + v$v, 64 * 1024^2, list(max_items = 5),
                       NULL)
  expect_identical(n, 1e6)
  expect_identical(seen, 1e6)
})

test_that("an interrupt during a stream read unwinds", {
  skip_heavy()
  # Long enough that no build finishes it inside the limit: a million
  # objects, each passed to an R function.
  one <- msgpack_encode(1:3)
  con <- rawConnection(rep(one, 1e6))
  on.exit(close(con))
  interrupted <- tryCatch({
    setTimeLimit(elapsed = 0.01, transient = TRUE)
    zmp_read_stream(con, function(v) NULL, 64 * 1024^2, list(), NULL)
    FALSE
  }, error = function(e) TRUE, finally = setTimeLimit())
  expect_true(interrupted)
  # The package still works.
  expect_identical(msgpack_decode(one), 1:3)
})
