# RFC 0005: `zumsgpack`, MessagePack in R

- **Status:** Adopted, 2026-10-09 (roadmap Stage 0). This is the
  package's own design; the RFC text below is kept as its starting point,
  and later changes are made here in the same commit as the code they
  describe.
- **Date:** 2026-10-07 (RFC); 2026-10-09 (adopted).
- **Packages:** `zumsgpack`; consumes `zufast` and `zubin` through
  `LinkingTo`.
- **Source:** `zucbor`'s design, which this RFC follows section for
  section where the two formats agree, since MessagePack and CBOR are the
  same idea with different heads; the MessagePack specification
  (`msgpack/spec.md`, with the timestamp extension); zufast's design §16
  and §17; zubin's design §9 and §12. Nothing below was checked against a
  running MessagePack implementation; section 15 says how that will be
  done.

## 1. What zumsgpack is

`zumsgpack` encodes and decodes MessagePack, the binary serialisation
used by Redis modules, Fluentd, Salt, neovim's RPC, many game and
telemetry protocols, and every language's "faster JSON". It is `zucbor`
with a different wire format: the same validate-before-build decoder,
the same limits, the same deterministic encoder, the same mapping to R,
so that a user who knows one knows the other, and a protocol library in
this family can switch between them by changing a prefix.

It is a *format* package, like `zucbor`. It vendors nothing: a
MessagePack head is one byte plus at most eight, and the whole decoder's
head table is shorter than TinyCBOR's licence file.

The one-line statement that governs every decision below:

> **Decode untrusted MessagePack only after it has been validated whole,
> encode R values deterministically, and map to R exactly as `zucbor`
> does.**

## 2. Scope

**In v0.1.0:**

- Every MessagePack format: nil, booleans, all integer forms, `float 32`
  and `float 64`, `str`, `bin`, arrays, maps, `fixext` and `ext`.
- The timestamp extension (type −1) in its three encodings, to and from
  `POSIXct`.
- Decoding one object, a sequence of objects, and the object a raw
  vector starts with; reading a path, URL or connection, bounded; reading
  a sequence item by item in bounded memory.
- Validation and an annotated hex dump.
- Extension handlers and an `as_msgpack()` generic, `zucbor`'s
  `tag_handlers` and `as_cbor()`.
- Deterministic encoding: smallest integer form, sorted map keys, no
  duplicate keys.
- Data frames as arrays of maps, opt-in on decode.

**Later, when asked:**

- Diagnostic notation (`msgpack_diagnose()`): MessagePack has no
  standard one; a JSON-like rendering with `ext(type, h'...')` is easy
  but is zumsgpack's own invention.
- The `bin`-versus-`str` compatibility mode of the pre-2013 spec (where
  `raw` meant both), for a protocol that still speaks it.

**Never:**

- Value sharing, string tables, compression: not in the format.
- A schema language.
- A canonical encoding beyond §8: the spec defines none, and zumsgpack's
  rules are its own, documented as such.

## 3. Position in the `zu*` family

The rows for `zu-family.md` (alignment R1):

| | zumsgpack |
| --- | --- |
| Role | format |
| R prefix | `msgpack_` |
| Info function | `zumsgpack_info()` |
| Root condition class | `zumsgpack_error` |
| Public C prefix | none; internal `zmp_` / `ZMP_` |
| From C | no C API; `LinkingTo` consumer only |
| Hides symbols | yes, from Stage 0 (R3) |
| Vendored code | none |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

The `zmp_` prefix was checked on 2026-10-07 against every sibling's
prefix; Stage 0 verifies it again.

**Relationships, as decided rather than as hoped:**

- **`zufast`** owns big-endian loads and stores (`zuf_load_be*`,
  `zuf_store_be*`), UTF-8 validation for `str`, and the integer
  formatting of the hex dump. MessagePack has no half floats, so §16's
  `f16` helpers are unused.
