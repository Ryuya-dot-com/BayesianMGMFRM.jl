# Roadmap and Scope

This page summarizes the package roadmap from a skeptical Bayesian measurement
reviewer's point of view. It is intentionally conservative: features move
forward only when their identification, diagnostics, validation, and reporting
contracts are clear.

The progress ledger below is the repository's implementation checklist.

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
  random-walk Metropolis, an AdvancedHMC/NUTS backend with a shared analytic/AD
  gradient adapter, and a Turing/NUTS wrapper around the same
  `MFRMLogDensity` target;
- guarded experimental generalized fitting via
  `fit(spec; experimental = true)`, returning [`GMFRMFit`](@ref) for the scalar
  rater-consistency GMFRM candidate, configured with the compatibility keyword
  `discrimination = :rater`, or [`MGMFRMFit`](@ref) for the fixed-Q
  two-dimensional confirmatory MGMFRM candidate;
- fit metadata, chain summaries, R-hat/ESS summaries, posterior summaries,
  prior/posterior predictive checks, calibration summaries, fair-average
  summaries, separation/reliability summaries, rater diagnostics, Wright-map
  rows, DFF screening rows, infit/outfit, WAIC, raw importance-sampling LOO,
  supplied heldout K-fold summaries, and same-observation or heldout
  comparisons;
- scalar Julia/BridgeStan validation fixtures and internal hand-computed
  source-aligned GMFRM/MGMFRM preview fixtures, including raw-coordinate
  source-constraint transforms, used by the test suite.

The current `backend = :julia` sampler is a random-walk Metropolis path for
small validation examples. `backend = :turing` is a NUTS interface limited to
the current minimal MFRM/RSM/PCM design. `backend = :advancedhmc` also backs the
guarded scalar GMFRM and fixed-Q confirmatory MGMFRM candidates when
`experimental = true`.

## Not Yet Public API

The following are planned but not yet exposed:

- broader production HMC/NUTS workflows beyond the minimal design and guarded
  generalized candidates;
- fit-ready GMFRM/MGMFRM likelihood compilation beyond the current
  specified-only manifests, row-by-category compiler previews, internal
  hand-computed GMFRM/MGMFRM source fixtures, preview-design raw/direct
  pointwise likelihood matrices, and guarded scalar/fixed-Q experimental paths;
- generalized rater/item discrimination terms beyond the guarded candidates;
- modeled DFF/bias effects;
- multidimensional loading and rotation/gauge machinery beyond the fixed-Q
  identity-correlation candidate;
- broader production exact/refit-management orchestration beyond the
  fit-supported shared-plan comparison slice and explicit guarded generalized
  refit execution;
- publication-grade manuscript rendering and publication/registration workflows
  beyond the current machine-readable reports, multi-report review dossiers,
  and local full-paper archive.

## Active MGMFRM Release Sequence

The source-grounded staged plan is maintained in
[MGMFRM Research Roadmap](mgmfrm-research-roadmap.md). The active sequence is:

- `v0.1.1`: refine fixed-Q confirmatory MGMFRM by strengthening execution,
  diagnostics, reporting, and validation for the existing guarded path.
- `v0.1.2`: remain fixed-Q and confirmatory, while expanding dimensionality
  and Q validation.
- `v0.1.3`: decide whether free latent correlations are ready for guarded
  exposure.
- `v0.1.4`: design exploratory loading and rotation policy before broad
  exposure.
- `v0.2.0`: promote generic MGMFRM only as a stable-public candidate after the
  earlier gates pass.

After `v0.2.0`, external validation should begin with known-truth simulation
comparisons against overlapping R package targets. Real-data validation and
R-package overlap claims are deliberately not `v0.1.x` or `v0.2.0` release
gates.

## v0.1.1 Focus

The next release should refine the core generalized and multidimensional
surfaces rather than broaden public claims. The target is better auditability:
the guarded scalar GMFRM and fixed-Q confirmatory MGMFRM paths should explain
their source equations, constraints, priors, diagnostics, and reports clearly
enough for serious review.

`v0.1.1` should keep these boundaries:

- no exploratory MGMFRM loadings, rotations, or free latent correlations;
- no dimensions beyond the guarded fixed-Q two-dimensional candidate;
- no fitted DFF model effects;
- no public model-weight, sparse-superiority, or manuscript-level claims;
- no direct-scale generalized priors unless the log-Jacobian policy is fully
  documented and tested.

