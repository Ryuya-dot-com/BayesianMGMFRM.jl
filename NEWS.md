# BayesianMGMFRM.jl release notes

## Unreleased

- Make the local publication-grade batch orchestrator default to the tracked
  batch-expansion plan, requiring ignored local-ready plans to be passed
  explicitly with `--plan` so stale local artifacts cannot silently change the
  execution budget.
- Add `diagnostic_map_data` as a plotting-backend-independent pathway-map data
  contract that joins MFRM Wright-map logit positions to posterior infit/outfit
  summaries.
- Add a local brms-like single-cell MGMFRM publication-grade execution review
  fixture that records the construct-reviewed revised-Q fold-1 run at `4`
  chains, `1000` warmup draws per chain, and `1000` retained draws per chain,
  with passed R-hat/ESS/HMC/heldout gates and public claims still blocked.
- Add a local brms-like full pilot execution review fixture for the five
  `well_specified_current_q` fold-1 publication-grade units, recording that
  3/4 MCMC gates passed, scalar GMFRM had two divergences, the analytic null
  reference ranked first on heldout ELPD, and public claims remain blocked.
- Add a local brms-like scalar remediation review fixture showing that
  increasing scalar GMFRM `target_acceptance` from `0.8` to `0.9` under the
  same `4/1000/1000` budget removed divergences (`2 -> 0`) without a material
  heldout-ELPD shift, while preserving the primary pilot row and blocking public
  model-comparison claims.
- Split the rendered API reference into smaller workflow pages to avoid the
  oversized single-page Documenter warning.
- Turn the Documenter 100 KiB rendered-page warning threshold into a hard docs
  build gate and expose that documentation-size guardrail in
  `release_scope_summary`.
- Relabel the completed 30-45 day roadmap section as a sprint record so the
  current remaining boundary is the manual public-scope/registration gate rather
  than a stale immediate-task label.
- Relabel completed release-roadmap task blocks as completed checklists so the
  100% checklist ledger does not retain stale task-heading language.
- Add a Documenter registration handoff page that mirrors the manual
  pre-registration boundary and links it from the docs navigation.
- Tighten the pre-registration gate to check the General AutoMerge-facing
  package-name rules and origin URL shape before handoff.
- Split the CI hygiene mode from the full manual pre-registration wording scan,
  so ordinary pushes still check package shape without claiming registration
  readiness.
- Add a local registration handoff script that verifies the manual release
  boundary and prints the Registrator trigger comment without performing any
  registration action.
- Add a DOI-backed local MGMFRM empirical Q-matrix recovery simulation-grid
  generator and committed JSON artifact that records Q-matrix validation
  literature, known-truth add/drop/noise scenarios, candidate-Q validation, and
  zero public automatic Q-revision promotion.
- Remove local reference-manager item keys from MGMFRM empirical Q-matrix
  recovery artifacts so package fixtures rely on public DOI metadata and stable
  citation keys.
- Add a local MGMFRM Q-candidate real-fit diagnostic-linkage generator and
  committed JSON artifact that sends valid candidate Q masks through the
  guarded fixed-Q `fit(spec; experimental = true)` diagnostics while blocking
  invalid candidates before fit and keeping Q revision claims diagnostic-only.
- Add a local MGMFRM Q-revision cross-validation policy generator and committed
  JSON artifact that screens candidate Q masks with fold-level heldout evidence,
  rejects noisy false positives, excludes invalid candidates before CV, and keeps
  CV-supported revisions manual-review-only pending construct-validity review.
- Add a local MGMFRM Q-revision construct-validity review generator and
  committed JSON artifact that reviews CV-supported Q candidates against a
  synthetic rubric trace, records reviewer-role agreement, keeps supported
  candidates manual-local-only, and clears the construct-review blocker without
  making public Q-revision claims.
- Add a local MGMFRM guarded fit entrypoint generator and committed JSON
  artifact that dry-runs construct-reviewed Q candidates through
  `fit(spec; experimental = true)`, confirms finite guarded local fit outputs,
  and keeps Q revision and broader MGMFRM claims blocked.
- Add a local MGMFRM fit-metric threshold-sensitivity generator and committed
  JSON artifact that compares existing MFRM infit/outfit diagnostics with
  fixed-Q MGMFRM WAIC, LOO, posterior predictive, calibration, and
  common-parameter-shift summaries across literature-motivated threshold
  profiles while keeping convergence, fit-metric, and Q-revision claims local.
- Extend the MGMFRM publication-grade refit batch results review to inherit
  those threshold profiles and record job-level, model-level, and
  scenario-model threshold surfaces so strict, screening, lenient, and
  sample-size-sensitive cutoffs can be compared before any public fit claim.
- Add a local MGMFRM construct-reviewed Q fit reporting-policy generator and
  committed JSON artifact that summarizes threshold-profile dependence,
  candidate/declared indicator conflicts, existing MFRM reference comparisons,
  and common-parameter-shift impact bands while keeping fit metrics as local
  appendix diagnostics only.
