# Default decoding limits, design section 12. Every decode entry point takes
# its defaults from here, so zumsgpack_info() reports what the decoder
# enforces.
zmp_default_limits <- function() {
  list(max_depth = 256L, max_size = 64 * 1024^2, max_items = 1e6, max_cells = 1e7)
}

#' Build information
#'
#' Reports the versions of the 'zufast' and 'zubin' headers the package was
#' compiled against, the ceiling on nesting depth, and the default decoding
#' limits.
#'
#' @return A list of class `zumsgpack_info` with elements:
#'   * `zufast_version`, `zubin_version`: the header versions compiled in.
#'     Both providers are header-only, so these describe the code inside
#'     this package, not a library loaded at run time.
#'   * `max_depth_cap`: the largest `max_depth` any function accepts.
#'   * `limits`: the default `max_depth`, `max_size` (bytes), `max_items`
#'     and `max_cells`.
#'   * `providers_ok`: `TRUE` if a self-test through both providers'
#'     functions passed.
#' @export
#' @examples
#' zumsgpack_info()
zumsgpack_info <- function() {
  info <- .Call(zmp_build_info)
  structure(
    list(
      zufast_version = info$zufast_version,
      zubin_version = info$zubin_version,
      max_depth_cap = info$max_depth_cap,
      limits = zmp_default_limits(),
      providers_ok = info$providers_ok
    ),
    class = "zumsgpack_info"
  )
}

#' @export
format.zumsgpack_info <- function(x, ...) {
  lim <- x$limits
  c(
    "<zumsgpack_info>",
    paste0("zufast:    ", x$zufast_version),
    paste0("zubin:     ", x$zubin_version),
    paste0("max_depth: ", lim$max_depth, " (at most ", x$max_depth_cap, ")"),
    paste0("max_size:  ", format(lim$max_size, scientific = FALSE), " bytes"),
    paste0("max_items: ", format(lim$max_items, scientific = FALSE)),
    paste0("max_cells: ", format(lim$max_cells, scientific = FALSE)),
    paste0("self-test: ", if (isTRUE(x$providers_ok)) "ok" else "FAILED")
  )
}

#' @export
print.zumsgpack_info <- function(x, ...) {
  writeLines(format(x, ...))
  invisible(x)
}
