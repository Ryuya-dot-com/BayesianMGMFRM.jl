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
