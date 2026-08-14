# BayesianMGMFRM.jl

[![CI](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml)

`BayesianMGMFRM.jl` provides conservative Bayesian workflows for many-facet
Rasch measurement in Julia. It validates long-format rating designs, constructs
identified MFRM/RSM/PCM models, fits them with Bayesian samplers, and produces
diagnostic and reporting tables.

The package deliberately distinguishes supported models from experimental
ones. A successful experimental fit is evidence about that exact configuration;
it is not evidence for broader GMFRM or MGMFRM support.

## Installation

Install the registered release from Julia General:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

To test unreleased development code, install an explicit Git revision:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl", rev = "main")
```

Pin a commit or tag instead of `main` for reproducible analyses.

## Model Support

| Model surface | Status | Entry point |
|:--|:--|:--|
| MFRM with rating-scale or partial-credit steps | Supported | `mfrm_spec`, `getdesign`, `fit` |
| Scalar GMFRM: item discrimination × rater consistency | Experimental | `BayesianMGMFRM.Experimental.fit(spec)` |
| Fixed-Q confirmatory MGMFRM | Experimental | `BayesianMGMFRM.Experimental.fit(spec)` |
| Broader discrimination structures | Not supported | Specification review only where documented |
| Exploratory multidimensional loadings or free latent correlations | Not supported | No fitting API |
| Fitted DFF effects | Not supported | Screening and design diagnostics only |
| Testlet, response-cluster, or rater-halo effects | Not supported | Metadata checks, report-only residual summaries, and simulation/protocol validation only |

The experimental GMFRM configuration is one-dimensional and estimates positive
item/task discrimination multiplied by positive rater consistency. Its
partial-credit step vector is rater-specific and shared across items and
persons on the direct parameter scale. It does not accept anchors or fitted DFF
terms.
The experimental MGMFRM configuration requires at least two dimensions, a
fixed confirmatory Q-matrix, partial-credit steps, identity latent correlation,
no anchors, and no fitted DFF terms.

Its conditional ability term is the Uto (2021) additive weighted sum across
active dimensions; it contains no latent-ability integral. A simple fixed Q
represents between-item multidimensionality, while fixed cross-loaded rows
represent within-item structure and a Q containing both is mixed. The source
paper labels the model non-compensatory, while its predictor is an additive
weighted sum. The documentation keeps those facts separate, and
`model_family_contract(spec)` makes the distinction machine-readable. The
package does not implement an alternative conjunctive/product/minimum response
rule.
Generalized fitting is GPCM-form. This fixed-Q branch is a restricted candidate,
not Uto's unrestricted item-dimension loading surface. Step vectors belong only
to the declared threshold owner: the rater for guarded GMFRM and the item for
guarded MGMFRM. Adding arbitrary facets does not automatically add facet-
specific steps. The fixed-Q stress generator accepts odd item counts: pure
items are allocated across the two dimensions with a count difference of one;
equal item counts per dimension are not treated as an identification condition.

## Quick Start

```julia
using BayesianMGMFRM

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
)

validation = validate_design(data)
validation.passed || error(validation)

# Sampler-free category-gap and boundary-response audit
response_patterns = ordinal_response_pattern_audit(data)

spec = mfrm_spec(data; thresholds = :partial_credit,
    validation_report = validation)
design = getdesign(spec)

fit_result = fit(design;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)

