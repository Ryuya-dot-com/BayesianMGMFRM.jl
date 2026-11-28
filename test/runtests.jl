using Test
import Turing
include("optional_dependencies.jl")
OptionalDependencyChecks.availability_checks()
using ForwardDiff
using JSON3
using LinearAlgebra
using LogDensityProblems
using Random
using ReverseDiff
using SHA
using Serialization

import AdvancedHMC
import BayesianMGMFRM
import LogDensityProblemsAD

include("diagnostic_split_metadata.jl")

include("test_groups.jl")

println("BayesianMGMFRM test group: ", ACTIVE_TEST_GROUP)

include(joinpath(dirname(@__DIR__), "scripts", "local_json.jl"))
include(joinpath(dirname(@__DIR__), "scripts",
    "scientific_payload_digest.jl"))

module RuntimePublicLanguagePolicyForTest

include(joinpath(@__DIR__, "..", "scripts", "public_language_gate.jl"))

end


const RuntimePublicLanguagePolicy =
    RuntimePublicLanguagePolicyForTest.PublicLanguageGate

function structured_field_names(value, fields = Symbol[])
    if value isa NamedTuple
        for field in keys(value)
            push!(fields, field)
            structured_field_names(getproperty(value, field), fields)
        end
    elseif value isa AbstractDict
        for (key, item) in value
            push!(fields, Symbol(key))
            structured_field_names(item, fields)
        end
    elseif value isa Tuple || value isa AbstractArray
        for item in value
            structured_field_names(item, fields)
        end
    end
    return fields
end

const PRIVATE_READER_FIT_FIELDS = Set((
    :artifact,
    :artifacts,
    :status_policy,
    :scope,
    :public_fit,
    :experimental_public,
    :fit_ready,
    :guarded_local_fit,
    :internal_target_constructor,
    :internal_sampler_diagnostic_constructor,
    :target,
    :initialization_policy,
    :source_path,
    :repository_path,
    :file_path,
))

function reader_payload_contains_identity_value(value)
    if value isa AbstractString
        return occursin(r"^[0-9a-fA-F]{64}$", value)
    elseif value isa NamedTuple
        return any(reader_payload_contains_identity_value(
            getproperty(value, field)) for field in keys(value))
    elseif value isa AbstractDict
        return any(reader_payload_contains_identity_value(item)
            for item in values(value))
    elseif value isa Tuple || value isa AbstractArray
        return any(reader_payload_contains_identity_value, value)
    end
    return false
end

function reader_payload_is_identity_free(value)
    fields_are_identity_free = all(structured_field_names(value)) do field
        name = lowercase(String(field))
        !occursin("hash", name) && !occursin("fingerprint", name) &&
            !occursin("digest", name) && !occursin("signature", name)
    end
    return fields_are_identity_free &&
        !reader_payload_contains_identity_value(value)
end

function public_portable_numeric_summary_matches(public, full)
    keys(public) == keys(full) || return false
    return all(keys(full)) do field
        public_value = getproperty(public, field)
        full_value = getproperty(full, field)
        if full_value isa AbstractFloat && !isfinite(full_value)
            return public_value == string(full_value)
        end
        return isequal(public_value, full_value)
    end
end

