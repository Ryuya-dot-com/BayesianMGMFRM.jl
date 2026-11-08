# Criterion collapse across ratings

Does a judge distinguish the criteria, or use the same criterion profile across
all of them? `Experimental.CriterionCollapse` fits one specific explanation for
halo-like ratings: a **constant latent class for each rater** that replaces
criterion-specific steps with their average. It is an experimental scalar model,
not an automatic detector or a rule for excluding judges.

The mechanism follows the mixture Rasch facets work of
[Jin and Chiu (2022)](https://doi.org/10.3758/s13428-021-01721-3) and the
inadequate-discrimination/general-impression distinction in
[Jin and Eckes (2025)](https://doi.org/10.3758/s13428-025-02667-6).
The implementation below states its own explicit exchangeable prior; it is not
a reproduction of the papers' complete priors or validation studies.
General impression, signed positive/negative halo or horns, preference for middle
categories, and severity drift are different explanations. The present model
does not estimate those mechanisms.

The [ConQuest comparison guide](migration-facets-conquest.md#Two-different-comparison-questions)
separates investigation of halo-related patterns from an exact shared-class
implementation match. The [roadmap](roadmap.md) states the remaining evidence
before broader mechanism or classification claims.

## Specify, fit, inspect and save

Each row contains a performance ID (`person`), criterion (`item`), rater and
score. The performance must remain the same across its ratings. Use the full
common category support, including categories not observed in a particular cell.
[CSV input](data-validation.md) and `FacetData` preserve this distinction between
missing ratings and actual zero scores.

```julia
using BayesianMGMFRM
C = BayesianMGMFRM.Experimental.CriterionCollapse
# ratings contains one row per performance/criterion/rater combination.
data = FacetData(ratings; person=:person, item=:criterion, rater=:rater,
    score=:score, category_levels=0:2)
# Illustrative prior, not a scientific recommendation. Gamma uses rate.
prior = C.Prior(person_precision_shape=3., person_precision_rate=2.,
    rater_precision_shape=3., rater_precision_rate=.5,
    step_sd=1.5, class_alpha=1., class_beta=1.)
target = C.model(data; prior)
C.design(target)
result = C.fit(target; ndraws=1000, warmup=1000, chains=4,
    seed=73, target_accept=.9, progress=true)
save_fit("criterion-collapse.jls", result)
report = posterior_summary(result)
report.classes
categories = C.category_report(result)
save_report("criterion-collapse.json", report)
save_report("criterion-categories.json", categories)
restored = load_fit("criterion-collapse.jls")
```

The executable `examples/criterion_collapse.jl` uses an existing simulated
144-rating dataset. Run it with an output directory, or append
`--saved-fit PATH` to review a saved fit without new inference or data generation.
It also saves `comparison.json`, the ordinary-submodel signed-count check in
`prediction.json`, and the corresponding file receipts. Its original labelled
numerical assessment checks global diagnostics and class/category focal MCSE
separately; the additional reports expose their own focal diagnostics and MCSE.
For every reported functional, an unavailable precision estimate is not a pass. Its tolerances are
teaching-example numerical limits, not effect-size or classification cutoffs.

The default runs chains serially. With multiple Julia threads, specify
`chain_execution=:threads, max_parallel_chains=2` for bounded concurrent chains.
The target uses ForwardDiff and the package's NUTS runner, with separate chain
streams and retained warmup telemetry. More workers consume more memory;
threading does not guarantee proportional speedup. Counts, seed and prior remain
explicit. There is no automatic retry or draw extension.

Native sample files require a trusted file and its original package/environment.
Loading checks target identity, chain layout, hashes and every retained density.
JSON saves computed reports, not interchangeable retained draws. A report's
source-sample hash identifies the sample used. Do not load a private research
script's historical cache through this new API.

## What the probabilities mean

`report.classes` gives each rater's integrated posterior class probability and
its chain-aware Monte Carlo standard error (MCSE). It does **not** return
quantiles of conditional class weights as credible limits for that integrated
probability. The class is constant for a rater, not the proportion of that
rater's ratings exhibiting halo. No 0.5 cutoff is imposed.

Inspect `report.diagnostics` and the continuous summaries' mean and interval
endpoint MCSE. Good global diagnostics do not certify every reported functional
at a useful precision. The `pi` parameter describes the mixing proportion under
the declared model and prior; it is distinct from each rater's class probability
and from the realized proportion of classes in the panel.

`category_report` compares observed and expected category proportions in every
rater/criterion cell, integrating over the joint posterior and the class learned
from all ratings of that rater. Means and their MCSE are returned. These are
in-sample conditional expectations; there are no replicated-count intervals,
heldout scores or predictive tail tests in this route. Marginal row probabilities
must not be multiplied to form a joint probability: the shared class induces
dependence. The explicit workspace budget bounds the category accumulation;
restored samples, per-draw probabilities and diagnostics require further memory.

Low class support does not establish good category fit or absence of other
mechanisms. In a small existing centrality-only example, class support stayed
low despite a category-use discrepancy. A separate ordinary example's class
probability changed when the step prior widened. These examples motivate
checking plausible competing explanations and prior sensitivity; they do not
estimate classification accuracy, false-positive rates or calibration. The
original ID-generated example also retained ambiguous class probabilities.

An alternative with rater-specific category effects can reproduce middle-score
usage through its estimating equations. Such a fitted match does not identify
the cause or independently validate a mechanism. The
[native ConQuest example and score identity](migration-facets-conquest.md#fitted-category-counts)
explain this distinction, including why fixed-MML predictive tails and this
model's joint-posterior expectations use different uncertainty treatments.
The count-distribution calculation in that example is not an additional feature
of `category_report`; this API continues to return conditional means and MCSE.

The `branch_shift` continuous summary is the mean absolute difference between
the two branches' expected scores for a rater's observed performances and
criteria, evaluated at the same parameters. It is not a causal correction or a
signed halo/horns effect. A statistical pattern alone does not establish bias,
unfairness or a psychological cause; see [interpretation](interpreting-results.md).

## Joint prediction and model comparison

Two questions need separate answers: which induced model has more support, and
whether that model predicts the category pattern of interest. Both operations
reuse all retained draws and preserve the diagnostic warnings of the fitted model.
They perform no fitting or random prediction.

```julia
comparison = compare_models(result)
comparison.posterior_all_ordinary
comparison.log_bf_ordinary_vs_any_collapse

# Total number of middle-category ratings, repeating the original design.
check = predictive_check(result; category=1, max_count_updates=200_000_000)
check.expected_count
check.upper_tail

# Optional signed count contrast. Supply actual rater labels, not indices.
contrast = Dict("R1" => -1, "R2" => -1, "R3" => 1, "R4" => 1)
ordinary = predictive_check(result; category=1, rater_weights=contrast,
    model=:all_ordinary, max_count_updates=200_000_000)
ordinary.expected_count
ordinary.upper_tail
receipt = save_report("ordinary-prediction.json", ordinary; return_receipt=true)
saved = load_report(receipt.path; expected_sha256=receipt.sha256)
```

Omit `rater_weights` for a total category count. In a supplied dictionary, allowed
weights are -1, 0 and +1; omitted raters have weight zero. Unknown labels, missing
category support, unsupported controls and an insufficient computation budget
raise errors. The explicit update budget bounds recurrence/convolution work;
it does not truncate ratings or posterior draws. `support` and `pmf` describe
the future count/contrast distribution, not an interval for a parameter.

The prediction keeps one class per rater. Conditional category indicators have
a Poisson-binomial count distribution **within each class**. The two complete
rater-count distributions are mixed once, then convolved across raters within
the same posterior draw. Finally the joint distribution is averaged over draws.
Multiplying marginal row mixtures or substituting posterior-average probabilities
would lose dependence. The prediction repeats known people, criteria, raters and
their allocation; it does not predict new levels or leave data out.

Let E denote the fitted mixture, A the event that all raters are ordinary, and
`w_rs` the conditional collapse probability for rater r at joint draw s. Define

```math
a_s=\prod_r(1-w_{rs}),\quad
p_0=E_E[a_s\mid y],\quad a_0=\frac{B(\alpha,\beta+R)}{B(\alpha,\beta)}.
```

`compare_models(result)` returns `p0`, `a0`, and the log of

```math
BF_{0,1}=\frac{p_0/(1-p_0)}{a_0/(1-a_0)},\qquad BF_{0,E}=p_0/a_0.
```

The first compares E conditional on A with E conditional on its complement;
the second compares the all-ordinary submodel with the encompassing mixture.
They use the original induced model odds, not equal model odds. With a uniform
Beta prior and four raters, `a0=1/5`, not `1/16`: the classes share a random
mixing proportion. The continuous prior is the induced prior of this model,
not the default public MFRM prior. Results can depend on step and class priors.

For `model=:all_ordinary`, posterior conditioning also changes the distribution
of continuous parameters. For any conditional predictive functional f,

```math
E[f\mid y,A]=\frac{E_E[a_s f_s\mid y]}{E_E[a_s\mid y]}.
```

The code uses these joint-draw weights. Switching only to the ordinary response
rule while averaging without weights would give a different prediction.
`model=:mixture` is the default and uses the full learned class distribution.

Expected counts, inclusive lower/upper tails and the observed point mass have
chain-aware MCSE. For a conditional-model ratio, MCSE uses the influence trace
`a_s * (f_s - estimate) / mean(a)` and retains numerator and denominator
diagnostics. `weight_denominator.mean` is on a numerically rescaled weight
scale; `log_scale` and `log_probability` make that scale explicit. The reported
weight concentration is **not MCMC ESS**. The model-comparison log-odds MCSE is
a delta-method numerical error, not posterior uncertainty about a Bayes factor.
Constant sampled probabilities and rounded boundaries cannot certify zero
probability or certainty. Unavailable MCSE is preserved.

`qualification` concerns whole-fit numerical diagnostics; it does not certify
these focal quantities. Inspect their diagnostics and MCSE separately, choosing
precision requirements for the question. No automatic MCSE, class or rejection
threshold is imposed. PMF-cell MCSE and discrete count-quantile precision are
not assessed. Inclusive tails overlap at the observed mass and are not calibrated
p-values. If several contrasts are selected after inspecting data, retain that
exploratory status rather than claiming multiplicity control.

Relative support does not imply adequate prediction. An existing centrality-only
control favored the all-ordinary submodel while its selected count contrast
retained an upper predictive tail near 0.01. That result illustrates the distinction;
it does not validate a centrality detector. `criteria(result)` therefore does
not relabel the Bayes factor or joint count check as WAIC/LOO. The explicit
held-out operation below answers a separate prediction question.

## Held-out profile prediction

Can the model predict one judge's criterion scores for an already assessed
performance, using that judge's other ratings and other judges' ratings of the
performance? Hold out **all observed criteria for that performance/rater pair**
together. The original people, raters, criteria, categories and finite-panel
prior remain fixed. This is not accuracy for new people or new raters.

```julia
heldout = criteria(result; unit=:performance_rater, model=:mixture)
ordinary = criteria(result; unit=:performance_rater, model=:all_ordinary)
comparison = compare_models(result; criterion=:loo, unit=:performance_rater)
comparison.difference  # mixture minus induced all-ordinary log score
receipt = save_report("heldout.json", comparison; return_receipt=true)
restored = load_report(receipt.path; expected_sha256=receipt.sha256)
```

The unit is required. A profile contains its explicitly listed observed criteria;
missing scores are never filled with zero. A fold that leaves its person or
rater with no other ratings is rejected from this known-level operation. Reports
retain row membership, actual labels/scores/categories, source identity and prior.
`compare_models(result)` without these keywords retains the Bayes-factor meaning.

For each profile H and continuous parameter draw, the mixture uses

```math
g_H(\psi)=\frac{p_E(y\mid\psi)}{p_E(y_{-H}\mid\psi)}.
```

The denominator removes the entire held-out profile before updating the shared
rater class. Conditional probabilities for individual criteria must not be
multiplied after mixing. Full-posterior draws are reweighted by `1/g_H` for the
training posterior. For the induced all-ordinary model A, the actual proposal
ratio is `P_E(A | psi,y_-H)/g_H`; merely substituting ordinary probabilities into
unweighted mixture-posterior draws is incorrect. The operation uses all retained
joint draws without predictive RNG or refitting.

`result.pointwise` in a criteria report contains profile log scores, Pareto-k,
its sample-size threshold, relative efficiency and importance ESS. A failed
tail/relative-efficiency diagnostic leaves the score `diagnostic_only` and its
MCSE unavailable. Constant sampled weights do not establish perfect precision.
Totals and paired differences retain covariance through the same joint draws.
`smoothed_weight_ess` is `1/sum(normalized_weight^2)` after smoothing;
`importance_ess` additionally multiplies this by relative efficiency. Neither
quantity is a count of independent held-out profiles or a precision guarantee.

MCSE is an **approximate chain-aware delta estimate** for the self-normalized
smoothed-weight log score. It does not separately estimate the uncertainty of
fitting the Pareto tail. Its influence trace retains chain diagnostics; failed
focal diagnostics also make MCSE unavailable. Even available MCSE needs a
question-specific precision requirement and adequate whole-fit sampling.
No automatic cutoff, winner, refit or draw extension is selected.

Sampling/design uncertainty is separate and remains unassessed. Profiles share
people, raters and training data, so an iid standard error is not supplied.
The score sum/mean describes this fixed collection of held-out profiles; it is
not evidence of reliable halo classification or causal mechanisms. Unequal-size
profiles retain their full joint probabilities and row counts.

For transparent inspection through the mathematical API:

```julia
terms = pointwise_loglikelihood(result; unit=:performance_rater,
    model=:all_ordinary)
terms.log_density
terms.log_ratios       # proposal is the full mixture posterior
terms.factorizes_joint  # false
```

These conditional columns do **not** factorize the fitted likelihood. Do not
use them for ordinary WAIC or summed training deviance. The all-ordinary
columns additionally require the returned proposal ratios. The primitive is
not an ordinary posterior-draw matrix for A. The [non-factorized LOO principle](https://doi.org/10.1007/s00180-020-01045-4)
and [PSIS algorithm](https://jmlr.org/papers/v25/19-556.html) motivate this
calculation; they do not guarantee precision or model adequacy in a particular fit.

## Plot saved results without fitting again

The optional CairoMakie extension displays the two questions separately:

```julia
using CairoMakie
class_note = IOBuffer()
fig = C.plot_classes(report; annotation_io=class_note)
save("class-probabilities.png", fig)
write("class-probabilities.txt", String(take!(class_note)))

category_note = IOBuffer()
# Match the actual rater label and its type in your data.
profiles = C.plot_categories(categories; rater="R2", annotation_io=category_note)
save("category-profiles.svg", profiles)
write("category-profiles.txt", String(take!(category_note)))
```

The first figure uses a common 0–1 scale for every rater's posterior class
probability and a **separate axis for MCSE**. It supplies neither credible
intervals nor a classification cutoff. The second compares observed and
posterior expected category proportions for all criteria of the selected rater,
with MCSE on separate axes. Probability axes are fixed at 0–1; the MCSE range
uses the whole report, so selecting another rater does not change that scale.
Unavailable MCSE stays labelled unavailable/NA, never zero. Orange text denotes
unavailable numerical precision, not a rater classified as exhibiting halo.

Keep the external title/note with each figure. Notes retain the whole-fit
numerical verdict, raw/transformed diagnostic summaries, retained and warmup
warnings, explicit prior parameters and interpretation limits, even when one
rater is selected. Global diagnostics do not certify focal precision or fit.
Use `annotation_io=nothing` if an embedded title/note is needed; external text
is the default. These two-dimensional displays show scalar probabilities and
categorical profiles; there is no additional latent dimension to plot.

Computed JSON reports can be read without native samples or CairoMakie:

```julia
receipt = save_report("classes.json", report; return_receipt=true)
# Retain this receipt independently of later edits to the file.
saved_report = load_report(receipt.path; expected_sha256=receipt.sha256)
# Later, with CairoMakie loaded:
C.plot_classes(saved_report)
```

`load_report` checks the file digest, model scope, complete plotted rows and
metadata. It reads stored means, MCSE and warnings; it does not recompute
estimates or diagnostics in the drawing environment. A digest protects against
byte changes, not a scientifically wrong model or an untrusted source. This
route is distinct from moving native samples between dependency environments.

`examples/criterion_collapse_figures.jl` takes an output directory, class-report
path and retained SHA-256, then category-report path and retained SHA-256. It
checks that the two reports refer to the same target and samples, and writes
PNG/SVG figures for all raters together with the full external notes and source
reports. It performs no inference or random prediction and preserves an existing
output directory. To inspect the teaching example, use its `report.json` and
`categories.json`; its `assessment.json` is a different kind of report and is
not accepted by this plotting loader.

## Model, identification and prior

For scores indexed as `0,...,K-1`, let `z_r=1` denote criterion collapse and
the step average use equal weights across criteria. Then

```math
\log\frac{P(Y_{pir}=k\mid z_r)}{P(Y_{pir}=k-1\mid z_r)}
=\theta_p-s_r-\{(1-z_r)\delta_{ik}+z_r\bar\delta_k\},
\qquad z_r\mid\pi\sim\mathrm{Bernoulli}(\pi).
```

The discrimination/logistic multiplier is **one**. Steps are unrestricted and
criterion-owned; they are not forced to be ordered or individually centered.
Persons and raters each sum to zero. All of one rater's row likelihoods are
multiplied within a branch, then the two branches are mixed once. Mixing each
row separately defines a different model.

For `P` persons, let `Q_P` have orthonormal columns spanning the sum-zero space.
The exchangeable prior is

```math
u\sim N(0,I_{P-1}),\quad
\theta=\sqrt{P/(P-1)}\,\tau_\theta^{-1/2}Q_Pu,\quad
\tau_\theta\sim\mathrm{Gamma}(a_\theta,b_\theta),
```

with shape `a` and **rate** `b`. Raters have the analogous prior. Each conditional
marginal location variance is `1/tau`; covariance between different locations
is `-1/((P-1)tau)` for persons. Independent steps have `Normal(0, step_sd)` priors
and `pi` has `Beta(class_alpha,class_beta)` prior. NUTS samples white coordinates,
log precisions and logit class proportion; the Gamma/log and Beta/logit
Jacobians are included exactly once. Conditional SDs and kernel coordinates
must not be confused. Proper positive Gamma shapes can still produce infinite
marginal moments.

This prior differs from independently assigning normal priors to all but the
last level and forcing that last level to minus their sum. Merely giving both
specifications the same SD does not make their priors equivalent.

The input screen requires at least two persons, raters and criteria, at least
three common categories, observed rater/criterion cells and connected
person-cell allocation. Individual ratings may be missing, but duplicate
performance/criterion/rater rows are rejected. Connectivity is a sufficient
location-design screen, not a guarantee of mixture identification or precision.
When criterion profiles coincide the branches coincide, so the ratings cannot
identify the class; weak profiles can also leave substantial prior dependence.

Optional facets, group effects, free slopes, multidimensional ability, shared
response effects, time processes, new-rater/person prediction and arbitrary
cross-family model comparison are not combined with this model. The induced-
submodel comparison and same-design joint count check above do not establish
replicated classification validation, held-out prediction or independent user
acceptance; those remain separate work.

## Julia help

```@docs
BayesianMGMFRM.Experimental.CriterionCollapse.Prior
BayesianMGMFRM.Experimental.CriterionCollapse.model
BayesianMGMFRM.Experimental.CriterionCollapse.design
BayesianMGMFRM.Experimental.CriterionCollapse.contract
BayesianMGMFRM.Experimental.CriterionCollapse.target_identity
BayesianMGMFRM.Experimental.CriterionCollapse.fit
BayesianMGMFRM.Experimental.CriterionCollapse.report
BayesianMGMFRM.Experimental.CriterionCollapse.category_report
BayesianMGMFRM.Experimental.CriterionCollapse.compare_models
BayesianMGMFRM.Experimental.CriterionCollapse.predictive_check
BayesianMGMFRM.Experimental.CriterionCollapse.save_result
BayesianMGMFRM.Experimental.CriterionCollapse.load_result
BayesianMGMFRM.Experimental.CriterionCollapse.save_report
BayesianMGMFRM.Experimental.CriterionCollapse.load_report
BayesianMGMFRM.Experimental.CriterionCollapse.plot_classes
BayesianMGMFRM.Experimental.CriterionCollapse.plot_categories
```
