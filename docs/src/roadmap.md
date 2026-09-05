# Roadmap and Scope

This page summarizes the package roadmap from a skeptical Bayesian measurement
reviewer's point of view. It is intentionally conservative: features move
forward only when their identification, diagnostics, validation, and reporting
contracts are clear.

The repository's internal Active Decision Roadmap governs new work; the section
below summarizes its order. Later progress ledgers and LD1b checklists are
historical snapshots, not current work orders or package-completion scores.

## Current Public Slice

The current package supports:

- long-format rating data with deterministic facet indexing via
  [`FacetData`](@ref);
- pre-fit design validation via [`validate_design`](@ref);
- minimal MFRM/RSM/PCM specification and design inspection via
  [`mfrm_spec`](@ref) and [`getdesign`](@ref);
- exact individual rater/item hard anchors in the stable MFRM/RSM/PCM
  likelihood and fit path, with fixed-coordinate manifest and diagnostic rows;
- specified-only GMFRM/MGMFRM configuration manifests and constraint tables via
  [`model_ladder`](@ref), [`constraint_table`](@ref), and
  [`model_manifest`](@ref);
- observation-level and row-by-category compiler inspection via
  [`design_row_table`](@ref), [`linear_predictor_table`](@ref), and
  [`linear_predictor_values`](@ref);
- small-example Bayesian fitting for the minimal identified design via
  [`fit`](@ref), [`MFRMPrior`](@ref), and [`MFRMFit`](@ref), including
  random-walk Metropolis, an AdvancedHMC/NUTS backend with a shared analytic/AD
  gradient adapter, a Turing/NUTS wrapper around the same `MFRMLogDensity`
  target, and a direct CmdStan/NUTS route using a package-owned stable model;
- guarded experimental generalized fitting via
  `BayesianMGMFRM.Experimental.fit(spec)`, returning [`GMFRMFit`](@ref) for the scalar
  rater-consistency GMFRM candidate, configured with the compatibility keyword
  `discrimination = :rater`, or [`MGMFRMFit`](@ref) for the fixed-Q
  confirmatory MGMFRM candidate with `dimensions >= 2`; the older
  `fit(spec; experimental = true)` spelling is compatibility-only;
- fit metadata, chain summaries, R-hat/ESS summaries, posterior summaries,
  stable-MFRM prior predictive checks, fit-family posterior predictive checks,
  calibration summaries, fair-average
  summaries, separation/reliability summaries, rater diagnostics, Wright-map
  rows, DFF screening rows, infit/outfit, WAIC, raw and PSIS-smoothed LOO with
  Pareto-k diagnostics, exact one-row LOO refits, supplied or package-executed
  K-fold refits, and same-observation or heldout comparisons;
- scalar Julia/BridgeStan validation fixtures and internal hand-computed
  source-aligned GMFRM/MGMFRM preview fixtures, including raw-coordinate
  source-constraint transforms, used by the test suite.

The current `backend = :julia` sampler is a random-walk Metropolis path for
small validation examples. `backend = :turing` is a NUTS interface limited to
the current minimal MFRM/RSM/PCM design. `backend = :cmdstan` supports those
stable models plus both guarded generalized configurations through the
experimental namespace and requires an external CmdStan installation; it is
not yet available through `cached_fit`. `backend = :advancedhmc` also backs
both guarded configurations.

## Distribution-First Adversarial Reset

This repository is first a package that strangers must be able to install,
understand, run, and remove. It is not primarily an evidence database, workflow
engine, or append-only laboratory notebook. A research control belongs in the
package repository only when it protects shipped behavior, a user-visible
claim, an external byte boundary, or a cache that could return a wrong result.

### Axis-Lock Checklist

Apply this checklist before accepting any roadmap item, pull request, or release
exception. Reset the **ACCEPT** boxes for each proposal. A proposal proceeds only
when every ACCEPT box can be checked. Any checked **STOP/MOVE** condition rejects
it from the package roadmap. Generalized-model expansion remains on hold until
every **P0 RELEASE** box is checked with current evidence.

**ACCEPT — all required for a new task**

- [ ] It names one shipped user behavior, correctness risk, privacy/security
  boundary, or predeclared scientific claim that it changes.
- [ ] This package repository is the smallest correct home; a companion research
  repository, external dataset, or versioned bundle would not be more honest.
- [ ] It addresses the highest unfinished tier: distributable core, then stable
  MFRM workflow, then independent scientific validation, then generalized scope.
- [ ] Success is observable through a focused behavior, schema, performance,
  portability, or privacy check rather than file count or document volume.
- [ ] Any new root export, mandatory dependency, fixture above 250 KiB, or public
  compatibility promise has a named user benefit and maintenance owner.
- [ ] The weakest sufficient identity mechanism is used: semantic identity by
  default, and one exact digest only where byte identity or cache correctness is
  the actual claim.

**P0 RELEASE — all required before generalized expansion**

- [x] A clean source archive, without `.git`, ignored artifacts, private paths,
  CmdStan, or R, can install, load, run the stable example, and build the manual.
- [ ] Ordinary CI reads no optional research results; instantiate, first/warm
  load, minimal fit, docs, and ordinary-test budgets are recorded and enforced.
- [ ] Stable MFRM supports intended category scale and actual individual
  rater/item hard-anchor fitting. Fixed-coordinate warnings, report integration,
  persistence coverage, the short anchor workflow, and category/rater
  practitioner-report integration are complete; final stable edge-case
  hardening still governs this composite box.
- [x] Root exports are frozen, every stable export is documented, and research
  or experimental entry points are visibly quarantined.
- [x] Release checks fail on behavior, schema, performance, portability, or
  privacy—not unrelated prose tokens or transitive source digests.
- [ ] The active work order is short; completed ledgers and large study outputs
  are archival or external and are not prerequisites for `Pkg.test()`.

Evidence recorded on 2026-08-15 for the checked item: `release_gate_check()`
passes 10 package-document presence rows and 28 structured manifest rows with
zero failures; a reader-facing prose-only edit remains accepted while a changed
structured GMFRM status fails. The public-language check passes all 19 declared
files without outlawing exported `audit`/`preflight` names. Full `Pkg.test()`
passes, and the 45-reference legacy code/document SHA traversal now runs only in
the opt-in research-evidence lane. This does not mark the remaining runtime-
budget, stable-workflow, API, or repository-separation boxes.

The ordinary-CI budget item remains open, but its first enforceable boundary is
in place. CI defaults research evidence to off; any non-empty optional research-
fixture path is rejected without the explicit opt-in. Ordinary shards now have
30--35 minute hard limits, the full minimum-Julia suite has a 75 minute limit,
and the remaining ordinary jobs have 20--35 minute limits. The manual research
lane alone enables the flag and has its own 300 minute ceiling. Warm-depot local
testset observations (8m19s core design, 5m48s fitting, and 2m02s/2m18s for the
two slowest local-dependence sets) are only diagnostics. The changed ordinary
core shard then passed its boundary test at 5/5 and its 2,422-test dominant
design set in 7m58s. The review rule uses
the median of three comparable successful CI runs and requires explanation or
remediation above 20% growth. Comparable CI whole-lane baselines and three-run
medians are still required before checking the runtime P0 box.

The clean-source item is complete on the current 2026-08-15 evidence. A
temporary 420-file, roughly 27.7-MB Git-visible candidate excluded ignored
artifacts and current-machine paths, disabled research evidence, exposed no
external command path, and ran without `.git`. Its first docs attempt exposed a
real Git-remote inference dependency; after making the Documenter remote and
`main` edit target explicit, repeated full reruns passed. A recorded privacy-
restricted run observed 0.21s assembly, 5.16s instantiate, 9.69s first load,
1.98s warm load, 13.16s minimal fit, and 14.76s docs. These phase budgets are
enforced in the 30-minute release-hygiene job. The separate ordinary-CI runtime
item remains open pending comparable CI lane baselines.

The root-API item is complete on the current 2026-08-15 evidence. All 186
exported bindings are assigned exactly once to a semantic contract: 137 stable,
5 compatibility-only, and 44 research-only. A test compares the named union
with Julia's actual export set, rejects overlap and unclassified growth, and
requires a docstring for every binding without hashing source files. The docs
pre-build check rejects a stable or compatibility binding missing from the API
reference while maintainer-only release controls remain unpublished. The
manual passes with compatibility audits and published research helpers visibly
labelled non-stable. Experimental workflow entry points remain fully qualified
under `BayesianMGMFRM.Experimental`; the two generalized fit types stay at root
only for serialized-cache type compatibility.

The intended-category-scale slice of the still-open stable-MFRM workflow item
is complete on the current 2026-08-16 evidence.
`FacetData(...; category_levels = ...)` preserves a consecutive integer scale
through validation, PCM threshold construction, likelihood and prediction,
LOO/K-fold training subsets, model and fit metadata, and fit-cache reloads. The
default observed-range inference remains compatible. Declared unobserved
endpoints receive a distinct actionable warning, and the focused scale
regression set passes 45/45 checks. Exact individual rater/item hard anchors
replace the default reference gauge and now propagate through fitting,
diagnostics, persistence, and stable report rows. Public, Markdown, JSON, and
table reports keep them out of posterior-summary rows and show aggregate
fixed-value, coordinate-dependent-prior, and conditional within-facet contrast
warnings; focused anchor declaration
and numerical/report checks pass 2,091/2,091. Pairwise rater contrasts distinguish fixed references, hard
anchors, and estimated coordinates: two-fixed-coordinate contrasts are exact
constants with no posterior uncertainty, interval probability, or quantile-
probability labels, while one-fixed-coordinate contrasts inherit uncertainty
only from the estimated side. These statuses survive public and JSON
projections. Stable reports now include category usage/threshold and pairwise
rater-contrast rows by default, preserve them across public, Markdown, JSON,
and table projections, and issue one aggregate category review warning without
automatic recoding. The focused practitioner regression set passes 258/258 and
covers zero-contrast single-rater semantics, an all-disconnected requested-
overlap graph kept distinct from full-model identification, invalid rater
controls, and simultaneous aggregate category and hard-anchor warnings.
Zero-row contrasts survive public JSON, table, and bundle round trips and can be
rendered explicitly in Markdown; declared-unobserved PCM endpoints remain in
usage rows alongside all item-specific step rows. Further stable edge-case
hardening remains open, so the P0 checkbox stays unchecked.

**STOP/MOVE — any one is sufficient**

- [ ] The deliverable only regenerates hashes, receipts, copied status prose, or
  another local evidence layer without changing a shipped behavior or claim.
- [ ] It adds a mandatory dependency, root export, large fixture, or compatibility
  surface for an optional or one-off research workflow.
- [ ] It optimizes raw repository bytes without a measured install, test, review,
  portability, or privacy benefit.
- [ ] It continues local simulation or ceremony after independent review,
  external data, or a promotion decision has become the real blocker.
- [ ] Its completion criterion is “more evidence” without a frozen estimand,
  acceptance rule, owner, and terminal allow/narrow/reject decision.

The 2026-08-15 snapshot tracks about 415 files and 27 MiB uncompressed. Tests
account for about 19 MiB, fixed fixtures for about 16 MiB, and 150 research
scripts for about 5 MiB. The compressed source archive is only about 3.1 MiB,
so raw download size is not the main defect. The risks are review cost,
ordinary-test latency, stale generated state, ambiguous authority, and package
changes blocked by unrelated research ledgers. The root module exposes 186
exported bindings (187 names when the module binding itself is counted), while
the principal source and test files remain unusually large.

The release must withstand these skeptical questions:

| Reader | Adversarial question | Required response |
| --- | --- | --- |
| New user | Can I identify and fit the supported model without reading a research roadmap? | One short supported workflow, one experimental boundary, and concise failures. |
| Release maintainer | Does a clean archive work without local artifacts, Git metadata, CmdStan, R, or private data? | Clean-environment package, docs, and example checks; optional tools are detected at call time. |
| Code maintainer | Does a local edit force unrelated fixture or digest regeneration? | Behavioral and schema checks first; byte coupling only at justified external boundaries. |
| Scientific reviewer | Are manifests and receipts substituting for independent recovery evidence? | One claim-to-evidence table separating execution, numerical agreement, scientific validation, and independent review. |
| Cross-platform user | Does the default install pay for an optional backend or research workflow? | Measured dependency and latency budgets, with materially costly optional integrations moved behind extensions or separate environments. |
| Data steward | Can outputs reveal identifiers or private paths? | Public outputs omit them by default; external bundles receive an explicit privacy review. |

