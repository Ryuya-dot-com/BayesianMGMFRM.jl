# BayesianMGMFRM.jl release notes

## 0.1.2 (unreleased)

### Changed

- Keep the paired CmdStan validation script parseable on Julia 1.10 by removing
  a trailing comma after its filtered generator expression.
- Support exact individual rater/item hard anchors in the stable MFRM/RSM/PCM
  compiler and fitting path. Fixed coordinates replace the block's default
  reference gauge, are omitted from sampling and prior density, and remain
  visible in predictor metadata, Wright-map rows, rater diagnostics, and model
  manifests. Stable fit reports now expose them in a dedicated fixed-coordinate
  section, keep them out of posterior-summary rows, and add concise fixed-value
  and coordinate-dependent-prior warnings when declared hard anchors are
  present. The latter makes explicit that the zero-centered prior on free
  identified coordinates is not shifted with the anchor, so a
  likelihood-equivalent anchor change need not be posterior-invariant. The
  report adds a third warning when two or more anchors in the same facet fix
  within-facet contrasts. Fixed external values do not propagate their source
  estimation or linking uncertainty. The public, Markdown, JSON, and
  table-report paths preserve this contract. Optional
  provenance/hash auditing does not gate fitting. Semantic design/cache
  identity is invariant to anchor declaration order but remains sensitive to
  anchor content. Known-truth checks distinguish likelihood-equivalent single-
  anchor gauge shifts from contaminated multi-anchor contrasts that change
  response probabilities and expected log score, while retaining the prior-
  coordinate caveat for the former. An exact dense/sparse check confirms equal
  likelihood under a shifted single-anchor gauge and shows that its log-prior
  difference scales as the inverse square of a common prior-scale multiplier.
  Exhaustive ordered two-anchor deletion checks also show that an incompatible
  clean/contaminated pair changes probabilities, while deleting either member
  restores a likelihood-equivalent single-anchor gauge; response likelihood
  alone cannot attribute which source value is contaminated.
  Reader-facing parameter-layout rows now omit compiler-only statuses while
  preserving reference and hard-anchor statuses on fixed coordinates.
  Disconnected rating graphs remain rejected:
  individual parameter anchors do not create observed graph links or implement
  FACETS-style group anchoring.
- Include the existing category-functioning and pairwise rater-homogeneity
  summaries in stable MFRM fit reports by default, with independent opt-out
  controls. Category usage and step-order review rows produce one aggregate
  warning without automatic score recoding. Rater rows keep shared-unit overlap
  separate from full additive-model identification and assume no universal
  severity ROPE. Public, Markdown, JSON, and table exports preserve the rows
  while omitting the reproduction-only data signature. Single-rater reports
  now mark pairwise contrasts and interpretation as not applicable instead of
  labelling the empty comparison graph connected and fully interpretable.
  Zero-row contrast tables survive public JSON, table, and bundle round trips;
  Markdown can show them explicitly with `include_empty = true`. Declared but
  unobserved category endpoints also remain visible in PCM usage rows alongside
  the full item-specific threshold-row set. Rater contrasts now distinguish
  default fixed references, hard anchors, and estimated coordinates. Two-fixed-
  coordinate differences are labelled exact constants with no posterior
  uncertainty or interval probabilities; one-fixed-coordinate differences
  attribute uncertainty only to the estimated side. These statuses survive
  public reports and JSON round trips.
- Preserve an explicitly declared consecutive ordinal scale through
  `FacetData(...; category_levels = ...)`, validation, likelihood and
  prediction design, refit subsets, fit/model metadata, and fit-cache reloads.
  The existing observed-minimum-to-maximum inference remains the default.
  Declared but unobserved endpoints now produce an actionable warning instead
  of silently reducing the fitted category universe.
- Freeze the `0.1.x` package-root API by classifying every exported binding as
  stable, compatibility-only, or research-only. Tests reject overlaps and
  unclassified export growth, while the docs build rejects missing stable or
  compatibility references; published compatibility and research surfaces are
  visibly separated from the stable workflow.
- Make the ordinary/research test boundary fail closed: non-empty optional
  research-fixture paths now require the explicit research-evidence flag, CI
  keeps that flag off outside the manual research lane, and every CI job has a
  documented hard timeout.
