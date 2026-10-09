# Writes the oracle's input (tools/run-conformance): one row per object,
# with zumsgpack's decoding of it in the canonical text form of
# tests/testthat/helper-canon.R. Three sources:
#
#   suite    every encoding in kawanet/msgpack-test-suite
#   python   every object Python's msgpack wrote (tools/make-fixtures.py)
#   encoded  R values of every row of design section 7.1, encoded by
#            zumsgpack, for Python to read back
#
#   Rscript tools/conformance.R <out.tsv>
#
# CONFORMANCE_CANARY=1 corrupts one row's canonical form, so that
# tools/run-conformance can see the oracle fail before trusting it.
library(zumsgpack)
test_path <- function(...) file.path("tests", "testthat", ...)
source(test_path("helper-canon.R"))

hex <- function(h) {
  h <- gsub("[^0-9a-fA-F]", "", h)
  if (!nzchar(h)) return(raw())
  as.raw(strtoi(substring(h, seq(1L, nchar(h), 2L), seq(2L, nchar(h), 2L)), 16L))
}

rows <- list()
add <- function(source, name, bytes, seq = FALSE) {
  c <- if (seq) paste(vapply(msgpack_decode_seq(bytes, simplify = "none", map_keys = "map",
                                                 ext = "keep"), canon, ""), collapse = ";")
       else canon_decode(bytes)
  rows[[length(rows) + 1L]] <<- data.frame(source = source, name = name,
                                           hex = canon_hex(bytes), canon = c)
}

s <- utils::read.delim(test_path("fixtures", "msgpack-test-suite.tsv"),
                       colClasses = "character", quote = "", encoding = "UTF-8")
for (i in seq_len(nrow(s)))
  add("suite", paste(s$group[i], s$case[i], s$form[i]), hex(s$hex[i]))

p <- python_fixtures()
for (i in seq_len(nrow(p)))
  add("python", p$name[i], hex(p$hex[i]), seq = p$name[i] == "fluentd forward stream")

utc <- function(x) structure(x, class = c("POSIXct", "POSIXt"), tzone = "UTC")
values <- list(
  "NULL" = NULL, "NA" = NA, "TRUE" = TRUE, "FALSE" = FALSE,
  "integer" = c(0L, 127L, 128L, -1L, -32L, -33L, 65536L, -.Machine$integer.max, NA),
  "whole double" = c(2^31, 2^32, -2^63, 2^64 - 2048, 2^53 + 2),
  "double" = c(1.5, 0.1, -0, Inf, -Inf, NaN, 1e-300),
  "double shortest" = I(c(0.5, 0.1)),
  "character" = c("", "a", "\u00fc\u6c34\U0001f600", strrep("x", 40), NA),
  "raw" = as.raw(0:255),
  "factor" = factor(c("b", "a", NA)),
  "POSIXct" = utc(c(0, 2^32, 1.5, -1.5, 2^34, NA)),
  "Date" = as.Date(c("1970-01-02", "1900-01-01", NA)),
  "msgpack_bigint" = msgpack_bigint(c("18446744073709551615", "-9223372036854775808")),
  "msgpack_map" = msgpack_map(list(1L, "k", as.raw(1), list(1L, 2L)), list(TRUE, NULL, "b", "a")),
  "msgpack_ext" = list(msgpack_ext(5, as.raw(1:3)), msgpack_ext(-2, raw(16)), msgpack_ext(127, raw())),
  "unnamed list" = list(1L, "a", NULL, list()),
  "named list" = list(b = 1L, a = list(c = "x"), aa = 2.5),
  "data.frame" = data.frame(n = c(2L, NA), s = c("a", "b")),
  "I()" = I(1L)
)
for (nm in names(values)) {
  add("encoded", nm, msgpack_encode(values[[nm]]))
  if (nm == "double shortest") add("encoded", "double floats=shortest", msgpack_encode(values[[nm]], floats = "shortest"))
}
add("encoded", "sequence", msgpack_encode_seq(list(1L, "a", TRUE)), seq = TRUE)

out <- do.call(rbind, rows)
if (nzchar(Sys.getenv("CONFORMANCE_CANARY"))) {
  out$canon[out$name == "TRUE"] <- "false"
}
utils::write.table(out, commandArgs(trailingOnly = TRUE)[1], sep = "\t", quote = FALSE,
                   row.names = FALSE, fileEncoding = "UTF-8")
cat(sprintf("==> %d objects for the oracle\n", nrow(out)))