- **`zubin`** owns the encoder's output buffer through `zubin-r.h`
  (`zb_r_buf_new()`: a buffer owned by a finalized external pointer,
  which is exactly `zucbor`'s hand-written one) and the per-key
  sub-buffers for non-text map keys. This is the consumer `zucbor` #49
  would have been, built that way from the start rather than refactored
  into it.
- **`zucbor`** is the template for everything else: the check and build
  phases, the lattice, the conditions, the limits, the stream mode, the
  handlers and the generic. The two designs are kept in step by a
  "differences from zucbor" section in zumsgpack's own design (§6.5
  here), so a reader of one does not re-read the other.
- **`bit64`**: integers beyond 2^53 follow `big_integers =` as in
  `zucbor`, with the class `msgpack_bigint`.

**Consumers.** None named. The users are R clients of services that
speak MessagePack (Redis modules, Fluentd, neovim, MQTT payloads, Salt),
and anyone with `.msgpack` files from Python or Go. zumsgpack is useful
on its own.

**What exists elsewhere.** `RcppMsgPack` (CRAN) binds the C++
`msgpack-c` library: no validation before building, no limits, no
sequence reading in bounded memory, timestamps as raw ext bytes, and a
C++ runtime. `msgpackR` (CRAN) is pure R and slow by orders of magnitude.
The gap is the same one `zucbor` filled for CBOR: hostile-input
discipline, determinism, and a mapping that round-trips.

## 4. Architecture

`zucbor` §4, with the walk over zumsgpack's own head reader instead of
TinyCBOR's iterator:

```text
raw / file / connection
      |
      v
  check phase  (src/zmp_walk.c, R-free)
      - one iterative walk with an explicit container stack
      - every head decoded by a 256-entry table: format, head size,
        payload size or element count
      - limits: max_depth, max_items, max_size; length headers checked
        against the bytes remaining before any element is read
      - str payloads validated as UTF-8 (zuf_utf8_valid)
      - map keys recorded and sorted per map; duplicates refused
      - ext type -1 checked for a timestamp's three legal lengths
      - a plan: every container's element count, in preorder
      |
      v
  build phase  (src/zmp_build.c, R)
      - allocates from the plan, never from a length header
      - stages scalar array elements in C, as zucbor does
      - simplifies arrays by the lattice; maps to named lists or
        msgpack_map; ext through handlers or to msgpack_ext
      |
      v
  R value
```

Four check modes, as `zucbor` has them: one object, a sequence, a
prefix, and a stream that stops before an object the input ends inside.
In MessagePack, truncation is always "fewer bytes than the head or the
length says", which is one status, so the stream mode's rule (stop
without a fault on that status alone) is the same as `zucbor`'s.

The check phase is R-free behind `zmp_check.h`, builds with
`-DZMP_STANDALONE`, and has a libFuzzer target with `zucbor`'s
invariants (relaxing an option accepts more, a prefix consumes every
byte of an object, every proper prefix of an object is truncation).

The encoder (`src/zmp_encode.c`) is one pass into a `zubin` buffer, with
map keys encoded into sub-buffers, merge-sorted with `memcmp`, and
checked for duplicates before the map is written: `zucbor` §8.

## 5. Public R API (complete v0.1.0 surface)

```r
# decode
msgpack_decode(x, ...)            # raw -> R value; exactly one object
msgpack_decode_seq(x, ...)        # raw -> list; zero or more objects
msgpack_decode_prefix(x, ...)     # raw -> list(value, consumed)
msgpack_read(file, ...)           # path, URL or connection -> R value
msgpack_read_seq(file, ..., each = NULL)   # -> list, or a count
msgpack_validate(x, sequence = FALSE, ..., error = FALSE)
msgpack_annotate(x, sequence = FALSE, ...) # annotated hex dump

# encode
msgpack_encode(x, ...)            # R value -> raw
msgpack_encode_seq(x, ...)        # list -> raw; one object per element

# values R has no native type for
msgpack_map(keys, values)         # a map with arbitrary keys
msgpack_ext(type, data)           # an extension object
msgpack_bigint(x)                 # an integer outside what a double holds

# classes of your own
as_msgpack(x, ...)                # S3 generic the encoder calls

zumsgpack_info()
```