- Add a release-hygiene smoke that assembles a Git-free candidate from visible,
  non-ignored files, rejects current-machine paths, disables research evidence
  and optional CmdStan/R environment hooks, and budget-checks instantiate,
  first/warm load, the minimal stable fit, and the docs build from that copy.
  Documenter now has an explicit package remote and `main` edit target, so its
  source-link setup no longer requires local Git metadata.
  The release-hygiene CI job also enforces a 4 MiB compressed Git source-archive
  budget before installing Julia.

### Added

- Add a fixed, two-replication MFRM hard-anchor pilot crossing four connected
  designs, a fitted-family versus R4 extremity-response generator, and five
  anchor regimes: true and shifted single anchors, true endpoint and interior
  multi-anchors, and contaminated endpoint multi-anchors. All 80 four-chain
  fits pass the pilot diagnostics with no divergences or maximum-tree-depth
  hits. Contamination worsens true-probability regret in 16/16 pairs but
  finite-sample holdout log loss in only 10/16; correct interior-versus-endpoint
  direction splits 10/16. The paired nested-link comparison is explicitly a
  composite ability-range, item-mix, and rater-load stress rather than an
  isolated placement effect. The result remains descriptive operability
  evidence, not calibrated recovery, new-level prediction, or a public claim.
- Add `mgmfrm_validation_replication_precision` to compare proposed fixed-Q
  MGMFRM simulation counts using separate coverage, worst-case binary-rate,
  and reference-SD bias MCSE calculations without freezing a study.
- Add `BayesianMGMFRM.Experimental.GeneralizedPrior` as a typed,
  cache-aware raw-coordinate scale contract for guarded GMFRM and MGMFRM
  refits. Direct-scale generalized priors remain outside this change.
- Add experimental generalized `prior_predict` and `prior_predictive_check`
  operations that retain raw/direct prior draws and reuse the existing score,
  category-use, facet-range, and sparse-design summaries without running MCMC.
- Add threshold-free MGMFRM validation scorers for known-truth category
  probabilities, expected scores, proper log-score regret, pairwise ordering,
  and caller-defined classification stability.
- Add `mgmfrm_validation_protocol()` as a non-executing Stage-A draft for the
  narrow fixed-Q promotion study. It records Uto source anchors, the
  between-item primary domain, boundary Q structures, estimands, interval and
  sampler policy, prior regimes, paired backend role, all-attempt failure
  accounting, and the remaining blockers without treating pilots as evidence.
- Add `ordinal_response_pattern_audit()` and pre-fit warnings for all-boundary
  person patterns and constant-score raters. Skipped interior categories,
  local boundary patterns, and globally single-category data now have distinct
  sampler-free interpretations.
- Add a nine-attempt, MCMC-free fixed-Q MGMFRM response-stress plan, generator,
  and denominator-preserving preflight. It covers dense and connected-sparse
  five-category gaps and boundary patterns, records typed generation failures,
  and keeps all repeated-fit and scientific decisions explicitly unrun.
- Add an explicit-plan MGMFRM response-stress fit-wiring runner with a
  one-attempt default resource bound, typed terminal failures, retained
  exceptions and partial fit results, and output-integrity diagnostics. Its
  four-warmup/four-draw profile cannot make convergence or scientific claims;
  the analysis profile remains blocked.
- Add a non-executing MGMFRM analysis-profile contract that now separates 13
  specified structural/computational/design components from four unresolved
  execution and scientific decisions. It preserves the fresh-seed block and
  refuses to infer an attempt count or thresholds from runtime pilots.
- Freeze a portable execution-design contract for five-fold conditional
  observation holdout, non-overwriting remediation, and 24 exact sensitivity
  role-cells spanning priors, response patterns, Q structure, unidimensional
  MFRM comparison, and paired CmdStan roles through documented package APIs.
- Add an explicit, MCMC-free MGMFRM resource probe with hard cell, observation,
  and pre-generation available-memory bounds. The default memory screen is 2 GiB
  with a non-lowerable 1 GiB floor; rejection leaves every cell unstarted. It
  measures local generation and warmed ForwardDiff gradient cost while
  prohibiting scientific, backend-ranking, and full-NUTS runtime claims.
  Bounded short-NUTS execution is available for a specifically reviewed cell,
  but it is no longer an automatic prerequisite or progression rule.
