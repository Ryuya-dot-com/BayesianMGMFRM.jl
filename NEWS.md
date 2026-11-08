# BayesianMGMFRM.jl release notes

## 0.1.2 (unreleased)

### Documentation and entry-point organization

- Organize `README.md` and the 38-page manual into six reader-oriented sidebar
  sections with a self-contained Quick Start output preview, a verified
  bring-your-own-table snippet, a software comparison table (`FACETS`,
  `ACER ConQuest`, `R (TAM / mirt)`, `brms / CmdStan`), a 5-minute Julia
  beginner's guide, an embedded 2×2 visualization gallery covering all 12
  `BayesianMGMFRM.plot(x; kind = ...)` modes, a Glass-Box API summary, and a
  manuscript reporting checklist with an illustrative Methods and Results
  template. No model, prior, sampler or saved-result schema changes.

### Local development: joint A–C fitted and predictive lifecycle

- The experimental Plackett association uses the shared fitting, summaries,
  marginal reporting and save/reopen workflow, including the unchanged association
  coordinate under `pair_132`. Its explicit Normal prior on log(psi) is retained.
- Prior and posterior checks generate the ordinal pair jointly. Predictive v3
  records the replication law; prior v2 and posterior v1/v2 independent-model
  reports remain readable. Unqualified-fit and unresolved-precision warnings persist.
- High-precision association fallbacks share a lock across threaded chains;
  no empirical adequacy, calibrated detection or universal speed claim is made.

### Local development: concurrent numerical priors

- The experimental concurrent 9/9/2 route accepts `ConcurrentPrior(preset; ...)`
  through its existing `getdesign` lifecycle. Gaussian/half-normal/LKJ numerical
  settings propagate to gradients, prior prediction, fitting and saved records.
- Portable model v2 retains complete custom settings and reads legacy preset v1;
  native plan v3 still requires its original source/environment. A full-interaction
  Stan data/reference adapter supports finite independent equation checks.

- Concurrent fits publish validated chain bytes without saving a second full copy.
  Failed validation or publication retains the returned record for diagnosis;
  completed-file names, native format and fitted results are unchanged.

- Concurrent targets now support `prior_predictive_check` and the shared
  `predictive_check(target; ndraws, seed)` entry. Independent joint-prior draws,
  replicated counts, explicit prior provenance, independent-draw precision and
  checksum report persistence are separate from fitted posterior checks.
- Concurrent prior/posterior predictive v2 reports preserve exact RNG seeds as
  decimal strings. Posterior v1 reports remain readable, with possible rounding
  of their stored large stream seeds; their original numerical results are retained.


- Concurrent fitted 9/9/2 results now support `predictive_check` and the existing
  `posterior_predictive_check` entry point. These generate **posterior** predictive
  responses from retained joint states, preserving original warnings, observed
  panels and chain identities. Reports explicitly label posterior versus prior
  parameter provenance, retain discrete CDF precision limitations, and use shared
  portable save/load operations. Prior predictive and new-level generation for
  this concurrent target remain unsupported; no native migration is supplied.

- `prior_sensitivity` accepts scientific factor powers for saved independent
  D1 fixed-one PCM `MeanProfilePrior` fits. `logprior` exposes normalized judge
  and all-owner step factors; units, original chain IDs, failed weights and
  matching supplied alternative fits remain explicit. Mean/paired-shift MCSE
  is a chain-aware plug-in approximation; quantile/decision precision remains
  uncomputed. Shared `save_report`/`load_report` preserve computed results with
  a separate checksum receipt. No automatic refit or native-cache migration.

- Star `prior_sensitivity` now recognizes an exactly unchanged resolved prior
  and returns `:unchanged_prior` instead of requesting a refit. Its PSIS diagnostics
  are `nothing` (JSON `null`); baseline sampling warnings and uncertainty remain.
  Different priors with constant observed weights still retain PSIS failure diagnostics.
  Existing saved reports are preserved; native fits remain bound to their producer
  source and environment.

- Common `criteria`, `compare_models` and `psis_loo` now select standard PSIS
  with chain-based relative efficiency, rather than the earlier Hill approximation.
  Choose `:hill_smoothed_loo` explicitly to retain historical arithmetic. Existing
  saved results, raw IS-LOO reports, WAIC and specialized-model kernels are unchanged.
  Fitted PSIS rejects draw subsets; matrix inputs without chain IDs or `r_eff`
  return an independence-assumption warning. Custom Hill tail controls are refused
  for standard PSIS. Constant tails and unavailable efficiency remain warnings.
  Finite reference agreement does not establish model-selection accuracy or
  calibrated uncertainty; the common comparison still does not compute MCMC MCSE.

- The concurrent three-outcome `prepare_fit`/`fit` route accepts `chain_execution=:threads`
and `max_parallel_chains`, retaining serial execution by default. Prepared chain seeds
remain identical across schedules. Plans, controls and computed reports expose the
effective worker count; progress covers all chains, and failures join active workers
while preserving completed files. Parallel workspace and elapsed speedup depend on
the machine and target. No model, prior, adaptation rule or qualification gate changes.

- Parameter diagnostics no longer allocate a full split-chain array solely to
  determine its dimensions. Per-parameter calculations, diagnostic fields,
  thresholds and retained draws are unchanged; other dense workspaces remain.

- Concurrent three-indicator targets now use shared preparation/fitting, diagnostics,
  joint posterior contrasts/probabilities, MCSE and native/portable persistence.
  Completed chains and failures are retained; incomplete or numerically unsuitable
  results retain their warnings. This does not establish empirical qualification.
- Concurrent three-indicator targets now share `event_probabilities`, `contrast`,
  `save_report` and `load_report`: observed events, eight preliminary contrasts
  and an explicit ENG reference panel at fixed points, with retained weights,
  extrapolation warnings and checked portable results. Concurrent model JSON
  also reloads through `load_report`. Fixed-point reports contain no posterior
  uncertainty; use the concurrent fitted workflow above for joint-draw reporting.
- `Experimental.ThreeIndicator.ConcurrentInput` adds a separate concurrent
  9/9/2 mathematical target with optional diagonal/full listener×word covariance.
  Shared `getdesign`, density/gradient, coordinate and model-specification saving
  operations preserve the original hierarchical priors by exact Gaussian
  convolution. This does not extend the preliminary-only fitting/reporting route
  or provide empirical acceptance of the concurrent model.

- A table overload of `mfrm_spec` accepts arbitrary user-named additive facets
  and explicit global/facet-owned steps. It provides sparse design inspection,
  normalized density and analytic gradient, coordinate/prior inspection,
  fixed-coordinate probabilities and seeded prior generation. The shared fitted
  lifecycle now includes analytic NUTS, named joint summaries/MCSE and contrasts,
  known-level posterior probabilities, numerical qualification and native/portable
  saving. Unknown levels and rank-deficient fits are refused. Existing
  `FacetData` construction, fitting and prior meanings remain unchanged.