- Add a local MGMFRM heldout-prediction validation-policy generator and
  committed JSON artifact that records heldout K-fold or external construct
  validation as required before fit-metric, Q-revision, model-weight, or
  sparse-superiority claims while keeping same-data WAIC/LOO and threshold
  profiles diagnostic-only.
- Add a local MGMFRM validation split/model-comparison policy generator and
  committed JSON artifact that predeclares the primary heldout split,
  sensitivity splits, leakage guards, comparison model set, and heldout metrics
  for the next MGMFRM prediction simulation while keeping public fit-metric,
  Q-revision, model-weight, and sparse-superiority claims blocked.
- Add a local MGMFRM heldout-prediction simulation-grid generator and committed
  JSON artifact that fixes five scenario families, comparison models, heldout
  metrics, threshold-profile impacts, and leakage guards before execution while
  keeping observed-result, model-weight, sparse-superiority, fit-metric, and
  Q-revision claims blocked.
- Add a local MGMFRM heldout-prediction execution generator and committed JSON
  artifact that materializes deterministic observation K-fold assignments and
  625 observed metric cells from the predeclared grid, records rank-stability,
  threshold, and diagnostic model-weight rows, and keeps public fit-metric,
  Q-revision, model-weight, and sparse-superiority claims blocked until full
  MCMC refit and external construct validation review.
- Add a local MGMFRM full-heldout-refit / construct-validation review generator
  and committed JSON artifact that carries the deterministic heldout execution
  into explicit full MCMC refit and external construct-validation requirements,
  records model refit plans and blockers, and keeps public heldout,
  Q-revision, model-weight, and sparse-superiority claims blocked until those
  requirements are executed.
- Add a local MGMFRM full-heldout MCMC refit execution-plan generator and
  committed JSON artifact that materializes the 125 scenario-model-fold refit
  workload, diagnostic thresholds, model-level execution budgets, and external
  construct dataset review placeholders while leaving full MCMC execution,
  external data attachment, and public MGMFRM claims blocked.
- Add a local MGMFRM full-heldout MCMC refit batch-smoke generator and JSON
  artifact that runs three representative scenario-model-fold units through the
  guarded MGMFRM fit path, records finite training pointwise log-likelihood
  outputs and expected smoke-only insufficient-chain diagnostics, and keeps the
  full 125-unit batch, heldout scoring, external construct dataset attachment,
  and public MGMFRM claims blocked.
- Add a local MGMFRM fold-1 heldout MCMC refit pilot generator and JSON
  artifact that runs all fold-1 fixed-Q MGMFRM candidate cells, records
  scalar/null comparison anchors as not fitted in that fixed-Q pilot, and keeps
  full-batch, publication-grade diagnostic, heldout-predictive,
  external-construct, and public model-comparison claims blocked.
- Add a local MGMFRM fold-1 heldout predictive-scoring generator and JSON
  artifact that scores those fixed-Q pilot refits on heldout observations,
  records pointwise log predictive density and expected-score residual rows,
  leaves scalar/null comparison anchors unscored in the fixed-Q pilot, and keeps
  full-batch, publication-grade diagnostic, external-construct, and public
  model-comparison claims blocked.
- Add a local MGMFRM all-fold fixed-Q candidate heldout predictive-scoring
  generator and JSON artifact that expands fold-1 scoring to all five folds for
  the three fixed-Q MGMFRM candidates, records 75 candidate refit scores and 600
  heldout pointwise rows, leaves scalar/null anchors unscored, and keeps
  model-weight, sparse-superiority, fit-threshold, and Q-revision claims blocked
  pending anchor refits or external construct validation.
- Add a local MGMFRM heldout anchor-scoring generator and JSON artifact that
  scores the scalar GMFRM and intercept/reference anchors across all five folds,
  joins them to the fixed-Q candidate k-fold summaries for a descriptive
  125-unit comparison, and keeps public model-weight, sparse-superiority,
  fit-threshold, and Q-revision claims blocked pending publication-grade refits
  or external construct validation.
- Add local MGMFRM publication-grade refit gate and single-cell pilot-plan
  artifacts that freeze the diagnostic thresholds, metric profile, selected
  scenario/fold/model workload, and claim blockers before heavy NUTS refits are
  run.
- Add a local MGMFRM publication-grade refit pilot execution-harness artifact
  that materializes the five pilot jobs, command templates, result targets,
  diagnostic-capture rows, and comparison hooks, plus a local runner script for
  dry-run, analytic-reference, and refit-job execution while keeping heavy
  pilot completion and public MGMFRM claims blocked.
- Add a local MGMFRM publication-grade refit pilot results-review artifact that
  reads local runner outputs, records missing, partial, or complete execution,
  adds descriptive heldout rank rows and diagnostic-failure rows when local
  outputs are present, keeps committed fixtures isolated from ignored local
  artifacts, and keeps fit-metric, Q-revision, model-weight, and
  sparse-superiority claims blocked until all selected jobs and diagnostics are
  reviewed.
