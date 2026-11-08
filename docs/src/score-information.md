# Expected scores and conditional information

An expected-score curve answers: *how would the mean score change with ability,
for these items and raters?* An information curve answers: *where would that
specified assessment distinguish nearby abilities, conditional on the fitted
item and rater parameters?* Both questions require an explicit rating design.

The initial `BayesianMGMFRM.score_information_report` route accepts ordinary
scalar `MFRMFit` results, with item-specific partial-credit steps or shared
rating-scale steps. Generalized, multidimensional and application-specific result
types have separate contracts and are not accepted by this entry point.

## Specify the assessment

Use the exact item and rater labels stored in the fit. A cell represents one
item/rater combination; `repetitions` is a positive integer count of independent
ratings under the model. It is not a survey weight. Repeated observations of the
same performance may need a shared-response model before this independence
assumption is appropriate. Missing ratings in the original data do not define
the assessment to be evaluated.

For an existing ordinary MFRM fit:

```julia
data = fit.design.spec.data
ratings = [
    (; id="task-1", item=data.item_levels[1], rater=data.rater_levels[1], repetitions=1),
    (; id="task-2", item=data.item_levels[2], rater=data.rater_levels[1], repetitions=2),
]
curves = BayesianMGMFRM.score_information_report(fit;
    dataset_id="assessment-2026", observation_ids=rating_ids,
    ratings, ability_grid=collect(-3.0:0.25:3.0), interval=0.95)
curves.rating_rows  # One rating at each item/rater combination
curves.test_rows    # Three ratings in the declared design
curves.sampling_quality
```

`rating_ids` must be persistent unique IDs in fitted-row order. The example needs
at least two stored item levels. Choose the grid for the substantive scale; a
curve outside observed ability support is an extrapolation. Abilities are in the
fit's unit-logit coordinate system. Rater severity, item location, steps and
anchors retain their fitted interpretation.

Each row contains `expected_score` and `information` summaries with a posterior
mean, SD, median, pointwise equal-tailed interval and detailed mean/quantile MCSE.
The full result retains the design, score labels, chain layout, source identities
and whole-fit warnings. A descriptive status supplies no automatic precision or
convergence guarantee; inspect MCSE for the quantity needed in the analysis.

## Mathematics and units

At one joint posterior draw, let k=0,...,K-1 be the category index and c_k the
stored score label. In the scalar MFRM, the logits can be written

```math
\eta_k(\theta)=k(\theta-b_i-r_j)-\sum_{h=1}^k\tau_{ih},\qquad
p_k=\frac{e^{\eta_k}}{\sum_l e^{\eta_l}},\qquad
m(\theta)=\sum_k c_kp_k.
```

Shared rating-scale steps replace the item index on tau. The probability kernel
uses stable softmax evaluation. Since

```math
\frac{\partial\log p_k}{\partial\theta}=k-E[k],\qquad
\mathcal I_{ij}(\theta)=\sum_k p_k(k-E[k])^2,
```

information is the variance of the category **index**, in inverse squared unit
logits. Score labels determine the expected score. Adding a constant to labels
shifts expected scores without changing information. In a different model with
ability multiplier beta, information would be beta-squared times this variance;
that identity does not add support for a generalized fit to this API.

For independent ratings conditional on ability and all nuisance parameters,

```math
m_{\mathrm{test}}=\sum_c n_c m_c,\qquad
\mathcal I_{\mathrm{test}}=\sum_c n_c\mathcal I_c.
```

The implementation adds these quantities **within each joint draw**. Summaries
of those totals retain posterior dependence between item/rater estimates.
Adding marginal interval endpoints would not give the total's interval.

Conditional information describes the likelihood when nuisance parameters are
fixed. Its posterior curve describes uncertainty about that conditional
quantity. It is not Fisher information of the posterior predictive mixture,
inverse posterior variance, reliability or an empirical design-performance
guarantee. The local approximation `1/sqrt(information)` is not reported as a
posterior standard error. Fixed anchors do not propagate external calibration
uncertainty.

## Save and display the same result

Use the existing opt-in report path to preserve the conditions alongside tables:

```julia
report = fit_report(fit;
    reporting=(;dataset_id="assessment-2026", observation_ids=rating_ids,
        score_information=(;ratings, ability_grid=collect(-3.0:0.25:3.0))),
    include_category_functioning=false, include_rater_homogeneity=false,
    include_prior_predictive=false, include_posterior_predictive=false,
    include_calibration=false, include_waic=false, include_loo=false,
    include_artifact=false, view=:public)
report.score_information.test_rows
save_fit_report_bundle("score-information-report", report; require_complete=true)
restored = load_fit_report_bundle("score-information-report"; require_complete=true)
```

The section exports `rating_rows`, `test_rows`, `design_rows` and `warning_rows`.
Its `result` keeps detailed quantile MCSE and source metadata. Bundle restoration
does not require a plotting package. The optional
`examples/plot_score_information.jl` in this source version provides a two-panel
CairoMakie example: run `using CairoMakie`, include that file, then call
`plot_score_information(curves)`.
Keep its annotation with the image: uncertainty bands are pointwise intervals
for the expected value and conditional information, not prediction intervals
for actual scores or simultaneous bands.

No outcome generation, refitting or draw subsampling occurs. One draw-by-category
matrix is used at a time; the explicit `max_curve_cells` budget limits total
evaluation work. Narrow the design/grid or deliberately raise that budget if
needed. Existing [observed-versus-expected calibration](api-workflow-diagnostics.md#observed-expected-calibration)
and [Wright maps](visualization-gallery.md) answer different questions.
