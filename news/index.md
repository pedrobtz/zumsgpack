# Changelog

## zumsgpack 0.0.0.9000

- Package identity:
  [`zumsgpack_info()`](https://pedrobtz.github.io/zumsgpack/reference/zumsgpack_info.md),
  and links to zufast and zubin through `LinkingTo` (roadmap Stage 0).
- [`msgpack_validate()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_validate.md)
  checks MessagePack without building any R value: every head, length
  and count against the bytes there are, UTF-8 in every `str`, the
  timestamp extension’s three layouts, duplicate map keys by value, and
  the `max_depth`, `max_size` and `max_items` limits. Faults are classed
  conditions inheriting `zumsgpack_error`, with the byte offset (roadmap
  Stage 1).
- [`msgpack_decode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md),
  [`msgpack_decode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_decode.md)
  and
  [`msgpack_read()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_read.md)
  build R values from checked input: integers by size, floats exactly,
  arrays simplified by zucbor’s lattice, maps as named lists or
  `msgpack_map`, exts as `msgpack_ext`, and integers beyond 2^53 by
  `big_integers`.
  [`msgpack_map()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md),
  [`msgpack_ext()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md)
  and
  [`msgpack_bigint()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack-values.md)
  construct the values R has no type for (roadmap Stage 2).
- [`msgpack_encode()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
  and
  [`msgpack_encode_seq()`](https://pedrobtz.github.io/zumsgpack/reference/msgpack_encode.md)
  write R values deterministically: the smallest integer form,
  `float 64` (or `float 32` when exact, with `floats = "shortest"`), one
  canonical NaN, `str` and `bin`, and map entries sorted by their
  encoded keys with no duplicates. The output buffer is zubin’s, owned
  by an external pointer (roadmap Stage 3).
