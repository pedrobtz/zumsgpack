# Encode R values as MessagePack

Turns an R value into MessagePack bytes, deterministically: identical R
objects give identical bytes in every session and on every platform.

## Usage

``` r
msgpack_encode(
  x,
  auto_unbox = TRUE,
  max_depth = 256L,
  floats = c("double", "shortest")
)

msgpack_encode_seq(
  x,
  auto_unbox = TRUE,
  max_depth = 256L,
  floats = c("double", "shortest")
)
```

## Arguments

- x:

  An R value. For `msgpack_encode_seq()`, a list whose elements are
  encoded one after another, as objects back to back.

- auto_unbox:

  If `TRUE`, a length-one atomic vector is a single value; if `FALSE`,
  it is an array of one. Names used as map keys are always single
  strings.

- max_depth:

  Deepest nesting to write, counting arrays, maps and exts as
  [`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
  does, so its output always decodes at the same `max_depth`.

- floats:

  `"double"` writes every non-integral double as `float 64`;
  `"shortest"` writes `float 32` when it holds the value exactly. Off by
  default, since some decoders widen a `float 32` through a type that
  changes the value their users see.

## Value

A raw vector.

## R to MessagePack

|  |  |
|----|----|
| R | MessagePack |
| `NULL`, `NA` of any type | `nil` |
| `TRUE`, `FALSE` | `true`, `false` |
| `integer` | the smallest integer form |
| `double`, whole, within -2^63 .. 2^64 - 1, not `-0` | the smallest integer form |
| any other `double`, including `NaN`, `Inf` and `-0` | `float 64` (see `floats`) |
| `character` | `str`, UTF-8 |
| `raw` | one `bin`, whatever its length |
| `factor` | its labels, as `str` |
| `msgpack_bigint` | the integer form if within -2^63 .. 2^64 - 1, else refused |
| `msgpack_map`, `msgpack_ext` | a map, an ext |
| unnamed list or vector | array |
| fully named list or vector | map with `str` keys |

A length-one atomic vector is a single value, not an array, unless it is
wrapped in [`I()`](https://rdrr.io/r/base/AsIs.html) or
`auto_unbox = FALSE`. A matrix is a flat array in column-major order.

Whole doubles become integers because R has no integer literal: `-7`
written in R is a double, and as a float it would be a different value
from the integer a protocol expects. So `1L` and `1` encode identically.

These have no MessagePack form and raise `zumsgpack_unsupported_type`:
complex numbers, functions, environments, external pointers, S4 objects
and `POSIXlt` (convert with
[`as.POSIXct()`](https://rdrr.io/r/base/as.POSIXlt.html)). Names that
are partly missing, `NA` or empty are `zumsgpack_invalid_argument`, and
two keys that encode identically are `zumsgpack_duplicate_key`.

## Deterministic encoding

MessagePack's specification says only that an encoder should use the
smallest integer form. zumsgpack always writes:

1.  the smallest form of every integer and of every length and count;

2.  `float 64` for every non-integral double, or with
    `floats = "shortest"` a `float 32` when it holds the value exactly;
    every `NaN` as one canonical quiet NaN, since R's `NaN` bits differ
    between platforms;

3.  `str` for text and `bin` for bytes, never the pre-2013 `raw`;

4.  map entries sorted by the bytewise order of their encoded keys, with
    no duplicate keys.

These are zumsgpack's rules, not the format's: another decoder is not
entitled to expect them, and
[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md)
does not check for them. They make the output byte-identical across
calls, sessions and platforms, which a signature or a content hash over
the bytes needs.

## Conversions that do not round-trip

Decoding what `msgpack_encode()` wrote gives back the value, except
that: `NA` comes back as `NULL`, or `NA` of the vector's type; a whole
double comes back as an integer; `list(1L)` and `1L` both encode as `1`;
a `NaN` payload is not kept; and a `float 32` input re-encodes as
`float 64` unless `floats = "shortest"`.

## See also

[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md),
[msgpack-values](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md).

## Examples

``` r
msgpack_encode(list(a = 1, b = c(2, 3)))
#> [1] 82 a1 61 01 a1 62 92 02 03
msgpack_encode(c(1.5, NaN, Inf))
#>  [1] 93 cb 3f f8 00 00 00 00 00 00 cb 7f f8 00 00 00 00 00 00 cb 7f f0 00 00 00
#> [26] 00 00 00
msgpack_encode(0.5, floats = "shortest")
#> [1] ca 3f 00 00 00

# Integer keys need msgpack_map().
msgpack_encode(msgpack_map(list(1L), list(-7)))
#> [1] 81 01 f9

# Deterministic: map entries are sorted by their encoded keys.
identical(msgpack_encode(list(b = 1, a = 2)), msgpack_encode(list(a = 2, b = 1)))
#> [1] TRUE

msgpack_encode_seq(list(1, "a", TRUE))
#> [1] 01 a1 61 c3
```
