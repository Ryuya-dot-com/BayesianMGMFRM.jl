# Scope and Releases

!!! note "Local development scope — 19 October 2026"
    This manual includes unreleased interfaces and examples. It is not the
    documentation of an installed release. Model support and scientific
    acceptance remain as stated on each page.

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

For promotion of an experimental route to **Supported**, the selected release
must specify the exact model/prior/backend and advertised operations, establish
their mathematical and claim-appropriate statistical evidence, verify the
complete public workflow (including figures and saved reproduction) in the
declared environments, and resolve independent scientific/user review before
finalizing its API and compatibility policy. These are the existing acceptance
conditions, not a requirement to finish every possible model combination.
Support describes that bounded promise; it is not a guarantee that any supplied
data support the construct, that every fit is adequate or that intervals are
calibrated under every data-generating process.

The normalized independent D2 route has bounded scientific and actual-fit
evidence; integrated environment acceptance and independent review remain.
The scalar design-planning route connects preparation, explicit execution,
full-roster summaries and saved reproduction. Fixed-truth target-attainment and
joint-prior SBC teaching studies now exercise these operations. Their evidence
is limited to the declared model, prior, allocation, quantities and precision
objectives: neither an unmet width target nor a rank screen supports a general
design recommendation or a calibration guarantee. Rank comparisons retain their
independence and posterior-stationarity assumptions. The design-planning route
remains experimental; independent workflow review and acceptance of the advertised
environment and compatibility scope still precede promotion. See
[the design-planning guide](design-planning.md#Choose-rank-resolution-and-a-finite-assessment)
for the reproducible procedure and its limits.

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
| Preliminary-only three-outcome no-state workflow | Experimental; explicit reference, steps or combined prior | `Experimental.ThreeIndicator` checks labelled 9/9/2 input, prepares and fits four serial Julia/AdvancedHMC chains, restores native results in the producing environment and reports named panel/contrast intervals, MCSE, prior settings and warnings. It also reads original Julia/Stan computed reports. Historical native migration, custom numerical priors, new contrasts after fitting, latent states and scientific acceptance are not supplied. See [fitting](fitting.md#three-outcome-fitting), [input inspection](data-validation.md#three-outcome-input) and [saved results](api-saved-reporting.md#three-outcome-saved-reports). |
| Concurrent three-outcome workflow | Experimental; named presets or explicit `ConcurrentPrior` | Two-study 9/9/2 input, full numerical Gaussian/half-normal/LKJ prior configuration, joint Julia fitting/reporting, prior and posterior predictive checks, and source-bound persistence. Portable model v2 reads legacy preset v1. The independent Stan data/reference adapter requires full listener×word covariance and does not supply a public Stan fitter. See [the concurrent guide](concurrent-three-outcome.md). |
| Two-criterion ordinal event association | Experimental | `Experimental.JointRatings.OrdinalAssociation`: explicit criterion means, estimated person SDs, centered task effects, correlated response effects and a common adjacent log odds ratio. Unit coefficients, explicit priors, separate criterion step groups; at least three common categories. Native fit/report/contrast/save/reopen and existing-event joint tables. No scientific default, new-level prediction or causal halo claim. See [Paired Ordinal Association](ordinal-association.md). |
| Two-criterion shared-response PCM | Local experimental | `Experimental.JointRatings`: fixed unit coefficients, correlated person/response effects, criterion-specific task/rater effects, explicit priors and declared criterion-group steps. Distinct native result/report types with shared save/reopen verbs; conditional known-level marginal prediction and response scores. No accepted heldout comparison or recovery/SBC claim. See [Joint Ratings](joint-ratings.md). |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Three-dimensional correlated MGMFRM | Experimental | [Correlated3D](correlated-3d.md): pure fixed Q, unit population marginal SDs, explicit normalized exchangeable scales/LKJ prior, generation, Julia NUTS, named marginal/partial correlations, conditional row probabilities and trusted native save/load. Scientific domain/calibration acceptance remains open. |
| Star-factorized multi-criterion ordinal association | Experimental | `Experimental.joint_rating_spec(...; association=:star)`: complete events with one declared root, mixed ordinal/binary category supports, correlated entity/rater effects, criterion-specific steps and root-branch residual associations. Explicit priors, Julia NUTS, qualification, reports, category PPC, event criteria, figures and native save/reopen. Scientific acceptance and general halo mechanisms remain unestablished. See [Star Association](star-association.md). |
| Exploratory loadings or higher-dimensional fixed-Q correlation workflows | Not supported for fitting | Learned/rotated Q and cross-loadings in Correlated3D are outside the admitted routes. `Experimental.correlated` admits the documented 2D and pure-Q 3D models, with different prior/scale contracts; this bound does not apply to the declared criterion vector in the separate StarAssociation model. |
| Observed-group differences in rater severity | Experimental | Separate `Experimental.RaterGroupEffects` scalar unit-slope item-step PCM, explicit finite-cohort ability means and double-centered rater/group effects. Paired contrasts, diagnostics and native save/reload; invariant items/steps, complete rater/group cells and full location rank. Broader DFF is unavailable. See [group effects](rater-group-effects.md). |
| Criterion-collapse class per rater | Experimental | Separate `Experimental.CriterionCollapse` scalar, unit-slope, criterion-step mixture with explicit exchangeable prior. Fit, class/category means and MCSE, diagnostics, induced-submodel comparison and same-design joint category-count prediction through shared verbs, native save/reload, checksum-checked computed reports and optional class/category figures. Held-out WAIC/LOO is not supplied. Connected person-cell allocation, observed rater/criterion cells, no duplicate performance ratings or optional facets. No calibrated classification or signed halo/horns; see [criterion collapse](criterion-collapse.md). |
| General testlet and rater-halo effects | Not supported for fitting | Explicit identifiers, structural checks, and residual/predictive summaries provide no calibrated decision or mechanism classification. Shared response effects are fitted only in the separate bounded JointRatings model above; that route does not add these effects to the common MFRM/MGMFRM fitter. |
| User-named additive scalar facets | Experimental scalar additive fitted workflow | [Arbitrary named facet collections](additive-facets.md), explicit step ownership/priors, sparse allocation checks, normalized density/gradient, original-row fixed-coordinate probabilities and prior simulation. Analytic NUTS, joint summaries/MCSE, known-level probabilities and native/portable saving; no unrestricted model combinations. Additional metadata alone does not add effects. |

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

For tested Julia/environment combinations, native-cache restrictions and the
steps to reopen or share an analysis, see the
[saved-result reproduction guide](api-saved-reporting.md#saved-result-reproduction).
The declared Julia minimum is not a guarantee for every environment or saved format.

`Experimental.JointRatings` has distinct model/result contracts. Use the shared
`load_fit`, `posterior_summary` and `save_report` verbs for persistence/reporting;
its specialized `predict` and `score` operations retain their documented targets. Its records are not
accepted by the common `fit_report`/`load_fit_cache` workflow or the comparison
and recovery functions in the table below. A computed response score is not an
accepted heldout model comparison.

The candidate connects eight result types to common saved-result operations:
`MFRMFit`, `GMFRMFit`, `MGMFRMFit`, `Experimental.NormalizedMGMFRMFit`,
`Experimental.CorrelatedMGMFRMFit`, `MultidimensionalMFRMFit`,
`Experimental.CorrelatedMFRMFit` and `Experimental.ExchangeableMFRMFit`.
An operation being available does not establish that every model is appropriate
for the same research question. Unsupported combinations remain unsupported.

| Operation | Available route | Boundary to check |
| --- | --- | --- |
| Fit, diagnostics and numerical precision | `fit` for scalar MFRM; `Experimental.fit` for the other routes; `diagnostics` and `posterior_mcse` | Use the model's required prior/specification and backend restrictions. Inspect MCSE for the actual quantities and interval endpoints you report. |
| Compare predictions of existing ratings | Qualified `compare_predictions` using the same data and persistent rating IDs | WAIC, raw IS, standard PSIS or historical Hill approximation; optional SE has declared unit assumptions. PSIS uses chain efficiency and retains warnings. No automatic winner. |
| Compare held-out predictions | `prediction_refit_plan`, separately fitted training models, `prediction_fold_observations`, `prediction_kfold`, `compare_kfold_predictions` | Known facet levels only; complete split and failure accounting. Optional first-order MCMC error from saved scores; combined errors require explicit independent simulation streams. Data-sampling K-fold SE and an automatic resumable multi-model refit runner are not supplied. |
| Compare one versus multiple dimensions under aligned response/prior conventions | `matched_dimension_refit_plans` in the [example](common_prediction_comparison.md#Matched-dimensionality-comparison), then the common refit/score route | Experimental MGMFRM with item-owned steps and one active Q loading per item; joint predictive priors still differ. This is not a scalar-GMFRM equivalence or model-choice validation. |
| Evaluate known-truth recovery | `recovery_quantities`, `recovery_evaluation`, `recovery_replications` | Truths must match model coordinates and constraints; independent datasets define replications. Optional `mcse_limits` screens computational precision while preserving failures and missing outcomes. This does not generate data, perform SBC or select a collection design. |
| Report categories, reliability and agreement | `fit_report(...; reporting=(...))` with `category_report`, `posterior_reliability` and `rater_agreement` | Explicit observation IDs, selected reliability cohorts and response matching. Finite-cohort reliability is not conventional Strata; exact/adjacent agreement is not ICC or Krippendorff alpha. |
| Describe observed-score reliability | `BayesianMGMFRM.krippendorff_alpha(data; item, level, ...)`; optional `reporting.alpha` | One explicit item and nominal/ordinal measurement level. No fit required; singleton exclusions and undefined values remain visible. No CI or severity adjustment; a different observed-score ICC operation is listed below. |
| Describe observed-score ICC | `BayesianMGMFRM.intraclass_correlation(data; item, model, definition, unit, score_scale, ...)`; optional `reporting.icc` | Complete crossed ratings on one item, explicit equal-gap scores and random/fixed, agreement/consistency, single/average choices. Point estimates only; no missing-data model, CI/SE or severity adjustment. |
| Save and reconstruct results | `save_fit_cache` / `load_fit_cache`, report bundles | Use canonical records for fixed-Q reports/recovery. Legacy v1 refusal remains explicit. Manual caches do not imply automatic request caching or general cross-version Julia serialization. |
| Compare abilities or raters within a saved fit | Qualified `posterior_contrast`, its [scalar MFRM recipe](examples.md#Compare-persons-or-raters-in-a-saved-scalar-MFRM-fit) and [MGMFRM label-based example](examples.md#Compare-abilities-or-raters-in-a-saved-MGMFRM-fit) | Scalar `MFRMFit` supports person/severity differences in unit logits, with fixed references/anchors and their excluded external uncertainty explicit. Independent `MGMFRMFit` and `NormalizedMGMFRMFit` additionally support log consistency ratios. Paired draws, MCSE and whole-fit warnings retained; no cross-model/dimension contrasts, automatic equivalence or fairness decisions. |
| Report conditional ability precision and classification risk | `BayesianMGMFRM.posterior_classification` and opt-in common `fit_report` section | Explicit people in one dimension, cutoff and probability rule; joint posterior risk and numerical MCSE. No automatic standard, multidimensional composite, ranking or known-truth error-rate guarantee. |
| Report rank uncertainty within a selected cohort | `BayesianMGMFRM.posterior_ranking` and optional common report section | One fitted ability dimension, explicit direction, joint-draw midranks and optional top-k tie bounds. No automatic selection, multidimensional aggregate, simultaneous ordering or population rank guarantee. |
| Export figures and facet diagnostics | Model-specific documented plotting and diagnostic routes | Common reporting does not extend every scalar diagnostic or plot. Wright/Pathway plots and assignment-adjusted DFF screening retain their documented scalar-MFRM scope; jointly fitted uniform group severity uses the separate [group-effects route](rater-group-effects.md), not these residual screens. |

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
| How well are unused ratings predicted? | The separate 32-block main assessment is complete: 960 fits, 938 numerically qualified, and 171 of 192 complete five-fold panels eligible. Six conditional mean log losses and three R0→R1 contrasts meet the declared replication and MCMC-error screens. | Each fit trains on 1,000 ratings and scores 250 at known person/item/rater levels. All four prior-width contrasts fail the relative-MCSE screen; they cannot select a prior. No new-level or unconditional prediction guarantee follows. |
| Which prior should be the default? | **No scientific default is adopted.** The normalized exchangeable prior remains an explicit research option with all six scales supplied. The observed R1/I1 undercoverage rules out treating SD 0.25 as generally calibrated merely because it samples well. | SD 0.5 and 1.0 also remain unaccepted as general alternatives. Prior-width ranking/equivalence is unresolved; computational defaults are not scientific recommendations. |
| Can a researcher reproduce the workflow? | The published development source has an eight-type saved workflow and short actual-fit operability checks, including report/cache reconstruction. The bounded claim and prior-default decision is recorded for this evidence. | Short fits do not establish adequate inference. Remaining integrated/environment acceptance, independent scientific review, unfamiliar-user reproduction and release acceptance stay open. |

See the [saved sensitivity illustration](prior-sensitivity.md#Saved-simulation-illustration)
for the observed prior dependence and the
[results guide](interpreting-results.md#Compare-models-against-the-same-prediction-task)
for interpreting comparisons. Research use should state the actual model, prior,
prediction target, diagnostics and unresolved limitations. An experimental API
is not a recommendation for every study that can supply its inputs.

## A bounded foundation, not a universal validation label

The October 14 scope decision retains a defensible **experimental research
workflow**: specify the normalized exchangeable target, compute its posterior,
inspect diagnostics and Monte Carlo uncertainty, report its named quantities,
and evaluate additional ratings at known facet levels. It does not adopt that
prior for every application or certify general interval coverage. Scientific
and unfamiliar-user review are still required before foundation acceptance.

The statistical evidence is narrower than the set of inputs the code accepts.
The evaluated foundation has two independent dimensions, fixed pure Q (items
I1/I2 measure dimension 1; I3/I4/I5 measure dimension 2), positive estimated
loadings and rater consistency, item-owned four-category PCM steps and a fixed
1.7 logit multiplier. Its complete data contain 50 people × 5 items × 5 raters.
These are study conditions, **not recommended minimum sample sizes**.
The prior anchors location/scale; they are not identified by the likelihood alone.

The analysis holds person/item SD at 1, severity/step kernel SD at √2 and
log-consistency kernel SD at √2/2, and compares log-loading SD 0.25, 0.5 and 1.0.
R0 uses loadings (0.7, 1.3, 0.7, 1.0, 1.3); R1 changes the first two to
(0.35, 0.5). R0 and R1 are generating conditions under the same fitted model,
not competing model families. Their prediction difference cannot decide between
MFRM and MGMFRM or between one and several dimensions. Higher log loss can also
reflect greater inherent outcome uncertainty; prediction error relative to the
known truth is a different quantity.

For example, at R1/I1 the 90% coverage counts are 1 confirmed / 0 unresolved
for prior SD 0.25, 20 / 3 for SD 0.5 and 26 / 3 for SD 1.0, each out of **32**.
The wider-prior observed ranges are 62.5–71.875% and 81.25–90.625%; they are
not confidence intervals or a calibration certificate. Recovery summaries retain
numerical failures and condition on eligible fits where stated. No finite
unconditional RMSE guarantee is supplied for failed fits.

For a new application, state the actual model, threshold owner, scale and prior;
check data support and the diagnostics of every reported quantity; report
unavailable precision and failed attempts. A converged fit cannot establish
that the model or prior answers the application question. Correlated/3D models,
mixed or sparse Q, fixed slopes, mean profiles, unknown facet levels, joint-prior
SBC and design-selection recommendations need their own evidence. Existing
operations for some of these cases remain available within their documented
experimental scope; the two-dimensional foundation study does not validate them.

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
| Dependence between dimensions | Ability prior correlation is fixed to identity. | This is a population-prior assumption, not a finding that posterior estimates or observed scores are independent. Estimating correlation requires a separate admitted 2D or [3D](correlated-3d.md) model; their priors and scopes differ. |

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

## Scalar temporal severity reports

[Experimental Rater Drift](rater-drift.md) checks regular-grid input, fits four
RW1 chains and restores them in the original environment. Reports retain
reference-relative intervals, MCSE, warnings, figures and portable re-saving.
Matched static/RW1 comparison retains model-conditional location uncertainty
and structural-zero changes. It does not import historical private chains, compute new contrasts or establish coverage/detection performance.
Its rater-owned step model is separate from item-step design planning.
