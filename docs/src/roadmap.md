# Roadmap and Scope

This page summarizes the package roadmap from a skeptical Bayesian measurement
reviewer's point of view. It is intentionally conservative: features move
forward only when their identification, diagnostics, validation, and reporting
contracts are clear.

See the repository-level `ROADMAP.md` for the full implementation checklist.

## Current Public Slice

The current package supports:

- long-format rating data with deterministic facet indexing via
  [`FacetData`](@ref);
- pre-fit design validation via [`validate_design`](@ref);
- minimal MFRM/RSM/PCM specification and design inspection via
  [`mfrm_spec`](@ref) and [`getdesign`](@ref);
- specified-only GMFRM/MGMFRM configuration manifests and constraint tables via
  [`model_ladder`](@ref), [`constraint_table`](@ref), and
  [`model_manifest`](@ref);
- observation-level and row-by-category compiler inspection via
  [`design_row_table`](@ref), [`linear_predictor_table`](@ref), and
  [`linear_predictor_values`](@ref);
- small-example Bayesian fitting for the minimal identified design via
  [`fit`](@ref), [`MFRMPrior`](@ref), and [`MFRMFit`](@ref), including
  random-walk Metropolis and an initial AdvancedHMC/NUTS backend;
- fit metadata, chain summaries, R-hat/ESS summaries, posterior summaries,
  prior/posterior predictive checks, calibration summaries, infit/outfit,
  WAIC, and same-observation WAIC comparisons;
- scalar Julia/BridgeStan validation fixtures and internal hand-computed
  source-aligned GMFRM/MGMFRM preview fixtures, including raw-coordinate
  source-constraint transforms, used by the test suite.

The current `backend = :julia` sampler is a random-walk Metropolis path for
small validation examples. `backend = :advancedhmc` is the first NUTS interface,
limited to the current minimal MFRM/RSM/PCM design.

## Not Yet Public API

The following are planned but not yet exposed:

- broader production HMC/NUTS workflows beyond the minimal design;
- fit-ready GMFRM/MGMFRM likelihood compilation beyond the current
  specified-only manifests, row-by-category compiler previews, and internal
  hand-computed GMFRM/MGMFRM source fixtures;
- generalized rater/item discrimination terms;
- modeled DFF/bias effects;
- multidimensional loading and rotation/gauge machinery;
- PSIS-smoothed or exact/K-fold LOO follow-up;
- report generation and full paper artifact reproduction.

## Critical Path to Fit-Ready MGMFRM

The roadmap treats fit-ready MGMFRM as a gated mathematical implementation,
not a naming milestone. The target follows Uto and Ueno (2020) for GMFRM and
Uto (2021) for MGMFRM, so the package must keep source equations, constraints,
priors, transforms, and sampler evidence aligned before exposing fitting. See
the [model-equations page](model-equations.md) for the DOI-backed source list.

1. **Source-equation lock**: keep the current MFRM/RSM/PCM likelihood separate
   from source-aligned GMFRM/MGMFRM targets; test every category numerator and
   denominator against hand-computed fixtures; add BridgeStan fixtures for one
   scalar GMFRM and one minimal MGMFRM.
2. **Identified raw parameterization**: document whether priors live on raw
   unconstrained coordinates or constrained direct parameters. If direct-scale
   priors are used through transforms, include log-Jacobian adjustments.
3. **Gauge and constraints**: expose product/scale, location, step, positivity,
   Q-mask, ability-scale, and latent-correlation choices in
   `constraint_table(spec)` and `model_manifest(spec)` before sampling.
4. **AD and HMC target proof**: add gradient checks and fixture-only HMC smoke
   tests for generalized raw targets; promote only the narrow scalar GMFRM path
   once its evidence is recorded.
5. **Public promotion**: promote scalar GMFRM first, only after Julia and
   BridgeStan pointwise log likelihoods, transforms, AD, and sampler diagnostics
   agree. Repeat for a minimal confirmatory MGMFRM with a fixed Q-mask and fixed
   latent identity correlation before expanding options.
6. **Evidence before claims**: use predeclared simulation grids, recovery
   metrics, calibration, posterior predictive checks, Stan comparisons, and at
   least one real rater-mediated case study before making broad claims.

