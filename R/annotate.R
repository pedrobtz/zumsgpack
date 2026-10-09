#' Annotated hex dump of MessagePack
#'
#' Shows where every byte of `x` went: one line per head, with its offset,
#' its bytes in hex and what it is (`fixmap(2)`, `fixstr(1) "a"`,
#' `uint 16 300`, `fixext 4 type -1, timestamp 32: 1514862245 s`),
#' indented by depth. The payload of a `str`, `bin` or ext follows its head
#' in rows of 16 bytes, so every byte of the input appears in the hex column
#' exactly once; previews stop at 32 bytes. For reviewing a message byte by
#' byte, such as one whose signature covers its bytes.
#'
#' The input is checked first, exactly as [msgpack_validate()] checks it,
#' and annotated only if it passes.
#'
#' @inheritParams msgpack_validate
#' @return A character vector of class `msgpack_annotation`, one element per
#'   line; it prints as the lines. Offsets are decimal and 0-based, as
#'   zumsgpack's conditions report them.
#' @export
#' @examples
#' msgpack_annotate(msgpack_encode(list(a = 1L, b = c("x", "y"))))
#' msgpack_annotate(as.raw(c(0xd6, 0xff, 0x5a, 0x4a, 0xf6, 0xa5)))
msgpack_annotate <- function(x, sequence = FALSE, duplicate_keys = FALSE,
                             max_depth = 256L, max_size = 64 * 1024^2,
                             max_items = 1e6) {
  call <- sys.call()
  zmp_arg_flag(sequence, "sequence", call)
  mode <- if (sequence) zmp_mode[["seq"]] else zmp_mode[["one"]]
  fault <- zmp_check_input(x, mode, duplicate_keys, max_depth, max_size,
                           max_items, call)
  if (!is.null(fault)) zmp_raise_fault(fault, call)
  a <- .Call(zmp_annotate_raw, x, sequence, as.integer(max_depth))
  if (!length(a$offset)) return(structure(character(), class = "msgpack_annotation"))
  off <- format(a$offset, scientific = FALSE, width = max(1L, nchar(format(max(a$offset), scientific = FALSE))))
  hex <- formatC(a$hex, width = -max(nchar(a$hex)), flag = "-")
  indent <- strrep("  ", pmin(a$depth, 16L))
  lines <- paste0(off, "  ", hex, "  ", indent, a$text)
  structure(sub("\\s+$", "", lines), class = "msgpack_annotation")
}

#' @export
print.msgpack_annotation <- function(x, ...) {
  writeLines(unclass(x))
  invisible(x)
}

#' @export
format.msgpack_annotation <- function(x, ...) unclass(x)
