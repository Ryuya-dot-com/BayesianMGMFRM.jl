# BayesianMGMFRM.jl

BayesianMGMFRM.jl is an early Julia package scaffold for many-facet Rasch
measurement workflows.

The package is under active development. The current public slice focuses on
long-format many-facet rating data, deterministic facet indexing, pre-fit design
validation, and a minimal MFRM specification/design compiler. Bayesian
fitting for the minimal MFRM/RSM/PCM design is now available through a
random-walk example backend, an initial AdvancedHMC/NUTS backend, and a
Turing/NUTS backend.
The spec object can now represent MFRM, planned GMFRM, and planned MGMFRM
configurations for manifest and constraint review, while generalized
discrimination terms, group/DFF model effects, and MGMFRM likelihoods remain
specified-only rather than fit-ready. Test-suite validation now includes
Julia/BridgeStan scalar fixtures and internal hand-computed source-aligned
GMFRM/MGMFRM preview fixtures, including raw-coordinate transforms for their
source identification restrictions and fixture-only raw-coordinate
log-likelihood / `LogDensityProblems.jl` target checks. The internal scalar
GMFRM promotion candidate also has local BridgeStan-oracle, candidate-chain,
recovery-smoke, stress-chain, baseline-comparison, and baseline/calibration-grid
evidence plus local interval/decision, sparse-design, and guarded-exposure
review artifacts plus WAIC influence, raw importance-sampling LOO/Pareto-k,
K-fold refit, guarded fit API dry-run, and guarded fit method-wiring reviews.
A narrow `fit(spec; experimental = true)` scalar GMFRM path is now wired for
local validation, and its experimental fit validation, posterior predictive,
sparse-pathology recovery, and prior/likelihood sensitivity grids are
recorded, a compact local real-data case study is recorded, and a local
claim-level recovery/reproduction archive manifest is recorded. A local
broader experimental exposure decision review now keeps the scalar GMFRM path
guarded-only. The full-paper reproduction archive records the local
regeneration commands, fixture hashes, code/documentation hashes, and local
verification commands without any publication or registration action.
A local DFF estimand/validation grid, Gate E manuscript-scale evidence grid,
and local full-paper reproduction archive are recorded; none of these promote
fitted DFF model effects or broader GMFRM/MGMFRM fit surfaces.
MGMFRM work has an internal
confirmatory gauge manifest and
BridgeStan confirmatory-candidate oracle plus a local candidate-chain
diagnostic artifact, recovery-smoke artifact, baseline-comparison artifact, and
connected sparse-recovery grid plus a local guarded fit method-wiring artifact,
local guarded fit validation grid, and local guarded fit API dry-run artifact,
plus a local guarded public exposure review and prediction-target/model-weight
policy. It now has a private guarded local fit entrypoint and artifact surface
for the fixed-Q confirmatory candidate, but not a public fit-ready sampler path.
Its next public blocker is a separate public-scope release decision; its
internal exposure decision remains `keep_internal`, and any publication or
registration step remains manual.

## Installation