- Criterion-collapse results now support explicit performance/rater-profile LOO
  through `criteria(...; unit=:performance_rater)` and predictive comparison
  through `compare_models(...; criterion=:loo, unit=:performance_rater)`.
  Conditional density/proposal-ratio inspection, PSIS diagnostics, approximate
  paired chain-aware delta MCSE and portable reports preserve the original
  finite-panel prior. No WAIC, iid comparison SE or new-level claim is added.
- Generalized summaries accept `scale=:model` or `:raw`, retaining the historical
  default and `direct_posterior_summary` spelling. For scalar/fixed-Q GMFRM/MGMFRM
  and normalized/correlated-2D MGMFRM, `posterior_summary` and `posterior_mcse`
  accept `estimand=:adjacent_logit_slope`. The optional `fit_report` section
  `include_effective_slopes=true` retains joint-draw products, literal multipliers,
  fixed/Q-zero status, credible intervals and MCSE through portable reports.
  No likelihood, prior, sampler, saved draws or default report sections change.

- CriterionCollapse now supports shared `compare_models(result)` for induced
  all-ordinary versus at-least-one-collapse model evidence, and
  `predictive_check(result; category, ...)` for exact same-design joint count
  predictions. Persistent classes, posterior conditioning, chain-aware MCSE,
  diagnostic warnings and portable save/reopen are retained. These operations
  do not provide held-out WAIC/LOO or calibrated mechanism classification.

- `compare_models` accepts observation-bound common-model comparisons through
  an explicit `comparison_axis`, retaining the existing `compare_predictions`
  checks. Star comparisons preserve named inputs, align event IDs and verify
  actual outcomes/supports; older criteria lacking observation bindings cannot
  be compared. Existing estimators, SE conventions and legacy ranking remain,
  with their differences documented explicitly.

- Unified persistence: `save_report(path, result)` now summarizes Star and the
  supported experimental sample records, and `return_receipt=true` provides a
  common path/SHA-256 receipt. Native directories and portable reports dispatch
  by stored schema; reader/writer controls are forwarded or rejected, never
  ignored. Required checksums, model checks and legacy return values remain.

- Experimental `qualify` now applies caller thresholds to raw, transformed and
  conditional diagnostics instead of returning an old qualification decision.
  Original diagnostics/warnings and existing chain requirements are retained;
  missing telemetry cannot qualify. Rater-group diagnostic delegation is repaired,
  and unsupported diagnostic keywords are rejected.
- Clarify the scalar Glass-Box ForwardDiff route and distinguish exact star-model
  transformations from clipped reference-information/routing approximations.
  Default initial step-size search no longer adds a hidden floor/cap or silently
  replaces a failed search; the explicit clamped pilot option retains its bounds.
  No likelihood, scientific prior, saved-fit schema or model support is changed.


- Add opt-in `Experimental.Correlated3D` generation, centered NUTS, named marginal/partial correlation and conditional row-probability summaries, and source-bound native persistence. The restricted fixed-Q domain remains Experimental; scientific calibration and broader composition are not established.

- Added the opt-in Experimental `JointRatings.OrdinalAssociation` workflow for
  explicit criterion means, estimated person scales and within-event ordinal
  association. It requires explicit priors and preserves joint raw draws plus
  conditional-location uncertainty through native save/reopen, named reporting
  and contrasts. Independent finite target checks and saved-result transfer do
  not establish scientific prior choice, adequate fit or posterior agreement
  with another engine. Existing JointRatings behavior is unchanged.

- Clarified the development outcomes and their dependencies: bounded foundation
  preparation, independent acceptance, matching delivery and separate capability
  branches. Distinguished remaining development work from conditions users must
  check in each analysis. Model, API and support statuses are unchanged.

- Added a worked native ConQuest category-use comparison to the interpretation
  guide. It explains fitted count matching through score equations, the limits
  of in-sample fit and the difference between fixed-MML and joint-posterior
  predictive uncertainty. Updated the roadmap to retain the bounded result;
  no model, prior, sampler, API or support status changes.

- Clarified the development roadmap and external-software comparison guide:
  common-posterior verification and competing-analysis evaluation have different
  requirements. Criterion collapse remains distinct from signed halo/horns and
  general impressions. The manual now exposes the roadmap and model-evidence
  pages. No model, prior, sampler, API or support status changes.

- Added optional CriterionCollapse class/category figures with separate MCSE
  scales, full diagnostic/prior notes and explicit unavailable precision.
  `CriterionCollapse.load_report` verifies computed JSON against a retained
  SHA-256; figures can use these stored summaries without native samples or
  refitting. No classification cutoff, credible interval for the class
  probability, predictive fit test or scientific acceptance is introduced.

- Added `Experimental.CriterionCollapse` for the bounded scalar rater-level
  criterion-collapse mixture: explicit exchangeable priors and allocation
  checks, NUTS with progress/bounded threads, class-probability and conditional
  category means/MCSE, global warnings, and native/report persistence. The
  example uses fixed saved simulated data. No automatic class cutoff, calibrated
  detection, signed halo/horns, general composition or scientific default is
  implied.

- Added Experimental observed-group rater severity fitting with explicit cohort
  means, allocation identification checks, analytic gradients, bounded parallel
  chains, paired posterior contrasts, diagnostics and native save/reload. See
  the group-effects guide; existing residual DFF screening is unchanged.

- Existing MFRM/GMFRM/MGMFRM fit artifacts now retain chain/iteration row indices
  when draws are requested; scalar columns have explicit names and public
  artifacts preserve actual prior/settings metadata. A saved scalar-fit example
  carries joint draws, reference/prior context and diagnostics into JSON for
  independent calculations. Priors, inference and native fit types are unchanged.

- Qualification now uses shared `max_rhat`, `min_ess`, `min_bfmi` controls for Star
  results, retaining the original aliases. Omitted transformed diagnostics or
  incomplete/misaligned telemetry cannot pass its whole-fit gate; invalid
  thresholds are rejected. Reports declare the exact focal-precision scope.
- Common-fit qualification explicitly leaves focal MCSE unassessed. Probability
  help distinguishes draw arrays, interval reports, joint/marginal targets and
  probability uncertainty from future-score variation.
- Repair the fixed-Q multidimensional MFRM probability/PPC delegation, including
  correlated abilities and exchangeable raters. `event_probabilities` and
  `predictive_check` reuse the existing verified reconstruction and conditional
  replication kernels; probability arrays and legacy seed-based reports remain.

- Concurrent fitted plans expose effective adaptation windows and warn when a
  requested diagonal metric will remain at its initial identity. Fitted controls
  and reports preserve actual metric changes and final inverse mass; sampler
  settings and inference algorithms are unchanged.

### Unified workflow corrections

- Unified report loading forwards completeness, record and checksum controls to
  the owning reader; unsupported controls are rejected by that reader.

- Qualification rejects degenerate/undiagnosable free coordinates and incomplete
  NUTS telemetry, while retaining missing event counts and stored warnings.
