#' Teach msgpack_encode() a class
#'
#' `msgpack_encode()` calls `as_msgpack()` on any object whose class it does
#' not know, and encodes what the method returns. A method returns
#' something zumsgpack can encode: often a [msgpack_ext()] carrying the
#' value's bytes under an extension type of the caller's choosing, or a
#' plain list or vector. The default method returns `x` unchanged, so an
#' object without a method is encoded as its underlying type.
#'
#' The method's result is not passed to `as_msgpack()` again, though its
#' elements are, so a chain of methods cannot loop; a method that returns
#' an object of the class it was given is an error. Classes the encoder
#' writes itself (`POSIXct`, `Date`, `factor`, `data.frame` and the
#' zumsgpack value classes) never reach `as_msgpack()`. [I()] alone does not
#' count as a class.
#'
#' An error in a method propagates unchanged: a method runs on the
#' caller's own data, not on input. The decoding half is
#' `msgpack_decode(ext_handlers = )`.
#'
#' @param x An object of a class `msgpack_encode()` does not know.
#' @param ... For methods.
#' @return Something `msgpack_encode()` can encode.
#' @export
#' @examples
#' # A class of our own, sent as extension type 7.
#' point <- function(x, y) structure(list(x = x, y = y), class = "point")
#' as_msgpack.point <- function(x, ...) {
#'   msgpack_ext(7, writeBin(c(x$x, x$y), raw(), size = 4, endian = "big"))
#' }
#' registerS3method("as_msgpack", "point", as_msgpack.point)
#'
#' bytes <- msgpack_encode(list(origin = point(0, 0)))
#' msgpack_decode(bytes, ext_handlers = list(
#'   "7" = function(data) {
#'     v <- readBin(data, "double", n = 2, size = 4, endian = "big")
#'     point(v[1], v[2])
#'   }
#' ))
as_msgpack <- function(x, ...) UseMethod("as_msgpack")

#' @rdname as_msgpack
#' @export
as_msgpack.default <- function(x, ...) x
