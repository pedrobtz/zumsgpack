# Annotated hex dump of MessagePack

Shows where every byte of `x` went: one line per head, with its offset,
its bytes in hex and what it is (`fixmap(2)`, `fixstr(1) "a"`,
`uint 16 300`, `fixext 4 type -1, timestamp 32: 1514862245 s`), indented
by depth. The payload of a `str`, `bin` or ext follows its head in rows
of 16 bytes, so every byte of the input appears in the hex column
exactly once; previews stop at 32 bytes. For reviewing a message byte by
byte, such as one whose signature covers its bytes.

## Usage

``` r
msgpack_annotate(
  x,
  sequence = FALSE,
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06
)
```

## Arguments

- x:

  A raw vector.

- sequence:

  If `TRUE`, `x` is zero or more objects back to back; if `FALSE`, it
  must be exactly one object.

- duplicate_keys:

  If `FALSE` (the default), a map with the same key twice is invalid.

- max_depth:

  Deepest nesting allowed, counting arrays, maps and extension objects.
  At most `zumsgpack_info()$max_depth_cap`.

- max_size:

  Largest input allowed, in bytes, or `Inf`.

- max_items:

  Most objects allowed, counting every array, map, key, value and
  element, or `Inf`.

## Value

A character vector of class `msgpack_annotation`, one element per line;
it prints as the lines. Offsets are decimal and 0-based, as zumsgpack's
conditions report them.

## Details

The input is checked first, exactly as
[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md)
checks it, and annotated only if it passes.

## Examples

``` r
msgpack_annotate(msgpack_encode(list(a = 1L, b = c("x", "y"))))
#>  0  82  fixmap(2)
#>  1  a1    fixstr(1) "a"
#>  2  61
#>  3  01    fixint 1
#>  4  a1    fixstr(1) "b"
#>  5  62
#>  6  92    fixarray(2)
#>  7  a1      fixstr(1) "x"
#>  8  78
#>  9  a1      fixstr(1) "y"
#> 10  79
msgpack_annotate(as.raw(c(0xd6, 0xff, 0x5a, 0x4a, 0xf6, 0xa5)))
#> 0  d6 ff        fixext 4 type -1, timestamp 32: 1514862245 s
#> 2  5a 4a f6 a5
```
