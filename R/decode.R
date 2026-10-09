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
#' | ext -1 (timestamp) | `POSIXct`, UTC |
#' | any other ext | `msgpack_ext`, or a handler's result |
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
#' The timestamp extension (type -1) has three layouts: `timestamp 32`
#' (seconds), `timestamp 64` (34-bit seconds, 30-bit nanoseconds) and
#' `timestamp 96` (64-bit signed seconds, 32-bit nanoseconds). A `POSIXct`
#' is a double, so nanoseconds are kept only to double precision, about
#' 2^-22 s near 2026; a handler for `"-1"` can keep the fields exactly.
#'
#' @section Extension handlers:
#' `ext_handlers` gives meaning to extension types zumsgpack does not
#' convert, or replaces the timestamp conversion. Each handler is called
#' with the ext's payload as a raw vector -- an ext has no structure beyond
#' its bytes -- and its result takes the ext's place:
#'
#' ```
#' msgpack_decode(x, ext_handlers = list(
#'   "5"  = function(data) rawToChar(data),
#'   "-1" = function(data) data               # keep timestamps as bytes
#' ))
#' ```
#'
#' A handler runs only once the whole input has been checked, so it never
#' sees a payload from an object with a bad length or a duplicate key. Its
#' result never joins an array's simplification: an array holding one is a
#' list. A handler applies whatever `ext` says. An error in a handler
#' becomes `zumsgpack_handler_error`, with the type as `type` and the
#' original condition as `parent`. A handler that calls `msgpack_decode()`
#' again, for MessagePack embedded in an ext, passes that call its own
#' limits. [as_msgpack()] is the encoding half.
#'
#' @section Data frames:
#' With `data_frame = TRUE`, an array of maps -- the usual way to send a
#' table, one map per row -- becomes a data frame. Its columns are the
#' union of the keys, in the order they are first seen; a key a row lacks
#' is `NA`; and each column simplifies by the same rules as an array, so a
#' column of mixed kinds is a list column. Row names are not kept, since
#' the format has none. Rows that share no keys make a frame with as many
#' columns as rows, quadratic in the input, so the number of cells is
#' checked against `max_cells` before anything is allocated
#' (`zumsgpack_cell_limit`). Arrays of any other shape decode as without
#' the option, and so does an empty array.
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
#' @param ext `"convert"` turns timestamps (ext -1) into `POSIXct` and
#'   keeps other exts as `msgpack_ext`; `"keep"` makes every ext a
#'   `msgpack_ext`.
#' @param big_integers What to do with an integer beyond 2^53, which a
#'   double cannot hold exactly: `"bigint"` returns a `msgpack_bigint`,
#'   `"double"` the nearest double, and `"error"` refuses the input.
#' @param ext_handlers `NULL`, or a list of functions of one argument, named
#'   by extension type from `"-128"` to `"127"`, such as
#'   `list("5" = function(data) ...)`. See "Extension handlers".
#' @param data_frame If `TRUE`, an array whose every element is a map with
#'   non-empty `str` keys, none twice in one map, becomes a data frame: see
#'   "Data frames".
#' @param max_cells Most cells (rows times columns) a data frame may have,
#'   checked before it is allocated, or `Inf`.
#' @inheritParams msgpack_validate
#' @return The decoded value; for `msgpack_decode_seq()`, a list with one
#'   element per object.
#' @seealso [msgpack_validate()], [msgpack_read()], [msgpack_read_seq()],
#'   [msgpack_decode_prefix()], [msgpack-values],
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
#'
#' # A timestamp, and the same bytes kept as an ext.
#' ts <- as.raw(c(0xd6, 0xff, 0x5a, 0x4a, 0xf6, 0xa5))
#' msgpack_decode(ts)
#' msgpack_decode(ts, ext = "keep")
msgpack_decode <- function(x, simplify = c("preserve", "none"),
                           map_keys = c("auto", "map", "string"),
                           ext = c("convert", "keep"),
                           big_integers = c("bigint", "double", "error"),
                           duplicate_keys = FALSE, max_depth = 256L,
                           max_size = 64 * 1024^2, max_items = 1e6,
                           ext_handlers = NULL, data_frame = FALSE,
                           max_cells = 1e7) {
  zmp_decode(x, zmp_mode[["one"]], simplify, map_keys, ext, big_integers,
             duplicate_keys, max_depth, max_size, max_items, ext_handlers,
             data_frame, max_cells, call = sys.call())
}

#' @rdname msgpack_decode
#' @export
msgpack_decode_seq <- function(x, simplify = c("preserve", "none"),
                               map_keys = c("auto", "map", "string"),
                               ext = c("convert", "keep"),
                               big_integers = c("bigint", "double", "error"),
                               duplicate_keys = FALSE, max_depth = 256L,
                               max_size = 64 * 1024^2, max_items = 1e6,
                               ext_handlers = NULL, data_frame = FALSE,
                               max_cells = 1e7) {
  zmp_decode(x, zmp_mode[["seq"]], simplify, map_keys, ext, big_integers,
             duplicate_keys, max_depth, max_size, max_items, ext_handlers,
             data_frame, max_cells, call = sys.call())
}

zmp_decode <- function(x, mode, simplify, map_keys, ext, big_integers,
                       duplicate_keys, max_depth, max_size, max_items,
                       ext_handlers, data_frame, max_cells, call) {
  zmp_arg_raw(x, "x", call)
  simplify <- zmp_arg_choice(simplify, "simplify", c("preserve", "none"), call)
  map_keys <- zmp_arg_choice(map_keys, "map_keys", c("auto", "map", "string"), call)
  ext <- zmp_arg_choice(ext, "ext", c("convert", "keep"), call)
  big_integers <- zmp_arg_choice(big_integers, "big_integers",
                                 c("bigint", "double", "error"), call)
  zmp_arg_flag(duplicate_keys, "duplicate_keys", call)
  zmp_arg_flag(data_frame, "data_frame", call)
  zmp_arg_limits(max_depth, max_size, max_items, call)
  zmp_arg_limit(max_cells, "max_cells", 2^53, allow_inf = TRUE, call)
  handlers <- zmp_arg_handlers(ext_handlers, call)
  if (length(x) > max_size) zmp_raise_fault(zmp_size_fault(max_size), call)
  opts <- c(mode, duplicate_keys, max_depth, simplify, map_keys, big_integers, ext,
            data_frame)
  res <- .Call(zmp_decode_raw, x, as.integer(opts),
               c(as.numeric(max_items), as.numeric(max_cells)), call, handlers)
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
