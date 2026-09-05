# Fixture boundary review

Reviewed 2026-09-05 against `fa7ffc9`; the large-file size baseline is
`bd22c01`. The [active roadmap](../../ROADMAP.md)
owns execution priority. This is a finite file-placement decision, not a new
scientific result, a signature validation, or a reason to regenerate evidence.

## Scope and result

At `bd22c01`, the tracked `test/fixtures/` tree contains 123 files /
16,164,587 bytes, including 108 JSON files. All 123 files are now classified:
**23 ordinary-test references, 99 research records, and one guide**. The
subsequent guide edit changes total bytes, not fixture membership or data.
Ignored local outputs are outside this review; no archive-size saving is claimed.

The **11 JSON files above 250 KiB** total 11,684,830 bytes (11.14 MiB) and
are a subset of the 99 research records, not an additional class.

| Placement class | Result within these 11 files | Decision |
| --- | --- | --- |
| Required ordinary numerical oracle | 0 | Do not confuse this with smaller scalar/Stan and ConQuest fixtures, which retain ordinary checks |
| Standalone archive move with unchanged consumers | 0 | No no-change move candidate was found |
| Research evidence requiring consumer/provenance changes before a move | 11 | Retain current paths and bytes; reasons are enumerated below |

**No fixture, generator, numerical test, result, or digest was changed.** The
decision is to retain this batch, not to make a symbolic directory move that
requires copied fixtures, compatibility links, or an additional path resolver.

## Complete tracked-file partition

Paths below are relative to `test/fixtures/`. Patterns describe the reviewed
revision only, not a rule for classifying future files. Counts are disjoint;
the existing [fixture guide](../../test/fixtures/README.md) owns the longer
artifact descriptions and reproduction commands.

| Membership | Files / bytes, excluding guide bytes | Actual consumer and retain decision |
| --- | --- | --- |
| `scalar_validation_{known_value,medium_known_value,stan_logdensity,medium_stan_logdensity}.json` | 4 / 14,420 | Ordinary `fitting_core`: analytic log-density/gradient checks and two frozen Stan comparisons. Keep these numerical oracles; ordinary checks do not launch Stan |
| All files in `conquest_5_47_5/` | 18 / 47,435 | Ordinary `fitting_reports`: parser, constraint reconstruction, history, manifest/receipt identity, and byte-integrity checks. Keep the complete version-specific bundle, including the two deliberately empty labels files; no licensed ConQuest execution is needed |
| `local_dependence_known_truth_preflight.json` | 1 / 92,011 | Ordinary `local_dependence_core`: the committed generator-contract test reads its scenario roster, claim boundaries, provenance shape, and canonical content hash. Retain as a behavioral reference, **not** a recovery/calibration result |
| All top-level `gmfrm_*.json`; all `mgmfrm_*.json` except the two indirect records below; both `source_*_bridge_logdensity.json` | 90 / 10,307,420 | 24 GMFRM + 64 MGMFRM + 2 source-bridge records. Each has a direct optional selector and a nonempty-path guard in the core design test. Retain for opt-in research checks; the source bridges also check the default Stan source's presence |
| `existing_api_design_robustness_{plan,stress_grid}.json` | 2 / 1,008,989 | Explicit research block in `fitting_core`. Preserve the linked plan/grid and protected generator defaults |
| `local_dependence_{calibration_scorer_preflight,pilot_protocol_preflight,pilot_batch_execution_harness,pilot_bounded_canonical_smoke_receipt}.json` | 4 / 4,559,713 | Research-only LD includes, runner/protocol inputs, and archive references. Keep the source-pinned chain and immutable canonical-smoke receipt; ordinary LD generator tests do not consume these four as result oracles |
| `mgmfrm_manual_public_scope_review_for_fit.json`; `mgmfrm_tam_direct_agreement_policy_refinement_execution_snapshot.json` | 2 / 73,837 | Indirect research inputs, not direct optional-selector entries. Threshold/external-scope reviews read/hash the former; TAM aggregation/audit/review and reproduction archives retain the immutable latter. Neither is an unreferenced orphan |
| `mgmfrm_tam_overlap_baseline.csv` | 1 / 7,044 | Research TAM baseline checker reads its 800 observations plus header and checks its digest; execution-review checks also hash it. Keep beside the baseline JSON; CSV is not read by the ordinary JSON privacy lint |
| `README.md` | 1 / not frozen | Maintained guide; not a numerical oracle. Historical research archives may record an older guide hash; documentation edits do not authorize updating those records |

Thus the remaining 112 files add 23 ordinary references, 88 research records,
and one guide to the earlier large-file review. Of the 108 JSON files, ten
belong to ordinary references and 98 to research records. Ordinary references
total 153,866 bytes; research records total 15,957,003 bytes, excluding the guide.

The ordinary ConQuest consumers are in
[the bridge tests](../../test/facets_conquest_bridge.jl#L1085); the LD exception
is explicit in [the committed preflight test](../../test/local_dependence_simulation.jl#L792).
The latter checks 22 stored scenarios but does not refit them or estimate an
error rate. These actual consumers, not size or a `local_dependence_` prefix,
are why those files remain ordinary dependencies.

## Ordinary versus research consumers

The [ordinary fixture selector](../../test/runtests.jl#L420) returns an empty
path without research opt-in, even when a default file exists. Non-empty
explicit overrides without opt-in are rejected. The
[test-group contract](../../test/test_groups.jl) requires `all` when research
evidence is enabled. Routes in the large-file table below are:

- **G**: generalized-topic checks in the core design test use
  `optional_fixture_path`; seven large files. This is not the CI shard named
  `generalized`.
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

The tracked-fixture classification is complete at the reviewed revision. Do
not repeat it unless membership or consumers change. Next inspect which
research-related modules are loaded by the package and ordinary test runner,
and whether each inclusion has a shipped behavioral purpose. That code-load
boundary, optional dependencies, and distribution budgets remain separate
decisions. Retaining the 99 research records assigns an archival role; it does
not establish that all of them must ship in a future package distribution.

## Verification and limits

- Read-only tracked-file size scan; filename references across source,
  scripts, tests, CI, and documentation; research guards and the candidate's
  overwrite/source-pin path were inspected.
- The complete partition was checked against `git ls-files test/fixtures`:
  123 entries, no omissions or overlaps. All 90 direct optional-selector paths
  exist and their check calls have nonempty-path guards. This is a finite
  source review, not a general static dependency analyzer.
- The earlier large-file selector probe passed 66 assertions on Julia 1.12.5.
  The expanded probe reuses the actual `optional_fixture_path` definition for
  all 90 direct optional paths, with opt-in off/on and absent, explicit, or
  empty overrides: 540 assertions passed on both Julia 1.10.8 and 1.12.5.
  Selector probes do not read research JSON payloads or launch research tests.
- Existing scalar/Stan-pair checks passed 45 assertions, and the existing LD
  committed-preflight test passed 49, on both Julia 1.10.8 and 1.12.5. The full
  bridge test file passed 504 assertions on macOS / Julia 1.12.5, using a fake
  executable for its runner checks, not licensed ConQuest. Its platform-specific count must
  not replace the 492-assertion Linux CI count.
- All 122 fixture data files are byte-identical to `fa7ffc9`; only the guide
  changed within `test/fixtures/`. No stored history was regenerated.
- No MCMC, fixture regeneration, source-pin refresh, deletion, relocation,
  independent review, or scientific-denominator change was performed. This
  is a static consumer review plus a selector check, not a whole-program
  dynamic file-access trace.
