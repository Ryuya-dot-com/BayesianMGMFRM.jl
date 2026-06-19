# Minimal Bayesian Fitting

The first Bayesian fitting paths target the same minimal additive MFRM/RSM/PCM
design returned by `getdesign`. They place independent zero-centered normal
priors on the identified parameter vector. `backend = :julia` uses a
random-walk Metropolis kernel for small validation examples, while
`backend = :advancedhmc` uses the package's `MFRMLogDensity` target with
AdvancedHMC/NUTS and `backend = :turing` wraps the same target in a
Turing/NUTS model.

## Guarded Generalized Model Caveats

The public `fit` path is currently limited to fit-supported MFRM/RSM/PCM
specifications by default. A narrow guarded experimental exception exists for
the scalar source-aligned GMFRM promotion candidate: `fit(spec; experimental =
true)` returns [`GMFRMFit`](@ref) only when the spec is one-dimensional,
`family = :gmfrm`, `discrimination = :rater`, and still on the specified-only
manifest path. Unsupported generalized options, public `MFRMPrior` priors,
MGMFRM specs, multidimensional specs, and non-rater discrimination specs are
rejected. Specified-only GMFRM and MGMFRM specs otherwise remain inspection
surfaces: they can expose manifests, constraint tables, preview rows, and
internal fixture evidence without silently fitting the wrong likelihood.

The scalar GMFRM promotion candidate is internal. Its source-aligned Julia
fixture, BridgeStan oracle, direct-parameter checks, candidate-chain artifact,
and recovery-smoke artifact are evidence for the private candidate, not a public
prior contract for arbitrary GMFRM variants. The local guarded-exposure review
now records the fit API dry-run contract, the guarded method-wiring artifact,
the experimental fit validation grid, the posterior predictive grid, and the
sparse-pathology recovery grid plus the prior/likelihood sensitivity grid; the
compact real-data case study, local full-paper reproduction archive, local
confirmatory MGMFRM guarded fit method-wiring artifact, and local confirmatory
MGMFRM guarded fit validation-grid plus guarded fit API dry-run, guarded public
exposure-review, and prediction/model-weight policy artifacts are also
recorded. The guarded local MGMFRM fit entrypoint and archive metadata are now
recorded, so broader generalized exposure remains blocked by the separate
public-scope release decision and stronger validation evidence.
A local claim-level recovery/reproduction archive manifest and a
broader experimental exposure decision review now record fixture hashes,
generator commands, source references, local verification commands, and the
guarded-scalar-only exposure decision. A local DFF estimand/validation grid is
also recorded as validation-only evidence; fitted DFF model effects remain
blocked. A local Gate E manuscript-scale evidence grid aggregates the versioned
fit-validation, posterior predictive, sparse-pathology, sensitivity, real-data,
DFF, and confirmatory MGMFRM sparse artifacts. Longer local stress-chain
evidence, an initial
same-observation
baseline comparison, a three-scenario baseline/calibration grid,
interval/decision and sparse-design grids, a WAIC influence review, the
raw importance-sampling LOO/Pareto-k review, a deterministic 3-fold refit
review, a guarded fit API dry-run artifact, the raw-prior Jacobian policy, and
the experimental generalized fit-artifact contract are recorded internally. The
guarded scalar GMFRM method now populates that contract locally and passes the
local validation, posterior predictive, sparse-pathology recovery, and
prior/likelihood sensitivity grids
while broader GMFRM/MGMFRM surfaces remain blocked.

The first MGMFRM candidate is even narrower: a confirmatory two-dimensional
candidate with a fixed Q-mask, fixed identity latent correlation, standard-normal
ability scale, positive interpreted Q-masked loadings, and source scale `1.7`.
Its BridgeStan oracle, candidate-chain artifact, recovery-smoke artifact, and
connected sparse-recovery grid do
not support exploratory loadings, free latent correlations, more than two
dimensions, sparse-design claims, or public recovery claims. A local
same-observation baseline-comparison artifact is recorded, but a public MGMFRM
fit path remains blocked until full reproduction artifacts and a public-scope
release decision are complete. A private guarded local fit entrypoint now
populates the same raw-prior/Jacobian policy and internal fit-artifact contract
for the fixed-Q confirmatory candidate; it is not a public MGMFRM fitting API.

