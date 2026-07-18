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
- an initial specification ladder that can record fit-supported MFRM, guarded
  experimental GMFRM/MGMFRM candidates, and broader specified-only
  GMFRM/MGMFRM configurations with machine-readable constraints;
- small-example Bayesian fitting paths for the minimal identified design using
  a Julia random-walk Metropolis sampler, an AdvancedHMC/NUTS backend with a
  shared analytic/AD gradient adapter, or a Turing/NUTS wrapper around the same
  `MFRMLogDensity` target;
- guarded experimental generalized fitting through
  `fit(spec; experimental = true)` for the scalar rater-consistency GMFRM
  candidate, configured with the compatibility keyword
  `discrimination = :rater`, and the fixed-Q confirmatory MGMFRM candidate
  with `dimensions >= 2`;
- cached-fit artifacts, sampler diagnostics, R-hat/ESS rows, parameter-block
  diagnostics, prior and posterior predictive replication, calibration
  summaries, observation-level predictive quantities, fair-average summaries,
  separation/reliability summaries, rater diagnostics, infit/outfit summaries,
  WAIC, raw importance-sampling LOO, supplied heldout K-fold summaries, and
  same-data or heldout comparison helpers;
- scalar Julia/BridgeStan validation fixtures and internal hand-computed
  source-aligned GMFRM/MGMFRM preview fixtures, including raw-coordinate
  source-constraint transforms, used by the test suite.

The package does not yet expose production HMC/NUTS workflows beyond the
minimal identified MFRM/RSM/PCM slice and the guarded generalized candidates,
full GMFRM/MGMFRM compilation, generalized discrimination, modelled DFF
effects, PSIS-smoothed/exact LOO, or MGMFRM loading/rotation machinery. Those
features require the gates below.

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

## Roadmap Operating Rules

The roadmap should be judged by claim control, not by the number of exported
functions. Each release must separate five claim tiers:

1. **Runs locally**: the code loads, examples run, and narrow tests pass.
2. **Mathematically aligned**: compiler rows, constraints, transforms, and
   pointwise likelihoods match source equations and BridgeStan fixtures.
3. **Computationally credible**: chains meet block-level diagnostics under
   predeclared controls, and failures are visible in report rows.
4. **Substantively interpretable**: parameters, contrasts, DFF screens, and
   rater summaries have practical-magnitude and design-support context.
5. **Externally validated**: post-`v0.2.0` comparisons against overlapping R
   package targets or real-data workflows support broader public claims.

Only the lowest satisfied tier should be advertised. A feature that runs but
does not pass source-alignment or sampler gates remains experimental or
internal, even if its API is convenient.

### Stop, Narrow, or Proceed Rules

| Evidence outcome | Roadmap action |
| --- | --- |
| Source-equation or BridgeStan mismatch | Stop promotion; keep the surface `internal_fixture` and fix compiler/transform rows before sampler work. |
| Non-identified or weakly linked design support | Narrow the accepted spec, add validation warnings or hard rejections, and avoid recovery or fairness claims. |
| Divergences, max-depth hits, low E-BFMI, or unstable R-hat/ESS in focal blocks | Keep the path `experimental_public` at most; improve parameterization, priors, initialization, or diagnostics before expanding examples. |
| Prior/likelihood sensitivity changes focal decisions | Report the decision as prior-sensitive, require refits or stronger design evidence, and block ranking/superiority language. |
| WAIC/LOO/K-fold rank changes with influential rows or prediction targets | Treat comparison as diagnostic only; do not report model weights or sparse-superiority claims. |
| R-package overlap target is not parameterization-compatible | Label the comparison as non-overlap; do not use disagreement as validation failure or success. |
| Privacy/anonymization status is unclear | Block public evidence artifacts that expose row-level labels or identifiable data. |

### Evidence Priority

Evidence should be accumulated in this order: source fixtures, raw/direct
transform checks, AD gradients, HMC smoke checks, block-level chain diagnostics,
known-truth simulations, sensitivity grids, compact workflow demonstrations,
post-`v0.2.0` R-package simulation comparisons, and only then real-data
validation claims. Real data are useful for workflow ergonomics, but they should
not compensate for failed identification, source-equation, or sampler gates.

### Current Literature-Grounded Priority Stack

The current Zotero-backed roadmap update sharpens the next work rather than
expanding the public API immediately:

1. Use MRCML, ConQuest, and multidimensional Rasch/MIRT sources to keep the
   next MGMFRM step fixed-Q and confirmatory.
2. Use Uto-style GMFRM/MGMFRM as the direct source target for rater severity,
   rater consistency, item/dimension discrimination, ordered categories, and
   Bayesian HMC diagnostics.
3. Treat Q matrices as fallible construct design objects. Q-revision evidence
   remains local and diagnostic until false-add, false-drop, sparse-dimension,
   weak-anchor, and rater-method-noise simulations are calibrated.
4. Treat fit thresholds as profiles, not constants. Existing MFRM infit/outfit
   indicators must be compared with MGMFRM PPC, calibration, WAIC/LOO, heldout
   ELPD, parameter-shift, and decision-reversal behavior under known-truth
   simulations before threshold language becomes public.
5. Keep external software comparisons as post-`v0.2.0` known-truth simulation
   work unless the target model, estimator, constraints, and prediction target
   genuinely overlap.

