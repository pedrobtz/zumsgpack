# Usage examples

This article walks through zumsgpack’s functions with small, runnable
examples: encoding and decoding, how R values map to MessagePack and
back, timestamps and extension types, files and streams, tables, and
what happens when the input is bad.

``` r

library(zumsgpack)
```

## Encode and decode

[`msgpack_encode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
turns an R value into a raw vector of MessagePack bytes, and
[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
turns bytes back into an R value.

``` r

b <- msgpack_encode(list(id = 7L, name = "sensor", values = c(1.5, 2.25)))
b
#>  [1] 83 a2 69 64 07 a4 6e 61 6d 65 a6 73 65 6e 73 6f 72 a6 76 61 6c 75 65 73 92
#> [26] cb 3f f8 00 00 00 00 00 00 cb 40 02 00 00 00 00 00 00
length(b)
#> [1] 43
str(msgpack_decode(b))
#> List of 3
#>  $ id    : int 7
#>  $ name  : chr "sensor"
#>  $ values: num [1:2] 1.5 2.25
```

Decoding needs exactly one object;
[`msgpack_decode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
reads zero or more objects written back to back, and
[`msgpack_encode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
writes them.

``` r

seq_bytes <- msgpack_encode_seq(list(1L, "two", TRUE))
seq_bytes
#> [1] 01 a3 74 77 6f c3
msgpack_decode_seq(seq_bytes)
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "two"
#> 
#> [[3]]
#> [1] TRUE
```

## Vectors, lists and missing values

An atomic vector is an array; a length-one vector is a single value
unless it is wrapped in [`I()`](https://rdrr.io/r/base/AsIs.html) or
`auto_unbox = FALSE`.

``` r

msgpack_encode(1:3)
#> [1] 93 01 02 03
msgpack_encode(5L)
#> [1] 05
msgpack_encode(I(5L))
#> [1] 91 05
msgpack_encode(5L, auto_unbox = FALSE)
#> [1] 91 05
```

On the way back, an array becomes an atomic vector when its elements
agree and a list otherwise. A one-element array comes back marked with
[`I()`](https://rdrr.io/r/base/AsIs.html), so that encoding it again
gives the same bytes.

``` r

msgpack_decode(msgpack_encode(list(1L, 2.5)))     # numbers combine
#> [1] 1.0 2.5
msgpack_decode(msgpack_encode(list(1L, "a")))     # mixed kinds: a list
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] "a"
str(msgpack_decode(msgpack_encode(I(5L))))     # an array of one, marked I()
#>  'AsIs' int 5
```

`NULL` and `NA` are both `nil`. Inside a vector, `nil` comes back as
`NA`; on its own, as `NULL`.

``` r

msgpack_encode(c(1L, NA, 3L))
#> [1] 93 01 c0 03
msgpack_decode(msgpack_encode(c(1L, NA, 3L)))
#> [1]  1 NA  3
msgpack_decode(msgpack_encode(NA))
#> NULL
```

Use `simplify = "none"` to get every array as a list.

``` r

msgpack_decode(msgpack_encode(1:3), simplify = "none")
#> [[1]]
#> [1] 1
#> 
#> [[2]]
#> [1] 2
#> 
#> [[3]]
#> [1] 3
```

## Maps

A fully named list or vector is a map with string keys, and a map whose
keys are all non-empty, unique strings comes back as a named list.

``` r

msgpack_decode(msgpack_encode(c(a = 1L, b = 2L)))
#> $a
#> [1] 1
#> 
#> $b
#> [1] 2
```

Map entries are written sorted by their encoded keys (shorter keys
first), so the same values always give the same bytes, whatever order
the list was built in:

``` r

identical(msgpack_encode(list(b = 1, a = 2)), msgpack_encode(list(a = 2, b = 1)))
#> [1] TRUE
```

Maps with other keys – integers, binary, nested values – are
`msgpack_map` objects, which keep the keys as they are. Build one with
[`msgpack_map()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md):

``` r

m <- msgpack_map(list(1L, 2L), list("one", "two"))
b <- msgpack_encode(m)
msgpack_decode(b)
#> <msgpack_map: 2 entries>
#> [[1]]
#> [1] "one"
#> [[2]]
#> [1] "two"
```

`map_keys` changes how maps are decoded: `"map"` always gives a
`msgpack_map`, and `"string"` always gives a named list, naming
non-string keys by a text rendering of them.

``` r

msgpack_decode(b, map_keys = "string")
#> $`1`
#> [1] "one"
#> 
#> $`2`
#> [1] "two"
msgpack_decode(msgpack_encode(list(a = 1L)), map_keys = "map")
#> <msgpack_map: 1 entry>
#> [[a]]
#> [1] 1
```

