# Experimental Generalized Models

`BayesianMGMFRM.Experimental` is the explicit quarantine for generalized
models that can be run for controlled methodological work but are not part of
the stable MFRM contract. Its existence does not promote GMFRM or MGMFRM to a
supported model family.

## Boundary

The namespace currently admits only two surfaces:

- one-dimensional scalar rater-consistency GMFRM with partial-credit steps;
- fixed-Q confirmatory MGMFRM with at least two dimensions, partial-credit
  steps, and fixed identity latent correlation.

Both reject anchors and fitted DFF terms. Broader discrimination, rating-scale
generalized kernels, exploratory or rotated loadings, and free latent
correlations remain outside the fitting boundary.

The compatibility selector `discrimination = :none` on MGMFRM means that no
broader generic discrimination family is selected. The guarded kernel still
estimates positive item-by-dimension discriminations at the active cells of
the fixed Q-matrix.

Inspect the executable contract before building an experimental workflow:

```julia
using BayesianMGMFRM

contract = BayesianMGMFRM.Experimental.surface_contract()
contract.families.mgmfrm
contract.stable_public_gates
contract.external_validated_gates
```

## Workflow

Specifications continue to use the common domain-language constructor. Design
preview, fitting, and cached fitting then cross the explicit namespace boundary:

```julia
spec = mfrm_spec(data;
    family = :mgmfrm,
    dimensions = 2,
    thresholds = :partial_credit,
    discrimination = :none,
    q_matrix = Bool[1 0; 0 1],
)

design = BayesianMGMFRM.Experimental.preview(spec)

fit_result = BayesianMGMFRM.Experimental.fit(spec;
    backend = :advancedhmc,
    ndraws = 500,
    warmup = 500,
    chains = 4,
    seed = 20260722,
)
```

The older `fit(spec; experimental = true)` form remains available during the
migration, but new code should not depend on it. Passing `experimental` inside
the namespace is rejected because the namespace itself is the opt-in.

## Two-dimensional correlation density candidate

The next mathematical slice is isolated one level deeper than the guarded fit.
For an exactly two-dimensional simple-structure Q design with at least two
pure items per dimension and observations on both dimensions for every person,
it appends one raw coordinate `zρ` to the existing parameter vector and sets
`ρ = tanh(zρ)`. Person abilities receive a bivariate normal prior with fixed
marginal scale and correlation `ρ`; `ρ` receives a normalized two-dimensional
LKJ prior including the `tanh` Jacobian. Existing response likelihood terms and
all earlier raw coordinates remain unchanged.

```julia
candidate = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_candidate(spec; lkj_eta = 2)

raw = BayesianMGMFRM.initial_params(candidate; zrho = 0.0)
state = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_state(candidate, raw)
diagnostics = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_diagnostics(
        spec,
        raw;
        finite_difference_coords = (1, 2, length(raw)),
    )

oracle = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_oracle_profile(
        spec,
        raw[1:end-1];
        truth_rho = 0.6,
    )
```

This first dependency-free slice accepts positive integer `lkj_eta` values.
Its name deliberately retains `2d`: independently transforming pairwise
correlations would not ensure a positive-definite matrix in higher dimensions,
where an LKJ-Cholesky parameterization is required. The candidate has no public
MCMC fit entry point, fit type, cache key, or promotion effect. A quarantined
`free_latent_correlation_2d_sampler_smoke` runs a short AdvancedHMC execution
and returns only a NamedTuple; it explicitly does not assess convergence or
recovery. The oracle profile conditions on complete known person abilities, so
it tests the correlation-prior slice but not response-level recovery.

## Known-truth response-recovery layer

The next layer now generates responses from an explicit population correlation
while keeping the population truth separate from the realized finite-sample
ability correlation. It uses distinct deterministic random streams for
abilities, responses, and sampling; a pure two-dimensional Q-matrix; and an
all-person-by-item design with Latin-square rater assignment. Generation fails
closed if the facet graph is disconnected, a category is absent, a direct
constraint is violated, or the response probabilities disagree with either
the candidate's pointwise likelihood or an independently coded, direct-scale
closed-form oracle. That oracle indexes the design blocks and Q-matrix itself;
it does not call the shared predictor, step, or normalization helpers. A
separate shared-kernel replay remains visible so the two checks cannot be
mistaken for one another. Hard quarantine limits cap the generated workload at
100,000 observations and 500,000 probability cells.

```julia
fixture = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_known_truth_fixture(
        rho_truth = 0.6,
        ability_seed = 20260723,
        response_seed = 20260724,
    )

pilot = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_recovery_pilot(
        fixture;
        mode = :diagnostic_smoke,
        chains = 2,
        warmup = 12,
        ndraws = 12,
        seed = 20260725,
    )
```