- Common-fit `criteria` honors criterion/LOO controls and keeps the same estimator
  with observation IDs. Draw subsetting and unknown options are rejected.
- Raw parameter names match the sampled columns for normalized, correlated and
  fixed-Q fits.
- Star posterior, diagnostic and predictive figures consume the actual report
  contracts. Predictive figures show category proportions and 95% replicated intervals.
- A complete Star example supplies explicit priors and valid event IDs; model
  support documentation distinguishes the restricted 3D and Star routes.


- Fix shared posterior MCSE estimation to consider all available split-chain
  autocorrelation lags instead of the dependency's default cap of 250. This
  prevents truncation of persistent autocorrelation from understating precision
  error. Apply the same rule to RW1 conditional-bridge MCSE and ESS. Posterior
  draws, model, prior and sampling are unchanged; existing
  computed reports retain the results of their producing version.

- Add `Experimental.RaterGroupEffects.category_predictive_check` for one declared
  rater/group category count. Exact conditional Poisson-binomial integration
  uses all joint draws without response simulation, retains mean MCSE and global
  warnings, and bounds recurrence work explicitly. Inclusive predictive tails
  are exploratory, with no automatic misfit, mechanism or fairness decision.

- Correct the overview and reporting table to identify the separate fitted
  rater-item/group severity routes while retaining validation-only common bias
  terms. Connect numerical precision, prediction, prior sensitivity, halo/drift
  mechanisms and substantive fairness in the existing interpretation guides.
  This documentation change adds no fitted model or reporting API.

- Added `Experimental.RaterGroupEffects.category_report` for observed-versus-
  expected category use and mean scores overall and within rater/group and
  item/group cells. It preserves missing cells, declared categories, joint-draw
  intervals, MCSE and whole-fit warnings, with a bounded aggregation workspace.
  Expected-value intervals are descriptive, not predictive fit tests. The
  saved-result example writes this report without new inference or simulation.

- The observed-group rater example now separates within-group gaps, group changes,
  whole-fit diagnostics and focal precision, retaining explicit failed or
  unavailable checks in a labelled saved assessment. The fitted model and
  sampler are unchanged.

- Make Turing an optional backend extension. Core input, AdvancedHMC and saved
  results use explicitly declared mathematical dependencies. To select Turing,
  add it to the analysis environment and run `import Turing` before fitting.
  The Turing target, adaptation schedule, defaults and saved result types remain
  unchanged; cache-key validation and saved Turing results do not require loading
  the sampler. No installation-time or sampling-speed guarantee is implied.

- Copy exact JSON tokens into fresh byte storage without source-alias checks,
  avoiding repeated hashing of the complete source string when loading large
  reports. Preserve exact integer tokens, signed zero, schemas and payload hashes.

- Split only the requested parameter's chains when calculating classical
  compatibility diagnostics. Avoid repeatedly copying the entire parameter
  cube during normalized-fit restoration and reporting; diagnostic definitions
  and thresholds are unchanged. Stop unused classical autocorrelation work at
  the original positive-pair cutoff, and reuse item thresholds within each
  pointwise likelihood evaluation without omitting validation.

- Accumulate `category_report` expected use by facet level without allocating
  the full draws-by-observations-by-categories tensor. Retain all draws, categories,
  conditioning, warnings and report fields. `max_prediction_cells` now bounds
  aggregation/logit workspace; it does not bound source-fit or MCSE memory.
  Summation order and resulting content hashes may differ from dense prediction.

- Add explicit bounded chain concurrency to scalar/shared independent
  AdvancedHMC fitting with `chain_execution=:threads` and `max_parallel_chains`.
  Preserve legacy serial streams by default; record independent per-chain seeds,
  isolate working state, retain chain order and diagnostics, join workers on
  failure, and aggregate progress across chains. Automatic caches distinguish
  the threaded RNG strategy; manual saved types and posterior targets are unchanged.

- Evaluate the existing normalized D1 slope-restricted Gaussian prior by active
  parameter blocks, avoiding full-vector copies and repeated block searches.
  Preserve zero-sum normalizers, mean profiles, finite-input validation, model
  identity and saved types. Likelihood, analytic score and sampler are unchanged.

- Reuse checked sample records inside normalized and correlated MGMFRM report
  contexts and report composition. Preserve posterior summaries, diagnostics,
  ranking warnings, source checks and saved formats; subsequent public calls
  still revalidate mutable inputs. No inference or prior changes.

- Show ordinary scalar MFRM's default zero references before fitting and explain
  their free-coordinate prior meaning in saved reports. References follow stored
  label order, not input row order; changing them without transporting the joint
  prior can change the model. Preserve hard-anchor and numerical warnings.
  Clarify reference invariance, fit-statistic comparability and decision sensitivity
  in the existing guide. Priors, likelihoods, samplers and saved fit types are unchanged.

- Accept explicit `rater=nothing` in `FacetData` for scalar unit-slope
  Rasch/1PL, PCM and RSM responses without a rater column. Preserve the absent
  facet in specification displays, subset preparation and saved data metadata.
  Rater anchors/bias terms and generalized or multidimensional specifications
  are rejected for this entry. Existing priors, kernels, samplers and saved
  object types are unchanged. Add an ordinary binary IRT worked example.
  Missing named-tuple columns now raise the same descriptive `ArgumentError`
  as other missing-column inputs.

- Add qualified `BayesianMGMFRM.load_conquest_reference_parameters` for the
  existing ConQuest 5.47.5 three-category RSM/PCM bridge. Validated point
  estimates map to first-reference item/rater coordinates with an explicit
  ability translation and unchanged centered steps. Source provenance remains
  available; joint uncertainty, priors, person estimates and estimator agreement
  are not inferred. Existing source-gauge loading and inference are unchanged.

- Add qualified `BayesianMGMFRM.score_information_report` for ordinary scalar
  MFRM: conditional expected-score and Fisher-information curves, explicit
  integer-replicated rating designs, joint-draw totals and chain-aware MCSE.
  Optional `fit_report(...; reporting=(; score_information=(...), ...))` connects
  the same results to public tables and saved bundles. Prediction cubes, new
  fits and outcome simulations are not required. Generalized/multidimensional
  fits and marginal information are outside this initial scope.

- Preserve rating counts, selected draw counts, posterior medians and interval
  probabilities in `calibration_plot_data`. Existing plot fields are unchanged;
  older reduced rows return `missing` for unavailable metadata. Clarify that
  bins group observed rows by their mean prediction and that the intervals
  describe expected values, not replicated ratings or a calibrated fit test.
  Prediction calculations, flags and saved fit/report formats are unchanged.

- Correct unsupported-operation guidance for fixed-coefficient multidimensional
  MFRM. Design inspection points to `getdesign(spec; preview=true)`; automatic
  cache requests point to `Experimental.fit` followed by manual save/load.
  These errors no longer recommend the scalar MFRM fitting entry. Supported
  operations, priors, likelihoods, samplers and saved formats are unchanged.

