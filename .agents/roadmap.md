# zumsgpack — Roadmap to 0.1.0 (first CRAN release)

Companion to [design.md](design.md). Section references (§) point there;
references to `zucbor` name its design (`zucbor` §n) or its roadmap
(`zucbor` Stage n) explicitly.

zumsgpack is `zucbor` with a different head reader (§1, D2), so this
roadmap is `zucbor`'s with the stages regrouped as §19 lists them and
with `zucbor`'s *What actually happened* notes turned into instructions.
Where a `zucbor` lesson applies, the stage says so in a **Carried over**
list, so that nothing `zucbor` paid for is paid for twice. Where a
`zucbor` criterion does not apply because of §6.5, the stage says that
too.

## Sequencing principles

1. **The check phase lands before the builder.** Limits, duplicate keys
   and validation are the security core (§4, §12). Building R objects
   first means retrofitting limits into code that already assumes they
   hold.
2. **The check phase is R-free from its first commit.** `zucbor` made it
   R-free at Stage 7 to fuzz it; here `src/zmp_walk.c` compiles with
   `-DZMP_STANDALONE` from Stage 1, which is also what makes acceptance
   criterion 2 structural rather than behavioural.
3. **The encoder lands before hardening.** Round trip is the strongest
   oracle available (§15); every stage after Stage 3 gets a better suite
   for free.
4. **Fixtures come from other implementations, never by hand** (§15), and
   they arrive when the first test needs them (Stage 1), not at the
   conformance stage. Stage 6 adds the runner, the oracle and the rest of
   the corpus.
5. **Every stage ends with something runnable and tested,** and **a stage
   is done when its exit criteria pass in CI on all three platforms**, not
   when the code is written.
6. **Gates need canaries.** A gate (symbol check, lint, fuzz, mutation,
   conformance baseline) is trusted once it has been seen to fail on
   purpose, not before.
7. **Change the design in the same commit as the contract.** A stage that
   changes a decision in §17 or answers a question in §18 edits design.md
   in that commit, along with the roxygen table and the tests that state
   it.
8. **Stay in step with `zucbor`.** A decision that differs from `zucbor`'s
   goes into §6.5, or it is a bug. A lesson learnt here that applies to
   `zucbor` is filed there as an issue in the same week.

Sizes are §19's: **S** ≈ a sitting, **M** ≈ a few, **L** ≈ the stage is
the week. `zucbor`'s check and build stages were L; these are M because
the design, the lattice and the tests already exist, but if Stage 1 or 2
runs long, that is why.

**"v1" means the first release's scope** (§2 *In v0.1.0*). It ships as
0.1.0 at Stage 8; 1.0.0 comes after a real consumer has used the API.

**Status never goes in a heading.** A heading is
`## Stage N — Title · Size` and nothing else; a stage's state is the
**Status:** line directly under it. Status words in a heading change its
GitHub anchor, which breaks every issue that links to the stage.

**Tracking.** One pull request per stage, linking to its heading here,
merged when its CI is green. This file stays authoritative: a stage's
**Status:** line is updated in its own pull request.

---

## Stage 0 — Package identity and a clean baseline · S

**Status:** complete.

The repository is the `usethis` skeleton plus pkgdown. Clear it, give it
its family identity (§3), and prove the providers link before any format
code is written.

**Do**

- **Check the providers first.** D3 assumes `zufast` and `zubin` are on
  CRAN (§14). On 2026-10-05 `zubin` was not (its roadmap: waiting for
  `zufast`). Record what CRAN has today in this stage's notes. Until both
  are there, develop with `Remotes: pedrobtz/zufast, pedrobtz/zubin` in
  `DESCRIPTION`, and add a Stage 8 blocker that removes it. Nothing in
  Stages 1–7 waits on CRAN; Stage 8 does.
- `DESCRIPTION`: real `Title` and `Description`; `Authors@R` (Pedro
  Baltazar, `aut`/`cre`/`cph`); `URL` and `BugReports`;
  `Depends: R (>= 4.1)`; `Language: en-GB`;
  `LinkingTo: zubin (>= 0.1.0), zufast (>= 0.1.0)`;
  `Suggests: testthat (>= 3.0.0), withr` (the rest of §14's `Suggests`
  arrive with the stage that uses them).
- `LICENSE` / `LICENSE.md` name a real copyright holder. No vendored code,
  so no other `cph` (D1).
- `.Rbuildignore`: `^tools$`, `^fuzz$`, `^\.agents$`, and the
  `src/**/*.o`, `*.so`, `*.dll` patterns.
- `NEWS.md`: `# zumsgpack 0.0.0.9000`.
- **The shared object.** Replace `src/zumsgpack.c` with `src/init.c`:
  `R_init_zumsgpack` with `R_registerRoutines()`,
  `R_useDynamicSymbols(FALSE)` and `R_forceSymbols(TRUE)`, the only
  symbol given default visibility. `src/Makevars` with
  `PKG_CFLAGS = $(C_VISIBILITY)`, and nothing in `Makevars.win` (R falls
  back to `Makevars`).
- **Include both providers' headers from one translation unit** and call
  one function from each (`zuf_load_be32()`, `zb_r_buf_new()`), so the
  `LinkingTo` is exercised rather than declared.