Twelve functions and a generic, the `zucbor` surface minus
`cbor_diagnose()` and `cbor_simple()` (MessagePack has no simple values
beyond nil and the booleans) and with `cbor_tag()` replaced by
`msgpack_ext()`.

### Decode arguments

```r
msgpack_decode(
  x,
  simplify       = c("preserve", "none"),
  map_keys       = c("auto", "map", "string"),
  ext            = c("convert", "keep"),     # the timestamp conversion
  big_integers   = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  max_depth      = 256L,
  max_size       = 64 * 1024^2,
  max_items      = 1e6,
  ext_handlers   = NULL,                     # list("5" = function(data) ...)
  data_frame     = FALSE,
  max_cells      = 1e7
)
```

The same arguments as `cbor_decode()`, with `tags` renamed `ext` and
`tag_handlers` renamed `ext_handlers`; there is no `deterministic =`
on decode, since MessagePack has no deterministic profile to check (§8).
`ext_handlers` is named by extension type, −128 to 127, as a string
(`"-1"` overrides the timestamp conversion). `msgpack_read_seq(each =)`
is `cbor_read_seq(each =)`: each object checked whole, decoded and
passed on, memory bounded by the largest object.

### Encode arguments

```r
msgpack_encode(
  x,
  auto_unbox = TRUE,
  max_depth  = 256L,
  floats     = c("double", "shortest")     # section 8
)
```

`msgpack_encode_seq()` takes a plain list and writes one object per
element.

## 6. MessagePack to R

### 6.1 Scalars and containers

| MessagePack | R |
| --- | --- |
| every integer form | `integer`, `double` or `msgpack_bigint` |
| `float 32`, `float 64` | `double`, exactly |
| `true`, `false` | `logical` |
| `nil` | `NULL`, or `NA` inside an atomic vector |
| `bin 8/16/32` | `raw` |
| `str` (fixstr, `str 8/16/32`) | `character`, UTF-8 |
| array | atomic vector when the elements agree, else `list` |
| map with non-empty, unique text keys | named `list` |
| any other map | `msgpack_map` (by `map_keys`) |
| ext −1 (timestamp) | `POSIXct`, UTC |
| any other ext | `msgpack_ext`, or a handler's result |

Notes:

- Integers follow `zucbor` §6.2: `integer` when within R's range,
  `double` up to 2^53, then `big_integers`. `uint 64` above 2^63 is the
  one case CBOR shares and MessagePack makes common.
- `float 32` is widened exactly; every NaN payload of a `float 64` is
  kept, so an R `NA_real_` written by `msgpack_encode()` reads back as
  `NA`.
- `str` must be valid UTF-8; the spec requires it and the check phase
  refuses otherwise (`zumsgpack_invalid_error`, with an offset). A
  `str` holding U+0000 is `zumsgpack_unrepresentable`. The old
  compatibility reading, where a `str` may hold arbitrary bytes, is
  deferred (§2).
- Maps: `zucbor` §6.4 and §6.5 unchanged, including comparison of keys
  by value (an `int` 1 and a `float` 1.0 are different keys; the
  integer 1 in one byte and in `uint 16` are the same key).
- The timestamp extension: `timestamp 32` (seconds), `timestamp 64`
  (34-bit seconds and 30-bit nanoseconds), `timestamp 96` (64-bit
  seconds and 32-bit nanoseconds). Nanoseconds above 999,999,999 are
  invalid per the spec and refused in the check phase. A `POSIXct` is a
  double, so nanoseconds are kept only to double precision; a handler
  for `"-1"` can keep the raw fields.

### 6.2 The lattice