Before another generalized mechanism or large simulation program:

1. restore a green clean-clone release path and replace brittle prose-token
   checks with structured support/status checks;
2. retain only compact ordinary fixtures that protect shipped behavior, moving
   large study results, batch controllers, and historical matrices to a
   companion repository or versioned research bundle when possible;
3. freeze package-root export growth in `0.1.x` and move research planning,
   resource measurement, and evidence scoring behind a research boundary;
4. measure clean instantiate, first/warm load, minimal fit, docs, and ordinary
   tests, then consider extension boundaries for materially costly optional
   adapters such as Turing;
5. split compiler/validation, likelihood, sampling, diagnostics, reports,
   persistence, and research policy into independently testable units; and
6. finish stable-MFRM edge-case hardening before widening the public model
   family; intended category-scale handling, exact individual rater/item hard
   anchors, fixed-coordinate warnings/reports, persistence propagation, the
   short example, and category/rater practitioner-report integration are now in
   place.

Identity mechanisms have a limited budget. Semantic identities remain for
data/design and cache correctness. Exact digests remain for external inputs,
binary/raw outputs, signed handoffs, and optionally one immutable research
bundle. Scientific payloads use versioned schemas, estimands, seeds, controls,
and semantic projections. A reproduction boundary records one Git commit/tree,
package version, and protocol version rather than pinning every transitive
source file. Ordinary code or prose edits use focused behavior, schema, and
documentation checks and do not trigger hash-of-hash regeneration.

The gate exits when a clean archive installs and runs the stable workflow;
ordinary CI reads no optional research results and has runtime budgets with a
20% regression review trigger; fixtures above 250 KiB have a documented reason
they cannot be reduced or moved; root exports do not increase; every stable
export is documented; the active roadmap becomes a short decision document;
and release failures identify behavior rather than unrelated prose or digest
drift. Compressed archive size is monitored, but byte reduction without an
install, test, review, or privacy benefit is not roadmap progress.

Cancel or relocate work that only updates digests, receipts, or duplicated
prose; cannot name the behavior or claim it unlocks; adds a mandatory dependency
for an optional workflow; adds a root export for a one-off study; or accumulates
local evidence after independent review is the actual blocker. Missing
independent evidence leaves MGMFRM experimental indefinitely rather than
justifying more local ceremony.

## Active Decision Roadmap