diagnostics(fit_result; view = :public)
posterior_summary(fit_result)
```

Small sampler settings are useful for smoke tests only. Substantive analyses
should predeclare sampler controls, inspect convergence and HMC diagnostics,
and repeat important conclusions under defensible prior and model choices.
An unused interior score category, an all-maximum person, or a constant-score
rater is warning-level stress evidence rather than an automatic fit failure;
inspect `response_patterns` and repeat those cases under predeclared priors.
One category across the entire dataset remains a pre-fit error.

The guarded fixed-Q MGMFRM validation program also provides a bounded MCMC-free
stress preflight:

```julia
stress = mgmfrm_response_stress_preflight()
stress.summary
```

It retains every planned attempt and typed generation failure. Passing this
preflight establishes only that the nine default dense/sparse category-gap and
boundary-pattern cases can be generated and structurally checked; repeated-fit
recovery evidence remains unrun.

Fit wiring can be checked separately with one explicitly selected case:

```julia
one_case = mgmfrm_response_stress_plan(
    design_strata = (:connected_sparse_systematic_link,),
    response_patterns = (:regular_all_categories,),
)
smoke = mgmfrm_response_stress_fit_attempts(one_case)
smoke.summary
```

The default resource bound admits one fit attempt and uses one chain with four
warmup and four retained draws. It preserves generation, pre-fit, fit, and
diagnostic failures, but deliberately does not assess convergence, recovery,
backend agreement, prior sensitivity, or scientific validity. The analysis
profile remains blocked until its protocol and thresholds are frozen.

The remaining boundary can be inspected without starting an analysis:

```julia
execution_design = mgmfrm_validation_execution_design_contract()
analysis_contract = mgmfrm_validation_analysis_contract()
primary_grid_candidates = mgmfrm_validation_primary_grid_candidates()
primary_candidate = simulate_mgmfrm_validation_primary_candidate(
    first(primary_grid_candidates.cells),
)
# Explicit and heavier: materializes all 16 candidate datasets.
primary_grid_preflight = mgmfrm_validation_primary_grid_preflight(
    primary_grid_candidates,
)
primary_resource_plan = mgmfrm_validation_primary_resource_plan()
# Explicit gradient measurement, one cell at a time:
primary_resource_probe = mgmfrm_validation_resource_probe(
    first(primary_resource_plan.rows),
)
resource_probe_plan = mgmfrm_validation_resource_probe()
short_nuts_plan = mgmfrm_validation_short_nuts_resource_probe()
scaled_resource_plan = mgmfrm_validation_scaled_resource_plan()
isolated_resource_plan = mgmfrm_validation_isolated_resource_probe()