Current exposure is deliberately conservative: MFRM/RSM/PCM fitting and
simulation/recovery helpers are public; GMFRM/MGMFRM manifests and compiler
previews are public for inspection; a guarded scalar GMFRM
`fit(spec; experimental = true)` path is available only for the
rater-discrimination promotion candidate; broader GMFRM/MGMFRM fitting, DFF
model effects, public model-weight claims, and manuscript claims about sparse
MGMFRM superiority remain blocked. Local scalar model-weight reporting is
restricted to the heldout K-fold prediction target; the confirmatory MGMFRM
manual public-scope review and guarded local fit entrypoint are recorded, but
public MGMFRM exposure still requires a separate release decision.

## Progress Ledger

The repository roadmap currently has 96 of 120 tracked checklist items complete,
or roughly 80.0% by simple implementation accounting. The stronger claim-level
progress is lower, about 40-45%, because the remaining work includes public
generalized fitting, Stan comparisons, broader recovery simulations,
and a public-scope release decision for generalized claims.

The current frontier is the scalar GMFRM internal promotion candidate. It has
source-aligned fixtures, raw transforms, BridgeStan raw checks, constrained
direct parameter checks, direct pointwise likelihood checks, ForwardDiff
diagnostics, an internal raw/direct AdvancedHMC sampler diagnostic surface, and
an internal fit-ready compiler-candidate manifest. It also has a BridgeStan
fit-ready oracle block for raw, constrained, gradient, pointwise, and
total-likelihood checks, plus a local predeclared candidate-chain study artifact
over two fixed initial-value fixtures. It also records an internal
experimental-public decision manifest whose current scalar decision is
`enable_guarded_experimental`.
It now has local recovery-smoke evidence by direct parameter block, a local
three-scenario stress-chain grid, an initial local baseline-comparison artifact,
and a three-scenario baseline/calibration grid against public MFRM/PCM/RSM
baselines. Local interval/decision, sparse-design, WAIC influence, raw
importance-sampling LOO/Pareto-k, deterministic K-fold refit, and
guarded-exposure review artifacts plus a guarded fit API dry run and guarded
fit method-wiring artifact are now recorded. The scalar candidate now has a
guarded experimental fit method plus local experimental fit validation and
posterior predictive grids plus local sparse-pathology recovery and
prior/likelihood sensitivity grids plus a compact real-data case study and a
local claim-level recovery/reproduction archive manifest plus a broader
exposure decision review plus local confirmatory MGMFRM sparse-recovery
evidence plus local confirmatory MGMFRM guarded fit method-wiring plus local
confirmatory MGMFRM guarded fit validation-grid plus local confirmatory MGMFRM
guarded fit API dry-run plus local confirmatory MGMFRM guarded public exposure
review, a local prediction-target/model-weight policy, a local manual
public-scope review, a local DFF
estimand/validation grid, Gate E manuscript-scale evidence, and a local
full-paper reproduction archive. A private guarded local MGMFRM fit entrypoint
now records fixed-Q confirmatory raw/direct draws, sampler diagnostics, direct
constraints, pointwise log likelihood, and a guarded local fit artifact while
keeping public MGMFRM exposure blocked.
The minimal
MGMFRM path now has an internal confirmatory gauge candidate manifest, a separated
fit-ready candidate transform manifest, and a BridgeStan confirmatory-candidate
oracle block for raw, direct, gradient, pointwise, and total-likelihood checks.
It also has a local two-fixture candidate-chain diagnostic artifact, a local
recovery-smoke artifact, a local baseline-comparison artifact, and a local
sparse-recovery grid over connected sparse fixed-Q scenarios. Its internal public-API decision currently remains
`keep_internal`. Guarded generalized-model caveat docs and an internal
experimental generalized fit-artifact contract are now recorded locally, and
DFF validation-only evidence is recorded. The generalized raw-prior
and Jacobian policy is recorded as raw-coordinate priors with no transform
Jacobian and no direct-scale priors.

## Promotion Levels

Model surfaces should move through explicit levels:

| Level | Meaning |
| --- | --- |
| `blocked` | Planned or unsupported; validation and docs prevent accidental use. |
| `internal_fixture` | Likelihood or transform exists only for tests and source-equation checks. |
| `internal_promotion_candidate` | Private target with raw/constrained manifests, AD checks, HMC diagnostics, and BridgeStan evidence. |
| `experimental_public` | Narrow user-facing fit path with explicit warnings, diagnostics, and recovery smoke evidence. |
| `stable_public` | Ordinary examples and paper claims are supported by simulations, real data, sensitivity checks, and reproduction artifacts. |

