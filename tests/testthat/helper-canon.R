# The canonical text form of a decoded value, as tools/canon.py writes it
# for Python's msgpack: two implementations agree on a value exactly when
# they print the same text. tools/conformance.R sources this file, so there
# is one R copy.
#
# Values must come from msgpack_decode(simplify = "none", map_keys = "map",
# ext = "keep"): every array a list, every map a msgpack_map in order, every
# timestamp its bytes.

canon_hex <- function(x) paste(sprintf("%02x", as.integer(x)), collapse = "")

canon_double <- function(d) paste0("n:", canon_hex(writeBin(as.double(d), raw(), size = 8L, endian = "big")))

canon_timestamp <- function(data) {
  be <- function(b) sum(as.numeric(b) * 256^(rev(seq_along(b)) - 1L))
  if (length(data) == 4L) return(paste0("t:", format(be(data), scientific = FALSE), ":0"))
  if (length(data) == 8L) {
    hi <- be(data[1:4])
    sec <- (hi %% 4) * 2^32 + be(data[5:8])
    return(paste0("t:", format(sec, scientific = FALSE), ":", format(hi %/% 4, scientific = FALSE)))
  }
  # timestamp 96: int 64 seconds, read exactly through the decoder itself.
  sec <- msgpack_decode(c(as.raw(0xd3), data[5:12]))
  paste0("t:", format(sec, scientific = FALSE), ":", format(be(data[1:4]), scientific = FALSE))
}

canon <- function(v) {
  if (is.null(v)) return("null")
  if (inherits(v, "msgpack_bigint")) return(paste0("i:", unclass(v)))
  if (inherits(v, "msgpack_ext")) {
    e <- unclass(v)
    if (e$type == -1L) return(canon_timestamp(e$data))
    return(paste0("x:", e$type, ":", canon_hex(e$data)))
  }
  if (inherits(v, "msgpack_map")) {
    m <- unclass(v)
    if (!length(m$keys)) return("{}")
    return(paste0("{", paste0(vapply(m$keys, canon, ""), "=", vapply(m$values, canon, ""),
                              collapse = ","), "}"))
  }
  if (is.list(v)) return(paste0("[", paste(vapply(v, canon, ""), collapse = ","), "]"))
  if (is.raw(v)) return(paste0("b:", canon_hex(v)))
  stopifnot(length(v) == 1L)
  if (is.logical(v)) return(if (v) "true" else "false")
  if (is.numeric(v)) return(canon_double(v))
  if (is.character(v)) return(paste0("s:", canon_hex(charToRaw(enc2utf8(v)))))
  stop("no canonical form for a ", class(v)[1])
}

canon_decode <- function(x) {
  canon(msgpack_decode(x, simplify = "none", map_keys = "map", ext = "keep"))
}

python_fixtures <- function() {
  utils::read.delim(test_path("fixtures", "python-msgpack.tsv"), colClasses = "character",
                    quote = "", encoding = "UTF-8")
}
