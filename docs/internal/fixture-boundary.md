# Large-fixture boundary review

Reviewed 2026-09-05 against `bd22c01`. The [active roadmap](../../ROADMAP.md)
owns execution priority. This is a finite file-placement decision, not a new
scientific result, a signature validation, or a reason to regenerate evidence.

## Scope and result

The tracked `test/fixtures/` tree contains 123 files / 16,164,587 bytes,
including 108 JSON files. All **11 JSON files above 250 KiB** were reviewed;
they total 11,684,830 bytes (11.14 MiB). This does not classify the remaining
112 files or ignored local outputs, and does not imply an archive-size saving.

| Placement class | Result within these 11 files | Decision |
| --- | --- | --- |
| Required ordinary numerical oracle | 0 | Do not confuse this with smaller scalar/Stan and ConQuest fixtures, which retain ordinary checks |
| Standalone archive move with unchanged consumers | 0 | No no-change move candidate was found |
| Research evidence requiring consumer/provenance changes before a move | 11 | Retain current paths and bytes; reasons are enumerated below |

**No fixture, generator, numerical test, result, or digest was changed.** The
decision is to retain this batch, not to make a symbolic directory move that
requires copied fixtures, compatibility links, or an additional path resolver.

## Ordinary versus research consumers

The [ordinary fixture selector](../../test/runtests.jl#L420) returns an empty
path without research opt-in, even when a default file exists. Non-empty
explicit overrides without opt-in are rejected. The
[test-group contract](../../test/test_groups.jl) requires `all` when research
evidence is enabled. Relevant routes in the table are:

- **G**: generalized numerical checks use `optional_fixture_path`; seven files.
- **D**: design-robustness generation and checks are inside the explicit
  `RUN_RESEARCH_EVIDENCE_TESTS` block; one file.
- **L**: LD artifact/protocol/harness test files are included only with that
  flag; three files. The harness portability comparison in
  [CI](../../.github/workflows/CI.yml) is manual-dispatch only.

The ordinary core still reads top-level fixture JSON text for leaked `.jl:line`
locations. That privacy lint is **real byte I/O**, but not use of scientific
results as numerical oracles. The prior-sensitivity path also appears in
`src/facet_workflow.jl` as returned metadata and in ordinary string-contract
assertions; those references do not read its JSON payload. Do not claim that
ordinary tests never touch these files at all.

## File-by-file placement decisions

File links are the retained locations. Reader references are representative
direct consumers; archived JSON parents also retain path/hash records.

| File | Bytes / route | Coupling and disposition |
| --- | --- | --- |
| [existing_api_design_robustness_stress_grid.json](../../test/fixtures/existing_api_design_robustness_stress_grid.json) | 984,048 / D | Retain. Only its generator and research test directly reference the filename in executable code, but the generator's default-path write guard and the committed generator-SHA assertion make relocation non-mechanical; see the bounded candidate review below |
| [gmfrm_prior_likelihood_sensitivity_grid.json](../../test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json) | 518,470 / G | Retain. Referenced by real-data, manuscript-grid, guarded-review, and archive generators, plus returned package metadata. Six other tracked JSON files reference its filename |
| [local_dependence_calibration_scorer_preflight.json](../../test/fixtures/local_dependence_calibration_scorer_preflight.json) | 264,118 / L | Retain. Consumed by the LD protocol generator and artifact checks; source/environment pins and three JSON parents must remain coherent |
| [local_dependence_pilot_protocol_preflight.json](../../test/fixtures/local_dependence_pilot_protocol_preflight.json) | 581,383 / L | Retain. Runner defaults, semantic-context loading, the harness, the canonical smoke receipt, and four JSON parents depend on it. A move must not imply readiness to execute LD1b |
| [local_dependence_pilot_batch_execution_harness.json](../../test/fixtures/local_dependence_pilot_batch_execution_harness.json) | 3,692,236 / L | Retain. Research harness tests, manual Windows portability CI, and two archive JSON parents reference it; moving only the JSON breaks that comparison path |
| [mgmfrm_heldout_prediction_execution.json](../../test/fixtures/mgmfrm_heldout_prediction_execution.json) | 444,077 / G | Retain. Input to heldout/refit planning and scoring; seven JSON parents reference it. Preserve the linked execution/scoring history |
| [mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json](../../test/fixtures/mgmfrm_full_heldout_mcmc_refit_candidate_batch_scoring.json) | 785,178 / G | Retain. Anchor scoring, manuscript aggregation, and the full-paper archive consume it; three JSON parents reference it |
| [mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json](../../test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json) | 581,825 / G | Retain. Publication-grade gate, pilot plan/harness, manuscript aggregation, and five JSON parents depend on this score record |
| [mgmfrm_publication_grade_refit_batch_expansion_plan.json](../../test/fixtures/mgmfrm_publication_grade_refit_batch_expansion_plan.json) | 1,514,052 / G | Retain. Batch-runner defaults, smoke/well-specified reviews, result review, and five JSON parents reference the execution plan |
| [mgmfrm_publication_grade_refit_batch_results_review.json](../../test/fixtures/mgmfrm_publication_grade_refit_batch_results_review.json) | 1,658,108 / G | Retain. Model-weight policy tests are research-gated; threshold-policy/external-construct generators and three JSON parents consume the result |
| [mgmfrm_tam_direct_agreement_multireplication.json](../../test/fixtures/mgmfrm_tam_direct_agreement_multireplication.json) | 661,335 / G | Retain. TAM policy/audit/review, broader/guarded exposure, and seven JSON parents use this overlap result; no external agreement is re-established by this inventory |

The JSON-parent counts come from literal filename matches in other tracked
fixture JSON files, excluding the file itself. They are direct references, not
complete transitive dependency counts or proof that every field is read on
every invocation. Before an eventual move, trace the candidate's complete
consumer path rather than using these counts as an automatic migration rule.

## Bounded candidate review and next action

The design-robustness grid was the smallest dependency boundary among the large
files: no other tracked JSON directly names it. However:

1. Its [generator](../../scripts/generate_existing_api_design_robustness_stress_grid.jl)
   defines the current path as `DEFAULT_OUTPUT`; `resolves_to_default_output`
   rejects executed fits that could overwrite the deterministic fixture.
2. The research test reads that path, tests the overwrite rejection, and checks
   the committed `generator.source_sha256` against the generator's current bytes.
   Changing the default path alone therefore invalidates that assertion.
3. The artifact also records the prerequisite-plan hash and source/environment
   provenance. Rewriting these solely for directory cosmetics would create new
   historical evidence without a changed scientific question.

Retain the grid until a substantive generator change or measured distribution
benefit justifies migrating its output/protection/reproduction contract as one
bounded change. Do not weaken overwrite checks or replace frozen provenance
with current hashes to make a move pass. The other ten files need coordinated
consumer-batch review; do not relocate them individually.

The next boundary task is to classify the remaining tracked fixtures by their
actual ordinary versus research consumers, starting with the small numerical
oracles that must remain. Reuse the [fixture guide](../../test/fixtures/README.md)
and current test routing. A reviewed retain decision closes a file-placement
question; it is not a blanket approval of the whole package/research layout.

## Verification and limits

- Read-only tracked-file size scan; filename references across source,
  scripts, tests, CI, and documentation; research guards and the candidate's
  overwrite/source-pin path were inspected.
- A stdlib-only probe evaluated the current `optional_fixture_path` definition
  for all 11 paths with opt-in off/on, absent overrides, explicit overrides,
  and empty overrides: 66 assertions passed on Julia 1.12.5. The probe did not
  read JSON payloads or launch research tests. Inspection of JSON metadata for
  this inventory was a separate read-only action.
- No MCMC, fixture regeneration, source-pin refresh, deletion, relocation,
  independent review, or scientific-denominator change was performed. This
  is a static consumer review plus a selector check, not a whole-program
  dynamic file-access trace.
