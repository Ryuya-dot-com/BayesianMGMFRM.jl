# BayesianMGMFRM.jl release notes

## Unreleased

### Added

- Add `BayesianMGMFRM.Experimental` as the canonical quarantine namespace for
  guarded scalar GMFRM and fixed-Q confirmatory MGMFRM work. It exposes design
  preview, fitting, cache-key, and cached-fit entry points plus a
  machine-readable stability and staged evidence contract. The existing
  `fit(spec; experimental = true)` path remains source-compatible during the
  migration but is no longer the recommended entry point for new experimental
  workflows.

- Add a quarantined response-level known-truth generator and single-dataset
  multichain pilot for the exactly two-dimensional free-latent-correlation
  MGMFRM candidate. Generation validates pure-Q coverage, Latin-square rater
  connectivity, direct constraints, shared-kernel probability replay, and a
  separately coded direct-scale closed-form probability oracle.
  Diagnostic-smoke and scientific modes remain quarantined, NamedTuple-only
  surfaces; the scientific mode enforces at
  least four chains with 500 warmup and 500 retained draws per chain, but no
  single-dataset result marks replicated recovery as verified or changes the
  public fit/cache contract.

- Add a frozen quarantined replicated-study control plane for that 2D
  free-correlation candidate. The unexecuted version-1 plan is explicitly
  retired into the version-2 lineage. Version 2 fixes a five-correlation roster of 25
  feasibility and 500 evaluation units, uses disjoint ability, response, and
  sampler seed namespaces, preserves every planned unit and categorized
  failure in an immutable ledger, and requires a digest-bound computation-only
  feasibility decision before evaluation. Future results must bind canonical
  plan, unit, seed, generation, sampler-control, runtime, Project/Manifest,
  source, and sample-bundle identities; cross-unit replay and mixed execution
  environments then fail closed. The feasibility decision retains rederived
  protocol-integrity evidence. Version 2 is pinned to plan fingerprint
  `d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3`
  and unit-roster SHA-256
  `0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08`.
  An optional MCMC-free resource probe can profile the initial gradient; the
  frozen plan currently records that probe and the short-NUTS profile as
  incomplete. A pre-execution harness uses no-replace hard-link publication
  for dry-run diagnostics while refusing all scientific attempt states. Its
  post-load file snapshots are not execution attestations or externally
  anchored signatures.
  The compatibility `study_run_unit` entry point is permanently preflight-only,
  so its `execute_mcmc = true` option always fails before generation; future
  scientific execution must use a separate non-public atomic worker that
  validates archive receipts before touching the sampler.
  Scientific execution stays blocked until a short-NUTS profile, pre-load
  immutable source snapshot, raw-draw archive, and full scientific runner are
  completed; there is no batch entry point. The versioned pure scorer reports
  conditional and fixed-denominator recovery, Wilson uncertainty,
  exact-rational endpoint-enumerated continuous uncertainty with directed
  Float64 bounds, zero-correlation false exclusion, and unpaired
  positive/negative-correlation symmetry. Only an unresolved interval wholly
  outside a limit is a hard continuous failure; a boundary crossing is
  inconclusive. It always keeps public fit, promotion, and
  replicated-recovery claims false; no replicated MCMC study is included in
  this release.

- Cache the fixed simple-Q integer layout in the quarantined 2D
  free-correlation scalar likelihood. The frozen 300-person benchmark reduces
  steady-state initial ForwardDiff gradient time and allocation by about 93%
  while preserving exact agreement with the source-aligned pointwise reference
  across dimensions and perturbations. This is performance evidence only, not
  recovery or promotion evidence.

- Add `design_identity` and a canonical model-contract guard for
  `FacetSpec`/`FacetDesign`. It rechecks the live encoded data against the
  validation signature, reconstructs derived spec fields, recompiles the
  expected parameter order, block ranges, and identification declarations,
  and returns a streaming SHA-256 semantic fingerprint. `getdesign`, numerical
  likelihood entry points, fit-cache requests, fit metadata, and design
  manifests now reject stale or hand-constructed noncanonical objects. Design
  manifests carry the fingerprint, so deterministic fit-cache keys now bind
  the same contract. `fit`, `MFRMLogDensity`, and guarded generalized targets
  retain validated deep snapshots; their stored design is semantically equal
  but no longer object-identical (`===`) to the caller's mutable design. The
  dedicated heldout-scoring path remains separate so LOO/K-fold scoring can use
  a training parameter map with heldout rows without weakening public fit
  guards. Fit-content and cache-envelope authentication remain the next cache
  integrity gate.

