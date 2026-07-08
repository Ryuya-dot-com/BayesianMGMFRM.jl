# Minimal Bayesian Fitting

The first Bayesian fitting paths target the same minimal additive MFRM/RSM/PCM
design returned by `getdesign`. They place independent zero-centered normal
priors on the identified parameter vector. `backend = :julia` uses a
random-walk Metropolis kernel for small validation examples, while
`backend = :advancedhmc` uses the package's `MFRMLogDensity` target with
AdvancedHMC/NUTS and `backend = :turing` wraps the same target in a
Turing/NUTS model.

## Guarded Generalized Model Caveats

The public `fit` path is currently limited to fit-supported MFRM/RSM/PCM
specifications by default. Narrow guarded experimental exceptions exist for
source-aligned generalized candidates: `fit(spec; experimental = true)` returns
[`GMFRMFit`](@ref) when the spec is one-dimensional, `family = :gmfrm`,
`discrimination = :rater`, and still on the specified-only manifest path; it
returns [`MGMFRMFit`](@ref) for the fixed-Q confirmatory `family = :mgmfrm`
candidate with `dimensions >= 2`. Unsupported generalized options, public
`MFRMPrior` priors for generalized raw-coordinate fits, exploratory MGMFRM
loadings, free latent correlations, and non-rater GMFRM discrimination specs
are rejected. Other specified-only GMFRM and MGMFRM specs remain inspection
surfaces: they can expose manifests, constraint tables, preview rows, and
fixture evidence without silently fitting the wrong likelihood.

The scalar GMFRM promotion candidate remains guarded. Its source-aligned Julia
fixture, BridgeStan oracle, direct-parameter checks, candidate-chain artifact,
and recovery-smoke artifact are evidence for the narrow public experiment, not a
public prior contract for arbitrary GMFRM variants. The committed small and medium
scalar Stan/BridgeStan log-density and gradient fixtures can be summarized with
[`stan_validation_row`](@ref) and [`stan_validation_summary`](@ref); that gate
is scalar fixture evidence, not a public generalized Stan-fit comparison. The
local guarded-exposure review
now records the fit API dry-run contract, the guarded method-wiring artifact,
the experimental fit validation grid, the posterior predictive grid, and the
sparse-pathology recovery grid plus the prior/likelihood sensitivity grid; the
compact real-data case study, local full-paper reproduction archive, local
confirmatory MGMFRM guarded fit method-wiring artifact, and local confirmatory
MGMFRM guarded fit validation-grid plus guarded fit API dry-run, guarded public
exposure-review, and prediction/model-weight policy artifacts are also
recorded. The fixed-Q confirmatory MGMFRM guarded sampler is now wired through
`fit(spec; experimental = true)`, while broader generalized exposure remains
blocked by stronger validation evidence and manual publication or registration.
A local claim-level recovery/reproduction archive manifest and a
broader experimental exposure decision review now record fixture hashes,
generator commands, source references, local verification commands, and the
guarded-scalar-only exposure decision. A local DFF estimand/validation grid is
also recorded as validation-only evidence; fitted DFF model effects remain
blocked. A local Gate E manuscript-scale evidence grid aggregates the versioned
fit-validation, posterior predictive, sparse-pathology, sensitivity, real-data,
DFF, and confirmatory MGMFRM sparse artifacts. Longer local stress-chain
evidence, an initial
same-observation
baseline comparison, a three-scenario baseline/calibration grid,
interval/decision and sparse-design grids, a WAIC influence review, the
raw importance-sampling LOO/Pareto-k review, a deterministic 3-fold refit
review, a guarded fit API dry-run artifact, the raw-prior Jacobian policy, and
the experimental generalized fit-artifact contract are recorded internally. The
guarded scalar GMFRM and fixed-Q confirmatory MGMFRM methods now populate that
contract locally. The scalar GMFRM path also passes the local validation,
posterior predictive, sparse-pathology recovery, and prior/likelihood
sensitivity grids, while broader GMFRM/MGMFRM surfaces remain blocked.

The first MGMFRM candidate remains narrow: a confirmatory fixed-Q candidate with
fixed identity latent correlation, standard-normal ability scale, positive
interpreted Q-masked loadings, and source scale `1.7`. Its BridgeStan oracle,
candidate-chain artifact, recovery-smoke artifact, and connected sparse-recovery
grid are still centered on compact guarded evidence; higher-dimensional fixed-Q
support is covered by local Julia smoke tests before broader validation is
claimed. They do not support exploratory loadings, free latent correlations,
sparse-design superiority claims, or public model-weight claims. A local
same-observation baseline-comparison artifact is recorded as evidence, but it is
not a model-selection claim. The guarded experimental MGMFRM fit path populates
the same raw-prior/Jacobian policy and fit-artifact contract for the fixed-Q
confirmatory candidate.

### Uto-Style Direction Check

A local Uto-style diagnostic now separates three questions that should not be
collapsed:

1. whether a correctly specified multidimensional source model has an oracle
   advantage over a Null/intercept reference;
2. whether the guarded fixed-Q MGMFRM fit can recover that direction after
   MCMC under source-aligned strong-signal data;
3. why the current compact publication-grade batch can still favor the Null
   reference.

The local reports answer the first two questions positively under the tested
conditions. A 3-seed replicated small-MCMC grid recovered the true-Q MGMFRM
direction in all seeds, with mean dELPD vs Null `+8.862` and minimum margin
`+4.087`. An internal source-fixture prior sensitivity grid over `default`,
`tight`, and `diffuse` profiles also recovered the direction in all tested
seed/profile cells, with mean dELPD vs Null `+6.789` and minimum margin
`+3.798`.

