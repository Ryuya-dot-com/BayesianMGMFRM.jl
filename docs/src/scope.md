# Scope and Releases

!!! note "Unreleased documentation preview — 13 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

| Model surface | Status | Notes |
|:--|:--|:--|
| One-dimensional MFRM with rating-scale or partial-credit steps | Supported | Available through the documented design, fitting, diagnostic, and reporting workflow. |
| Fixed-coefficient multidimensional MFRM | Experimental | `Experimental.fit` on Julia or CmdStan; fixed Q coefficients, unit logits and identity latent correlation. Manual caches and report/figure bundles are available. |
| Two-dimensional correlated MFRM | Experimental | `Experimental.correlated(spec)` then `Experimental.fit`; between-item fixed Q, at least two pure items per dimension and both dimensions observed for each person. Julia/CmdStan, manual caches and report/figure bundles are available. |
| Fixed-coefficient multidimensional MFRM with an exchangeable rater prior | Experimental | Explicit `Experimental.ExchangeablePrior` with independent abilities or the admitted 2D correlated specification. Julia/CmdStan return `Experimental.ExchangeableMFRMFit`. The rater kernel SD is supplied, not estimated; this prior is not accepted by scalar MFRM, GMFRM or MGMFRM. |
| Scalar GMFRM: item discrimination × rater consistency | Experimental | Enter through `BayesianMGMFRM.Experimental`; the documented structural restrictions remain mandatory. |
| Fixed-Q confirmatory MGMFRM with the raw prior | Experimental | `Experimental.fit` with explicit `GeneralizedPrior`; one or more dimensions with an explicit fixed Q mask, estimated positive active loadings and rater consistency, and independent ability priors. |
| Fixed-Q MGMFRM with a normalized prior | Experimental | Unwrapped `Experimental.fit` with explicit `NormalizedMGMFRMPrior`, `prior_model=:exchangeable` or `:source`, all six scales and a source-rater ID when required. Independent abilities; Julia/AdvancedHMC admits binary categories, CmdStan requires at least three. Manual caches and reports are available. This selects a different prior target, not a relabeling of a raw fit. Correlated fitting and automatic request caching are unavailable. |
| D1 MGMFRM with matched fixed/free item slopes | Experimental | `Experimental.slope_restriction`, item-owned PCM, rater consistency fixed at one and explicit exchangeable `NormalizedMGMFRMPrior`. Julia/AdvancedHMC with raw coordinates only; manual caches and known-level refit planning. CmdStan and source priors are unavailable for this wrapper. See [the slope contract](experimental.md#Matched-fixed-and-estimated-item-slopes). |
| D1 fixed-slope MGMFRM with explicit location/step means | Experimental | `Experimental.MeanProfilePrior` additionally requires fixed-one item slopes and exact item/category IDs. Julia/AdvancedHMC with raw coordinates only; manual caches and known-level refit planning. Requires the successor source; absent from the earlier 13 October preview. See [the mean-profile contract](experimental.md#Fixed-location-and-step-mean-profiles). |
| Two-dimensional correlated MGMFRM | Experimental | Between-item Q, estimated positive loadings/consistency, `Experimental.correlated(spec)` and explicit `GeneralizedPrior`. Julia/CmdStan, prior/conditional posterior prediction, summaries, MCSE, diagnostics, manual caches and report/figure bundles are available. Scientific prior/domain acceptance remains open. |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Exploratory loading patterns or higher-dimensional correlation estimation | Not supported for fitting | MGMFRM retains a fixed Q pattern and independent abilities unless explicitly wrapped for the admitted 2D correlation model. Both correlated models above require exactly two dimensions. |
| Group and differential facet functioning effects | Not supported for fitting | Design validation may describe these terms, but estimation is not yet exposed. |
| Testlet, response-cluster, and rater-halo effects | Not supported for fitting | Explicit identifiers, structural checks, and residual/predictive summaries are available. These report-only summaries provide no calibrated decision or mechanism classification. |
| Arbitrary five-or-more-facet compositions | Not supported through the public fitter | Additional metadata columns do not add estimated effects. Task, criterion, occasion and response roles require explicit likelihood, constraints, threshold ownership and prediction contracts. Finite structural checks and research prototypes are not a public fitting route. See [facets versus levels and dimensions](learning-guide.md#facets-levels-dimensions). |

Experimental features may change in a minor release and should be
used with sensitivity checks. They must not be described as stable equivalents
of external software or as evidence for broader MGMFRM support.
The namespace is an explicit experimental stability boundary, not a maturity claim.
`BayesianMGMFRM.Experimental.surface_contract()` records its exact current
family configurations and constraints. For slope restrictions, inspect
`surface_contract(model; prior)` instead of inheriting a family-level backend
list. Unwrapped normalized, slope-restricted and mean-profile models all return
`NormalizedMGMFRMFit`; distinguish their priors and coefficient policies using
`fit_metadata`, not the result type alone. The historical `experimental = true` keyword is a
compatibility route and does not define the forward-looking API.

For their exact parameter meanings and runnable entry points, see
[exchangeable rater priors](experimental.md#Exchangeable-rater-prior),
[normalized MGMFRM priors](experimental.md#MGMFRM-prior-choice-and-comparable-scales)
and the [normalized fitting example](examples.md#Explicit-normalized-prior-MGMFRM-workflow).
The two uses of "exchangeable" above are different prior types for different
models. Neither estimates a population rater SD from the data.

## [Common operations and model-specific limits](@id common-operation-support)

The candidate connects eight result types to common saved-result operations:
`MFRMFit`, `GMFRMFit`, `MGMFRMFit`, `Experimental.NormalizedMGMFRMFit`,
`Experimental.CorrelatedMGMFRMFit`, `MultidimensionalMFRMFit`,
`Experimental.CorrelatedMFRMFit` and `Experimental.ExchangeableMFRMFit`.
An operation being available does not establish that every model is appropriate
for the same research question. Unsupported combinations remain unsupported.

| Operation | Available route | Boundary to check |
| --- | --- | --- |
| Fit, diagnostics and numerical precision | `fit` for scalar MFRM; `Experimental.fit` for the other routes; `diagnostics` and `posterior_mcse` | Use the model's required prior/specification and backend restrictions. Inspect MCSE for the actual quantities and interval endpoints you report. |
| Compare predictions of existing ratings | Qualified `compare_predictions` using the same data and persistent rating IDs | Descriptive WAIC/raw IS-LOO; optional approximate SE has declared unit assumptions. Hill smoothing is not reference-validated PSIS. No automatic winner. |
| Compare held-out predictions | `prediction_refit_plan`, separately fitted training models, `prediction_fold_observations`, `prediction_kfold`, `compare_kfold_predictions` | Known facet levels only; complete split and failure accounting. Optional first-order MCMC error from saved scores; combined errors require explicit independent simulation streams. Data-sampling K-fold SE and an automatic resumable multi-model refit runner are not supplied. |
| Compare one versus multiple dimensions under aligned response/prior conventions | `matched_dimension_refit_plans` in the [example](common_prediction_comparison.md#Matched-dimensionality-comparison), then the common refit/score route | Experimental MGMFRM with item-owned steps and one active Q loading per item; joint predictive priors still differ. This is not a scalar-GMFRM equivalence or model-choice validation. |
| Evaluate known-truth recovery | `recovery_quantities`, `recovery_evaluation`, `recovery_replications` | Truths must match model coordinates and constraints; independent datasets define replications. This does not generate data, perform SBC or select a collection design. |
| Report categories, reliability and agreement | `fit_report(...; reporting=(...))` with `category_report`, `posterior_reliability` and `rater_agreement` | Explicit observation IDs, selected reliability cohorts and response matching. Finite-cohort reliability is not conventional Strata; exact/adjacent agreement is not ICC or Krippendorff alpha. |
| Describe observed-score reliability | `BayesianMGMFRM.krippendorff_alpha(data; item, level, ...)`; optional `reporting.alpha` | One explicit item and nominal/ordinal measurement level. No fit required; singleton exclusions and undefined values remain visible. No CI or severity adjustment; a different observed-score ICC operation is listed below. |
| Describe observed-score ICC | `BayesianMGMFRM.intraclass_correlation(data; item, model, definition, unit, score_scale, ...)`; optional `reporting.icc` | Complete crossed ratings on one item, explicit equal-gap scores and random/fixed, agreement/consistency, single/average choices. Point estimates only; no missing-data model, CI/SE or severity adjustment. |
| Save and reconstruct results | `save_fit_cache` / `load_fit_cache`, report bundles | Use canonical records for fixed-Q reports/recovery. Legacy v1 refusal remains explicit. Manual caches do not imply automatic request caching or general cross-version Julia serialization. |
| Report conditional ability precision and classification risk | `BayesianMGMFRM.posterior_classification` and opt-in common `fit_report` section | Explicit people in one dimension, cutoff and probability rule; joint posterior risk and numerical MCSE. No automatic standard, multidimensional composite, ranking or known-truth error-rate guarantee. |
| Report rank uncertainty within a selected cohort | `BayesianMGMFRM.posterior_ranking` and optional common report section | One fitted ability dimension, explicit direction, joint-draw midranks and optional top-k tie bounds. No automatic selection, multidimensional aggregate, simultaneous ordering or population rank guarantee. |
| Export figures and facet diagnostics | Model-specific documented plotting and diagnostic routes | Common reporting does not extend every scalar diagnostic or plot. Wright/Pathway plots and assignment-adjusted DFF screening retain their documented scalar-MFRM scope; fitted DFF is not supplied. |

The [3D response-surface API](fitting.md#3D-item-response-surfaces-for-MGMFRM)
specifically accepts independent `MGMFRMFit` results with `GeneralizedPrior`
and at least two dimensions. It does not accept normalized, slope-restricted,
mean-profile or correlated fits, even where their numerical prediction and
posterior interval summaries are available. Plot support is separate from fit
and common-report support.

Start with the [saved comparison and recovery workflow](common_prediction_comparison.md)
and [integrated reporting example](api-saved-reporting.md).
The [combined saved workflow](common_prediction_comparison.md#Connect-comparison,-diagnostics-and-persistence)
accepts all eight types in a common row order and can include explicit per-model
category, agreement and reliability requests before saving/reopening reports.
Use all original retained chains/draws when required by those operations; warnings
and unavailable results are part of the output. A complete report means its
requested sections executed, not that inference or model selection was accepted.

## [What the current evidence permits](@id current-scientific-evidence)

The current mathematical and computational checks, recovery studies and user
workflow examples answer different questions. Their results must not be pooled
into one "validated model" label. In particular, the completed normalized-prior
recovery assessment concerns a fixed pure-Q, independent two-dimensional design
with 50 persons, five items, five raters and four categories. It used 32 independent
paired blocks across two truth scenarios and three loading-prior widths. The
192 fits are not 192 independent replications of each condition. That study
does not validate all eight result types, arbitrary Q or correlated/3D models.

| Question | Current evidence and permitted interpretation | Remaining boundary |
| --- | --- | --- |
| Does the implementation evaluate the declared model? | Matched Julia/Stan density and gradient checks support the checked targets and coordinates. | Finite checks are not a general identification theorem or a posterior-precision guarantee. |
| Did numerical estimation work in the recovery assessment? | 184 of 192 fits met that assessment's numerical qualification; eight retained diagnostic failures. | Successful diagnostics do not establish recovery or calibration. Other designs/backends have their own evidence. |
| Are the parameter intervals calibrated? | Recovery and failure summaries are available for the declared conditions. In the R1 stress condition, I1's 90% interval covered its true loading in only 1 of 32 blocks at log-loading prior SD 0.25, despite all 32 fits qualifying numerically. | General 90% coverage and joint-prior SBC calibration are not established. The wider priors are not automatically accepted alternatives. |
| How well are unused ratings predicted? | The scoring path and pilot are checked; the fresh main assessment is still incomplete. | Final predictive means/contrasts and their precision remain open. Existing-rating WAIC/LOO is a different target; new-level prediction needs separate evidence. |
| Which prior should be the default? | Saved-fit sensitivity shows how named estimates and contrasts change across explicit priors. | No scientific default follows solely from mixing, RMSE or predictive ranking. Inspect prior implications and the relevant inferential target. |
| Can a researcher reproduce the workflow? | Eight result types have a saved workflow and short actual-fit operability checks, including report/cache reconstruction. | Short fits do not establish adequate inference. Final scope, independent scientific review, unfamiliar-user reproduction and release acceptance remain open. |

See the [saved sensitivity illustration](prior-sensitivity.md#Saved-simulation-illustration)
for the observed prior dependence and the
[results guide](interpreting-results.md#Compare-models-against-the-same-prediction-task)
for interpreting comparisons. Research use should state the actual model, prior,
prediction target, diagnostics and unresolved limitations. An experimental API
is not a recommendation for every study that can supply its inputs.

## What Changes When You Choose MGMFRM

Suppose several raters score responses on criteria intended to measure two
abilities. The analysis must separate ability differences from item difficulty
and rater severity. A fixed-coefficient multidimensional MFRM assigns each
active item-dimension link a coefficient of one. MGMFRM additionally estimates
how strongly each active dimension affects an item's ratings and how sharply
each rater's category probabilities concentrate. Choose between these models
according to that question and the rating design; the additional parameters
are assumptions to investigate, not an automatic improvement.

For the independent fixed-Q MGMFRM:

| Component | Estimated or specified? | Interpretation |
|:--|:--|:--|
| Q pattern and active loadings | The zero/nonzero pattern is supplied; each active positive loading is estimated. | Fixed Q does **not** mean fixed coefficients. A zero excludes a dimension from that item. Multiple active dimensions enter an additive weighted sum. |
| Abilities and item difficulties | Person abilities and item difficulties are estimated; the ability prior mean is zero and `person_sd` is supplied. | The prior SD is not estimated population variability or an individual's posterior uncertainty. Separate ability/item locations depend on the declared priors. |
| Rater severity and consistency | Both are estimated subject to zero-sum severity and product-one consistency constraints. | Severity shifts the rating distribution. Consistency multiplies the category logits; larger values concentrate probability around the most favored category or tied categories, holding other parameters fixed. It is not a test-retest reliability coefficient or a measure of accuracy against an external standard. |
| Category steps | Free item-specific steps are estimated; the baseline step is zero and the last nonbaseline step is reconstructed to make their sum zero. | Category use can differ by item. The steps for an item are shared across raters and dimensions. |
| Dependence between dimensions | Ability prior correlation is fixed to identity. | This is a population-prior assumption, not a finding that posterior estimates or observed scores are independent. Estimating correlation requires the separate admitted two-dimensional correlated model. |

The response multiplier is fixed at `1.7` in MGMFRM; fixed-coefficient MFRM uses
unit logits. Raw ability or difficulty estimates from the two models therefore
cannot be compared as though the scale and prior were unchanged. The
[equations](model-equations.md#Generalized-Partial-Credit-and-Multidimensional-Structure)
and [experimental guide](experimental.md#Workflow) give the parameter and prior
conventions. In particular, the compatibility value `discrimination = :none`
does not disable the estimated loadings in an MGMFRM specification.

Read constraints together with priors. With more than two raters, equal SDs on
free coordinates in the raw `GeneralizedPrior` do not give every constrained
rater the same marginal prior. The last sorted rater is reconstructed from the others; changing which
rater occupies that position can change the prior and posterior. Likewise,
finite posterior intervals for separate ability and item locations do not
establish likelihood identification. The [location explanation](experimental.md#Location-diagnostics-for-fixed-Q-MGMFRM)
shows which joint shift leaves rating probabilities unchanged and how to inspect
its mixing without changing the model. The explicitly normalized exchangeable
prior removes the raw rater-label asymmetry by changing the prior target; it does
not by itself establish likelihood identification or calibrated inference.

## Interpreting Support and Versions

“Supported” describes the documented implementation boundary, not proof of
convergence or validity for a new dataset. Experimental availability does not
establish recovery, robustness, or external-software agreement. Known-truth
simulation and protocol helpers have their own [research API
reference](api-validation-evidence.md); their presence does not change the
fitting boundary above.

The registered release remains the default installation. Development versions
may contain unreleased behavior and should be pinned to an explicit revision
when used in reproducible work.

Read the manual and examples for the installed revision. Development
documentation can describe features absent from an earlier registered release.

For reporting scope and current limitations of bias, separation/reliability,
Strata and score agreement, see [the MFRM reporting guide](interpreting-results.md#Bias,-reliability-and-a-complete-MFRM-report).
In particular, the historical posterior separation screen is not a validated
FACETS or EAP reliability estimator; it should not be promoted by a Strata
transformation.
