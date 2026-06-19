# BayesianMGMFRM.jl

`BayesianMGMFRM.jl` is an early Julia package scaffold for many-facet Rasch
measurement workflows.

The current public slice focuses on:

- long-format rating data via [`FacetData`](@ref);
- pre-fit design validation via [`validate_design`](@ref);
- minimal MFRM specification and design inspection via [`mfrm_spec`](@ref) and
  [`getdesign`](@ref);
- source-traced likelihood contracts via [`model_equation`](@ref);
- specified-only GMFRM/MGMFRM configuration manifests and non-fit-ready preview
  designs via [`model_ladder`](@ref), [`constraint_table`](@ref),
  [`identification_declarations`](@ref), [`getdesign`](@ref), and
  [`model_manifest`](@ref);
- fit-ready parameter layout metadata via
  [`fit_ready_parameter_layout`](@ref) and domain compiler review rows via
  [`domain_compilation_summary`](@ref);
- initial Bayesian fitting for the minimal identified design via [`fit`](@ref),
  [`cached_fit`](@ref), [`MFRMPrior`](@ref), [`fit_metadata`](@ref),
  [`fit_artifact`](@ref), and [`posterior_summary`](@ref), including a small
  random-walk backend, initial AdvancedHMC/NUTS and Turing/NUTS backends, and
  RDS-like serialized fit caches;
- a guarded experimental scalar GMFRM path via `fit(spec; experimental = true)`
  returning [`GMFRMFit`](@ref) for the one-dimensional rater-discrimination
  promotion candidate only, with local validation, posterior predictive, and
  sparse-pathology recovery evidence recorded;
- serializable provenance manifests for fit-supported specs, specified-only
  specs, designs, fits, and cached-fit artifacts via [`model_manifest`](@ref)
  and [`fit_artifact`](@ref);
- integrated diagnostic summaries via [`diagnostics`](@ref);
- chain-level sampler summaries via [`sampler_diagnostics`](@ref);
- chain-aware R-hat and ESS summaries via [`mcmc_diagnostics`](@ref);
- parameter-block R-hat and ESS summaries via
  [`parameter_block_diagnostics`](@ref);
- prior and posterior predictive replication via [`prior_predict`](@ref),
  [`prior_predictive_check`](@ref), [`posterior_predict`](@ref), and
  [`posterior_predictive_check`](@ref);
- simulation-study helpers via [`simulate_responses`](@ref),
  [`parameter_recovery`](@ref), and [`parameter_recovery_summary`](@ref);
- report-ready predictive-check summaries, including grouped PPC expansion
  rows, via [`predictive_check_summary`](@ref);
- binned expected-score and ordinal-category calibration summaries via
  [`calibration_table`](@ref);
- plotting-ready rows via [`parameter_recovery_plot_data`](@ref),
  [`calibration_plot_data`](@ref), and
  [`predictive_check_plot_data`](@ref);
- Wright-map rows for posterior facet measures and item-threshold positions via
  [`wright_map_data`](@ref);
- row-by-category likelihood inspection via [`linear_predictor_table`](@ref)
  and [`linear_predictor_values`](@ref);
- observation-level predictive probabilities, expected scores, variances, and
  residuals via [`predictive_probabilities`](@ref), [`expected_scores`](@ref),
  [`predictive_variances`](@ref), and [`predictive_residuals`](@ref);
- posterior fair-average expected-score intervals for person, rater, or item
  reports via [`fair_average_summary`](@ref);
- declared or ad hoc DFF screening rows on expected-score and local logit
  scales via [`dff_report`](@ref);
- posterior separation and empirical reliability intervals for person, rater,
  and item measures via [`separation_reliability_summary`](@ref);
- rater severity, category-use, range/centrality, residual, and available
  discrimination diagnostics via [`rater_diagnostics`](@ref);
- posterior residual summaries and infit/outfit summaries by observation or
  facet level via [`residual_summary`](@ref) and [`fit_stats`](@ref);
- WAIC, raw importance-sampling LOO, and supplied heldout K-fold
  model-comparison and sensitivity rows via [`waic`](@ref), [`loo`](@ref),
  [`kfold`](@ref), [`compare_models`](@ref), [`compare_kfold`](@ref), and
  [`sensitivity_comparison`](@ref);
- fit-independent reporting data via [`coverage_summary`](@ref),
  [`coverage_matrix`](@ref), [`rater_overlap`](@ref),
  [`domain_compilation_summary`](@ref), [`design_row_table`](@ref),
  [`linear_predictor_table`](@ref), [`threshold_map_data`](@ref),
  [`wright_map_data`](@ref), and [`dff_report`](@ref);
- test-suite validation against small/medium Julia/BridgeStan scalar fixtures
  and internal hand-computed source-aligned GMFRM/MGMFRM preview fixtures, including
  raw-coordinate transforms for source identification restrictions and
  fixture-only raw-coordinate log-likelihood / log-density target checks, plus
  local scalar GMFRM BridgeStan-oracle, candidate-chain, stress-chain, and
  recovery-smoke evidence for the private promotion candidate, and an internal
  confirmatory MGMFRM gauge manifest with BridgeStan confirmatory-candidate and
  local candidate-chain/recovery-smoke evidence.

Stan/CmdStan sampling, PSIS-smoothed or exact LOO, generalized discrimination
likelihoods, group/DFF model terms, and Multidimensional Generalized
Many-Facet Rasch Model (MGMFRM) fitting APIs are planned work and are not
exposed yet. The Turing/NUTS backend is currently limited to the minimal
MFRM/RSM/PCM `MFRMLogDensity` target.
Specified-only GMFRM/MGMFRM configs are available for constraint and manifest
review, with estimation currently limited to the guarded scalar GMFRM
rater-discrimination candidate. See the [Bayesian Workflow](bayesian-workflow.md)
page for the current check sequence and limitations, and
[Roadmap and Scope](roadmap.md) for the implementation gates for planned
GMFRM/MGMFRM work.

```@contents
Pages = ["data-validation.md", "model-equations.md", "bayesian-workflow.md", "fitting.md", "roadmap.md", "api.md"]
Depth = 2
```
