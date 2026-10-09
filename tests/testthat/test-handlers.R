test_that("a handler receives the payload and replaces the ext", {
  got <- dec("92 d4 05 61 c7 03 05 61 62 63", ext_handlers = list("5" = rawToChar))
  expect_identical(got, list("a", "abc"))
  # Other types are untouched.
  expect_identical(dec("d4 06 00", ext_handlers = list("5" = rawToChar)), msgpack_ext(6, raw(1)))
})

test_that("a handler for -1 replaces the timestamp conversion, whatever ext says", {
  h <- list("-1" = function(data) length(data))
  expect_identical(dec("d6 ff 00 00 00 01", ext_handlers = h), 4L)
  expect_identical(dec("d6 ff 00 00 00 01", ext_handlers = h, ext = "keep"), 4L)
})

test_that("a handler's result never joins an array's simplification", {
  h <- list("5" = function(data) 1L)
  expect_identical(dec("92 01 d4 05 00", ext_handlers = h), list(1L, 1L))
})

test_that("an error in a handler is zumsgpack_handler_error with type and parent", {
  h <- list("5" = function(data) stop("bad payload"))
  e <- expect_error(dec("91 d4 05 00", ext_handlers = h), class = "zumsgpack_handler_error")
  expect_s3_class(e, "zumsgpack_error")
  expect_identical(e$type, 5L)
  expect_identical(conditionMessage(e$parent), "bad payload")
  expect_identical(e$call[[1]], quote(msgpack_decode))
})

test_that("a handler never runs on input the check refuses", {
  ran <- FALSE
  h <- list("5" = function(data) { ran <<- TRUE; 1 })
  expect_error(dec("82 a1 61 d4 05 00 a1 61 c0", ext_handlers = h),
               class = "zumsgpack_duplicate_key")
  expect_false(ran)
  expect_error(dec("92 d4 05 00 c1", ext_handlers = h), class = "zumsgpack_parse_error")
  expect_false(ran)
})

test_that("a handler that decodes again sees its own limits", {
  inner <- msgpack_encode(list(1L, list(2L, list(3L))))
  outer <- msgpack_encode(msgpack_ext(9, inner))
  h <- list("9" = function(data) msgpack_decode(data, max_depth = 2L))
  expect_error(msgpack_decode(outer, ext_handlers = h), class = "zumsgpack_handler_error")
  h2 <- list("9" = function(data) msgpack_decode(data))
  expect_identical(msgpack_decode(outer, ext_handlers = h2, max_depth = 1L),
                   list(1L, list(2L, I(3L))))
})

test_that("a handler that returns something huge is fine", {
  h <- list("5" = function(data) seq_len(1e6))
  expect_length(dec("91 d4 05 00", ext_handlers = h)[[1]], 1e6)
})

test_that("ext_handlers is checked", {
  x <- hex_raw("c0")
  bad <- list(list(function(d) d), list("5" = 1), list("x" = identity),
              list("128" = identity), list("-129" = identity), list("05" = identity),
              list("+5" = identity), list("5" = identity, "5" = identity), "5",
              structure(list("5" = identity), class = "foo"))
  for (b in bad) expect_error(msgpack_decode(x, ext_handlers = b),
                              class = "zumsgpack_invalid_argument")
  expect_null(msgpack_decode(x, ext_handlers = list()))
  expect_null(msgpack_decode(x, ext_handlers = list("-128" = identity, "127" = identity, "0" = identity)))
})

test_that("as_msgpack() methods teach the encoder a class", {
  registerS3method("as_msgpack", "zmp_test_uuid", function(x, ...)
    msgpack_ext(37, unclass(x)), envir = asNamespace("zumsgpack"))
  u <- structure(as.raw(1:16), class = "zmp_test_uuid")
  expect_msgpack(u, paste("d8 25", raw_hex(as.raw(1:16))))
  expect_msgpack(list(id = u), paste("81 a2 69 64 d8 25", raw_hex(as.raw(1:16))))
  # The decoding half.
  back <- msgpack_decode(msgpack_encode(u), ext_handlers = list(
    "37" = function(data) structure(data, class = "zmp_test_uuid")))
  expect_identical(back, u)
})

test_that("a class without a method is encoded as its underlying type", {
  x <- structure(list(a = 1L), class = "zmp_no_method")
  expect_msgpack(x, "81 a1 61 01")
  expect_msgpack(I(1:2), "92 01 02")
})

test_that("a method's result is not converted again, but its elements are", {
  registerS3method("as_msgpack", "zmp_test_wrap", function(x, ...)
    list(inner = structure(1L, class = "zmp_test_leaf")), envir = asNamespace("zumsgpack"))
  registerS3method("as_msgpack", "zmp_test_leaf", function(x, ...) "leaf",
                   envir = asNamespace("zumsgpack"))
  expect_msgpack(structure(list(), class = "zmp_test_wrap"), "81 a5 69 6e 6e 65 72 a4 6c 65 61 66")
})

test_that("a method returning its own class is an error, and a method's error propagates", {
  registerS3method("as_msgpack", "zmp_test_same", function(x, ...)
    structure(unclass(x)[1], class = class(x)),
                   envir = asNamespace("zumsgpack"))
  expect_error(msgpack_encode(structure(1:2, class = "zmp_test_same")),
               class = "zumsgpack_unsupported_type")
  registerS3method("as_msgpack", "zmp_test_fails", function(x, ...) stop("no way"),
                   envir = asNamespace("zumsgpack"))
  e <- expect_error(msgpack_encode(list(structure(1, class = "zmp_test_fails"))), "no way")
  expect_false(inherits(e, "zumsgpack_error"))
})

test_that("a method on a map key runs exactly once", {
  n <- 0L
  registerS3method("as_msgpack", "zmp_test_count", function(x, ...) { n <<- n + 1L; 1L },
                   envir = asNamespace("zumsgpack"))
  m <- msgpack_map(list(structure(0, class = "zmp_test_count")), list("v"))
  expect_msgpack(m, "81 01 a1 76")
  expect_identical(n, 1L)
})

test_that("the second cross-platform fixture is byte-identical", {
  registerS3method("as_msgpack", "zmp_test_point", function(x, ...)
    msgpack_ext(7, as.raw(c(unclass(x)$a, 2L))), envir = asNamespace("zumsgpack"))
  want <- readLines(test_path("fixtures", "encode-stage4.hex"))
  expect_identical(raw_hex(msgpack_encode(mixed_value_4())), paste(want, collapse = " "))
  # Stage 3's fixture is unchanged (test-encode.R checks its bytes).
})

test_that("an interrupt while handlers run unwinds, and the input then decodes", {
  skip_heavy()
  n <- 1e5
  x <- c(hex_raw("dd"), as.raw(c(n %/% 16777216, (n %/% 65536) %% 256, (n %/% 256) %% 256, n %% 256)),
         rep(hex_raw("d4 05 01"), n))
  h <- list("5" = function(data) as.integer(data) + 1L)
  interrupted <- tryCatch({
    setTimeLimit(elapsed = 0.01, transient = TRUE)
    msgpack_decode(x, max_items = Inf, ext_handlers = h)
    FALSE
  }, error = function(e) TRUE, finally = setTimeLimit())
  expect_true(interrupted)
  v <- msgpack_decode(x, max_items = Inf, ext_handlers = h)
  expect_length(v, n)
  expect_identical(v[[n]], 2L)
})