Scalar GMFRM can become `experimental_public` only after fit-ready raw and
constrained compiler maps exist, the raw-prior/Jacobian policy is recorded,
BridgeStan agrees with Julia on raw, constrained, and pointwise quantities,
candidate chains produce block-level diagnostics, baseline comparisons are
available, the guarded exposure decision is defensible, and unsupported options
are rejected with actionable errors.

The first MGMFRM target should stay confirmatory: fixed Q-mask, fixed identity
latent correlation, documented ability scale, explicit sign/positivity rules,
manifested rater/item constraints, and BridgeStan pointwise checks before any
HMC study.

## Reviewer Gates

### Identification

Every future parameter block must have documented constraints, transforms,
priors, and interpretation. `getdesign(spec)` should expose these decisions
before fitting, and `validate_design` should warn when the observed data cannot
support the requested structure.

### Bayesian Computation

Future HMC/NUTS fits must report diagnostics by parameter block: R-hat,
bulk/tail ESS, divergences or numerical errors, max-treedepth hits, step size,
leapfrog counts, and E-BFMI where available. Faster runtime is not evidence
unless sampling quality also passes.

### Bayesian Workflow

Posterior summaries are not enough. The package roadmap includes prior
predictive checks, posterior predictive checks, calibration summaries, LOO/WAIC
diagnostics, and prior/likelihood sensitivity workflows as first-class APIs.

### DFF and Fairness

DFF should be treated as screening evidence for fairness review. Future DFF
APIs should define estimands before fitting, separate rater main severity from
DFF, report both logit and expected-score scales, and include practical
magnitude and model-checking evidence.

### Reproducibility

Paper-grade artifacts should have both full rerun and fast cached-draw
reproduction paths. Seeds, specs, priors, sampler controls, package versions,
Stan fixtures, cached draws, and rendered reports should be versioned.

## Release Targets

### v0.1 Scaffold Hardening

- Add public roadmap/scope documentation. [Done]
- Add a validation-to-suggestion map. [Done]
- Add `model_manifest(spec)` or an equivalent provenance schema. [Done]
- Add a diagnostics schema that can grow from random-walk Metropolis to HMC.
  [Done]
- Keep documentation explicit that current model-comparison and predictive
  helpers are small-model scaffolding.

### v0.2 Specification Compiler

- Represent MFRM, GMFRM, and MGMFRM as configurations of one canonical spec.
  [Initial specified-only ladder done]
- Add source-traced equation contracts that distinguish the current
  fit-supported MFRM/RSM/PCM kernel from the primary-literature GMFRM/MGMFRM
  targets and their missing parameter blocks. [Done]
- Compile domain options into design blocks, loading masks, scoring vectors,
  constraints, priors, and validation requirements.
  [Observation-level design row metadata added for MFRM and specified-only
  GMFRM/MGMFRM previews; row-by-category linear-predictor metadata added for
  denominator review; internal hand-computed source-aligned GMFRM/MGMFRM preview
  fixture, raw-coordinate transform checks, and fixture-only raw-coordinate
  log-likelihood / `LogDensityProblems.jl` target checks added; preview
  raw-parameterization manifest rows now expose raw/constrained block maps,
  transform rows, raw prior policy, and no-Jacobian raw-density policy;
  normalized identification declarations now cover sum-to-zero, reference,
  fixed, geometric-mean-one, hard/soft anchors, and multidimensional gauge
  rows; fit-ready parameter layout metadata now records MFRM direct blocks and
  GMFRM/MGMFRM raw/constrained candidate blocks; scalar GMFRM internal
  promotion-candidate gates, a fit-ready compiler-candidate manifest, gradient
  diagnostics, direct block metadata, direct pointwise fixture API,
  raw-to-direct transform diagnostics, internal raw/direct sampler diagnostic
  surface, a local candidate-chain study artifact, an internal
  experimental-public decision manifest, a local recovery-smoke artifact,
  BridgeStan constrained parameter checks, fit-ready BridgeStan oracle checks,
  a minimal confirmatory MGMFRM gauge-candidate manifest, and a separated
  fit-ready MGMFRM candidate transform manifest plus confirmatory BridgeStan
  oracle checks added]
