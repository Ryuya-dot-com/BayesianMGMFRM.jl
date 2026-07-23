# Scope and Releases

`BayesianMGMFRM.jl` follows a conservative release policy: a model family is
documented as supported only when its likelihood, parameterization, fitting
path, diagnostics, and user-facing examples are covered together.

## Current Support

| Model surface | Status | Notes |
|:--|:--|:--|
| MFRM with rating-scale or partial-credit steps | Supported | Available through the documented design, fitting, diagnostic, and reporting workflow. |
| Scalar rater-consistency GMFRM | Experimental | Enter through `BayesianMGMFRM.Experimental`; the documented structural restrictions remain mandatory. |
| Fixed-Q confirmatory MGMFRM | Experimental | Enter through `BayesianMGMFRM.Experimental`; requires at least two dimensions and a fixed confirmatory loading design. |
| Broader generalized discrimination structures | Not supported | No stable fitting claim is made. |
| Exploratory or freely estimated multidimensional loading structures | Not supported | Confirmatory fixed-Q support does not imply exploratory MGMFRM support. |
| Group and differential facet functioning effects | Not supported for fitting | Design validation may describe these terms, but estimation is not yet exposed. |
| Testlet, response-cluster, and rater-halo effects | Not supported for fitting | Explicit identifiers, structural auditing, standardized residual inputs, LD1a known-truth simulation, the LD1b0 calibration scorer, the MCMC-free LD1b1 pilot execution-protocol preflight, and a batch execution-harness dry run are available; pilot execution, repeated calibration, and fitted cluster effects are not. |

Experimental features may change in a compatible minor release and should be
used with sensitivity checks. They must not be described as stable equivalents
of external software or as evidence for broader MGMFRM support.
The namespace boundary is an API quarantine rather than a maturity claim.
`BayesianMGMFRM.Experimental.surface_contract()` records its exact current
scope and promotion gates. The historical `experimental = true` keyword is a
compatibility route and does not define the forward-looking API.

The completed LD1a surface consists of a 22-scenario planning grid and an
independent ordinal known-truth generator. Its effect magnitudes are study-
local, and its ability-confounded no-drift and ability-informed-assignment
scenarios are design stress controls,
not a dynamic-rater model. LD1b0 defines the repeated-calibration scorer and
denominator rules. LD1b1 preflights a `30 × 22 = 660` execution matrix
containing 540 eligible jobs and 120 planned structural rejections, but runs no
fit or MCMC.
Rank-normalized R-hat and bulk/tail ESS are now available, so that execution
protocol is authorized under an exact dependency, operation-order, primary-
field, E-BFMI-coverage, and diagnostic-source-hash contract. Authorization
does not mean that the pilot has been run. The 50- and
100-replication evaluation sizes remain candidates to be selected and frozen
after the pilot and before evaluation. Repeated calibration, pairwise power,
diagnostic decisions, and mechanism interpretation remain unavailable.

The MCMC-free `local_dependence_pilot_batch_execution_harness.json` dry run
checks all 660 planned rows, deterministic plan and job identities, and the
contract requiring source-bound execution records and status-specific evidence
validation. Each role must bind one hashed source artifact and its exact
upstream evidence hashes. The frozen `pilot_contract` and ordered 660 job rows
must match canonical SHA-256 values. A `pre_fit_rejected` record requires the
`generated_data` -> `structural_rejection_audit` -> `calibration_row` chain,
with the last member following the existing public calibration-row contract.
Simulation response data, table columns, probability cells, truth and row-truth
arrays, and data/score/design signatures are validated. Fit evidence is a
structured `local_dependence_pilot_fit_artifact_export.v1` JSON wrapper
containing retained draws, log posterior values, and sampler statistics. Its
package-native content hash must be verified by the future pinned canonical
executor before JSON projection; the batch runner separately recomputes the
canonical JSON payload hash and verifies the exact file SHA-256. The JSON
projection cannot soundly reconstruct the native typed hash. Fit, sampler,
local-dependence, and calibration members must agree on data, design, fit-
artifact, retained-draw, chain, and iteration provenance. The custom
`local_dependence_pilot_summary_bundle.v1` directly records the draw-selection
and posterior-predictive seeds; the runner compares both with its evidence
payload, the frozen job, and the calibration execution seeds. Draw selection
uses the frozen `sha256_seeded_rank_without_replacement_v1` algorithm, and the
runner recomputes its ordered draw indices from the frozen seed.
The posterior-predictive seed is source-bound, but seed-to-result replay
verification remains
pending the canonical single-job executor and bounded smoke review. A
`diagnostic_failed` record may name `sampler_quality_gate` only when that gate
failed, or `local_dependence_summary` only after the gate passed.
Frozen resource and sampler-quality conditions are checked explicitly, and
linked or unmanifested attempt files are rejected. The same contract preserves
nonoverwriting primary outcomes and additive remediation records. On resume,
the complete attempt archive is first
rescanned as the source of truth; the derived checkpoint is then verified and
compared, and only verified terminal primary records are skipped. Because the
generated dry run does not scan an attempt archive, archive integrity is not
assessed. Static snapshot and inventory checks are not an atomic completed-
attempt seal. The canonical single-job executor, bounded smoke review,
completed-attempt seal, and append-only recovery or retirement path for
interrupted attempts remain execution prerequisites, so the pilot cannot yet be
started from the repository. No response data are generated, no model is
fitted, and no MCMC is run; pilot results, calibration or power estimates,
diagnostic decisions, and mechanism interpretations remain unavailable.
Controlled benchmark-response placement across a rating sequence remains a
separate temporal-identification study.

## Release Direction

- The `0.1.x` series prioritizes reliability, diagnostics, reproducible reports,
  and clearer separation between stable and experimental functionality.
- A future minor release may stabilize a narrowly defined fixed-Q generalized
  subset only after implementation, inference, documentation, and independent
  validation checks all pass.
- Broader generalized, exploratory multidimensional, and differential facet
  functioning models remain later research and implementation work.
- External validation and publication claims are evaluated separately from
  package-version readiness.

The registered release remains the default installation. Development versions
may contain unreleased behavior and should be pinned to an explicit revision
when used in reproducible work.