## Numbers

Integers come back as `integer` when R’s integer type holds them, as
`double` up to 2^53, and beyond that as `msgpack_bigint`, which keeps
the exact value as decimal text. `big_integers` chooses otherwise.

``` r

big <- msgpack_encode(msgpack_bigint("18446744073709551615"))   # 2^64 - 1
msgpack_decode(big)
#> <msgpack_bigint[1]>
#> [1] 18446744073709551615
msgpack_decode(big, big_integers = "double")
#> [1] 1.844674e+19
```

A whole double is written as an integer, since R has no integer literal:
`1` and `1L` encode the same. Other doubles are `float 64`; with
`floats = "shortest"`, a `float 32` when it holds the value exactly.

``` r

msgpack_encode(1)
#> [1] 01
msgpack_encode(0.5)
#> [1] cb 3f e0 00 00 00 00 00 00
msgpack_encode(0.5, floats = "shortest")
#> [1] ca 3f 00 00 00
```

## Strings and bytes

Character vectors are UTF-8 `str`; raw vectors are `bin`.

``` r

msgpack_encode("héllo")
#> [1] a6 68 c3 a9 6c 6c 6f
msgpack_decode(msgpack_encode(as.raw(c(0xde, 0xad, 0xbe, 0xef))))
#> [1] de ad be ef
```

## Timestamps and dates

`POSIXct` is written as MessagePack’s timestamp extension, in the
smallest of its three layouts, and comes back as a `POSIXct` in UTC. A
`Date` is a timestamp at midnight UTC.

``` r

when <- as.POSIXct("2026-10-09 12:30:00.25", tz = "UTC")
b <- msgpack_encode(when)
b
#>  [1] d7 ff 3b 9a ca 00 6a c8 de 48
format(msgpack_decode(b), "%Y-%m-%d %H:%M:%OS3 %Z")
#> [1] "2026-10-09 12:30:00.250 UTC"
msgpack_decode(msgpack_encode(as.Date("2026-10-09")))
#> [1] "2026-10-09 UTC"
```

`ext = "keep"` leaves timestamps as raw extension objects.

``` r

msgpack_decode(b, ext = "keep")
#> <msgpack_ext type -1, 8 bytes>
#> [1] 3b 9a ca 00 6a c8 de 48
```

## Extension types

An extension object is a type number and some bytes. Types without a
conversion come back as `msgpack_ext`, and
[`msgpack_ext()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md)
builds one.

``` r

e <- msgpack_ext(5, charToRaw("hi"))
msgpack_decode(msgpack_encode(e))
#> <msgpack_ext type 5, 2 bytes>
#> [1] 68 69
```

`ext_handlers` gives a type meaning on decode: each handler gets the
payload as a raw vector and returns any R value.

``` r

msgpack_decode(msgpack_encode(list(e, e)), ext_handlers = list("5" = rawToChar))
#> [[1]]
#> [1] "hi"
#> 
#> [[2]]
#> [1] "hi"
```

The encoding half is the
[`as_msgpack()`](https://pedrobtz.github.io/zumsgpack/reference/as_msgpack.md)
generic: a method for your class returns something zumsgpack can encode,
often a
[`msgpack_ext()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md).

``` r

point <- function(x, y) structure(list(x = x, y = y), class = "point")
as_msgpack.point <- function(x, ...) {
  msgpack_ext(7, writeBin(c(x$x, x$y), raw(), size = 4, endian = "big"))
}
registerS3method("as_msgpack", "point", as_msgpack.point)

# "tip" is decoded before "origin": map keys are written sorted, shorter first.
b <- msgpack_encode(list(origin = point(0, 0), tip = point(3, 4)))
str(msgpack_decode(b, ext_handlers = list("7" = function(data) {
  v <- readBin(data, "double", n = 2, size = 4, endian = "big")
  point(v[1], v[2])
})))
#> List of 2
#>  $ tip   :List of 2
#>   ..$ x: num 3
#>   ..$ y: num 4
#>   ..- attr(*, "class")= chr "point"
#>  $ origin:List of 2
#>   ..$ x: num 0
#>   ..$ y: num 0
#>   ..- attr(*, "class")= chr "point"
```

## Files and connections

