# Read a sequence of MessagePack objects

Reads objects written back to back with no framing, as MessagePack
streams are: Fluentd's forward protocol, neovim's RPC, Python's
`msgpack.Unpacker`. A sequence has no marker of its own, so the caller
says that this is one.

## Usage

``` r
msgpack_read_seq(file, ..., each = NULL, max_size = 64 * 1024^2)
```

## Arguments

- file:

  A file path, a URL, or a connection.

- ...:

  Arguments passed on to
  [`msgpack_decode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md):
  `simplify`, `map_keys`, `ext`, `big_integers`, `duplicate_keys`,
  `max_depth`, `max_items` and `ext_handlers`.

- each:

  `NULL`, or a function called with each object in turn.

- max_size:

  Largest input allowed, in bytes, or `Inf`.

## Value

Without `each`, a list of the objects; with it, the number of objects
read, invisibly.

## Details

Without `each`, the whole input is read, at most `max_size + 1` bytes of
it, and decoded as
[`msgpack_decode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
would: a list with one element per object.

With `each`, a function of one argument, the input is read in blocks and
each object is checked whole, decoded and passed to `each` as soon as
its last byte has arrived; nothing accumulates, and the call returns the
number of objects read. Memory is then bounded by the largest object,
not the stream: `max_size` and `max_items` apply to each object on its
own. An object is never decoded before all of it has been checked, so
`each` never sees part of one. A malformed object stops the read with a
classed condition whose `offset` is its position in the stream; the
objects before it have already been passed on. The stream ending inside
an object is `zumsgpack_parse_error` at that object's offset. An error
raised by `each` itself propagates unchanged.

## See also

[`msgpack_read()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read.md),
[`msgpack_decode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md),
[`msgpack_decode_prefix()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode_prefix.md).

## Examples

``` r
path <- tempfile(fileext = ".msgpack")
writeBin(msgpack_encode_seq(list(list(tag = "a", n = 1L),
                                 list(tag = "b", n = 2L))), path)
msgpack_read_seq(path)
#> [[1]]
#> [[1]]$n
#> [1] 1
#> 
#> [[1]]$tag
#> [1] "a"
#> 
#> 
#> [[2]]
#> [[2]]$n
#> [1] 2
#> 
#> [[2]]$tag
#> [1] "b"
#> 
#> 

# One object at a time, in memory bounded by the largest.
total <- 0
msgpack_read_seq(path, each = function(x) total <<- total + x$n)
total
#> [1] 3
unlink(path)
```