- Add a local MGMFRM publication-grade sampler-remediation review artifact that
  records a separate scalar GMFRM target-acceptance escalation run for the pilot
  divergence warning without replacing the preregistered primary pilot result.
- Add a local MGMFRM scalar-remediation comparison artifact that compares the
  primary scalar GMFRM pilot fit with the target-acceptance escalation before
  batch expansion, records a local-only scalar batch sampler policy, and keeps
  public fit-metric and model-comparison claims blocked.
- Add a local MGMFRM publication-grade batch-expansion plan artifact that
  materializes the full 125 scenario-model-fold command manifest, consumes the
  brms-like scalar remediation review, applies scalar target acceptance 0.9,
  keeps fixed-Q MGMFRM candidates at 0.8, upgrades the batch warmup budget to
  `1000` per chain, and marks the local runner path ready while public claims
  remain blocked until batch results are reviewed.
- Add a local publication-grade batch smoke execution review fixture for the
  five `well_specified_current_q` fold-1 jobs, recording that all four MCMC
  gates passed through the batch runner path, scalar target acceptance 0.9 kept
  divergences at zero, the analytic null/reference still ranked first on
  heldout ELPD, and remaining batch/public claims stay blocked.
- Add a local publication-grade `well_specified_current_q` scenario execution
  review fixture that summarizes all 25 five-fold jobs, records the remaining
  20 jobs as runner-successful under the brms-like budget, preserves scalar
  divergence failures in folds 3 and 5 as sampler-stability blockers, and keeps
  public fit, model-weight, Q-revision, and sparse-superiority claims blocked.
- Update the local publication-grade batch results-review fixture after the
  first full 125-unit local run, recording all 375 result/diagnostic/heldout
  artifacts as present, fixed-Q MGMFRM candidate and analytic-reference
  diagnostic gates as passed, the initial scalar GMFRM divergence-count
  failures, the analytic null/reference as the descriptive heldout winner in
  24/25 folds, and public fit/model-weight/Q/sparse claims still blocked.
- Add targeted scalar publication-grade refits for the 11 divergence-failing
  batch units, using higher target acceptance and warmup locally, and update the
  batch results-review fixture to record 125/125 diagnostic gates passed,
  zero diagnostic-failure rows, the next fit-threshold/model-weight sensitivity
  comparison gate, and continued public-claim blocking pending external
  construct evidence and independent public-scope review.
- Extend the publication-grade refit runner so it can read either the pilot
  plan or the full batch-expansion plan via `--plan`, preserving pilot
  compatibility while enabling batch dry-runs and analytic reference jobs.
- Add a local publication-grade refit batch orchestrator that reads the 125-unit
  plan, skips completed artifacts by default, writes resumable manifests and
  per-job logs, and requires explicit `--execute`/`--materialize-dry-run-artifacts`
  plus a job limit or explicit unit selection before invoking runner jobs.
- Add a local MGMFRM publication-grade batch results-review artifact that reads
  batch runner outputs when explicitly requested, records model and
  scenario-model execution summaries, and keeps fit, Q-revision, model-weight,
  and sparse-superiority claims blocked until the full batch and diagnostics are
  reviewed.
- Add a local MGMFRM fit-threshold/Q/heldout linkage generator and JSON
  artifact that connects threshold-profile sensitivity, Q-matrix recovery
  diagnostics, predeclared heldout simulation expectations, and observed fold-1
  heldout rankings while keeping fit-threshold, Q-revision, model-weight, and
  sparse-superiority claims blocked pending full-batch or external construct
  validation.
- Expose pre-registration gate availability in `release_scope_summary` and
  clarify that Julia General registration is a manual action after the local
  gate passes.
- Clarify that the current public package is a data validation, design, and
  minimal MFRM fitting scaffold with guarded scalar GMFRM and fixed-Q
  confirmatory MGMFRM experiments, not a full GMFRM/MGMFRM fitting API.
- Introduce `validate_design` / `ValidationReport` as the public terminology for
  pre-fit design checks.
- Preserve requested DFF/bias validation evidence in `mfrm_spec`.
- Add a local GMFRM DFF estimand/validation-grid generator and committed JSON
  artifact that predeclares logit and expected-score DFF screening estimands,
  verifies sparse, empty, confounded, and invalid-facet validation behavior,
  retains valid DFF terms as validation-only constraint rows, and advances the
  remaining broader-exposure blocker to Gate E manuscript-scale evidence.
- Add a local Gate E manuscript-scale evidence-grid generator and committed
  JSON artifact that aggregates versioned scalar GMFRM validation, posterior
  predictive, sparse-pathology, prior/likelihood sensitivity, real-data,
  DFF-validation, and confirmatory MGMFRM sparse-recovery evidence as an input
  to the local full-paper reproduction archive.
- Add a local full-paper reproduction archive generator and committed JSON
  artifact that records fixture hashes, generator commands, code/documentation
  hashes, source references, and local verification commands without any
  publication or registration action, advancing the remaining blocker to manual
  public-scope review and guarded MGMFRM fit validation.