- Correct the MGMFRM resource preflight on macOS so Julia/libuv's raw free-page
  count is not mislabeled as available memory. Preserve the raw value for
  compatibility, record a separate conservative reclaimable-page estimate and
  system memory pressure, and propagate both through isolated worker receipts
  and threshold-free reviews.
- Allow the fixed-Q response-stress generator to use odd item counts. Pure
  items are split between the two dimensions with a count difference of one,
  so the source-anchored 5- and 15-item candidates are no longer rejected by
  an unnecessary equal-count restriction.
- Add a non-executing 16-cell primary-grid candidate contract spanning the two
  planned designs and source-anchored person, item, and rater sizes. It exposes
  the 500--22,500 observation range, the nine cells above the current 2,000-
  observation short-NUTS bound without freezing a grid or authorizing
  evaluation.
- Add a provisional three-stage review inside the primary-grid contract: a
  minimum operability pair, a larger-support design pair, and a sparse
  rater-coverage extension. Its five cells are minimal only for the three
  listed contrasts; the contract explicitly rejects factorial, separate
  person/item, isolated rater-count, recovery-from-Stage-1, and universal
  sparse-percentage interpretations.
- Add a four-category known-truth generator and MCMC-free primary-grid
  preflight. They share the fixed-Q generation core with the five-category
  response-stress path, preserve explicit seed roles, and establish structural
  operability rather than recovery or scientific evidence. The all-candidate
  materialization check is kept outside the default test entry point because
  it is substantially more expensive than representative-cell smoke coverage.
- Add an ordered four-cell primary gradient resource plan using the actual
  four-category DGP. The generic MCMC-free gradient probe now accepts those
  rows. The plan prohibits automatic progression and does not claim full axis
  coverage or freeze the resource envelope; its seeds are explicitly
  resource-only rather than structural-preflight or evaluation seeds.
- Extend the denominator-preserving bounded fit adapter to one four-category
  primary candidate at a time. Primary short-NUTS attempts reuse the existing
  fit, diagnostic, and typed-failure loop, return primary-specific schemas, and
  route successful operational probes to primary resource review rather than
  the five-category stress scaling plan.
- Allow the process-isolated resource worker and threshold-free reviewer to
  select the two primary resource rows inside the current short-NUTS bound.
  Primary and legacy stress/scaling receipts retain separate ordered
  collections and cannot be mixed into a passing review.
- Link those two primary receipts to the provisional Stage 1 candidate cells
  in the threshold-free review. Missing records remain visible and prefer
  recovery before rerun; a complete submitted pair permits only a manual
  operability-scope decision and cannot establish convergence, recovery,
  portable performance, or scientific validity.
- Preserve short-NUTS geometry in isolated worker receipts and reviews:
  divergences, maximum-depth hits, mean leapfrog steps, mean and maximum tree
  depth, mean step size, and complete-chain E-BFMI availability. The bounded
  single-chain probe still makes no convergence or scientific decision.
- Add on-demand `posterior_mcse` rows for posterior means, standard
  deviations, and requested quantiles. The function supports identified MFRM
  parameters, generalized raw/direct coordinates, and chain-blocked matrices
  of user-defined estimands; short or single-chain inputs fail visibly as
  unavailable, and no universal precision threshold is applied.
- Reduce guarded MGMFRM gradient allocation without changing the fixed-Q
  likelihood: build the Q-to-loading index matrix once per evaluation, avoid
  row-level predictor arrays in the fit path, and accumulate total likelihood
  directly instead of materializing a pointwise vector that is immediately
  summed. Explicit tests compare every primary-row predictor and the total
  versus pointwise likelihood.
- Add a separate explicit-execution short-NUTS resource probe. It admits only
  one connected-sparse AdvancedHMC cell, uses 25 warmup and 25 retained draws,
  enforces workload and available-memory gates before generation, discards fit
  objects, and cannot make convergence, recovery, peak-memory, or performance
  claims.
