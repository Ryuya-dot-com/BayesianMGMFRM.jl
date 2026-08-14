# Validation and Evidence API

```@docs
CmdStanError
simulation_grid
simulation_grid_summary
mgmfrm_response_stress_plan
simulate_mgmfrm_response_stress
mgmfrm_response_stress_preflight
mgmfrm_response_stress_fit_attempts
mgmfrm_validation_execution_design_contract
mgmfrm_validation_analysis_contract
local_dependence_simulation_grid
simulate_local_dependence
local_dependence_calibration_contract
local_dependence_calibration_row
local_dependence_calibration_summary
local_dependence_calibration_pilot_contract
local_dependence_calibration_pilot_check
falsification_rules
falsification_rule_summary
simulate_responses
parameter_recovery
parameter_recovery_plot_data
parameter_recovery_summary
mgmfrm_predictive_recovery_score
mgmfrm_decision_stability_score
stan_validation_row
stan_validation_summary
cmdstan_backend_contract
cmdstan_backend_check
comparison_evidence_row
comparison_evidence_summary
benchmark_result_row
benchmark_summary
evidence_metadata
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