The first implementation slice of item 2 is now recorded in
`mgmfrm_literature_anchored_synthetic_benchmark.json`: one deterministic
smallest-cell Uto and Ueno (2020) scalar-GMFRM dataset and one deterministic
smallest-cell Uto (2021) fixed-Q adaptation, with `1,700` total synthetic
ratings, a loading-weighted ability sum for the multidimensional source term,
parameter truth, seed separation, hashes, and a standalone-equation to
package-oracle probability check. This completes dataset materialization and
generator wiring only. `mgmfrm_literature_anchored_independent_review_packet.json`
now freezes the benchmark, generator source, hashes, exact/adapted labels, and
claim ledger for reviewer handoff. `mgmfrm_tam_overlap_baseline.json` and its
CSV now prepare a TAM `tam.mml.mfr` overlap baseline, and
`mgmfrm_tam_overlap_execution_review.json` records one local TAM run plus
diagnostic parameter-table comparisons. The follow-up
`mgmfrm_tam_comparison_policy_review.json` confirms the item-step constraint and
category-intercept mapping, freezes post-pilot thresholds for future runs, and
records that the current item/rater results clear those gates while item-step
precision does not. The predeclared multi-replication follow-up now records 30
TAM fits at 40, 100, and 250 persons: all parameter blocks pass in 10/10 primary
250-person replications, while item-step passes 6/10 at 40 persons and 10/10 at
100 and 250 persons. A same-data direct-estimate pilot now also records a stable
four-chain package fit and correlations above 0.99 between package posterior
means and TAM estimates for item, rater, and item-step blocks. This pilot was
run before direct-agreement thresholds were frozen, so it remains descriptive.
`mgmfrm_tam_direct_agreement_policy.json` now freezes the future direct
package-versus-TAM gates after that pilot and before any direct multi-replication
package fits. The separate
`mgmfrm_tam_direct_agreement_policy_refinement.json` preserves those frozen
gates while adding a prospective adjudication overlay. It distinguishes
same-data numerical agreement from known-truth recovery, classifies the current
item-step pilot as descriptive agreement without full recovery support, fixes
the 4-of-5 denominator and failed-fit/retry rules, freezes fresh disjoint seeds
and the complete package/TAM fit contracts, and prohibits extrapolation to Uto
(2021), generalized GMFRM/MGMFRM, sparse designs, or construct validity. The
scheduled execution is now recorded separately in
`mgmfrm_tam_direct_agreement_multireplication.json`. All ten package fits pass
the frozen sampler gate, all ten TAM fits pass their numerical and adapter
audit, and all three directly compared blocks pass in 5/5 primary 100-person
replications. Package and TAM known-truth recovery also pass 5/5 for every
primary block, so the narrow scientific classification is local numerical
agreement with both recovery profiles. The 40-person stress rows still separate
agreement from recovery: direct agreement is 5/5 for all blocks, while the
package and TAM recovery counts are 4/5 for item, 5/5 for rater, and 3/5 for
item-step. Four rank-normalized R-hat values fall just above the prospective
advisory cutoff, but every frozen classical R-hat/ESS/HMC gate passes; the
advisories therefore remain visible without changing the primary decision.
The all-attempt audit retains 11 attempts and hashes 230 files, including the
non-selected result-writer failure and its same-seed infrastructure retry. A
separate post-execution review packet is ready. Its core execution hash chain
passes, while the immutable pre-execution packet is transparently retained with
an older refinement-snapshot hash rather than regenerated after seeing results;
that chronology difference now requires independent adjudication. Independent
re-execution, a signed independent review, multi-replication generalized recovery,
FACETS/ConQuest overlap bridges, and external construct data remain open. The
TAM result does not transfer to GMFRM/MGMFRM or Uto (2021) and does not release
package-wide or public validation claims. The claim-recovery/full reproduction
archives and broader/guarded exposure reviews now carry the result under that
non-transfer scope and retain independent-review and chronology adjudication as
TAM-specific blockers without disabling existing guarded local fit surfaces.

## Claim-to-Evidence Ledger

The roadmap should track claims as evidence obligations. The package can expose
helpers earlier than it can make claims about them.

| Claim surface | Minimum evidence before public wording | If evidence is missing |
| --- | --- | --- |
| Minimal MFRM/RSM/PCM workflow is usable | Load check, deterministic design rows, identified constraints, narrow examples, diagnostics, PPC/calibration rows, and report metadata. | Call it a small-example workflow, not a production workflow. |
| Scalar rater-consistency GMFRM is fit-supported | Source-aligned log density, raw/direct transform checks, AD gradient checks, block diagnostics, prior-policy rows, and sensitivity rows for rater consistency. | Keep `fit(...; experimental = true)` guarded and label outputs experimental. |
| Fixed-Q confirmatory MGMFRM is interpretable | Q validation, fixed gauge, positive interpreted loading checks, initialization fallback reporting, dimension labels, direct-constraint checks, block diagnostics, and recovery evidence. | Keep it as a fixed-Q guarded path; do not broaden into exploratory loading, free correlation, or generic MGMFRM claims. |
| DFF/fairness rows support decisions | Nonempty and weak-cell flags, group/rater/item support, grouped PPC, confounding warnings, practical-magnitude thresholds, and prior/likelihood sensitivity. | Report screening evidence only; block unfairness, bias, or causal language. |
| Model comparison can guide selection | Shared prediction target, row matching, pointwise diagnostics, Pareto-k/refit or K-fold follow-up, and sensitivity of ranks to influential rows. | Present WAIC/LOO/K-fold as diagnostics; block model weights and superiority claims. |
| External software validates the package | Comparable parameterization, known-truth simulation target, aligned scoring output, and documented non-overlap cases. | Use related-software positioning only; do not call disagreements validation failures or successes. |
| Performance is a package strength | ESS/sec by substantive block, compile/runtime and memory costs, sampler diagnostics, and accuracy checks against BridgeStan or comparable targets. | Publish no speed claims; report timings only as local environment metadata. |
| Case studies support broader claims | Provenance, anonymization status, reproduction manifest, exact package/environment hashes, and a statement of what the case does not validate. | Treat the case as an ergonomics demonstration, not validation evidence. |

## Roadmap Maintenance Loop

Before each release candidate, run the roadmap as a consistency audit rather
than as a feature wish list:

1. Compare every public claim in README, docs, examples, reports, and release
   notes against `release_scope_summary`, `model_surface_audit`, and the
   claim-to-evidence ledger.
2. Downgrade wording when the weakest evidence tier is lower than the proposed
   claim. A polished report table does not promote a model surface by itself.
3. Recheck the newest work against the stop/narrow/proceed rules. A late
   diagnostics or sensitivity failure should narrow the release, not become a
   caveat hidden in prose.
4. Record unresolved blockers as named follow-up issues with a failed gate and
   an owner surface: source equation, design support, sampler diagnostics,
   report wording, evidence bundle, privacy, or external overlap.
5. Keep historical completed work separate from active release blockers so that
   high checklist completion does not obscure low claim maturity.

## Current Roadmap Checkpoint

As of the local evidence archive that records `73` fixture artifacts, `86`
code/doc references, `73` full regeneration commands, and `5596`
manuscript-scale evidence cells, the practical boundary has moved from
"execute the MGMFRM publication-grade batch" to "attach valid external
construct evidence and an independent public-scope review before any broader
MGMFRM validation, model-comparison, construct-validity, or superiority claim."
The completed local chain now includes the full
125-unit publication-grade batch, threshold/model-weight policy review,
external-construct requirement gate, attachment intake preflight, and
external-attachment request packet.

This checkpoint creates two separate work tracks:

- **External-dependent track**: wait for user-supplied external construct
  dataset and independent public-scope review manifests. The package must not
  fabricate, infer, or approve those inputs. The next external gate is
  `attach_valid_external_construct_dataset_manifest_and_independent_public_scope_review_manifest`.
- **Local-hardening track**: continue improving guarded generalized diagnostics,
  report contracts, fixed-Q invariance checks, predictive/calibration rows,
  release-scope checks, and documentation while keeping all model-weight,
  Q-revision, construct-validity, and sparse-superiority wording blocked.

### External Attachment Critical Path

The external handoff is now machine-readable, but it is not evidence. Future
work should keep these gates separate:

| Stage | Required artifact | Promotion effect |
| --- | --- | --- |
| Request packet recorded | `mgmfrm_external_construct_attachment_request_packet.json` with 25 user-supplied fields, 10 checklist rows, and 6 rejection conditions. | No public claim release; this only tells a data owner and independent reviewer what must be supplied. |
| Attachment acceptance | Valid external dataset manifest and independent review manifest at the recorded paths, with expected schemas, required fields, hashes, signature, and no placeholders. | Allows external scoring/review to run; does not by itself approve claims. |
| External construct scoring | Recomputed heldout or external construct metrics using the predeclared crosswalk, validation split, and scoring plan. | Can support construct-validity review only if file integrity and leakage controls pass. |
| Independent public-scope review | Signed per-claim allow/block/request-revision table bound to the exact external manifest and threshold/model-weight review hashes. | May unblock selected public wording only at the claim level; broad MGMFRM support remains separately gated. |
| Release-scope reconciliation | README/docs/reports/release notes checked against the signed claim table and evidence artifacts. | Only the weakest supported claim tier may be advertised. |

