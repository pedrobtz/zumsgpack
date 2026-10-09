#' Encode R values as MessagePack
#'
#' Turns an R value into MessagePack bytes, deterministically: identical R
#' objects give identical bytes in every session and on every platform.
#'
#' @section R to MessagePack:
#' | R | MessagePack |
#' |---|---|
#' | `NULL`, `NA` of any type | `nil` |
#' | `TRUE`, `FALSE` | `true`, `false` |
#' | `integer` | the smallest integer form |
#' | `double`, whole, within -2^63 .. 2^64 - 1, not `-0` | the smallest integer form |
#' | any other `double`, including `NaN`, `Inf` and `-0` | `float 64` (see `floats`) |
#' | `character` | `str`, UTF-8 |
#' | `raw` | one `bin`, whatever its length |
#' | `factor` | its labels, as `str` |
#' | `POSIXct` | ext -1, the smallest of the three timestamp layouts that holds it |
#' | `Date` | ext -1 at midnight UTC |
#' | `msgpack_bigint` | the integer form if within -2^63 .. 2^64 - 1, else refused |
#' | `msgpack_map`, `msgpack_ext` | a map, an ext |
#' | unnamed list or vector | array |
#' | fully named list or vector | map with `str` keys |
#' | `data.frame` | array of maps, one per row |
#'
#' A length-one atomic vector is a single value, not an array, unless it is
#' wrapped in [I()] or `auto_unbox = FALSE`. A matrix is a flat array in
#' column-major order. A data frame is an array with one map per row, keyed
#' by the column names; `NA` is `nil`, and row names are not written. An
#' object whose class zumsgpack does not know goes through [as_msgpack()]
#' first, so a method can say how to write it; without one it is written as
#' its underlying type.
#'
#' Whole doubles become integers because R has no integer literal: `-7`
#' written in R is a double, and as a float it would be a different value
#' from the integer a protocol expects. So `1L` and `1` encode identically.
#'
#' These have no MessagePack form and raise `zumsgpack_unsupported_type`:
#' complex numbers, functions, environments, external pointers, S4 objects,
#' `POSIXlt` (convert with [as.POSIXct()]) and a data frame column that is
#' itself a matrix. Names that are partly
#' missing, `NA` or empty are `zumsgpack_invalid_argument`, and two keys
#' that encode identically are `zumsgpack_duplicate_key`.
#'
#' @section Deterministic encoding:
#' MessagePack's specification says only that an encoder should use the
#' smallest integer form. zumsgpack always writes:
#'
#' 1. the smallest form of every integer and of every length and count;
#' 2. `float 64` for every non-integral double, or with
#'    `floats = "shortest"` a `float 32` when it holds the value exactly;
#'    every `NaN` as one canonical quiet NaN, since R's `NaN` bits differ
#'    between platforms;
#' 3. `str` for text and `bin` for bytes, never the pre-2013 `raw`;
#' 4. map entries sorted by the bytewise order of their encoded keys, with
#'    no duplicate keys;
#' 5. the smallest timestamp layout that holds the instant, after fixing it
#'    to whole nanoseconds by one rule: the seconds by `floor()`, the
#'    fraction rounded to the nearest nanosecond, a carry at 10^9.
#'
#' These are zumsgpack's rules, not the format's: another decoder is not
#' entitled to expect them, and [msgpack_validate()] does not check for
#' them. They make the output byte-identical across calls, sessions and
#' platforms, which a signature or a content hash over the bytes needs.
#'
#' @section Conversions that do not round-trip:
#' Decoding what `msgpack_encode()` wrote gives back the value, except
#' that: `NA` comes back as `NULL`, or `NA` of the vector's type; a whole
#' double comes back as an integer; `list(1L)` and `1L` both encode as `1`;
#' a `NaN` payload is not kept; a `float 32` input re-encodes as `float 64`
#' unless `floats = "shortest"`; a factor comes back as its labels; a
#' `Date` comes back as a `POSIXct` at midnight UTC; a `POSIXct` keeps its
#' fractional seconds only to double precision, about 2^-22 s near 2026;
#' and a data frame loses its row names, its factor levels and its column
#' order, since map keys are sorted.
#'
#' @param x An R value. For `msgpack_encode_seq()`, a list whose elements
#'   are encoded one after another, as objects back to back.
#' @param auto_unbox If `TRUE`, a length-one atomic vector is a single
#'   value; if `FALSE`, it is an array of one. Names used as map keys are
#'   always single strings.
#' @param max_depth Deepest nesting to write, counting arrays, maps and
#'   exts as [msgpack_decode()] does, so its output always decodes at the
#'   same `max_depth`.
#' @param floats `"double"` writes every non-integral double as `float 64`;
#'   `"shortest"` writes `float 32` when it holds the value exactly. Off by
#'   default, since some decoders widen a `float 32` through a type that
#'   changes the value their users see.
#' @return A raw vector.
#' @seealso [msgpack_decode()], [as_msgpack()], [msgpack-values].
#' @export
#' @examples
#' msgpack_encode(list(a = 1, b = c(2, 3)))
#' msgpack_encode(c(1.5, NaN, Inf))
#' msgpack_encode(0.5, floats = "shortest")
#'
#' # Integer keys need msgpack_map().
#' msgpack_encode(msgpack_map(list(1L), list(-7)))
#'
#' # Deterministic: map entries are sorted by their encoded keys.
#' identical(msgpack_encode(list(b = 1, a = 2)), msgpack_encode(list(a = 2, b = 1)))
#'
#' msgpack_encode_seq(list(1, "a", TRUE))
#'
#' # A timestamp, and a table as an array of records.
#' msgpack_encode(as.POSIXct("2026-01-01", tz = "UTC"))
#' msgpack_encode(data.frame(id = 1:2, name = c("a", "b")))
msgpack_encode <- function(x, auto_unbox = TRUE, max_depth = 256L,
                           floats = c("double", "shortest")) {
  zmp_encode(x, sequence = FALSE, auto_unbox, max_depth, floats, sys.call())
}

#' @rdname msgpack_encode
#' @export
msgpack_encode_seq <- function(x, auto_unbox = TRUE, max_depth = 256L,
                               floats = c("double", "shortest")) {
  call <- sys.call()
  if (!is.list(x) || is.object(x)) {
    zmp_invalid_argument("x", "`x` must be a plain list: each element is one object of the sequence.", call)
  }
  zmp_encode(x, sequence = TRUE, auto_unbox, max_depth, floats, call)
}

zmp_encode <- function(x, sequence, auto_unbox, max_depth, floats, call) {
  zmp_arg_flag(auto_unbox, "auto_unbox", call)
  zmp_arg_limit(max_depth, "max_depth", zmp_max_depth_cap(), allow_inf = FALSE, call)
  floats <- zmp_arg_choice(floats, "floats", c("double", "shortest"), call)
  opts <- as.integer(c(sequence, auto_unbox, max_depth, floats))
  .Call(zmp_encode_raw, x, opts, call, topenv())
}
