# Roadmap and Scope

This page summarizes the package roadmap from a skeptical Bayesian measurement
reviewer's point of view. It is intentionally conservative: features move
forward only when their identification, diagnostics, validation, and reporting
contracts are clear.

The progress ledger below is the repository's implementation checklist.

## Current Public Slice

The current package supports:

- long-format rating data with deterministic facet indexing via
  [`FacetData`](@ref);
- pre-fit design validation via [`validate_design`](@ref);
- minimal MFRM/RSM/PCM specification and design inspection via
  [`mfrm_spec`](@ref) and [`getdesign`](@ref);
- specified-only GMFRM/MGMFRM configuration manifests and constraint tables via
  [`model_ladder`](@ref), [`constraint_table`](@ref), and
  [`model_manifest`](@ref);
- observation-level and row-by-category compiler inspection via
  [`design_row_table`](@ref), [`linear_predictor_table`](@ref), and
  [`linear_predictor_values`](@ref);
- small-example Bayesian fitting for the minimal identified design via
  [`fit`](@ref), [`MFRMPrior`](@ref), and [`MFRMFit`](@ref), including
  random-walk Metropolis, an AdvancedHMC/NUTS backend with a shared analytic/AD
  gradient adapter, and a Turing/NUTS wrapper around the same
  `MFRMLogDensity` target;
- guarded experimental generalized fitting via
  `BayesianMGMFRM.Experimental.fit(spec)`, returning [`GMFRMFit`](@ref) for the scalar
  rater-consistency GMFRM candidate, configured with the compatibility keyword
  `discrimination = :rater`, or [`MGMFRMFit`](@ref) for the fixed-Q
  confirmatory MGMFRM candidate with `dimensions >= 2`; the older
  `fit(spec; experimental = true)` spelling is compatibility-only;
- fit metadata, chain summaries, R-hat/ESS summaries, posterior summaries,
  prior/posterior predictive checks, calibration summaries, fair-average
  summaries, separation/reliability summaries, rater diagnostics, Wright-map
  rows, DFF screening rows, infit/outfit, WAIC, raw importance-sampling LOO,
  supplied heldout K-fold summaries, and same-observation or heldout
  comparisons;
- scalar Julia/BridgeStan validation fixtures and internal hand-computed
  source-aligned GMFRM/MGMFRM preview fixtures, including raw-coordinate
  source-constraint transforms, used by the test suite.

The current `backend = :julia` sampler is a random-walk Metropolis path for
small validation examples. `backend = :turing` is a NUTS interface limited to
the current minimal MFRM/RSM/PCM design. `backend = :advancedhmc` also backs the
guarded scalar GMFRM and fixed-Q confirmatory MGMFRM candidates when
`experimental = true`.

## Active Core Integrity Gate

The current implementation sequence pauses broader model expansion until the
same validated model contract is used by compilation, fitting, cache requests,
diagnostics, and reports. The first completed slice provides
[`design_identity`](@ref), stale-object rejection, canonical compiler checks,
streaming SHA-256 fingerprints, and validated deep execution snapshots.

The next slices bind fit contents and cache envelopes, unify compilation/
exposure/evidence status, introduce shared prior and sampler-control contracts,
and then make release-facing reports public by construction. Completion
percentages remain unchanged until both execution and evidence gates pass.

## Not Yet Public API

The following are planned but not yet exposed:

- broader production HMC/NUTS workflows beyond the minimal design and guarded
  generalized candidates;
- fit-ready GMFRM/MGMFRM likelihood compilation beyond the current
  specified-only manifests, row-by-category compiler previews, internal
  hand-computed GMFRM/MGMFRM source fixtures, preview-design raw/direct
  pointwise likelihood matrices, and guarded scalar/fixed-Q experimental paths;
- generalized rater/item discrimination terms beyond the guarded candidates;
- modeled DFF/bias effects;
- multidimensional loading and rotation/gauge machinery beyond the fixed-Q
  identity-correlation candidate;
- broader production exact/refit-management orchestration beyond the
  fit-supported shared-plan comparison slice and explicit guarded generalized
  refit execution;
- publication-grade manuscript rendering and publication/registration workflows
  beyond the current machine-readable reports, multi-report review dossiers,
  and local full-paper archive.

## v0.1.x MGMFRM Release Sequence

The source-grounded staged plan is maintained in
[MGMFRM Research Roadmap](mgmfrm-research-roadmap.md). The sequence records
`v0.1.1` as completed and continues with:

- `v0.1.1`: completed fixed-Q confirmatory MGMFRM refinement by strengthening
  execution, diagnostics, reporting, and validation for the existing guarded
  path.
- next `v0.1.x` checkpoint: complete core identity/cache integrity and the
  minimal-MFRM hard-anchor, report, and repeated sparse/nonrandom gates.
- `v0.1.2` candidate: remain fixed-Q and confirmatory while auditing and
  calibrating the already implemented multidimensional compiler across 2D/3D,
  sparse and misspecified Q, recovery, and performance conditions.
- `v0.1.3`: decide whether free latent correlations are ready for guarded
  exposure.
- `v0.1.4`: design exploratory loading and rotation policy before broad
  exposure.
- `v0.2.0`: establish an intentional stable API boundary only for options that
  passed the vertical-slice gates; it does not automatically claim generic
  MGMFRM completion.

Known-truth external comparisons should occur before a generalized option is
promoted to stable-public whenever an overlapping target exists. Real-data
validation remains subsequent evidence and cannot substitute for failed
source, recovery, identification, or external-overlap gates.

## Parallel Rater-Process and Design Research

A separate research track now records the path beyond a static MGMFRM. Its
first target is not a dynamic fit API. It is a known-truth robustness test of
the existing public MFRM and guarded GMFRM/MGMFRM APIs under rating topology,
ability-dependent assignment, common-linking-response amount and range,
additive versus fixed-total-target-displacement rating budgets, and
latent/outcome dispersion. The fixed-total condition separately reports
planned, observed, and dropped person--item targets. A
separate misspecification track injects a true order effect before fitting the
same static API; a pure row permutation remains only an invariance check. The
generic `simulation_grid.anchor_size`
field is planning metadata and the existing small connected sparse fixtures are
computational smoke evidence; neither substitutes for this paired-replication
study.
Both static tracks set testlet and rater-by-response halo variation to zero, so
passing them does not establish local independence. The separate cluster gate
below reuses their design skeletons with nonzero competing mechanisms.

The versioned `existing_api_design_robustness_plan.json` executes seven
deterministic contract checks. Row-order and categorical-`occasion` invariance,
the rank/linking rejection of an ability-nested no-link design, exact 5% and
10% materialized all-rater common-target counts, assignment-warning retention, and the
separation of parameter anchors from linking responses all pass. Parameter
recovery has not yet been run, so the artifact explicitly blocks a design-
robustness claim. The next grid compares 0%, 2%, 5%, 10%, and 20% linking
targets; these are experimental doses, not a universal recommended anchor
percentage. It reports multiply-scored, common-set, controlled-benchmark, and
rating-event-burden quantities separately; a double-rated baseline is 100%
multiply scored even when it has no special common set.

The corresponding MCMC-free stress-grid artifact now passes for 24
model-design cells and 21 paired datasets. It covers all three current fit
families, additive and fixed-total-target-displacement budgets, achieved
ability/order and assignment/severity diagnostics, outcome dispersion, and six
pure row-permutation contracts. Three additional C2P checks hold the event set,
truth, response uniforms, and scores fixed while moving the 5% common set from
early to distributed positions. Replication seeds resample assignment and
order skeletons, with each paired A/B comparison sharing the same realization;
underresolved smoke designs are kept planned-only. Seeded full-range selection
now guarantees both ability- and item-range ratios of at least 0.75 whenever
the requested common set contains at least two targets. Every requested pilot
or calibration skeleton is checked design-only before score generation, and
the same all-replication check blocks fitting on any failed row. The
50-replication calibration profile passes all 1,050 candidate-family skeleton
rows. This is a reproducible
simulation/likelihood dry run, not repeated recovery evidence. The complete
repeated parameter-recovery and interval-coverage scorer is now implemented
and MCMC-free tested. It aggregates bias, MAE, RMSE, empirical coverage,
posterior-SD calibration, block completeness, and sampler-gate outcomes while
preserving failed and unattempted fits. Pilot and calibration preflights are
regenerated from canonical options before their content-addressed records are
accepted; the reviewed pilot snapshot, statistical policy, and thresholds are
one bound decision record. A passing q95/q99 result is labelled
well-specified-static distributional contract success rather than recovery of
every cell or parameter. External chronology attestation remains a separate
unmet evidence requirement. No repeated MCMC has yet been executed. Predictive and
decision-stability scorers remain missing, so the full gate
stays closed. The next gate is to finish those scorers, run the 30-replication
pilot to freeze study-local thresholds, and then run 50--100 evaluation
replications on untouched seeds.