The implementation roadmap has six workstreams.
The issue-sized implementation checklist is maintained in
[v0.1.1 Implementation Checklist](v0.1.1-implementation-checklist.md).

1. **Equation and status audit**: reconcile public terminology for rater
   consistency, item/dimension discrimination, raw coordinates, direct
   parameters, constraints, and status levels across `model_manifest`,
   `constraint_table`, `fit_metadata`, reports, README text, and docs. Add a
   [`related_software_capability_matrix`](@ref) so the package is positioned
   against Facets, TAM, mirt, sirt, immer, and brms/Stan workflows without
   overstating coverage. Add
   `evidence_artifact_schema_policy` rows for schema version,
   package/git/environment hashes, cache provenance, unsupported-claim flags,
   and raw-data/anonymization status. Add [`release_gate_check`](@ref) so
   README, docs, roadmap, and manifest status rows fail fast when they drift.
2. **Generalized MFRM refinement**: make the scalar GMFRM experimental path use
   a coherent compiler-generated raw/direct block layout, improve unsupported
   option errors with actionable `blocked_option` and `next_gate` values, keep
   broader GMFRM variants gated, decide whether item discrimination remains
   preview-only or becomes an internal promotion target, separate stable
   guarded public target labels from private constructor names in artifacts,
   record that rater-step source blocks are not yet public fit options, expose
   prior/pooling policy rows in `fit_report`, and record that
   hierarchical facet priors or partial pooling remain blocked until estimands,
   hyperpriors, shrinkage diagnostics, and sensitivity are documented.
3. **Fixed-Q MGMFRM hardening**: `q_matrix_validation` now validates Q-matrices
   for empty rows/dimensions, aliased columns, fixed cross-loading policy, and
   dimension-specific coverage; dimension labels now flow through manifests,
   constraint rows, metadata, reports, and report tables; `fit_report` records
   the fixed gauge and blocked alternatives. `rating_design_audit` now covers
   missingness, anchor coverage,
   repeated ratings, time/order fields, sparse person-rater-item blocks, and
   nonignorable assignment warnings, and add checks that reports do not depend
   on rotation or free latent correlation interpretations.
4. **Diagnostics and reporting**: standardize generalized diagnostics across
   `GMFRMFit` and `MGMFRMFit`, report the prior contract and prior-predictive
   implications, add posterior predictive and calibration rows that state the
   predictive path used, label the current classical R-hat/ESS diagnostics
   clearly until rank-normalized R-hat and bulk/tail ESS are implemented, and
   keep WAIC/LOO/K-fold outputs as diagnostic rows rather than model-weight
   claims. Add a binary-response note that distinguishes many-facet
   Rasch/1PL IRT from generalized binary GMFRM/MGMFRM terms. Add runtime,
   memory, and ESS/sec fields without making performance claims before sampler
   quality gates pass. Add category-functioning rows for observed category use,
   skipped/sparse categories, posterior step uncertainty, predictive category
   replication, and diagnostic-only category-collapsing flags.
5. **Validation evidence**: add small and medium BridgeStan fit-target
   comparisons, predeclared simulation grids for rater consistency and
   fixed-Q loading recovery, compact workflow demonstrations, prior-scale
   sensitivity rows, prior/likelihood power-scaling sensitivity with
   weight-ESS or Pareto-k/refit follow-up flags, and versioned evidence
   artifacts. Defer real-data validation and overlapping R-package comparison
   until after `v0.2.0`, and run the R comparison first as a known-truth
   simulation study. Include missingness, weak linking, skipped categories,
   and rater-specific category compression in the simulation pathologies.
6. **Interpretation policy**: keep model comparison diagnostic rather than
   claim-making, stabilize plotting-data schemas before backend-specific
   visualization recipes, keep DFF/bias effects validation-only, add rater
   homogeneity summaries based on posterior contrasts with ROPE and HDI or
   explicitly labelled central intervals, add a FACETS-fit compatibility
   policy for infit/outfit MNSQ, degrees-of-freedom approximations, and ZSTD
   labels, add migration examples for users coming from Facets/TAM/mirt/sirt/
   immer, and keep Bayes factors out of the default workflow until
   prior-sensitivity policy is documented.

The release gate is documentation and evidence, not API breadth. `v0.1.1`
should ship only if the guarded GMFRM/MGMFRM paths become easier to inspect and
harder to overinterpret. Broad generalized fitting remains blocked until the
later stable-public gates pass.

### Critical Triage Rules

The next roadmap decisions should use a conservative triage order:

