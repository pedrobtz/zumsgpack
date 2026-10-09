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
cat(sprintf("==> %d checks over %d seeds\n", n, length(seeds)))
