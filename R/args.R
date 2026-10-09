# Argument checks shared by every entry point. A limit is a security
# property: one silently replaced by a default, or truncated from a
# fraction, is a limit the caller did not set (design section 12).

zmp_arg_raw <- function(x, arg = "x", call = NULL) {
  if (!is.raw(x)) {
    zmp_invalid_argument(arg, sprintf(
      "`%s` must be a raw vector, not %s; MessagePack is bytes.", arg,
      zmp_describe(x)), call)
  }
  invisible(x)
}

zmp_arg_flag <- function(x, arg, call = NULL) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    zmp_invalid_argument(arg, sprintf("`%s` must be TRUE or FALSE.", arg), call)
  }
  invisible(x)
}

# A positive whole number no larger than `max`, or Inf where `allow_inf`.
# `max` is the largest finite value C can take exactly.
zmp_arg_limit <- function(x, arg, max, allow_inf, call = NULL) {
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 1 &&
    (is.infinite(x) && allow_inf || is.finite(x) && x == trunc(x) && x <= max)
  if (!ok) {
    range <- if (allow_inf)
      sprintf("a whole number from 1 to %s, or Inf", format(max, scientific = FALSE))
    else sprintf("a whole number from 1 to %s", format(max, scientific = FALSE))
    zmp_invalid_argument(arg, sprintf("`%s` must be %s.", arg, range), call)
  }
  invisible(x)
}

zmp_arg_limits <- function(max_depth, max_size, max_items, call = NULL) {
  zmp_arg_limit(max_depth, "max_depth", zmp_max_depth_cap(), allow_inf = FALSE, call)
  zmp_arg_limit(max_size, "max_size", 2^53, allow_inf = TRUE, call)
  zmp_arg_limit(max_items, "max_items", 2^53, allow_inf = TRUE, call)
}

zmp_max_depth_cap <- function() 1023L

zmp_describe <- function(x) {
  if (is.null(x)) "NULL" else sprintf("a %s vector", typeof(x))
}

# Check modes, as src/zmp_check.h numbers them.
zmp_mode <- c(one = 0L, seq = 1L, prefix = 2L, stream = 3L)