If external inputs are not available, do not create placeholder manifests to
make tests pass. Instead, keep the external blockers visible and advance the
local-hardening track.

## Public Claim Language Guardrails

Use narrow language until the evidence tier changes. The same restriction
applies to README text, docs, examples, report labels, release notes, and paper
drafts.

| Surface | Allowed wording now | Blocked wording now |
| --- | --- | --- |
| MFRM/RSM/PCM | "small-example Bayesian many-facet Rasch workflow" and "identified minimal design" | "production-grade MFRM replacement" or "fully validated MFRM platform" |
| Scalar GMFRM | "guarded experimental rater-consistency path" | "general GMFRM support" or "rater discrimination fully validated" |
| Fixed-Q MGMFRM | "guarded fixed-Q confirmatory experiment" | "exploratory MGMFRM", "free multidimensional structure", or "general MGMFRM support" |
| DFF/fairness | "screening rows", "design-support warnings", and "posterior predictive checks" | "bias detection", "unfairness proof", or "causal DFF effect" |
| Model comparison | "diagnostic comparison for a named prediction target" | "model weights", "best model", or "sparse-design superiority" |
| External software | "capability positioning" and "post-v0.2.0 overlap target" | "validated against R packages" before compatible known-truth comparisons exist |
| Performance | "local runtime metadata" | "faster than Stan/R" before ESS/sec, diagnostics, memory, and accuracy evidence exist |
| Case studies | "workflow demonstration" | "real-data validation" unless provenance, reproduction, sensitivity, and external-overlap evidence support it |

## Minimum Gate Thresholds

These are default gates for promotion discussions. They can be overridden only
when the release decision record explains why the weaker threshold is still
defensible.

| Gate | Default threshold | Action when missed |
| --- | --- | --- |
| Source alignment | Hand-computed, Julia, and BridgeStan pointwise log likelihoods agree within predeclared tolerance for the promoted target. | Stop promotion and fix equations, indexing, constraints, or transforms. |
| Gradients | AD gradients match finite-difference or external reference checks at stable fixture points. | Keep the target internal; do not run promotion HMC as evidence. |
| HMC pathologies | Zero unreported divergences, no unreported max-depth saturation, finite log density, and E-BFMI reported where available. | Keep the path experimental and improve parameterization, priors, or initialization. |
| Chain diagnostics | Manuscript-facing blocks use max R-hat <= 1.01 and bulk/tail ESS >= 400 for focal contrasts; weaker smoke thresholds must be labelled as smoke tests. | Remove interpretation examples or label conclusions diagnostic-only. |
| Direct constraints | Direct draws satisfy positivity, gauge, location, product/scale, and Q-mask constraints with zero silent failures. | Stop interpretation and repair raw/direct transforms or report checks. |
| Predictive comparison | WAIC/LOO/K-fold rows name the prediction target, row matching, candidate set, and influential-row or Pareto-k follow-up policy. | Block model weights, ranking, and superiority wording. |
| Sensitivity | Prior/likelihood perturbations do not change focal decisions, or the decision is explicitly labelled sensitive with refit guidance. | Block ranking, fairness, or practical-decision language. |
| Design support | Rating graph, anchors, category use, Q matrix, and DFF cells support the requested contrast. | Report design triage only; do not interpret the contrast. |
| Reproducibility | Seed, sampler controls, package versions, project hashes, artifact schema, and raw-data policy are present. | Keep artifacts local or provisional. |

## Failure Triage Playbook

Gate failures should produce a specific next action. Avoid treating every
failure as a generic "needs more validation" item.

| Failure class | First check | Preferred response |
| --- | --- | --- |
| Source mismatch | Confirm row ordering, category coding, constraints, offsets, and raw/direct transforms before touching sampler code. | Fix the compiler or fixture; keep the fit path internal until the equation row passes. |
| Gradient mismatch | Check transform differentiability, constrained parameter boundaries, and finite-difference step size. | Repair the target before HMC tuning; do not use successful short chains as counter-evidence. |
| HMC pathology | Inspect the failing parameter block, initialization, prior scale, and raw/direct geometry. | Narrow examples, add stronger priors or reparameterization, and keep outputs experimental. |
| Direct-constraint failure | Identify whether the failure is transform, naming, draw extraction, or report-row logic. | Stop interpretation; add invariant tests before rerunning examples. |
| Sensitivity failure | Determine whether the focal conclusion, only nuisance blocks, or the prediction target changes. | Relabel the conclusion sensitive, require refits where needed, and block decision language. |
| Design-support failure | Inspect connectedness, anchors, sparse cells, skipped categories, Q support, and confounding. | Report design triage; avoid fairness, recovery, and ranking claims for that contrast. |
| Docs/manifest drift | Compare README, docs, examples, reports, `release_scope_summary`, and `model_surface_audit`. | Narrow public wording first; only then decide whether code promotion is still appropriate. |
| Artifact privacy failure | Inspect exported identifiers, row-level data, case-study labels, hashes, and provenance rows. | Remove or anonymize raw fields and require explicit opt-in before public artifact claims. |

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

Weakness response plan:

- Treat TAM/mirt/sirt/immer breadth as a baseline, not as a feature checklist.
  The package should not try to duplicate every generic IRT, MIRT, DIF,
  latent-class, plausible-value, and HRM function.
- Maintain a side-by-side capability matrix that separates `supported`,
  `guarded_experimental`, `specified_only`, and `out_of_scope` surfaces.
- Defer overlap validation against Facets/TAM/mirt/sirt/immer until after
  `v0.2.0`, and run it first as a known-truth simulation comparison for
  genuinely comparable model targets.
- Use the package's distinctive claims carefully: Bayesian MGMFRM workflow,
  source-audited equations, sparse-design validation, prior sensitivity,
  posterior predictive checking, and reproducible reporting.
- Avoid performance claims until ESS/sec, compile/runtime cost, memory use, and
  accuracy are benchmarked against BridgeStan and overlapping software.

### 4. Evidence Is Simulation-Only

Risk: simulation can show recovery but not real workflow usability.

Required package behavior:

- Use simulation for controlled recovery, misspecification, sparse-density,
  top-set, and DFF-decision outcomes.
- Before `v0.2.0`, use compact data only as workflow demonstrations, not as
  validation evidence.