- `zumsgpack_info()` (R1): package version, the `zufast` and `zubin`
  header versions it was built against, and the default limits (§5,
  §12), including the 1023 depth cap.
- `tools/check-symbols`: `nm` over the built shared object, failing on any
  exported symbol other than `R_init_zumsgpack` and on `stdout`, `stderr`,
  `printf`, `puts`, `abort`, `exit`, `__assert_fail` and `__assert_rtn`.
  **Plant a `fprintf(stderr, …)` in a scratch copy and see it fail.**
- **Verify the `zmp_` prefix again** (§3) against every checked-out
  sibling's `src/` and `inst/include/`, and record the command and the
  date here.
- **Consumer inventory.** Write down, in this file, which packages will
  call zumsgpack and how. §3 names none; check every sibling's design for
  MessagePack, Redis, Fluentd or neovim, and record the result even if it
  is "none".
- Replace the template test with `tests/testthat/test-init.R` (the DLL is
  loaded and registered) and `test-info.R`, in the same commit that
  removes the template, so `tests/testthat/` is never empty.
- Turn design.md's header from *RFC, Proposed* into the package's own
  design: status *Adopted*, the date, and a line saying the RFC text is
  kept as the starting point.

**Carried over from `zucbor`**

- An empty `tests/testthat/` next to `tests/testthat.R` is a hard check
  error (`zucbor` Stage 0).
- roxygen2 8.1.0 rewrites `RoxygenNote` into
  `Config/roxygen2/version`; keep 8.1.0 or newer.
- `R CMD check --as-cran` does not show the development-version NOTE
  locally; that comes from the incoming checks.
- The symbol check must list `assert`'s symbols and must look for the
  stream (`__stderrp`, `stderr`), not only function names: clang rewrites
  `fprintf` into `fwrite` (`zucbor` Stage 1).

**Exit**

- `R CMD check --as-cran` passes on the full CI matrix.
- `tools/check-symbols` passes and has been seen to fail.
- The providers' status, the prefix check and the consumer inventory are
  written here.

**Providers (2026-10-09).** Neither `zufast` nor `zubin` is on CRAN
(`available.packages()` from cloud.r-project.org lists neither). Both are
public on GitHub and come in through `Remotes:`. `zubin`'s headers are
still version `0.0.0`, so `LinkingTo: zubin` carries no version bound until
it is released; Stage 8 restores `(>= 0.1.0)`.

**Prefix (2026-10-09).** `grep -rlE '\b(zmp_|ZMP_)'` over the `.c`, `.h`,
`.cpp` and `.R` files of every checked-out sibling (26 `zu*` repositories
and the rest of `~/src/github.com/pedrobtz`) finds nothing outside
zumsgpack.

**Consumer inventory (2026-10-09)**

| Candidate | How it would consume zumsgpack | Confirmed? |
|---|---|---|
| any `zu*` sibling | — | No. No sibling design mentions MessagePack, Redis, Fluentd or neovim; `zubin/.agents/ideas.md` lists `RcppMsgPack` and `msgpackR` only as packages not to duplicate |

**No consumer is confirmed**, so v1 is the R API alone, as §3 says, and
nothing in it is shaped around a particular sibling.

**What actually happened**

- `git rm` of the template test removed `tests/testthat/`, as the roadmap
  warned; the tests were written into a recreated directory before
  anything was built.
- `zubin-r.h` does not include `zubin/version.h`; `ZUBIN_VERSION` needs
  `<zubin.h>` first.
- `tools/check-symbols` gained a second check beyond `zucbor`'s: the only
  defined external text symbol may be `R_init_zumsgpack`. Both halves were
  seen to fail: a planted `fprintf(stderr, …)` was caught through
  `___stderrp`, and a planted `visibility("default")` function by name.
- zubin already has big-endian puts (`zb_put_u16be` … `zb_put_f64be`), so
  the encoder needs `zufast`'s stores only for scratch bytes outside a
  `zb_buf`.
- The milestone and issues are not created: the stages are tracked by
  their pull requests instead, one per stage, each linking its heading.

---

## Stage 1 — The head table and the check phase · M

**Status:** complete.

The core. Everything after it relies on what this stage guarantees, and
the stage's output is a user-facing function, `msgpack_validate()`.

**Do**

- **Conditions.** `src/zmp_cond.c`: classed conditions raised from C with
  the user's call attached; the status enumerator and its name table
  (§11, "zumsgpack's own enumerator"). `R/conditions.R` for R-side
  argument errors of the same shape. `?"zumsgpack-conditions"` documents
  the §11 hierarchy.
- **Arguments.** Validation of `max_size`, `max_depth`, `max_items`:
  positive whole numbers, `Inf` where allowed, `max_depth` ≤ 1023
  (§12).
- **The head table.** `src/zmp_head.c` (or a `static const` table in the
  walk): 256 entries giving kind, head length (1, 2, 3, 5 or 9), what the
  head carries (count, payload length or value) and `fixext`'s fixed
  payload length (§9). `0xc1` is the only invalid byte. A test enumerates
  all 256 bytes against an independent table written from the spec's own
  format list.
- **The walk.** `src/zmp_walk.c` behind `src/zmp_check.h`, R-free and
  building with `-DZMP_STANDALONE` against an arena from this stage on
  (principle 2). Scratch memory, interrupts and offsets reach R through
  hooks in `zmp_check.h`, as `zucbor`'s do. One iterative walk with an
  explicit container stack sized from `max_depth`; byte offsets on every
  fault; a trailing-bytes check; interrupts every 65,536 items.
