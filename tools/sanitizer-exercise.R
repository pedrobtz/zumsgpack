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

# Stage 3: every decoded seed encoded again under both float options and a
# tight depth, faults included; and encoder faults raised from deep inside
# maps, whose key buffers must be freed by their owners.
encoded <- 0L
for (x in seeds) {
  v <- tryCatch(msgpack_decode(x, duplicate_keys = TRUE), zumsgpack_error = function(e) NULL)
  for (fl in c("double", "shortest")) for (d in c(256L, 2L)) {
    tryCatch(msgpack_encode(v, floats = fl, max_depth = d), zumsgpack_error = function(e) NULL)
    encoded <- encoded + 1L
  }
}
bad <- msgpack_map(list(list(1L, 2L), "b", msgpack_ext(1, raw(3))), list(1L, list(x = 1i), 2L))
for (i in 1:200) tryCatch(msgpack_encode(bad), zumsgpack_error = function(e) NULL)

# Stage 4: handlers on every type the seeds hold, one of which errors, the
# timestamp conversion both ways, and as_msgpack() methods, one of which
# errors from inside a map key.
h <- lapply(-128:127, function(t) if (t == 5L) function(d) stop("no") else function(d) length(d))
names(h) <- as.character(-128:127)
for (x in seeds) {
  tryCatch(msgpack_decode(x, ext_handlers = h), zumsgpack_error = function(e) NULL)
  tryCatch(msgpack_decode(x, ext = "keep"), zumsgpack_error = function(e) NULL)
}
registerS3method("as_msgpack", "zmp_ex", function(x, ...) msgpack_ext(3, as.raw(unclass(x))))
registerS3method("as_msgpack", "zmp_ex_bad", function(x, ...) stop("no"))
times <- structure(c(0, -1.5, 2^34, 1e9 + 0.123456, NA), class = c("POSIXct", "POSIXt"))
for (i in 1:200) {
  msgpack_decode(msgpack_encode(list(times, as.Date("2024-02-29"), structure(1:3, class = "zmp_ex"))))
  tryCatch(msgpack_encode(msgpack_map(list(structure(1, class = "zmp_ex_bad")), list(1))),
           error = function(e) NULL)
}
cat(sprintf("==> %d checks, %d decodes and %d encodes over %d seeds; handlers and timestamps\n",
            n, decoded, encoded, length(seeds)))