- After `v0.2.0`, run known-truth simulation comparisons against overlapping R
  package targets before deciding whether real-data validation is mature enough
  for broad claims.

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
that target to a multidimensional GPCM-style, loading-weighted ability sum with
a fixed `1.7` scaling constant, rater consistency, rater severity, and item-step
effects.
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
raw-coordinate GMFRM/MGMFRM targets; broader fit-ready public generalized
fixtures are still required beyond the guarded scalar GMFRM and fixed-Q
confirmatory MGMFRM candidates.

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
policy. Broader fit-ready public generalized transforms and any direct-scale
prior/Jacobian policy remain outside the guarded candidates; the recorded
policy keeps priors on raw coordinates.

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
GMFRM/MGMFRM raw targets. The scalar GMFRM rater-consistency target and the
fixed-Q confirmatory MGMFRM target now have guarded experimental `fit` methods;
broader generalized `fit` paths remain blocked.

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
rater-consistency candidate and fixed-Q confirmatory MGMFRM candidate with
`dimensions >= 2`.

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
| GMFRM/MGMFRM manifests and compiler previews | Public preview/specification plus guarded generalized experiments | Useful for mathematical review and design inspection; only the scalar rater-consistency GMFRM candidate, configured with `discrimination = :rater`, and fixed-Q confirmatory MGMFRM candidate with `dimensions >= 2` have guarded experimental fit methods. |
| GMFRM/MGMFRM raw likelihood targets | Internal tests plus guarded experimental targets | Source-aligned fixtures, AD checks, HMC smoke tests, BridgeStan checks, and guarded GMFRM/MGMFRM fit paths exist; broader gauge contracts and exploratory promotion remain incomplete. |
| GMFRM/MGMFRM `fit` | Guarded experimental public paths | `fit(spec; experimental = true)` returns `GMFRMFit` for the scalar rater-consistency GMFRM candidate or `MGMFRMFit` for the fixed-Q confirmatory MGMFRM candidate with `dimensions >= 2`. Exploratory Q-matrices, free latent correlations, and broad generalized claims remain blocked. |
| DFF model effects | Blocked | Current DFF support is validation/specification evidence, not fitted effects. |
| PSIS/exact LOO and model weights | Local scalar policy only | Same-observation WAIC and raw importance LOO remain diagnostic-only; deterministic 3-fold heldout log-score evidence is the selected local scalar model-weight target. Public model-weight claims remain blocked until a future public model-weight claim review. |
| Manuscript claims about sparse MGMFRM superiority | Blocked | Prediction-target/model-weight policy, manual public-scope review, and a guarded local MGMFRM fit artifact path are recorded, but sparse-superiority claims still require broader reproducible validation and a separate public-scope release decision. |

## Progress Ledger and Promotion Rules

The roadmap has two different progress notions:

- **Checklist progress**: currently 151 of 182 tracked roadmap checkboxes are
  complete, or 83.0%. This is useful for implementation accounting.
- **Claim progress**: broad v1 claims are closer to 50-55% complete. Local
  reproducibility and publication-grade MGMFRM execution evidence are now much
  stronger, but public claim release still depends on valid external construct
  attachments, an independent signed public-scope review, broader generalized
  diagnostics/reporting hardening, and post-`v0.2.0` overlap validation for
  external-software claims.

The former scalar GMFRM internal promotion candidate is now a guarded
experimental path. It has source-aligned fixtures, raw transforms, BridgeStan
raw checks, constrained direct parameter checks, direct pointwise likelihood
checks, ForwardDiff diagnostics, an internal raw/direct AdvancedHMC sampler
diagnostic surface, and an internal fit-ready compiler-candidate manifest. The
scalar GMFRM candidate also has a BridgeStan fit-ready oracle block for raw,
constrained, gradient, pointwise, and total-likelihood checks, plus a
predeclared local candidate-chain study artifact over two fixed initial-value
fixtures. The committed small and medium scalar Stan/BridgeStan log-density and
gradient fixtures now have machine-readable validation rows and a gate summary
via `stan_validation_row` and `stan_validation_summary`. It also records an
experimental-public decision manifest whose current decision is
`enable_guarded_experimental` for the scalar rater-consistency path. It now
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
a local full-paper reproduction archive are now recorded. The fixed-Q
confirmatory MGMFRM guarded sampler is now available through
`fit(spec; experimental = true)` and produces an experimental fit artifact while
keeping broader MGMFRM exposure blocked.

The local publication-grade MGMFRM chain has since advanced through a completed
125-unit batch, threshold/model-weight policy review, external-construct and
independent public-scope requirements gate, attachment intake preflight, and an
external-attachment request packet. These artifacts make the handoff auditable,
but they intentionally do not create external evidence or approve public
MGMFRM fit, model-weight, Q-revision, construct-validity, or sparse-superiority
claims.

The minimal MGMFRM path now has an internal confirmatory gauge candidate manifest
and a separated fit-ready candidate transform manifest. It also has a
BridgeStan confirmatory-candidate oracle block for raw, direct, gradient,
pointwise, and total-likelihood checks, plus a local two-fixture candidate-chain
diagnostic artifact, a local recovery-smoke artifact, and a local
baseline-comparison artifact and a local sparse-recovery grid over three
connected sparse fixed-Q scenarios. Guarded generalized caveat docs, DFF
validation-only evidence, and Gate E evidence are recorded locally for both
scalar GMFRM and confirmatory MGMFRM.
The experimental generalized fit-artifact contract is now populated by the
guarded scalar GMFRM fit path and by the guarded experimental MGMFRM path for
the fixed-Q confirmatory candidate. MGMFRM exploratory fitting and broader
public claims remain blocked. The generalized
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
| `stable_public` | The surface supports ordinary package examples and package claims. | Predeclared internal simulation grid, sensitivity checks, reproducibility archive. |
| `external_validated` | Post-`v0.2.0` external validation claims are supported. | Known-truth comparisons against overlapping R-package targets and, only after those comparisons are understood, real-data validation evidence. |

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

### Active post-v0.1.0 MGMFRM release sequence

This active sequence keeps the package claim narrow while the generalized and
multidimensional surface is hardened. See
[`docs/src/mgmfrm-research-roadmap.md`](docs/src/mgmfrm-research-roadmap.md)
for the literature-grounded rationale and detailed gates.

| Version | Scope | Release gate |
| --- | --- | --- |
| `v0.1.1` | Fixed-Q confirmatory MGMFRM refinement. Strengthen execution, diagnostics, reporting, and validation for the existing guarded path. | Guarded scalar GMFRM and fixed-Q MGMFRM are easier to audit and harder to overinterpret. |
| `v0.1.2` | Fixed-Q dimensionality and Q validation expansion. Still confirmatory. | Higher-dimensional fixed-Q examples pass source, AD, HMC, recovery, and report-shape tests. |
| `v0.1.3` | Free latent correlation decision. | Free correlation is either kept blocked, promoted internally, or exposed narrowly with diagnostics and prior policy. |
| `v0.1.4` | Exploratory loading and rotation policy design. | Rotation, sign, permutation, and reporting rules are documented and validated before exposure. |
| `v0.2.0` | Generic MGMFRM stable-public candidate. | Source, transform, prior, internal simulation/recovery, reporting, and rejection gates pass for every exposed surface; R-package simulation comparison is post-`v0.2.0`. |

### v0.1.1: generalized and multidimensional refinement

Goal: turn the `v0.1.0` guarded generalized paths from "available for narrow
experiments" into auditable experimental workflows whose equations,
parameterization, diagnostics, and reports are precise enough for serious
review. This release should improve the generalized MFRM and fixed-Q
confirmatory MGMFRM surfaces without changing the package claim to broad
GMFRM/MGMFRM support.

Issue-sized implementation drafts are maintained in
[`docs/src/v0.1.1-implementation-checklist.md`](docs/src/v0.1.1-implementation-checklist.md).
The workstreams below preserve the original planning record. For the release
candidate, scope is frozen to the completed auditability, portable-report,
fixed-Q, FACETS-description, and runnable-example work listed in the release
gate. Unchecked stretch items are deferred to `v0.1.2` or later and are not
`v0.1.1` ship criteria.