- Add a local confirmatory MGMFRM guarded fit method-wiring generator and
  committed JSON artifact that records the source-aligned target,
  raw-to-direct transform, sampler protocol, artifact-contract preview, fixture
  hashes, and then-current public-fit rejection checks while the MGMFRM
  entrypoint was still disabled.
- Add a local confirmatory MGMFRM guarded fit validation-grid generator and
  committed JSON artifact that aggregates bridge-oracle, candidate-chain,
  recovery-smoke, baseline-comparison, sparse-recovery, and method-wiring
  evidence from the pre-exposure state and advances the next local blocker to
  a guarded fit API dry-run.
- Add a local confirmatory MGMFRM guarded fit API dry-run generator and
  committed JSON artifact that records pre-exposure public-fit rejections, the
  artifact contract, validation-grid evidence, and AD/finite-difference checks
  for the internal source-aligned target before public exposure review.
- Add a local confirmatory MGMFRM guarded fit public exposure-review generator
  and committed JSON artifact that reviews the internal MGMFRM guarded-fit
  evidence, kept the MGMFRM entrypoint disabled at that gate, and advanced the
  remaining blocker to prediction-target/model-weight policy without
  publication or registration action.
- Add a local prediction-target/model-weight policy generator and committed JSON
  artifact that recorded same-observation WAIC and raw PSIS/LOO as
  diagnostic-only, selected heldout K-fold log score for local scalar
  model-weight reporting, and kept MGMFRM fit, model-weight, and
  sparse-superiority claims blocked at that gate until manual public-scope
  review.
- Add `MGMFRMFit` and expose the fixed-Q two-dimensional confirmatory MGMFRM
  candidate through `fit(spec; experimental = true)` as a guarded experimental
  public path with metadata, diagnostics, fit artifacts, WAIC/LOO inputs, and
  unsupported-option rejection checks while keeping exploratory loadings, free
  latent correlations, higher dimensions, model-weight claims, and
  sparse-superiority claims blocked.
- Add `examples/guarded_mgmfrm.jl`, a compact fixed-Q confirmatory MGMFRM
  guarded-fit example, and run it from the pre-registration gate.
- Add a guarded fixed-Q MGMFRM example section to the Bayesian fitting docs.
- Split the Bayesian fitting docs examples into separate guarded MGMFRM and
  minimal MFRM workflow sections.
- Add a Documenter Examples page linking the minimal MFRM and guarded fixed-Q
  MGMFRM scripts.
- Add `fit_report`, a compact machine-readable report bundle for fitted MFRM,
  guarded GMFRM, and guarded fixed-Q MGMFRM objects, and enable calibration
  rows for guarded MGMFRM fits.
- Show `fit_report` in the README, overview/workflow docs, Bayesian fitting
  docs, and runnable minimal/guarded MGMFRM examples.
- Document and test `artifact_content_hash` verification for `fit_report`
  bundles as well as fit artifacts.
- Add `save_fit_report` and `load_fit_report` for JSON fit-report export
  records with verified JSON-payload hashes and checked hash-record metadata.
- Add `fit_report_sections`, `fit_report_section`, and `fit_report_rows` for
  extracting report sections and rows from in-memory or JSON-loaded fit reports.
- Add `save_fit_report_tables` for exporting each `fit_report` row field as a
  portable JSON table file with a manifest of table paths, row counts, and
  content hashes.
- Add `fit_report_markdown` and `save_fit_report_markdown` for dependency-light
  Markdown review drafts with metadata, section summaries, table previews, and
  Markdown content hashes.
- Add `save_fit_report_bundle` for one-call fit-report directories containing
  JSON report exports, table files, Markdown drafts, and a bundle manifest with
  nested content hashes.
- Add `load_fit_report_bundle` to verify bundle manifests and nested JSON,
  table-manifest, table-file, and Markdown hashes before returning the report
  payload, including hash-record metadata for bundle file rows.
- Add `load_fit_report_tables` to verify table-export manifests and table-file
  hashes before returning JSON-loaded table records, including hash-record
  metadata for manifests, manifest rows, and table files.
- Add `scripts/generate_validation_plan.jl`, a deterministic validation-plan
  artifact generator that records simulation-grid controls, coverage summaries,
  falsification-rule coverage, and content hashes without running simulations or
  fitting models.
- Reject boolean score columns instead of silently treating them as `0/1`.
- Report empty data with a dedicated `:empty_data` validation error.
- Use numeric ordering for numeric facet labels.
- Warn when item/category cells are unobserved or an item uses only one category,
  because partial-credit thresholds may be weakly informed.
- Add reference constraints for the minimal additive design: first rater and
  item levels are fixed, and threshold steps use a sum-to-zero reconstruction.
- Add an initial Bayesian `fit` API for the minimal MFRM/RSM/PCM scaffold,
  returning `MFRMFit` posterior draws from a `backend = :julia` random-walk
  Metropolis sampler.
- Add `MFRMLogDensity`, `initial_params`, `loglikelihood`, and `logprior` as a
  `LogDensityProblems.jl`-compatible posterior target and separated target
  components for external sampler and AD experiments.
