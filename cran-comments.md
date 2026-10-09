## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

* GitHub Actions: macOS (R release), Windows (R release), Ubuntu (R release
  and oldrel-1), and R-devel containers matching CRAN's
  r-devel-linux-x86_64-debian-gcc and -debian-clang flavours.
* Native-code checks on every change: ASan and UBSan (gcc and clang),
  valgrind, gctorture, rchk and LTO.

## Dependencies

The package uses the header-only C libraries of two packages by the same
maintainer through `LinkingTo` alone: zufast and zubin. Both were submitted
to CRAN first, and this package was checked against their CRAN releases.

## Compiled code

No code is vendored. The shared object exports `R_init_zumsgpack` only and
references no console-output or process-exit symbols.
