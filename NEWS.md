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
  and a fixed 660-job pilot-plan check. The pilot and evaluation remain unrun,
  and clustered effects remain unsupported for fitting.
- Add report-only testlet-design and local-dependence diagnostics, including
  predictive standardized residuals and explicit structural-support checks.
  These diagnostics do not establish a cluster effect or calibrated decision.
- Add `model_surface_check`, `rating_design_check`, `testlet_design_check`, and
  `local_dependence_calibration_pilot_check` as reader-facing validation APIs.
- Add anchor-declaration validation for candidate provenance and
  the proposed affine hard-anchor strategy without performing a constrained
  refit.
- Add FACETS and ACER ConQuest migration guidance plus deterministic offline
  bridge bundles for the narrow unanchored, unit-weighted MFRM/RSM/PCM overlap.
  External executables and licences are not distributed with the package.
- Add MFRM category-functioning and rater-homogeneity summaries with explicit
  uncertainty and design-support fields.

### Changed

- Make an explicit CmdStan fitting backend a required gate before stable
  promotion while keeping CmdStan an optional external runtime. Add a portable
  runtime/toolchain check and a direct CLI adapter for stable MFRM/RSM/PCM
  designs. The adapter compiles a package-owned Stan model, preserves the
  identified Julia parameter order, imports CmdStan sampler diagnostics, checks
  generated pointwise log likelihoods, and raises typed failures. Extend the
  same CLI path to both guarded generalized raw-coordinate targets, including
  their Julia identification transforms, common `GMFRMFit`/`MGMFRMFit`
  diagnostics, and prediction interfaces. MGMFRM remains fixed-Q and
  identity-correlation only. Cache integration and analysis-scale comparison
  evidence remain pending.
- Add a resource-bounded, opt-in AdvancedHMC/CmdStan validation runner covering
  stable MFRM, guarded scalar GMFRM, and guarded fixed-Q MGMFRM under fully
  crossed and connected sparse layouts. Its short-chain output is explicitly
  execution evidence, not backend-equivalence or parameter-recovery evidence.
- Add an analysis-facing roadmap program for unified sampler profiles,
  four-chain substantive defaults, chain-level seeds, integrated summaries and
  warnings, simple fit persistence, visualization rows, interval/HDI policy,
  prior predictive checks, bias analysis, and a guarded Bayes-factor boundary.
- Clarify that guarded scalar GMFRM fitting uses item/task discrimination
  multiplied by rater consistency with rater-specific step vectors, and expose
  this sharing structure plus the computational sampler defaults in the
  experimental surface contract.
- Extend `q_matrix_validation` with generic zero-pattern structural rank,
  person-specific dimension-support rows, pure-item counts, and an explicit
  standard-normal/identity-correlation prior-anchor record. Structurally
  rank-deficient Q patterns now fail before fitting; person-level support gaps
  and pure-item gaps remain guarded warnings and block the conservative stable-
  structure screen.
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
- Keep the earlier validation function names available for compatibility while
  documenting the new reader-facing check names.
- Clarify the boundary between stable MFRM/RSM/PCM fitting and the executable
  but provisional generalized configurations in the experimental namespace.
- Share the guarded GMFRM/MGMFRM AdvancedHMC execution and diagnostic-table
  aggregation through typed shared implementation helpers. Family-specific
  direct transforms, constraint checks, MGMFRM initialization/invariance
  policy, and public result schemas remain explicit in their family wrappers.
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
  addition to downstream diagnostic capabilities. The plan check itself does
  not run the pilot or contribute a scientific outcome.
- Preserve the full 660-job denominator across planned rejection, generation
  failure, fit failure, diagnostic failure, and completed outcomes.
- Preserve native `UInt64` LD1b1 data signatures as canonical decimal strings
  before JSON hashing, require the same signature at every fit-artifact and
  calibration lineage path, and reject JSON numbers or noncanonical strings.
- Make generalized numerical paths and diagnostic quality gates fail closed on
  inconsistent design identity, unsupported options, incomplete chain-level
  diagnostics, or incompatible cached records.
- Narrow table-column fallback handling to lookup failures raised by
  `getindex`; errors while materializing a returned column now propagate
  unchanged. Generalized experimental-fit capability and specified-only MFRM
  preview layout selection now use explicit status/branch logic instead of
  treating broad `ArgumentError`s as control flow.
- Reject malformed, non-authorizing, cross-ledger, or result-mismatched
  free-correlation study authorization artifacts instead of silently treating
  them as absent; truly absent authorization remains a visible protocol
  violation for ledger checks.
- Keep evidence metadata usable when optional environment probes fail and
  expose concise collection status, stage, and reason records without leaking
  failed optional-command stderr into ordinary output. Its artifact policy now
  states explicitly that project/Git hashes are recorded only when available
  and that a package installation without a Git checkout is supported.
- Streamline the runnable fixed-Q MGMFRM example around data validation,
  fitting, diagnostics, posterior summaries, and posterior predictive checks.
- Run complete ordinary package coverage under Linux: once as a full suite on
  minimum Julia and through named current-Julia `core`, `fitting`,
  `local_dependence`, and `generalized` shards. Use focused package-load/
  validation/likelihood/minimal-fit smokes on macOS and Windows, remove
  duplicate digest execution, and stop making byte-exact legacy archive drift
  a normal release gate. Plain `Pkg.test()` still runs every ordinary group.
- Treat execution-environment SHA values as provenance rather than requiring
  every replicated free-correlation study unit to come from one machine, and
  run the 90 optional SHA-chained research fixtures only when
  `BAYESIANMGMFRM_RESEARCH_EVIDENCE_TESTS=true` is explicitly requested.
- Compute the free-correlation plan and unit-roster fingerprints from their
  semantic contents without comparing them with hard-coded source constants.
- Harden FACETS/ConQuest transfer validation, returned-file checking, and the
  version-specific ConQuest semantic reader without claiming product
  equivalence or independent replication.

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
- Fit reports now distinguish model exposure from report-generation health.
  Captured section errors produce `report_status = :incomplete` and a
  structured `fit_report_health` summary; `require_complete = true` makes
  report, export, load, and dossier paths fail closed for evidence workflows.

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