- Add `backend = :advancedhmc`, an initial AdvancedHMC/NUTS fitting path for
  the minimal MFRM/RSM/PCM design using `MFRMLogDensity` and ForwardDiff.
- Extend `mfrm_spec` into an initial model ladder that records fit-supported
  MFRM and specified-only GMFRM/MGMFRM configurations in one `FacetSpec`.
- Add `model_ladder` and `constraint_table` for machine-readable family,
  identification, transform, prior-block, DFF validation-only, and
  multidimensional Q-mask gauge declarations.
- Add `model_equation` for source-traced mathematical contracts that separate
  the current fit-supported MFRM/RSM/PCM slice from the primary-literature
  GMFRM/MGMFRM target equations and their remaining implementation gaps.
- Add `getdesign(spec; preview = true)` for non-fit-ready GMFRM/MGMFRM
  parameter blueprints. GMFRM previews now expose source-aligned
  item-discrimination, rater-consistency, and rater-step blocks; MGMFRM previews
  expose person-by-dimension, item-dimension-discrimination, rater-consistency,
  and item-step blocks.
- Add `design_row_table` for observation-level compiler inspection, including
  facet parameter indexes, source-step paths, and preview-only generalized
  parameter indexes for specified-only GMFRM/MGMFRM specs.
- Add `linear_predictor_table` for row-by-category compiler inspection of
  denominator terms, including source-aligned GMFRM/MGMFRM preview kernels
  without enabling unsupported fitting.
- Add `linear_predictor_values` for numeric MFRM/RSM/PCM row-by-category
  `eta`, log-denominator, and category log-probability inspection, and route
  pointwise likelihood/probability calculations through the same evaluator.
- Add internal hand-computed GMFRM and MGMFRM source fixtures that check the
  source-aligned preview compiler against constrained direct parameter values
  without enabling generalized fitting.
- Add internal raw-coordinate transforms for the GMFRM/MGMFRM source fixtures,
  covering sum-to-zero, positive, and product-one source restrictions, and
  compose those transforms with fixture-only pointwise log-likelihood kernels
  without exposing a public generalized likelihood API.
- Add an internal fixture-only `LogDensityProblems.jl` target for the
  source-aligned GMFRM/MGMFRM raw coordinates, including independent normal raw
  priors for validation of the future HMC target shape without enabling
  generalized fitting.
- Document the fixture-only raw prior/Jacobian policy and add ForwardDiff
  gradient checks against central finite differences for the internal
  GMFRM/MGMFRM raw-coordinate targets.
- Add fixture-only AdvancedHMC/NUTS smoke checks for the internal
  GMFRM/MGMFRM raw-coordinate targets, verifying finite AD gradients, draws,
  and sampler stats without exposing generalized fitting.
- Tighten source-fixture positive constraints so raw log-discrimination and
  raw log-consistency overflow/underflow states fail before fixture likelihood
  evaluation.
- Add source-aligned GMFRM/MGMFRM Stan reference models, a BridgeStan generation
  script, and committed BridgeStan JSON log-density/gradient fixtures for the
  internal raw-coordinate targets. The default test suite now compares those
  fixture-only Julia targets against BridgeStan while keeping generalized
  fitting blocked.
- Expose internal GMFRM/MGMFRM raw-parameterization manifests on preview
  designs, including raw/constrained block maps, transform rows, raw prior
  policy, and no-Jacobian raw-density policy while keeping public generalized
  fitting blocked.
- Add an internal scalar GMFRM promotion-candidate path that records candidate
  gates in the preview raw-parameterization manifest and exposes finite
  log-density, ForwardDiff gradient, and finite-difference gradient diagnostics
  without opening the public `fit` API.
- Split the scalar GMFRM promotion candidate from the source-fixture blueprint
  by adding an internal fit-ready compiler-candidate manifest with generated
  raw/constrained block maps, transform rows, constraint rows, unsupported
  public-option declarations, and raw-prior/Jacobian policy fields.
- Extend that GMFRM promotion-candidate path with constrained direct-parameter
  metadata and raw-to-direct transform diagnostics that verify source
  constraints and pointwise log-likelihood agreement.
- Add an internal GMFRM promotion-candidate direct pointwise fixture API that
  returns direct parameter blocks, row/category likelihood rows, observed
  pointwise log likelihoods, and source-constraint summaries without exposing
  public generalized likelihood evaluation.
- Add an internal GMFRM promotion-candidate sampler diagnostic surface that
  runs the raw-coordinate AdvancedHMC/NUTS target and records chain-level HMC
  stats, raw-parameter R-hat/ESS rows, raw-block diagnostics, constrained
  direct draws, direct pointwise log-likelihood draws, and direct-block
  diagnostics while keeping public generalized fitting disabled.
- Add a local scalar GMFRM candidate-chain study generator and committed JSON
  artifact that records a predeclared AdvancedHMC/NUTS protocol over two fixed
  initial-value fixtures, including divergences, tree-depth hits, E-BFMI,
  raw/direct R-hat and ESS, direct constraints, and pointwise likelihood
  finiteness checks.