execution_design.heldout
execution_design.retry
execution_design.sensitivity
analysis_contract.fixed_components
analysis_contract.open_decisions
analysis_contract.readiness
```

This draft fixes the four-chain sampler, computational gate, estimands,
interval and scale policies, prior regimes, backend subset, seeds, terminal
statuses, all-attempt denominator, five-fold conditional observation holdout,
non-overwriting remediation, and 24 exact sensitivity role-cells. New-person,
new-item, and new-rater prediction are not claimed. Execution remains blocked
while the final primary grid, replication count, resource caps, and
independently reviewed scientific thresholds are unresolved. These contracts
use documented package APIs and explicit semantic options. Candidate generation
and preflight run no MCMC and do not authorize evaluation.

`primary_grid_candidates` enumerates 16 non-executing source-anchored cells:
two designs crossed with 50/100 persons, 5/15 items, and 5/15 raters. Expected
observations range from 500 to 22,500. Nine cells exceed the current 2,000-
observation short-NUTS bound. A public four-category known-truth generator and
MCMC-free structural preflight are available, but resource coverage, final
cell selection, and evaluation replications remain unresolved. This is not yet
the frozen evaluation grid.

`primary_resource_plan` selects four ordered 4-category cells with 500, 1,250,
3,750, and 7,500 observations for explicit, one-cell-at-a-time gradient
profiling. It does not cover every primary axis and does not progress
automatically. The current short-NUTS runner remains tied to the five-category
stress workflow and rejects primary-grid rows, so a primary short-NUTS adapter
is required before the resource envelope can be frozen.

The first resource-planning surface is also MCMC-free by default. Calling
`mgmfrm_validation_resource_probe()` only returns the bounded dense/sparse
plan. Set `execute_measurement = true` explicitly to measure local generation,
ForwardDiff gradient time, allocation, and free memory. Before generation, the
explicit path applies a 2 GiB free-memory screen with a non-lowerable 1 GiB
floor; a rejection leaves every planned cell unstarted. This screen is not a
memory reservation or a guarantee that a later measurement will complete.
Measured values may guide the cells and batch size for a later bounded
short-NUTS probe, but they are not convergence, recovery, backend, or
performance evidence and are not extrapolated into a full-fit runtime.

`mgmfrm_validation_short_nuts_resource_probe()` similarly plans one connected-
sparse AdvancedHMC cell without executing it. An explicit
`execute_measurement = true` request starts its 25-warmup/25-draw single chain
only after the workload check and a 2 GiB free-memory preflight pass. The
minimum cannot be lowered below 1 GiB. A failed memory preflight starts neither
generation nor MCMC. Even a completed probe is short-chain operability metadata
only; convergence, peak memory, and full-analysis runtime remain unassessed.
The validation work order executes this primitive through the isolated wrapper
below, rather than running the same cell once directly and once in a worker.

After the isolated default sparse short-NUTS receipt succeeds in a suitable
environment,
`mgmfrm_validation_scaled_resource_plan()` provides four ordered cells with
144, 600, 600, and 2,000 observations. Pass exactly one cell identifier at a
time to the isolated probe; automatic progression is prohibited.
`Sys.maxrss()` is recorded as process-lifetime maxRSS before and after a reused-
process run, not as interval-attributable peak memory. For stronger worker-
level attribution,
`mgmfrm_validation_isolated_resource_probe()` can launch exactly one selected
cell in a dedicated Julia process. It is inert by default, requires explicit
execution, repeats the memory preflight in both parent and child, and enforces
a wall-time limit. The worker uses one Julia thread. Its peak RSS includes
Julia startup, package loading, compilation, generation, and diagnostics as
well as sampling; it is not sampler-only memory. The receipt records
Julia/OS/architecture/thread and basic memory context. Completed or rejected
invocations can be passed to
`mgmfrm_validation_isolated_resource_review()` for a threshold-free table of
both memory preflights, elapsed time, child status, and worker peak RSS. The
review never launches the next cell or freezes a resource policy.

Stable MFRM/RSM/PCM designs also support `backend = :cmdstan`. CmdStan is an
optional external runtime, discovered with `cmdstan_backend_check()`; it is not
required to load the package or use Julia backends. Both guarded generalized
families also support
`BayesianMGMFRM.Experimental.fit(spec; backend = :cmdstan)` with the same
raw-coordinate priors and identification transforms as their Julia targets.
The MGMFRM route remains limited to the fixed-Q, identity-correlation
confirmatory contract. `cached_fit` is not yet connected to CmdStan.

## Main Workflow

1. Create `FacetData` from long-format ratings.
2. Run `validate_design` and inspect coverage, connectedness, category use,
   anchors, and optional grouping fields.
3. Create an `mfrm_spec` and inspect `getdesign`, `constraint_table`, and
   `model_manifest` before fitting.
4. Fit the supported model with `fit` or use `cached_fit` when the cache
   identity is part of the reproducibility plan.
5. Review `sampler_diagnostics`, `mcmc_diagnostics`,
   `parameter_block_diagnostics`, posterior predictive checks, calibration,
   and sensitivity results.
6. Export `fit_report(fit; view = :public)` for a portable reader-facing
   structured report, or use a human-readable Markdown summary.

`fit_report` keeps model exposure (`status`) separate from report-generation
health (`report_status`). Inspect `fit_report_health(report)` before treating a
report as complete. Evidence and release exports should use
`require_complete = true`; exploratory workflows may retain the default
captured error section for diagnosis.

`mcmc_diagnostics` uses rank-normalized split R-hat, bulk ESS, and tail ESS as
its primary convergence fields. Classical `rhat` and `ess` remain available
for compatibility only. Odd-draw rank/fold/tail operation order and ESS lag
handling follow Stan/posterior semantics. Guarded generalized fits gate both
raw unconstrained and direct constrained parameter rows, and their cache
identity includes a versioned diagnostic contract. A direct coordinate fixed
by a transform with zero raw dimension remains visible with `diagnostic_status`
and `flag` equal to
`:structurally_fixed` and `quality_gate_applicable = false`; it is excluded
from diagnostic extrema and failure counts. A reconstructed direct coordinate
that varies with free raw coordinates remains part of the gate.

Sampler summaries retain the minimum available `e_bfmi` value for
compatibility and also report `n_e_bfmi_expected`, `n_e_bfmi_available`,
`n_e_bfmi_unavailable`, and `e_bfmi_complete`. The quality gate applies the
E-BFMI threshold only when every chain contributes a finite value; a missing or
non-finite energy value within a chain makes that chain unavailable. Diagnostic
wrapper schemas stay at version 1. Their migration boundary is the row-level
`diagnostic_contract`:
rows without `rank_normalized_rhat_bulk_tail_ess_v1` are pre-modern records and
must not be reinterpreted as modern diagnostics. The primary `flag` aliases
`rank_normalized_flag`; `classical_compatibility_flag` reports the legacy check.
Publication-grade MCMC gate rows fail closed when that contract identifier is
missing or different.

Useful reporting functions include:

- `posterior_summary`, `fair_average_summary`, and
  `separation_reliability_summary`;
- `category_functioning_summary` for observed and posterior-predictive category
  use plus RSM/PCM step uncertainty, and `rater_homogeneity_summary` for
  draw-wise severity contrasts with optional ROPEs and separately labelled
  shared-unit overlap versus model-identification support;
- `rater_diagnostics`, `residual_summary`, `fit_stats`, and `wright_map_data`;
- `predictive_standardized_residuals`, the provisional
  `local_dependence_contract`, and the report-only `local_dependence_summary`
  for clustered-response design and residual-association work, including
  selected-pair, shared-unit, pair-by-draw, and predictive-cell resource
  checks;
- `local_dependence_simulation_grid` and `simulate_local_dependence` for the
  22-scenario LD1a known-truth generator and design validation. Its ordinal
  response kernel is coded independently of the fitted likelihood, and its
  zero/near-zero/small/moderate/large magnitudes are study-local simulation
  settings rather than universal diagnostic cutoffs. Separate scenarios stress
  ability-confounded order and ability-informed assignment;
- `local_dependence_calibration_contract`,
  `local_dependence_calibration_row`, and
  `local_dependence_calibration_summary` for the MCMC-free LD1b0 protocol and
  scorer validation. They preserve planned, failed, rejected, unsupported, and
  completed replication counts; keep pooled pair fractions descriptive; and
  attach Wilson intervals only to replication-level binary rates;
- `local_dependence_calibration_pilot_contract` and
  `local_dependence_calibration_pilot_check` for the MCMC-free LD1b1 pilot
  execution-protocol check. The frozen plan contains 30 replications for each
  of 22 scenarios (`30 × 22 = 660`): 540 eligible fitting jobs and 120 planned
  structural rejections. It does not execute those jobs;
- `prior_predictive_check`, `posterior_predictive_check`, and
  `calibration_table`;
- `waic`, `loo`, `psis_loo`, and K-fold helpers with an explicitly stated
  prediction target;
- `fit_report`, `fit_report_health`, `fit_report_public`,
  `fit_report_markdown`, and report-bundle exporters. The full version-1 report
  remains available for compatibility; use the public view for material shared
  with report readers and `require_complete = true` for evidence exports.

`facets_report` (also available as `facets_compatibility_stats`) returns an
explicitly approximate, unit-weighted posterior-mean plugin table for supported
MFRM/RSM/PCM fits. It does not claim numerical equivalence with FACETS and is
not available for generalized fits.

For migration, see the [FACETS and ACER ConQuest crosswalk](docs/src/migration-facets-conquest.md).
`anchor_refit_plan` checks candidate anchor provenance and the proposed affine
hard-anchor strategy, but numerical anchor-constrained refitting is not yet an
implemented fitting path.

The package can also prepare manual-syntax FACETS or ConQuest bridge bundles on
a Mac with `facets_bridge_bundle` or `conquest_bridge_bundle`, save them with a
SHA-256 input manifest, and verify the returned directory after an operator
runs FACETS with the included Windows launcher or ConQuest with the included
Windows or macOS launcher on an authorized host. Version 1 is unanchored and
limited to the one-dimensional, unit-weighted additive MFRM/RSM/PCM overlap;
unsupported interactions, generalized discrimination, and anchors fail closed.
Category-universe checks require both scale endpoints globally for FACETS,
within each FACETS PCM item, and within each observed ConQuest rater--item
generalized item so the external response denominator cannot silently narrow.
The returned `host_preflight` values support an out-of-band host-side hash
comparison of the transferred verifier and runner; the transfer-contained
launcher is not itself a trust anchor. A version-specific macOS execution
fixture now records successful ConQuest 5.47.5 demonstration-build RSM and PCM
known-truth runs, including constraint reconstruction and recovery checks. It
is not independent replication or product equivalence.
`load_conquest_semantic_parameters` now provides a fail-closed semantic layer
for the exact ConQuest 5.47.5, three-category RSM/PCM boundary. It requires the
complete hash-bound bundle, matches it back to the supplied specification, and
jointly validates identifier/category maps, parameter comments, and the design
matrix before reconstructing ConQuest's sum-to-zero rater, item, and step
values. It deliberately does not align those values to the package's
first-reference gauge. A return receipt binds a raw-file snapshot to hashes and
records reported completion, but neither the receipt nor the semantic layer
independently proves execution, convergence, numerical agreement, or
equivalence with either product. See the migration guide for the complete host
sequence and the remaining gauge-alignment and anchored second-stage work.
The default identifier map still contains unsalted deterministic hashes of
canonical label representations. That is pseudonymization, not anonymization;
guessable labels can be matched and equal labels remain linkable across bundles.

LD1a provides known-truth simulation and structural checks, LD1b0 validates the
calibration scorer, and LD1b1 freezes a 30-replication pilot plan for each of 22
scenarios (`30 × 22 = 660` planned jobs). The plan accepts only the supported
MFRM `ForwardDiff` route and does not execute any of those jobs. No official
pilot result is included in this release.

These planning and validation functions provide no repeated-calibration,
power, diagnostic-decision, or mechanism-identification evidence. Testlet,
response-cluster, halo, rater-by-task, multidimensional, and temporal effects
remain unsupported for fitting.

## Experimental Fixed-Q MGMFRM

```julia
q_matrix = Bool[1 0; 0 1]