- D1 slope-restricted MGMFRM fitting, diagnostics and cache restoration now
  accumulate observation-level likelihood checks one draw at a time, avoiding
  an obligatory draw-by-observation matrix. Per-draw totals, finite-value
  counts, diagnostic warnings, sample validation and saved formats are unchanged.
  Explicit pointwise prediction results still include their requested arrays.

- Single-item location-design validation now uses the exact person-rater
  incidence rank, avoiding a dense observation-by-parameter matrix. Disconnected
  person-rater groups remain rank-deficient even when the shared item connects
  the three-facet graph. Multi-item validation, warnings, targets and saved
  formats retain their existing behavior.

- Correlated two-dimensional pure-Q MGMFRM now provides an exact gradient for
  estimated positive item loadings, product-one rater consistency and the
  normalized correlation prior. Public Julia fitting selects it with the
  default `ad_backend=:auto`; explicit AD choices remain available and the
  actual selection is saved. Likelihood, prior, coordinates and cache schemas
  are unchanged. Other multidimensional compositions keep their own scope.

- JointRatings now selects an exact analytic gradient for Julia sampling by
  default (`ad_backend=:auto`), retaining explicit AD overrides and recording
  the selected backend. Julia fits accept `SamplingProgress`. The likelihood,
  prior measure, coordinates and saved-result schema are unchanged.

- Add Experimental.RaterDrift input/design checks and saved computed-report review,
  with baseline-relative intervals, MCSE, whole-report warnings, optional figures
  and portable re-saving. Add explicit four-chain RW1 fitting, retained failure
  records and same-environment native restoration. Computed reports preserve
  joint-draw results when conditional integration is unavailable. Statistical
  acceptance remains open. Add a matched static target and descriptive static/RW1
  comparison with performance/severity location intervals, MCSE and warnings.
  Comparisons preserve structural zeros, reject mismatched inputs/settings and
  reopen from both exact source reports; no model-selection claim is made.

### Analysis

- Reuse checked samples within normalized/correlated MGMFRM artifact composition
  and cache verification. Avoid repeating full draw validation and diagnostics
  for each metadata/summary section. Every public operation still validates its
  source; no persistent memoization, hash change or integrity-check removal.

- Prefer an exact gradient automatically (`ad_backend=:auto`, selecting
  `:analytic`) for the D1
  `Experimental.slope_restriction` route, including fixed mean profiles and
  estimated-positive item slopes. Preserve the original likelihood, prior
  normalizers, last-reconstructed coordinates and saved model identity.
  Report the selected gradient in `surface_contract` and saved sampler controls;
  explicit ForwardDiff/analytic choices remain available. Other model defaults
  are unchanged, and numerical failures do not trigger silent fallback.

- Add `SamplingProgress` and `progress_snapshot` for the scalar and shared
  experimental AdvancedHMC fitting routes. Display a compact overall bar,
  distinguish warmup from retained sampling, and optionally publish atomic JSON
  snapshots. Boolean progress and fit cache keys remain unchanged; progress is
  transition completion, not convergence or save completion.

- Clarify the mathematical help for scalar versus fixed-Q prior conventions,
  declared but unobserved score categories, normalized zero-sum densities,
  fixed-one scale conversion and the two-dimensional LKJ Jacobian. Distinguish
  reference-rater predictions from panel averages. Runtime models, priors,
  samplers and saved formats are unchanged.

- Correct the Chopin stage-1 input adapter's response metadata to identify the
  performance shared by judges, while retaining each rating's observation ID.
  Common-response overlap now agrees with performance overlap. The input scores,
  model, prior and likelihood are unchanged; original saved artifacts are preserved.

- Display a `FacetSpec` at the Julia prompt to inspect slopes, category-step
  ownership, Q dimensions, validation-only terms, fitting availability and
  warning counts. Preserve compact printing, constructor meanings, model
  identities and saved formats; no new fitting or model options are introduced.

- Prior-sensitivity figures label dimensionless coefficients and the fixed-one
  D1 profile location conversion to unit logits. External notes now pair each
  row with mean/quantile MCSE, its declared limit and screen, sampling warnings
  and cutoff decisions. Numerical results and saved formats are unchanged.

- The first MFRM example now saves and prints its MCSE limits and separates
  retained-draw sampler diagnostics from warmup history. Missing history stays
  unavailable; the numerical criteria, fitting and native cache format are unchanged.

- Save and announce the first MFRM example's native fit before summarizing it,
  so a later reporting error retains the completed draws. The existing
  `--saved-fit` mode regenerates the answer without fitting again.

- Extend the mean-profile guide with a saved-fit severity contrast, explicit
  model-to-unit-logit conversion and a recorded endpoint-MCSE failure despite
  passing global diagnostics. The recipe reuses draws; runtime and APIs are
  unchanged, and the illustrative tolerances are not package defaults.

- Write fit reports with export envelope v2 and an exact-integer JSON-payload
  checksum, including the report inside a bundle. Changed large integer IDs are
  now detected. V1 exports remain readable with their original checksum rules;
  old readers cannot open v2 exports. Native caches, report payloads and separate
  table/dossier checksum formats are unchanged.

- Preserve integer tokens exactly when reading report JSON, including UInt64
  input signatures and integers in mixed numeric arrays. Retain signed zeros,
  existing exports and hash policies. This corrects reading without refitting;
  values already rounded by another export cannot be recovered from that copy.

- Compute `probability_equal` directly from tied draws, avoiding negative or
  spurious residual probabilities from subtraction. Historical caches retain
  their original fields and hashes; readers accept only the exact former
  complement formula when comparing regenerated summaries. Newly computed
  summaries use the corrected count. Other probability and interval fields,
  fitting, priors and native schemas are unchanged.

- Add `Experimental.JointRatings.contrast` for named person or rater differences
  within one criterion. Retain joint-draw intervals, MCSE, raw-score direction,
  source diagnostics and portable computed reports. No fitting, prior or native
  sample format changes; the experimental scope and acceptance limits remain.
  Avoid unused marginal summaries and MCSE when computing these contrasts;
  retain complete source validation and all source diagnostics.

- Extend named `posterior_contrast` to scalar `MFRMFit` for RSM/PCM person
  and severity differences. Reuse joint draws, reconstructed references/anchors,
  intervals, MCSE and whole-fit warnings; differences use unit logits and exclude
  external anchor uncertainty. Fitting, priors and native fit formats are unchanged.

- Fix one-dimensional MGMFRM category profiles to retain item loadings and the
  literal 1.7 rater-consistency scale, including fixed-one mean-profile fits.
  Correct free-loading adjacent-category crossings. Regenerate affected curves
  and crossings from original fit caches; no refit is needed. Previously saved
  computed reports are not rewritten. Existing-row expected category use,
  centered steps, scalar MFRM/GMFRM and multidimensional curves are unchanged.

- Add opt-in `vary=:mean_profile` to saved prior sensitivity comparisons for
  independent D1 fixed-one PCM fits with `MeanProfilePrior`. Compare item/step
  means and their residual SDs while retaining other priors, data, labels and
  coefficient policies. Preserve failed/missing alternatives, paired within-fit
  contrasts, MCSE, warnings and source identities. The default loading-SD route,
  fitting and prior-predictive comparison scope are unchanged.

