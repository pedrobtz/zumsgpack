# zumsgpack

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zumsgpack/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zumsgpack/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zumsgpack/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zumsgpack/actions/workflows/coverage.yaml)
<!-- badges: end -->

zumsgpack reads and writes [MessagePack](https://msgpack.org), the compact
binary format behind Redis modules, Fluentd, neovim's RPC and many
telemetry protocols, from R.

- **Untrusted input is checked whole before anything is built.** Every
  head, length and count is checked against the bytes there are, every
  string's UTF-8 and every timestamp's layout are verified, maps with the
  same key twice are refused, and size, depth and item limits apply, all
  before R allocates a thing. A five-byte header claiming four billion
  elements costs nothing.
- **Encoding is deterministic.** The smallest integer forms, sorted map
  keys and one form for every value: identical R values give identical
  bytes on every platform, which a hash or signature over the bytes needs.
- **The mapping round-trips.** Arrays become vectors when their elements
  agree and lists otherwise; timestamps become `POSIXct`; extension types
  get meaning through handlers and the `as_msgpack()` generic; arrays of
  records become data frames on request.

It follows [zucbor](https://github.com/pedrobtz/zucbor)'s design for CBOR,
so code written for one reads like code written for the other.

## Installation

``` r
# install.packages("pak")
pak::pak("pedrobtz/zumsgpack")
```

## Example

``` r
library(zumsgpack)

b <- msgpack_encode(list(name = "sensor-1", values = c(20.5, 21.25), ok = TRUE))
b
#>  [1] 83 a2 6f 6b c3 a4 6e 61 6d 65 a8 73 65 6e 73 6f 72 2d 31 a6 76 61 6c 75 65
#> [26] 73 92 cb 40 34 80 00 00 00 00 00 cb 40 35 40 00 00 00 00 00
# Map keys are sorted (shorter first), so the bytes never depend on the
# order the list was built in.
str(msgpack_decode(b))
#> List of 3
#>  $ ok    : logi TRUE
#>  $ name  : chr "sensor-1"
#>  $ values: num [1:2] 20.5 21.2
```

## The mapping, on one screen

| MessagePack | R |
|---|---|
| integer | `integer`, `double` up to 2^53, then `msgpack_bigint` |
| `float 32`, `float 64` | `double` |
| `true`, `false`, `nil` | `logical`; `NULL`, or `NA` in a vector |
| `str`, `bin` | `character`, `raw` |
| array | atomic vector when the elements agree, else `list` |
| map with string keys | named `list`; other maps `msgpack_map` |
| timestamp (ext -1) | `POSIXct`, UTC |
| other ext | `msgpack_ext`, or a handler's result |

## What it is not

zumsgpack does not invent a text notation for MessagePack (the format has
none), does not read the pre-2013 "raw" type as both text and bytes, and
has no schema language. Its deterministic encoding is its own: the
MessagePack specification defines no canonical form, so another decoder
is not entitled to expect one.

Compared with [RcppMsgPack](https://cran.r-project.org/package=RcppMsgPack):
zumsgpack checks input against limits before building anything, reads a
stream in memory bounded by its largest object, converts timestamps, and
needs no C++ runtime.
