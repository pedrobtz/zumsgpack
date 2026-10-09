# Validate MessagePack

Checks that `x` holds well-formed, valid MessagePack within the given
limits, without building any R value. This is exactly the check the
decoders run before they build anything, so they agree about the bytes;
they disagree only where the bytes are valid but R cannot hold the
value, such as a `str` containing U+0000.

## Usage

``` r
msgpack_validate(
  x,
  sequence = FALSE,
  duplicate_keys = FALSE,
  max_depth = 256L,
  max_size = 64 * 1024^2,
  max_items = 1e+06,
  error = FALSE
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

- error:

  If `TRUE`, raise the classed condition describing the fault instead of
  returning `FALSE`; see
  [zumsgpack-conditions](https://pedrobtz.github.io/zumsgpack/reference/zumsgpack-conditions.md).

## Value

`TRUE` or `FALSE`; with `error = TRUE`, `TRUE` invisibly or an error.

## Details

The check covers well-formedness (every head, length and count against
the bytes there are, and the reserved byte `0xc1`), UTF-8 in every
`str`, the three legal layouts of the timestamp extension (type -1),
duplicate map keys, and the limits. Keys are compared by value: the
integer 1 in one byte and in `uint 16` is the same key, and so is a
`float 32` 1.0 and a `float 64` 1.0; the integer 1 and the float 1.0 are
different keys, as are a `str` and a `bin` with the same bytes. An array
or map used as a key is compared by its encoded bytes.

MessagePack defines no canonical form, so there is no `deterministic`
argument: zumsgpack's encoder follows rules of its own (see
`msgpack_encode()`), which a decoder is not entitled to expect.

## Examples

``` r
msgpack_validate(as.raw(c(0x93, 0x01, 0x02, 0x03)))   # [1, 2, 3]
#> [1] TRUE
msgpack_validate(as.raw(c(0x93, 0x01, 0x02)))         # truncated
#> [1] FALSE
msgpack_validate(as.raw(c(0x82, 0x01, 0x00, 0xcc, 0x01, 0x00)))  # {1: 0, 1: 0}
#> [1] FALSE
msgpack_validate(as.raw(c(0x01, 0x02)), sequence = TRUE)
#> [1] TRUE
```
