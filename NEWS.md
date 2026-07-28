# BayesianMGMFRM.jl release notes

## 0.1.2 (unreleased)

### Added

- Add `BayesianMGMFRM.Experimental` as the explicit namespace for the
  documented scalar rater-consistency GMFRM and fixed-Q confirmatory MGMFRM
  configurations. These configurations can be fitted with
  `BayesianMGMFRM.Experimental.fit`; they are not part of the stable fitting
  surface and do not imply broader MGMFRM support.
- Add an experimental two-dimensional free-latent-correlation density with
  transformed-state and finite-difference gradient diagnostics. It has no
  fitting or cache path and does not change the stable MGMFRM surface.
- Add local-dependence known-truth simulation, calibration-scorer validation,
  and pilot-plan preflight APIs. The pilot and evaluation remain unrun, and
  clustered effects remain unsupported for fitting.
- Add the strict LD1b1 canonical single-job worker and controller-owned
  reservation -> owner -> launch -> exit receipt protocol, including
  reservation-before-precommit and launched-attempt recovery. Five terminal
  statuses and two reserved nonterminal artifact failures publish exact
  source/evidence/result transactions without running the official pilot.
- Add an ordered seven-source LD1b1 executor pin to the protocol. The controller
  compares every recorded SHA-256 with the repository files before deriving
  authorization, harness, all 660 command, and checkpoint identities. This
  plus the final successful verification-only bounded canonical smoke advances the
  local `v0.1.2` integration checklist to `7/9` (`77.8%`), with Gates 3--7
  still pending tracked release-lineage verification. The smoke ran canonical
  row 5 with 4 chains, 500 warmup and 500 retained iterations per chain in a
  separate denominator-ineligible namespace. Gate 8, independent pinned
  recovery/readiness review, is the only remaining pre-pilot blocker, so
  operational readiness remains false and the official pilot remains `0/660`.
- Add report-only testlet-design and local-dependence diagnostics, including
  predictive standardized residuals and explicit structural-support checks.
  These diagnostics do not establish a cluster effect or calibrated decision.
- Add an anchor-declaration preflight that validates candidate provenance and
  the proposed affine hard-anchor strategy without performing a constrained
  refit.
- Add FACETS and ACER ConQuest migration guidance plus deterministic offline
  bridge bundles for the narrow unanchored, unit-weighted MFRM/RSM/PCM overlap.
  External executables and licences are not distributed with the package.
- Add MFRM category-functioning and rater-homogeneity summaries with explicit
  uncertainty and design-support fields.

### Changed

- Disambiguate the external-construct review, attachment-intake, request-packet,
  and reproduction-archive `passed` fields as contract/blocker-preservation
  checks, while exposing fail-closed attachment, integrity, evidence,
  independent-review, and public-claim-release gates separately.
- Use rank-normalized split R-hat, bulk ESS, and tail ESS as the primary MCMC
  diagnostics while retaining classical R-hat and ESS as compatibility fields.
  E-BFMI thresholds apply only when every expected chain supplies a finite
  value.
- Strengthen semantic identity checks for encoded data, specifications,
  compiled designs, fit caches, and reproducibility records so stale or
  incompatible inputs fail before numerical work.
- Add explicit reader-facing public projections for model manifests, fit
  metadata and diagnostics, comparison/simulation summaries, fit artifacts,
  and fit-reproduction manifests while retaining the complete view as the
  compatibility default for private reproduction archives.
- Clarify the boundary between stable MFRM/RSM/PCM fitting and the executable
  but provisional generalized configurations in the experimental namespace.
- Improve performance of the experimental two-dimensional correlation
  likelihood by caching its fixed simple-Q layout. The effect is
  workload- and environment-dependent; no general speedup is guaranteed.
- Focus the public manual and release notes on user-visible behavior, supported
  configurations, and scientific limitations rather than repository execution
  bookkeeping.

### Fixed

- Correct the unexecuted LD1b1 pilot contract from the unsupported MFRM
  `ad_backend = :analytic` route to `:ForwardDiff`, and make protocol
  authorization check the MFRM sampler, algorithm, and gradient route in
  addition to downstream diagnostic capabilities. An isolated full-control
  wiring run selected the smallest supported-pair row for the subsequent sealed
  canonical smoke; neither run is a pilot outcome, and the pilot remains unrun.
- Make LD1b1 execute modes require an explicit conjunctive operational-
  readiness gate and fail before attempt-root creation. A runner file alone no
  longer marks the execution plan complete.
- Add create-new LD1b1 completed-attempt seals. Result-only attempts remain
  partial, while semantic result validation plus a matching seal is required
  for terminal-denominator admission; post-seal mutation and duplicate
  publication fail closed. The bounded smoke now passes locally; an independent
  pinned recovery-control review remains an unsatisfied pre-execution gate.
- Require a public-schema calibration result row for every existing LD1b1
  terminal status, including generation, fit, and diagnostic failures, and add
  a mixed-status public-constructor denominator test.
- Reconstruct LD1b1 generation-failure calibration rows from the frozen public
  660-row plan, pin the semantic-validator source in execution identity, and
  reject archived rows that differ from the sole public canonical result even
  when surrounding archive hashes are coherently republished.
- Require context-bound canonical public calibration replay for all five LD1b1
  terminal statuses, including revalidation of the protocol file identity and
  exact comparison of the complete 660-row plan and public preflight; require
  exact completed pair/family/global diagnostic linkage, and reject the
  reserved nonterminal `sampler_diagnostics_unavailable`
  and `final_calibration_serialization_failed` codes from canonical runner
  validation for completed seal and terminal admission.
