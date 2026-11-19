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

# 5. Helpers and VoI table functions run, return the expected columns and finite, sensible values.
stopifnot(isTRUE(all.equal(discount(c(100, 100), 10), c(100, 100 / 1.1))),
          isTRUE(all.equal(discount(c(100, 100), 10, calculate_NPV = TRUE), 100 + 100 / 1.1)))
set.seed(1)
stopifnot(length(vv(100, 10, 50)) == 50, all(chance_event(1, 5, 0, n = 20) == 5),
          all(chance_event(0, 5, 0, n = 20) == 0))
tmp <- tempfile(fileext = ".csv")
stopifnot(identical(cached_csv(tmp, data.frame(a = 1)), data.frame(a = 1)), file.exists(tmp),
          cached_csv(tmp, data.frame(a = 2))$a == 1)  # second call reads the cache

dec <- garden_decisions(mc)
tab <- evpi_table(dec)
stopifnot(setequal(tab$school, c("private", "public")), all(is.finite(tab$evpi)), all(tab$evpi >= 0),
          all(tab$best_now %in% colnames(dec$public)))

sub <- x[, c("bureaucratic_barriers", "if_community_likes", "school_event_value")]
single <- evppi_single_all(dec, sub)
stopifnot(nrow(single) == 2 * ncol(sub), all(is.finite(single$evppi)), all(single$evppi >= 0))

rob <- evppi_robustness(dec, sub, single, n_top = 2, B = 20)
stopifnot(nrow(rob) == 4, all(c("gam", "se", "earth", "bart") %in% names(rob)),
          all(is.finite(c(rob$gam, rob$se, rob$earth, rob$bart))))

groups <- garden_input_groups(x)
stopifnot(all(unlist(groups) %in% names(x)))
grp <- withCallingHandlers(evppi_groups_table(dec, x, groups, tab),
  warning = function(w) invokeRestart("muffleWarning"))
stopifnot(nrow(grp) == 2 * length(groups), !anyNA(grp$earth))
# earth can overshoot when the fit is poor (voi issue #8). The numbers are kept but must be flagged,
# and every flagged cell must carry voi's own warning text.
stopifnot(identical(grp$earth_exceeds_evpi, grp$earth > grp$evpi),
          all(grepl("greater than the EVPI", grp$earth_warning[grp$earth_exceeds_evpi])))

sv <- barrier_survey_value(dec, x, sizes = c(10L, 50L))
stopifnot(nrow(sv$studies) == 3, all(is.finite(sv$breakeven$breakeven_schools)), all(sv$breakeven$cost > 0))

par <- mc_pareto_set(mc$y$NPV_garden_inclusive, mc$y$NPV_garden_STEM_inclusive, mc$y$total_costs)
stopifnot(nrow(par) >= 1, nrow(par) <= nrow(mc$y))

cat("All tests passed.\n")