1. **Correctness before speed**: source-equation, BridgeStan, raw/direct
   transform, and pointwise likelihood checks outrank runtime and API breadth.
2. **Diagnostics before interpretation**: posterior summaries are reportable
   only when sampler diagnostics, direct-constraint checks, and prediction-path
   labels are present in the same artifact.
3. **Design support before fairness**: DFF rows remain screening evidence
   unless the rating graph, group/rater/item cells, and posterior predictive
   checks support the requested contrast.
4. **Sensitivity before ranking**: model ranking, rater ordering, loading
   interpretation, and sparse-design claims require prior/likelihood
   sensitivity rows and explicit practical-magnitude thresholds.
5. **Scope labels before examples**: every runnable example must state whether
   it is `supported`, `experimental_public`, `specified_only`, or `blocked`.

Fallback paths should be explicit. If fixed-Q MGMFRM diagnostics are unstable,
`v0.1.1` should ship report-governance and validation improvements without
expanding examples. If source or sensitivity checks fail for generalized
blocks, keep the API guarded and document the failed gate. If external
comparison targets do not match, classify them as non-overlap rather than
forcing a misleading validation table.

### Evidence Maturity Matrix

Use the weakest satisfied row as the public status of a feature.

| Status | Required artifacts | Allowed public wording |
| --- | --- | --- |
| Specified only | Spec/design rows, constraints, blocked-option rows, and unsupported-claim flags. | The model can be described and inspected, but not fit or interpreted. |
| Experimental public | Narrow fitting path, source/transform checks, small examples, diagnostics, and explicit caveats. | Users may run the path for review or experimentation; conclusions are provisional. |
| Fit supported | Stable constraints, documented priors, block diagnostics, PPC/calibration rows, prediction-target labels, and reproducible artifacts. | The package supports fitting this narrow model under stated design conditions. |
| Interpretation supported | Fit-supported evidence plus practical-magnitude thresholds, sensitivity checks, design-support checks, and report wording tests. | Posterior contrasts or summaries may be interpreted within the stated scope. |
| Validation supported | Interpretation-supported evidence plus known-truth simulations and compatible external-target comparisons. | The claim may appear in release notes, papers, or external validation summaries. |

This matrix is deliberately stricter than the existence of exported functions.
For example, a model-comparison helper can be public while model-weight claims
remain blocked, and a DFF screening row can be useful while fitted DFF effects
remain out of scope.

### Promotion Audit Questions

Before promoting any feature, answer these questions in the docs or the
machine-readable artifact that backs the docs:

- What is the estimand, and which parameter block or contrast carries it?
- Which design conditions must hold before the estimate is interpretable?
- Which constraint, gauge, prior, and transform choices make the parameter
  identifiable?
- Which diagnostics can fail, and where does the failure appear in report rows?
- Which prior, likelihood, prediction-target, or heldout split sensitivity
  would change the substantive conclusion?
- Which comparable external target exists, if any, and which cases are
  explicitly non-overlap?
- Which row-level data, labels, hashes, or provenance fields are exported, and
  is that appropriate for public artifacts?

If one of these questions has no answer, the feature can remain callable, but
the claim should stay at `specified_only` or `experimental_public`.

### Claim Budget by Release

Each release should spend its claim budget on fewer, better-supported
statements.

| Release | Claim budget | Explicitly not in budget |
| --- | --- | --- |
| `v0.1.1` | Existing guarded scalar GMFRM and fixed-Q MGMFRM paths are more auditable: status, priors, diagnostics, Q/gauge, rating-design, report, and artifact wording become harder to overinterpret. | Broader generalized fitting, higher dimensions, fitted DFF effects, model weights, external validation, performance claims. |
| `v0.1.2` | Fixed-Q confirmatory dimensionality expands only if Q validation, source checks, initialization, diagnostics, recovery, and report schemas scale cleanly. | Free latent correlations, exploratory loading, broad MGMFRM, real-data validation claims. |
| `v0.1.3` | Free latent correlation receives a proceed/narrow/stop decision with parameterization, prior, diagnostics, and sensitivity evidence. | Automatic promotion of free correlations or exploratory loadings. |
| `v0.1.4` | Exploratory loading and rotation policy is designed and stress-tested as a reporting problem before exposure. | Stable exploratory MGMFRM claims without rotation/sign/permutation evidence. |
| `v0.2.0` | A narrower stable-public MGMFRM candidate may ship if every exposed option passes source, transform, computation, simulation, sensitivity, and reporting gates. | R-package validation and real-data validation as prerequisites for v0.2.0; those are post-v0.2.0 evidence. |
| Post-`v0.2.0` | Compatible known-truth simulation comparisons against overlapping R package targets can support external validation language. | Treating non-overlap targets or single real-data examples as validation. |

