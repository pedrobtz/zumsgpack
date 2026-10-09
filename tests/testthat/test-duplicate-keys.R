# Keys are compared by value (design section 6.1, zucbor section 6.5); each
# comparison class of the roadmap's Stage 1 list has a case here.

test_that("one integer in every width and signedness is one key", {
  dup_error("82 05 c0 cc 05 c0")
  dup_error("82 05 c0 cd 00 05 c0")
  dup_error("82 05 c0 ce 00 00 00 05 c0")
  dup_error("82 05 c0 cf 00 00 00 00 00 00 00 05 c0")
  # A non-negative value in a signed form, which MessagePack allows.
  dup_error("82 05 c0 d0 05 c0")
  dup_error("82 cc 05 c0 d3 00 00 00 00 00 00 00 05 c0")
  # A map with the same key as fixint, uint 8 and uint 16 (design section 15).
  dup_error("83 01 c0 cc 01 c0 cd 00 01 c0")
})

test_that("one negative integer in every width is one key", {
  dup_error("82 ff c0 d0 ff c0")
  dup_error("82 ff c0 d1 ff ff c0")
  dup_error("82 ff c0 d2 ff ff ff ff c0")
  dup_error("82 ff c0 d3 ff ff ff ff ff ff ff ff c0")
  valid("82 ff c0 01 c0")                       # -1 and 1
  valid("82 d3 80 00 00 00 00 00 00 00 c0 cf 80 00 00 00 00 00 00 00 c0")  # -2^63, 2^63
})

test_that("a float 32 and the float 64 it widens to are one key", {
  dup_error("82 ca 3f 80 00 00 c0 cb 3f f0 00 00 00 00 00 00 c0")
  # Every NaN is one key.
  dup_error("82 cb 7f f8 00 00 00 00 00 00 c0 cb 7f f8 00 00 00 00 00 01 c0")
  dup_error("82 ca 7f c0 00 00 c0 cb 7f f8 00 00 00 00 00 00 c0")
})

test_that("an integer and a float are different keys", {
  valid("82 01 c0 cb 3f f0 00 00 00 00 00 00 c0")
  valid("82 01 c0 ca 3f 80 00 00 c0")
})

test_that("one str in every head is one key, and a bin is a different one", {
  dup_error("82 a1 61 c0 d9 01 61 c0")
  dup_error("82 a1 61 c0 da 00 01 61 c0")
  dup_error("82 a1 61 c0 db 00 00 00 01 61 c0")
  dup_error("82 c4 01 61 c0 c5 00 01 61 c0")
  valid("82 a1 61 c0 c4 01 61 c0")
  valid("82 a0 c0 c4 00 c0")
})

test_that("exts are one key by type and payload, whatever the head", {
  dup_error("82 d4 05 61 c0 c7 01 05 61 c0")
  dup_error("82 d6 05 01 02 03 04 c0 c8 00 04 05 01 02 03 04 c0")
  valid("82 d4 05 61 c0 d4 06 61 c0")
  valid("82 d4 05 61 c0 d4 05 62 c0")
})

test_that("nil and the booleans are keys like any other", {
  dup_error("82 c0 01 c0 02")
  dup_error("82 c3 01 c3 02")
  valid("83 c0 01 c2 02 c3 03")
})

test_that("arrays and maps as keys are compared by their encoded bytes", {
  dup_error("82 91 01 c0 91 01 c0")
  dup_error("82 81 01 02 c0 81 01 02 c0")
  valid("82 91 01 c0 91 02 c0")
  # The same value in two encodings is two keys: a container key is compared
  # by bytes, as zucbor compares one.
  valid("82 91 01 c0 91 cc 01 c0")
  # A map used as a key is itself checked for duplicates.
  dup_error("81 82 01 c0 01 c0 c0")
})

test_that("nested maps keep their own keys", {
  # {"a": {"a": 1}, "b": nil}: the inner "a" is not the outer's.
  valid("82 a1 61 81 a1 61 01 a1 62 c0")
  # The outer map's duplicate is found past a nested map.
  dup_error("82 a1 61 81 a1 61 01 a1 61 c0")
  # A map inside an array inside a map.
  dup_error("81 a1 61 91 82 01 c0 01 c0")
})

test_that("the fault is at the later of the two keys", {
  e <- fault_of(hex_raw("83 01 c0 02 c0 cc 01 c0"))
  expect_s3_class(e, "zumsgpack_duplicate_key")
  expect_identical(e$status, "ZMP_ERR_DUPLICATE_KEY")
  expect_identical(e$offset, 5)
})

test_that("duplicate_keys = TRUE accepts them", {
  expect_true(msgpack_validate(hex_raw("82 01 c0 01 c0"), duplicate_keys = TRUE))
})

test_that("a large map is sorted in O(n log n) and checked", {
  n <- 20000L
  keys <- lapply(seq_len(n) - 1L, function(i)
    as.raw(c(0xcd, i %/% 256L, i %% 256L, 0xc0)))
  head <- as.raw(c(0xde, n %/% 256L, n %% 256L))
  x <- c(head, unlist(rev(keys)))
  t <- system.time(ok <- msgpack_validate(x))
  expect_true(ok)
  expect_lt(t[["elapsed"]], 5)
  # The same map with its last key a copy of its first.
  keys[[n]] <- keys[[1]]
  expect_s3_class(fault_of(c(head, unlist(keys))), "zumsgpack_duplicate_key")
})