- Add explicit `:reference`, `:steps` and `:combined` prior choices to
  experimental three-outcome preparation and fitting. Preserve the original
  reference and record the selected prior's numerical settings in preparation,
  computed reports and native archives. Older recognized reports retain their
  reference-only provenance and exact source bytes. These choices are not
  general empirical recommendations or statistical acceptance.

- Show observed listener/L1 position ranges and extrapolation warnings when
  preparing and reporting experimental three-outcome contrasts. Inspect a plan
  with `report(plan)` before fitting. Preserve the context in new portable reports;
  historical summaries without it explicitly report unavailable support.
  Range checks do not establish joint overlap or identification and do not
  change the requested contrast, interval or numerical qualification.

- Add experimental no-state three-outcome `prepare`, `fit`, `load_fit` and
  `summarize` with an explicitly selected fixed reference prior. Preserve input
  validation, four-chain settings, complete native records and failures,
  diagnostics, interval MCSE and portable report provenance. Native loading
  requires the producing source/environment; historical migration and scientific
  acceptance are not supplied. The installed example prepares without fitting.

- Extend the experimental three-outcome report reader to the Julia producer
  with mandatory input validation. Check model/producer combinations together,
  preserve original Julia/Stan exports and refuse unknown combinations.
  Fitting and native-chain import remain outside this interface.

- Add experimental `ThreeIndicator.inspect_input` for labelled no-state 9/9/2
  inputs. Check IDs, recording ownership, scoring, fixed rank and consistency
  between stimulus conditions and current/previous indicator columns. Preserve
  block-reset history separately from trial links, labels, units and unobserved
  categories. Include an existing synthetic input and a package-only example;
  no fitting or scientific acceptance is implied.

- Add experimental `ThreeIndicator.load_report`, `report` and `save_report` for
  supported three-outcome computed JSON reports. Preserve fixed-panel and
  contrast definitions, outcome directions, intervals, MCSE, whole-report and
  warmup warnings, and an optional saved Julia/Stan comparison. Portable copies
  retain source bytes and checksums; the package-only example checks supplied
  receipts and refuses existing outputs. No fitting, native chain restoration
  or scientific acceptance is supplied by this interface.

- Add qualified `posterior_contrast` for independent MGMFRM and normalized-prior
  MGMFRM saved fits. Compute same-dimension ability differences, severity
  differences and log consistency ratios from paired model-coordinate draws,
  preserving chain order, intervals, MCSE, contrast diagnostics and whole-fit
  warnings. The saved-contrast example now uses this shared calculation and
  accepts both types. Model-support status and fitting behavior are unchanged.

- Make the saved prior-sensitivity example accept labelled user fit caches,
  explicit planned priors and scientific contrasts. It preserves
  failed/missing variants and warnings,
  refuses existing output directories and verifies the saved comparison.

- Fix installed-project imports in the prior-sensitivity, JointRatings, saved
  contrast and saved MGMFRM review examples. They reuse the package's JSON and
  diagnostic dependencies; no separate JSON3 or MCMCDiagnosticTools installation
  is needed. CairoMakie remains an explicit dependency for figures.

- Add `examples/run_mfrm_recovery.jl` for explicit single-dataset fixed-truth
  or joint-prior SBC PCM execution through a chosen stage. SBC preserves the
  realized full truth before responses, uses the parent study ledger, checks
  saved truth/observation binding and retains rank/dependence exclusions.
  Register observations alone as the SBC generation artifact and keep the
  dataset plan separately; guide/help now match the saved-summary format.
  Reuse completed stages, retain failed
  and unfinished work, save checkpoints and wall-time/artifact costs, and
  refuse retries or existing output directories. Merely including the example
  does not draw parameters, generate responses or fit models. Model-support
  status is unchanged; execution and artificial checks do not establish calibration.

- Add `Experimental.RecoveryPlanning.summarize_recovery` to aggregate saved
  fixed-truth PCM reviews directly from a plan and full stage ledger. Preserve
  failures, unattempted/unfinished work, artifact problems and per-quantity
  numerical exclusions; apply the plan's MCSE limits and existing optional
  width-target uncertainty. Validate saved bindings without loading native fits,
  generating data or repeating estimation. Support status is unchanged.

- Add optional `width_confidence_level` to `recovery_replications` and
  `design_precision_plot_data` / `plot_design_precision` for saved width-target
  studies. Conditional Clopper-Pearson intervals retain uncertainty for small
  samples and all-success/all-failure results. The two-panel plot distinguishes
  these intervals from full-planned unresolved-outcome bounds, including failed
  or missing scenarios. Unresolved independence suppresses intervals. Existing
  aggregation output is unchanged when the new keyword is omitted; no sampling,
  automatic design selection or change of model-support status occurs.

- Fix the first MFRM tutorial in projects that install only BayesianMGMFRM.
  Reuse the package's JSON dependency when saving the answer; no separate
  JSON3 installation is needed. Model, prior and sampling settings are unchanged.

- Add `Experimental.RecoveryPlanning.summarize_sbc` to combine saved rank reviews
  with every planned dataset in the study ledger. Preserve failures, missing or
  changed artifacts and exclusions; bind observations, fits and rank records.
  Report missing-rank CDF bounds and, only with a declared across-dataset
  independence assessment, a conditional family-adjusted DKW screen. No departure
  is not calibration acceptance; no generation, fitting or tie breaking occurs.

- Add `Experimental.RecoveryPlanning.review_sbc_fit` for saved scalar PCM
  results with predeclared rank iterations. Verify the parent study, realized
  truth and native cache; report focal-parameter and joint-log-likelihood ranks,
  exact tie ranges, all-retained-draw diagnostics and unresolved dependence.
  Preserve exclusions without generating draws or breaking ties automatically.
  This does not provide study-wide uniformity assessment or establish calibration.

- Add joint-prior SBC input preparation to `Experimental.RecoveryPlanning`.
  Declare separate parameter/response/fit seeds, require matching generating and
  analysis priors, and bind all free coordinates with reconstructed reference
  values and final item steps. Reuse generation inputs and saved-study accounting.
  Preparation draws no parameters or data; SBC ranks and calibration assessment
  remain separate from these operations.

- Add `Experimental.RecoveryPlanning.relocate_ledger` for a saved study folder
  that has been copied or moved. Check every destination artifact against its
  recorded hash, preserve failures and unfinished stages, and retain relocation
  history through later stage updates. No files are moved or fits reopened by
  this operation; mismatched or missing destination files are rejected.

- Integrate score-free fixed-truth PCM planning and saved-fit review as
  `Experimental.RecoveryPlanning`. Reuse existing preparation, actual-score
  binding and outcome-accounting operations without starting generation or
  fitting. Preserve legacy v2 plan/v1 result schemas. Add a two-allocation
  teaching example, searchable guide and Julia help; SBC and automatic
  study execution are separate capabilities.