`mode = :diagnostic_smoke` checks only sampler, chain-layout, diagnostic, and
recovery-table wiring; its short R-hat, ESS, direction, and interval results
are not scientific evidence. `mode = :scientific` enforces at least four
chains, 500 warmup iterations, and 500 retained draws per chain, disperses
default correlation starts across negative and positive values, and evaluates
a fail-closed single-dataset gate. The pilot defaults to a diagonal adaptive
metric and maximum tree depth 10, and records the resolved sampler controls in
its result. Even a passing scientific pilot always
returns `recovery_verified = false`: one simulated dataset cannot establish
bias, interval coverage, or robustness. The next required study is a
preregistered, replicated grid over correlations and seeds that retains failed fits in its
denominator and adds prior, likelihood, identification, and symmetry stress
conditions. Source/test files join the archive inventory only during the
pending deliberate closed-set refresh.

## Replicated-study control plane

The replicated-study control plane is also quarantined. Version 2 explicitly
retires the unexecuted version-1 plan and records its historically reported
plan fingerprint, roster hash, zero scientific executions, and amendment
reason. The predecessor plan artifact was not retained and its hash cannot be
reconstructed from the present repository, so that identity is lineage
metadata rather than independently reproducible evidence.
The canonical plan fixes five population correlations (`-0.6`, `-0.3`, `0.0`,
`0.3`, and `0.6`), five feasibility replications and 100 evaluation
replications per correlation, and a common 300-person, 12-item, four-rater,
four-category design. Ability, response, and sampler seeds occupy new,
separate deterministic namespaces. The complete 525-unit study roster
therefore exists before any feasibility result is observed; feasibility may
authorize its protocol phase, but it cannot resize the evaluation or replace
its seeds. Version 2 is pinned to plan fingerprint
`d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3`
and unit-roster SHA-256
`0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08`;
the constructor fails if either frozen identity changes.

```julia
plan = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_study_plan()
ledger = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_study_ledger(plan)
preflight = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_study_unit_preflight(
        plan,
        first(plan.units).unit_id,
    )
same_preflight = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_study_run_unit(
        plan,
        first(plan.units).unit_id,
        execute_mcmc = false,
    )
probe_plan = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_study_resource_probe(
        plan,
        first(plan.units).unit_id,
    )
dry_run = BayesianMGMFRM.Experimental.
    free_latent_correlation_2d_study_dry_run(plan; max_units = 2)
```

`probe_plan` performs no generation, gradient calculation, or MCMC. Setting
`execute_measurement = true` generates exactly one fixed feasibility fixture
and measures only the initial ForwardDiff log-density-and-gradient path. The
profile checks elapsed time, allocation, GC fraction, free memory, and a
frozen planning projection computed as median initial-gradient time times 32
gradients per transition times 4,000 transitions, while recording source,
Project, version-appropriate Manifest, runtime, and fixture digests. Passing
this initial-gradient profile still does not authorize scientific execution.
The canonical default currently returns
`status = :resource_probe_planned_measurement_not_executed`,
`measurement_completed = false`, and `profile_thresholds_passed = false`;
both operational and scientific authorization remain false, and the frozen
plan retains `resource_probe_completed = false` until a deliberate evidence
update rather than mutating itself after a local measurement.

A local three-repetition measurement on Julia 1.12.5 (2026-07-23, one thread)
returned elapsed times of `0.0446396`, `0.0438387`, and `0.0441816` seconds and
allocations of `85,811,896`, `85,811,848`, and `85,811,848` bytes, with zero
measured GC time. The median gradient time (`0.0441816` seconds), median
allocation (`85,811,848` bytes), and frozen 32-gradients-per-transition
planning projection (`5,655.2448` seconds) passed their respective thresholds.
That projection is neither a measured short-NUTS runtime nor a worst-case
upper bound. Minimum observed free memory was only `2,770,472,960` bytes
(2.580 GiB), below the required 8 GiB, so the artifact status was
`initial_gradient_profile_failed_operational_gate_blocked`; its content
identity was
`78bc652642dc61ff49c109d208fd910bcf15391ce7e8389b1522838392625d2f`.
This is local runtime evidence without an external authenticity or timestamp
anchor. It executed no MCMC, authorized nothing, and does not change the frozen
plan's uncompleted resource-probe field.

