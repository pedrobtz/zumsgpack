test_that("both providers' functions link and work", {
  expect_true(zumsgpack_info()$providers_ok)
})

test_that("the provider versions are reported as strings", {
  info <- zumsgpack_info()
  expect_match(info$zufast_version, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_match(info$zubin_version, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
})

test_that("the depth ceiling is zucbor's", {
  expect_identical(zumsgpack_info()$max_depth_cap, 1023L)
})

test_that("default limits are the design's", {
  lim <- zumsgpack_info()$limits
  expect_identical(lim$max_depth, 256L)
  expect_identical(lim$max_size, 64 * 1024^2)
  expect_identical(lim$max_items, 1e6)
  expect_identical(lim$max_cells, 1e7)
  expect_lte(lim$max_depth, zumsgpack_info()$max_depth_cap)
})

test_that("zumsgpack_info() prints without error", {
  expect_output(print(zumsgpack_info()), "self-test: ok", fixed = TRUE)
})
