# zumsgpack 0.0.0.9000

* Package identity: `zumsgpack_info()`, and links to zufast and zubin
  through `LinkingTo` (roadmap Stage 0).
* `msgpack_validate()` checks MessagePack without building any R value:
  every head, length and count against the bytes there are, UTF-8 in every
  `str`, the timestamp extension's three layouts, duplicate map keys by
  value, and the `max_depth`, `max_size` and `max_items` limits. Faults are
  classed conditions inheriting `zumsgpack_error`, with the byte offset
  (roadmap Stage 1).