```julia
using BayesianMGMFRM
using Random

ratings = (
    examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
    rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
    item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
    score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
)

data = FacetData(ratings; person = :examinee, rater = :rater, item = :item, score = :score)
spec = mfrm_spec(data; thresholds = :partial_credit)
spec_rsm = mfrm_spec(data; thresholds = :rating_scale)
prior = MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)
target = MFRMLogDensity(spec; prior)
initial_params(target)
linear_predictor_values(spec, initial_params(spec))
loglikelihood(spec, initial_params(spec))
logprior(spec, initial_params(spec), prior)
logposterior(spec, initial_params(spec), prior)
prior_predict(spec; prior, ndraws = 100)
prior_ppc = prior_predictive_check(spec; prior, ndraws = 100)
prior_ppc.implication_diagnostics
predictive_check_summary(prior_ppc)
fit_result = cached_fit(spec; cache_path = "cache/pcm_fit.jls", prior,
    backend = :julia, ndraws = 500, warmup = 500, chains = 4, step_size = 0.04, seed = 20260618)
fit_result_rsm = cached_fit(spec_rsm; cache_path = "cache/rsm_fit.jls", prior,
    backend = :julia, ndraws = 500, warmup = 500, chains = 4, step_size = 0.04, seed = 20260619)
fit_result_nuts = cached_fit(spec; cache_path = "cache/pcm_nuts_fit.jls", prior,
    backend = :advancedhmc, ndraws = 500, warmup = 500,
    chains = 4, step_size = 0.04, target_accept = 0.8, max_depth = 10, seed = 20260620)
fit_result_turing = cached_fit(spec; cache_path = "cache/pcm_turing_fit.jls", prior,
    backend = :turing, ndraws = 500, warmup = 500,
    chains = 4, step_size = 0.04, target_accept = 0.8, max_depth = 10, seed = 20260623)

fit_metadata(fit_result)
model_manifest(fit_result)
fit_cache_key(spec; prior, backend = :julia, ndraws = 500, warmup = 500,
    chains = 4, step_size = 0.04, seed = 20260618)
fit_artifact(fit_result; include_draws = true, include_environment = false)
diagnostics(fit_result)
sampler_diagnostics(fit_result)
mcmc_diagnostics(fit_result)
parameter_block_diagnostics(fit_result)
posterior_summary(fit_result)
posterior_summary(fit_result; intervals = (0.66, 0.9, 0.95), rope = 0.1)
pointwise_loglikelihood_matrix(fit_result)
waic(fit_result)
waic_diagnostics(fit_result)
compare_models(:partial_credit => fit_result, :rating_scale => fit_result_rsm)
sensitivity_comparison(:partial_credit => fit_result, :rating_scale => fit_result_rsm;
    axis = :thresholds, baseline = :partial_credit)
predictive_probabilities(fit_result)
expected_scores(fit_result)
predictive_variances(fit_result)
predictive_residuals(fit_result)
calibration_table(fit_result; bins = 5)
calibration_table(fit_result; target = :all, bins = 5)
fit_stats(fit_result; by = :rater)
posterior_predict(fit_result; ndraws = 100)
ppc = posterior_predictive_check(fit_result; ndraws = 100)
predictive_check_summary(ppc)
predictive_check_summary(ppc; include_grouped = true)

truth = initial_params(getdesign(spec); value = 0.0)
simulated = simulate_responses(spec, truth; rng = MersenneTwister(20260621))
sim_spec = mfrm_spec(simulated; thresholds = :partial_credit)
sim_fit = fit(sim_spec; prior, backend = :julia, ndraws = 100,
    warmup = 100, chains = 2, step_size = 0.04, seed = 20260622)
recovery = parameter_recovery(sim_fit, truth)
parameter_recovery_summary(recovery)
parameter_recovery_plot_data(recovery)
calibration_plot_data(calibration_table(fit_result; bins = 5))
predictive_check_plot_data(predictive_check_summary(ppc))
```

