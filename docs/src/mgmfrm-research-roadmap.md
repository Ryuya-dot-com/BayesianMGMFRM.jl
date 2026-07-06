# MGMFRM Research Roadmap

This roadmap records the research basis and implementation sequence for moving
`BayesianMGMFRM.jl` from the current guarded fixed-Q MGMFRM experiment toward a
stable public generalized MGMFRM surface. The governing principle is simple:
the package should not expose a broader model surface until identification,
diagnostics, validation, and reporting are at least as clear as the likelihood
equation.

## Scope Decision

The active post-`v0.1.0` sequence is:

- `v0.1.1`: refine fixed-Q confirmatory MGMFRM. Strengthen execution,
  diagnostics, reporting, and validation for the existing guarded path.
- `v0.1.2`: stay fixed-Q and confirmatory, but expand dimensionality,
  Q validation, and fit-threshold calibration beyond the original compact
  smoke surface.
- `v0.1.3`: decide whether free latent correlations are ready for guarded
  exposure.
- `v0.1.4`: design the exploratory loading and rotation policy without yet
  making exploratory MGMFRM stable public.
- `v0.2.0`: promote a general MGMFRM surface only as a stable-public candidate,
  after the earlier gates have passed.

The version numbers are intentionally conservative. The hard part is not adding
parameters; the hard part is preventing non-identified or non-interpretable
posterior summaries from looking authoritative.

## Global and Local Review

The large-scale objective is not simply "run MGMFRM." The objective is to make
MGMFRM outputs reviewable enough that a user can tell which statements are
model equations, which are sampler evidence, which are posterior summaries, and
which are practical decisions. The stable package should therefore optimize for
claim control before feature breadth.

At the global level, the roadmap has seven standing contracts:

- **Model-surface contract:** every exposed surface declares its family,
  dimensions, Q/gauge choices, rater-effect blocks, discrimination blocks,
  latent-correlation policy, and unsupported options.
- **Rating-design contract:** every analysis records the observed rating
  assignment design, structural versus accidental missingness, anchor/linking
  choices, repeated ratings, time/order fields when available, and category-use
  support before model claims are interpreted.
- **Computation contract:** every fitted surface reports prior policy,
  initialization, sampler controls, divergences, max-depth hits, E-BFMI,
  rank-normalized R-hat, bulk/tail ESS, direct-constraint failures, and
  non-finite likelihood checks.
- **Predictive contract:** model comparison, PPC, calibration, and heldout
  scoring must name the prediction target. WAIC/LOO/K-fold rows are diagnostic
  unless a separate model-weight policy passes.
- **Interpretation contract:** rater severity, rater consistency, loading, DFF,
  and group-difference outputs must distinguish statistical uncertainty from
  practical magnitude. ROPE/HDI-style summaries and posterior contrasts are the
  default decision layer; Bayes factors are optional research artifacts, not the
  default public workflow.
- **Communication contract:** the package should provide stable table and
  plotting-data schemas before binding to any plotting backend. The first
  public goal is reproducible report data, not publication graphics.
- **Artifact governance contract:** report bundles should carry the
  `evidence_artifact_schema_policy` contract for schema versions,
  package/git/environment hashes, random seeds, sampler controls, cache
  provenance or not-applicable markers, unsupported-claim flags, and explicit
  raw-data/anonymization status.

At the local level, each topic has a specific near-term decision.

| Topic | Current posture | Roadmap decision |
| --- | --- | --- |
| Weakly informative priors | Public MFRM uses independent normal priors on identified parameters. Guarded generalized fits use raw-coordinate independent normal priors. | Keep defaults weakly informative but require prior predictive checks and prior/likelihood power-scaling sensitivity before interpretation. |
| Hierarchical shrinkage | Current public priors are independent by block; sparse rater-mediated designs often invite partial pooling, but pooling changes estimands and shrinkage interpretation. | Keep independent priors as the v0.1.x default. Before `v0.2.0`, decide whether hierarchical facet priors are out of scope, optional experimental, or part of the stable MGMFRM surface; if added, report shrinkage diagnostics and sensitivity. |
| Convergence diagnostics | Current R-hat/ESS are classical split R-hat and autocorrelation ESS. HMC rows include divergences, tree-depth fields, and E-BFMI when available. | Label current R-hat/ESS as provisional and add rank-normalized R-hat plus bulk/tail ESS before stable generalized claims. |
| Model comparison | WAIC, raw LOO, PSIS-LOO, K-fold, and shared-plan refit comparison rows exist. | Keep comparison rows diagnostic in `v0.1.1`; require prediction-target statements, Pareto-k/refit or K-fold follow-up, and no model-weight/superiority language. |
| Visualization | The package returns plotting-ready rows for recovery, calibration, PPC, threshold maps, coverage matrices, rater overlap, and Wright maps. | In `v0.1.1`, stabilize plot-data schemas and documentation examples; defer backend-specific recipes until the report data contract is stable. |
| Category functioning | Rating-scale and partial-credit interpretations can fail when categories are skipped, disordered, sparse, or used differently by raters. | Add category-functioning rows that separate observed category use, posterior threshold/step uncertainty, predictive category replication, and any category-collapsing recommendation. Recommendations should be diagnostic, not automatic data editing. |
| Missingness and rater assignment | MFRM assumes the observed rating graph can support the intended facet comparisons; nonrandom assignment, planned missingness, and time/order effects can change what is identifiable. | Add a rating-design audit: structural missingness, accidental missingness, disconnectedness, anchor coverage, repeated ratings, time/order fields, and warnings that current models do not correct nonignorable assignment unless an explicit assignment model is introduced. |
| Binary responses and multi-facet IRT | The current MFRM family includes two-category responses as the dichotomous Rasch special case with additional facet terms. Guarded generalized paths add discrimination/consistency terms that move beyond strict Rasch measurement. | Document the binary bridge explicitly: MFRM is a many-facet one-parameter logistic IRT model; GMFRM/MGMFRM with item discrimination, rater consistency, or multidimensional Q-masked loadings should be labelled generalized or 2PL/GPCM-like, not strict Rasch. |
| Infit, outfit, and FACETS degrees of freedom | `fit_stats` currently returns posterior infit/outfit mean-square summaries for minimal MFRM fits; generalized paths do not yet expose full FACETS-style fit tables or ZSTD degrees-of-freedom approximations. | Keep posterior infit/outfit as the default Bayesian residual diagnostic. Add a separate FACETS-compatibility policy that records MNSQ formula, `outfit_df`, `infit_information`, optional Wilson-Hilferty/ZSTD approximation, and clear warnings when posterior uncertainty or generalized discrimination makes FACETS degrees of freedom only approximate. |
| DFF and bias | DFF is validation and screening only: sparse/empty/confounded cells, grouped PPC rows, and posterior predictive interaction residuals. | Keep fitted DFF effects blocked through `v0.1.1`; use DFF rows for triage, design repair, and sensitivity planning, not unfairness or causal claims. |
| Rater homogeneity | Posterior summaries support probability of direction and ROPE for individual parameters; pairwise rater contrasts are not yet first-class. | Add rater contrast summaries for severity and log-consistency using ROPE and HDI/credible intervals. Treat Bayes factors as optional and blocked from the default workflow until prior sensitivity is documented. |
| Artifact schemas and data governance | Report bundles exist, but broad use requires stable schemas and clear handling of raw rating data. | Version report-table schemas, include manifest compatibility checks, and make raw-data inclusion opt-in. Public artifacts should prefer anonymized or hashed identifiers unless the user explicitly exports raw labels. |

