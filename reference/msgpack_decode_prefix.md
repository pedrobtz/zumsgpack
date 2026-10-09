# Decode the MessagePack object at the start of a raw vector

Decodes the one object that `x` starts with and reports how many bytes
it used, for MessagePack inside binary framing: a payload after a fixed
header, or the first message of a buffer that may hold more. The object
is checked and decoded exactly as by
[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md),
with the same arguments; what follows it is not read at all.

## Usage

``` r
msgpack_decode_prefix(
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

  A raw vector starting with a MessagePack object.

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

A list: `value`, the decoded object, and `consumed`, the number of bytes
it took, a double.

## Details

That also means nothing about the rest is known: it may be more
MessagePack, the next field of the framing, or garbage. It is the
caller's to make sense of, as `x[-seq_len(consumed)]`.

`max_size` applies to `x` as a whole, since all of it is in memory
already. An empty `x` is `zumsgpack_parse_error`, as for
[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md);
so is an object cut short by the end of `x`.

## See also

[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
for one object and nothing else,
[`msgpack_decode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
for objects all the way to the end, and
[`msgpack_read_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read_seq.md)
for a stream.

## Examples

``` r
# [1, 2] followed by four bytes of something else.
x <- as.raw(c(0x92, 0x01, 0x02, 0xde, 0xad, 0xbe, 0xef))
r <- msgpack_decode_prefix(x)
r$value
#> [1] 1 2
x[-seq_len(r$consumed)]
#> [1] de ad be ef
```