The same diagnosis explains why this does not license a broad MGMFRM
superiority claim. The current compact Null-win batch has much larger
structured-model losses, including Current Q dELPD vs Null `-33.027`, Revised Q
`-32.808`, and Sparse Q `-36.889`. That pattern points to signal strength,
category calibration, Q support, prior sensitivity, and posterior recovery loss
as the next diagnostic targets. It does not show that fixed-Q MGMFRM is
inherently unable to reproduce Uto-style conclusions.

A local calibration bridge now makes the threshold issue explicit. In the
strong source-aligned condition, true-Q MCMC remained positive (`+9.420` dELPD
vs Null). In a moderate transition condition, the oracle margin was only
`+0.201` and the MCMC refit flipped to `-4.855`. In a weak compressed-category
condition, true-Q MCMC was positive but small (`+2.783`), clearing `0` and `2`
dELPD thresholds but not `4` or `8`. This is evidence that fit-threshold choices
must be treated as a profile before they are promoted to package-facing
guidance.

The replicated bridge keeps that interpretation under 2 seeds and 3 internal
prior profiles. The strong source-aligned condition recovered in every cell
(minimum true-Q MCMC dELPD vs Null `+3.798`), the moderate transition condition
recovered in no cell (mean `-6.022`), and the weak compressed-category condition
recovered in every cell but never cleared the `4` dELPD threshold after MCMC.
The internal prior profiles had the same overall scenario-recovery rate
(`0.6667`), so profile choice is not the main explanation in this small
diagnostic.

A local MCMC-budget bridge now checks whether the bridge result is mostly a
short-chain artifact. It reruns the same generated rows and splits under
`20/20`, `80/20`, `20/80`, and `80/80` warmup/draw budgets. No non-baseline
budget changed the recovered/not-recovered direction. The strong condition
remained positive across all retained-draw budgets (minimum `+9.420`), the
moderate condition remained negative (maximum `-4.580`), and the weak
compressed-category condition still failed the all-retained dELPD `4` threshold.
Post-hoc retained-draw thinning changed one near-cutoff threshold cell, so
thinning can affect boundary threshold calls. It should not be interpreted as
sampler-level thinning because the current `fit` API exposes warmup, retained
draws, and chains, but not a sampler thinning argument.

A category-calibration bridge now links those threshold calls to heldout
category-probability calibration. In the strong source-aligned condition,
true-Q MCMC improved log score, Brier score, category distribution distance,
and cumulative threshold distance versus Null. In the weak compressed-category
condition, true-Q MCMC also improved the category-calibration metrics versus
Null, but its log-score gain remained below the `4` threshold (`+2.783` under
the baseline budget and `+3.323` under the increased budget). In the moderate
transition condition, true-Q MCMC was worse than Null both predictively and in
category calibration. Thus the weak threshold-`4` failure is a magnitude and
cutoff issue in this local check, not a category-calibration reversal.

A threshold false-alarm/power profile now treats the candidate cutoffs as
simulation profiles rather than defaults. In the replicated bridge, threshold
`2` had signal power `1.0` and negative-control false promotion `0.0`, but its
maximum competing scalar/wrong-Q pass rate was `0.6111`; therefore it can only
be read as a screening profile, not as Q-validation evidence. Threshold `4`
had weak-signal power `0.0`, so it creates a false-negative risk for
compressed-category conditions even though it reduces competing-model passes.

A threshold/Q-misspecification expansion now connects that profile to the
empirical Q-matrix recovery grid and adds an explicit null requirement. It
records `13` scenarios across `11` expansion axes. Threshold `2` creates `4`
false-add specificity cells that need explicit Q/noise simulations; threshold
`4` creates `5` false-negative risk cells for false-drop and weak-dimension
cases. This is a pre-execution map: it says which simulations must be run next,
not which cutoff should be used.

A first small Q-misspecification MCMC batch now runs the representative
explicit-null, false-add, false-drop, weak-dimension, and rater-noise proxy
cases. Threshold `2` produced `1` candidate false-promotion cell and threshold
`4` produced `1` false-negative cell. All `20` MCMC model rows have short-chain
diagnostic warnings, so this remains a screening result; it needs replication,
larger MCMC budgets, and category-calibration joins before threshold policy.

A replicated Q-misspecification/category bridge now makes that join explicit.
Across 2 seeds and 5 scenarios with 2-chain `16/16` warmup/draw settings,
threshold `2` had candidate false-promotion rate `0.2`, threshold `4` had
false-negative rate `0.2`, and `2` seed-scenario cells had predictive gain with
a category-calibration caveat. All `40` MCMC rows still had sampler warnings,
so the practical rule should remain predictive-plus-category screening, not a
public cutoff.

A Q/category budget-stability check then reruns the same replicated Q scenarios
under `16/16` and `32/32` warmup/draw profiles. Threshold `2` false-promotion
rate moved from `0.2` to `0.3`, threshold `4` false-negative rate stayed
`0.2`, `4` threshold risk labels changed, and the `32/32` profile still had
`40` warning rows. The threshold rule is therefore not budget-stable enough for
public wording.

A multi-axis instability diagnosis now ranks alternative explanations instead
of assigning the problem to a single cause. The highest-priority mechanisms are
sampler/budget instability, threshold-cutoff sensitivity, and false-add Q
specificity. Category calibration mismatch, false-drop seed variability,
rater-noise/competing structure, and heldout category sparsity also remain
high-priority. Prior profile alone and a broad "MGMFRM is impossible"
interpretation are low-plausibility under the local evidence.

A critical-cell follow-up grid now reconstructs the base seeds for the 4
budget-sensitive cells and maps them to 12 targeted follow-up runs. The heldout
category-support screen is adequate in every baseline critical cell (minimum
heldout category count at least `3`), so the next technical gate is split-seed
control plus sampler-remediation, not another broad unfocused simulation.

