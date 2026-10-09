# Conditions raised by zumsgpack

Every error zumsgpack raises carries a condition class, so it can be
caught by kind rather than by matching the message, which may change.
Every class below inherits from `zumsgpack_error`.

## Details

- `zumsgpack_invalid_argument`:

  An argument was unusable: an input that is not a raw vector, a flag
  that is not `TRUE` or `FALSE`, or a limit that is not a positive whole
  number within its range.

- `zumsgpack_parse_error`:

  The input is not well-formed MessagePack: it ends early (a head, a
  length or a count claims more bytes than there are), uses the reserved
  byte `0xc1`, or has bytes after the object.

- `zumsgpack_invalid_error`:

  The input is well-formed but not valid: a `str` that is not UTF-8, or
  a timestamp (ext type -1) whose payload is not 4, 8 or 12 bytes or
  whose nanoseconds exceed 999,999,999.

- `zumsgpack_duplicate_key`:

  A map has the same key twice and `duplicate_keys = FALSE`. Keys are
  compared by value.

- `zumsgpack_unrepresentable`:

  The input is valid but holds a value R cannot, such as a `str`
  containing U+0000.

- `zumsgpack_unsupported_type`:

  An R value with no MessagePack form was given to the encoder.

- `zumsgpack_handler_error`:

  An extension handler raised an error.

- `zumsgpack_limit_error`:

  A limit was reached. The subclasses `zumsgpack_depth_limit`,
  `zumsgpack_size_limit`, `zumsgpack_item_limit` and
  `zumsgpack_cell_limit` name which one.

- `zumsgpack_io_error`:

  Reading the input failed.

A condition raised while checking input carries `offset`, the 0-based
byte offset of the object at fault, and `status`, the name of the
underlying status, such as `"ZMP_ERR_TRUNCATED"`. It is there for
diagnostics: branch on the class, not on it. A limit error also carries
`limit`, the argument's name, such as `"max_depth"`, and `limit_value`.
A `zumsgpack_invalid_argument` condition carries `arg`, the argument at
fault.

## Examples

``` r
tryCatch(
  msgpack_validate(as.raw(c(0x92, 0x01)), error = TRUE),
  zumsgpack_parse_error = function(e) e$offset
)
#> [1] 0
```