using BayesianMGMFRM:
    FacetData,
    anchor_linking_summary,
    artifact_content_hash,
    benchmark_result_row,
    benchmark_summary,
    calibration_plot_data,
    case_study_provenance_manifest,
    cached_fit,
    comparison_evidence_row,
    comparison_evidence_summary,
    compare_kfold,
    compare_models,
    constraint_table,
    coverage_matrix,
    coverage_summary,
    diagnostic_map_data,
    diagnostics,
    design_row_table,
    dff_report,
    domain_compilation_summary,
    evidence_artifact_schema_policy,
    evidence_metadata,
    expected_scores,
    facets_compatibility_stats,
    facets_report,
    facet_response_table,
    fair_average_summary,
    falsification_rule_summary,
    falsification_rules,
    fit,
    fit_archive_manifest,
    fit_artifact,
    fit_cache_key,
    fit_report,
    fit_report_health,
    fit_report_public,
    fit_report_dossier,
    fit_report_dossier_markdown,
    fit_report_markdown,
    fit_reproduction_manifest,
    fit_report_section,
    fit_report_sections,
    fit_report_rows,
    fit_ready_parameter_layout,
    fit_stats,
    getdesign,
    identification_declarations,
    initial_params,
    kfold,
    kfold_diagnostics,
    kfold_plan,
    kfold_plan_diagnostics,
    kfold_refit,
    kfold_refit_comparison,
    kfold_sensitivity_comparison,
    ScalarValidationData,
    ScalarValidationAnalyticLogDensity,
    ScalarValidationContrastLogDensity,
    ScalarValidationLogDensity,
    scalar_validation_contrast_num_params,
    scalar_validation_decode,
    scalar_validation_decode_contrast,
    scalar_validation_logposterior,
    scalar_validation_logposterior_and_gradient,
    scalar_validation_logposterior_contrast,
    scalar_validation_num_params,
    scalar_validation_offsets,
    calibration_table,
    loglikelihood,
    loo,
    loo_diagnostics,
    loo_refit,
    loo_refit_comparison,
    loo_refit_plan,
    logposterior,
    logprior,
    linear_predictor_table,
    linear_predictor_values,
    local_dependence_calibration_contract,
    local_dependence_calibration_pilot_check,
    local_dependence_calibration_pilot_contract,
    local_dependence_calibration_pilot_preflight,
    local_dependence_calibration_row,
    local_dependence_calibration_summary,
    local_dependence_contract,
    local_dependence_simulation_grid,
    local_dependence_summary,
    GMFRMFit,
    MGMFRMFit,
    MFRMFit,
    MFRMLogDensity,
    MFRMPrior,
    mfrm_spec,
    model_equation,
    model_manifest,
    model_surface_check,
    model_surface_audit,
    fit_metadata,
    mcmc_diagnostics,
    parameter_block_diagnostics,
    parameter_recovery,
    parameter_recovery_plot_data,
    parameter_recovery_summary,
    pointwise_loglikelihood,
    pointwise_loglikelihood_matrix,
    posterior_predict,
    posterior_predictive_check,
    posterior_summary,
    psis_loo,
    prior_likelihood_sensitivity,
    predictive_check_summary,
    predictive_check_plot_data,
    predictive_probabilities,
    predictive_residuals,
    predictive_standardized_residuals,
    predictive_variances,
    prior_predict,
    prior_predictive_check,
    q_matrix_validation,
    rater_diagnostics,
    rater_overlap,
    rating_design_check,
    rating_design_audit,
    related_software_capability_matrix,
    residual_summary,
    release_gate_check,
    release_scope_summary,
    load_fit_cache,
    load_fit_report,
    load_fit_report_dossier,
    load_fit_report_bundle,
    load_fit_report_tables,
    sampler_diagnostics,
    save_fit_cache,
    save_fit_report,
    save_fit_report_dossier,
    save_fit_report_dossier_markdown,
    save_fit_report_bundle,
    save_fit_report_markdown,
    save_fit_report_tables,
    simulation_grid,
    simulation_grid_summary,
    simulate_local_dependence,
    simulate_responses,
    stan_validation_row,
    stan_validation_summary,
    sensitivity_comparison,
    sensitivity_comparison_summary,
    separation_reliability_summary,
    threshold_map_data,
    testlet_design_check,
    testlet_design_audit,
    model_ladder,
    validate_design,
    validation_suggestions,
    waic,
    waic_diagnostics,
    wright_map_data,
    zerosum_basis_fast