- Add optional `max_interval_widths` to `BayesianMGMFRM.recovery_replications`.
  With explicit MCSE limits, report width-target counts and conditional frequency,
  replication SE where applicable, and unresolved-outcome bounds over the full
  planned roster. Preserve failures and numerical exclusions; no automatic
  design choice, assurance claim, generation or fitting is introduced.

### Documentation

- Connect the existing rating-data, specification, fitting, diagnostic,
  interpretation and save/reopen APIs in the Bayesian Workflow guide. The
  walkthrough reuses the first MFRM example and distinguishes posterior fitting,
  predictive generation and saved-result reading. README and task help link to
  it without introducing another public API or changing runtime behavior.

- Reconcile the local manual's compatibility table with the staged scalar MFRM
  and normalized D2 fitting/restoration checks, installation/startup checks and
  current saved-fit replay. Distinguish the local source from the published
  preview, retain platform and scientific limits, and explain why original
  Julia launch options matter for exact diagnostic reconstruction.

- Align citation metadata with the unreleased package version and omit the
  previous version's release date. Explain citation of an exact development
  source and check Project, citation and release-note version/date consistency
  in the existing release-verification gate. Fitting and saved formats are unchanged.

- Make troubleshooting, problem reports, version pinning and saved-result
  migration available through the manual's navigation and search. Reuse the
  existing contribution and versioning guides, with recovery links and a
  version-information command that does not read ratings or fit a model.

### Examples

- Add a CSV-to-specification recipe that preserves text identifiers and the
  declared category scale, rejects missing or invalid required values, and
  assembles a two-dimensional Q matrix by item label. It uses optional CSV.jl
  and existing public data/model APIs without fitting or changing package dependencies.
- The normalized MGMFRM example now inspects its fixed teaching inputs when
  run without arguments. `--help` and `-h` explain the modes without fitting
  or writing results. To run the former short demonstration, pass `--demo`;
  use `--demo --figures` for its plots. The explicit `--fit-example` and
  `--saved-fit PATH` routes retain their fitting and reporting behavior.
- Show person-level dimension support in the normalized MGMFRM input inspection.
  The data guide now includes an executable item-labelled Q mapping and an
  incomplete-assignment check that runs without sampling.

### Fixed

- Reject a negative report-bundle `max_rows` before creating or replacing
  export files. Invalid preview options no longer leave a partial bundle or
  replace JSON/tables while retaining an older Markdown file and manifest.

### First analysis

- Bundle fixed artificial data for the normalized MGMFRM example. Use
  `--inspect-example` to check the allocation, Q matrix, prior and sampling
  settings without fitting; `--fit-example` uses four chains with 1,000 warmup
  and 1,000 retained draws each, then the existing interpretation/save route.
  The data and explicit settings match an existing completed analysis. The
  no-argument short demonstration and `--saved-fit` retain their previous roles.
  The example now saves and prints the fit-cache path before building its
  report, so a reporting failure can be investigated without repeating MCMC.
- Extend the existing normalized MGMFRM example with `--saved-fit` to read a
  trusted fit without fitting or random generation. It preserves the saved data,
  prior and warnings, prints dimension-specific ability intervals, and saves a
  readable answer, fit cache and portable report with MCSE. Including the example
  now only defines functions; call `NormalizedMGMFRMExample.main(...)` to run it.
- Add a complete teaching example for the R2−R1 severity contrast using 72 fixed
  artificial ratings and explicit four-chain NUTS settings. It checks numerical
  adequacy before interpreting the contrast and saves/reopens the fit and a
  plain-text/JSON answer. A saved-fit mode requires matching data, model and prior.
  Beginner navigation now leads to this example; the 50-draw `minimal.jl` remains
  a separate short sampler demonstration.

### Recovery precision

- Add optional `mcse_limits` to `BayesianMGMFRM.recovery_replications`. Explicit
  limits on the posterior mean and both central-interval endpoints add a
  precision-qualified summary without removing global warnings, failures or
  missing datasets. Existing default outputs are preserved. Computational
  precision remains distinct from interval width, calibration and study-design
  adequacy; no simulation or fitting is started by this operation.
- Extend `examples/saved_recovery_replications.jl` with a saved-width review for
  a user-supplied research target. It retains every planned dataset, distinguishes
  numerical exclusions from observed width outcomes, and explains why a single
  narrow interval or small MCSE cannot establish a preferred data-collection design.

### Experimental shared-response ratings

- Add `Experimental.JointRatings` for a bounded two-criterion model, trusted
  saved results, parameter reports, marginal prediction and joint response
  scoring. Explicit priors, original warnings and numerical integration limits
  remain; no new scientific acceptance or release is implied.
- Provide English help and a saved-result example without prototype includes.

### Development successor (not merged or released)

- Align the existing version handoff with the development successor: distinguish
  source identity from package version, explain slope/report and mean-profile
  migration, preserve original environments/results, and name the remaining
  delivery and compatibility checks. No release gate is executed by this change.

- Correct recorded MGMFRM reports for fixed item slopes: active Q entries now
  say `fixed_one`, and Q/fixed-coordinate explanations agree with the coefficient
  policy. Fixed rater consistency is explicit for both restricted slope routes.
  Saved historical reports retain their original text; regenerate from the
  matching native fit to obtain corrected report fields without refitting.

- Fix K-fold aggregation for fixed/free item-slope restrictions, including the
  mean-profile prior. These independent models no longer enter the correlated
  model metadata branch. Retain explicit item-slope and rater-consistency
  policies in comparison rows; add a matched-slope guide and deterministic
  aggregation/comparison checks. No likelihood, prior, sampler or selection
  rule changes; missing folds and numerical warnings remain visible.

- Add experimental `MeanProfilePrior` for independent D1, fixed-one slopes and
  item-owned steps. Require explicit item/category IDs and mean units; retain
  centered Gaussian residuals, raw-scale base SDs and existing zero-mean records.
  Prior prediction, Julia raw-coordinate fitting, reports, manual caches and
  existing-level refit requests preserve the profile. Ordered means do not impose
  hard ordering. This addition requires the `development/20261013-successor`
  source and matching guide; the earlier October preview remains unchanged.
  Application-prior selection and statistical acceptance remain open.

- Publish the development source corresponding to the 13 October guide on
  `development/20261013-guide`. Document a separate project, revision pinning
  and installed examples independent of the working directory. This introduces
  no runtime changes, new model fits or stable-release promotion.

- Add qualified `intraclass_correlation` for complete crossed observed ratings
  on one item. Require explicit random/fixed rater, agreement/consistency,
  single/average and equal-gap score choices. Retain ANOVA components, response
  identities, negative estimates and unavailable-denominator statuses; reject
  incomplete rosters without deletion. Optional `reporting.icc` survives common
  public bundles and saved workflows. No fitting, CI/SE, sparse-design model or
  severity adjustment is supplied.