- Split interrupted-attempt retirement slot identity from scientific
  contribution and harden create-new publication across pre-link,
  post-link/pre-unlink, and post-unlink crash windows.
- Add strict LD1b1 owner, child-launch, child-exit, and stopped-process review
  artifacts; bind the review to the actual attempt inventory, optional result
  SHA-256, semantic result classification, and retirement reason. Integrate
  `retire-interrupted` with the scanner and checkpoint state while keeping a
  retired primary missing from the scientific numerator. Controller-owned
  execute-path receipt binding and reservation-before-precommit recovery now
  pass local MCMC-free tests; bounded smoke passes in the local worktree, while
  independent review and tracked release-lineage verification remain pending.
  No pilot job or official pilot MCMC has been executed, so the scientific
  count remains `0/660`.
- Record two earlier verification-only smoke plans that failed closed before
  `job_result` or evidence publication: one exposed a native-`UInt64` JSON
  projection bug and one exposed a String-key lineage bug. Both defects were
  fixed and regression-tested before the first successful canonical smoke; the
  failed plans and every verification smoke contribute zero scientifically.
- Make tracked MCMC-free LD1b1 harness generation explicitly use
  `consume_bounded_smoke_receipt = false`. The harness is byte-identical before
  and after a local raw receipt (SHA-256
  `1afde641277e2219d4f0bbdb8a2665201876ff1f34a97b29a81a5adb67dd363d`).
  Archive the earlier successful smoke plan `d4c6ed67958f47094efb68d4995b75846866f8c41f5d6c1d89687ac19ddd06c8`
  after discovering that it had influenced the tracked dry-run harness. Because
  the portability fix changed the pinned source, rerun smoke plan
  `d2d7169629d21a5ff49d35eeafac30bc5a342cc699b0029b9cfbf1c9366f8119`.
  A later clean `Pkg.test()` exposed `Sockets` missing from test extras; add it
  to the test target with a compatibility bound. That Project-only hash change
  archives the `d2d716…` receipt and requires smoke plan `7c8e49…`. Clean
  testing then identifies the known-truth fixture's Project SHA as stale;
  regenerate the known-truth -> scorer -> protocol chain and the Julia 1.10.8
  robustness fixture, archive `7c8e49…`, and rerun final smoke plan
  `4e32bbbaae5dafda795ccca1ddaf819cc1bd715568206134278a878f8c8b19a9`
  under unchanged source pin
  `781bb1aebfda5c16c662b60939a33bde97664cdce6f385ea7bddb25a72353793`
  and parent plan `197d91c65b89b669dcff6a0813b73f727acf57da90191fbda56c497a05544329`;
  the final receipt SHA-256 is
  `de7f1ffab4002e99b75c86d64efbe73deca695b97ac45b0cf177afa5398b58c3`.
- Preserve native `UInt64` LD1b1 data signatures as canonical decimal strings
  before JSON hashing, require the same signature at every fit-artifact and
  calibration lineage path, and reject JSON numbers or noncanonical strings.
- Make generalized numerical paths and diagnostic quality gates fail closed on
  inconsistent design identity, unsupported options, incomplete chain-level
  diagnostics, or incompatible cached records.
- Harden FACETS/ConQuest transfer validation, returned-file checking, and the
  version-specific ConQuest semantic reader without claiming product
  equivalence or independent replication.
- Bind local-dependence evidence identity to the tracked Julia 1.10 manifest so
  fresh checkouts and Windows runners verify the same minimum-version lockfile.

## 0.1.1

### Added

- Add `facets_report`, with `facets_compatibility_stats` as an alias, for
  explicitly approximate MFRM/RSM/PCM infit, outfit, degrees-of-freedom, and
  standardized-fit rows.
- Add clearer reporting for the guarded experimental fixed-Q confirmatory
  MGMFRM path, covering Q validation, gauge choices, initialization, prior
  policy, sampler diagnostics, predictive checks, and portable Markdown
  reports.
- Add stricter reproducibility checks for fit caches, report bundles, content
  hashes, and full-versus-cached reproduction paths.
- Add `fit_report_public` and `fit_report(...; view = :public)` for a
  reader-facing structured report that can be saved as path-free JSON, table,
  Markdown, or bundle output.
- Add automated reader-facing language checks for exported docstrings,
  representative displays and errors, and public report artifacts.
- Add a runnable guarded scalar GMFRM example alongside the minimal MFRM and
  fixed-Q confirmatory MGMFRM examples.

### Changed

- Unsupported generalized thresholds, discrimination choices, anchors, DFF
  terms, Q-matrix changes, backends, priors, and refit configurations now fail
  before numerical evaluation.
- User-facing experimental fit displays and errors now use reader-facing model
  language and actionable supported-configuration guidance.
- Refocus the published manual on installation, model scope, fitting,
  diagnostics, examples, and API reference.
- Reader-facing structured fit reports and human-readable report/dossier
  Markdown omit implementation details and machine-specific paths. Complete
  version-1 report payloads remain unchanged for compatibility. Public report
  hashes use JSON-normalized content so they remain stable after save/load,
  while user-supplied labels remain unchanged.

### Fixed

- Strengthen fixed-Q structural checks during held-out MGMFRM scoring while
  allowing a valid scoring slice to omit observations from another dimension.
- Prevent reviewed but failed evidence from being summarized as passing.
- Keep v0.1.0 report dossiers readable while converting loaded content to the
  portable reader-facing form.

## 0.1.0

- Initial registered release with long-format facet-data validation,
  MFRM/RSM/PCM design and Bayesian fitting, diagnostics, predictive checks,
  reporting artifacts, and opt-in scalar GMFRM and fixed-Q confirmatory MGMFRM
  experiments.
