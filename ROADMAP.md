# BayesianMGMFRM.jl Roadmap

This roadmap is written from the point of view of a skeptical Bayesian
measurement reviewer. Its purpose is to keep the package's implementation
sequence aligned with claims that can be defended in documentation, examples,
registration review, and a future software paper.

## Current Scope

`BayesianMGMFRM.jl` is currently a many-facet Rasch workflow scaffold. The
implemented public slice covers:

- long-format rating data ingestion with deterministic facet indexing;
- pre-fit design validation for category use, connectedness, singleton levels,
  weak item/category support, DFF cell counts, and rank of the current minimal
  reference-constrained location design;
- a minimal MFRM/RSM/PCM specification and inspectable design object;
- an initial specification ladder that can record fit-supported MFRM and
  specified-only GMFRM/MGMFRM configurations with machine-readable constraints;
- small-example Bayesian fitting paths for the minimal identified design using
  a Julia random-walk Metropolis sampler or an initial AdvancedHMC/NUTS backend;
- cached-fit artifacts, sampler diagnostics, R-hat/ESS rows, parameter-block
  diagnostics, prior and posterior predictive replication, calibration
  summaries, observation-level predictive quantities, infit/outfit summaries,
  WAIC, and WAIC-based same-data comparison helpers;
- scalar Julia/BridgeStan validation fixtures and internal hand-computed
  source-aligned GMFRM/MGMFRM preview fixtures, including raw-coordinate
  source-constraint transforms, used by the test suite.

The package does not yet expose production HMC/NUTS workflows beyond the
minimal identified MFRM/RSM/PCM slice, full GMFRM/MGMFRM compilation,
generalized discrimination, modelled DFF effects, PSIS-smoothed/exact LOO, or MGMFRM
loading/rotation machinery. Those features require the gates below.

## Defensible v1 Thesis

The v1 goal should remain narrow:

> A domain-language Julia workflow for Bayesian many-facet Rasch measurement
> that compiles long-format rater-mediated data into identified MFRM/GMFRM/
> MGMFRM specifications, fits them with documented Bayesian diagnostics,
> validates selected likelihoods against Stan and overlapping MFRM software,
> and reports practitioner-facing outputs for sparse designs, DFF/fairness,
> anchoring/linking, and posterior predictive checking.

Avoid claiming a new measurement theory. Avoid claiming "Bayesian IRT in
Julia" as the novelty. The defensible contribution is the integration of many
facets, generalized rater effects, multidimensional loadings, sparse-design
validation, Bayesian workflow diagnostics, and reproducible reporting.

## Reviewer Objections and Required Answers

### 1. The Model Is Not Identified

Risk: ability, item difficulty, rater severity, thresholds, discrimination,
loadings, DFF effects, and anchors can trade off. In sparse designs the
posterior may be driven by priors rather than by data.

Required package behavior:

- Every parameter block has a documented constraint, transform, prior, and
  interpretation.
- `getdesign(spec)` exposes the block table before fitting.
- `validate_design` warns when a requested model is unsupported by the observed
  graph, category use, anchors, or DFF cells.
- Multidimensional loadings have an explicit gauge: confirmatory Q-mask or
  documented free-loading regime, positivity or sign constraints, latent
  correlation structure, and post-hoc Procrustes only where interpretation is
  invariant.

Gate: reject or warn on a feature if the compiler cannot explain the
identification rule in a machine-readable table.

### 2. Bayesian Computation Is Not Trustworthy

Risk: rater discrimination, per-rater thresholds, and sparse anchor designs are
funnel-prone. Faster Julia execution is not evidence unless it also passes
sampling-quality checks.

Required package behavior:

- `diagnostics(fit)` reports R-hat, bulk ESS, tail ESS, divergences or
  numerical errors, max-treedepth hits, step size, leapfrog counts, and E-BFMI
  where available.
- Diagnostics are summarized by parameter block and include machine-readable
  pass/fail flags.
- ESS/sec is reported for substantive blocks, not only for all parameters
  pooled together.
- Stan/BridgeStan remains an external oracle for selected faithful fixtures.
- Variational inference is not a v1 claim unless HMC has already established
  the target and VI is presented as an approximation with calibration checks.

Manuscript-grade default thresholds should be stricter than spike thresholds:
max R-hat <= 1.01 for reported blocks, bulk/tail ESS >= 400 for focal
contrasts, zero divergences where feasible, no unreported max-treedepth
pathologies, and documented Pareto-k handling for LOO.

### 3. Existing Software Already Covers This

Risk: FACETS, TAM, sirt, immer, mirt, brms/Stan, RaschModels.jl, and Uto-Ueno
Stan cover parts of the space.

Required package behavior:

- Position the package as an MFRM/MGMFRM-specific Bayesian workflow with
  sparse-design validation and practitioner reporting.
- Keep a related-software capability matrix in paper materials and docs.
- Align conceptually with JuliaPsychometrics where possible.
- Do not claim that no Julia Rasch or Bayesian IRT package exists.

### 4. Evidence Is Simulation-Only

Risk: simulation can show recovery but not real workflow usability.

Required package behavior:

- Use simulation for controlled recovery, misspecification, sparse-density,
  top-set, and DFF-decision outcomes.
- Add at least one compact real rater-mediated dataset with clear licensing or
  reproducible anonymization before broad v1 claims.
- The real-data example must run the full workflow: data -> validation -> spec
  -> fit -> diagnostics -> PPC/calibration -> DFF or practitioner output ->
  report artifact.

### 5. Bayesian Workflow Is Only Posterior Summaries

Risk: posterior medians and intervals are not enough. Bayesian inference needs
priors, diagnostics, predictive checks, model comparison target clarity, and
sensitivity analysis.

Required package behavior:

- Each fit retains data dimensions, facet counts, formula/spec summary, prior
  table, chains, draws, warmup, seed, backend, sampler controls, thread
  settings, package versions, hashes, and cache provenance.
- Prior predictive checks examine score distributions, category use, rater
  severity, discrimination, thresholds, and expected facet ranges.
- Posterior predictive checks cover overall score/category distributions and
  grouped summaries by person, rater, item/rubric, group, DFF cell, and sparse
  design block.
- Calibration summaries compare observed category proportions or mean scores
  against posterior predictive intervals by facet and design cell.
- LOO/WAIC reports include prediction target, row matching, Pareto-k or
  high-variance diagnostics, and refit guidance.
- Power-scaling or an equivalent sensitivity workflow is available for focal
  DFF, ranking, threshold, and discrimination claims.

### 6. DFF and Fairness Are Overclaimed

Risk: a posterior contrast is screening evidence, not proof of unfairness.

Required package behavior:

- Define DFF estimands before fitting: rater-by-group, rater-by-item,
  item-by-group, category/threshold DFF, or discrimination DFF.
- Keep rater main severity separate from DFF.
- Report DFF on both logit and expected-score scales.
- Include practical magnitude, ROPE/probability of practical equivalence,
  probability of direction, shrinkage behavior, and PPC evidence.