- Add a FACETS and ACER ConQuest migration guide for the overlapping minimal
  MFRM/RSM/PCM targets. It provides a runnable long-format Bayesian example,
  sign/identification/threshold/estimator crosswalks, visible rejection rules
  for unsupported weights and model structures, and staged hard-anchor,
  threshold/group-anchor, soft-anchor, and provenance round-trip policies.

- Add deterministic, manual-syntax offline bridge bundles for the unanchored
  one-dimensional, unit-weighted MFRM/RSM/PCM overlap with FACETS and ACER
  ConQuest. A Mac can generate control, rating, and mapping files with SHA-256
  manifests, plus Windows verifier/runners and a ConQuest-specific macOS
  verifier/runner for execution on an authorized host; returned inputs and
  declared raw outputs can be checked and bound to a receipt on the originating
  machine. The manifest identity commits
  the full transfer and required-output contract. Default label hashes are
  explicitly recorded as unsalted pseudonyms, not anonymization.
  Host-preflight records expose the verifier and runner hashes for independent
  comparison because a transfer-contained launcher is not a trust anchor.
  ConQuest automatic filename extensions are disabled so declared output names
  remain exact, and receipts distinguish operator-reported completion from
  independently verified execution. Receipt hashing, fatal-marker inspection,
  and ConQuest parameter-row validation use bounded streaming reads rather than
  retaining raw return files in memory.
  Category-universe checks reject source cells whose observed endpoints would
  silently narrow an external response denominator, and the ConQuest reader
  accepts documented positional parameter-number/value exports with an optional
  single ConQuest source comment while keeping semantic identity unresolved.
  `load_conquest_semantic_parameters` adds a separate fail-closed semantic
  layer for the exact ConQuest 5.47.5, three-category RSM/PCM boundary. It
  requires a complete returned bundle, regenerates and matches the source
  control/rating/identifier/category/observation inputs from the supplied
  specification, constructs a receipt from the current returned-file snapshot,
  verifies parameter comments and the complete design basis, and reconstructs
  term-wise sum-to-zero rater, item, and step values
  without a global sign reversal. The artifact keeps destination-gauge
  alignment, convergence, anchor construction, and numerical comparison
  disabled.
  A privacy-reduced, version-specific fixture records successful RSM and PCM
  known-truth executions of ConQuest 5.47.5 Demonstration on macOS through the
  hardened verifier/runner. It retains the executed control, manifest,
  verifier, runner, receipt, and four privacy-reduced raw outputs per model;
  tests rebuild bundle and receipt identities, verify the 15-record output
  inventories, reconstruct constraints, select the minimum-deviance iteration,
  and recompute block RMSE. It contains no row-level ratings, person estimates,
  original labels, executable, or activation material. Bytes for 11 receipt-
  inventoried raw outputs per model are intentionally omitted. Independent
  execution, software authentication, convergence adjudication,
  reference-gauge alignment, anchored second-stage calibration, direct package
  agreement, and product equivalence remain open.

- Add `anchor_refit_plan` as a fail-closed, plan-only preflight for candidate
  individual rater/item hard anchors and later soft-anchor work. It validates
  target observability, model/threshold compatibility, normalized destination
  scale and sign, source provenance and SHA-256 shape, finite representable
  values, reference-level conflicts, and hard-versus-soft fields. It records
  the affine direct-parameter refit strategy but does not yet execute an
  anchor-constrained fit or verify the referenced source bytes.

