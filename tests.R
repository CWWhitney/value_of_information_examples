# Run from this folder: Rscript tests.R
#
# Sanity checks for the school garden analysis (functions in functions/). Approximate where Monte Carlo
# or regression error is involved; tolerances are set accordingly.
suppressPackageStartupMessages(library(voi))
source("functions/load_all.R")
est <- garden_estimate()

# 1. Every variable in the input table is used by the model.
vars <- rownames(est$marginal)
model_text <- paste(readLines("functions/school_garden_model.R"), collapse = " ")
stopifnot(all(sapply(vars, grepl, x = model_text, fixed = TRUE)))

# 2. land_access matters for the public-school NPV: a higher chance of having land gives a
#    higher mean NPV.
est_land <- function(lo, hi) { e <- est; e$marginal["land_access", c("lower", "upper")] <- c(lo, hi); e }
mean_public_npv <- function(e) mean(run_garden_mc(n = 4000, seed = 2, estimate = e)$y$NPV_garden_public_school_inclusive)
stopifnot(mean_public_npv(est_land(0.9, 0.99)) > mean_public_npv(est_land(0.1, 0.3)))

# 3. Private-school results are not affected by the public-school failure events: costs in years
#    2+ are never zeroed, so total costs are positive in every run.
mc <- run_garden_mc(n = 3000, seed = 1)
stopifnot(all(mc$y$total_costs > 0), all(mc$y$total_costs_STEM > 0))

# 4. VoI sanity: EVPI >= 0, EVPPI of an input <= EVPI (+ regression noise); bootstrap SEs are returned;
#    pop_voi() follows its documented formula; enbs() runs on an evsi-style data frame.
x <- garden_inputs(mc)
pub <- garden_decisions(mc)$public
whole <- voi::evpi(pub)
stopifnot(whole >= 0)
for (p in c("bureaucratic_barriers", "school_event_value", "if_community_likes"))
  stopifnot(voi::evppi(pub, x, pars = p)$evppi <= 1.1 * whole)
stopifnot(voi::evppi(pub, x, pars = list(names(x)), method = "earth")$evppi <= 1.1 * whole)
g <- voi::evppi(pub, x, pars = list("bureaucratic_barriers"), se = TRUE, B = 100)
stopifnot(is.finite(g$se), g$se > 0)
stopifnot(isTRUE(all.equal(voi::pop_voi(2, 100, 5, 0.05), 2 * 100 / 0.05 * (1 - exp(-0.05 * 5)))))
ev <- data.frame(n = c(10, 50), k = 1, evsi = c(1, 2))
en <- voi::enbs(ev, costs_setup = 2, costs_pp = 0.5, pop = 100, time = 5, dis = 0.05)
stopifnot(all(is.finite(en$enbs)), nrow(attr(en, "enbsmax")) == 1)

# 5. Cache: a saved result is reused only while its key is unchanged.
f <- tempfile(fileext = ".csv")
invisible(cached_csv(f, data.frame(a = 1), key = "k1"))
stopifnot(cached_csv(f, data.frame(a = 2), key = "k1")$a == 1)   # same key: reused
stopifnot(cached_csv(f, data.frame(a = 2), key = "k2")$a == 2)   # key changed: recomputed
stopifnot(cached_csv(f, data.frame(a = 3), key = "k2", refresh = TRUE)$a == 3)
stopifnot(nchar(cache_key()) == 32, cache_key() != cache_key("other"))

# 6. README.md tables agree with the saved CSVs in outputs/ (README.md is built from README.Rmd).
readme <- readLines("README.md")
md_table <- function(header) {
  start <- grep(header, readme)[1]
  stopifnot(!is.na(start))
  end <- start
  while (end < length(readme) && startsWith(readme[end + 1], "|")) end <- end + 1
  body <- sub("\\|\\s*$", "", sub("^\\|", "", readme[c(start, (start + 2):end)]))
  rows <- strsplit(body, "|", fixed = TRUE)
  rows <- lapply(rows, function(r) gsub("`", "", trimws(r)))
  tab <- as.data.frame(do.call(rbind, rows[-1]), stringsAsFactors = FALSE)
  names(tab) <- rows[[1]]
  tab
}
num <- function(v) suppressWarnings(as.numeric(gsub("[~<\\\\ ]", "", v)))
near <- function(readme_value, csv_value, digits) stopifnot(abs(num(readme_value) - csv_value) <= 0.5 * 10^-digits + 1e-9)

evpi_csv <- read.csv("outputs/evpi.csv")
evpi_md <- md_table("^\\| *School +\\| *Best option now")
for (i in seq_len(nrow(evpi_md))) {
  r <- evpi_csv[tolower(evpi_csv$school) == tolower(evpi_md$School[i]), ]
  stopifnot(r$best_now == evpi_md[["Best option now"]][i])
  near(evpi_md[["Expected NPV"]][i], r$expected_npv_best, 0)
  near(evpi_md$EVPI[i], r$evpi, 0)
}

rob_csv <- read.csv("outputs/evppi_robustness.csv")
rob_md <- md_table("^\\| *School +\\| *Input")
for (i in seq_len(nrow(rob_md))) {
  r <- rob_csv[tolower(rob_csv$school) == tolower(rob_md$School[i]) & rob_csv$input == rob_md$Input[i], ]
  if (nrow(r) == 1) {
    near(rob_md$gam[i], r$gam, 1); near(rob_md$SE[i], r$se, 1)
    near(rob_md$earth[i], r$earth, 1); near(rob_md$bart[i], r$bart, 1)
  } else {   # summary row for the five private-school inputs: everything below the stated bound
    p <- rob_csv[rob_csv$school == "private", ]
    stopifnot(all(p$gam < 0.1), all(p$earth < 0.1), all(p$bart < 0.4))
  }
}

evsi_csv <- read.csv("outputs/evsi_bureaucratic_barriers.csv")
evsi_md <- md_table("^\\| *Survey size n")
stopifnot(identical(num(evsi_md[["Survey size n"]]), as.numeric(evsi_csv$n)))
for (i in seq_len(nrow(evsi_csv))) {
  if (!evsi_csv$noisy[i] || evsi_csv$evsi_per_school[i] > 0.01) {
    near(evsi_md[["EVSI per school"]][i], evsi_csv$evsi_per_school[i], 2)
    near(evsi_md[["Value for 100 schools"]][i], evsi_csv$value_pop_ref[i], 0)
    near(evsi_md[["Break-even schools"]][i], read.csv("outputs/evsi_breakeven_schools.csv")$breakeven_schools[i], 1)
  }
  near(evsi_md[["Study cost"]][i], evsi_csv$cost[i], 1)
  stopifnot(identical(evsi_md$Noisy[i] == "yes", evsi_csv$noisy[i]))
}
# EVPPI cannot exceed EVPI
stopifnot(all(read.csv("outputs/evppi_single.csv")$evppi <= 1.1 * max(evpi_csv$evpi)))

cat("All tests passed.\n")