- Add an internal scalar GMFRM experimental-public decision manifest that keeps
  the candidate internal, records the proposed guarded `fit(spec;
  experimental = true)` shape, lists accepted and rejected option surfaces, and
  names recovery evidence, stress-chain evidence, raw-prior/Jacobian policy, and
  guarded exposure blockers before any public generalized fitting API can be
  exposed.
- Add a local scalar GMFRM recovery-smoke generator and committed JSON artifact
  that predeclares a small full-crossed simulation grid, simulates responses
  from fixed scalar GMFRM truth, runs the internal raw-coordinate HMC candidate,
  and records direct-scale recovery summaries by parameter block while keeping
  generalized fitting internal.
- Add a local scalar GMFRM baseline-comparison generator and committed JSON
  artifact that reuses the recovery-smoke simulation data, compares the internal
  candidate with public MFRM/PCM/RSM baselines by WAIC on the same observations,
  and records that the single-smoke comparison is insufficient by itself for
  public generalized fitting.
- Add a local scalar GMFRM baseline/calibration-grid generator and committed
  JSON artifact that runs near-Rasch, moderate-generalized, and
  stronger-generalized scenarios, recording same-observation WAIC,
  expected-score calibration bins, residual metrics, and sampler diagnostics
  while keeping public generalized fitting blocked pending guarded exposure
  review.
- Add a local scalar GMFRM interval/decision-grid generator and committed JSON
  artifact that records direct-parameter interval coverage at 80% and 95%,
  repeats the same public-baseline comparison scenarios, and verifies stable
  keep-internal decisions while keeping sparse-design and WAIC follow-up
  blockers visible.
- Add a local scalar GMFRM sparse-design-grid generator and committed JSON
  artifact that records connected sparse validation warnings, full-rank
  location designs, public-baseline comparisons, direct-parameter intervals,
  and stable keep-internal decisions across predeclared sparse patterns.
- Add a local scalar GMFRM WAIC influence-review generator and committed JSON
  artifact that extracts pointwise high-variance observations across
  full-crossed and sparse scenarios, removes their scenario-level union, and
  records model-rank sensitivity while keeping the decision internal.
- Add a local scalar GMFRM guarded-exposure review generator and committed JSON
  artifact that hashes the candidate-chain, stress-chain, recovery,
  baseline-comparison, baseline/calibration, interval/decision, and
  sparse-design and WAIC influence fixtures, records the review as local-only,
  and keeps public generalized fitting blocked on follow-up evidence.
- Add `loo` and `loo_diagnostics` for raw importance-sampling LOO with
  Pareto-k screening, plus `compare_models(...; criterion = :loo)`.
- Add a local scalar GMFRM PSIS/LOO review generator and committed JSON
  artifact that records raw importance-sampling LOO, Pareto-k warnings,
  WAIC-vs-LOO rank sensitivity, and keeps public generalized fitting blocked
  on exact LOO/K-fold follow-up.
- Add a local scalar GMFRM exact LOO/K-fold review generator and committed JSON
  artifact that records deterministic 3-fold heldout refits, verifies training
  parameter-order matches, compares heldout log scores, and advances the
  remaining public blocker to the guarded fit API dry run.
- Add a local scalar GMFRM guarded fit API dry-run generator and committed JSON
  artifact that records the proposed `fit(spec; experimental = true)` entrypoint
  without enabling it, verifies specified-only rejection and fit-artifact
  contract fields, runs a finite-logdensity/gradient target dry run, and
  advances the remaining public blocker to guarded method wiring.
- Add `GMFRMFit` and a guarded scalar GMFRM
  `fit(spec; experimental = true)` method for the one-dimensional
  rater-discrimination promotion candidate, plus a local guarded fit
  method-wiring generator and JSON artifact that verifies the experimental
  fit-artifact contract, WAIC/LOO inputs, and unsupported-option rejections.
  This wires the local guarded entrypoint while keeping broader generalized
  exposure gated on follow-up validation.
- Add a local scalar GMFRM experimental fit validation-grid generator and
  committed JSON artifact that runs the guarded `fit(spec; experimental = true)`
  path across three fixed scalar scenarios, verifies `GMFRMFit` metadata,
  pointwise log-likelihood shape, fit-artifact contract coverage, finite
  WAIC/LOO inputs, and direct-scale recovery bounds, and advances the remaining
  scalar GMFRM blocker to posterior predictive review before broader exposure.
- Add posterior predictive, expected-score, variance, residual, calibration,
  and posterior predictive check support for guarded scalar `GMFRMFit` objects,
  plus a local scalar GMFRM posterior predictive-grid generator and committed
  JSON artifact that records replicated-score intervals, category probability
  checks, calibration rows, and the now-superseded sparse-pathology recovery
  follow-up.
- Add a local scalar GMFRM sparse-pathology recovery-grid generator and
  committed JSON artifact that reruns guarded `fit(spec; experimental = true)`
  on three connected sparse designs, records sparse validation warnings,
  finite WAIC/LOO summaries, direct-scale recovery rows, posterior predictive
  checks, calibration rows, and advances the remaining guarded scalar blocker
  to prior/likelihood sensitivity evidence.