# Shared definitions only; test execution remains under the shard gates below.
include("support/common.jl")
include("support/chain_fixtures.jl")
include("support/gmfrm_recovery.jl")
include("support/gmfrm_comparisons.jl")
include("support/gmfrm_api.jl")
include("support/gmfrm_sensitivity.jl")
include("support/gmfrm_archives.jl")
include("support/gmfrm_dff_and_scope.jl")
include("support/gmfrm_exposure.jl")
include("support/mgmfrm_recovery.jl")
include("support/mgmfrm_benchmarks.jl")
include("support/mgmfrm_agreement.jl")
include("support/mgmfrm_q_review.jl")
include("support/mgmfrm_heldout.jl")
include("support/mgmfrm_refits.jl")
include("support/mgmfrm_publication.jl")
include("support/mgmfrm_remediation.jl")
include("support/mgmfrm_external_evidence.jl")
include("support/mgmfrm_budgets.jl")
include("support/mgmfrm_api.jl")
include("support/scalar_validation.jl")

# Select before expanding these large test blocks, including on other shards.
@static if test_group_enabled(:core)
include("suites/core.jl")
end

@static if test_group_enabled(:fitting_core)
include("suites/fitting_core.jl")
end

test_group_enabled(:fitting_core) && include("fitting_boundaries.jl")
test_group_enabled(:fitting_core) && include("spec_display.jl")
test_group_enabled(:fitting_core) && include("rater_free_irt.jl")
test_group_enabled(:fitting_core) && include("warmup_diagnostics.jl")
test_group_enabled(:fitting_core) && include("posterior_plot.jl")
test_group_enabled(:fitting_core) && include("pathway_plot.jl")
test_group_enabled(:fitting_core) && include("response_surface.jl")
test_group_enabled(:fitting_core) && include("wright_ridge.jl")

if test_group_enabled(:generalized) && RUN_RESEARCH_EVIDENCE_TESTS
    include("existing_api_design_robustness_recovery_scorer.jl")
end
if test_group_enabled(:fitting_reports)
    include("joint_draw_artifact.jl")
    include("reference_prior_reporting.jl")
    include("facets_conquest_bridge.jl")
    include("conquest_reference.jl")
    include("model_contract.jl")
    include("facets_compatibility_stats.jl")
    include("practitioner_diagnostics.jl")
    include("anchor_refit_plan.jl")
    include("hard_anchor_fit.jl")
    include("mfrm_anchor_attempt_record.jl")
end
# This deterministic RSM/PCM grid used to dominate the reports shard.
if test_group_enabled(:core) || ACTIVE_TEST_GROUP === :fitting
    include("mfrm_anchor_generator_crosscheck.jl")
end
if test_group_enabled(:local_dependence_core)
    include("testlet_design_audit.jl")
    include("testlet_overlap_contract.jl")
    include("predictive_standardized_residuals.jl")
    include("local_dependence_contract.jl")
    include("local_dependence_summary.jl")
    include("local_dependence_simulation.jl")
end
if test_group_enabled(:local_dependence_core) ||
        test_group_enabled(:local_dependence_integrity)
    include("local_dependence_calibration.jl")
end
if test_group_enabled(:local_dependence) && RUN_RESEARCH_EVIDENCE_TESTS
    include("local_dependence_calibration_artifact.jl")
    include("local_dependence_calibration_pilot.jl")
    include("local_dependence_pilot_harness_reproduction.jl")
    check_current_pilot_harness(; executor_tests = true)