A split-controlled critical grid now decouples generation seeds from holdout
split seeds on those 4 cells. Across 2 split offsets, `4` threshold risk labels
changed and all `32` MCMC model rows still had sampler warnings. In this
restricted pilot, threshold `2` false-promotion rate was `0.125` and threshold
`4` false-negative rate was `0.0`; the important result is that split
variability itself remains active.

A sampler-remediation critical pilot then reruns the split-stable critical cell
with a larger local MCMC budget (`4` chains, `64/64` warmup/draws, target
acceptance `0.85`). Threshold risk labels stayed stable and threshold `2`
false-promotion fell to `0.0`, but all `8` selected MCMC model rows still had
`mcmc_warning` flags. The next gate should diagnose the warning surface itself
rather than simply adding more retained draws.

A warning-surface diagnosis now records that same split-stable cell with block
and chain diagnostics. All `8` warning rows are raw R-hat/ESS warnings, while
sampler warnings, nonfinite log-density, divergences, max-tree-depth hits, and
direct-transform failures are `0`. This makes thinning a poor first-line
remediation; block-targeted draws, chains, or parameterization checks are the
next local gate.

A block-targeted follow-up plan ranks the warning-heavy raw blocks before
launching a larger grid. The top targets are `person`, `item`,
`log_item_dimension_discrimination`, and `item_steps`; the first executable
profile is `draws_x2_smoke`. That smoke run reran 3 priority model/split cells
with `4` chains, `64` warmup draws, and `128` retained draws per chain. Minimum
ESS and maximum R-hat improved in all 3 jobs and warning counts fell, but all 3
jobs still had `mcmc_warning`. The next gate is therefore a `draws_x4` or
chain-count check, not public threshold wording.

The `draws_x4` gate then reran the same 3 cells with `4` chains, `128` warmup
draws, and `256` retained draws per chain. Minimum ESS and maximum R-hat again
improved in all 3 jobs beyond `draws_x2`, with bad-Rhat and low-ESS counts
falling sharply. None of the 3 jobs fully cleared `mcmc_warning`, but the
remaining failures are near threshold: one row has max R-hat `1.0147` and min
ESS `328.2402`, one has max R-hat `1.0096` and min ESS `353.5260`, and one has
max R-hat `1.0109` with min ESS `403.0495`. The next gate should separate chain
count from parameterization rather than simply endorse thresholds.

A chain-count gate then reran the same 3 cells with `6` chains, `64` warmup
draws, and `128` retained draws per chain. Compared with `draws_x4`, 0/3 jobs
improved maximum R-hat, 0/3 improved minimum ESS, and 0/3 cleared warnings. A
Stan-guided review therefore records the next gate as rank-normalized R-hat,
bulk/tail ESS, and parameterization audit. The decision follows Stan diagnostic
practice: high R-hat/low ESS are validity warnings, thinning is not the primary
remediation, and difficult hierarchical geometry should be checked through
parameterization. Relevant sources include Stan's diagnostics page, the
`posterior::ess_bulk` documentation, Stan User's Guide efficiency tuning, and
Stan Discourse discussions on thinning and ESS reporting.

A local rank-normalized diagnostic gate has now executed that next check for
the same 3 priority cells under the `draws_x4` profile. All 3 cells still
flagged rank warnings and geometry warnings remained `0`. The residual pattern
is not one metric: declared-Q split `101` is limited by rank R-hat and bulk
ESS, rotated-wrong-Q split `17` is limited by bulk ESS, and rotated-wrong-Q
split `101` is limited by rank R-hat and tail ESS. The warning blocks are
concentrated in `person`, `item`, and `item_steps`, so the next local gate is
`parameterization_audit_for_rank_warning_blocks`, not thinning, a chain-count
only run, or public threshold wording.

That parameterization audit has now joined the 10 raw warning parameters back
to the train splits without new MCMC. The warning parameters had moderate or
adequate local row support, so the pattern is not just empty support. A small
`init_jitter = 0.05` smoke rerun then cleared 0/3 rank-warning cells and
improved only 1/3, with geometry warnings still `0`. The next gate is therefore
a person/item/item-step coupling parameterization pilot.

The coupling pilot then reran the same `draws_x4` cells and measured posterior
draw correlations for the warning parameters. It found 0 strong couplings at
the `0.70` threshold, 42 moderate couplings at `0.40`, maximum absolute
correlation `0.6473`, and geometry warnings still `0`. The observed pattern is
mostly person-item location coupling rather than item-step-dominated coupling,
so a package-level reparameterization should wait for replication or a larger
draw-budget coupling check.

That larger retained-draw check then kept warmup at `128` per chain and raised
retained draws from `256` to `512` per chain. It cleared all 3 rank-warning
cells, improved the rank surface in all 3, kept geometry warnings at `0`, and
still showed no strong couplings at the `0.70` threshold. The current local
evidence therefore points first to retained-draw budget, not an immediate
parameterization change.

An independent-seed replication then reran the same `128/512` warmup/draw
profile with seed offset `1009`. It again cleared all 3 rank-warning cells,
kept geometry warnings at `0`, found 0 strong couplings at the `0.70`
threshold, and had 0 coupling-delta review rows. The retained-draw explanation
is therefore stronger than a single-seed artifact, but the next local gate is
warmup/thinning sensitivity before changing package defaults or public wording.

That warmup/thinning gate then doubled warmup to `256` while keeping `512`
retained draws per chain. The full retained draws still cleared all 3
rank-warning cells and kept geometry warnings at `0`, but only 1/3 rows
improved relative to the `128/512` replication. Post-hoc thinning was not a
fix: `thin = 2` reintroduced rank warnings in 2/3 rows and `thin = 4`
reintroduced rank warnings in 3/3 rows. Locally, the practical issue is
retained draw support, not burn-in alone or thinning.