The next parallel gate addresses local independence and clustered ratings. The
current likelihood is conditionally row-independent; observation residuals,
infit/outfit, grouped PPC, and rater-overlap counts do not by themselves
diagnose pairwise or response-cluster dependence. The initial metadata and
estimand scaffold is complete: `FacetData` records distinct `testlet_id`, `response_id`, and
categorical `occasion` metadata; `testlet_design_audit` checks target-specific
structural support; `predictive_standardized_residuals` returns draw-specific
Pearson residuals; and `local_dependence_contract` separates single-rating
item, within-rater item, and rater-pair targets while fixing matching,
draw-specific support, duplicate, weighting, FDR/FWER, and
conditional/marginal PPC rules. LD0b is also complete:
`local_dependence_summary` returns report-only Q3/adjusted-Q3-style item-pair
and same-response/same-criterion rater-pair summaries, paired predictive tail
fractions, family-by-testlet support graphs, within-family BH values, and one
all-family maximum-statistic reference. It uses distinct posterior draws,
keeps criterion-split responses out of the single-rater family, and exposes
single-response concentration separately from response-criterion counts.
Applicability is evaluated per testlet, and materialized audit rows,
shared-unit work, positive pair-by-draw work, and predictive cells are bounded
before large allocations.
These surfaces provide no calibrated decision label and no fitted cluster
effect. LD1 is now split into two evidence stages. **LD1a is complete:**
`local_dependence_simulation_grid` freezes 22 matched scenarios and
`simulate_local_dependence` uses an adjacent-category ordinal kernel that is
independent of the fitted probability and likelihood implementation. The
generated bundles record component seeds, semantic event-keyed uniforms,
complete
truth, intended and realized category support, exact sequence positions,
design audits, and resource preflights. The scenarios cover null and exact-
zero controls, study-local near-zero through large person-by-testlet effects,
support boundaries, sparse and rejected designs, halo, rater-by-task severity,
omitted multidimensionality, randomized drift, ability-confounded no-drift
order, ability-informed rater assignment, and a testlet-plus-sequence mixture.

**LD1b0 scorer/protocol preflight is complete.**
`local_dependence_calibration_contract`,
`local_dependence_calibration_row`, and
`local_dependence_calibration_summary` freeze the candidate pair,
family-maximum, and all-family-maximum scoring rules; retain planned, failed,
rejected, and unresolved replication denominators; apply Wilson intervals only
to replication-level binary rates; and label pooled pair rates as descriptive.
The MCMC-free `local_dependence_calibration_scorer_preflight.json` artifact
checks this contract over all 22 planned scenarios and the four declared
pre-fit rejection rows.

