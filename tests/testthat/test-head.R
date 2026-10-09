# The head table against an independent one, written here from the
# MessagePack specification's format list (msgpack/spec.md, "Overview").

spec_formats <- function() {
  # first, last, kind, head length, field width, fixext payload length
  rows <- list(
    list(0x00, 0x7f, "uint", 1, 0, 0),   # positive fixint
    list(0x80, 0x8f, "map", 1, 0, 0),    # fixmap
    list(0x90, 0x9f, "array", 1, 0, 0),  # fixarray
    list(0xa0, 0xbf, "str", 1, 0, 0),    # fixstr
    list(0xc0, 0xc0, "nil", 1, 0, 0),
    list(0xc1, 0xc1, "reserved", 1, 0, 0),
    list(0xc2, 0xc2, "false", 1, 0, 0),
    list(0xc3, 0xc3, "true", 1, 0, 0),
    list(0xc4, 0xc4, "bin", 2, 1, 0),
    list(0xc5, 0xc5, "bin", 3, 2, 0),
    list(0xc6, 0xc6, "bin", 5, 4, 0),
    list(0xc7, 0xc7, "ext", 3, 1, 0),
    list(0xc8, 0xc8, "ext", 4, 2, 0),
    list(0xc9, 0xc9, "ext", 6, 4, 0),
    list(0xca, 0xca, "f32", 5, 4, 0),
    list(0xcb, 0xcb, "f64", 9, 8, 0),
    list(0xcc, 0xcc, "uint", 2, 1, 0),
    list(0xcd, 0xcd, "uint", 3, 2, 0),
    list(0xce, 0xce, "uint", 5, 4, 0),
    list(0xcf, 0xcf, "uint", 9, 8, 0),
    list(0xd0, 0xd0, "int", 2, 1, 0),
    list(0xd1, 0xd1, "int", 3, 2, 0),
    list(0xd2, 0xd2, "int", 5, 4, 0),
    list(0xd3, 0xd3, "int", 9, 8, 0),
    list(0xd4, 0xd4, "ext", 2, 0, 1),
    list(0xd5, 0xd5, "ext", 2, 0, 2),
    list(0xd6, 0xd6, "ext", 2, 0, 4),
    list(0xd7, 0xd7, "ext", 2, 0, 8),
    list(0xd8, 0xd8, "ext", 2, 0, 16),
    list(0xd9, 0xd9, "str", 2, 1, 0),
    list(0xda, 0xda, "str", 3, 2, 0),
    list(0xdb, 0xdb, "str", 5, 4, 0),
    list(0xdc, 0xdc, "array", 3, 2, 0),
    list(0xdd, 0xdd, "array", 5, 4, 0),
    list(0xde, 0xde, "map", 3, 2, 0),
    list(0xdf, 0xdf, "map", 5, 4, 0),
    list(0xe0, 0xff, "int", 1, 0, 0)     # negative fixint
  )
  kinds <- c("nil", "false", "true", "uint", "int", "f32", "f64", "str", "bin",
             "array", "map", "ext", "reserved")
  out <- data.frame(kind = integer(256), hlen = integer(256), width = integer(256),
                    fixlen = integer(256))
  seen <- logical(256)
  for (r in rows) {
    i <- (r[[1]]:r[[2]]) + 1L
    stopifnot(!any(seen[i]))
    seen[i] <- TRUE
    out$kind[i] <- match(r[[3]], kinds) - 1L
    out$hlen[i] <- r[[4]]
    out$width[i] <- r[[5]]
    out$fixlen[i] <- r[[6]]
  }
  stopifnot(all(seen))
  out
}

test_that("every one of the 256 head bytes matches the specification", {
  got <- as.data.frame(.Call(zmp_head_table))
  want <- spec_formats()
  bad <- which(rowSums(got != want) > 0)
  expect(length(bad) == 0L, sprintf("bytes differ from the spec: %s",
    paste(sprintf("0x%02x", bad - 1L), collapse = ", ")))
})

test_that("a lone byte is a whole object exactly where the spec says", {
  # Complete on its own: every fixint, nil, the booleans, and the empty
  # fixmap, fixarray and fixstr. Every other byte promises more bytes, and
  # 0xc1 is never used at all.
  whole <- c(0x00:0x7f, 0x80, 0x90, 0xa0, 0xc0, 0xc2, 0xc3, 0xe0:0xff)
  got <- vapply(0:255, function(b) fault_class(as.raw(b)), character(1))
  expect_identical(which(got == "ok") - 1L, as.integer(whole))
  expect_true(all(got[-(whole + 1L)] == "zumsgpack_parse_error"))
  expect_identical(fault_of(as.raw(0xc1))$status, "ZMP_ERR_RESERVED")
})