A no-new-MCMC retained-draw guidance synthesis turns these gates into a local
workflow rule. For similar guarded MGMFRM diagnostics, use at least `4` chains,
`128` warmup draws per chain, and `512` retained draws per chain before
treating rank warnings as substantive model evidence. If a `256`-draw run has
rank-normalized R-hat, bulk ESS, or tail ESS warnings with no geometry
warnings, increase retained draws to `512` per chain and rerun diagnostics
before reparameterizing or thinning. This is local guidance, not a package-wide
default change.

The first empirical check of that rule reran the `well_specified_current_q`
fold-1 MGMFRM candidates at `4/128/512` and compared them with the heavier
`4/500/1000` publication-grade pilot artifacts. Confirmatory current-Q and
sparse current-Q passed the local diagnostic gate. Construct-reviewed revised-Q
kept geometry warnings at `0` but showed a borderline rank-normalized R-hat
warning (`1.0109` vs the `1.01` threshold). Heldout ELPD shifts versus the
heavier comparator were descriptively small in this single fold (maximum
absolute delta `0.1099`), but that does not license public fit or model-weight
claims. The next gate is a targeted extended-budget follow-up for
construct-reviewed revised-Q.

That follow-up indicates a budget-sensitive warning. The construct-reviewed
revised-Q profile cleared with retained draws increased to `1000` while keeping
warmup at `128` (`R-hat = 1.0030`, minimum ESS `1903.8`), and it also cleared
with warmup increased to `256` while keeping `512` retained draws
(`R-hat = 1.0051`). The `4/256/1000` profile passed at both
`target_accept = 0.8` and `0.9`, so target acceptance is not the first-line
explanation. The next gate is scenario/fold replication of the
construct-reviewed revised-Q `1000`-draw profile.

The first replication smoke keeps the rank conclusion but adds a geometry
caveat. Four default `4/128/1000` profiles all passed the rank gate (maximum
R-hat `1.0035`), but `well_specified_current_q` fold 2 produced one divergence.
That fold-2 geometry warning cleared both with `target_accept = 0.9` at
`4/128/1000` and with warmup increased to `256` at `target_accept = 0.8`. In the
cross-scenario missing-loading fold-1 cell, the lightweight `4/128/1000` profile
was close to the heavy `4/500/1000` comparator (dELPD `-0.0160`). The next gate
therefore keeps 1000 retained draws as the rank-guidance candidate while
expanding a separate geometry-remediation branch.

The expanded 25-cell check keeps the same interpretation. All default
`4/128/1000` construct-reviewed revised-Q profiles passed the rank gate
(maximum R-hat `1.0091`, minimum ESS `605.2`), while 23/25 passed the full local
gate. The two failures were both one-divergence `well_specified_current_q`
cells, folds 2 and 4. All six geometry-remediation profiles for those cells
passed: `target_accept = 0.9`, warmup `256`, and the combined profile. In the
missing-loading scenario, lightweight `4/128/1000` stayed descriptively close to
the heavy `4/500/1000` comparator across folds (maximum absolute dELPD
`0.3031`). The next gate is to connect these budget diagnostics to model
comparison and category-calibration evidence.

The report-facing MGMFRM budget guidance is therefore brms-like: `4` chains,
`1000` warmup draws per chain, and `1000` retained draws per chain. This matches
the brms convention of `iter = 2000` including warmup with default warmup
`iter/2`, yielding `4000` retained posterior draws across four chains. This is a
guarded MGMFRM report-guidance setting, not a package-wide `fit` default change
or a public fit-threshold claim.

The first brms-like publication-grade single-cell execution is also recorded as
local evidence for the construct-reviewed revised-Q MGMFRM in the
`well_specified_current_q` fold-1 cell. That run used `4` chains, `1000` warmup
draws per chain, and `1000` retained draws per chain; it passed all 12 local
diagnostic-gate rows (`R-hat = 1.0030`, minimum ESS `1551.4`, E-BFMI `0.8548`,
no divergences, no max-treedepth hits) and produced heldout ELPD `-11.794`.
This clears the initial runtime/geometry check for one revised-Q cell only. The
remaining pilot units, threshold recalibration, full 125-unit batch, external
construct evidence, and public MGMFRM claims remain blocked.

The brms-like fold-1 pilot has now also been executed for all five selected
comparison units. Current-Q confirmatory, sparse current-Q, and
construct-reviewed revised-Q MGMFRM passed the full local diagnostic gate. The
scalar GMFRM baseline retained two divergences, so the next gate is sampler
remediation before batch expansion. The analytic null reference ranked first on
heldout ELPD (`-8.926`), scalar was the best MCMC model (`-10.164`) but failed
the divergence gate, and sparse current-Q was the best diagnostic-passed MCMC
model (`-11.674`). These ranks are descriptive local diagnostics only; they
motivate signal-strength, category-calibration, and threshold-sensitivity
checks rather than any public model-weight claim.

The scalar remediation gate has a brms-like rerun at the same `4` chains,
`1000` warmup draws per chain, and `1000` retained draws per chain. Raising only
`target_acceptance` from `0.8` to `0.9` removed the scalar GMFRM divergences
(`2 -> 0`), kept R-hat/ESS/E-BFMI inside the local gate, and left heldout ELPD
essentially unchanged (`-10.164 -> -10.160`, dELPD `+0.0043`). This is local
sampler-policy evidence, not a replacement of the primary pilot row or a public
model-selection claim.

The full 125-unit publication-grade batch plan now consumes that brms-like
scalar remediation review. Scalar GMFRM jobs are planned with
`target_acceptance = 0.9`, fixed-Q MGMFRM jobs with `0.8`, and all MCMC jobs
with `4` chains, `1000` warmup draws, and `1000` retained draws per chain. The
runner adapter is ready for local execution, but the full-batch result review,
external construct evidence, and public-scope review remain unresolved.