- Frame DFF as evidence for fairness review, not as an automatic policy
  conclusion.

### 7. Reproduction Is Fragile

Risk: Bayesian workflows depend on hidden cached fits, stale environments, or
hand-built notebooks.

Required package behavior:

- Provide a full rerun path and a fast cached-draw report path for paper
  artifacts.
- Version source data or anonymization scripts, seeds, specs, Stan code, Julia
  `Project.toml`, paper `Manifest.toml`, cached draws, result JSON/CSV, and
  rendered reports.
- Cache invalidation is explicit: preprocessing, spec, priors, sampler
  controls, diagnostics, or package version changes invalidate old fits.
- Benchmark claims require idle-machine repeats, median/IQR, hardware/software
  metadata, and diagnostic-adjusted efficiency.

## Product Contracts

### Specification Contract

A canonical specification object must be serializable and inspectable. It
should contain:

- facet roles and original column names;
- deterministic level maps and integer indexes;
- score scale and category labels;
- threshold regime;
- additive/location design blocks;
- loading/discrimination blocks and Q-mask if present;
- DFF/bias terms;
- anchors and linking constants;
- constraints and transforms;
- prior blocks and hyperpriors;
- validation report and data signature.

Done when a saved spec can be loaded and used to regenerate the same pointwise
log likelihood on a fixture.

### Fit Contract

A fitted object must not be only a draw matrix. It should contain:

- `spec` and `design`;
- posterior draws and parameter-block index map;
- pointwise log likelihood, log prior, and log posterior hooks;
- sampler metadata and diagnostics;
- prior table and posterior summaries;
- predictive draw hooks;
- artifact manifest and cache key.

Done when `fit_metadata`, `diagnostics`, `posterior_summary`,
`posterior_predictive_check`, `calibration_table`, `loo_inputs`, and `report`
can operate without private notebook logic.

### Report Contract

The report driver should provide:

- data/design summary and validation warnings;
- model specification and priors;
- convergence diagnostics;
- prior predictive checks;
- posterior predictive checks and calibration;
- posterior summaries with 66%, 90%, and 95% credible intervals where useful;
- probability of direction and ROPE/practical-magnitude flags for focal
  contrasts;
- DFF/fairness summaries where requested;
- LOO/WAIC with target and diagnostics;
- sensitivity models or regimes;
- reproducibility metadata.

## Critical Path to Fit-Ready MGMFRM

The central risk is mathematical, not engineering speed. Uto and Ueno (2020)
define the generalized MFRM by adding item discrimination, rater consistency,
and rater-specific steps to the many-facet ordinal kernel; Uto (2021) extends
that target to a multidimensional GPCM-style ability term with a fixed `1.7`
scaling constant, rater consistency, rater severity, and item-step effects.
The DOI-backed source list is maintained in `docs/src/model-equations.md`.
Therefore the public MGMFRM implementation should advance only through these
gates.

### Gate A: source-equation lock

- Keep the current MFRM/RSM/PCM likelihood separate from the GMFRM/MGMFRM
  targets in docs, manifests, and compiler rows.
- For GMFRM, test every category numerator and denominator against a
  hand-computed source fixture with item discrimination, rater consistency,
  item difficulty, rater severity, and rater-step reconstruction.
- For MGMFRM, test every category numerator and denominator against a
  hand-computed source fixture with the multidimensional ability inner product,
  fixed Q-mask, `1.7` scaling, rater consistency, rater severity, and item-step
  reconstruction.
- Add BridgeStan fixtures for one scalar faithful GMFRM target and one minimal
  MGMFRM target before exposing generalized fitting.

Current status: internal source-aligned compiler previews, raw-coordinate
transforms, fixture-only likelihoods, and fixture-only `LogDensityProblems.jl`
targets exist. BridgeStan JSON fixtures now check the internal source-aligned
raw-coordinate GMFRM/MGMFRM targets; fit-ready public generalized fixtures are
still required.

### Gate B: identified raw parameterization

- Document whether each prior is placed on raw unconstrained coordinates or on
  constrained direct parameters. If direct-parameter priors are used through a
  transform, include the required log-Jacobian adjustment.
- GMFRM must have explicit positivity or sign rules for discrimination and
  consistency terms, product-one or equivalent scale constraints, location
  constraints for item/rater severity, and step constraints.
- MGMFRM must have an explicit multidimensional gauge: fixed Q-mask first,
  sign/positivity rules for item-dimension discriminations where interpreted,
  standard-normal or otherwise documented ability scale, rater consistency
  scale constraint, rater severity location constraint, item-step constraints,
  and a first-release policy for latent correlations. The conservative first
  policy is fixed identity correlation; free correlations can follow only after
  rotation and interpretability tests.
- `constraint_table(spec)` and `model_manifest(spec)` must expose these choices
  before any sampler is called.

Current status: machine-readable declarations, raw transforms, and preview
design raw-parameterization manifests exist for the internal source fixtures.
Those manifest rows expose raw/constrained block maps, transform rows,
independent normal raw-coordinate priors, and the no-Jacobian raw-density
policy. Fit-ready public generalized transforms and any direct-scale
prior/Jacobian policy remain outside the guarded candidate; the recorded policy
keeps priors on raw coordinates.

### Gate C: AD and HMC target proof

- Add ForwardDiff gradient checks for the internal GMFRM/MGMFRM raw targets,
  comparing AD values to finite-difference or known-answer fixtures on stable
  points away from boundaries.
- Run fixture-only AdvancedHMC smoke tests with strict failure reporting, but
  keep broad generalized `fit` disabled until each surface has its own guarded
  evidence.
- Promote a generalized likelihood only after the target is stable under AD,
  finite log density checks, and block-level diagnostics.

Current status: raw-coordinate `LogDensityProblems.jl` targets exist for
internal tests, and ForwardDiff gradients are checked against central finite
differences at stable GMFRM/MGMFRM fixture points. Fixture-only AdvancedHMC/NUTS
smoke tests now verify finite draws and sampler stats for the internal
GMFRM/MGMFRM raw targets. The scalar GMFRM rater-discrimination target now has
a guarded experimental `fit` method; broader generalized `fit` paths remain
blocked.

### Gate D: public compiler promotion

- Generate fit-ready block names, ranges, transforms, and log-density hooks for
  scalar GMFRM first.
- Match Julia pointwise log likelihoods to BridgeStan on the same constrained
  values and on raw initialization points transformed to constrained values.
- Only then expose `fit` for an experimental scalar GMFRM backend.
- Repeat the same sequence for one minimal confirmatory MGMFRM with a fixed
  Q-mask and fixed latent identity correlation before expanding model options.

Current status: public fitting is intentionally restricted to the current
MFRM/RSM/PCM slice plus the guarded experimental scalar GMFRM
rater-discrimination candidate.

### Gate E: evidence before claims

