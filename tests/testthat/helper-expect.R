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
