"""
    BayesianMGMFRM

Analyze ordinal and multi-criterion ratings while accounting for entity/person
ability, item/task difficulty, and rater severity, with Bayesian uncertainty
estimates, diagnostic qualification, and transparent target densities.

# Unified Practitioner Workflow

Start with a rating table and `mfrm_spec` (`prior = :default` for the standard
isometric zero-sum Bayesian parameterization, or `prior = :none` for frequentist
estimation), validate the design with `validate_design`, pass explicit sampling
settings to `fit`, inspect `qualify`, `diagnostics`, and `contrast`, and persist
verified fits or portable handoff reports. The extended operations below share
names across models, while availability and return values remain model-specific.
Consult the selected model guide; checkpointing is not required for an ordinary fit.
Use `AbstractMFRMSpec` and `AbstractMFRMFit` for type annotations spanning these
standard specifications and fits; concrete fields remain model-specific.

1. **Specify & Inspect Design**: Build an identified model directly from a rating
   table with `mfrm_spec(ratings; person = ..., score = ..., facets = ..., steps = ..., category_levels = ..., prior = :default)`
   (including optional `slope = :rater | :item` for 1D GMFRM or `q_matrix = ...`
   for scale-identified MGMFRM, or `Experimental.joint_rating_spec` for
   multi-criterion rating events). Inspect `validate_design` and `design_summary`,
   and modify specifications cleanly with `with_options`. Legacy reference-coded
   `FacetData` workflows remain available for `0.1.x` compatibility (`FacetData`
   with `mfrm_spec(data; prior = :default)` also compiles to the isometric route).
2. **Check Priors & Simulate**: Draw from the joint prior with `prior_draw`,
   generate synthetic datasets with `simulate`, and screen plausibility with
   `prior_predictive_check`.
3. **Fit & Checkpoint**: Estimate models via `fit` (analytic-gradient NUTS by
   default, or `method = :mmle | :jmle` on 1D `prior = :none` specifications;
   multi-worker execution uses `prepare_fit`, `run_chain_worker`,
   `worker_status`, `collect_fit`).
4. **Qualify, Summarize & Decide**: Screen convergence with `qualify` and
   `diagnostics` (`:mcmc`, `:fit_statistics`, `:fair_average`, `:pair_bias`,
   `:residual_correlation`), inspect `posterior_summary`, `posterior_mcse`,
   `facet_summary`, `category_summary`, `contrast`, `plausible_values`,
   `anchor_linking_summary`, `predict`, `event_probabilities`, `reliability`,
   `ranking`, `classification`, `predictive_check`, `criteria`, `compare_models`,
   and `prior_sensitivity`.
5. **Visualize & Persist**: Render publication-ready figures via
   `BayesianMGMFRM.plot(fit; kind = :posterior)` (after `using CairoMakie`),
   and persist verified fits or portable JSON reports with `save_fit` / `load_fit`
   and `save_report` / `load_report`.

# Glass-Box Researcher & Submodule Surfaces

Methodological researchers can load `using BayesianMGMFRM.GlassBox` to inspect
exact model contracts, coordinate maps, basis partitions, Jacobians, analytical
gradients, CmdStan inputs, and interoperability bridges (`contract`,
`parameter_names`, `facet_basis`, `coordinates`, `to_ncp_reference`,
`from_ncp_reference`, `reparameterize_point`, `reparameterize_draws`,
`log_jacobian_to_ncp`, `logprior`, `loglikelihood`, `pointwise_loglikelihood`,
`logposterior`, `logdensity_and_gradient`, `stan_data`, `sampler_controls`,
`MRCML`, `StanAdapter`, `PortableHandoff`, `ModelOperationMatrix`).

Simulation-study, calibration-pilot, and benchmark harnesses live in
`BayesianMGMFRM.ValidationSuite`, compatibility aliases from `0.1.x` live in
`BayesianMGMFRM.Legacy`, and generalized, multidimensional, correlated, and
multi-criterion models use `BayesianMGMFRM.Experimental`; computational
availability does not establish scientific model-selection acceptance.
"""
module BayesianMGMFRM

import StatsAPI: fit, predict

export
    # Core Types (6)
    FacetData,
    AbstractMFRMSpec,
    AbstractMFRMFit,
    SamplingProgress,
    ValidationIssue,
    ValidationReport,
    # Design, Priors & Simulation (7)
    mfrm_spec,
    with_options,
    design_summary,
    validate_design,
    prior_draw,
    simulate,
    prior_predictive_check,
    # Fitting & Worker Checkpointing (6)
    fit,
    prepare_fit,
    run_chain_worker,
    worker_status,
    collect_fit,
    progress_snapshot,
    # Qualification, Summaries, Contrasts, Equating & Decisions (12)
    qualify,
    diagnostics,
    posterior_summary,
    posterior_mcse,
    facet_summary,
    category_summary,
    contrast,
    plausible_values,
    reliability,
    ranking,
    classification,
    anchor_linking_summary,
    # Prediction, Model Comparison, Sensitivity & Persistence (10)
    predict,
    event_probabilities,
    predictive_check,
    criteria,
    compare_models,
    prior_sensitivity,
    save_fit,
    load_fit,
    save_report,
    load_report

