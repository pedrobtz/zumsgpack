# Build information

Reports the versions of the 'zufast' and 'zubin' headers the package was
compiled against, the ceiling on nesting depth, and the default decoding
limits.

## Usage

``` r
zumsgpack_info()
```

## Value

A list of class `zumsgpack_info` with elements:

- `zufast_version`, `zubin_version`: the header versions compiled in.
  Both providers are header-only, so these describe the code inside this
  package, not a library loaded at run time.

- `max_depth_cap`: the largest `max_depth` any function accepts.

- `limits`: the default `max_depth`, `max_size` (bytes), `max_items` and
  `max_cells`.

- `providers_ok`: `TRUE` if a self-test through both providers'
  functions passed.

## Examples

``` r
zumsgpack_info()
#> <zumsgpack_info>
#> zufast:    0.1.0
#> zubin:     0.0.0
#> max_depth: 256 (at most 1023)
#> max_size:  67108864 bytes
#> max_items: 1000000
#> max_cells: 10000000
#> self-test: ok
```