- Use simulation to check parameter recovery, posterior interval coverage,
  convergence, calibration, and decision stability under predeclared sparse and
  near-complete designs.
- Compare scalar GMFRM and minimal MGMFRM fits with source-faithful Stan models
  on small and medium fixtures.
- Add at least one licensed or reproducibly anonymized real rater-mediated
  dataset before making broad workflow claims.
- Treat failure as informative: if generalized Bayesian priors do not improve
  convergence, recovery, calibration, or decision stability over simpler
  baselines in sparse designs, narrow the v1 claim.

### Exposure decision table

| Surface | Current exposure | Reason |
| --- | --- | --- |
| MFRM/RSM/PCM fitting | Public scaffold | Identified minimal design, tested likelihood path, diagnostics, simulation/recovery, and plotting-ready rows exist. |
| GMFRM/MGMFRM manifests and compiler previews | Public preview/specification plus guarded scalar GMFRM experiment | Useful for mathematical review and design inspection; only the scalar rater-discrimination GMFRM candidate has a guarded experimental fit method. |
| GMFRM/MGMFRM raw likelihood targets | Internal tests plus guarded scalar GMFRM target | Source-aligned fixtures, AD checks, HMC smoke tests, BridgeStan checks, and a guarded scalar GMFRM fit path exist; broader gauge contracts and fit-ready promotion remain incomplete. |
| GMFRM/MGMFRM `fit` | Guarded scalar GMFRM public experiment plus private MGMFRM local entrypoint | `fit(spec; experimental = true)` returns `GMFRMFit` only for the scalar rater-discrimination GMFRM candidate. A private `_fit_guarded_mgmfrm` path now produces a guarded local `MGMFRMFit` artifact for the fixed-Q confirmatory candidate, but public MGMFRM fitting remains blocked by the `keep_internal` decision. |
| DFF model effects | Blocked | Current DFF support is validation/specification evidence, not fitted effects. |
| PSIS/exact LOO and model weights | Local scalar policy only | Same-observation WAIC and raw importance LOO remain diagnostic-only; deterministic 3-fold heldout log-score evidence is the selected local scalar model-weight target. Public model-weight claims remain blocked until a future public model-weight claim review. |
| Manuscript claims about sparse MGMFRM superiority | Blocked | Prediction-target/model-weight policy, manual public-scope review, and a guarded local MGMFRM fit artifact path are recorded, but sparse-superiority claims still require broader reproducible validation and a separate public-scope release decision. |

## Progress Ledger and Promotion Rules

The roadmap has two different progress notions:

- **Checklist progress**: currently 98 of 120 tracked roadmap checkboxes are
  complete, or roughly 81.7%. This is useful for implementation accounting.
- **Claim progress**: broad v1 claims are closer to 40-45% complete because
  the remaining items include public generalized fitting, Stan comparisons,
  broader recovery simulations and a public-scope release decision.

The current frontier is the scalar GMFRM internal promotion candidate. It now
has source-aligned fixtures, raw transforms, BridgeStan raw checks, constrained
direct parameter checks, direct pointwise likelihood checks, ForwardDiff
diagnostics, an internal raw/direct AdvancedHMC sampler diagnostic surface, and
an internal fit-ready compiler-candidate manifest. The scalar GMFRM candidate
also has a BridgeStan fit-ready oracle block for raw, constrained, gradient,
pointwise, and total-likelihood checks, plus a predeclared local candidate-chain
study artifact over two fixed initial-value fixtures. It also records an
experimental-public decision manifest whose current decision is
`enable_guarded_experimental` for the scalar rater-discrimination path. It now
has local recovery-smoke evidence by direct parameter
block, a local stress-chain grid over three fixed scenarios, and an initial
local baseline-comparison artifact plus a three-scenario baseline/calibration
grid against public MFRM/PCM/RSM baselines. A local guarded-exposure review is
now recorded with local interval/decision, sparse-design, and WAIC influence
review grids, raw importance LOO/Pareto-k review, deterministic K-fold refit,
guarded fit API dry-run artifact, guarded fit method-wiring artifact, and
experimental fit validation grid. The scalar GMFRM posterior predictive grid,
sparse-pathology recovery grid, prior/likelihood sensitivity grid, compact
real-data case study, local claim-level recovery/reproduction archive manifest,
broader exposure decision review, local confirmatory MGMFRM sparse-recovery
grid, local confirmatory MGMFRM guarded fit method-wiring, local confirmatory
MGMFRM guarded fit validation-grid, local confirmatory MGMFRM guarded fit
API dry-run, local confirmatory MGMFRM guarded public exposure review, local
prediction-target/model-weight policy, local DFF estimand/validation grid,
Gate E manuscript-scale evidence grid, a local manual public-scope review, and
a local full-paper reproduction archive are now recorded. A private guarded
local MGMFRM fit entrypoint now produces a fixed-Q confirmatory artifact while
keeping public MGMFRM exposure blocked.
The
minimal MGMFRM path now has an internal confirmatory gauge candidate manifest
and a separated fit-ready candidate transform manifest. It also has a
BridgeStan confirmatory-candidate oracle block for raw, direct, gradient,
pointwise, and total-likelihood checks, plus a local two-fixture candidate-chain
diagnostic artifact, a local recovery-smoke artifact, and a local
baseline-comparison artifact and a local sparse-recovery grid over three
connected sparse fixed-Q scenarios. Guarded generalized caveat docs, DFF
validation-only evidence, and Gate E evidence are recorded locally for both
scalar GMFRM and confirmatory MGMFRM.
The experimental generalized fit-artifact contract is now populated by the
guarded scalar GMFRM fit path and by the private guarded local MGMFRM
entrypoint for the fixed-Q confirmatory candidate. MGMFRM public fitting still
remains `keep_internal`. The generalized
raw-prior/Jacobian policy is recorded as raw
coordinate priors with no transform Jacobian and no direct-scale priors.

### Status Levels

Every major model surface should move through the same status levels:

| Level | Meaning | Required evidence |
| --- | --- | --- |
| `blocked` | The feature is documented as planned or unsupported. | Scope language, validation rejection or warning, no accidental public fit path. |
| `internal_fixture` | The likelihood or transform exists only for tests. | Hand-computed fixture, stable parameter names, pointwise likelihood checks. |
| `internal_promotion_candidate` | The target is close to fit-ready but private. | Raw/constrained manifest, AD gradient checks, HMC diagnostics, BridgeStan checks. |
| `experimental_public` | Users may fit a narrow model with explicit warnings. | Public docs, fit artifact support, diagnostics, recovery smoke study, fallback rejection for unsupported options. |
| `stable_public` | The surface supports ordinary package examples and paper claims. | Predeclared simulation grid, real-data example, sensitivity checks, reproducibility archive. |

Promotion should be explicit in `model_manifest`, `constraint_table`, docs, and
tests. A target may not skip levels because each level answers a different
reviewer objection.