- Add a local scalar GMFRM prior/likelihood sensitivity-grid generator and
  committed JSON artifact that reuses the sparse-pathology scenarios, performs
  self-normalized importance reweighting across raw-coordinate prior profiles
  and likelihood powers, records weight ESS plus direct-parameter and
  predictive shifts.
- Add a local scalar GMFRM real-data case-study generator and committed JSON
  artifact that fits compact anonymized writing and speaking rater-mediated
  slices with the guarded scalar GMFRM path, compares public MFRM baselines,
  records posterior predictive and calibration checks, and advances the
  remaining guarded scalar blocker.
- Add a local scalar GMFRM claim-level recovery/reproduction archive generator
  and committed JSON artifact that records fixture hashes, generator commands,
  external source references, code/doc hashes, and local verification commands
  without publishing or registration actions, advancing the remaining guarded
  scalar blocker to a broader experimental exposure decision review.
- Add a local broader experimental exposure decision-review generator and
  committed JSON artifact that keeps the scalar GMFRM path guarded-only while
  leaving broader GMFRM/MGMFRM fitting, DFF effects, public model weights, and
  manuscript claims blocked for explicit policy and method evidence.
- Add a local confirmatory MGMFRM sparse-recovery-grid generator and committed
  JSON artifact that records connected sparse fixed-Q validation, sampler,
  WAIC, and direct-scale recovery evidence while keeping MGMFRM fitting
  internal.
- Add an internal minimal confirmatory MGMFRM candidate manifest that freezes
  the first multidimensional gauge as fixed Q-mask, fixed identity latent
  correlation, standard-normal ability scale, positive interpreted loadings,
  and source-scale `1.7`, while recording fit-ready transform, Stan oracle,
  sampler, and recovery blockers.
- Split the minimal confirmatory MGMFRM candidate from the source-fixture
  blueprint by adding an internal fit-ready candidate blueprint and raw
  transform manifest rows while keeping fit-ready MGMFRM likelihood, sampler,
  and recovery checks blocked.
- Add a nested fit-ready confirmatory MGMFRM BridgeStan oracle block that
  records the fixed Q-mask gauge metadata and compares raw log density, raw
  gradients, constrained direct values, pointwise log likelihoods, and total
  likelihood against the internal candidate while keeping MGMFRM fitting
  private.
- Add a local confirmatory MGMFRM candidate-chain study artifact with fixed
  AdvancedHMC/NUTS controls, near-oracle and zero-centered initial values,
  raw/direct R-hat and ESS, E-BFMI, direct constraints, and pointwise
  finiteness checks.
- Add a local confirmatory MGMFRM recovery-smoke generator and committed JSON
  artifact that simulates a full-crossed fixed-Q dataset, samples the internal
  raw target, transforms draws to the direct scale, and reports recovery by
  parameter block while MGMFRM fitting was private.
- Add a local confirmatory MGMFRM baseline-comparison generator and committed
  JSON artifact that compares the internal fixed-Q candidate with public
  MFRM/PCM/RSM baselines on the same recovery-smoke observations, records WAIC
  ranks, weights, and warnings, and kept MGMFRM fitting private pending sparse
  recovery evidence.
- Add an internal confirmatory MGMFRM experimental-public API decision manifest
  that records accepted and rejected option surfaces, cites BridgeStan,
  candidate-chain, and recovery artifacts, and keeps the candidate internal
  until sparse-grid blockers are cleared after the caveat-doc,
  fit-artifact, and raw-prior/Jacobian contracts are recorded.
- Add local guarded generalized-model caveat docs for scalar GMFRM and
  confirmatory MGMFRM, and record the docs artifact in the internal
  experimental-public decision manifests while keeping broader generalized
  fitting guarded.
- Add an internal experimental generalized fit-artifact contract that requires
  future guarded GMFRM/MGMFRM fits to record raw/direct parameter orders,
  transform/Jacobian policy, sampler controls, diagnostics, pointwise
  log-likelihoods, caveat docs, and fixture provenance before generalized
  fitting can be exposed.
- Add a local scalar GMFRM stress-chain grid artifact with longer fixed
  AdvancedHMC/NUTS chains across near-oracle, zero-centered, and high-acceptance
  scenarios, keeping scalar GMFRM fitting internal.
- Record the generalized raw-prior/Jacobian policy for guarded GMFRM/MGMFRM
  candidates: independent normal priors are placed on raw unconstrained
  coordinates, no transform Jacobian is added for that density, and direct-scale
  priors remain unsupported.
- Extend source BridgeStan fixtures with constrained parameter values,
  likelihood values, and GMFRM direct-parameter order checks so the promotion
  candidate's direct values and pointwise likelihood sum are compared with the
  external Stan oracle.
