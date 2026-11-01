# Running the school garden model (decisionSupport front end)

# Read the 90% CI input table (inputs/school_garden_estimate.csv) as a decisionSupport estimate
garden_estimate <- function(file = "inputs/school_garden_estimate.csv") {
  suppressWarnings(decisionSupport::estimate_read_csv(file))
}

# Monte Carlo simulation of the model
run_garden_mc <- function(n = 1e4, seed = 42, estimate = garden_estimate()) {
  set.seed(seed)
  suppressWarnings(decisionSupport::mcSimulation(
    estimate = estimate, model_function = school_garden_function, numberOfModelRuns = n,
    functionSyntax = "plainNames"))
}
