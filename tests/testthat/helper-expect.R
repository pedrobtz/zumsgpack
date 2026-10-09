# Helpers shared by the test files. They live here, not at the top of a
# test file, because testthat's shuffle = TRUE reorders a file's top-level
# expressions, definitions included (zucbor Stage 2).

# Bytes from hex, ignoring spaces and dashes; several pieces are joined.
hex_raw <- function(...) {
  s <- gsub("[^0-9a-fA-F]", "", paste(c(...), collapse = ""))
  if (!nzchar(s)) return(raw())
  as.raw(strtoi(substring(s, seq(1L, nchar(s), 2L), seq(2L, nchar(s), 2L)), 16L))
}

raw_hex <- function(x) paste(sprintf("%02x", as.integer(x)), collapse = " ")

# The class a check of x raises, its first class only, or "ok". Bulk checks
# compute every outcome and assert once, naming the failing inputs: thousands
# of expect_error() calls made zucbor's suite take 20 s.
fault_class <- function(x, ...) {
  tryCatch({
    msgpack_validate(x, ..., error = TRUE)
    "ok"
  }, zumsgpack_error = function(e) class(e)[1L])
}

fault_of <- function(x, ...) {
  tryCatch({
    msgpack_validate(x, ..., error = TRUE)
    NULL
  }, zumsgpack_error = function(e) e)
}

expect_all_class <- function(inputs, class, ..., label = "input") {
  got <- vapply(inputs, fault_class, character(1), ...)
  bad <- which(got != class)
  expect(length(bad) == 0L, sprintf(
    "%d of %d %ss were not %s; first: %s gave %s", length(bad), length(got),
    label, class, if (length(bad)) raw_hex(inputs[[bad[1L]]]) else "",
    if (length(bad)) got[[bad[1L]]] else ""))
}

dup_error <- function(hex, ...) {
  expect_error(msgpack_validate(hex_raw(hex), error = TRUE, ...),
               class = "zumsgpack_duplicate_key", info = hex)
}

valid <- function(hex, ...) {
  expect_true(msgpack_validate(hex_raw(hex), ...), info = hex)
}

# kawanet/msgpack-test-suite, as tools/update-fixtures wrote it: one row per
# encoding of each case, `value` as R source text.
suite <- function() {
  utils::read.delim(test_path("fixtures", "msgpack-test-suite.tsv"),
                    colClasses = "character", quote = "", encoding = "UTF-8")
}

# Skips a test that allocates millions of R objects. It checks a limit or a
# code path, not memory safety, and under gctorture it would take hours;
# native-checks.yaml sets ZUMSGPACK_SKIP_HEAVY for the gctorture job.
skip_heavy <- function() {
  skip_if(nzchar(Sys.getenv("ZUMSGPACK_SKIP_HEAVY")), "ZUMSGPACK_SKIP_HEAVY is set")
}

# A double from its IEEE 754 bits, big-endian hex. R's parser does not round
# every decimal literal correctly where long double is only a double (macOS
# arm64, zucbor Stage 3), so a float a test compares exactly is built from
# its bits, or from arithmetic that is exact.
f64 <- function(hex) readBin(hex_raw(hex), "double", size = 8L, endian = "big")
f32 <- function(hex) readBin(hex_raw(hex), "double", size = 4L, endian = "big")

# R's byte-code compiler folds the literal -0 to +0 (zucbor Stage 4), so a
# test that needs negative zero makes it at run time.
neg_zero <- function() {
  z <- 0
  -z
}

dec <- function(hex, ...) msgpack_decode(hex_raw(hex), ...)

# A decoded value with every I() mark removed, recursively, for comparing
# structure where the one-element marking is beside the point.
un_i <- function(x) {
  if (inherits(x, "AsIs")) class(x) <- setdiff(class(x), "AsIs")
  if (length(class(x)) == 0L || identical(class(x), character())) attr(x, "class") <- NULL
  if (is.list(x) && !is.object(x)) {
    nm <- names(x)
    x <- lapply(x, un_i)
    names(x) <- nm
  }
  x
}

# A suite case's value (JSON-shaped: numbers double, arrays and objects
# lists) next to a decoded one, both flattened to the same shape: atomic
# vectors become lists of their elements, with NA as NULL, and numbers are
# compared as doubles.
json_shape <- function(x) {
  # A one-element array decodes as an I() vector: an array, not a scalar.
  if (inherits(x, "AsIs")) return(lapply(as.list(un_i(x)), json_shape))
  x <- un_i(x)
  if (is.null(x)) return(NULL)
  if (inherits(x, "msgpack_ext")) return(list(ext = unclass(x)$type, data = unclass(x)$data))
  if (is.raw(x)) return(x)
  if (is.atomic(x) && length(x) == 1L && is.null(names(x))) {
    if (is.na(x)) return(NULL)
    return(if (is.numeric(x)) as.numeric(x) else x)
  }
  if (is.atomic(x)) x <- as.list(x)
  # jsonlite reads {} as an unnamed list(), the same as [].
  if (length(x) == 0L) return(list())
  nm <- names(x)
  out <- lapply(x, json_shape)
  names(out) <- nm
  out
}

# msgpack_encode(x) is exactly these bytes.
expect_msgpack <- function(x, hex, ...) {
  expect_identical(raw_hex(msgpack_encode(x, ...)), raw_hex(hex_raw(hex)), info = hex)
}

# A value exercising every Stage 3 encoder path, for the cross-platform
# fixture (test-encode.R). Built at run time: -0 and the float bit patterns
# must not pass through R's parser or byte-code compiler.
mixed_value <- function() {
  list(
    ints = c(0L, 127L, 128L, 255L, 256L, 65535L, 65536L, -1L, -32L, -33L, -128L,
             -129L, -32768L, -32769L, .Machine$integer.max, -.Machine$integer.max, NA),
    doubles = c(0, neg_zero(), 1.5, f64("3ff199999999999a"), 2^31, 2^32, 2^53 + 2,
                2^64 - 2048, -2^63, 2^64, -2^63 - 2048, f64("7e37e43c8800759c"), NaN, Inf, -Inf, NA),
    text = c("", "a", "ü水\U00010151", strrep("x", 31), strrep("y", 32),
             strrep("z", 256), NA),
    raw = as.raw(0:40),
    lgl = c(TRUE, FALSE, NA),
    fac = factor(c("lo", "hi", NA, "lo")),
    big = msgpack_bigint(c("18446744073709551615", "-9223372036854775808", "1", NA)),
    map = msgpack_map(list(1L, "k", as.raw(1), -1L, list(1L, 2L)),
                      list(TRUE, NULL, "bin key", 1.5, "array key")),
    ext = list(msgpack_ext(1, as.raw(1)), msgpack_ext(2, raw(2)), msgpack_ext(-2, raw(3)),
               msgpack_ext(127, raw(16)), msgpack_ext(-128, raw(17)), msgpack_ext(5, raw(300))),
    nested = list(list(list(I(1L), list())), structure(list(), names = character())),
    sixteen = as.list(1:16),
    zz = I("boxed"), aa = c(b = 1L, a = 2L)
  )
}
