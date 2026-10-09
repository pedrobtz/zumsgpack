#' Decode the MessagePack object at the start of a raw vector
#'
#' Decodes the one object that `x` starts with and reports how many bytes it
#' used, for MessagePack inside binary framing: a payload after a fixed
#' header, or the first message of a buffer that may hold more. The object
#' is checked and decoded exactly as by [msgpack_decode()], with the same
#' arguments; what follows it is not read at all.
#'
#' That also means nothing about the rest is known: it may be more
#' MessagePack, the next field of the framing, or garbage. It is the
#' caller's to make sense of, as `x[-seq_len(consumed)]`.
#'
#' `max_size` applies to `x` as a whole, since all of it is in memory
#' already. An empty `x` is `zumsgpack_parse_error`, as for
#' `msgpack_decode()`; so is an object cut short by the end of `x`.
#'
#' @inheritParams msgpack_decode
#' @param x A raw vector starting with a MessagePack object.
#' @return A list: `value`, the decoded object, and `consumed`, the number
#'   of bytes it took, a double.
#' @seealso [msgpack_decode()] for one object and nothing else,
#'   [msgpack_decode_seq()] for objects all the way to the end, and
#'   [msgpack_read_seq()] for a stream.
#' @export
#' @examples
#' # [1, 2] followed by four bytes of something else.
#' x <- as.raw(c(0x92, 0x01, 0x02, 0xde, 0xad, 0xbe, 0xef))
#' r <- msgpack_decode_prefix(x)
#' r$value
#' x[-seq_len(r$consumed)]
msgpack_decode_prefix <- function(x, simplify = c("preserve", "none"),
                                  map_keys = c("auto", "map", "string"),
                                  ext = c("convert", "keep"),
                                  big_integers = c("bigint", "double", "error"),
                                  duplicate_keys = FALSE, max_depth = 256L,
                                  max_size = 64 * 1024^2, max_items = 1e6,
                                  ext_handlers = NULL, data_frame = FALSE,
                                  max_cells = 1e7) {
  zmp_decode(x, zmp_mode[["prefix"]], simplify, map_keys, ext, big_integers,
             duplicate_keys, max_depth, max_size, max_items, ext_handlers,
             data_frame, max_cells, call = sys.call())
}