## Literature-Informed Priority Update

The July 2026 Zotero additions sharpen the roadmap rather than broadening the
public API immediately. Duplicate Zotero records are acceptable as library
state; package artifacts should record public bibliographic identifiers and
source URLs, not internal item keys.

| Literature cluster | What is now better supported | Roadmap consequence |
| --- | --- | --- |
| Multidimensional Rasch and MRCML foundations | Adams, Wilson, and Wang's MRCML paper, ConQuest documentation, Reckase's MIRT text, and multidimensional partial-credit work make the fixed-Q dimensional contract the natural bridge from Rasch models to MGMFRM. | Treat `v0.1.2` as a confirmatory multidimensional Rasch/MGPCM expansion, not as exploratory discovery. Dimension labels, constraints, and Q masks must be inspectable before broader fitting claims. |
| Uto-style GMFRM/MGMFRM | Uto and Ueno's GMFRM and Uto's MGMFRM provide the direct rater-mediated target: severity, consistency, item/task discrimination, ordered categories, fixed scaling, and Bayesian HMC estimation. | Keep the current scalar GMFRM and fixed-Q MGMFRM paths guarded until report rows can explain each source-equation block, prior, transform, and diagnostic failure. |
| Q-matrix validation | de la Torre and Chiu, Chiu, Chen, Terzi and de la Torre, Najera et al., Madison and Bradshaw, and da Silva et al. show that Q matrices are fallible design objects, but empirical revisions need error control. | Keep empirical Q revision local and diagnostic. Simulations must include false-add, false-drop, weak-dimension, duplicate-column, and sparse-anchor cases before any public Q-revision helper is promoted. |
| Fit statistics and threshold uncertainty | Wright/Linacre-style mean-square ranges are useful screening heuristics, but Smith/Schumacker/Bush and Mueller-style critiques make fixed universal cutoffs unsafe. Bayesian LOO/WAIC and R-hat/ESS literature adds a separate computation and prediction layer. | Treat thresholds as named profiles, not defaults. Compare existing MFRM infit/outfit with MGMFRM PPC, calibration, WAIC/LOO, heldout ELPD, and parameter-shift rows under simulation before allowing threshold-based claims. |
| Existing software and practice | Facets, ConQuest, TAM, mirt, sirt, immer, and Stan/brms already cover important adjacent surfaces. | The package's niche remains source-audited Bayesian many-facet/MGMFRM workflow, not generic IRT breadth. External comparisons should start with known-truth simulations only after the stable-public candidate exists. |

### Refined Critical Path

1. Finish `v0.1.1` as a reporting and evidence-governance release for guarded
   scalar GMFRM and fixed-Q MGMFRM. Do not expand the API until diagnostics,
   fit-threshold provenance, prediction targets, and blocked-claim rows are
   consistently visible in reports and archives.
2. Make `v0.1.2` the fixed-Q validation and threshold-calibration release.
   The key deliverable is not "more dimensions"; it is evidence that the
   package can distinguish well-specified fixed-Q MGMFRM, Q misspecification,
   rater-method noise, sparse dimension support, and ordinary MFRM misfit.
3. Keep `v0.1.3` focused on whether free latent correlations are defensible
   under a Cholesky/LKJ-style policy. A free-correlation path that changes
   focal decisions under prior or likelihood sensitivity remains internal.
4. Keep `v0.1.4` as an exploratory-loading design gate. Exploratory MGMFRM
   should remain blocked unless rotation, sign, permutation, and reporting
   invariance are handled before users see posterior loading tables.
5. Promote `v0.2.0` only if fixed-Q, optional free correlation, and any
   exploratory surface that survived earlier gates all have source fixtures,
   diagnostics, simulation recovery, sensitivity, reporting, and rejection
   tests. If not, release the narrower supported surface.

### Fit-Threshold Simulation Linkage

Fit thresholds should now be treated as simulation-calibrated decision profiles.
The roadmap should connect literature-motivated thresholds to known-truth data
generating conditions before using them in public wording.

| Simulation axis | Why it is needed | Metrics to compare | Release consequence |
| --- | --- | --- | --- |
| Well-specified MFRM/RSM/PCM baseline | Controls false alarms from Rasch MNSQ, PPC, calibration, WAIC/LOO, and heldout scoring. | Infit/outfit profile pass rates, PPC discrepancy rates, calibration error, WAIC/LOO instability, heldout ELPD, parameter bias and coverage. | Thresholds that falsely flag the baseline too often become screening-only. |
| True fixed-Q MGMFRM | Checks whether multidimensional signal is recovered without inventing Q revisions. | Loading recovery, dimension ability recovery, rater consistency recovery, heldout ELPD improvement, posterior predictive category replication. | Supports fixed-Q interpretation only if diagnostics and recovery pass by block. |
| Missing required Q loading | Tests power to detect under-specified dimensions or item masks. | Candidate-cell detection, ELPD loss, item/dimension residuals, calibration shifts, changes in rater consistency and severity. | A detected issue can trigger local review, not automatic public Q editing. |
| False-positive Q loading or cross-loading | Tests overfitting and construct drift. | Loading shrinkage or instability, predictive gain/loss, decision reversal, false public-promotion rate. | Block promotion if extra loadings look plausible only because priors or sparse data support them. |
| Weak or sparse dimension support | Mirrors realistic rubric designs with limited items or anchors per dimension. | Dimension-specific ESS/R-hat, coverage, interval width, Q graph support, heldout rank stability. | Require warning or rejection when dimension claims are prior-dominated. |
| Rater-method noise and DFF-adjacent confounding | Separates rater behavior from multidimensional construct structure. | Rater consistency/severity shifts, grouped PPC, DFF screening rows, Q-revision false positives, heldout score changes. | Keep DFF and Q revisions diagnostic unless design support and sensitivity pass. |

The immediate implementation target is a small fixture that links
`mgmfrm_fit_metric_threshold_sensitivity`, the empirical Q-matrix recovery
simulation grid, and fold-1 heldout scoring outputs into one roadmap artifact.
It should report which threshold profiles would change conclusions and which
parameter blocks absorb the change.

## Decision Gates and Fallback Paths

Each release should have a positive gate and a fallback gate. Passing the
positive gate allows promotion; failing it should narrow claims rather than
silently carrying risk into the next release.

