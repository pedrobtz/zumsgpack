# The condition hierarchy of design section 11. The class is the contract:
# callers branch on it and on the fields below, never on the message.

#' Conditions raised by zumsgpack
#'
#' Every error zumsgpack raises carries a condition class, so it can be
#' caught by kind rather than by matching the message, which may change.
#' Every class below inherits from `zumsgpack_error`.
#'
#' \describe{
#'   \item{`zumsgpack_invalid_argument`}{An argument was unusable: an input
#'     that is not a raw vector, a flag that is not `TRUE` or `FALSE`, or a
#'     limit that is not a positive whole number within its range.}
#'   \item{`zumsgpack_parse_error`}{The input is not well-formed
#'     MessagePack: it ends early (a head, a length or a count claims more
#'     bytes than there are), uses the reserved byte `0xc1`, or has bytes
#'     after the object.}
#'   \item{`zumsgpack_invalid_error`}{The input is well-formed but not
#'     valid: a `str` that is not UTF-8, or a timestamp (ext type -1) whose
#'     payload is not 4, 8 or 12 bytes or whose nanoseconds exceed
#'     999,999,999.}
#'   \item{`zumsgpack_duplicate_key`}{A map has the same key twice and
#'     `duplicate_keys = FALSE`. Keys are compared by value.}
#'   \item{`zumsgpack_unrepresentable`}{The input is valid but holds a value
#'     R cannot, such as a `str` containing U+0000.}
#'   \item{`zumsgpack_unsupported_type`}{An R value with no MessagePack
#'     form was given to the encoder.}
#'   \item{`zumsgpack_handler_error`}{An extension handler raised an error.}
#'   \item{`zumsgpack_limit_error`}{A limit was reached. The subclasses
#'     `zumsgpack_depth_limit`, `zumsgpack_size_limit`,
#'     `zumsgpack_item_limit` and `zumsgpack_cell_limit` name which one.}
#'   \item{`zumsgpack_io_error`}{Reading the input failed.}
#' }
#'
#' A condition raised while checking input carries `offset`, the 0-based
#' byte offset of the object at fault, and `status`, the name of the
#' underlying status, such as `"ZMP_ERR_TRUNCATED"`. It is there for
#' diagnostics: branch on the class, not on it. A limit error also carries
#' `limit`, the argument's name, such as `"max_depth"`, and `limit_value`. A
#' `zumsgpack_invalid_argument` condition carries `arg`, the argument at
#' fault.
#'
#' @name zumsgpack-conditions
#' @examples
#' tryCatch(
#'   msgpack_validate(as.raw(c(0x92, 0x01)), error = TRUE),
#'   zumsgpack_parse_error = function(e) e$offset
#' )
NULL

zmp_abort <- function(class, message, ..., call = NULL) {
  stop(structure(
    class = c(class, "zumsgpack_error", "error", "condition"),
    list(message = message, call = call, ...)
  ))
}

zmp_invalid_argument <- function(arg, message, call = NULL) {
  zmp_abort("zumsgpack_invalid_argument", message, arg = arg, call = call)
}

# Status name -> class vector, by the status's name. test-conditions.R checks
# every name C can report is here.
zmp_status_class <- local({
  parse <- "zumsgpack_parse_error"
  invalid <- "zumsgpack_invalid_error"
  dup <- "zumsgpack_duplicate_key"
  unrep <- "zumsgpack_unrepresentable"
  list(
    ZMP_ERR_TRUNCATED = parse,
    ZMP_ERR_RESERVED = parse,
    ZMP_ERR_TRAILING = parse,
    ZMP_ERR_INVALID_UTF8 = invalid,
    ZMP_ERR_TIMESTAMP_LENGTH = invalid,
    ZMP_ERR_TIMESTAMP_NANOS = invalid,
    ZMP_ERR_DUPLICATE_KEY = dup,
    ZMP_ERR_KEY_COLLISION = dup,
    ZMP_ERR_DEPTH_LIMIT = c("zumsgpack_depth_limit", "zumsgpack_limit_error"),
    ZMP_ERR_ITEM_LIMIT = c("zumsgpack_item_limit", "zumsgpack_limit_error"),
    ZMP_ERR_SIZE_LIMIT = c("zumsgpack_size_limit", "zumsgpack_limit_error"),
    ZMP_ERR_CELL_LIMIT = c("zumsgpack_cell_limit", "zumsgpack_limit_error"),
    ZMP_ERR_NUL_IN_STR = unrep,
    ZMP_ERR_STRING_TOO_LONG = unrep,
    ZMP_ERR_BIG_INTEGER = unrep,
    ZMP_ERR_UNREPRESENTABLE = unrep,
    ZMP_ERR_UNSUPPORTED_TYPE = "zumsgpack_unsupported_type",
    ZMP_ERR_INVALID_VALUE = "zumsgpack_invalid_argument"
  )
})

zmp_fault_message <- function(fault, class) {
  at <- if (is.na(fault$offset)) "" else
    paste0(" at byte ", format(fault$offset, scientific = FALSE))
  detail <- if (is.na(fault$detail)) "" else paste0(": ", fault$detail)
  switch(class[1L],
    zumsgpack_parse_error = paste0("MessagePack parse error", at, detail),
    zumsgpack_invalid_error = paste0("invalid MessagePack", at, detail),
    zumsgpack_duplicate_key = paste0("duplicate map key", at,
      if (identical(fault$status, "ZMP_ERR_KEY_COLLISION"))
        " once keys are converted to names" else ""),
    zumsgpack_unrepresentable = paste0("MessagePack value R cannot hold", at, detail),
    zumsgpack_unsupported_type = paste0("cannot encode `x`", detail),
    zumsgpack_invalid_argument = paste0("cannot encode `x`", detail),
    zumsgpack_depth_limit = paste0("MessagePack nested deeper than max_depth = ",
                                   fault$limit_value, at),
    zumsgpack_item_limit = paste0("MessagePack has more than max_items = ",
      format(fault$limit_value, scientific = FALSE), " objects", at),
    zumsgpack_size_limit = paste0("MessagePack input is larger than max_size = ",
      format(fault$limit_value, scientific = FALSE), " bytes"),
    zumsgpack_cell_limit = paste0("data frame would have more than max_cells = ",
      format(fault$limit_value, scientific = FALSE), " cells", at),
    paste0("MessagePack error", at, detail)
  )
}

# Raises the condition for a fault returned by C.
zmp_raise_fault <- function(fault, call = NULL) {
  class <- zmp_status_class[[fault$status]]
  if (is.null(class)) class <- character()
  # Built directly, not through do.call(): that would evaluate `call`, the
  # user's own expression, a second time (zucbor Stage 4).
  cond <- list(message = zmp_fault_message(fault, class), call = call,
               offset = fault$offset, status = fault$status,
               limit = fault$limit, limit_value = fault$limit_value)
  if ("zumsgpack_invalid_argument" %in% class) cond$arg <- "x"
  stop(structure(class = c(class, "zumsgpack_error", "error", "condition"), cond))
}

zmp_size_fault <- function(max_size) {
  structure(list(
    status = "ZMP_ERR_SIZE_LIMIT", detail = NA_character_, offset = NA_real_,
    limit = "max_size", limit_value = as.numeric(max_size)
  ), class = "zmp_fault")
}