- **Guards**, each a single-line `/* GUARD: name */` marker so the
  mutation tool of Stage 7 can disable it:
  - `length-headers`: every `str`/`bin`/`ext` length against the bytes
    remaining, before the payload is touched;
  - `container-count`: every array count against the bytes remaining,
    and every map count against half of them;
  - `depth`, `items`, `size`, `trailing-bytes`;
  - `utf8`: every `str` payload through `zuf_utf8_valid()`, in the walk;
  - `duplicate-keys`: per-map key descriptors, merge-sorted (never
    `qsort()`), adjacent comparison by value (§6.1);
  - `timestamp`: ext −1 payload length 4, 8 or 12, and nanoseconds
    ≤ 999,999,999 in the 64- and 96-bit forms (§6.1, §9).
- **The plan.** The walk records every container's element count in
  preorder (§4), which the build phase of Stage 2 allocates from.
- **Check modes.** One object and a sequence now; prefix and stream arrive
  at Stage 5, but the mode is an enumerator from the start
  (`zucbor` Stage 11's `mode = 0, 1, 2`), not a growing set of flags.
- **Export `msgpack_validate(x, sequence = FALSE, ..., error = FALSE)`.**
  `error = TRUE` raises the classed condition rather than returning
  `FALSE`, which the tests need and so will users (`zucbor` Stage 2).
- **Fixtures, first instalment.** `tools/update-fixtures` fetches
  `kawanet/msgpack-test-suite` at a pinned revision and converts its YAML
  to JSON once, in `tools/` (§18 Q4, closed here as recommended). A
  manifest records source, revision, licence and SHA-256. Valid cases
  validate; the test helper decodes their hex, never hand-written bytes.
- **Hostile inputs** (§15), each a permanent regression: `0xdd` and `0xdf`
  with a count of 2^32−1 and no elements; `0xdb ff ff ff ff` with a short
  payload; `0x91` nested 10^6 deep; a map with the same key as `fixint`,
  `uint 8` and `uint 16`; a `str` with every invalid UTF-8 class; ext −1
  with a 5-byte payload; `timestamp 64` with nanoseconds of 10^9; `0xc1`;
  every proper prefix of every valid fixture.
- **`native-checks.yaml` now,** not at Stage 7 (`zucbor` brought it
  forward to its check stage for the same reason): UBSan over the suite
  with `-UNDEBUG`, the ASan containers over `tools/sanitizer-exercise.R`,
  valgrind, a blocking `rchk`, and `tools/check-symbols`.

**Duplicate keys: the comparison classes to test** (§6.1, `zucbor` §6.5)

- Same integer in every width: positive `fixint`, `uint 8/16/32/64`, and
  **a non-negative value in a signed form** (`int 8` holding 5), which
  MessagePack allows and CBOR cannot express.
- Same negative integer as negative `fixint`, `int 8/16/32/64`.
- `float 32` 1.0 against `float 64` 1.0: the same key.
- `int` 1 against `float` 1.0: different keys.
- `fixstr`, `str 8`, `str 16` with the same bytes: the same key.
- `str` "a" against `bin` "a": different keys.
- Equal `ext` objects by type and payload, including `fixext` against
  `ext 8` of the same length: the same key.
- Equal nested arrays and maps as keys.

**Not applicable from `zucbor`** (§6.5): indefinite lengths, string
chunks, the odd-map guard, tag-content rules, half floats, simple values,
`deterministic =` (D11), and TinyCBOR's status table.

**Carried over from `zucbor`**

- Check every length against the bytes left *before* any size arithmetic,
  so a 4 GiB claim is a `zumsgpack_parse_error` at offset 0
  (`zucbor` Stage 2).
- `NULL + 0` is undefined in C: test for the empty map before forming a
  pointer into the key array.
- Shared test helpers live in `helper-*.R`; `shuffle = TRUE` reorders a
  file's top-level definitions too.
- Bulk checks compute every outcome and assert once, naming the failing
  inputs; thousands of `expect_error()` calls made `zucbor`'s suite take
  20 s.

**Exit**

- Every valid case of the test suite validates; every hostile input above
  fails with its own class, `offset` and `status`, with no crash and no
  stack overflow, the deep cases also under a 1 MB stack in the sanitizer
  job.
- Each limit trips its own class with `limit` and `limit_value` set; a
  test asserts every status enumerator maps to a class.
- The standalone build compiles with no R headers on the include path.
- ASan, UBSan (`-UNDEBUG`) and `rchk` clean.

**What actually happened**

- **The suite already ships as JSON.** `kawanet/msgpack-test-suite` has
  `dist/msgpack-test-suite.json` beside its YAML, so §18 Q4 closed with no
  conversion of our own. `tools/update-fixtures` checks the download
  against a pinned SHA-256 and writes one TSV row per encoding (85 cases,
  233 encodings), the value as R source text, so the tests need no JSON
  parser.
- **The head table is built by the compiler.** A conditional expression
  over struct values is not a constant expression in C, and repeating a
  row through nested macros splits it at its commas. Each repeat macro
  takes a row macro's *name* and calls it, so the 128 positive fixints,
  the fix ranges and the 32 negative fixints are one line each, and the
  32 formats from `0xc0` to `0xdf` a row each. `test-head.R` compares all
  256 entries with a table written in the test from the spec.
- **The standalone gate arrived with the walk.** `fuzz/probe` (built by
  `tools/build-standalone` with no R include path) prints a status per
  file; `tools/run-standalone` runs it under ASan and UBSan over 1,922
  seeds (every suite encoding, each of its proper prefixes, and the
  hostile list) in all five modes, in the `gates` workflow. Clean.
- **Stream mode exists already.** The check modes are one enumerator, as
  planned, and the stream rule (stop before an object the input ends
  inside, with `max_items` per object) cost a dozen lines, so the walk has
  it now and Stage 5 only exposes it.
- **A count is refused at its container.** The count guard runs before the
  first element, so `93 01 02` (three elements promised, two there) is
  truncation at offset 0, not at offset 3. Every proper prefix is still
  `ZMP_ERR_TRUNCATED`; only the offset says which guard saw it.
- **Container keys compare by bytes,** as zucbor's do: `[1]` and
  `[uint 8 1]` are two keys. Scalar keys compare by value, including an
  `int 8` holding 5 against a positive fixint 5, and a `float 32` against
  the `float 64` it widens to. `-0.0` and `0.0` are two keys (by bits, as
  zucbor). `?msgpack_validate` says all of this.
- **An ext is a level.** `max_depth = 1` accepts a top-level ext and
  refuses one inside an array, so the encoder must charge the same at
  Stage 3.

---

## Stage 2 — The build phase: scalars, arrays, the lattice, maps · M

**Status:** complete.

**Do**

- `src/zmp_build.c`: recursion bounded by the checked depth, allocation
  from the plan only (never from a length header), one CHARSXP maker with
  the NUL guard (`zumsgpack_unrepresentable`, §6.1).
- **Integers** (§6.1): `integer`, then `double` up to 2^53, then
  `big_integers = c("bigint", "double", "error")`. `uint 64` above 2^63
  is the common case here; test both 64-bit boundaries in every form.
  `msgpack_bigint` holds at most 64 bits, so its decimal conversion is
  `zufast`'s integer formatting, not a bignum routine.
- **Floats**: `float 32` widened exactly; every `float 64` NaN payload
  kept, so `NA_real_`'s bits survive.
- **The lattice** (§6.2, `zucbor` §6.3 verbatim), staging scalar array
  elements in C rather than one R object per element (`zucbor` Stage 8's
  largest decode win).
- **Maps** under all three `map_keys` modes, and `duplicate_keys = TRUE`
  producing `msgpack_map`. Non-text keys under `map_keys = "string"` are
  named by a single formatter, floats by their shortest round-trip
  decimal (`zucbor` Stage 3 and 5).
- **Exts** decode to `msgpack_ext` (type and data) for now; the timestamp
  conversion and handlers are Stage 4's. Reserved types −2 to −128 are
  read, not refused (§18 Q2, closed here as recommended).
- **The value classes**: `msgpack_map()`, `msgpack_ext()`,
  `msgpack_bigint()` constructors that validate their input;
  `print`/`format`/`as.character`/`length`; `as.numeric.msgpack_bigint`.
- **Export `msgpack_decode()`, `msgpack_decode_seq()`, and
  `msgpack_read()`** over a bounded `readBin()` loop that reads at most
  `max_size + 1` bytes (§10). The source helper is `zucbor`'s
  `R/zu_source.R`, copied.
- **Write the §6 tables into roxygen now**, from design.md, with one test
  per row.

**Carried over from `zucbor`**

- **One-element arrays decode as `I()`**, and **logical is a kind of its
  own**: both were found by `zucbor`'s round-trip test and are already in
  §6.2; test them here so Stage 3 does not rediscover them.
- Make `-0` at run time (`neg_zero()`), never as a literal: R's byte-code
  compiler folds `-0` to `+0`.
- Build exact floats from their bits (`f64()`, `f32()`), not decimal
  literals: R's parser is off by one ulp on macOS arm64.
- Raise build-phase faults with the user's call wrapped in `quote()`, and
  never through `do.call()`, which re-evaluates the call.
- `PROTECT` every argument to `Rf_setAttrib()` that allocates (`rchk`
  found `Rf_mkString("UTC")` unprotected).
- `close()` destroys an R connection; a test must not ask a closed
  connection whether it is open.

**Exit**

- Every §6.1 row has a test; roxygen, design.md and tests agree.
- Every case of the test suite decodes to the value the suite states,
  checked with `identical()` (timestamps excepted until Stage 4).
- Clean under `gctorture(TRUE)`; the fifty-times interleaved
  failing/succeeding test passes.
- The interrupt test (`setTimeLimit(elapsed = 0.01)` inside the decoding
  expression, over millions of empty arrays) unwinds, and the same input
  then decodes in full.
- `msgpack_read()` on an endless connection stops one byte past
  `max_size`.

**What actually happened**

- **The builder is zucbor's, re-pointed.** `src/zmp_build.c` keeps the
  staged arrays, the lattice, the `I()` marking and the map paths line for
  line; what changed is that it reads heads with `zmp_read_head()` at a
  cursor instead of walking TinyCBOR's iterator. Containers still take
  their size from the plan, never from a head.
- **The head's integer form made the ladder free.** `zmp_read_head()`
  stores a negative integer as `-(v + 1)` with a flag, which is CBOR's own
  encoding of negatives, so zucbor's `integer_value()` applies unchanged:
  `integer` from -(2^31 - 1) to 2^31 - 1, `double` within 2^53 (both
  signs, so -2^53 is a double), then `big_integers`. `msgpack_bigint`'s
  decimal comes from `zuf_write_u64()`.
- **Key names for `map_keys = "string"` are zumsgpack's own.**
  MessagePack has no notation, so non-`str` keys are named by a small
  JSON-like formatter in the build phase: integers in decimal, floats by
  `zuf_format_f64_opt()` with a forced `.0` (so `1.0` never reads as `1`),
  `nil`, `true`, `h'..'`, `ext(t, h'..')`, `[..]` and `{..}`. Keys that
  collide once named are `zumsgpack_duplicate_key`
  (`ZMP_ERR_KEY_COLLISION`), as in zucbor.
- **The suite compares by shape.** jsonlite reads `{}` as an unnamed
  `list()`, the same as `[]`, and a one-element array decodes as an `I()`
  vector, so the suite test flattens both sides to one JSON-like shape;
  the per-row tests check types exactly. Timestamps wait for Stage 4.
- **The interrupt test runs unskipped locally** (1.5 million empty maps,
  interrupted by `setTimeLimit()`, then decoded in full), and the
  gctorture test compares five mixed inputs and one fault with the
  untortured results.
- `tools/sanitizer-exercise.R` now decodes every seed under all 36 option
  sets, as one object and as a sequence: 138,384 decodes, faults
  included, in about eleven seconds unsanitized.

---

## Stage 3 — The encoder on `zubin`'s buffer · M

**Status:** complete.

**Do**

- `src/zmp_encode.c`: one pass into a `zb_buf` owned by a finalized
  external pointer from `zb_r_buf_new()` (§4, §13). No measuring pass:
  that was the last of `zucbor`'s encoder slow-downs, and the buffer
  makes it unnecessary.
- **Map keys** encoded into per-key sub-buffers, merge-sorted with
  `memcmp`, checked for duplicates, then written (§8 rule 4). Partial,
  duplicate, `NA` and empty names refused (§7.1).
- **The §7.1 mapping** except timestamps and data frames: smallest
  integer forms for values and lengths (§8 rule 1, non-negative values
  always in the unsigned family); whole doubles within −2^63 … 2^64−1 and
  not `-0` as integers (D6); `float 64` for the rest (D4), and
  `floats = "shortest"` writing `float 32` when it round-trips exactly;
  `str` and `bin`, never the old `raw` (§8 rule 3); factors as labels;
  `msgpack_bigint` within 64 bits, otherwise
  `zumsgpack_unrepresentable`; `msgpack_map` and `msgpack_ext`;
  `auto_unbox` and `I()`.
- **Refuse what has no row yet.** `POSIXct` and `Date` arrive at Stage 4
  and data frames at Stage 6; until then each is
  `zumsgpack_unsupported_type`, so no interim encoding (a data frame as a
  map of columns) ever exists to be relied on.
- Floats written through `zuf_store_be32/64`, never `memcpy()`, so a
  big-endian host writes the same bytes.
- Depth charged exactly as the decoder charges it (§12).
- **Export `msgpack_encode()` and `msgpack_encode_seq()`.**
- **Round-trip property tests** (`test-roundtrip.R`, §15): 300 generated
  nested values, each encoded twice and decoded back; every test-suite
  case in §8 form satisfies `msgpack_encode(msgpack_decode(b)) == b`.
- **The cross-platform fixture**: a checked-in hex encoding of one large
  mixed value exercising every encoder path of this stage, compared byte
  for byte on every CI platform. Stage 4 adds a second fixture rather
  than changing this one.

**Carried over from `zucbor`**

- Each non-text key is encoded once, into its own buffer, so an
  `as_msgpack()` method on a key (Stage 4) never runs twice
  (`zucbor` Stage 10).
- If entry pools are kept per depth for map sorting, a map's end must
  forget every deeper pool: `zucbor` had a latent use after free there
  that no test caught until the sanitizer exerciser was given its shape.
- `rchk` cannot balance a `PROTECT` inside a two-pass loop, and objects
  held across allocations need protecting (`zucbor` Stage 7's findings in
  its encoder).

**Exit**

- Every test-suite case in §8 form encodes to its exact bytes.
- The cross-platform fixture is byte-identical on every CI platform.
- `msgpack_encode()` at `max_depth = d` never produces output
  `msgpack_decode(max_depth = d)` refuses, at `d` and `d + 1`, for every
  container kind.
- `gctorture(TRUE)` and `rchk` clean; an error from inside the encoder
  (unsupported type deep in a map) leaks no buffer under ASan.

**What actually happened**

- **NaN is canonical, which the design did not say.** §8 lists the rules
  that make output byte-identical across platforms, but R's `NaN` is
  `0/0`, whose bits differ by host: x86's default NaN has the sign bit
  set, ARM's does not. Writing a NaN's own bits would have made the
  cross-platform fixture depend on the CI runner. Every NaN is written as
  `cb 7f f8 00 …` (`ca 7f c0 00 00` under `floats = "shortest"`), and §8
  rule 2 says so now. `NA_real_` is not a float: it is `nil`, as §7.1
  already said, so no NaN payload needs keeping on encode; the decoder
  still keeps every payload it reads.
- **R's parser struck again.** The test for a double `float 32` cannot
  hold used the literal `1e300`, which R on macOS arm64 reads one ulp
  away from the nearest double (`…75a0`, not `…759c`). The encoder wrote
  exactly the bits it was given; the test and the fixture value now build
  that double from its bits, as zucbor's Stage 3 learnt to. Had the
  fixture kept the literal, it would have failed on every x86 runner.
- **The buffer is zubin's, so there is no measuring pass and no
  hand-written owner.** The output and each non-`str` key are a
  `zb_buf` from `zb_r_buf_new()`; zubin's big-endian puts write every
  field. zucbor's per-depth entry pools are gone: each map `R_alloc()`s
  its entries inside its own `vmax` mark, so no pool can outlive the map
  that made it, which is the use after free zucbor's Stage 10 found.
- **The order of `str` keys needs no encoding.** A `str` head grows with
  the length (`0xa0 + n`, then `0xd9`, `0xda`, `0xdb`), so the bytewise
  order of encoded `str` keys is length, then bytes, exactly as in CBOR.
- **Timestamps and data frames are refused until their stages,** as
  planned: `POSIXct`, `Date` and `data.frame` are
  `zumsgpack_unsupported_type`, so a data frame never falls through to
  the named-list path.
- The round-trip property holds over 300 generated values (including
  exts with random types and payloads), every suite case re-encodes to
  one of its listed encodings (numbers aside, whose whole-valued float
  forms come back as integers, §7.2), and the cross-platform fixture is
  1,094 bytes.

---

## Stage 4 — Timestamps, exts, handlers, `as_msgpack()` · M

**Status:** not started.

**Do**

- **Decoding timestamps** (§6.1, D8): `timestamp 32`, `64` and `96` to
  `POSIXct` in UTC under `ext = "convert"` (the default); `ext = "keep"`
  leaves them as `msgpack_ext`. `POSIXct` is kind "classed scalar" in the
  lattice and stays its class (§6.2).
- **Encoding timestamps** (§7.1, §8 rule 5, D7): `POSIXct` as the smallest
  of the three encodings that holds the instant, `Date` at midnight UTC.
  **Decide and write into §8 how a double becomes (seconds,
  nanoseconds)**: floor the seconds, round the fraction to the nearest
  nanosecond, carry at 10^9, and pre-1970 instants as `timestamp 96` with
  negative seconds and non-negative nanoseconds. The rule has to be one a
  big-endian or 32-bit platform computes identically; test values on
  either side of each encoding's boundary (2^32 s, 2^34 s, negative, a
  nanosecond carry).
