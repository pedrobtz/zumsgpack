#' Decode MessagePack
#'
#' Turns MessagePack bytes into ordinary R values. The whole input is
#' checked first -- well-formedness, validity, duplicate keys and the
#' limits, exactly as [msgpack_validate()] does -- and nothing is built
#' until that check passes, so a length or count in a head cannot make R
#' allocate for data the input does not hold.
#'
#' @section MessagePack to R:
#' | MessagePack | R |
#' |---|---|
#' | every integer form | `integer` if it fits, else `double` up to 2^53, else by `big_integers` |
#' | `float 32`, `float 64` | `double`, exactly |
#' | `true`, `false` | `logical` |
#' | `nil` | `NULL`, or `NA` inside an atomic vector |
#' | `bin 8/16/32` | `raw` |
#' | `str` (fixstr, `str 8/16/32`) | `character`, UTF-8 |
#' | array | atomic vector when the elements agree, else `list` |
#' | map with non-empty, unique `str` keys | named `list` |
#' | any other map | `msgpack_map` (by `map_keys`) |
#' | ext | `msgpack_ext` |
#'
#' An array simplifies to an atomic vector only when its elements agree:
#' integers and floats combine to the wider; booleans stay logical, and
#' text stays text; wide integers and integer-valued numbers combine to
#' `msgpack_bigint`. `nil` joins any of them as `NA`. Anything else -- raw
#' vectors, nested arrays and maps, exts, booleans with numbers, a mixture
#' -- is a list. `[]` is `logical(0)`.
#'
#' A one-element array that simplifies is marked with [I()], so that the
#' encoder writes it back as an array rather than a single value.
#'
#' A `str` holding U+0000 cannot be an R string and is
#' `zumsgpack_unrepresentable`.
#'
#' @param x A raw vector holding exactly one MessagePack object
#'   (`msgpack_decode()`), or zero or more objects back to back
#'   (`msgpack_decode_seq()`).
#' @param simplify `"preserve"` simplifies arrays whose elements agree to
#'   atomic vectors; `"none"` makes every array a list.
#' @param map_keys `"auto"` gives a named list when every key is a
#'   non-empty, unique `str`, and a `msgpack_map` otherwise. `"map"` always
#'   gives a `msgpack_map`. `"string"` always gives a named list, naming each
#'   entry by its `str` key, or by a text rendering of any other key (`1`,
#'   `1.0`, `nil`, `h'00ff'`, `ext(5, h'01')`, `[1, "a"]`); it is lossy, and
#'   refuses a map whose keys collide once named.
#' @param big_integers What to do with an integer beyond 2^53, which a
#'   double cannot hold exactly: `"bigint"` returns a `msgpack_bigint`,
#'   `"double"` the nearest double, and `"error"` refuses the input.
#' @inheritParams msgpack_validate
#' @return The decoded value; for `msgpack_decode_seq()`, a list with one
#'   element per object.
#' @seealso [msgpack_validate()], [msgpack_read()], [msgpack-values],
#'   [zumsgpack-conditions].
#' @export
#' @examples
#' msgpack_decode(as.raw(c(0x93, 0x01, 0x02, 0x03)))        # [1, 2, 3]
#' msgpack_decode(as.raw(c(0x81, 0xa1, 0x61, 0xc3)))        # {"a": true}
#'
#' # Integer keys, so a msgpack_map.
#' msgpack_decode(as.raw(c(0x81, 0x01, 0xd0, 0xf9)))        # {1: -7}
#'
#' msgpack_decode_seq(as.raw(c(0x01, 0xa1, 0x61)))          # 1, then "a"
msgpack_decode <- function(x, simplify = c("preserve", "none"),
                           map_keys = c("auto", "map", "string"),
                           big_integers = c("bigint", "double", "error"),
                           duplicate_keys = FALSE, max_depth = 256L,
                           max_size = 64 * 1024^2, max_items = 1e6) {
  zmp_decode(x, zmp_mode[["one"]], simplify, map_keys, big_integers,
             duplicate_keys, max_depth, max_size, max_items, call = sys.call())
}

#' @rdname msgpack_decode
#' @export
msgpack_decode_seq <- function(x, simplify = c("preserve", "none"),
                               map_keys = c("auto", "map", "string"),
                               big_integers = c("bigint", "double", "error"),
                               duplicate_keys = FALSE, max_depth = 256L,
                               max_size = 64 * 1024^2, max_items = 1e6) {
  zmp_decode(x, zmp_mode[["seq"]], simplify, map_keys, big_integers,
             duplicate_keys, max_depth, max_size, max_items, call = sys.call())
}

zmp_decode <- function(x, mode, simplify, map_keys, big_integers,
                       duplicate_keys, max_depth, max_size, max_items, call) {
  zmp_arg_raw(x, "x", call)
  simplify <- zmp_arg_choice(simplify, "simplify", c("preserve", "none"), call)
  map_keys <- zmp_arg_choice(map_keys, "map_keys", c("auto", "map", "string"), call)
  big_integers <- zmp_arg_choice(big_integers, "big_integers",
                                 c("bigint", "double", "error"), call)
  zmp_arg_flag(duplicate_keys, "duplicate_keys", call)
  zmp_arg_limits(max_depth, max_size, max_items, call)
  if (length(x) > max_size) zmp_raise_fault(zmp_size_fault(max_size), call)
  opts <- c(mode, duplicate_keys, max_depth, simplify, map_keys, big_integers)
  res <- .Call(zmp_decode_raw, x, as.integer(opts), as.numeric(max_items), call)
  if (!is.null(res[[1L]])) zmp_raise_fault(res[[1L]], call)
  if (mode == zmp_mode[["prefix"]]) list(value = res[[2L]], consumed = res[[3L]])
  else res[[2L]]
}

# The 0-based code of a choice, the way C reads it. The default is the whole
# choice vector, as with match.arg(); anything else must be one of them.
zmp_arg_choice <- function(x, arg, choices, call = NULL) {
  if (identical(x, choices)) return(0L)
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% choices) {
    zmp_invalid_argument(arg, sprintf("`%s` must be one of %s.", arg,
                                      paste0('"', choices, '"', collapse = ", ")), call)
  }
  match(x, choices) - 1L
}
