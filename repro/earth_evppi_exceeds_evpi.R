# Standalone reproduction: voi::evppi(method = "earth") larger than voi::evpi().
# Needs only the voi and earth packages and repro/private_school_voi_data.rds
# (payoffs: 10,000 x 3 net-benefit matrix; inputs: 10,000 x 84 data frame; pars: 64 input names).
library(voi)
d <- readRDS("repro/private_school_voi_data.rds")
cat("EVPI:", evpi(d$payoffs), "\n")
cat("EVPPI earth, 64 inputs:", evppi(d$payoffs, d$inputs, pars = list(d$pars), method = "earth")$evppi, "\n")
# Smaller N, same data: does the excess depend on sample size?
for (n in c(1000, 2500, 5000)) {
  i <- seq_len(n)
  cat(n, "EVPI", round(evpi(d$payoffs[i, ]), 1), "EVPPI earth",
      round(evppi(d$payoffs[i, ], d$inputs[i, ], pars = list(d$pars), method = "earth")$evppi, 1), "\n")
}
