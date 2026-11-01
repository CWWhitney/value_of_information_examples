
<!-- README.md is built from README.Rmd. Do not edit README.md directly;
     edit README.Rmd and rebuild with:
     Rscript -e 'rmarkdown::render("README.Rmd")' -->

# EVPI, EVPPI and EVSI: value of information for the Hanoi school garden decision

Value-of-information (VoI) analysis of a real decision model: should
urban Hanoi schools build a school garden, with or without a formal STEM
education programme, rather than keep using the land for play space or
parking? The model is the CODAS / NIFAM school garden model of Whitney
et al. ([2026](#ref-whitney2026garden)) (original code:
[nifam_codas_school_garden](https://github.com/CWWhitney/nifam_codas_school_garden)),
and the analysis is split front end / back end:

- Front end,
  [decisionSupport](https://cran.r-project.org/package=decisionSupport):
  the 84 uncertain inputs are defined in
  [inputs/school_garden_estimate.csv](inputs/school_garden_estimate.csv)
  as 90%-confidence intervals with a distribution shape
  (`estimate_read_csv()`); values combine figures reported in the
  underlying studies with structured estimates from experts and
  estimation tools where no study exists. `mcSimulation()` propagates
  them through the model in
  [functions/school_garden_model.R](functions/school_garden_model.R) to
  give a Monte Carlo sample of inputs and payoffs (net present value,
  NPV, in million VND relative to the no-garden use of the land).
- Back end, [voi](https://chjackson.github.io/voi/): `evpi()`, `evppi()`
  and `evsi()` compute the value-of-information measures from that
  sample. The Pareto trade-offs (economic return, child health,
  biodiversity) are extracted with
  [rPref](https://cran.r-project.org/package=rPref).

This file is generated from [README.Rmd](README.Rmd); references come
from [bib/references.bib](bib/references.bib). Edit `README.Rmd`, not
`README.md`, and rebuild with
`Rscript -e 'rmarkdown::render("README.Rmd")'`.

Install with `install.packages(c("decisionSupport", "voi", "rPref"))`.

## How the repository is organised

Functions are in `functions/*.R` (`functions/load_all.R` loads them
all); the analysis is an R Markdown document that calls those functions
and saves its results in `outputs/`:

| Document | What it does |
|----|----|
| [value_of_information.Rmd](value_of_information.Rmd) | Value of information with `voi`: EVPI, EVPPI (with standard errors), EVSI, population value and net benefit of sampling |

``` r
rmarkdown::render("value_of_information.Rmd")   # add params = list(refresh = TRUE) to recompute
source("tests.R")                                # sanity checks
```

## What EVPI, EVPPI and EVSI mean

Choose the decision with the largest *expected* payoff, classical
decision theory ([Raiffa and Schlaifer 1961](#ref-raiffa1961)).

**EVPI** — how much better off we'd be, on average, if we could see
every uncertain input's true value before deciding, versus deciding now
(e.g. "do nothing").

**EVPPI** — the same idea for one input (or group), while the rest stay
uncertain; introduced to health-economic modelling by Felli and Hazen
([1998](#ref-felli1998)). For example, learning one input doesn't also
reveal the others, so we still need to average over the others before
deciding. Inputs can also be individually worthless but jointly decisive
(see the grouped EVPPI below). `voi::evppi()` estimates this with a
regression fitted to the Monte Carlo sample ([Strong et al.
2014](#ref-strong2014)).

**EVSI** — the value of one specific, realistic study that only
partially reduces uncertainty (e.g. a survey of schools), as opposed to
perfect information. It needs a model of how the study's data arise and
update our beliefs. `voi::evsi()` uses the regression method of Strong
et al. ([2015](#ref-strong2015)). A study informing only one input is
worth no more than perfect knowledge of that input, which is worth no
more than perfect knowledge of everything.

Net value of sampling is EVSI minus study cost: an expensive study can
have positive EVSI but negative net value. See Heath et al.
([2017](#ref-heath2017)), Jackson et al. ([2022](#ref-jackson2022)), or
the book by Heath et al. ([2024](#ref-heath2024)) for fuller treatments.

## The school garden decision

The decision problems are private schools and public schools, each
choosing between no garden (payoff 0 by construction), a garden, and a
garden with a formal STEM programme. Public schools additionally face
the chance that they have no land access, that the land is unsuitable,
or that bureaucratic barriers stop the project; in those cases there are
no benefits.

``` r
garden_mc <- decisionSupport::mcSimulation(
  estimate = decisionSupport::estimate_read_csv("inputs/school_garden_estimate.csv"),
  model_function = school_garden_function,
  numberOfModelRuns = 10000, functionSyntax = "plainNames")
private <- cbind(no_garden = 0, garden = garden_mc$y$NPV_garden_inclusive,
                 garden_STEM = garden_mc$y$NPV_garden_STEM_inclusive)
voi::evpi(private)
```

### EVPI

| School  | Best option now | Expected NPV | EVPI |
|---------|-----------------|-------------:|-----:|
| Private | garden          |         1417 |  ~36 |
| Public  | garden          |          545 | ~195 |

Public schools have far more to gain from resolving uncertainty, because
the garden can fail altogether.

### EVPPI

Almost all single inputs have an EVPPI close to zero, even though the
EVPI is large. Two likely reasons (not separately tested here): the
plain garden is the best option in most of the input space, so no single
input changes the decision often; and much of the EVPI is *irreducible
randomness inside each run* (`chance_event()` and `vv()` draws: whether
this school's land turns out to be unsuitable, year-to-year variation),
which no parameter study can resolve. A clairvoyant forecast of those
events is not scientific knowledge.

For the top five inputs per school type, `value_of_information.Rmd` adds
bootstrap standard errors (`evppi(se = TRUE)`) and cross-checks with the
`earth` and `bart` regression methods (`outputs/evppi_robustness.csv`),
million VND:

| School  | Input                   |  `gam` |  SE | `earth` | `bart` |
|---------|-------------------------|-------:|----:|--------:|-------:|
| Public  | `school_event_value`    |    4.2 | 2.7 |     4.9 |    3.7 |
| Public  | `bureaucratic_barriers` |    1.9 | 0.9 |     2.7 |    4.1 |
| Public  | `if_community_likes`    |    0.9 | 1.4 |     2.4 |    0.7 |
| Private | all five inputs         | \< 0.1 |     |  \< 0.1 | \< 0.4 |

Only `bureaucratic_barriers` is more than two standard errors above
zero. `school_event_value` is similar in size across all three methods
but its standard error is large, and every other input is
indistinguishable from zero. The private-school EVPPIs are zero to
within the noise. All of these are tiny next to the public-school EVPI
(~195), so the supported conclusion is that no single input is worth
resolving on its own, and that `bureaucratic_barriers` is the most
credible candidate. Grouped EVPPI (`outputs/evppi_groups.csv`) for the
three land-access and bureaucracy probabilities is ~3 (`gam`) to ~5
(`earth`) for public schools. The residuals of the `school_event_value`
fit are checked with `voi::check_regression()` (shown in
`value_of_information.Rmd`).

### EVSI, population value and net benefit of sampling

An illustrative study surveys `n` public schools to learn how often
bureaucratic barriers stop a garden, using a custom binomial data
generator (`datagen_fn`) with `voi::evsi()`. Per school, EVSI rises to
about 2 million VND at n = 100, close to the EVPPI of this input (1.9
+/- 0.9), but it is non-monotonic at small n (about 1.0 at n = 10, 0.6
at n = 20), which is regression noise, not a real effect.

EVSI is per school; the survey pays off only if enough schools use the
result. `voi::pop_voi()` and `voi::enbs()` scale it to a population over
a time horizon. **The number of schools deciding is not taken from any
source**: `outputs/enbs_by_population.csv` shows a grid (10 to 5000
schools), and `outputs/evsi_breakeven_schools.csv` gives the number of
schools that must face the decision for each survey to break even. With
the illustrative assumptions (5-year horizon, 5% continuous discounting,
study cost 2 + 0.5 per school surveyed, million VND) a survey of 100
schools breaks even at about 6 schools using the result. These
break-even counts are small because the per-school EVSI is of the order
of 1-2 million VND, but that EVSI is itself uncertain (standard error
about 0.9 on the matching EVPPI), so the break-even numbers should be
read as an order of magnitude only. Replace the cost, horizon, discount
rate and school count with real values before drawing conclusions.

### Pareto trade-offs

A simpler post hoc view, alongside EVPI/EVPPI/EVSI: which draws of the
Monte Carlo sample are not dominated on all three objectives at once
(economic return, child health, biodiversity), using `rPref::psel()`
(`outputs/pareto_summary.csv`).

## Other things to keep in mind

- Separate learnable parameter uncertainty from irreducible randomness
  (e.g. future weather): average over the latter before computing EVPI,
  or a clairvoyant forecast of random events gets valued as scientific
  knowledge.
- `voi`'s regression methods are approximate: cross-check more than one
  `method` before trusting a single number for a real decision.
- If inputs are correlated, pass that structure to `estimate_read_csv()`
  (see `?estimate_read_csv`) rather than sampling independently.

## Packages

- [decisionSupport](https://cran.r-project.org/package=decisionSupport)
  (front end) ([Luedeling et al.
  2025](#ref-luedeling2025decisionsupport)): also has `chance_event()`
  (risky events), `vv()` (year-to-year variation) and `discount()`
  (discounting cash flows).
- [voi](https://chjackson.github.io/voi/) (back end) ([Jackson and Heath
  2024](#ref-jackson2024voi)): EVPPI/EVSI methods include `"gam"`,
  `"gp"`, `"bart"`, `"earth"`, `"inla"` (EVPPI) and regression, `"is"`,
  `"mm"` (EVSI).
- [BCEA](https://gianluca.statistica.it/software/bcea/) and
  [SAVI](https://github.com/Sheffield-Accelerated-VoI/SAVI) for
  cost-effectiveness-analysis-style outputs or a web interface.

(see[bib/references.bib](bib/references.bib))

## References

<div id="refs" class="references csl-bib-body hanging-indent">

<div id="ref-felli1998" class="csl-entry">

Felli, James C., and Gordon B. Hazen. 1998. “Sensitivity Analysis and
the Expected Value of Perfect Information.” *Medical Decision Making* 18
(1): 95–109. <https://doi.org/10.1177/0272989X9801800117>.

</div>

<div id="ref-heath2024" class="csl-entry">

Heath, Anna, Natalia Kunst, and Christopher Jackson. 2024. *Value of
Information for Healthcare Decision-Making*. Chapman and Hall/CRC.
<https://doi.org/10.1201/9781003156109>.

</div>

<div id="ref-heath2017" class="csl-entry">

Heath, Anna, Ioanna Manolopoulou, and Gianluca Baio. 2017. “A Review of
Methods for Analysis of the Expected Value of Information.” *Medical
Decision Making* 37 (7): 747–58.
<https://doi.org/10.1177/0272989X17697692>.

</div>

<div id="ref-jackson2022" class="csl-entry">

Jackson, Christopher H., Gianluca Baio, Anna Heath, Mark Strong, Nicky
J. Welton, and Edward C. F. Wilson. 2022. “Value of Information Analysis
in Models to Inform Health Policy.” *Annual Review of Statistics and Its
Application* 9: 95–118.
<https://doi.org/10.1146/annurev-statistics-040120-010730>.

</div>

<div id="ref-jackson2024voi" class="csl-entry">

Jackson, Christopher, and Anna Heath. 2024.
*<span class="nocase">voi</span>: Expected Value of Information*.
<https://doi.org/10.32614/CRAN.package.voi>.

</div>

<div id="ref-luedeling2025decisionsupport" class="csl-entry">

Luedeling, Eike, Lutz Goehring, Katja Schiffers, Cory Whitney, and
Eduardo Fernandez. 2025. *decisionSupport: Quantitative Support of
Decision Making Under Uncertainty*.
<https://doi.org/10.32614/CRAN.package.decisionSupport>.

</div>

<div id="ref-raiffa1961" class="csl-entry">

Raiffa, Howard, and Robert Schlaifer. 1961. *Applied Statistical
Decision Theory*. Division of Research, Graduate School of Business
Administration, Harvard University.

</div>

<div id="ref-strong2014" class="csl-entry">

Strong, Mark, Jeremy E. Oakley, and Alan Brennan. 2014. “Estimating
Multiparameter Partial Expected Value of Perfect Information from a
Probabilistic Sensitivity Analysis Sample: A Nonparametric Regression
Approach.” *Medical Decision Making* 34 (3): 311–26.
<https://doi.org/10.1177/0272989X13505910>.

</div>

<div id="ref-strong2015" class="csl-entry">

Strong, Mark, Jeremy E. Oakley, Alan Brennan, and Penny Breeze. 2015.
“Estimating the Expected Value of Sample Information Using the
Probabilistic Sensitivity Analysis Sample: A Fast, Nonparametric
Regression-Based Method.” *Medical Decision Making* 35 (5): 570–83.
<https://doi.org/10.1177/0272989X15575286>.

</div>

<div id="ref-whitney2026garden" class="csl-entry">

Whitney, Cory, Thi Thu Giang Luu, Johannes Kopton, and Eike Luedeling.
2026. “A Decision-Analysis Framework for School Garden Investments in
Vietnam: Evaluating Trade-Offs for Nutrition, Biodiversity, and Economic
Outcomes.” *Humanities and Social Sciences Communications* 13 (1): 580.
<https://doi.org/10.1057/s41599-026-07204-0>.

</div>

</div>