The ledger always starts with one row for every planned unit. Missing units and
generation, fit-pipeline, diagnostic, or compact recovery-scoring failures stay
in the fixed denominator; a completed fit that misses the truth remains a completed
fit with an unfavorable scientific outcome. In particular, interval coverage
and sign agreement never determine execution status, and direction is not
applicable at zero correlation. Duplicate, unknown, cross-unit replayed, or
provenance-modified results fail closed. Each future post-generation result
must bind the
exact plan and unit identity, phase, correlation, replication, seeds, immutable
attempt number, generation evidence, fixture signature, sampler controls, and
sample aggregate. It also binds runtime/environment and source receipts plus a
streaming digest of each major numeric sample array and structured telemetry. A
ledger may not combine results from different execution-environment identities
and still pass protocol integrity. Fixture signatures use a canonical
lowercase 16-hex representation. The bounded dry run validates fixture
generation and orchestration only and never invokes MCMC. Neither a successful
dry run nor a feasibility gate sets `recovery_verified` or changes the public
MGMFRM surface.
Evaluation execution additionally requires a frozen feasibility-decision
artifact bound to all 25 primary feasibility-result digests and to an
execution-only decision digest. That decision retains and revalidates the
feasibility execution-environment identity, protocol-violation count, and the
number of evaluation results already recorded at freeze time. The result
ledger records a valid artifact independently of ingestion order. An
evaluation result without that artifact is retained as a permanent protocol
violation and cannot later be upgraded.

Preflight distinguishes protocol authorization from operational
authorization. A feasibility unit can pass the protocol phase while the
legacy `execution_authorized` field remains false. At this checkpoint even an
explicit single-unit call with `execute_mcmc = true` fails closed before data
generation. The compatibility `study_run_unit` entry point is permanently
preflight-only; changing the operational gate cannot connect it to a sampler.
Scientific execution requires a separate future non-public atomic worker after
the short-NUTS, immutable pre-load source snapshot, raw-draw archive, and
reservation-receipt gates pass. Within the preflight record,
`resource_checks.passed` refers only to deterministic workload-count identities
and quarantine caps. Its machine-readable scope is
`static_workload_shape_and_quarantine_caps_only`; it is not a runtime resource
profile and cannot make `operational_execution_authorized` true. The
pre-execution command-line harness can inspect,
validate, and publish MCMC-free dry-run diagnostics through a same-volume,
no-replace hard-link operation. It rejects existing scientific unit or attempt
directories instead of interpreting states that this runner cannot create.
Its `execute-primary` mode is recognized but deliberately exits as blocked
without reserving an attempt. There is no batch executor, retry, resume,
sampler override, or overwrite path.

The first production MCMC-free dry run for the first feasibility unit was
published on 2026-07-23 under the pinned v2 plan by same-volume hard-link
create-new. Its 17,584-byte snapshot is retained as historical lineage after
the public `study_run_unit` path was made permanently preflight-only (file
SHA-256
`4bc95ae2903310abab20d6a47a67e784a61e3bae28562e738323544f436539a0`;
content identity
`de7861f89e805aa17d5fcd4e7faec90eb885ea14223792c6d062002e309aeb8f`).
A new current-source snapshot was then published by the same no-replace
operation.
The current 17,711-byte file has SHA-256
`5911eee0653f4c4f20fd7d74221d9f2044fc15d50331f5189312a83c16ddadca`
and adjacent content identity
`96b724c2501a21225a03b280308de678c99534ab2228b9b0560ba7df35793178`.
Immediate exact-path validation matched the current source snapshot and stable
environment identity; the validation record's content identity is
`c712f75703685dbf3f41872aeba6c085eb43ee86a8a16947f0c058a09d610ddc`.
That identity belongs to the returned validation object, which was not saved
as a separate file. Both dry-run files are workspace-local, outside the
distributed package and any external archive.
The staging directory was empty afterward, and no scientific unit root,
attempt reservation, generated fixture/response data, fit, MCMC, or terminal
state existed. This verifies only current-snapshot self-consistency and the
pre-execution publication path; authenticity, timestamp, and
scientific-execution attestation all remain false.

The harness snapshots current files after the package has loaded. It therefore
labels its source and environment records as current diagnostics, not as an
attestation of the bytes that produced an execution. Its adjacent content
hashes detect accidental corruption but have no external signature or
append-only anchor and are not evidence against a malicious rewrite. A future
scientific worker must execute from a load-before-use immutable source snapshot
and anchor the final archive digest outside the attempt tree.

The compact result hashes the returned sample bundle but does not yet persist
raw draws. Consequently, independent recalculation of R-hat, ESS, and related
diagnostics from an external archive remains a separate execution blocker, not
evidence supplied by the current control plane.