- Add a fail-closed repeated recovery scorer to the existing-API sparse and
  nonrandom-assignment stress runner. Successful scoring requires exact
  truth-parameter sets, internally consistent recovery rows, modern sampler
  diagnostics, complete-chain E-BFMI, canonical pilot/calibration rosters,
  pre-response assignment/event/truth/sampler hashes, exact regeneration of
  pilot/calibration preflights from canonical options, a content-addressed
  pre-response freeze-input record bound into the later freeze contract, a
  content-hashed and contract-consistent pilot artifact, and reaggregation
  from paired rows inside the gate. Pilot observations, statistical policy,
  reviewed thresholds, revision, and time are sealed in one threshold-decision
  record rather than accepted as detached inputs. Coverage treats
  replications as clusters and uses a fixed upper uncertainty bound;
  parameter-row Wilson values are sensitivity-only. Block MAE, focal absolute
  error, and posterior-SD calibration use fixed quantiles while raw extrema
  remain stress sentinels. A passing result is explicitly named a
  well-specified-static distributional gate under the recorded contract, not
  recovery of every cell or parameter. Julia, Project, Manifest, and source-tree
  hashes are bound; clean immutable VCS state, external chronology attestation,
  raw draw/cache identity, and broader recovery/public claims remain false. The
  versioned fixture remains MCMC-free, predictive and decision-stability
  scorers remain incomplete, and no design-robustness claim is released.

- Add MFRM-only `category_functioning_summary` rows for overall, rater, and
  item category use, posterior predictive replicated proportions, RSM/PCM step
  uncertainty, and adjacent-step ordering probabilities. Sparse, skipped, and
  predictive discrepancies are diagnostic review prompts; the API never
  collapses categories or refits the model automatically.
- Add MFRM-only `rater_homogeneity_summary` with draw-wise pairwise severity
  contrasts, explicitly labelled central posterior intervals, probability of
  direction, optional user-declared ROPE probabilities, and direct, network,
  or disconnected rater-overlap support. Positive contrasts mean rater A is
  more severe; the rows do not equate severity homogeneity with observed-score
  agreement or bias evidence.

- Preserve the byte-exact TAM direct-agreement refinement snapshot used by the
  retained execution jobs. A separate aggregate entrypoint and the all-attempt
  audit now verify selected-job and retained-attempt input, fixed-truth, seed,
  and environment lineage against that immutable snapshot without rerunning
  MCMC. The older refinement hash in the
  pre-execution review packet remains unchanged as a chronology-review blocker;
  exact execution lineage does not release independent-review or public-claim
  gates.

- Add rank-normalized split R-hat, bulk ESS, and tail ESS to the shared MFRM,
  guarded GMFRM, and guarded MGMFRM diagnostic rows and block summaries.
  Generalized quality gates inspect both raw unconstrained and direct
  constrained parameter surfaces. For odd split chains, bulk metrics discard
  the center draw before ranking, folded R-hat folds around the untrimmed pooled
  median before the same discard, and tail ESS fixes pooled tail quantiles
  before splitting. ESS uses all available valid split-chain lags, matching
  Stan/posterior semantics.
  Existing `rhat` and `ess` fields remain as classical compatibility outputs;
  they are not the primary convergence gate. A versioned diagnostic contract
  is included in generalized fit-cache identity so stale provisional
  diagnostic surfaces are not silently reused.

- Keep direct constrained coordinates that are fixed by zero-raw-dimension
  transforms in diagnostic output as `:structurally_fixed`, with
  `quality_gate_applicable = false`. They do not enter extrema or failure
  counts; reconstructed constrained coordinates that still vary with free raw
  coordinates remain gated. The primary `flag` now follows
  `rank_normalized_flag`, while `classical_compatibility_flag` preserves the
  legacy assessment.

- Add complete-chain E-BFMI accounting to sampler summaries. The existing
  minimum available `e_bfmi` is retained for compatibility, alongside
  `n_e_bfmi_expected`, `n_e_bfmi_available`, `n_e_bfmi_unavailable`, and
  `e_bfmi_complete`. Publication checks apply the E-BFMI threshold only when
  all chains have finite values; a missing or non-finite energy value within a
  chain makes that chain unavailable and the coverage incomplete.

