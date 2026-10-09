#' Read a sequence of MessagePack objects
#'
#' Reads objects written back to back with no framing, as MessagePack
#' streams are: Fluentd's forward protocol, neovim's RPC, Python's
#' `msgpack.Unpacker`. A sequence has no marker of its own, so the caller
#' says that this is one.
#'
#' Without `each`, the whole input is read, at most `max_size + 1` bytes of
#' it, and decoded as [msgpack_decode_seq()] would: a list with one element
#' per object.
#'
#' With `each`, a function of one argument, the input is read in blocks
#' and each object is checked whole, decoded and passed to `each` as soon as
#' its last byte has arrived; nothing accumulates, and the call returns the
#' number of objects read. Memory is then bounded by the largest object,
#' not the stream: `max_size` and `max_items` apply to each object on its
#' own. An object is never decoded before all of it has been checked, so
#' `each` never sees part of one. A malformed object stops the read with a
#' classed condition whose `offset` is its position in the stream; the
#' objects before it have already been passed on. The stream ending inside
#' an object is `zumsgpack_parse_error` at that object's offset. An error
#' raised by `each` itself propagates unchanged.
#'
#' @param file A file path, a URL, or a connection.
#' @param ... Arguments passed on to [msgpack_decode_seq()]: `simplify`,
#'   `map_keys`, `ext`, `big_integers`, `duplicate_keys`, `max_depth`,
#'   `max_items` and `ext_handlers`.
#' @param each `NULL`, or a function called with each object in turn.
#' @inheritParams msgpack_decode
#' @return Without `each`, a list of the objects; with it, the number of
#'   objects read, invisibly.
#' @seealso [msgpack_read()], [msgpack_decode_seq()],
#'   [msgpack_decode_prefix()].
#' @export
#' @examples
#' path <- tempfile(fileext = ".msgpack")
#' writeBin(msgpack_encode_seq(list(list(tag = "a", n = 1L),
#'                                  list(tag = "b", n = 2L))), path)
#' msgpack_read_seq(path)
#'
#' # One object at a time, in memory bounded by the largest.
#' total <- 0
#' msgpack_read_seq(path, each = function(x) total <<- total + x$n)
#' total
#' unlink(path)
msgpack_read_seq <- function(file, ..., each = NULL, max_size = 64 * 1024^2) {
  call <- sys.call()
  if (is.null(each)) {
    return(msgpack_decode_seq(zmp_read_bounded(file, max_size, call), ...,
                              max_size = max_size))
  }
  if (!is.function(each)) {
    zmp_invalid_argument("each", "`each` must be NULL or a function of one argument.", call)
  }
  zmp_arg_limit(max_size, "max_size", 2^53, allow_inf = TRUE, call)
  input <- zu_open_input(file, what = "file", prefix = "zumsgpack",
                         abort = function(arg, message) zmp_invalid_argument(arg, message, call))
  if (input$close) on.exit(close(input$con), add = TRUE)
  invisible(zmp_read_stream(input$con, each, max_size, list(...), call))
}

# The stream reader: blocks from con, the check in stream mode over the
# unconsumed tail plus each new block, every complete object built and
# passed to each(), the rest kept for the next block. Each read is at least
# as long as the tail already held, so an object larger than a block is
# re-checked a logarithmic number of times, not once per block: the work
# stays linear in its size. `chunk` is for tests, which feed the stream in
# blocks of a few bytes.
zmp_read_stream <- function(con, each, max_size, args, call, chunk = 65536L) {
  opts <- do.call(zmp_stream_options, args)
  tail <- raw()
  offset <- 0          # stream position of tail[1]
  n <- 0
  repeat {
    want <- max(chunk, length(tail))
    b <- tryCatch(readBin(con, "raw", n = want),
                  error = function(e) zmp_abort("zumsgpack_io_error",
                    paste0("could not read input: ", conditionMessage(e)), call = call))
    eof <- length(b) == 0L
    if (!eof) tail <- c(tail, b)
    if (length(tail) == 0L) {
      if (eof) break
      next
    }
    res <- .Call(zmp_decode_raw, tail, opts$codes, opts$max_items, call, opts$handlers)
    if (!is.null(res[[1L]])) {
      fault <- res[[1L]]
      fault$offset <- fault$offset + offset
      zmp_raise_fault(fault, call)
    }
    for (v in res[[2L]]) {
      each(v)
      n <- n + 1
    }
    consumed <- res[[3L]]
    if (consumed > 0) {
      tail <- tail[-seq_len(consumed)]
      offset <- offset + consumed
    }
    # One object, pending, larger than max_size: it can never be decoded.
    if (length(tail) > max_size) {
      fault <- zmp_size_fault(max_size)
      fault$offset <- offset
      zmp_raise_fault(fault, call)
    }
    if (eof) {
      if (length(tail)) {
        zmp_raise_fault(structure(list(
          status = "ZMP_ERR_TRUNCATED", detail = "the stream ends inside an object",
          offset = offset, limit = NA_character_, limit_value = NA_real_),
          class = "zmp_fault"), call)
      }
      break
    }
  }
  n
}

# The decoding options of msgpack_read_seq(each =), checked once, in C's
# codes. max_size is the reader's own.
zmp_stream_options <- function(simplify = c("preserve", "none"),
                               map_keys = c("auto", "map", "string"),
                               ext = c("convert", "keep"),
                               big_integers = c("bigint", "double", "error"),
                               duplicate_keys = FALSE, max_depth = 256L,
                               max_items = 1e6, ext_handlers = NULL) {
  call <- sys.call(-1L)
  simplify <- zmp_arg_choice(simplify, "simplify", c("preserve", "none"), call)
  map_keys <- zmp_arg_choice(map_keys, "map_keys", c("auto", "map", "string"), call)
  ext <- zmp_arg_choice(ext, "ext", c("convert", "keep"), call)
  big_integers <- zmp_arg_choice(big_integers, "big_integers",
                                 c("bigint", "double", "error"), call)
  zmp_arg_flag(duplicate_keys, "duplicate_keys", call)
  zmp_arg_limits(max_depth, 1, max_items, call)
  list(codes = as.integer(c(zmp_mode[["stream"]], duplicate_keys, max_depth, simplify,
                            map_keys, big_integers, ext)),
       max_items = as.numeric(max_items),
       handlers = zmp_arg_handlers(ext_handlers, call))
}