### Fit-Ready Scalar GMFRM Exit Criteria

Scalar GMFRM can move from `internal_promotion_candidate` to
`experimental_public` only when all of the following are true:

1. Fit-ready raw and constrained block maps are generated by the compiler, not
   by source-fixture helper code.
2. The direct-parameter prior policy is decided: either priors stay on raw
   coordinates, or direct-scale priors include explicit log-Jacobian terms.
3. Julia pointwise log likelihood matches BridgeStan at constrained direct
   values and at transformed raw initialization points.
4. AdvancedHMC candidate chains produce finite log density, finite gradients,
   zero direct-constraint failures, recorded divergences/max-depth/E-BFMI, and
   raw/direct block-level R-hat/ESS rows.
5. `fit(spec; experimental = true)` or an equivalent guarded entry point
   accepts only the scalar GMFRM subset that passed the checks, and rejects all
   unsupported generalized options with actionable errors.
6. A small recovery smoke study covers person, item difficulty, item
   discrimination, rater severity, rater consistency, and step blocks.

### Minimal MGMFRM Exit Criteria

The first MGMFRM path should be confirmatory and deliberately narrow:

1. Fixed Q-mask with documented dimension labels.
2. Fixed identity latent correlation and standard-normal ability scale.
3. Explicit sign or positivity rules for interpreted loadings.
4. Rater consistency and rater severity constraints exposed in the manifest.
5. Item-step constraints and `1.7` scaling checked against the source equation.
6. BridgeStan pointwise likelihood and raw-gradient checks pass before any HMC
   study.

Free rotations, free latent correlations, exploratory loadings, and broad
MGMFRM examples remain out of scope until this minimal confirmatory target is
stable.

## Release Roadmap

### v0.1: scaffold hardening

Goal: keep the current package useful while preventing users from mistaking it
for a full Bayesian MGMFRM engine.

TODO:

- [x] Add public roadmap/scope documentation.
- [x] Add a machine-readable validation-to-suggestion map.
- [x] Add `model_manifest(spec)` or an equivalent manifest schema aligned with
  current `fit_metadata`.
- [x] Add a minimal diagnostics schema that can grow from random-walk
  Metropolis to HMC/NUTS without renaming fields.
- [x] Add an initial `backend = :advancedhmc` NUTS path for the minimal
  MFRM/RSM/PCM posterior.
- [x] Document that current WAIC, PPC, calibration, and fit-stat helpers are
  small-model workflow scaffolding.

Gate: documentation, README, examples, and exported APIs all agree on the
implemented scope.

### v0.2: domain-first specification compiler

Goal: compile domain options into one canonical identified design.

TODO:

- [x] Extend `mfrm_spec` into an initial ladder that can represent MFRM, GMFRM,
  and MGMFRM as configurations of one `FacetSpec` while marking unsupported
  likelihoods as specified-only.
- [x] Add a source-traced `model_equation` contract so manifests distinguish
  the current fit-supported MFRM/RSM/PCM kernel from the primary-literature
  GMFRM/MGMFRM targets and their missing parameter blocks.
