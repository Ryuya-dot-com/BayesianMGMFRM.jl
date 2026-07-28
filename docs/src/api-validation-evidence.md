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
evidence_metadata
```

`evidence_metadata()` returns portable environment, package, project, and git
metadata without machine-local paths by default. Set `include_paths = true`
only for a private reproduction record whose access controls and retention
policy permit complete local paths and free-form execution notes.

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
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_preflight` form the LD1b1 pilot execution-
protocol preflight. They freeze a 30-replication pilot plan for each of the 22
scenarios and validate its study-specific sampler and diagnostic requirements.
The frozen MFRM route is AdvancedHMC/NUTS with `ForwardDiff`; the capability
record rejects a backend, algorithm, or gradient route that the MFRM target
cannot execute. The batch controller separately requires canonical source/root
binding, a bounded-smoke receipt, completed-attempt seal support, and an
independent interrupted-attempt recovery-control readiness review before it may
create an execution attempt. Completed-attempt seal support now passes its
MCMC-free synthetic boundary tests. Receipt-bearing launched-attempt recovery
and retirement are integrated with the v3 scanner/checkpoint contract,
including its primary-disposition digest, in synthetic tests. The canonical
worker now binds controller-owned execute-path receipts and covers reservation-
before-precommit recovery in local MCMC-free tests. Final source pinning,
dependent identity regeneration, and bounded canonical smoke are complete in
the local worktree. The smoke used canonical row 5 with 4 chains, 500 warmup
and 500 retained iterations per chain in a separate verification-only
namespace; its sealed result contributes zero to the official `0/660` pilot
denominator. The smoke was first rerun after a harness-portability fix changed
the source pin; MCMC-free fixture generation now explicitly disables smoke-
receipt consumption and remains independent of local raw smoke state. A clean
`Pkg.test()` then exposed `Sockets` missing from the test extras. Adding its
test-only target and compatibility bound changed the Project hash, so that
intermediate receipt was archived and the smoke was rerun. The Project change
also made the upstream known-truth Project SHA stale; after regenerating the
known-truth -> scorer -> protocol chain and the Julia 1.10.8 robustness fixture,
that receipt was archived and the final smoke was rerun again.
Independent pinned recovery/readiness review remains incomplete,
so operational readiness is false. These checks do not execute the pilot plan,
and retirement contributes no scientific outcome. The smoke raw archive remains
local pending tracked release-lineage verification.
This places the local `v0.1.2` LD1b integration checklist at `7/9` gates
(`77.8%`); Gate 8 review is the only remaining pre-pilot blocker.
The job-evidence schema requires a `local_dependence_calibration_row.v1` source
member for completed, planned-rejection, generation-failure, fit-failure, and
diagnostic-failure outcomes. A mixed-status public-constructor test preserves
the scientific denominator. Generation failures are now reconstructed from the
frozen public 660-row plan and compared exactly after public-summary validation;
the semantic-validator source is pinned in execution identity. Full semantic
replay of completed diagnostic contents and the other source-backed statuses
passes local tests; tracked release-lineage verification remains pending.

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

The pilot and evaluation remain unrun. These APIs therefore provide no
repeated-calibration, power, diagnostic-decision, or mechanism-identification
evidence and do not make clustered effects available for fitting.
