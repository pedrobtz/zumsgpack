# MessagePack values without a native R type

Constructors for the three values the decoder returns when R has no
faithful type of its own. The encoder accepts them too, to write those
values back.

## Usage

``` r
msgpack_map(keys = list(), values = list())

msgpack_ext(type, data = raw())

msgpack_bigint(x)
```

## Arguments

- keys, values:

  Lists (or vectors, taken element by element) of equal length.

- type:

  A whole number from -128 to 127.

- data:

  A raw vector.

- x:

  Decimal strings or whole numbers.

## Value

An object of class `msgpack_map`, `msgpack_ext` or `msgpack_bigint`.

## Details

- `msgpack_map()` is a map whose keys are not all non-empty, unique
  `str`s: integer keys, for example. `keys` and `values` are lists of
  equal length, in order.

- `msgpack_ext()` is an extension object: `type`, a whole number from
  -128 to 127, and `data`, its payload as a raw vector. Type -1 is the
  timestamp; the other negative types are reserved by the specification.

- `msgpack_bigint()` is an integer outside what a double holds exactly,
  stored as canonical decimal text. It accepts decimal strings, or whole
  numbers within 2^53. MessagePack holds integers from -2^63 to 2^64 -
  1, and the encoder refuses one outside that range.

## Examples

``` r
msgpack_map(list(1L, 3L), list(-7L, "ES256"))
#> <msgpack_map: 2 entries>
#> [[1]]
#> [1] -7
#> [[3]]
#> [1] "ES256"
msgpack_ext(5, as.raw(c(0x01, 0x02)))
#> <msgpack_ext type 5, 2 bytes>
#> [1] 01 02
msgpack_bigint("18446744073709551615")
#> <msgpack_bigint[1]>
#> [1] 18446744073709551615
```