### Runtime-Aware Verification

The remaining `v0.1.1` work should use staged verification because Julia
startup, precompilation, guarded HMC smoke tests, Documenter builds, and
fixture/archive regeneration can be slow. Local slices should start with load
checks and targeted fixture scripts; manifest, report, or docs changes should
regenerate low-level fixtures before review/archive fixtures; and the fixture
SHA scan should run before the full test suite. Full `Pkg.test()` runs remain
mandatory for milestone slices, supported-Julia release checks, and the final
tag candidate, but they should not be the first feedback loop for every small
edit.

### Verification Ladder

Use the cheapest check that can falsify the current change, then climb the
ladder as the release candidate hardens.

| Stage | When to run | What it can prove | What it cannot prove |
| --- | --- | --- | --- |
| Package load | After dependency, export, or documentation-reference changes. | The package imports and precompilation reaches the changed surface. | Mathematical correctness or sampler quality. |
| Narrow unit or fixture check | After source, transform, report-row, or validation edits. | The changed contract still produces the expected rows. | Broad workflow stability. |
| Guarded smoke fit | After generalized fit, initialization, or diagnostic edits. | The narrow experimental path still runs and records failures visibly. | Production HMC reliability. |
| Fixture/archive scan | After regenerating stored evidence or report bundles. | Stored hashes and expected artifacts are internally consistent. | New statistical validity. |
| Docs build | After docs, examples, exports, or public wording changes. | References, examples, and pages render in the docs environment. | Release readiness if the docs manifest points at a stale local path. |
| Full `Pkg.test()` | Before milestone merge, release candidate, or tag. | The package-level test contract passes under the selected Julia version. | External validation or general MGMFRM support. |
| Supported-version release pass | Before tagging. | The release is reproducible across declared supported Julia versions. | Claims outside the release-scope rows. |

### Release Evidence Packet

A release candidate should have a compact evidence packet whose contents match
the release-scope claim. Missing entries do not always block a code release, but
they do block the corresponding public claim.

| Packet entry | Required for | Minimum content |
| --- | --- | --- |
| Scope summary | Every release | `release_scope_summary(; include_evidence = true)` output and blocked-claim rows. |
| Model-surface audit | Generalized or multidimensional releases | Family, dimensions, constraints, status levels, unsupported options, and public wording. |
| Source/transform evidence | Fit-surface promotion | Fixture IDs, tolerance policy, raw/direct checks, and BridgeStan or hand-computed comparison. |
| Diagnostic evidence | Fit-supported or interpretation-supported claims | Block-level diagnostics, sampler pathologies, R-hat/ESS type, direct constraints, and failure rows. |
| Design-support evidence | DFF, rater, anchor, or Q-matrix claims | Rating graph, category use, anchors, Q support, sparse cells, and confounding warnings. |
| Predictive evidence | PPC, calibration, or comparison claims | Prediction target, row matching, candidate set, PPC/calibration rows, Pareto-k or refit guidance. |
| Sensitivity evidence | Ranking, fairness, loading, or practical-decision claims | Prior-scale, likelihood-power, weight-quality, and refit-required rows. |
| Artifact governance | Public bundles or case studies | Schema version, hashes, seeds, package versions, provenance, anonymization, and raw-data policy. |
| Verification log | Release candidate | Load check, targeted tests, docs build, fixture/archive scan, and full test status. |

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
   tests for generalized raw targets; promote only the narrow scalar GMFRM and
   fixed-Q confirmatory MGMFRM paths once their evidence is recorded.
5. **Public promotion**: promote scalar GMFRM first, only after Julia and
   BridgeStan pointwise log likelihoods, transforms, AD, and sampler diagnostics
   agree. Repeat that gate for a minimal confirmatory MGMFRM with a fixed Q-mask
   and fixed latent identity correlation before expanding options.
6. **Evidence before claims**: use predeclared simulation grids, recovery
   metrics, calibration, posterior predictive checks, and Stan comparisons
   before `v0.2.0`. Defer real-data validation and overlapping R-package
   comparison until after `v0.2.0`, using known-truth simulations before any
   external validation claims.