**LD1b1 pilot execution-protocol preflight is complete.**
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_preflight` freeze 30 replications for each
of the 22 scenarios (`30 × 22 = 660`). The planned rows comprise 540 eligible
fitting jobs and 120 planned structural rejections. The MCMC-free
`local_dependence_pilot_protocol_preflight.json` artifact checks separated
seeds, job identity, resource and failure policies, and preserves an original
failure when a retry is recorded. Its operational candidate bounds are study-
local. Evaluation sizes of 50 and 100 replications remain candidates; one must
be selected and frozen after the pilot and before evaluation.

Authorization pins `rank_normalized_rhat_bulk_tail_ess_v1` and its exact
dependency and operation-order record, primary fields, tail probability,
minimum chain and draw requirements, complete-chain E-BFMI coverage, and the
SHA-256 digest of `src/bayesian_fit.jl`. Authorization verifies the plan only;
it is not execution or calibration evidence.

**LD1b1 MCMC-free batch execution-harness dry run is complete.**
`scripts/generate_local_dependence_pilot_batch_execution_harness.jl` records
the versioned `local_dependence_pilot_batch_execution_harness.json` artifact,
and `scripts/run_local_dependence_calibration_pilot_batch.jl` implements status,
dry-run, and aggregate-only modes and defines fail-closed execute-primary and
execute-retry interfaces;
`--resume` is a checkpoint-verified option. The dry run covers all 660 planned
rows, including 540 eligible fitting jobs and 120 planned pre-fit rejections.
The batch-controller and generator sources are identified. The execution plan
remains incomplete until the canonical single-job executor SHA-256 is
materialized. Terminal records require exact status-specific semantic
evidence, one hashed source artifact per evidence
role, and exact upstream evidence hashes. The frozen `pilot_contract` and
ordered 660 job rows must match their canonical SHA-256 values. Every
`pre_fit_rejected` result retains the exact `generated_data` ->
`structural_rejection_audit` -> `calibration_row` chain, and the calibration
member follows the existing public calibration-row contract. Simulation
members are checked down to their response data, table columns, probability
cells, truth and row-truth arrays, and data/score/design signatures. Fit members
must use the structured `local_dependence_pilot_fit_artifact_export.v1` JSON
wrapper containing retained draws, log posterior values, and sampler statistics.
Its package-native content hash must be verified by the future pinned canonical
executor before JSON projection; the batch runner separately recomputes the
canonical JSON payload hash and verifies the exact file SHA-256. The JSON
projection cannot soundly reconstruct the native typed hash. Resource counts
and fixed sampler controls are checked, while convergence, divergence, depth,
and complete-chain E-BFMI gates are validated individually. Fit,
sampler, local-dependence, and calibration evidence must agree on data, design,
fit-artifact, retained-draw, chain, and iteration provenance. The custom
`local_dependence_pilot_summary_bundle.v1` directly records the draw-selection
and posterior-predictive seeds; the runner compares both with its evidence
payload, the frozen job, and the calibration execution seeds. Draw selection
uses the frozen `sha256_seeded_rank_without_replacement_v1` algorithm, and the
runner recomputes its ordered draw indices from the frozen seed.
The posterior-predictive seed is source-bound, but seed-to-result replay
verification remains
pending the canonical single-job executor and bounded smoke review. A
`diagnostic_failed` record may identify `sampler_quality_gate` only when that
gate failed, or `local_dependence_summary` only after the sampler gate passed.
Symbolic links, hard links, and unmanifested files fail archive integrity.
Aggregate state binds the verified
primary-result, evidence-manifest, and attempt-inventory digests. The controller
refuses to overwrite primary attempts and keeps remediation as additive
records. On resume, it first rescans the complete attempt archive as the source
of truth, then verifies and compares the derived checkpoint, and skips only
verified terminal primary records. Invalid
remediation fails archive integrity without replacing the primary denominator.
The generated dry run does not scan an attempt archive, so integrity is not
assessed. It generates no response data, fits no model, and runs no MCMC;
pilot results, calibration or power estimates, diagnostic decisions, and
mechanism interpretations remain unavailable.

Snapshot and inventory values are rechecked during validation, but this is a
static consistency check rather than an atomic completed-attempt seal.

Before the 660-job pilot begins, the canonical single-job executor must be
materialized against the frozen result schema. Each terminal status must retain
its required hashed data, fit, sampler-diagnostic, local-dependence,
calibration, or structural-rejection records and pass a bounded execution
smoke review without changing seeds, sampler controls, or primary denominators.
A completed-attempt seal and append-only recovery or retirement path for
interrupted attempts must also be reviewed before execution; remediation must
not promote a partial primary into the scientific denominator.

**LD1b pilot execution and evaluation remain pending.** Rank-normalized split
R-hat and bulk/tail ESS are now available from package sampler diagnostics, and
the LD1b1 preflight authorizes the pilot execution protocol. The required
sequence is now single-job executor materialization, bounded smoke,
completed-attempt sealing, and interrupted-attempt recovery review, followed by pilot
execution, review and freeze, then separately seeded evaluation.
Repeated simulation must estimate false declarations, pair/family/global
multiplicity behavior, support-related missingness, and mechanism-confusion
rates before any fitted-effect interpretation or diagnostic decision becomes
available. The preflight runs no fit or MCMC and supplies no calibration
evidence, pairwise power, diagnostic decision, or mechanism interpretation;
`local_dependence_summary` remains report-only. LD1a magnitudes remain study-
local settings rather than universal cutoffs. The ability-confounded no-drift
scenario is the first order/case-mix stress control; parameter anchors, common
linking responses, and controlled benchmark responses remain distinct, and
early/middle/late benchmark placement belongs to the separate static-design
and temporal-identification studies.

The first model candidate is a non-centered scalar person-by-testlet random
effect with one common standard deviation in unidimensional MFRM, restricted
initially to one response per person-by-testlet. Repeated responses require a
separate response/occasion effect. Because person-by-testlet and response are
one-to-one in that slice, the term is labelled only as a shared cluster effect.
The candidate is compared against rater-by-
response halo, rater-by-task severity, omitted multidimensionality, and temporal
sequence mechanisms under known truth. One task per person, one indicator per
person-by-testlet cluster, rater-by-response cells with fewer than two item or
criterion observations, no independent rater overlap, rater nesting within
task, or unsupported
Q-by-testlet coverage blocks the corresponding mechanism claim before sampling.
Decomposing stable person-by-testlet from response/occasion variation further
requires multiple occasions per supported person-by-testlet, multiple indicators
per response, and enough repeated clusters; one occasion is a rejection control.

The stress grid includes true independence, near-zero through large testlet
standard deviations, halo, rater-by-task, multidimensional, sequence-only, and
selected mixture generators. It crosses cluster size, testlets per person, raters per
response, same-rater versus criterion-split scoring, sparse/crossed/nested and
ability-informed assignment, Q-by-testlet support, dependence shape, and
latent/outcome dispersion. Promotion requires calibrated null behavior,
positive-truth recovery and coverage, boundary-zero ROPE/false-declaration
calibration under frozen practical/probability thresholds, pair-level
localization and one global dataset-level FWER gate across all enabled
diagnostic families, correction of the targeted cluster discrepancy, low
mechanism-misclassification, stable decisions and priors, and passing HMC
diagnostics.

Prediction must distinguish another rating on a known response, a calibrated
rater newly assigned to an observed response, that rater on a wholly held-out
response, a rater absent from fitting, a repeated new response on the same task,
a new person-by-testlet combination, a new person, and a new task. Each
supported target holds out and marginalizes the
corresponding unseen effect; fixed person/rater/task facets do not support
population prediction for wholly new levels, and the first scalar slice does
not support response-to-response variation. Observation-row LOO alone can leak
a learned cluster effect and is
not evidence for any whole-cluster target.
The full model, identification, stress-grid, falsification, and cluster-
prediction contracts are maintained in
[MGMFRM Research Roadmap](mgmfrm-research-roadmap.md).

Only after the static and local-dependence gates pass does the temporal
identification study begin. Before time-varying severity can be interpreted, a
predeclared stress test must cross
true rater drift with changing early/late examinee ability, presentation and
assignment policy, temporal benchmark placement, and rating-graph sparsity.
The central negative control has no true drift but deliberately places lower-
or higher-ability responses late in the sequence. Evenly distributed,
full-range repeated benchmark responses and randomized or counterbalanced
presentation are evaluated as design repairs.

The detailed roadmap distinguishes current parameter anchors from linking
performances, monitoring/validity benchmarks, and repeated embedded benchmark
responses. It also maps direct primary precedents for dynamic MFRM, ratings and
rating-time models, Hierarchical Rater Models, Bayesian G theory, DFF,
adaptive rater monitoring, and human--machine rating. These component areas
have prior research; their fixed-Q multidimensional, time-varying,
assignment-aware integration remains a later research contribution and does
not broaden the current public package scope.

## Literature-Anchored Synthetic Benchmark

The first DOI-traced benchmark artifact materializes two deterministic
known-truth datasets from the literature-informed design review. The scalar pilot is
the smallest Uto and Ueno (2020) recovery cell (`J=30`, `I=3`, `R=5`, `K=5`,
fully crossed). The multidimensional pilot uses the smallest two-dimensional Uto
(2021) cell (`J=50`, `I=5`, `R=5`, `L=2`, `K=4`, fully crossed), but is explicitly
adapted to the package's confirmatory fixed-Q surface: inactive loadings are zero
rather than the paper's non-primary anchor loading of `0.2`, and the ability
term is recorded as a loading-weighted sum.

The generator duplicates the published adjacent-category equations in a
standalone response-sampling path and does not call package simulation or
probability helpers. After generation, it uses the package source-equation path
only as an oracle check. The committed artifact records the maximum probability
error, parameter truth, independent truth/response seeds, row hashes, and the
exact/adapted crosswalk. This is stronger wiring evidence than a same-code
simulation, but remains an in-repository crosscheck rather than an independently
maintained external oracle.

The independent review packet is now frozen as a separate artifact, but it is
not a signed review. A TAM `tam.mml.mfr` overlap baseline and CSV export are
prepared, and one local TAM execution review records the extracted parameter
table plus diagnostic item/rater/item-step comparisons. A follow-up TAM policy
review reconstructs the TAM category intercepts from the expanded facet table,
confirms the item-step sum constraints, and freezes post-pilot thresholds for
future replications. The item/rater pilot clears those future numerical gates;
item-step does not. The frozen policy has now been executed over 30 TAM fits at
40, 100, and 250 persons. All three parameter blocks pass in every primary
250-person replication; item-step passes 6/10 at 40 persons and 10/10 at both
100 and 250 persons. A same-data direct-estimate pilot then fits the package with
four AdvancedHMC chains: all sampler gates pass and the three aligned parameter
blocks correlate above 0.99 with TAM estimates. Because direct-agreement
thresholds were not frozen before that pilot, it remains descriptive. A
prospective direct package-versus-TAM agreement policy is now frozen for future
runs. A separate multiaxial refinement sidecar leaves every frozen primary
threshold unchanged while separating agreement from truth recovery, fixing
seed/data/fit/retry/failure contracts, recording the five-replication precision
limit, and constraining any result to the fully crossed unit-discrimination
MFRM/PCM overlap. The current item-step pilot is therefore classified as close
descriptive package/TAM agreement without full known-truth recovery support. A
separate completed execution artifact now applies that unchanged policy to five
fresh 40-person and five fresh 100-person datasets. All ten package fits pass
the frozen sampler gate, all ten TAM fits pass the numerical and adapter audit,
and item, rater, and item-step direct agreement pass 5/5 in the primary
100-person condition. Both estimators' known-truth recovery qualifiers also
pass 5/5 for every primary block. The 40-person stress condition illustrates
why these layers remain separate: direct agreement is 5/5 for every block,
while package and TAM recovery counts are 4/5 for item, 5/5 for rater, and 3/5
for item-step. Four rank-normalized R-hat advisories just exceed 1.01, although
every prospectively frozen classical R-hat/ESS/HMC gate passes. The all-attempt
audit retains 11 attempts and hashes 230 files, including the non-selected
result-writer failure and its same-seed infrastructure retry. The separate
post-execution packet is ready for review and its core execution hash chain
passes. The byte-exact refinement snapshot used by the retained jobs is now
preserved separately, and selected-job plus all-attempt input lineage is
checked against it without rerunning MCMC. The immutable pre-execution packet
is not rewritten, however: its policy hash matches while its refinement hash
identifies an older snapshot. That chronology difference remains an explicit
independent-review task and public-claim blocker. Independent re-execution and
a signed review remain
incomplete. The remaining scientific gates are
multi-replication generalized recovery refits, a unit-discrimination MFRM
bridge for FACETS, an aligned MRCML bridge for ConQuest, and external construct
data. None of the TAM evidence transfers to GMFRM/MGMFRM or Uto (2021), and no
package-wide or public validation claim is released.
The upper claim-recovery/full reproduction archives and broader/guarded
exposure reviews carry the TAM artifacts only as MFRM-overlap non-transfer
evidence. Their pending independent review and chronology adjudication remain
TAM-claim blockers and do not disable the existing guarded local fit surfaces.
Synthetic known truth can test source equations, constraints, recovery, and
design stress; it cannot
establish construct representation, population generalization, fairness, or
performance on an external real dataset.

## v0.1.1 Release Record

The `v0.1.1` release refined the core generalized and multidimensional surfaces
without broadening public claims. Its target was better auditability: the
guarded scalar GMFRM and fixed-Q confirmatory MGMFRM paths were required to
explain their source equations, constraints, priors, diagnostics, and reports
clearly enough for serious review.

`v0.1.1` kept these boundaries:

- no exploratory MGMFRM loadings, rotations, or free latent correlations;
- no dimensionality discovery beyond a fixed confirmatory Q-matrix;
- no fitted DFF model effects;
- no public model-weight, sparse-superiority, or manuscript-level claims;
- no direct-scale generalized priors unless the log-Jacobian policy is fully
  documented and tested.

The implementation roadmap originally defined six workstreams. The `v0.1.1`
scope was frozen to the completed status, portable-report, fixed-Q,
initial-diagnostics, MFRM FACETS-description, reproducibility, and runnable
example slices. Broader predictive/category reporting, rank-normalized and
bulk/tail diagnostics, rater-homogeneity work, and expanded validation bundles
described below are deferred to v0.1.2 or later.
The issue-sized implementation checklist is maintained in
[v0.1.1 Implementation Checklist](v0.1.1-implementation-checklist.md).

1. **Equation and status review**: reconcile public terminology for rater
   consistency, item/dimension discrimination, raw coordinates, direct
   parameters, constraints, and status levels across `model_manifest`,
   `constraint_table`, `fit_metadata`, reports, README text, and docs. Add a
   [`related_software_capability_matrix`](@ref) so the package is positioned
   against Facets, TAM, mirt, sirt, immer, and brms/Stan workflows without
   overstating coverage. Add
   `evidence_artifact_schema_policy` rows for schema version,
   package/git/environment hashes, cache provenance, unsupported-claim flags,
   and raw-data/anonymization status. Add [`release_gate_check`](@ref) so
   README, docs, roadmap, and manifest status rows fail fast when they drift.
2. **Generalized MFRM refinement**: make the scalar GMFRM experimental path use
   a coherent compiler-generated raw/direct block layout, improve unsupported
   option errors with actionable `blocked_option` and `next_gate` values, keep
   broader GMFRM variants gated, decide whether item discrimination remains
   preview-only or becomes an internal promotion target, separate stable
   guarded public target labels from private constructor names in artifacts,
   record that rater-step source blocks are not yet public fit options, expose
   prior/pooling policy rows in `fit_report`, and record that
   hierarchical facet priors or partial pooling remain blocked until estimands,
   hyperpriors, shrinkage diagnostics, and sensitivity are documented.
3. **Fixed-Q MGMFRM hardening**: `q_matrix_validation` now validates Q-matrices
   for empty rows/dimensions, aliased columns, fixed cross-loading policy, and
   dimension-specific coverage; dimension labels now flow through manifests,
   constraint rows, metadata, reports, and report tables; `fit_report` records
   the fixed gauge and blocked alternatives. `rating_design_audit` now covers
   missingness, anchor coverage,
   repeated ratings, time/order fields, sparse person-rater-item blocks, and
   nonignorable assignment warnings, and add checks that reports do not depend
   on rotation or free latent correlation interpretations.
4. **Diagnostics and reporting**: generalized diagnostics now use
   rank-normalized split R-hat and bulk/tail ESS across
   `GMFRMFit` and `MGMFRMFit`, report the prior contract and prior-predictive
   implications, add posterior predictive and calibration rows that state the
   predictive path used, retain classical `rhat`/`ess` fields for compatibility
   only, gate raw unconstrained and applicable direct constrained rows, keep
   zero-raw-dimension coordinates as non-gated `:structurally_fixed` rows while
   retaining reconstructed-but-varying coordinates in the gate, require
   complete finite chain coverage before applying the E-BFMI threshold, bind a
   versioned diagnostic contract into generalized cache identity, keep wrapper
   schemas at version 1 while treating rows without
   `rank_normalized_rhat_bulk_tail_ess_v1` as pre-modern, and
   keep WAIC/LOO/K-fold outputs as diagnostic rows rather than model-weight
   claims. Add a binary-response note that distinguishes many-facet
   Rasch/1PL IRT from generalized binary GMFRM/MGMFRM terms. Add runtime,
   memory, and ESS/sec fields without making performance claims before sampler
   quality gates pass. Add category-functioning rows for observed category use,
   skipped/sparse categories, posterior step uncertainty, predictive category
   replication, and diagnostic-only category-collapsing flags.
5. **Validation evidence**: add small and medium BridgeStan fit-target
   comparisons, predeclared simulation grids for rater consistency and
   fixed-Q loading recovery, compact workflow demonstrations, prior-scale
   sensitivity rows, prior/likelihood power-scaling sensitivity with
   weight-ESS or Pareto-k/refit follow-up flags, and versioned evidence
   artifacts. Defer real-data validation and overlapping R-package comparison
   until after `v0.2.0`, and run the R comparison first as a known-truth
   simulation study. Include missingness, weak linking, skipped categories,
   and rater-specific category compression in the simulation pathologies.
6. **Interpretation policy**: keep model comparison diagnostic rather than
   claim-making, stabilize plotting-data schemas before backend-specific
   visualization recipes, keep DFF/bias effects validation-only, add rater
   homogeneity summaries based on posterior contrasts with ROPE and HDI or
   explicitly labelled central intervals, add a FACETS-fit compatibility
   policy for infit/outfit MNSQ, degrees-of-freedom approximations, and ZSTD
   labels, maintain the FACETS/ConQuest migration crosswalk, extend overlapping
   examples to TAM/mirt/sirt/immer, and keep Bayes factors out of the default
   workflow until
   prior-sensitivity policy is documented.

The release gate was documentation and evidence, not API breadth. `v0.1.1` was
limited to changes that made the guarded GMFRM/MGMFRM paths easier to inspect
and harder to overinterpret. Broad generalized fitting remains blocked until
the later stable-public gates pass.

### Critical Triage Rules

The next roadmap decisions should use a conservative triage order:

1. **Correctness before speed**: source-equation, BridgeStan, raw/direct
   transform, and pointwise likelihood checks outrank runtime and API breadth.
2. **Diagnostics before interpretation**: posterior summaries are reportable
   only when sampler diagnostics, direct-constraint checks, and prediction-path
   labels are present in the same artifact.
3. **Design support before fairness**: DFF rows remain screening evidence
   unless the rating graph, group/rater/item cells, and posterior predictive
   checks support the requested contrast.
4. **Sensitivity before ranking**: model ranking, rater ordering, loading
   interpretation, and sparse-design claims require prior/likelihood
   sensitivity rows and explicit practical-magnitude thresholds.
5. **Cluster structure before dynamic interpretation**: residual dependence
   must be compared across testlet, halo, rater-by-task, multidimensional, and
   sequence mechanisms using cluster-heldout prediction before it is labelled.
6. **Scope labels before examples**: every runnable example must state whether
   it is `supported`, `experimental_public`, `specified_only`, or `blocked`.

Fallback paths remain explicit for later releases. For `v0.1.1`, unstable
fixed-Q MGMFRM diagnostics would have narrowed the release to report-governance
and validation improvements without expanding examples. If source or
sensitivity checks fail for generalized blocks, keep the API guarded and
document the failed gate. If external comparison targets do not match,
classify them as non-overlap rather than forcing a misleading validation table.

### Evidence Maturity Matrix

Use the weakest satisfied row as the public status of a feature.

| Status | Required artifacts | Allowed public wording |
| --- | --- | --- |
| Specified only | Spec/design rows, constraints, blocked-option rows, and unsupported-claim flags. | The model can be described and inspected, but not fit or interpreted. |
| Experimental public | Narrow fitting path, source/transform checks, small examples, diagnostics, and explicit caveats. | Users may run the path for review or experimentation; conclusions are provisional. |
| Fit supported | Stable constraints, documented priors, block diagnostics, PPC/calibration rows, prediction-target labels, and reproducible artifacts. | The package supports fitting this narrow model under stated design conditions. |
| Interpretation supported | Fit-supported evidence plus practical-magnitude thresholds, sensitivity checks, design-support checks, and report wording tests. | Posterior contrasts or summaries may be interpreted within the stated scope. |
| Validation supported | Interpretation-supported evidence plus known-truth simulations and compatible external-target comparisons. | The claim may appear in release notes, papers, or external validation summaries. |

This matrix is deliberately stricter than the existence of exported functions.
For example, a model-comparison helper can be public while model-weight claims
remain blocked, and a DFF screening row can be useful while fitted DFF effects
remain out of scope.

### Promotion Review Questions

Before promoting any feature, answer these questions in the docs or the
machine-readable artifact that backs the docs:

- What is the estimand, and which parameter block or contrast carries it?
- Which design conditions must hold before the estimate is interpretable?
- Which constraint, gauge, prior, and transform choices make the parameter
  identifiable?
- Which diagnostics can fail, and where does the failure appear in report rows?
- Which prior, likelihood, prediction-target, or heldout split sensitivity
  would change the substantive conclusion?
- What is the conditional-independence unit, and does a heldout target leave an
  entire response/testlet cluster unseen or condition on information from it?
- Which design contrast distinguishes testlet, rater-response halo,
  rater-by-task, multidimensional, and sequence explanations?
- Which comparable external target exists, if any, and which cases are
  explicitly non-overlap?
- Which row-level data, labels, hashes, or provenance fields are exported, and
  is that appropriate for public artifacts?

If one of these questions has no answer, the feature can remain callable, but
the claim should stay at `specified_only` or `experimental_public`.

### Claim Budget by Release

Each release should spend its claim budget on fewer, better-supported
statements.

| Release | Claim budget | Explicitly not in budget |
| --- | --- | --- |
| `v0.1.1` | Delivered: existing guarded scalar GMFRM and fixed-Q MGMFRM paths became more auditable; status, priors, diagnostics, Q/gauge, rating-design, report, and artifact wording became harder to overinterpret. | Broader generalized fitting, exploratory loading, free latent correlations, fitted DFF effects, model weights, external validation, performance claims. |
| `v0.1.2` | Fixed-Q confirmatory dimensionality expands only if Q validation, source checks, initialization, diagnostics, recovery, and report schemas scale cleanly. | Free latent correlations, exploratory loading, broad MGMFRM, real-data validation claims. |
| `v0.1.3` | Free latent correlation receives a proceed/narrow/stop decision with parameterization, prior, diagnostics, and sensitivity evidence. | Automatic promotion of free correlations or exploratory loadings. |
| `v0.1.4` | Exploratory loading and rotation policy is designed and stress-tested as a reporting problem before exposure. | Stable exploratory MGMFRM claims without rotation/sign/permutation evidence. |
| `v0.2.0` | A narrower stable-public MGMFRM candidate may ship if every exposed option passes source, transform, computation, simulation, sensitivity, and reporting gates. | R-package validation and real-data validation as prerequisites for v0.2.0; those are post-v0.2.0 evidence. |
| Post-`v0.2.0` | Compatible known-truth simulation comparisons against overlapping R package targets can support external validation language. | Treating non-overlap targets or single real-data examples as validation. |

### Runtime-Aware Verification

Post-v0.1.1 work should use staged verification because Julia
startup, precompilation, guarded HMC smoke tests, Documenter builds, and
fixture/archive regeneration can be slow. Local slices should start with load
checks and targeted fixture scripts; manifest, report, or docs changes should
regenerate low-level fixtures before review/archive fixtures; and the fixture
SHA scan should run before the full test suite. Full `Pkg.test()` runs remain
mandatory for milestone slices, supported-Julia release checks, and the final
tag candidate, but they should not be the first feedback loop for every small
edit.

### Verification Ladder

Use the cheapest check that can falsify the current change, then climb the
ladder as the release candidate hardens.

| Stage | When to run | What it can prove | What it cannot prove |
| --- | --- | --- | --- |
| Package load | After dependency, export, or documentation-reference changes. | The package imports and precompilation reaches the changed surface. | Mathematical correctness or sampler quality. |
| Narrow unit or fixture check | After source, transform, report-row, or validation edits. | The changed contract still produces the expected rows. | Broad workflow stability. |
| Guarded smoke fit | After generalized fit, initialization, or diagnostic edits. | The narrow experimental path still runs and records failures visibly. | Production HMC reliability. |
| Fixture/archive scan | After regenerating stored evidence or report bundles. | Stored hashes and expected artifacts are internally consistent. | New statistical validity. |
| Docs build | After docs, examples, exports, or public wording changes. | References, examples, and pages render in the docs environment. | Release readiness if the docs manifest points at a stale local path. |
| Full `Pkg.test()` | Before milestone merge, release candidate, or tag. | The package-level test contract passes under the selected Julia version. | External validation or general MGMFRM support. |
| Supported-version release pass | Before tagging. | The release is reproducible across declared supported Julia versions. | Claims outside the release-scope rows. |

### Release Evidence Packet

A release candidate should have a compact evidence packet whose contents match
the release-scope claim. Missing entries do not always block a code release, but
they do block the corresponding public claim.

| Packet entry | Required for | Minimum content |
| --- | --- | --- |
| Scope summary | Every release | `release_scope_summary(; include_evidence = true)` output and blocked-claim rows. |
| Model-surface review | Generalized or multidimensional releases | Family, dimensions, constraints, status levels, unsupported options, and public wording. |
| Source/transform evidence | Fit-surface promotion | Fixture IDs, tolerance policy, raw/direct checks, and BridgeStan or hand-computed comparison. |
| Diagnostic evidence | Fit-supported or interpretation-supported claims | Block-level diagnostics, sampler pathologies, R-hat/ESS type, direct constraints, and failure rows. |
| Design-support evidence | DFF, rater, anchor, or Q-matrix claims | Rating graph, category use, anchors, Q support, sparse cells, and confounding warnings. |
| Cluster-dependence evidence | Testlet, halo, rater-by-task, or dynamic claims | Response/testlet keys, mechanism-specific graph audit, null and positive-control calibration, competing-generator results, and whole-cluster marginal prediction. |
| Predictive evidence | PPC, calibration, or comparison claims | Prediction target, row matching, candidate set, PPC/calibration rows, Pareto-k or refit guidance. |
| Sensitivity evidence | Ranking, fairness, loading, or practical-decision claims | Prior-scale, likelihood-power, weight-quality, and refit-required rows. |
| Artifact governance | Public bundles or case studies | Schema version, hashes, seeds, package versions, provenance, anonymization, and raw-data policy. |
| Verification log | Release candidate | Load check, targeted tests, docs build, fixture/archive scan, public-language source/render/runtime checks, manual reader-facing wording review, and full test status. |

## Critical Path to Fit-Ready MGMFRM

The roadmap treats fit-ready MGMFRM as a gated mathematical implementation,
not a naming milestone. The target follows Uto and Ueno (2020) for GMFRM and
Uto (2021) for MGMFRM, so the package must keep source equations, constraints,
priors, transforms, and sampler evidence aligned before exposing fitting. See
the [model-equations page](model-equations.md) for the DOI-backed source list.

1. **Source-equation lock**: keep the current MFRM/RSM/PCM likelihood separate
   from source-aligned GMFRM/MGMFRM targets; test every category numerator and
   denominator against hand-computed fixtures; add BridgeStan fixtures for one
   scalar GMFRM and one minimal MGMFRM.
2. **Identified raw parameterization**: document whether priors live on raw
   unconstrained coordinates or constrained direct parameters. If direct-scale
   priors are used through transforms, include log-Jacobian adjustments.
3. **Gauge and constraints**: expose product/scale, location, step, positivity,
   Q-mask, ability-scale, and latent-correlation choices in
   `constraint_table(spec)` and `model_manifest(spec)` before sampling.
4. **AD and HMC target proof**: add gradient checks and fixture-only HMC smoke
   tests for generalized raw targets; promote only the narrow scalar GMFRM and
   fixed-Q confirmatory MGMFRM paths once their evidence is recorded.
5. **Public promotion**: promote scalar GMFRM first, only after Julia and
   BridgeStan pointwise log likelihoods, transforms, AD, and sampler diagnostics
   agree. Repeat that gate for a minimal confirmatory MGMFRM with a fixed Q-mask
   and fixed latent identity correlation before expanding options.
6. **Evidence before claims**: use predeclared simulation grids, recovery
   metrics, calibration, posterior predictive checks, and Stan comparisons
   before `v0.2.0`. Defer real-data validation and overlapping R-package
   comparison until after `v0.2.0`, using known-truth simulations before any
   external validation claims.

Current exposure is deliberately conservative: MFRM/RSM/PCM fitting and
simulation/recovery helpers are public; GMFRM/MGMFRM manifests and compiler
previews are public for inspection; guarded
`BayesianMGMFRM.Experimental.fit(spec)` paths are available for the scalar
rater-consistency GMFRM candidate and the fixed-Q confirmatory MGMFRM
candidate with `dimensions >= 2`. Broader GMFRM/MGMFRM fitting, DFF model effects,
public model-weight claims, and manuscript claims about sparse MGMFRM
superiority remain blocked. Local scalar model-weight reporting is restricted to
the heldout K-fold prediction target; confirmatory MGMFRM fitting is exposed
only as a guarded experimental path without model-weight or sparse-superiority
claims.

The public FACETS/ConQuest bridge is an input-and-receipt workflow, not an
external estimator. It prepares manual-syntax unanchored MFRM/RSM/PCM bundles
on a Mac, supplies a Windows path for FACETS and Windows/macOS paths for
ConQuest, and checks the input inventory and raw returned files. Its
`host_preflight` record exposes the bundle ID plus verifier and launcher hashes
for retention through a separate channel. The operator must compare those
hashes with a trusted host-side tool before launch: a launcher delivered inside
the same transfer is not its own trust anchor, and without that comparison the
workflow claims accidental-corruption detection rather than protection from
hostile replacement. A receipt alone does not establish that an external
execution occurred correctly, that it converged, that parameters were mapped,
that gauges agree, or that numerical results are equivalent. A separate
fail-closed adapter now resolves source-gauge rater, item, and step identities
for the exact ConQuest 5.47.5 three-category RSM/PCM boundary by jointly
validating the complete bundle, comments, and design matrix. It does not align
the destination gauge or establish convergence. The macOS fixtures and adapter
remain version-specific single-operator evidence rather than independent
external validation.

## Progress Ledger and Canonical Maturity Dashboard

This dashboard is the canonical interpretation of completion percentages.
Every percentage has its own named denominator; values from different rows
must not be averaged or treated as interchangeable.

| Progress axis | Current estimate | Denominator | What remains outside or incomplete |
| --- | ---: | --- | --- |
| Mechanical roadmap checklist | **160/189 (84.7%)** | All checked and unchecked roadmap tasks, including historical delivery, documentation, evidence, and future research infrastructure. | This is task-accounting only. It is **not** the implementation rate of MFRM, GMFRM, or MGMFRM. |
| Minimal MFRM/RSM/PCM core implementation | **about 96%** | The declared Bayesian scope: long-format data/specification, identified RSM/PCM likelihoods, priors, HMC fitting, diagnostics, PPC/calibration, category/rater practitioner summaries, reporting rows, cache/reproduction support, tests, and examples. | Remaining work is actual hard-anchor refitting, report integration for the new practitioner summaries, and edge-case hardening. FACETS feature parity, JMLE/MMLE backends, generalized discrimination, and external construct validation are not part of this denominator. |
| Minimal MFRM/RSM/PCM validation maturity | **about 80-83%** | Evidence needed to call the narrow Bayesian implementation externally validated and production-ready under stated design conditions. | The repeated recovery scorer, design preflights, narrow TAM evidence, and a version-specific ConQuest RSM/PCM known-truth execution fixture exist. Staged repeated MCMC, FACETS execution, independent ConQuest/TAM re-execution and review, external construct data, and comparative performance evidence remain open. |
| TAM narrow-overlap evidence for MFRM | **about 80-85%** | The fully crossed unit-discrimination MFRM/PCM target currently shared by the package and TAM, with aligned signs, constraints, known truth, and direct parameter blocks. | Local direct agreement and recovery evidence are strong, but independent re-execution, signed review, and chronology adjudication remain open; the result does not transfer to GMFRM/MGMFRM. |
| FACETS compatibility and validation bridge | **about 65-72%** | Familiar MFRM summaries plus a matched known-truth comparison with FACETS under aligned model, scale, anchoring, weighting, and reporting conventions. | The migration crosswalk and deterministic manual-syntax input/return-integrity bundle are implemented. Actual Windows PowerShell 5.1 verification, a licensed-host execution, version-specific output samples, semantic result adapter, gauge-aligned comparison, anchored second stage, and independent numerical review remain open. |
| ConQuest overlap bridge | **about 72-76%** | A matched MRCML/MFRM target with explicit design matrices, constraints, parameter signs, and known-truth recovery. | The MRCML crosswalk, deterministic bundle, Windows/macOS launch paths, strict raw reader, exact output contract, receipt-bound macOS 5.47.5 RSM/PCM known-truth fixtures, and a fail-closed three-category source-gauge semantic adapter now exist. The adapter binds the complete bundle back to the specification, verifies exact comment/header order and the full design basis, and reconstructs rater/item/step constraints without a sign reversal. A convergence policy, destination reference-gauge transform, direct package comparison, anchor-aware second stage, Windows-path execution, and independent re-execution/review remain open. |
| Full FACETS/TAM product feature parity | **not scored (non-goal)** | The complete breadth of mature products, including model catalogs, arbitrary facet structures, response types, weighting, operational workflows, graphics, and long-established examples. | Add only capabilities that strengthen the declared Bayesian MFRM/MGMFRM workflow; do not turn unrelated product breadth into a hidden completion requirement. |
| Guarded scalar GMFRM implementation | **about 72-78%** | The deliberately narrow rater-consistency candidate, not every generalized MFRM variant. | Stable-public promotion, broader generalized kernels/priors, recovery breadth, and external validation remain open. |
| Guarded fixed-Q confirmatory MGMFRM implementation | **about 72-78%** | Fixed Q, confirmatory dimensions, fixed latent identity correlation, guarded Bayesian fitting, diagnostics, and recovery artifacts. | Stable-public promotion and broader design validation remain open; exploratory Q/loadings and free latent correlations are excluded. |
| Broad stable-public generalized claim maturity | **about 50-55%** | Evidence required for broader release or manuscript claims, rather than callable local implementations. | Valid external construct attachments, independent signed public-scope review, generalized diagnostics/reporting hardening, and compatible post-`v0.2.0` external comparisons remain open. |
| Generic MGMFRM research target | **about 30-40%** | A broader engine including exploratory/estimated structure, free latent correlations, generalized kernels and priors, and wider validation. | Major mathematical, computational, identification, reporting, and validation milestones remain downstream. |

The absence of JMLE or MMLE does not lower the approximately 96%
core-implementation score:
the package currently declares a Bayesian estimator, so JMLE/MMLE would be a
new estimator family and should receive a separate future milestone and
evidence ledger. Likewise, the breadth of FACETS or TAM is a related-software
positioning and overlap-validation axis, not a hidden requirement for calling
the declared Bayesian MFRM/RSM/PCM implementation complete. The present TAM
evidence strengthens the overlapping MFRM slice; it does not establish feature
parity, production superiority, construct validity, or transfer to
GMFRM/MGMFRM.

### MFRM Completion and Interoperability Tracks

The remaining MFRM work is split into three tracks so that estimator breadth
cannot silently reduce the declared Bayesian implementation score:

1. **Bayesian core-to-complete:** finish the predictive and decision-stability
   portions of the paired sparse/nonrandom scorer, execute the staged repeated
   fits, integrate the completed MFRM category/rater summaries into
   `fit_report`, and implement the affine hard-anchor refit map. The new
   `anchor_refit_plan` is a provenance, identifiability, and numerical-strategy
   preflight; it does not yet perform a constrained refit or estimate linking
   constants.
2. **Practitioner and external bridges:** the FACETS/ConQuest migration guide
   now freezes sign, scale, constraint, threshold, anchor, and estimator
   non-equivalence rules. The deterministic version-1 bridge prepares
   unanchored manual-syntax bundles on a Mac, verifies inputs before the
   FACETS Windows or ConQuest Windows/macOS launcher calls an authorized
   executable, and verifies the returned input inventory and raw-output hashes.
   The ConQuest 5.47.5 macOS RSM/PCM known-truth run and privacy-reduced sample
   freeze and the narrow source-gauge semantic adapter are complete. Next,
   independently re-execute those samples, validate a separate destination
   reference-gauge transform, execute FACETS and the Windows paths, and only
   then design an anchor-aware second stage for the exact returned designs. A
   successful receipt is transport-integrity evidence,
   not convergence or numerical-validation evidence. Independently re-execute the
   narrow TAM comparison as a separate gate; keep point-estimate agreement and
   uncertainty agreement separate.
3. **Optional estimator interoperability:** prefer reproducible external
   adapters before considering native JMLE or MMLE engines. A native
   frequentist backend should be proposed only for a concrete use case and must
   have its own mathematical, numerical, diagnostic, and maintenance gates; it
   is not part of the final five percent of the Bayesian core.

The former scalar GMFRM frontier is now a guarded experimental path. It has
source-aligned fixtures, raw transforms, BridgeStan raw checks, constrained
direct parameter checks, direct pointwise likelihood checks, ForwardDiff
diagnostics, an internal raw/direct AdvancedHMC sampler diagnostic surface, and
an internal fit-ready compiler-candidate manifest. It also has a BridgeStan
fit-ready oracle block for raw, constrained, gradient, pointwise, and
total-likelihood checks, plus a local predeclared candidate-chain study artifact
over two fixed initial-value fixtures. The committed small and medium scalar
Stan/BridgeStan log-density and gradient fixtures now have machine-readable
validation rows and a gate summary via [`stan_validation_row`](@ref) and
[`stan_validation_summary`](@ref). It also records an internal
experimental-public decision manifest whose current scalar decision is
`enable_guarded_experimental`.
It now has local recovery-smoke evidence by direct parameter block, a local
three-scenario stress-chain grid, an initial local baseline-comparison artifact,
and a three-scenario baseline/calibration grid against public MFRM/PCM/RSM
baselines. Local interval/decision, sparse-design, WAIC influence, raw
importance-sampling LOO/Pareto-k, deterministic K-fold refit, and
guarded-exposure review artifacts plus a guarded fit API dry run and guarded
fit method-wiring artifact are now recorded. The scalar candidate now has a
guarded experimental fit method plus local experimental fit validation and
posterior predictive grids plus local sparse-pathology recovery and
prior/likelihood sensitivity grids plus a compact real-data case study and a
local claim-level recovery/reproduction archive manifest plus a broader
exposure decision review plus local confirmatory MGMFRM sparse-recovery
evidence plus local confirmatory MGMFRM guarded fit method-wiring plus local
confirmatory MGMFRM guarded fit validation-grid plus local confirmatory MGMFRM
guarded fit API dry-run plus local confirmatory MGMFRM guarded public exposure
review, a local prediction-target/model-weight policy, a local manual
public-scope review, a local DFF
estimand/validation grid, Gate E manuscript-scale evidence, and a local
full-paper reproduction archive. The fixed-Q confirmatory MGMFRM guarded sampler
is now available through `BayesianMGMFRM.Experimental.fit(spec)` and records
raw/direct draws, sampler diagnostics, direct constraints, pointwise log
likelihood, and an experimental fit artifact while keeping broader MGMFRM
exposure blocked. The older keyword spelling remains compatibility-only.
The minimal
MGMFRM path now has an internal confirmatory gauge candidate manifest, a separated
fit-ready candidate transform manifest, and a BridgeStan confirmatory-candidate
oracle block for raw, direct, gradient, pointwise, and total-likelihood checks.
It also has a local two-fixture candidate-chain diagnostic artifact, a local
recovery-smoke artifact, a local baseline-comparison artifact, and a local
sparse-recovery grid over connected sparse fixed-Q scenarios. Its public-API
decision is now `enable_guarded_experimental` for the fixed-Q confirmatory
candidate only. Guarded generalized-model caveat docs and an experimental
generalized fit-artifact contract are now recorded locally, and DFF
validation-only evidence is recorded. The generalized raw-prior
and Jacobian policy is recorded as raw-coordinate priors with no transform
Jacobian and no direct-scale priors.

## Promotion Levels

Model surfaces should move through explicit levels:

| Level | Meaning |
| --- | --- |
| `blocked` | Planned or unsupported; validation and docs prevent accidental use. |
| Test-only implementation | Likelihood or transform exists only for tests and source-equation checks. |
| Private validation candidate | Private target with raw/constrained manifests, AD checks, HMC diagnostics, and BridgeStan evidence. |
| `experimental_public` | Narrow user-facing fit path with explicit warnings, diagnostics, and recovery smoke evidence. |
| `stable_public` | Ordinary examples and package claims are supported by internal simulation, sensitivity checks, and reproduction artifacts. |
| `external_validated` | Post-`v0.2.0` claims supported by known-truth R-package simulation comparisons and, only after that, real-data validation evidence. |

Scalar GMFRM can become `experimental_public` only after fit-ready raw and
constrained compiler maps exist, the raw-prior/Jacobian policy is recorded,
BridgeStan agrees with Julia on raw, constrained, and pointwise quantities,
candidate chains produce block-level diagnostics, baseline comparisons are
available, the guarded exposure decision is defensible, and unsupported options
are rejected with actionable errors.

The first MGMFRM target stays confirmatory: fixed Q-mask, fixed identity latent
correlation, documented ability scale, explicit sign/positivity rules,
manifested rater/item constraints, BridgeStan pointwise checks, and guarded HMC
diagnostics before any broader MGMFRM option is exposed.

## Reviewer Gates

### Identification

Every future parameter block must have documented constraints, transforms,
priors, and interpretation. `getdesign(spec)` should expose these decisions
before fitting, and `validate_design` should warn when the observed data cannot
support the requested structure.

### Local Independence and Cluster Prediction

Residual dependence is screening evidence, not a mechanism label. A testlet or
rating-bundle extension must declare response/testlet keys, cluster replication,
rater and task crossing, Q-by-testlet support, the variance-boundary policy,
and whether prediction conditions on or marginalizes each shared random effect.
Whole-response heldout evaluation is required for new-response claims.

### Bayesian Computation

Future HMC/NUTS fits must report diagnostics by parameter block: R-hat,
bulk/tail ESS, divergences or numerical errors, max-treedepth hits, step size,
leapfrog counts, and E-BFMI coverage. Summaries may retain the minimum finite
available E-BFMI for compatibility, but the quality threshold applies only
when every expected chain is available. Faster runtime is not evidence unless
sampling quality also passes.

### Bayesian Workflow

Posterior summaries are not enough. The package roadmap includes prior
predictive checks, posterior predictive checks, calibration summaries, LOO/WAIC
diagnostics, and prior/likelihood sensitivity workflows as first-class APIs.

### DFF and Fairness

DFF should be treated as screening evidence for fairness review. DFF APIs
should define estimands before fitting, separate rater main severity from DFF,
report both logit and expected-score scales, include declared-threshold
practical magnitude, and pair screening rows with model-checking evidence.

### Reproducibility

Paper-grade artifacts should have both full rerun and fast cached-draw
reproduction paths. Seeds, specs, priors, sampler controls, package versions,
Stan fixtures, cached draws, and rendered reports should be versioned.

## Release Targets

### v0.1 Scaffold Hardening

- Add public roadmap/scope documentation. [Done]
- Add a validation-to-suggestion map. [Done]
- Add `model_manifest(spec)` or an equivalent provenance schema. [Done]
- Add a diagnostics schema that can grow from random-walk Metropolis to HMC.
  [Done]
- Keep documentation explicit that current model-comparison and predictive
  helpers are small-model scaffolding.

### v0.2 Specification Compiler

- Represent MFRM, GMFRM, and MGMFRM as configurations of one canonical spec.
  [Initial specified-only ladder done]
- Add source-traced equation contracts that distinguish the current
  fit-supported MFRM/RSM/PCM kernel from the primary-literature GMFRM/MGMFRM
  targets and their missing parameter blocks. [Done]
- Compile domain options into design blocks, loading masks, scoring vectors,
  constraints, priors, and validation requirements.
  [`domain_compilation_summary` now ties domain options to compiled blocks,
  fixed loading masks, scoring vectors, constraints, priors, and validation
  requirements. Observation-level design row metadata added for MFRM and specified-only
  GMFRM/MGMFRM previews; row-by-category linear-predictor metadata added for
  denominator review; internal hand-computed source-aligned GMFRM/MGMFRM preview
  fixture, raw-coordinate transform checks, and fixture-only raw-coordinate
  log-likelihood / `LogDensityProblems.jl` target checks added; preview
  raw-parameterization manifest rows now expose raw/constrained block maps,
  transform rows, raw prior policy, and no-Jacobian raw-density policy;
  normalized identification declarations now cover sum-to-zero, reference,
  fixed, geometric-mean-one, hard/soft anchors, and multidimensional gauge
  rows; fit-ready parameter layout metadata now records MFRM direct blocks and
  GMFRM/MGMFRM raw/constrained candidate blocks; guarded generalized fit
  diagnostics and fit artifacts now carry the compiler-generated
  raw/constrained layout plus raw/direct posterior row schemas; scalar GMFRM
  item-discrimination public promotion is explicitly kept preview-only for
  `v0.1.1` via a machine-readable decision row; scalar GMFRM internal
  experimental-candidate gates, a fit-ready compiler-candidate manifest, gradient
  diagnostics, direct block metadata, direct pointwise fixture API,
  raw-to-direct transform diagnostics, internal raw/direct sampler diagnostic
  surface, a local candidate-chain study artifact, an internal
  experimental-public decision manifest, a local recovery-smoke artifact,
  BridgeStan constrained parameter checks, fit-ready BridgeStan oracle checks,
  a minimal confirmatory MGMFRM gauge-candidate manifest, and a separated
  fit-ready MGMFRM candidate transform manifest plus confirmatory BridgeStan
  oracle checks added]
- Add stable preview block names and parameter names for specified-only
  GMFRM/MGMFRM specs. [Done]
- Align specified-only preview blocks with the primary-literature GMFRM and
  MGMFRM equations: item discrimination, rater consistency, rater-specific
  steps, item-dimension discrimination, and item-specific steps. [Done]
- Expose all-category linear-predictor compiler rows for the current MFRM
  kernel and specified-only source-aligned GMFRM/MGMFRM previews. [Done]
- Connect the current MFRM/RSM/PCM linear-predictor rows to numeric `eta`,
  log-denominator, and category log-probability values. [Done]
- Add fit-ready block names, parameter names, and fixture-backed likelihood
  tests. [Initial GMFRM/MGMFRM preview fixtures and fixture-only raw likelihood
  / log-density target checks, ForwardDiff raw-target gradient checks, and raw
  transform boundary checks done; preview raw-parameterization manifest rows
  added; public fit-ready parameter layout rows added for MFRM direct blocks
  and GMFRM/MGMFRM raw/constrained compiler candidates; scalar GMFRM
  experimental-candidate fit-ready compiler manifest, gradient and raw-to-direct
  transform diagnostics, direct pointwise fixture API, and BridgeStan
  direct-parameter checks added; internal raw/direct sampler diagnostics, a
  local two-fixture candidate-chain study artifact, an experimental-public
  decision manifest, a local recovery-smoke artifact, guarded method-wiring
  evidence, and fit-ready scalar GMFRM BridgeStan oracle checks added; minimal
  confirmatory MGMFRM gauge manifest, fit-ready candidate transform manifest,
  confirmatory direct/raw pointwise fixture, fit-ready confirmatory MGMFRM
  BridgeStan oracle checks, a local confirmatory MGMFRM candidate-chain
  artifact, and a local recovery-smoke artifact, and an internal keep-internal
  public API decision manifest added]
- Add BridgeStan fixture generation for scalar GMFRM and one minimal
  confirmatory MGMFRM before exposing generalized fitting. [Source-aligned raw
  GMFRM/MGMFRM Stan reference models, BridgeStan JSON fixtures, generation
  script, and default Julia checks are in place for the internal fixture
  targets; nested fit-ready scalar GMFRM and confirmatory MGMFRM oracle checks
  are in place while broader generalized fitting remains guarded]

### v0.3 HMC Estimation Core

- Add AdvancedHMC/Turing sampling behind a shared fit object. [AdvancedHMC
  minimal backend added; shared analytic/AD gradient adapter added for current
  HMC paths; minimal Turing/NUTS backend added for the MFRMLogDensity fit path]
- Add diagnostics with parameter-block pass/fail flags. [Done for current
  identified blocks]
- Store sampler controls, optional seeds, thread/package environment metadata,
  and draw-inclusion policy in a fit artifact. [Done for MFRM and guarded
  generalized fit objects]
- Add RDS-like serialized fit caches with initialization-vector hashes and
  explicit cache-key invalidation checks. [Done for MFRM and guarded
  experimental GMFRM/MGMFRM fit objects]
- Add artifact content hashes and long-term archive manifests for exported
  cache bundles. [Done for current fit artifact/cache records]
- Expose log likelihood, log prior, and log posterior separately. [Done for
  scalar target evaluation and draw-level fit-object component vectors]
- Add AD gradient checks and fixture-only HMC smoke tests for internal
  GMFRM/MGMFRM raw targets before broad generalized fitting. [ForwardDiff
  raw-target gradient checks, fixture-only AdvancedHMC/NUTS smoke tests,
  guarded scalar GMFRM method wiring, and swappable AdvancedHMC gradient
  adapter checks done]
- Validate against Stan on small and medium fixtures. [Small and medium scalar
  Stan/BridgeStan log-density and gradient fixtures are committed, checked by
  tests, and exposed through [`stan_validation_row`](@ref) and
  [`stan_validation_summary`](@ref); broader generalized Stan fit comparisons
  remain a separate claim-level validation item]

### v0.4 Bayesian Workflow Layer

- Extend prior/posterior predictive checks and calibration. [Single-dataset
  simulation, recovery summaries, and plotting-ready recovery/calibration/PPC
  rows added for the current fit-supported MFRM/RSM/PCM slice; prior
  predictive implication diagnostics now cover category use and broad facet
  mean-score ranges; predictive-check summaries can expand grouped DFF-cell
  and observed sparse-design-block rows; calibration summaries now cover
  expected-score rows and all ordinal category-probability rows in one report;
  GMFRM/MGMFRM preview and guarded-fit simulation/recovery helpers now cover
  raw and constrained direct candidate coordinates without broad public
  generalized fitting]
- Add multiple credible intervals, probability of direction, and ROPE summaries.
  [Done for `posterior_summary`; focal [`dff_report`](@ref) rows now include
  optional estimand-specific practical-magnitude probabilities when expected-score
  or logit thresholds are declared]
- Add PSIS-smoothed or exact/K-fold LOO and prior/likelihood sensitivity.
  [Raw importance-sampling LOO, PSIS-smoothed LOO, and Pareto-k diagnostics are
  available for the current minimal fit path, guarded generalized fit objects,
  and guarded generalized preview-design raw/direct pointwise likelihood
  matrices. [`loo_refit_plan`](@ref) constructs deterministic
  one-observation-heldout plans for exact LOO follow-up from selected
  observations or Pareto-k flagged raw LOO rows, [`loo_refit`](@ref) executes
  those exact one-row refits for fit-supported MFRM/RSM/PCM specs and guarded
  experimental GMFRM/MGMFRM specs after coverage diagnostics pass, and
  [`kfold_plan`](@ref) now constructs deterministic observation-level or grouped
  heldout fold plans,
  [`kfold_plan_diagnostics`](@ref) checks heldout-only fold levels before
  refits, [`kfold_refit`](@ref) executes fit-supported MFRM/RSM/PCM heldout
  folds and explicit guarded GMFRM/MGMFRM folds automatically,
  [`loo_refit_comparison`](@ref) and
  [`kfold_refit_comparison`](@ref) run shared exact/K-fold refit plans across
  multiple fit-supported or explicitly guarded experimental candidates,
  `kfold` plus [`kfold_diagnostics`](@ref)
  record supplied heldout refit log-likelihood rows, [`compare_kfold`](@ref) summarizes same
  heldout-observation and fold-assignment comparison contracts, and
  [`kfold_sensitivity_comparison`](@ref) records baseline-relative K-fold
  sensitivity rows for supplied external summaries.
  [`prior_likelihood_sensitivity`](@ref) records local self-normalized
  importance-reweighting grids over prior and likelihood powers. Broader
  production refit-management workflows remain planned.]
- Add first-class sensitivity comparisons for threshold, discrimination, DFF,
  anchor, dimensionality, and prior choices. [`sensitivity_comparison`](@ref)
  now provides same-data, fit-object sensitivity rows with declared axes,
  custom axis values, baseline-relative differences, and declared
  dimensionality/Q sensitivity safeguards; [`kfold_sensitivity_comparison`](@ref)
  provides the same sensitivity-row shape for supplied heldout K-fold summaries.
  [`sensitivity_comparison_summary`](@ref)
  audits required threshold, discrimination, rater-pooling, DFF, anchor,
  dimensionality, and prior-regime row coverage; unsupported generalized, DFF,
  anchor, and dimensionality refit orchestration remains planned.

### v0.5 Practitioner Outputs

- Add fair averages, expected-score summaries, infit/outfit, residuals,
  separation/reliability, rater diagnostics, Wright-map data, DFF reports, and
  anchoring/linking diagnostics. [`fair_average_summary`](@ref) provides
  posterior fair-average expected-score intervals for person, rater, or item
  reports using a balanced reference grid,
  [`separation_reliability_summary`](@ref) provides posterior separation and
  empirical reliability intervals for person, rater, and item measures,
  [`rater_diagnostics`](@ref) combines rater severity, observed category-use,
  range/centrality, residual, and available discrimination diagnostics,
  [`wright_map_data`](@ref) returns backend-independent posterior facet-measure
  and item-threshold position rows for Wright-map-style displays,
  [`dff_report`](@ref) returns declared or ad hoc DFF screening rows with
  expected-score interaction residuals and local logit-scale approximations,
  [`fit_stats`](@ref) provides posterior infit/outfit rows,
  [`facets_report`](@ref) / [`facets_compatibility_stats`](@ref) provides separately labelled
  unit-weighted posterior-mean plugin rows with Wright--Masters fourth-moment
  df and capped Wilson--Hilferty ZSTD for MFRM/RSM/PCM fits only, and
  [`residual_summary`](@ref) now provides observation- or facet-level
  expected-score and residual intervals with residual-screening caveat flags.
  [`anchor_linking_summary`](@ref) adds declared hard/soft anchor review rows,
  anchor target checks, rater-linking connectedness diagnostics, and optional
  anchor-axis sensitivity coverage summaries, while retaining the caveat that
  it is not an anchor refit or linking-constant estimator.
  [`rating_design_audit`](@ref) adds report rows for observed graph
  connectedness, rater links, anchors, complete-grid coverage, repeated
  ratings, sparse person-rater-item blocks, optional time/order metadata, and
  nonignorable rater-assignment interpretation limits.

### v0.6 Validation Evidence

- Build simulation grids and real-data case studies, including parameter
  recovery, interval coverage, calibration, predictive checks, and decision
  stability. [`simulation_grid`](@ref) and
  [`simulation_grid_summary`](@ref) now predeclare and check the density,
  anchor-size, ratings-per-target, category-pathology, rater-noise, DFF,
  dimensionality, and misspecification axes. A deterministic validation-plan export
  now turns those controls and the falsification-rule contract into a
  deterministic JSON plan artifact; it still does not run simulations or fit
  models.
- Predeclare falsification conditions for sparse Bayesian MGMFRM claims.
  [`falsification_rules`](@ref) and
  [`falsification_rule_summary`](@ref) now define and check required rule
  domains for sparse hierarchical-prior stability claims before those claims
  are interpreted.
- Compare against Stan and overlapping MFRM tools.
  [`comparison_evidence_row`](@ref) and
  [`comparison_evidence_summary`](@ref) now record precomputed faithful
  Stan/BridgeStan, overlapping R/frequentist, and simpler nested-model
  comparison evidence and check required comparison-class coverage. They do not
  run external tools or refit models.
- Record idle-machine repeated benchmarks.
  [`benchmark_result_row`](@ref) and [`benchmark_summary`](@ref) now record
  supplied repeated timings with median/IQR elapsed time, ESS/sec,
  time-to-quality threshold checks, and Stan/Julia ratio rows. They do not run
  benchmarks.
- Archive full and fast reproduction artifacts. [`fit_reproduction_manifest`](@ref)
  now audits full rerun and fast cached-draw paths together for the current fit
  artifact/cache/report-bundle surface and rejects mismatched fit-cache records
  before marking fast cached-draw reproduction ready. [`release_scope_summary`](@ref)
  now exposes those fit-cache, reproduction, and Documenter HTML page-size
  guardrails as local evidence rows without broadening public generalized claims,
  and records the release-verification gate as the registry-update readiness
  boundary.

## Completed 30-45 Day Sprint Record

This section is retained as the completed sprint record for guarded scalar
GMFRM and fixed-Q confirmatory MGMFRM exposure work. Broader stable-public claims
and release actions remain governed by the release-scope and independent scope-review
gates above.

1. Split the scalar GMFRM experimental candidate from source-fixture helper logic
   into an internal fit-ready compiler path with generated raw blocks,
   constrained blocks, transforms, constraints, and prior-policy rows.
   [Initial manifest split done]
2. Extend BridgeStan fixtures to the fit-ready scalar GMFRM candidate and
   compare raw log density, raw gradient, constrained direct parameters,
   pointwise log likelihood, and total likelihood. [Done for scalar GMFRM]
3. Replace smoke-only HMC evidence with a tiny predeclared candidate-chain
   study that records divergences, max-depth hits, E-BFMI, raw/direct R-hat,
   raw/direct ESS, direct constraint failures, and pointwise finiteness.
   [Done for the local two-fixture scalar GMFRM study]
4. Decide whether a guarded scalar GMFRM entry point, such as
   `fit(spec; experimental = true)`, can be exposed; if any source, transform,
   Stan, HMC, recovery, or documentation check fails, keep it internal.
   [Current decision: enable guarded experimental for scalar GMFRM; local
   interval/decision, sparse-design,
   WAIC influence, raw importance LOO/Pareto-k, deterministic K-fold refit,
   guarded-exposure review, guarded fit API dry-run, and guarded method-wiring
   artifacts plus experimental fit validation-grid and posterior predictive
   evidence plus sparse-pathology recovery and prior/likelihood sensitivity
   evidence plus a compact real-data case study, local claim-level archive,
   broader exposure decision review, and MGMFRM sparse recovery evidence
   plus DFF estimand/validation, Gate E manuscript-scale evidence, and local
   full-paper reproduction archive recorded; broader exposure remains blocked
   by public-scope release review]
5. Predeclare the first scalar GMFRM simulation grid and recovery criteria.
   [Initial full-crossed recovery smoke artifact, same-observation baseline
   comparison, three-scenario baseline/calibration grid, interval/decision
   grid, scalar sparse-design grid, WAIC influence review, raw importance
   LOO/Pareto-k review, deterministic K-fold refit review, guarded fit API
   dry run, guarded method wiring, experimental fit validation grid, and
   posterior predictive grid, sparse-pathology recovery grid, and
   prior/likelihood sensitivity grid plus compact real-data case-study, local
   claim-level archive, broader exposure decision-review evidence, local
   confirmatory MGMFRM sparse-recovery evidence, MGMFRM guarded fit
   method-wiring, validation-grid, API dry-run, public-exposure review,
   prediction/model-weight policy, DFF estimand/validation evidence, Gate E
   manuscript-scale evidence, and local full-paper reproduction archive done;
   broader generalized claims still need a public-scope release decision]
6. Freeze the first MGMFRM candidate as confirmatory: fixed Q-mask, fixed
   latent identity correlation, documented ability scale, and explicit
   sign/positivity rules. [Initial internal gauge manifest and fit-ready
   candidate transform manifest done; confirmatory BridgeStan oracle, local
   candidate-chain/recovery-smoke studies, guarded fit method-wiring,
   validation-grid, API dry-run, public-exposure review, prediction/model-weight
   policy, caveat docs, and fit-artifact contract done for the guarded fixed-Q
   experiment]
7. Keep the selected compact real rater-mediated case-study licensing or
   anonymization record synchronized with any publication-facing archive.
   [Done: [`case_study_provenance_manifest`](@ref) now records source
   licensing/anonymization status and syncs it to local claim-level,
   manuscript-scale, and full-paper archive rows without granting a license or
   performing publication/registration actions.]

## Current Risks

| Risk | Response |
| --- | --- |
| Direct-prior ambiguity | Keep priors on raw coordinates and block public direct-prior API. |
| Scalar GMFRM HMC pathologies | Tune parameterization, strengthen priors, or keep GMFRM internal. |
| MGMFRM gauge confusion | Restrict v1 to confirmatory Q-mask and fixed identity correlation. |
| Sparse-design overclaim | Narrow claims, add warnings, or require stronger validation. |
| Local-dependence mechanism confusion | Compare person-by-testlet, rater-by-response halo, rater-by-task, multidimensional, and sequence generators; keep the effect diagnostic until cluster prediction and known-truth separation pass. |
| BridgeStan drift | Treat Julia/Stan fixture disagreement as a release blocker. |
| Documentation drift | Require synchronized README, docs, manifest, and roadmap status updates. |

## Red Lines

- Do not add per-rater thresholds without hierarchical pooling and explicit
  warnings.
- Do not report LOO model weights without Pareto-k diagnostics and a prediction
  target statement.
- Do not call a DFF contrast unfairness without practical magnitude and model
  checking.
- Do not use single-run timings as manuscript evidence.
- Do not interpret the observed rating graph as random rater assignment unless
  the design or assignment model justifies that claim.
- Do not label residual association as a testlet, halo, or dimension effect
  without an identified competing-mechanism study.
- Do not use observation-row LOO as evidence for a wholly new response when a
  shared response/testlet effect was learned from other rows in that response.
- Do not automatically collapse sparse or disordered categories without a
  recorded analysis decision.
- Do not report partially pooled facet effects as unpooled facet locations.
- Do not export raw identifiers or row-level rating data in public artifacts by
  default.
- Do not claim broad or exploratory MGMFRM support, model-weight superiority,
  or sparse-design superiority from the guarded fixed-Q path until broader
  multidimensional fixtures, recovery/sensitivity evidence, and public-scope
  release review pass.