end
if test_group_enabled(:generalized)
    include("model_family_contract.jl")
    include("mgmfrm_validation_protocol.jl")
    include("mgmfrm_validation_scoring.jl")
    include("ordinal_response_patterns.jl")
    include("mgmfrm_response_stress.jl")
    include("mgmfrm_response_stress_fit.jl")
    include("mgmfrm_validation_resource_probe.jl")
    include("mgmfrm_validation_isolated_resource_probe.jl")
    include("mgmfrm_validation_isolated_resource_review.jl")
    include("mgmfrm_validation_primary_grid.jl")
    include("mgmfrm_validation_execution_design.jl")
    include("mgmfrm_validation_analysis_contract.jl")
    include("generalized_prior.jl")
    include("generalized_summary.jl")
    include("mgmfrm_location_diagnostics.jl")
    include("mgmfrm_location_parameterization.jl")
    include("mgmfrm_core_location_section.jl")
    include("mgmfrm_core_nuts_stationarity.jl")
    include("mgmfrm_core_coupled_geometry.jl")
    include("mgmfrm_location_api.jl")
    include("mgmfrm_adaptation_record.jl")
    include("cmdstan_adaptation_record.jl")
    include("mgmfrm_adaptation_review.jl")
    include("mgmfrm_density_measure.jl")
    include("mgmfrm_prior_measure.jl")
    include("mgmfrm_normalized_prior_predictive.jl")
    withenv("BAYESIANMGMFRM_NORMALIZED_FIT_SMOKE" => "true") do
        include("mgmfrm_normalized_fit.jl")
        include("mgmfrm_normalized_location.jl")
    end
    include("mgmfrm_normalized_samples.jl")
    include("mgmfrm_unidimensional.jl")
    include("mgmfrm_slope_restriction.jl")
    include("mgmfrm_slope_gradient.jl")
    include("mgmfrm_slope_prior_blocks.jl")
    include("mgmfrm_gradient_selection.jl")
    include("mgmfrm_artifact_reuse.jl")
    include("mgmfrm_report_reuse.jl")
    MGMFRMReportReuseChecks.checks()
    include("mgmfrm_diagnostic_memory.jl")
    MGMFRMDiagnosticMemoryChecks.checks()
    include("mgmfrm_mean_profile.jl")
    include("matched_dimension_refit_plans.jl")
    include("mfrm_fixed_q_result.jl")
    include("mfrm_fixed_q_spec.jl")
    include("mfrm_correlated_2d.jl")
    include("sampling_observer.jl")
    include("sampling_progress.jl")
    include("sampling_execution.jl")
    include("mfrm_correlated_2d_samples.jl")
    include("mfrm_correlated_2d_result.jl")
    include("mfrm_prior_predictive.jl")
    include("mfrm_prior_identification.jl")
    include("mfrm_exchangeable_raters.jl")
    include("mfrm_rater_prior_predictive.jl")
    include("mfrm_exchangeable_samples.jl")
    include("mfrm_exchangeable_reports.jl")
    include("mfrm_exchangeable_api.jl")
    include("mfrm_validation_preparation.jl")
    include("synthetic_paired_ratings.jl")
    include("paired_rating_reference.jl")
    include("paired_rating_predictive.jl")
    include("paired_rating_prior_review.jl")
    include("paired_rating_precision.jl")
    include("mfrm_fixed_q_fit.jl")
    include("mfrm_fixed_q_samples.jl")
    include("generalized_guard_contract.jl")
    include("fixed_q_identification.jl")
    include("mgmfrm_estimand_invariance.jl")
end
test_group_enabled(:fitting_reports) && include("common_prediction_tests.jl")
test_group_enabled(:fitting_reports) && include("fit_report_completeness.jl")
test_group_enabled(:fitting_reports) && include("report_bundle_preflight.jl")
test_group_enabled(:fitting_reports) && include("report_columns.jl")
test_group_enabled(:fitting_reports) && include("report_figures.jl")
test_group_enabled(:fitting_reports) && include("warmup_report.jl")
if test_group_enabled(:generalized)
    include("free_correlation_authorization.jl")
end
test_group_enabled(:fitting_reports) && include("evidence_metadata_resilience.jl")
if test_group_enabled(:generalized)
    include("experimental_namespace.jl")
    include("joint_ratings.jl")
    JointRatingsTests.finite_checks()
    include("ordinal_association.jl")
    OrdinalAssociationTests.finite_checks()
    include("joint_rating_gradient.jl")
    JointRatingGradientTests.finite_checks()
    include("mgmfrm_free_latent_correlation_2d.jl")
    include("mgmfrm_correlated_2d_cmdstan.jl")
    include("mgmfrm_correlated_gradient.jl")
    CorrelatedGradientTests.finite_checks()
    include("mgmfrm_correlated_2d_samples.jl")
    include("mgmfrm_correlated_2d_result.jl")
    include("mgmfrm_correlated_2d_predictive.jl")
    include("mgmfrm_correlated_2d_reports.jl")