| Release | Positive gate | Fallback if the gate fails |
| --- | --- | --- |
| `v0.1.1` | Existing guarded scalar GMFRM and fixed-Q MGMFRM fits have auditable diagnostics, report sections, prior policy, predictive path labels, and blocked-claim rows. | Ship documentation, manifest, and report-governance improvements only. Keep guarded examples minimal and mark unresolved diagnostics as blockers. |
| `v0.1.2` | Higher-dimensional fixed-Q designs pass Q validation, source/BridgeStan checks, initialization checks, simulation recovery, and report-shape tests. | Keep the public fixed-Q surface guarded and confirmatory; allow only the evidence-backed subset to remain `experimental_public`. |
| `v0.1.3` | Free latent correlations have a stable parameterization, prior policy, sampler diagnostics, and interpretation rules that do not change focal conclusions under sensitivity checks. | Keep identity correlation as the stable policy and record free-correlation evidence as internal research only. |
| `v0.1.4` | Exploratory loading proposals have rotation, sign, permutation, and reporting rules that make posterior summaries interpretable. | Keep exploratory loadings blocked; provide only design-review tools and confirmatory Q workflows. |
| `v0.2.0` | Generic MGMFRM surfaces pass source, transform, prior, computation, simulation, sensitivity, and reporting gates for every exposed option. | Release a narrower stable public surface and carry unsupported options forward as `specified_only` or `experimental_public`. |

The fallback path is part of the roadmap, not a failure of the project. It
protects users from mistaking a runnable generalized model for a validated
measurement workflow.

## Pre-Mortem and Early Warning Signals

The most likely roadmap failures are not syntax failures. They are cases where
the package produces polished artifacts before the evidence can support the
interpretation.

| Failure mode | Early warning signal | Roadmap response |
| --- | --- | --- |
| Fixed-Q MGMFRM appears to work but dimensions are not interpretable | Duplicate or weak Q columns, sparse dimension-specific item support, unstable loading signs, or report rows that require rotation language. | Freeze the fixed-Q surface, require stronger `q_matrix_validation`, and keep exploratory or free-correlation wording blocked. |
| Global diagnostics look acceptable while focal blocks fail | Overall R-hat/ESS pass but rater-consistency, loading, threshold, or DFF-adjacent contrasts have low ESS, divergences, max-depth hits, or direct-constraint failures. | Promote block-level diagnostics to release blockers and remove focal interpretation examples. |
| Priors silently determine generalized conclusions | Prior predictive ranges are implausible, power-scaling shifts focal decisions, or reweighting diagnostics are unstable. | Require refits or narrower priors; label affected conclusions prior-sensitive and block rankings. |
| Rating design cannot support the requested fairness or rater claim | `rating_design_audit` reports disconnectedness, weak anchor coverage, sparse person-rater-item blocks, or confounded group/rater cells. | Keep outputs as design triage and screening rows; do not fit or interpret DFF effects as bias evidence. |
| Category functioning is mistaken for automatic data cleaning | Skipped categories, rater-specific category compression, or disordered steps appear, and examples imply categories should be collapsed automatically. | Make category rows diagnostic-only and require user-confirmed design or scoring changes outside the model report. |
| Comparison rows become model-selection claims | WAIC/LOO/K-fold ranks flip under target changes, influential rows, Pareto-k warnings, or heldout splits. | Keep comparison as local diagnostic evidence; block model weights, sparse-superiority, and manuscript-level selection claims. |
| External validation is forced onto non-overlap targets | Facets/TAM/mirt/sirt/immer outputs use different constraints, priors, dimensions, estimands, or estimation targets. | Mark the case as non-overlap and use it for terminology or migration notes, not validation. |
| Documentation drifts ahead of manifests | README, docs, report tables, or release notes advertise broader GMFRM/MGMFRM support than `release_scope_summary` and `model_surface_audit` allow. | Treat `release_gate_check` failures as release blockers and narrow the wording before code promotion. |
| Evidence artifacts leak more data than intended | Bundles include raw labels, row-level data, institution names, or unreviewed case-study files. | Make raw-data export opt-in and require explicit anonymization/provenance rows before sharing artifacts. |

## Release Decision Record Template

Every generalized release candidate should leave a short decision record. The
record is not a release note; it is the audit trail for why the surface was
promoted, held, or narrowed.

| Field | Required content |
| --- | --- |
| Candidate surface | Exact model family, backend, dimensions, Q/gauge policy, rater-effect blocks, and unsupported options. |
| Proposed status | One of `specified_only`, `experimental_public`, `stable_public`, or `external_validated`, with the previous status named. |
| Evidence reviewed | Source fixtures, transform checks, gradients, HMC diagnostics, simulations, sensitivity, reports, artifacts, and docs wording. |
| Design conditions | Minimum rating graph, category use, anchor/linking, missingness, Q-matrix, and DFF-cell support required for interpretation. |
| Failed or weak gates | Any source, computation, sensitivity, prediction-target, report, privacy, or external-overlap weakness that remains. |
| Wording allowed | Exact public claim language that is allowed in docs, examples, and release notes. |
| Wording blocked | Claims that must not appear, especially broad MGMFRM support, fairness conclusions, model weights, or superiority language. |
| Decision | `proceed`, `narrow`, or `stop`, with the follow-up issue or release target for unresolved work. |

The default decision is `narrow` when evidence is mixed. Use `proceed` only
when the claim language, evidence artifacts, and release-scope rows all agree.
Use `stop` when source alignment, identification, diagnostics, privacy, or
external-overlap assumptions are actively contradicted.

## Research Debt Register

The roadmap should keep research debt visible instead of hiding it behind
implementation progress.

| Debt | Why it matters | Resolution path | Release impact |
| --- | --- | --- | --- |
| Rank-normalized diagnostics are not yet the stable generalized default | Classical split R-hat and autocorrelation ESS can miss tail or rank pathologies in generalized blocks. | Add rank-normalized R-hat, bulk ESS, tail ESS, and block-level pass/fail rows. | Blocks interpretation-supported generalized claims. |
| Fixed-Q invariance checks are incomplete | Dimension labels and loading signs can look stable when the gauge is actually doing the work. | Add fixed-sign, fixed-identity-correlation, positive-loading, and direct-constraint invariance checks. | Blocks broader fixed-Q claims and non-confirmatory expansion. |
| Prior sensitivity is not yet tied to focal decisions | Weak priors can determine rater consistency, loading, or sparse DFF-adjacent conclusions. | Connect prior predictive rows, prior-scale grids, and power-scaling shifts to report decision labels. | Blocks ranking and practical-decision language. |
| Predictive targets are not yet uniformly attached to comparison rows | WAIC, LOO, and K-fold can answer different questions if row matching or targets differ. | Require prediction-target, row-matching, candidate-set, and influential-row fields before interpretation. | Blocks model weights and superiority claims. |
| DFF remains screening-only | Sparse or confounded cells can produce compelling contrasts that are not fairness evidence. | Keep fitted DFF effects blocked; add design-support, grouped PPC, practical-magnitude, and sensitivity rows. | Blocks bias/unfairness language. |
| External overlap targets are unresolved | Mature R packages may estimate related but nonidentical models. | Start post-`v0.2.0` with known-truth simulations and explicit non-overlap labels. | Blocks external validation claims. |
| Artifact privacy policy needs release testing | Rating data often contain identifiable people, raters, institutions, tasks, or groups. | Make raw labels opt-in, require provenance/anonymization rows, and test bundle contents. | Blocks public evidence bundles. |
| Docs environment can drift from package state | Stale docs manifests can hide broken references or examples. | Repair docs project paths, build docs locally, and keep docs readiness out of the claim until the build passes. | Blocks release-candidate documentation sign-off. |

## Sensitivity and Refit Policy

