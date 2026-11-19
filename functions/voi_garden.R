# Value-of-information post hoc analysis of the school garden model (voi back end).
# Inputs are a Monte Carlo run from run_garden_mc() and the payoff matrices from garden_decisions().

# Inputs that vary (number_of_years is a constant)
garden_inputs <- function(mc) mc$x[, sapply(mc$x, function(v) length(unique(v)) > 1)]

# Payoff matrices for voi: one column per option, "no garden" = 0 (NPVs are relative to it)
garden_decisions <- function(mc) {
  list(private = cbind(no_garden = 0, garden = mc$y$NPV_garden_inclusive,
                       garden_STEM = mc$y$NPV_garden_STEM_inclusive),
       public  = cbind(no_garden = 0, garden = mc$y$NPV_garden_public_school_inclusive,
                       garden_STEM = mc$y$NPV_garden_STEM_public_school_inclusive))
}

# Whole-model EVPI and the option that is best now, per school type
evpi_table <- function(decisions) {
  data.frame(school = names(decisions),
             best_now = sapply(decisions, function(d) colnames(d)[which.max(colMeans(d))]),
             expected_npv_best = sapply(decisions, function(d) max(colMeans(d))),
             evpi = sapply(decisions, voi::evpi), row.names = NULL)
}

# EVPPI of every input on its own (regression-based, default "gam"); negative regression noise set to 0
evppi_single_all <- function(decisions, x) {
  res <- do.call(rbind, lapply(names(decisions), function(s) {
    data.frame(school = s, input = names(x),
               evppi = sapply(names(x), function(p) voi::evppi(decisions[[s]], x, pars = p)$evppi),
               row.names = NULL)
  }))
  res$evppi <- pmax(res$evppi, 0)
  res[order(res$school, -res$evppi), ]
}

# Bootstrap standard errors (evppi(se = TRUE)) and the "earth" and "bart" regression methods for
# the `n_top` largest single-input EVPPIs of each school type: is the ranking signal or noise?
evppi_robustness <- function(decisions, x, single_evppi, n_top = 5, B = 500) {
  res <- do.call(rbind, lapply(names(decisions), function(s) {
    p <- head(single_evppi$input[single_evppi$school == s], n_top)
    g <- voi::evppi(decisions[[s]], x, pars = as.list(p), se = TRUE, B = B)
    by_method <- function(m) pmax(sapply(p, function(i) voi::evppi(decisions[[s]], x, pars = i, method = m)$evppi), 0)
    data.frame(school = s, input = g$pars, gam = pmax(g$evppi, 0), se = g$se,
               earth = by_method("earth"), bart = by_method("bart"), row.names = NULL)
  }))
  # estimates below 0.01 million VND are numerically zero, whatever their SE
  res$gam_above_2se <- res$gam > 0.01 & res$gam > 2 * res$se
  res
}

# Groups of inputs for grouped EVPPI
garden_input_groups <- function(x) {
  prob <- grep("^if_|^land_|^suit|^bureau|^chance_", names(x), value = TRUE)
  list(access_barriers = c("land_access", "suitability_of_land_for_garden", "bureaucratic_barriers"),
       engagement_risks = c("if_students_like", "if_parents_like", "if_community_likes", "if_effective_manage"),
       health_values = c("child_garden_health_care_savings", "child_garden_school_performance_value",
                         "child_STEM_health_care_savings", "garden_mental_health_value"),
       all_probabilities = prob, all_values = setdiff(names(x), prob))
}

# Grouped EVPPI by regression method. "gam" handles up to 4 inputs; "earth" any number.
# earth's default model is additive (no interactions), which can fit poorly and push EVPPI above EVPI
# (voi issue #8). The voi author's advice is to raise `degree` to allow interactions and to check that the
# estimate is stable between degrees (2 vs 3). We do that and keep every number the function returns,
# including impossible ones: voi's own warning text (warn_evppi_gt_evpi) goes in `earth_warning` and
# `earth_exceeds_evpi` flags the cells where the fit has failed, so the report can explain them.
evppi_earth <- function(decision, x, pars, degree) {
  msg <- NA_character_
  val <- withCallingHandlers(
    tryCatch(voi::evppi(decision, x, pars = list(pars), method = "earth", degree = degree)$evppi,
             error = function(e) NA_real_),
    warning = function(w) { msg <<- conditionMessage(w); invokeRestart("muffleWarning") })
  list(value = val, warning = msg)
}

