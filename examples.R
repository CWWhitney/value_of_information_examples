# Run from this folder: Rscript examples.R
#
# Front end:  decisionSupport, for uncertain inputs defined as 90%-CI estimates
#             in inputs/*.csv (estimate_read_csv) and their propagation through
#             a model (mcSimulation).
# Back end:   voi, for the value-of-information calculations themselves
#             (evpi, evppi, evsi) on the resulting Monte Carlo sample.
suppressPackageStartupMessages({
  library(decisionSupport)
  library(voi)
})
set.seed(2026)
dir.create("outputs", showWarnings = FALSE)

# ------------------------------------------------------------------
# Example: invest in a hypothetical agricultural technology?
# Uncertain inputs (yield, price) are defined in inputs/investment_estimate.csv
# as decisionSupport-style 90% confidence intervals with a distribution shape.
# ------------------------------------------------------------------
investment_estimate <- estimate_read_csv("inputs/investment_estimate.csv")
cat("\nInput distributions (90% CI), as read from CSV:\n")
print(investment_estimate)

# decisionSupport calls this once, with x's columns as whole MC-sample vectors.
investment_model <- function(x) {
  list(
    no_investment = rep(0, length(x$yield)),
    invest = x$yield * x$price - 100
  )
}

investment_mc <- mcSimulation(
  estimate = investment_estimate,
  model_function = investment_model,
  numberOfModelRuns = 20000L,
  functionSyntax = "data.frameNames"
)

cat("\nWhole-model EVPI (voi::evpi on the MC sample):\n")
print(voi::evpi(investment_mc$y))

partial <- voi::evppi(
  investment_mc$y, investment_mc$x,
  pars = list("yield", "price", c("yield", "price"))
)
cat("\nSingle-variable and grouped EVPPI (voi::evppi, regression-based):\n")
print(partial)

# A pilot study measures mean yield across n plots (known per-plot SD), using
# voi's built-in "normal_known" sampling design. Larger pilots approach the
# yield EVPPI; they never learn price.
sizes <- c(1L, 2L, 5L, 10L, 20L, 50L)
evsi_sized <- voi::evsi(
  investment_mc$y, investment_mc$x,
  study = "normal_known", pars = "yield", n = sizes,
  aux_pars = list(sd = 1.5)
)
study_cost <- 1 + 0.5 * sizes
studies <- rbind(
  data.frame(n = 0L, evsi = 0, cost = 0, net_value = 0),
  data.frame(n = sizes, evsi = evsi_sized$evsi, cost = study_cost,
             net_value = evsi_sized$evsi - study_cost)
)
cat("\nEVSI and net value of sampling by pilot size (voi::evsi):\n")
print(studies)

# ------------------------------------------------------------------
# Example: complementary information. Neither variable alone changes the
# decision, but knowing both does. Inputs are defined the same CSV-based way,
# in inputs/interaction_estimate.csv.
# ------------------------------------------------------------------
interaction_estimate <- estimate_read_csv("inputs/interaction_estimate.csv")
interaction_model <- function(x) {
  drought <- x$rainfall_anomaly < 0
  pest_outbreak <- x$pest_pressure_anomaly > 0
  list(
    keep_old_variety = rep(0, length(x$rainfall_anomaly)),
    adopt_new_variety = ifelse(xor(drought, pest_outbreak), 100, -100)
  )
}
interaction_mc <- mcSimulation(
  estimate = interaction_estimate,
  model_function = interaction_model,
  numberOfModelRuns = 20000L,
  functionSyntax = "data.frameNames"
)

whole_evpi <- voi::evpi(interaction_mc$y)
rainfall_evppi <- voi::evppi(interaction_mc$y, interaction_mc$x,
                              pars = "rainfall_anomaly")$evppi
pest_evppi <- voi::evppi(interaction_mc$y, interaction_mc$x,
                          pars = "pest_pressure_anomaly")$evppi
# The default "gam" method smooths across the discontinuity in this pure
# interaction model and underestimates its EVPPI; "bart" (regression trees)
# captures the interaction much better. See the EVPPI method comparison below.
joint_evppi <- voi::evppi(interaction_mc$y, interaction_mc$x,
                           pars = c("rainfall_anomaly", "pest_pressure_anomaly"),
                           method = "bart", nsim = 5000L)$evppi
cat("\nComplementary information example:\n")
print(c(whole_evpi = whole_evpi, rainfall_evppi = rainfall_evppi,
        pest_evppi = pest_evppi, both_evppi_bart = joint_evppi))

# Joint EVPPI method comparison: a pure interaction effect, with no additive
# main-effect signal, is a stress test for regression-based EVPPI methods.
method_comparison <- data.frame(
  method = c("gam", "earth", "bart"),
  joint_evppi = c(
    voi::evppi(interaction_mc$y, interaction_mc$x,
               pars = c("rainfall_anomaly", "pest_pressure_anomaly"),
               method = "gam")$evppi,
    voi::evppi(interaction_mc$y, interaction_mc$x,
               pars = c("rainfall_anomaly", "pest_pressure_anomaly"),
               method = "earth")$evppi,
    joint_evppi
  )
)
cat("\nJoint EVPPI by regression method (true value is close to whole-model EVPI):\n")
print(method_comparison)

write.csv(partial, "outputs/evppi.csv", row.names = FALSE)
write.csv(studies, "outputs/study_designs.csv", row.names = FALSE)
write.csv(method_comparison, "outputs/interaction_evppi_methods.csv", row.names = FALSE)

pdf("outputs/value_of_information.pdf", width = 9, height = 4)
par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
barplot(c(EVPI = voi::evpi(investment_mc$y),
          Yield = partial$evppi[partial$pars == "yield"],
          Price = partial$evppi[partial$pars == "price"]),
        ylab = "Currency units", main = "Perfect information", col = "steelblue")
plot(studies$n, studies$evsi, type = "b",
     ylim = range(c(0, studies$net_value, partial$evppi[partial$pars == "yield"])),
     xlab = "Number of pilot plots", ylab = "Currency units",
     main = "Sample information", col = "steelblue", pch = 16)
lines(studies$n, studies$net_value, type = "b", col = "darkorange", pch = 17)
abline(h = partial$evppi[partial$pars == "yield"], lty = 2)
legend("bottomright", c("EVSI", "EVSI minus study cost", "Yield EVPPI"),
       col = c("steelblue", "darkorange", "black"), lty = c(1, 1, 2), bty = "n")
invisible(dev.off())