- Add a four-cell sequential resource-scaling plan with matched-observation
  sparse/dense cells and no automatic progression. Short-NUTS results now
  distinguish reused-process lifetime `Sys.maxrss()` from dedicated-worker
  peak memory.
- Add an inert-by-default, single-cell isolated resource probe with parent and
  child memory gates, a bounded wall time, compact JSON receipts, and typed
  launch/timeout/child/receipt failures. Worker peak RSS includes Julia startup
  and compilation and is explicitly not labelled sampler-only memory.
- Add a threshold-free isolated-resource review that preserves parent and
  child preflights, rejected or incomplete cells, worker time, environment,
  and peak RSS while prohibiting automatic progression and resource-policy
  decisions.
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

- Make the release-scope check depend on required package-document presence and
  the existing structured support manifest instead of exact README or roadmap
  sentences. Public API names containing `audit` or `preflight` no longer fail
  a stylistic regex gate, while public-boundary, private-path, runtime-output,
  example, and Documenter checks remain. The experimental surface contract now
  declares its reader-facing bindings, removing a duplicated runtime-gate list.
  Legacy code/document archive SHA traversal now runs only in the opt-in
  research-evidence lane. The committed local-dependence preflight artifact
  continues to verify its own content digest and provenance-field shapes, but
  ordinary tests no longer require its historical source digests to equal the
  current working tree.
- Reorder the active roadmap around a distribution-first gate. Ordinary package
  behavior, clean-clone release checks, stable-MFRM usability, root-API and
  dependency budgets, and separation of research fixtures now precede new
  generalized mechanisms or large simulation programs. An axis-lock checklist
  now requires a named outcome and the weakest sufficient identity mechanism,
  while making digest-only work and unfalsifiable evidence accumulation explicit
  stop/move conditions. Exact digests remain for cache correctness and genuine
  external-byte boundaries, but transitive source-hash chains are no longer
  roadmap progress or scientific evidence.
- Separate Uto's 30-repetition RMSE/bias study and two-rater ability comparison
  from package precision and sparse-robustness requirements. Primary-grid rows
  now report effective per-rater exposure and coverage roles, while the
  protocol requires link, coverage, fit, and assignment-order sensitivity.
- Reframe the active MGMFRM roadmap around a narrow fixed-Q scientific
  promotion decision. The new sequence separates pilot operability from
  fresh-seed validation, external/independent evidence, and user-workflow
  hardening; keeps Stan as a required reference rather than a default backend;
  defers anchor-dose and broader model studies until their fitted contracts
  exist; and replaces routine SHA-oriented gates with resource-aware executable
  checks.
- Refine the Stage-A contract with explicit estimand units, Q and sparse-design
  scope, executable prior-refit sensitivity, `1.7`/`1.702` scale
  harmonization, a paired CmdStan comparison subset, layered decision rules,
  and five-category response-pattern stress scenarios.
- Add a bounded Stage 0 model-family skeleton before scientific protocol
  freezing. It separates between-item, within-item, and mixed fixed-Q
  structures; the source's non-compensatory label from its additive weighted-
  sum predictor; GPCM-form category kernels; model-specific step ownership;
  and executable versus unsupported branches without proposing a generic
  sampler framework. The public `model_family_contract()` API returns that
  skeleton, while `model_family_contract(spec_or_design)` resolves the exact
  branch and its fitting boundary. It also records the original scalar GMFRM
  unit-scale convention separately from the MGMFRM `1.7` convention and marks
  cross-family discrimination comparisons as requiring explicit harmonization.
  The MGMFRM contract now distinguishes the published executable literal
  `1.7` from the conventional normal-ogive minimax reference `1.702`; the latter
  is metadata, not a silent likelihood replacement.
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
- Add a separate opt-in paired known-truth recovery pilot with nonzero truth,
  common direct-scale MAE/RMSE/coverage summaries, and separate sampler,
  R-hat, bulk-ESS, and tail-ESS reporting. It applies no pilot-derived pass
  threshold or backend ranking.
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
  duplicate digest execution, and move byte-exact legacy code/document archive
  traversal out of ordinary `Pkg.test()` and into the opt-in research-evidence
  lane. Plain `Pkg.test()` still runs every ordinary behavioral group.
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
