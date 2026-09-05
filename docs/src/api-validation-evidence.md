# Validation and Evidence API

## User-facing runtime and provenance utilities

These bindings support ordinary package workflows. CmdStan remains an optional
runtime detected when requested; it is not required to install or load the
package.

```@docs
CmdStanError
cmdstan_backend_contract
cmdstan_backend_check
evidence_metadata
simulate_responses
```

## Research-only planning and evidence helpers

The bindings below remain package-root exports for `0.1.x` source
compatibility. They plan, score, or record package research and release
evidence; they are not part of the stable MFRM user workflow, and their
presence is not validation of GMFRM, MGMFRM, or local-dependence claims. New
research orchestration should not expand this root surface.

```@docs
benchmark_result_row
benchmark_summary
comparison_evidence_row
comparison_evidence_summary
falsification_rule_summary
falsification_rules
local_dependence_calibration_contract
local_dependence_calibration_pilot_check
local_dependence_calibration_pilot_contract
local_dependence_calibration_pilot_preflight
local_dependence_calibration_row
local_dependence_calibration_summary
local_dependence_simulation_grid
mgmfrm_decision_stability_score
mgmfrm_predictive_recovery_score
mgmfrm_response_stress_fit_attempts
mgmfrm_response_stress_plan
mgmfrm_response_stress_preflight
mgmfrm_validation_analysis_contract
mgmfrm_validation_execution_design_contract
mgmfrm_validation_isolated_resource_probe
mgmfrm_validation_isolated_resource_review
mgmfrm_validation_primary_grid_candidates
mgmfrm_validation_primary_grid_preflight
mgmfrm_validation_primary_resource_plan
mgmfrm_validation_protocol
mgmfrm_validation_replication_precision
mgmfrm_validation_resource_probe
mgmfrm_validation_scaled_resource_plan
mgmfrm_validation_short_nuts_resource_probe
parameter_recovery
parameter_recovery_plot_data
parameter_recovery_summary
simulate_local_dependence
simulate_mgmfrm_response_stress
simulate_mgmfrm_validation_primary_candidate
simulation_grid
simulation_grid_summary
stan_validation_row
stan_validation_summary
```

`evidence_metadata()` returns portable environment, package, project, and git
metadata without machine-local paths by default. Set `include_paths = true`
only for a private reproduction record whose access controls and retention
policy permit complete local paths and free-form execution notes. Environment
discovery is best-effort: an unavailable optional command or file does not stop
report creation, and `collection.issues` records its stage and short reason.

`cmdstan_backend_check()` validates local runtime/toolchain availability
without compiling a model or running MCMC, and omits local paths by default.
Stable MFRM/RSM/PCM and both guarded generalized configurations now have
executable `backend = :cmdstan` routes. `cmdstan_backend_contract()` keeps this
implementation status separate from the remaining recovery, sparse-design,
cache, parallel-chain, independent-review, and analysis-scale evidence.

`local_dependence_simulation_grid` and `simulate_local_dependence` form the
completed LD1a generator and design-validation surface. The 22 frozen scenarios
use a standalone adjacent-category ordinal kernel rather than the fitted
likelihood implementation and record the complete generating truth. Their
magnitude labels are study-local simulation settings. LD1b pilot execution and
evaluation remain pending, so these functions do not provide diagnostic
cutoffs, enable a decision in `local_dependence_summary`, or identify an
observed-data dependence mechanism.

The LD1b0 calibration-protocol functions validate one-result-per-planning-row
provenance and summarize candidate pair, family, and global reference behavior
across repeated known-truth simulations. They keep failed, rejected, missing,
and unsupported replications visible in the denominator. Pair declarations
within a replication are dependent, so pooled pair fractions are descriptive;
Monte Carlo intervals are attached only to replication-level binary rates.
This protocol-validation surface does not run MCMC, does not yet provide
pairwise power under alternative mechanisms, and does not change the
report-only status of `local_dependence_summary`.
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_check` validate the LD1b1 pilot plan. They
freeze 30 replications for each of 22 scenarios
(`30 × 22 = 660` planned jobs) and validate the study-specific sampler and
diagnostic requirements. The supported route is AdvancedHMC/NUTS with
`ForwardDiff`; unsupported backend, algorithm, or gradient choices are
rejected. These functions validate the plan but do not execute it.

The related diagnostic functions expose rank-normalized split
R-hat, bulk ESS, and tail ESS as the primary diagnostic fields. Classical
`rhat` and `ess` remain compatibility fields. For odd split chains, bulk ranks
exclude the center draw, folding uses the untrimmed pooled median before that
exclusion, and tail ESS uses untrimmed pooled quantiles before splitting. ESS
uses all valid split-chain lags, matching Stan/posterior semantics.
Guarded GMFRM/MGMFRM checks require both raw unconstrained and direct
constrained rows to pass when the rows are quality-gate applicable. A direct
coordinate fixed by a zero-raw-dimension transform remains visible as
`:structurally_fixed` with `quality_gate_applicable = false` and does not enter
extrema or failure counts. A reconstructed coordinate that varies with free raw
coordinates remains gated. Cache identity records the versioned diagnostic
contract.

No official pilot result is included in this release. These APIs therefore provide no
repeated-calibration, power, diagnostic-decision, or mechanism-identification
evidence and do not make clustered effects available for fitting.
