# Fixtures written by another implementation, Python's msgpack at a pinned
# version (tools/make-fixtures.py), each with Python's own decoding of it.

test_that("every object Python wrote decodes to the value Python read back", {
  p <- python_fixtures()
  p <- p[p$name != "fluentd forward stream", ]
  expect_gt(nrow(p), 80L)
  got <- vapply(p$hex, function(h) canon_decode(hex_raw(h)), "")
  bad <- which(got != p$canon)
  expect(length(bad) == 0L, paste("differ:", paste(p$name[bad], collapse = "; ")))
})

test_that("every object Python wrote validates and, in section 8 form, re-encodes exactly", {
  p <- python_fixtures()
  p <- p[p$name != "fluentd forward stream", ]
  expect_true(all(vapply(p$hex, function(h) msgpack_validate(hex_raw(h)), NA)))
  # Python writes the smallest integer forms and float 64 too, so most of
  # its output is already in zumsgpack's form. Each exception has a stated
  # cause (design sections 7.2 and 8): float 32 re-encodes as float 64; a
  # whole float is an integer; a map's keys are sorted; and a timestamp's
  # nanoseconds survive a double only near the epoch.
  same <- vapply(p$hex, function(h) {
    b <- hex_raw(h)
    identical(msgpack_encode(msgpack_decode(b)), b)
  }, NA)
  expected <- c(
    grep("^float32 ", p$name, value = TRUE),          # float 32 -> float 64
    "float64 0.0",                                    # whole float -> integer
    "map int keys", "map mixed keys", "records",      # keys sorted
    "timestamp 1514862245 678901234",                 # nanoseconds beyond a double
    "timestamp 17179869183 999999999",
    "timestamp 253402300799 999999999")
  expect_setequal(p$name[!same], expected)
})

test_that("the Fluentd forward stream reads object by object", {
  p <- python_fixtures()
  row <- p[p$name == "fluentd forward stream", ]
  bytes <- hex_raw(row$hex)
  objs <- msgpack_decode_seq(bytes, simplify = "none", map_keys = "map", ext = "keep")
  expect_identical(paste(vapply(objs, canon, ""), collapse = ";"), row$canon)
  # The way a caller would: EventTime (ext 0) through a handler, records as
  # named lists, one message at a time.
  event_time <- function(d) structure(sum(as.numeric(d[1:4]) * 256^(3:0)) +
                                        sum(as.numeric(d[5:8]) * 256^(3:0)) / 1e9,
                                      class = c("POSIXct", "POSIXt"), tzone = "UTC")
  con <- rawConnection(bytes)
  on.exit(close(con))
  tags <- character()
  n <- msgpack_read_seq(con, ext_handlers = list("0" = event_time),
                        each = function(m) tags <<- c(tags, m[[1]]))
  expect_identical(n, 2)
  expect_identical(tags, c("app.access", "app.error"))
})

test_that("an array of records becomes a data frame", {
  p <- python_fixtures()
  df <- msgpack_decode(hex_raw(p$hex[p$name == "records"]), data_frame = TRUE)
  expect_s3_class(df, "data.frame")
  expect_identical(names(df), c("id", "name", "score", "tags"))
  expect_identical(df$id, 1:3)
  expect_identical(df$name, c("a", "b", NA))
  expect_identical(df$score, c(1.5, NA, NA))
  expect_identical(df$tags, list(NULL, NULL, c("x", "y")))
})

test_that("the suite's decodings agree with the canonical form of its values", {
  # A cross-check of the canonical writer itself, on the other corpus.
  s <- suite()
  s <- s[s$type %in% c("nil", "bool", "string", "binary"), ]
  for (i in seq_len(nrow(s))) {
    v <- eval(str2lang(s$value[i]))
    want <- switch(s$type[i], binary = canon(hex_raw(v)), canon(v))
    expect_identical(canon_decode(hex_raw(s$hex[i])), want, info = s$hex[i])
  }
})