mgmfrm_spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix,
    anchors = [],
)

mgmfrm_fit = BayesianMGMFRM.Experimental.fit(mgmfrm_spec;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260718,
)
```

This path is confirmatory: the Q-matrix is fixed, dimension labels and gauge
choices must be interpreted explicitly, and exploratory loading claims are out
of scope. The `BayesianMGMFRM.Experimental` namespace deliberately separates
this provisional surface from the stable MFRM workflow. The older
`fit(spec; experimental = true)` spelling remains available as a compatibility
path, but new experimental work should use the namespace.

Run the small end-to-end execution example with:

```bash
julia --project=. examples/guarded_mgmfrm.jl
```

The example uses two draws and one chain to keep the execution check small;
those controls are not suitable for substantive inference.

## Documentation

- [Data validation](docs/src/data-validation.md)
- [Model equations](docs/src/model-equations.md)
- [Bayesian workflow](docs/src/bayesian-workflow.md)
- [Bayesian fitting](docs/src/fitting.md)
- [Experimental generalized models](docs/src/experimental.md)
- [Examples](docs/src/examples.md)
- [FACETS and ConQuest migration](docs/src/migration-facets-conquest.md)
- [Scope and releases](docs/src/scope.md)
- [API overview](docs/src/api.md)
- [Release notes](NEWS.md)

Runnable examples are available in
[`examples/minimal.jl`](examples/minimal.jl),
[`examples/guarded_gmfrm.jl`](examples/guarded_gmfrm.jl), and
[`examples/guarded_mgmfrm.jl`](examples/guarded_mgmfrm.jl).

## Development

For ordinary repository verification:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --startup-file=no --project=docs docs/build.jl
```

