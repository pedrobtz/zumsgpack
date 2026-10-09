# zumsgpack: Deterministic and Secure 'MessagePack' Encoding and Decoding

Encodes R values as 'MessagePack' (<https://msgpack.org>) and decodes
'MessagePack' into ordinary R vectors and lists. Decoding checks the
whole input against configurable depth, size and item limits before any
R object is built, so untrusted input from network peers cannot drive
large allocations. Encoding is deterministic: identical R objects always
produce identical bytes. Timestamps convert to and from 'POSIXct', and
extension types can be given meaning by user handlers.

## See also

Useful links:

- <https://github.com/pedrobtz/zumsgpack>

- <https://pedrobtz.github.io/zumsgpack/>

- Report bugs at <https://github.com/pedrobtz/zumsgpack/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]