Current exposure is deliberately conservative: MFRM/RSM/PCM fitting and
simulation/recovery helpers are public; GMFRM/MGMFRM manifests and compiler
previews are public for inspection; guarded
`fit(spec; experimental = true)` paths are available for the scalar
rater-consistency GMFRM candidate and the fixed-Q two-dimensional
confirmatory MGMFRM candidate. Broader GMFRM/MGMFRM fitting, DFF model effects,
public model-weight claims, and manuscript claims about sparse MGMFRM
superiority remain blocked. Local scalar model-weight reporting is restricted to
the heldout K-fold prediction target; confirmatory MGMFRM fitting is exposed
only as a guarded experimental path without model-weight or sparse-superiority
claims.

## Progress Ledger

The repository roadmap currently has 143 of 179 tracked checklist items complete,
or 79.9% by simple implementation accounting. The stronger claim-level
progress is lower, about 45-50%, because the remaining work includes broader
generalized fitting, broader recovery simulations, and a public-scope release
decision for generalized claims beyond the guarded GMFRM/MGMFRM experiments.

The former scalar GMFRM frontier is now a guarded experimental path. It has
source-aligned fixtures, raw transforms, BridgeStan raw checks, constrained
direct parameter checks, direct pointwise likelihood checks, ForwardDiff
diagnostics, an internal raw/direct AdvancedHMC sampler diagnostic surface, and
an internal fit-ready compiler-candidate manifest. It also has a BridgeStan
fit-ready oracle block for raw, constrained, gradient, pointwise, and
total-likelihood checks, plus a local predeclared candidate-chain study artifact
over two fixed initial-value fixtures. The committed small and medium scalar
Stan/BridgeStan log-density and gradient fixtures now have machine-readable
validation rows and a gate summary via [`stan_validation_row`](@ref) and
[`stan_validation_summary`](@ref). It also records an internal
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
full-paper reproduction archive. The fixed-Q confirmatory MGMFRM guarded sampler
is now available through `fit(spec; experimental = true)` and records raw/direct
draws, sampler diagnostics, direct constraints, pointwise log likelihood, and an
experimental fit artifact while keeping broader MGMFRM exposure blocked.
The minimal
MGMFRM path now has an internal confirmatory gauge candidate manifest, a separated
fit-ready candidate transform manifest, and a BridgeStan confirmatory-candidate
oracle block for raw, direct, gradient, pointwise, and total-likelihood checks.
It also has a local two-fixture candidate-chain diagnostic artifact, a local
recovery-smoke artifact, a local baseline-comparison artifact, and a local
sparse-recovery grid over connected sparse fixed-Q scenarios. Its public-API
decision is now `enable_guarded_experimental` for the fixed-Q confirmatory
candidate only. Guarded generalized-model caveat docs and an experimental
generalized fit-artifact contract are now recorded locally, and DFF
validation-only evidence is recorded. The generalized raw-prior
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
| `stable_public` | Ordinary examples and package claims are supported by internal simulation, sensitivity checks, and reproduction artifacts. |
| `external_validated` | Post-`v0.2.0` claims supported by known-truth R-package simulation comparisons and, only after that, real-data validation evidence. |

Scalar GMFRM can become `experimental_public` only after fit-ready raw and
constrained compiler maps exist, the raw-prior/Jacobian policy is recorded,
BridgeStan agrees with Julia on raw, constrained, and pointwise quantities,
candidate chains produce block-level diagnostics, baseline comparisons are
available, the guarded exposure decision is defensible, and unsupported options
are rejected with actionable errors.

The first MGMFRM target stays confirmatory: fixed Q-mask, fixed identity latent
correlation, documented ability scale, explicit sign/positivity rules,
manifested rater/item constraints, BridgeStan pointwise checks, and guarded HMC
diagnostics before any broader MGMFRM option is exposed.

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