- Add qualified `krippendorff_alpha` for observed `FacetData`, requiring one
  item label and an explicit nominal or ordinal measurement level. Preserve
  pairable category margins, coincidence weighting, singleton exclusions,
  negative values and undefined results. Add optional `reporting.alpha` to
  common report bundles and saved examples. No fitting, interval, SE,
  missingness correction or severity-adjusted reliability is supplied.

- Add `Experimental.slope_restriction` for one-dimensional item-step MGMFRM
  with fixed-one or estimated-positive item slopes and fixed-one rater
  consistency. Require an explicit normalized exchangeable prior; support
  Julia raw-coordinate fitting, manual persistence and common K-fold refit
  preparation. Retain structural constants and policy identity. Public CmdStan
  fitting and transformed coordinates remain unsupported for this restriction;
  short workflow checks do not establish model-selection performance.

- Add qualified `posterior_ranking` for explicit person cohorts in one ability
  dimension. Require rank direction; retain joint-draw midranks, discrete
  pointwise intervals, mean MCSE and optional top-k inclusion bounds when ties
  cross the boundary. Integrate opt-in `ranking` into common reports and saved
  workflows across eight fit types. No automatic selection, composite ability,
  population rank or known-truth rank-recovery claim is supplied.

- Add qualified `posterior_classification` for explicitly selected people in
  one fitted ability dimension, with required cutoff and probability decision
  rule. Report conditional ability SD/ETI, posterior qualification/error
  probabilities, joint-draw cohort error counts and any-error probability,
  retaining numerical MCSE and sampling warnings. All eight common saved-fit
  types and opt-in `fit_report(reporting=(;classification=(...)))` persistence
  are supported without refitting. These are posterior risks, not known-truth
  repeated-sampling error rates or a multidimensional composite decision.

- Add opt-in `prediction_kfold(...; mcse=:delta)` for first-order numerical
  error of held-out log predictive scores, preserving joint rating covariance
  and chain autocorrelation. Combining fold/model errors requires explicit
  independent-RNG declarations; detect known sample reuse, retain incomplete
  folds and diagnostics, and report insufficient/degenerate precision as missing.
  Extend `saved_kfold_comparison` with the same options. Defaults retain prior
  result structures. This is not data-sampling K-fold SE, a precision guarantee,
  PSIS, or an automatic model-selection rule; no fitting is performed.

- Admit the explicit one-dimensional restriction of the fixed-Q MGMFRM kernel
  through `Experimental.fit` on Julia and CmdStan, retaining item-owned steps,
  positive loadings, the 1.7 constant and existing raw/normalized prior rules.
  Add a distinct family-contract branch and a matched-dimension refit example.
  The scalar rater-step GMFRM and two-dimensional correlation boundary remain
  separate. Native density/gradient checks and short saved-workflow fits establish
  numerical/operational compatibility, not recovery, calibration or a model-choice
  recommendation.

- Extend `examples/saved_prediction_workflow.jl` to all eight common saved-fit
  types, including scalar MFRM/GMFRM and raw MGMFRM. Optional explicit per-model
  category, agreement and reliability choices share the comparison's dataset
  and rating IDs and survive report save/reload. Preserve existing five-type
  calls, native report schemas and warnings; reject invalid requests before
  writing. This example uses existing APIs and performs no fitting.

- Reconcile the public support table with all eight common result types,
  including normalized MGMFRM and exchangeable-rater MFRM. Connect model/prior
  choices to operation limits and the current recovery/prediction evidence.
  Translate the saved comparison/recovery guide into English, preserving its
  examples, uncertainty definitions and legacy heading links. No model, prior,
  sampler, cache format or scientific acceptance changes.

- Recorded MGMFRM and multidimensional MFRM caches now tolerate floating-point
  roundoff in reconstructed posterior means and SDs. Original sample/artifact
  hashes, other summary fields and metadata remain strictly checked; stored
  summaries are preserved without rewriting or refitting.

- Integrate category, finite-cohort posterior reliability and common-response
  agreement through optional `fit_report(...; reporting=(...))` across the eight
  common saved-fit types. Require explicit cohorts/targets and shared rating
  identities; preserve all draws, native results, MCSE, warnings and failures.
  Include named reliability cohorts, table-ready rows, public/Markdown/JSON/bundle
  output and saved-fit replay. Keep old report behavior when the option is omitted
  and the historical replicated-category section distinct. No new estimator,
  inference calibration, HDI, Strata, predictive interval or model fitting is added.

- Add qualified `BayesianMGMFRM.category_report` across the eight common saved-fit
  types. Retain declared categories, observed denominators and actual step-owner
  groups; summarize native shared/item/rater steps, joint-draw ordering and gaps,
  and optional conditional probability slices and adjacent crossings. Distinguish
  expected-use posterior intervals from the existing replicated-use intervals.
  Preserve native scale, all draws, source identity, MCSE and sampling warnings.
  Include saved-cache replay and English help. No category collapse, new fit,
  simultaneous band or HDI is introduced.

- Change ordinary-MFRM `dff_report` to a count-weighted additive projection by
  default (`adjustment=:assignment`), removing the documented unbalanced-margin
  counterexample. Retain empty and unsupported cells, assignment rank/components,
  interaction support, usable-draw counts and uncertainty/multiplicity labels.
  Preserve historical arithmetic with an explicit warning-bearing
  `:observed_margins` option. `fit_report` forwards `dff_adjustment` and saves it.
  This changes residual-screen values, not fitted parameters or fitted DFF effects.

- Add qualified `BayesianMGMFRM.rater_agreement` across the eight common saved-fit
  types. Require explicit response identities, retain all fitted rater pairs
  and their common-response/item denominators, and report observed exact/adjacent
  agreement and joint-draw model expectations. Separate expected-rate posterior
  intervals and MCSE from optional person-cluster observed-rate SEs. Repeated
  ratings, context conflicts and resource overruns fail explicitly. Include
  saved-cache replay, help and an English reporting example. No predictive
  interval, kappa, mechanism diagnosis or reliability correction is implied.

- Add qualified `BayesianMGMFRM.posterior_reliability` for an explicitly selected
  finite cohort of estimated location coordinates across the eight common saved
  fit types. Require an absolute or jointly centered target; retain normalized
  weights, variance components, chain-aware delta-method MCSE and sampling
  warnings. Reject anchors, mixed dimensions and non-location parameters.
  The historical separation screen now warns but preserves numerical values.
  No reliability CrI, population/design coefficient or Strata is inferred.

- Clarify MFRM reporting scope for residual DFF screening, reliability, Strata
  and score agreement. Deterministic counterexamples expose assignment-dependent
  residual centering and limitations of the historical posterior separation
  screen. Strengthen help and the English results guide without changing fitted
  targets or existing numerical outputs. No validated replacement reliability,
  reporting Strata or joint DFF estimator is introduced by this documentation.