The first batch smoke execution ran the five `well_specified_current_q` fold-1
jobs through the full batch runner path. All four MCMC jobs passed the local
diagnostic gate, the scalar GMFRM job used `target_acceptance = 0.9` with zero
divergences, and scalar remained the best diagnostic-passed MCMC model. The
analytic null/reference still ranked first on heldout ELPD, so the evidence
continues to support batch expansion for diagnosis rather than any public
structured-model superiority claim.

These numbers are local diagnostic evidence only. They should not be cited as
public fit thresholds, model weights, Q-revision evidence, sparse-superiority
evidence, or a stable-public MGMFRM validation claim.

## Guarded Fixed-Q MGMFRM Example

The guarded MGMFRM path is opt-in and deliberately small. A spec must use
`family = :mgmfrm`, `dimensions >= 2`, and a fixed item-by-dimension `q_matrix`;
then `fit(spec; experimental = true)` returns an [`MGMFRMFit`](@ref). The
example below uses tiny sampler settings so the API path is quick to inspect,
not so the posterior diagnostics are publication-ready.

```julia
using BayesianMGMFRM
using Random

ratings = (
    examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
    item = ["I1", "I1", "I2", "I1", "I2", "I2"],
    score = [0, 1, 2, 1, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
)

q_matrix = Bool[1 0; 0 1]
q_matrix_validation(data; dimensions = 2, q_matrix)
spec = mfrm_spec(data;
    thresholds = :partial_credit,
    family = :mgmfrm,
    dimensions = 2,
    q_matrix,
)

fit_result = fit(spec;
    experimental = true,
    seed = 20260630,
    ndraws = 2,
    warmup = 0,
    chains = 1,
    step_size = 0.02,
    max_depth = 8,
    metric = :unit,
)

fit_metadata(fit_result)
fit_artifact(fit_result; include_environment = false)
fit_report(fit_result; include_loo = false, artifact_include_environment = false)
sampler_diagnostics(fit_result)
posterior_summary(fit_result)
posterior_predictive_check(fit_result;
    draw_indices = [1, 2],
    rng = MersenneTwister(20260633),
)
```

The repository also includes the same workflow as a runnable script at
[`examples/guarded_mgmfrm.jl`](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/blob/main/examples/guarded_mgmfrm.jl).

## Minimal MFRM Workflow Example

The ordinary public fitting path remains the minimal MFRM/RSM/PCM workflow.
This example exercises the current cache, diagnostics, predictive-check,
model-comparison, simulation, and reporting helpers for that fit-supported
surface.

```julia
using BayesianMGMFRM
using Random

ratings = (
    examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
    rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
    item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
    score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
)

data = FacetData(ratings; person = :examinee, rater = :rater, item = :item, score = :score)
spec = mfrm_spec(data; thresholds = :partial_credit)
spec_rsm = mfrm_spec(data; thresholds = :rating_scale)
prior = MFRMPrior(; person_sd = 1.5, rater_sd = 1.0, item_sd = 1.0, step_sd = 1.0)
target = MFRMLogDensity(spec; prior)
initial_params(target)
linear_predictor_values(spec, initial_params(spec))
loglikelihood(spec, initial_params(spec))
logprior(spec, initial_params(spec), prior)
logposterior(spec, initial_params(spec), prior)
prior_predict(spec; prior, ndraws = 100)
prior_ppc = prior_predictive_check(spec; prior, ndraws = 100)
prior_ppc.implication_diagnostics
predictive_check_summary(prior_ppc)
fit_result = cached_fit(spec; cache_path = "cache/pcm_fit.jls", prior,
    backend = :julia, ndraws = 500, warmup = 500, chains = 4, step_size = 0.04, seed = 20260618)
fit_result_rsm = cached_fit(spec_rsm; cache_path = "cache/rsm_fit.jls", prior,
    backend = :julia, ndraws = 500, warmup = 500, chains = 4, step_size = 0.04, seed = 20260619)
fit_result_nuts = cached_fit(spec; cache_path = "cache/pcm_nuts_fit.jls", prior,
    backend = :advancedhmc, ndraws = 500, warmup = 500,
    chains = 4, step_size = 0.04, target_accept = 0.8, max_depth = 10, seed = 20260620)
fit_result_turing = cached_fit(spec; cache_path = "cache/pcm_turing_fit.jls", prior,
    backend = :turing, ndraws = 500, warmup = 500,
    chains = 4, step_size = 0.04, target_accept = 0.8, max_depth = 10, seed = 20260623)

fit_metadata(fit_result)
model_manifest(fit_result)
fit_cache_key(spec; prior, backend = :julia, ndraws = 500, warmup = 500,
    chains = 4, step_size = 0.04, seed = 20260618)
fit_artifact(fit_result; include_draws = true, include_environment = false)
fit_report(fit_result; include_prior_predictive = true,
    prior_predictive_ndraws = 4,
    artifact_include_environment = false)
diagnostics(fit_result)
sampler_diagnostics(fit_result)
mcmc_diagnostics(fit_result)
parameter_block_diagnostics(fit_result)
posterior_summary(fit_result)
posterior_summary(fit_result; intervals = (0.66, 0.9, 0.95), rope = 0.1)
pointwise_loglikelihood_matrix(fit_result)
waic(fit_result)
waic_diagnostics(fit_result)
compare_models(:partial_credit => fit_result, :rating_scale => fit_result_rsm)
sensitivity_comparison(:partial_credit => fit_result, :rating_scale => fit_result_rsm;
    axis = :thresholds, baseline = :partial_credit)
predictive_probabilities(fit_result)
expected_scores(fit_result)
predictive_variances(fit_result)
predictive_residuals(fit_result)
calibration_table(fit_result; bins = 5)
calibration_table(fit_result; target = :all, bins = 5)
fit_stats(fit_result; by = :rater)
posterior_predict(fit_result; ndraws = 100)
ppc = posterior_predictive_check(fit_result; ndraws = 100)
predictive_check_summary(ppc)
predictive_check_summary(ppc; include_grouped = true)

truth = initial_params(getdesign(spec); value = 0.0)
simulated = simulate_responses(spec, truth; rng = MersenneTwister(20260621))
sim_spec = mfrm_spec(simulated; thresholds = :partial_credit)
sim_fit = fit(sim_spec; prior, backend = :julia, ndraws = 100,
    warmup = 100, chains = 2, step_size = 0.04, seed = 20260622)
recovery = parameter_recovery(sim_fit, truth)
parameter_recovery_summary(recovery)
parameter_recovery_plot_data(recovery)
calibration_plot_data(calibration_table(fit_result; bins = 5))
predictive_check_plot_data(predictive_check_summary(ppc))
wright_map_data(fit_result)
dff_report(fit_result; terms = (:rater, :item))
```

