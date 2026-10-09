# Benchmarks against design section 16's targets. Not in CI: shared runners
# are too noisy to gate on. Run from the package root with zumsgpack,
# zucbor, RcppMsgPack and bench installed:  Rscript tools/benchmarks.R
#
# Each fixture is one R value, encoded once as MessagePack (zumsgpack) and
# once as CBOR (zucbor), so both decoders read the same data. RcppMsgPack
# packs and unpacks the same value; its unpack is called with
# simplify = TRUE, its closest match to zumsgpack's mapping. Every package
# is called through its namespace: RcppMsgPack also exports msgpack_map()
# and msgpack_read().
suppressPackageStartupMessages(library(bench))
set.seed(16)

record <- function(i) list(n = paste0("sensor-", i %% 50), t = 1.7e9 + i,
                           v = round(stats::rnorm(1, 20, 5), 3), u = "Cel", ok = i %% 7 != 0)
fixtures <- list(
  "1 KiB message" = list(alg = -7L, kid = "11", payload = strrep("x", 800),
                         claims = list(iss = "coap://as.example.com", exp = 1444064944L)),
  "100 KiB telemetry" = lapply(1:1200, record),
  "10 MiB document" = lapply(1:120000, record),
  "many tiny items" = as.list(seq_len(500000) %% 100L),
  "large strings" = lapply(1:40, function(i) strrep(letters[i %% 26 + 1], 250000)),
  "1e6 doubles" = stats::runif(1e6)
)

ms <- function(x) as.numeric(x) * 1000
mp_decode <- function(b) zumsgpack::msgpack_decode(b, max_items = Inf, max_size = Inf)
cb_decode <- function(b) zucbor::cbor_decode(b, max_items = Inf, max_size = Inf)
rows <- list()
for (name in names(fixtures)) {
  x <- fixtures[[name]]
  m <- zumsgpack::msgpack_encode(x)
  c <- zucbor::cbor_encode(x)
  r <- tryCatch(RcppMsgPack::msgpackPack(x), error = function(e) NULL)
  dec <- mark(msgpack = mp_decode(m), cbor = cb_decode(c),
              rcpp = if (!is.null(r)) RcppMsgPack::msgpackUnpack(r, simplify = TRUE),
              check = FALSE, min_iterations = 5, time_unit = "s")
  enc <- mark(msgpack = zumsgpack::msgpack_encode(x), cbor = zucbor::cbor_encode(x),
              rcpp = RcppMsgPack::msgpackPack(x),
              check = FALSE, min_iterations = 5, time_unit = "s")
  chk <- mark(zumsgpack::msgpack_validate(m, max_items = Inf, max_size = Inf),
              min_iterations = 5, time_unit = "s")
  rows[[name]] <- data.frame(
    fixture = name, msgpack_kb = round(length(m) / 1024), cbor_kb = round(length(c) / 1024),
    dec_msgpack_ms = ms(dec$median[1]), dec_cbor_ms = ms(dec$median[2]),
    dec_rcpp_ms = if (is.null(r)) NA else ms(dec$median[3]),
    enc_msgpack_ms = ms(enc$median[1]), enc_cbor_ms = ms(enc$median[2]),
    enc_rcpp_ms = ms(enc$median[3]),
    check_share = as.numeric(chk$median[1]) / as.numeric(dec$median[1])
  )
}
res <- do.call(rbind, rows)
rownames(res) <- NULL
res$dec_vs_cbor <- res$dec_msgpack_ms / res$dec_cbor_ms
res$enc_vs_cbor <- res$enc_msgpack_ms / res$enc_cbor_ms
res$dec_vs_rcpp <- res$dec_msgpack_ms / res$dec_rcpp_ms
print(format(res, digits = 3), row.names = FALSE)
cat("\nTargets (design 16): dec_vs_cbor and enc_vs_cbor within 1.5;",
    "dec_vs_rcpp below 1 on arrays of numbers.\n")