evppi_groups_table <- function(decisions, x, groups, evpi_tab, degree = 2, check_degree = degree + 1) {
  res <- do.call(rbind, lapply(names(decisions), function(s) {
    do.call(rbind, lapply(names(groups), function(g) {
      pars <- groups[[g]]
      gam <- if (length(pars) <= 4)
        tryCatch(voi::evppi(decisions[[s]], x, pars = list(pars), method = "gam")$evppi, error = function(e) NA_real_)
      else NA_real_
      e <- evppi_earth(decisions[[s]], x, pars, degree)
      e2 <- evppi_earth(decisions[[s]], x, pars, check_degree)
      data.frame(school = s, group = g, n_inputs = length(pars), gam = gam,
                 earth = e$value, earth_check_degree = e2$value, earth_warning = e$warning, row.names = NULL)
    }))
  }))
  res <- merge(res, evpi_tab[, c("school", "evpi")], by = "school")
  res$earth_exceeds_evpi <- !is.na(res$earth) & res$earth > res$evpi
  if (any(res$earth_exceeds_evpi))
    warning("earth EVPPI exceeds the EVPI (voi: \"", unique(na.omit(res$earth_warning))[1], "\") for ",
            paste(res$school[res$earth_exceeds_evpi], res$group[res$earth_exceeds_evpi], collapse = "; "),
            ". Values are kept; see earth_check_degree for degree = ", check_degree, ".", call. = FALSE)
  res
}

# ---- EVSI: a survey of n public schools about bureaucratic barriers ---------------------------
# Each surveyed school independently reports a barrier with probability `bureaucratic_barriers`.
barrier_study <- function(inputs, n = 20) {
  data.frame(barriers_seen = rbinom(nrow(inputs), n, inputs[, "bureaucratic_barriers"]))
}

# Study cost is an illustrative assumption (setup 2 + 0.5 per school surveyed, million VND), as are
# the 5-year horizon and 5% continuous discount rate; the number of schools is NOT taken from any source.
barrier_survey_value <- function(decisions, x, sizes = c(5L, 10L, 20L, 50L, 100L),
                                 costs_setup = 2, costs_pp = 0.5, time = 5, dis = 0.05,
                                 pop_grid = c(10, 50, 100, 500, 1000, 5000)) {
  evsi <- voi::evsi(decisions$public, x, study = NULL, pars = "bureaucratic_barriers",
                    datagen_fn = barrier_study, n = sizes, check = TRUE)
  evsi$k <- 1  # no willingness-to-pay threshold: payoffs are already monetary
  enbs <- voi::enbs(evsi, costs_setup = costs_setup, costs_pp = costs_pp, pop = pop_grid, time = time, dis = dis)
  best <- as.data.frame(attr(enbs, "enbsmax"))
  best$pop <- pop_grid[best$ind]
  cost <- costs_setup + costs_pp * sizes
  breakeven <- data.frame(n_survey = sizes, evsi_per_school = evsi$evsi, cost = cost,
                          breakeven_schools = cost / voi::pop_voi(evsi$evsi, 1, time, dis))
  studies <- data.frame(n = c(0L, sizes), evsi = c(0, evsi$evsi), cost = c(0, cost))
  studies$net_value <- studies$evsi - studies$cost
  list(evsi = evsi, enbs_best = best[, c("pop", "nmax", "enbsmax")], breakeven = breakeven, studies = studies)
}

# ---- Pareto-optimal draws of the Monte Carlo sample itself (not the optimisation) --------------
mc_pareto_set <- function(econ, health, biodiv) {
  d <- data.frame(economic_return = econ, child_health = health, biodiversity = biodiv)
  rPref::psel(d, rPref::high(economic_return) * rPref::high(child_health) * rPref::high(biodiversity))
}