- Correct the publication-grade refit runner so diagnostic rows named
  rank-normalized R-hat, bulk ESS, and tail ESS read the explicit modern
  summary fields and carry the diagnostic-contract identifier. Previously
  committed job artifacts are retained as pre-modern historical evidence and
  are not reinterpreted as contract-bound modern diagnostics. Modern metric
  rows are marked missing/failing when any raw or direct parameter row is
  insufficient, non-finite, or degenerate, so finite extrema cannot mask an
  invalid diagnostic surface. The result, diagnostic, and heldout wrapper
  schemas remain version 1; a row is modern only when its
  `diagnostic_contract` is `rank_normalized_rhat_bulk_tail_ess_v1`. Missing or
  mismatched contract identifiers now make every MCMC-required publication
  gate value missing and failing.

- Add explicit `response_id` and `testlet_id` metadata roles without changing
  the fitted MFRM/GMFRM/MGMFRM likelihoods. Add `testlet_design_audit` to check
  response nesting, duplicate rating keys, target-specific replication,
  mechanism-specific connectivity, joint halo support, repeated responses,
  replicated rater-by-task crossing, connected fixed-Q dimension-by-testlet
  contrasts, and testlet-stratified pair support. The audit separates
  structural eligibility from unavailable fitting and mechanism claims.
- Add `predictive_standardized_residuals` for draw-specific Pearson score
  residuals with explicit low-variance exclusions and errors for non-finite
  predictions. Add a machine-readable `local_dependence_contract` that keeps
  single-rating item, within-rater item, and rater-pair estimands separate,
  forbids implicit aggregation, and separates pairwise localization from the
  all-family maximum-statistic decision. Q3/aQ3 decisions and fitted testlet
  effects remain outside the current model API pending calibration.
- Add report-only `local_dependence_summary` for MFRM and guarded GMFRM/MGMFRM
  fits. It reports testlet-stratified Q3-style and adjusted-Q3-style item pairs,
  same-response/same-criterion rater pairs, paired posterior predictive tail
  fractions, within-family BH values, support graphs, sparse reason codes, and
  one all-family maximum-statistic reference. Posterior draws are distinct and
  sampled without replacement; criterion-split responses are not silently
  treated as single-rater item pairs. Applicability and support are separated
  by testlet, so an inapplicable criterion-split stratum does not suppress a
  valid single-rating stratum. Zero-overlap combinations remain in aggregate
  support rows; audit-pair, shared-unit, positive-pair-by-draw, and predictive-
  cell preflights bound large work and allocations. Decision labels, universal
  cutoffs, and mechanism attribution remain unavailable pending independent
  calibration.
- Add `local_dependence_simulation_grid` and `simulate_local_dependence` as the
  completed LD1a known-truth generator and design-preflight surface. The frozen
  22-scenario plan covers null and exact-zero controls, study-local near-zero
  through large person-by-testlet variation, support boundaries, connected and
  rejected sparse designs, rater-response halo, crossed and nested
  rater-by-task severity, omitted multidimensionality, randomized drift,
  ability-confounded no-drift order, ability-informed rater assignment, and a
  testlet-plus-sequence mixture. The
  adjacent-category response kernel is implemented independently of the fitted
  likelihood, uses semantic event-keyed response uniforms and facet-specific
  keyed streams,
  preserves the intended category scale, records complete generating truth,
  and applies pre-allocation rating, probability, truth-cell, and design
  preflights. Repeated LD1b calibration remains
  pending; the study-local magnitudes are not universal cutoffs, and existing
  `decision_labels_available = false` and
  `mechanism_interpretation_eligible = false` fields remain unchanged.
- Add the LD1b0 calibration protocol and pure aggregation surface. It validates
  planning-row and simulation provenance, reserves independent semantic seed
  namespaces for fitting, draw selection, and posterior prediction, records
  structural rejections and execution failures without treating them as
  negative findings, and separates pair, family, and global candidate
  reference behavior. Wilson intervals are limited to replication-level binary
  rates; pooled pair fractions remain descriptive. This addition runs no MCMC,
  does not yet establish pairwise power under alternative mechanisms, and does
  not enable observed-data decisions or mechanism labels.
