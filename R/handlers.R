# ext_handlers as C reads it: NULL, or list(types, functions in the same
# order, the namespace zmp_run_handler() is called from). Names are checked
# by their digits, not only as numbers: "+5", "05" and "5.0" all parse as 5
# and would otherwise name the same handler (zucbor Stage 10).
zmp_arg_handlers <- function(h, call = NULL) {
  if (is.null(h)) return(NULL)
  bad <- function(why) {
    zmp_invalid_argument("ext_handlers", paste0(
      "`ext_handlers` must be NULL or a list of functions named by extension type: ",
      why, "."), call)
  }
  if (!is.list(h) || is.object(h)) bad("it is not a plain list")
  if (length(h) == 0L) return(NULL)
  nm <- names(h)
  if (is.null(nm) || anyNA(nm) || !all(grepl("^(0|-?[1-9][0-9]{0,2})$", nm))) {
    bad("every name must be a type from \"-128\" to \"127\", such as \"5\"")
  }
  types <- as.integer(nm)
  if (any(types < -128L | types > 127L)) bad("types run from -128 to 127")
  if (anyDuplicated(types)) bad("a type is named twice")
  if (!all(vapply(h, is.function, logical(1L)))) bad("every element must be a function")
  list(types, unname(h), topenv())
}

# Called from C for each ext with a handler (src/zmp_ext.c, run_handler).
zmp_run_handler <- function(handler, data, type, call) {
  tryCatch(handler(data), error = function(e) {
    zmp_abort("zumsgpack_handler_error",
              paste0("the handler for ext type ", type, " failed: ", conditionMessage(e)),
              type = type, parent = e, call = call)
  })
}