- **`ext_handlers`** (§6.3): a named list keyed by type −128 … 127 as a
  string; names checked by their digits, not parsed as numbers. A handler
  receives the payload as `raw` and returns any R value, kind "other";
  `"-1"` overrides the timestamp conversion. Handlers run only after the
  check has accepted the whole input. An error inside one is
  `zumsgpack_handler_error` with `type` and `parent`.
- **`as_msgpack()`**, an exported S3 generic: called once for a class the
  encoder does not know; its result is not converted again (only its
  elements are); the default method returns its input; `I()` alone
  neither counts as known nor asks for a call. An error in a method
  propagates unchanged.
- **§18 Q1, closed as recommended:** no `timestamp =` argument; the
  examples article (Stage 8) shows a `"-1"` handler returning seconds and
  nanoseconds as integers.
- The second cross-platform fixture: `POSIXct`, `Date`, an `as_msgpack()`
  method and an `msgpack_ext`, byte-identical on every CI platform. Stage
  3's fixture is unchanged.

**Exit**

- Every timestamp case of the test suite decodes to its instant and
  re-encodes to its bytes when they are in §8 form.
- A `"-1"` handler and an `as_msgpack()` method round-trip a
  nanosecond-exact value.
- A handler that errors, one that returns a huge object, and one that
  calls `msgpack_decode()` again (seeing its own limits, not the outer
  call's) are each tested.
- gctorture, `rchk`, UBSan and ASan clean over the handler and method
  paths; the interrupt test passes with a handler in the input.
- Stage 3's fixture is unchanged.

---

## Stage 5 — Sequences, prefix, stream mode, `msgpack_read_seq(each =)` · M

**Status:** not started.

MessagePack streams are unframed objects back to back (§10): Fluentd
forward, neovim RPC, `msgpack.Unpacker`. This stage makes them readable
in memory bounded by the largest object.

**Do**

- **Prefix mode** and **`msgpack_decode_prefix(x, ...)`**, returning
  `list(value = , consumed = )`. The check covers the first object only;
  the bytes after it are neither read nor trusted, and the documentation
  says so. An empty input is `zumsgpack_parse_error`.
- **Stream mode**: the walk stops without a fault when, and only when, the
  status is truncation (§4: in MessagePack every truncation is "fewer
  bytes than the head or the length says", one status). Anything else is
  a fault at its offset in the stream.
- **`msgpack_read_seq(file, ..., each = NULL)`**. Without `each`, a list
  of every object, the whole source bounded by `max_size`. With a
  function, each object is checked whole, built, passed on and dropped;
  the call returns the count, and `max_size` and `max_items` bound one
  object, not the stream (§12).
- Reading from a connection in blocks, keeping only the unconsumed tail
  between reads.

**Ahead of `zucbor`.** `zucbor` Stage 15 is the same feature and is not
started (checked 2026-10-09). Whichever package lands it first sets the
pattern: write the decisions into this design and file the matching
issue on `zucbor` (principle 8).

**Exit**

- The stream invariants (§15) over every fixture fed in blocks of 1, 2, 3
  and 7 bytes: the same objects as a whole-input decode.
- Every proper prefix of every fixture is truncation in stream mode and
  `zumsgpack_parse_error` in object mode.
- Prefix: trailing garbage, trailing valid objects, an object exactly
  filling the input, and every fixture with random bytes appended.
- 10^6 objects from a connection are read with `each =` in memory bounded
  by the largest object; an interrupt during the read unwinds; a
  malformed object stops the read with its offset in the stream.

---

## Stage 6 — Data frames, annotate, conformance corpus · M

**Status:** not started.

**Do**

- **Data frames** (§6.4, §7.1). Encoding: an array of one `str`-keyed map
  per row, keys sorted like any map's, `NA` as `nil`, row names dropped,
  list columns allowed. Decoding, opt-in with `data_frame = TRUE`: an
  array whose elements are all text-keyed maps becomes a data frame,
  columns in first-seen order, missing keys `NA`, each column through the
  lattice, bounded by `max_cells` before allocation. `zucbor` Stage 14 is
  the same feature, also not started; principle 8 applies.
- **`msgpack_annotate(x, sequence = FALSE, ...)`**: runs after the check;
  one line per head with offset (decimal, 0-based), hex, indentation by
  depth and meaning (`map(2)`, `str(1) "a"`, `ext(-1, 8) timestamp`,
  `float32 1.5`); payloads in rows of 16 bytes so every byte appears
  exactly once; previews capped at 32 bytes and indentation at 16 levels
  so output is bounded by a constant multiple of the input
  (`zucbor` Stage 13's refinement).
- **The rest of the corpus** (§15) through `tools/update-fixtures`:
  `msgpack/msgpack-c`'s test vectors at a pinned revision, and files
  written by Python's `msgpack` at a pinned version through
  `tools/make-fixtures.py` (every §7.1 shape, every integer boundary,
  every timestamp form, a Fluentd forward-mode stream). Manifest entries
  for each.
- **`tools/run-conformance`**: checks every fixture against its source's
  SHA-256 and runs the suites against baselines attributed by rule, not
  by file name, so a new deviation cannot hide inside a known one. It
  runs as the `conformance` job.
- **The oracle**: Python's `msgpack` through `reticulate`, in the
  conformance job only, never in the CRAN suite. Every fixture is
  decoded by both and compared; every §7.1 row is encoded by zumsgpack
  and unpacked by Python.

**Exit**

- Data frames round-trip modulo the documented losses (row names, factor
  levels, column order); the cell budget refuses a quadratic input (rows
  that share no keys) before allocating.
- Every test-suite case annotates with each input byte exactly once,
  checked mechanically.
- The conformance run has zero unexplained deviations and has been seen
  to fail with a baseline lowered and with a rule removed.
- The oracle agrees on every fixture in both directions.

---

## Stage 7 — Hardening: fuzz, mutation, sanitizers, benchmarks · M

**Status:** not started.

**Do**

- **libFuzzer** over the standalone check phase: `fuzz/fuzz_check.c` with
  `zucbor`'s invariants (§4): relaxing an option never rejects what the
  stricter one accepted; a passing object passes as a prefix consuming
  every byte; a prefix consuming n bytes passes as one object over those
  n; every proper prefix of an object is truncation; a pass reports no
  container count larger than the input. Seeds from every fixture and the
  hostile list.
- `fuzz/fuzz_canary.c` must crash through the same code path before any
  real target runs; `tools/run-fuzz` exits non-zero if it does not, and
  captures the fuzzer's own exit status, not a pipe's.
- `hardening.yaml`: two minutes per target on pull requests, thirty
  minutes nightly on a cached corpus.
- **`tools/run-mutation-check`**: disables each `/* GUARD */` in turn in a
  throwaway copy and requires its hostile input's answer to change. It
  refuses to continue when a mutant equals the original. A guard whose
  removal makes the probe abort counts as load-bearing.
- **`tools/run-lint`**: `-Wall -Wextra -Wpedantic -Wshadow -Werror` under
  `-std=gnu17` (§14) over every project source, the standalone build
  included; R's headers as `-isystem`; `init.c` alone with
  `-Wno-cast-function-type`. Seen to fail on a planted warning.
- `tools/check-no-network`: no test opens a connection to the network.
- The R-bound phases (build, encode, annotate) are exercised under the
  sanitizers through `tools/sanitizer-exercise.R` and the property tests,
  as in `zucbor`; design §15 says so if it does not already.
- **`tools/run-benchmarks`** (§16) against `RcppMsgPack` and `zucbor` on
  the same values, not in CI. Record the numbers in design §16.
- `.covrignore` excludes `fuzz/` and the standalone stubs.
- Heavy tests call `skip_heavy()` (`ZUMSGPACK_SKIP_HEAVY`), which the
  gctorture job sets; gctorture runs at the quick step on pull requests
  and at step 100 after merge.

**Exit**

- Every guard is shown load-bearing by the mutation check.
- Zero warnings from project sources under the lint gate.
- The fuzz gate has been seen to fail on its canary, and the nightly job
  is accruing hours with no finding.
- Benchmarks meet §16 (within 1.5× of `zucbor`; faster than `RcppMsgPack`
  on arrays of numbers), or each gap is written into §16 with its
  measured reason.

---

## Stage 8 — Documentation and release 0.1.0 · S

**Status:** not started.

**Do**

- roxygen for every export, with runnable examples; the §6.1, §7.1 and
  §7.2 tables in the help pages; §8's rules stated as zumsgpack's own,
  not the format's.
- A vignette shipped in the tarball: *Decoding untrusted MessagePack*
  (limits, duplicate keys, validation, streams with `each =`). A
  pkgdown-only examples article: the nanosecond timestamp handler (§18
  Q1), a user `ext` type with an `as_msgpack()` method, a Fluentd forward
  stream, switching between `zucbor` and zumsgpack by prefix.
- README: what zumsgpack is, the one-screen mapping, how it differs from
  `RcppMsgPack`, and plainly what it is not (no diagnostic notation, no
  schema, no compatibility `raw` mode).
- `_pkgdown.yml` reference index grouped as §5 groups the API.
- `cran-comments.md`; `inst/WORDLIST`;
  `R CMD check --as-cran --run-donttest` on every CI row.
- **Remove `Remotes:`** and install `zufast` and `zubin` from their CRAN
  tarballs before the final check (§14, R10.3, acceptance criterion 10).
  If either is not on CRAN, the release waits here; nothing else does.
- **The acceptance table.** Verify each §20 criterion explicitly, in a
  table in this file naming the test file, tool or CI job behind it.
  Writing it out is the check: `zuxml` and `zucbor` each found criteria
  backed only by gates nothing else mentioned, or by review rather than
  by a tool, and said so instead of claiming them.

**The human steps.** `main` carries `0.0.0.9000`. At submission, set
`Version: 0.1.0` and the `NEWS.md` heading to `# zumsgpack 0.1.0` in one
commit, check once more, tag `v0.1.0` on `main`, submit
(`devtools::submit_cran()`), and respond to the reviewers. After
acceptance, bump `main` to `0.1.0.9000`, so pkgdown builds the dev site
into `/dev/` and the released docs stay at the root.

**Exit**

- Zero NOTEs beyond "New submission".
- Every §20 criterion has a row in the acceptance table.
- Both cross-platform fixtures still match their Stage 3 and 4 bytes.

---

## Deferred past 0.1.0, with the reason

| Item | Why not now | What would bring it in |
|---|---|---|
| `msgpack_diagnose()` | MessagePack has no standard notation; one would be zumsgpack's invention (§2, D10) | A user who needs to read messages as text, and an agreed notation |
| The pre-2013 `raw` compatibility reading | The current spec requires UTF-8 in `str` (D9) | A protocol that still speaks the old spec |
| A `timestamp = "fields"` argument | The `"-1"` handler covers it (§18 Q1) | Repeated handler recipes in the wild |
| A shared C core with `zucbor` | One format per package; a shared core is a provider with two consumers (§21) | Both packages released and the walks visibly drifting |

## Not planned

Value sharing, string tables and compression (not in the format); a
schema language; a canonical form beyond §8 (§2 *Never*).

---

## Risk register

| Risk | Stage | Mitigation |
|---|---|---|
| `zubin` or `zufast` not on CRAN when the package is ready | 0, 8 | `Remotes:` during development; release blocked only at Stage 8 |
| A provider's header changes under the package | all | `LinkingTo` lower bounds; `zumsgpack_info()` reports the versions built against; Stage 8 rebuilds against CRAN tarballs |
| A length header drives an allocation | 1–2 | Check before build; allocation from the plan only; the 4 GiB and 2^32−1-count regressions; mutation check |
| Duplicate keys let two parsers disagree | 1 | Rejected by value; every comparison class, including positive values in signed forms |
| Encoder output the decoder refuses | 3 | Depth charged identically; property test at `d` and `d + 1` |
| Non-determinism across platforms | 3–4 | `memcmp` key order; floats and timestamps written byte by byte; the (seconds, nanoseconds) rule written down; two cross-platform fixtures |
| `float 32` widening in other decoders changes values | 3 | `float 64` by default (D4); `"shortest"` opt-in and documented |
| A handler's or method's error leaks a buffer | 3–4 | Buffers owned by finalized external pointers (§13); ASan over error paths |
| Truncation mistaken for malformation in stream mode | 5 | Every prefix of every fixture, fed in blocks of 1, 2, 3 and 7 bytes; fuzz invariant |
| Data-frame decoding blows up quadratically | 6 | `max_cells` before allocation |
| zumsgpack and `zucbor` drift apart | all | §6.5 as the one list of differences; principle 8; Stages 5 and 6 land ahead of `zucbor` and set its pattern |
| A gate passes vacuously | 0, 6, 7 | Every gate seen to fail on a canary before it is trusted |

---

## After v1

1. The first real consumer (Stage 0's inventory) and whatever it shows
   the API gets wrong. 1.0.0 follows that.
2. The deferred items above, each when its trigger arrives.