- Add `local_dependence_calibration_pilot_contract` and
  `local_dependence_calibration_pilot_preflight` for the LD1b1 pilot
  execution-protocol preflight. The MCMC-free
  `local_dependence_pilot_protocol_preflight.json` artifact fixes 30
  replications across each of the 22 scenarios (`30 × 22 = 660`), yielding 540
  eligible fitting jobs, and 120 planned structural rejections. Retry outcomes
  are additive records and cannot replace an original failure. Operational
  candidate bounds are study-local, and the 50- and 100-replication evaluation
  sizes remain candidates to be chosen and frozen after the pilot and before
  evaluation. This preflight runs no fit or MCMC. Rank-normalized R-hat and
  bulk/tail ESS are now available, so the preflight authorizes the pilot
  execution protocol only when the exact full dependency and operation record,
  primary diagnostic fields, tail probability, minimum chain and draw
  requirements, complete-chain E-BFMI coverage, and the SHA-256 digest of
  `src/bayesian_fit.jl` match the frozen plan. The pilot itself remains unrun;
  authorization is not execution evidence. Repeated calibration,
  pairwise power, diagnostic decisions, and mechanism interpretation remain
  unavailable.
- Add the MCMC-free `local_dependence_pilot_batch_execution_harness.json` dry
  run for the same 660-row plan: 540 eligible fitting jobs and 120 planned
  pre-fit rejections. The controller and generator sources are identified,
  while the execution plan remains incomplete until the canonical single-job
  executor is materialized and its SHA-256 is included. The contract requires
  each role-specific evidence envelope to identify one source
  artifact by bytes and SHA-256, and verifies exact upstream evidence hashes.
  It rejects changes to the frozen `pilot_contract` or ordered 660 job rows by
  their canonical SHA-256 values. A `pre_fit_rejected` result requires the
  `generated_data` -> `structural_rejection_audit` -> `calibration_row` chain,
  with the final row using the existing public calibration-row contract.
  Simulation members are checked for response data, table columns, probability
  cells, truth and row-truth arrays, and data/score/design signatures. Fit
  members use the structured `local_dependence_pilot_fit_artifact_export.v1`
  JSON wrapper containing retained draws, log posterior values, and sampler
  statistics. Its package-native content hash must be verified by the future
  pinned canonical executor before JSON projection; the batch runner separately
  recomputes the canonical JSON payload hash and verifies the exact file
  SHA-256. The JSON projection cannot soundly reconstruct the native typed
  hash. Generated resource counts must match the frozen job. Sampler
  evidence is checked against the fixed controls and the individual R-hat,
  bulk/tail ESS, divergence, depth, and complete-chain E-BFMI gates. Fit,
  sampler, local-dependence, and calibration members must agree on their data,
  design, fit-artifact, retained-draw, chain, and iteration provenance. The
  custom `local_dependence_pilot_summary_bundle.v1` directly records the
  draw-selection and posterior-predictive seeds; the runner compares both with
  its evidence payload, the frozen job, and the calibration execution seeds.
  Draw selection uses the frozen `sha256_seeded_rank_without_replacement_v1`
  algorithm, and the runner recomputes its ordered draw indices from the frozen
  seed. The posterior-predictive seed is source-bound, but seed-to-result replay
  verification remains pending the canonical single-job executor and bounded
  smoke review. A
  `diagnostic_failed` record may name `sampler_quality_gate` only when that gate
  failed, or `local_dependence_summary` only after the gate passed.
  Symbolic links, hard links, and unmanifested files are rejected, and validated
  snapshots are rechecked against the final attempt inventory. This static
  recheck is not an atomic completed-attempt seal. The controller carries
  primary-result and evidence digests into checkpoint and aggregate state. It
  preserves nonoverwriting primary outcomes and additive remediation. On
  resume, it first rescans the complete attempt archive as the source of truth,
  then verifies and compares the derived checkpoint, and skips only verified
  terminal primary records. A dry run
  reports archive integrity as not assessed. The canonical single-job executor
  and bounded smoke review remain pending, so execute modes are unavailable.
  A completed-attempt seal and an append-only recovery or retirement path for
  interrupted partial attempts are also required before execution.
  No response data are generated, no model is fitted, and no MCMC is run;
  pilot results, calibration or power estimates, diagnostic decisions, and
  mechanism interpretations remain unavailable.