DFF should be treated as screening evidence for fairness review. DFF APIs
should define estimands before fitting, separate rater main severity from DFF,
report both logit and expected-score scales, include declared-threshold
practical magnitude, and pair screening rows with model-checking evidence.

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
  [`domain_compilation_summary` now ties domain options to compiled blocks,
  fixed loading masks, scoring vectors, constraints, priors, and validation
  requirements. Observation-level design row metadata added for MFRM and specified-only
  GMFRM/MGMFRM previews; row-by-category linear-predictor metadata added for
  denominator review; internal hand-computed source-aligned GMFRM/MGMFRM preview
  fixture, raw-coordinate transform checks, and fixture-only raw-coordinate
  log-likelihood / `LogDensityProblems.jl` target checks added; preview
  raw-parameterization manifest rows now expose raw/constrained block maps,
  transform rows, raw prior policy, and no-Jacobian raw-density policy;
  normalized identification declarations now cover sum-to-zero, reference,
  fixed, geometric-mean-one, hard/soft anchors, and multidimensional gauge
  rows; fit-ready parameter layout metadata now records MFRM direct blocks and
  GMFRM/MGMFRM raw/constrained candidate blocks; guarded generalized fit
  diagnostics and fit artifacts now carry the compiler-generated
  raw/constrained layout plus raw/direct posterior row schemas; scalar GMFRM
  item-discrimination public promotion is explicitly kept preview-only for
  `v0.1.1` via a machine-readable decision row; scalar GMFRM internal
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
  confirmatory MGMFRM gauge manifest, fit-ready candidate transform manifest,
  confirmatory direct/raw pointwise fixture, fit-ready confirmatory MGMFRM
  BridgeStan oracle checks, a local confirmatory MGMFRM candidate-chain
  artifact, and a local recovery-smoke artifact, and an internal keep-internal
  public API decision manifest added]
- Add BridgeStan fixture generation for scalar GMFRM and one minimal
  confirmatory MGMFRM before exposing generalized fitting. [Source-aligned raw
  GMFRM/MGMFRM Stan reference models, BridgeStan JSON fixtures, generation
  script, and default Julia checks are in place for the internal fixture
  targets; nested fit-ready scalar GMFRM and confirmatory MGMFRM oracle checks
  are in place while broader generalized fitting remains guarded]

### v0.3 HMC Estimation Core

- Add AdvancedHMC/Turing sampling behind a shared fit object. [AdvancedHMC
  minimal backend added; shared analytic/AD gradient adapter added for current
  HMC paths; minimal Turing/NUTS backend added for the MFRMLogDensity fit path]
- Add diagnostics with parameter-block pass/fail flags. [Done for current
  identified blocks]
- Store sampler controls, optional seeds, thread/package environment metadata,
  and draw-inclusion policy in a fit artifact. [Done for MFRM and guarded
  generalized fit objects]
- Add RDS-like serialized fit caches with initialization-vector hashes and
  explicit cache-key invalidation checks. [Done for MFRM and guarded
  experimental GMFRM/MGMFRM fit objects]
- Add artifact content hashes and long-term archive manifests for exported
  cache bundles. [Done for current fit artifact/cache records]
- Expose log likelihood, log prior, and log posterior separately. [Done for
  scalar target evaluation and draw-level fit-object component vectors]
- Add AD gradient checks and fixture-only HMC smoke tests for internal
  GMFRM/MGMFRM raw targets before broad generalized fitting. [ForwardDiff
  raw-target gradient checks, fixture-only AdvancedHMC/NUTS smoke tests,
  guarded scalar GMFRM method wiring, and swappable AdvancedHMC gradient
  adapter checks done]
- Validate against Stan on small and medium fixtures. [Small and medium scalar
  Stan/BridgeStan log-density and gradient fixtures are committed, checked by
  tests, and exposed through [`stan_validation_row`](@ref) and
  [`stan_validation_summary`](@ref); broader generalized Stan fit comparisons
  remain a separate claim-level validation item]

### v0.4 Bayesian Workflow Layer

- Extend prior/posterior predictive checks and calibration. [Single-dataset
  simulation, recovery summaries, and plotting-ready recovery/calibration/PPC
  rows added for the current fit-supported MFRM/RSM/PCM slice; prior
  predictive implication diagnostics now cover category use and broad facet
  mean-score ranges; predictive-check summaries can expand grouped DFF-cell
  and observed sparse-design-block rows; calibration summaries now cover
  expected-score rows and all ordinal category-probability rows in one report;
  GMFRM/MGMFRM preview and guarded-fit simulation/recovery helpers now cover
  raw and constrained direct candidate coordinates without broad public
  generalized fitting]
- Add multiple credible intervals, probability of direction, and ROPE summaries.
  [Done for `posterior_summary`; focal [`dff_report`](@ref) rows now include
  optional estimand-specific practical-magnitude probabilities when expected-score
  or logit thresholds are declared]