Non-goals for `v0.1.1`:

- no exploratory MGMFRM loadings, rotations, or post-hoc dimension discovery;
- no free latent correlation matrix for MGMFRM;
- no dimensionality discovery beyond a fixed confirmatory Q-matrix;
- no public DFF model-effect fitting;
- no model-weight, sparse-superiority, or manuscript-level claims;
- no direct-scale generalized priors unless the log-Jacobian policy is fully
  documented, tested, and exposed in reports.

#### v0.1.1 Workstream A: equation, naming, and status audit

- [x] Reconcile public terminology for the generalized path: use
  "rater consistency" where that is the source-equation parameter, reserve
  "discrimination" for item or dimension discrimination, and keep any legacy
  aliases documented as compatibility wording.
- [x] Add a model-surface audit table that records, for every GMFRM/MGMFRM
  block, the source symbol, direct interpretation, raw coordinate, constraint,
  prior scale, report label, and current status level.
- [x] Keep `experimental_public` and related machine labels in the complete
  version-1 compatibility payload, while README, published docs, displays, and
  the structured public report use reader-facing `experimental`, `supported`,
  and `not_supported` labels.
- [x] Add an evidence-artifact schema policy: schema version, package/git/
  environment hashes, seed and sampler controls, cache provenance,
  unsupported-claim flags, and raw-data/anonymization status.
- [x] Add a related-software capability matrix that compares Facets, TAM,
  mirt, sirt, immer, brms/Stan-style workflows, and `BayesianMGMFRM.jl` across
  model coverage, estimation method, rater effects, multidimensional support,
  Bayesian diagnostics, sensitivity analysis, and report artifacts.
- [x] Add a release-gate check that fails when README, docs, roadmap, and
  manifest status rows disagree about generalized support.

Exit criterion: a reviewer can trace every public generalized label back to a
source-equation role and a machine-readable manifest row.

#### v0.1.1 Workstream B: generalized MFRM compiler refinement

- [x] Separate the guarded GMFRM fit target from "promotion candidate"
  internal naming in user-facing artifacts while preserving private helper names
  where needed for compatibility.
  - [x] Add stable public target labels to GMFRM/MGMFRM experimental decision
    manifests and fit artifacts:
    `guarded_scalar_gmfrm_logdensity` and
    `guarded_confirmatory_mgmfrm_logdensity`.
  - [x] Keep `_gmfrm_promotion_candidate_*` and guarded local MGMFRM helper
    names as internal compatibility metadata via `internal_*_constructor`
    fields.
  - [x] Require `public_target_label` and `internal_target_constructor` in
    generalized experimental fit artifact contracts.
- [x] Generate the scalar GMFRM raw/direct block layout, transforms,
  constraints, and direct posterior row schema from the same compiler path used
  by `model_manifest` and `getdesign`.
- [ ] Tighten validation for the guarded scalar GMFRM path: reject unsupported
  item-discrimination, rater-step, DFF-effect, and multidimensional variants
  with errors that describe the supported configuration and next user action
  instead of generic unsupported messages.
  - [x] Add actionable reader-facing messages for item-discrimination,
    DFF-effect, unsupported backend/prior choices, and multidimensional GMFRM
    spec construction, while keeping maintenance gate identifiers out of
    public errors.
  - [x] Add an explicit user-facing rater-step option/policy gate before
    rater-step variants can be rejected as public options rather than internal
    source-model blocks.
- [x] Decide the first item-discrimination GMFRM promotion target: either keep
  item discrimination preview-only in `v0.1.1`, or add an internal
  fit-candidate manifest with BridgeStan and recovery gates before any exposure.
- [x] Add block-level prior controls for raw rater-consistency and any internal
  item-discrimination candidate, while keeping the default raw-prior/no-Jacobian
  policy explicit in artifacts and reports.
- [x] Add a user-facing prior contract row for every generalized fit: public
  MFRM priors are weakly informative independent normals on identified
  parameters, guarded generalized priors are independent normals on raw
  unconstrained coordinates, and direct-scale generalized priors remain disabled
  until a log-Jacobian policy is implemented.
- [x] Add a pooling-policy row for generalized fits: v0.1.x uses independent
  priors by default; hierarchical facet priors or partial pooling remain
  blocked unless estimands, hyperpriors, shrinkage diagnostics, and sensitivity
  are documented.

Exit criterion: the scalar GMFRM experimental path is generated, diagnosed, and
reported as a coherent generalized MFRM surface, and unsupported broader GMFRM
options fail with actionable gate names.

#### v0.1.1 Workstream C: fixed-Q MGMFRM gauge hardening

- [x] Add Q-matrix validation rows for empty dimensions, empty items, duplicate
  or aliased dimension columns, disconnected dimension/facet subgraphs, and
  item blocks that cannot identify positive interpreted loadings.
- [x] Add rating-design audit rows for structural versus accidental
  missingness, disconnected components, anchor coverage, repeated ratings,
  optional time/order fields, sparse person-rater-item blocks, and nonignorable
  assignment warnings.
- [x] Expose dimension labels throughout `model_manifest`, `constraint_table`,
  direct posterior summaries, `fit_report`, and exported table files.
- [x] Add explicit report rows for the fixed gauge: fixed identity latent
  correlation, standard-normal ability scale, positive interpreted loadings,
  fixed `1.7` scaling, rater consistency constraints, rater severity location
  constraints, and item-step constraints.
- [ ] Improve guarded MGMFRM initialization strategies for sparse fixed-Q
  designs and report when initialization falls back to conservative
  zero-centered raw coordinates.
- [ ] Add invariant checks showing that the fixed-Q reports do not rely on
  rotation, sign switching, or free latent correlation interpretation.

Exit criterion: the fixed-Q MGMFRM fit object can explain why the dimensions are
identified, how they are labeled, and which broader multidimensional choices
remain blocked.

#### v0.1.1 Workstream D: diagnostics and posterior workflow

- [ ] Standardize `diagnostics`, `parameter_block_diagnostics`, and
  `sampler_diagnostics` across `MFRMFit`, `GMFRMFit`, and `MGMFRMFit`,
  including divergences, max-depth hits, E-BFMI availability, rank-normalized
  R-hat, bulk/tail ESS, and direct-constraint failures.
- [ ] Until rank-normalized diagnostics are implemented, label the current
  classical split R-hat and autocorrelation ESS as provisional in reports and
  artifacts, and keep the thresholds explicit.
- [ ] Add prior-policy and prior-predictive report rows for guarded generalized
  fits: raw prior scales, direct-scale prior status, no-Jacobian policy,
  prior-predictive category/facet implications, and any prior implication
  warnings.
- [ ] Add generalized posterior predictive summaries that are explicit about
  whether expected scores are computed from direct GMFRM/MGMFRM draws or from
  the minimal MFRM predictive path.
- [ ] Add calibration summaries for guarded generalized fits by rater, item,
  category, group/DFF cell, and sparse-design block.
- [ ] Add category-functioning report rows: observed category use by rater,
  item, and dimension; skipped or sparse categories; posterior step/threshold
  uncertainty; predictive category replication; and diagnostic-only category
  collapsing flags.