- Add stable preview block names and parameter names for specified-only
  GMFRM/MGMFRM specs. [Done]
- Align specified-only preview blocks with the primary-literature GMFRM and
  MGMFRM equations: item discrimination, rater consistency, rater-specific
  steps, item-dimension discrimination, and item-specific steps. [Done]
- Expose all-category linear-predictor compiler rows for the current MFRM
  kernel and specified-only source-aligned GMFRM/MGMFRM previews. [Done]
- Connect the current MFRM/RSM/PCM linear-predictor rows to numeric `eta`,
  log-denominator, and category log-probability values. [Done]
- Add fit-ready block names, parameter names, and fixture-backed likelihood
  tests. [Initial GMFRM/MGMFRM preview fixtures and fixture-only raw likelihood
  / log-density target checks, ForwardDiff raw-target gradient checks, and raw
  transform boundary checks done; preview raw-parameterization manifest rows
  added; public fit-ready parameter layout rows added for MFRM direct blocks
  and GMFRM/MGMFRM raw/constrained compiler candidates; scalar GMFRM
  promotion-candidate fit-ready compiler manifest, gradient and raw-to-direct
  transform diagnostics, direct pointwise fixture API, and BridgeStan
  direct-parameter checks added; internal raw/direct sampler diagnostics, a
  local two-fixture candidate-chain study artifact, an experimental-public
  decision manifest, a local recovery-smoke artifact, guarded method-wiring
  evidence, and fit-ready scalar GMFRM BridgeStan oracle checks added; minimal
  confirmatory MGMFRM gauge manifest and fit-ready candidate transform manifest
  plus fit-ready confirmatory MGMFRM BridgeStan oracle checks, a local
  confirmatory MGMFRM candidate-chain artifact, and a local recovery-smoke
  artifact, and an internal keep-internal public API decision manifest added;
  broader fit-ready generalized fixtures still planned]
- Add BridgeStan fixture generation for scalar GMFRM and one minimal
  confirmatory MGMFRM before exposing generalized fitting. [Source-aligned raw
  GMFRM/MGMFRM Stan reference models, BridgeStan JSON fixtures, generation
  script, and default Julia checks are in place for the internal fixture
  targets; nested fit-ready scalar GMFRM and confirmatory MGMFRM oracle checks
  are in place while broader generalized fitting remains guarded]

### v0.3 HMC Estimation Core

- Add AdvancedHMC/Turing sampling behind a shared fit object. [AdvancedHMC
  minimal backend added]
- Add diagnostics with parameter-block pass/fail flags. [Done for current
  identified blocks]
- Store sampler controls, optional seeds, thread/package environment metadata,
  and draw-inclusion policy in a fit artifact. [Done for current fit object]
- Add RDS-like serialized fit caches with initialization-vector hashes and
  explicit cache-key invalidation checks. [Done for current fit object]
- Add artifact content hashes and long-term archive manifests for exported
  cache bundles. [Done for current fit artifact/cache records]
- Expose log likelihood, log prior, and log posterior separately.
- Add AD gradient checks and fixture-only HMC smoke tests for internal
  GMFRM/MGMFRM raw targets before broad generalized fitting. [ForwardDiff
  raw-target gradient checks, fixture-only AdvancedHMC/NUTS smoke tests, and
  guarded scalar GMFRM method wiring done]
- Validate against Stan on small and medium fixtures.

### v0.4 Bayesian Workflow Layer

- Extend prior/posterior predictive checks and calibration. [Single-dataset
  simulation, recovery summaries, and plotting-ready recovery/calibration/PPC
  rows added for the current fit-supported MFRM/RSM/PCM slice]
- Add multiple credible intervals, probability of direction, and ROPE summaries.
- Add PSIS-smoothed or exact/K-fold LOO and prior/likelihood sensitivity.
  [Raw importance-sampling LOO and Pareto-k diagnostics are available for the
  current minimal fit path]
- Add first-class sensitivity comparisons for threshold, discrimination, DFF,
  anchor, dimensionality, and prior choices.

### v0.5 Practitioner Outputs

- Add fair averages, expected-score summaries, infit/outfit, residuals,
  separation/reliability, rater diagnostics, Wright-map data, DFF reports, and
  anchoring/linking diagnostics.

### v0.6 Validation Evidence