- Add PSIS-smoothed or exact/K-fold LOO and prior/likelihood sensitivity.
  [Raw importance-sampling LOO, PSIS-smoothed LOO, and Pareto-k diagnostics are
  available for the current minimal fit path, guarded generalized fit objects,
  and guarded generalized preview-design raw/direct pointwise likelihood
  matrices. [`loo_refit_plan`](@ref) constructs deterministic
  one-observation-heldout plans for exact LOO follow-up from selected
  observations or Pareto-k flagged raw LOO rows, [`loo_refit`](@ref) executes
  those exact one-row refits for fit-supported MFRM/RSM/PCM specs and guarded
  experimental GMFRM/MGMFRM specs after coverage diagnostics pass, and
  [`kfold_plan`](@ref) now constructs deterministic observation-level or grouped
  heldout fold plans,
  [`kfold_plan_diagnostics`](@ref) checks heldout-only fold levels before
  refits, [`kfold_refit`](@ref) executes fit-supported MFRM/RSM/PCM heldout
  folds and explicit guarded GMFRM/MGMFRM folds automatically,
  [`loo_refit_comparison`](@ref) and
  [`kfold_refit_comparison`](@ref) run shared exact/K-fold refit plans across
  multiple fit-supported or explicitly guarded experimental candidates,
  `kfold` plus [`kfold_diagnostics`](@ref)
  record supplied heldout refit log-likelihood rows, [`compare_kfold`](@ref) summarizes same
  heldout-observation and fold-assignment comparison contracts, and
  [`kfold_sensitivity_comparison`](@ref) records baseline-relative K-fold
  sensitivity rows for supplied external summaries.
  [`prior_likelihood_sensitivity`](@ref) records local self-normalized
  importance-reweighting grids over prior and likelihood powers. Broader
  production refit-management workflows remain planned.]
- Add first-class sensitivity comparisons for threshold, discrimination, DFF,
  anchor, dimensionality, and prior choices. [`sensitivity_comparison`](@ref)
  now provides same-data, fit-object sensitivity rows with declared axes,
  custom axis values, baseline-relative differences, and declared
  dimensionality/Q sensitivity safeguards; [`kfold_sensitivity_comparison`](@ref)
  provides the same sensitivity-row shape for supplied heldout K-fold summaries.
  [`sensitivity_comparison_summary`](@ref)
  audits required threshold, discrimination, rater-pooling, DFF, anchor,
  dimensionality, and prior-regime row coverage; unsupported generalized, DFF,
  anchor, and dimensionality refit orchestration remains planned.

### v0.5 Practitioner Outputs

- Add fair averages, expected-score summaries, infit/outfit, residuals,
  separation/reliability, rater diagnostics, Wright-map data, DFF reports, and
  anchoring/linking diagnostics. [`fair_average_summary`](@ref) provides
  posterior fair-average expected-score intervals for person, rater, or item
  reports using a balanced reference grid,
  [`separation_reliability_summary`](@ref) provides posterior separation and
  empirical reliability intervals for person, rater, and item measures,
  [`rater_diagnostics`](@ref) combines rater severity, observed category-use,
  range/centrality, residual, and available discrimination diagnostics,
  [`wright_map_data`](@ref) returns backend-independent posterior facet-measure
  and item-threshold position rows for Wright-map-style displays,
  [`dff_report`](@ref) returns declared or ad hoc DFF screening rows with
  expected-score interaction residuals and local logit-scale approximations,
  [`fit_stats`](@ref) provides posterior infit/outfit rows, and
  [`residual_summary`](@ref) now provides observation- or facet-level
  expected-score and residual intervals with residual-screening caveat flags.
  [`anchor_linking_summary`](@ref) adds declared hard/soft anchor review rows,
  anchor target checks, rater-linking connectedness diagnostics, and optional
  anchor-axis sensitivity coverage summaries, while retaining the caveat that
  it is not an anchor refit or linking-constant estimator.
  [`rating_design_audit`](@ref) adds report rows for observed graph
  connectedness, rater links, anchors, complete-grid coverage, repeated
  ratings, sparse person-rater-item blocks, optional time/order metadata, and
  nonignorable rater-assignment interpretation limits.

### v0.6 Validation Evidence

- Build simulation grids and real-data case studies, including parameter
  recovery, interval coverage, calibration, predictive checks, and decision
  stability. [`simulation_grid`](@ref) and
  [`simulation_grid_summary`](@ref) now predeclare and check the density,
  anchor-size, ratings-per-target, category-pathology, rater-noise, DFF,
  dimensionality, and misspecification axes. `scripts/generate_validation_plan.jl`
  now turns those controls and the falsification-rule contract into a
  deterministic JSON plan artifact; it still does not run simulations or fit
  models.