- [ ] Compile domain options into fit-ready additive blocks, loading masks,
  scoring vectors, constraints, priors, and validation requirements.
  - [x] Add observation-level design row metadata for current MFRM and
    specified-only GMFRM/MGMFRM previews without enabling unsupported fitting.
  - [x] Add row-by-category linear-predictor metadata for denominator review
    under the current MFRM kernel and specified-only source-aligned
    GMFRM/MGMFRM previews.
  - [x] Add numeric row-by-category `eta`, log-denominator, and category
    log-probability rows for the fit-supported MFRM/RSM/PCM likelihood.
  - [x] Add internal hand-computed GMFRM/MGMFRM source fixtures that check the
    preview compiler's baseline-coded row-by-category logits, denominator
    terms, and primary-literature identification restrictions without enabling
    fitting.
  - [x] Add internal raw-coordinate transforms for the GMFRM/MGMFRM source
    fixtures, covering sum-to-zero, positive, and product-one restrictions
    without exposing generalized fitting.
  - [x] Compose those raw-coordinate transforms with fixture-only pointwise
    log-likelihood kernels so future HMC targets can start from a tested raw
    coordinate likelihood bridge.
  - [x] Add a fixture-only internal `LogDensityProblems.jl` target over those
    raw coordinates with independent normal raw priors, for HMC target-shape
    validation without exposing generalized fitting.
  - [x] Document the fixture-only raw prior policy: priors are evaluated on raw
    unconstrained coordinates and no transform Jacobian is added; future
    constrained direct-parameter priors must include explicit log-Jacobian
    terms.
  - [x] Add raw-parameterization manifest rows for GMFRM/MGMFRM preview
    designs, including raw/constrained block maps, transform rows, raw prior
    policy, and no-Jacobian raw-density policy.
  - [x] Add an internal scalar GMFRM promotion-candidate manifest section and
    diagnostic helper that reports finite log-density, ForwardDiff gradient,
    and finite-difference agreement while keeping public `fit` blocked.
  - [x] Split the scalar GMFRM promotion candidate from source-fixture helper
    logic by adding an internal fit-ready compiler-candidate manifest with
    generated raw/constrained block maps, transform rows, constraint rows, and
    unsupported public-option declarations.
  - [x] Add constrained direct-parameter metadata and raw-to-direct transform
    diagnostics for the scalar GMFRM promotion candidate, including source
    constraint checks and pointwise likelihood agreement.
  - [x] Add an internal scalar GMFRM direct pointwise fixture API that returns
    direct parameter blocks, row/category likelihood rows, observed pointwise
    log likelihoods, and source-constraint summaries.
  - [x] Add an internal scalar GMFRM sampler diagnostic surface that records
    chain-level HMC stats, raw-parameter R-hat/ESS rows, raw-block diagnostics,
    divergences, tree-depth hits, E-BFMI when available, constrained direct
    draws, and direct-block diagnostics.
  - [x] Add a predeclared scalar GMFRM candidate-chain study artifact that
    records protocol controls, fixed seeds and initial values, raw/direct
    R-hat and ESS, divergences, max-depth hits, E-BFMI, direct constraint
    failures, and pointwise log-likelihood finiteness without rerunning chains.
  - [x] Add a local scalar GMFRM stress-chain grid artifact with longer fixed
    chains across near-oracle, zero-centered, and high-acceptance scenarios.
  - [x] Add an internal scalar GMFRM experimental-public decision manifest that
    proposes the guarded `fit(spec; experimental = true)` shape, records
    accepted and rejected option surfaces, and keeps the candidate internal
    until guarded exposure blockers are cleared after stress-chain evidence,
    baseline comparison evidence, caveat
    docs, the fit-artifact contract, and the raw-prior/Jacobian policy are
    recorded.
  - [x] Add a local scalar GMFRM recovery-smoke artifact that predeclares a
    small full-crossed simulation grid, simulates from fixed scalar GMFRM truth,
    runs the internal raw-coordinate HMC candidate, and reports direct-scale
    recovery by parameter block.
  - [x] Add a local scalar GMFRM baseline-comparison artifact that reuses the
    recovery-smoke data, compares the internal candidate with public
    MFRM/PCM/RSM baselines by same-observation WAIC, and records that the
    guarded public exposure remains blocked.
  - [x] Add a local scalar GMFRM baseline/calibration grid artifact that
    compares near-Rasch, moderate, and stronger-generalized scenarios against
    public MFRM/PCM/RSM baselines with WAIC, expected-score calibration, and
    residual metrics.
  - [x] Add a local scalar GMFRM interval/decision grid artifact that records
    direct-parameter interval coverage at 80% and 95% and verifies that the
    keep-internal decision is stable across the same near-Rasch,
    moderate-generalized, and stronger-generalized scenarios.
  - [x] Add a local scalar GMFRM sparse-design grid artifact that records
    connected sparse validation warnings, full-rank location designs,
    interval coverage, baseline comparisons, and stable keep-internal
    decisions across predeclared sparse patterns.
  - [x] Add a local scalar GMFRM WAIC influence-review artifact that records
    pointwise high-variance observations across full-crossed and sparse
    scenarios, removes their scenario-level union, and records model-rank
    sensitivity while preserving the keep-internal decision.
  - [x] Add a local scalar GMFRM guarded-exposure review artifact that hashes
    the candidate-chain, stress-chain, recovery, baseline-comparison,
    baseline/calibration, interval/decision, sparse-design, and WAIC influence
    artifacts; records the review as local-only; and keeps public fitting
    blocked on PSIS/LOO follow-up.
  - [x] Add a local scalar GMFRM PSIS/LOO review artifact that records raw
    importance-sampling LOO, Pareto-k screening, WAIC-vs-LOO rank sensitivity,
    and keeps public fitting blocked on exact LOO/K-fold follow-up when
    high Pareto-k rows are present.
  - [x] Add a local scalar GMFRM exact LOO/K-fold review artifact that records
    deterministic 3-fold heldout refits, verifies training parameter-order
    matches, compares heldout log scores, and advances the next blocker to a
    guarded fit API dry run.
  - [x] Add a local scalar GMFRM guarded fit API dry-run artifact that records
    the proposed `fit(spec; experimental = true)` entrypoint without enabling
    it, verifies specified-only rejection and artifact-contract fields, and
    advances the next blocker to guarded method wiring.
  - [x] Add a local scalar GMFRM guarded fit method-wiring artifact that runs
    `fit(spec; experimental = true)`, returns `GMFRMFit`, verifies the
    experimental fit-artifact contract and unsupported-option rejections, and
    advances the next blocker to an experimental fit validation grid.
  - [x] Add a local scalar GMFRM experimental fit validation-grid artifact that
    runs the guarded `fit(spec; experimental = true)` entrypoint across fixed
    scalar scenarios, validates artifact shape, finite WAIC/LOO inputs, and
    direct-scale recovery bounds, and advances the next blocker to a posterior
    predictive grid.
  - [x] Add an internal minimal confirmatory MGMFRM candidate manifest that
    freezes the first multidimensional gauge as fixed Q-mask, fixed identity
    latent correlation, standard-normal ability scale, positive interpreted
    loadings, and source-scale `1.7`, while keeping fit-ready MGMFRM fitting
    blocked.
  - [x] Split the minimal confirmatory MGMFRM candidate from the source-fixture
    blueprint by adding an internal fit-ready candidate blueprint and raw
    transform manifest rows while keeping fit-ready MGMFRM likelihood, sampler,
    and recovery checks blocked.
  - [x] Extend the GMFRM BridgeStan fixture with constrained parameter values
    and likelihood checks against the promotion candidate's direct parameter
    vector and direct pointwise likelihood sum.
  - [x] Add a fit-ready scalar GMFRM BridgeStan oracle block with raw
    log-density, raw-gradient, constrained direct-parameter, pointwise
    log-likelihood, and total-likelihood checks.
  - [x] Add a fit-ready confirmatory MGMFRM BridgeStan oracle block with fixed
    Q-mask gauge metadata, direct parameter values, raw-gradient checks,
    pointwise log likelihoods, and total likelihood.
  - [x] Add a local confirmatory MGMFRM candidate-chain diagnostic artifact
    with fixed HMC controls, two initial-value fixtures, raw/direct R-hat and
    ESS, E-BFMI, direct constraints, and pointwise finiteness checks.
  - [x] Add a local confirmatory MGMFRM recovery-smoke artifact that simulates
    a full-crossed fixed-Q dataset, samples the internal raw target, transforms
    draws to direct scale, and reports recovery by parameter block.
  - [x] Add a local confirmatory MGMFRM baseline-comparison artifact that
    compares the internal fixed-Q candidate with public MFRM/PCM/RSM baselines
    on the same recovery-smoke observations while keeping MGMFRM internal.
  - [x] Add an internal confirmatory MGMFRM experimental-public API decision
    manifest that records accepted/rejected options and keeps the candidate
    private until sparse-grid blockers are cleared after caveat
    docs, the fit-artifact contract, and the raw-prior/Jacobian policy are
    recorded.
  - [x] Add guarded generalized-model caveat docs for scalar GMFRM and
    confirmatory MGMFRM and record the docs artifact in the internal
    experimental-public decision manifests.
  - [x] Add an internal experimental generalized fit-artifact contract for
    future guarded scalar GMFRM and confirmatory MGMFRM fits, including
    raw/direct parameter orders, transform/Jacobian policy, sampler controls,
    diagnostics, pointwise likelihoods, caveat docs, and fixture provenance.
  - [x] Record the generalized raw-prior/Jacobian policy: independent normal
    priors on raw unconstrained coordinates, no transform Jacobian for that
    density, and no direct-scale priors in the guarded candidate.
  - [x] Add a local DFF estimand/validation grid that predeclares logit and
    expected-score screening estimands, verifies sparse/empty/confounded and
    invalid-facet validation behavior, and keeps DFF model effects
    validation-only until a future DFF model-effect fit policy exists.
  - [x] Add a local Gate E manuscript-scale evidence grid that aggregates the
    versioned validation, recovery, posterior predictive, prior/likelihood
    sensitivity, real-data, DFF, and confirmatory MGMFRM sparse artifacts as
    an input to the local full-paper reproduction archive.
  - [x] Add a local confirmatory MGMFRM guarded fit method-wiring artifact that
    records the source-aligned target, raw-to-direct transform, sampler
    protocol, artifact contract, fixture hashes, and current public-fit
    rejection checks while keeping the MGMFRM entrypoint disabled for
    subsequent validation-grid and API dry-run evidence.
  - [x] Add a local confirmatory MGMFRM guarded fit validation grid that
    aggregates the bridge oracle, candidate-chain, recovery, baseline,
    sparse-recovery, and method-wiring artifacts while keeping the MGMFRM
    entrypoint disabled for subsequent API dry-run and exposure-review
    evidence.
  - [x] Add a local confirmatory MGMFRM guarded fit API dry-run artifact that
    records current public-fit rejections, the artifact contract, validation
    grid evidence, and AD/finite-difference checks for the internal target
    while keeping public exposure blocked until review.
  - [x] Add a local confirmatory MGMFRM guarded fit public exposure review
    artifact that reviews the internal method-wiring, validation-grid, API
    dry-run, sparse-recovery, baseline, and DFF validation evidence while
    keeping MGMFRM fitting internal until prediction-target/model-weight
    policy exists.
  - [x] Add a local prediction-target/model-weight policy artifact that keeps
    same-observation WAIC and raw PSIS/LOO diagnostic-only, selects heldout
    K-fold log score for local scalar model-weight reporting, and kept MGMFRM
    fit and sparse-superiority claims blocked pending manual public-scope
    review and a later release decision.
  - [x] Add a local manual public-scope review artifact for confirmatory
    MGMFRM fit that records the fixed-Q scope, keeps public MGMFRM fit and
    sparse-superiority claims blocked, and advanced the next local gate to the
    now-recorded guarded local MGMFRM fit entrypoint.
  - [x] Add a private guarded local MGMFRM fit entrypoint for the fixed-Q
    confirmatory candidate that records raw/direct draws, sampler diagnostics,
    direct constraints, pointwise log likelihood, WAIC-ready log-likelihood
    matrices, and a guarded local fit artifact while keeping public MGMFRM fit
    disabled.