Sensitivity rows should change release decisions, not merely decorate reports.

| Sensitivity outcome | Interpretation policy | Required follow-up |
| --- | --- | --- |
| Focal contrast is stable across prior-scale and likelihood-power checks | The contrast can be interpreted if design support and diagnostics also pass. | Report the sensitivity range and keep the claim within the tested design. |
| Focal contrast changes direction, ROPE class, or practical-magnitude class | The conclusion is prior/likelihood sensitive. | Block ranking or decision language; require a refit or narrower design claim. |
| Importance reweighting has weak effective sample size or high Pareto-k | Reweighted sensitivity is not reliable evidence. | Trigger exact refit, K-fold/refit follow-up, or mark the sensitivity result inconclusive. |
| Sensitivity failure appears only in non-focal nuisance blocks | Keep focal interpretation only if nuisance instability cannot change the target contrast. | Record the block and add a follow-up issue; do not generalize beyond the tested claim. |
| DFF or fairness contrast is sensitivity-dependent | Treat the row as screening evidence only. | Require stronger design support, predeclared practical thresholds, and refits before fairness language. |
| Model-comparison rank flips across prediction targets or folds | Comparison is diagnostic only. | Report target-specific scores; block model weights and "best model" wording. |

## External Validation Protocol

External validation starts after a stable-public candidate exists. It should
begin with target matching, not with real-data examples.

| Step | Requirement | Failure handling |
| --- | --- | --- |
| 1. Target declaration | Name the exact package, function, model family, link, thresholds, facets, dimensions, constraints, priors or estimator, and prediction target. | If the target cannot be stated, classify the case as related-software positioning only. |
| 2. Overlap audit | Decide whether the external target estimates the same estimand or only a related quantity. | Label non-overlap explicitly and do not count disagreement as validation evidence. |
| 3. Known-truth simulation | Generate data from a target both workflows can represent, with fixed seeds and documented design support. | If either workflow cannot represent the target, narrow the target or drop the comparison. |
| 4. Recovery metrics | Compare bias, RMSE, interval coverage, calibration, rater-effect recovery, loading recovery, and failure rates. | Treat runtime or point estimates alone as insufficient. |
| 5. Computation metrics | Record divergences, convergence warnings, ESS/sec where applicable, elapsed time, memory, and failed fits. | Do not make performance claims without sampler-quality context. |
| 6. Reporting comparison | Compare scale conventions, constraints, practical summaries, and diagnostics users actually see. | Document translation rules; avoid claiming one tool is wrong when scales differ. |
| 7. Real-data demonstration | Only after known-truth behavior is understood, run compact real data as workflow evidence. | Treat unexplained disagreement as an investigation item, not validation. |

## Competitive Weaknesses and Mitigation

The package should be honest about where the R ecosystem is stronger. TAM,
mirt, sirt, immer, and Facets are mature tools with broad model coverage,
worked examples, and established user expectations. `BayesianMGMFRM.jl` should
not try to win by implementing every IRT model. It should win only where a
Bayesian MGMFRM-specific workflow can be more explicit, auditable, and
reproducible.

The package now exposes the same positioning table programmatically through
[`related_software_capability_matrix`](@ref). The table is a scope-governance
artifact, not a validation result or superiority claim.