Ordinary `Pkg.test()` checks package behavior and portable artifact contracts.
The long SHA-chained research-evidence archive is intentionally opt-in:

```bash
BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=true \
  julia --project=. -e 'using Pkg; Pkg.test()'
```

Use that mode when reviewing or regenerating frozen study evidence, not as a
prerequisite for installing or fitting the package on another computer.

The complete package suite runs once on Ubuntu with the Julia 1.10.8 minimum
version. On the latest Julia 1.x release, the same ordinary test coverage is
partitioned into named `core`, `fitting`, `local_dependence`, and `generalized`
shards. Running `Pkg.test()` locally still selects all groups; a single group can
be selected with `BAYESIANMGMFRM_TEST_GROUP=<group>`. Focused current-Julia
smokes on macOS and Windows verify package loading, design validation and
compilation, likelihood evaluation, a minimal stable Bayesian fit, and
non-blocking environment metadata collection. Separate jobs build the
documentation and verify examples and release-facing language. The root
`Manifest.toml` and `docs/Manifest.toml` are ignored, machine-local files. The
versioned `Manifest-v1.10.toml` is the tracked lockfile for the Julia 1.10.8
minimum-version lane; Julia 1.10 selects it while the latest-1.x lane resolves
from `Project.toml` compatibility bounds as the forward-drift check. A study
should record the package version and relevant environment information with its
outputs; exact manifest-byte equality is not an ordinary package gate.

## Citation

If you use the package in research, cite the software version and the primary
measurement-model sources appropriate to your analysis. DOI-traced model
sources are listed in the [model-equation documentation](docs/src/model-equations.md).

## License

MIT License. See [LICENSE](LICENSE).
