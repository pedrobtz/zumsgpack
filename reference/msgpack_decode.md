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
  ext = c("convert", "keep"),
  big_integers = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06,
  ext_handlers = NULL,
  data_frame = FALSE,
  max_cells = 1e+07
)

msgpack_decode_seq(
  x,
  simplify = c("preserve", "none"),
  map_keys = c("auto", "map", "string"),
  ext = c("convert", "keep"),
  big_integers = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06,
  ext_handlers = NULL,
  data_frame = FALSE,
  max_cells = 1e+07
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

- ext:

  `"convert"` turns timestamps (ext -1) into `POSIXct` and keeps other
  exts as `msgpack_ext`; `"keep"` makes every ext a `msgpack_ext`.

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

- ext_handlers:

  `NULL`, or a list of functions of one argument, named by extension
  type from `"-128"` to `"127"`, such as
  `list("5" = function(data) ...)`. See "Extension handlers".

- data_frame:

  If `TRUE`, an array whose every element is a map with non-empty `str`
  keys, none twice in one map, becomes a data frame: see "Data frames".

- max_cells:

  Most cells (rows times columns) a data frame may have, checked before
  it is allocated, or `Inf`.

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
| ext -1 (timestamp) | `POSIXct`, UTC |
| any other ext | `msgpack_ext`, or a handler's result |

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

The timestamp extension (type -1) has three layouts: `timestamp 32`
(seconds), `timestamp 64` (34-bit seconds, 30-bit nanoseconds) and
`timestamp 96` (64-bit signed seconds, 32-bit nanoseconds). A `POSIXct`
is a double, so nanoseconds are kept only to double precision, about
2^-22 s near 2026; a handler for `"-1"` can keep the fields exactly.

## Extension handlers

`ext_handlers` gives meaning to extension types zumsgpack does not
convert, or replaces the timestamp conversion. Each handler is called
with the ext's payload as a raw vector – an ext has no structure beyond
its bytes – and its result takes the ext's place:

    msgpack_decode(x, ext_handlers = list(
      "5"  = function(data) rawToChar(data),
      "-1" = function(data) data               # keep timestamps as bytes
    ))

A handler runs only once the whole input has been checked, so it never
sees a payload from an object with a bad length or a duplicate key. Its
result never joins an array's simplification: an array holding one is a
list. A handler applies whatever `ext` says. An error in a handler
becomes `zumsgpack_handler_error`, with the type as `type` and the
original condition as `parent`. A handler that calls `msgpack_decode()`
again, for MessagePack embedded in an ext, passes that call its own
limits.
[`as_msgpack()`](https://pedrobtz.github.io/zumsgpack/reference/as_msgpack.md)
is the encoding half.

## Data frames

With `data_frame = TRUE`, an array of maps – the usual way to send a
table, one map per row – becomes a data frame. Its columns are the union
of the keys, in the order they are first seen; a key a row lacks is
`NA`; and each column simplifies by the same rules as an array, so a
column of mixed kinds is a list column. Row names are not kept, since
the format has none. Rows that share no keys make a frame with as many
columns as rows, quadratic in the input, so the number of cells is
checked against `max_cells` before anything is allocated
(`zumsgpack_cell_limit`). Arrays of any other shape decode as without
the option, and so does an empty array.

## See also

[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md),
[`msgpack_read()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read.md),
[`msgpack_read_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read_seq.md),
[`msgpack_decode_prefix()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode_prefix.md),
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

# A timestamp, and the same bytes kept as an ext.
ts <- as.raw(c(0xd6, 0xff, 0x5a, 0x4a, 0xf6, 0xa5))
msgpack_decode(ts)
#> [1] "2018-01-02 03:04:05 UTC"
msgpack_decode(ts, ext = "keep")
#> <msgpack_ext type -1, 4 bytes>
#> [1] 5a 4a f6 a5
```