- Predeclare falsification conditions for sparse Bayesian MGMFRM claims.
  [`falsification_rules`](@ref) and
  [`falsification_rule_summary`](@ref) now define and check required rule
  domains for sparse hierarchical-prior stability claims before those claims
  are interpreted.
- Compare against Stan and overlapping MFRM tools.
  [`comparison_evidence_row`](@ref) and
  [`comparison_evidence_summary`](@ref) now record precomputed faithful
  Stan/BridgeStan, overlapping R/frequentist, and simpler nested-model
  comparison evidence and check required comparison-class coverage. They do not
  run external tools or refit models.
- Record idle-machine repeated benchmarks.
  [`benchmark_result_row`](@ref) and [`benchmark_summary`](@ref) now record
  supplied repeated timings with median/IQR elapsed time, ESS/sec,
  time-to-quality threshold checks, and Stan/Julia ratio rows. They do not run
  benchmarks.
- Archive full and fast reproduction artifacts. [`fit_reproduction_manifest`](@ref)
  now audits full rerun and fast cached-draw paths together for the current fit
  artifact/cache/report-bundle surface and rejects mismatched fit-cache records
  before marking fast cached-draw reproduction ready. [`release_scope_summary`](@ref)
  now exposes those fit-cache, reproduction, and Documenter HTML page-size
  guardrails as local evidence rows without broadening public generalized claims,
  and records the local pre-registration gate as the manual General-registration
  readiness boundary.

## Completed 30-45 Day Sprint Record

This section is retained as the completed sprint record for guarded scalar
GMFRM and fixed-Q confirmatory MGMFRM exposure work. Broader stable-public claims
and release actions remain governed by the release-scope and manual public-scope
gates above.

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
   plus DFF estimand/validation, Gate E manuscript-scale evidence, and local
   full-paper reproduction archive recorded; broader exposure remains blocked
   by public-scope release review]
5. Predeclare the first scalar GMFRM simulation grid and recovery criteria.
   [Initial full-crossed recovery smoke artifact, same-observation baseline
   comparison, three-scenario baseline/calibration grid, interval/decision
   grid, scalar sparse-design grid, WAIC influence review, raw importance
   LOO/Pareto-k review, deterministic K-fold refit review, guarded fit API
   dry run, guarded method wiring, experimental fit validation grid, and
   posterior predictive grid, sparse-pathology recovery grid, and
   prior/likelihood sensitivity grid plus compact real-data case-study, local
   claim-level archive, broader exposure decision-review evidence, local
   confirmatory MGMFRM sparse-recovery evidence, MGMFRM guarded fit
   method-wiring, validation-grid, API dry-run, public-exposure review,
   prediction/model-weight policy, DFF estimand/validation evidence, Gate E
   manuscript-scale evidence, and local full-paper reproduction archive done;
   broader generalized claims still need a public-scope release decision]
6. Freeze the first MGMFRM candidate as confirmatory: fixed Q-mask, fixed
   latent identity correlation, documented ability scale, and explicit
   sign/positivity rules. [Initial internal gauge manifest and fit-ready
   candidate transform manifest done; confirmatory BridgeStan oracle, local
   candidate-chain/recovery-smoke studies, guarded fit method-wiring,
   validation-grid, API dry-run, public-exposure review, prediction/model-weight
   policy, caveat docs, and fit-artifact contract done for the guarded fixed-Q
   experiment]
7. Keep the selected compact real rater-mediated case-study licensing or
   anonymization record synchronized with any publication-facing archive.
   [Done: [`case_study_provenance_manifest`](@ref) now records source
   licensing/anonymization status and syncs it to local claim-level,
   manuscript-scale, and full-paper archive rows without granting a license or
   performing publication/registration actions.]

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
- Do not report LOO model weights without Pareto-k diagnostics and a prediction
  target statement.
- Do not call a DFF contrast unfairness without practical magnitude and model
  checking.
- Do not use single-run timings as manuscript evidence.
- Do not interpret the observed rating graph as random rater assignment unless
  the design or assignment model justifies that claim.
- Do not automatically collapse sparse or disordered categories without a
  recorded analysis decision.
- Do not report partially pooled facet effects as unpooled facet locations.
- Do not export raw identifiers or row-level rating data in public artifacts by
  default.
- Do not claim broad or exploratory MGMFRM support, model-weight superiority,
  or sparse-design superiority from the guarded fixed-Q path until broader
  multidimensional fixtures, recovery/sensitivity evidence, and public-scope
  release review pass.
