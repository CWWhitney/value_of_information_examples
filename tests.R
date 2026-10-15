# Run from this folder: Rscript tests.R
#
# Integration sanity checks for the decisionSupport (front end) + voi (back
# end) pipeline used in examples.R. These are approximate, since both the
# Monte Carlo sample and the EVPPI/EVSI regressions have sampling error;
# tolerances are set accordingly.
suppressPackageStartupMessages({
  library(decisionSupport)
  library(voi)
})

near <- function(actual, expected, tolerance) {
  stopifnot(isTRUE(all.equal(unname(actual), expected, tolerance = tolerance,
                              scale = 1)))
}

set.seed(1)

# ------------------------------------------------------------------
# Investment example
# ------------------------------------------------------------------
investment_estimate <- estimate_read_csv("inputs/investment_estimate.csv")
stopifnot(identical(sort(rownames(investment_estimate$marginal)),
                     c("price", "yield")))

investment_model <- function(x) {
  list(no_investment = rep(0, length(x$yield)),
       invest = x$yield * x$price - 100)
}
investment_mc <- mcSimulation(
  estimate = investment_estimate,
  model_function = investment_model,
  numberOfModelRuns = 20000L,
  functionSyntax = "data.frameNames"
)

whole_evpi <- voi::evpi(investment_mc$y)
stopifnot(whole_evpi >= 0)

partial <- voi::evppi(
  investment_mc$y, investment_mc$x,
  pars = list("yield", "price", c("yield", "price"))
)
yield_evppi <- partial$evppi[partial$pars == "yield"]
price_evppi <- partial$evppi[partial$pars == "price"]
joint_evppi <- partial$evppi[partial$pars == "yield,price"]

# Single-variable EVPPI must be nonnegative and bounded above by the
# whole-model EVPI (small MC/regression tolerance).
stopifnot(yield_evppi >= -0.5, yield_evppi <= whole_evpi + 0.5)
stopifnot(price_evppi >= -0.5, price_evppi <= whole_evpi + 0.5)
# The payoff is a deterministic function of yield and price together, so
# learning both should recover (approximately) the whole-model EVPI.
near(joint_evppi, whole_evpi, tolerance = 0.5)
# Known analytical approximate values for this model (posnorm 90% CIs of
# yield in [2,6] and price in [20,40]): whole EVPI and single-variable
# EVPPI should sit near 8.7, 6.6 and 2.7 respectively.
near(whole_evpi, 8.7, tolerance = 1.5)
near(yield_evppi, 6.6, tolerance = 1.5)
near(price_evppi, 2.7, tolerance = 1.5)

sizes <- c(1L, 5L, 20L, 50L)
evsi_sized <- voi::evsi(
  investment_mc$y, investment_mc$x,
  study = "normal_known", pars = "yield", n = sizes,
  aux_pars = list(sd = 1.5)
)
# EVSI must be nonnegative, bounded by the yield EVPPI, and nondecreasing
# as the pilot gets larger.
stopifnot(all(evsi_sized$evsi >= -0.5))
stopifnot(all(evsi_sized$evsi <= yield_evppi + 1))
stopifnot(all(diff(evsi_sized$evsi) >= -0.5))

# ------------------------------------------------------------------
# Complementary information example
# ------------------------------------------------------------------
interaction_estimate <- estimate_read_csv("inputs/interaction_estimate.csv")
interaction_model <- function(x) {
  drought <- x$rainfall_anomaly < 0
  pest_outbreak <- x$pest_pressure_anomaly > 0
  list(keep_old_variety = rep(0, length(x$rainfall_anomaly)),
       adopt_new_variety = ifelse(xor(drought, pest_outbreak), 100, -100))
}
interaction_mc <- mcSimulation(
  estimate = interaction_estimate,
  model_function = interaction_model,
  numberOfModelRuns = 20000L,
  functionSyntax = "data.frameNames"
)

interaction_evpi <- voi::evpi(interaction_mc$y)
# Exact analytical value for this symmetric construction is 50.
near(interaction_evpi, 50, tolerance = 5)

rainfall_evppi <- voi::evppi(interaction_mc$y, interaction_mc$x,
                              pars = "rainfall_anomaly")$evppi
pest_evppi <- voi::evppi(interaction_mc$y, interaction_mc$x,
                          pars = "pest_pressure_anomaly")$evppi
# Neither variable alone should carry much value (exact value is 0).
stopifnot(abs(rainfall_evppi) < 3, abs(pest_evppi) < 3)

joint_bart <- voi::evppi(interaction_mc$y, interaction_mc$x,
                          pars = c("rainfall_anomaly", "pest_pressure_anomaly"),
                          method = "bart", nsim = 5000L)$evppi
joint_earth <- voi::evppi(interaction_mc$y, interaction_mc$x,
                           pars = c("rainfall_anomaly", "pest_pressure_anomaly"),
                           method = "earth")$evppi
# "bart" should recover most of the interaction value; "earth" (an additive
# MARS model with no built-in interaction terms) should find close to none.
stopifnot(joint_bart > 30, abs(joint_earth) < 3)

cat("All value-of-information integration tests passed.\n")
