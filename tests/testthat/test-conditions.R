test_that("every status C can report maps to a class", {
  statuses <- .Call(zmp_status_names)
  missing <- setdiff(statuses, names(zmp_status_class))
  expect_identical(missing, character())
  # ... and the map names nothing C cannot report.
  expect_identical(setdiff(names(zmp_status_class), statuses), character())
})

test_that("every condition inherits zumsgpack_error with offset and status", {
  e <- fault_of(hex_raw("92 01"))
  expect_s3_class(e, "zumsgpack_parse_error")
  expect_s3_class(e, "zumsgpack_error")
  expect_identical(e$status, "ZMP_ERR_TRUNCATED")
  expect_identical(e$offset, 0)
  expect_match(conditionMessage(e), "at byte 0")
})

test_that("the call attached is the user's", {
  e <- tryCatch(msgpack_validate(hex_raw("c1"), error = TRUE), error = identity)
  expect_identical(e$call[[1]], quote(msgpack_validate))
})
