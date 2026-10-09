# Writes the check phase's seed inputs into a directory: every encoding in
# the test suite and each of its proper prefixes, and the hostile inputs of
# design section 15. Base R only. Used by tools/run-standalone and, from
# Stage 7, as the fuzzers' seed corpus.
#
#   Rscript tools/fuzz-seeds.R <dir>

zmp_seed_hex <- function(h) {
  h <- gsub("[^0-9a-fA-F]", "", h)
  if (!nzchar(h)) return(raw())
  as.raw(strtoi(substring(h, seq(1L, nchar(h), 2L), seq(2L, nchar(h), 2L)), 16L))
}

zmp_hostile <- function() {
  n <- 20000L
  keys <- unlist(lapply(seq_len(n) - 1L, function(i)
    as.raw(c(0xcd, i %/% 256L, i %% 256L, 0xc0))))
  c(lapply(c(
    "dd ff ff ff ff", "df ff ff ff ff", "db ff ff ff ff 61 62", "c6 ff ff ff ff",
    "c9 ff ff ff ff 01", "c1", "91 c1", "c7 05 ff 01 02 03 04 05",
    "d7 ff ee 6b 28 00 00 00 00 00", "c7 0c ff 3b 9a ca 00 00 00 00 00 00 00 00 00",
    "83 01 c0 cc 01 c0 cd 00 01 c0", "82 ca 3f 80 00 00 c0 cb 3f f0 00 00 00 00 00 00 c0",
    "a2 c0 80", "a3 ed a0 80", "a4 f4 90 80 80", "c0 c0", "81 82 01 c0 01 c0 c0"
  ), zmp_seed_hex),
  list(c(rep(as.raw(0x91), 1e6), as.raw(0xc0)),
       c(rep(as.raw(0x81), 2000), rep(as.raw(0xc0), 2001)),
       c(as.raw(c(0xde, n %/% 256L, n %% 256L)), keys)))
}

zmp_suite_seeds <- function(tsv) {
  s <- utils::read.delim(tsv, colClasses = "character", quote = "", encoding = "UTF-8")
  out <- list()
  for (h in s$hex) {
    b <- zmp_seed_hex(h)
    for (n in 0:length(b)) out[[length(out) + 1L]] <- b[seq_len(n)]
  }
  out
}

if (!interactive() && sys.nframe() == 0L) {
  dir <- commandArgs(trailingOnly = TRUE)[1]
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  seeds <- c(zmp_suite_seeds(file.path("tests", "testthat", "fixtures",
                                       "msgpack-test-suite.tsv")),
             zmp_hostile())
  for (i in seq_along(seeds))
    writeBin(seeds[[i]], file.path(dir, sprintf("seed-%05d", i)))
  cat(sprintf("==> %d seeds in %s\n", length(seeds), dir))
}