Until the package is registered:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl")
```

After General registration:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

## Minimal Example

```julia
using BayesianMGMFRM
using Random

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    group = ["A", "A", "B", "B", "B", "B", "A", "A"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
design = getdesign(spec)

model_ladder()
constraint_table(design)
design.parameter_names
coverage_summary(spec)
coverage_matrix(data; rows = :rater, columns = :person)
rater_overlap(data)
threshold_map_data(design; params = zeros(length(design.parameter_names)))

prior = MFRMPrior()
target = MFRMLogDensity(design; prior)
initial_params(target)
linear_predictor_values(design, initial_params(design))
loglikelihood(design, initial_params(design))
logprior(design, initial_params(design), prior)
logposterior(design, initial_params(design), prior)
prior_ppc = prior_predictive_check(spec; prior, ndraws = 4, rng = MersenneTwister(101))
prior_ppc.implication_diagnostics
cache_path = joinpath("cache", "minimal_fit.jls")
fit_result = cached_fit(spec;
    cache_path,
    prior,
    ndraws = 4,
    warmup = 4,
    chains = 2,
    step_size = 0.1,
    seed = 102,
)
ppc = posterior_predictive_check(fit_result; ndraws = 4, rng = MersenneTwister(103))

predictive_check_summary(prior_ppc)
fit_metadata(fit_result)
sampler_diagnostics(fit_result)
mcmc_diagnostics(fit_result)
parameter_block_diagnostics(fit_result)
diagnostics(fit_result)
fit_cache_key(spec; prior, ndraws = 4, warmup = 4, chains = 2, step_size = 0.1, seed = 102)
fit_artifact(fit_result; include_draws = true, include_environment = false)
posterior_summary(fit_result)
posterior_summary(fit_result; intervals = (0.66, 0.9, 0.95), rope = 0.1)
waic_diagnostics(fit_result)
loo_diagnostics(fit_result)
calibration_table(fit_result; bins = 2)
calibration_table(fit_result; target = :all, bins = 2)
predictive_check_summary(ppc)
predictive_check_summary(ppc; include_grouped = true)

truth = initial_params(design; value = 0.0)
simulated = simulate_responses(design, truth; rng = MersenneTwister(104))
sim_spec = mfrm_spec(simulated; thresholds = :partial_credit)
sim_fit = fit(sim_spec; prior, ndraws = 4, warmup = 4, chains = 2, seed = 105)
recovery = parameter_recovery(sim_fit, truth)
parameter_recovery_summary(recovery)
parameter_recovery_plot_data(recovery)
calibration_plot_data(calibration_table(fit_result; bins = 2))
predictive_check_plot_data(predictive_check_summary(ppc))
```

See [`examples/minimal.jl`](examples/minimal.jl) for the same minimal example as
a script.

See [`docs/`](docs/) for the Documenter source pages covering data validation
and the public API.
See [`ROADMAP.md`](ROADMAP.md) for the critical-reviewer implementation
roadmap separating the current scaffold from planned HMC/GMFRM/MGMFRM work.

## Development Status

Current public API:

- `FacetData`: long-format rating data with stable person/rater/item/category
  indexes and optional metadata such as `group`, `task`, `form`, and `occasion`.
- `validate_design`: pre-fit category, connectedness, singleton, and DFF-cell
  checks, item/category support warnings, plus a rank check for the current
  minimal reference-constrained location design.
- `validation_suggestions`: machine-readable next-step suggestions for
  validation issues, including disconnected designs, sparse DFF cells, skipped
  categories, and weak item/category support.
- `mfrm_spec`: a declarative specification object for the fit-supported
  minimal MFRM/RSM/PCM slice and specified-only GMFRM/MGMFRM configurations.
- `model_ladder`, `constraint_table`, and `identification_declarations`:
  machine-readable scope, constraint, transform, prior-block, hard/soft anchor,
  and gauge declarations separating fit-supported blocks from specified-only
  future blocks.
- `model_equation`: source-traced mathematical contracts for the current MFRM
  slice and the planned GMFRM/MGMFRM targets, including primary-source links,
  required blocks, identification restrictions, and implementation gaps.
- `getdesign`: an inspectable internal design object with deterministic
  parameter-block ordering. The current minimal design fixes the first rater and
  item levels as references and uses sum-to-zero threshold steps. By default it
  rejects specified-only GMFRM/MGMFRM configurations instead of silently fitting
  the wrong likelihood; `getdesign(spec; preview = true)` returns a non-fit-ready
  parameter blueprint for design review.
- `fit_ready_parameter_layout`: deterministic fit-ready parameter names, block
  ranges, raw/constrained candidate blocks, and transform rows for the current
  MFRM/RSM/PCM likelihood and guarded GMFRM/MGMFRM compiler candidates.
- `design_row_table`: observation-level compiler metadata showing which
  identified person, rater, item, source-step, item-discrimination,
  item-dimension-discrimination, and rater-consistency parameters each rating
  row touches. For specified-only GMFRM/MGMFRM specs, use
  `design_row_table(spec; preview = true)` for inspection without enabling
  fitting.
- `linear_predictor_table`: row-by-category compiler metadata for checking
  denominator terms, category-specific location multipliers, source-step paths,
  and source-aligned GMFRM/MGMFRM preview blocks before generalized likelihood
  fitting is enabled.
- `linear_predictor_values`: numeric row-by-category `eta`, log-denominator,
  and category log-probability rows for the fit-supported MFRM/RSM/PCM
  likelihood. Numeric values remain disabled for specified-only GMFRM/MGMFRM
  previews.
- `model_manifest`: serializable provenance metadata for data, specs, designs,
  and fits, including column roles, level maps, validation status, parameter
  blocks, identification declarations, constraint tables, prior-block
  declarations, and fit diagnostics when available.
- `fit`, `MFRMPrior`, `MFRMFit`, `fit_metadata`, and `posterior_summary`:
  initial Bayesian fitting paths for the minimal MFRM/RSM/PCM design using
  `backend = :julia` for small random-walk validation examples or
  `backend = :advancedhmc` for the direct AdvancedHMC/NUTS path, or
  `backend = :turing` for the Turing/NUTS wrapper around the same
  `MFRMLogDensity` target. Posterior summary rows include the legacy
  lower/upper interval columns plus central credible-interval rows,
  probability of direction, and optional ROPE/practical-equivalence
  probabilities.
- `GMFRMFit`: a guarded experimental scalar GMFRM fit result returned only by
  `fit(spec; experimental = true)` for the source-aligned one-dimensional
  rater-discrimination promotion candidate. This path is local validation
  evidence and remains narrower than broad GMFRM/MGMFRM support.
- `fit_artifact`: reproducibility artifacts that combine the model manifest,
  diagnostics, posterior summaries, sampler controls, RNG seed metadata, and
  optional cached draws/environment metadata. Artifacts include a stable
  `artifact_content_hash` value and an embedded `fit_archive_manifest` for
  exported-review checks.
- `cached_fit`, `fit_cache_key`, `save_fit_cache`, and `load_fit_cache`:
  RDS-like serialized fit caches for avoiding recomputation when the
  data/spec/design, prior, sampler controls, seed, Julia version, and
  initialization hash still match. Saved cache records include the artifact
  content hash and archive manifest. Automatic cache keys require an integer
  `seed` so cached draws are tied to a replayable fit request.
- `MFRMLogDensity`, `initial_params`, `linear_predictor_values`,
  `loglikelihood`, `logprior`, and `logposterior`: a
  `LogDensityProblems.jl`-compatible posterior target, row-by-category
  likelihood inspection, and separated likelihood/prior/posterior evaluators
  for external sampler and AD experiments.
- `diagnostics`: a single diagnostic surface combining chain-level sampler rows,
  parameter-level R-hat/ESS rows, parameter-block pass/fail rows, pass/fail
  counts, and HMC/NUTS fields when the selected backend exposes them.
- `sampler_diagnostics`: chain-level draw counts, acceptance rates, and
  log-posterior summaries, including NUTS divergence, tree-depth, step-count,
  step-size, and E-BFMI fields when available.
- `mcmc_diagnostics`: chain-aware R-hat and effective-sample-size summaries for
  fitted objects with two or more chains, with row-level `:mcmc_warning` flags
  when R-hat or ESS fails the supplied thresholds.
- `parameter_block_diagnostics`: block-level summaries of R-hat/ESS diagnostics
  for person, rater, item, and threshold blocks.
- `pointwise_loglikelihood`: pointwise log-likelihood evaluation for the
  minimal identified design, using the same linear-predictor evaluator exposed
  by `linear_predictor_values`.
- `pointwise_loglikelihood_matrix`: draws-by-observations log-likelihood output
  for posterior checks and model-comparison helpers.
- `waic`: widely applicable information criterion summaries from posterior
  pointwise log-likelihood draws.
- `waic_diagnostics`: observation-level WAIC diagnostics with person, rater,
  item, score, and optional facet labels when fitted objects are supplied.
- `loo`: raw importance-sampling leave-one-out summaries with Pareto-k
  screening diagnostics. This path does not perform PSIS smoothing; high
  Pareto-k rows require exact LOO, K-fold, or other model-specific follow-up
  before strong comparison claims.
- `loo_diagnostics`: observation-level LOO diagnostics with person, rater,
  item, score, optional facet labels, raw-importance effective sample sizes,
  and Pareto-k flags when fitted objects are supplied.
- `kfold`: heldout K-fold log predictive density summaries from fold-specific
  refit log-likelihood matrices. This helper records supplied heldout
  evidence; it does not build folds or refit models.
- `compare_models`: WAIC- or raw importance-sampling LOO-based comparison rows,
  including relative weights and model-contract fields, for fitted models that
  share the same observation data, row order, ordinal categories, latent
  dimensions, and fixed Q-matrix contract.
- `compare_kfold`: K-fold comparison rows for `kfold` summaries that share the
  same heldout observation order and fold assignment order.
- `sensitivity_comparison`: report-ready sensitivity rows that wrap
  `compare_models` with a declared axis, per-model axis values, baseline
  labels, and baseline-relative ELPD/information-criterion differences.
- `posterior_predict` and `posterior_predictive_check`: posterior replicated
  score generation plus compact observed-vs-replicated summaries for mean
  scores, category proportions, person means, rater means, item means, and
  optional facet means. Predictive-check objects also carry grouped DFF-cell
  and observed sparse-design-block summaries for report expansion.
- `prior_predict` and `prior_predictive_check`: prior replicated score
  generation for checking whether the declared priors imply plausible score
  distributions before fitting. Prior predictive checks include
  `implication_diagnostics` rows for category nonuse/sparsity and broad facet
  mean-score ranges.
- `simulate_responses`, `parameter_recovery`, and
  `parameter_recovery_summary`: simulation-study helpers for generating one
  dataset from known minimal MFRM/RSM/PCM parameters and checking posterior
  bias, RMSE, interval coverage, and block-level recovery summaries.
- `predictive_check_summary`: report-ready summaries of prior or posterior
  predictive checks with replicated intervals and tail probabilities, including
  person, rater, item, and optional facet mean-score rows, plus DFF-cell and
  sparse-design-block rows when called with `include_grouped = true`.
- `calibration_table`: binned observed-vs-predicted calibration summaries from
  posterior expected scores, one selected category probability, all ordinal
  category probabilities, or the combined `target = :all` report.
- `parameter_recovery_plot_data`, `calibration_plot_data`, and
  `predictive_check_plot_data`: plotting-ready long-form rows for Makie,
  Plots.jl, AlgebraOfGraphics, R/ggplot, Quarto, or CSV workflows without
  adding a plotting dependency.
- `predictive_probabilities`, `expected_scores`, `predictive_variances`, and
  `predictive_residuals`: observation-level posterior predictive quantities for
  calibration tables, residual checks, infit/outfit, and model-comparison
  helpers.
- `fair_average_summary`: posterior fair-average expected-score intervals for
  person, rater, or item reports using a balanced reference grid.
- `separation_reliability_summary`: posterior separation and empirical
  reliability intervals for person, rater, and item measures.
- `residual_summary`: observation- or facet-level posterior expected-score and
  residual summaries with residual-screening caveat flags.
- `fit_stats`: posterior summaries of infit and outfit mean-square statistics
  by facet level.
- `coverage_summary`, `coverage_matrix`, `rater_overlap`, `design_row_table`,
  `linear_predictor_table`, and `threshold_map_data`: fit-independent
  reporting-data helpers for Quarto tables, coverage heat maps, rater-linking
  plots, denominator reviews, and threshold-map prototypes. Use
  `linear_predictor_values` when a parameter vector is available and numeric
  category-score inspection is needed.

Future workflow APIs will continue to use domain-oriented names such as
`simulate_responses`, `parameter_recovery`, and `posterior_summary` rather
than repeatedly prefixing function names with the package name.

Not yet implemented in the public API:

- Stan/CmdStan sampling, PSIS-smoothed LOO, exact LOO refit orchestration, or
  refit-managed model-comparison workflows. The K-fold helpers summarize
  supplied heldout log-likelihood matrices but do not build folds or refit
  models. The AdvancedHMC/NUTS and Turing/NUTS backends are currently limited
  to the minimal MFRM/RSM/PCM design; the guarded experimental scalar GMFRM
  promotion candidate remains on the AdvancedHMC path.
- Broad fitting for the specified-only GMFRM/MGMFRM blocks declared by
  `mfrm_spec`, beyond the guarded scalar GMFRM rater-discrimination path.
- Generalized discrimination, group/DFF model effects, or MGMFRM likelihood
  terms.
- Automated regeneration of external Stan/BridgeStan validation fixtures in CI.
  Current scalar Stan/BridgeStan checks and the internal GMFRM/MGMFRM preview
  fixtures, raw transforms, and scalar GMFRM candidate-chain artifact are
  test-suite validation evidence, not a public fitting API or a general prior
  declaration. The scalar GMFRM recovery-smoke artifact is also internal
  promotion evidence, the scalar GMFRM stress-chain grid is longer local
  sampler evidence, and the scalar GMFRM baseline-comparison artifact is local
  same-observation WAIC evidence against public MFRM/PCM/RSM baselines. The
  scalar GMFRM baseline/calibration grid extends that local evidence across
  three fixed scenarios with expected-score calibration and residual metrics.
  A scalar GMFRM interval/decision grid records direct-parameter interval
  coverage and stable keep-internal decisions across those scenarios. A scalar
  GMFRM sparse-design grid records connected sparse validation warnings,
  full-rank location designs, interval coverage, and stable keep-internal
  decisions. A scalar GMFRM WAIC influence review records flagged pointwise
  high-variance observations and model-rank sensitivity after removing their
  scenario-level union. A scalar GMFRM raw importance-sampling LOO/Pareto-k
  review records high Pareto-k rows and WAIC-vs-LOO rank sensitivity. A scalar
  GMFRM K-fold refit review records heldout log-score comparisons with matched
  training parameter orders. A scalar GMFRM guarded fit API dry-run artifact
  records the proposed `fit(spec; experimental = true)` entrypoint contract
  and is now superseded by method wiring. A scalar GMFRM guarded fit
  method-wiring artifact records that the narrow experimental entrypoint now
  returns `GMFRMFit`, satisfies the
  experimental fit-artifact contract, and rejects unsupported generalized
  options. A scalar GMFRM experimental fit validation grid runs that guarded
  entrypoint across three fixed scenarios, validates artifact shape and finite
  WAIC/LOO inputs, and hands off to posterior predictive review. A scalar GMFRM
  posterior predictive grid records replicated-score
  intervals, category probability checks, and calibration rows from the guarded
  `GMFRMFit` path. A scalar GMFRM sparse-pathology recovery grid reruns the
  guarded fit path on three connected sparse designs and records validation,
  recovery, posterior predictive, and calibration checks. A scalar GMFRM
  prior/likelihood sensitivity grid records local self-normalized
  importance-reweighting checks over raw-coordinate prior profiles and
  likelihood powers. A scalar GMFRM real-data case-study artifact runs the
  guarded path on compact anonymized writing and speaking rater-mediated slices
  with public MFRM baselines. A scalar GMFRM claim-level
  recovery/reproduction archive manifest records fixture hashes, generator
  commands, external source references, and local verification commands. A
  local broader experimental exposure decision review records that the scalar
  GMFRM path remains guarded-only while broader generalized exposure, DFF
  effects, public model-weight claims, and manuscript claims remain blocked;
  local scalar model-weight reporting is restricted to the heldout K-fold
  prediction target; the DFF
  estimand/validation grid is now recorded as validation-only evidence.
  The
  MGMFRM confirmatory BridgeStan oracle is gauge and
  likelihood evidence. The MGMFRM candidate-chain artifact is sampler-shape
  evidence, the MGMFRM recovery-smoke artifact is local smoke evidence, and the
  MGMFRM baseline-comparison artifact is same-observation WAIC evidence against
  public MFRM/PCM/RSM baselines. The MGMFRM sparse-recovery grid records three
  connected sparse fixed-Q scenarios with validation, sampler, WAIC, and
  recovery summaries while keeping MGMFRM fitting internal, not a public MGMFRM
  fit claim. Guarded
  generalized-model caveat docs are present locally, and an internal
  experimental generalized fit-artifact contract records required provenance
  fields for the guarded scalar GMFRM fit path and future generalized
  extensions.

Current registration checklist:

- Package name: `BayesianMGMFRM`
- Repository name for General: `BayesianMGMFRM.jl`
- License: MIT
- Initial version: `0.1.0`
- Tests: `Pkg.test()` passes locally
- Load check: `import BayesianMGMFRM` passes locally
- General registration is pending until the constrained data/spec API is fully
  documented and backed by non-optional validation fixtures. External
  Stan/BridgeStan validation claims are currently limited to the scalar fixture
  checked in `Pkg.test()`.

## Pre-Registration Gate

Before requesting Julia General registration, run:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl
```

The gate checks clean temporary-environment import, `Pkg.test()`, the minimal
example, Documenter build, Aqua package hygiene, project metadata, `git diff
--check`, and public wording/skipped-test scans. CI runs the same gate in a
lighter mode because test and docs jobs already cover `Pkg.test()` and
Documenter.

Manifest policy: package `Manifest.toml` files are intentionally ignored for
General registration. The local gate develops the package in fresh temporary
environments so ignored local manifests do not affect registration checks.
Reproducibility manifests belong with versioned paper or evidence artifacts
rather than the registered package root.

Serialized fit caches from `cached_fit` are for same-environment recomputation
avoidance. For long-term archival or cross-version review, keep the
`model_manifest`, `fit_artifact`, embedded archive manifest, exported summaries,
and source data alongside the cache.

## License

MIT License. See [`LICENSE`](LICENSE).