The authoritative milestone status, owners, evidence limits, and completion
criteria live in the repository's
[internal roadmap](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/ROADMAP.md#active-decision-roadmap).
Its immediate order is M0: fix the validation baseline; M1: freeze the MFRM
anchor study; M2: execute independent known-truth evaluation; and M3: review
external agreement and the supported domain. Protocol drafting can proceed
alongside integration; fresh evaluation requires both to be complete.

Local integration checks and the 80-fit PCM anchor pilot have passed, but the
pilot has two data replications per cell, joint rater/item interventions,
truth-based initialization, and a shared generation kernel. The internal plan
therefore calls for independent RSM/PCM generation, separate facet interventions,
ordinary initialization, prior refits, precision-based replication counts, and
all-attempt failure accounting. This does not change supported API scope or
establish a general anchor recommendation. Existing generalized stages below
remain downstream, with their own evidence requirements.

### Downstream Fixed-Q Program

The pilot boundary is strict: a pilot answers only whether the planned program
can execute and what resources it is likely to require. Pilot R-hat, ESS,
recovery, coverage, or backend differences are descriptive planning data. They
must not become acceptance thresholds, model rankings, or evidence for
promotion.

After the M0-M3 scope decision, the downstream generalized program is:

| Stage | Priority and scope | Exit condition |
| --- | --- | --- |
| 0. Freeze the MGMFRM family skeleton | **P0, completed.** `model_family_contract()` records between-item, within-item, and mixed fixed-Q structures; source terminology versus algebraic dimension aggregation; PCM/GPCM kernels; step-sharing ownership; latent-correlation policy; facet roles; and executable/specified-only/blocked status. No new sampler was added. | Met: the public machine-readable skeleton, exact spec/design resolver, prose, and boundary tests distinguish implemented, guarded, specified-only, and blocked branches. |
| A. Freeze the validation protocol | **P0, in progress.** `mgmfrm_validation_protocol()` now records identified-block and heldout-response estimands; the source-literal `1.7` versus reference `1.702` scale policy; primary between-item Q, boundary within/mixed Q, and Q-misspecification scope; connected sparse design; actual prior refits; a paired CmdStan subset; layered criteria; and five-category stress. The bounded wiring smoke preserves typed outcomes without scientific scoring. `mgmfrm_validation_execution_design_contract()` freezes five-fold conditional observation holdout, non-overwriting remediation, and 24 portable sensitivity role-cells. The explicit-execution memory-guarded MCMC-free gradient and short-NUTS probes, four-cell sequential scaling plan, single-cell isolated worker, and threshold-free receipt review provide bounded local resource surfaces without authorizing convergence or full-runtime claims. Worker peak RSS includes startup and compilation and is not sampler-only memory. `mgmfrm_validation_analysis_contract()` separates 13 specified components from four unresolved decisions. Final primary cells, replications, resource caps, the executor, and independent threshold review remain blockers. | A reviewable, portable protocol and commands exist; the analysis runner retains every attempt and stress stratum, and independently reviewed scientific thresholds are frozen before any fresh evaluation starts. |
| B. Run fresh-seed known-truth validation | **P0.** Run repeated dense and connected-sparse recovery, prior sensitivity, prediction/calibration, and nested unidimensional MFRM comparisons. Use one predeclared primary backend for the full grid and both backends on a stratified conformance subset. | Predeclared parameter-block and focal-decision criteria pass, or the supported domain is narrowed and the surface remains experimental. |
| C. Add external and independent evidence | **P0 before stable promotion.** Reproduce a matching public benchmark, analyze one provenance- and licence-cleared external dataset when available, and obtain review of equations, Q, priors, transforms, diagnostics, and claims from someone other than the implementer. | The exact overlapping targets reproduce in a separate environment and the reviewer records claim-level allow/block decisions. |
| D. Harden the generalized user workflow | **P1, only where it enables B/C or a reviewed user need.** Reuse the stable workflow closed under M0; address bounded chains, optional-backend persistence, sampler profiles, and report failures only for the supported generalized branch. A new stable-MFRM regression returns to M0's finite gap list. | A non-maintainer can fit, diagnose, save, reload, and report the declared generalized model with clear unsupported boundaries. Its convenience does not close the scientific gates. |
| E. Make the promotion decision | **Release gate.** Review the narrow candidate only; choose stable, remain experimental, or narrow further. | Stable wording is allowed only for the domain that passed A-D. Missing broader mechanisms are stated as non-goals rather than hidden caveats. |

Stage 0 records source classification separately from algebra. Uto (2021)
calls the multidimensional GPCM basis and proposed MGMFRM non-compensatory, but
the conditional predictor uses the additive weighted sum
`sum_l alpha[i,l] * theta[p,l]`. The package must preserve both facts and avoid
inferring an operational compensation claim from the summation sign alone.

Fixed Q defines item dimensionality: one active dimension per item is between-
item, multiple active dimensions are within-item, and a Q with both is mixed.
The current kernel can execute validated fixed-mask branches, but not Uto's
unrestricted within-item-capable `alpha[i,l]` surface. An all-active Q is not
automatically an identified replacement for that source model. The current
branch also lacks a non-additive conjunctive/product/minimum aggregator.
Conditional response probabilities contain no ability integral; HMC samples
explicit person abilities, and posterior marginalization over draws is a
separate operation.

The generalized kernel is GPCM-form. Scalar GMFRM uses rater-specific step
vectors shared across items and persons; MGMFRM uses item-specific vectors
shared across raters and dimensions. Stable MFRM separately supports globally
shared rating-scale steps or item-specific PCM steps. Adding a facet does not
automatically add a step vector. Arbitrary facet-specific or crossed step blocks
remain unsupported.

Stage A first locks the source-reproduction multiplier to the published `1.7`
and records `1.702` only as the normal-ogive minimax reference; changing the
likelihood or comparing parameter scales requires an explicit conversion or
sensitivity contract. It then freezes the structural-versus-prior
identification statement, focal direct-scale estimands, parameter-block
bias/RMSE/coverage and decision metrics, connected dense/sparse and
misspecification cells, actual weak/reference/strong prior refits, and complete
attempted-fit failure accounting. Failed fits are not removed from the
scientific denominator. Acceptance rules must be fixed before fresh evaluation
results are inspected.

The primary inference units are identified parameter blocks and heldout
responses, not unconstrained coordinates. Raw discriminations are compared
only when Q, constraints, and the `1.7` likelihood scale agree; otherwise the
harmonized targets are the linear predictor, category probabilities, expected
score, and heldout log score. Person ability remains secondary, and boundary-
only persons are reported separately rather than forced through an individual
hard-recovery gate. The primary Q has one active dimension per item. Fixed
cross-loading and mixed Q are boundary evidence; omitted true and added false
Q entries are misspecification cells, not exploratory-Q estimation.
The two-dimensional stress generator permits odd item totals and assigns pure
items with a dimension-count difference of one. Equal item counts per
dimension are therefore not misrepresented as an identification condition,
and the source-anchored 5- and 15-item candidates remain executable.

Sparse validation uses a connected systematic link with two raters per person,
plus a disconnected negative control that must fail before sampling. It does
not assume arbitrary missingness is ignorable. A separate five-category stress
axis covers an unused interior category, an all-maximum person, an all-minimum
rater, and their combination. These patterns trigger separate reporting and a
predeclared, non-Cartesian prior-sensitivity subset spanning every pattern and
prior regime; their presence alone is not failure. A globally single-category
outcome is structurally rejected, and
pooled means cannot hide a failed stress stratum.

The first executable slice of this axis is intentionally sampler-free. It
generates four separate patterns for a fully crossed design and five for a
connected sparse design, retaining raw/direct truth, pre-intervention
probabilities, changed rows, validation, Q checks, and typed terminal status.
The combined all-maximum-person/all-minimum-rater case is sparse-only because
the two exact constraints contradict each other in shared fully crossed cells.
Passing this preflight is generation and structural evidence only. A separate
one-attempt-default wiring smoke now preserves outcomes through fitting and
output-integrity diagnostics, but its four-warmup/four-draw chain cannot assess
convergence or recovery. The portable execution-design contract now freezes a
five-fold existing-level observation target, non-overwriting remediation, and
24 sensitivity role-cells; the analysis contract records 13 fixed components
and four unresolved decisions. The attempt-complete analysis executor remains
open.

`mgmfrm_validation_primary_grid_candidates()` now makes the implied 16-cell
source-anchored envelope explicit without freezing it: dense/sparse design is
crossed with 50/100 persons, 5/15 items, and 5/15 raters. Expected observations
range from 500 to 22,500. Nine candidates exceed the current 2,000-observation
short-NUTS bound. A four-category known-truth generator and MCMC-free
all-candidate structural preflight are available. Resource coverage, final cell
selection, and evaluation replications remain unresolved; generation preflight
is not validation evidence.

The candidate contract now also records a provisional three-stage review. It
starts with the two minimum-support dense/sparse cells for operability, adds a
matched larger-support dense/sparse pair, and only then adds one sparse cell
that changes the rater pool and per-rater information while holding observations
fixed. Those three declared contrasts require five unique endpoints, but this
is not a globally minimal or factorial validation grid: person and item sample
size are jointly changed, and rater count is not separable from per-rater
information. No stage is frozen, Stage 1 cannot establish recovery, and later
cells require explicit resource review rather than automatic short-NUTS
progression. Both Stage 1 cells are inside the current short-NUTS workload
bound; all three later additions are outside it.

`mgmfrm_validation_primary_resource_plan()` now selects four ordered
four-category representatives (500, 1,250, 3,750, and 7,500 observations) for
the existing MCMC-free gradient probe. Automatic progression is prohibited.
The bounded short-NUTS adapter now accepts one actual four-category primary row
and retains primary-specific result schemas without duplicating the fit and
diagnostic loop. The first two representative cells meet the current workload
bound. Memory-guarded execution and primary-specific resource review still
precede any resource-envelope or final-grid decision.

The threshold-free receipt review now exposes a Stage 1 operability section
linking candidate cells 01/09 to their two resource-cell records. A complete
submitted pair may be considered manually for an operability-only milestone;
it never closes the milestone automatically and never implies convergence,
recovery, or portable performance. The previously observed run values remain
outside the package contract because no durable machine-readable Stage 1
receipts are currently ingested. Recovering those existing receipts is
therefore the next step; rerunning the cells is not automatically authorized.

External validation uses simulation and observed data for different purposes.
Known-truth simulation evaluates recovery, coverage, and false-decision rates.
A public synthetic or literature benchmark evaluates reproducible overlap. A
licence-cleared existing-study or independently curated observed dataset
evaluates workflow portability and substantive plausibility, but cannot
establish bias because its truth is unknown. Wind/Jones-style linking conditions
and McEwen-style sparse coverage inform the design grid; they do not replace a
package-specific recovery study.

Anchor proportions are not part of the current MGMFRM promotion grid because
the guarded generalized fit has no declared hard- or soft-anchor estimation
contract. First implement and validate the estimand, constraint, uncertainty,
and failure behavior. Then freeze a separate dose study crossing linking
proportion with absolute common-target count, per-rater/per-dimension coverage,
range, and rating burden. The existing 0%, 2%, 5%, 10%, and 20% cells remain
experimental doses, not a recommended universal percentage.

CmdStan is a required reference backend for stable promotion, not the sole or
automatic default. Julia owns domain objects, validation, parameter semantics,
reporting, and a native execution path. Stan supplies an independently
implemented target and familiar sampler diagnostics. A stratified conformance
subset checks equation, transform, initialization, and draw-import drift;
feature parity and speed superiority are not goals. The package must continue
to load and provide supported Julia-only workflows when CmdStan is absent.

AdvancedHMC runs the primary grid. CmdStan covers the smallest predeclared
paired subset that spans dense/sparse designs, ordinary/category-gap/boundary
patterns, and reference/source-aligned priors. The comparison targets density,
gradient, identified summaries, probabilities, diagnostics, and terminal
status—not speed. Agreement is necessary implementation evidence, not a
scientific validation result.

Verification follows a resource-aware ladder:

| Tier | Trigger | Typical checks |
| --- | --- | --- |
| T0: static | Every change | Formatting/diff checks, schema and documentation consistency, no repository-specific paths. |
| T1: focused | Every implementation slice | Unit and contract tests for the touched path. |
| T2: family integration | Before merging a model slice | Small deterministic fixtures for the affected family. |
| T3: real sampler smoke | Opt-in or sampler/backend changes | Short Julia and/or CmdStan execution proving operability only. |
| T4: scientific evaluation | After M0/M1 for the anchor study, or the downstream prerequisites and Stage A for MGMFRM | Fresh-seed repeated simulations and the predeclared cross-backend subset. |
| T5: release regression | Release/integration boundary | Full suite, docs build, cross-platform checks, and separate-environment reproduction. |

Routine changes do not rerun T4/T5. Normal Git history, portable versioned
configuration, explicit seeds and controls, schemas, and executable behavior
are the working record. Byte-exact source snapshots and transitive SHA chains
remain only where external-input provenance or cache correctness genuinely
requires them; they are not scientific promotion gates.

After the narrow promotion decision, independent research tracks address free
latent correlation with an LKJ-Cholesky gauge, fitted anchors and linking dose,
exploratory loading/rotation policy, fitted DFF/testlet/halo/rater-by-task
mechanisms, and multiple discrimination components within a facet with an
explicit threshold-sharing contract. Broader brms-like ergonomics follows the
statistical contracts rather than defining them.

Do not turn Stage 0 into a generic sampler framework, add free correlation to
the public fit, infer an anchor percentage from current sparse fixtures, make
CmdStan the default, tune decision rules after seeing fresh results, compare
backend speed from warmed pilots, or expand source-hash machinery. Failures
should first narrow the claim or supported design domain, not automatically
increase model complexity.

## Why the Generalized Fit Is Guarded

The guard is an evidence and contract boundary, not a synonym for a missing
feature list. The current confirmatory MGMFRM candidate deliberately fixes Q,
dimension labels, latent correlation to identity, and ability distributions to
standard normal by dimension. Positive Q-masked loadings fix signs; rater
severity sums to zero; rater consistency has geometric mean one; item steps and
the source `1.7` scale complete the declared gauge.

Exploratory loadings and a public free-correlation model remain unsupported.
DFF is screening-only, while testlet, halo, and rater-by-task mechanisms are
diagnosed or simulated but not fitted. Their absence blocks claims about those
mechanisms; it does not by itself prevent promotion of a sufficiently
validated no-DFF, locally independent, fixed-Q model. The actual promotion
blockers are repeated sparse-design and prediction/decision evidence, an
exchangeable direct-scale prior decision, external/independent validation of
matching targets, stable failure/report/cache behavior, and maintainable code
boundaries.

## Julia, R, and Stan Roles

Julia is used so the design compiler, typed parameter layouts, AD log density,
HMC backends, simulation, diagnostics, and evidence artifacts share one
language and one model contract. This is not a claim that R is unable to fit
these models. R's Facets/TAM/mirt/sirt/immer ecosystem remains the breadth,
migration, and overlap-comparison baseline, while Julia's compilation latency
and smaller psychometric ecosystem remain real costs.

CmdStan fitting is now required before stable promotion, while remaining an
optional external runtime rather than a hard dependency for loading the
package. Julia stays the canonical model/data contract and Julia-only features
must work on machines without CmdStan, but the stable fitting claim must include
an explicit working `backend = :cmdstan` route. This is a required independent
execution path, not a declaration that Stan is the sole or default backend.

`cmdstan_backend_check()` checks a local CmdStan root, `stanc`, `make`, and C++
compiler without compiling or sampling. Stable MFRM/RSM/PCM designs now have a
package-owned Stan model, data/initialization encoder, explicit chain seeds and
controls, direct CLI execution, standard sampler-column import, a common
`MFRMFit` result, typed failures, and per-draw Julia/Stan pointwise-likelihood
agreement checks. Both guarded generalized configurations now have the same
vertical route into `GMFRMFit`/`MGMFRMFit`, including raw-to-direct Julia
transformation and per-draw pointwise checks. This does not yet satisfy the
release gate: cache integration, bounded parallel chains, recovery,
sparse-design, independent review, and analysis-scale comparisons remain.
BridgeStan remains
an equation/gradient oracle rather than evidence that every sampling adapter is
complete. No Julia-versus-R/Stan speed or accuracy superiority claim is
supported without predeclared evidence.

## Identification, Priors, and Engineering Debt

Stable fixed-Q promotion requires machine-readable and prose agreement on Q
rank/connectivity, minimum pure-item and observation support per dimension,
positive loading signs, the prior-anchored standard-normal ability scale,
identity correlation, rater and step constraints, and all direct transforms.
The roadmap separates structural/likelihood identification from identification
supplied by the population prior. A future free-correlation model requires an
LKJ-Cholesky contract and a joint loading/correlation gauge decision.

The current guarded validator intentionally accepts a three-dimensional cyclic
cross-loading Q (`110`, `011`, `101`) with no pure item as warning-only. Stable
exposure must either prove and delimit that class or reject it before fitting.
The isolated 2D free-correlation candidate is already narrower: simple Q, at
least two pure items per dimension, and person-level coverage of both
dimensions.

`q_matrix_validation` now makes this boundary executable. A maximum-matching
structural-rank check rejects Q zero patterns that cannot generically support
all loading dimensions, while person-specific ranks show when an ability
direction is supported only by the population prior. The conservative
structure flag additionally requires pure-item support and connected
dimension-specific facet graphs; it remains only one input to promotion.

The current MFRM/MGMFRM baseline artifact remains smoke evidence: one
4-person, 2-item, 3-rater, 24-observation dataset, 2 chains with 32 warmup and
32 retained draws, permissive R-hat/ESS thresholds, and high-variance WAIC.
MGMFRM ranks third while rating-scale MFRM ranks first. `passed` records finite
comparison mechanics, not multidimensional superiority or model-selection
validity.

The generalized defaults currently use independent raw-coordinate normals:
scale `1.0` for person, rater, item, and step coordinates and `0.5` for log
loading/discrimination and log-consistency coordinates. Promotion requires
prior-predictive implications, exchangeable alternatives to last-coordinate
sum/product transforms, refit-based weak/reference/strong scale sensitivity,
and focal-decision stability. Every MGMFRM simulation also includes public
unidimensional MFRM on the same ratings and reports blockwise recovery,
classification/ranking, heldout prediction, diagnostics, and cost.

The implementation audit confirms that the final coordinate under the current
sum-to-zero transform has variance `(k - 1)s^2`, not `s^2`, when the preceding
raw coordinates are independent with variance `s^2`; the same asymmetry occurs
on the log scale for the geometric-mean-one transform. It also confirms that
the existing GMFRM sensitivity grid is a 24-draw importance-reweighting screen,
not a refit study. Its minimum weight ESS rate is about 5.94% and its maximum
single weight about 0.835. Its local `passed` label must not satisfy the
stable-public prior-robustness gate.

The guarded fit now accepts the typed, cache-aware
`BayesianMGMFRM.Experimental.GeneralizedPrior` for raw-coordinate scale
variants, so sensitivity must use actual refits rather than the earlier
importance-reweighting screen. Direct-scale generalized priors remain blocked,
while prior-predictive execution is now available before fitting.

The August 2026 review records 21,364 lines in `src/bayesian_fit.jl`, 9,850 in
`src/facet_workflow.jl`, and 33,064 in `test/runtests.jl`. These counts establish
a reviewability risk. A direct comparison also finds more than 300 shared lines
across the roughly 358-line GMFRM and 368-line MGMFRM sampler-diagnostic
functions. Their common sampler-control validation, RNG setup, AdvancedHMC
execution, chain rows, and raw/direct diagnostic aggregation now live in typed
shared helpers. Four small dispatch methods retain the family-specific direct
transforms and constraint checks; the approximately 161-line GMFRM and 183-line
MGMFRM wrappers still own their schemas, statuses, and MGMFRM-specific
initialization/fixed-Q invariance rows. Fixed-seed pre/post checks preserve the
numerical outputs. The broader gate remains: split compiler, density/transform,
sampler, diagnostic, reporting, cache, and evidence code; consolidate repeated
traversal/hash/artifact helpers; and use small dispatch or capability rows where
they clarify family-specific branches.
Core numerical and authorization code must not use naked `catch`. Optional
metadata failures and captured report errors must expose structured status and
reason rows.

The current narrow-error-handling slice catches table lookup failures only
around `getindex`; iteration or conversion failures from a returned column
propagate unchanged. Generalized experimental-fit capability returns an
explicit typed support issue rather than catching arbitrary `ArgumentError`s,
and specified-only MFRM domain layout selection uses a direct family/status
branch. Missing authorization remains visible protocol state, while supplied
malformed or non-authorizing evidence throws.

No current false-positive report artifact was found. `fit_report` now records
separate `report_status` and structured `report_health`; public reports and
dossiers preserve or aggregate that health, and `require_complete = true` is
available on report, export, load, and dossier paths. Promotion and release
callers must continue to opt into the explicit fail-closed policy.

Hashes remain available as provenance metadata for external inputs and handoff
bundles, but ordinary code or documentation drift is not a byte-exact release
gate. Routine verification prioritizes schema validation, scientific fields,
and executable tests over deep transitive source-file hash chains.

## Analysis-Facing Workflow Program

The numerical workflow is feature-rich but not yet one brms-like user
contract. Stable MFRM defaults to one chain, guarded direct fitting defaults to
two short chains, and guarded cached fitting currently inherits a different
one-chain root-cache default. Posterior summaries, convergence diagnostics,
reports, plotting rows, and serialized caches also remain separate operations.

The next ordered program is:

1. Add one typed sampler-profile resolver shared by `fit`,
   `BayesianMGMFRM.Experimental.fit`, `fit_cache_key`, and `cached_fit`. The
   candidate `:analysis` profile uses an explicit supported NUTS backend with 4
   chains, 1,000 warmup iterations and 1,000 retained draws per chain; CmdStan
   support is required before stable promotion, but is not silently made the
   default. `:quick` keeps the current 2-chain 100/100 computational budget.
   Tests and research fixtures request their short controls explicitly.
2. Derive and record deterministic chain-level seeds from one fit seed, add
   resource-bounded optional parallel chains, map `target_accept` explicitly to
   Stan/brms `adapt_delta`, and reject backend-inapplicable controls. Keep
   sampler thinning at one; a future storage stride is not a convergence fix.
3. Add `summary(fit)` and concise fit-time warnings that combine direct-scale
   estimates, interval summaries, R-hat, bulk/tail ESS, divergences,
   tree-depth, and E-BFMI coverage. `fit_report_health` continues to describe
   report-construction completeness rather than convergence.
4. Add simple `save_fit`/`load_fit` wrappers for ordinary RDS-like local use,
   while retaining keyed caches for recomputation and portable JSON/table
   reports for interchange.
5. Stabilize trace, density, rank, autocorrelation, pairs/divergence, and
   energy plotting rows before optional Makie or Plots extensions. Extend
   direct-scale generalized facet and threshold maps without coupling the core
   package to one plotting backend.

`posterior_summary` already returns legacy 95% central interval columns and
66%, 90%, and 95% nested central intervals. The primary table interval remains
95% for compatibility; 66% is an optional inner plot band and 90% is an
explicitly selectable primary interval. Add
`interval_method = :equal_tailed | :hdi`, retaining equal-tailed intervals as
the default because they are equivariant under a monotone re-expression of the
same scalar estimand, while an HDI is not transformation invariant. HDI rows
for raw coordinates or derived direct-scale parameters must name the reported
scale and finite-draw algorithm and warn about multimodality. ROPEs remain
estimand-specific and user-declared.

The stable default prior is zero-centered independent normal on identified
coordinates, with standard deviation 1.5 for persons and 1.0 for rater, item,
and step blocks. Guarded generalized defaults use raw-coordinate standard
deviations 1.0 for person/rater/item/step and 0.5 for log
discrimination/loading and log consistency. These are computational defaults,
not universally validated priors; the current constrained final coordinates
are not exchangeable with the free coordinates.

Stable MFRM already implements `prior_predict` and `prior_predictive_check` for
category use, facet ranges, grouped DFF cells, and observed sparse blocks.
The typed raw-coordinate `BayesianMGMFRM.Experimental.GeneralizedPrior` now
enables cache-aware weak/reference/strong refits and generalized
prior-predictive replication with raw/direct draw records. Promotion still
requires replicated stress tests and fit-report integration. Importance or
power reweighting remains screening evidence that requires ESS/Pareto
diagnostics and refit follow-up.

Bias reporting separates known-truth repeated-simulation bias, bias caused by
model/design misspecification, DFF/fairness screening, and prior-driven
displacement. Existing recovery rows compute bias, absolute bias, coverage,
and interval width when truth is known. Promotion additionally requires Monte
Carlo uncertainty, failed/unattempted-fit denominators, empirical-versus-
posterior uncertainty, and rank/classification stability. Unknown-truth real
data support sensitivity and predictive-discrepancy language, not an estimator-
bias claim.

Bayes factors remain outside the default workflow. They are marginal-
likelihood ratios that require priors, not summaries derivable from posterior
draws alone. Any future research-only implementation must use preregistered
nested hypotheses, compatible nuisance priors, a declared bridge/marginal-
likelihood or valid Savage--Dickey route, Monte Carlo error, prior sensitivity,
and null/alternative calibration. Posterior direction, ROPE probability, and
interval exclusion are not Bayes factors; posterior contrasts/ROPEs remain the
practical-decision path and PSIS-LOO/K-fold remain the predictive-comparison
path.

The exit criterion is a coherent fit--diagnose--summarize--save--visualize
workflow with identical resolved sampler controls at every entry point and
explicit interval, prior, bias, and evidence semantics.

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

## v0.1.x MGMFRM Release Sequence

The source-grounded staged plan is maintained in
[MGMFRM Research Roadmap](mgmfrm-research-roadmap.md). The sequence records
`v0.1.1` as completed and continues with:

- `v0.1.1`: completed fixed-Q confirmatory MGMFRM refinement by strengthening
  execution, diagnostics, reporting, and validation for the existing guarded
  path.
- current `v0.1.2` integration checkpoint: retain the fixed-Q confirmatory
  boundary while completing core identity/cache integrity, minimal-MFRM hard-
  anchor, report, and repeated sparse/nonrandom gates, and auditing the already
  implemented multidimensional compiler across 2D/3D, sparse and misspecified
  Q, recovery, performance, and report-shape conditions. LD1b follows its
  independent nine-gate checklist without broadening this release boundary.
- `v0.1.3`: decide whether free latent correlations are ready for guarded
  exposure.
- `v0.1.4`: design exploratory loading and rotation policy before broad
  exposure.
- `v0.2.0`: establish an intentional stable API boundary only for options that
  passed the vertical-slice gates; it does not automatically claim generic
  MGMFRM completion.

Known-truth external comparisons should occur before a generalized option is
promoted to stable-public whenever an overlapping target exists. Real-data
validation remains subsequent evidence and cannot substitute for failed
source, recovery, identification, or external-overlap gates.

## Parallel Rater-Process and Design Research

A separate research track now records the path beyond a static MGMFRM. Its
first target is not a dynamic fit API. It is a known-truth robustness test of
the existing public MFRM and guarded GMFRM/MGMFRM APIs under rating topology,
ability-dependent assignment, common-linking-response amount and range,
additive versus fixed-total-target-displacement rating budgets, and
latent/outcome dispersion. The fixed-total condition separately reports
planned, observed, and dropped person--item targets. A
separate misspecification track injects a true order effect before fitting the
same static API; a pure row permutation remains only an invariance check. The
generic `simulation_grid.anchor_size`
field is planning metadata and the existing small connected sparse fixtures are
computational smoke evidence; neither substitutes for this paired-replication
study.
Both static tracks set testlet and rater-by-response halo variation to zero, so
passing them does not establish local independence. The separate cluster gate
below reuses their design skeletons with nonzero competing mechanisms.

The versioned `existing_api_design_robustness_plan.json` executes seven
deterministic contract checks. Row-order and categorical-`occasion` invariance,
the rank/linking rejection of an ability-nested no-link design, exact 5% and
10% materialized all-rater common-target counts, assignment-warning retention, and the
separation of parameter anchors from linking responses all pass. Parameter
recovery has not yet been run, so the artifact explicitly blocks a design-
robustness claim. The next grid compares 0%, 2%, 5%, 10%, and 20% linking
targets; these are experimental doses, not a universal recommended anchor
percentage. It reports multiply-scored, common-set, controlled-benchmark, and
rating-event-burden quantities separately; a double-rated baseline is 100%
multiply scored even when it has no special common set.

The Zotero-traced design literature makes the next refinement more specific.
Wind and Jones (2018) found rater estimates more sensitive than examinee/task
estimates as the link set shrank; McEwen (2018) identified rater coverage as the
largest incomplete-design influence and greater rater-order variability in
sparser conditions; Wind, Jones, and Grajeda (2023) compare MFRM and
generalizability theory under sparse designs. The grid therefore crosses link
percentage with absolute and per-rater/per-dimension coverage, represented
score range, assignment/order, and controlled model fit. Outcomes are scored
separately for person, item/task, and rater blocks and include a G-theory/
D-study design comparison.

The corresponding MCMC-free stress-grid artifact now passes for 24
model-design cells and 21 paired datasets. It covers all three current fit
families, additive and fixed-total-target-displacement budgets, achieved
ability/order and assignment/severity diagnostics, outcome dispersion, and six
pure row-permutation contracts. Three additional C2P checks hold the event set,
truth, response uniforms, and scores fixed while moving the 5% common set from
early to distributed positions. Replication seeds resample assignment and
order skeletons, with each paired A/B comparison sharing the same realization;
underresolved smoke designs are kept planned-only. Seeded full-range selection
now guarantees both ability- and item-range ratios of at least 0.75 whenever
the requested common set contains at least two targets. Every requested pilot
or calibration skeleton is checked design-only before score generation, and
the same all-replication check blocks fitting on any failed row. The
50-replication calibration profile passes all 1,050 candidate-family skeleton
rows. This is a reproducible
simulation/likelihood dry run, not repeated recovery evidence. The complete
repeated parameter-recovery and interval-coverage scorer is now implemented
and MCMC-free tested. It aggregates bias, MAE, RMSE, empirical coverage,
posterior-SD calibration, block completeness, and sampler-gate outcomes while
preserving failed and unattempted fits. Pilot and calibration preflights are
regenerated from canonical options before their content-addressed records are
accepted; the reviewed pilot snapshot, statistical policy, and thresholds are
one bound decision record. A passing q95/q99 result is labelled
well-specified-static distributional contract success rather than recovery of
every cell or parameter. External chronology attestation remains a separate
unmet evidence requirement. No repeated MCMC has yet been executed. The core
threshold-free predictive-recovery and decision-stability scorers now exist.
The bounded stress runner intentionally stops at output integrity. Held-out,
retry, and exact sensitivity-cell choices are now frozen without repository or
hash identity, while the final primary grid, replications, resource caps, and
scientific thresholds remain unresolved, so the full gate stays closed. The
initial MCMC-free gradient and bounded short-NUTS resource-probe surfaces are
implemented, together with a four-cell sequential scaling plan and a dedicated
single-cell Julia worker. Both direct probes remain explicit and are blocked
before generation when their free-memory gates are not met; the isolated
short-NUTS route checks both parent and child processes. Reused-process maxRSS
remains process-lifetime metadata; dedicated-worker maxRSS is
worker-attributable but includes startup and compilation. A threshold-free
review surface preserves both preflights and incomplete cells without advancing
automatically. Execution in a suitable environment and sequential receipt
review precede grid/resource freezing and independent threshold review. The
attempt-complete
executor and evaluation with untouched seeds follow.

The next parallel gate addresses local independence and clustered ratings. The
current likelihood is conditionally row-independent; observation residuals,
infit/outfit, grouped PPC, and rater-overlap counts do not by themselves
diagnose pairwise or response-cluster dependence. The initial metadata and
estimand scaffold is complete: `FacetData` records distinct `testlet_id`, `response_id`, and
categorical `occasion` metadata; `testlet_design_audit` checks target-specific
structural support; `predictive_standardized_residuals` returns draw-specific
Pearson residuals; and `local_dependence_contract` separates single-rating
item, within-rater item, and rater-pair targets while fixing matching,
draw-specific support, duplicate, weighting, FDR/FWER, and
conditional/marginal PPC rules. LD0b is also complete:
`local_dependence_summary` returns report-only Q3/adjusted-Q3-style item-pair
and same-response/same-criterion rater-pair summaries, paired predictive tail
fractions, family-by-testlet support graphs, within-family BH values, and one
all-family maximum-statistic reference. It uses distinct posterior draws,
keeps criterion-split responses out of the single-rater family, and exposes
single-response concentration separately from response-criterion counts.
Applicability is evaluated per testlet, and materialized audit rows,
shared-unit work, positive pair-by-draw work, and predictive cells are bounded
before large allocations.
These surfaces provide no calibrated decision label and no fitted cluster
effect. LD1 is now split into two evidence stages. **LD1a is complete:**
`local_dependence_simulation_grid` freezes 22 matched scenarios and
`simulate_local_dependence` uses an adjacent-category ordinal kernel that is
independent of the fitted probability and likelihood implementation. The
generated bundles record component seeds, semantic event-keyed uniforms,
complete
truth, intended and realized category support, exact sequence positions,
design audits, and resource preflights. The scenarios cover null and exact-
zero controls, study-local near-zero through large person-by-testlet effects,
support boundaries, sparse and rejected designs, halo, rater-by-task severity,
omitted multidimensionality, randomized drift, ability-confounded no-drift
order, ability-informed rater assignment, and a testlet-plus-sequence mixture.

**LD1b0 scorer/protocol preflight is complete.**
`local_dependence_calibration_contract`,
`local_dependence_calibration_row`, and
`local_dependence_calibration_summary` freeze the candidate pair,
family-maximum, and all-family-maximum scoring rules; retain planned, failed,
rejected, and unresolved replication denominators; apply Wilson intervals only
to replication-level binary rates; and label pooled pair rates as descriptive.
The MCMC-free `local_dependence_calibration_scorer_preflight.json` artifact
checks this contract over all 22 planned scenarios and the four declared
pre-fit rejection rows.

**LD1b1 pilot execution-protocol preflight is complete.**
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_preflight` freeze 30 replications for each
of the 22 scenarios (`30 × 22 = 660`). The planned rows comprise 540 eligible
fitting jobs and 120 planned structural rejections. The MCMC-free
`local_dependence_pilot_protocol_preflight.json` artifact checks separated
seeds, job identity, resource and failure policies, and preserves an original
failure when a retry is recorded. Its operational candidate bounds are study-
local. Evaluation sizes of 50 and 100 replications remain candidates; one must
be selected and frozen after the pilot and before evaluation.

Authorization pins `rank_normalized_rhat_bulk_tail_ess_v1` and its exact
dependency and operation-order record, primary fields, tail probability,
minimum chain and draw requirements, complete-chain E-BFMI coverage, and the
SHA-256 digest of `src/bayesian_fit.jl`. Authorization verifies the plan only;
it is not execution or calibration evidence.

An executor-readiness audit found that the earlier frozen
`ad_backend = :analytic` route cannot execute the order-0 MFRM target. Before
any pilot job was run, the contract was re-pinned to `:ForwardDiff` and the
capability gate was extended to check the MFRM backend, NUTS algorithm, and
target-compatible gradient route. A target-level wiring test reproduces
failure of the old route and a finite gradient from the revised route. This is
pre-execution evidence only. Context-bound semantic replay for all five
terminal statuses and the corresponding nonterminal failure semantics are now
complete in the local worktree. The canonical receipt- and precommit-capable
worker and its seven-source pin/dependent identity regeneration are also
complete locally. The bounded smoke on that source is now complete in the local
worktree; independent recovery/readiness review and all `660` primary outcomes
remain open. Completed-attempt seal support is implemented separately below.

An isolated noncanonical full-control run selected row 5,
`null_support_at_minimum`, as the smallest planned row with actual supported
pairs. It completed 4 chains and 2,000 retained draws with maximum
rank-normalized R-hat `1.00483`, minimum bulk/tail ESS `1439.8`/`1152.1`, no
divergences or depth hits, complete-chain minimum E-BFMI `0.9438`, and 24
supported `:report_only` pair rows. A matched row-4 comparison found
ForwardDiff about 3.50 times faster per warm gradient and 3.14 times faster in
a short NUTS run than an isolated ReverseDiff environment; ReverseDiff is not
an ordinary runtime dependency. These local observations select the future
canonical smoke target and gradient route but do not satisfy the sealed-smoke
gate or enter the numerator of the official 660-job denominator.

Gate 7 subsequently ran that exact canonical row 5 in a separate
verification-only namespace against the final source pin. The active evidence
binds parent plan
`197d91c65b89b669dcff6a0813b73f727acf57da90191fbda56c497a05544329`,
source pin
`781bb1aebfda5c16c662b60939a33bde97664cdce6f385ea7bddb25a72353793`,
and smoke plan
`4e32bbbaae5dafda795ccca1ddaf819cc1bd715568206134278a878f8c8b19a9`;
the receipt file SHA-256 is
`de7f1ffab4002e99b75c86d64efbe73deca695b97ac45b0cf177afa5398b58c3`.
Its frozen 4-chain NUTS configuration used 500 warmup and 500 retained
iterations per chain and published a strictly validated completed-attempt seal
and bounded-smoke receipt. The child completed in 387.724 seconds with peak RSS
of 3,131,703,296 bytes and peak archive size of 4,936,558 bytes, within the
fixed limits. The canonical pilot root was unchanged before and after the smoke,
so this evidence contributes zero to the scientific denominator and leaves the
official count at `0/660`. The sealed raw bundle remains local pending tracked
release-lineage verification.

The earlier successful plan `d4c6ed…` receipt was archived after a portability
audit found that tracked dry-run harness generation consumed local raw smoke
state. The build and generator now explicitly set
`consume_bounded_smoke_receipt = false`; the generated harness is byte-identical
before and after a local receipt, with SHA-256
`1afde641277e2219d4f0bbdb8a2665201876ff1f34a97b29a81a5adb67dd363d`.
Because that fix changed the pinned source, smoke plan `d2d716…` was rerun
instead of reusing the archived `d4c6ed…` receipt. A subsequent clean
`Pkg.test()` exposed `Sockets` missing from the test extras. Adding `Sockets` to
the test target with its compatibility bound changed the Project hash, so the
`d2d716…` receipt was also archived and plan `7c8e49…` was rerun. The
canonical executor source pin itself remained unchanged across this Project-
only transition. Clean testing then found that the known-truth fixture still
recorded the pre-change Project SHA. Regenerating the known-truth -> scorer ->
protocol provenance chain and the Julia 1.10.8 robustness fixture changed the
parent plan, so `7c8e49…` was archived and final plan `4e32bb…` was rerun. The
source pin remained unchanged.

The batch controller also now uses an explicit conjunctive operational-
readiness gate. Protocol authorization, a pinned canonical executor source, a
passing bounded canonical-smoke receipt, completed-attempt seal support, a
passing interrupted-attempt recovery-control readiness review, and the
canonical execution root must all be present. Execute mode checks the gate
before creating an attempt root or job directory. Completed-attempt seal
support now passes its MCMC-free synthetic boundary tests. Receipt-bearing
launched attempts also have a fail-closed recovery path that validates owner/
launch lineage plus either a validated exit receipt or a separately prepared
external process-identity review, then checks result state and the pre-review
inventory before create-new review and retirement publication. All five
terminal statuses now require an explicit semantic context and exact replay
through the canonical public calibration constructor and summary. Completed
outcomes additionally require exact pair/family/global diagnostic linkage. The
reserved nonterminal `sampler_diagnostics_unavailable` and
`final_calibration_serialization_failed` codes cannot pass the canonical runner
validation required for a completed seal or terminal admission. With this gate
complete in the local worktree, the canonical worker now implements execute-
path reservation, owner, launch, and exit receipt lineage plus reservation-
before-precommit and launched-attempt recovery. The protocol records an ordered
seven-source SHA-256 pin, and the controller compares every digest with the
repository files before deriving authorization, harness, all 660 command, and
checkpoint identities. This source-pin gate and bounded smoke are complete in
the local worktree. Independent recovery/readiness review is the only remaining
pre-pilot blocker, keeps operational readiness false, and leaves the count at
`0/660`.

All five existing terminal statuses now require a
`local_dependence_calibration_row.v1` source member, including generation, fit,
and diagnostic failures. The failure row keeps status-specific dependency
hashes and never fabricates unavailable simulation or diagnostic provenance; a
mixed-status test uses the public constructors and reconstructs all `5/5`
planned rows through `local_dependence_calibration_summary`. Generation-failure
rows are now rebuilt from the public frozen 660-row plan and compared with the
archived member by exact normalized JSON after public-summary validation;
thirteen independent planned-field mutations fail closed, and the validator
source is pinned in the execution identity. Every status now fails closed
without an explicit semantic context and must replay exactly through the
canonical public calibration constructor and summary. The protocol file
identity is revalidated, and the complete 660-row plan and public preflight are
reconstructed and compared exactly before replay. Completed rows also bind
and recompute exact pair-, family-, and global-diagnostic contents, including
the generated observed-score source. The unavailable-diagnostic and final-
serialization codes remain reserved nonterminal states and cannot pass the
canonical runner validation required for a completed seal or terminal
admission. Tracked release-lineage verification is still pending.

**LD1b1 MCMC-free batch execution-harness dry run is complete.**
`scripts/generate_local_dependence_pilot_batch_execution_harness.jl` records
the `bayesianmgmfrm.local_dependence_pilot_batch_execution_harness.v3` artifact
in `local_dependence_pilot_batch_execution_harness.json`,
and `scripts/run_local_dependence_calibration_pilot_batch.jl` implements status,
dry-run, aggregate-only, and receipt-verified `retire-interrupted` modes and
defines fail-closed execute-primary and execute-retry interfaces. After a fresh
archive scan, `--resume` verifies the derived
`bayesianmgmfrm.local_dependence_pilot_batch_checkpoint.v3` checkpoint. The dry
run covers all 660 planned rows, including 540 eligible fitting jobs and 120
planned pre-fit rejections.
The batch-controller and generator sources are identified. The protocol now
pins the ordered seven-source canonical executor set, and the controller
recomputes those file digests before deriving authorization, harness, all 660
command, and checkpoint identities. Gate 7 bounded canonical smoke passes in
the local worktree; the execution plan remains incomplete until independent
recovery/readiness review passes.
Terminal records require exact status-specific semantic
evidence, one hashed source artifact per evidence
role, and exact upstream evidence hashes. The frozen `pilot_contract` and
ordered 660 job rows must match their canonical SHA-256 values. Every
`pre_fit_rejected` result retains the exact `generated_data` ->
`structural_rejection_audit` -> `calibration_row` chain, and the calibration
member follows the existing public calibration-row contract. Simulation
members are checked down to their response data, table columns, probability
cells, truth and row-truth arrays, and data/score/design signatures. Fit members
must use the structured `local_dependence_pilot_fit_artifact_export.v1` JSON
wrapper containing retained draws, log posterior values, and sampler statistics.
Its package-native content hash is verified by the pinned canonical executor
before JSON projection; the batch runner separately recomputes the
canonical JSON payload hash and verifies the exact file SHA-256. The JSON
projection cannot soundly reconstruct the native typed hash. Resource counts
and fixed sampler controls are checked, while convergence, divergence, depth,
and complete-chain E-BFMI gates are validated individually. Fit,
sampler, local-dependence, and calibration evidence must agree on data, design,
fit-artifact, retained-draw, chain, and iteration provenance. The custom
`local_dependence_pilot_summary_bundle.v1` directly records the draw-selection
and posterior-predictive seeds; the runner compares both with its evidence
payload, the frozen job, and the calibration execution seeds. Draw selection
uses the frozen `sha256_seeded_rank_without_replacement_v1` algorithm, and the
runner recomputes its ordered draw indices from the frozen seed.
The posterior-predictive seed is source-bound, and its recorded lineage passes
the bounded smoke on the pinned canonical single-job executor. Independent
recovery/readiness review remains pending. A
`diagnostic_failed` record may identify `sampler_quality_gate` only when that
gate failed, or `local_dependence_summary` only after the sampler gate passed.
Symbolic links, hard links, and unmanifested files fail archive integrity. The
v3 scan/checkpoint records separate digests for verified primary results and
primary dispositions. Result rows bind result, evidence-manifest, seal, and
attempt-inventory identities; disposition rows bind either a completed seal or
an interrupted-retirement control artifact and its attempt inventory. The
controller refuses to overwrite primary attempts and keeps remediation as
additive records. On resume, it first rescans the complete attempt archive as
the source of truth, then verifies and compares the derived checkpoint, and skips only
verified terminal primary records. Invalid
remediation fails archive integrity without replacing the primary denominator.
Terminal admission now also requires a create-new completed-attempt seal after
semantic result validation. The seal binds plan, source, job, attempt, terminal
outcome, result, evidence-manifest, and inventory identities. A result without
its seal remains partial; post-seal mutation, file addition, missing or
mismatched outcome identity, and duplicate publication fail closed. Seal and
result validation remains a static verification boundary, not a transactional
filesystem snapshot.
The generated dry run does not scan an attempt archive, so integrity is not
assessed. It generates no response data, fits no model, and runs no MCMC;
pilot results, calibration or power estimates, diagnostic decisions, and
mechanism interpretations remain unavailable.

The canonical single-job executor is now materialized in the local worktree
against the frozen result schema. Each terminal status retains its required
hashed data, fit, sampler-diagnostic, local-dependence, calibration, or
structural-rejection records; source -> evidence -> result publication uses
CREATE_NEW semantics; controller-owned reservation, owner, launch, and exit
receipts are bound; and reservation-before-precommit recovery preserves seeds,
sampler controls, and primary denominators. Its final local source set is
represented by the ordered seven-source protocol pin that the controller
checks before regenerating authorization, harness, all 660 command, and
checkpoint identities.
The retirement path now validates owner/launch receipt lineage plus either a
validated exit receipt or an external process-identity review, the pre-review
inventory, and the actual optional result SHA-256 and semantic classification
before publishing a zero-contribution nonterminal disposition.
Review-only state remains partial, while a valid retirement can restore archive
integrity without completing the scientific outcome. Source pinning, dependent
identity regeneration, and Gate 7 bounded canonical smoke are complete in the
local worktree. Gate 8 independent pinned recovery/readiness review is the next
open integration gate; a retired predecessor cannot yet authorize remediation.

**LD1b pilot execution and evaluation remain pending.** Rank-normalized split
R-hat and bulk/tail ESS are now available from package sampler diagnostics, and
the LD1b1 preflight authorizes the pilot execution protocol. The remaining
required sequence is independent pinned recovery/readiness review; pilot
execution, review, and freeze; then separately seeded evaluation.
Repeated simulation must estimate false declarations, pair/family/global
multiplicity behavior, support-related missingness, and mechanism-confusion
rates before any fitted-effect interpretation or diagnostic decision becomes
available. The preflight runs no fit or MCMC and supplies no calibration
evidence, pairwise power, diagnostic decision, or mechanism interpretation;
`local_dependence_summary` remains report-only. LD1a magnitudes remain study-
local settings rather than universal cutoffs. The ability-confounded no-drift
scenario is the first order/case-mix stress control; parameter anchors, common
linking responses, and controlled benchmark responses remain distinct, and
early/middle/late benchmark placement belongs to the separate static-design
and temporal-identification studies.

The first model candidate is a non-centered scalar person-by-testlet random
effect with one common standard deviation in unidimensional MFRM, restricted
initially to one response per person-by-testlet. Repeated responses require a
separate response/occasion effect. Because person-by-testlet and response are
one-to-one in that slice, the term is labelled only as a shared cluster effect.
The candidate is compared against rater-by-
response halo, rater-by-task severity, omitted multidimensionality, and temporal
sequence mechanisms under known truth. One task per person, one indicator per
person-by-testlet cluster, rater-by-response cells with fewer than two item or
criterion observations, no independent rater overlap, rater nesting within
task, or unsupported
Q-by-testlet coverage blocks the corresponding mechanism claim before sampling.
Decomposing stable person-by-testlet from response/occasion variation further
requires multiple occasions per supported person-by-testlet, multiple indicators
per response, and enough repeated clusters; one occasion is a rejection control.

The stress grid includes true independence, near-zero through large testlet
standard deviations, halo, rater-by-task, multidimensional, sequence-only, and
selected mixture generators. It crosses cluster size, testlets per person, raters per
response, same-rater versus criterion-split scoring, sparse/crossed/nested and
ability-informed assignment, Q-by-testlet support, dependence shape, and
latent/outcome dispersion. Promotion requires calibrated null behavior,
positive-truth recovery and coverage, boundary-zero ROPE/false-declaration
calibration under frozen practical/probability thresholds, pair-level
localization and one global dataset-level FWER gate across all enabled
diagnostic families, correction of the targeted cluster discrepancy, low
mechanism-misclassification, stable decisions and priors, and passing HMC
diagnostics.

Prediction must distinguish another rating on a known response, a calibrated
rater newly assigned to an observed response, that rater on a wholly held-out
response, a rater absent from fitting, a repeated new response on the same task,
a new person-by-testlet combination, a new person, and a new task. Each
supported target holds out and marginalizes the
corresponding unseen effect; fixed person/rater/task facets do not support
population prediction for wholly new levels, and the first scalar slice does
not support response-to-response variation. Observation-row LOO alone can leak
a learned cluster effect and is
not evidence for any whole-cluster target.
The full model, identification, stress-grid, falsification, and cluster-
prediction contracts are maintained in
[MGMFRM Research Roadmap](mgmfrm-research-roadmap.md).

Only after the static and local-dependence gates pass does the temporal
identification study begin. Before time-varying severity can be interpreted, a
predeclared stress test must cross
true rater drift with changing early/late examinee ability, presentation and
assignment policy, temporal benchmark placement, and rating-graph sparsity.
The central negative control has no true drift but deliberately places lower-
or higher-ability responses late in the sequence. Evenly distributed,
full-range repeated benchmark responses and randomized or counterbalanced
presentation are evaluated as design repairs.

The detailed roadmap distinguishes current parameter anchors from linking
performances, monitoring/validity benchmarks, and repeated embedded benchmark
responses. It also maps direct primary precedents for dynamic MFRM, ratings and
rating-time models, Hierarchical Rater Models, Bayesian G theory, DFF,
adaptive rater monitoring, and human--machine rating. These component areas
have prior research; their fixed-Q multidimensional, time-varying,
assignment-aware integration remains a later research contribution and does
not broaden the current public package scope.

## Literature-Anchored Synthetic Benchmark

The first DOI-traced benchmark artifact materializes two deterministic
known-truth datasets from the literature-informed design review. The scalar pilot is
the smallest Uto and Ueno (2020) recovery cell (`J=30`, `I=3`, `R=5`, `K=5`,
fully crossed). The multidimensional pilot uses the smallest two-dimensional Uto
(2021) cell (`J=50`, `I=5`, `R=5`, `L=2`, `K=4`, fully crossed), but is explicitly
adapted to the package's confirmatory fixed-Q surface: inactive loadings are zero
rather than the paper's non-primary anchor loading of `0.2`, and the ability
term is recorded as a loading-weighted sum.

The generator duplicates the published adjacent-category equations in a
standalone response-sampling path and does not call package simulation or
probability helpers. After generation, it uses the package source-equation path
only as an oracle check. The committed artifact records the maximum probability
error, parameter truth, independent truth/response seeds, row hashes, and the
exact/adapted crosswalk. This is stronger wiring evidence than a same-code
simulation, but remains an in-repository crosscheck rather than an independently
maintained external oracle.

The independent review packet is now frozen as a separate artifact, but it is
not a signed review. A TAM `tam.mml.mfr` overlap baseline and CSV export are
prepared, and one local TAM execution review records the extracted parameter
table plus diagnostic item/rater/item-step comparisons. A follow-up TAM policy
review reconstructs the TAM category intercepts from the expanded facet table,
confirms the item-step sum constraints, and freezes post-pilot thresholds for
future replications. The item/rater pilot clears those future numerical gates;
item-step does not. The frozen policy has now been executed over 30 TAM fits at
40, 100, and 250 persons. All three parameter blocks pass in every primary
250-person replication; item-step passes 6/10 at 40 persons and 10/10 at both
100 and 250 persons. A same-data direct-estimate pilot then fits the package with
four AdvancedHMC chains: all sampler gates pass and the three aligned parameter
blocks correlate above 0.99 with TAM estimates. Because direct-agreement
thresholds were not frozen before that pilot, it remains descriptive. A
prospective direct package-versus-TAM agreement policy is now frozen for future
runs. A separate multiaxial refinement sidecar leaves every frozen primary
threshold unchanged while separating agreement from truth recovery, fixing
seed/data/fit/retry/failure contracts, recording the five-replication precision
limit, and constraining any result to the fully crossed unit-discrimination
MFRM/PCM overlap. The current item-step pilot is therefore classified as close
descriptive package/TAM agreement without full known-truth recovery support. A
separate completed execution artifact now applies that unchanged policy to five
fresh 40-person and five fresh 100-person datasets. All ten package fits pass
the frozen sampler gate, all ten TAM fits pass the numerical and adapter audit,
and item, rater, and item-step direct agreement pass 5/5 in the primary
100-person condition. Both estimators' known-truth recovery qualifiers also
pass 5/5 for every primary block. The 40-person stress condition illustrates
why these layers remain separate: direct agreement is 5/5 for every block,
while package and TAM recovery counts are 4/5 for item, 5/5 for rater, and 3/5
for item-step. Four rank-normalized R-hat advisories just exceed 1.01, although
every prospectively frozen classical R-hat/ESS/HMC gate passes. The all-attempt
audit retains 11 attempts and hashes 230 files, including the non-selected
result-writer failure and its same-seed infrastructure retry. The separate
post-execution packet is ready for review and its core execution hash chain
passes. The byte-exact refinement snapshot used by the retained jobs is now
preserved separately, and selected-job plus all-attempt input lineage is
checked against it without rerunning MCMC. The immutable pre-execution packet
is not rewritten, however: its policy hash matches while its refinement hash
identifies an older snapshot. That chronology difference remains an explicit
independent-review task and public-claim blocker. Independent re-execution and
a signed review remain
incomplete. The remaining scientific gates are
multi-replication generalized recovery refits, a unit-discrimination MFRM
bridge for FACETS, an aligned MRCML bridge for ConQuest, and external construct
data. None of the TAM evidence transfers to GMFRM/MGMFRM or Uto (2021), and no
package-wide or public validation claim is released.
The upper claim-recovery/full reproduction archives and broader/guarded
exposure reviews carry the TAM artifacts only as MFRM-overlap non-transfer
evidence. Their pending independent review and chronology adjudication remain
TAM-claim blockers and do not disable the existing guarded local fit surfaces.
Synthetic known truth can test source equations, constraints, recovery, and
design stress; it cannot
establish construct representation, population generalization, fairness, or
performance on an external real dataset.

## v0.1.1 Release Record

The `v0.1.1` release refined the core generalized and multidimensional surfaces
without broadening public claims. Its target was better auditability: the
guarded scalar GMFRM and fixed-Q confirmatory MGMFRM paths were required to
explain their source equations, constraints, priors, diagnostics, and reports
clearly enough for serious review.

`v0.1.1` kept these boundaries:

- no exploratory MGMFRM loadings, rotations, or free latent correlations;
- no dimensionality discovery beyond a fixed confirmatory Q-matrix;
- no fitted DFF model effects;
- no public model-weight, sparse-superiority, or manuscript-level claims;
- no direct-scale generalized priors unless the log-Jacobian policy is fully
  documented and tested.

The implementation roadmap originally defined six workstreams. The `v0.1.1`
scope was frozen to the completed status, portable-report, fixed-Q,
initial-diagnostics, MFRM FACETS-description, reproducibility, and runnable
example slices. Broader predictive/category reporting, rank-normalized and
bulk/tail diagnostics, rater-homogeneity work, and expanded validation bundles
described below are deferred to v0.1.2 or later.
The issue-sized implementation checklist is maintained in
[v0.1.1 Implementation Checklist](v0.1.1-implementation-checklist.md).

1. **Equation and status review**: reconcile public terminology for rater
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
4. **Diagnostics and reporting**: generalized diagnostics now use
   rank-normalized split R-hat and bulk/tail ESS across
   `GMFRMFit` and `MGMFRMFit`, report the prior contract and prior-predictive
   implications, add posterior predictive and calibration rows that state the
   predictive path used, retain classical `rhat`/`ess` fields for compatibility
   only, gate raw unconstrained and applicable direct constrained rows, keep
   zero-raw-dimension coordinates as non-gated `:structurally_fixed` rows while
   retaining reconstructed-but-varying coordinates in the gate, require
   complete finite chain coverage before applying the E-BFMI threshold, bind a
   versioned diagnostic contract into generalized cache identity, keep wrapper
   schemas at version 1 while treating rows without
   `rank_normalized_rhat_bulk_tail_ess_v1` as pre-modern, and
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
   artifacts. Before stable promotion, run genuinely overlapping R-package
   targets first as known-truth simulation comparisons, followed by separate-
   environment reproduction and provenance-cleared observed-data plausibility
   work. Include missingness, weak linking, skipped categories, and rater-
   specific category compression in the simulation pathologies.
6. **Interpretation policy**: keep model comparison diagnostic rather than
   claim-making, stabilize plotting-data schemas before backend-specific
   visualization recipes, keep DFF/bias effects validation-only, add rater
   homogeneity summaries based on posterior contrasts with ROPE and HDI or
   explicitly labelled central intervals, add a FACETS-fit compatibility
   policy for infit/outfit MNSQ, degrees-of-freedom approximations, and ZSTD
   labels, maintain the FACETS/ConQuest migration crosswalk, extend overlapping
   examples to TAM/mirt/sirt/immer, and keep Bayes factors out of the default
   workflow until
   prior-sensitivity policy is documented.

The release gate was documentation and evidence, not API breadth. `v0.1.1` was
limited to changes that made the guarded GMFRM/MGMFRM paths easier to inspect
and harder to overinterpret. Broad generalized fitting remains blocked until
the later stable-public gates pass.

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
5. **Cluster structure before dynamic interpretation**: residual dependence
   must be compared across testlet, halo, rater-by-task, multidimensional, and
   sequence mechanisms using cluster-heldout prediction before it is labelled.
6. **Scope labels before examples**: every runnable example must state whether
   it is `supported`, `experimental_public`, `specified_only`, or `blocked`.

Fallback paths remain explicit for later releases. For `v0.1.1`, unstable
fixed-Q MGMFRM diagnostics would have narrowed the release to report-governance
and validation improvements without expanding examples. If source or
sensitivity checks fail for generalized blocks, keep the API guarded and
document the failed gate. If external comparison targets do not match,
classify them as non-overlap rather than forcing a misleading validation table.

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

### Promotion Review Questions

Before promoting any feature, answer these questions in the docs or the
machine-readable artifact that backs the docs:

- What is the estimand, and which parameter block or contrast carries it?
- Which design conditions must hold before the estimate is interpretable?
- Which constraint, gauge, prior, and transform choices make the parameter
  identifiable?
- Which diagnostics can fail, and where does the failure appear in report rows?
- Which prior, likelihood, prediction-target, or heldout split sensitivity
  would change the substantive conclusion?
- What is the conditional-independence unit, and does a heldout target leave an
  entire response/testlet cluster unseen or condition on information from it?
- Which design contrast distinguishes testlet, rater-response halo,
  rater-by-task, multidimensional, and sequence explanations?
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
| `v0.1.1` | Delivered: existing guarded scalar GMFRM and fixed-Q MGMFRM paths became more auditable; status, priors, diagnostics, Q/gauge, rating-design, report, and artifact wording became harder to overinterpret. | Broader generalized fitting, exploratory loading, free latent correlations, fitted DFF effects, model weights, external validation, performance claims. |
| `v0.1.2` | Freeze and begin the scientific-validation protocol for the existing narrow fixed-Q candidate while hardening only the workflow needed to execute it. | Free latent correlations, exploratory loading, broad MGMFRM, or stable-validation claims. |
| Later `v0.1.x` | Complete fresh-seed validation, matching external overlap, separate-environment reproduction, and independent review without assuming that a version number guarantees promotion. | Automatic promotion of a mechanism because its code or pilot runs. |
| `v0.2.0` candidate | A narrow stable-public MGMFRM surface may ship only if Stages A-D pass for its named domain. Otherwise it remains experimental without delaying unrelated stable MFRM work. | Generic MGMFRM, non-overlap validation, or superiority claims. |
| After the narrow promotion decision | Free correlation, fitted anchors, exploratory loading, and dependence mechanisms receive separate proceed/narrow/stop programs. | Bundling all extensions into one broad MGMFRM milestone. |

### Runtime-Aware Verification

Post-v0.1.1 work should use staged verification because Julia
startup, precompilation, guarded HMC smoke tests, Documenter builds, and
fixture/archive regeneration can be slow. Local slices should start with load
checks and targeted fixture scripts; manifest, report, or docs changes should
regenerate low-level fixtures before review/archive fixtures; and the fixture
SHA scan should run before the full test suite. Full `Pkg.test()` runs remain
mandatory for milestone slices, supported-Julia release checks, and the final
tag candidate, but they should not be the first feedback loop for every small
edit.

The shared test runner now selects named `core`, `fitting`, `local_dependence`,
and `generalized` groups while plain `Pkg.test()` defaults to `all`. Ordinary
pull requests run complete coverage as one full minimum-Julia suite and four
current-Julia shards, plus focused macOS and Windows portability smokes. Record
duration and resource use before deciding whether finer groups or physical
helper extraction are justified.

| Tier | Feedback target | Default scope |
| --- | --- | --- |
| T0 | <= 2 minutes after precompilation | Diff/load plus the smallest affected group; no HMC for documentation-only edits. |
| T1 | <= 10 minutes | All groups mapped to the changed contract, deterministic fixtures first. |
| T2 | <= 30 minutes per PR shard | Primary Julia/Linux integration, changed-surface smoke, docs, and public-language checks. |
| T3 | Scheduled/manual | Full suite and supported Julia/OS matrix for milestone merge, release candidate, or tag. |

Groups that exceed their target in three consecutive runs are split or
reclassified. MCMC evidence is regenerated only when its model, design,
sampler, seed, schema, or scientific scoring contract changes.

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
| Model-surface review | Generalized or multidimensional releases | Family, dimensions, constraints, status levels, unsupported options, and public wording. |
| Source/transform evidence | Fit-surface promotion | Fixture IDs, tolerance policy, raw/direct checks, and BridgeStan or hand-computed comparison. |
| Diagnostic evidence | Fit-supported or interpretation-supported claims | Block-level diagnostics, sampler pathologies, R-hat/ESS type, direct constraints, and failure rows. |
| Design-support evidence | DFF, rater, anchor, or Q-matrix claims | Rating graph, category use, anchors, Q support, sparse cells, and confounding warnings. |
| Cluster-dependence evidence | Testlet, halo, rater-by-task, or dynamic claims | Response/testlet keys, mechanism-specific graph audit, null and positive-control calibration, competing-generator results, and whole-cluster marginal prediction. |
| Predictive evidence | PPC, calibration, or comparison claims | Prediction target, row matching, candidate set, PPC/calibration rows, Pareto-k or refit guidance. |
| Sensitivity evidence | Ranking, fairness, loading, or practical-decision claims | Prior-scale, likelihood-power, weight-quality, and refit-required rows. |
| Artifact governance | Public bundles or case studies | Schema version, hashes, seeds, package versions, provenance, anonymization, and raw-data policy. |
| Verification log | Release candidate | Load check, targeted tests, docs build, fixture/archive scan, public-language source/render/runtime checks, manual reader-facing wording review, and full test status. |

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
   metrics, calibration, posterior predictive checks, Stan comparisons, and
   genuinely overlapping R-package known-truth comparisons before stable
   promotion. Observed data follow recovery and separate-environment
   reproduction and support plausibility, not known-truth bias claims.

Current exposure is deliberately conservative: MFRM/RSM/PCM fitting and
simulation/recovery helpers are public; GMFRM/MGMFRM manifests and compiler
previews are public for inspection; guarded
`BayesianMGMFRM.Experimental.fit(spec)` paths are available for the scalar
rater-consistency GMFRM candidate and the fixed-Q confirmatory MGMFRM
candidate with `dimensions >= 2`. Broader GMFRM/MGMFRM fitting, DFF model effects,
public model-weight claims, and manuscript claims about sparse MGMFRM
superiority remain blocked. Local scalar model-weight reporting is restricted to
the heldout K-fold prediction target; confirmatory MGMFRM fitting is exposed
only as a guarded experimental path without model-weight or sparse-superiority
claims.

The public FACETS/ConQuest bridge is an input-and-receipt workflow, not an
external estimator. It prepares manual-syntax unanchored MFRM/RSM/PCM bundles
on a Mac, supplies a Windows path for FACETS and Windows/macOS paths for
ConQuest, and checks the input inventory and raw returned files. Its
`host_preflight` record exposes the bundle ID plus verifier and launcher hashes
for retention through a separate channel. The operator must compare those
hashes with a trusted host-side tool before launch: a launcher delivered inside
the same transfer is not its own trust anchor, and without that comparison the
workflow claims accidental-corruption detection rather than protection from
hostile replacement. A receipt alone does not establish that an external
execution occurred correctly, that it converged, that parameters were mapped,
that gauges agree, or that numerical results are equivalent. A separate
fail-closed adapter now resolves source-gauge rater, item, and step identities
for the exact ConQuest 5.47.5 three-category RSM/PCM boundary by jointly
validating the complete bundle, comments, and design matrix. It does not align
the destination gauge or establish convergence. The macOS fixtures and adapter
remain version-specific single-operator evidence rather than independent
external validation.

## Historical Progress Ledger and Maturity Snapshot

This dashboard preserves earlier workstream denominators. It is not the active
schedule or a package-completion score. Every percentage has its own named
denominator; values from different rows must not be averaged or treated as
interchangeable.

| Progress axis | Current estimate | Denominator | What remains outside or incomplete |
| --- | ---: | --- | --- |
| Historical mechanical roadmap snapshot | **160/189 (84.7%)** | Frozen count of the existing Markdown checkboxes in the historical/workstream ledger, including historical delivery, documentation, evidence, and future research infrastructure. | This legacy value is retained for continuity and is not the current `v0.1.2` workstream score or the implementation rate of MFRM, GMFRM, or MGMFRM. The independent current checklist below is excluded from this denominator. |
| Historical `v0.1.2` LD1b integration checklist snapshot | **7/9 gates recorded (77.8% at capture)** | Nine integration-acceptance gates in the historical checklist below. | This is retained gate bookkeeping, not current effort, implementation maturity, or scientific progress. Official LD1b execution recorded by this snapshot remains `0/660`. |
| Minimal MFRM/RSM/PCM core implementation | **implemented with remaining gaps** | The declared Bayesian scope: long-format data/specification, identified RSM/PCM likelihoods, exact individual rater/item hard anchors, priors, HMC fitting, diagnostics, PPC/calibration, category/rater practitioner summaries, fixed-coordinate report rows/warnings, cache/reproduction support, tests, and examples. | Fixed-coordinate and category/rater practitioner-report integration are complete. Remaining work is stable edge-case hardening. Soft, threshold, and group-mean anchors remain outside the stable numerical slice. FACETS feature parity, JMLE/MMLE backends, generalized discrimination, and external construct validation are not part of this denominator. |
| Minimal MFRM/RSM/PCM validation maturity | **partial** | Evidence needed to call the narrow Bayesian implementation externally validated and production-ready under stated design conditions. | The repeated recovery scorer, design preflights, narrow TAM evidence, and a version-specific ConQuest RSM/PCM known-truth execution fixture exist. Staged repeated MCMC, FACETS execution, independent ConQuest/TAM re-execution and review, external construct data, and comparative performance evidence remain open. |
| TAM narrow-overlap evidence for MFRM | **partial; locally reproduced** | The fully crossed unit-discrimination MFRM/PCM target currently shared by the package and TAM, with aligned signs, constraints, known truth, and direct parameter blocks. | Local direct agreement and recovery evidence are recorded, but independent re-execution, signed review, and chronology adjudication remain open; the result does not transfer to GMFRM/MGMFRM. |
| FACETS compatibility and validation bridge | **input workflow implemented; execution evidence pending** | Familiar MFRM summaries plus a matched known-truth comparison with FACETS under aligned model, scale, anchoring, weighting, and reporting conventions. | The migration crosswalk and deterministic manual-syntax input/return-integrity bundle are implemented. Actual Windows PowerShell 5.1 verification, a licensed-host execution, version-specific output samples, semantic result adapter, gauge-aligned comparison, anchored second stage, and independent numerical review remain open. |
| ConQuest overlap bridge | **version-specific local evidence; independent review pending** | A matched MRCML/MFRM target with explicit design matrices, constraints, parameter signs, and known-truth recovery. | The MRCML crosswalk, deterministic bundle, Windows/macOS launch paths, strict raw reader, exact output contract, receipt-bound macOS 5.47.5 RSM/PCM known-truth fixtures, and a fail-closed three-category source-gauge semantic adapter now exist. The adapter binds the complete bundle back to the specification, verifies exact comment/header order and the full design basis, and reconstructs rater/item/step constraints without a sign reversal. A convergence policy, destination reference-gauge transform, direct package comparison, anchor-aware second stage, Windows-path execution, and independent re-execution/review remain open. |
| Full FACETS/TAM product feature parity | **not scored (non-goal)** | The complete breadth of mature products, including model catalogs, arbitrary facet structures, response types, weighting, operational workflows, graphics, and long-established examples. | Add only capabilities that strengthen the declared Bayesian MFRM/MGMFRM workflow; do not turn unrelated product breadth into a hidden completion requirement. |
| Guarded scalar GMFRM implementation | **experimental and executable** | The deliberately narrow rater-consistency candidate, not every generalized MFRM variant. | Stable-public promotion, broader generalized kernels/priors, recovery breadth, and external validation remain open. |
| Guarded fixed-Q confirmatory MGMFRM implementation | **experimental and executable** | Fixed Q, confirmatory dimensions, fixed latent identity correlation, guarded Bayesian fitting, diagnostics, and recovery artifacts. | Stable-public promotion and broader design validation remain open; exploratory Q/loadings and free latent correlations are excluded. |
| Quarantined 2D free-correlation operational prerequisites | **0/3 passed; initial-gradient timing measured, memory adjudication invalidated** | Three conjunctive pre-scientific gates: a passing MCMC-free initial-gradient resource profile, a passing bounded short-NUTS resource profile, and an atomic single-unit scientific worker with a separately verifiable raw-draw archive and external digest anchor. | The historical three-repetition receipt passed the gradient, dimension, fixture/oracle, runtime, allocation, GC, and projected-time checks, but its 3.91 GiB field was the raw Julia/libuv free-page signal rather than a defensible available-memory observation on macOS. It cannot support either pass or fail. Re-measure with the corrected raw/available/pressure distinction before short-NUTS; the 8 GiB policy is not relaxed in place. |
| Quarantined 2D free-correlation scientific execution | **0/525 (0.0%)** | The frozen version-2 roster: 25 computation-only feasibility units followed, only after authorization, by 500 separately seeded recovery-evaluation units. | Resource probes, dry runs, and test-only receipts are outside this denominator. Feasibility remains 0/25, evaluation remains 0/500, and `recovery_verified` remains false. |
| LD1b local-dependence pilot execution | **0/660 (0.0%)** | The frozen 30-replication pilot: 540 eligible fitting jobs and 120 planned structural rejections across 22 scenarios. | The MCMC-free controller harness, completed-attempt seal boundary, receipt-bearing launched-attempt retirement integration, context-bound five-status semantic replay, receipt- and precommit-capable canonical worker, seven-source pin/dependent identity regeneration, and the final verification-only bounded canonical smoke are complete in the local worktree. Remaining order: independent pinned review, then pilot. Harness dry runs and the smoke receipt are outside this denominator. |
| Broad stable-public generalized claim maturity | **blocked** | Evidence required for broader release or manuscript claims, rather than callable experimental implementations. | Matching external evidence, independent claim-level review, generalized diagnostics/reporting hardening, and separate promotion programs for broader mechanisms remain open. |
| Generic MGMFRM research target | **research only** | A broader engine including exploratory/estimated structure, free latent correlations, generalized kernels and priors, and wider validation. | Major mathematical, computational, identification, reporting, and validation milestones remain downstream. |

### Historical v0.1.2 LD1b Integration Checklist

This frozen checklist records nine former integration-acceptance gates. Its
`7/9` snapshot is retained for provenance only; it is not an estimate of current
effort, implementation maturity, scientific progress, or release readiness.
The Active Decision Roadmap governs whether any related pilot or evaluation is
run.

| Gate | Status | Completion evidence or next condition |
| --- | --- | --- |
| Freeze the `v0.1.2` fixed-Q/guarded exposure boundary and align package/release metadata. | `complete` | `Project.toml` records `0.1.2`; free correlation, exploratory loading, and broad generalized claims remain outside the checkpoint. |
| Freeze LD1b0 scoring and LD1b1 authorization, seeds, controls, and the 660-row denominator. | `complete` | The scorer/protocol preflights record 540 eligible jobs and 120 planned structural rejections without executing the pilot. |
| Complete the MCMC-free batch harness, completed-attempt seal, and receipt-bearing launched-attempt retirement boundary. | `complete_local_worktree` | Synthetic archive/controller/scanner/checkpoint evidence passes while retired attempts remain nonterminal and contribute zero scientifically; tracked release-lineage verification remains pending. |
| Complete public-contract semantic replay for every terminal source member and define unavailable-diagnostic and final-serialization failure semantics. | `complete_local_worktree` | All five terminal statuses require explicit semantic context and exact replay through the canonical public calibration constructor/summary; completed outcomes require exact pair/family/global diagnostic linkage, while `sampler_diagnostics_unavailable` and `final_calibration_serialization_failed` remain nonterminal and cannot pass canonical runner validation for a completed seal or terminal admission. Tracked release-lineage verification remains pending. |
| Implement the canonical single-job worker with status-specific artifacts, execute-path owner/launch/exit receipts, and reservation-before-precommit recovery. | `complete_local_worktree` | The strict worker preserves frozen seeds, controls, job identities, and the primary denominator; routes five terminal statuses and two reserved nonterminal artifact failures; projects exact UInt64 data signatures before hashing; publishes source -> evidence -> result with CREATE_NEW semantics; validates controller-owned reservation -> owner -> launch -> exit lineage; and passes MCMC-free production pre-fit, receipt, tamper, and interruption-recovery tests. Tracked release-lineage verification remains pending. |
| Pin the final worker source and regenerate every authorization, harness, command, and checkpoint identity that depends on it. | `complete_local_worktree` | The protocol records an ordered seven-source SHA-256 pin covering the batch controller, canonical JSON helper, single-job worker, attempt archive, interruption recovery, calibration semantics, and harness generator. The controller compares every recorded digest with the repository files before deriving authorization, harness, all 660 command, and checkpoint identities. The worker execute path reconstructs readiness, so a CLI authorization flag alone cannot bypass missing smoke/review evidence. MCMC-free identity/tamper tests pass; tracked release-lineage verification remains pending. |
| Pass the bounded canonical smoke against that exact final pinned source. | `complete_local_worktree` | Canonical row 5 completed under the frozen 4-chain, 500-warmup plus 500-retained-per-chain controls in a separate verification-only namespace. The strict receipt validates the sealed archive and unchanged pilot root; scientific contribution is zero and tracked release-lineage verification remains pending. |
| Pass an independent pinned recovery/readiness review over the final worker, receipts, precommit recovery, and smoke evidence. | `open` | Controller readiness remains false until the independent review is accepted. The review must also exercise the transition from the receipt's unchanged `0/660` snapshot to a nonempty append-only official root and confirm that later resume checks do not retroactively invalidate the historical smoke evidence. |
| Execute, review, and freeze the authorized 660-job pilot. | `open` | Only verified terminal primary outcomes enter the scientific numerator; pilot review then freezes the evaluation size and study-local operating rules. |

The absence of JMLE or MMLE does not change the core implementation status:
the package currently declares a Bayesian estimator, so JMLE/MMLE would be a
new estimator family and should receive a separate future milestone and
evidence ledger. Likewise, the breadth of FACETS or TAM is a related-software
positioning and overlap-validation axis, not a hidden requirement for calling
the declared Bayesian MFRM/RSM/PCM implementation complete. The present TAM
evidence strengthens the overlapping MFRM slice; it does not establish feature
parity, production superiority, construct validity, or transfer to
GMFRM/MGMFRM.

### MFRM Completion and Interoperability Tracks

The remaining MFRM work is split into three tracks so that estimator breadth
cannot silently reduce the declared Bayesian implementation score:

1. **Bayesian core-to-complete:** finish the predictive and decision-stability
   portions of the paired sparse/nonrandom scorer, execute the staged repeated
   fits, and harden the remaining stable-MFRM edge cases. Category/rater
   summaries are integrated into `fit_report`, and the affine selection map for
   exact individual rater/item hard anchors is implemented. `anchor_refit_plan`
   remains a non-mutating semantic and optional-provenance check; it is not a
   linking-constant estimator.
2. **Practitioner and external bridges:** the FACETS/ConQuest migration guide
   now freezes sign, scale, constraint, threshold, anchor, and estimator
   non-equivalence rules. The deterministic version-1 bridge prepares
   unanchored manual-syntax bundles on a Mac, verifies inputs before the
   FACETS Windows or ConQuest Windows/macOS launcher calls an authorized
   executable, and verifies the returned input inventory and raw-output hashes.
   The ConQuest 5.47.5 macOS RSM/PCM known-truth run and privacy-reduced sample
   freeze and the narrow source-gauge semantic adapter are complete. Next,
   independently re-execute those samples, validate a separate destination
   reference-gauge transform, execute FACETS and the Windows paths, and only
   then design an anchor-aware second stage for the exact returned designs. A
   successful receipt is transport-integrity evidence,
   not convergence or numerical-validation evidence. Independently re-execute the
   narrow TAM comparison as a separate gate; keep point-estimate agreement and
   uncertainty agreement separate.
3. **Optional estimator interoperability:** prefer reproducible external
   adapters before considering native JMLE or MMLE engines. A native
   frequentist backend should be proposed only for a concrete use case and must
   have its own mathematical, numerical, diagnostic, and maintenance gates; it
   is not part of the final five percent of the Bayesian core.

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
is now available through `BayesianMGMFRM.Experimental.fit(spec)` and records
raw/direct draws, sampler diagnostics, direct constraints, pointwise log
likelihood, and an experimental fit artifact while keeping broader MGMFRM
exposure blocked. The older keyword spelling remains compatibility-only.
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
| Test-only implementation | Likelihood or transform exists only for tests and source-equation checks. |
| Private validation candidate | Private target with raw/constrained manifests, AD checks, HMC diagnostics, and BridgeStan evidence. |
| `experimental_public` | Narrow user-facing fit path with explicit warnings, diagnostics, and recovery smoke evidence. |
| `stable_public` | Ordinary examples and package claims are supported by internal simulation, sensitivity checks, and reproduction artifacts. |
| `external_validated` | A reviewed named-domain claim supported by overlapping known-truth comparisons, separate-environment reproduction, and only then observed-data plausibility evidence. |

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

### Local Independence and Cluster Prediction

Residual dependence is screening evidence, not a mechanism label. A testlet or
rating-bundle extension must declare response/testlet keys, cluster replication,
rater and task crossing, Q-by-testlet support, the variance-boundary policy,
and whether prediction conditions on or marginalizes each shared random effect.
Whole-response heldout evaluation is required for new-response claims.

### Bayesian Computation

Future HMC/NUTS fits must report diagnostics by parameter block: R-hat,
bulk/tail ESS, divergences or numerical errors, max-treedepth hits, step size,
leapfrog counts, and E-BFMI coverage. Summaries may retain the minimum finite
available E-BFMI for compatibility, but the quality threshold applies only
when every expected chain is available. Faster runtime is not evidence unless
sampling quality also passes.

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
  experimental-candidate gates, a fit-ready compiler-candidate manifest, gradient
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
  experimental-candidate fit-ready compiler manifest, gradient and raw-to-direct
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
  [`fit_stats`](@ref) provides posterior infit/outfit rows,
  [`facets_report`](@ref) / [`facets_compatibility_stats`](@ref) provides separately labelled
  unit-weighted posterior-mean plugin rows with Wright--Masters fourth-moment
  df and capped Wilson--Hilferty ZSTD for MFRM/RSM/PCM fits only, and
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
  dimensionality, and misspecification axes. A deterministic validation-plan export
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
  and records the release-verification gate as the registry-update readiness
  boundary.

## Completed 30-45 Day Sprint Record

This section is retained as the completed sprint record for guarded scalar
GMFRM and fixed-Q confirmatory MGMFRM exposure work. Broader stable-public claims
and release actions remain governed by the release-scope and independent scope-review
gates above.

1. Split the scalar GMFRM experimental candidate from source-fixture helper logic
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
| Local-dependence mechanism confusion | Compare person-by-testlet, rater-by-response halo, rater-by-task, multidimensional, and sequence generators; keep the effect diagnostic until cluster prediction and known-truth separation pass. |
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
- Do not label residual association as a testlet, halo, or dimension effect
  without an identified competing-mechanism study.
- Do not use observation-row LOO as evidence for a wholly new response when a
  shared response/testlet effect was learned from other rows in that response.
- Do not automatically collapse sparse or disordered categories without a
  recorded analysis decision.
- Do not report partially pooled facet effects as unpooled facet locations.
- Do not export raw identifiers or row-level rating data in public artifacts by
  default.
- Do not claim broad or exploratory MGMFRM support, model-weight superiority,
  or sparse-design superiority from the guarded fixed-Q path until broader
  multidimensional fixtures, recovery/sensitivity evidence, and public-scope
  release review pass.
