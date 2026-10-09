# Getting started with zumsgpack

``` r

library(zumsgpack)
```

## Encoding and decoding

[`msgpack_encode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
turns an R value into MessagePack bytes and
[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
turns them back:

``` r

x <- list(name = "sensor-1", values = c(20.5, 21.25), ok = TRUE)
b <- msgpack_encode(x)
b
#>  [1] 83 a2 6f 6b c3 a4 6e 61 6d 65 a8 73 65 6e 73 6f 72 2d 31 a6 76 61 6c 75 65
#> [26] 73 92 cb 40 34 80 00 00 00 00 00 cb 40 35 40 00 00 00 00 00
str(msgpack_decode(b))
#> List of 3
#>  $ ok    : logi TRUE
#>  $ name  : chr "sensor-1"
#>  $ values: num [1:2] 20.5 21.2
```

Arrays whose elements agree become atomic vectors; anything else is a
list. Maps with string keys become named lists; maps with other keys
become a `msgpack_map`, which keeps the keys as they were:

``` r

msgpack_decode(msgpack_encode(msgpack_map(list(1L, 2L), list("one", "two"))))
#> <msgpack_map: 2 entries>
#> [[1]]
#> [1] "one"
#> [[2]]
#> [1] "two"
```

## The same bytes, every time

Encoding is deterministic: the smallest integer forms, sorted map keys,
one form for every value. Identical R values give identical bytes on
every platform, which a hash or a signature over the bytes needs:

``` r

identical(msgpack_encode(list(b = 1, a = 2)), msgpack_encode(list(a = 2, b = 1)))
#> [1] TRUE
```

## Timestamps and extension types

The timestamp extension becomes a `POSIXct` in UTC, and back:

``` r

when <- as.POSIXct("2026-10-09 12:00:00.25", tz = "UTC")
msgpack_decode(msgpack_encode(when))
#> [1] "2026-10-09 12:00:00 UTC"
```

Other extension types come back as `msgpack_ext`, unless you give them a
handler; see
[`vignette("untrusted")`](https://pedrobtz.github.io/zumsgpack/articles/untrusted.md)
for decoding input you do not control, and the examples article on the
package site for recipes.

## Files, streams and tables

``` r

path <- tempfile(fileext = ".msgpack")
writeBin(msgpack_encode(list(list(id = 1L, v = "a"), list(id = 2L, v = "b"))), path)
msgpack_read(path, data_frame = TRUE)
#>   v id
#> 1 a  1
#> 2 b  2
unlink(path)
```