end
if test_group_enabled(:generalized) && RUN_RESEARCH_EVIDENCE_TESTS
    include("mgmfrm_free_latent_correlation_2d_study.jl")
    @testset "free-correlation runner workspace-project subprocess" begin
        runner_test_path = joinpath(
            @__DIR__,
            "mgmfrm_free_latent_correlation_2d_study_unit_runner.jl",
        )
        command = addenv(
            `$(Base.julia_cmd()) --project=$(dirname(@__DIR__)) $runner_test_path`,
            "JULIA_LOAD_PATH" => join(
                ("@", "@stdlib"), Sys.iswindows() ? ';' : ':'),
        )
        process = mktemp() do _, log_io
            child = run(pipeline(
                command;
                stdout = log_io,
                stderr = log_io,
            ); wait = false)
            wait(child)
            if !success(child)
                flush(log_io)
                seekstart(log_io)
                write(stderr, read(log_io))
                println(stderr, "\nsubprocess exit code: ", child.exitcode)
            end
            child
        end
        @test success(process)
    end
end
test_group_enabled(:generalized) && RUN_RESEARCH_EVIDENCE_TESTS &&
    include("publication_grade_policy_contract.jl")
if test_group_enabled(:fitting_reports)
    include("single_item_design_rank.jl")
    SingleItemDesignRankChecks.checks()
    include("release_metadata.jl")
    include("public_language_gate.jl")
    include("cache_hash.jl")
    include("cache_summary_roundoff.jl")
    CacheSummaryRoundoffChecks.checks()
    include("posterior_direction.jl")
    PosteriorDirectionChecks.checks()
    include("json_integer_preservation.jl")
    JSONIntegerPreservationChecks.checks()
    include("report_integer_checksum.jl")
    ReportIntegerChecksumChecks.checks()
    include("posterior_mcse.jl")
    include("saved_mgmfrm_contrasts.jl")
    include("three_indicator_reports.jl")
    ThreeIndicatorReportChecks.checks()
    ThreeIndicatorReportChecks.provenance_checks()
    ThreeIndicatorReportChecks.support_checks()
    include("three_indicator_input.jl")
    ThreeIndicatorInputChecks.checks()
    ThreeIndicatorInputChecks.interface_checks()
    include("three_indicator_concurrent.jl")
    ThreeIndicatorConcurrentChecks.checks()
    ThreeIndicatorConcurrentChecks.persistence_checks()
    include("three_indicator_concurrent_prior_config.jl")
    ThreeIndicatorConcurrentPriorConfigChecks.checks()
    include("three_indicator_concurrent_association.jl")
    ThreeIndicatorConcurrentAssociationChecks.checks()
    ThreeIndicatorConcurrentAssociationChecks.lifecycle_checks()
    include("three_indicator_concurrent_reports.jl")
    ThreeIndicatorConcurrentReportChecks.checks()
    ThreeIndicatorConcurrentReportChecks.support_checks()
    include("three_indicator_concurrent_workflow.jl")
    include("three_indicator_concurrent_parallel.jl")
    ThreeIndicatorConcurrentParallelChecks.checks()
    ThreeIndicatorConcurrentWorkflowChecks.checks()
    include("three_indicator_concurrent_predictive.jl")
    ThreeIndicatorConcurrentPredictiveChecks.checks()
