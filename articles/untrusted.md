# Decoding untrusted MessagePack

MessagePack usually arrives from somewhere you do not control: a network
peer, a log shipper, a message queue. zumsgpack treats every input as
hostile, and this vignette shows what that means in practice.

``` r

library(zumsgpack)
hex <- function(h) as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
```

## Check first, build second

[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
works in two phases. The first walks the whole input and checks it:
every head, length and count against the bytes there are, UTF-8 in every
`str`, the layout of every timestamp, duplicate map keys and the limits.
Only when all of that passes does the second phase build R values. So
five bytes claiming an array of 2^32 − 1 elements are refused before R
allocates anything:

``` r

tryCatch(msgpack_decode(hex("ddffffffff")),
         zumsgpack_error = function(e) conditionMessage(e))
#> [1] "MessagePack parse error at byte 0: a count is larger than the input"
```

[`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md)
runs exactly that first phase and nothing else. It returns `TRUE` or
`FALSE`; with `error = TRUE` it raises the condition that explains a
`FALSE`:

``` r

msgpack_validate(hex("930102"))
#> [1] FALSE
tryCatch(msgpack_validate(hex("930102"), error = TRUE),
         zumsgpack_error = function(e) e$offset)
#> [1] 0
```

The two agree about the bytes. They disagree only where the bytes are
valid MessagePack that R cannot hold, such as a `str` containing U+0000,
which
[`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
refuses with `zumsgpack_unrepresentable`.

## Limits

Four limits bound what an input can cost.

| Limit       | Default    | What it bounds                                  |
|-------------|------------|-------------------------------------------------|
| `max_size`  | 64 MiB     | the input, in bytes                             |
| `max_depth` | 256        | nesting of arrays, maps and exts (at most 1023) |
| `max_items` | 1,000,000  | objects, counting every key, value and element  |
| `max_cells` | 10,000,000 | cells of a data frame, with `data_frame = TRUE` |

`max_items` matters even though `max_size` bounds the input: one byte of
MessagePack can become dozens of bytes of R objects, so 64 MiB of empty
arrays would otherwise cost gigabytes.

``` r

deep <- c(rep(as.raw(0x91), 1000), as.raw(0xc0))   # 1000 nested arrays
tryCatch(msgpack_decode(deep), zumsgpack_depth_limit = function(e) e$limit_value)
#> [1] 256
```

Each limit has its own condition class, all inheriting
`zumsgpack_limit_error`, and carries `limit` and `limit_value`, so a
server can answer “too large” differently from “malformed”.

## Duplicate keys

Two parsers that disagree about a map with the same key twice – one
keeps the first, the other the last – can be made to see different
messages in the same bytes. zumsgpack refuses such maps, comparing keys
by value: the integer 1 written in one byte and in three is the same
key.

``` r

dup <- hex("8201c0cd0001c0")       # {1: nil, uint16 1: nil}
tryCatch(msgpack_decode(dup), zumsgpack_duplicate_key = function(e) e$offset)
#> [1] 3
```

With `duplicate_keys = TRUE` they are allowed, and the map comes back as
a `msgpack_map`, which keeps every entry in order.

## Reading a stream

MessagePack streams are objects back to back with no framing. With
`msgpack_read_seq(each =)` each object is checked whole, decoded and
passed on as soon as its last byte arrives, so memory is bounded by the
largest object rather than the stream, and the limits apply to each
object on its own:

``` r

path <- tempfile(fileext = ".msgpack")
writeBin(msgpack_encode_seq(lapply(1:1000, function(i) list(seq = i, ok = i %% 3 != 0))), path)
failures <- 0
n <- msgpack_read_seq(path, max_items = 10, each = function(m) {
  if (!m$ok) failures <<- failures + 1
})
c(objects = n, failures = failures)
#>  objects failures 
#>     1000      333
unlink(path)
```

A malformed object stops the read with its offset in the stream, after
the objects before it have been passed on.

## Seeing the bytes

[`msgpack_annotate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_annotate.md)
shows where every byte went, for reviewing a message whose bytes matter,
such as one a signature covers:

``` r

msgpack_annotate(msgpack_encode(list(alg = -7L, kid = "11", ts = as.POSIXct(0, tz = "UTC"))))
#>  0  83           fixmap(3)
#>  1  a2             fixstr(2) "ts"
#>  2  74 73
#>  4  d6 ff          fixext 4 type -1, timestamp 32: 0 s
#>  6  00 00 00 00
#> 10  a3             fixstr(3) "alg"
#> 11  61 6c 67
#> 14  f9             fixint -7
#> 15  a3             fixstr(3) "kid"
#> 16  6b 69 64
#> 19  a2             fixstr(2) "11"
#> 20  31 31
```