The random-walk sampler is intended for small validation examples and API
stabilization. The AdvancedHMC/NUTS and Turing/NUTS backends are
gradient-based sampler paths for the minimal design; AdvancedHMC also backs the
guarded experimental GMFRM and fixed-Q MGMFRM candidates, but it is not yet a
broad GMFRM/MGMFRM fitting backend. The package does not yet expose Stan/CmdStan
sampling or broad refit-managed model-comparison workflows outside the
fit-supported shared-plan comparison slice and guarded generalized refits that
are explicitly requested with `experimental = true`.
[`loo_refit_plan`](@ref) constructs deterministic one-observation-heldout
plans for exact LOO follow-up, optionally restricted to selected observations
or Pareto-k flagged rows from raw LOO summaries, and [`loo_refit`](@ref)
executes those exact one-row refits for fit-supported MFRM/RSM/PCM specs and
guarded experimental GMFRM/MGMFRM specs after checking heldout-level coverage.
[`kfold_plan`](@ref) constructs deterministic observation-level or grouped
heldout folds, and [`kfold`](@ref) plus [`compare_kfold`](@ref) summarize
supplied heldout refit log-likelihood matrices. [`kfold_refit`](@ref) executes
those folds automatically for fit-supported MFRM/RSM/PCM specs and guarded
experimental GMFRM/MGMFRM specs after checking heldout-level coverage.
`MFRMLogDensity` exposes the
same minimal posterior through the `LogDensityProblems.jl` protocol for
external sampler and automatic differentiation experiments. AdvancedHMC uses a
shared gradient adapter: `ad_backend = :ForwardDiff` is the default,
`:ReverseDiff` can be selected when that package is available in the active
environment, and `:analytic` uses a target-provided
`LogDensityProblems.logdensity_and_gradient` method for targets that implement
one. Turing wraps the same target with a flat vector parameter and
`Turing.@addlogprob!`; that backend currently accepts only
`ad_backend = :ForwardDiff`.
`linear_predictor_values` exposes the row-by-category `eta`, log-denominator,
and category log-probability values for the same minimal likelihood used by
`pointwise_loglikelihood`. `loglikelihood`, `logprior`, and `logposterior`
expose the corresponding scalar target components for inspection and
validation, and also return draw-level log component vectors from fitted
MFRM/GMFRM/MGMFRM objects. `fit_metadata` returns report-ready data dimensions,
draw dimensions, model family, dimensions, estimation status, backend, sampler,
and prior scales for a fitted object.
`model_manifest` records the data/spec/design/fit provenance contract, including
validation status, deterministic parameter blocks, constraint tables,
prior-block declarations, prior scales, and the compact diagnostic summary.
`fit_artifact` extends that manifest into a cached-fit artifact with sampler
controls, RNG seed metadata, posterior summaries, selected diagnostic
thresholds, optional draws, optional environment/package metadata, a stable
[`artifact_content_hash`](@ref), and an embedded [`fit_archive_manifest`](@ref)
for long-term export checks.
For guarded GMFRM/MGMFRM fits, the artifact also records a
`raw_prior_control_manifest`: each raw block lists its normal-prior scale
parameter, the resolved `_SourceFixturePrior` scale, and the raw-density
no-Jacobian policy, while direct-scale generalized priors remain blocked.
[`fit_reproduction_manifest`](@ref) combines that full-rerun artifact with a
hash-verified fit-cache record from [`save_fit_cache`](@ref) or
[`cached_fit`](@ref), treating full rerun and fast cached-draw reproduction as
separate required paths. When a cache record is supplied, the manifest checks
that the record's embedded fit identity matches the target fit before marking
the fast cached-draw path ready. It can also attach a fit-report bundle manifest
for review exports, while explicitly recording that no publication or
registration action is performed.
[`case_study_provenance_manifest`](@ref) records the local real-data
case-study source licensing/anonymization status and synchronizes that record
with the claim-level, manuscript-scale, and full-paper archive rows. It is a
provenance guardrail only, not a data-license grant, IRB determination,
publication action, registration action, or manuscript-claim approval.
`fit_report` is the lighter report-facing bundle: it combines metadata,
manifest, diagnostics, rating-design review rows, MGMFRM fixed-Q validation and
gauge rows when applicable, MGMFRM local MCMC-budget guidance rows,
prior-policy rows, pooling-policy rows, posterior summaries, posterior
predictive summaries, calibration rows, WAIC/LOO summaries and diagnostics,
optional DFF rows, and compact artifact provenance. The MGMFRM
`mcmc_budget_guidance` section surfaces brms-like local guidance (`4` chains,
`1000` warmup draws, and `1000` retained draws per chain) in report rows without
changing package defaults or adding thinning as a primary fit control. Reports can be verified with
[`artifact_content_hash`](@ref), which ignores embedded hash/archive metadata
when recomputing the content hash. It captures section-level errors by default,
so short validation fits can still return a partial report with
`status = :error` for unavailable sections such as LOO. Pass
`include_full_artifact = true` only when the embedded compact artifact itself is
needed.
Use [`save_fit_report`](@ref) to write a JSON export record for cross-tool
review. The export stores the original report content hash and a separate
JSON-payload hash; [`load_fit_report`](@ref) validates the export/hash metadata
and verifies that JSON payload hash by default before returning ordinary
`Dict{String,Any}` / `Vector{Any}` data. Use
[`fit_report_sections`](@ref), [`fit_report_section`](@ref), and
[`fit_report_rows`](@ref) to list available report sections and extract rows
from either the in-memory report or the JSON-loaded payload. Use
[`save_fit_report_tables`](@ref) when downstream review or Quarto workflows need
one JSON file per report table plus a `manifest.json` with table filenames, row
counts, and table content hashes; [`load_fit_report_tables`](@ref) verifies the
manifest and table-file hashes plus their hash-record metadata before returning
the table records. Use
[`fit_report_markdown`](@ref) or
[`save_fit_report_markdown`](@ref) to generate a dependency-light Markdown
review draft with report metadata, section summaries, and table previews before
moving the tables into a manuscript-specific renderer. Use
[`save_fit_report_bundle`](@ref) when a review bundle should keep the JSON
report, table directory, Markdown draft, and bundle manifest together under one
export directory; [`load_fit_report_bundle`](@ref) verifies the nested report,
table manifest/table file, and Markdown hashes plus their hash-record metadata
before returning the report payload.
Use [`fit_report_dossier`](@ref) to combine one or more fit-report payloads
with supplied comparison, sensitivity, or evidence rows into a multi-report
review dossier. [`fit_report_dossier_markdown`](@ref),
[`save_fit_report_dossier`](@ref), [`load_fit_report_dossier`](@ref), and
[`save_fit_report_dossier_markdown`](@ref) provide hash-checked JSON and
Markdown review artifacts while explicitly recording that no publication or
registration action is performed.
`cached_fit` is the RDS-like recomputation guard: it serializes the fitted
object with Julia's standard `Serialization` format and only reuses the file
when [`fit_cache_key`](@ref) still matches the current data/spec/design, prior,
sampler controls, seed, Julia version, and initialization hash. This is intended
for same-environment analysis caches. Automatic cache keys require an integer
`seed`; use `fit` plus manual [`save_fit_cache`](@ref) for unseeded exploratory
fits. The cache helpers also accept guarded experimental [`GMFRMFit`](@ref) and
[`MGMFRMFit`](@ref) objects. Automatic generalized caches are available only
with `experimental = true` on the guarded AdvancedHMC raw-coordinate fit path,
and the cache key records that experimental contract and raw initialization
hash. Saved cache records store the artifact content hash and archive manifest;
[`load_fit_cache`](@ref) verifies those hashes and their hash metadata by
default. Use manifests and exported tables for long-term, cross-version
archival records.
`diagnostics` combines chain-level sampler summaries, parameter-level R-hat/ESS
rows, and parameter-block pass/fail rows into a single machine-readable surface
with AdvancedHMC/NUTS fields such as divergent-transition counts,
max-tree-depth hits, and E-BFMI when available.
`sampler_diagnostics` returns chain-level draw counts, acceptance rates, and
log-posterior summaries.
`mcmc_diagnostics` returns classical split R-hat and autocorrelation-based ESS
when a fit has at least two chains, and marks row-level `:mcmc_warning` flags
when R-hat or ESS fails the supplied thresholds. `posterior_summary` returns
mean, standard deviation, median, the requested lower/upper interval, central
credible-interval rows, probability of direction relative to a reference value,
and optional ROPE/practical-equivalence probabilities. `parameter_block_diagnostics`
aggregates R-hat/ESS rows for person, rater, item, and threshold blocks. The current prior and
posterior predictive checks return compact observed-vs-replicated summaries for
overall mean score, category proportions, person-level mean scores, rater-level
mean scores, item-level mean scores, and optional facet mean scores;
predictive-check objects also carry grouped DFF-cell and observed
sparse-design-block summaries for report expansion with
`predictive_check_summary(...; include_grouped = true)`. Prior predictive
checks also return implication diagnostics for category
nonuse/sparsity and broad facet mean-score ranges before fitting.
`predictive_check_summary` turns those checks into rows with replicated
intervals and tail probabilities.
`simulation_grid` returns predeclared scenario rows for density, anchor-size,
ratings-per-target, category-pathology, rater-noise, DFF, dimensionality, and
misspecification axes, and `simulation_grid_summary` checks whether those rows
cover the required axes. These helpers plan validation grids; they do not run
simulations or fit models. `scripts/generate_validation_plan.jl` records those
rows' deterministic controls, coverage summary, and falsification-rule contract
as a JSON validation-plan artifact before any manuscript-scale evidence run.
`falsification_rules` predeclares rule rows for sparse hierarchical-prior
MGMFRM stability claims, and `falsification_rule_summary` checks that all
required claim domains are represented before a study is interpreted.
`simulate_responses` generates one simulated response dataset from known
identified parameters under the current fit-supported MFRM/RSM/PCM likelihood.
It also supports specified-only GMFRM/MGMFRM preview designs for guarded
simulation scaffolding on constrained direct parameters, or raw candidate
coordinates with `parameter_space = :raw`. Use `parameter_recovery` and
`parameter_recovery_summary` to inspect posterior bias, absolute error, RMSE,
interval coverage, interval width, and block-level recovery; GMFRM/MGMFRM fit
objects can be summarized on either direct or raw coordinates.
`pointwise_loglikelihood_matrix` also accepts specified-only GMFRM/MGMFRM
preview designs with constrained direct draws, or raw candidate-coordinate
draws when `parameter_space = :raw`, so external generalized draws can be
turned into the same WAIC/LOO log-likelihood matrix contract before strong
comparison claims are made.
`parameter_recovery_plot_data`, `calibration_plot_data`,
`predictive_check_plot_data`, `wright_map_data`, and `diagnostic_map_data`
return plotting-ready rows without depending on a specific plotting library.
`diagnostic_map_data` joins Wright-map logit positions to posterior
infit/outfit summaries for pathway-map displays with fit metrics on one axis
and logit locations on the other.
`waic` computes WAIC from posterior pointwise log-likelihood draws, and
`waic_diagnostics` reports the observation-level WAIC components and flags
high-variance rows. `loo` computes raw importance-sampling LOO, while
`psis_loo` applies Pareto smoothing to the largest importance ratios before
computing the self-normalized LOO log score. `compare_models` ranks fitted
models by WAIC-, raw-LOO-, or PSIS-LOO-derived expected log predictive density,
including an Akaike-style `relative_weight` for same-data candidate models.
Because the comparison uses pointwise differences, `compare_models` requires
the same observation data in the same row order, ordinal category levels,
latent dimensionality, and fixed Q-matrix contract; returned rows include the
checked model family, thresholds, discrimination mode, dimensionality,
Q-matrix, and data signature.
`loo_refit_plan` constructs deterministic one-observation-heldout plans for
exact LOO follow-up, optionally restricted to selected observations or Pareto-k
flagged rows from raw LOO summaries.
`loo_refit` executes such plans for fit-supported MFRM/RSM/PCM specs and
guarded experimental GMFRM/MGMFRM specs by refitting each complementary
training split, scoring the single heldout row, and returning a
K-fold-compatible heldout log-score summary.
`loo_refit_comparison` applies one shared exact-refit plan across multiple
fit-supported or explicitly guarded experimental candidates, then returns
K-fold-compatible comparison and sensitivity rows.
`kfold_plan` constructs deterministic observation-level or grouped heldout fold
assignments for planned refits. `kfold_plan_diagnostics` checks each fold and
facet for heldout-only levels before external refits. `kfold` summarizes
supplied heldout log-likelihood matrices from fold-specific refits, and
`kfold_diagnostics` returns observation-level heldout rows with fold IDs and
facet labels when data are supplied. `compare_kfold` ranks those K-fold
summaries when the heldout observation order and fold assignment order match
across models. `kfold_sensitivity_comparison` adds declared sensitivity axis
values and baseline-relative K-fold differences to those supplied summaries.
`kfold_refit` executes the planned folds automatically for the current
fit-supported MFRM/RSM/PCM slice and the guarded experimental GMFRM/MGMFRM
slice when `experimental = true`, and `kfold_refit_comparison` runs the same
shared plan across labeled candidate specs, designs, data objects, or existing
MFRM/GMFRM/MGMFRM fits before returning comparison-ready rows. Use
[`facet_response_table`](@ref) with a plan row's `training_observations` or
`heldout_observations` when a role-normalized table is needed for external
fold-specific fitting scripts.
`sensitivity_comparison` uses the same WAIC/raw-LOO/PSIS-LOO scoring path with
a declared sensitivity axis, per-model axis values, a baseline model, and
baseline-relative ELPD and information-criterion differences for report tables.
Direct `compare_models`
output keeps same-dimension and same-Q-matrix safeguards, while declared
`sensitivity_comparison` rows can compare dimensionality or fixed-Q choices
when those are the stated sensitivity axes and the observation data and
category levels match. `sensitivity_comparison_summary` audits whether the
declared rows cover the expected threshold, discrimination, rater-pooling, DFF,
anchor, dimensionality, and prior-regime axes; it does not create refits or
fit unsupported generalized/DFF/anchor effects.
`prior_likelihood_sensitivity` instead holds one fitted draw set fixed and
uses self-normalized importance reweighting to summarize local prior and
likelihood power-scaling cells. Its effective-sample-size warnings identify
cells where the local reweighting approximation is too weak and refit-based
follow-up is needed.
`comparison_evidence_row` records already computed checks against faithful
Stan/BridgeStan models, overlapping R/frequentist tools, or simpler nested
models, and `comparison_evidence_summary` checks whether those required
comparison classes are present and passing. These helpers do not run external
tools or refit models.
`benchmark_result_row` summarizes supplied repeated idle-machine timings with
median/IQR elapsed time, ESS/sec, and time-to-quality thresholds, while
`benchmark_summary` checks required Julia/Stan engine coverage and reports
Stan/Julia elapsed-time and ESS/sec ratios. These helpers record benchmark
evidence; they do not run benchmarks.
Observation-level
predictive probabilities, expected scores,
variances, and residuals are exposed as the substrate for calibration,
infit/outfit, and further model-comparison helpers. `calibration_table` bins
observations by posterior predictive expected score, or by a selected category
probability, and returns observed-vs-predicted summaries with posterior
intervals. It can also return one block per ordinal score category with
`category = :all`, or expected-score and all ordinal category rows together
with `target = :all`. `fit_stats` currently returns posterior summaries of infit and
outfit mean-square statistics by facet level. `fair_average_summary` returns
person-, rater-, or item-level fair-average expected-score intervals using a
balanced reference grid; `separation_reliability_summary` returns posterior
separation and empirical reliability intervals for person, rater, and item
measures; `residual_summary` returns observation- or facet-level expected-score
and residual intervals with screening caveats for sparse groups and nonzero
residual intervals; `rater_diagnostics` combines rater severity, category-use,
range/centrality, residual, and available discrimination rows for reports;
`dff_report` returns DFF screening rows with expected-score interaction
residuals, local logit-scale approximations, and optional practical-magnitude
probabilities when estimand thresholds are declared. The
`backend` keyword is explicit
so additional engines can be added without changing the fitted-object shape.
