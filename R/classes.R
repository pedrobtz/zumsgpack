# Values R has no native type for (design sections 6 and 7). Users build
# them as well as receive them, so the constructors validate.

#' MessagePack values without a native R type
#'
#' Constructors for the three values the decoder returns when R has no
#' faithful type of its own. The encoder accepts them too, to write those
#' values back.
#'
#' * `msgpack_map()` is a map whose keys are not all non-empty, unique
#'   `str`s: integer keys, for example. `keys` and `values` are lists of
#'   equal length, in order.
#' * `msgpack_ext()` is an extension object: `type`, a whole number from
#'   -128 to 127, and `data`, its payload as a raw vector. Type -1 is the
#'   timestamp; the other negative types are reserved by the specification.
#' * `msgpack_bigint()` is an integer outside what a double holds exactly,
#'   stored as canonical decimal text. It accepts decimal strings, or whole
#'   numbers within 2^53. MessagePack holds integers from -2^63 to 2^64 - 1,
#'   and the encoder refuses one outside that range.
#'
#' @param keys,values Lists (or vectors, taken element by element) of equal
#'   length.
#' @param type A whole number from -128 to 127.
#' @param data A raw vector.
#' @param x Decimal strings or whole numbers.
#' @return An object of class `msgpack_map`, `msgpack_ext` or
#'   `msgpack_bigint`.
#' @name msgpack-values
#' @examples
#' msgpack_map(list(1L, 3L), list(-7L, "ES256"))
#' msgpack_ext(5, as.raw(c(0x01, 0x02)))
#' msgpack_bigint("18446744073709551615")
NULL

#' @rdname msgpack-values
#' @export
msgpack_map <- function(keys = list(), values = list()) {
  call <- sys.call()
  keys <- as.list(keys)
  values <- as.list(values)
  if (length(keys) != length(values)) {
    zmp_invalid_argument("values", "`keys` and `values` must have the same length.", call)
  }
  structure(list(keys = unname(keys), values = unname(values)), class = "msgpack_map")
}

#' @rdname msgpack-values
#' @export
msgpack_ext <- function(type, data = raw()) {
  call <- sys.call()
  if (!is.numeric(type) || length(type) != 1L || is.na(type) ||
      type != trunc(type) || type < -128 || type > 127) {
    zmp_invalid_argument("type", "`type` must be a whole number from -128 to 127.", call)
  }
  if (!is.raw(data)) {
    zmp_invalid_argument("data", "`data` must be a raw vector.", call)
  }
  structure(list(type = as.integer(type), data = data), class = "msgpack_ext")
}

#' @rdname msgpack-values
#' @export
msgpack_bigint <- function(x) {
  call <- sys.call()
  if (inherits(x, "msgpack_bigint")) return(x)
  if (is.numeric(x)) {
    if (!all(is.na(x) | (is.finite(x) & x == trunc(x) & abs(x) <= 2^53))) {
      zmp_invalid_argument("x", "numbers must be whole and within 2^53; give larger ones as text.", call)
    }
    x <- ifelse(is.na(x), NA_character_, formatC(x, format = "f", digits = 0, big.mark = ""))
  }
  if (!is.character(x)) {
    zmp_invalid_argument("x", "`x` must be decimal strings or whole numbers.", call)
  }
  x <- unname(x)
  ok <- is.na(x) | grepl("^-?(0|[1-9][0-9]*)$", x)
  if (!all(ok)) {
    zmp_invalid_argument("x", "`x` must be canonical decimal integers, such as \"-12\".", call)
  }
  x[!is.na(x) & x == "-0"] <- "0"
  structure(x, class = "msgpack_bigint")
}

#' @export
format.msgpack_bigint <- function(x, ...) format(unclass(x), ...)

#' @export
as.character.msgpack_bigint <- function(x, ...) as.vector(unclass(x))

#' @export
as.numeric.msgpack_bigint <- function(x, ...) as.numeric(unclass(x))

#' @export
as.double.msgpack_bigint <- function(x, ...) as.double(unclass(x))

#' @export
`[.msgpack_bigint` <- function(x, i) structure(unclass(x)[i], class = "msgpack_bigint")

#' @export
print.msgpack_bigint <- function(x, ...) {
  cat("<msgpack_bigint[", length(x), "]>\n", sep = "")
  if (length(x)) print(unclass(x), quote = FALSE)
  invisible(x)
}

#' @export
format.msgpack_ext <- function(x, ...) {
  d <- unclass(x)$data
  shown <- paste(sprintf("%02x", as.integer(utils::head(d, 16L))), collapse = "")
  if (length(d) > 16L) shown <- paste0(shown, "...")
  paste0("ext(", unclass(x)$type, ", h'", shown, "')")
}

#' @export
as.character.msgpack_ext <- function(x, ...) format(x)

#' @export
print.msgpack_ext <- function(x, ...) {
  cat("<msgpack_ext type ", unclass(x)$type, ", ", length(unclass(x)$data),
      if (length(unclass(x)$data) == 1L) " byte>\n" else " bytes>\n", sep = "")
  if (length(unclass(x)$data)) print(unclass(x)$data)
  invisible(x)
}

#' @export
length.msgpack_map <- function(x) length(unclass(x)$keys)

#' @export
format.msgpack_map <- function(x, ...) {
  paste0("<msgpack_map: ", length(x), if (length(x) == 1L) " entry>" else " entries>")
}

#' @export
as.character.msgpack_map <- function(x, ...) format(x)

#' @export
print.msgpack_map <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  m <- unclass(x)
  for (i in seq_along(m$keys)) {
    key <- m$keys[[i]]
    label <- if (is.atomic(key) && length(key) == 1L && !is.raw(key)) format(key)
             else if (inherits(key, "msgpack_ext")) format(key)
             else paste(utils::capture.output(utils::str(key, give.head = FALSE)), collapse = " ")
    cat("[[", trimws(label), "]]\n", sep = "")
    print(m$values[[i]], ...)
  }
  invisible(x)
}