| Tool | Established strength | BayesianMGMFRM overlap | v0.1.1 stance |
| --- | --- | --- | --- |
| [Facets](https://www.winsteps.com/facets.htm) | Mature many-facet Rasch measurement workflow, facet maps, fit tables, and practitioner reporting. | MFRM-facing outputs such as severity, fair averages, fit statistics, maps, and sparse-design warnings. | Migration and terminology reference, not a replacement claim. |
| [TAM](https://cran.r-project.org/web/packages/TAM/refman/TAM.html) | Broad R IRT toolkit including Rasch/PCM/GPCM, multidimensional IRT, and multi-faceted Rasch models. | MFRM/PCM/GPCM and fixed-Q multidimensional cases where targets genuinely overlap. | Breadth baseline; do not duplicate generic IRT coverage just to match TAM. |
| [mirt](https://www.jstatsoft.org/article/view/v048i06) | Exploratory and confirmatory multidimensional IRT with mature estimation and diagnostics. | Fixed-Q MIRT expectations and multidimensional loading interpretation. | Multidimensional baseline, not a dedicated many-facet replacement. |
| [sirt](https://cran.r-project.org/web/packages/sirt/sirt.pdf) | Supplementary IRT methods, including specialized model, diagnostic, and rater-related tools. | Rater-effect, DIF/DFF, and diagnostic-method context. | Specialized-method reference; keep fitted DFF effects blocked in v0.1.1. |
| [immer](https://cran.r-project.org/web/packages/immer/immer.pdf) | Item response models for multiple ratings and rater-mediated designs. | Multiple-rating and rater-effect context. | Rater-model reference; overlap comparison waits until post-v0.2.0. |
| [brms](https://cran.r-project.org/web/packages/brms/brms.pdf) / [Stan](https://mc-stan.org/docs/stan-users-guide/item-response-models.html) | Flexible Bayesian multilevel and custom IRT modeling with HMC/NUTS diagnostics. | Bayesian diagnostics, posterior predictive checks, custom IRT targets, and model-comparison workflow. | Bayesian workflow baseline, not a packaged MGMFRM substitute. |
| `BayesianMGMFRM.jl` | Source-audited Julia workflow for Bayesian MFRM, guarded rater-consistency GMFRM, and fixed-Q confirmatory MGMFRM artifacts. | Own current public surface. | Narrow auditable workflow; generic IRT replacement and superiority claims remain blocked. |

| Weakness | Why it matters | Mitigation target |
| --- | --- | --- |
| Narrower model coverage than TAM/mirt/sirt/immer | Users may expect broad IRT, MIRT, DIF, latent-class, plausible-value, and HRM coverage. | Maintain a related-software matrix and state non-goals clearly. Add features only when they strengthen the MGMFRM workflow rather than duplicating generic IRT coverage. |
| Generalized paths are still guarded | A runnable experimental MGMFRM is not the same as stable public MGMFRM. | Keep `experimental_public` labels until source, transform, prior, HMC, recovery, and reporting gates pass. Treat real-data validation and R-package overlap comparison as post-`v0.2.0` evidence. |
| Bayesian priors add responsibility | Weak priors can stabilize sparse designs but can also drive results. | Require prior predictive checks, prior-scale grids, and prior/likelihood power-scaling sensitivity before focal generalized claims. |
| HMC diagnostics are more demanding than MML/JML output | Users can mistake posterior intervals for valid inference even when chains fail. | Promote rank-normalized R-hat, bulk/tail ESS, divergence, max-depth, E-BFMI, block-level diagnostics, and failure flags to first-class report sections. |
| Fewer standard practitioner tables than Facets/TAM | FACETS-trained users expect familiar fit, separation, map, and rater tables. | Add a compatibility layer for FACETS-style MNSQ/ZSTD labels, separation/reliability summaries, fair averages, rater diagnostics, and Wright-map rows while keeping Bayesian caveats explicit. |
| Visualization and examples are less mature | R packages benefit from many tutorials and familiar plotting workflows. | Stabilize plotting-data schemas first, then add Makie/AlgebraOfGraphics or recipe-based examples only after the table contract is stable. |
| Real-data evidence is still limited | Simulation recovery does not prove practical usefulness, but real-data validation can obscure whether discrepancies are due to model differences, estimation, or data idiosyncrasy. | Do not make real-data validation a `v0.1.x` or `v0.2.0` release gate. Use compact data only as workflow demonstrations before `v0.2.0`; after `v0.2.0`, compare against R packages first through known-truth simulations, then decide whether real-data validation is mature enough for manuscript claims. |
| Ecosystem migration friction | Existing users have data and scripts built around R or FACETS. | Before `v0.2.0`, provide import/export examples, column-mapping helpers, and report-table schemas. After `v0.2.0`, run simulation comparisons against TAM, mirt, sirt, immer, or Facets only where model targets overlap. |
| Privacy and artifact governance | Rating data can include identifiable people, raters, institutions, tasks, and groups. | Treat raw labels and raw row-level data as sensitive by default. Add anonymized export modes, schema versions, and artifact manifests that say exactly what data were included. |
| Performance is not yet a claim | Julia can be fast, but speed without sampler quality is not useful. | Report ESS/sec, compile/runtime costs, memory, and accuracy against BridgeStan or overlapping software before making performance claims. |

## Prior Research Map

| Area | Key sources | Consequence for the package |
| --- | --- | --- |
| Rasch rating and partial-credit foundations | Andrich's rating-scale formulation defines ordered-category rating structure and threshold interpretation; Masters' partial-credit model generalizes ordered response alternatives item by item; Muraki's generalized partial-credit model adds varying slope/discrimination to PCM. Sources: [Andrich 1978](https://doi.org/10.1007/BF02293814), [Masters 1982](https://doi.org/10.1007/BF02296272), [Muraki 1992](https://eric.ed.gov/?id=EJ452375). | Keep RSM/PCM/MFRM parameterization and threshold constraints separate from generalized discrimination. Do not blur step parameters, thresholds, and discrimination in report labels. |
| Many-facet Rasch measurement | Linacre's MFRM extends Rasch measurement to rater-mediated settings with multiple facets; Facets documentation frames each rating as an interaction of examinee, item/task, rater, and other elements, modeled additively. Sources: [Linacre MFRM book page](https://www.rasch.org/facet.htm), [Facets theory](https://www.winsteps.com/facetman/theory.htm). | The package should remain intelligible to MFRM users: facet maps, severity, fair averages, fit statistics, connectedness, and sparse design warnings remain first-class even as MGMFRM grows. |
| Dichotomous many-facet IRT bridge | Facets documentation presents the dichotomous Rasch model as `log(P/(1-P)) = ability - difficulty`, then extends the same additive structure to many-facet ordinal observations by adding rater severity and other facet elements. Sources: [Facets theory](https://www.winsteps.com/facetman/theory.htm), [Rasch dichotomous fit statistics](https://www.rasch.org/rmt/rmt82a.htm). | For binary outcomes, document MFRM as a many-facet 1PL/Rasch IRT model. For generalized binary MGMFRM, document exactly which terms create a generalized IRT model: Q-masked multidimensional ability, item/dimension discrimination, rater consistency, severity, and any step/intercept terms. |
| Infit/outfit and FACETS fit tables | Rasch fit statistics are conventionally reported as mean-squares with expected value one. Outfit is the average squared standardized residual; infit is information-weighted. Winsteps/FACETS documentation treats outfit degrees of freedom as the observation count and infit degrees of freedom as the information in the observations, with Wilson-Hilferty-style ZSTD approximations. Mean-square cutoffs vary by purpose, sample size, and reviewer convention. Sources: [Winsteps misfit diagnosis](https://www.winsteps.com/winman/misfitdiagnosis.htm), [Facets WHEXACT](https://www.winsteps.com/facetman/whexact.htm), [Rasch MNSQ/ZSTD interpretation](https://www.rasch.org/rmt/rmt162f.htm), [reasonable mean-square ranges](https://www.rasch.org/rmt/rmt83b.htm), [Smith, Schumacker, and Bush 1998](https://pubmed.ncbi.nlm.nih.gov/9661732/), [Mueller 2020](https://link.springer.com/article/10.1186/s40488-020-00108-7). | Separate three outputs: posterior MNSQ intervals for Bayesian diagnostics, optional FACETS-compatible point-estimate MNSQ/ZSTD rows for MFRM user familiarity, and simulation-calibrated posterior predictive checks. Do not apply FACETS ZSTD or degrees-of-freedom formulas to posterior-summarized GMFRM/MGMFRM fit statistics without explicit approximation labels. Treat cutoffs as threshold profiles whose false-positive rate and power must be checked by simulation before they support claims. |
| Rater effects | The MFRM literature distinguishes severity/leniency, centrality/extremity, inconsistency, range restriction, halo, and differential rater functioning. HRM and newer facets models show that rater severity and rater consistency/centrality are separable model targets. Sources: [Patz et al. 2002](https://journals.sagepub.com/doi/10.3102/10769986027004341), [Jin and Wang 2018](https://doi.org/10.1111/JEDM.12191), [Myford and Wolfe references](https://jampress.org/pubs.htm). | Use "rater consistency" for Uto-style `alpha_r`; reserve "discrimination" for item/dimension discrimination unless the docs explicitly name compatibility aliases. Keep DFF as screening evidence until fitted DFF effects have their own model and validation policy. |
| Generalized MFRM | Uto and Ueno propose a generalized MFRM that jointly represents rater severity, rater consistency, rater-specific range restriction/step behavior, and task/item discrimination, estimated with NUT-HMC. Source: [Uto and Ueno 2020](https://link.springer.com/article/10.1007/s41237-020-00115-7). | The GMFRM compiler must expose item discrimination, rater consistency, rater severity, and step/range-restriction blocks with source-equation roles, constraints, priors, and report labels. |
| Multidimensional generalized MFRM | Uto extends generalized MFRM to multidimensional rubric assessment, using a multidimensional GPCM-style ability term, rater consistency, rater severity, item-step effects, fixed `1.7` scaling, and NUT-HMC. Source: [Uto 2021](https://link.springer.com/article/10.1007/s41237-021-00144-w). | Start with confirmatory fixed-Q MGMFRM. Do not expose exploratory dimensions or free rotations until dimension labels, gauge constraints, and posterior summaries are invariant enough for users to interpret. |
| Multidimensional Rasch and polytomous IRT | The MRCML framework generalizes a wide class of Rasch models to multidimensional settings; multidimensional partial-credit/GPCM work gives item/test statistics and MCMC estimation for mixed item formats. Sources: [Adams, Wilson, and Wang 1997](https://journals.sagepub.com/doi/10.1177/0146621697211001), [Yao and Schwarz 2006](https://journals.sagepub.com/doi/10.1177/0146621605284537), [Reckase 2009](https://link.springer.com/book/10.1007/978-0-387-89976-3). | `v0.1.2` can extend fixed-Q dimensionality, but the compiler must treat dimension structure as a design contract, not a loose matrix argument. |
| Q-matrix validation and revision | CDM and MIRT Q-matrix literature treats the Q matrix as a substantive design object whose misspecification can be empirically diagnosed but not safely edited by a single automatic rule. Sources: [Chiu 2013](https://journals.sagepub.com/doi/10.1177/0146621613488436), [de la Torre and Chiu 2016](https://doi.org/10.1007/s11336-015-9467-8), [Chen 2017](https://journals.sagepub.com/doi/10.1177/0146621616686021), [Terzi and de la Torre 2018](https://doi.org/10.21449/ijate.407193), [da Silva et al. 2019](https://doi.org/10.1177/0013164418814898), [Najera et al. 2020](https://journals.sagepub.com/doi/10.1177/0146621620909904). | Keep Q revision as construct review plus simulation evidence. The package can propose local diagnostic candidates, but public automatic Q editing remains blocked until false-add/false-drop rates, sparse-dimension behavior, and impact on focal parameters are calibrated. |
| Existing software | Facets covers unidimensional MFRM; TAM covers unidimensional and multidimensional IRT, GPCM, and multi-faceted Rasch models; mirt covers exploratory and confirmatory MIRT with EM/MHRM-style estimation. Sources: [Facets](https://www.winsteps.com/facets.htm), [TAM CRAN docs](https://cran.r-project.org/web/packages/TAM/refman/TAM.html), [Chalmers 2012 mirt](https://www.jstatsoft.org/article/view/v048i06). | The package's defensible niche is Bayesian, source-audited, rater-mediated MGMFRM workflow in Julia, with reproducible diagnostics and reporting. Do not claim the ecosystem lacks MFRM or MIRT tools. |
| Bayesian computation | NUTS reduces hand tuning relative to HMC but does not remove the need for diagnostics; rank-normalized R-hat/ESS improve convergence assessment; SBC is useful for validating Bayesian implementations. Sources: [Hoffman and Gelman 2014](https://jmlr.org/papers/v15/hoffman14a.html), [Vehtari et al. 2021](https://doi.org/10.1214/20-BA1221), [Talts et al. 2018](https://arxiv.org/abs/1804.06788). | Every promotion must record divergences, max-depth hits, E-BFMI, R-hat, bulk/tail ESS, direct-constraint failures, SBC/recovery evidence, and failure modes by parameter block. |
| Bayesian model checking and comparison | Posterior/prior predictive checks test data features under replicated data; PSIS-LOO and WAIC estimate pointwise predictive accuracy, with PSIS-LOO more robust than WAIC in finite weak-prior/influential-observation settings. Sources: [Stan predictive checks](https://mc-stan.org/docs/stan-users-guide/posterior-predictive-checks.html), [Vehtari, Gelman, and Gabry 2017](https://link.springer.com/article/10.1007/s11222-016-9696-4). | Generalized reports should emphasize predictive checks, calibration, and prediction target statements. Model weights and superiority claims remain blocked until Pareto-k/refit evidence and prediction-target policy are explicit. |
| Prior and likelihood sensitivity | Power-scaling sensitivity analysis perturbs the prior or likelihood by an exponent and uses importance sampling to estimate how posterior summaries change. It can diagnose prior-data conflict or likelihood noninformativity, but unstable importance weights require explicit warnings or refits. Source: [Kallioinen et al. 2024](https://link.springer.com/article/10.1007/s11222-023-10366-5). | Treat weakly informative priors as defaults that must be checked, not as automatic protection. Reports should state prior scales, prior-predictive implications, prior/likelihood power-scaling shifts, weight-ESS or Pareto-k diagnostics, and refit requirements when reweighting is unstable. |
| Free correlations and rotations | Correlation matrices should be parameterized by Cholesky factors in Bayesian computation; unconstrained factor/loadings models suffer rotation, sign, and permutation invariance that can make loading means and intervals meaningless without constraints or post-processing. Sources: [Stan correlation matrix distributions](https://mc-stan.org/docs/functions-reference/correlation_matrix_distributions.html), [Stan factor loading notes](https://mc-stan.org/docs/2_18/stan-users-guide/loading-matrix-for-factor-analysis.html), [Papastamoulis and Ntzoufras 2022](https://link.springer.com/article/10.1007/s11222-022-10084-4). | `v0.1.3` and `v0.1.4` are decision/design releases, not automatic exposure releases. Free correlation and exploratory loading require separate gauge, prior, reporting, and post-processing contracts. |

## Version Roadmap

### v0.1.1: Fixed-Q Confirmatory MGMFRM Refinement

**Goal:** make the existing fixed-Q guarded MGMFRM path
auditable and hard to overinterpret.

**Research basis:** Uto's MGMFRM is confirmatory in spirit for rubric
dimensions and uses NUT-HMC; Bayesian workflow literature requires diagnostics,
predictive checks, and validation evidence before claims.

**Implementation work:**

- `q_matrix_validation` now strengthens the current fixed-Q
  path: binary-mask schema checks, empty dimensions, empty item rows, duplicate
  or aliased columns, fixed cross-loading policy, dimension/facet subgraph
  coverage, and item blocks that cannot identify positive interpreted loadings.
- Add a rating-design audit section: structural versus accidental missingness,
  disconnected components, anchor coverage, repeated ratings, optional
  time/order fields, sparse person-rater-item blocks, and warnings that
  nonignorable rater assignment is not corrected by the current likelihood.
- Dimension labels now flow through `mfrm_spec`, `model_manifest`,
  `constraint_table`, `fit_metadata`, parameter/direct-posterior names,
  `fit_report`, and exported report-table rows.
- `fit_report(...).q_matrix` now records the fixed gauge for MGMFRM: fixed
  identity latent correlation, standard-normal ability scale, positive
  interpreted loadings, fixed `1.7` scaling, rater consistency/product
  constraints, rater severity location constraints, item-step constraints, and
  blocked alternatives such as exploratory Q or free latent correlation.
- `fit_report` now includes a prior-policy section: public MFRM defaults use weakly
  informative independent normal priors on identified parameters; guarded
  GMFRM/MGMFRM defaults use independent normal priors on raw unconstrained
  coordinates, log-discrimination, and log-consistency blocks; direct-scale
  generalized priors remain disabled until a log-Jacobian policy is implemented.
- `fit_report` now includes pooling-policy rows: v0.1.x generalized fits use independent priors by
  default; hierarchical facet priors and partial-pooling claims remain blocked
  unless a later gate documents estimands, hyperpriors, shrinkage diagnostics,
  and sensitivity.
- Standardize generalized diagnostics across `GMFRMFit` and `MGMFRMFit`:
  divergences, max-depth hits, E-BFMI availability, rank-normalized R-hat,
  bulk/tail ESS, direct-constraint failures, pointwise log-likelihood
  finiteness, and parameter-block pass/fail flags. Until rank-normalized
  diagnostics are implemented, reports must label the current classical split
  R-hat and autocorrelation ESS as provisional diagnostics.
- Add a binary-response interpretation note to the docs and reports: the
  two-category MFRM is a many-facet Rasch/1PL IRT model, while binary
  GMFRM/MGMFRM variants with item discrimination, rater consistency, or
  multidimensional Q-masked loadings are generalized IRT models rather than
  strict Rasch models.
- Add a FACETS-fit compatibility note for `fit_stats`: posterior infit/outfit
  intervals remain the default Bayesian diagnostic; optional FACETS-style
  rows should record the residual formula, `outfit_df = n_obs`,
  `infit_information`, any Wilson-Hilferty/ZSTD approximation, and whether the
  row is point-estimate, draw-wise, or posterior-predictive. Do not treat
  FACETS degrees of freedom as exact for posterior-summarized generalized
  fits.
- Add category-functioning report rows: observed category use by rater/item/
  dimension, skipped or sparse categories, posterior step/threshold
  uncertainty, predictive category replication, and diagnostic-only category
  collapsing flags.
- Make posterior predictive and calibration rows explicit about whether they
  use direct GMFRM/MGMFRM draws or the minimal MFRM predictive path.
- Add power-scaling sensitivity rows for prior and likelihood powers around
  one, including direct-parameter shifts, log-prior/log-likelihood shifts,
  weight effective sample size, and an explicit refit/Pareto-k follow-up flag
  when importance reweighting is unstable.
- Add model-comparison policy rows that name the prediction target, scoring
  rule, candidate set, influential-row diagnostics, and whether exact refit or
  K-fold evidence is required before interpretation.
- Stabilize plotting-data schemas for diagnostics, calibration, PPC, rater
  diagnostics, rater homogeneity, DFF screening, Q-matrix validation, and local
  model-comparison evidence without depending on a plotting backend.
- Add rater homogeneity summaries based on posterior contrasts: severity
  differences on the latent scale and rater-consistency ratios on the log scale,
  with ROPE probabilities, HDI or explicitly labelled central intervals, and
  practical-equivalence classifications.
- Keep Bayes factors out of the default workflow. If implemented internally,
  they must be limited to preregistered contrasts with explicit prior
  sensitivity and must not replace ROPE/HDI posterior-contrast summaries.
- Keep DFF/bias effects validation-only: report sparse, empty, and confounded
  cells; include grouped PPC/DFF screening rows; and keep fitted DFF effects
  blocked.
- Add small and medium BridgeStan comparisons for the guarded fit target, not
  only source-equation log-density fixtures.
- Keep compact data examples as workflow demonstrations only. Do not use
  real-data validation or R-package overlap comparison as a `v0.1.1` release
  gate.
- Thread the `evidence_artifact_schema_policy` contract through fit reports and
  evidence bundles; extend bundle/export manifests where a downstream workflow
  needs file-level policy checks.

**Implementation order and runtime policy:**

- Finish the remaining fixed-Q MGMFRM initialization fallback reporting and
  invariance checks first.
- Standardize generalized diagnostics before adding more report sections,
  because predictive, calibration, category-functioning, and interpretation
  rows should share the same diagnostic vocabulary.
- Add predictive-path, calibration, category-functioning, FACETS-compatibility,
  model-comparison-policy, and rater-homogeneity rows after the report shape is
  stable.
- Finish evidence-artifact governance and versioned evidence bundles after the
  report schemas settle.
- Use staged Julia verification: load checks and targeted fixture scripts for
  small edits, low-level fixture regeneration before archive/review fixtures,
  fixture SHA scans before full tests, and full `Pkg.test()` only for milestone
  slices, supported-version release checks, and final tag candidates.

**Exit gate:**

- The guarded fixed-Q MGMFRM example runs with small sampler settings.
- `fit_report` explains the gauge, dimensions, diagnostics, predictive path,
  prior policy, sensitivity evidence, model-comparison policy, visualization
  data contract, rater homogeneity summaries, DFF screening status, and blocked
  claims.
- `release_scope_summary(; include_evidence = true)` includes a
  `v0.1.1_generalized_refinement` row and keeps broad generalized claims
  blocked.

### v0.1.2: Fixed-Q Dimensionality and Q Validation Expansion

**Goal:** remain confirmatory and fixed-Q, but support a broader fixed-Q design
contract than the original compact candidate.

**Research basis:** MRCML and multidimensional partial-credit work show that
multidimensional polytomous models are viable, but dimensional structure and
item statistics must be explicit. Existing MIRT tools distinguish confirmatory
and exploratory models.

**Implementation work:**

- Generalize the fixed-Q compiler to `dimensions >= 2` under strict
  confirmatory rules, while keeping default examples small.
- Add Q-matrix schema checks: binary/nonnegative mask, named dimensions,
  minimum items per dimension, optional cross-loading policy, rank diagnostics,
  dimension connectedness, and sparse cell warnings.
- Extend empirical Q-matrix simulation fixtures with known-truth false-add,
  false-drop, weak-dimension, duplicate-column, sparse-anchor, and rater-method
  noise scenarios. Record false public-promotion rate separately from local
  candidate-detection rate.
- Extend rating-design audits to higher-dimensional fixed-Q designs, including
  dimension-specific anchor coverage, planned missingness, repeated ratings,
  and time/order metadata where present.
- Add dimension-wise ability summaries, loading summaries, expected-score
  summaries, calibration rows, and PPC rows.
- Compare fit-threshold profiles rather than promoting a single cutoff:
  strict Bayesian workflow, screening workflow, lenient Rasch exploration,
  sample-size-sensitive mean-square screening, and heldout-predictive-first
  profiles.
- Compare existing-model indicators with MGMFRM indicators in every threshold
  scenario: MFRM infit/outfit, posterior predictive discrepancies,
  calibration error, WAIC/LOO or heldout ELPD, direct parameter shifts, and
  decision reversals.
- Extend power-scaling sensitivity to higher-dimensional fixed-Q designs, with
  block-wise prior/likelihood sensitivity for abilities, rater consistency,
  item/dimension discrimination, and item-step effects.
- Decide whether PSIS/Pareto-k or refit-based fallback is required for unstable
  sensitivity weights before sensitivity rows can pass release gates.
- Extend rater homogeneity summaries to fixed-Q multidimensional reports,
  including dimension-specific severity/consistency contrasts where the
  parameterization supports them.
- Add first backend-specific visualization recipes only after plot-data schemas
  are stable; recipes should cover Q matrices, diagnostic heatmaps, rater maps,
  PPC/calibration panels, and model-comparison uncertainty.
- Add simulation fixtures for 2D, 3D, and at least one sparse higher-dimensional
  fixed-Q case, including recovery and diagnostics by dimension.
- Add explicit failure modes when higher-dimensional fixed-Q designs are weakly
  identified under the observed rating graph.

**Exit gate:**

- Fixed-Q higher-dimensional examples pass source, AD, HMC, recovery, and
  report-shape tests.
- Fit-threshold profiles are calibrated by simulation and remain labelled as
  profiles; no single universal cutoff is promoted.
- Existing MFRM fit indicators and MGMFRM predictive/report indicators are
  compared under matched simulation conditions before threshold claims are
  used in public wording.
- Broad exploratory MGMFRM remains blocked.

### v0.1.3: Free Latent Correlation Decision

**Goal:** decide whether free latent correlations are ready for guarded
experimental exposure.

**Research basis:** Uto's current MGMFRM target uses a simple ability scale; free
correlation adds a covariance structure whose parameterization should use
Cholesky/LKJ-style priors. Free correlations can also change dimension
interpretation in sparse data.

**Implementation work:**

- Implement an internal candidate with Cholesky-factor latent correlation and
  an LKJ-style prior policy.
- Add prior predictive checks for plausible latent correlations and score
  distributions.
- Compare fixed-identity and free-correlation variants on source fixtures and
  simulated fixed-Q data. Any compact data example is a workflow smoke test,
  not validation evidence.
- Add reporting rows that separate dimension means/scales, correlations,
  loadings, and predictive fit.
- Add a decision artifact with three possible outcomes:
  `keep_blocked`, `internal_promotion_candidate`, or `experimental_public`.

**Exit gate:**

- Free correlation is exposed only if posterior diagnostics, sensitivity, and
  interpretability are stable under predeclared designs.
- If correlations are prior-dominated or unstable, the feature remains internal
  and the release records the blocker.

### v0.1.4: Exploratory Loading and Rotation Policy

**Goal:** design the exploratory loading path and rotation/post-processing
policy before exposing exploratory MGMFRM as an ordinary API.

**Research basis:** MIRT and Bayesian factor-analysis literature both show that
exploratory loadings have rotation, sign, and permutation invariance. Posterior
means and intervals for loadings can be meaningless without a gauge or
post-processing policy.

**Implementation work:**

- Define candidate exploratory loading regimes:
  lower-triangular constraints, target rotation, sparse priors with
  post-processing, or simple-structure restrictions.
- Build internal fixtures showing where loading summaries are invariant and
  where they are not.
- Add rotation/sign/permutation diagnostics for MCMC draws.
- Define report language for exploratory loadings that distinguishes predictive
  validity from construct interpretation.
- Compare against mirt-style exploratory/confirmatory expectations on small
  fixtures where feasible.

**Exit gate:**

- `v0.1.4` can ship a design document, internal fixtures, and validation
  artifacts.
- Public exploratory fitting remains blocked unless the package can prevent
  invalid loading summaries by construction.

### v0.2.0: Generic MGMFRM Stable-Public Candidate

**Goal:** make a generic MGMFRM surface a stable-public candidate, not merely a
larger experimental path.

**Research basis:** the stable surface must reconcile Uto-style rater-mediated
MGMFRM, multidimensional polytomous IRT, rater-effect modeling, and Bayesian
workflow validation.

**Candidate scope:**

- fixed-Q confirmatory MGMFRM with expanded dimension counts and Q structures;
- optional free latent correlation only if `v0.1.3` passed;
- exploratory loading only if `v0.1.4` produced a defensible gauge or
  post-processing contract;
- generalized rater consistency, rater severity, item/dimension discrimination,
  item-step effects, and sparse-design validation;
- an explicit pooling policy for facet blocks: independent priors, optional
  hierarchical priors, or blocked partial pooling, with shrinkage diagnostics
  if hierarchical priors are exposed;
- full fit/report/cache/reproduction support.

**Stable-public gate:**

- Source equations, constraints, transforms, priors, and direct report labels
  are machine-readable.
- BridgeStan/source fixtures cover representative scalar GMFRM, fixed-Q
  confirmatory MGMFRM, higher-dimensional fixed-Q MGMFRM, and any free
  correlation/exploratory variants that are exposed.
- Simulation-based calibration or equivalent recovery evidence passes for
  predeclared complete, sparse, weakly connected, and misspecified designs.
- Compact workflow demonstrations can run end to end, but real-data validation
  and R-package overlap comparisons are not required for `v0.2.0` completion.
- Rating-design audits, category-functioning diagnostics, pooling-policy rows,
  and artifact-governance metadata are present for every stable-public surface.
- Unsupported or weakly identified designs fail with actionable messages.
- Model-weight, sparse-superiority, and DFF-causality claims remain absent
  unless separate evidence gates are added.

### Post-v0.2.0: R Simulation Comparison and External Validation

**Goal:** after the generic MGMFRM surface is complete enough to be stable
public, evaluate it against mature R software under known-truth simulation
conditions before making external superiority or real-data validation claims.

**Comparison policy:**

- Compare only overlapping model targets. Candidate comparisons include
  Facets/TAM-style MFRM, TAM-compatible GPCM or multi-facet Rasch cases,
  mirt-style fixed-Q MIRT cases, and sirt/immer rater-effect cases where the
  parameterization can be matched.
- Use simulation first, not real data first. Known truth should define
  parameter recovery, interval coverage, ranking stability, calibration,
  rater-effect recovery, DFF-screening behavior, and failure modes.
- Report both statistical and computational quantities: bias, RMSE, coverage,
  calibration, convergence/failure rates, runtime, memory, and ESS/sec when
  applicable.
- Treat non-overlapping models as non-comparable. Differences caused by
  priors, estimators, link functions, parameter constraints, or prediction
  targets must be labelled before any interpretation.
- Decide real-data validation only after the simulation comparison explains
  where the Julia and R workflows agree, differ, or answer different
  questions.

## Promotion Rules

| Level | Meaning | Required evidence |
| --- | --- | --- |
| `blocked` | Planned or unsupported. | Scope docs, validation rejection, no accidental fit path. |
| `internal_fixture` | Likelihood or transform exists only for tests. | Source-equation fixture, stable names, pointwise likelihood checks. |
| `internal_promotion_candidate` | Private target close to fit-ready. | Raw/direct manifests, AD checks, HMC diagnostics, BridgeStan checks. |
| `experimental_public` | Narrow user-facing path with explicit caveats. | Docs, fit artifact, diagnostics, recovery smoke evidence, rejection tests. |
| `stable_public` | Ordinary examples and package claims are supported. | Internal simulation grid, sensitivity checks, reproducible report archive. |
| `external_validated` | Post-`v0.2.0` external validation claims are supported. | Known-truth comparisons against overlapping R-package targets and, only after those comparisons are understood, real-data validation evidence. |

No MGMFRM surface skips a level. The reason is practical: each level answers a
different reviewer objection.

## Red Lines

- Do not call fixed-Q confirmatory MGMFRM "general MGMFRM."
- Do not expose free correlations without Cholesky/LKJ-style parameterization,
  prior predictive checks, and correlation-specific diagnostics.
- Do not expose exploratory loadings until rotation, sign, and permutation
  invariance are handled in reports.
- Do not promote one universal infit/outfit, PPC, calibration, WAIC/LOO, or
  heldout-ELPD threshold without simulation evidence for false alarms, power,
  parameter distortion, and decision reversals.
- Do not report model weights without a prediction target, Pareto-k or refit
  diagnostics, and sensitivity to influential rows.
- Do not treat weakly informative priors as validated until prior predictive
  checks and prior/likelihood power-scaling sensitivity have been reported.
- Do not interpret the observed rating graph as if raters were randomly
  assigned unless the design or assignment model justifies that claim.
- Do not automatically collapse sparse or disordered categories; category
  collapsing flags are diagnostic recommendations requiring a recorded
  analysis decision.
- Do not report partially pooled facet effects as if they were unpooled facet
  locations; label shrinkage estimands and hyperpriors explicitly.
- Do not export raw identifiers or row-level rating data in public artifacts by
  default.
- Do not present DFF screening rows as proof of unfairness.
- Do not use one successful dataset as evidence of sparse-design superiority.