- Add a deterministic existing-API design-robustness plan and versioned
  artifact. It verifies row-order and `occasion` invariance, rejects an
  ability-nested no-link design before fitting, materializes separate 5% and
  10% all-rater common-linking conditions, and keeps parameter anchors,
  multiply-scored targets, controlled benchmarks, and common linking responses
  distinct. Paired MFRM/GMFRM/MGMFRM recovery remains
  explicitly unrun and blocked from public claims.
- Add the corresponding MCMC-free stress-grid runner and versioned dry-run
  artifact. The dry run materializes 24 model-design cells and 21 paired
  well-specified/omitted-order-effect datasets, verifies six three-family row
  permutation contracts plus three same-event early/distributed placement
  contracts, and records achieved common-linking, target-coverage,
  rating-budget, order/ability, assignment/severity, multidimensional
  Q-active-source, and outcome-dispersion metrics. Replication seeds resample
  the assignment/order skeleton while paired A/B conditions share one
  realization. Full-range common sets use constrained seeded selection, and
  all requested pilot/calibration skeletons are design-preflighted before
  fitting. This remains design and likelihood-contract evidence only: it does
  not run MCMC or support recovery, calibration, or design-robustness claims.

### Changed

- Replace the single roadmap completion percentage with a denominator-specific
  maturity dashboard. The declared minimal Bayesian MFRM/RSM/PCM core is now
  tracked separately from external validation, narrow TAM overlap, FACETS and
  ConQuest bridges, generalized-model maturity, and non-goal product parity.
  The roadmap also distinguishes Bayesian HMC/NUTS completion from optional
  future JMLE/MMLE interoperability and clarifies that the current anchor API
  provides declarations and diagnostics rather than anchor-constrained refits.

- Remove research-sequencing metadata from the public diagnostic row policy and
  make its informational and failure flag vocabularies disjoint.

- Put the existing static API through a dedicated design-robustness gate before
  the temporal-drift study. The paired grid crosses sparse-link
  topology, ability-informed assignment, linking amount/range, additive versus
  fixed-total-target-displacement rating budgets, and latent/outcome
  dispersion. It separates a
  correctly specified recovery track from an omitted-order-effect
  misspecification track and records requested-versus-achieved design metrics.
- Refine the research roadmap with an explicit temporal-confounding gate for
  rater-drift claims, a predeclared stress-test design crossing severity drift,
  ability/order composition, temporal benchmark placement, assignment, and
  design sparsity, and a primary-research map for broader rater-process,
  decision, and human--machine extensions.
- Insert a local-independence and clustered-rating gate between static design
  robustness and temporal drift. The roadmap now separates person-by-testlet,
  rater-by-response halo, rater-by-task severity, multidimensional, and
  sequence mechanisms; specifies identification and variance-boundary rules;
  and requires known-truth mechanism-confusion tests plus target-specific
  cluster predictive validation before fitted testlet or drift claims are
  promoted.
- Clarify that the current optional `occasion` metadata and parameter-anchor
  summaries do not establish within-rater order, randomized presentation, or
  time-distributed benchmark-response support for dynamic interpretations.
- Track the detailed MGMFRM research-roadmap page in both claim-level and
  full-paper reproduction archives so roadmap wording changes invalidate the
  recorded code/document hash set.

### Fixed

- Keep the free-correlation pre-execution runner's workspace-environment
  attestation strict under `Pkg.test()` by running its environment-bound test
  in a fresh Julia child process with the repository project, rather than
  evaluating it in Pkg's temporary test project.
- Make `docs/build.jl` activate and refresh the ignored docs environment before
  building, bind both `docs/build.jl` and `docs/make.jl` into the claim/full
  reproduction archives, document `Manifest-v1.10.toml` as the tracked Julia
  1.10.8 lock, and run the bounded free-correlation candidate and recovery
  diagnostic smokes explicitly in their dedicated CI job.
- Align the roadmap's full-archive code/document reference count with the 114
  records required by the fixture and tests.
- Refresh the guarded-fit dry-run fixture for the canonical experimental
  namespace, then refresh its dependent policy, claim, full-paper, and exposure
  review artifacts so both package tests and the manual strict archive gate
  reflect the current tree.

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