`zucbor` §6.3, verbatim: integers and floats combine to the wider;
booleans are a kind of their own; text stays text; wide integers and
integer-valued numbers combine to `msgpack_bigint`; `POSIXct` stays its
class; `nil` joins any of them as `NA`; anything else is a list; `[]` is
`logical(0)`; a one-element array that simplifies is marked `I()`.

### 6.3 Extensions

`ext_handlers` is `zucbor`'s `tag_handlers` with the type number in
place of the tag number: a handler receives the ext's payload as a `raw`
vector (an ext has no structure beyond its bytes) and returns any R
value, which is kind "other" in the lattice. Without a handler an ext
is a `msgpack_ext` holding `type` (an integer) and `data` (a raw
vector), except type −1 under `ext = "convert"`. Handlers run only
after the check phase has accepted the whole input, so a handler never
sees a payload from an object with a bad length or a duplicate key.

### 6.4 Data frames

`zucbor` §6.10 unchanged: `data_frame = TRUE` turns an array of
text-keyed maps into a data frame, columns in first-seen order, missing
keys `NA`, each column through the lattice with the kinds its cells were
built with, bounded by `max_cells` before allocation.

### 6.5 Differences from `zucbor`, in one place

| | CBOR (`zucbor`) | MessagePack (`zumsgpack`) |
| --- | --- | --- |
| Semantic tags | 2^64 tags, typed content | 256 ext types, byte payloads |
| Half floats | yes | no |
| Indefinite lengths | yes | no |
| `undefined`, simple values | yes | no |
| Bignums (tags 2, 3) | yes | no: 64 bits is the ceiling |
| Dates | tags 0, 1, 100, 1004 | ext −1 only |
| Typed arrays (RFC 8746) | yes | no |
| Deterministic profile | RFC 8949 §4.2.1 | none in the spec; §8 is ours |
| Diagnostic notation | RFC 8949 §8 | none |
| Byte strings | major type 2 | `bin` |
| Maximum length | 2^64 | 2^32 |

Everything not in this table is identical, and the two designs say so
by cross-reference rather than by restating.

## 7. R to MessagePack

### 7.1 The mapping

| R | MessagePack |
| --- | --- |
| `NULL`, `NA` of any type | `nil` |
| `TRUE`, `FALSE` | `true`, `false` |
| `integer` | the smallest integer form |
| `double`, whole, within −2^63 … 2^64−1, not `-0` | the smallest integer form |
| any other `double` | `float 64` (§8) |
| `character` | `str`, UTF-8 |
| `raw` | one `bin` |
| `factor` | its labels, as `str` |
| `POSIXct` | ext −1, the smallest of the three encodings that holds it |
| `Date` | ext −1 at midnight UTC |
| `msgpack_bigint` | the integer form if within 64 bits, else refused |
| `msgpack_map`, `msgpack_ext` | a map, an ext |
| unnamed list or vector | array |
| fully named list or vector | map with `str` keys |
| `data.frame` | array of maps, one per row |

`zucbor` §7.1 to §7.3 and §7.7 apply: a length-one atomic vector is a
scalar unless `I()`-wrapped or `auto_unbox = FALSE`; partial names,
duplicate names and `NA` or empty names are refused; a class the
encoder does not know goes through `as_msgpack()` once (§7.5 there);
complex, functions, environments, external pointers, S4 and `POSIXlt`
are `zumsgpack_unsupported_type`.

Two things CBOR has and MessagePack lacks change the table: there is no
bignum, so an `msgpack_bigint` outside 64 bits is
`zumsgpack_unrepresentable` on encode rather than a tag; and there is no
`Date` type, so a `Date` is a timestamp at midnight UTC and comes back as
a `POSIXct`, a documented loss.

### 7.2 Known lossy conversions

`zucbor` §7.4's table minus the rows for `undefined`, bignums and typed
arrays, plus:

| Construct | Behaviour |
| --- | --- |
| `Date` | ext −1 at midnight UTC; reads back as `POSIXct` |
| `POSIXct` fractional seconds | from a double: about 2^-20 s near 2026 |
| `float 32` input | widened; re-encodes as `float 64` |