- [ ] Add direct-parameter posterior summary rows for generalized blocks with
  probability of direction and practical-magnitude fields where interpretation
  is defensible.
- [ ] Add a binary-response interpretation note to docs and reports: the
  two-category MFRM is a many-facet Rasch/1PL IRT model, while binary
  GMFRM/MGMFRM variants with item discrimination, rater consistency, or
  multidimensional Q-masked loadings are generalized IRT models rather than
  strict Rasch models.
- [ ] Keep WAIC, raw LOO, and K-fold comparison outputs available as diagnostic
  rows only; block model-weight language in generalized reports.
- [ ] Add benchmark-report fields for ESS/sec, compile time, runtime, memory,
  and backend used, while preventing speed claims when sampler quality gates
  fail.

Exit criterion: a guarded generalized report can be reviewed without reading
private notebook logic or inferring which predictive path was used.

#### v0.1.1 Workstream E: interpretation, comparison, and visualization policy

- [ ] Add a model-comparison policy section to `fit_report` and evidence
  artifacts: prediction target, scoring rule, candidate set, same-data or
  heldout contract, WAIC/LOO/K-fold status, influential-row diagnostics, and
  whether refit or K-fold follow-up is required.
- [ ] Keep model comparison diagnostic in `v0.1.1`: no posterior model
  probabilities, no generalized model weights in public reports, and no
  superiority language for MGMFRM over MFRM/GMFRM baselines.
- [ ] Stabilize plotting-data schemas before adding backend-specific recipes:
  diagnostic heatmaps, trace/rank-ready rows, PPC/calibration panels, rater
  severity/consistency maps, Q-matrix/loading heatmaps, DFF screening panels,
  and model-comparison uncertainty rows.
- [x] Add a separate `facets_report` / `facets_compatibility_stats` policy while keeping
  `fit_stats` posterior infit/outfit intervals as the default Bayesian
  diagnostic. The compatibility rows record the posterior-mean plugin residual
  formula, Wright--Masters fourth-moment infit/outfit df, unit weighting,
  Wilson-Hilferty/ZSTD cap, and explicit approximation status.
- [ ] Do not treat FACETS degrees of freedom as exact for posterior-summarized
  GMFRM/MGMFRM fit statistics; require explicit approximation labels and
  simulation calibration before generalized ZSTD interpretation.
- [ ] Add migration and compatibility examples for users coming from Facets,
  TAM, mirt, sirt, or immer: column mapping, equivalent or non-equivalent model
  choices, comparable output rows, and explicit unsupported surfaces.
- [ ] Add rater homogeneity summaries for severity and rater consistency:
  pairwise posterior contrasts, ROPE probabilities, HDI or explicitly labelled
  central intervals, probability of direction, and practical-equivalence flags.
- [ ] Treat Bayes factors as optional research artifacts, not a default
  workflow. If added, they must be limited to preregistered contrasts and paired
  with prior sensitivity, power-scaling evidence, and clear warnings that point
  equality is not the default measurement decision target.
- [ ] Keep DFF/bias effects validation-only: retain sparse/empty/confounded
  cell checks, grouped PPC rows, and posterior predictive interaction residual
  screening, but do not fit DFF model effects or report unfairness claims.

Exit criterion: the guarded generalized report separates posterior summaries,
practical decisions, visualizable evidence, and blocked claims in a way that a
measurement reviewer can audit without inferring policy from code.

#### v0.1.1 Workstream F: validation evidence

- [ ] Add small and medium BridgeStan comparison fixtures for the guarded
  scalar GMFRM and fixed-Q MGMFRM fit targets, not only source-aligned
  log-density fixtures.
- [ ] Run a predeclared simulation grid focused on the `v0.1.1` question:
  rater consistency recovery, item/dimension loading recovery, sparse fixed-Q
  failure modes, calibration, PPC, interval coverage, and block-level
  diagnostics.
- [ ] Include rating-design and category pathologies in the validation grid:
  planned missingness, accidental sparse cells, disconnected or weakly linked
  components, skipped categories, and rater-specific category compression.
- [ ] Keep compact data examples as workflow demonstrations only; do not use
  real-data validation as a `v0.1.1` release gate.
- [ ] Defer overlap validation against Facets/TAM/mirt/sirt/immer until after
  `v0.2.0`, when known-truth simulation comparisons can be run against
  comparable R-package model targets.
- [ ] Add a sensitivity grid for raw-prior scales on generalized parameters and
  record when posterior decisions are prior-dominated.
- [ ] Promote `prior_likelihood_sensitivity` into a release artifact using
  power-scaling perturbations of the prior and likelihood around one. Record
  direct-parameter shifts, log-prior/log-likelihood shifts, weight effective
  sample size, and a `refit_required` or Pareto-k follow-up flag when
  importance reweighting is unstable.
- [ ] Add a compact interpretation evidence bundle that exercises model
  comparison policy rows, plotting-data exports, DFF screening, and rater
  homogeneity summaries on the minimal MFRM, scalar GMFRM, and fixed-Q MGMFRM
  examples.
- [ ] Archive the evidence as versioned JSON/report bundles with seeds,
  sampler controls, package version, git tree, source fixture hashes, and
  falsification outcomes.

Exit criterion for a later validation release: stronger experimental workflow
evidence may be claimed for the guarded generalized paths, but stable broad
GMFRM/MGMFRM support still requires its own promotion decision.

#### Post-v0.1.1 Runtime-Aware Implementation Sequence

The deferred generalized-report and validation work should be implemented in an
order that minimizes schema churn and avoids unnecessary long Julia runs:

1. Keep the external request packet as the boundary object for data-owner and
   independent-reviewer handoff. Do not write placeholder external manifests.
2. Expand fixed-Q MGMFRM initialization and invariance evidence beyond the
   contract and helper checks shipped in `v0.1.1`.
3. Add rank-normalized and bulk/tail generalized diagnostics before adding more
   report sections.
4. Add predictive-path, calibration, and category-functioning rows after the
   diagnostic shape is stable.
5. Extend the `v0.1.1` MFRM FACETS description with model-comparison policy and
   rater-homogeneity rows after the report shape is stable.
6. Finish evidence-artifact governance and evidence bundles after report schemas
   settle.
7. Reconcile public wording and release-scope rows before promoting any later
   model or evidence surface.

The external-dependent work should proceed only when valid user-supplied
manifests arrive. At that point, the first implementation task is an attachment
acceptance generator that validates schemas, required fields, hashes,
crosswalk keys, signatures, and per-claim release decisions against the request
packet before any external construct scoring or public-scope claim review is
allowed.

Verification should be staged. Use load checks and targeted fixture scripts for
small edits; regenerate low-level fixtures before review/archive fixtures; run
the fixture SHA scan before the full suite; and reserve full `Pkg.test()` runs
for milestone slices and release candidates. Final release still requires
`Pkg.test()` on supported Julia versions, docs build with the page-size gate,
example scripts, and release-scope checks.

#### v0.1.1 Release Gate

- [ ] `Pkg.test()` passes on the supported Julia versions.
- [x] Documentation builds with the page-size gate enabled.
- [x] The mandatory source-level public-language gate scans README, NEWS,
  examples, and every page in the published Documenter navigation; CI does not
  skip it.
