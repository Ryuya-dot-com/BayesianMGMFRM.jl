# Scope and Releases

!!! note "Development manual"
    Use the [matching source and installation instructions](installation.md).
    This is a development snapshot, not an accepted stable release.
    Model support and scientific acceptance remain as stated on each page.

Choose a model by the structure of your ratings and the quantities you need to
estimate. The table lists implemented models, available operations and specific
restrictions. Numerical precision and model adequacy must be assessed for your
data, regardless of the model family.

## Current Support

Three questions require different checks:

- **Can the package perform the requested operation?** Check the model, prior,
  backend and supported combinations below.
- **Is this fitted result adequate for the analysis?** Inspect design information,
  R-hat, ESS, divergences, energy diagnostics, MCSE and predictive checks.
- **What performance has been demonstrated?** Recovery and coverage studies apply
  to their stated generating conditions, priors and designs; see the
  [evidence summary](#current-scientific-evidence).

The [design-planning guide](design-planning.md#Choose-rank-resolution-and-a-finite-assessment)
connects preparation, execution, full-roster summaries and saved reproduction.
Its fixed-truth and joint-prior SBC examples address declared quantities and
precision objectives. They do not supply minimum sample sizes or calibration
guarantees for other designs.

| Model | Available operations and constraints |
|:--|:--|
| One-dimensional MFRM with rating-scale or partial-credit steps | Primary `0.2.0-DEV` route: `mfrm_spec(...; prior = :default)` (and `mfrm_spec(data; identification = :isometric)` or R `fit_mgmfrm(..., identification = "isometric")`, including per-criterion `category_levels` dictionaries/lists under `steps = :item` / `"item"` and explicit `fixed_calibration`) using label-permutation-invariant orthonormal Helmert zero-sum facets/steps with estimated `population_mean` and `residual_sd[person]`, posterior-integrated vs. plug-in `Infit`/`Outfit` (`diagnostics(fit; kind = :fit_statistics)`), Fair Average Score (`diagnostics(fit; kind = :fair_average)`), Table-14-style pair-level residual screening (`diagnostics(fit; kind = :pair_bias)`), and finite-cohort posterior `reliability`. The explicit reference-coded `BayesianMGMFRM.Legacy.FacetSpec` + `BayesianMGMFRM.Legacy.MFRMPrior` route remains supported for backward compatibility and emits an `over_anchored_reference_prior_risk` warning when unanchored zero-fixed references are paired with a zero-mean fixed-SD person prior. |
| Custom Stan post-estimation adapter and portable joint-draw handoff | `BayesianMGMFRM.StanAdapter` (`fit_stan`, `import_csv`) wraps explicit-role CmdStan `.stan` runs or existing `.csv` chains without arbitrary `.stan` parsing or implicit variable guessing; `BayesianMGMFRM.PortableHandoff` (`export_handoff`) exports versioned, SHA-256-sealed IEEE-754 `Float64` `chain × iteration × parameter` handoffs (`expected_sha256` required on `load_report`). See [Custom Stan Adapter and Portable Handoffs](stan-adapter.md). |
| Non-Bayesian 1D RSM/PCM via `JMLE` and `MMLE` (`method = :jmle \| :mmle`) | `fit(spec; method = :jmle \| :mmle, ...)` across 3-facet `BayesianMGMFRM.Legacy.FacetSpec` and general $F$-facet `mfrm_spec` (with `prior = :none`, `prior = :default`, or `prior_sd`). Exact constrained observed-information SE + FACETS conditional/real SEs, `EAP`/`WLE`/`MLE` person scoring, Wright–Masters `Infit`/`Outfit` `MNSQ`/`ZSTD`, MMLE `AIC`/`BIC` `compare_models`, and `:posterior`/`:wright`/`:pathway` figures. Multidimensional and GPCM frequentist estimation remain out of scope; see [frequentist 1D JMLE & MMLE](frequentist-mfrm.md). |
| Fixed-coefficient multidimensional MFRM | `Experimental.fit` on Julia or CmdStan; fixed Q coefficients, unit logits and identity latent correlation. Manual caches and report/figure bundles are available. |
| Two-dimensional correlated MFRM | `Experimental.correlated(spec)` then `Experimental.fit`; between-item fixed Q, at least two pure items per dimension and both dimensions observed for each person. Julia/CmdStan, manual caches and report/figure bundles are available. |
| Fixed-coefficient multidimensional MFRM with an exchangeable rater prior | Explicit `Experimental.ExchangeablePrior` with independent abilities or the admitted 2D correlated specification. Julia/CmdStan return `Experimental.ExchangeableMFRMFit`. The rater kernel SD is supplied, not estimated; this prior is not accepted by scalar MFRM, GMFRM or MGMFRM. |
| Scalar GMFRM: item discrimination × rater consistency | Use the specialized `BayesianMGMFRM.Experimental` interface for this source-aligned specification; unit response scale (`logit_scale = 1.0`), rater-owned steps, and `loading_scope = :entire_linear_predictor` remain mandatory. |
| Fixed-Q confirmatory MGMFRM with the raw prior | `Experimental.fit` with explicit `GeneralizedPrior`; one or more dimensions with an explicit fixed Q mask, estimated positive active loadings and rater consistency, and independent ability priors. |
| Fixed-Q MGMFRM with a normalized prior | Unwrapped `Experimental.fit` with explicit `NormalizedMGMFRMPrior`, `prior_model=:exchangeable` or `:source`, all six scales and a source-rater ID when required. Independent abilities; Julia/AdvancedHMC admits binary categories, CmdStan requires at least three. Manual caches and reports are available. This selects a different prior target, not a relabeling of a raw fit. Correlated fitting and automatic request caching are unavailable. |
| Scale-identified 1D GMFRM (`slope = :rater \| :item \| :both`) | `mfrm_spec(...; slope = :rater \| :item \| :both, steps = :global \| :item \| :rater, prior = :default)` and `fit` (or R `fit_mgmfrm(..., model = "gmfrm", slope = ...)`). Supports orthonormal isometric rater consistency and/or item discrimination (`:geometric_mean_one` or `:anchor_item`), `rater_slope_scope = :entire_linear_predictor` (default) or `:ability_only`, `logit_scale = 1.0` (default) or `1.7`, draw-specific orthogonal location decoupling, common-plan `fair_average`, weighted sufficient scores, and importance-sampling `prior_sensitivity`. |
| Fixed-Q MGMFRM with multiplicative scale identification (`Experimental.ScaleIdentifiedMGMFRMPrior`) | `mfrm_spec(...; q_matrix = ..., prior = :default)` and `fit` provide the unified entry point (accepting matrix or label-keyed `q_matrix` inputs, `steps = :global \| :item \| :rater`, `correlation = :independent \| :lkj`, `rater_slope_scope = :entire_linear_predictor \| :ability_only`, and `aggregation = :additive \| :softmin` with estimated or fixed `softmin_kappa`); `Experimental.scale_identified_target(spec; ...)` provides direct target access. Decouples dimension ability SDs `ability_sd[dim=d]` ($\sigma_{\theta_d}$) from within-dimension item sensitivity via `:geometric_mean_one` (label-permutation-invariant Helmert zero-sum pure-item log-loadings, geometric mean `1.0`) or `:anchor_item` (`1.0` pure reference item per dimension), reconstructs unit-variance population `standardized_loading` ($a^{\text{std}}_{id} = \tilde{a}_{id}\sigma_{\theta_d}$), audits generalized location-and-step design rank via `MRCML.design_matrices`, supports `logit_scale = 1.7` or `1.0`, exact analytical gradients, CmdStan `2.39.0` fixed-point parity, `fair_average`, `prior_sensitivity`, and `PortableHandoff` export. |
| D1 MGMFRM with matched fixed/free item slopes | `Experimental.slope_restriction`, item-owned PCM, rater consistency fixed at one and explicit exchangeable `NormalizedMGMFRMPrior`. Julia/AdvancedHMC with raw coordinates only; manual caches and known-level refit planning. CmdStan and source priors are unavailable for this wrapper. See [the slope contract](experimental.md#Matched-fixed-and-estimated-item-slopes). |
| D1 fixed-slope MGMFRM with explicit location/step means | `Experimental.MeanProfilePrior` additionally requires fixed-one item slopes and exact item/category IDs. Julia/AdvancedHMC with raw coordinates only; manual caches and known-level refit planning. Included in this development snapshot. See [the mean-profile contract](experimental.md#Fixed-location-and-step-mean-profiles). |
| Two-dimensional correlated MGMFRM | Between-item Q, estimated positive loadings/consistency, `Experimental.correlated(spec)` and explicit `GeneralizedPrior`. Julia/CmdStan, prior/conditional posterior prediction, summaries, MCSE, diagnostics, manual caches and report/figure bundles are available. Prior sensitivity and interval coverage remain dependent on the rating design. |
| Preliminary-only three-outcome no-state workflow | `Experimental.ThreeIndicator` checks labelled 9/9/2 input, prepares and fits four serial Julia/AdvancedHMC chains, restores native results in the producing environment and reports named panel/contrast intervals, MCSE, prior settings and warnings. It also reads original Julia/Stan computed reports. Historical native migration, custom numerical priors, new contrasts after fitting and latent states are not supplied. See [fitting](fitting.md#three-outcome-fitting), [input inspection](data-validation.md#three-outcome-input) and [saved results](api-saved-reporting.md#three-outcome-saved-reports). |
| Concurrent three-outcome workflow | Two-study 9/9/2 input, full numerical Gaussian/half-normal/LKJ prior configuration, joint Julia fitting/reporting, prior and posterior predictive checks, and source-bound persistence. Portable model v2 reads legacy preset v1. The independent Stan data/reference adapter requires full listener×word covariance and does not supply a public Stan fitter. See [the concurrent guide](concurrent-three-outcome.md). |
| Two-criterion ordinal event association | `Experimental.JointRatings.OrdinalAssociation`: explicit criterion means, estimated person SDs, centered task effects, correlated response effects and a common adjacent log odds ratio. Unit coefficients, explicit priors, separate criterion step groups; at least three common categories. Native fit/report/contrast/save/reopen and existing-event joint tables. No scientific default, new-level prediction or causal halo claim. See [Paired Ordinal Association](ordinal-association.md). |
| Two-criterion shared-response PCM | `Experimental.JointRatings`: fixed unit coefficients, correlated person/response effects, criterion-specific task/rater effects, explicit priors and declared criterion-group steps. Distinct native result/report types with shared save/reopen verbs; conditional known-level marginal prediction and response scores. No accepted heldout comparison or recovery/SBC claim. See [Joint Ratings](joint-ratings.md). |
| Other generalized discrimination structures | Fitting is available only for the slope, threshold and Q combinations listed here; arbitrary combinations are not implemented. |
| Three-dimensional correlated MGMFRM | [Correlated3D](correlated-3d.md): pure fixed Q, unit population marginal SDs, explicit normalized exchangeable scales/LKJ prior, generation, Julia NUTS, named marginal/partial correlations, conditional row probabilities and trusted native save/load. General recovery and interval coverage across rating designs have not been established. |
| Star-factorized multi-criterion ordinal association | `Experimental.joint_rating_spec(...; association=:star)`: complete events with one declared root, mixed ordinal/binary category supports, correlated entity/rater effects, criterion-specific steps and root-branch residual associations. Explicit priors, Julia NUTS, qualification, reports, category PPC, event criteria, figures and native save/reopen. Recovery across rating designs and general halo mechanisms remain unestablished. See [Star Association](star-association.md). |
| Exploratory loadings or higher-dimensional fixed-Q correlation workflows | Learned/rotated Q and cross-loadings in Correlated3D are outside the admitted routes. `Experimental.correlated` admits the documented 2D and pure-Q 3D models, with different prior/scale contracts; this bound does not apply to the declared criterion vector in the separate StarAssociation model. |
| Observed-group differences in rater severity | Separate `Experimental.RaterGroupEffects` scalar unit-slope item-step PCM, explicit finite-cohort ability means and double-centered rater/group effects. Paired contrasts, diagnostics and native save/reload; invariant items/steps, complete rater/group cells and full location rank. Broader DFF is unavailable. See [group effects](rater-group-effects.md). |
| Criterion-collapse class per rater | Separate `Experimental.CriterionCollapse` scalar, unit-slope, criterion-step mixture with explicit exchangeable prior. Fit, class/category means and MCSE (`fit_report` / `posterior_summary` / `category_summary`), diagnostics, induced-submodel and two-report held-profile `compare_models`, `loo_refit_plan` training-posterior `MaskedTarget` refits, and same-design joint category-count `predictive_check` / `posterior_predictive_check` through shared verbs, native save/reload, checksum-checked computed reports and `BayesianMGMFRM.plot` (`:posterior`, `:criterion_collapse_categories`, `:predictive`, `:comparison`). Conditional performance–rater profile PSIS-LOO is available; row-wise WAIC/LOO and new-level prediction are not supplied. Connected person-cell allocation, observed rater/criterion cells, no duplicate performance ratings or optional facets. No calibrated classification or signed halo/horns; see [criterion collapse](criterion-collapse.md). |
| General testlet and rater-halo effects | Scalar unit-slope person-by-testlet cluster residuals ($u_{p, d} \sim \mathcal{N}(0, \sigma_u^2)$) reuse the `mfrm_spec` explanatory population/performance workflow ([Person-by-Testlet Dependence](person-testlet.md)), with matched `0.0` no-testlet held-cluster comparison and `mode=:new_owners` cluster prediction. Explicit identifiers, structural checks, and residual/predictive summaries provide no calibrated detector; multidimensional testlets, rater-specific halo mechanisms, and combined testlet-halo-DFF models are not supported. |
| User-named additive scalar facets | [Arbitrary named facet collections](additive-facets.md), explicit step ownership/priors, sparse allocation checks, normalized density/gradient, original-row fixed-coordinate probabilities and prior simulation. Analytic NUTS, joint summaries/MCSE, known-level probabilities and native/portable saving; no unrestricted model combinations. Additional metadata alone does not add effects. |
| Single bounded score with endpoints | [Bounded scores](bounded-scores.md) retain raw bounds/endpoint atoms, owner mean regressions, within/between predictors and iid population random intercepts. Explicit Normal coefficients/logits and fixed or LogNormal residual SDs; LogNormal precision. Shared diagnostics, prior/PPC, known-owner and explicit `mode=:new_owners` population-integrated predictions, sensitivity, rating-wise PSIS and saved plots. [One or more correlated intercept/slope effects](random-slopes.md) per named owner are supported in the interior mean. [Distributional regressions](distributional-scores.md) add precision and endpoint predictors with independent population intercepts. No Rasch-property guarantee, finite sum-zero effects, or cross-parameter covariance. |
| Mixed-family multi-outcome speaking events | [Mixed-outcome speaking models](mixed-outcomes.md) combine `:ordinal`, `:zero_one_inflated_beta`, `:binomial`, and `:beta_binomial` outcomes on one event table with partial-outcome `missing` masks, matrix-driven 1D or correlated (`LKJ`) owner factors and fixed/estimated loadings, joint paired within-event PPC (`paired_cells`), held-performance Gauss–Hermite integration, prior powers, and distinct `mode=:known_owners` versus `mode=:new_owners` prediction. Conditionally independent within event given declared owners; distinct from `Concurrent` (fixed `9/9/2` Plackett copula) and `StarAssociation` (ordinal-only star association). |
| Scalar predictors and population severity | [Owner-declared regression](explanatory-ratings.md) through the same `mfrm_spec` and lifecycle: person/response/facet predictors, explicit Normal coefficients and fixed/LogNormal (or `0.0` inactive) residual SDs; known-owner and explicit `mode=:new_owners` population-integrated category probabilities, posterior PPC and saved-report figures. [Repeated-performance decomposition](repeated-performances.md) preserves unique-performance means, and [person-by-testlet cluster residuals](person-testlet.md) reuse the same iid performance route. [Criterion-owned coefficients and category supports](criterion-effects.md) permit explicit binary/ordinal combinations and same-source contrasts under a scalar shared-effect model. [Held-performance comparison](explanatory-diagnostics.md#Does-adding-the-interactions-improve-predictions?) integrates one declared iid performance residual, retaining known other owners and the observed predictor roster; computed reports/plots preserve numerical warnings. No crossed-design population SE or automatic ranking. Unit slopes/multiplier; no Patz HRM, ordinal random slopes, or arbitrary composition. |

The module name `BayesianMGMFRM.Experimental` and existing saved status fields
are retained for API and file compatibility. Interfaces in that namespace may
change in a minor release; pin the package version when relying on them.
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
`BayesianMGMFRM.Legacy.MFRMFit`, `GMFRMFit`, `MGMFRMFit`, `Experimental.NormalizedMGMFRMFit`,
`Experimental.CorrelatedMGMFRMFit`, `MultidimensionalMFRMFit`,
`Experimental.CorrelatedMFRMFit` and `Experimental.ExchangeableMFRMFit`.
An operation being available does not establish that every model is appropriate
for the same research question. Unsupported combinations remain unsupported.

| Operation | Available route | Boundary to check |
| --- | --- | --- |
| Fit, diagnostics and numerical precision | `fit` for scalar MFRM; `Experimental.fit` for the other routes; `diagnostics` and `posterior_mcse` | Use the model's required prior/specification and backend restrictions. Inspect MCSE for the actual quantities and interval endpoints you report. |
| Compare predictions of existing ratings | Qualified `compare_predictions` using the same data and persistent rating IDs | WAIC, raw IS, standard PSIS or historical Hill approximation; optional SE has declared unit assumptions. PSIS uses chain efficiency and retains warnings. No automatic winner. |
| Compare held-out predictions | `prediction_refit_plan`, separately fitted training models, `prediction_fold_observations`, `prediction_kfold`, `compare_kfold_predictions` | Known facet levels only; complete split and failure accounting. Optional first-order MCMC error from saved scores; combined errors require explicit independent simulation streams. Data-sampling K-fold SE and an automatic resumable multi-model refit runner are not supplied. |
| Compare one versus multiple dimensions under aligned response/prior conventions | `matched_dimension_refit_plans` in the [example](common_prediction_comparison.md#Matched-dimensionality-comparison), then the common refit/score route | MGMFRM with item-owned steps and one active Q loading per item; joint predictive priors still differ. This is not a scalar-GMFRM equivalence or model-choice validation. |
| Evaluate known-truth recovery | `recovery_quantities`, `recovery_evaluation`, `recovery_replications` | Truths must match model coordinates and constraints; independent datasets define replications. Optional `mcse_limits` screens computational precision while preserving failures and missing outcomes. This does not generate data, perform SBC or select a collection design. |
| Report categories, reliability and agreement | `fit_report(...; reporting=(...))` with `category_report`, `posterior_reliability` and `rater_agreement` | Explicit observation IDs, selected reliability cohorts and response matching. Finite-cohort reliability is not conventional Strata; exact/adjacent agreement is not ICC or Krippendorff alpha. |
| Describe observed-score reliability | `BayesianMGMFRM.krippendorff_alpha(data; item, level, ...)`; optional `reporting.alpha` | One explicit item and nominal/ordinal measurement level. No fit required; singleton exclusions and undefined values remain visible. No CI or severity adjustment; a different observed-score ICC operation is listed below. |
| Describe observed-score ICC | `BayesianMGMFRM.intraclass_correlation(data; item, model, definition, unit, score_scale, ...)`; optional `reporting.icc` | Complete crossed ratings on one item, explicit equal-gap scores and random/fixed, agreement/consistency, single/average choices. Point estimates only; no missing-data model, CI/SE or severity adjustment. |
| Save and reconstruct results | `save_fit_cache` / `load_fit_cache`, report bundles | Use canonical records for fixed-Q reports/recovery. Legacy v1 refusal remains explicit. Manual caches do not imply automatic request caching or general cross-version Julia serialization. |
| Compare abilities or raters within a saved fit | Qualified `posterior_contrast`, its [scalar MFRM recipe](examples.md#Compare-persons-or-raters-in-a-saved-scalar-MFRM-fit) and [MGMFRM label-based example](examples.md#Compare-abilities-or-raters-in-a-saved-MGMFRM-fit) | Scalar `BayesianMGMFRM.Legacy.MFRMFit` supports person/severity differences in unit logits, with fixed references/anchors and their excluded external uncertainty explicit. Independent `MGMFRMFit` and `NormalizedMGMFRMFit` additionally support log consistency ratios. Paired draws, MCSE and whole-fit warnings retained; no cross-model/dimension contrasts, automatic equivalence or fairness decisions. |
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

## [Shared-event analysis: available and missing operations](@id shared-event-operations)

The scalar shared-effect model fits person-by-rater or person-by-testlet effects
with `mfrm_spec` / `fit`, and through R `fit_mgmfrm(..., random_effects = ...)`.
Posterior summaries, contrasts, sampler diagnostics and saved results are available.
The following operations share the same posterior draws and preserve numerical warnings:

- Standard MRCML and shared-event fits support assessment/performance-unit LOO
  and explicit event-deletion refits. Integrate the shared event effect once over
  the joint response profile; the standard model uses its joint conditional likelihood.
- Q3 and Infit/Outfit describe residual fit conditional on fitted effects and
  provide posterior predictive reference distributions. Finite-cohort posterior
  reliability and numerical MCSE are available; population/design reliability
  is not inferred from one fitted cohort.
- R `random_effects` composes with group effects, DFF on the finite facets,
  and fixed calibration of the finite facets. Shared effects themselves cannot
  simultaneously be threshold owners, fixed anchors, or fixed DFF interactions.
- [Bayesian multivariate G-theory](multivariate-generalizability.md) separates
  score-scale covariance components and supplies posterior D-study coefficients.

For a standard-model check followed by a shared-effect refit, compare predictions
for the same held-out unit. Individual-rating LOO and integrated assessment LOO
answer different questions and cannot be compared directly. Residual dependence
can motivate a shared-effect model, but does not by itself identify a halo mechanism.
See [shared event effects](explanatory-ratings.md#Shared-event-effects-(Experimental))
for model specification and interpretation.

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
| Are the parameter intervals calibrated? | Recovery and failure summaries are available for the declared conditions. Under prior-only scale anchoring (`NormalizedMGMFRMPrior`), in the R1 stress condition I1's 90% interval covered its true loading (`0.35`) in only `1 / 32` blocks (`3.1%`) at log-loading prior SD `0.25`, despite all 32 fits qualifying numerically. Decoupling dimension scale $\sigma_{\theta_d}$ from within-dimension loading shape via `Experimental.ScaleIdentifiedMGMFRMPrior` at the same relative log-loading SD (`0.25`) raised `standardized_loading[I1, dim=1]` 90% coverage on the same 32-block R1 benchmark to `30 / 32` (`93.8%`) under both `:geometric_mean_one` (`27 / 32` whole-fit qualified) and `:anchor_item` (`28 / 32` whole-fit qualified). In a separate 200-dataset 1D comparison (60 examinees, 6 raters, 3 raters per examinee, 4 criteria, 5 categories, 720 ratings per dataset) with heterogeneous rater slopes (`0.468` to `1.871`), rater-slope GMFRM reduced mean person RMSE from `0.3481` to `0.3213` logits (lower in `184 / 200` datasets) and raised person 95% interval coverage from `92.00%` to `94.83%` (`190 / 200` standard MFRM and `179 / 200` GMFRM fits met all four-chain whole-fit diagnostic thresholds; person coverage among qualified fits was `91.98%` and `94.82%`, and joint whole-fit qualification plus person coverage over all 200 datasets was `87.38%` and `84.87%`). Across the six generating slopes, rater-slope 95% coverage averaged `89.58%` overall (`89.66%` among the 179 qualified fits; `80.25%` jointly qualified and covered out of 200), with shrinkage toward `1.0` lowering coverage at the extremes (`150 / 200 = 75.0%` for `R1 = 0.468` and `172 / 200 = 86.0%` for `R6 = 1.871`). | Fixed-truth studies are not general coverage theorems or joint-prior SBC calibration across arbitrary designs. Unqualified fits remain retained in full denominators, and individual rater-slope intervals remain sensitive to shrinkage at extreme slopes. |
| What do the 2D correlation and aggregation checks show? | In a 200-dataset fixed pure-Q 2D recovery comparison (`100` datasets at `rho = 0.40` and `100` at `rho = 0.75`; 60 examinees, 6 raters, 3 raters per examinee, 4 criteria with 2 pure items per dimension, 5 categories, 720 ratings per dataset, low standardized loading `0.35` on `I1`, rater consistency `0.748` to `1.347`, 4 chains × 1,000 retained draws per fit), all 600 fits returned with zero divergences and zero max-treedepth hits; four-chain whole-fit diagnostics passed in `195 / 200` (`97.5%`: `95 / 100` at `rho = 0.40`, `100 / 100` at `rho = 0.75`) `LKJ(2.0)` `:geometric_mean_one` MGMFRM fits, `190 / 200` (`95.0%`: `95 / 100` in each stratum) independent 2D fits, and `195 / 200` (`97.5%`) 1D `MRCML` fits. Relative to independent 2D MGMFRM, `LKJ(2.0)` reduced low-loading dimension-1 person RMSE from `0.2597` to `0.2500` logits (`-0.0096` `[−0.0111, −0.0081]`, lower in `168 / 200` datasets; `-0.0150` logits and `92 / 100` datasets at `rho = 0.75`) while maintaining nominal 95% person interval coverage (`94.97%` unconditional, `94.95%` among qualified fits, `92.58%` jointly qualified and covered out of `200`; dimension 2: RMSE `0.3289` vs. `0.3348`, coverage `95.18%` unconditional, `92.78%` joint). Under `LKJ(2.0)`, 95% intervals covered `standardized_loading[I1, dim=1] = 0.35` in `190 / 200` datasets (`95.0%`; `95 / 100` in each stratum, `92.5%` joint; pure-item `loading[I1, dim=1]` `188 / 200 = 94.0%`), dimension SDs in `194 / 200` (`97.0%`) and `191 / 200` (`95.5%`), rater consistency slopes in `94.92%` (`93.0%–97.5%`), and latent correlation in `92 / 100` datasets at `rho = 0.40` (bias `-0.030`, RMSE `0.140`) and `93 / 100` at `rho = 0.75` (bias `-0.045`, RMSE `0.096`; `185 / 200 = 92.5%` unconditional, `180 / 200 = 90.0%` joint). Under 1D `MRCML`, maximum absolute adjusted residual correlation (`ppp_max_abs_adjusted_q3 < 0.05`) flagged 2D misfit in `99 / 100` (`rho = 0.40`) and `64 / 100` (`rho = 0.75`) datasets vs. `0 / 200` for unadjusted mean `Q3` (within- and between-dimension residuals cancel). Six reserved standard, single-bridge, and `rho = 0.90` datasets also matched between Julia NUTS and CmdStan within combined Monte Carlo error; across a 15-scenario × 50-replication sensitivity grid, forcing pure Q onto mixed-Q data inflated correlation (`0.703` vs. `0.421` at truth `0.40`); and on cross-loaded bottleneck items (`kappa = 3.5`), `aggregation = :softmin` separated from additive compensation at `rho = 0.35` (`ΔELPD_LOO = +26.1 ± 5.6`, avoiding `+0.38` to `+0.43` logit difficulty bias) but became indistinguishable at `rho = 0.80` (`+0.05 ± 1.28`). | Fixed-truth connected pure-Q 2D results retain mild `LKJ(2.0)` correlation shrinkage toward zero at 60 examinees, high rating-level PSIS Pareto-`k` rates (`198 / 200` fits), and separate boundaries for sparse/unbridged panels, omitted cross-loadings, `:anchor_item` under extreme ability spread, earlier fixed-slope MML comparisons, and three-dimensional correlation models. |
| How well are unused ratings predicted? | The separate 32-block main assessment is complete: 960 fits, 938 numerically qualified, and 171 of 192 complete five-fold panels eligible. Six conditional mean log losses and three R0→R1 contrasts meet the declared replication and MCMC-error screens. | Each fit trains on 1,000 ratings and scores 250 at known person/item/rater levels. All four prior-width contrasts fail the relative-MCSE screen; they cannot select a prior. No new-level or unconditional prediction guarantee follows. |
| Which prior should be the default? | **No universal MGMFRM prior default is adopted.** Prior-only scale anchoring (`NormalizedMGMFRMPrior` at SD `0.25`) shrinks a low-loading dimension's overall spread toward `1.0` and causes severe undercoverage on R1/I1; `Experimental.ScaleIdentifiedMGMFRMPrior` separates dimension SD $\sigma_{\theta_d}$ from pure-item relative loadings, but users must still choose `:geometric_mean_one` or `:anchor_item`, location identification, and prior scales explicitly. | Prior-only SD `0.5` and `1.0` also remain unaccepted as general defaults. Computational defaults are not universal scientific recommendations. |
| Can a researcher reproduce the workflow? | The published development source has an eight-type saved workflow and short actual-fit operability checks, including report/cache reconstruction. The bounded claim and prior-default decision is recorded for this evidence. | Short fits do not establish adequate inference. Remaining integrated/environment acceptance, independent scientific review, unfamiliar-user reproduction and release acceptance stay open. |

See the [saved sensitivity illustration](prior-sensitivity.md#Saved-simulation-illustration)
for the observed prior dependence and the
[results guide](interpreting-results.md#Compare-models-against-the-same-prediction-task)
for interpreting comparisons. Research use should state the actual model, prior,
prediction target, diagnostics and unresolved limitations. An available API
is not a recommendation for every study that can supply its inputs.

## A bounded foundation, not a universal validation label

The evaluated normalized-prior workflow is: specify the normalized exchangeable target, compute its posterior,
inspect diagnostics and Monte Carlo uncertainty, report its named quantities,
and evaluate additional ratings at known facet levels. It does not adopt that
prior for every application or certify general interval coverage.

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
configurations; the two-dimensional foundation study does not validate them.

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
and [model extensions guide](experimental.md#Workflow) give the parameter and prior
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

Available operations describe what this version can compute. Convergence,
model adequacy and precision must be assessed for each analysis. Availability
alone does not establish recovery, robustness or external-software agreement. Known-truth
simulation and protocol helpers have their own [research API
reference](api-validation-evidence.md); their presence does not change the
fitting boundary above.

Use the [matching source snapshot](installation.md)
for this manual. Other installed versions describe their own support; preserve
the exact revision/archive for reproducible work.

Read the manual and examples for the installed revision. Development
documentation can describe features absent from an earlier registered release.

For reporting scope and current limitations of bias, separation/reliability,
Strata and score agreement, see [the MFRM reporting guide](interpreting-results.md#Bias,-reliability-and-a-complete-MFRM-report).
In particular, the historical posterior separation screen is not a validated
FACETS or EAP reliability estimator; it should not be promoted by a Strata
transformation.

## Scalar temporal severity reports

[Rater Drift](rater-drift.md) checks regular-grid input, fits four
RW1 chains and restores them in the original environment. Reports retain
reference-relative intervals, MCSE, warnings, figures and portable re-saving.
Matched static/RW1 comparison retains model-conditional location uncertainty
and structural-zero changes. It does not import historical private chains, compute new contrasts or establish coverage/detection performance.
Its rater-owned step model is separate from item-step design planning.

Correct/total responses have an [scalar count route](count-scores.md):
binomial or beta-binomial observations, explicit trials, explanatory population
intercepts, known-owner prediction, denominator-aware diagnostics and saved reports.
This does not establish word-specific difficulty, random slopes, joint outcomes or new-owner prediction.

## [Interaction (DFF) Scale Priors, Local Dependence, and Non-Goals](@id dff-priors-and-non-goals)

### Interaction / DFF prior rationale (explicit choice, no silent default)

Jointly fitted differential facet functioning (`interactions` in `mfrm_spec`, such
as `(:rater, :item) => prior` or `(:rater, :step) => prior` on the doubly centered
Kronecker–Helmert subspace) requires an
explicit prior scale specification—no silent default is substituted when
`interactions` are declared:

| Prior family | Role and recommendation | Mathematical and computational rationale |
| :--- | :--- | :--- |
| **`HalfNormal(s)`** (`truncated(Normal(0, s), 0, Inf)`) | **Recommended zero-supporting interaction SD prior** | Positive density at $\tau = 0$ permits shrinkage to pure additive main effects when interaction evidence is weak, while Gaussian tails give finite marginal cell and tetrad-contrast variance (`implied_tetrad_contrast_sd` in `design_summary(spec)`). Verified against CmdStan `2.39`. |
| **`Half-t(df = 3–4, s)`** (`truncated(LocationScale(0, s, TDist(df)), 0, Inf)`) | **Recommended heavy-bias-tolerant interaction SD prior** | Positive density at $\tau = 0$ with finite variance ($\nu > 2$), accommodating occasional larger focal rater–item bias spikes better than `HalfNormal` without inducing pathological tail funnels. Verified against CmdStan `2.39`. |
| **`LogNormal(mu, sd)`** | Supported explicit positive-scale alternative | Useful when prior domain knowledge bounds $\tau$ strictly away from zero, but has zero density at $\tau = 0$ and can resist full collapse to zero when true DFF is absent. |
| **`Half-Cauchy`** (`df = 1`) | **Excluded from recommended presets** (`design_summary` emits a funnel warning for `df <= 2`) | Infinite prior variance ($\mathbb{E}[\tau^2] = \infty$) produces severe HMC funnel geometry and divergent transitions when sparse rater–item cells carry limited information. |
| **`Laplace` (Bayesian LASSO)** | **Excluded from recommended presets** | A fixed Laplace penalty combines weak concentration near zero with exponential tail shrinkage that over-shrinks genuinely large focal biases (Carvalho, Polson, & Scott, 2010). |
| **`LKJ(eta)`** (e.g., `LKJ(2)`) | **Correlation matrices $R$ only** | Applies strictly to positive-definite correlation matrices in multi-criterion, random-slope, and multidimensional models—never to scalar interaction standard deviations. |
| **Regularized Horseshoe** (Piironen & Vehtari, 2017) | **Not implemented** | Standard coordinate-wise local scales $\lambda_{ri}$ break exchangeability or distort marginal slab widths when projected through doubly centered row- and column-sum-to-zero constraints; deferred pending a subspace-invariant formulation. |

Use `diagnostics(fit; kind = :pair_bias, pair = (:rater, :item))` (or
`BayesianMGMFRM.dff_report(fit)`) to inspect observed vs. expected scores,
score residuals, information-weighted approximate severity-bias logits, and tail
probabilities. Its `analysis_mode` explicitly distinguishes exploratory
post-hoc residual screens on main-effects models (`:secondary_residual_screen`)
from posterior interaction summaries on jointly fitted interaction models
(`:joint_interaction_model`). Use `diagnostics(fit; kind = :fair_average, by = :rater)`
to translate logit severities into expected rating-scale scores at sample-mean
or zero-origin baselines with full posterior credible intervals and MCSE.

### Temporal drift and local-dependence status

Temporal severity drift (`Experimental.RaterDrift` `RW1`) and all local-dependence
extensions—person-by-testlet cluster residuals ([Person-by-Testlet Dependence](person-testlet.md)),
paired and star-factorized multi-criterion event association ([Joint Ratings](joint-ratings.md),
[Ordinal Association](ordinal-association.md), [Star Association](star-association.md)),
and rater criterion-collapse mixtures ([Criterion Collapse](criterion-collapse.md))—remain
available through their model-specific interfaces in `0.2.0-DEV`.

### Declared `0.2.0-DEV` non-goals vs. FACETS and ACER ConQuest

| Capability | External reference software | `BayesianMGMFRM.jl` `0.2.0-DEV` boundary |
| :--- | :--- | :--- |
| High-dimensional frequentist MML / Monte Carlo integration and survey-weighted multidimensional latent regression | ACER ConQuest (`mml` / `montecarlo` with replicate weights and plausible-value conditioning) | **Out of scope.** Frequentist `method = :mmle` and `method = :jmle` are strictly one-dimensional; multidimensional models (`GMFRM`, `MGMFRM`, `Correlated3D`, `StarAssociation`) are Bayesian NUTS routes without complex-survey case weights. Use ACER ConQuest for PISA/NAEP-scale survey-weighted multidimensional MML. |
| Observation, element, or sampling replication weights in standard Bayesian MFRM | FACETS (`Models=` / element / datum weights) and ConQuest (`caseweight`) | **Explicitly refused.** Multiplying log-likelihood contributions by non-unit weights distorts posterior variance and credible-interval calibration unless a pseudo-posterior sandwich or survey-design model is specified; unweighted rating rows are required. |
| Native FACETS specification-file or ConQuest command-file syntax parsers and interactive GUI workflows | FACETS specification files / GUI and ConQuest `.cqc` command scripts | **Out of scope.** Models are declared semantically via `mfrm_spec`, R `fit_mgmfrm`, or `MRCML.from_tam` / `MRCML.custom_spec`, and persisted via SHA-256-verified JSON handoff bundles (`PortableHandoff`) rather than legacy command-file emulation. |