The round-trip property is `zucbor`'s: for any MessagePack object `b`
in the form §8 produces, `msgpack_encode(msgpack_decode(b))` is `b`,
pinned by the generated corpus and by the siblings' fixtures.

## 8. Deterministic encoding

MessagePack's specification says only that an encoder "should" use the
smallest integer form and says nothing about map order or float width.
zumsgpack always produces:

1. the smallest integer form for every integer, including lengths
   (`fixint` to `uint 64` / `int 64`), which is the spec's
   recommendation and what every mainstream encoder does;
2. `float 64` for every non-integral double by default. `floats =
   "shortest"` writes `float 32` when the value survives the round
   trip exactly, as `zucbor` does for CBOR; it is opt-in because several
   decoders (older Ruby, some Go configurations) widen `float 32`
   through `float`, which changes the value as seen by their users.
   Every `NaN` is written as one canonical quiet NaN (`cb 7f f8 00 00 00
   00 00 00`, or `ca 7f c0 00 00` under `"shortest"`): R's `NaN` is
   `0/0`, whose bits differ between x86 and ARM, and bytes must not
   depend on the host (roadmap Stage 3). `NA_real_` is `nil` (§7.1), not
   a float;
3. `str` for text and `bin` for bytes, never the compatibility `raw`;
4. map entries sorted by the bytewise lexicographic order of their
   encoded keys, as RFC 8949 §4.2.1 sorts CBOR maps; no duplicate keys;
5. the smallest timestamp encoding that holds the instant exactly. A
   `POSIXct` is first fixed to whole nanoseconds by one rule: the seconds
   by `floor()`, the fraction times 10^9 rounded to the nearest (half away
   from zero), a carry into the seconds at 10^9 (roadmap Stage 4). Each of
   those is a correctly rounded IEEE operation, so every host computes
   the same fields. Then `timestamp 32` when there are no nanoseconds and
   the seconds are within 0 .. 2^32 - 1, `timestamp 64` when the seconds
   are within 0 .. 2^34 - 1, and `timestamp 96` otherwise, nanoseconds
   never negative (−1.5 s is −2 s and 500,000,000 ns).

These are zumsgpack's rules, not the format's, and the documentation
says so; a decoder is not entitled to expect them. They make
`msgpack_encode()` byte-identical across calls, sessions and platforms,
which is what a signature or a content hash over the bytes needs.
`msgpack_validate()` has no `deterministic =` argument for that reason:
there is no spec-defined form to check against.

Floats are written byte by byte through `zuf_store_be32/64`, so a
big-endian host writes the same bytes.

## 9. The wire format, as zumsgpack reads it

A 256-entry table indexed by the first byte gives, for every format:
the kind, the head length (1, 2, 3, 5 or 9 bytes), whether the head
carries a count (array, map), a payload length (`str`, `bin`, `ext`) or
the value itself (fixint, `float`, `int`/`uint`), and for `fixext` the
fixed payload length. The bytes `0xc1` (never used), and nothing else,
are invalid. Lengths are big-endian unsigned and at most 32 bits, so a
head can claim 4 GiB; the check phase compares every claimed length
with the bytes remaining before touching the payload, under a `/* GUARD:
length-headers */` marker, and an array or map count with the remaining
bytes divided by one (or two) under a second.

An ext object is a type byte, signed, and a payload; type −1 is the
timestamp with payload lengths 4, 8 or 12, each a different layout; a
payload of any other length under type −1 is `zumsgpack_invalid_error`.
Types −2 to −128 are reserved by the spec and are read as plain
`msgpack_ext` objects.

## 10. Input sources and sequences

`zucbor` §9 unchanged: `msgpack_decode()` needs the whole object;
`msgpack_read()` reads at most `max_size + 1` bytes; a sequence is
objects back to back with no framing, which MessagePack streams
(Fluentd, neovim RPC, `msgpack.Unpacker` in Python) use directly;
`msgpack_read_seq(each =)` reads such a stream in memory bounded by
its largest object. There is no MessagePack equivalent of CBOR's
self-describe tag, so a stream is identified by its caller.

