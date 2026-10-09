# zumsgpack 0.0.0.9000

* Package identity: `zumsgpack_info()`, and links to zufast and zubin
  through `LinkingTo` (roadmap Stage 0).
* `msgpack_validate()` checks MessagePack without building any R value:
  every head, length and count against the bytes there are, UTF-8 in every
  `str`, the timestamp extension's three layouts, duplicate map keys by
  value, and the `max_depth`, `max_size` and `max_items` limits. Faults are
  classed conditions inheriting `zumsgpack_error`, with the byte offset
  (roadmap Stage 1).
* `msgpack_decode()`, `msgpack_decode_seq()` and `msgpack_read()` build R
  values from checked input: integers by size, floats exactly, arrays
  simplified by zucbor's lattice, maps as named lists or `msgpack_map`,
  exts as `msgpack_ext`, and integers beyond 2^53 by `big_integers`.
  `msgpack_map()`, `msgpack_ext()` and `msgpack_bigint()` construct the
  values R has no type for (roadmap Stage 2).
* `msgpack_encode()` and `msgpack_encode_seq()` write R values
  deterministically: the smallest integer form, `float 64` (or `float 32`
  when exact, with `floats = "shortest"`), one canonical NaN, `str` and
  `bin`, and map entries sorted by their encoded keys with no duplicates.
  The output buffer is zubin's, owned by an external pointer (roadmap
  Stage 3).
* Timestamps (ext type -1) decode to `POSIXct` in UTC and `POSIXct` and
  `Date` encode as the smallest of the three layouts that holds the
  instant, nanoseconds rounded by one rule on every host. `ext = "keep"`
  leaves them as `msgpack_ext`. `ext_handlers` gives meaning to extension
  types, and the `as_msgpack()` generic teaches the encoder a class
  (roadmap Stage 4).