- [x] Developer roadmaps, implementation checklists, fixture inventories, and
  registry-maintenance guidance are excluded from the published Documenter
  navigation.
- [x] Exported docstrings, representative user-visible errors, and
  reader-facing structured and Markdown report output pass a runtime
  public-language scan without implementation-only identifiers or
  machine-specific paths.
- [x] The minimal example, guarded scalar GMFRM example, and guarded fixed-Q
  MGMFRM example run with intentionally small sampler controls.
- [x] `release_scope_summary(; include_evidence = true)` includes a
  `v0.1.1_generalized_refinement` row and still marks broad generalized claims
  as blocked.
- [x] README uses `Pkg.add("BayesianMGMFRM")` as the standard installation and
  states the exact experimental model boundaries.

Release decision: ship `v0.1.1` only if the guarded GMFRM/MGMFRM paths become
easier to audit and harder to overinterpret. If the work exposes unresolved
identification or sampler pathologies, ship narrower documentation and
validation improvements instead of broadening the fit API.

### Post-v0.2.0: R simulation comparison and external validation

After `v0.2.0` completes the generic MGMFRM stable-public candidate, run a
separate external-validation phase against mature R software. This is not a
`v0.1.x` or `v0.2.0` release gate.

- Compare only genuinely overlapping model targets: Facets/TAM-style MFRM,
  TAM-compatible GPCM or multi-facet Rasch cases, mirt-style fixed-Q MIRT
  cases, and sirt/immer rater-effect cases where the parameterization can be
  matched.
- Use known-truth simulation before real data. Simulation should evaluate
  recovery, bias, RMSE, interval coverage, calibration, ranking stability,
  rater-effect recovery, DFF-screening behavior, convergence/failure rates,
  runtime, memory, and ESS/sec where applicable.
- Label non-overlap explicitly: priors, estimators, link functions,
  constraints, prediction targets, and reporting scales can make packages
  answer different questions.
- Decide real-data validation only after the R simulation comparison explains
  where the Julia and R workflows agree, differ, or are not comparable.

### Historical completed implementation tracks

The following sections are retained as the original implementation ledger. They
describe completed or earlier-scoped work and do not supersede the active
post-`v0.1.0` MGMFRM release sequence above.

### v0.1: scaffold hardening

Goal: keep the current package useful while preventing users from mistaking it
for a full Bayesian MGMFRM engine.

Completed checklist:

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

Completed checklist:

- [x] Extend `mfrm_spec` into an initial ladder that can represent MFRM, GMFRM,
  and MGMFRM as configurations of one `FacetSpec` while marking unsupported
  likelihoods as specified-only.
- [x] Add a source-traced `model_equation` contract so manifests distinguish
  the current fit-supported MFRM/RSM/PCM kernel from the primary-literature
  GMFRM/MGMFRM targets and their missing parameter blocks.
- [x] Compile domain options into fit-ready additive blocks, loading masks,
  scoring vectors, constraints, priors, and validation requirements.
  [`domain_compilation_summary` returns review rows that tie domain options to
  compiled parameter blocks, fixed loading masks, scoring vectors, constraints,
  priors, and validation requirements for fit-supported and preview designs.]
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
    protocol, artifact contract, fixture hashes, and then-current public-fit
    rejection checks while the MGMFRM entrypoint was disabled for
    subsequent validation-grid and API dry-run evidence.
  - [x] Add a local confirmatory MGMFRM guarded fit validation grid that
    aggregates the bridge oracle, candidate-chain, recovery, baseline,
    sparse-recovery, and method-wiring artifacts while the MGMFRM entrypoint
    was disabled for subsequent API dry-run and exposure-review
    evidence.
  - [x] Add a local confirmatory MGMFRM guarded fit API dry-run artifact that
    records pre-exposure public-fit rejections, the artifact contract, validation
    grid evidence, and AD/finite-difference checks for the internal target
    while public exposure was blocked until review.
  - [x] Add a local confirmatory MGMFRM guarded fit public exposure review
    artifact that reviews the internal method-wiring, validation-grid, API
    dry-run, sparse-recovery, baseline, and DFF validation evidence before
    guarded MGMFRM fitting is exposed.
  - [x] Add a local prediction-target/model-weight policy artifact that
    recorded same-observation WAIC and raw PSIS/LOO as diagnostic-only, selected
    heldout K-fold log score for local scalar model-weight reporting, and kept
    MGMFRM fit and sparse-superiority claims blocked pending manual
    public-scope review and a later release decision.
  - [x] Add a local manual public-scope review artifact for confirmatory
    MGMFRM fit that records the fixed-Q scope, keeps sparse-superiority claims
    blocked, and advanced the next local gate to the guarded local MGMFRM fit
    entrypoint.
  - [x] Add a guarded local MGMFRM fit entrypoint for the fixed-Q
    confirmatory candidate that records raw/direct draws, sampler diagnostics,
    direct constraints, pointwise log likelihood, WAIC-ready log-likelihood
    matrices, and a guarded fit artifact.
  - [x] Expose the fixed-Q confirmatory MGMFRM path through
    `fit(spec; experimental = true)` while keeping exploratory Q-matrices, free
    latent correlations, model-weight claims, and
    sparse-superiority claims blocked.
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

Completed checklist:

- [x] Integrate the analytic-gradient path where available and keep AD backends
  swappable for unsupported specs.
- [x] Implement an initial AdvancedHMC/NUTS backend with the shared fit object.
- [x] Implement Turing sampling with the shared fit object.
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
- [x] Extend simulation/recovery helpers to planned fit-ready GMFRM/MGMFRM
  target skeletons. [Simulation
  and recovery helpers now cover specified-only GMFRM/MGMFRM preview designs
  and guarded fit objects on constrained direct or raw candidate coordinates;
  broad public generalized fitting remains gated.]
- [x] Validate against Stan on small and medium fixtures before scaling.
  [Small and medium scalar Stan/BridgeStan log-density and gradient fixtures
  are committed, checked by tests, and exposed through `stan_validation_row`
  and `stan_validation_summary`; broader generalized Stan fit comparisons
  remain a separate claim-level validation item.]

Gate: scalar GMFRM and one minimal MGMFRM configuration pass convergence,
recovery, and Stan-comparison checks on predeclared sparse designs.

### v0.4: Bayesian workflow layer

Goal: make diagnostics and sensitivity analysis first-class APIs.

Completed checklist:

- [x] Implement prior predictive checks for category use, facet ranges, and
  implausible prior implications.
- [x] Implement posterior predictive checks grouped by facet, group, DFF cell,
  category, and sparse-design block.
- [x] Extend calibration summaries to ordinal categories and expected scores.
- [x] Implement posterior summaries with multiple intervals, probability of
  direction, and ROPE/practical equivalence.
- [x] Provide plotting-ready rows for current parameter-recovery, calibration,
  and predictive-check summaries without selecting a plotting backend.
- [x] Implement PSIS-smoothed or exact/K-fold LOO and dimension-matching
  safeguards. [Raw importance-sampling LOO and Pareto-k diagnostics are
  available for the current minimal fit path. `kfold_plan` now constructs
  deterministic observation-level or grouped heldout fold plans, and `kfold`
  plus `compare_kfold` summarize supplied heldout refit log-likelihood
  matrices with same heldout-observation and fold-assignment comparison
  contracts. Exact LOO refit orchestration, automatic K-fold refitting, and
  PSIS smoothing remain planned.]