## 11. Errors

`zucbor` §10 with the prefix changed: every condition inherits
`zumsgpack_error`; classes `zumsgpack_invalid_argument`,
`zumsgpack_parse_error` (truncation, the reserved byte `0xc1`),
`zumsgpack_invalid_error` (bad UTF-8 in a `str`, a timestamp payload of
the wrong length or with nanoseconds out of range),
`zumsgpack_duplicate_key`, `zumsgpack_unrepresentable`,
`zumsgpack_unsupported_type`, `zumsgpack_handler_error` (with `type` and
`parent`), `zumsgpack_limit_error` with the subclasses
`zumsgpack_depth_limit`, `zumsgpack_size_limit`, `zumsgpack_item_limit`
and `zumsgpack_cell_limit`, and `zumsgpack_io_error`. Conditions from the
check phase carry `offset` and `status`; `status` names zumsgpack's own
enumerator, since there is no vendored library's table to map.

## 12. Limits and hostile input

`zucbor` §11 unchanged in substance: `max_size` (64 MiB), `max_depth`
(256, capped at 1023 by the build phase's recursion), `max_items` (1e6,
per object, per top-level object in a stream), `max_cells` (1e7).
Depth counts arrays, maps and exts (an ext is one level, as a tag is).

Two MessagePack specifics:

- **Length headers are 32-bit**, so the worst case a header can claim
  is 4 GiB, not 2^64; the guard is the same and the fuzz seeds include
  `0xdb 0xff 0xff 0xff 0xff` with a short payload.
