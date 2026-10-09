# Decode MessagePack

Turns MessagePack bytes into ordinary R values. The whole input is
checked first – well-formedness, validity, duplicate keys and the
limits, exactly as
[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md)
does – and nothing is built until that check passes, so a length or
count in a head cannot make R allocate for data the input does not hold.

## Usage

``` r
msgpack_decode(
  x,
  simplify = c("preserve", "none"),
  map_keys = c("auto", "map", "string"),
  big_integers = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06
)

msgpack_decode_seq(
  x,
  simplify = c("preserve", "none"),
  map_keys = c("auto", "map", "string"),
  big_integers = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06
)
```

## Arguments

- x:

  A raw vector holding exactly one MessagePack object
  (`msgpack_decode()`), or zero or more objects back to back
  (`msgpack_decode_seq()`).

- simplify:

  `"preserve"` simplifies arrays whose elements agree to atomic vectors;
  `"none"` makes every array a list.

- map_keys:

  `"auto"` gives a named list when every key is a non-empty, unique
  `str`, and a `msgpack_map` otherwise. `"map"` always gives a
  `msgpack_map`. `"string"` always gives a named list, naming each entry
  by its `str` key, or by a text rendering of any other key (`1`, `1.0`,
  `nil`, `h'00ff'`, `ext(5, h'01')`, `[1, "a"]`); it is lossy, and
  refuses a map whose keys collide once named.

- big_integers:

  What to do with an integer beyond 2^53, which a double cannot hold
  exactly: `"bigint"` returns a `msgpack_bigint`, `"double"` the nearest
  double, and `"error"` refuses the input.

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

The decoded value; for `msgpack_decode_seq()`, a list with one element
per object.

## MessagePack to R

|  |  |
|----|----|
| MessagePack | R |
| every integer form | `integer` if it fits, else `double` up to 2^53, else by `big_integers` |
| `float 32`, `float 64` | `double`, exactly |
| `true`, `false` | `logical` |
| `nil` | `NULL`, or `NA` inside an atomic vector |
| `bin 8/16/32` | `raw` |
| `str` (fixstr, `str 8/16/32`) | `character`, UTF-8 |
| array | atomic vector when the elements agree, else `list` |
| map with non-empty, unique `str` keys | named `list` |
| any other map | `msgpack_map` (by `map_keys`) |
| ext | `msgpack_ext` |

An array simplifies to an atomic vector only when its elements agree:
integers and floats combine to the wider; booleans stay logical, and
text stays text; wide integers and integer-valued numbers combine to
`msgpack_bigint`. `nil` joins any of them as `NA`. Anything else – raw
vectors, nested arrays and maps, exts, booleans with numbers, a mixture
– is a list. `[]` is `logical(0)`.

A one-element array that simplifies is marked with
[`I()`](https://rdrr.io/r/base/AsIs.html), so that the encoder writes it
back as an array rather than a single value.

A `str` holding U+0000 cannot be an R string and is
`zumsgpack_unrepresentable`.

## See also

[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md),
[`msgpack_read()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read.md),
[msgpack-values](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md),
[zumsgpack-conditions](https://pedrobtz.github.io/zumsgpack/reference/zumsgpack-conditions.md).

## Examples

``` r
msgpack_decode(as.raw(c(0x93, 0x01, 0x02, 0x03)))        # [1, 2, 3]
#> [1] 1 2 3
msgpack_decode(as.raw(c(0x81, 0xa1, 0x61, 0xc3)))        # {"a": true}
#> $a
#> [1] TRUE
#> 

# Integer keys, so a msgpack_map.
msgpack_decode(as.raw(c(0x81, 0x01, 0xd0, 0xf9)))        # {1: -7}
#> <msgpack_map: 1 entry>
#> [[1]]
#> [1] -7

msgpack_decode_seq(as.raw(c(0x01, 0xa1, 0x61)))          # 1, then "a"
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
#> 
```
