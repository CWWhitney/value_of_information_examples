# Joint EVPPI for a large group of inputs: variants and a negative control (see evppi_many_inputs.Rmd).
# Regression-based EVPPI is biased upwards when many inputs are used; a permutation control (payoff rows
# shuffled relative to the inputs, so the true EVPPI is exactly 0) measures that bias for each method.

# EVPPI of the group `pars` for one regression variant; voi's own "EVPPI > EVPI" warning is captured, not shown
evppi_one <- function(pay, x, pars, method, ...) {
  warned <- FALSE
  t <- system.time(v <- withCallingHandlers(
    voi::evppi(pay, x, pars = list(pars), method = method, ...)$evppi,
    warning = function(w) { warned <<- grepl("greater than the EVPI", conditionMessage(w)); invokeRestart("muffleWarning") }))
  data.frame(evppi = v, voi_warned = warned, seconds = unname(t[3]))
}

# Each variant on the real data and on the permutation control
evppi_variants <- function(pay, x, pars, variants, seed = 42) {
  evpi <- voi::evpi(pay)
  set.seed(seed)
  pay_null <- pay[sample(nrow(pay)), , drop = FALSE]
  do.call(rbind, lapply(names(variants), function(v) {
    a <- variants[[v]]
    real <- do.call(evppi_one, c(list(pay, x, pars, a$method), a$args))
    null <- do.call(evppi_one, c(list(pay_null, x, pars, a$method), a$args))
    data.frame(variant = v, evpi = evpi, evppi = real$evppi, above_evpi = real$evppi > evpi,
               null_evppi = null$evppi, corrected = real$evppi - null$evppi, seconds = real$seconds,
               row.names = NULL)
  }))
}