- [x] Implement identification declarations: sum-to-zero, reference, fixed,
  geometric-mean-one, hard anchors, soft anchors, and multidimensional gauge.
- [x] Generate stable preview parameter names and block ranges for
  specified-only GMFRM/MGMFRM specs without enabling fitting.
- [x] Align specified-only preview blocks with the primary-literature GMFRM and
  MGMFRM equations: item discrimination, rater consistency, rater-specific
  steps, item-dimension discrimination, and item-specific steps.
- [x] Expose all-category linear-predictor compiler rows before adding
  generalized likelihood evaluation.
- [x] Route the current MFRM/RSM/PCM pointwise likelihood and predictive
  probabilities through the same linear-predictor evaluator.
- [x] Generate fit-ready parameter names and block ranges for every compiled
  likelihood.
- [x] Add fixture tests showing compiled fit-ready specs reproduce
  hand-computed or hand-coded pointwise log likelihoods.
  - [x] Initial source-aligned GMFRM/MGMFRM preview fixtures for constrained
    direct parameter values.
  - [x] Internal raw-coordinate transform checks for those preview fixtures.
  - [x] Fixture-only raw-coordinate pointwise log-likelihood checks for
    GMFRM/MGMFRM preview fixtures.
  - [x] Fixture-only raw-coordinate `LogDensityProblems.jl` target checks for
    GMFRM/MGMFRM preview fixtures.
  - [x] ForwardDiff gradient checks against central finite differences for the
    fixture-only raw-coordinate GMFRM/MGMFRM targets.
  - [x] Boundary-value checks for raw log-discrimination and raw
    log-consistency transforms so overflow/underflow states fail before
    fixture likelihood evaluation.
  - [x] Fixture-only AdvancedHMC/NUTS smoke tests for the internal
    raw-coordinate GMFRM/MGMFRM targets.
  - [x] Internal scalar GMFRM promotion-candidate diagnostics over the raw
    source-aligned target.
  - [x] Internal scalar GMFRM raw-to-direct transform diagnostics and direct
    block metadata.
  - [x] Internal scalar GMFRM direct pointwise fixture API.
  - [x] Internal scalar GMFRM sampler diagnostic surface with raw and direct
    block-level HMC diagnostics.
  - [x] BridgeStan constrained-parameter and likelihood checks for the scalar
    GMFRM promotion candidate.
  - [x] Fit-ready scalar GMFRM BridgeStan oracle checks for raw, direct,
    pointwise, gradient, and total likelihood quantities.
  - [x] Fit-ready GMFRM and MGMFRM fixtures after fit-ready identified
    transforms are implemented.
- [x] Add BridgeStan fixture generation for the scalar faithful GMFRM and one
  minimal confirmatory MGMFRM fixture.
  - [x] Draft source-aligned GMFRM/MGMFRM Stan reference models and a
    BridgeStan generation script for raw-coordinate log-density/gradient
    fixtures.
  - [x] Add opt-in Julia checks for generated source GMFRM/MGMFRM BridgeStan
    JSON fixtures.
  - [x] Add BridgeStan JSON fixtures for the internal source-aligned
    raw-coordinate targets, and promote them to default checks.
  - [x] Add nested fit-ready oracle checks for the scalar GMFRM promotion
    candidate and the minimal confirmatory MGMFRM candidate while keeping broad
    generalized fit paths guarded.

Gate: the compiler regenerates a scalar faithful GMFRM model and one minimal
confirmatory MGMFRM model with matching pointwise log likelihoods against
hand-computed and BridgeStan fixtures.

### v0.3: HMC estimation core

Goal: make Bayesian fitting credible before adding broad reporting features.

TODO:

- [ ] Integrate the analytic-gradient path where available and keep AD backends
  swappable for unsupported specs.
- [x] Implement an initial AdvancedHMC/NUTS backend with the shared fit object.
- [ ] Implement Turing sampling with the shared fit object.
- [x] Expose a `LogDensityProblems.jl` target for the minimal MFRM posterior.
- [x] Store sampler controls, optional seeds, thread/package environment
  metadata, and draw-inclusion policy in a fit artifact.
- [x] Add RDS-like serialized fit caches with initialization-vector hashes and
  explicit cache-key invalidation checks.
- [x] Add artifact content hashes and long-term archive manifests for exported
  cache bundles.
- [x] Implement `diagnostics(fit)` with parameter-block pass/fail flags for
  the current identified blocks.
- [x] Expose log likelihood, log prior, and log posterior separately.
- [x] Add prior and posterior predictive simulation for the current
  fit-supported MFRM/RSM/PCM specs.
- [x] Add single-dataset simulation, parameter-recovery rows, block-level
  recovery summaries, and plotting-ready recovery/calibration/PPC row helpers
  for the current fit-supported MFRM/RSM/PCM specs.
- [ ] Extend simulation/recovery helpers to planned fit-ready GMFRM/MGMFRM
  specs after their public likelihoods and gauges are implemented.
- [ ] Validate against Stan on small and medium fixtures before scaling.

Gate: scalar GMFRM and one minimal MGMFRM configuration pass convergence,
recovery, and Stan-comparison checks on predeclared sparse designs.

### v0.4: Bayesian workflow layer

Goal: make diagnostics and sensitivity analysis first-class APIs.

TODO:

- [ ] Implement prior predictive checks for category use, facet ranges, and
  implausible prior implications.
- [ ] Implement posterior predictive checks grouped by facet, group, DFF cell,
  category, and sparse-design block.
- [ ] Extend calibration summaries to ordinal categories and expected scores.
- [ ] Implement posterior summaries with multiple intervals, probability of
  direction, and ROPE/practical equivalence.
- [x] Provide plotting-ready rows for current parameter-recovery, calibration,
  and predictive-check summaries without selecting a plotting backend.
- [ ] Implement PSIS-smoothed or exact/K-fold LOO and dimension-matching
  safeguards. [Raw importance-sampling LOO and Pareto-k diagnostics are
  available for the current minimal fit path]
- [x] Implement prior/likelihood sensitivity, including power-scaling or an
  equivalent package-native workflow.
- [ ] Implement first-class sensitivity comparisons: RSM vs PCM/GPCM,
  discrimination on/off, pooled vs unpooled rater effects, DFF on/off, anchor
  choices, dimensionality, and prior regimes.

Gate: a case-study report can be regenerated from fit objects without custom
notebook logic for diagnostics, PPC, calibration, model comparison, or
sensitivity tables.

### v0.5: practitioner MFRM outputs

Goal: make the package useful to FACETS-trained MFRM users.

TODO:

- [ ] Implement fair averages and expected-score summaries with uncertainty.
- [ ] Implement posterior infit/outfit and residual summaries with caveats.
- [ ] Implement separation and reliability summaries with Bayesian uncertainty.
- [ ] Implement rater severity, discrimination, category-use, range/centrality,
  and residual diagnostics.
- [ ] Implement Wright-map-style data APIs before committing to one plotting
  backend.
- [ ] Implement DFF reports on logit and expected-score scales.
- [ ] Implement hard/soft anchors, anchor sensitivity, and robust linking
  diagnostics.

Gate: a FACETS-trained user can recognize the report, and a Bayesian reviewer
can inspect the uncertainty and diagnostics behind it.

### v0.6: validation and evidence package

Goal: make broad claims falsifiable and reproducible.

TODO:

- [ ] Build simulation grids for sparse-to-near-complete density, anchor size,
  ratings per target, category pathologies, rater noise, DFF,
  multidimensionality, and misspecification.
- [ ] Predeclare falsification conditions for the claim that hierarchical
  priors stabilize sparse MGMFRM designs.
- [ ] Compare against Stan faithful models, overlapping R/frequentist tools,
  and simpler nested models.
- [x] Secure and document at least one real rater-mediated case study.
- [ ] Run idle-machine repeated benchmarks with median/IQR, ESS/sec,
  Stan/Julia ratios, and time-to-quality thresholds.
- [x] Archive local full and fast reproduction scripts, manifests, seeds,
  hashes, fixture-generation commands, and verification commands without any
  publication or registration action.

Gate: a reviewer can rerun or inspect every paper claim from a versioned
artifact bundle.

## Immediate TODO: next 30-45 days

### Sprint 1: fit-ready scalar GMFRM compiler split

Goal: separate source-fixture helper logic from a fit-ready scalar GMFRM
compiler path while keeping public `fit` blocked.

1. Add an internal fit-ready scalar GMFRM compiler manifest with generated raw
   blocks, constrained blocks, transforms, constraints, and prior-policy rows.
   [Done]
2. Make the promotion candidate consume this fit-ready manifest instead of
   relying on source-fixture-specific block declarations. [Done]
3. Preserve the existing source-aligned fixtures as oracle tests. [Done]
4. Add failure tests for unsupported scalar GMFRM variants before public fit
   exposure. [Initial rejection tests done]

Done when one internal scalar GMFRM design can regenerate the same direct
parameter names, transforms, constraints, pointwise likelihoods, and sampler
diagnostic rows from the fit-ready compiler path. Initial manifest-level
regeneration is complete; BridgeStan fit-ready fixture promotion remains in
Sprint 2.

### Sprint 2: scalar GMFRM external-oracle alignment

Goal: compare the fit-ready scalar GMFRM candidate with BridgeStan on the same
parameterization used by the candidate compiler.

1. Extend the BridgeStan fixture generator to write fit-ready scalar GMFRM raw,
   constrained, and pointwise likelihood fields. [Done for scalar GMFRM]
2. Compare Julia raw log density, raw gradient, constrained direct parameter
   values, pointwise log likelihood, and total likelihood with BridgeStan.
   [Done for scalar GMFRM]
3. Add a mismatch report that names the first failing parameter, observation,
   category, or transform block. [Initial test-level diagnostics done]
4. Keep the current source-aligned BridgeStan fixtures as regression checks.
   [Done]

Done when the fit-ready scalar GMFRM candidate has an external-oracle fixture
that can fail precisely enough to debug compiler, transform, or prior mistakes.
Scalar GMFRM now meets this sprint-level oracle condition; confirmatory MGMFRM
fit-ready oracle work is recorded in Sprint 6.

### Sprint 3: scalar GMFRM candidate-chain study

Goal: replace smoke-only HMC evidence with a small but predeclared diagnostic
study.

1. Define a tiny fixture-chain protocol: seeds, warmup, draws, chains,
   `target_accept`, `max_depth`, metric, initial values, and pass/fail
   thresholds. [Done]
2. Run the internal raw/direct sampler diagnostic surface on at least two
   stable scalar GMFRM fixtures. [Done: near-oracle and zero-centered initial
   values]
3. Record divergences, max-depth hits, E-BFMI, raw/direct R-hat, raw/direct
   ESS, direct constraint failures, and pointwise log-likelihood finiteness.
   [Done]
4. Add an artifact row or JSON summary so diagnostics can be inspected without
   rerunning long chains. [Done:
   `test/fixtures/gmfrm_candidate_chain_study.json`]

Initial sprint condition is met for the local two-fixture study and the
three-scenario stress-chain grid. Scalar GMFRM now has an initial local
baseline-comparison artifact and a three-scenario baseline/calibration grid,
plus a local interval/decision grid and guarded-exposure review that defend the
guarded scalar exposure decision. The guarded caveat docs, fit-artifact
contract, raw-prior/Jacobian policy, and guarded method-wiring artifact are now
recorded locally.

### Sprint 4: guarded experimental scalar GMFRM decision

Goal: decide whether a narrow scalar GMFRM entry point can be exposed without
overstating package scope.

1. Draft the guarded API shape, for example `fit(spec; experimental = true)`,
   and document every accepted and rejected option. [Done internally in the
   promotion-candidate decision manifest]
2. Ensure `model_manifest(fit)` records `experimental_public`, source fixture
   hashes, BridgeStan fixture hashes, sampler controls, and diagnostics.
   [Done for the guarded scalar GMFRM `GMFRMFit` artifact path]
3. Add user-facing docs that show the scalar GMFRM caveats before examples.
   [Done locally in `docs/src/fitting.md`; broader generalized fitting remains
   guarded]
