# Loads every function of this repository (run from the repository root, or from an Rmd in it):
#   source("functions/load_all.R")
suppressPackageStartupMessages(library(decisionSupport))
for (f in c("vv", "chance_event", "discount",             # decisionSupport helpers used by the model
            "school_garden_model",                        # the model (Whitney et al.)
            "run_garden_mc",                               # running the model
            "voi_garden",                                 # value of information (voi)
            "evppi_many_inputs",                          # EVPPI of many inputs: variants and control
            "utils"))                                      # small generic helpers
  source(file.path("functions", paste0(f, ".R")))