include("workflow_types.jl")
include("cmdstan_backend.jl")
include("evidence_metadata.jl")
include("facet_workflow.jl")
include("ordinal_response_patterns.jl")
include("model_family_contract.jl")
include("mgmfrm_validation_protocol.jl")
include("mgmfrm_validation_scoring.jl")
include("model_contract.jl")
include("testlet_design_audit.jl")
include("sampling_progress.jl")
include("bayesian_fit.jl")
include("sampling_execution.jl")
include("mgmfrm_location_diagnostics.jl")
include("mgmfrm_location_parameterization.jl")
include("posterior_plot.jl")
include("response_surface.jl")
include("cmdstan_fit.jl")
include("mgmfrm_normalized_prior.jl")
include("mgmfrm_slope_restriction.jl")
include("mgmfrm_slope_gradient.jl")
include("mfrm_fixed_q_samples.jl")
include("mgmfrm_free_correlation_candidate.jl")
include("mgmfrm_correlated_2d_samples.jl")
include("mgmfrm_correlated_2d_predictive.jl")
include("mgmfrm_correlated_2d_reports.jl")
include("mgmfrm_normalized_fit.jl")
include("mgmfrm_scale_identified.jl")
include("generalized_summary.jl")
include("mfrm_correlated_2d.jl")
include("mfrm_prior_predictive.jl")
include("mfrm_exchangeable_raters.jl")
include("mgmfrm_free_correlation_recovery.jl")
include("mgmfrm_free_correlation_study.jl")
include("mgmfrm_free_correlation_resource_probe.jl")
include("mgmfrm_free_correlation_study_scoring.jl")
include("experimental.jl")
include("mgmfrm_response_stress.jl")
include("mgmfrm_response_stress_fit.jl")
include("mgmfrm_validation_resource_probe.jl")
include("mgmfrm_validation_primary_grid.jl")
include("mgmfrm_validation_isolated_resource_probe.jl")
include("mgmfrm_validation_isolated_resource_review.jl")
include("mgmfrm_validation_execution_design.jl")
include("mgmfrm_validation_analysis_contract.jl")
include("anchor_refit_plan.jl")
include("facets_conquest_bridge.jl")
include("practitioner_diagnostics.jl")
include("local_dependence.jl")
include("local_dependence_known_truth_dgp.jl")
include("local_dependence_simulation.jl")
include("local_dependence_calibration.jl")
include("local_dependence_calibration_pilot.jl")

# Scalar validation target used by the analytic-gradient test suite.
include("scalar_validation_logp.jl")

# Qualified candidate APIs; exports and legacy comparison semantics are preserved.
include("prediction_observations.jl")
include("common_psis.jl")
using .PredictionObservationAdapter: prediction_observations, observation_alignment, prediction_criteria
include("prediction_comparison.jl")
include("prediction_refit.jl")
include("prediction_mcse.jl")
include("prediction_kfold.jl")
include("recovery_evaluation.jl")
include("posterior_contrast.jl")
include("posterior_reliability.jl")
include("posterior_classification.jl")
include("posterior_ranking.jl")
include("rater_agreement.jl")
include("krippendorff_alpha.jl")
include("intraclass_correlation.jl")
include("category_report.jl")
include("score_information.jl")
include("recovery_replications.jl")
include("prior_sensitivity.jl")
include("prior_power_sensitivity.jl")
include("prior_predictive_sensitivity.jl")
include("prediction_report.jl")
include("saved_reporting.jl")
include("validation_suite.jl")
include("unified_workflow.jl")
include("concurrent_plot.jl")
include("glass_box.jl")
include("additive_facets.jl")
include("explanatory_power_sensitivity.jl")
include("explanatory_comparison.jl")
include("bounded_comparison.jl")
include("mixed_outcomes_comparison.jl")
include("frequentist_mfrm.jl")
include("frequentist_mfrm_api.jl")
include("design_connectedness.jl")
include("stan_adapter.jl")
include("mgmfrm_scale_identified_api.jl")
include("fair_reference_extensions.jl")
include("frequentist_fair_reference.jl")
Base.include(Experimental.RecoveryPlanning, joinpath(@__DIR__, "v02_sbc.jl"))
include("api_contract_freeze.jl")
include("multivariate_generalizability.jl")
include("glass_box_module.jl")
include("legacy_module.jl")

# Exact 0.2.x root-export and submodule classification boundary.
include("root_api_contract.jl")

using PrecompileTools: @compile_workload
@compile_workload begin
    tbl = (
        person = ["P1", "P1", "P2", "P2", "P3", "P3"],
        item   = ["I1", "I2", "I1", "I2", "I1", "I2"],
        rater  = ["R1", "R2", "R2", "R1", "R1", "R2"],
        score  = [0, 1, 2, 1, 1, 2],
    )
    t_mrcml = mfrm_spec(
        tbl;
        person = :person,
        score = :score,
        facets = (item = :item, rater = :rater),
        steps = :global,
        category_levels = 0:2,
        prior = :default,
    )
    validate_design(t_mrcml)
    design_summary(t_mrcml)
    q0 = zeros(Float64, t_mrcml.dimension)
    logposterior(t_mrcml, q0)
    LogDensityProblems.logdensity_and_gradient(t_mrcml, q0)
    freq = mfrm_spec(merge(tbl,(score=[0,2,1,0,2,1],)); person=:person, score=:score, facets=(rater=:rater,),
                     steps=:global, category_levels=0:2, prior=:none)
    fit(freq; method=:jmle)
    fit(freq; method=:mmle)
    fit(freq; method=:mmle, quad_points=7, estimate_sd=false)
end

end