The random-walk sampler is intended for small validation examples and API
stabilization. The AdvancedHMC/NUTS and Turing/NUTS backends are
gradient-based sampler paths for the minimal design; they are not yet broad
GMFRM/MGMFRM fitting backends. The package does not yet expose Stan/CmdStan
sampling, PSIS-smoothed or exact LOO refits, grouped cross-validation, or
refit-managed model-comparison workflows. [`kfold`](@ref) and
[`compare_kfold`](@ref) summarize supplied heldout refit log-likelihood
matrices, but they do not construct folds or refit models.
`MFRMLogDensity` exposes the
same minimal posterior through the `LogDensityProblems.jl` protocol for
external sampler and automatic differentiation experiments. AdvancedHMC uses a
shared gradient adapter: `ad_backend = :ForwardDiff` is the default,
`:ReverseDiff` can be selected when that package is available in the active
environment, and `:analytic` uses a target-provided
`LogDensityProblems.logdensity_and_gradient` method for targets that implement
one. Turing wraps the same target with a flat vector parameter and
`Turing.@addlogprob!`; that backend currently accepts only
`ad_backend = :ForwardDiff`.
`linear_predictor_values` exposes the row-by-category `eta`, log-denominator,
and category log-probability values for the same minimal likelihood used by
`pointwise_loglikelihood`. `loglikelihood`, `logprior`, and `logposterior`
expose the corresponding scalar target components for inspection and
validation. `fit_metadata` returns report-ready data dimensions, draw
dimensions, model family, dimensions, estimation status, backend, sampler, and
prior scales for a fitted object.
`model_manifest` records the data/spec/design/fit provenance contract, including
validation status, deterministic parameter blocks, constraint tables,
prior-block declarations, prior scales, and the compact diagnostic summary.
`fit_artifact` extends that manifest into a cached-fit artifact with sampler
controls, RNG seed metadata, posterior summaries, selected diagnostic
thresholds, optional draws, optional environment/package metadata, a stable
[`artifact_content_hash`](@ref), and an embedded [`fit_archive_manifest`](@ref)
for long-term export checks.
`cached_fit` is the RDS-like recomputation guard: it serializes the fitted
object with Julia's standard `Serialization` format and only reuses the file
when [`fit_cache_key`](@ref) still matches the current data/spec/design, prior,
sampler controls, seed, Julia version, and initialization hash. This is intended
for same-environment analysis caches. Automatic cache keys require an integer
`seed`; use `fit` plus manual [`save_fit_cache`](@ref) for unseeded exploratory
fits. Saved cache records store the artifact content hash and archive manifest;
use manifests and exported tables for long-term, cross-version archival records.
`diagnostics` combines chain-level sampler summaries, parameter-level R-hat/ESS
rows, and parameter-block pass/fail rows into a single machine-readable surface
with AdvancedHMC/NUTS fields such as divergent-transition counts,
max-tree-depth hits, and E-BFMI when available.
`sampler_diagnostics` returns chain-level draw counts, acceptance rates, and
log-posterior summaries.
`mcmc_diagnostics` returns classical split R-hat and autocorrelation-based ESS
when a fit has at least two chains, and marks row-level `:mcmc_warning` flags
when R-hat or ESS fails the supplied thresholds. `posterior_summary` returns
mean, standard deviation, median, the requested lower/upper interval, central
credible-interval rows, probability of direction relative to a reference value,
and optional ROPE/practical-equivalence probabilities. `parameter_block_diagnostics`
aggregates R-hat/ESS rows for person, rater, item, and threshold blocks. The current prior and
posterior predictive checks return compact observed-vs-replicated summaries for
overall mean score, category proportions, person-level mean scores, rater-level
mean scores, item-level mean scores, and optional facet mean scores;
predictive-check objects also carry grouped DFF-cell and observed
sparse-design-block summaries for report expansion with
`predictive_check_summary(...; include_grouped = true)`. Prior predictive
checks also return implication diagnostics for category
nonuse/sparsity and broad facet mean-score ranges before fitting.
`predictive_check_summary` turns those checks into rows with replicated
intervals and tail probabilities.
`simulate_responses` generates one simulated response dataset from known
identified parameters under the current fit-supported MFRM/RSM/PCM likelihood.
Use `parameter_recovery` and `parameter_recovery_summary` to inspect posterior
bias, absolute error, RMSE, interval coverage, interval width, and block-level
recovery. `parameter_recovery_plot_data`, `calibration_plot_data`, and
`predictive_check_plot_data` return plotting-ready rows without depending on a
specific plotting library.
`waic` computes WAIC from posterior pointwise log-likelihood draws, and
`waic_diagnostics` reports the observation-level WAIC components and flags
high-variance rows. `compare_models` ranks fitted models by WAIC-derived
expected log predictive density, including an Akaike-style `relative_weight`
for same-data candidate models. Because the comparison uses pointwise
differences, `compare_models` requires the same observation data in the same
row order, ordinal category levels, latent dimensionality, and fixed Q-matrix
contract; returned rows include the checked model family, thresholds,
discrimination mode, dimensionality, Q-matrix, and data signature.
`kfold` summarizes supplied heldout log-likelihood matrices from fold-specific
refits, and `compare_kfold` ranks those K-fold summaries when the heldout
observation order and fold assignment order match across models. These helpers
record K-fold evidence but do not create folds or refit models.
`sensitivity_comparison` wraps those rows with a declared sensitivity axis,
per-model axis values, a baseline model, and baseline-relative ELPD and
information-criterion differences for report tables.
Observation-level
predictive probabilities, expected scores,
variances, and residuals are exposed as the substrate for calibration,
infit/outfit, and further model-comparison helpers. `calibration_table` bins
observations by posterior predictive expected score, or by a selected category
probability, and returns observed-vs-predicted summaries with posterior
intervals. It can also return one block per ordinal score category with
`category = :all`, or expected-score and all ordinal category rows together
with `target = :all`. `fit_stats` currently returns posterior summaries of infit and
outfit mean-square statistics by facet level. `fair_average_summary` returns
person-, rater-, or item-level fair-average expected-score intervals using a
balanced reference grid; `residual_summary` returns observation- or facet-level
expected-score and residual intervals with screening caveats for sparse groups
and nonzero residual intervals. The `backend` keyword is explicit
so additional engines can be added without changing the fitted-object shape.
