#' Read MessagePack from a file or connection
#'
#' Reads the input and decodes it as [msgpack_decode()] would. At most
#' `max_size + 1` bytes are ever read, so an oversized file or an endless
#' connection fails with `zumsgpack_size_limit` rather than exhausting
#' memory.
#'
#' A string with an `http`, `https`, `ftp`, `ftps` or `file` scheme is read
#' with [url()], any other string as a file path. A connection that is not
#' open is opened in `"rb"` mode and closed afterwards; an open one must be
#' binary, is read from its current position, and is left open.
#'
#' @param file A file path, a URL, or a connection.
#' @param ... Arguments passed on to [msgpack_decode()].
#' @inheritParams msgpack_decode
#' @return As [msgpack_decode()].
#' @export
#' @examples
#' path <- tempfile(fileext = ".msgpack")
#' writeBin(as.raw(c(0x81, 0xa1, 0x61, 0x01)), path)
#' msgpack_read(path)
#' unlink(path)
msgpack_read <- function(file, ..., max_size = 64 * 1024^2) {
  call <- sys.call()
  msgpack_decode(zmp_read_bounded(file, max_size, call), ..., max_size = max_size)
}

# Reads at most max_size + 1 bytes: one past the limit is enough to know the
# input is too big, and nothing more is ever held (design section 10).
zmp_read_bounded <- function(file, max_size, call) {
  zmp_arg_limit(max_size, "max_size", 2^53, allow_inf = TRUE, call)
  input <- zu_open_input(file, what = "file", prefix = "zumsgpack",
                         abort = function(arg, message) zmp_invalid_argument(arg, message, call))
  if (input$close) on.exit(close(input$con), add = TRUE)
  chunk <- 65536L
  chunks <- list()
  total <- 0
  repeat {
    want <- if (is.finite(max_size)) min(chunk, max_size + 1 - total) else chunk
    b <- tryCatch(readBin(input$con, "raw", n = want),
                  error = function(e) zmp_abort("zumsgpack_io_error",
                    paste0("could not read input: ", conditionMessage(e)), call = call))
    if (length(b) == 0L) break
    chunks[[length(chunks) + 1L]] <- b
    total <- total + length(b)
    if (total > max_size) zmp_raise_fault(zmp_size_fault(max_size), call)
  }
  if (length(chunks) == 0L) raw() else unlist(chunks, use.names = FALSE)
}
