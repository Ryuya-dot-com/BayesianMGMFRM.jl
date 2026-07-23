# MGMFRM Research Roadmap

This roadmap records the research basis and implementation sequence for moving
`BayesianMGMFRM.jl` from the current guarded fixed-Q MGMFRM experiment toward a
stable public generalized MGMFRM surface. The governing principle is simple:
the package should not expose a broader model surface until identification,
diagnostics, validation, and reporting are at least as clear as the likelihood
equation.

## Scope Decision

The `v0.1.x` sequence records `v0.1.1` as completed and continues with:

- `v0.1.1`: completed fixed-Q confirmatory MGMFRM refinement by strengthening
  execution, diagnostics, reporting, and validation for the existing guarded
  path.
- `v0.1.2`: next, stay fixed-Q and confirmatory, but expand dimensionality,
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
  non-finite likelihood checks. Guarded generalized fits gate both raw
  unconstrained and direct constrained diagnostics, and cache identity includes
  the versioned diagnostic contract.
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
  public goal is reproducible report data, not publication graphics. Public
  pages state evidence and scope in reader-facing language; reference-manager
  metadata, private paths, placeholders, temporary review instructions, and
  execution-diary prose remain outside release text.
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
| Convergence diagnostics | Rank-normalized split R-hat, bulk ESS, and tail ESS are the primary quality fields. Classical `rhat`/`ess` and the minimum available `e_bfmi` remain compatibility outputs. E-BFMI coverage counts and `e_bfmi_complete` show whether every chain supplied a finite value. Odd-draw rank/fold/tail operation order and all-valid-lag ESS follow Stan/posterior semantics. | Require both raw unconstrained and applicable direct constrained generalized rows to pass. Preserve zero-raw-dimension coordinates as non-gated `:structurally_fixed` rows, keep reconstructed-but-varying coordinates gated, require complete-chain E-BFMI before applying its threshold, preserve the versioned cache contract, and validate the modern fields in every promotion artifact. |
| Model comparison | WAIC, raw LOO, PSIS-LOO, K-fold, and shared-plan refit comparison rows exist. | The `v0.1.1` scope kept comparison rows diagnostic; prediction-target statements, Pareto-k/refit or K-fold follow-up, and no model-weight/superiority language remain required. |
| Visualization | The package returns plotting-ready rows for recovery, calibration, PPC, threshold maps, coverage matrices, rater overlap, and Wright maps. | The `v0.1.1` plan targeted plot-data schema and documentation-example stabilization; unfinished work continues under `v0.1.2` or later, with backend-specific recipes deferred until the report data contract is stable. |
| Category functioning | Rating-scale and partial-credit interpretations can fail when categories are skipped, disordered, sparse, or used differently by raters. | Add category-functioning rows that separate observed category use, posterior threshold/step uncertainty, predictive category replication, and any category-collapsing recommendation. Recommendations should be diagnostic, not automatic data editing. |
| Missingness and rater assignment | MFRM assumes the observed rating graph can support the intended facet comparisons; nonrandom assignment, planned missingness, and time/order effects can change what is identifiable. | Add rating-design review rows: structural missingness, accidental missingness, disconnectedness, anchor coverage, repeated ratings, time/order fields, and warnings that current models do not correct nonignorable assignment unless an explicit assignment model is introduced. |
| Local independence and clustered ratings | The likelihood treats observed rows as conditionally independent. LD0a supplies response/testlet identifiers, a pre-fit design audit, draw-specific residuals, and a frozen estimand contract; LD0b adds report-only pair and multiplicity references; LD1a adds an independent 22-scenario known-truth generator and structural preflight; LD1b0 freezes the scorer and denominator-preserving aggregation protocol; LD1b1 preflights and authorizes the 30-replication pilot execution protocol, and its MCMC-free batch harness dry run checks orchestration without running the pilot. Applicability remains testlet-specific, and `task` is metadata rather than a fitted testlet term. | Materialize and pin the canonical single-job executor, pass bounded smoke, add a completed-attempt seal, and pass interrupted-attempt recovery review before executing the authorized pilot with the rank-normalized R-hat and bulk/tail ESS gate. Freeze the study-local operating rules and either 50 or 100 evaluation replications, and run the separately seeded evaluation before adding any diagnostic decision label, fitting a testlet extension, or interpreting temporal dependence. |
| Temporal rater process and order confounding | The current `FacetData` contract stores an optional categorical `occasion` field, but it does not encode within-rater sequence, timestamps, active duration, breaks, repeated benchmark-response identity, or assignment reason. A late shift in examinee case mix can therefore be mistaken for rater drift. | Before any dynamic-severity fit surface is exposed, define a process-data contract and complete a known-truth stress test that crosses true drift, ability/order composition, temporal benchmark placement, assignment, and rating-graph sparsity. Keep drift claims blocked when the design cannot separate rater change from changing case mix. |
| Binary responses and multi-facet IRT | The current MFRM family includes two-category responses as the dichotomous Rasch special case with additional facet terms. Guarded generalized paths add discrimination/consistency terms that move beyond strict Rasch measurement. | Document the binary bridge explicitly: MFRM is a many-facet one-parameter logistic IRT model; GMFRM/MGMFRM with item discrimination, rater consistency, or multidimensional Q-masked loadings should be labelled generalized or 2PL/GPCM-like, not strict Rasch. |
| Infit, outfit, and FACETS degrees of freedom | `fit_stats` returns posterior infit/outfit mean-square summaries for minimal MFRM fits. The separate `facets_report` / `facets_compatibility_stats` API now returns unit-weighted posterior-mean plugin rows with Wright--Masters fourth-moment infit/outfit df, capped Wilson--Hilferty ZSTD, and explicit approximation labels; generalized fits are rejected. | Keep posterior infit/outfit as the default Bayesian residual diagnostic. Retain the separate MFRM/RSM/PCM-only compatibility surface, and require simulation calibration before considering any experimental generalized extension. |
| DFF and bias | DFF is validation and screening only: sparse/empty/confounded cells, grouped PPC rows, and posterior predictive interaction residuals. | The `v0.1.1` scope kept fitted DFF effects blocked and used DFF rows for triage, design repair, and sensitivity planning, not unfairness or causal claims. |
| Rater homogeneity | Posterior summaries support probability of direction and ROPE for individual parameters; pairwise rater contrasts are not yet first-class. | Add rater contrast summaries for severity and log-consistency using ROPE and HDI/credible intervals. Treat Bayes factors as optional and blocked from the default workflow until prior sensitivity is documented. |
| Artifact schemas and data governance | Report bundles exist, but broad use requires stable schemas and clear handling of raw rating data. | Version report-table schemas, include manifest compatibility checks, and make raw-data inclusion opt-in. Public artifacts should prefer anonymized or hashed identifiers unless the user explicitly exports raw labels. |

## Literature-Informed Priority Update

The July 2026 literature review sharpens the roadmap rather than broadening the
public API immediately. Public artifacts record bibliographic identifiers and
source URLs rather than reference-manager metadata.

| Literature cluster | What is now better supported | Roadmap consequence |
| --- | --- | --- |
| Multidimensional Rasch and MRCML foundations | Adams, Wilson, and Wang's MRCML paper, ConQuest documentation, Reckase's MIRT text, and multidimensional partial-credit work make the fixed-Q dimensional contract the natural bridge from Rasch models to MGMFRM. | Treat `v0.1.2` as a confirmatory multidimensional Rasch/MGPCM expansion, not as exploratory discovery. Dimension labels, constraints, and Q masks must be inspectable before broader fitting claims. |
| Uto-style GMFRM/MGMFRM | Uto and Ueno's GMFRM and Uto's MGMFRM provide the direct rater-mediated target: severity, consistency, item/task discrimination, ordered categories, fixed scaling, and Bayesian HMC estimation. | Keep the current scalar GMFRM and fixed-Q MGMFRM paths guarded until report rows can explain each source-equation block, prior, transform, and diagnostic failure. |
| Local dependence and testlet models | Bayesian random-effects, Rasch/partial-credit testlet, bifactor, covariance, rater-bundle, and multiple-rating models establish several non-equivalent explanations for clustered responses. | Diagnose dependence before choosing a model. Compare person-by-testlet, rater-by-response halo, rater-by-task severity, omitted multidimensionality, and drift under known truth; do not treat one scalar testlet effect as a generic repair. |
| Q-matrix validation | de la Torre and Chiu, Chiu, Chen, Terzi and de la Torre, Najera et al., Madison and Bradshaw, and da Silva et al. show that Q matrices are fallible design objects, but empirical revisions need error control. | Keep empirical Q revision local and diagnostic. Simulations must include false-add, false-drop, weak-dimension, duplicate-column, and sparse-anchor cases before any public Q-revision helper is promoted. |
| Fit statistics and threshold uncertainty | Wright/Linacre-style mean-square ranges are useful screening heuristics, but Smith/Schumacker/Bush and Mueller-style critiques make fixed universal cutoffs unsafe. Bayesian LOO/WAIC and R-hat/ESS literature adds a separate computation and prediction layer. | Treat thresholds as named profiles, not defaults. Compare existing MFRM infit/outfit with MGMFRM PPC, calibration, WAIC/LOO, heldout ELPD, and parameter-shift rows under simulation before allowing threshold-based claims. |
| Existing software and practice | Facets, ConQuest, TAM, mirt, sirt, immer, and Stan/brms already cover important adjacent surfaces. | The package's niche remains source-audited Bayesian many-facet/MGMFRM workflow, not generic IRT breadth. External comparisons should start with known-truth simulations only after the stable-public candidate exists. |

## Rater-Process, Design, and Decision Research Horizon

The broader research objective is not to turn one likelihood into an
unrestricted mega-model. It is to connect four auditable layers: measurement,
rater process, assignment design, and decision support. The primary literature
already establishes most component models, but it does not establish their full
integration under a fixed-Q multidimensional rater model. This section separates
direct precedent from the package's prospective research contribution; none of
these rows broadens the current public API.

### Prior-Research Map and Novelty Boundary

