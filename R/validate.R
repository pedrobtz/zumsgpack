#' Validate MessagePack
#'
#' Checks that `x` holds well-formed, valid MessagePack within the given
#' limits, without building any R value. This is exactly the check the
#' decoders run before they build anything, so they agree about the bytes;
#' they disagree only where the bytes are valid but R cannot hold the value,
#' such as a `str` containing U+0000.
#'
#' The check covers well-formedness (every head, length and count against
#' the bytes there are, and the reserved byte `0xc1`), UTF-8 in every `str`,
#' the three legal layouts of the timestamp extension (type -1), duplicate
#' map keys, and the limits. Keys are compared by value: the integer 1 in
#' one byte and in `uint 16` is the same key, and so is a `float 32` 1.0 and
#' a `float 64` 1.0; the integer 1 and the float 1.0 are different keys, as
#' are a `str` and a `bin` with the same bytes. An array or map used as a
#' key is compared by its encoded bytes.
#'
#' MessagePack defines no canonical form, so there is no `deterministic`
#' argument: zumsgpack's encoder follows rules of its own (see
#' `msgpack_encode()`), which a decoder is not entitled to expect.
#'
#' @param x A raw vector.
#' @param sequence If `TRUE`, `x` is zero or more objects back to back; if
#'   `FALSE`, it must be exactly one object.
#' @param duplicate_keys If `FALSE` (the default), a map with the same key
#'   twice is invalid.
#' @param max_depth Deepest nesting allowed, counting arrays, maps and
#'   extension objects. At most `zumsgpack_info()$max_depth_cap`.
#' @param max_size Largest input allowed, in bytes, or `Inf`.
#' @param max_items Most objects allowed, counting every array, map, key,
#'   value and element, or `Inf`.
#' @param error If `TRUE`, raise the classed condition describing the fault
#'   instead of returning `FALSE`; see [zumsgpack-conditions].
#' @return `TRUE` or `FALSE`; with `error = TRUE`, `TRUE` invisibly or an
#'   error.
#' @export
#' @examples
#' msgpack_validate(as.raw(c(0x93, 0x01, 0x02, 0x03)))   # [1, 2, 3]
#' msgpack_validate(as.raw(c(0x93, 0x01, 0x02)))         # truncated
#' msgpack_validate(as.raw(c(0x82, 0x01, 0x00, 0xcc, 0x01, 0x00)))  # {1: 0, 1: 0}
#' msgpack_validate(as.raw(c(0x01, 0x02)), sequence = TRUE)
msgpack_validate <- function(x, sequence = FALSE, duplicate_keys = FALSE,
                             max_depth = 256L, max_size = 64 * 1024^2,
                             max_items = 1e6, error = FALSE) {
  call <- sys.call()
  zmp_arg_flag(error, "error", call)
  zmp_arg_flag(sequence, "sequence", call)
  mode <- if (sequence) zmp_mode[["seq"]] else zmp_mode[["one"]]
  fault <- zmp_check_input(x, mode, duplicate_keys, max_depth, max_size,
                           max_items, call)
  if (is.null(fault)) {
    if (error) invisible(TRUE) else TRUE
  } else {
    if (error) zmp_raise_fault(fault, call) else FALSE
  }
}

# The check phase: argument checks, then the walk. Returns NULL or a fault;
# a size fault is returned as one too, so msgpack_validate() can say FALSE.
zmp_check_input <- function(x, mode, duplicate_keys, max_depth, max_size,
                            max_items, call = NULL) {
  zmp_arg_raw(x, "x", call)
  zmp_arg_flag(duplicate_keys, "duplicate_keys", call)
  zmp_arg_limits(max_depth, max_size, max_items, call)
  if (length(x) > max_size) return(zmp_size_fault(max_size))
  .Call(zmp_check_raw, x, mode, duplicate_keys, as.integer(max_depth),
        as.numeric(max_items))
}