- Add prior-predictive sensitivity comparison for normalized MGMFRM loading-prior
  widths, using the existing generator with explicit draw counts and seeds.
  Bind optional saved posterior comparisons through data/prior/target identities;
  preserve missing/failed variants and distinguish predictive intervals, IID MCSE
  and posterior uncertainty. Add category/item/rater views with external notes,
  sealed save/reload, an English worked example and numerical downloads. No new
  posterior fit, calibrated prior-conflict test or automatic prior recommendation
  is implied.

- Add qualified `BayesianMGMFRM.plot_pathway` for stable unidimensional MFRM
  RSM/PCM, with infit/outfit, facet selection and configurable central intervals.
  Preserve fixed locations, fit uncertainty, rating counts, numerical flags and
  whole-fit diagnostics. Titles/notes are external by default. Saved-fit replay
  and `figures = (pathway = (...),)` bundles retain PDF/SVG, JSON inputs and notes.
  Multidimensional and generalized fit estimands remain unsupported. No new
  fitting or statistical validation is implied by this presentation API.

- Add `person_display = :histogram` to `plot_wright` for stable MFRM/RSM/PCM.
  Count one posterior median per person on the shared logit axis, retain the
  individual-interval default, and support explicit bin counts or edges.
  External notes and report JSON preserve counts, edges and the full roster;
  aggregated persons do not consume the individual-position display limit.
  This is a distribution of estimates, not a population density or uncertainty
  distribution. Add an English gallery illustration without new fitting.

- Plot titles and notes now appear outside images by default. `annotation_io`
  defaults to `stdout`, accepts a writable stream for saving the text, and accepts
  `nothing` for the previous embedded layout. Figures remain editable; report
  bundles preserve matching external titles/notes and numerical inputs. The
  English visualization gallery uses the new layout. This does not establish
  APA compliance or add new model/plot support.

- Add an English visualization gallery with Wright Maps, a downloadable
  Pathway-style CairoMakie example, and a saved MGMFRM response surface.
  Explain artificial inputs, uncertainty, fit statistics and display dimensions.

- Add a sampler-free first example and a guide to Julia's REPL help. Explain
  data inputs, validation results and model specification in their docstrings;
  separate concise fitting help from full backend controls with `??fit`.
  Preserve existing defaults, including the random-walk `:julia` backend.

- Add an English beginner learning path covering rating data, model choice,
  worked category probabilities, Bayesian interpretation and simulation for
  study planning. Link it from the manual home and preserve experimental limits.

- Add a rendered API reference and task-based guide for saved prediction and
  recovery. Clarify available K-fold aggregation, separate automatic refitting,
  and keep scientific support and uncertainty limits explicit.

- Add qualified `recovery_replications` and a saved-evaluation example for
  fixed-truth scenarios. Keep the complete dataset roster, failures, missing
  quantities and numerical warnings. Report each focal quantity separately,
  with declared-independence replication SE and unresolved coverage envelopes.
  Separate warning-inclusive from warning-free descriptive subsets; neither
  establishes calibration, precision qualification or design adequacy. This
  does not generate data, fit models, verify independence or run SBC.

- Add qualified `recovery_quantities` and `recovery_evaluation` for named,
  model-coordinate truths across eight saved-fit types, with native reconstruction,
  recovery arithmetic and MCMC MCSE. Retain diagnostics, fixed-value/truth
  mismatches and source identities. Structural constants have missing coverage;
  do not treat them as estimated calibration. Existing vector-truth recovery
  methods remain unchanged. This is a single-dataset evaluator, not a simulation
  runner, joint-prior SBC or replication-level precision assessment.

- Add qualified `prediction_kfold` and `compare_kfold_predictions`, plus a saved
  K-fold comparison example. Retain missing/failed folds and diagnostic warnings;
  require complete results before reporting full scores and all candidates before
  reporting contrasts. Match source, split, persistent rating IDs and target;
  preserve model/dimension/Q contracts. Do not infer a winner or fold-independent
  uncertainty. Prepared plans and fold scores now use content-bound v2 records;
  existing fit-cache and fold-request formats remain unchanged.

- Add qualified `prediction_refit_plan` and `prediction_fold_observations` for
  source-bound known-level K-fold requests and heldout scoring across eight
  supported fit types. Require explicit priors; validate the actual training
  target and retain sampling warnings. These calls do not execute fits or
  compare models. Training-row criteria continue to reject heldout results.

- Reject invalid K-fold/LOO plans before the first refit: overlapping or incomplete
  training sets, duplicated or missing heldout rows, split grouping units, and
  inconsistent scoring labels/counts. Valid subset and empty LOO plans remain
  supported. Preserve custom dimension labels when constructing training specs
  and source order among observed fitted levels, keeping raw-coordinate priors
  on the same reference labels across folds.
- Connect eight concrete saved-fit types to qualified prediction/comparison
  APIs with persistent dataset/rating IDs, explicit model/dimension/Q axes,
  warnings and uncertainty limits. No automatic model winner is selected.
- Add opt-in WAIC and raw importance-sampling LOO report sections for normalized
  and correlated MGMFRM and canonical fixed-coefficient multidimensional MFRM,
  preserving warnings through public reports and save/reload. This is not
  reference-validated PSIS. Legacy scalar defaults and fit-cache formats are
  unchanged; old fixed-Q v1 records still reject public report generation.
- Register comparison/report checks in the existing `fitting_reports` test
  group and add a saved-fit workflow with fresh-process replay. Link its guide
  from the documentation navigation and correct the outdated module help on
  experimental correlated fitting and manual caches. Scientific support,
  common refitting, independent review and release verification remain open.

### Changed

- Split ordinary fitting and local-dependence CI into two shards each, retaining
  every check and the legacy combined group names. Restore a 30-minute ceiling
  for each local-dependence shard after measuring the combined lane at 37m26s
  under its temporary 45-minute ceiling. Comparable split-lane timings remain
  required before closing the performance item.
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
- Add `mgmfrm_validation_protocol()` as a non-executing draft study specification for the
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
- Refine the validation study specification with explicit estimand units, Q and sparse-design
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

- Correct the unexecuted local-dependence pilot contract from the unsupported MFRM
  `ad_backend = :analytic` route to `:ForwardDiff`, and make protocol
  authorization check the MFRM sampler, algorithm, and gradient route in
  addition to downstream diagnostic capabilities. The plan check itself does
  not run the pilot or contribute a scientific outcome.
- Preserve the full 660-job denominator across planned rejection, generation
  failure, fit failure, diagnostic failure, and completed outcomes.
- Preserve native `UInt64` local-dependence data signatures as canonical decimal strings
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

### Unreleased isolated prior-sensitivity candidate

- Compare named model coordinates and within-fit paired contrasts across saved normalized MGMFRM loading-prior SD variants, with equal-tailed intervals, chain-aware MCSE, explicit failure rosters and cutoff screens.
- Add interval/ridge displays and verified bundles with external notes and positive-support log-KDE. No new sampling or stable API promotion is implied.
- Accept bounded floating reduction differences when validating historical saved sampler summaries; preserve content hashes and exact discrete diagnostic fields.