| Research track | Direct primary precedent | What is established | Prospective package contribution |
| --- | --- | --- | --- |
| Local dependence and testlet effects | [Bradlow, Wainer, and Wang 1999](https://doi.org/10.1007/BF02294533), [Wang and Wilson 2005](https://doi.org/10.1177/0146621604271053), and [Wang, Bradlow, and Wainer 2002](https://doi.org/10.1177/0146621602026001007) develop random-effects testlet models; [Li, Bolt, and Fu 2006](https://doi.org/10.1177/0146621605275414), [DeMars 2006](https://doi.org/10.1111/j.1745-3984.2006.00010.x), and [Fox, Wenzel, and Klotzke 2021](https://doi.org/10.3102/1076998620941204) compare bifactor or covariance alternatives and boundary behavior. | Shared person-by-testlet variation can model positive within-testlet association, but alternative parameterizations need not be empirically distinguishable in weak designs. | Build a design-audited scalar testlet candidate and a mechanism-confusion stress grid before GMFRM/MGMFRM integration; use cluster-heldout prediction and explicit null-boundary policy. |
| Rating bundles and halo | [Wilson and Hoskens 2001](https://doi.org/10.3102/10769986026003283) model rater bundles, [Wang and Wilson 2005](https://doi.org/10.1177/0146621605276281) develop a random-effects facet model, and [Wang, Su, and Qiu 2014](https://doi.org/10.1111/jedm.12045) model local dependence among multiple ratings. | Common response content, common raters, and repeated ratings can create different dependence structures even when marginal severity is similar. | Separate rater-by-response halo from person-by-testlet performance and rater-by-task severity using both within-rater response repetition and independent rater overlap; criterion splitting helps only when it preserves both forms of replication. |
| Dynamic rater severity and rating order | [Uto 2023](https://doi.org/10.3758/s13428-022-01997-z) links time-specific rater severity with a first-order Markov process; [Huang 2023](https://doi.org/10.1177/01466216231174566) models systematic and stochastic order effects with rater-specific change points. | Dynamic unidimensional MFRM/MF-IRT parameter recovery and empirical drift monitoring have direct precedents. | Join fixed-Q multidimensional ability with time-varying severity or consistency, while testing whether changing examinee case mix is falsely absorbed as drift. The reviewed primary literature does not provide this full integration. |
| Rating time and rater speed | [Jin and Eckes 2024](https://doi.org/10.3758/s13428-023-02259-2) jointly model ordinal ratings and rating times with examinee ability/time intensity and rater severity/centrality/speed. | A static score--rating-time facets model has simulation and essay-data evidence. | Add within-rater learning, fatigue, breaks, and correlated severity--speed innovations only after the static joint model passes recovery and design gates. |
| Text length and process data | [Fleckenstein et al. 2020](https://doi.org/10.3389/fpsyg.2020.562462) show that text length can affect writing judgments; [Guo et al. 2018](https://doi.org/10.1111/jedm.12172) link keystroke and pause features to writing outcomes. | Response length is a potentially construct-relevant and rater-dependent feature, not a neutral exposure by default. | Keep ordinal score, count-rate, and process submodels distinct: use a log-word-count offset only for a defensible count exposure, and investigate an ordinal/count/time joint model rather than forcing an offset into the ordinal MFRM. |
| Hierarchical rater consensus | [Patz et al. 2002](https://doi.org/10.3102/10769986027004341) introduce the Hierarchical Rater Model for latent consensus, severity, and consistency; signal-detection extensions add rater precision and decision criteria. | HRM is an established alternative model family for separating a latent ideal rating from the observed rater process. | Provide comparable posterior-contrast and predictive-agreement contracts across MFRM/GMFRM and an eventual fixed-Q or dynamic HRM, rather than treating severity equivalence as score agreement. |
| Bayesian G-study and D-study | [Jiang and Skorupski 2018](https://doi.org/10.3758/s13428-017-0986-3) develop Bayesian multivariate generalizability theory; [Wind, Jones, and Grajeda 2023](https://doi.org/10.1177/01466216231182148) compare G theory and MFRM under sparse rating designs. | Bayesian variance-component uncertainty and sparse-design comparisons have direct precedents. | Use posterior predictive D-studies to compare rater counts, task counts, overlap, benchmark burden, classification error, and cost while respecting rating-graph connectivity. |
| Rater linking and assignment design | [DeMars, Shapovalov, and Hathcoat 2023](https://commons.lib.jmu.edu/gradpsych/63/) compare rotating, fixed, random-pair, and common-linking-set designs; [Hombo, Donoghue, and Thayer 2001](https://doi.org/10.1002/j.2333-8504.2001.tb01847.x) compare complete, nested, and spiral assignment; [Wind and Jones 2018](https://doi.org/10.1177/0013164417703733) study linking-set size in sparse networks; and [Uto 2021](https://doi.org/10.3758/s13428-020-01498-x) varies common raters and tasks for performance-test linking. | Connectivity alone is insufficient: topology, link strength, assignment, severity dispersion, and the range represented in the linking set affect empirical uncertainty and bias. | Test the existing static APIs over materialized linking-response fractions and nonrandom assignment before using the same assignment skeletons for a dynamic model. Do not treat a universal anchor percentage as established by this literature. |
| Mixture and IRTree rater strategies | [Huang 2025](https://doi.org/10.1177/01466216251333578) uses a mixed IRTree to distinguish rubric-guided and preference-influenced judgment processes. | Latent rater-strategy heterogeneity can be represented rather than forced into one severity parameter. | Test time-varying strategy classes, dimension-specific strategies, and their separation from severity/consistency drift after simpler dynamic models are identified. |
| DFF and fairness | The [Dual DRF Facets Model](https://doi.org/10.1177/00131644211043207) jointly represents differential severity and centrality; sparse-design studies show that DRF sensitivity depends on assignment structure. | Severity, centrality, and group-specific rater effects have direct model and simulation precedents. | Add dimension-specific posterior ROPE contrasts, decision-impact probabilities, hierarchical multiplicity control, and assignment-sensitivity analysis without turning a detected interaction into a causal unfairness claim. |
| Adaptive monitoring and second scoring | [Wang et al. 2017](https://doi.org/10.1177/0146621616672855) select validity essays by D-optimal or Fisher-information criteria and recover rater parameters with fewer monitoring essays. | Information-adaptive rater monitoring is feasible. | Extend from monitoring-rater information to posterior expected-loss decisions about whether an operational response needs another rating and which rater should provide it, subject to fairness, cost, and connectivity constraints. |
| Real-time quality control | [Myford and Wolfe 2009](https://doi.org/10.1111/j.1745-3984.2009.00088.x) monitor accuracy and category use over time; earlier real-time feedback work shows that operational intervention and contamination must be designed explicitly. | Sequential monitoring indicators and operational feedback have precedents. | Predeclare posterior alarm rules, false-alarm calibration, intervention effects, and cluster-level contamination controls before exposing any live warning workflow. |
| Human and automated raters | [Uto and Aramaki 2024](https://doi.org/10.3758/s13428-024-02485-2) use neural automated essay scoring for IRT linking; [Mizumoto and Eguchi 2024](https://doi.org/10.1016/j.rmal.2024.100133) compare ChatGPT-4.0 with human raters using MFRM; [Xiao, Patz, and Wilson 2026](https://doi.org/10.1111/bmsp.70034) study human--machine rater configurations and scoring design. | Automated systems can be treated as fallible raters or linking devices, and hybrid reliability depends on bias structure and design. | Treat human and machine outputs symmetrically as uncertain observations; model system version, prompt, run, and update drift as facets; never use an automated score as an unquestioned truth anchor. |

The clearest novelty boundary is therefore the intersection of fixed-Q
multidimensional measurement, time-varying rater behavior, nonrandom order or
assignment, and temporally distributed benchmark responses. Each component has
precedent; the joint identification and decision workflow does not yet have the
same evidence base.

### Existing-API Design-Robustness Stress Test

The assignment problem is not confined to a future dynamic model. The public
MFRM fit and the guarded scalar GMFRM and fixed-Q MGMFRM fits must first show
known-truth recovery under the sparse designs for which they may be used.
Existing evidence does not yet answer that question completely:

| Existing asset | What it establishes | What it does not establish |
| --- | --- | --- |
| `simulation_grid` | A reproducible eight-axis planning schema. | It does not simulate, fit, or materialize linking responses. In particular, changing `anchor_size` does not change the planned rating count. |
| Scalar GMFRM sparse-pathology fixture | The guarded fit and predictive APIs return finite results for three small connected sparse patterns. | It does not cross ability-dependent assignment, omitted order effects, common-linking-set fraction, or repeated-replication coverage. Its short-chain thresholds are computational smoke criteria. |
| Fixed-Q MGMFRM sparse-recovery fixture | The guarded fixed-Q path runs on three small connected sparse patterns with named recovery rows. | It does not estimate robustness to case-mix assignment, linking-set amount or range, or unmodeled order dependence. |
| Existing-API design stress dry run | Twenty-four MFRM/GMFRM/MGMFRM model-design cells compile or reject as planned; 21 paired well-specified/omitted-order-effect datasets, fixed/additive budgets, achieved metrics, six pure row-permutation checks, and three same-event C2P placement checks are materialized without MCMC. A fail-closed repeated recovery/coverage scorer and response-free 50-replication contract preflight are implemented. | It remains generator, likelihood-contract, and scorer-wiring evidence: repeated MCMC has not run, and predictive plus decision-stability scorers are still incomplete. |

The versioned
`test/fixtures/existing_api_design_robustness_plan.json` therefore separates a
completed deterministic contract layer from an unrun
paired-replication layer. Its generator is
`scripts/generate_existing_api_design_robustness_plan.jl`. The deterministic
layer currently passes all seven checks:

- pointwise and total likelihood are equivariant to a pure row permutation
  after rows and named parameters are aligned;
- adding categorical `occasion` metadata does not change the static
  likelihood, and the audit labels it `recorded_not_modeled`;
- a fully ability-nested, no-link design is blocked by rank deficiency and a
  disconnected rater-link graph before sampling;
- 5% and 10% all-rater common-linking designs materialize exactly 20 and 40 shared
  person--item targets out of 400 while retaining the assignment warning;
- linking targets leave the parameter-anchor count at zero;
- a declared parameter anchor remains specified-only and cannot be reported as
  a fitted linking response; and
- the legacy generic-grid `anchor_size` field is confirmed to be planning
  metadata rather than generated rating events.

This is useful API evidence, but it is not parameter-recovery evidence. The
artifact therefore keeps `design_robustness_claim_supported=false` and blocks
release claims until paired known-truth refits are complete.

The study records four quantities that must not be conflated:

```math
\text{multiply-scored-target fraction}
= \frac{\#\{\text{unique person--item targets scored by at least two raters}\}}
        {\#\{\text{all unique person--item targets}\}},
```

the planned common-linking-target fraction, the fraction of rating events
spent on those common targets, and the additional-link rating fraction. A
balanced double-rated design has a multiply-scored-target fraction of 100%
even when it has no designated all-rater common set. A controlled benchmark
with a reference score or uncertainty is yet another data object. Parameter
anchors are model constraints and must never be substituted for any of these
design quantities.

The stress study is split into two tracks. Track A generates data exactly from
the fitted static family and isolates topology, assignment, common-linking
amount/range, rating budget, and latent dispersion. Track B deliberately
injects an order-dependent severity process but fits the same static API. It
measures the bias, predictive failure, and warning behavior caused by omitted
order dependence. Purely sorting or permuting identical observed rows belongs
only to the deterministic equivariance control: without an order-dependent
data-generating process, it cannot test ability--order confounding.
Both tracks set person-by-testlet and rater-by-response halo variation to zero.
Their success does not establish local independence; the later cluster gate
reuses the rating-design skeletons under nonzero competing dependence
mechanisms and has a separate claim threshold.

The later paired grid varies the following factors through mandatory paired
cells followed by an interaction-focused fractional factorial. A full cross is
prohibited because it would be computationally wasteful before replications:

| Axis | Required levels |
| --- | --- |
| Existing fit surface | public MFRM, guarded scalar GMFRM, guarded fixed-Q MGMFRM |
| Rating topology | fully crossed; rotating, fixed, and random pairs; mostly single-rated plus a common linking set; weak bridge; disconnected rejection control |
| Assignment | balanced random, ability-stratified balanced, ability-nested, severity-aligned, severity-opposed |
| Track A order control | random versus identical rows permuted; no true order effect |
| Track B ability/order composition | random, low-to-high, high-to-low, block-clustered under no, linear, or change-point order effects |
| Common-linking-target fraction | 0%, 2%, 5%, 10%, 20% |
| Raters per common target | 2, 3, or all raters |
| Rating budget | additive common ratings versus fixed-total target displacement; later, fixed-total routine-overlap reallocation |
| Linking support | full ability/item range versus narrow low, middle, or high range |
| Ability and severity dispersion | ability SD 0.5/1.0/2.0 and rater-severity SD 0.25/0.75/1.50 |
| Outcome dispersion | compressed, reference, and wide threshold spacing, with achieved score SD and category use recorded |

The minimum matched contrasts are:

1. a balanced random, double-rated baseline and the identical ratings under a
   row permutation;
2. ability-nested single ratings with no link as a pre-fit negative control;
3. the nested design with a 5% full-range common linking set placed early;
4. the identical 5% observations distributed through the row sequence, which
   must be numerically equivalent for the static likelihood;
5. the nested design with a 10% distributed full-range common set as the
   linking-dose contrast;
6. matched additive and fixed-total-target-displacement versions. The latter
   holds the single-rating event budget constant by dropping ordinary
   person--item targets, so planned-target, observed-target, and dropped-target
   fractions must all be reported. A later routine-overlap-reallocation policy
   should retain all targets and move duplicate ratings into the common set;
7. 10% narrow-range links as a check that count-based connectedness can pass
   while scale support remains weak; and
8. no-effect, random-order, reinforcing ability/order, and opposing
   ability/order cells for the omitted-order-effect boundary.

The 2%, 5%, 10%, and 20% levels are experimental doses, not literature-derived
optimal constants. [DeMars et al. 2023](https://commons.lib.jmu.edu/gradpsych/63/)
also show why posterior/model-based standard errors alone are insufficient:
empirical uncertainty across simulated assignments can differ while analytic
standard errors appear nearly unchanged. The grid must therefore compare
empirical RMSE with posterior interval width and coverage across paired
replications.

The first 30 replications are a pilot used only to debug the generator and
freeze recovery, calibration, prediction, and decision thresholds. Evaluation
uses at least 50 paired replications, extending to 100 when Monte Carlo
uncertainty cannot resolve a gate. The sampler contract is fixed in advance:
`R-hat <= 1.01`, bulk/tail ESS at least 400, no divergence or
maximum-tree-depth hit. Every generated cell must also verify its achieved
rating count, observed and dropped target coverage, score SD, common and
multiply-scored fractions under named denominators, rating-event burden,
within-rater sequence--ability correlation, assignment--severity
correlation, early/late ability shift, and graph connectivity from the
materialized rows. A disconnected negative control reaching the sampler, an
ability-informed design losing its assignment warning, or a parameter anchor
being described as a common response is a hard failure.

Assignment, common-link selection, fixed-budget displacement, and within-rater
order are resampled from a replication-specific design seed. The paired A/B
conditions retain the same realized skeleton, truth, response uniforms, and
sampler seed. Pilot and evaluation use disjoint seed namespaces while holding
sample size and sampler settings fixed. Requested percentages and placement
labels are not sufficient: underresolved smoke cells are marked planned-only,
and pilot/evaluation fits require the achieved range, placement, linking, and
event-budget checks to pass. For fixed-total conditions, multiply-scored and
common-linking fractions are reported against both planned and observed target
denominators.

The specialized runner is now
`scripts/generate_existing_api_design_robustness_stress_grid.jl`, with the
MCMC-free versioned artifact
`test/fixtures/existing_api_design_robustness_stress_grid.json`. Its dry run
passes all contract checks, including the three-family C2P comparison that
keeps named events, truth, uniforms, and scores fixed while moving common rows
from the beginning to distributed positions. It also records dimension-wise
and Q-active-source ability/order diagnostics for MGMFRM. This is not recovery
evidence because repeated MCMC has not run. The repeated parameter-recovery,
interval-coverage, posterior-SD calibration, sampler, and parameter-
completeness scorer is implemented fail-closed, including internal
reaggregation from paired rows. Its study-local statistical gate treats the
replication as the coverage cluster, uses a fixed upper uncertainty bound, and
uses predeclared error/uncertainty quantiles; parameter-row Wilson values and
raw maxima remain sensitivity sentinels. Pilot/calibration preflights are
regenerated from canonical options before a content-addressed freeze-input is
accepted. Pilot observations, statistical policy, reviewed thresholds,
revision, and time are then bound into one decision record; q95/q99 success is
explicitly well-specified-static distributional contract success rather than
evidence that every cell and parameter recovered. Pilot artifacts bind Julia,
Project, Manifest, source-tree, generator, and complete-payload hashes. Clean
immutable VCS state, external chronology attestation, and raw-draw/cache
identity remain separate unverified boundaries. Predictive and decision-stability scorers are still
incomplete, so pilot/calibration MCMC remains blocked. Before any fit, the
runner audits every requested design skeleton; the 50-replication calibration
profile passes all 1,050 candidate-family rows after constrained ability-by-
item full-range selection and can freeze assignment/event/truth/sampler hashes
before responses are generated. The next gate is to complete the two remaining
scorers, then run the 30-replication paired pilot and freeze study-local
thresholds before evaluation seeds. Only after the repeated
grid passes should its assignment skeletons feed the temporal-drift
identifiability study below. Track A asks whether the current static API is
robust when correctly specified. Track B maps how it fails when a true order
effect is omitted; it does not estimate drift. The later dynamic study asks
whether time change can be identified. This ordering avoids making a new model
compensate for an untested static design.

### Local Independence, Testlets, and Rating Bundles

Local independence is conditional on every latent and facet effect included in
the model. Residual association within a task, response, rubric, or repeated-
rating bundle indicates missing structure, but it does not identify that
structure by itself. In rater-mediated assessment, similar patterns can arise
from task-specific performance, a shared rater impression, task-specific rater
severity, omitted multidimensionality, or sequence effects. The research track
therefore begins with cluster-aware diagnosis and competing-mechanism
falsification rather than automatic addition of a testlet term.

The current model is the negative-control baseline: conditional on its
parameters, the likelihood factorizes over rating rows. Existing observation
residuals, infit/outfit, grouped PPC, and rater-overlap counts remain useful,
but they are not a first-class local-independence diagnosis. The first planned
diagnostic contract should report Q3/adjusted-Q3-style criterion or item pairs
with setting-dependent calibration informed by [Christensen, Makransky, and
Horton 2017](https://doi.org/10.1177/0146621616677520), LD-X2-style checks
informed by [Chen and Thissen
1997](https://doi.org/10.3102/10769986022003265) where category support is
adequate, rater-pair residual association on shared responses, sequence-lag
summaries, posterior predictive
tail areas, common-observation counts, and sparse-pair or disconnected flags.
Its thresholds must be calibrated by model family and design rather than
presented as universal cutoffs.

#### Diagnostic Estimand and Multiplicity Contract

Before implementation, the diagnostic plan freezes the residual, matching, and
aggregation rules. For observation `n` and posterior draw `d`, the primary
residual is the draw-specific standardized score residual

```math
e_{nd} =
\frac{y_n - \operatorname{E}(Y_n \mid \psi_d)}
     {\sqrt{\operatorname{Var}(Y_n \mid \psi_d)}}.
```

Associations are computed within each draw and then summarized over draws;
correlating posterior-mean residuals is a separate sensitivity statistic, not
the primary estimand. Posterior predictive replicates retain the observed
assignment, missingness, and pair-eligibility pattern. Conditional PPC holds
the fitted latent effects fixed for the named observed clusters; marginal PPC
regenerates the random effects named as unseen by the prediction target.

Pair estimands use separately declared definitions even when their underlying
observations overlap:

- criterion/item pairs within one rater use the matching key
  `(response_id, rater)` and are sensitive to same-rater halo as well as shared
  response structure;
- criterion/item pairs across independent raters match on `response_id` under a
  predeclared rater-pair and weighting rule, reducing but not eliminating halo
  ambiguity;
- rater pairs match on `(response_id, criterion)` and diagnose dependence among
  multiple ratings; and
- testlet item pairs match on the declared person-by-testlet cluster. Repeated
  responses require `occasion` or `response_id` and are never collapsed merely
  because person and task labels agree.

Every row reports the eligible-cluster count, paired-observation count, missing-
pair rule, duplicate/occasion rule, and weighting rule. Adjusted Q3 is centered
within posterior draw by the mean eligible off-diagonal correlation for its
diagnostic family. Pairs below the frozen support minimum are reported as
sparse and do not enter a pass/fail aggregate; missing pairs are not imputed.

Multiplicity has two distinct outputs. Pair-level rows are localization screens
with a predeclared FDR or posterior exceedance profile whose achieved error is
checked by simulation. The dataset-level promotion gate takes one maximum
absolute standardized discrepancy across every enabled diagnostic family and
every eligible pair, including pairs whose source observations overlap. This
global maximum is calibrated under the exact model family and design and
controls the family-wise error for the complete local-dependence screen.
Family-specific maxima are reported for diagnosis but do not replace the global
gate. Simulation reports pairwise Type-I error/power, family-specific error,
and global dataset-level FWER/power with Monte Carlo intervals. Enabled
families, support cutoffs, directionality, standardization, and the FWER/FDR
profile are frozen after pilot seeds and before evaluation seeds.

#### Competing Model Ladder

Let `s` identify a response, `t(s)` its task or testlet, `p` the person, `r` the
rater, and `i` the item or rubric criterion. Candidate terms are intentionally
kept separate:

| Candidate | Added location term | Intended variation | Principal competing explanation |
| --- | --- | --- | --- |
| Static MFRM/GMFRM/MGMFRM | none | Conditional row independence after existing facets | Negative control for overfitting and false alarms. |
| Scalar person-by-testlet | `u[p,t(s)] = sigma_T * z[p,t(s)]` | A shared deviation across the criteria/items and raters of the unique person-by-testlet response. In the first slice, person-by-testlet and response clusters are one-to-one and are not empirically separable. | Omitted substantive dimension, task difficulty, or response/occasion variation. |
| Repeated-response decomposition | `u[p,t(s)] + v[p,t(s),o(s)]` | Stable person-by-testlet variation separated from a deviation shared only within one repeated response | Sequence effects or a design with too few repeated occasions. |
| Rater-by-response bundle/halo | `h[r,s]` | A shared impression by one rater across criteria on the same response | Person-by-testlet performance when only one rater observes the response. |
| Rater-by-task severity | `g[r,t(s)]` | A rater being systematically stricter or more lenient on a task | DFF, assignment, and temporal task blocks. |
| Dimension-specific testlet/bifactor | `u[p,t(s),l]` with declared loadings | Cluster dependence that differs by substantive dimension | Q-matrix misspecification or a new general/specific factor. |
| Residual covariance | declared signed covariance within a cluster | Negative, mixed-sign, or item-specific dependence not representable by one random intercept | Unstable covariance estimation in sparse clusters. |

The first fitted candidate is the non-centered scalar MFRM term with one common
standard deviation `sigma_T` and exactly one response per person-by-testlet. It
is labelled only as a shared person-by-testlet/response-cluster effect because
those units coincide in this design. It is not evidence of stable task-specific
performance, a new substantive dimension, or a causal halo process. A fixed
task main effect is not a substitute: when items are nested in tasks it is
aliased with item difficulty, and it does not model person-specific within-task
dependence. A dataset with
repeated responses to the same task requires `response_id` plus an explicit
response/occasion effect candidate; silently treating those responses as one
`u[p,t]` cluster is rejected.

[Ip 2010](https://doi.org/10.1348/000711009X466835) shows why empirical fit alone
may not distinguish multidimensional and local-dependence representations.
[Fox, Wenzel, and Klotzke
2021](https://doi.org/10.3102/1076998620941204) also motivates a covariance
alternative when the common-positive-association restriction of a scalar random
intercept is false. Theory, design, and a named prediction target must therefore
accompany model comparison.

#### Identification and Boundary Contract

| Target | Minimum design evidence | Blocking condition |
| --- | --- | --- |
| Person-by-testlet standard deviation `sigma_T` | Each person ordinarily contributes to at least two testlets; tasks recur across persons; each person-by-testlet cluster has multiple usable indicators and adequate person replication. | One task per person, one indicator per cluster, unique tasks, or disconnected person--testlet support. Two indicators are retained as a weak-support stress level, not a universal sufficiency rule. |
| Rater-by-response halo | Each rater-by-response cell has at least two criterion/item observations, responses have independent rater overlap, and raters score multiple responses. Criterion splitting helps only when the design still supplies within-rater-by-response repetition. | One observation per rater-by-response cell, including a pure one-criterion-per-rater split; or one rater per response with no independent overlap. Multiple raters alone are insufficient. |
| Rater-by-task severity | Raters cross tasks and share linking responses or persons across tasks. | Raters are nested in tasks or task is perfectly aligned with time, form, or assignment. |
| MGMFRM versus testlet | Multiple testlets cover each claimed dimension; Q-by-testlet support is connected and includes contrasts that are not perfectly aligned. | A dimension occurs in one testlet, Q columns are unsupported within clusters, or testlet membership duplicates a Q dimension. |
| Repeated-response decomposition | Stable `response_id`, task, person, rater, criterion, and occasion or sequence keys; at least two occasions within each supported person-by-testlet; multiple indicators within each response; and enough repeated person-by-testlet clusters to separate `u[p,t]` from `v[p,t,o]`. | One occasion per person-by-testlet, one indicator per response, too few repeated clusters, responses collapsed into one key, or order inferred from row order. In these cases only a combined cluster component is estimable. |
| Sparse rating graph | Cluster-level replication, rater-within-response overlap, and person--testlet and rater--task connectivity in addition to ordinary person--rater connectedness. | The ordinary rating graph is connected but the mechanism-specific graph is disconnected or supported by a single bridge. |

`sigma_T = 0` is a variance-component boundary. Under a continuous half-normal
or half-t prior, `P(sigma_T > 0 | y)` is one by construction and is not evidence
that a testlet effect exists. The reporting contract instead uses a predeclared
practical ROPE such as `P(sigma_T < epsilon | y)`, posterior intervals, prior-
scale sensitivity, cluster PPC, and predictive comparison. An explicit spike-
and-slab model is a later option if a point-null probability is substantively
required. `sigma_T` always denotes a standard deviation; `sigma_T^2` is labelled
separately whenever variance is reported.

Evaluation also separates the boundary from positive truths. At `sigma_T = 0`,
the declaration rule is
`P(sigma_T > epsilon | y) > gamma`. The practical threshold `epsilon`, posterior
probability threshold `gamma`, and one-sided upper-limit credibility level
`1 - alpha_U` are named in a decision profile and frozen after pilot seeds and
before evaluation seeds. The primary null quantities are that rule's false
declaration rate, ROPE calibration, and the distribution of the frozen upper
credible limit. Equal-tailed interval coverage of exact zero is not used
because a continuous positive-scale posterior excludes the boundary. Bias,
RMSE, and two-sided interval coverage for `sigma_T` are evaluated only at
strictly positive truths. Prior-generative SBC is a separate computational
calibration and is not presented as point-null coverage.

#### Known-Truth Mechanism-Confusion Grid

The study uses mandatory matched contrasts followed by a fractional-factorial
extension. A full cross is prohibited before the pilot establishes feasible
cells and freezes thresholds.

LD1a now freezes and materializes the first 22-scenario preflight subset with
`local_dependence_simulation_grid` and `simulate_local_dependence`. The
standalone adjacent-category kernel does not call the fitted likelihood;
facet-specific semantic keys and event-keyed uniforms support matched
comparisons, and each bundle records all generating components and structural-
audit results.
The subset covers null and exact-zero controls, study-local near-zero through
large person-by-testlet effects, support boundaries, sparse and underidentified
controls, halo, crossed and nested rater-by-task conditions, omitted
multidimensionality, randomized drift, ability-confounded no-drift order,
ability-informed assignment, and a testlet-plus-sequence mixture. It does not
complete the factorial grid or
provide repeated calibration evidence.

LD1b0 now freezes the MCMC-free calibration contract, result-row schema, and
aggregation scorer. Planned, rejected, failed, and unresolved replications
remain explicit; Wilson intervals apply only to replication-level binary
rates, while pooled pair rates remain descriptive. The versioned scorer
preflight checks all 22 scenario denominators and the four declared pre-fit
rejections.

LD1b1 now freezes the pilot execution protocol through
`local_dependence_calibration_pilot_contract` and
`local_dependence_calibration_pilot_preflight`. Thirty replications for each
of 22 scenarios produce `30 × 22 = 660` planned rows: 540 eligible fitting
jobs and 120 planned structural rejections. The MCMC-free
`local_dependence_pilot_protocol_preflight.json` artifact checks separated
seeds, job identities, resource and failure policies, and preserves an original
failure when a retry is recorded. Operational candidate bounds are study-local.
The 50- and 100-replication evaluation sizes remain candidates to be selected
and frozen after the pilot and before evaluation.

The authorization pins `rank_normalized_rhat_bulk_tail_ess_v1` and its full
dependency and operation-order record, primary fields, tail probability,
minimum chain and draw requirements, complete-chain E-BFMI coverage, and the
SHA-256 digest of `src/bayesian_fit.jl`. A mismatch requires a new preflight.

The MCMC-free batch execution-harness dry run is recorded by
`scripts/generate_local_dependence_pilot_batch_execution_harness.jl`, using
the orchestration contract in
`scripts/run_local_dependence_calibration_pilot_batch.jl`. It checks all 660
planned rows, including 540 eligible fitting jobs and 120 planned pre-fit
rejections. The batch-controller and generator sources are identified; the
execution plan remains incomplete until the canonical single-job executor
SHA-256 is materialized. Terminal records require exact role-specific semantic
evidence, one hashed source artifact per role, and exact upstream evidence
hashes. The frozen `pilot_contract` and the
canonical ordering of all 660 job rows are verified by canonical SHA-256. A
`pre_fit_rejected` result requires the exact `generated_data` ->
`structural_rejection_audit` -> `calibration_row` chain, including simulation
and rejection provenance in a row conforming to the existing public
calibration-row contract. Simulation evidence validates response data, table
columns, probability cells, truth and row-truth arrays, structural eligibility,
and data/score/design signatures. Fit evidence uses the structured
`local_dependence_pilot_fit_artifact_export.v1` JSON wrapper containing retained
draws, log posterior values, sampler statistics, sampler
controls, and reproducibility metadata. Its package-native content hash must be
verified by the future pinned canonical executor before JSON projection; the
batch runner separately recomputes the canonical JSON payload hash and verifies
the exact file SHA-256. The JSON projection cannot soundly reconstruct the
native typed hash. Frozen resource counts and sampler controls are checked, and
convergence, divergence, depth, and complete-chain E-BFMI gates are validated
individually. Fit, sampler, local-dependence, and calibration evidence must
agree on data, design, fit-artifact, retained-draw, chain, and iteration
provenance. The custom `local_dependence_pilot_summary_bundle.v1` directly
records the draw-selection and posterior-predictive seeds; the runner compares
both with its evidence payload, the frozen job, and the calibration execution
seeds. Draw selection uses the frozen
`sha256_seeded_rank_without_replacement_v1` algorithm, and the runner
recomputes its ordered draw indices from the frozen seed.
The posterior-predictive seed is source-bound, but seed-to-result replay
verification remains
pending the canonical single-job executor and bounded smoke review. A
`diagnostic_failed` component identifies the sampler-quality gate
only when it failed, or the local-dependence summary only after that gate
passed. Symbolic links, hard links, and unmanifested files fail archive
integrity. Aggregate state binds the verified primary-result,
evidence-manifest, and attempt-inventory digests.
Primary attempts are nonoverwritable, and remediation remains additive. Resume
first rescans the complete attempt archive as the source of truth, then verifies
and compares the derived checkpoint, and skips only verified terminal primary
records. Invalid remediation fails archive integrity without replacing the
primary denominator.
The generated dry run does not scan an attempt archive, so integrity is not
assessed. It generates no response data, fits no model, and runs no MCMC;
pilot results, calibration or power estimates, diagnostic decisions, and
mechanism interpretations remain unavailable.

Snapshot and inventory values are rechecked during validation, but this remains
a static consistency check rather than an atomic completed-attempt seal.

The next execution-control step is the canonical single-job executor. Before
the pilot starts, it must retain the status-specific hashed data, fit, sampler-
diagnostic, local-dependence, calibration, or structural-rejection records and
pass a bounded smoke review without changing the frozen seeds, sampler
controls, or primary denominator. The same gate must add a completed-attempt
seal and an append-only recovery or retirement path for interrupted attempts;
remediation cannot promote a partial primary into the scientific denominator.

Rank-normalized split R-hat and bulk/tail ESS are now available from package
sampler diagnostics, so the preflight authorizes pilot execution after the
executor, smoke, completed-attempt seal, and interrupted-attempt recovery gates
pass. Pilot and evaluation replications have not been run, so the completed
preflight provides
no repeated-calibration evidence, pairwise power, diagnostic decision, or
mechanism interpretation.

| Axis | Required levels |
| --- | --- |
| Fitted family | MFRM, guarded scalar GMFRM, guarded fixed-Q MGMFRM after the unidimensional gate |
| True dependence mechanism | none; scalar person-by-testlet; rater-by-response halo; rater-by-task severity; dimension-specific testlet; omitted substantive dimension; temporal sequence only; selected mixtures |
| Practical dependence magnitude | `sigma_T` standard deviation at zero, near-zero, small, moderate, and large values frozen after prior-predictive pilot work; no universal cutoff |
| Indicators per cluster | 1 as a rejection control, then 2, 4, and 8 |
| Testlets per person | 1 as a confounding control, then 2 and 4 or more |
| Repeated responses per person-by-testlet | 1 as a decomposition-rejection control, then 2 and 3 or more with multiple indicators per response |
| Raters per response | 1, 2 independent raters, and 3 or more where feasible |
| Rubric assignment | same rater across all criteria, criterion-split raters, and communicating/adjudicated raters as a misspecification condition |
| Rating topology and assignment | crossed, rotating pairs, connected sparse, weak bridge, task-nested, disconnected rejection, balanced random, and ability-informed assignment |
| Q-by-testlet structure | unidimensional; fixed-Q two/three dimensional; testlets aligned with, crossed over, or weakly supporting dimensions |
| Dependence shape | common positive, item-specific loading, heterogeneous testlet standard deviation, and negative or mixed-sign covariance |
| Order and dispersion | randomized versus ability-confounded task order; compressed/reference/wide thresholds; low/reference/high ability and severity dispersion |
| Prior profile | at least three regularizing scales with the same truth, realized design, response uniforms, and fit seeds across candidate comparisons |

Mandatory matched contrasts are:

1. true independence fitted with and without the testlet block;
2. a true scalar person-by-testlet effect under an identified crossed design;
3. the same signal under one-testlet-per-person and one-rater-per-response
   confounding controls, which must be rejected or labelled underidentified;
4. halo truth fitted by baseline, testlet-only, and halo candidates;
5. rater-by-task truth under crossed versus task-nested rater assignment;
6. multidimensional truth fitted by scalar testlet and correct fixed-Q models;
7. common-positive versus negative or mixed covariance truth; and
8. repeated-response truth with enough occasions versus the matched one-
   occasion rejection control, comparing the combined and decomposed cluster
   candidates; and
9. sequence-only truth, plus true drift with testlet dependence, so neither
   static cluster effects nor drift are credited for the other's signal.

The LD1a ability-confounded no-drift scenario is the initial order/case-mix
negative control. It does not vary parameter anchors, common linking
responses, or the amount and temporal placement of controlled benchmark
responses. Those anchor and benchmark-design contrasts remain in the existing-
API and temporal-identification studies, where early/middle/late placement can
be assessed without being mistaken for evidence from the local-dependence
generator.

Primary metrics are bias, RMSE, interval coverage, interval width, and prior
sensitivity for ability, item/task, rater, thresholds, and strictly positive
standard-deviation components. Boundary-zero cells instead use practical-
effect false declarations, ROPE calibration, and upper-limit behavior.
Q3/cluster-PPC metrics include both pair-level Type-I error/power and dataset-
level FWER/power; reliability or information inflation from ignored dependence;
classification, rank, cut-score, and re-score
decisions; mechanism-misclassification rate; divergences, depth, E-BFMI,
R-hat, ESS, and posterior correlations; and predictive performance at the
declared cluster target.

Promotion requires the null model not to manufacture practically important
dependence, identified positive controls to recover their generating blocks,
and non-testlet mechanisms not to be systematically absorbed by `sigma_T`.
Adding the correct block should remove the targeted within-cluster posterior
predictive discrepancy without degrading between-cluster or category
calibration. A good sampler with a wrong mechanism label is a failed claim
gate, not a successful model.

#### Cluster-Level Prediction Contract

| Prediction target | Information allowed | Random-effect treatment |
| --- | --- | --- |
| Another criterion/rating within an observed response | Other ratings for that response may be used | Conditional on every learned person-by-testlet, response/occasion, and rater-by-response effect named by the fitted candidate. |
| A calibrated rater scoring an observed response for the first time | The rater's other responses and other raters on this response may be used, but none from the held-out rater-by-response cell | Condition on the calibrated rater severity/consistency and shared response information; marginalize the unseen halo cell if that block exists. |
| A calibrated rater scoring a wholly held-out person-by-testlet response | The rater's other responses and the person's other testlets may be used; no row from the held-out person-by-testlet enters fitting | Condition on calibrated rater and person effects; integrate the unseen `u[p,t]` and any supported response/halo effect. |
| A rater absent from the fitting data | No row from that rater may enter fitting | Unsupported when rater effects are fixed facets. Prediction requires a separately validated hierarchical rater-population model that marginalizes severity, consistency, halo, and any task interaction. |
| A new response from a known person on an already observed testlet | The person's other responses and testlets may be used; no row from the new `response_id` may be used | Not a supported first-slice target because stable `u[p,t]` and response-specific variation were not separated. The repeated-response extension must learn `u[p,t]` from prior occasions and marginalize the unseen `v[p,t,o]`. |
| A new person-by-testlet combination for a known person and calibrated testlet | The person's other testlets and other persons on the target testlet may be used | Condition on the person's learned ability and calibrated item/task terms; integrate the unseen `u[p,t]`. |
| A new person | No row from that person may enter fitting | Unsupported as a population prediction when person abilities are fixed facets. A separately validated ability-population model must marginalize ability and every person-specific testlet/response effect; a parameter prior alone is not automatically a population distribution. |
| A wholly new, uncalibrated task/testlet | No score from the task may enter fitting | Unsupported for a fixed task/item effect; requires a separately validated hierarchical task model and marginalization target. |

Summing row log likelihoods into a cluster score is not enough when the
posterior cluster effect was estimated from rows later called held out. Whole-
cluster prediction requires refit/K-fold evaluation or a proper marginal
predictive density. WAIC or PSIS-LOO at the observation row is not evidence for
new-response or new-person-by-testlet performance. Reports must state the
scoring unit, conditioning set, whether an unseen effect is marginalized, and
whether any row from the
held-out cluster informed the posterior.

#### Extension Gates

1. **LD0a -- metadata and estimand scaffold (complete, non-decision):** `FacetData` now keeps
   `testlet_id`, `response_id`, and repeated `occasion` distinct;
   `testlet_design_audit` reports target-specific structural support;
   `predictive_standardized_residuals` supplies the draw-specific Pearson
   estimand; and `local_dependence_contract` separates single-rating item,
   within-rater item, and rater-pair targets while freezing matching,
   duplicate, draw-specific support, weighting, FWER/FDR, and
   conditional/marginal PPC rules. These functions do not enable a calibrated
   decision label or fit a cluster effect.
2. **LD0b -- pair-support engine (complete, report-only):**
   `local_dependence_summary` implements family-consistent item and rater-pair
   matching, applicability-first duplicate handling, testlet-stratified support
   graphs, raw and adjusted-Q3-style summaries, paired predictive tail
   fractions, within-family BH values, and the all-family maximum-statistic
   reference. It uses distinct posterior draws and one conditional replicate
   per draw. Criterion-split applicability is evaluated per testlet, so an
   inapplicable stratum does not suppress a valid single-rating stratum.
   Materialized audit rows, shared-unit work, positive pair-by-draw work, and
   prediction cells are bounded before large allocations. Single-response rater
   concentration is reported conservatively, and calibrated decision labels
   remain absent.
3. **LD1a -- independent generator and design preflight (complete):** the
   standalone ordinal kernel, 22 frozen scenarios, component-specific seeds,
   event-keyed uniforms, full truth records, category-scale preservation,
   structural audits, and resource bounds cover null, positive, boundary,
   sparse, rejection, and competing-mechanism preflights.
4. **LD1b0 -- calibration scorer/protocol preflight (complete):** freeze
   candidate pair, family-maximum, and all-family-maximum scoring; preserve
   planned and unresolved denominators; keep pooled pair rates descriptive;
   and materialize the four pre-fit rejection rows without fitting or MCMC.
5. **LD1b1 -- pilot execution-protocol preflight (complete):** freeze the
   `30 × 22 = 660` execution matrix, 540 eligible jobs, 120 planned rejections,
   separated seeds, resource and failure policy, and append-only retry history.
   The operational bounds are study-local, and the 50- and 100-replication
   evaluation sizes are candidates rather than completed runs. **The pilot
   protocol is authorized, but execution remains gated** until the canonical
   single-job executor, bounded smoke review, completed-attempt seal, and
   interrupted-attempt recovery review pass. Rank-normalized split R-hat and
   bulk/tail ESS are available
   under the exact frozen diagnostic contract, complete-chain E-BFMI rule, and
   recorded diagnostic-source hash.
   Authorization is a plan check, not execution or calibration evidence.
   The MCMC-free batch harness dry run checks deterministic identities and the
   attempt layout for all 660 rows, refuses primary-attempt overwrite, keeps
   remediation additive, first rescans the complete attempt archive as the
   source of truth on resume, then verifies and compares the derived checkpoint,
   and skips only verified terminal primary records. The generated dry run does
   not assess an attempt archive
   and generates no response data, fit, MCMC output, or operating-characteristic
   evidence. After the execution-control gates pass, execute the pilot, freeze
   the operating rules and one evaluation size, and run separately seeded
   evaluation replications. Pairwise power,
   calibration, diagnostic decisions, and mechanism interpretation remain
   unavailable until the applicable evidence passes.
6. **LD2 -- scalar MFRM candidate:** implement a common-standard-deviation
   non-centered person-by-testlet term for one-response-per-person-by-testlet
   data; pass source, transform, gradient, HMC, positive-truth recovery, null-
   boundary false-declaration, and prior-sensitivity checks.
7. **LD3 -- prediction and decomposition:** add the distinct within-response,
   calibrated-rater, unseen-rater, repeated-response, person-by-testlet-heldout,
   new-person, and new-task targets; add a compatible MRCML/ConQuest bridge and
   separate response/occasion, halo, and rater-by-task candidates. Freeze the
   claim rule from the competing fits.
8. **LD4 -- generalized extension:** extend to GMFRM only after LD2--LD3 pass.
   Extend to fixed-Q MGMFRM only after Q-by-testlet design support and the base
   MGMFRM evidence gate also pass.
9. **LD5 -- richer structures:** compare dimension-specific testlet, bifactor,
   heterogeneous-variance, and signed covariance candidates only when the
   scalar model is falsified and the design supports the extra structure.
10. **LD6 -- dynamic integration:** expose dynamic scalar MFRM only after the
   static robustness, LD3 decomposition, process-data, and temporal-
   identification gates pass; dynamic fixed-Q MGMFRM additionally requires
   LD4 and a stable multidimensional gauge.

LD1a, the LD1b0 scorer/protocol preflight, the LD1b1 pilot execution-protocol
preflight, and its MCMC-free batch execution-harness dry run are complete.
The harness covers 660 planned rows, including 540 eligible fitting jobs and
120 planned pre-fit rejections. Because the dry run does not scan attempts, its
archive assessment is `not_assessed`. Rank-normalized split R-hat and bulk/tail
ESS are implemented, but the LD1b pilot begins only after the executor, bounded
smoke, completed-attempt seal, and interrupted-attempt recovery gates pass. The
existing-API recovery
scorer may proceed in parallel. The pilot itself remains unrun. Pilot review
then freezes the study-local rules and one evaluation size before separately
seeded evaluation.
Fitted effect promotion begins only after both evidence tracks pass. This
dependency prevents a new random effect from compensating for an untested
static design and prevents a temporal term from absorbing unmodeled response
clustering.

### Temporal Drift Identifiability Stress Test

The primary falsification target is a dynamic model declaring rater drift when
true rater severity is constant but the ability distribution of responses
changes over the rating sequence. [Yeates et al. 2022](https://doi.org/10.1111/medu.14713)
provide a direct experimental rationale: the same embedded performances received
different scores when shown early versus late. [Hombo, Donoghue, and Thayer
2001](https://doi.org/10.1002/j.2333-8504.2001.tb01847.x) show that nested rater
assignment can bias ability estimates while spiral designs are more robust, and
[Wind and Jones 2019](https://doi.org/10.1111/jedm.12201) show that incomplete
design and rater-effect detection interact. The reviewed literature does not
cross all of these factors with a Bayesian drift model, making this a genuine
methodological stress test rather than a routine implementation check.

The roadmap must distinguish four uses of the overloaded word "anchor":

- a **parameter anchor** fixes or regularizes a model parameter and corresponds
  to the current `FacetSpec.anchors` contract;
- a **linking performance** is a common response used to connect raters or
  assessment groups;
- a **monitoring or validity benchmark** has an expert or consensus score and is
  seeded into an operational queue;
- a **repeated embedded benchmark response** is the same controlled performance
  shown in multiple time windows to identify temporal change.

The last three are data-collection objects, not current generalized-likelihood
parameter anchors. The future process-data contract should therefore record
`sequence_index`, session and timestamp fields, active duration and breaks,
response identity, benchmark type and reference-score uncertainty, whether the
benchmark was blind, assignment reason, and the planned-design identifier.

The minimum known-truth grid should include the following axes.

| Axis | Required levels | Failure mode isolated |
| --- | --- | --- |
| True severity process | none, monotone linear, random walk/AR(1), abrupt change point | False drift, missed gradual drift, and missed abrupt drift. |
| Practical drift magnitude | zero plus small, moderate, and large values defined relative to a preregistered practical threshold | Statistical detection that is not practically meaningful. |
| True clustered process | none, person-by-testlet, rater-by-response halo, rater-by-task severity, and the minimum drift-plus-testlet mixture | Static response or task structure absorbed as time-varying severity. |
| Fitted nuisance structure | omit or include the predeclared testlet, halo, and rater-by-task blocks in nested candidates | Apparent drift that disappears only when a competing clustered mechanism is represented. |
| Ability/order composition | randomized; low-to-high; high-to-low; block-clustered; mild and strong correlation or late-window mean shifts | Examinee case mix absorbed as rater drift, including cancellation and amplification. |
| Presentation policy | randomized, ability-blocked, task/form-blocked, and adaptive routing | Order randomization versus operational routing. |
| Temporal benchmark schedule | none, initial-only, initial-plus-final, evenly distributed early/middle/late, blind-random, and information-adaptive | Inability of front-loaded controls to identify mid-session or nonlinear change. |
| Benchmark range, target fraction, and burden | narrow low/middle/high versus full-range; 0%, 2%, 5%, and 10% unique controlled-response fractions; achieved rating-event burden reported separately; fixed versus uncertain reference scores | Local-only scale support, category/threshold drift, and cost--information tradeoffs hidden by a single percentage. |
| Rating assignment | fully crossed, two-rater systematic link, mostly single-rated plus common benchmarks, weak bridge, nested or ability-informed assignment, and disconnected rejection control | Prior-driven comparisons and assignment confounding. |
| Observation fidelity | exact within-rater order, coarse occasion bins, missing timestamps, interrupted active time, and mislabeled order | Operational metadata that cannot support the fitted time scale. |

The mandatory contrast families are:

1. no true drift, randomized presentation, and distributed full-range benchmark
   responses as a negative control;
2. no true drift, strong late low- or high-ability case mix, and no or
   initial-only benchmark responses as the principal false-positive challenge;
3. the same confounded case mix with evenly distributed full-range blind
   benchmarks, which should reduce false drift without manufacturing power;
4. true practical drift under randomized order, and then under opposing and
   reinforcing case-mix trends, as positive, cancellation, and amplification
   controls;
5. no drift with task-blocked presentation and a true rater-by-task effect, no
   drift with a true person-by-testlet effect, and no drift with true halo, each
   fitted both with and without the corresponding nuisance block; and
6. true practical drift plus person-by-testlet dependence, fitted with the
   drift-only, testlet-only, and joint candidates as a mechanism-separation
   control.

Each dataset should be evaluated with a static MFRM, an independent
time-specific severity model, the Markov drift model, a change-point model, and
an assignment/case-mix-aware candidate where the data contract supports it.
The primary estimand is a preregistered contrast such as

```math
\Delta_r = \rho_{r,\mathrm{last}} - \rho_{r,\mathrm{first}},
```

with a practical drift threshold `epsilon`. Primary evidence includes the
calibration of `P(abs(Delta_r) > epsilon | y)`, false drift declarations under
the no-drift controls, interval coverage and bias/RMSE for time-specific
severity and ability, change-point error, early/late cut-score reversals,
posterior severity--time-window-ability confounding, and information gain per
benchmark response.

Before the full grid is run, pilot seeds must be separated from evaluation
seeds and the decision profile must be frozen. The promotion gate requires:

- empirical false-drift behavior under no-drift controls to be compatible with
  the preregistered nominal decision rate within Monte Carlo uncertainty;
- near-nominal interval coverage under the primary identified designs and no
  practically important ability or severity bias hidden by acceptable sampler
  diagnostics;
- distributed full-range benchmarks to be no worse than no-benchmark or
  initial-only designs on both false-drift rate and drift-estimation error;
- the design audit to return a blocking `drift_assignment_confounded` status
  when order, benchmark support, or time-window connectivity cannot identify
  the requested contrast;
- prediction to target held-out benchmark responses or a future time window,
  rather than using same-data WAIC as evidence that drift is identified;
- prior, time-bin, drift-shape, assignment, and seed sensitivity to be recorded;
  and
- the existing manuscript-facing HMC criteria to pass for every promoted cell.

The planned artifacts are a small predeclared design document followed by a
dedicated stress grid, rather than expansion of the generic eight-axis
simulation grid:

- `scripts/generate_rater_drift_identifiability_plan.jl` and
  `test/fixtures/rater_drift_identifiability_plan.json`;
- `scripts/generate_rater_drift_identifiability_stress_grid.jl` and a separate
  versioned grid/review artifact after the plan is frozen.

No dynamic MGMFRM fit should be attempted until the unidimensional dynamic MFRM
passes this falsification track. A Markov prior may improve sparse recovery, but
it cannot turn an uninformative or confounded assignment design into data-based
identification.

### Parallel Process-and-Design Sequence

This research track does not change the `v0.1.2`--`v0.2.0` fixed-Q release
sequence. Work that improves data capture and design triage can proceed in
parallel; new fitted model families remain later research surfaces.

1. **P0 -- existing-API design robustness:** complete the paired known-truth
   MFRM/GMFRM/MGMFRM grid over linking amount and range, assignment topology,
   order invariance, and latent dispersion. The deterministic contract layer is
   complete; replicated recovery and calibration remain pending.
2. **P1a -- cluster and process-data contract:** response/testlet identity,
   categorical occasion metadata, and the target-specific cluster audit are
   complete. Sequence, session, duration, benchmark-response, independence,
   and assignment metadata remain to be added in parallel with P0.
3. **P1b -- calibrated local-dependence diagnosis:** draw-specific Pearson
   residuals, the matching/multiplicity contract, report-only pair-support and
   Q3/adjusted-Q3 references, the independent LD1a generator, and structural
   rejection controls and the LD1b0 denominator-preserving scorer preflight are
   complete. The LD1b1 pilot execution protocol is also preflighted and
   authorized for 660 planned rows without fitting. Its MCMC-free batch harness
   dry run checks 540 eligible fitting jobs, 120 planned pre-fit rejections,
   identified batch-controller and generator sources, an execution plan that
   remains incomplete until the canonical single-job executor SHA-256 is
   materialized, semantic evidence contracts, and nonoverwrite and additive-
   remediation rules. On resume, it first rescans the complete attempt archive,
   then verifies and compares the derived checkpoint, and skips only verified
   terminal primary records. The generated dry run reports archive integrity
   as not assessed and supplies no pilot evidence. Rank-normalized split R-hat
   and bulk/tail ESS are implemented. Next materialize and pin the single-job
   executor, pass bounded smoke, add a completed-attempt seal, and pass
   interrupted-attempt recovery review before executing the pilot. Then freeze
   one of the 50/100 evaluation sizes and the
   study-local operating rules, and run evaluation for pair, family, and global
   reference behavior and mechanism confusion.
4. **P1c -- scalar testlet candidate:** after P0 and P1b pass, run source,
   gradient, HMC, null-boundary, positive-truth recovery, and prior-sensitivity
   gates for a non-centered unidimensional MFRM person-by-testlet standard-
   deviation effect under the one-response-per-person-by-testlet restriction.
5. **P1d -- mechanism decomposition and cluster prediction:** distinguish
   testlet, response/occasion, rater-by-response halo, rater-by-task severity,
   omitted dimensions, and sequence effects; validate every distinct cluster-
   holdout target and the compatible MRCML/ConQuest bridge.
6. **P2 -- posterior rater comparisons and temporal design:** finish pairwise
   severity/consistency contrasts and predictive agreement; freeze the drift-
   identifiability plan and time-window graph audit. These summaries may be
   developed earlier, but dynamic interpretation depends on P1d.
7. **P3 -- dynamic scalar MFRM:** run the temporal falsification grid with
   testlet/halo/rater-by-task negative controls before interpreting drift,
   fatigue, learning, or change points.
8. **P4 -- static score--rating-time model:** reproduce HFM-RT-style recovery
   before adding within-rater learning, fatigue, or severity--speed coupling.
9. **P5 -- text/count process models:** distinguish ordinal length effects from
   count exposures and validate joint score/count/time models with repeated
   prompts or process indicators.
10. **P6 -- dynamic fixed-Q MGMFRM:** add dimension-specific testlet or temporal
   effects only after P1d--P5 identify their simpler components, Q-by-testlet
   coverage passes, and the fixed-Q gauge remains stable.
11. **P7 -- decision and hybrid systems:** evaluate posterior predictive
   D-studies, adaptive monitoring/second scoring, real-time interventions, and
   human--machine rater configurations under explicit loss and fairness
   functions.

### Refined Critical Path

1. Use the completed `v0.1.1` reporting and evidence-governance release as the
   baseline for guarded scalar GMFRM and fixed-Q MGMFRM. Do not expand the API
   until diagnostics, fit-threshold provenance, prediction targets, and
   blocked-claim rows are consistently visible in reports and archives.
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
| Unmodeled response/testlet dependence | Checks whether pairwise residual screens detect clustering without labelling halo, task-specific severity, omitted dimensions, or sequence as a testlet effect. | Q3/adjusted-Q3 and cluster-PPC false-positive rate/power, reliability inflation, ability/rater/Q shifts, mechanism-misclassification, and whole-response heldout ELPD. | Keep local-dependence thresholds and fitted cluster effects experimental until null calibration and mechanism separation pass. |
| True fixed-Q MGMFRM | Checks whether multidimensional signal is recovered without inventing Q revisions. | Loading recovery, dimension ability recovery, rater consistency recovery, heldout ELPD improvement, posterior predictive category replication. | Supports fixed-Q interpretation only if diagnostics and recovery pass by block. |
| Missing required Q loading | Tests power to detect under-specified dimensions or item masks. | Candidate-cell detection, ELPD loss, item/dimension residuals, calibration shifts, changes in rater consistency and severity. | A detected issue can trigger local review, not automatic public Q editing. |
| False-positive Q loading or cross-loading | Tests overfitting and construct drift. | Loading shrinkage or instability, predictive gain/loss, decision reversal, false public-promotion rate. | Block promotion if extra loadings look plausible only because priors or sparse data support them. |
| Weak or sparse dimension support | Mirrors realistic rubric designs with limited items or anchors per dimension. | Dimension-specific ESS/R-hat, coverage, interval width, Q graph support, heldout rank stability. | Require warning or rejection when dimension claims are prior-dominated. |
| Rater-method noise and DFF-adjacent confounding | Separates rater behavior from multidimensional construct structure. | Rater consistency/severity shifts, grouped PPC, DFF screening rows, Q-revision false positives, heldout score changes. | Keep DFF and Q revisions diagnostic unless design support and sensitivity pass. |

The small linkage fixture is now implemented as
`mgmfrm_fit_threshold_q_heldout_linkage`. It links
`mgmfrm_fit_metric_threshold_sensitivity`, the empirical Q-matrix recovery
simulation grid, heldout-prediction simulation expectations, and fold-1 heldout
scoring outputs into one roadmap artifact. Its role is diagnostic: it records
threshold-profile sensitivity, Q-recovery risk, parameter-shift absorption, and
observed-versus-expected fold-1 rank matches while keeping public fit,
Q-revision, model-weight, and sparse-superiority claims blocked.

The `mgmfrm_full_heldout_mcmc_refit_anchor_scoring` fixture joins 50 scalar or
intercept/reference anchor rows to 75 fixed-Q candidate rows. That 125-unit
plan has now been executed locally at the publication-grade controls: all 375
result, diagnostic, and heldout artifacts are present, and all 125 units pass
their local diagnostic gates after targeted scalar refits. The downstream
threshold/model-weight review remains deliberately negative: only 24 of 500
threshold-profile job rows pass, no threshold profile is promoted, the
analytic null/reference ranks first in 24 of 25 folds, and Current Q has total
dELPD versus Null of `-153.200`. These are bounded local diagnostic results,
not public model-selection evidence. The remaining gate for broader validation
or comparison wording is valid external construct evidence plus an independent
signed public-scope review; local hardening can continue without releasing
model-weight or sparse-superiority claims.

### Uto-Style Inconsistency Diagnosis

The local Uto-style diagnostics now clarify an important failure mode. The
current compact batch can favor the Null/intercept reference, but that should
not be read as a basic contradiction of Uto-style GMFRM/MGMFRM conclusions.
When the data are generated from a source-aligned strong multidimensional
condition, the guarded fixed-Q true-Q MGMFRM recovers the expected direction
after MCMC.

The evidence is deliberately local and bounded:

| Diagnostic layer | Result | Roadmap interpretation |
| --- | --- | --- |
| Large Uto-style oracle | True-Q oracle dELPD vs Null `+417.079`. | Strong multidimensional signal and design support reproduce the expected direction. |
| Compact weak oracle | True-Q oracle dELPD vs Null `+4.195`. | Small margins can be overturned by estimation, prior, calibration, or support losses. |
| Source-aligned small MCMC | True-Q MCMC dELPD `+9.420`; loss vs oracle `-2.288`. | Guarded fit can recover the direction. |
| Replicated small MCMC | Recovery `1.0` across 3 seeds; minimum dELPD `+4.087`. | Not a one-seed result. |
| Internal prior sensitivity | Recovery `1.0` across default/tight/diffuse and 2 seeds; minimum dELPD `+3.798`. | Prior profile alone does not explain the pattern. |
| Calibration bridge | Strong `+9.420`; moderate oracle `+0.201` but MCMC `-4.855`; weak `+2.783`. | Thresholds and categories change conclusions. |
| Replicated calibration bridge | 2 seeds x 3 priors: strong recovery `1.0`; moderate `0.0`; weak `1.0` but threshold `4` pass `0.0`. | Not one-seed or prior-only. |
| MCMC-budget bridge | `20/20`, `80/20`, `20/80`, `80/80`: direction stable; one post-hoc thinning threshold cell changed. | Near-cutoff thresholds need calibration. |
| Category-calibration bridge | Strong/weak recovered; moderate stayed negative; `24` aligned cells and `0` caveats. | Require predictive plus category alignment. |
| Threshold false-alarm/power profile | Threshold `2`: power `1.0`, false promotion `0.0`; threshold `4`: weak power `0.0`. | Screening profiles only. |
| Threshold/Q-misspecification expansion | `13` scenarios, `11` axes, `4` false-add cells, `5` false-negative cells. | MCMC and category calibration needed. |
| Q-misspecification small MCMC | 5 scenarios: one threshold-`2` false promotion, one threshold-`4` false negative, `20` warnings. | Replicate and calibrate. |
| Replicated Q/category bridge | 2 seeds x 5 scenarios: threshold `2` false-promotion `0.2`; threshold `4` false-negative `0.2`; `40` warnings. | Public threshold wording remains blocked. |
| Q/category budget stability | `16/16` to `32/32`: false-promotion `0.2` to `0.3`; `4` labels changed; `40` warnings. | Not budget-stable. |
| Multi-axis diagnosis | Priority: sampler/budget, thresholds, false-add specificity, category, false-drop, rater-noise, split sparsity. | Treat as multi-causal. |
| Critical-cell follow-up grid | 4 cells, 12 runs, 4 split-seed jobs, min heldout category count `3`. | Split control and sampler remediation next. |
| Split-controlled critical grid | 4 cells x 2 splits: `4` risk labels changed; threshold `2` false-promotion `0.125`; `32` warnings. | Split variability is active. |
| Sampler-remediation pilot | Split-stable cell with `4` chains and `64/64`: threshold `2` false-promotion `0.0`; `8` warnings. | Diagnose warning surface next. |
| Warning-surface diagnosis | Same cell: `8` raw R-hat/ESS warnings; geometry/direct warnings `0`. | Budget/parameterization over thinning. |
| Block-targeted/draws-x2 follow-up | Top blocks: person, item, discrimination, item steps; `draws_x2` improved 3/3 but cleared 0/3. | Run `draws_x4` or chain-count gate. |
| Draws-x4 gate | Same 3 jobs: improved 3/3, cleared 0/3; failures are near threshold. | Chain-count plus parameterization audit. |
| Chain/rank gates | `512` retained draws cleared and replicated 3/3; `256/512` warmup/draws stayed clear; post-hoc thinning warned in 5/6 rows; guidance synthesis recommends local `4` chains, `128` warmup, `512` retained draws. | Surface guidance in reports; no default change yet. |
| Current compact Null-win batch | Scalar `-10.166`, Revised Q `-32.808`, Current Q `-33.027`, Sparse Q `-36.889` dELPD. | Diagnose calibration, Q/design support, and estimation loss. |

Consequence: source-aligned cases reproduce the Uto-style direction; the
Null-win case remains a signal/support/calibration/estimation problem. Public
fit-threshold, Q-revision, model-weight, and sparse-superiority claims remain
blocked. Next: surface local retained-draw guidance in reports.

### Canonical Current Evidence Checkpoint

The evidence tracks below are the current source of truth for roadmap
sequencing. The five-unit smoke and the full 125-unit publication-grade batch
are completed evidence stages, not future execution gates.

| Evidence track | Current state | Next gate |
| --- | --- | --- |
| Fixed-Q MGMFRM local batch | The 125-unit batch is complete locally; all 125 units pass their local diagnostic gates, but the downstream review promotes no threshold or model-weight policy. | Continue fixed-Q invariance, recovery, prior-sensitivity, design-robustness, and reporting hardening without converting heldout ranks into superiority claims. |
| Narrow MFRM/PCM overlap with TAM | In the primary fully crossed 100-person condition, package-versus-TAM direct agreement passes 5/5 and both workflows' known-truth recovery qualifiers pass 5/5 for item, rater, and item-step blocks. The 40-person stress rows show weaker recovery for item and item-step despite 5/5 direct agreement. A separate ConQuest 5.47.5 macOS fixture now covers single-run RSM/PCM known-truth transport and recovery, but not direct package agreement. | Obtain independent TAM and ConQuest re-execution and signed review, adjudicate the preserved TAM chronology difference, and execute genuinely overlapping FACETS outputs. Do not transfer this evidence to GMFRM/MGMFRM. |
| External construct and public-scope evidence | The request and intake contracts exist, but a valid external dataset manifest and signed independent public-scope review are not attached. | Accept only user-supplied, hash-bound, non-placeholder manifests; then score and release wording claim by claim. |

Accordingly, the active plan has two parallel tracks: an external-dependent
claim-review track and a local hardening track. Absence of external attachments
does not prevent implementation and simulation work, but it continues to block
construct-validity, broad validation, model-weight, Q-revision, and
sparse-superiority wording.

## Decision Gates and Fallback Paths

Each release should have a positive gate and a fallback gate. Passing the
positive gate allows promotion; failing it should narrow claims rather than
silently carrying risk into the next release.

| Release | Positive gate | Fallback if the gate fails |
| --- | --- | --- |
| `v0.1.1` (completed) | Existing guarded scalar GMFRM and fixed-Q MGMFRM fits were made more auditable through diagnostics, report sections, prior policy, predictive path labels, and blocked-claim rows. | Historical fallback: narrow the release to documentation, manifest, and report-governance improvements; keep guarded examples minimal and mark unresolved diagnostics as blockers. |
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
| A multidimensional or dynamic term absorbs response clustering | Within-response residual dependence disappears only after adding Q loadings or drift, but whole-response prediction fails or the effect changes under a testlet/halo candidate. | Fit the predeclared competing mechanisms, inspect Q-by-testlet and rater-within-response support, and block dimension, halo, and drift wording until the decomposition gate passes. |
| Category functioning is mistaken for automatic data cleaning | Skipped categories, rater-specific category compression, or disordered steps appear, and examples imply categories should be collapsed automatically. | Make category rows diagnostic-only and require user-confirmed design or scoring changes outside the model report. |
| Comparison rows become model-selection claims | WAIC/LOO/K-fold ranks flip under target changes, influential rows, Pareto-k warnings, or heldout splits. | Keep comparison as local diagnostic evidence; block model weights, sparse-superiority, and manuscript-level selection claims. |
| External validation is forced onto non-overlap targets | Facets/TAM/mirt/sirt/immer outputs use different constraints, priors, dimensions, estimands, or estimation targets. | Mark the case as non-overlap and use it for terminology or migration notes, not validation. |
| Documentation drifts ahead of manifests | README, docs, report tables, or release notes advertise broader GMFRM/MGMFRM support than `release_scope_summary` and `model_surface_audit` allow. | Treat `release_gate_check` failures as release blockers and narrow the wording before code promotion. |
| Evidence artifacts leak more data than intended | Bundles include raw labels, row-level data, institution names, or unreviewed case-study files. | Make raw-data export opt-in and require explicit anonymization/provenance rows before sharing artifacts. |

## Release Decision Record Template

Every generalized release candidate should leave a short decision record. The
record is not a release note; it is the evidence trail for why the surface was
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
| Modern generalized diagnostics need promotion evidence | Rank-normalized split R-hat, bulk ESS, tail ESS, structurally fixed coordinate handling, and complete-chain E-BFMI accounting are implemented, but implementation alone does not validate interpretation-supported generalized claims. Historical publication-grade runner artifacts predate the versioned contract and remain classical compatibility evidence. | Exercise raw and applicable direct block-level pass/fail rows, zero-raw-dimension versus reconstructed-varying transforms, incomplete E-BFMI coverage, the Stan/posterior odd-draw and lag contract, and versioned cache invalidation in new fits. Keep wrapper schemas at version 1, but do not reinterpret rows lacking `rank_normalized_rhat_bulk_tail_ess_v1`. | Blocks interpretation-supported generalized claims, not authorization of the LD1b1 protocol; pilot execution still has its own executor, smoke, completed-attempt seal, and recovery gates. |
| Fixed-Q invariance checks are incomplete | Dimension labels and loading signs can look stable when the gauge is actually doing the work. | Add fixed-sign, fixed-identity-correlation, positive-loading, and direct-constraint invariance checks. | Blocks broader fixed-Q claims and non-confirmatory expansion. |
| Prior sensitivity is not yet tied to focal decisions | Weak priors can determine rater consistency, loading, or sparse DFF-adjacent conclusions. | Connect prior predictive rows, prior-scale grids, and power-scaling shifts to report decision labels. | Blocks ranking and practical-decision language. |
| Predictive targets are not yet uniformly attached to comparison rows | WAIC, LOO, and K-fold can answer different questions if row matching or targets differ. | Require prediction-target, row-matching, candidate-set, and influential-row fields before interpretation. | Blocks model weights and superiority claims. |
| Local-dependence calibration and cluster prediction are incomplete | Report-only pair summaries, the LD1b0/LD1b1 preflights, and the MCMC-free batch harness dry run do not establish operating characteristics, and row-level prediction can leak shared response/testlet information. | First materialize and pin the single-job executor, pass bounded smoke, add a completed-attempt seal, and pass interrupted-attempt recovery review. Then execute the authorized pilot and frozen evaluation with the modern sampler-diagnostic gate, followed by calibrated pair/cluster PPC and conditional versus whole-response marginal prediction. | Blocks testlet/halo interpretation and any claim that row-level LOO validates clustered ratings. |
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
| 2. Overlap review | Decide whether the external target estimates the same estimand or only a related quantity. | Label non-overlap explicitly and do not count disagreement as validation evidence. |
| 3. Known-truth simulation | Generate data from a target both workflows can represent, with fixed seeds and documented design support. | If either workflow cannot represent the target, narrow the target or drop the comparison. |
| 4. Recovery metrics | Compare bias, RMSE, interval coverage, calibration, rater-effect recovery, loading recovery, and failure rates. | Treat runtime or point estimates alone as insufficient. |
| 5. Computation metrics | Record divergences, convergence warnings, ESS/sec where applicable, elapsed time, memory, and failed fits. | Do not make performance claims without sampler-quality context. |
| 6. Reporting comparison | Compare scale conventions, constraints, practical summaries, and diagnostics users actually see. | Document translation rules; avoid claiming one tool is wrong when scales differ. |
| 7. Real-data demonstration | Only after known-truth behavior is understood, run compact real data as workflow evidence. | Treat unexplained disagreement as an investigation item, not validation. |

For FACETS and ConQuest, the first transport layer is now implemented without
requiring either executable on the Mac that prepares an analysis. The
version-1 bridge compiles only unanchored, one-dimensional, unit-weighted
MFRM/RSM/PCM controls; FACETS has a Windows launch path and ConQuest has
Windows and macOS paths. The hardened ConQuest macOS path now has receipt-bound
5.47.5 Demonstration RSM/PCM known-truth fixtures with retained control,
manifest, verifier, runner, receipt, and privacy-reduced output samples. This
establishes version-specific transport and point-recovery evidence, not
independent execution, convergence, or direct package agreement. The next
external work must independently re-execute ConQuest, execute FACETS and the
Windows paths, validate the destination first-reference gauge transform and a
convergence policy, and then review an aligned numerical-comparison artifact.
The exact 5.47.5 three-category source-gauge semantic map is already locally
validated. Anchors remain a second-stage compiler target until the destination
transform and comparison establish stable targets for the exact external
design.

## Competitive Weaknesses and Mitigation

The package should be honest about where the R ecosystem is stronger. TAM,
mirt, sirt, immer, and Facets are mature tools with broad model coverage,
worked examples, and established user expectations. `BayesianMGMFRM.jl` should
not try to win by implementing every IRT model. It should win only where a
Bayesian MGMFRM-specific workflow can be more explicit, auditable, and
reproducible.

### Separate Maturity, Feature-Parity, and Estimator-Parity Axes

A single completion percentage obscures three different questions. The roadmap
must score them separately and must name the denominator whenever a percentage
is reported.

| Axis | Current interpretation | Roadmap consequence |
| --- | --- | --- |
| Declared Bayesian MFRM/RSM/PCM scope | The stable minimal path includes identified RSM/PCM likelihoods, Bayesian fitting, posterior summaries, diagnostics, PPC/calibration, category/rater practitioner summaries, fair averages, separation/reliability rows, Wright-map data, FACETS-labelled compatibility rows, reports, caches, and reproducibility support. On this deliberately bounded implementation denominator, maturity is about 96%; the remaining work is mainly staged stress execution, actual hard-anchor refitting, new-summary report integration, and independent overlap evidence rather than a missing core estimator. | Track the remaining evidence and usability work explicitly. Do not lower this percentage merely because the package does not reproduce every FACETS/TAM feature or estimator. |
| FACETS/TAM practitioner-feature parity | Practitioner-facing coverage is substantial but partial. The package provides familiar summaries, compatibility labels, and a fail-closed offline FACETS/ConQuest input-and-receipt bridge, while FACETS and TAM retain broader model catalogs, mature import/export conventions, established graphical and batch workflows, and a much larger body of operational examples. Full product parity is not a declared release goal. A ConQuest 5.47.5 RSM/PCM output sample and a three-category source-gauge semantic adapter now exist, but destination-gauge alignment and independent review remain open. | Execute FACETS samples only for genuinely overlapping targets, independently re-execute ConQuest, validate the separate gauge and comparison layers before numerical claims, and record non-goals instead of duplicating unrelated IRT breadth. |
| JMLE/MMLE estimator parity | Bayesian HMC/NUTS is the package's intended estimator. FACETS-style JMLE and TAM-style MMLE/EM are not alternate fitting engines in this package, so their absence is an estimator-scope difference rather than incomplete Bayesian MFRM implementation. The completed TAM study supports only a narrow fully crossed unit-discrimination MFRM/PCM overlap and does not establish general estimator equivalence. | Compare estimators only under aligned likelihoods, constraints, scales, and known truth. Keep independent re-execution/review and licensed-host FACETS/ConQuest comparison evidence open; do not treat numerical agreement as proof that posterior and frequentist uncertainty summaries have the same interpretation. |

This separation also clarifies release language: a high declared-scope MFRM
maturity score can coexist with partial FACETS/TAM feature parity and no plan to
embed JMLE or MMLE as interchangeable estimators.

The package now exposes the same positioning table programmatically through
[`related_software_capability_matrix`](@ref). The table is a scope-governance
artifact, not a validation result or superiority claim.

| Tool | Established strength | BayesianMGMFRM overlap | v0.1.1 recorded stance |
| --- | --- | --- | --- |
| [Facets](https://www.winsteps.com/facets.htm) | Mature many-facet Rasch measurement workflow, facet maps, fit tables, and practitioner reporting. | MFRM-facing outputs such as severity, fair averages, fit statistics, maps, and sparse-design warnings. | Migration and terminology reference, not a replacement claim. |
| [TAM](https://cran.r-project.org/web/packages/TAM/refman/TAM.html) | Broad R IRT toolkit including Rasch/PCM/GPCM, multidimensional IRT, and multi-faceted Rasch models. | MFRM/PCM/GPCM and fixed-Q multidimensional cases where targets genuinely overlap. | Breadth baseline; do not duplicate generic IRT coverage just to match TAM. |
| [mirt](https://www.jstatsoft.org/article/view/v048i06) | Exploratory and confirmatory multidimensional IRT with mature estimation and diagnostics. | Fixed-Q MIRT expectations and multidimensional loading interpretation. | Multidimensional baseline, not a dedicated many-facet replacement. |
| [sirt](https://cran.r-project.org/web/packages/sirt/sirt.pdf) | Supplementary IRT methods, including specialized model, diagnostic, and rater-related tools. | Rater-effect, DIF/DFF, and diagnostic-method context. | Specialized-method reference; `v0.1.1` kept fitted DFF effects blocked. |
| [immer](https://cran.r-project.org/web/packages/immer/immer.pdf) | Item response models for multiple ratings and rater-mediated designs. | Multiple-rating and rater-effect context. | Rater-model reference; overlap comparison waits until post-v0.2.0. |
| [brms](https://cran.r-project.org/web/packages/brms/brms.pdf) / [Stan](https://mc-stan.org/docs/stan-users-guide/item-response-models.html) | Flexible Bayesian multilevel and custom IRT modeling with HMC/NUTS diagnostics. | Bayesian diagnostics, posterior predictive checks, custom IRT targets, and model-comparison workflow. | Bayesian workflow baseline, not a packaged MGMFRM substitute. |
| `BayesianMGMFRM.jl` | Source-audited Julia workflow for Bayesian MFRM, guarded rater-consistency GMFRM, and fixed-Q confirmatory MGMFRM artifacts. | Own current public surface. | Narrow auditable workflow; generic IRT replacement and superiority claims remain blocked. |

| Weakness | Why it matters | Mitigation target |
| --- | --- | --- |
| Narrower model coverage than TAM/mirt/sirt/immer | Users may expect broad IRT, MIRT, DIF, latent-class, plausible-value, and HRM coverage. | Maintain a related-software matrix and state non-goals clearly. Add features only when they strengthen the MGMFRM workflow rather than duplicating generic IRT coverage. |
| Generalized paths are still guarded | A runnable experimental MGMFRM is not the same as stable public MGMFRM. | Keep `experimental_public` labels until source, transform, prior, HMC, recovery, and reporting gates pass. Treat real-data validation and R-package overlap comparison as post-`v0.2.0` evidence. |
| Bayesian priors add responsibility | Weak priors can stabilize sparse designs but can also drive results. | Require prior predictive checks, prior-scale grids, and prior/likelihood power-scaling sensitivity before focal generalized claims. |
| HMC diagnostics are more demanding than MML/JML output | Users can mistake posterior intervals for valid inference even when chains fail. | Use the implemented rank-normalized R-hat, bulk/tail ESS, divergence, max-depth, E-BFMI, raw/direct block diagnostics, and failure flags as first-class report sections. |
| Practitioner workflow parity with Facets/TAM remains partial | The package now provides FACETS-labelled MNSQ/ZSTD compatibility rows, posterior separation/reliability summaries, category-functioning and pairwise-rater rows, fair averages, rater diagnostics, Wright-map data, a FACETS/ConQuest migration crosswalk, deterministic offline transfer bundles, a version-specific ConQuest 5.47.5 macOS RSM/PCM execution fixture, and a narrow three-category source-gauge semantic adapter. FACETS execution, Windows-path execution, destination-gauge alignment, direct package agreement, and independently reviewed numerical overlap evidence remain absent. | Maintain the Bayesian caveats, execute only matched known-truth bundles on authorized hosts, independently re-execute ConQuest, validate the separate gauge and comparison layers, and keep anchored second-stage compilation and full product parity as separate later decisions. |
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

### v0.1.1 release record: Fixed-Q Confirmatory MGMFRM Refinement

**Recorded goal:** make the existing fixed-Q guarded MGMFRM path
auditable and hard to overinterpret.

**Research basis:** Uto's MGMFRM is confirmatory in spirit for rubric
dimensions and uses NUT-HMC; Bayesian workflow literature requires diagnostics,
predictive checks, and validation evidence before claims.

The list below preserves the original plan. `v0.1.1` shipped only the narrowed
auditability, portable-report, fixed-Q, FACETS-description, reproducibility,
and runnable-example subset; unfinished items continue under `v0.1.2` or later.

**Historical implementation plan:**

- `q_matrix_validation` now strengthens the current fixed-Q
  path: binary-mask schema checks, empty dimensions, empty item rows, duplicate
  or aliased columns, fixed cross-loading policy, dimension/facet subgraph
  coverage, and item blocks that cannot identify positive interpreted loadings.
- Add rating-design review rows: structural versus accidental missingness,
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
- Generalized diagnostics are standardized across `GMFRMFit` and `MGMFRMFit`:
  divergences, max-depth hits, complete-chain E-BFMI coverage, rank-normalized R-hat,
  bulk/tail ESS, direct-constraint failures, pointwise log-likelihood
  finiteness, and parameter-block pass/fail flags. Raw unconstrained and direct
  constrained rows both enter the gate unless a direct coordinate is fixed by
  a zero-raw-dimension transform. Those coordinates remain visible as
  non-gated `:structurally_fixed` rows; reconstructed coordinates that vary
  with free raw coordinates remain gated. Classical `rhat`, `ess`, and the
  minimum available `e_bfmi` remain compatibility fields. The general `flag`
  follows `rank_normalized_flag`, and `classical_compatibility_flag` remains
  separate. A versioned diagnostic contract protects cached generalized
  surfaces and distinguishes modern rows from pre-modern version-1 wrappers.
- Add a binary-response interpretation note to the docs and reports: the
  two-category MFRM is a many-facet Rasch/1PL IRT model, while binary
  GMFRM/MGMFRM variants with item discrimination, rater consistency, or
  multidimensional Q-masked loadings are generalized IRT models rather than
  strict Rasch models.
- Keep `fit_stats` as the default Bayesian fit diagnostic. Use the separate
  `facets_report` compatibility surface only for labelled, unit-weighted
  MFRM/RSM/PCM plugin rows; generalized fits remain rejected.
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

**Historical implementation order and runtime policy:**

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

**Recorded exit gate:**

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
- Carry those threshold profiles into the publication-grade refit batch review
  so every executed fold can be read under multiple cutoffs before threshold
  wording, model weights, or sparse-superiority language is considered.
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

**Current quarantined checkpoint (2026-07-23):** the exactly two-dimensional
slice now has a normalized LKJ prior on a `tanh` correlation coordinate,
analytic/AD/finite-difference checks, a quarantined sampler, a response-level
known-truth generator, and a single-dataset multichain pilot. The generator
checks a separately coded direct-scale closed-form probability oracle as well
as the shared-kernel replay. The scalar likelihood hot path now caches the
fixed simple-Q integer layout; on the frozen 300-person first unit this reduced
steady-state initial ForwardDiff gradient time by about 93% (roughly 14.7x)
and allocation by about 93%, while retaining the pointwise source path as an
independent reference.

A frozen version-2 replicated-study control plane now fixes 25 feasibility and
500 evaluation units over five correlations, separates new
ability/response/sampler seed namespaces, preserves every planned unit and
categorized failure in its denominator, and binds evaluation execution to a
digest-backed feasibility decision. Version 1 was retired before scientific
execution and is recorded as the predecessor. Version 2 is pinned to plan
fingerprint `d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3`
and unit-roster SHA-256
`0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08`.
Its future result schema requires exact runtime/environment/source provenance,
canonical fixture signatures, and per-array plus aggregate sample-bundle
digests. Each future unit result must bind plan, unit, seeds, generation
evidence, exact sampler controls, and the sample aggregate; cross-unit replay
and mixed execution environments then fail closed. The
feasibility decision carries rederived protocol-integrity evidence instead of
relying on an unsubstantiated Boolean. Its pure scorer separates conditional
from fixed-denominator coverage, reports Wilson uncertainty, distinguishes
execution failure from noncoverage, treats zero-correlation direction as not
applicable, and evaluates symmetry as unpaired because the positive and
negative cells use independent seeds. Continuous missing-outcome sensitivity
uses exact-rational endpoint-enumerated full-denominator envelopes with
directed Float64 bounds: only a lower bound beyond a limit is a hard failure,
while a boundary-crossing upper bound is inconclusive.

Protocol eligibility is now separate from operational authorization. The
initial-gradient resource probe and the pre-execution archive harness are
MCMC-free; the latter uses no-replace hard-link publication for dry-run
diagnostics and rejects all scientific attempt states that it cannot create.
Its post-load file snapshot is explicitly not loaded-code attestation, and its
self-hashes are not an external authenticity anchor. Scientific execution
remains fail-closed. This remains planning,
implementation, orchestration, performance, and scorer evidence: the 25
scientific feasibility fits and 500 evaluation fits have not run.
The compatibility `study_run_unit` entry point is permanently preflight-only,
so changing the operational gate alone cannot connect it to a sampler; a
separate non-public atomic worker must validate all archive receipts before
future scientific execution.
The first production pre-execution dry run was retained as historical lineage
after the public `study_run_unit` path was made permanently preflight-only
(17,584 bytes; file SHA-256
`4bc95ae2903310abab20d6a47a67e784a61e3bae28562e738323544f436539a0`;
content identity
`de7861f89e805aa17d5fcd4e7faec90eb885ea14223792c6d062002e309aeb8f`).
A replacement current-source dry run was published by no-replace hard link and
immediately validated against the current source and stable environment
snapshots (17,711 bytes; file SHA-256
`5911eee0653f4c4f20fd7d74221d9f2044fc15d50331f5189312a83c16ddadca`,
content identity
`96b724c2501a21225a03b280308de678c99534ab2228b9b0560ba7df35793178`,
validation-record identity
`c712f75703685dbf3f41872aeba6c085eb43ee86a8a16947f0c058a09d610ddc`).
The two dry-run files are workspace-local under the git-ignored `artifacts/`
tree; the validation identity is a returned object and was not persisted as a
separate record. They are not repository-distributed or externally archived.
Neither dry run created scientific unit/attempt state; both remain
self-consistency evidence only, without authenticity or timestamp attestation.
The frozen plan still records `resource_probe_completed = false`,
`short_nuts_resource_profile_completed = false`, and both operational and
scientific execution authorization as false; an optional local initial-gradient
measurement does not mutate those preregistered facts.
The 2026-07-23 three-repetition Julia 1.12.5 measurement had median gradient
time `0.0441816` seconds, median allocation `85,811,848` bytes, zero measured
GC time, and a frozen 32-gradients-per-transition planning projection of
`5,655.2448` seconds. Those thresholds passed, but that projection is neither
a measured short-NUTS runtime nor a worst-case upper bound. Minimum free memory
was 2.580 GiB against the frozen 8 GiB minimum, so the overall resource gate
failed closed. The returned local
artifact identity was
`78bc652642dc61ff49c109d208fd910bcf15391ce7e8389b1522838392625d2f`;
it is not externally anchored and is not scientific execution evidence.
Replicated recovery, separate prior and likelihood sensitivity,
misspecification stress, an independently reproduced decision artifact, and
higher-dimensional LKJ-Cholesky parameterization remain pending; every current
artifact retains `recovery_verified = false`.

**Implementation work:**

- Retain the completed 2D `tanh`/LKJ slice in quarantine and implement a
  Cholesky-factor policy before generalizing free correlation beyond two
  dimensions.
- Freeze and pass the MCMC-free initial-gradient resource profile, then add a
  bounded short-NUTS resource profile that measures transitions, peak memory,
  and failure behavior without making recovery claims.
- Complete an atomic single-unit scientific worker with immutable attempt
  reservation, terminal-result persistence, and a separate raw-draw archive
  sufficient to recalculate R-hat/ESS independently. Execute that worker from
  a source snapshot captured before package load and anchor its final digest in
  append-only or signed storage outside the attempt tree. Only then run one
  bounded feasibility unit and review it before considering the remaining
  frozen feasibility roster. Evaluation remains blocked unless the
  computation-only feasibility decision passes.
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
- The publication-grade refit gate is frozen before heavy runs: 4-chain NUTS
  controls, R-hat/ESS/HMC diagnostic thresholds, posterior-predictive checks,
  expected-score calibration, heldout ELPD/K-fold summaries, and public-claim
  blockers are recorded before the first single-cell pilot is executed.
- The publication-grade runner chain has completed the five-unit smoke and the
  full 125-unit local batch. The result-review layer records all 375 expected
  artifacts and zero final local diagnostic-gate failures while keeping
  threshold profiles, model weights, Q-revision, and sparse-superiority claims
  blocked. The next external-dependent gate is a valid external construct
  dataset manifest plus an independent signed public-scope review; the next
  local gates are fixed-Q recovery, design-robustness, sensitivity, and
  reporting hardening.
- Compact workflow demonstrations can run end to end, but real-data validation
  and R-package overlap comparisons are not required for `v0.2.0` completion.
- Rating-design reviews, category-functioning diagnostics, pooling-policy rows,
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
- Do not treat a residual correlation as proof of a testlet effect, halo, or
  substantive dimension; compare the predeclared competing mechanisms under an
  identified design.
- Do not use observation-row LOO as evidence for a new response when a shared
  response/testlet random effect was learned from other rows in that response.
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