include("three_indicator_concurrent_prior_predictive.jl")
ThreeIndicatorConcurrentPriorPredictiveChecks.checks()
include("concurrent_plot.jl")
ConcurrentPlotChecks.checks()
include("three_indicator_coordinates.jl")
ThreeIndicatorCoordinateChecks.checks()
include("three_indicator_adaptation.jl")
ThreeIndicatorAdaptationChecks.checks()
    include("three_indicator_fitting.jl")
    ThreeIndicatorFittingChecks.context_checks()
    include("three_indicator_priors.jl")
    ThreeIndicatorPriorChecks.checks()
    ThreeIndicatorPriorChecks.report_checks(ThreeIndicatorReportChecks.support_fixture)
    mktempdir() do out
        ThreeIndicatorFittingChecks.checks(joinpath(out,"three-indicator"))
    end
    include("rater_drift.jl")
    RaterDriftChecks.checks()
    include("rater_drift_comparison.jl")
    mktempdir() do output
        RaterDriftComparisonChecks.checks(joinpath(output,"comparison"))
    end
    include("rater_drift_fitting.jl")
    mktempdir() do output
        RaterDriftFittingChecks.prepare_checks(joinpath(output,"deterministic"))
        RaterDriftFittingChecks.bridge_unit_checks()
        RaterDriftFittingChecks.public_checks(output)
    end
    include("posterior_contrast.jl")
    PosteriorContrastChecks.checks()
    include("rater_item_interactions.jl")
    include("additive_facets.jl")
    include("additive_facets_workflow.jl")
    include("explanatory_facets.jl")
    include("bounded_facets.jl")
    include("count_facets.jl")
    include("location_slopes.jl")
include("bounded_distributional.jl")
    include("mixed_outcomes.jl")
    include("person_testlet_reuse.jl")
    include("predictive_representation.jl")
    include("repeated_explanatory.jl")
    include("criterion_explanatory.jl")
include("additive_patterns.jl")
    if Base.get_extension(BayesianMGMFRM,:BayesianMGMFRMCairoMakieExt)!==nothing
        include("additive_caption.jl")
    end
    include("explanatory_facets_workflow.jl")
    include("additive_plot_reports.jl")
    include("rater_group_effects.jl")
    include("criterion_collapse.jl")
    include("criterion_collapse_prediction.jl")
    include("criterion_collapse_loo.jl")
    include("criterion_collapse_plots.jl")
    include("criterion_collapse_lifecycle.jl")
    include("frequentist_mfrm.jl")
    include("mrcml_design_matrix.jl")
    include("mrcml_population_design.jl")
    include("grouped_plausible_values.jl")
    include("stan_adapter_and_handoff.jl")
    include("public_workflow_types.jl")
    include("public_contract_regressions.jl")
    include("api_contract_freeze.jl")
    include("cr5_design_validation_and_connectedness.jl")
    include("cr6_prior_defaults_mgmfrm_sbc.jl")
    include("cr8_dff_fair_average_and_boundaries.jl")
    include("fair_reference.jl")
    include("reliability_functional.jl")
    include("fair_reference_extensions.jl")
    include("fair_reference_interactions.jl")
    include("p2_1_exchange_schema_and_group_dff.jl")
    include("rater_group_categories.jl")
    include("rater_group_predictive.jl")
    include("rater_group_example.jl")
    include("rank_normalized_diagnostics.jl")
    include("scientific_payload_digest.jl")
    RUN_RESEARCH_EVIDENCE_TESTS &&
        include("legacy_archive_provenance.jl")
end

test_group_enabled(:generalized) && RUN_RESEARCH_EVIDENCE_TESTS &&
    include("full_paper_reproduction_archive_contract.jl")

# Each shared check belongs to one shard and remains part of the full run.
if test_group_enabled(:generalized)
    include("correlated_3d.jl")
    include("unified_api_and_star_association.jl")
    include("star_prior_identity.jl")
    include("mathematical_api_contract.jl")
    include("explanatory_power.jl")
    include("cr4_mgmfrm_scale_identification.jl")
    include("p2_2_gmfrm_lkj_mgmfrm_and_q3.jl")
    include("q_matrix_labels.jl")
    include("mrcml_shared_effects.jl")
    include("multivariate_generalizability.jl")
    include("generalizability_likelihood.jl")
    include("generalizability_region.jl")
    include("p2_3_event_operations.jl")
end

if test_group_enabled(:fitting_reports)
    include("unified_api_review_fixes.jl")
    include("unified_persistence.jl")
    include("comparison_api_contract.jl")
    include("qualification_prediction_contract.jl")
    include("common_psis.jl")
    include("explanatory_comparison.jl")
    include("prediction_criteria_adapter.jl")
    include("stan_brms_aliases.jl")
end

if test_group_enabled(:core)
    include("review_json.jl")
    include("distribution_archive_boundary.jl")
end