- Build simulation grids and real-data case studies, including parameter
  recovery, interval coverage, calibration, predictive checks, and decision
  stability.
- Predeclare falsification conditions for sparse Bayesian MGMFRM claims.
- Compare against Stan and overlapping MFRM tools.
- Archive full and fast reproduction artifacts.

## Next 30-45 Days

1. Split the scalar GMFRM promotion candidate from source-fixture helper logic
   into an internal fit-ready compiler path with generated raw blocks,
   constrained blocks, transforms, constraints, and prior-policy rows.
   [Initial manifest split done]
2. Extend BridgeStan fixtures to the fit-ready scalar GMFRM candidate and
   compare raw log density, raw gradient, constrained direct parameters,
   pointwise log likelihood, and total likelihood. [Done for scalar GMFRM]
3. Replace smoke-only HMC evidence with a tiny predeclared candidate-chain
   study that records divergences, max-depth hits, E-BFMI, raw/direct R-hat,
   raw/direct ESS, direct constraint failures, and pointwise finiteness.
   [Done for the local two-fixture scalar GMFRM study]
4. Decide whether a guarded scalar GMFRM entry point, such as
   `fit(spec; experimental = true)`, can be exposed; if any source, transform,
   Stan, HMC, recovery, or documentation check fails, keep it internal.
   [Current decision: enable guarded experimental for scalar GMFRM; local
   interval/decision, sparse-design,
   WAIC influence, raw importance LOO/Pareto-k, deterministic K-fold refit,
   guarded-exposure review, guarded fit API dry-run, and guarded method-wiring
   artifacts plus experimental fit validation-grid and posterior predictive
   evidence plus sparse-pathology recovery and prior/likelihood sensitivity
   evidence plus a compact real-data case study, local claim-level archive,
   broader exposure decision review, and MGMFRM sparse recovery evidence
   plus DFF estimand/validation and Gate E manuscript-scale evidence recorded,
   with full paper reproduction evidence now blocking broader exposure]
5. Predeclare the first scalar GMFRM simulation grid and recovery criteria.
   [Initial full-crossed recovery smoke artifact, same-observation baseline
   comparison, three-scenario baseline/calibration grid, interval/decision
   grid, scalar sparse-design grid, WAIC influence review, raw importance
   LOO/Pareto-k review, deterministic K-fold refit review, guarded fit API
   dry run, guarded method wiring, experimental fit validation grid, and
   posterior predictive grid, sparse-pathology recovery grid, and
   prior/likelihood sensitivity grid plus compact real-data case-study, local
   claim-level archive, broader exposure decision-review evidence, and local
   confirmatory MGMFRM sparse-recovery evidence plus DFF estimand/validation
   evidence and Gate E manuscript-scale evidence done; full paper reproduction
   evidence remains pending]
6. Freeze the first MGMFRM candidate as confirmatory: fixed Q-mask, fixed
   latent identity correlation, documented ability scale, and explicit
   sign/positivity rules. [Initial internal gauge manifest and fit-ready
   candidate transform manifest done; confirmatory BridgeStan oracle and
   local candidate-chain/recovery-smoke studies plus keep-internal public API
   decision, caveat docs, and fit-artifact contract done]
7. Select the real rater-mediated case-study candidate and record licensing or
   anonymization status.

## Current Risks

| Risk | Response |
| --- | --- |
| Direct-prior ambiguity | Keep priors on raw coordinates and block public direct-prior API. |
| Scalar GMFRM HMC pathologies | Tune parameterization, strengthen priors, or keep GMFRM internal. |
| MGMFRM gauge confusion | Restrict v1 to confirmatory Q-mask and fixed identity correlation. |
| Sparse-design overclaim | Narrow claims, add warnings, or require stronger validation. |
| BridgeStan drift | Treat Julia/Stan fixture disagreement as a release blocker. |
| Documentation drift | Require synchronized README, docs, manifest, and roadmap status updates. |

## Red Lines

- Do not add per-rater thresholds without hierarchical pooling and explicit
  warnings.
- Do not report model weights without influence diagnostics and a prediction
  target statement.
- Do not call a DFF contrast unfairness without practical magnitude and model
  checking.
- Do not use single-run timings as manuscript evidence.
- Do not claim MGMFRM is implemented until fit-ready multidimensional
  fixtures, identification/gauge documentation, and sampler diagnostics all
  pass.
