# Teach msgpack_encode() a class

[`msgpack_encode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
calls `as_msgpack()` on any object whose class it does not know, and
encodes what the method returns. A method returns something zumsgpack
can encode: often a
[`msgpack_ext()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md)
carrying the value's bytes under an extension type of the caller's
choosing, or a plain list or vector. The default method returns `x`
unchanged, so an object without a method is encoded as its underlying
type.

## Usage

``` r
as_msgpack(x, ...)

# Default S3 method
as_msgpack(x, ...)
```

## Arguments

- x:

  An object of a class
  [`msgpack_encode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
  does not know.

- ...:

  For methods.

## Value

Something
[`msgpack_encode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
can encode.

## Details

The method's result is not passed to `as_msgpack()` again, though its
elements are, so a chain of methods cannot loop; a method that returns
an object of the class it was given is an error. Classes the encoder
writes itself (`POSIXct`, `Date`, `factor`, `data.frame` and the
zumsgpack value classes) never reach `as_msgpack()`.
[`I()`](https://rdrr.io/r/base/AsIs.html) alone does not count as a
class.

An error in a method propagates unchanged: a method runs on the caller's
own data, not on input. The decoding half is
`msgpack_decode(ext_handlers = )`.

## Examples

``` r
# A class of our own, sent as extension type 7.
point <- function(x, y) structure(list(x = x, y = y), class = "point")
as_msgpack.point <- function(x, ...) {
  msgpack_ext(7, writeBin(c(x$x, x$y), raw(), size = 4, endian = "big"))
}
registerS3method("as_msgpack", "point", as_msgpack.point)

bytes <- msgpack_encode(list(origin = point(0, 0)))
msgpack_decode(bytes, ext_handlers = list(
  "7" = function(data) {
    v <- readBin(data, "double", n = 2, size = 4, endian = "big")
    point(v[1], v[2])
  }
))
#> $origin
#> $x
#> [1] 0
#> 
#> $y
#> [1] 0
#> 
#> attr(,"class")
#> [1] "point"
#> 
```
