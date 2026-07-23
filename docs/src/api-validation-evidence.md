# Validation and Evidence API

```@docs
simulation_grid
simulation_grid_summary
local_dependence_simulation_grid
simulate_local_dependence
local_dependence_calibration_contract
local_dependence_calibration_row
local_dependence_calibration_summary
local_dependence_calibration_pilot_contract
local_dependence_calibration_pilot_preflight
falsification_rules
falsification_rule_summary
simulate_responses
parameter_recovery
parameter_recovery_plot_data
parameter_recovery_summary
stan_validation_row
stan_validation_summary
comparison_evidence_row
comparison_evidence_summary
benchmark_result_row
benchmark_summary
```

`local_dependence_simulation_grid` and `simulate_local_dependence` form the
completed LD1a generator and design-preflight surface. The 22 frozen scenarios
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
The versioned MCMC-free
`local_dependence_calibration_scorer_preflight.json` artifact checks all 22
planned scenario denominators, materializes the four declared pre-fit
rejections, and leaves the 18 structurally eligible rows unresolved for the
pending pilot-execution and evaluation stages.

`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_preflight` form the LD1b1 pilot execution-
protocol preflight. They fix 30 replications for each of the 22 scenarios
(`30 × 22 = 660`): 540 eligible fitting jobs and 120 planned structural
rejections.
Every eligible scenario provisionally requires at least 27 completed jobs, at
most three categorized failures, and no missing outcome; all 30 outcomes for
each structural-rejection scenario must remain planned rejections. Retry
outcomes are appended and cannot replace an original failure. These operational
bounds are study-local candidates rather than package defaults or established
performance thresholds.

The same study-local resource preflight caps the complete plan at 700 jobs, 600
fits, 500,000 ratings, 2,000,000 probability cells, and 13,000,000 truth cells.
Each generated dataset is capped at 2,500 ratings, 10,000 probability cells,
and 60,000 truth cells.

The planned AdvancedHMC/NUTS run uses four chains, 500 warmup and 500 retained
draws per chain, a target acceptance rate of 0.9, maximum tree depth 10, a
diagonal metric, and analytic differentiation. Diagnostics use 250 distinct
posterior-predictive draws. Candidate quality bounds require rank-normalized
R-hat at most 1.01, bulk and tail ESS of at least 400, no divergences or
maximum-depth hits, and E-BFMI of at least 0.3. The E-BFMI threshold is
evaluated only when every chain supplies a finite value. The summary preserves
the minimum available `e_bfmi` for compatibility and records
`n_e_bfmi_expected`, `n_e_bfmi_available`, `n_e_bfmi_unavailable`, and
`e_bfmi_complete`; a missing or non-finite energy value within a chain makes
that chain unavailable.
Pilot precision provisionally
uses a maximum Wilson half-width of 0.18; the evaluation target is 0.10. The
evaluation size must be selected as either 50 or 100 replications after the
pilot and frozen before evaluation, without a mid-evaluation extension.

The package-level capability behind that gate exposes rank-normalized split
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

LD1b1 authorization pins the exact diagnostic identifier and full dependency
and operation-order record, primary fields, tail probability, minimum chain and
draw requirements, complete-chain E-BFMI coverage, and the SHA-256 digest of
`src/bayesian_fit.jl`. The result, diagnostic, and heldout wrappers remain
version 1: rows without
`diagnostic_contract = rank_normalized_rhat_bulk_tail_ess_v1` are pre-modern
and must not be relabelled. In modern rows, `flag` aliases
`rank_normalized_flag`; `classical_compatibility_flag` is the legacy result.

The MCMC-free `local_dependence_pilot_protocol_preflight.json` artifact checks
this plan but does not execute it. Package sampler diagnostics now provide the
required rank-normalized R-hat and bulk/tail ESS, so the preflight authorizes
the pilot execution protocol. Authorization is not execution or evidence from
completed replications. The pilot remains unrun and the artifact supplies
no repeated-calibration evidence, pairwise power, diagnostic decision, or
mechanism interpretation.

The MCMC-free `local_dependence_pilot_batch_execution_harness.json` dry run
checks all 660 planned rows, comprising 540 eligible fitting jobs and 120
planned pre-fit rejections. Result validation checks both byte integrity and
status-specific semantic consistency: the execution source, job, seeds,
attempt, terminal status, and evidence role must agree. Each role binds one
source artifact by bytes and SHA-256 and records its exact upstream evidence
hashes. The frozen `pilot_contract` and canonical ordering of all 660 job rows
are independently checked by canonical SHA-256. A `pre_fit_rejected` terminal
record requires `generated_data` -> `structural_rejection_audit` ->
`calibration_row`, including simulation and rejection provenance in a row that
conforms to the existing public calibration-row contract. The simulation source
member is checked for response data, table columns, probability cells, truth
and row-truth arrays, structural eligibility, and data/score/design signatures.
Fit evidence must use the structured
`local_dependence_pilot_fit_artifact_export.v1` JSON wrapper containing retained
draws, log posterior values, sampler statistics, sampler controls, and
reproducibility metadata. Its package-native content hash must be verified by
the future pinned canonical executor before JSON projection; the batch runner
separately recomputes the canonical JSON payload hash and verifies the exact
file SHA-256. The JSON projection cannot soundly reconstruct the native typed
hash. Fit, sampler,
local-dependence, and calibration evidence must agree on data, design, fit-
artifact, retained-draw, chain, and iteration provenance. The custom
`local_dependence_pilot_summary_bundle.v1` directly records the draw-selection
and posterior-predictive seeds; the runner compares both with its evidence
payload, the frozen job, and the calibration execution seeds. Draw selection
uses the frozen `sha256_seeded_rank_without_replacement_v1` algorithm, and the
runner recomputes its ordered draw indices from the frozen seed.
The posterior-predictive seed is source-bound, but seed-to-result replay
verification remains
pending the canonical single-job executor and bounded smoke review. For
`diagnostic_failed`, a `sampler_quality_gate` component requires a failed
sampler gate, while a `local_dependence_summary` component requires a passing
sampler gate. Frozen resource counts and sampler-quality conditions are checked
explicitly; symbolic links, hard links, and unmanifested files are rejected.
Aggregate and checkpoint state include the ordered primary-result,
evidence-manifest, and attempt-inventory digests. Primary outcomes remain
nonoverwritable, and remediation remains additive. Resume first rescans the
complete attempt archive as the
source of truth, then verifies and compares the derived checkpoint, and skips
only verified terminal primary records. Capability, execution, archive
assessment, and statistical evidence are reported separately; because the
generated dry run does not scan
an attempt archive, archive integrity is not assessed. Snapshot values are
rechecked against a static inventory, but this does not provide an atomic
completed-attempt seal. The canonical single-job executor, bounded smoke review,
completed-attempt seal, and append-only recovery or retirement path for
interrupted attempts remain required before execution. These consistency
checks do not establish scientific validity. No response data are generated,
no model is fitted, and no MCMC is run; pilot results, calibration or power
estimates, diagnostic decisions, and mechanism interpretations remain
unavailable.
