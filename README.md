# BayesianMGMFRM.jl

[![CI](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl/actions/workflows/CI.yml)

`BayesianMGMFRM.jl` is a conservative Julia package for Bayesian many-facet
Rasch measurement workflows. It is designed for rating data where people,
raters, items, categories, and optional grouping variables all matter, and where
model checks are as important as posterior summaries.

The current public release focuses on a reliable first workflow:

- normalize long-format rating data into stable facet indexes;
- validate connectedness, sparse cells, skipped categories, and design rank
  before fitting;
- inspect many-facet Rasch design matrices, constraints, thresholds, and model
  manifests;
- fit minimal MFRM/RSM/PCM models with Bayesian samplers;
- summarize diagnostics, posterior measures, predictive checks, calibration,
  WAIC/LOO inputs, rater diagnostics, DFF screening rows, and report bundles;
- explore narrow guarded GMFRM/MGMFRM experiments without broadening public
  claims beyond their validation evidence.

The package is intentionally explicit about scope. Minimal MFRM/RSM/PCM fitting
is the fit-supported surface. Scalar rater-consistency GMFRM, configured through
the compatibility keyword `discrimination = :rater`, and fixed-Q confirmatory
MGMFRM with `dimensions >= 2` are available only through guarded experimental
paths. Broader generalized discrimination, exploratory MGMFRM, free latent
correlations, modeled DFF effects, sparse-superiority claims, and public
model-weight claims remain out of scope.

## Installation

Until the package is registered in Julia General, install it directly from
GitHub:

```julia
using Pkg
Pkg.add(url = "https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl")
```

After General registration, use:

```julia
using Pkg
Pkg.add("BayesianMGMFRM")
```

The package currently supports Julia `1.10.8` and later Julia 1.x releases.

## First Run

This tiny example keeps sampler settings deliberately small so the whole
workflow is quick to inspect. Increase `ndraws`, `warmup`, and `chains` for
real analysis.

```julia
using BayesianMGMFRM
using Random

ratings = (
    examinee = ["E1", "E1", "E1", "E1", "E2", "E2", "E2", "E2"],
    rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
    item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
    group = ["A", "A", "B", "B", "B", "B", "A", "A"],
    score = [0, 1, 2, 0, 1, 2, 0, 2],
)

data = FacetData(ratings;
    person = :examinee,
    rater = :rater,
    item = :item,
    score = :score,
    group = :group,
)

validation = validate_design(data; bias = [(:rater, :group)])
spec = mfrm_spec(data; thresholds = :partial_credit, validation_report = validation)
design = getdesign(spec)

println(validation)
println(design)
println(design.parameter_names)

prior = MFRMPrior()
fit_result = fit(spec;
    prior,
    backend = :julia,
    ndraws = 8,
    warmup = 8,
    chains = 2,
    step_size = 0.1,
    seed = 20260621,
)

posterior_summary(fit_result)
diagnostics(fit_result)

ppc = posterior_predictive_check(fit_result;
    ndraws = 8,
    rng = MersenneTwister(20260622),
)
predictive_check_summary(ppc)

report = fit_report(fit_result;
    include_prior_predictive = true,
    prior_predictive_ndraws = 8,
    rng = MersenneTwister(20260623),
    artifact_include_environment = false,
)
fit_report_sections(report)
```

For a fuller script with cache exports, diagnostic tables, calibration, WAIC,
and report-bundle examples, see [`examples/minimal.jl`](examples/minimal.jl).

## What You Get

`BayesianMGMFRM.jl` is organized around the workflow a measurement reviewer
usually wants to see.

**Data and design**

- `FacetData` turns long-format ratings into deterministic person, rater, item,
  category, and optional metadata indexes.
- `validate_design` checks category support, connectedness, singleton levels,
  sparse DFF cells, and design rank before a sampler is started.
- `mfrm_spec`, `getdesign`, `constraint_table`, `model_manifest`,
  `design_row_table`, `linear_predictor_table`, and `threshold_map_data` make
  the design contract inspectable.
- `coverage_summary`, `coverage_matrix`, `rater_overlap`,
  `anchor_linking_summary`, and `rating_design_audit` help review whether the
  data can support the intended comparison.

**Bayesian fitting**

- `fit` supports minimal MFRM/RSM/PCM models with `backend = :julia`,
  `backend = :advancedhmc`, or `backend = :turing`.
- `cached_fit`, `fit_cache_key`, `save_fit_cache`, and `load_fit_cache` provide
  same-environment recomputation control.
- `MFRMPrior`, `MFRMLogDensity`, `initial_params`, `loglikelihood`,
  `logprior`, and `logposterior` expose the likelihood/prior target for review
  and external sampler experiments.

**Diagnostics and reporting**

- `fit_metadata`, `sampler_diagnostics`, `mcmc_diagnostics`,
  `parameter_block_diagnostics`, and `diagnostics` summarize sampler and chain
  quality.
- `posterior_summary`, `fair_average_summary`,
  `separation_reliability_summary`, `rater_diagnostics`, `residual_summary`,
  `fit_stats`, `wright_map_data`, and `diagnostic_map_data` produce
  report-ready measurement and pathway-map rows.
- `prior_predictive_check`, `posterior_predictive_check`,
  `predictive_check_summary`, `calibration_table`, `waic_diagnostics`,
  `loo_diagnostics`, `psis_loo`, `kfold`, and `compare_models` support the
  Bayesian workflow around the fitted object.
- `fit_artifact`, `fit_report`, `save_fit_report`, `save_fit_report_tables`,
  `save_fit_report_markdown`, `save_fit_report_bundle`, and
  `fit_report_dossier` create hash-checked artifacts for local review.
- `evidence_artifact_schema_policy` records the required provenance fields for
  schema versioning, content hashes, package/git/environment hashes, seed and
  sampler controls, cache provenance, blocked claims, and raw-data status.

**Validation and reproducibility**

- `simulate_responses`, `simulation_grid`, `parameter_recovery`, and
  `parameter_recovery_summary` support small recovery studies.
- `stan_validation_row` and `stan_validation_summary` expose committed
  Julia/BridgeStan scalar fixture checks.
- `release_scope_summary` records the current public surface, guarded
  experimental surfaces, blocked claims, and release-readiness guardrails.
- `related_software_capability_matrix` positions Facets, TAM, mirt, sirt,
  immer, brms/Stan workflows, and this package without making replacement or
  superiority claims.
- `release_gate_check` checks that README, roadmap, docs, and manifest status
  rows agree before a release is cut.

## Model Support

| Surface | Status | Entry point | Notes |
| --- | --- | --- | --- |
| Minimal MFRM/RSM/PCM | `supported` | `mfrm_spec`, `getdesign`, `fit` | Main public workflow for current analyses. |
| Scalar rater-consistency GMFRM | `experimental_public` | `mfrm_spec(...; family = :gmfrm, discrimination = :rater)`, then `fit(spec; experimental = true)` | Narrow guarded source-aligned candidate; `discrimination = :rater` is the compatibility keyword for the positive rater-consistency multiplier. |
| Fixed-Q confirmatory MGMFRM | `experimental_public` | `mfrm_spec(...; family = :mgmfrm, dimensions = D, q_matrix = Q)`, then `fit(spec; experimental = true)` | Guarded fixed Q-mask candidate for `D >= 2`; identity latent correlation only. |
| Broader GMFRM/MGMFRM, DFF model effects, exploratory Q-matrices | `blocked` | Manifest and preview inspection only where available | Not a public fit API until identification, diagnostics, validation, and reporting contracts are stronger. |

### Local Uto-Style MGMFRM Diagnostic

Recent local diagnostics check why the current compact batch can favor a
Null/intercept reference even though Uto-style GMFRM/MGMFRM simulations should
favor a correctly specified multidimensional model. The short answer is that
the apparent inconsistency is a condition-and-estimation issue, not evidence
that fixed-Q MGMFRM cannot recover the expected direction.

In source-aligned strong-signal data, the guarded true-Q MGMFRM direction was
recovered after MCMC across replicated seeds and internal prior profiles:

- 3-seed replicated small MCMC: true-Q MGMFRM beat the Null reference in all
  seeds; mean dELPD vs Null was `+8.862`, minimum margin was `+4.087`.
- Internal prior-profile sensitivity (`default`, `tight`, `diffuse`) kept the
  direction stable across all tested seed/profile cells; mean dELPD vs Null was
  `+6.789`, minimum margin was `+3.798`.
- A local calibration bridge now varies signal strength and category-step
  calibration. The strong source-aligned condition kept the true-Q MCMC margin
  positive (`+9.420` dELPD vs Null), a moderate transition condition flipped
  after MCMC despite a small positive oracle margin (`+0.201` oracle, `-4.855`
  MCMC), and the weak compressed-category condition was threshold-sensitive
  (`+2.783` MCMC; it clears `0` and `2` dELPD thresholds but not `4` or `8`).
- A replicated calibration bridge over 2 seeds and 3 internal prior profiles
  kept the strong source-aligned condition stable (recovery rate `1.0`; minimum
  true-Q MCMC margin `+3.798`), kept the moderate transition condition unstable
  after MCMC (recovery rate `0.0`; mean `-6.022`), and confirmed that the weak
  compressed-category condition is threshold-sensitive (recovery rate `1.0`;
  mean `+2.978`; threshold `4` MCMC pass rate `0.0`).
- A local MCMC-budget bridge then varied warmup/draw budgets (`20/20`, `80/20`,
  `20/80`, `80/80`) on the same generated rows and splits. No non-baseline
  budget changed the recovered/not-recovered direction. The strong condition
  stayed clearly positive (minimum all-retained dELPD `+9.420`), the moderate
  condition stayed negative (maximum `-4.580`), and the weak compressed-category
  condition still failed the all-retained threshold `4` check. Post-hoc retained
  draw thinning changed one near-cutoff threshold cell, so thinning can affect
  boundary threshold calls even when it does not change the direction. The fit
  API exposes warmup/draws/chains, not sampler-level thinning.
- A category-calibration bridge now links dELPD/log-score thresholds to
  heldout category probability calibration. In the strong condition, true-Q
  MCMC improved log score, Brier score, category distribution distance, and
  cumulative threshold distance versus Null. In the weak compressed-category
  condition, true-Q MCMC also improved those calibration metrics versus Null,
  but its log-score gain still did not reach the `4` threshold. In the moderate
  transition condition, true-Q MCMC was worse than Null on both log score and
  category calibration. Across the tested threshold cells, `24` were predictive
  and category-calibration aligned, with `0` predictive-gain/category-caveat
  cells.
- A threshold false-alarm/power profile now reads those candidate thresholds as
  simulation profiles. In the replicated bridge, threshold `2` had signal power
  `1.0` and negative-control false promotion `0.0`, but the maximum competing
  scalar/wrong-Q pass rate was `0.6111`, so it is screening-only rather than
  Q-validation evidence. Threshold `4` had weak-signal power `0.0`, making it a
  false-negative risk for compressed-category conditions.
- A threshold/Q-misspecification expansion now joins that threshold profile to
  the empirical Q-matrix recovery grid and adds an explicit null requirement.
  The expansion records `13` scenarios across `11` axes: threshold `2` has `4`
  false-add specificity cells to test, while threshold `4` has `5`
  false-negative risk cells for false-drop and weak-dimension cases. This is a
  pre-execution map, not MCMC evidence for a public cutoff.
- A first small Q-misspecification MCMC batch now executes representative
  explicit-null, false-add, false-drop, weak-dimension, and rater-noise proxy
  cases. Threshold `2` produced `1` candidate false-promotion cell and threshold
  `4` produced `1` false-negative cell. All `20` MCMC model rows carry short
  chain warnings, so this is a screening result that must be replicated and
  joined to category calibration.
- A replicated Q-misspecification/category bridge now reruns those cases over
  2 seeds with 2-chain `16/16` warmup/draw settings. Threshold `2` still has a
  candidate false-promotion rate of `0.2`, threshold `4` has a false-negative
  rate of `0.2`, and `2` seed-scenario cells show predictive gain with a
  category-calibration caveat. All `40` MCMC rows still carry sampler warnings,
  so threshold policy remains blocked.
- A Q/category budget-stability check now compares `16/16` and `32/32`
  warmup/draw profiles on the same replicated Q scenarios. Threshold `2`
  false-promotion rate moved from `0.2` to `0.3`, threshold `4`
  false-negative rate stayed `0.2`, `4` threshold risk labels changed, and the
  `32/32` profile still had `40` warning rows. This strengthens the
  requirement that any threshold rule be predictive-plus-category and
  budget-stable before public wording.
- A multi-axis instability diagnosis now treats the remaining pattern as
  multi-causal. The highest-priority mechanisms are sampler/budget instability,
  threshold-cutoff sensitivity, and false-add Q specificity. Category
  calibration mismatch, false-drop seed variability, rater-noise/competing
  structure, and heldout category sparsity are also high-priority explanations.
  Prior profile alone and "MGMFRM is generally impossible" are low-plausibility
  explanations under the local evidence.
- A critical-cell follow-up grid now reconstructs the base seeds for the 4
  budget-sensitive cells and turns them into 12 targeted follow-up runs. The
  category-support screen is adequate in all baseline critical cells (minimum
  heldout category count at least `3`), so the next technical gate is not more
  category counting; it is split-seed control plus sampler-remediation runs.
- A split-controlled critical grid now decouples generation seeds from holdout
  split seeds on those 4 cells. Across 2 split offsets, `4` threshold risk
  labels changed and all `32` MCMC model rows still had sampler warnings. The
  critical-cell threshold `2` false-promotion rate was `0.125`; threshold `4`
  false-negative rate was `0.0` in this restricted pilot. This confirms that
  split variability is an active mechanism, not just a bookkeeping concern.
- A sampler-remediation critical pilot now reruns the split-stable critical
  cell with a larger local MCMC budget (`4` chains, `64/64` warmup/draws,
  target acceptance `0.85`). The threshold risk labels stayed stable and
  threshold `2` false-promotion fell to `0.0`, but all `8` selected MCMC model
  rows still had `mcmc_warning` flags. The next gate is therefore to diagnose
  the warning surface itself, not simply increase draws again.
- The warning-surface diagnosis now reruns that same split-stable cell and
  exports block, chain, and summary diagnostics. All `8` warning rows were
  explained by raw R-hat/ESS counts; sampler warnings, nonfinite log-density,
  divergences, max-tree-depth hits, and direct-transform failures were all `0`.
  Thinning is therefore not the primary remediation target; the next gate is a
  block-targeted budget or parameterization follow-up.
- A block-targeted follow-up plan now ranks raw warning blocks before launching
  wider MCMC. The top targets are `person` (priority `247.535`), `item`
  (`161.588`), `log_item_dimension_discrimination` (`98.182`), and
  `item_steps` (`89.280`). The first executable profile is `draws_x2_smoke`.
- The `draws_x2_smoke` follow-up then reran the 3 priority model/split cells
  with `4` chains, `64` warmup draws, and `128` retained draws per chain. All
  3 jobs improved minimum ESS and maximum R-hat and reduced bad-Rhat/low-ESS
  counts, but all 3 still had `mcmc_warning`. This supports a larger
  `draws_x4` or chain-count gate, not immediate public threshold wording.
- The `draws_x4` gate then reran the same 3 priority cells with `4` chains,
  `128` warmup draws, and `256` retained draws per chain. All 3 jobs again
  improved minimum ESS and maximum R-hat beyond `draws_x2`, and warning counts
  fell sharply, but 0/3 fully cleared `mcmc_warning`. The remaining failures
  are near-threshold R-hat/ESS cases, so the next gate is a chain-count check
  plus parameterization audit rather than a broad threshold claim.
- A chain-count gate then reran the same 3 cells with `6` chains, `64` warmup
  draws, and `128` retained draws per chain. Relative to `draws_x4`, 0/3 jobs
  improved maximum R-hat or minimum ESS, and 0/3 cleared warnings. This points
  away from chain count alone and toward parameterization plus richer
  diagnostics.
- A Stan-guided sampler-remediation review now aligns the local result with
  Stan diagnostics practice: high R-hat/low ESS remain validity warnings,
  geometry controls are not first-line when divergences, treedepth, and BFMI
  warnings are absent, thinning is not a primary fix, and rank-normalized
  R-hat plus bulk/tail ESS should be added before public gates. The top
  parameterization-audit target is still the `person` block.
- A local rank-normalized diagnostic gate then reran the same 3 priority cells
  with the `draws_x4` profile. All 3 retained rank warnings and geometry
  warnings stayed at `0`. The remaining failures split across rank R-hat,
  bulk ESS, and tail ESS: declared-Q split `101` had max rank R-hat `1.0144`
  and min bulk ESS `330.5745`; rotated-wrong-Q split `17` had min bulk ESS
  `358.4369`; rotated-wrong-Q split `101` had max rank R-hat `1.0166` and
  min tail ESS `376.0319`. The warning blocks are now concentrated in
  `person`, `item`, and `item_steps`, so the next gate is a targeted
  parameterization audit rather than thinning or chain-count-only escalation.
- A no-new-MCMC parameterization audit then joined the 10 raw warning
  parameters back to the train splits. Their observed support was moderate or
  adequate rather than structurally empty: warning blocks remained `person`,
  `item`, and `item_steps`. An `init_jitter = 0.05` smoke rerun cleared 0/3
  rank-warning cells and improved only 1/3, with geometry warnings still `0`.
  Initial jitter alone is therefore not sufficient; the next gate is a
  person/item/item-step coupling parameterization pilot.
- That coupling pilot reran the same `draws_x4` cells and measured posterior
  draw correlations for the warning parameters. It found 0 strong couplings at
  the `0.70` threshold, 42 moderate couplings at `0.40`, maximum absolute
  correlation `0.6473`, and geometry warnings still `0`. The strongest pattern
  is person-item location coupling, not an item-step-dominated failure. The
  next gate is therefore to replicate the coupling pilot or extend the draw
  budget before applying a package-level reparameterization.
- A retained-draw budget extension then kept warmup at `128` per chain and
  increased retained draws from `256` to `512` per chain. This cleared all 3
  rank-warning cells, improved the rank surface in all 3, kept geometry
  warnings at `0`, and still found 0 strong couplings (maximum absolute
  coupling correlation `0.6496`). This makes insufficient retained draws the
  leading local explanation for the residual rank warnings and motivated an
  independent-seed replication before changing the package parameterization.
- The independent-seed replication of that extended budget used seed offset
  `1009` with the same `128/512` warmup/draw profile. It again cleared all 3
  rank-warning cells, kept geometry warnings at `0`, found 0 strong couplings
  (maximum absolute coupling correlation `0.6524`), and had 0 coupling-delta
  review rows. The retained-draw explanation is therefore seed-stable in this
  local gate, but package defaults and public wording should still wait for a
  warmup/thinning-sensitivity check.
- The warmup/thinning sensitivity gate then doubled warmup to `256` while
  keeping `512` retained draws per chain and seed offset `1009`. Full retained
  draws again cleared all 3 rank-warning cells with geometry warnings at `0`,
  but only 1/3 rows improved relative to the `128/512` replication. Post-hoc
  thinning reintroduced rank warnings in 5/6 thinned rows (`thin = 2` warned in
  2/3 rows; `thin = 4` warned in 3/3). Burn-in is not the leading local
  blocker, and thinning should not be treated as the primary fix.
- A no-new-MCMC retained-draw guidance synthesis now records the local user
  guidance: for similar guarded MGMFRM diagnostics, use at least `4` chains,
  `128` warmup draws per chain, and `512` retained draws per chain before
  treating rank warnings as substantive model evidence. If a `256`-draw run
  has rank warnings but no geometry warnings, increase retained draws before
  reparameterizing or thinning. This is not a package-wide default change.
- A first empirical check of that guidance reran the `well_specified_current_q`
  fold-1 MGMFRM candidates at `4/128/512` and compared them with the heavier
  publication-grade `4/500/1000` pilot artifacts. Confirmatory current-Q and
  sparse current-Q passed the local diagnostic gate; construct-reviewed
  revised-Q had no geometry warning but showed borderline rank-normalized
  R-hat (`1.0109` against the `1.01` threshold). Heldout ELPD shifts versus
  the heavier comparator were small in this single fold (max absolute delta
  `0.1099`), but this is not a public fit claim. The next gate is a targeted
  extended-budget follow-up for construct-reviewed revised-Q before broadening
  the guidance.
- That targeted follow-up shows the borderline construct-reviewed revised-Q
  warning is budget-sensitive rather than a geometry failure. `4/128/1000`
  cleared the warning (`R-hat = 1.0030`, minimum ESS `1903.8`), and
  `4/256/512` also cleared it (`R-hat = 1.0051`). The combined
  `4/256/1000` profile passed at both `target_accept = 0.8` and `0.9`, so
  raising target acceptance is not the first-line fix. The next gate is to
  replicate the construct-reviewed revised-Q profile with `1000` retained draws
  across scenarios/folds before changing defaults or public wording.
- A first 1000-draw scenario/fold replication keeps the rank conclusion but
  separates it from geometry. Four default `4/128/1000` profiles all passed the
  rank gate (maximum R-hat `1.0035`), but `well_specified_current_q` fold 2 had
  one divergence. Both `target_accept = 0.9` at `4/128/1000` and warmup
  extension to `4/256/1000` cleared that fold-2 geometry warning. In the
  cross-scenario missing-loading fold-1 cell, the lightweight `4/128/1000`
  profile stayed close to the heavy `4/500/1000` comparator (dELPD `-0.0160`).
  The next gate is to expand this geometry branch across the remaining
  construct-reviewed revised-Q cells before changing defaults or public wording.
- The full 25-cell geometry-branch expansion now strengthens that split. All
  25 default `4/128/1000` construct-reviewed revised-Q profiles passed the rank
  gate (maximum R-hat `1.0091`, minimum ESS `605.2`), while 23/25 passed the
  full local gate. The only geometry failures were two one-divergence
  `well_specified_current_q` cells (folds 2 and 4). All six remediation
  profiles for those cells passed: `target_accept = 0.9`, warmup `256`, and the
  combined profile. In the missing-loading scenario, lightweight `4/128/1000`
  and heavy `4/500/1000` foldwise ELPD stayed descriptively close (maximum
  absolute dELPD `0.3031`). The next gate is to join these budget diagnostics
  to model-comparison and category-calibration evidence.
- The report-facing MGMFRM budget guidance is now brms-like: `4` chains,
  `1000` warmup draws per chain, and `1000` retained draws per chain
  (`2000` total iterations per chain, `4000` retained posterior draws). This
  updates the report guidance without changing the package-wide `fit` defaults
  or making a public threshold claim.
- A first brms-like publication-grade single-cell execution has now been
  recorded for the construct-reviewed revised-Q MGMFRM in the
  `well_specified_current_q` fold-1 cell. The run used `4` chains, `1000`
  warmup draws per chain, and `1000` retained draws per chain, passed all 12
  local diagnostic-gate rows (`R-hat = 1.0030`, minimum ESS `1551.4`, E-BFMI
  `0.8548`, no divergences, no max-treedepth hits), and produced heldout ELPD
  `-11.794`. This is single-cell local evidence only; the remaining pilot
  units, threshold recalibration, full 125-unit batch, external construct
  evidence, and public claims remain blocked.
- The current compact Null-win batch still shows large structured-model losses
  (for example Current Q dELPD vs Null `-33.027`), so current failures should be
  diagnosed through signal strength, category calibration, Q support, prior
  sensitivity, and estimation loss rather than treated as a general rejection of
  MGMFRM.

These are local research diagnostics, not public model-selection or
fit-threshold claims. The relevant generated reports are under
`artifacts/uto_style_inconsistency_diagnosis/`,
`artifacts/uto_style_calibration_bridge/`,
`artifacts/uto_style_category_calibration_bridge/`,
`artifacts/uto_style_threshold_false_alarm_power_profiles/`,
`artifacts/uto_style_threshold_q_misspecification_expansion/`,
`artifacts/uto_style_q_misspecification_mcmc_simulations/`,
`artifacts/uto_style_replicated_q_misspecification_category_bridge/`,
`artifacts/uto_style_q_category_budget_stability/`,
`artifacts/uto_style_multiaxis_instability_diagnosis/`,
`artifacts/uto_style_critical_cell_followup_grid/`,
`artifacts/uto_style_split_controlled_critical_grid/`,
`artifacts/uto_style_sampler_remediation_critical_pilot/`,
`artifacts/uto_style_sampler_warning_surface_diagnosis/`,
`artifacts/uto_style_block_targeted_warning_followup_plan/`,
`artifacts/uto_style_draws_x2_smoke_followup/`,
`artifacts/uto_style_draws_x4_gate_followup/`,
`artifacts/uto_style_chain_count_gate_followup/`,
`artifacts/uto_style_stan_guided_sampler_remediation_review/`,
`artifacts/uto_style_rank_normalized_diagnostic_gate/`,
`artifacts/uto_style_rank_warning_parameterization_audit/`,
`artifacts/uto_style_init_jitter_smoke/`,
`artifacts/uto_style_person_item_step_coupling_pilot/`,
`artifacts/uto_style_coupling_budget_extension/`,
`artifacts/uto_style_extended_budget_replication_gate/`,
`artifacts/uto_style_warmup_thinning_sensitivity_gate/`,
`artifacts/uto_style_retained_draw_budget_guidance/`,
`artifacts/uto_style_mcmc_budget_bridge/`,
`artifacts/uto_style_replicated_calibration_bridge/`,
`artifacts/uto_style_replicated_mcmc_refit/`, and
`artifacts/uto_style_prior_sensitivity/` when those scripts have been run.

The guarded MGMFRM example is runnable at
[`examples/guarded_mgmfrm.jl`](examples/guarded_mgmfrm.jl).

## Reading Path

- Start with [`examples/minimal.jl`](examples/minimal.jl) if you want a runnable
  end-to-end example.
- Read [`docs/src/data-validation.md`](docs/src/data-validation.md) when you
  are preparing a rating dataset.
- Read [`docs/src/fitting.md`](docs/src/fitting.md) for sampler choices,
  guarded generalized caveats, and reporting helpers.
- Read [`docs/src/model-equations.md`](docs/src/model-equations.md) for the
  source-traced likelihood contracts.
- Read [`docs/src/roadmap.md`](docs/src/roadmap.md) for the conservative scope
  boundary and future MGMFRM promotion gates.
- Read [`docs/src/registration.md`](docs/src/registration.md) for the manual
  Julia General handoff boundary.

## Development Checks

For ordinary local verification:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=docs docs/make.jl
```

Before requesting Julia General registration, run the stricter local gate:

```bash
julia --startup-file=no scripts/pre_registration_gate.jl
```

The gate checks temporary-environment import, package tests, examples,
documentation rendering, Aqua package hygiene, project metadata, whitespace,
public wording, and skipped-test scans. CI runs the hygiene subset in a lighter
mode because package tests and docs are separate jobs, and the stricter public
wording scan remains a manual pre-registration check.

The repository also includes a manual handoff helper:

```bash
julia --project=. scripts/registration_handoff.jl --strict
```

It verifies the release boundary and prints the Registrator comment. It does not
call GitHub, Registrator, General, or any publication endpoint.

## Manifest and Cache Policy

Package `Manifest.toml` files are intentionally ignored for Julia General
registration. The package gate develops the repository in fresh temporary
environments so local manifests do not affect registration checks.

Serialized fit caches from `cached_fit` are for same-environment recomputation
avoidance. For durable review, keep the `model_manifest`, `fit_artifact`,
exported summaries, report bundles, source data, and exact code version with
the analysis.

## Citation

If you use `BayesianMGMFRM.jl`, please cite the package metadata in
[`CITATION.cff`](CITATION.cff):

```text
Ryuya Komuro. BayesianMGMFRM.jl: Bayesian many-facet Rasch measurement in
Julia, version 0.1.0. https://github.com/Ryuya-dot-com/BayesianMGMFRM.jl
```

## License

MIT License. See [`LICENSE`](LICENSE).
