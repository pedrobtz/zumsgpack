# Drives the package's C code over the seed inputs and through every path
# the stages have built so far, with base R only: the sanitizer containers
# carry no testthat (native-checks.yaml). Grows with each stage.
#
#   Rscript tools/sanitizer-exercise.R
library(zumsgpack)
source(file.path("tools", "fuzz-seeds.R"))

seeds <- c(zmp_suite_seeds(file.path("tests", "testthat", "fixtures",
                                     "msgpack-test-suite.tsv")),
           zmp_hostile())
n <- 0L
for (x in seeds) {
  for (seq in c(FALSE, TRUE)) for (dup in c(FALSE, TRUE)) {
    msgpack_validate(x, sequence = seq, duplicate_keys = dup)
    msgpack_validate(x, sequence = seq, duplicate_keys = dup, max_depth = 3L,
                     max_items = 5)
    n <- n + 2L
  }
}

# Stage 2: every seed decoded under every option set, faults included.
decoded <- 0L
options <- expand.grid(simplify = c("preserve", "none"),
                       map_keys = c("auto", "map", "string"),
                       big_integers = c("bigint", "double", "error"),
                       duplicate_keys = c(FALSE, TRUE), stringsAsFactors = FALSE)
for (x in seeds) {
  for (i in seq_len(nrow(options))) {
    o <- options[i, ]
    for (f in list(msgpack_decode, msgpack_decode_seq)) {
      r <- tryCatch(f(x, simplify = o$simplify, map_keys = o$map_keys,
                      big_integers = o$big_integers, duplicate_keys = o$duplicate_keys),
                    zumsgpack_error = function(e) NULL)
      decoded <- decoded + 1L
    }
  }
}
cat(sprintf("==> %d checks and %d decodes over %d seeds\n", n, decoded, length(seeds)))