- **A map's count is pairs**, and an odd element count cannot occur
  (the count is of pairs in the head, unlike CBOR's indefinite maps), so
  there is no odd-map guard.

Interrupts every 65,536 items in both phases, as in `zucbor`.

## 13. Memory model

`zucbor` §12 with the encoder's buffer replaced by `zubin`'s: the
output buffer and each non-text key's sub-buffer are `zb_buf`s owned by
finalized external pointers through `zb_r_buf_new()`, so they survive a
longjmp from a handler, an `as_msgpack()` method, an interrupt or an
allocation failure, and are freed eagerly on success. Everything else
is `R_alloc()`ed or `PROTECT`ed. The check phase allocates no R object.

## 14. Build, portability and CRAN

- C99, the family's lint flags under `-std=gnu17`; no vendored code.
- `DESCRIPTION`: `LinkingTo: zubin (>= 0.1.0), zufast (>= 0.1.0)`;
  `Suggests: bit64, testthat, withr, knitr, rmarkdown`. No `Imports`.
  No `Remotes:` in a submitted tarball; the consumer fixture is rebuilt
  against both providers' CRAN tarballs before submission (R10.3).
- `src/Makevars`: `PKG_CFLAGS = $(C_VISIBILITY)`; the shared object
  exports `R_init_zumsgpack` only.
- CRAN order: after `zufast` and `zubin`. Nothing else waits.
- Workflows: the family's standard set, with `native-checks` and
  `hardening` as `zucbor` runs them, since the code shape is the same.

## 15. Testing

- **Fixtures from other implementations, never by hand.**
  `tools/update-fixtures` fetches, at pinned revisions:
  `kawanet/msgpack-test-suite`, a corpus of value-to-bytes cases covering
  every format including the timestamp extension (read from upstream's
  own JSON build); and a set of objects written by Python's `msgpack` at
  a pinned version through `tools/make-fixtures.py`, each with Python's
  own decoding of it. A manifest records each file's source and SHA-256,
  and `tools/run-conformance` checks the fixtures against their sources.
  (The RFC also named `msgpack/msgpack-c`'s test vectors; checked at
  roadmap Stage 6, its tests are C++ code, not data, so there is nothing
  to fetch.)
- **The oracle is Python's `msgpack`,** in the conformance job only:
  every object of the suite and of Python's fixtures, and zumsgpack's
  encoding of every R value of §7.1, decoded by both and compared. The
  two sides meet in a canonical text form (`tools/canon.py`,
  `tests/testthat/helper-canon.R`) rather than through `reticulate`, so
  the package needs no Python-facing `Suggests` and the R tests compare
  against Python's recorded decodings without running Python. Any
  difference must be attributed by a named rule with an exact baseline
  (`tools/conformance-baselines.tsv`); the runner is seen to fail on a
  corrupted row and on a raised and a lowered baseline.
- **Round trip as a property**: `zucbor`'s `test-roundtrip.R` with the
  format changed; 300 generated values, each encoded twice and decoded
  back; and the stream invariants over every fixture fed in blocks of
  1, 2, 3 and 7 bytes.
- **The check phase is fuzzed** with libFuzzer under ASan and UBSan
  with `zucbor`'s invariants and seeds from every fixture; the canary
  must crash first.
- **Hostile inputs**, each a permanent regression: `0xdd` with a count
  of 2^32−1 and no elements; `0xdf` likewise; `0xdb` with a 4 GiB length;
  `0x91` nested 10^6 deep; a map with the same key as `fixint`, `uint 8`
  and `uint 16`; a `str` with every invalid UTF-8 class; ext −1 with a
  payload of 5 bytes; `timestamp 64` with nanoseconds of 10^9; `0xc1`;
  every proper prefix of every fixture.
- **The mutation check** over every `/* GUARD */` in the walk.
- Tests are self-sufficient, pass under `shuffle = TRUE`, stay serial,
  and the CRAN suite runs in under 15 s; heavy cases call `skip_heavy()`.

## 16. Performance targets

Measured by `tools/run-benchmarks` against `RcppMsgPack` and `zucbor`
(the same values in both formats) and recorded in the design: within
1.5× of `zucbor` on every benchmark of `zucbor` §17, since the shapes
are the same and MessagePack's heads are simpler; faster than
`RcppMsgPack` on decoding arrays of numbers, through the staged
simplification `zucbor` Stage 8 measured.

## 17. Decisions

| # | Question | Decision |
| --- | --- | --- |
| D1 | Decoder | project code; no vendored library |
| D2 | Design | `zucbor`'s, by cross-reference; §6.5 lists the differences |
| D3 | Dependencies | `LinkingTo: zubin, zufast` from the start |
| D4 | Floats on encode | `float 64`; `floats = "shortest"` opt-in |
| D5 | Map order on encode | bytewise sorted encoded keys, as `zucbor` |
| D6 | Whole doubles | integers, `zucbor`'s rule |
| D7 | `Date` on encode | ext −1 at midnight UTC; a documented loss |
| D8 | Timestamps on decode | `POSIXct` in UTC; `"-1"` handler overrides |
| D9 | `str` validity | UTF-8 required; the compatibility reading later |
| D10 | Diagnostic notation | none in 0.1.0 |
| D11 | `deterministic =` on decode | none: the spec defines no profile |
| D12 | Info function | `zumsgpack_info()`, the package name (R1) |

Reasons where they are not in the section cited:

- D1: `msgpack-c`'s C library is a buffer-and-callback API that
  allocates as it parses, the opposite of check-then-build; `mpack` and
  `cmp` are single-file and permissive but would still be adapted to
  the walk, which is shorter than the adapter. The head table and the
  walk are under a thousand lines, as `zucbor`'s walk is.
- D3: zumsgpack starts after both providers are on CRAN (§14), so the
  family review's objection to retrofitting `zucbor` (finding 2) does
  not apply: nothing is replaced, and the buffer code is never written.
- D4: `zucbor` chooses the shortest exact width because RFC 8949 says
  to; MessagePack says nothing, and the widening behaviour of some
  decoders makes `float 32` a value change for their users. The opt-in
  keeps the bytes small when the reader is known.
- D5: MessagePack has no key-order rule, so any order is "correct"; the
  bytewise order makes two encoders agree and gives `msgpack_encode()`
  the hashing property, and it is the order a `zucbor` user already
  knows.

## 18. Open questions

1. **`POSIXct` precision.** A double holds microseconds comfortably but
   not nanoseconds; `timestamp 96` nanoseconds round-trip only through a
   handler. Offer a `timestamp = c("POSIXct", "fields")` argument
   returning seconds and nanoseconds as a list? Recommended: no, the
   handler recipe covers it and the examples article shows it.
2. **The reserved ext types −2 to −128.** Read as `msgpack_ext` (as
   proposed), or refuse? The spec reserves them for future extensions;
   refusing would break on a future spec. Recommended: read.
3. **`bin` of length one versus a scalar `raw`.** `zucbor` writes any
   `raw` vector as one byte string; the same here, but a list of raw
   vectors is an array of `bin`. Nothing to decide; recorded so it is
   not re-asked.
4. **Interop corpus.** `kawanet/msgpack-test-suite` is the richest
   public corpus but is a YAML file; reading it needs `zuyaml` in
   `Suggests` for the conformance job, or a one-time conversion to JSON
   in `tools/`. Recommended: convert once in `tools/`, so the test suite
   needs no sibling. *Closed at roadmap Stage 1: upstream ships its own
   JSON build, which `tools/update-fixtures` reads and writes as a TSV.*

## 19. Roadmap

| Stage | Title | Size |
| --- | --- | --- |
| 0 | Package identity and a clean baseline | S |
| 1 | The head table and the check phase | M |
| 2 | The build phase: scalars, arrays, the lattice, maps | M |
| 3 | The encoder on `zubin`'s buffer | M |
| 4 | Timestamps, exts, handlers, `as_msgpack()` | M |
| 5 | Sequences, prefix, stream mode, `msgpack_read_seq(each =)` | M |
| 6 | Data frames, annotate, conformance corpus | M |
| 7 | Hardening: fuzz, mutation, sanitizers, benchmarks | M |
| 8 | Documentation and release 0.1.0 | S |

Exit criteria follow `zucbor`'s stages of the same name, with the
fixtures and oracle of §15; each stage's criteria are copied into the
package's roadmap with the format's names substituted, and the
differences of §6.5 called out where a `zucbor` criterion does not
apply.

## 20. Acceptance criteria for v0.1.0

`zucbor` §20, with these substitutions:

1. Builds everywhere with `zubin` and `zufast` from CRAN and nothing
   else at run time.
2. No R object is allocated before the check phase has passed; verified
   by the 4 GiB header and `max_items` fixtures.
3. Every oversized, deep, truncated or malformed input fails through a
   classed `zumsgpack_error`; the fuzz gate has been seen to fail on
   its canary.
4. Duplicate keys are rejected by value by default.
5. Encoding is deterministic by §8, byte-identical across platforms.
6. Every case of the two interop corpora passes in both directions.
7. Every documented mapping row has a test, and the three copies of
   each table agree.
8. The round-trip properties hold across the corpus.
9. `R CMD check --as-cran` clean everywhere; `R_init_zumsgpack` is the
   only export; no stdio or exit symbols.
10. The consumer fixture builds against the providers' CRAN tarballs.

## 21. What this RFC does not decide

- Whether `zucbor` and zumsgpack should share a package or a common C
  core. They could: the walk, lattice and builder differ only in the
  head reader. The family's rule is one format per package, and a
  shared core would be a provider with two consumers, which is exactly
  the shape the family has found hard to keep in step. Record the
  option; do not take it before both exist.
- Whether `msgpack_diagnose()` should invent a notation. Not in 0.1.0.
- Whether zumsgpack is worth more than `RcppMsgPack` to the people who
  use MessagePack from R. The case is §3's gap; the maintainer judges
  the audience.

Review prepared with assistance from generative AI.