4. If any source, transform, BridgeStan, HMC, recovery, baseline-comparison, or
   documentation check fails, keep the API internal and write down the blocker.
   [Current decision: enable guarded experimental scalar GMFRM; flagged
   observation sensitivity, raw importance LOO Pareto-k rows, K-fold refit
   evidence, fit API dry-run, method wiring, experimental fit validation grid,
   posterior predictive grid, sparse-pathology recovery grid, and
   prior/likelihood sensitivity grid, a compact real-data case study, and a
   local claim-level recovery/reproduction archive plus broader exposure
   decision review, MGMFRM baseline-comparison evidence, and MGMFRM sparse
   recovery evidence plus local DFF estimand/validation evidence and Gate E
   manuscript-scale evidence plus the full paper reproduction archive are
   recorded; broader exposure still requires a separate public-scope release
   decision]

Done when the exposure decision can be defended by manifest evidence rather
than by developer intent.

### Sprint 5: recovery evidence for the first generalized model

1. Predeclare a scalar GMFRM simulation grid: persons, items, raters,
   categories, rating density, rater consistency variance, item discrimination
   variance, category-step spread, and sparse-cell pathologies. [Initial
   full-crossed smoke grid, scalar sparse-design grid, and sparse-pathology
   recovery grid done]
2. Run recovery using `simulate_responses`, generalized fitting once available,
   `parameter_recovery`, `parameter_recovery_summary`, calibration rows, and
   predictive-check rows. [Internal raw-coordinate candidate recovery smoke
   done; guarded scalar GMFRM fitting now available and used for validation,
   posterior predictive, sparse-pathology recovery, and prior/likelihood
   sensitivity grids]
   - [x] Run sparse-pathology recovery through the guarded scalar GMFRM fit
     path on connected sparse designs.
3. Report recovery by parameter block: ability, item difficulty, item
   discrimination, rater severity, rater consistency, and steps. [Done for the
   local smoke artifact]
4. Compare generalized fits with simpler MFRM/RSM/PCM baselines on recovery,
   calibration, interval coverage, and decision stability. [Initial
   same-observation WAIC baseline-comparison artifact, three-scenario
   expected-score calibration, interval/decision grid, scalar sparse-design
   grid, WAIC influence review, raw importance LOO/Pareto-k review, and
   deterministic K-fold refit review plus experimental fit validation,
   posterior predictive, sparse-pathology recovery, and prior/likelihood
   sensitivity grids plus compact real-data case-study, local claim-level
   archive, broader exposure decision-review evidence, local confirmatory
   MGMFRM sparse-recovery evidence, MGMFRM guarded fit method-wiring, MGMFRM
   guarded fit validation-grid, MGMFRM guarded fit API dry-run, MGMFRM guarded
   public exposure review, prediction/model-weight policy, DFF
   estimand/validation evidence, Gate E manuscript-scale evidence, and local
   full-paper reproduction archive done; broader generalized claims still need
   a public-scope release decision]

Initial smoke and sparse-pathology recovery conditions are met for the guarded
scalar GMFRM candidate. Prior/likelihood sensitivity evidence, a compact
real-data case study, a local claim-level archive manifest, a broader exposure
decision review, local confirmatory MGMFRM sparse-recovery grid, local
confirmatory MGMFRM guarded fit method-wiring, a local confirmatory MGMFRM
guarded fit validation-grid, a local confirmatory MGMFRM guarded fit API
dry-run, a local confirmatory MGMFRM guarded public exposure review, a local
prediction/model-weight policy, a local DFF estimand/validation grid, Gate E
manuscript-scale evidence, and a local full-paper reproduction archive are now
recorded. Broader exposure and stable claims still require manual public-scope
review.

### Sprint 6: minimal MGMFRM gauge and fixture

1. Freeze the first public MGMFRM candidate as confirmatory only: fixed Q-mask,
   fixed identity latent correlation, documented ability scale, and explicit
   sign/positivity rules for interpreted loadings. [Done internally as a
   confirmatory gauge candidate manifest; not public]
2. Implement the fit-ready raw transform and manifest rows for this minimal
   candidate, still behind an internal path. [Blueprint/manifest split done]
3. Match Julia and BridgeStan pointwise log likelihoods for the minimal MGMFRM
   fixture. [Done for the nested confirmatory-candidate BridgeStan oracle]
4. Run a tiny recovery and sampler diagnostic study only after the source and
   Stan checks pass. [Sampler diagnostic and recovery-smoke artifacts done;
   keep-internal public API decision manifest, caveat docs, and fit-artifact
   contract done]
   - [x] Run a local confirmatory MGMFRM sparse-recovery grid over connected
     sparse fixed-Q scenarios and keep the MGMFRM fit surface internal.

Done when the team can defend why the MGMFRM gauge is identified and why the
reported dimensions are interpretable.

### Risk Register

| Risk | Trigger | Response |
| --- | --- | --- |
| Direct-prior ambiguity | Direct-scale priors are requested for the guarded candidate. | Keep priors on raw coordinates and block public direct-prior API. |
| Scalar GMFRM HMC pathologies | Divergences, low E-BFMI, or unstable R-hat appear in candidate chains. | Tune parameterization, strengthen priors, or keep GMFRM internal. |
| MGMFRM gauge confusion | Different rotations or sign choices change interpreted loadings. | Restrict v1 to confirmatory Q-mask and fixed identity correlation. |
| Sparse-design overclaim | Recovery fails in sparse cells or DFF decisions are unstable. | Narrow claims, add warnings, or require stronger design validation. |
| BridgeStan drift | Julia and Stan disagree after compiler refactors. | Treat Stan fixture mismatch as a release blocker. |
| Documentation drift | README, docs, and manifest statuses disagree. | Require synchronized doc updates for every status transition. |

### Parallel documentation and evidence tasks

1. Keep `docs/src/model-equations.md`, `ROADMAP.md`, and the README scope
   language synchronized whenever a generalized target moves between blocked,
   internal, experimental, and public status.
2. Select the real rater-mediated case-study candidate and record licensing or
   anonymization status.
3. Convert the simulation grid and falsification rules into versioned scripts
   before running manuscript-scale experiments.
4. Keep cached-fit artifacts reproducible: data hash, spec hash, prior policy,
   sampler controls, initialization hash, diagnostics, package versions, and
   source/Stan fixture hashes.

## Red Lines

- Do not add per-rater thresholds without hierarchical pooling and explicit
  warnings.
- Do not report LOO model weights without Pareto-k diagnostics and a prediction
  target statement.
- Do not call a DFF contrast unfairness without practical magnitude and model
  checking.
- Do not use single-run timings as manuscript evidence.
- Do not claim "MGMFRM implemented" until fit-ready multidimensional fixtures,
  identification/gauge documentation, and sampler diagnostics all pass.
- Do not advertise a broad Bayesian MGMFRM API before docs clearly separate
  implemented and planned functionality.