[`msgpack_read()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read.md)
reads one object from a path, URL or connection, and reads at most
`max_size + 1` bytes, so an oversized file fails rather than filling
memory.

``` r

path <- tempfile(fileext = ".msgpack")
writeBin(msgpack_encode(list(a = 1L, b = "x")), path)
msgpack_read(path)
#> $a
#> [1] 1
#> 
#> $b
#> [1] "x"
```

[`msgpack_read_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read_seq.md)
reads objects written back to back. Without `each` it returns a list;
with `each`, every object is checked whole, decoded and passed to your
function as soon as it arrives, so memory is bounded by the largest
object rather than the whole stream.

``` r

writeBin(msgpack_encode_seq(lapply(1:5, function(i) list(seq = i, ok = i %% 2 == 1))), path)
msgpack_read_seq(path)[[2]]
#> $ok
#> [1] FALSE
#> 
#> $seq
#> [1] 2

ok <- 0
n <- msgpack_read_seq(path, each = function(m) if (m$ok) ok <<- ok + 1)
c(read = n, ok = ok)
#> read   ok 
#>    5    3
unlink(path)
```

## The object at the start of a buffer

When MessagePack sits inside other framing,
[`msgpack_decode_prefix()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode_prefix.md)
decodes the first object and reports how many bytes it used, without
reading what follows.

``` r

x <- c(msgpack_encode(1:2), as.raw(c(0xde, 0xad, 0xbe, 0xef)))
r <- msgpack_decode_prefix(x)
r$value
#> [1] 1 2
x[-seq_len(r$consumed)]
#> [1] de ad be ef
```

## Tables

`data_frame = TRUE` turns an array of records – one map per row – into a
data frame. A key a row lacks is `NA`, and a column of mixed kinds is a
list column. A data frame encodes as such an array.

``` r

df <- data.frame(id = 1:3, name = c("a", "b", NA), score = c(1.5, NA, 3))
b <- msgpack_encode(df)
msgpack_decode(b, data_frame = TRUE)
#>   id name score
#> 1  1    a   1.5
#> 2  2    b    NA
#> 3  3 <NA>   3.0
```

Columns come back in sorted key order, since map keys are sorted on
encode.

## Bad input

Input is checked whole before anything is built.
[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md)
runs just that check and says whether it passed.

``` r

msgpack_validate(msgpack_encode(1:3))
#> [1] TRUE
msgpack_validate(as.raw(c(0x93, 0x01, 0x02)))   # promises 3 elements, has 2
#> [1] FALSE
```

Every error is a classed condition inheriting `zumsgpack_error`, with
the byte offset of the fault, so it can be caught by kind.

``` r

tryCatch(
  msgpack_decode(as.raw(c(0x82, 0x01, 0xc0, 0x01, 0xc0))),   # {1: nil, 1: nil}
  zumsgpack_duplicate_key = function(e) conditionMessage(e)
)
#> [1] "duplicate map key at byte 3"
```

Limits bound what an input can cost: `max_size` (bytes), `max_depth`
(nesting), `max_items` (objects) and, for data frames, `max_cells`.

``` r

deep <- c(rep(as.raw(0x91), 300), as.raw(0xc0))   # 300 nested arrays
tryCatch(msgpack_decode(deep), zumsgpack_depth_limit = function(e) e$limit_value)
#> [1] 256
msgpack_decode(deep, max_depth = 300L) |> class()
#> [1] "list"
```

See
[`vignette("untrusted")`](https://pedrobtz.github.io/zumsgpack/articles/untrusted.md)
for more on decoding input you do not control.

## Looking at the bytes

[`msgpack_annotate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_annotate.md)
prints an annotated hex dump: each head’s offset, its bytes, and what it
is, indented by depth.

``` r

msgpack_annotate(msgpack_encode(list(id = 7L, tags = c("a", "b"), when = when)))
#>  0  83                       fixmap(3)
#>  1  a2                         fixstr(2) "id"
#>  2  69 64
#>  4  07                         fixint 7
#>  5  a4                         fixstr(4) "tags"
#>  6  74 61 67 73
#> 10  92                         fixarray(2)
#> 11  a1                           fixstr(1) "a"
#> 12  61
#> 13  a1                           fixstr(1) "b"
#> 14  62
#> 15  a4                         fixstr(4) "when"
#> 16  77 68 65 6e
#> 20  d7 ff                      fixext 8 type -1, timestamp 64: 1791549000 s 250000000 ns
#> 22  3b 9a ca 00 6a c8 de 48
```

## Build information

``` r

zumsgpack_info()
#> <zumsgpack_info>
#> zufast:    0.1.0
#> zubin:     0.0.0
#> max_depth: 256 (at most 1023)
#> max_size:  67108864 bytes
#> max_items: 1000000
#> max_cells: 10000000
#> self-test: ok
```
