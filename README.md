# zumsgpack

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zumsgpack/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zumsgpack/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zumsgpack/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zumsgpack/actions/workflows/coverage.yaml)
<!-- badges: end -->

zumsgpack encodes R values as [MessagePack](https://msgpack.org) and decodes
MessagePack into ordinary R vectors and lists. Input is checked whole, against
size, depth and item limits, before any R object is built; encoding is
deterministic. It follows [zucbor](https://github.com/pedrobtz/zucbor)'s
design, so code written for one reads like code written for the other.

The package is under development; see `.agents/roadmap.md`.

## Installation

``` r
# install.packages("pak")
pak::pak("pedrobtz/zumsgpack")
```