The versioned scorer requires all 100 evaluation units in every correlation
cell to be terminal and at least 95 to contain diagnostically valid and
scientifically scored results. It reports conditional rates alongside joint
success over the fixed planned denominator and unresolved worst-case bounds.
For continuous outcomes it uses exact rational sufficient statistics for the
observed Float64 values, enumerates bounded endpoint completions, and rounds
their full-denominator normal-approximation MCSE guards outward to Float64 by
exact comparison. This removes cancellation and one-ULP-assumption dependence
at the decision boundary. A hard failure requires the whole unresolved interval
to lie beyond the relevant limit; an interval that crosses the decision
boundary is `inconclusive_not_passed`. The same hard-versus-uncertain
distinction applies to zero-correlation false exclusion. Other rules use a
minimum per-cell joint coverage of 0.80, an equal-weight aggregate
one-sided Wilson lower bound of 0.85, corresponding nonzero-correlation
direction rules, and limits for bias, RMSE, and unpaired symmetry. These MCSE
guards remain finite-sample approximations, not distribution-free confidence
bounds. Prior and likelihood sensitivity remain outside this primary
denominator and require separate versioned protocols.

## Stability and promotion

Experimental types, arguments, parameterizations, and report details may
change in a minor release. A successful run demonstrates only that exact
guarded configuration. Stable-public consideration requires source-equation,
identification, gradient, HMC geometry, known-truth recovery, predictive,
sensitivity, reproducibility, and independent-scope-review evidence. The later
external-validated level separately requires comparable external targets,
external-software known-truth comparisons, construct evidence, and real-data
validation. Every status change is an explicit release decision; passing local
tests does not perform it.

The current Float64 numerical audit found no Critical, High, or Medium
stability defect in this slice. Around the stable-residual switch, the largest
observed relative error was below `4sqrt(eps(Float64))`. One Low-severity
representation-floor limitation remains: when both aligned standardized
abilities equal the smallest Float64 subnormal, a one-subnormal gradient can
round to zero after the exact-slice expansion splits it across terms. The same
floor applies to the correlation normalizer at `zrho = ±nextfloat(0.0)`.
This does not affect ordinary HMC-scale values, but it remains an explicit
numerical limitation rather than promotion evidence.

Evidence migration keeps two integrity questions separate. Exact file SHA-256
remains the transport and full-reproduction record. A staged
`scientific_payload_sha256` records only a schema-specific explicit projection
of data/design identities, priors, sampler controls, numerical results, and
decisions. It never removes fields merely because their names contain
`sha256`. Legacy artifacts without that projection can be inventoried, but
their absence does not verify scientific equivalence. A partial pair,
malformed digest, schema-contract violation, or digest mismatch fails closed.
The current validator is repository tooling, not yet a package-level artifact
API: real archive schemas have not yet been migrated, and two artifacts are
not declared scientifically equivalent merely because either contains a
self-consistent digest.

Ordinary CI may report code/document byte changes as `provenance_drift` while
keeping them distinct from verified scientific equivalence. Generated
artifacts, raw data, immutable snapshots, and receipts still require exact
file SHA-256. Release reproduction additionally enables
`BAYESIANMGMFRM_STRICT_ARCHIVE_SHA=true`, which makes code/document drift an
exact-file failure until the archive is deliberately refreshed. Normal CI
runs the portable canonicalization contract first and reports every tolerated
code/document drift path. A manually dispatched CI workflow additionally runs
the strict archive reproduction gate; it remains an intentional release
blocker while the legacy archives await a deliberate, closed-set refresh.

```@docs
BayesianMGMFRM.Experimental
BayesianMGMFRM.Experimental.GMFRMFit
BayesianMGMFRM.Experimental.MGMFRMFit
BayesianMGMFRM.Experimental.surface_contract
BayesianMGMFRM.Experimental.free_latent_correlation_2d_contract
BayesianMGMFRM.Experimental.preview
BayesianMGMFRM.Experimental.free_latent_correlation_2d_candidate
BayesianMGMFRM.Experimental.free_latent_correlation_2d_state
BayesianMGMFRM.Experimental.free_latent_correlation_2d_diagnostics
BayesianMGMFRM.Experimental.free_latent_correlation_2d_sampler_smoke
BayesianMGMFRM.Experimental.free_latent_correlation_2d_oracle_profile
BayesianMGMFRM.Experimental.free_latent_correlation_2d_known_truth_fixture
BayesianMGMFRM.Experimental.free_latent_correlation_2d_recovery_pilot
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_plan
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_ledger
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_apply_result
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_feasibility_decision
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_unit_preflight
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_resource_probe
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_run_unit
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_dry_run
BayesianMGMFRM.Experimental.free_latent_correlation_2d_study_score
BayesianMGMFRM.Experimental.fit
BayesianMGMFRM.Experimental.fit_cache_key
BayesianMGMFRM.Experimental.cached_fit
```