- Extend the source BridgeStan fixtures with deterministic generated-quantity
  pointwise log-likelihood values and add a fit-ready scalar GMFRM oracle block
  that compares raw log density, raw gradients, constrained direct values,
  pointwise log likelihoods, and total likelihood against the internal
  promotion candidate.
- Add `fit_metadata` for report-ready fitted-object dimensions, backend,
  sampler, model-family fields, prior scales, and data signatures.
- Add `model_manifest` for serializable data/spec/design/fit provenance,
  including column roles, level maps, validation status, parameter blocks,
  identification rules, constraint tables, prior-block declarations, prior
  scales, and diagnostic summaries.
- Add `fit_artifact` for cached-fit reproducibility records that combine the
  fit manifest, diagnostics, posterior summaries, sampler controls, optional
  RNG seeds, optional cached draws, and optional environment/package metadata.
- Add a `seed` keyword to `fit` so reproducible examples can record a local
  `MersenneTwister` seed in sampler controls.
- Add `cached_fit`, `fit_cache_key`, `save_fit_cache`, and `load_fit_cache` for
  RDS-like serialized fit caches with key-based stale-cache protection and
  load-time artifact-hash and hash-record metadata verification.
- Require an integer `seed` for automatic `cached_fit` / `fit_cache_key` reuse so
  cache keys cannot silently ignore non-replayable RNG state.
- Add `validation_suggestions` for machine-readable next-step guidance from
  validation issues.
- Add multi-chain support to the Julia random-walk backend and expose
  `mcmc_diagnostics` for classical split R-hat and effective sample size.
- Mark parameter-level `mcmc_diagnostics` rows with `:mcmc_warning` when R-hat or
  ESS fails the supplied thresholds.
- Add `sampler_diagnostics` for chain-level draw counts, acceptance rates, and
  log-posterior summaries, including AdvancedHMC/NUTS divergence, tree-depth,
  step-count, step-size, and E-BFMI fields when available.
- Add `diagnostics` as an integrated diagnostic surface combining sampler rows,
  parameter-level R-hat/ESS rows, parameter-block pass/fail rows, pass/fail
  counts, and HMC/NUTS fields when available.
- Add `parameter_block_diagnostics` for block-level R-hat/ESS summaries over
  person, rater, item, and threshold blocks.
- Add `posterior_predict` and `posterior_predictive_check` for posterior
  replicated scores and compact observed-vs-replicated summaries.
- Add `prior_predict` and `prior_predictive_check` for prior replicated scores
  and compact observed-vs-replicated summaries before fitting.
- Add `predictive_check_summary` for report-ready prior/posterior predictive
  check rows with replicated intervals and tail probabilities.
- Extend prior/posterior predictive checks and summaries to include person-level
  and optional-facet mean-score rows.
- Add `simulate_responses`, `parameter_recovery`, and
  `parameter_recovery_summary` for minimal MFRM/RSM/PCM simulation studies,
  including posterior bias, RMSE, interval coverage, and block-level recovery
  summaries.
- Add plotting-ready row helpers `parameter_recovery_plot_data`,
  `calibration_plot_data`, and `predictive_check_plot_data` without adding a
  plotting dependency.
- Add observation-level predictive probabilities, expected scores, variances,
  and residuals as the basis for future calibration, infit/outfit, and
  model-comparison helpers.
- Add `calibration_table` for binned observed-vs-predicted posterior
  calibration summaries from expected scores or category probabilities.
- Add `fit_stats` for posterior infit/outfit summaries by facet level.
- Add `waic` for WAIC summaries from posterior pointwise log-likelihood draws.
- Add `waic_diagnostics` for observation-level WAIC components and
  high-variance row flags.
- Add `compare_models` for WAIC-based comparison rows across fitted models.
- Require `compare_models` inputs to share the same observation data signature
  instead of accepting same-length but different datasets.
- Add WAIC-derived `relative_weight` values to `compare_models` rows for
  same-data candidate model tables.
- Add a Bayesian workflow documentation page that separates currently supported
  predictive checks from planned production diagnostics.
- Refine the roadmap around fit-ready GMFRM/MGMFRM gates: source-equation
  fixtures, identified raw transforms, prior/Jacobian policy, AD/HMC target
  proof, BridgeStan comparison, simulation recovery, and real-data evidence.
- Stabilize scalar validation log-probability paths with log-sum-exp.
- Add a non-optional scalar known-answer fixture for the analytic log-density
  and gradient, removing the default skipped Stan-fixture test path.
- Check that raw and contrast scalar parameterizations agree at the same
  constrained parameter values.
- Add the scalar Stan reference model, a BridgeStan-generated scalar
  log-density fixture, and a regeneration script under `scripts/`.
- Connect the scalar validation target to real `FacetData` input for one-item
  designs, replacing the previous synthetic-only construction path.
- Add a minimal Documenter site for the data-validation workflow and public API,
  with a CI documentation build job.
- Extend the GitHub Actions test matrix to Windows in addition to Ubuntu and
  macOS.
- Add `scripts/pre_registration_gate.jl` and a CI pre-registration gate job for
  clean import, metadata, Aqua, example, docs/test, diff, and wording checks.