- [x] Implement prior/likelihood sensitivity, including power-scaling or an
  equivalent package-native workflow.
- [x] Implement first-class sensitivity comparisons: RSM vs PCM/GPCM,
  discrimination on/off, pooled vs unpooled rater effects, DFF on/off, anchor
  choices, dimensionality, and prior regimes. [`sensitivity_comparison`] now
  provides same-data, fit-object sensitivity rows with declared axes, custom
  axis values, baseline-relative differences, and declared dimensionality/Q
  sensitivity safeguards; `sensitivity_comparison_summary` audits required
  threshold, discrimination, rater-pooling, DFF, anchor, dimensionality, and
  prior-regime row coverage. Unsupported generalized, DFF, anchor, and
  dimensionality refit orchestration remains planned.

Gate: a case-study report can be regenerated from fit objects without custom
notebook logic for diagnostics, PPC, calibration, model comparison, or
sensitivity tables.

### v0.5: practitioner MFRM outputs

Goal: make the package useful to FACETS-trained MFRM users.

Completed checklist:

- [x] Implement fair averages and expected-score summaries with uncertainty.
  [`fair_average_summary` provides posterior fair-average expected-score
  intervals for person, rater, or item reports using a balanced reference grid.]
- [x] Implement posterior infit/outfit and residual summaries with caveats.
  [`fit_stats` provides posterior infit/outfit rows, and `residual_summary`
  now provides observation- or facet-level expected-score and residual
  intervals with residual-screening caveat flags.]
- [x] Implement separation and reliability summaries with Bayesian uncertainty.
  [`separation_reliability_summary` provides posterior separation and
  empirical reliability intervals for person, rater, and item measures with
  screening caveats.]
- [x] Implement rater severity, discrimination, category-use, range/centrality,
  and residual diagnostics.
  [`rater_diagnostics` combines rater severity, observed category-use,
  range/centrality, residual diagnostics, MFRM infit/outfit where available,
  and scalar GMFRM rater-consistency discrimination summaries with screening
  caveats.]
- [x] Implement Wright-map-style data APIs before committing to one plotting
  backend.
  [`wright_map_data` returns plotting-backend-independent posterior facet
  measure and item-threshold position rows on the logit scale.]
- [x] Implement DFF reports on logit and expected-score scales.
  [`dff_report` returns declared or ad hoc DFF screening rows with
  expected-score interaction residuals and local logit-scale approximations,
  while retaining a fitted-effect caveat.]
- [x] Implement hard/soft anchors, anchor sensitivity, and robust linking
  diagnostics.
  [`anchor_linking_summary` combines declared hard/soft anchor rows, anchor
  target checks, rater-linking connectedness diagnostics, and optional
  anchor-axis sensitivity coverage. It is a diagnostic summary and does not yet
  refit anchor regimes or estimate linking constants.]

Gate: a FACETS-trained user can recognize the report, and a Bayesian reviewer
can inspect the uncertainty and diagnostics behind it.

### v0.6: validation and evidence package

Goal: make broad claims falsifiable and reproducible.

Completed checklist:

- [x] Build simulation grids for sparse-to-near-complete density, anchor size,
  ratings per target, category pathologies, rater noise, DFF,
  multidimensionality, and misspecification.
  [`simulation_grid` and `simulation_grid_summary` now predeclare and check
  these axes as machine-readable validation-grid rows.
  `scripts/generate_validation_plan.jl` now records deterministic smoke and
  manuscript validation-plan JSON artifacts from those controls plus the
  falsification-rule contract. The helper and script do not run simulations,
  fit models, or establish claim-level evidence.]
- [x] Predeclare falsification conditions for the claim that hierarchical
  priors stabilize sparse MGMFRM designs.
  [`falsification_rules` and `falsification_rule_summary` now provide
  machine-readable rule rows and required-domain checks for sparse
  hierarchical-prior stability claims. They define claim blockers but do not
  evaluate study results.]
- [x] Compare against Stan faithful models, overlapping R/frequentist tools,
  and simpler nested models.
  [`comparison_evidence_row` and `comparison_evidence_summary` now record
  precomputed faithful Stan/BridgeStan, overlapping R/frequentist, and simpler
  nested-model comparison evidence and check required comparison-class coverage.
  They do not run external tools or refit models.]
- [x] Secure and document at least one real rater-mediated case study.
- [x] Run idle-machine repeated benchmarks with median/IQR, ESS/sec,
  Stan/Julia ratios, and time-to-quality thresholds.
  [`benchmark_result_row` and `benchmark_summary` now record repeated
  idle-machine timing rows with median/IQR, ESS/sec, time-to-quality threshold
  checks, and Stan/Julia elapsed-time and ESS/sec ratios. They do not run
  benchmarks.]
- [x] Archive local full and fast reproduction scripts, manifests, seeds,
  hashes, fixture-generation commands, and verification commands without any
  publication or registration action.

Gate: a reviewer can rerun or inspect every paper claim from a versioned
artifact bundle.

## Completed 30-45 Day Sprint Record

This section is retained as the completed sprint record for guarded scalar
GMFRM and fixed-Q confirmatory MGMFRM exposure work. Broader stable-public claims
and release actions remain governed by the release-scope and manual public-scope
gates above.

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
   sign/positivity rules for interpreted loadings. [Done as a confirmatory gauge
   candidate manifest and guarded experimental public fit]
2. Implement the fit-ready raw transform and manifest rows for this minimal
   candidate. [Blueprint/manifest split done]
3. Match Julia and BridgeStan pointwise log likelihoods for the minimal MGMFRM
   fixture. [Done for the nested confirmatory-candidate BridgeStan oracle]
4. Run a tiny recovery and sampler diagnostic study only after the source and
   Stan checks pass. [Sampler diagnostic and recovery-smoke artifacts done;
   guarded experimental public API decision manifest, caveat docs, and fit-artifact
   contract done]
   - [x] Run a local confirmatory MGMFRM sparse-recovery grid over connected
     sparse fixed-Q scenarios and keep sparse-superiority claims blocked.

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
2. Keep the selected compact real rater-mediated case-study licensing or
   anonymization record synchronized with any publication-facing archive.
3. Convert the simulation grid and falsification rules into versioned scripts
   before running manuscript-scale experiments.
   [`scripts/generate_validation_plan.jl` now records deterministic smoke and
   manuscript validation-plan JSON artifacts; it does not run simulations or
   evaluate claims.]
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
- Do not interpret the observed rating graph as random rater assignment unless
  the design or assignment model justifies that claim.
- Do not automatically collapse sparse or disordered categories without a
  recorded analysis decision.
- Do not report partially pooled facet effects as unpooled facet locations;
  label shrinkage estimands and hyperpriors explicitly.
- Do not export raw identifiers or row-level rating data in public artifacts by
  default.
- Do not claim broad or exploratory MGMFRM support, model-weight superiority,
  or sparse-design superiority from the guarded fixed-Q path until the broader
  multidimensional fixtures, recovery/sensitivity evidence, and public-scope
  release review pass.
- Do not advertise a broad Bayesian MGMFRM API before docs clearly separate
  implemented and planned functionality.
