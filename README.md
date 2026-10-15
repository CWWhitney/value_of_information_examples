# EVPI, EVPPI and EVSI: standalone R examples


Examples, split into a front end and a back end:

- Front end ([decisionSupport](https://cran.r-project.org/package=decisionSupport)):
  uncertain inputs are defined as a 90%-confidence interval with a distribution
  shape per variable, in `inputs/*.csv` (`estimate_read_csv()`). `mcSimulation()` propagates this
  uncertainty through the decision model to produce a Monte Carlo sample of
  inputs and payoffs.
- Back end ([voi](https://chjackson.github.io/voi/)): `evpi()`, `evppi()`
  and `evsi()` compute the value-of-information measures from that sample,
  using regression-based methods that work directly with continuous inputs.

Running the scripts requires the `decisionSupport` and `voi` packages
(`install.packages(c("decisionSupport", "voi"))`). Rendering this optional
document requires `rmarkdown`.

## The distinction

Let U(d, theta) be the payoff from decision d in uncertain state theta.
Choose the decision with the largest expected payoff, not the highest median
or the highest probability of making a profit. This assumes risk neutrality.
With risk aversion, supply utilities instead of monetary payoffs.

Whole-model EVPI is the expected value of learning all decision-relevant
uncertain parameters before choosing:

$$EVPI = E_\theta[\max_d U(d,\theta)] - \max_d E_\theta[U(d,\theta)].$$

The first term allows a different decision in each world. The second requires
one decision now. The difference is the expected loss from deciding with
current information. Include every feasible alternative, including the
status quo. It is not the sum of single-variable information values.

EVPPI (Expected Value of Partial Perfect Information) is the value of
learning one parameter or a group phi perfectly, while uncertainty about the
remaining parameters psi persists:

$$EVPPI(\phi) =
 E_\phi[\max_d E_{\psi|\phi}[U(d,\phi,\psi)]]
 - \max_d E_\theta[U(d,\theta)].$$

The inner expectation must come BEFORE the maximum: knowing yield does not
also reveal price. Preserve the conditional distribution of correlated
parameters rather than resampling them independently. What is often called
"EVPI for a variable" is more precisely single-variable EVPPI.

Small individual EVPPI values do not imply small whole-model EVPI. Inputs can
be complementary: neither is useful alone, but knowing both changes the
decision. The second example demonstrates individual values of zero and a
joint value of 50. EVPPI values are not generally additive.

EVSI (Expected Value of Sample Information) is the value of a specific,
imperfect study. Let D denote possible future data:

$$EVSI =
 E_D[\max_d E_{\theta|D}[U(d,\theta)]] - \max_d E_\theta[U(d,\theta)].$$

It requires a sampling model P(D|theta) and a posterior update. An arbitrary
reduction in an input's standard deviation is not a proper EVSI calculation.
The study can change the chosen decision, but cannot eliminate all uncertainty.
Evaluate it before seeing the data by averaging over possible study results.

For a study that learns only phi through P(D|phi):

$$0 \le EVSI \le EVPPI(\phi) \le EVPI.$$

These are theoretical bounds; approximate Monte Carlo or regression estimates
can violate them because of numerical error or bias. Studies targeting other
parameters need not be bounded by the EVPPI of phi.

Net value of sampling is EVSI minus study cost. An expensive study can have
positive EVSI but negative net value. The examples use the same currency,
decision scale and timing for payoffs and study costs. For real applications,
also account for implementation delay, discounting, the population benefiting
from information, and any direct benefits or harms of the study.

## Run

Open an R session with this folder as the working directory:

```r
source("examples.R")
source("tests.R")
```

The example prints results and creates three CSV tables and a two-panel PDF in
`outputs/`. It deliberately does not modify any other project.

## Example: invest in an agricultural technology?

The uncertain inputs, yield and price, are defined in
[inputs/investment_estimate.csv](inputs/investment_estimate.csv) the way you
would define them for any `decisionSupport` model: a `distribution`, and a
90%-confidence interval (`lower`, `upper`). Both are independent positive
normal (`posnorm`) distributions here:

| variable | distribution | lower (5%) | upper (95%) |
|----------|---------------|-----------:|------------:|
| yield    | posnorm       | 2          | 6           |
| price    | posnorm       | 20         | 40          |

```r
investment_estimate <- decisionSupport::estimate_read_csv("inputs/investment_estimate.csv")
investment_model <- function(x) {
  list(no_investment = rep(0, length(x$yield)),
       invest = x$yield * x$price - 100)
}
investment_mc <- decisionSupport::mcSimulation(
  estimate = investment_estimate,
  model_function = investment_model,
  numberOfModelRuns = 20000,
  functionSyntax = "data.frameNames"
)
```

`investment_mc$x` is the sampled inputs (one row per MC run, one column per
variable) and `investment_mc$y` is the sampled payoffs (one column per
decision): exactly the `inputs`/`outputs` format `voi` expects.

Approximate results from 20,000 Monte Carlo runs (regression-based, so these
will vary slightly run to run and with the regression method chosen):

| Quantity | Currency units |
|----------|---------------:|
| Whole-model EVPI (`voi::evpi`) | ~8.7 |
| Yield EVPPI (`voi::evppi`) | ~6.6 |
| Price EVPPI (`voi::evppi`) | ~2.7 |
| Yield and price together, EVPPI | ~8.7 |

Yield captures most of the whole-model EVPI here, a feature of this toy model
(payoff is close to linear in yield over its range), not a general result.

A pilot study measures mean yield across `n` plots with a known per-plot
standard deviation, using `voi`'s built-in `"normal_known"` sampling design:

```r
sizes <- c(1, 2, 5, 10, 20, 50)
voi::evsi(investment_mc$y, investment_mc$x,
          study = "normal_known", pars = "yield", n = sizes,
          aux_pars = list(sd = 1.5))
```

More pilot plots approach the yield EVPPI; they never learn price. Larger
pilots cost more (`cost = 1 + 0.5 * n` in the example), so net value of
sampling (EVSI minus cost) can fall even as EVSI itself keeps rising; the
example's output shows the net value turning negative beyond a handful of
plots.

## Example: complementary information

Neither of two variables individually changes the decision, but knowing both
does. Inputs are defined the same CSV-based way, in
[inputs/interaction_estimate.csv](inputs/interaction_estimate.csv): a rainfall
anomaly and a pest-pressure anomaly, each normal with a 90% CI straddling
zero. The model adopts a new variety only if a drought (negative rainfall
anomaly) and a pest outbreak (positive pressure anomaly) occur, but not both,
i.e. an `xor`:

```r
interaction_model <- function(x) {
  drought <- x$rainfall_anomaly < 0
  pest_outbreak <- x$pest_pressure_anomaly > 0
  list(keep_old_variety = rep(0, length(x$rainfall_anomaly)),
       adopt_new_variety = ifelse(xor(drought, pest_outbreak), 100, -100))
}
```

The exact (analytical) values for this symmetric construction are
whole-model EVPI = 50, and EVPPI = 0 for each variable alone, but EVPPI = 50
for both together: individually worthless information that is jointly
decisive. `voi::evppi()`'s regression-based single-variable estimates recover
the near-zero values easily. The *joint* EVPPI is a stress test for the
regression method, because there is no additive main-effect signal for a
smoother to pick up on, only a pure interaction:

| Method | Joint EVPPI (true value: 50) |
|--------|------------------------------:|
| `"gam"` (default) | ~32, a substantial underestimate |
| `"earth"` (MARS) | ~0, misses the interaction completely |
| `"bart"` (regression trees) | ~47, the closest of the three |

This is a real, general caveat, not specific to this toy model: always check
whether EVPPI/EVSI estimates for parameter groups are sensitive to the
regression `method`, especially when parameters are suspected to interact, and
prefer methods that can represent interactions (`"bart"`, `"gp"`, or a `"gam"`
with an explicit interaction/tensor term) over purely additive ones
(`"earth"` without manually added interaction terms).

## Important limits

- An arbitrary reduction in an input's standard deviation is not a proper
  EVSI calculation. A study design needs an explicit sampling model, either
  one of `voi`'s built-in designs (`"binary"`, `"trial_binary"`,
  `"normal_known"`) or a custom `datagen_fn`.
- Distinguish learnable parameter uncertainty from irreducible random
  outcomes. If a payoff model simulates future weather or individual
  outcomes, average that randomness conditional on the learnable parameters
  before calculating parameter EVPI; otherwise a clairvoyant forecast of
  events gets valued as if it were parameter knowledge, which can overstate
  what research can deliver.
- `voi`'s regression-based EVPPI/EVSI methods are approximate. As the
  complementary-information example shows, results can differ substantially
  between methods; use `se = TRUE` where supported, increase
  `numberOfModelRuns`, and cross-check with more than one method before
  relying on a single number for a real decision.
- Preserve correlation between inputs. If variables are correlated, supply
  the correlation file to `estimate_read_csv()` (see `?estimate_read_csv`)
  rather than sampling them independently, since conditioning on one
  correlated variable implicitly reveals information about the other.

## Package roles

- [decisionSupport](https://cran.r-project.org/package=decisionSupport)
  (front end): `estimate_read_csv()` reads the 90%-CI/distribution-shape CSV
  format; `mcSimulation()` propagates that uncertainty through a model
  function to produce the Monte Carlo sample of inputs and payoffs. Other
  useful parts of the package for building real models include
  `chance_event()` (binary/categorical risky events), `vv()` (adding
  simulated year-to-year variation), and `discount()` (discounting a cash
  flow series).
- [voi](https://chjackson.github.io/voi/) (back end): `evpi()`,
  `evppi()` and `evsi()` compute the value-of-information measures from that
  sample, with several EVPPI/EVSI methods (`"gam"`, `"gp"`, `"bart"`,
  `"earth"`, `"inla"`, `"so"`, `"sal"` for EVPPI; `"gam"`/other
  regression methods, `"is"`, `"mm"` for EVSI).

Related packages, for cost-effectiveness-analysis-style outputs or a web
interface, include [BCEA](https://gianluca.statistica.it/software/bcea/) and
[SAVI](https://github.com/Sheffield-Accelerated-VoI/SAVI). Check each
package's documentation for its current API and method-specific assumptions.
