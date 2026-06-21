using Test
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
    diagnostics,
    design_row_table,
    dff_report,
    domain_compilation_summary,
    expected_scores,
    facet_response_table,
    fair_average_summary,
    falsification_rule_summary,
    falsification_rules,
    fit,
    fit_archive_manifest,
    fit_artifact,
    fit_cache_key,
    fit_report,
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
    GMFRMFit,
    MGMFRMFit,
    MFRMFit,
    MFRMLogDensity,
    MFRMPrior,
    mfrm_spec,
    model_equation,
    model_manifest,
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
    predictive_variances,
    prior_predict,
    prior_predictive_check,
    rater_diagnostics,
    rater_overlap,
    residual_summary,
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
    simulate_responses,
    stan_validation_row,
    stan_validation_summary,
    sensitivity_comparison,
    sensitivity_comparison_summary,
    separation_reliability_summary,
    threshold_map_data,
    model_ladder,
    validate_design,
    validation_suggestions,
    waic,
    waic_diagnostics,
    wright_map_data,
    zerosum_basis_fast

struct ExplodingTable end
Base.getindex(::ExplodingTable, args...) = error("backend exploded")

struct InternalMethodErrorTable end
_method_error_trigger(::Int) = nothing
Base.getindex(::InternalMethodErrorTable, args...) = _method_error_trigger("not an Int")

function central_difference(logp, x, i; eps = 1e-5)
    xp = copy(x)
    xm = copy(x)
    xp[i] += eps
    xm[i] -= eps
    return (logp(xp) - logp(xm)) / (2eps)
end

function check_forwarddiff_gradient(logp, x; coords = nothing, atol = 1e-4, rtol = 1e-4)
    lp = logp(x)
    @test isfinite(lp)
    gradient = ForwardDiff.gradient(logp, x)
    @test length(gradient) == length(x)
    @test all(isfinite, gradient)
    check_coords = coords === nothing ? eachindex(x) : coords
    for i in check_coords
        @test gradient[i] ≈ central_difference(logp, x, i) atol = atol rtol = rtol
    end
    return gradient
end

function check_advancedhmc_smoke(target, initial;
        seed::Int,
        ndraws::Int = 2,
        step_size::Float64 = 0.03,
        max_depth::Int = 2,
        ad_backend::Symbol = :ForwardDiff)
    nparams = LogDensityProblems.dimension(target)
    @test length(initial) == nparams
    @test isfinite(LogDensityProblems.logdensity(target, initial))

    gradient_adapter = BayesianMGMFRM._logdensity_gradient_target(target, initial, ad_backend)
    lp, gradient = LogDensityProblems.logdensity_and_gradient(gradient_adapter.target, initial)
    @test gradient_adapter.ad_backend === ad_backend
    @test isfinite(lp)
    @test length(gradient) == nparams
    @test all(isfinite, gradient)

    metric = AdvancedHMC.UnitEuclideanMetric(nparams)
    hamiltonian = AdvancedHMC.Hamiltonian(
        metric,
        x -> LogDensityProblems.logdensity(gradient_adapter.target, x),
        x -> LogDensityProblems.logdensity_and_gradient(gradient_adapter.target, x),
    )
    integrator = AdvancedHMC.Leapfrog(step_size)
    kernel = AdvancedHMC.HMCKernel(AdvancedHMC.Trajectory{AdvancedHMC.MultinomialTS}(
        integrator,
        AdvancedHMC.GeneralisedNoUTurn(max_depth, 1000.0),
    ))
    samples, stats = AdvancedHMC.sample(
        MersenneTwister(seed),
        hamiltonian,
        kernel,
        copy(initial),
        ndraws,
        AdvancedHMC.NoAdaptation(),
        0;
        drop_warmup = false,
        verbose = false,
        progress = false,
    )

    @test length(samples) == ndraws
    @test length(stats) == ndraws
    for (iteration, sample) in enumerate(samples)
        @test length(sample) == nparams
        @test all(isfinite, sample)
        @test isfinite(LogDensityProblems.logdensity(target, sample))
        stat_row = BayesianMGMFRM._advancedhmc_stat_row(stats[iteration], 1, iteration)
        @test stat_row.chain == 1
        @test stat_row.iteration == iteration
        @test isfinite(stat_row.log_density)
        @test stat_row.n_steps >= 1
        @test 0 <= stat_row.tree_depth <= max_depth
        @test isfinite(stat_row.step_size) && stat_row.step_size > 0
    end
    return samples, stats
end

function has_issue(report, code::Symbol)
    return any(issue -> issue.code === code, report.issues)
end

function has_issue(report, code::Symbol, facet::Symbol)
    return any(report.issues) do issue
        issue.code === code &&
            haskey(issue.context, :facet) &&
            issue.context[:facet] === facet
    end
end

function has_doc(mod, name::Symbol)
    isdefined(mod, name) || return false
    binding = Base.Docs.Binding(mod, name)
    haskey(Base.Docs.meta(mod), binding) && return true
    try
        return Base.Docs.doc(getfield(mod, name)) !== nothing
    catch error
        error isa MethodError || rethrow()
        return false
    end
end

function file_sha256(path)
    return bytes2hex(open(sha256, path))
end

function optional_fixture_path(env_key::AbstractString, default_path::AbstractString)
    root = dirname(@__DIR__)
    if haskey(ENV, env_key)
        fixture_path = ENV[env_key]
        isempty(fixture_path) && return ""
        resolved_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
        isfile(resolved_path) ||
            throw(ArgumentError("fixture path from $env_key does not exist: $fixture_path"))
        return fixture_path
    end
    resolved_default = joinpath(root, default_path)
    return isfile(resolved_default) ? default_path : ""
end

function optional_source_bridge_fixture_path(env_key::AbstractString,
        default_path::AbstractString,
        default_stan_model::AbstractString)
    fixture_path = optional_fixture_path(env_key, default_path)
    isempty(fixture_path) && return ""
    root = dirname(@__DIR__)
    if !haskey(ENV, env_key) &&
            !isfile(joinpath(root, default_stan_model))
        return ""
    end
    return fixture_path
end

function check_source_bridge_fixture(fixture_path::AbstractString,
        target;
        expected_schema::AbstractString,
        expected_stan_model::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == expected_schema
    @test Bool(fixture[:propto]) == false
    @test Bool(fixture[:jacobian]) == false
    @test String(fixture[:stan_model]) == expected_stan_model
    stan_model_path = joinpath(root, expected_stan_model)
    @test isfile(stan_model_path)
    @test String(fixture[:stan_model_sha256]) == file_sha256(stan_model_path)
    @test Vector{String}(fixture[:julia_raw_parameter_order]) == target.blueprint.parameter_names

    data = fixture[:stan_data]
    @test Float64(data[:person_sd]) == target.prior.person_sd
    @test Float64(data[:rater_sd]) == target.prior.rater_sd
    @test Float64(data[:item_sd]) == target.prior.item_sd
    @test Float64(data[:log_discrimination_sd]) == target.prior.log_discrimination_sd
    @test Float64(data[:log_consistency_sd]) == target.prior.log_consistency_sd
    @test Float64(data[:step_sd]) == target.prior.step_sd

    x = Vector{Float64}(fixture[:x])
    @test length(x) == LogDensityProblems.dimension(target)
    tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
    stan_lp = Float64(fixture[:stan_log_density])
    @test LogDensityProblems.logdensity(target, x) ≈ stan_lp atol = tol rtol = tol
    if haskey(fixture, :stan_log_likelihood)
        stan_ll = Float64(fixture[:stan_log_likelihood])
        @test stan_lp - BayesianMGMFRM._source_fixture_logprior(target, x) ≈
            stan_ll atol = tol rtol = tol
        @test BayesianMGMFRM._source_fixture_loglikelihood(target, x) ≈
            stan_ll atol = tol rtol = tol
    end
    if haskey(fixture, :stan_pointwise_log_likelihood)
        stan_pointwise = Vector{Float64}(fixture[:stan_pointwise_log_likelihood])
        julia_pointwise = if target.blueprint.family === :gmfrm
            BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
                target.design,
                x,
            )
        elseif target.blueprint.family === :mgmfrm
            BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
                target.design,
                x,
            )
        else
            Float64[]
        end
        @test stan_pointwise ≈ julia_pointwise atol = tol rtol = tol
        @test sum(stan_pointwise) ≈ Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol
    end

    if haskey(fixture, :stan_gradient)
        adtarget = LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x = x)
        lp, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, x)
        @test lp ≈ stan_lp atol = tol rtol = tol
        stan_gradient = Vector{Float64}(fixture[:stan_gradient])
        @test length(stan_gradient) == length(gradient)
        @test maximum(abs.(gradient .- stan_gradient)) < max(tol, 1e-6)
    end
end

function check_gmfrm_bridge_direct_fixture(fixture_path::AbstractString,
        target)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test haskey(fixture, :stan_constrained_parameter_order)
    @test haskey(fixture, :stan_constrained_parameter_values)
    @test haskey(fixture, :julia_direct_parameter_order)
    @test haskey(fixture, :julia_direct_parameter_values)
    @test haskey(fixture, :stan_log_likelihood)
    @test haskey(fixture, :fit_ready_candidate)

    stan_constrained_names = Vector{String}(fixture[:stan_constrained_parameter_order])
    @test "item.1" in stan_constrained_names
    @test "item_discrimination.1" in stan_constrained_names
    @test "rater_consistency.1" in stan_constrained_names
    @test length(stan_constrained_names) == length(Vector{Float64}(fixture[:stan_constrained_parameter_values]))

    x = Vector{Float64}(fixture[:x])
    transform_diagnostics =
        BayesianMGMFRM._gmfrm_promotion_candidate_transform_diagnostics(target, x)
    pointwise_fixture =
        BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(target, x)
    tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
    @test transform_diagnostics.summary.passed
    @test pointwise_fixture.summary.passed
    @test Vector{String}(fixture[:julia_direct_parameter_order]) ==
        transform_diagnostics.direct_parameter_names
    @test pointwise_fixture.parameter_names == transform_diagnostics.direct_parameter_names
    @test Vector{Float64}(fixture[:julia_direct_parameter_values]) ≈
        transform_diagnostics.direct_parameter_values atol = tol rtol = tol
    @test Vector{Float64}(fixture[:julia_direct_parameter_values]) ≈
        pointwise_fixture.parameter_values atol = tol rtol = tol
    @test sum(transform_diagnostics.direct_pointwise_loglikelihood) ≈
        Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol
    @test pointwise_fixture.loglikelihood ≈
        Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol
    candidate = fixture[:fit_ready_candidate]
    @test String(candidate[:schema]) ==
        "bayesianmgmfrm.fit_ready_scalar_gmfrm_bridge_oracle.v1"
    @test String(candidate[:status]) == "internal_fit_ready_candidate"
    @test Bool(candidate[:public_fit]) == false
    @test Bool(candidate[:fit_ready]) == false
    @test Vector{String}(candidate[:raw_parameter_order]) == target.blueprint.parameter_names
    @test Vector{Float64}(candidate[:raw_parameter_values]) ≈ x atol = tol rtol = tol
    @test Float64(candidate[:raw_log_density]) ≈
        LogDensityProblems.logdensity(target, x) atol = tol rtol = tol
    candidate_gradient = Vector{Float64}(candidate[:raw_gradient])
    adtarget = LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x = x)
    _, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, x)
    @test candidate_gradient ≈ gradient atol = max(tol, 1e-6) rtol = max(tol, 1e-6)
    @test Vector{String}(candidate[:direct_parameter_order]) ==
        target.blueprint.constrained_parameter_names
    @test Vector{Float64}(candidate[:direct_parameter_values]) ≈
        pointwise_fixture.parameter_values atol = tol rtol = tol
    @test Vector{Float64}(candidate[:pointwise_log_likelihood]) ≈
        pointwise_fixture.pointwise_loglikelihood atol = tol rtol = tol
    @test Float64(candidate[:log_likelihood]) ≈
        pointwise_fixture.loglikelihood atol = tol rtol = tol
    @test Vector{String}(candidate[:stan_generated_quantity_order]) ==
        ["log_lik.$index" for index in 1:length(pointwise_fixture.pointwise_loglikelihood)]
end

function json_bool_matrix(value)
    rows = [Vector{Bool}(row) for row in value]
    isempty(rows) && return Matrix{Bool}(undef, 0, 0)
    return [rows[row][col] for row in eachindex(rows), col in eachindex(rows[1])]
end

function check_mgmfrm_bridge_confirmatory_fixture(fixture_path::AbstractString,
        target)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test haskey(fixture, :stan_constrained_parameter_order)
    @test haskey(fixture, :stan_constrained_parameter_values)
    @test haskey(fixture, :julia_direct_parameter_order)
    @test haskey(fixture, :julia_direct_parameter_values)
    @test haskey(fixture, :stan_log_likelihood)
    @test haskey(fixture, :confirmatory_candidate)

    stan_constrained_names = Vector{String}(fixture[:stan_constrained_parameter_order])
    @test "item_dimension_discrimination.1" in stan_constrained_names
    @test "rater_consistency.1" in stan_constrained_names
    @test "rater.1" in stan_constrained_names
    @test length(stan_constrained_names) == length(Vector{Float64}(fixture[:stan_constrained_parameter_values]))

    x = Vector{Float64}(fixture[:x])
    direct = BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        target.design,
        x,
    )
    pointwise = BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(
        target.design,
        direct,
    )
    tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
    @test Vector{String}(fixture[:julia_direct_parameter_order]) ==
        target.blueprint.constrained_parameter_names
    @test Vector{Float64}(fixture[:julia_direct_parameter_values]) ≈
        direct atol = tol rtol = tol
    @test sum(pointwise) ≈ Float64(fixture[:stan_log_likelihood]) atol = tol rtol = tol

    candidate = fixture[:confirmatory_candidate]
    @test String(candidate[:schema]) ==
        "bayesianmgmfrm.fit_ready_confirmatory_mgmfrm_bridge_oracle.v1"
    @test String(candidate[:status]) == "internal_fit_ready_candidate"
    @test Bool(candidate[:public_fit]) == false
    @test Bool(candidate[:fit_ready]) == false
    @test Int(candidate[:dimensions]) == target.design.spec.dimensions
    @test json_bool_matrix(candidate[:q_matrix]) == target.design.spec.q_matrix
    @test String(candidate[:latent_correlation]) == "identity_fixed"
    @test String(candidate[:ability_location]) == "zero_by_dimension"
    @test String(candidate[:ability_scale]) == "unit_variance_by_dimension"
    @test Float64(candidate[:source_scale]) == 1.7
    @test String(candidate[:interpreted_loading_sign]) == "positive"
    @test Vector{String}(candidate[:raw_parameter_order]) == target.blueprint.parameter_names
    @test Vector{Float64}(candidate[:raw_parameter_values]) ≈ x atol = tol rtol = tol
    @test Float64(candidate[:raw_log_density]) ≈
        LogDensityProblems.logdensity(target, x) atol = tol rtol = tol
    candidate_gradient = Vector{Float64}(candidate[:raw_gradient])
    adtarget = LogDensityProblemsAD.ADgradient(:ForwardDiff, target; x = x)
    _, gradient = LogDensityProblems.logdensity_and_gradient(adtarget, x)
    @test candidate_gradient ≈ gradient atol = max(tol, 1e-6) rtol = max(tol, 1e-6)
    @test Vector{String}(candidate[:direct_parameter_order]) ==
        target.blueprint.constrained_parameter_names
    @test Vector{Float64}(candidate[:direct_parameter_values]) ≈
        direct atol = tol rtol = tol
    @test Vector{Float64}(candidate[:pointwise_log_likelihood]) ≈
        pointwise atol = tol rtol = tol
    @test Float64(candidate[:log_likelihood]) ≈
        sum(pointwise) atol = tol rtol = tol
    @test Vector{String}(candidate[:stan_generated_quantity_order]) ==
        ["log_lik.$index" for index in 1:length(pointwise)]
end

function test_parameter_order_hash(names::Vector{String})
    return bytes2hex(sha256(codeunits(join(names, "\n"))))
end

function check_gmfrm_candidate_chain_study_fixture(fixture_path::AbstractString,
        target,
        near_oracle_raw::AbstractVector)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_candidate_chain_study.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_promotion_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_gmfrm_promotion_candidate_logdensity"
    @test String(fixture[:density_space]) == "raw_unconstrained"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_candidate_chain_v1"
    @test String(protocol[:backend]) == "advancedhmc"
    @test String(protocol[:sampler]) == "nuts"
    @test Int(protocol[:chains]) == 2
    @test Int(protocol[:warmup]) == 32
    @test Int(protocol[:draws]) == 32
    @test Float64(protocol[:step_size]) == 0.02
    @test Float64(protocol[:target_accept]) == 0.8
    @test Int(protocol[:max_depth]) == 5
    @test String(protocol[:metric]) == "unit"
    @test Bool(protocol[:split_chains])
    @test Float64(thresholds[:max_rhat]) == 1.2
    @test Float64(thresholds[:min_ess]) == 8.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Int(thresholds[:n_divergences]) == 0
    @test Int(thresholds[:n_max_treedepth]) == 0
    @test Int(thresholds[:n_failed_direct_constraints]) == 0
    @test Int(thresholds[:n_nonfinite_logdensity]) == 0
    @test Int(thresholds[:n_nonfinite_direct_loglikelihood]) == 0

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test raw_names == target.blueprint.parameter_names
    @test direct_names == target.blueprint.constrained_parameter_names
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)

    study_fixtures = fixture[:fixtures]
    @test length(study_fixtures) == 2
    labels = Set(String(row[:fixture]) for row in study_fixtures)
    @test labels == Set(["near_oracle", "zero_centered"])
    for row in study_fixtures
        label = String(row[:fixture])
        initial_raw = Vector{Float64}(row[:initial_raw_parameter_values])
        if label == "near_oracle"
            @test initial_raw ≈ Float64.(collect(near_oracle_raw))
        elseif label == "zero_centered"
            @test initial_raw == zeros(length(near_oracle_raw))
        end
        @test length(Vector{Float64}(row[:initial_direct_parameter_values])) ==
            length(direct_names)

        summary = row[:summary]
        @test Bool(summary[:internal_passed])
        @test Bool(summary[:passed_protocol])
        @test String(summary[:internal_flag]) == "ok"
        @test Int(summary[:n_chains]) == Int(protocol[:chains])
        @test Int(summary[:draws_per_chain]) == Int(protocol[:draws])
        @test Int(summary[:total_draws]) ==
            Int(protocol[:chains]) * Int(protocol[:draws])
        @test Float64(summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
        @test Float64(summary[:min_ess]) >= Float64(thresholds[:min_ess])
        @test Float64(summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
        @test Int(summary[:n_bad_rhat]) == 0
        @test Int(summary[:n_low_ess]) == 0
        @test Int(summary[:n_divergences]) == Int(thresholds[:n_divergences])
        @test Int(summary[:n_max_treedepth]) == Int(thresholds[:n_max_treedepth])
        @test Int(summary[:n_nonfinite_logdensity]) ==
            Int(thresholds[:n_nonfinite_logdensity])
        @test Int(summary[:n_nonfinite_direct_loglikelihood]) ==
            Int(thresholds[:n_nonfinite_direct_loglikelihood])
        @test Int(summary[:n_failed_direct_constraints]) ==
            Int(thresholds[:n_failed_direct_constraints])

        @test length(row[:sampler_rows]) == Int(protocol[:chains])
        @test all(sampler_row -> String(sampler_row[:flag]) == "ok", row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_divergences]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_max_treedepth]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Float64(sampler_row[:e_bfmi]) >=
            Float64(thresholds[:min_ebfmi]), row[:sampler_rows])

        @test all(block_row -> String(block_row[:flag]) == "ok", row[:raw_block_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:direct_block_rows])
        @test all(constraint_row -> Bool(constraint_row[:passed]),
            row[:direct_constraint_rows])
        @test all(constraint_row -> Int(constraint_row[:n_failed]) == 0,
            row[:direct_constraint_rows])

        pointwise = row[:pointwise]
        @test Int(pointwise[:n_observations]) == target.design.spec.data.n
        @test Int(pointwise[:n_draws]) == Int(summary[:total_draws])
        @test Int(pointwise[:n_nonfinite_pointwise]) == 0
        @test Int(pointwise[:n_nonfinite_loglikelihood]) == 0
        @test isfinite(Float64(pointwise[:minimum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:minimum_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_loglikelihood]))
    end

    overall = fixture[:summary]
    @test Int(overall[:n_fixtures]) == 2
    @test Int(overall[:n_passed_protocol]) == 2
    @test Bool(overall[:overall_passed])
    @test Float64(overall[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(overall[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(overall[:min_ebfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(overall[:n_divergences]) == 0
    @test Int(overall[:n_max_treedepth]) == 0
    @test Int(overall[:n_failed_direct_constraints]) == 0
    @test Int(overall[:n_nonfinite_logdensity]) == 0
    @test Int(overall[:n_nonfinite_direct_loglikelihood]) == 0
end

function check_gmfrm_stress_chain_grid_fixture(fixture_path::AbstractString,
        target,
        near_oracle_raw::AbstractVector)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_stress_chain_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_promotion_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_gmfrm_promotion_candidate_logdensity"
    @test String(fixture[:density_space]) == "raw_unconstrained"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_stress_chain_grid_v1"
    @test Int(protocol[:chains]) == 2
    @test Int(protocol[:warmup]) == 96
    @test Int(protocol[:draws]) == 96
    @test String(protocol[:metric]) == "unit"
    @test Bool(protocol[:split_chains])
    @test Float64(thresholds[:max_rhat]) == 1.2
    @test Float64(thresholds[:min_ess]) == 16.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test raw_names == target.blueprint.parameter_names
    @test direct_names == target.blueprint.constrained_parameter_names
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    labels = Set(String(row[:scenario]) for row in scenarios)
    @test labels == Set([
        "near_oracle_long",
        "zero_centered_long",
        "near_oracle_high_acceptance",
    ])
    for row in scenarios
        label = String(row[:scenario])
        initial_raw = Vector{Float64}(row[:initial_raw_parameter_values])
        if label == "zero_centered_long"
            @test initial_raw == zeros(length(near_oracle_raw))
        else
            @test initial_raw ≈ Float64.(collect(near_oracle_raw))
        end
        @test length(Vector{Float64}(row[:initial_direct_parameter_values])) ==
            length(direct_names)

        controls = row[:controls]
        @test Float64(controls[:step_size]) > 0
        @test Float64(controls[:target_accept]) >= 0.8
        @test Int(controls[:max_depth]) >= 6
        @test Float64(controls[:init_jitter]) >= 0

        summary = row[:summary]
        @test Bool(summary[:internal_passed])
        @test Bool(summary[:passed_protocol])
        @test String(summary[:internal_flag]) == "ok"
        @test Int(summary[:n_chains]) == Int(protocol[:chains])
        @test Int(summary[:draws_per_chain]) == Int(protocol[:draws])
        @test Int(summary[:total_draws]) ==
            Int(protocol[:chains]) * Int(protocol[:draws])
        @test Float64(summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
        @test Float64(summary[:min_ess]) >= Float64(thresholds[:min_ess])
        @test Float64(summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
        @test Int(summary[:n_bad_rhat]) == 0
        @test Int(summary[:n_low_ess]) == 0
        @test Int(summary[:n_divergences]) == Int(thresholds[:n_divergences])
        @test Int(summary[:n_max_treedepth]) == Int(thresholds[:n_max_treedepth])
        @test Int(summary[:n_nonfinite_logdensity]) ==
            Int(thresholds[:n_nonfinite_logdensity])
        @test Int(summary[:n_nonfinite_direct_loglikelihood]) ==
            Int(thresholds[:n_nonfinite_direct_loglikelihood])
        @test Int(summary[:n_failed_direct_constraints]) ==
            Int(thresholds[:n_failed_direct_constraints])
        @test all(sampler_row -> String(sampler_row[:flag]) == "ok", row[:sampler_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:raw_block_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:direct_block_rows])
        @test all(constraint_row -> Bool(constraint_row[:passed]),
            row[:direct_constraint_rows])

        pointwise = row[:pointwise]
        @test Int(pointwise[:n_observations]) == target.design.spec.data.n
        @test Int(pointwise[:n_draws]) == Int(summary[:total_draws])
        @test Int(pointwise[:n_nonfinite_pointwise]) == 0
        @test Int(pointwise[:n_nonfinite_loglikelihood]) == 0
    end

    overall = fixture[:summary]
    @test Int(overall[:n_scenarios]) == 3
    @test Int(overall[:n_passed_protocol]) == 3
    @test Bool(overall[:overall_passed])
    @test Float64(overall[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(overall[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(overall[:min_ebfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(overall[:n_divergences]) == 0
    @test Int(overall[:n_max_treedepth]) == 0
    @test Int(overall[:n_failed_direct_constraints]) == 0
    @test Int(overall[:n_nonfinite_logdensity]) == 0
    @test Int(overall[:n_nonfinite_direct_loglikelihood]) == 0
end

function check_mgmfrm_candidate_chain_study_fixture(fixture_path::AbstractString,
        target,
        near_oracle_raw::AbstractVector)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_candidate_chain_study.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_fit_ready_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_source_fixture_logdensity"
    @test String(fixture[:density_space]) == "raw_unconstrained"
    @test Int(fixture[:dimensions]) == target.design.spec.dimensions
    @test json_bool_matrix(fixture[:q_matrix]) == target.design.spec.q_matrix
    @test String(fixture[:latent_correlation]) == "identity_fixed"
    @test String(fixture[:ability_scale]) == "unit_variance_by_dimension"
    @test Float64(fixture[:source_scale]) == 1.7

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "confirmatory_mgmfrm_candidate_chain_v1"
    @test String(protocol[:backend]) == "advancedhmc"
    @test String(protocol[:sampler]) == "nuts"
    @test Int(protocol[:chains]) == 2
    @test Int(protocol[:warmup]) == 32
    @test Int(protocol[:draws]) == 32
    @test Float64(protocol[:step_size]) == 0.02
    @test Float64(protocol[:target_accept]) == 0.8
    @test Int(protocol[:max_depth]) == 8
    @test String(protocol[:metric]) == "unit"
    @test Bool(protocol[:split_chains])
    @test Float64(thresholds[:max_rhat]) == 1.35
    @test Float64(thresholds[:min_ess]) == 6.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Int(thresholds[:n_divergences]) == 0
    @test Int(thresholds[:n_max_treedepth]) == 0
    @test Int(thresholds[:n_failed_direct_constraints]) == 0
    @test Int(thresholds[:n_nonfinite_logdensity]) == 0
    @test Int(thresholds[:n_nonfinite_direct_loglikelihood]) == 0

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test raw_names == target.blueprint.parameter_names
    @test direct_names == target.blueprint.constrained_parameter_names
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)

    study_fixtures = fixture[:fixtures]
    @test length(study_fixtures) == 2
    labels = Set(String(row[:fixture]) for row in study_fixtures)
    @test labels == Set(["near_oracle", "zero_centered"])
    for row in study_fixtures
        label = String(row[:fixture])
        initial_raw = Vector{Float64}(row[:initial_raw_parameter_values])
        if label == "near_oracle"
            @test initial_raw ≈ Float64.(collect(near_oracle_raw))
        elseif label == "zero_centered"
            @test initial_raw == zeros(length(near_oracle_raw))
        end
        @test length(Vector{Float64}(row[:initial_direct_parameter_values])) ==
            length(direct_names)

        summary = row[:summary]
        @test Bool(summary[:internal_passed])
        @test Bool(summary[:passed_protocol])
        @test String(summary[:internal_flag]) == "ok"
        @test Int(summary[:n_chains]) == Int(protocol[:chains])
        @test Int(summary[:draws_per_chain]) == Int(protocol[:draws])
        @test Int(summary[:total_draws]) ==
            Int(protocol[:chains]) * Int(protocol[:draws])
        @test Float64(summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
        @test Float64(summary[:min_ess]) >= Float64(thresholds[:min_ess])
        @test Float64(summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
        @test Int(summary[:n_bad_rhat]) == 0
        @test Int(summary[:n_low_ess]) == 0
        @test Int(summary[:n_divergences]) == Int(thresholds[:n_divergences])
        @test Int(summary[:n_max_treedepth]) == Int(thresholds[:n_max_treedepth])
        @test Int(summary[:n_nonfinite_logdensity]) ==
            Int(thresholds[:n_nonfinite_logdensity])
        @test Int(summary[:n_nonfinite_direct_loglikelihood]) ==
            Int(thresholds[:n_nonfinite_direct_loglikelihood])
        @test Int(summary[:n_failed_direct_constraints]) ==
            Int(thresholds[:n_failed_direct_constraints])

        @test length(row[:sampler_rows]) == Int(protocol[:chains])
        @test all(sampler_row -> String(sampler_row[:flag]) == "ok", row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_divergences]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Int(sampler_row[:n_max_treedepth]) == 0,
            row[:sampler_rows])
        @test all(sampler_row -> Float64(sampler_row[:e_bfmi]) >=
            Float64(thresholds[:min_ebfmi]), row[:sampler_rows])

        @test all(block_row -> String(block_row[:flag]) == "ok", row[:raw_block_rows])
        @test all(block_row -> String(block_row[:flag]) == "ok", row[:direct_block_rows])
        @test all(constraint_row -> Bool(constraint_row[:passed]),
            row[:direct_constraint_rows])
        @test all(constraint_row -> Int(constraint_row[:n_failed]) == 0,
            row[:direct_constraint_rows])

        pointwise = row[:pointwise]
        @test Int(pointwise[:n_observations]) == target.design.spec.data.n
        @test Int(pointwise[:n_draws]) == Int(summary[:total_draws])
        @test Int(pointwise[:n_nonfinite_pointwise]) == 0
        @test Int(pointwise[:n_nonfinite_loglikelihood]) == 0
        @test isfinite(Float64(pointwise[:minimum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_pointwise_loglikelihood]))
        @test isfinite(Float64(pointwise[:minimum_loglikelihood]))
        @test isfinite(Float64(pointwise[:maximum_loglikelihood]))
    end

    overall = fixture[:summary]
    @test Int(overall[:n_fixtures]) == 2
    @test Int(overall[:n_passed_protocol]) == 2
    @test Bool(overall[:overall_passed])
    @test Float64(overall[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(overall[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(overall[:min_ebfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(overall[:n_divergences]) == 0
    @test Int(overall[:n_max_treedepth]) == 0
    @test Int(overall[:n_failed_direct_constraints]) == 0
    @test Int(overall[:n_nonfinite_logdensity]) == 0
    @test Int(overall[:n_nonfinite_direct_loglikelihood]) == 0
end

function check_gmfrm_recovery_smoke_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_recovery_smoke.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_promotion_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_gmfrm_promotion_candidate_logdensity"

    protocol = fixture[:protocol]
    grid = protocol[:grid]
    sampler = protocol[:sampler]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260701
    @test Int(protocol[:sampler_seed]) == 20260702
    @test Int(grid[:persons]) == 4
    @test Int(grid[:items]) == 3
    @test Int(grid[:raters]) == 3
    @test Int(grid[:categories]) == 3
    @test String(grid[:rating_density]) == "full_crossed"
    @test Int(grid[:observations]) == 36
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 64
    @test Int(sampler[:draws]) == 64
    @test Float64(sampler[:target_accept]) == 0.85
    @test Int(sampler[:max_depth]) == 6
    @test String(sampler[:metric]) == "unit"
    @test Float64(thresholds[:max_rhat]) == 1.2
    @test Float64(thresholds[:min_ess]) == 12.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Float64(thresholds[:max_block_mean_absolute_error]) == 0.5
    @test Float64(thresholds[:max_parameter_absolute_error]) == 1.0
    @test Float64(thresholds[:min_block_coverage_rate]) == 0.5

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test length(raw_names) == 17
    @test length(direct_names) == 19
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)
    @test length(Vector{Float64}(fixture[:truth][:raw_parameter_values])) == length(raw_names)
    @test length(Vector{Float64}(fixture[:truth][:direct_parameter_values])) ==
        length(direct_names)

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == Int(grid[:observations])
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == Int(grid[:observations])
    @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])
    @test length(simulated[:person_levels]) == Int(grid[:persons])
    @test length(simulated[:rater_levels]) == Int(grid[:raters])
    @test length(simulated[:item_levels]) == Int(grid[:items])

    sampler_summary = fixture[:sampler_summary]
    @test String(sampler_summary[:internal_flag]) == "ok"
    @test Bool(sampler_summary[:internal_passed])
    @test Int(sampler_summary[:n_chains]) == Int(sampler[:chains])
    @test Int(sampler_summary[:draws_per_chain]) == Int(sampler[:draws])
    @test Int(sampler_summary[:total_draws]) ==
        Int(sampler[:chains]) * Int(sampler[:draws])
    @test Float64(sampler_summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(sampler_summary[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(sampler_summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(sampler_summary[:n_divergences]) == 0
    @test Int(sampler_summary[:n_max_treedepth]) == 0
    @test Int(sampler_summary[:n_failed_direct_constraints]) == 0
    @test Int(sampler_summary[:n_nonfinite_logdensity]) == 0
    @test Int(sampler_summary[:n_nonfinite_direct_loglikelihood]) == 0

    recovery_rows = fixture[:recovery_rows]
    recovery_by_block = fixture[:recovery_by_block]
    @test length(recovery_rows) == length(direct_names)
    @test length(recovery_by_block) == 6
    @test Set(String(row[:group]) for row in recovery_by_block) == Set([
        "person",
        "rater",
        "item",
        "item_discrimination",
        "rater_consistency",
        "rater_steps",
    ])
    @test all(row -> Float64(row[:absolute_bias]) <=
        Float64(thresholds[:max_parameter_absolute_error]), recovery_rows)
    @test all(row -> Float64(row[:mean_absolute_error]) <=
        Float64(thresholds[:max_block_mean_absolute_error]), recovery_by_block)
    @test all(row -> Float64(row[:coverage_rate]) >=
        Float64(thresholds[:min_block_coverage_rate]), recovery_by_block)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_parameters]) == length(direct_names)
    @test Int(summary[:n_blocks]) == length(recovery_by_block)
    @test Float64(summary[:max_block_mean_absolute_error]) <=
        Float64(thresholds[:max_block_mean_absolute_error])
    @test Float64(summary[:max_parameter_absolute_error]) <=
        Float64(thresholds[:max_parameter_absolute_error])
    @test Float64(summary[:min_block_coverage_rate]) >=
        Float64(thresholds[:min_block_coverage_rate])
    @test String(fixture[:baseline_comparison][:status]) == "pending"
end

function check_gmfrm_baseline_comparison_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_baseline_comparison.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_baseline_comparison"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_baseline_comparison_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260701
    @test Int(protocol[:thresholds][:minimum_models]) == 3
    @test Int(protocol[:thresholds][:n_observations]) == 36
    @test Bool(protocol[:thresholds][:require_same_observations])
    @test Bool(protocol[:thresholds][:require_finite_elpd])
    @test Bool(protocol[:thresholds][:require_finite_weights])
    @test String(protocol[:gmfrm_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:gmfrm_sampler][:draws]) == 64
    @test String(protocol[:baseline_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:baseline_sampler][:draws]) == 64
    @test Int(protocol[:baseline_sampler][:seeds][:partial_credit]) == 20260742
    @test Int(protocol[:baseline_sampler][:seeds][:rating_scale]) == 20260743

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == 36
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == 36
    @test length(simulated[:person_levels]) == 4
    @test length(simulated[:rater_levels]) == 3
    @test length(simulated[:item_levels]) == 3
    @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])
    @test String(simulated[:truth_source]) == "gmfrm_recovery_smoke_truth"

    model_rows = fixture[:model_rows]
    @test length(model_rows) == 3
    @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
    @test issorted([Float64(row[:elpd_waic]) for row in model_rows]; rev = true)
    @test Set(String(row[:model]) for row in model_rows) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test all(row -> Int(row[:n_observations]) == 36, model_rows)
    @test all(row -> Int(row[:n_draws]) == 128, model_rows)
    @test all(row -> isfinite(Float64(row[:elpd_waic])), model_rows)
    @test all(row -> isfinite(Float64(row[:waic])), model_rows)
    @test all(row -> isfinite(Float64(row[:relative_weight])), model_rows)
    @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
    @test all(row -> String(row[:criterion]) == "waic", model_rows)
    @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
        model_rows)
    @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
        model_rows)

    gmfrm_row = only(row for row in model_rows
        if String(row[:model]) == "gmfrm_internal_candidate")
    @test String(gmfrm_row[:family]) == "gmfrm"
    @test String(gmfrm_row[:source]) == "internal_raw_candidate"
    @test String(gmfrm_row[:threshold_regime]) == "generalized_partial_credit"
    @test Bool(gmfrm_row[:public_fit]) == false
    @test Int(gmfrm_row[:n_parameters]) == 17
    @test String(simulated[:raw_parameter_order_sha256]) ==
        String(gmfrm_row[:parameter_order_sha256])
    @test String(simulated[:direct_parameter_order_sha256]) ==
        String(gmfrm_row[:direct_parameter_order_sha256])
    @test Float64(gmfrm_row[:elpd_difference]) <= 0.0
    @test Float64(gmfrm_row[:se_elpd_difference]) >
        abs(Float64(gmfrm_row[:elpd_difference]))

    baseline_rows = [row for row in model_rows if String(row[:family]) == "mfrm"]
    @test length(baseline_rows) == 2
    @test all(row -> String(row[:source]) == "public_minimal_fit", baseline_rows)
    @test all(row -> Bool(row[:public_fit]), baseline_rows)
    @test Set(String(row[:threshold_regime]) for row in baseline_rows) ==
        Set(["partial_credit", "rating_scale"])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:comparison_executed])
    @test Int(summary[:n_models]) == length(model_rows)
    @test String(summary[:best_model]) == String(model_rows[1][:model])
    @test Int(summary[:gmfrm_rank]) == Int(gmfrm_row[:rank])
    @test Float64(summary[:gmfrm_elpd_difference]) ≈
        Float64(gmfrm_row[:elpd_difference])
    @test Float64(summary[:gmfrm_relative_weight]) ≈
        Float64(gmfrm_row[:relative_weight])
    @test Bool(summary[:any_high_variance_waic])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_guarded_exposure_decision"
end

function check_gmfrm_baseline_calibration_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_baseline_calibration_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_baseline_calibration_grid"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_baseline_calibration_grid_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_recovery_smoke_grid_variant"
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:calibration][:target]) == "expected_score"
    @test Int(protocol[:calibration][:bins]) == 3
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Bool(thresholds[:require_all_scenarios_passed])
    @test Bool(thresholds[:require_same_observations])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_finite_calibration])
    @test Bool(thresholds[:require_sampler_passed])
    @test Float64(thresholds[:max_expected_score_rmse]) == 1.25
    @test Float64(thresholds[:max_mean_absolute_calibration_error]) == 0.75

    scenarios = fixture[:scenarios]
    @test length(scenarios) == Int(thresholds[:n_scenarios])
    @test Set(String(scenario[:scenario]) for scenario in scenarios) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    for scenario in scenarios
        simulated = scenario[:simulated_data]
        @test Int(simulated[:n_observations]) == Int(thresholds[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) ==
            Int(thresholds[:n_observations])
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) ==
            Set([0, 1, 2])
        @test length(simulated[:person_levels]) == 4
        @test length(simulated[:rater_levels]) == 3
        @test length(simulated[:item_levels]) == 3
        @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])

        model_rows = scenario[:model_rows]
        @test length(model_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
        @test issorted([Float64(row[:elpd_waic]) for row in model_rows]; rev = true)
        @test Set(String(row[:model]) for row in model_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> Int(row[:n_observations]) == Int(thresholds[:n_observations]),
            model_rows)
        @test all(row -> Int(row[:n_draws]) == 128, model_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), model_rows)
        @test all(row -> isfinite(Float64(row[:relative_weight])), model_rows)
        @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
            model_rows)
        @test all(row -> length(row[:expected_score_calibration]) == 3, model_rows)
        @test all(row -> Float64(row[:predictive_metrics][:expected_score_rmse]) <=
            Float64(thresholds[:max_expected_score_rmse]), model_rows)
        @test all(row -> Float64(row[:predictive_metrics][:mean_absolute_calibration_error]) <=
            Float64(thresholds[:max_mean_absolute_calibration_error]), model_rows)
        @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
            model_rows)

        gmfrm_row = only(row for row in model_rows
            if String(row[:model]) == "gmfrm_internal_candidate")
        @test String(gmfrm_row[:family]) == "gmfrm"
        @test String(gmfrm_row[:source]) == "internal_raw_candidate"
        @test Bool(gmfrm_row[:public_fit]) == false
        @test Int(gmfrm_row[:n_parameters]) == 17
        @test String(gmfrm_row[:direct_parameter_order_sha256]) != "null"

        baseline_rows = [row for row in model_rows if String(row[:family]) == "mfrm"]
        @test length(baseline_rows) == 2
        @test all(row -> String(row[:source]) == "public_minimal_fit", baseline_rows)
        @test all(row -> Bool(row[:public_fit]), baseline_rows)

        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test String(summary[:best_model]) == String(model_rows[1][:model])
        @test Int(summary[:gmfrm_rank]) == Int(gmfrm_row[:rank])
        @test Float64(summary[:gmfrm_expected_score_rmse]) ≈
            Float64(gmfrm_row[:predictive_metrics][:expected_score_rmse])
        @test Float64(summary[:gmfrm_mean_absolute_calibration_error]) ≈
            Float64(gmfrm_row[:predictive_metrics][:mean_absolute_calibration_error])
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_models]) == length(scenarios) * Int(thresholds[:n_models_per_scenario])
    @test Int(summary[:n_public_baseline_models]) == 2 * length(scenarios)
    @test Int(summary[:n_internal_candidate_models]) == length(scenarios)
    @test sum(Int(row[:n]) for row in summary[:best_model_counts]) == length(scenarios)
    @test Float64(summary[:max_expected_score_rmse]) <=
        Float64(thresholds[:max_expected_score_rmse])
    @test Float64(summary[:max_mean_absolute_calibration_error]) <=
        Float64(thresholds[:max_mean_absolute_calibration_error])
    @test Bool(summary[:any_high_variance_waic])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_public_exposure_review"
end

function check_gmfrm_interval_decision_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_interval_decision_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_interval_decision_grid"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_interval_decision_grid_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_baseline_calibration_grid_v1"
    @test Set(String(scenario) for scenario in protocol[:scenarios]) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    @test Set(Float64(interval) for interval in protocol[:intervals]) == Set([0.8, 0.95])
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:prediction_target]) == "same_observation_waic"
    @test String(protocol[:decision_rules][:public_exposure_decision]) == "keep_internal"
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:high_variance_waic_blocks_public_exposure])
    @test Bool(protocol[:decision_rules][:sparse_design_grid_required_before_exposure])
    @test Bool(protocol[:decision_rules][:psis_loo_or_influence_review_required_before_exposure])
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Bool(thresholds[:require_same_observations])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_intervals])
    @test Bool(thresholds[:require_decision_stability])

    scenarios = fixture[:scenarios]
    @test length(scenarios) == Int(thresholds[:n_scenarios])
    @test Set(String(scenario[:scenario]) for scenario in scenarios) ==
        Set(String(scenario) for scenario in protocol[:scenarios])
    for scenario in scenarios
        simulated = scenario[:simulated_data]
        @test Int(simulated[:n_observations]) == Int(thresholds[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) ==
            Int(thresholds[:n_observations])
        @test length(scenario[:gmfrm_parameter_order]) == 19
        @test String(scenario[:gmfrm_parameter_order_sha256]) != "null"

        model_rows = scenario[:model_rows]
        @test length(model_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
        @test all(row -> Int(row[:n_observations]) == Int(thresholds[:n_observations]),
            model_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
        gmfrm_row = only(row for row in model_rows
            if String(row[:model]) == "gmfrm_internal_candidate")
        @test String(gmfrm_row[:family]) == "gmfrm"
        @test Bool(gmfrm_row[:public_fit]) == false
        @test Int(gmfrm_row[:n_parameters]) == 17
        @test String(gmfrm_row[:direct_parameter_order_sha256]) ==
            String(scenario[:gmfrm_parameter_order_sha256])

        interval_rows = scenario[:interval_coverage]
        @test length(interval_rows) == 2
        @test Set(Float64(row[:interval_probability]) for row in interval_rows) ==
            Set([0.8, 0.95])
        for interval_row in interval_rows
            @test length(interval_row[:recovery_by_block]) == 6
            @test Int(interval_row[:summary][:n_parameters]) == 19
            @test Int(interval_row[:summary][:n_blocks]) == 6
            @test Bool(interval_row[:summary][:all_intervals_finite])
            @test Float64(interval_row[:summary][:overall_coverage_rate]) >= 0.8
            @test Float64(interval_row[:summary][:min_block_coverage_rate]) >= 0.0
            @test all(row -> String(row[:flag]) in ("ok", "coverage_below_nominal"),
                interval_row[:recovery_by_block])
        end

        decision = scenario[:decision]
        @test String(decision[:selected_decision]) == "keep_internal"
        @test Bool(decision[:public_fit_allowed]) == false
        @test Bool(decision[:experimental_keyword_enabled]) == false
        @test String(decision[:prediction_target]) == "same_observation_waic"
        @test Bool(decision[:all_samplers_passed])
        @test Bool(decision[:any_high_variance_waic])
        @test Set(String(row[:blocker]) for row in decision[:blocker_rows]) ==
            Set(["high_variance_waic_requires_followup", "sparse_design_grid_missing"])

        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test String(summary[:selected_decision]) == "keep_internal"
        @test Bool(summary[:any_high_variance_waic])
        @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
        @test Float64(summary[:min_block_coverage_rate]) >= 0.0
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_interval_records]) == 2 * length(scenarios)
    @test Int(summary[:n_models]) == 3 * length(scenarios)
    @test Bool(summary[:all_local_intervals_finite])
    @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
    @test Float64(summary[:min_block_coverage_rate]) >= 0.0
    @test Int(summary[:keep_internal_decision_count]) == length(scenarios)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Bool(summary[:any_high_variance_waic])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_variance_waic_requires_followup", "sparse_design_grid_missing"])
    @test String(summary[:recommendation]) == "keep_internal_until_sparse_and_waic_followup"
    @test String(summary[:next_gate]) == "scalar_gmfrm_sparse_design_grid"
end

function check_gmfrm_sparse_design_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_sparse_design_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_sparse_design_grid"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_sparse_design_grid_v1"
    @test String(protocol[:simulation_source]) == "scalar_gmfrm_interval_decision_grid_v1"
    @test Int(protocol[:full_crossed_observations]) == 36
    @test String(protocol[:sparse_designs][:rating_density]) == "sparse_connected"
    @test Set(String(pattern) for pattern in protocol[:sparse_designs][:patterns]) ==
        Set(["half_crossed_parity", "reference_bridge", "cyclic_missing_item_cells"])
    @test String(protocol[:validation][:bias_terms][1][1]) == "rater"
    @test String(protocol[:validation][:bias_terms][1][2]) == "item"
    @test Int(protocol[:validation][:min_cell_count]) == 3
    @test Bool(protocol[:validation][:require_no_validation_errors])
    @test Bool(protocol[:validation][:require_connected_design])
    @test Bool(protocol[:validation][:require_full_location_rank])
    @test Bool(protocol[:validation][:warnings_recorded_not_blocking])
    @test Set(Float64(interval) for interval in protocol[:intervals]) == Set([0.8, 0.95])
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:prediction_target]) == "same_observation_waic"
    @test String(protocol[:decision_rules][:public_exposure_decision]) == "keep_internal"
    @test Bool(protocol[:decision_rules][:sparse_design_grid_recorded])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:high_variance_waic_blocks_public_exposure])
    @test Bool(protocol[:decision_rules][:psis_loo_or_influence_review_required_before_exposure])
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:min_observations]) == 18
    @test Int(thresholds[:max_observations]) == 35
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_finite_calibration])
    @test Bool(thresholds[:require_finite_intervals])
    @test Bool(thresholds[:require_decision_stability])

    scenarios = fixture[:scenarios]
    @test length(scenarios) == Int(thresholds[:n_scenarios])
    @test Set(String(scenario[:scenario]) for scenario in scenarios) == Set([
        "balanced_parity_sparse",
        "reference_bridge_sparse",
        "cyclic_missing_item_sparse",
    ])
    for scenario in scenarios
        density = scenario[:design_density]
        simulated = scenario[:simulated_data]
        n_observations = Int(density[:n_observations])
        @test Int(density[:full_crossed_observations]) == Int(protocol[:full_crossed_observations])
        @test Int(thresholds[:min_observations]) <= n_observations <=
            Int(thresholds[:max_observations])
        @test n_observations < Int(protocol[:full_crossed_observations])
        @test Float64(density[:observed_fraction]) < 1.0
        @test Int(density[:missing_observations]) > 0
        @test Int(simulated[:n_observations]) == n_observations
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) == n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])
        @test length(simulated[:person_levels]) == 4
        @test length(simulated[:rater_levels]) == 3
        @test length(simulated[:item_levels]) == 3
        @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])

        validation = scenario[:validation]
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_warnings]) >= 1
        @test Int(validation[:n_components]) == 1
        @test Int(validation[:location_design_rank]) == 8
        @test Int(validation[:n_location_parameters]) == 8
        @test Bool(validation[:location_design_full_rank])
        issue_codes = Set(String(code) for code in validation[:issue_codes])
        @test issubset(issue_codes,
            Set(["unobserved_item_category", "sparse_dff_cell"]))
        @test !isempty(issue_codes)
        @test all(row -> String(row[:severity]) == "warning",
            validation[:issue_rows])
        @test !isempty(validation[:dff_cell_counts])

        model_rows = scenario[:model_rows]
        @test length(model_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in model_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> Int(row[:n_observations]) == n_observations, model_rows)
        @test all(row -> Int(row[:n_draws]) == 128, model_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
        @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
            model_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), model_rows)
        @test all(row -> isfinite(Float64(row[:predictive_metrics][:expected_score_rmse])) &&
            isfinite(Float64(row[:predictive_metrics][:mean_absolute_calibration_error])),
            model_rows)
        @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
            model_rows)
        @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
        gmfrm_row = only(row for row in model_rows
            if String(row[:model]) == "gmfrm_internal_candidate")
        @test String(gmfrm_row[:family]) == "gmfrm"
        @test Bool(gmfrm_row[:public_fit]) == false
        @test Int(gmfrm_row[:n_parameters]) == 17
        @test String(gmfrm_row[:direct_parameter_order_sha256]) ==
            String(scenario[:gmfrm_parameter_order_sha256])

        interval_rows = scenario[:interval_coverage]
        @test length(interval_rows) == 2
        @test Set(Float64(row[:interval_probability]) for row in interval_rows) ==
            Set([0.8, 0.95])
        for interval_row in interval_rows
            @test length(interval_row[:recovery_by_block]) == 6
            @test Int(interval_row[:summary][:n_parameters]) == 19
            @test Int(interval_row[:summary][:n_blocks]) == 6
            @test Bool(interval_row[:summary][:all_intervals_finite])
            @test Float64(interval_row[:summary][:overall_coverage_rate]) >= 0.8
            @test Float64(interval_row[:summary][:min_block_coverage_rate]) >= 0.0
        end

        decision = scenario[:decision]
        @test String(decision[:selected_decision]) == "keep_internal"
        @test Bool(decision[:public_fit_allowed]) == false
        @test Bool(decision[:experimental_keyword_enabled]) == false
        @test Bool(decision[:all_samplers_passed])
        @test Set(String(row[:blocker]) for row in decision[:blocker_rows]) ==
            Set(["high_variance_waic_requires_followup"])

        summary = scenario[:summary]
        @test Bool(summary[:passed])
        @test String(summary[:selected_decision]) == "keep_internal"
        @test Bool(summary[:validation_passed])
        @test Int(summary[:location_design_rank]) == 8
        @test Int(summary[:n_location_parameters]) == 8
        @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_sparse_validation_records]) == length(scenarios)
    @test Int(summary[:n_interval_records]) == 2 * length(scenarios)
    @test Int(summary[:n_models]) == 3 * length(scenarios)
    @test Int(summary[:n_observations_minimum]) >= Int(thresholds[:min_observations])
    @test Int(summary[:n_observations_maximum]) < Int(protocol[:full_crossed_observations])
    @test Bool(summary[:all_sparse_validations_passed])
    @test Bool(summary[:all_location_designs_full_rank])
    @test Bool(summary[:all_local_intervals_finite])
    @test Float64(summary[:min_interval_coverage_rate]) >= 0.8
    @test Float64(summary[:min_block_coverage_rate]) >= 0.0
    @test Int(summary[:keep_internal_decision_count]) == length(scenarios)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Bool(summary[:any_high_variance_waic])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_variance_waic_requires_followup"])
    @test String(summary[:recommendation]) == "keep_internal_until_waic_followup"
    @test String(summary[:next_gate]) == "scalar_gmfrm_waic_influence_review"
end

function check_gmfrm_waic_influence_review_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_waic_influence_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_waic_influence_review"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_waic_influence_review_v1"
    @test Set(String(source) for source in protocol[:simulation_sources]) == Set([
        "scalar_gmfrm_interval_decision_grid_v1",
        "scalar_gmfrm_sparse_design_grid_v1",
    ])
    @test String(protocol[:review_kind]) == "local_pointwise_waic_influence_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Float64(protocol[:pointwise_threshold]) == 0.4
    @test String(protocol[:influence_action]) ==
        "remove_union_of_flagged_observations_within_scenario"
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:public_exposure_decision]) == "keep_internal"
    @test Bool(protocol[:decision_rules][:high_variance_waic_review_recorded])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:require_masked_comparison_finite])
    @test Bool(protocol[:decision_rules][:psis_loo_or_exact_loo_required_before_public_exposure])
    @test Int(thresholds[:n_full_crossed_scenarios]) == 3
    @test Int(thresholds[:n_sparse_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:min_retained_observations_after_mask]) == 4
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])

    reviews = fixture[:scenario_reviews]
    @test length(reviews) ==
        Int(thresholds[:n_full_crossed_scenarios]) +
        Int(thresholds[:n_sparse_scenarios])
    @test count(review -> String(review[:scenario_group]) == "full_crossed",
        reviews) == 3
    @test count(review -> String(review[:scenario_group]) == "sparse_connected",
        reviews) == 3
    for review in reviews
        simulated = review[:simulated_data]
        n_observations = Int(simulated[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) == n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])

        full_rows = review[:full_comparison_rows]
        masked_rows = review[:masked_comparison_rows]
        @test length(full_rows) == Int(thresholds[:n_models_per_scenario])
        @test length(masked_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in full_rows] == [1, 2, 3]
        @test [Int(row[:rank]) for row in masked_rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in full_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]), full_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), full_rows)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), masked_rows)
        @test sum(Float64(row[:relative_weight]) for row in full_rows) ≈ 1.0
        @test sum(Float64(row[:relative_weight]) for row in masked_rows) ≈ 1.0

        flagged_rows = review[:flagged_observation_rows]
        flagged_union = review[:flagged_observation_union]
        @test !isempty(flagged_rows)
        @test !isempty(flagged_union)
        @test all(row -> Float64(row[:p_waic]) > Float64(protocol[:pointwise_threshold]),
            flagged_rows)
        @test all(row -> String(row[:flag]) == "high_loglik_variance",
            flagged_rows)

        influence = review[:influence_summary]
        @test Bool(influence[:passed])
        @test Int(influence[:n_observations]) == n_observations
        @test Int(influence[:n_flagged_model_observations]) == length(flagged_rows)
        @test Int(influence[:n_flagged_unique_observations]) == length(flagged_union)
        @test Int(influence[:n_retained_observations]) >=
            Int(thresholds[:min_retained_observations_after_mask])
        @test Float64(influence[:max_p_waic]) >=
            Float64(protocol[:pointwise_threshold])
        @test Bool(influence[:all_samplers_passed])
        @test Bool(influence[:all_masked_comparisons_finite])
        @test String(influence[:selected_decision]) == "keep_internal"
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_public_experimental_fit"
    @test String(decision[:interpretation]) ==
        "pointwise_waic_influence_review_recorded_but_high_variance_persists"
    @test String(decision[:required_followup]) == "psis_loo_or_exact_loo_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenario_reviews]) == length(reviews)
    @test Int(summary[:n_full_crossed_scenarios]) == 3
    @test Int(summary[:n_sparse_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == length(reviews)
    @test Int(summary[:n_models]) == 3 * length(reviews)
    @test Int(summary[:n_flagged_model_observations]) > 0
    @test Float64(summary[:max_p_waic]) > Float64(protocol[:pointwise_threshold])
    @test Int(summary[:min_retained_observations]) >=
        Int(thresholds[:min_retained_observations_after_mask])
    @test Int(summary[:n_best_model_changes_after_flagged_removal]) >= 1
    @test Int(summary[:n_gmfrm_rank_changes_after_flagged_removal]) >= 1
    @test Bool(summary[:all_samplers_passed])
    @test Bool(summary[:all_masked_comparisons_finite])
    @test Bool(summary[:any_high_variance_waic])
    @test Int(summary[:keep_internal_decision_count]) == length(reviews)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_variance_waic_requires_psis_loo_followup"])
    @test String(summary[:recommendation]) == "keep_internal_until_psis_loo_followup"
    @test String(summary[:next_gate]) == "scalar_gmfrm_psis_loo_review"
end

function check_gmfrm_psis_loo_review_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_psis_loo_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_psis_loo_review"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_psis_loo_review_v1"
    @test Set(String(source) for source in protocol[:simulation_sources]) == Set([
        "scalar_gmfrm_interval_decision_grid_v1",
        "scalar_gmfrm_sparse_design_grid_v1",
        "scalar_gmfrm_waic_influence_review_v1",
    ])
    @test String(protocol[:review_kind]) ==
        "local_raw_importance_loo_pareto_k_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:psis_smoothing_enabled]) == false
    @test String(protocol[:loo_method]) == "raw_importance_sampling"
    @test String(protocol[:pareto_k_estimator]) == "hill_log_tail"
    @test Float64(protocol[:pareto_k_threshold]) == 0.7
    @test Float64(protocol[:tail_fraction]) == 0.2
    @test Int(protocol[:min_tail_draws]) == 5
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test String(protocol[:decision_rules][:public_exposure_decision]) ==
        "keep_internal"
    @test Bool(protocol[:decision_rules][:raw_importance_loo_review_recorded])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:require_finite_loo_comparison])
    @test Bool(protocol[:decision_rules][:high_pareto_k_blocks_public_exposure])
    @test Bool(protocol[:decision_rules][:exact_loo_or_kfold_required_before_public_exposure])
    @test Int(thresholds[:n_full_crossed_scenarios]) == 3
    @test Int(thresholds[:n_sparse_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])

    reviews = fixture[:scenario_reviews]
    @test length(reviews) ==
        Int(thresholds[:n_full_crossed_scenarios]) +
        Int(thresholds[:n_sparse_scenarios])
    @test count(review -> String(review[:scenario_group]) == "full_crossed",
        reviews) == 3
    @test count(review -> String(review[:scenario_group]) == "sparse_connected",
        reviews) == 3
    for review in reviews
        simulated = review[:simulated_data]
        n_observations = Int(simulated[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) == n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])

        waic_rows = review[:waic_comparison_rows]
        loo_rows = review[:loo_comparison_rows]
        @test length(waic_rows) == Int(thresholds[:n_models_per_scenario])
        @test length(loo_rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in waic_rows] == [1, 2, 3]
        @test [Int(row[:rank]) for row in loo_rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in loo_rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> String(row[:criterion]) == "loo", loo_rows)
        @test all(row -> String(row[:method]) == "raw_importance_sampling",
            loo_rows)
        @test all(row -> Bool(row[:psis_smoothing]) == false, loo_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]),
            loo_rows)
        @test all(row -> isfinite(Float64(row[:elpd_loo])) &&
            isfinite(Float64(row[:looic])), loo_rows)
        @test all(row -> Float64(row[:max_pareto_k]) >= 0, loo_rows)
        @test all(row -> Float64(row[:min_effective_sample_size]) >= 1,
            loo_rows)
        @test sum(Float64(row[:relative_weight]) for row in loo_rows) ≈ 1.0

        high_pareto_rows = review[:high_pareto_observation_rows]
        high_pareto_union = review[:high_pareto_observation_union]
        @test !isempty(high_pareto_rows)
        @test !isempty(high_pareto_union)
        @test all(row -> Float64(row[:pareto_k]) >
            Float64(protocol[:pareto_k_threshold]), high_pareto_rows)
        @test all(row -> String(row[:flag]) == "high_pareto_k",
            high_pareto_rows)

        summary = review[:loo_summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_observations]) == n_observations
        @test Int(summary[:n_high_pareto_model_observations]) ==
            length(high_pareto_rows)
        @test Int(summary[:n_high_pareto_unique_observations]) ==
            length(high_pareto_union)
        @test Float64(summary[:max_pareto_k]) >
            Float64(protocol[:pareto_k_threshold])
        @test Bool(summary[:all_samplers_passed])
        @test Bool(summary[:all_loo_comparisons_finite])
        @test Bool(summary[:any_high_pareto_k])
        @test String(summary[:selected_decision]) == "keep_internal"
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_public_experimental_fit"
    @test String(decision[:interpretation]) ==
        "raw_importance_loo_review_recorded_but_not_public_sufficient"
    @test String(decision[:required_followup]) == "exact_loo_or_kfold_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenario_reviews]) == length(reviews)
    @test Int(summary[:n_full_crossed_scenarios]) == 3
    @test Int(summary[:n_sparse_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == length(reviews)
    @test Int(summary[:n_models]) == 3 * length(reviews)
    @test Int(summary[:n_high_pareto_model_observations]) > 0
    @test Float64(summary[:max_pareto_k]) > Float64(protocol[:pareto_k_threshold])
    @test Int(summary[:n_best_model_changes_from_waic_to_loo]) >= 1
    @test Int(summary[:n_gmfrm_rank_changes_from_waic_to_loo]) >= 1
    @test Bool(summary[:all_samplers_passed])
    @test Bool(summary[:all_loo_comparisons_finite])
    @test Bool(summary[:any_high_pareto_k])
    @test Bool(summary[:psis_smoothing_enabled]) == false
    @test Int(summary[:keep_internal_decision_count]) == length(reviews)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["high_pareto_k_requires_exact_loo_or_kfold_followup"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_exact_loo_or_kfold_followup"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_exact_loo_or_kfold_review"
end

function check_gmfrm_exact_loo_or_kfold_review_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_exact_loo_or_kfold_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_exact_loo_or_kfold_review"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_exact_loo_or_kfold_review_v1"
    @test Set(String(source) for source in protocol[:simulation_sources]) == Set([
        "scalar_gmfrm_interval_decision_grid_v1",
        "scalar_gmfrm_sparse_design_grid_v1",
        "scalar_gmfrm_psis_loo_review_v1",
    ])
    @test String(protocol[:review_kind]) == "local_refit_kfold_elpd_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:exact_loo_enabled]) == false
    @test Bool(protocol[:kfold_enabled])
    @test Int(protocol[:k_folds]) == 3
    @test Int(protocol[:fold_seed]) == 1
    @test String(protocol[:prediction_target]) ==
        "heldout_observation_log_score"
    @test Set(String(model) for model in protocol[:models]) == Set([
        "gmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test Bool(protocol[:decision_rules][:exact_loo_or_kfold_review_recorded])
    @test Bool(protocol[:decision_rules][:require_all_training_designs_parameter_order_matched])
    @test Bool(protocol[:decision_rules][:require_all_samplers_passed])
    @test Bool(protocol[:decision_rules][:require_finite_kfold_comparison])
    @test Bool(protocol[:decision_rules][:require_all_observations_held_out_once])
    @test Bool(protocol[:decision_rules][:guarded_fit_api_dry_run_required_before_public_exposure])
    @test Int(thresholds[:n_full_crossed_scenarios]) == 3
    @test Int(thresholds[:n_sparse_scenarios]) == 3
    @test Int(thresholds[:n_models_per_scenario]) == 3
    @test Int(thresholds[:n_folds]) == 3
    @test Bool(thresholds[:require_same_observations_within_scenario])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_parameter_order_match])

    reviews = fixture[:scenario_reviews]
    @test length(reviews) ==
        Int(thresholds[:n_full_crossed_scenarios]) +
        Int(thresholds[:n_sparse_scenarios])
    @test count(review -> String(review[:scenario_group]) == "full_crossed",
        reviews) == 3
    @test count(review -> String(review[:scenario_group]) == "sparse_connected",
        reviews) == 3
    for review in reviews
        simulated = review[:simulated_data]
        n_observations = Int(simulated[:n_observations])
        @test sum(Int(row[:n]) for row in simulated[:score_counts]) ==
            n_observations
        @test Set(Int(row[:score]) for row in simulated[:score_counts]) ==
            Set([0, 1, 2])

        folds = review[:folds]
        @test length(folds) == Int(protocol[:k_folds])
        heldout = Int[]
        for fold in folds
            append!(heldout, Int.(fold[:heldout_observations]))
            @test Int(fold[:n_heldout_observations]) ==
                length(fold[:heldout_observations])
            @test length(fold[:heldout_rows]) ==
                Int(fold[:n_heldout_observations])
        end
        @test sort(heldout) == collect(1:n_observations)

        fold_rows = review[:fold_model_rows]
        @test length(fold_rows) ==
            Int(protocol[:k_folds]) * Int(thresholds[:n_models_per_scenario])
        @test all(row -> String(row[:criterion]) == "kfold", fold_rows)
        @test all(row -> Bool(row[:parameter_order_matched]), fold_rows)
        @test all(row -> Bool(row[:sampler_summary][:internal_passed]),
            fold_rows)
        @test all(row -> isfinite(Float64(row[:elpd_heldout])) &&
            isfinite(Float64(row[:kfoldic_heldout])), fold_rows)
        @test all(row -> Int(row[:n_train_observations]) +
            Int(row[:n_heldout_observations]) == n_observations, fold_rows)

        rows = review[:kfold_comparison_rows]
        @test length(rows) == Int(thresholds[:n_models_per_scenario])
        @test [Int(row[:rank]) for row in rows] == [1, 2, 3]
        @test Set(String(row[:model]) for row in rows) == Set([
            "gmfrm_internal_candidate",
            "mfrm_partial_credit",
            "mfrm_rating_scale",
        ])
        @test all(row -> String(row[:criterion]) == "kfold", rows)
        @test all(row -> String(row[:prediction_target]) ==
            "heldout_observation_log_score", rows)
        @test all(row -> Bool(row[:all_parameter_orders_matched]), rows)
        @test all(row -> Bool(row[:all_samplers_passed]), rows)
        @test all(row -> isfinite(Float64(row[:elpd_kfold])) &&
            isfinite(Float64(row[:kfoldic])), rows)
        @test sum(Float64(row[:relative_weight]) for row in rows) ≈ 1.0

        summary = review[:kfold_summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_observations]) == n_observations
        @test Int(summary[:n_folds]) == Int(protocol[:k_folds])
        @test Bool(summary[:all_observations_held_out_once])
        @test Bool(summary[:all_parameter_orders_matched])
        @test Bool(summary[:all_samplers_passed])
        @test Bool(summary[:all_kfold_comparisons_finite])
        @test String(summary[:selected_decision]) == "keep_internal"
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_public_experimental_fit"
    @test String(decision[:interpretation]) ==
        "kfold_refit_review_recorded_and_exact_loo_gate_satisfied"
    @test String(decision[:required_followup]) == "guarded_fit_api_dry_run"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_scenario_reviews]) == length(reviews)
    @test Int(summary[:n_full_crossed_scenarios]) == 3
    @test Int(summary[:n_sparse_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == length(reviews)
    @test Int(summary[:n_models]) == 3 * length(reviews)
    @test Int(summary[:n_fold_model_records]) ==
        3 * Int(protocol[:k_folds]) * length(reviews)
    @test Int(summary[:n_folds]) == Int(protocol[:k_folds])
    @test Bool(summary[:all_observations_held_out_once])
    @test Bool(summary[:all_parameter_orders_matched])
    @test Bool(summary[:all_samplers_passed])
    @test Bool(summary[:all_kfold_comparisons_finite])
    @test Int(summary[:min_train_observations]) >= 12
    @test Int(summary[:n_gmfrm_best_model_scenarios]) >= 1
    @test Float64(summary[:max_gmfrm_kfoldic_difference]) >= 0
    @test 0 <= Float64(summary[:min_gmfrm_relative_weight]) <= 1
    @test Int(summary[:keep_internal_decision_count]) == length(reviews)
    @test String(summary[:decision_stability]) == "stable_keep_internal"
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["guarded_fit_api_dry_run_missing"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_guarded_fit_api_dry_run"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_guarded_fit_api_dry_run"
end

function check_gmfrm_guarded_fit_api_dry_run_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_guarded_fit_api_dry_run.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "internal_guarded_fit_api_dry_run"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(fixture[:entrypoint_enabled]) == false

    protocol = fixture[:protocol]
    rules = protocol[:decision_rules]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_guarded_fit_api_dry_run_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_fit_api_contract_dry_run"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:dry_run_only])
    @test String(protocol[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(protocol[:entrypoint_enabled]) == false
    @test Bool(protocol[:superseded_by_guarded_fit_method_wiring])
    @test Bool(protocol[:superseded_by_prior_likelihood_sensitivity_grid])
    @test Bool(protocol[:superseded_by_real_data_case_study])
    @test Bool(protocol[:superseded_by_claim_recovery_reproduction_archive])
    @test Bool(protocol[:superseded_by_broader_experimental_exposure_decision_review])
    @test String(protocol[:target_constructor]) ==
        "_gmfrm_promotion_candidate_logdensity"
    @test String(protocol[:diagnostics_constructor]) ==
        "_gmfrm_promotion_candidate_diagnostics"
    @test Bool(rules[:require_specified_only_public_fit_rejection])
    @test Bool(rules[:require_preview_design_experimental_keyword_rejection])
    @test Bool(rules[:require_artifact_contract_recorded])
    @test Bool(rules[:require_required_fields_recorded])
    @test Bool(rules[:require_required_provenance_recorded])
    @test Bool(rules[:require_file_evidence_present])
    @test Bool(rules[:require_finite_internal_target])
    @test Bool(rules[:require_gradient_diagnostics_passed])
    @test Bool(rules[:guarded_fit_method_wiring_required_before_public_exposure])

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 2
    public_rejection = only(row for row in rejection_checks
        if String(row[:check]) == "fit_specified_only_gmfrm")
    @test Bool(public_rejection[:rejected])
    @test String(public_rejection[:error_type]) == "ArgumentError"
    @test occursin("specified_only", String(public_rejection[:message]))
    experimental_rejection = only(row for row in rejection_checks
        if String(row[:check]) == "fit_preview_design_with_experimental_keyword")
    @test Bool(experimental_rejection[:rejected])
    @test String(experimental_rejection[:error_type]) == "MethodError"
    @test occursin("unsupported keyword argument \"experimental\"",
        String(experimental_rejection[:message]))

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test String(contract[:status]) == "contract_recorded"
    @test Bool(contract[:public_fit])
    @test Bool(contract[:experimental_public])
    @test String(contract[:artifact_kind]) ==
        "experimental_generalized_fit_artifact"
    @test Int(contract[:n_required_fields]) == 14
    @test Int(contract[:n_required_provenance_artifacts]) == 4
    @test Bool(contract[:all_required_fields_recorded])
    @test Bool(contract[:all_required_provenance_recorded])
    @test Set(String(field) for field in contract[:required_field_names]) == Set([
        "schema",
        "experimental_public",
        "public_fit",
        "family",
        "scope",
        "density_space",
        "raw_parameter_names",
        "direct_parameter_names",
        "raw_to_direct_transform",
        "sampler_controls",
        "diagnostics",
        "pointwise_loglikelihood",
        "caveat_docs_artifact",
        "fixture_provenance",
    ])

    evidence_rows = fixture[:evidence_reference_rows]
    @test length(evidence_rows) >= 20
    @test all(row -> Bool(row[:exists]), evidence_rows)
    self_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "guarded_fit_api_dry_run")
    @test String(self_reference[:reference_kind]) == "current_artifact_self"
    @test String(self_reference[:artifact]) ==
        "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"
    broader_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "broader_experimental_exposure_decision_review")
    @test String(broader_reference[:reference_kind]) ==
        "broader_review_cycle_break"
    @test isnothing(broader_reference[:sha256])
    manuscript_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "manuscript_scale_simulation_grid")
    @test String(manuscript_reference[:reference_kind]) ==
        "manuscript_grid_cycle_break"
    @test isnothing(manuscript_reference[:sha256])
    full_archive_reference = only(row for row in evidence_rows
        if String(row[:evidence]) == "full_paper_reproduction_archive")
    @test String(full_archive_reference[:reference_kind]) ==
        "full_archive_cycle_break"
    @test isnothing(full_archive_reference[:sha256])
    for row in evidence_rows
        String(row[:reference_kind]) == "local_file" || continue
        path = first(split(String(row[:artifact]), '#'; limit = 2))
        @test String(row[:sha256]) == file_sha256(joinpath(root, path))
    end

    target = fixture[:target_dry_run]
    @test String(target[:target]) == "_gmfrm_promotion_candidate_logdensity"
    @test String(target[:diagnostics]) == "_gmfrm_promotion_candidate_diagnostics"
    @test Int(target[:n_raw_parameters]) == length(target[:raw_parameter_names])
    @test Int(target[:n_checked_gradient_coordinates]) == 6
    @test Bool(target[:finite_logdensity])
    @test isfinite(Float64(target[:logdensity]))
    @test String(target[:diagnostics_flag]) == "ok"
    @test Bool(target[:diagnostics_passed])
    @test Int(target[:n_failed_gradient_checks]) == 0
    @test Float64(target[:max_abs_error]) <= Float64(target[:max_tolerance])

    manifest = fixture[:manifest_snapshot]
    @test String(manifest[:candidate_status]) == "internal_promotion_candidate"
    @test String(manifest[:compiler_stage]) == "fit_ready_candidate"
    @test Bool(manifest[:experimental_public_ready])
    @test String(manifest[:experimental_decision_status]) == "experimental_public"
    @test String(manifest[:experimental_decision]) == "enable_guarded_experimental"
    @test Bool(manifest[:experimental_summary][:fit_allowed])
    @test Bool(manifest[:experimental_summary][:experimental_keyword_enabled])
    @test Int(manifest[:experimental_summary][:n_evidence_done]) >= 25
    @test String(manifest[:experimental_summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test Bool(decision[:current_manifest_fit_allowed])
    @test Bool(decision[:current_manifest_experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "guarded_scalar_gmfrm_only"
    @test String(decision[:interpretation]) ==
        "guarded_entrypoint_contract_dry_run_superseded_by_broader_exposure_decision_review"
    @test String(decision[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:dry_run_only])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled]) == false
    @test Bool(summary[:superseded_by_guarded_fit_method_wiring])
    @test Bool(summary[:superseded_by_experimental_fit_validation_grid])
    @test Bool(summary[:superseded_by_posterior_predictive_grid])
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Bool(summary[:superseded_by_prior_likelihood_sensitivity_grid])
    @test Bool(summary[:superseded_by_real_data_case_study])
    @test Bool(summary[:superseded_by_claim_recovery_reproduction_archive])
    @test Bool(summary[:superseded_by_broader_experimental_exposure_decision_review])
    @test Bool(summary[:superseded_by_full_paper_reproduction_archive])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Bool(summary[:current_manifest_fit_allowed])
    @test Bool(summary[:current_manifest_experimental_keyword_enabled])
    @test Bool(summary[:fit_rejects_specified_only_gmfrm])
    @test Bool(summary[:fit_preview_rejects_experimental_keyword])
    @test Bool(summary[:artifact_contract_recorded])
    @test Bool(summary[:all_required_artifact_fields_recorded])
    @test Bool(summary[:all_required_provenance_artifacts_recorded])
    @test Bool(summary[:all_file_evidence_present])
    @test Bool(summary[:target_logdensity_finite])
    @test Bool(summary[:target_diagnostics_passed])
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "full_archive_recorded_keep_guarded_scalar_gmfrm_only"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end

function check_gmfrm_guarded_fit_method_wiring_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_guarded_fit_method_wiring.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "guarded_experimental_fit_method_wired"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test String(fixture[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(fixture[:entrypoint_enabled])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    rules = protocol[:decision_rules]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_guarded_fit_method_wiring_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_fit_method_wiring"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:proposed_entrypoint]) == "fit(spec; experimental = true)"
    @test Bool(protocol[:entrypoint_enabled])
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 4
    @test Int(sampler[:draws]) == 4
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test Float64(sampler[:rhat_threshold]) == 100.0
    @test Float64(sampler[:ess_threshold]) == 1.0
    @test Bool(rules[:require_guarded_experimental_fit_success])
    @test Bool(rules[:require_artifact_contract_satisfied])
    @test Bool(rules[:require_unsupported_public_options_rejected])
    @test Bool(rules[:sparse_pathology_recovery_grid_required_before_broader_exposure])

    manifest = fixture[:manifest_snapshot]
    @test String(manifest[:candidate_status]) == "internal_promotion_candidate"
    @test String(manifest[:compiler_stage]) == "fit_ready_candidate"
    @test Bool(manifest[:experimental_public_ready])
    @test String(manifest[:experimental_decision_status]) == "experimental_public"
    @test String(manifest[:experimental_decision]) == "enable_guarded_experimental"
    @test Bool(manifest[:experimental_summary][:fit_allowed])
    @test Bool(manifest[:experimental_summary][:experimental_keyword_enabled])
    @test Int(manifest[:experimental_summary][:n_evidence_done]) >= 23
    @test String(manifest[:experimental_summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    fit_record = fixture[:fit_record]
    @test String(fit_record[:type]) == "GMFRMFit"
    @test String(fit_record[:backend]) == "advancedhmc"
    @test String(fit_record[:sampler]) == "nuts"
    @test Vector{Int}(fit_record[:raw_draws_shape]) == [8, 17]
    @test Vector{Int}(fit_record[:direct_draws_shape]) == [8, 19]
    @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [8, 36]
    @test Int(fit_record[:n_chain_acceptance_rates]) == 2
    @test Int(fit_record[:n_sampler_stats]) == 8

    metadata = fixture[:metadata_review]
    @test String(metadata[:family]) == "gmfrm"
    @test Int(metadata[:dimensions]) == 1
    @test String(metadata[:discrimination]) == "rater"
    @test Bool(metadata[:public_fit])
    @test Bool(metadata[:experimental_public])
    @test String(metadata[:density_space]) == "raw_unconstrained"
    @test Int(metadata[:n_draws]) == 8
    @test Int(metadata[:n_chains]) == 2
    @test Int(metadata[:draws_per_chain]) == 4

    diagnostics_review = fixture[:diagnostics_review]
    @test String(diagnostics_review[:schema]) ==
        "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
    @test Bool(diagnostics_review[:public_fit])
    @test Bool(diagnostics_review[:experimental_public])
    diagnostic_summary = diagnostics_review[:summary]
    @test String(diagnostic_summary[:flag]) == "ok"
    @test Bool(diagnostic_summary[:passed])
    @test Int(diagnostic_summary[:n_sampler_warnings]) == 0
    @test Int(diagnostic_summary[:n_divergences]) == 0
    @test Int(diagnostic_summary[:n_max_treedepth]) == 0
    @test Int(diagnostic_summary[:n_failed_direct_constraints]) == 0

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test Bool(contract[:public_fit])
    @test Bool(contract[:experimental_public])
    @test String(contract[:artifact_kind]) ==
        "experimental_generalized_fit_artifact"
    @test Int(contract[:n_required_fields]) == 14
    @test Int(contract[:n_required_provenance_artifacts]) == 4
    @test Bool(contract[:all_required_fields_present])
    @test Bool(contract[:all_required_provenance_recorded])
    @test Bool(contract[:enables_public_fit])

    artifact = fixture[:artifact_review]
    @test String(artifact[:schema]) ==
        "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
    @test String(artifact[:status]) == "experimental_public_fit_artifact"
    @test Bool(artifact[:public_fit])
    @test Bool(artifact[:experimental_public])
    @test Bool(artifact[:fit_ready])
    @test String(artifact[:density_space]) == "raw_unconstrained"
    @test Vector{Int}(artifact[:pointwise_loglikelihood_shape]) == [8, 36]
    @test String(artifact[:caveat_docs_artifact]) ==
        "docs/src/fitting.md#guarded-generalized-model-caveats"
    @test Int(artifact[:n_fixture_provenance_rows]) == 4

    @test Bool(fixture[:waic_review][:all_top_level_numeric_finite])
    @test Bool(fixture[:loo_review][:all_top_level_numeric_finite])
    @test Int(fixture[:information_criterion_rows][:n_waic_rows]) == 36
    @test Int(fixture[:information_criterion_rows][:n_loo_rows]) == 36

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 6
    @test all(check -> Bool(check[:rejected]), rejection_checks)
    @test Set(String(check[:check]) for check in rejection_checks) == Set([
        "fit_specified_only_gmfrm_without_experimental",
        "fit_preview_design_with_experimental_keyword",
        "fit_experimental_unsupported_backend",
        "fit_experimental_public_mfrm_prior",
        "fit_experimental_mgmfrm",
        "fit_experimental_non_rater_discrimination",
    ])

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_by_sparse_pathology_recovery_grid"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_experimental_fit_method_wired_validated_ppc_and_sparse_pathology_checked_locally"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled])
    @test Bool(summary[:public_fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test Bool(summary[:gmfrm_fit_returned])
    @test Bool(summary[:artifact_contract_satisfied])
    @test Bool(summary[:pointwise_loglikelihood_shape_valid])
    @test Bool(summary[:waic_and_loo_finite])
    @test Bool(summary[:all_unsupported_public_options_rejected])
    @test Bool(summary[:superseded_by_experimental_fit_validation_grid])
    @test Bool(summary[:superseded_by_posterior_predictive_grid])
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_experimental_fit_validation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_experimental_fit_validation_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_fit_validation_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    diagnostics = protocol[:diagnostics]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_experimental_fit_validation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_fit_validation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:superseded_by_sparse_pathology_recovery_grid])
    @test String(protocol[:entrypoint_under_validation]) ==
        "fit(spec; experimental = true)"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_baseline_calibration_grid_scenarios"
    @test Int(protocol[:data_grid][:observations]) == 36
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test String(sampler[:ad_backend]) == "ForwardDiff"
    @test Bool(sampler[:split_chains])
    @test Float64(diagnostics[:rhat_threshold]) == 100.0
    @test Float64(diagnostics[:ess_threshold]) == 1.0
    @test Int(diagnostics[:loo_min_tail_draws]) == 5
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_public_fit_metadata])
    @test Bool(thresholds[:require_artifact_contract_satisfied])
    @test Bool(thresholds[:require_pointwise_shape])
    @test Bool(thresholds[:require_information_criteria_finite])
    @test Bool(thresholds[:require_no_divergences])
    @test Bool(thresholds[:require_no_max_treedepth])
    @test Bool(thresholds[:require_no_failed_direct_constraints])
    @test Float64(thresholds[:max_direct_parameter_mean_absolute_error]) == 5.0
    @test Float64(thresholds[:max_direct_block_mean_absolute_error]) == 3.0

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    for scenario in scenarios
        @test Int(scenario[:simulated_data][:n_observations]) == 36
        @test length(scenario[:simulated_data][:score_counts]) >= 1
        @test length(scenario[:simulated_data][:person_levels]) == 4
        @test length(scenario[:simulated_data][:rater_levels]) == 3
        @test length(scenario[:simulated_data][:item_levels]) == 3
        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test String(fit_record[:backend]) == "advancedhmc"
        @test String(fit_record[:sampler]) == "nuts"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [24, 36]

        metadata = scenario[:metadata_review]
        @test Bool(metadata[:public_fit])
        @test Bool(metadata[:experimental_public])
        @test String(metadata[:family]) == "gmfrm"
        @test Int(metadata[:dimensions]) == 1
        @test String(metadata[:discrimination]) == "rater"
        @test Int(metadata[:n_draws]) == 24
        @test Int(metadata[:n_chains]) == 2
        @test Int(metadata[:draws_per_chain]) == 12
        @test Int(metadata[:n_parameters]) == 17
        @test Int(metadata[:n_direct_parameters]) == 19

        diagnostic_summary = scenario[:diagnostics_review][:summary]
        @test String(scenario[:diagnostics_review][:schema]) ==
            "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
        @test Bool(scenario[:diagnostics_review][:public_fit])
        @test Bool(scenario[:diagnostics_review][:experimental_public])
        @test String(diagnostic_summary[:flag]) == "ok"
        @test Bool(diagnostic_summary[:passed])
        @test Int(diagnostic_summary[:n_divergences]) == 0
        @test Int(diagnostic_summary[:n_max_treedepth]) == 0
        @test Int(diagnostic_summary[:n_failed_direct_constraints]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_logdensity]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_direct_loglikelihood]) == 0

        artifact = scenario[:artifact_review]
        @test String(artifact[:schema]) ==
            "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
        @test Bool(artifact[:public_fit])
        @test Bool(artifact[:experimental_public])
        @test Bool(artifact[:fit_ready])
        @test String(artifact[:density_space]) == "raw_unconstrained"
        @test Vector{Int}(artifact[:pointwise_loglikelihood_shape]) == [24, 36]
        @test Int(artifact[:n_fixture_provenance_rows]) == 4

        contract = scenario[:artifact_contract_review]
        @test String(contract[:schema]) ==
            "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
        @test Bool(contract[:public_fit])
        @test Bool(contract[:experimental_public])
        @test String(contract[:artifact_kind]) ==
            "experimental_generalized_fit_artifact"
        @test Int(contract[:n_required_fields]) == 14
        @test Int(contract[:n_required_provenance_artifacts]) == 4
        @test Bool(contract[:all_required_fields_present])
        @test Bool(contract[:all_required_provenance_recorded])
        @test Bool(contract[:enables_public_fit])

        @test Bool(scenario[:waic_review][:all_top_level_numeric_finite])
        @test Bool(scenario[:loo_review][:all_top_level_numeric_finite])
        @test Int(scenario[:information_criterion_rows][:n_waic_rows]) == 36
        @test Int(scenario[:information_criterion_rows][:n_loo_rows]) == 36
        @test length(scenario[:direct_recovery_rows]) == 19
        @test all(row -> Bool(row[:finite]), scenario[:direct_recovery_rows])
        @test all(row -> Bool(row[:all_finite]),
            scenario[:direct_recovery_by_block])

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Bool(scenario_summary[:pointwise_shape_valid])
        @test Bool(scenario_summary[:artifact_contract_satisfied])
        @test Bool(scenario_summary[:information_criteria_finite])
        @test Int(scenario_summary[:n_divergences]) == 0
        @test Int(scenario_summary[:n_max_treedepth]) == 0
        @test Int(scenario_summary[:n_failed_direct_constraints]) == 0
        @test Int(scenario_summary[:n_nonfinite_logdensity]) == 0
        @test Int(scenario_summary[:n_nonfinite_direct_loglikelihood]) == 0
        @test Float64(scenario_summary[:max_direct_parameter_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_parameter_mean_absolute_error])
        @test Float64(scenario_summary[:max_direct_block_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_block_mean_absolute_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_by_sparse_pathology_recovery_grid"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:superseded_by_posterior_predictive_grid])
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_total_draws_per_scenario]) == 24
    @test Bool(summary[:all_guarded_fit_returned])
    @test Bool(summary[:all_artifact_contracts_satisfied])
    @test Bool(summary[:all_pointwise_shapes_valid])
    @test Bool(summary[:all_information_criteria_finite])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Float64(summary[:max_direct_parameter_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_parameter_mean_absolute_error])
    @test Float64(summary[:max_direct_block_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_block_mean_absolute_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_posterior_predictive_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_posterior_predictive_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_posterior_predictive_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    diagnostics = protocol[:diagnostics]
    posterior_predictive = protocol[:posterior_predictive]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_posterior_predictive_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_posterior_predictive_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:superseded_by_sparse_pathology_recovery_grid])
    @test String(protocol[:entrypoint_under_validation]) ==
        "posterior_predictive_check(fit(spec; experimental = true))"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_experimental_fit_validation_grid_scenarios"
    @test Int(protocol[:data_grid][:observations]) == 36
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test String(sampler[:ad_backend]) == "ForwardDiff"
    @test Bool(sampler[:split_chains])
    @test Float64(diagnostics[:rhat_threshold]) == 100.0
    @test Float64(diagnostics[:ess_threshold]) == 1.0
    @test Int(diagnostics[:loo_min_tail_draws]) == 5
    @test String(posterior_predictive[:draw_policy]) == "all_fit_draws"
    @test Float64(posterior_predictive[:interval]) == 0.9
    @test Int(posterior_predictive[:calibration_bins]) == 3
    @test String(posterior_predictive[:category_calibration]) ==
        "highest_observed_category"
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_observations]) == 36
    @test Int(thresholds[:n_replicates_per_scenario]) == 24
    @test Int(thresholds[:n_summary_rows]) == 14
    @test Bool(thresholds[:require_ppc_returned])
    @test Bool(thresholds[:require_replicated_scores_in_categories])
    @test Bool(thresholds[:require_probability_sums])
    @test Bool(thresholds[:require_summary_rows_finite])
    @test Bool(thresholds[:require_mean_score_inside_interval])
    @test Bool(thresholds[:require_calibration_rows_finite])

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 1
    reviewed_validation_grid = only(reviewed)
    @test String(reviewed_validation_grid[:artifact]) ==
        "test/fixtures/gmfrm_experimental_fit_validation_grid.json"
    @test Bool(reviewed_validation_grid[:exists])
    @test String(reviewed_validation_grid[:sha256]) ==
        file_sha256(joinpath(root, String(reviewed_validation_grid[:artifact])))

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "near_rasch",
        "moderate_generalized",
        "stronger_generalized",
    ])
    for scenario in scenarios
        @test Int(scenario[:simulated_data][:n_observations]) == 36
        @test length(scenario[:simulated_data][:score_counts]) >= 1
        @test length(scenario[:simulated_data][:person_levels]) == 4
        @test length(scenario[:simulated_data][:rater_levels]) == 3
        @test length(scenario[:simulated_data][:item_levels]) == 3
        @test Vector{Int}(scenario[:simulated_data][:category_levels]) == [0, 1, 2]

        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test String(fit_record[:backend]) == "advancedhmc"
        @test String(fit_record[:sampler]) == "nuts"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [24, 36]

        predictive = scenario[:predictive_probability_review]
        @test Vector{Int}(predictive[:shape]) == [24, 36, 3]
        @test Bool(predictive[:probability_sums_valid])
        @test Float64(predictive[:max_probability_sum_error]) <= 1.0e-12
        @test Vector{Int}(predictive[:expected_scores][:shape]) == [24, 36]
        @test Bool(predictive[:expected_scores][:all_finite])
        @test Float64(predictive[:expected_scores][:minimum]) >= 0.0
        @test Float64(predictive[:expected_scores][:maximum]) <= 2.0
        @test Vector{Int}(predictive[:predictive_variances][:shape]) == [24, 36]
        @test Bool(predictive[:predictive_variances][:all_finite])
        @test Float64(predictive[:predictive_variances][:minimum]) >= -sqrt(eps())
        @test Vector{Int}(predictive[:predictive_residuals][:shape]) == [24, 36]
        @test Bool(predictive[:predictive_residuals][:all_finite])
        @test Bool(predictive[:expected_scores_in_range])

        ppc = scenario[:posterior_predictive_review]
        @test Vector{Int}(ppc[:draw_indices]) == collect(1:24)
        @test Vector{Int}(ppc[:replicated_scores_shape]) == [24, 36]
        @test Bool(ppc[:replicated_scores_in_categories])
        @test Int(ppc[:n_summary_rows]) == 14
        @test length(ppc[:summary_rows]) == 14
        @test length(ppc[:summary_group_rows]) == 5
        @test all(row -> Int(row[:n_replicates]) == 24, ppc[:summary_rows])
        @test all(row -> String(row[:flag]) in ("ok", "outside_interval"),
            ppc[:summary_rows])
        @test Set(String(row[:statistic]) for row in ppc[:summary_group_rows]) ==
            Set(["mean_score", "category_proportion", "person_mean",
                "rater_mean", "item_mean"])

        calibration = scenario[:calibration_review]
        @test Int(calibration[:top_category]) == 2
        @test Int(calibration[:n_rows]) == 6
        @test Bool(calibration[:all_rows_finite])
        @test length(calibration[:expected_score_rows]) == 3
        @test length(calibration[:category_probability_rows]) == 3
        @test all(row -> String(row[:target]) == "expected_score",
            calibration[:expected_score_rows])
        @test all(row -> String(row[:target]) == "category_probability",
            calibration[:category_probability_rows])
        @test all(row -> Int(row[:n_draws]) == 24,
            calibration[:expected_score_rows])
        @test all(row -> Int(row[:n_draws]) == 24,
            calibration[:category_probability_rows])
        @test Float64(calibration[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Bool(scenario_summary[:ppc_returned])
        @test Int(scenario_summary[:n_replicates]) == 24
        @test Int(scenario_summary[:n_summary_rows]) == 14
        @test Bool(scenario_summary[:replicated_scores_in_categories])
        @test Bool(scenario_summary[:probability_sums_valid])
        @test Bool(scenario_summary[:summary_rows_finite])
        @test Bool(scenario_summary[:calibration_rows_finite])
        @test Bool(scenario_summary[:mean_score_inside_interval])
        @test Bool(scenario_summary[:expected_scores_in_range])
        @test Bool(scenario_summary[:predictive_variances_nonnegative])
        @test Float64(scenario_summary[:outside_interval_rate]) <=
            Float64(thresholds[:max_summary_outside_interval_rate])
        @test Float64(scenario_summary[:max_absolute_summary_error]) <=
            Float64(thresholds[:max_absolute_summary_error])
        @test Float64(scenario_summary[:max_absolute_mean_score_error]) <=
            Float64(thresholds[:max_absolute_mean_score_error])
        @test Float64(scenario_summary[:max_absolute_category_proportion_error]) <=
            Float64(thresholds[:max_absolute_category_proportion_error])
        @test Float64(scenario_summary[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_by_sparse_pathology_recovery_grid"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_posterior_predictive_grid_passed"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:superseded_by_sparse_pathology_recovery_grid])
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_replicates_per_scenario]) == 24
    @test Bool(summary[:all_ppc_returned])
    @test Bool(summary[:all_replicated_scores_in_categories])
    @test Bool(summary[:all_probability_sums_valid])
    @test Bool(summary[:all_summary_rows_finite])
    @test Bool(summary[:all_calibration_rows_finite])
    @test Bool(summary[:all_mean_scores_inside_interval])
    @test Float64(summary[:max_outside_interval_rate]) <=
        Float64(thresholds[:max_summary_outside_interval_rate])
    @test Float64(summary[:max_absolute_summary_error]) <=
        Float64(thresholds[:max_absolute_summary_error])
    @test Float64(summary[:max_absolute_mean_score_error]) <=
        Float64(thresholds[:max_absolute_mean_score_error])
    @test Float64(summary[:max_absolute_category_proportion_error]) <=
        Float64(thresholds[:max_absolute_category_proportion_error])
    @test Float64(summary[:max_absolute_calibration_error]) <=
        Float64(thresholds[:max_absolute_calibration_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_sparse_pathology_recovery_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_sparse_pathology_recovery_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_sparse_pathology_recovery_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    sampler = protocol[:sampler]
    diagnostics = protocol[:diagnostics]
    posterior_predictive = protocol[:posterior_predictive]
    thresholds = protocol[:thresholds]
    sparse_pathologies = protocol[:sparse_pathologies]
    validation_protocol = protocol[:validation]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_sparse_pathology_recovery_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_sparse_pathology_recovery_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:entrypoint_under_validation]) ==
        "fit(spec; experimental = true) on sparse connected pathologies"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_sparse_design_grid_scenarios"
    @test Set(String(protocol_id) for protocol_id in protocol[:reviewed_protocols]) ==
        Set([
            "scalar_gmfrm_sparse_design_grid_v1",
            "scalar_gmfrm_posterior_predictive_grid_v1",
        ])
    @test String(sparse_pathologies[:rating_density]) == "sparse_connected"
    @test Int(sparse_pathologies[:persons]) == 4
    @test Int(sparse_pathologies[:raters]) == 3
    @test Int(sparse_pathologies[:items]) == 3
    @test Int(sparse_pathologies[:categories]) == 3
    @test Set(String(pattern) for pattern in sparse_pathologies[:patterns]) == Set([
        "half_crossed_parity",
        "reference_bridge",
        "cyclic_missing_item_cells",
    ])
    @test Bool(validation_protocol[:require_no_validation_errors])
    @test Bool(validation_protocol[:require_connected_design])
    @test Bool(validation_protocol[:require_full_location_rank])
    @test Bool(validation_protocol[:warnings_recorded_not_blocking])
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test String(sampler[:ad_backend]) == "ForwardDiff"
    @test Bool(sampler[:split_chains])
    @test Float64(diagnostics[:rhat_threshold]) == 100.0
    @test Float64(diagnostics[:ess_threshold]) == 1.0
    @test Int(diagnostics[:loo_min_tail_draws]) == 5
    @test String(posterior_predictive[:draw_policy]) == "all_fit_draws"
    @test Float64(posterior_predictive[:interval]) == 0.9
    @test Int(posterior_predictive[:calibration_bins]) == 3
    @test String(posterior_predictive[:category_calibration]) ==
        "highest_observed_category"
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:min_observations]) == 18
    @test Int(thresholds[:max_observations]) == 35
    @test Int(thresholds[:n_replicates_per_scenario]) == 24
    @test Int(thresholds[:n_summary_rows]) == 14
    @test Bool(thresholds[:require_validation_passed])
    @test Bool(thresholds[:require_connected_design])
    @test Bool(thresholds[:require_full_location_rank])
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_pointwise_shape])
    @test Bool(thresholds[:require_information_criteria_finite])
    @test Bool(thresholds[:require_no_divergences])
    @test Bool(thresholds[:require_no_max_treedepth])
    @test Bool(thresholds[:require_no_failed_direct_constraints])
    @test Bool(thresholds[:require_no_nonfinite_logdensity])
    @test Bool(thresholds[:require_no_nonfinite_direct_loglikelihood])
    @test Bool(thresholds[:require_replicated_scores_in_categories])
    @test Bool(thresholds[:require_probability_sums])
    @test Bool(thresholds[:require_summary_rows_finite])
    @test Bool(thresholds[:require_calibration_rows_finite])
    @test Float64(thresholds[:max_direct_parameter_mean_absolute_error]) == 8.0
    @test Float64(thresholds[:max_direct_block_mean_absolute_error]) == 5.0
    @test Float64(thresholds[:max_summary_outside_interval_rate]) == 0.85
    @test Float64(thresholds[:max_absolute_summary_error]) == 1.25
    @test Float64(thresholds[:max_absolute_mean_score_error]) == 1.0
    @test Float64(thresholds[:max_absolute_category_proportion_error]) == 1.0
    @test Float64(thresholds[:max_absolute_calibration_error]) == 1.25

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 2
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "test/fixtures/gmfrm_sparse_design_grid.json",
        "test/fixtures/gmfrm_posterior_predictive_grid.json",
    ])
    for row in reviewed
        artifact = String(row[:artifact])
        @test Bool(row[:exists])
        @test String(row[:sha256]) == file_sha256(joinpath(root, artifact))
    end

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "balanced_parity_sparse",
        "reference_bridge_sparse",
        "cyclic_missing_item_sparse",
    ])
    @test Set(String(row[:sparse_pattern]) for row in scenarios) == Set([
        "half_crossed_parity",
        "reference_bridge",
        "cyclic_missing_item_cells",
    ])
    for scenario in scenarios
        n_observations = Int(scenario[:simulated_data][:n_observations])
        density = scenario[:design_density]
        @test String(density[:rating_density]) == "sparse_connected"
        @test Int(density[:n_observations]) == n_observations
        @test Int(density[:full_crossed_observations]) == 36
        @test Int(thresholds[:min_observations]) <= n_observations <=
            Int(thresholds[:max_observations])
        @test 0.0 < Float64(density[:observed_fraction]) < 1.0
        @test Int(density[:missing_observations]) > 0

        simulated = scenario[:simulated_data]
        @test Vector{Int}(simulated[:category_levels]) == [0, 1, 2]
        @test length(simulated[:person_levels]) == 4
        @test length(simulated[:rater_levels]) == 3
        @test length(simulated[:item_levels]) == 3
        @test length(simulated[:score_counts]) >= 1

        validation = scenario[:validation]
        @test Int(validation[:n_observations]) == n_observations
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_warnings]) >= 1
        @test Int(validation[:n_components]) == 1
        @test Bool(validation[:location_design_full_rank])
        @test length(validation[:issue_rows]) >= 1
        @test length(validation[:issue_codes]) >= 1
        pathology_profile = scenario[:sparse_pathology_profile]
        @test Int(pathology_profile[:n_observations]) == n_observations
        @test Int(pathology_profile[:n_warnings]) == Int(validation[:n_warnings])
        @test Int(pathology_profile[:n_components]) == 1
        @test Bool(pathology_profile[:location_design_full_rank])
        @test length(pathology_profile[:warning_codes]) >= 1

        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test String(fit_record[:backend]) == "advancedhmc"
        @test String(fit_record[:sampler]) == "nuts"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) ==
            [24, n_observations]

        metadata = scenario[:metadata_review]
        @test Bool(metadata[:public_fit])
        @test Bool(metadata[:experimental_public])
        @test String(metadata[:family]) == "gmfrm"
        @test Int(metadata[:dimensions]) == 1
        @test String(metadata[:discrimination]) == "rater"
        @test Int(metadata[:n_draws]) == 24
        @test Int(metadata[:n_chains]) == 2
        @test Int(metadata[:draws_per_chain]) == 12
        @test Int(metadata[:n_parameters]) == 17
        @test Int(metadata[:n_direct_parameters]) == 19

        diagnostic_summary = scenario[:diagnostics_review][:summary]
        @test String(scenario[:diagnostics_review][:schema]) ==
            "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
        @test Bool(scenario[:diagnostics_review][:public_fit])
        @test Bool(scenario[:diagnostics_review][:experimental_public])
        @test String(diagnostic_summary[:flag]) == "ok"
        @test Bool(diagnostic_summary[:passed])
        @test Int(diagnostic_summary[:n_divergences]) == 0
        @test Int(diagnostic_summary[:n_max_treedepth]) == 0
        @test Int(diagnostic_summary[:n_failed_direct_constraints]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_logdensity]) == 0
        @test Int(diagnostic_summary[:n_nonfinite_direct_loglikelihood]) == 0

        information = scenario[:information_criteria_review]
        @test Bool(information[:all_top_level_numeric_finite])
        @test Bool(information[:waic][:all_top_level_numeric_finite])
        @test Bool(information[:loo][:all_top_level_numeric_finite])
        @test Int(information[:waic][:n_observations]) == n_observations
        @test Int(information[:loo][:n_observations]) == n_observations
        @test length(scenario[:direct_recovery_rows]) == 19
        @test all(row -> Bool(row[:finite]), scenario[:direct_recovery_rows])
        @test length(scenario[:direct_recovery_by_block]) == 6
        @test all(row -> Bool(row[:all_finite]),
            scenario[:direct_recovery_by_block])

        predictive = scenario[:predictive_probability_review]
        @test Vector{Int}(predictive[:shape]) == [24, n_observations, 3]
        @test Bool(predictive[:probability_sums_valid])
        @test Float64(predictive[:max_probability_sum_error]) <= 1.0e-12
        @test Vector{Int}(predictive[:expected_scores][:shape]) ==
            [24, n_observations]
        @test Bool(predictive[:expected_scores][:all_finite])
        @test Float64(predictive[:expected_scores][:minimum]) >= 0.0
        @test Float64(predictive[:expected_scores][:maximum]) <= 2.0
        @test Vector{Int}(predictive[:predictive_variances][:shape]) ==
            [24, n_observations]
        @test Bool(predictive[:predictive_variances][:all_finite])
        @test Float64(predictive[:predictive_variances][:minimum]) >= -sqrt(eps())
        @test Bool(predictive[:expected_scores_in_range])

        ppc = scenario[:posterior_predictive_review]
        @test Vector{Int}(ppc[:replicated_scores_shape]) ==
            [24, n_observations]
        @test Bool(ppc[:replicated_scores_in_categories])
        @test Int(ppc[:n_summary_rows]) == 14
        @test length(ppc[:summary_rows]) == 14
        @test length(ppc[:summary_group_rows]) == 5
        @test all(row -> Int(row[:n_replicates]) == 24, ppc[:summary_rows])
        @test all(row -> String(row[:flag]) in ("ok", "outside_interval"),
            ppc[:summary_rows])
        @test Set(String(row[:statistic]) for row in ppc[:summary_group_rows]) ==
            Set(["mean_score", "category_proportion", "person_mean",
                "rater_mean", "item_mean"])

        calibration = scenario[:calibration_review]
        @test Int(calibration[:top_category]) == 2
        @test Int(calibration[:n_rows]) == 6
        @test Bool(calibration[:all_rows_finite])
        @test length(calibration[:expected_score_rows]) == 3
        @test length(calibration[:category_probability_rows]) == 3
        @test all(row -> String(row[:target]) == "expected_score",
            calibration[:expected_score_rows])
        @test all(row -> String(row[:target]) == "category_probability",
            calibration[:category_probability_rows])
        @test Float64(calibration[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Int(scenario_summary[:n_observations]) == n_observations
        @test Bool(scenario_summary[:validation_passed])
        @test Int(scenario_summary[:validation_warnings]) >= 1
        @test Bool(scenario_summary[:location_design_full_rank])
        @test Bool(scenario_summary[:pointwise_shape_valid])
        @test Bool(scenario_summary[:information_criteria_finite])
        @test Int(scenario_summary[:n_divergences]) == 0
        @test Int(scenario_summary[:n_max_treedepth]) == 0
        @test Int(scenario_summary[:n_failed_direct_constraints]) == 0
        @test Int(scenario_summary[:n_nonfinite_logdensity]) == 0
        @test Int(scenario_summary[:n_nonfinite_direct_loglikelihood]) == 0
        @test Bool(scenario_summary[:ppc_returned])
        @test Int(scenario_summary[:n_replicates]) == 24
        @test Int(scenario_summary[:n_summary_rows]) == 14
        @test Bool(scenario_summary[:replicated_scores_in_categories])
        @test Bool(scenario_summary[:probability_sums_valid])
        @test Bool(scenario_summary[:summary_rows_finite])
        @test Bool(scenario_summary[:calibration_rows_finite])
        @test Bool(scenario_summary[:expected_scores_in_range])
        @test Bool(scenario_summary[:predictive_variances_nonnegative])
        @test Float64(scenario_summary[:max_direct_parameter_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_parameter_mean_absolute_error])
        @test Float64(scenario_summary[:max_direct_block_mean_absolute_error]) <=
            Float64(thresholds[:max_direct_block_mean_absolute_error])
        @test Float64(scenario_summary[:outside_interval_rate]) <=
            Float64(thresholds[:max_summary_outside_interval_rate])
        @test Float64(scenario_summary[:max_absolute_summary_error]) <=
            Float64(thresholds[:max_absolute_summary_error])
        @test Float64(scenario_summary[:max_absolute_mean_score_error]) <=
            Float64(thresholds[:max_absolute_mean_score_error])
        @test Float64(scenario_summary[:max_absolute_category_proportion_error]) <=
            Float64(thresholds[:max_absolute_category_proportion_error])
        @test Float64(scenario_summary[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_scalar_gmfrm_prior_likelihood_sensitivity_grid_followup"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_replicates_per_scenario]) == 24
    @test Int(summary[:n_observations_minimum]) == 18
    @test Int(summary[:n_observations_maximum]) == 28
    @test Bool(summary[:all_validations_passed])
    @test Bool(summary[:all_location_designs_full_rank])
    @test Bool(summary[:all_guarded_fit_returned])
    @test Bool(summary[:all_pointwise_shapes_valid])
    @test Bool(summary[:all_information_criteria_finite])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_no_nonfinite_logdensity])
    @test Bool(summary[:all_no_nonfinite_direct_loglikelihood])
    @test Bool(summary[:all_ppc_returned])
    @test Bool(summary[:all_replicated_scores_in_categories])
    @test Bool(summary[:all_probability_sums_valid])
    @test Bool(summary[:all_summary_rows_finite])
    @test Bool(summary[:all_calibration_rows_finite])
    @test Float64(summary[:max_direct_parameter_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_parameter_mean_absolute_error])
    @test Float64(summary[:max_direct_block_mean_absolute_error]) <=
        Float64(thresholds[:max_direct_block_mean_absolute_error])
    @test Float64(summary[:max_outside_interval_rate]) <=
        Float64(thresholds[:max_summary_outside_interval_rate])
    @test Float64(summary[:max_absolute_summary_error]) <=
        Float64(thresholds[:max_absolute_summary_error])
    @test Float64(summary[:max_absolute_mean_score_error]) <=
        Float64(thresholds[:max_absolute_mean_score_error])
    @test Float64(summary[:max_absolute_category_proportion_error]) <=
        Float64(thresholds[:max_absolute_category_proportion_error])
    @test Float64(summary[:max_absolute_calibration_error]) <=
        Float64(thresholds[:max_absolute_calibration_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_prior_likelihood_sensitivity_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_prior_likelihood_sensitivity_grid"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
end

function check_gmfrm_prior_likelihood_sensitivity_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_prior_likelihood_sensitivity_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_prior_likelihood_sensitivity_grid_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    sampler = protocol[:sampler]
    sensitivity = protocol[:sensitivity_method]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_prior_likelihood_sensitivity_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:entrypoint_under_validation]) ==
        "importance-reweighted fit(spec; experimental = true) prior and likelihood sensitivity"
    @test String(protocol[:simulation_source]) ==
        "scalar_gmfrm_sparse_pathology_recovery_grid_scenarios"
    @test Set(String(protocol_id) for protocol_id in protocol[:reviewed_protocols]) ==
        Set([
            "scalar_gmfrm_sparse_pathology_recovery_grid_v1",
            "scalar_gmfrm_guarded_exposure_review_v1",
        ])
    @test String(sensitivity[:draw_source]) ==
        "guarded_experimental_gmfrm_fit_draws"
    @test String(sensitivity[:prior_sensitivity]) ==
        "raw_coordinate_importance_reweighting"
    @test String(sensitivity[:likelihood_sensitivity]) ==
        "power_likelihood_tempering"
    @test String(sensitivity[:refit_policy]) ==
        "not_refit_local_guarded_screen"
    @test String(sensitivity[:normalization]) ==
        "self_normalized_importance_weights"
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 12
    @test Int(sampler[:draws]) == 12
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"

    @test length(protocol[:prior_profiles]) == 5
    @test Set(String(profile[:name]) for profile in protocol[:prior_profiles]) == Set([
        "baseline_raw_prior",
        "globally_tighter_raw_prior",
        "globally_weaker_raw_prior",
        "tighter_generalized_scale_prior",
        "weaker_generalized_scale_prior",
    ])
    @test Float64.(protocol[:likelihood_powers]) == [0.8, 1.0, 1.2]
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:n_prior_profiles]) == 5
    @test Int(thresholds[:n_likelihood_powers]) == 3
    @test Int(thresholds[:n_sensitivity_cells]) == 15
    @test Int(thresholds[:n_draws_per_cell]) == 24
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_all_logweights_finite])
    @test Bool(thresholds[:require_baseline_identity])
    @test Bool(thresholds[:require_all_direct_shifts_finite])
    @test Bool(thresholds[:require_all_predictive_shifts_finite])
    @test Float64(thresholds[:require_weight_ess_rate_minimum]) == 0.05
    @test Float64(thresholds[:max_direct_parameter_mean_shift]) == 3.0
    @test Float64(thresholds[:max_direct_block_mean_shift]) == 2.0
    @test Float64(thresholds[:max_expected_score_shift]) == 1.25
    @test Float64(thresholds[:max_top_category_probability_shift]) == 0.60
    @test Float64(thresholds[:max_loglikelihood_mean_shift]) == 20.0
    @test Float64(thresholds[:max_logposterior_decomposition_error]) == 1.0e-8

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 2
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        "test/fixtures/gmfrm_guarded_exposure_review.json",
    ])
    sparse_reference = only(row for row in reviewed
        if String(row[:artifact]) ==
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json")
    @test Bool(sparse_reference[:exists])
    @test String(sparse_reference[:hash_policy]) == "sha256"
    @test String(sparse_reference[:sha256]) ==
        file_sha256(joinpath(root, String(sparse_reference[:artifact])))
    guarded_reference = only(row for row in reviewed
        if String(row[:artifact]) ==
            "test/fixtures/gmfrm_guarded_exposure_review.json")
    @test Bool(guarded_reference[:exists])
    @test String(guarded_reference[:hash_policy]) ==
        "existence_only_avoids_cyclic_review_hash"
    @test isnothing(guarded_reference[:sha256])

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "balanced_parity_sparse",
        "reference_bridge_sparse",
        "cyclic_missing_item_sparse",
    ])
    @test Set(String(row[:sparse_pattern]) for row in scenarios) == Set([
        "half_crossed_parity",
        "reference_bridge",
        "cyclic_missing_item_cells",
    ])
    for scenario in scenarios
        n_observations = Int(scenario[:n_observations])
        fit_record = scenario[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) ==
            [24, n_observations]

        baseline_prior = scenario[:baseline_prior]
        @test Float64(baseline_prior[:person_sd]) == 1.0
        @test Float64(baseline_prior[:rater_sd]) == 1.0
        @test Float64(baseline_prior[:item_sd]) == 1.0
        @test Float64(baseline_prior[:log_discrimination_sd]) == 0.5
        @test Float64(baseline_prior[:log_consistency_sd]) == 0.5
        @test Float64(baseline_prior[:step_sd]) == 1.0
        decomposition = scenario[:baseline_logposterior_decomposition]
        @test Bool(decomposition[:passed])
        @test Float64(decomposition[:maximum_absolute_error]) <=
            Float64(thresholds[:max_logposterior_decomposition_error])

        cells = scenario[:sensitivity_cells]
        @test length(cells) == 15
        @test Set(String(cell[:prior_profile]) for cell in cells) == Set([
            "baseline_raw_prior",
            "globally_tighter_raw_prior",
            "globally_weaker_raw_prior",
            "tighter_generalized_scale_prior",
            "weaker_generalized_scale_prior",
        ])
        @test Set(Float64(cell[:likelihood_power]) for cell in cells) ==
            Set([0.8, 1.0, 1.2])
        baseline_cell = only(cell for cell in cells
            if String(cell[:prior_profile]) == "baseline_raw_prior" &&
                Float64(cell[:likelihood_power]) == 1.0)
        @test Float64(baseline_cell[:summary][:max_direct_parameter_mean_shift]) <=
            1.0e-10
        @test Float64(baseline_cell[:summary][:max_expected_score_shift]) <=
            1.0e-10
        @test Float64(baseline_cell[:summary][:max_top_category_probability_shift]) <=
            1.0e-10

        for cell in cells
            @test Int(cell[:n_draws]) == 24
            weight = cell[:weight_review]
            @test Bool(weight[:all_logweights_finite])
            @test Float64(weight[:logweight_range]) >= 0.0
            @test Float64(weight[:effective_sample_size]) >= 1.0
            @test Float64(weight[:effective_sample_size_rate]) >=
                Float64(thresholds[:require_weight_ess_rate_minimum])
            @test 0.0 <= Float64(weight[:maximum_weight]) <= 1.0
            @test 0.0 <= Float64(weight[:normalized_entropy]) <=
                1.0 + 10eps(Float64)

            prior_review = cell[:logprior_review]
            @test Bool(prior_review[:baseline][:all_finite])
            @test Bool(prior_review[:sensitivity][:all_finite])
            @test Bool(prior_review[:delta][:all_finite])
            loglikelihood = cell[:loglikelihood_review]
            @test isfinite(Float64(loglikelihood[:baseline_mean]))
            @test isfinite(Float64(loglikelihood[:weighted_mean]))
            @test Float64(loglikelihood[:absolute_shift]) <=
                Float64(thresholds[:max_loglikelihood_mean_shift])

            direct_rows = cell[:direct_parameter_shift_rows]
            @test length(direct_rows) == 19
            @test all(row -> Bool(row[:finite]), direct_rows)
            @test all(row -> isfinite(Float64(row[:absolute_shift])), direct_rows)
            block_rows = cell[:direct_block_shift_rows]
            @test length(block_rows) == 6
            @test all(row -> Bool(row[:all_finite]), block_rows)
            @test all(row -> Float64(row[:mean_absolute_shift]) <=
                Float64(thresholds[:max_direct_block_mean_shift]), block_rows)

            predictive = cell[:predictive_shift_review]
            @test Float64(predictive[:expected_score_max_absolute_shift]) <=
                Float64(thresholds[:max_expected_score_shift])
            @test Float64(predictive[:top_category_probability_max_absolute_shift]) <=
                Float64(thresholds[:max_top_category_probability_shift])

            cell_summary = cell[:summary]
            @test Bool(cell_summary[:all_logweights_finite])
            @test Float64(cell_summary[:weight_ess_rate]) >=
                Float64(thresholds[:require_weight_ess_rate_minimum])
            @test Float64(cell_summary[:max_direct_parameter_mean_shift]) <=
                Float64(thresholds[:max_direct_parameter_mean_shift])
            @test Float64(cell_summary[:max_direct_block_mean_shift]) <=
                Float64(thresholds[:max_direct_block_mean_shift])
            @test Float64(cell_summary[:max_expected_score_shift]) <=
                Float64(thresholds[:max_expected_score_shift])
            @test Float64(cell_summary[:max_top_category_probability_shift]) <=
                Float64(thresholds[:max_top_category_probability_shift])
            @test Float64(cell_summary[:loglikelihood_mean_absolute_shift]) <=
                Float64(thresholds[:max_loglikelihood_mean_shift])
        end

        scenario_summary = scenario[:summary]
        @test Bool(scenario_summary[:passed])
        @test Int(scenario_summary[:n_sensitivity_cells]) == 15
        @test Int(scenario_summary[:n_prior_profiles]) == 5
        @test Int(scenario_summary[:n_likelihood_powers]) == 3
        @test Bool(scenario_summary[:all_cells_finite])
        @test Bool(scenario_summary[:baseline_identity])
        @test Float64(scenario_summary[:min_weight_ess_rate]) >=
            Float64(thresholds[:require_weight_ess_rate_minimum])
        @test Float64(scenario_summary[:max_weight]) <= 1.0
        @test Float64(scenario_summary[:max_direct_parameter_mean_shift]) <=
            Float64(thresholds[:max_direct_parameter_mean_shift])
        @test Float64(scenario_summary[:max_direct_block_mean_shift]) <=
            Float64(thresholds[:max_direct_block_mean_shift])
        @test Float64(scenario_summary[:max_expected_score_shift]) <=
            Float64(thresholds[:max_expected_score_shift])
        @test Float64(scenario_summary[:max_top_category_probability_shift]) <=
            Float64(thresholds[:max_top_category_probability_shift])
        @test Float64(scenario_summary[:max_loglikelihood_mean_shift]) <=
            Float64(thresholds[:max_loglikelihood_mean_shift])
        @test Float64(scenario_summary[:max_logposterior_decomposition_error]) <=
            Float64(thresholds[:max_logposterior_decomposition_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_scalar_gmfrm_real_data_case_study_followup"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed"
    @test String(decision[:required_followup]) ==
        "scalar_gmfrm_real_data_case_study"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_scenarios]) == 3
    @test Int(summary[:n_passed_scenarios]) == 3
    @test Int(summary[:n_sensitivity_cells]) == 45
    @test Int(summary[:n_prior_profiles]) == 5
    @test Int(summary[:n_likelihood_powers]) == 3
    @test Bool(summary[:all_cells_finite])
    @test Bool(summary[:all_baseline_identity])
    @test Float64(summary[:min_weight_ess_rate]) >=
        Float64(thresholds[:require_weight_ess_rate_minimum])
    @test Float64(summary[:max_weight]) <= 1.0
    @test Float64(summary[:max_direct_parameter_mean_shift]) <=
        Float64(thresholds[:max_direct_parameter_mean_shift])
    @test Float64(summary[:max_direct_block_mean_shift]) <=
        Float64(thresholds[:max_direct_block_mean_shift])
    @test Float64(summary[:max_expected_score_shift]) <=
        Float64(thresholds[:max_expected_score_shift])
    @test Float64(summary[:max_top_category_probability_shift]) <=
        Float64(thresholds[:max_top_category_probability_shift])
    @test Float64(summary[:max_loglikelihood_mean_shift]) <=
        Float64(thresholds[:max_loglikelihood_mean_shift])
    @test Float64(summary[:max_logposterior_decomposition_error]) <=
        Float64(thresholds[:max_logposterior_decomposition_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["scalar_gmfrm_real_data_case_study_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_real_data_case_study"
    @test String(summary[:next_gate]) ==
        "scalar_gmfrm_real_data_case_study"
end

function check_gmfrm_real_data_case_study_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_real_data_case_study.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "guarded_experimental_real_data_case_study_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    selection = protocol[:selection]
    source_policy = protocol[:source_policy]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_real_data_case_study_v1"
    @test String(protocol[:review_kind]) ==
        "local_guarded_experimental_real_data_case_study"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test Bool(source_policy[:source_files_external_to_package])
    @test Bool(source_policy[:artifact_rows_anonymized])
    @test Bool(source_policy[:no_raw_text_exported])
    @test Int(selection[:person_count]) == 4
    @test Int(selection[:rater_count]) == 3
    @test Int(selection[:criterion_count]) == 3
    @test Bool(selection[:require_complete_crossing_after_selection])
    @test Int(thresholds[:n_cases]) == 2
    @test Int(thresholds[:n_observations_per_case]) == 36
    @test Int(thresholds[:n_replicates_per_case]) == 24
    @test Bool(thresholds[:require_source_file_available])
    @test Bool(thresholds[:require_validation_passed])
    @test Bool(thresholds[:require_complete_crossing])
    @test Bool(thresholds[:require_guarded_fit_returned])
    @test Bool(thresholds[:require_baseline_fits_returned])
    @test Bool(thresholds[:require_model_comparison_finite])

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 4
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "../Simulation/data/writing_long.csv",
        "../Simulation/data/speaking_long.csv",
        "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        "test/fixtures/gmfrm_guarded_exposure_review.json",
    ])
    for row in reviewed
        @test Bool(row[:exists])
        if String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(normpath(joinpath(root, String(row[:artifact]))))
        else
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_cyclic_review_hash"
            @test isnothing(row[:sha256])
        end
    end

    cases = fixture[:cases]
    @test length(cases) == 2
    @test Set(String(case[:case_id]) for case in cases) == Set([
        "writing_icnale_small_slice",
        "speaking_icnale_small_slice",
    ])
    for case in cases
        selected = case[:selected_data]
        @test Int(selected[:n_observations]) == 36
        @test Bool(selected[:complete_crossing])
        @test length(selected[:person_levels]) == 4
        @test length(selected[:rater_levels]) == 3
        @test length(selected[:item_levels]) == 3
        @test Vector{Int}(selected[:category_levels]) == [0, 1, 2]

        validation = case[:validation]
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_warnings]) >= 0
        @test all(row -> String(row[:severity]) == "warning",
            validation[:issue_rows])
        @test Bool(validation[:location_design_full_rank])

        metadata = case[:metadata_review]
        @test Bool(metadata[:public_fit])
        @test Bool(metadata[:experimental_public])
        @test String(metadata[:family]) == "gmfrm"
        @test Int(metadata[:n_draws]) == 24
        @test Int(metadata[:n_parameters]) == 17
        @test Int(metadata[:n_direct_parameters]) == 19

        fit_record = case[:fit_record]
        @test String(fit_record[:type]) == "GMFRMFit"
        @test Vector{Int}(fit_record[:raw_draws_shape]) == [24, 17]
        @test Vector{Int}(fit_record[:direct_draws_shape]) == [24, 19]
        @test Vector{Int}(fit_record[:pointwise_loglikelihood_shape]) == [24, 36]

        diagnostics = case[:diagnostics_review][:summary]
        @test Bool(diagnostics[:passed])
        @test Int(diagnostics[:n_divergences]) == 0
        @test Int(diagnostics[:n_max_treedepth]) == 0
        @test Int(diagnostics[:n_failed_direct_constraints]) == 0
        @test Int(diagnostics[:n_nonfinite_logdensity]) == 0
        @test Int(diagnostics[:n_nonfinite_direct_loglikelihood]) == 0

        information = case[:information_criteria_review]
        @test Bool(information[:all_top_level_numeric_finite])
        @test String(information[:waic][:criterion]) == "waic"
        @test String(information[:loo][:criterion]) == "loo"

        ppc = case[:posterior_predictive_review]
        @test Vector{Int}(ppc[:replicated_scores_shape]) == [24, 36]
        @test Bool(ppc[:replicated_scores_in_categories])
        @test Int(ppc[:n_summary_rows]) == 14
        @test all(row -> String(row[:flag]) in ("ok", "outside_interval"),
            ppc[:summary_rows])

        calibration = case[:calibration_review]
        @test Int(calibration[:top_category]) == 2
        @test Int(calibration[:n_rows]) == 6
        @test Bool(calibration[:all_rows_finite])
        @test Float64(calibration[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])

        model_records = case[:model_records]
        @test length(model_records) == 3
        @test Set(String(row[:model]) for row in model_records) == Set([
            "guarded_scalar_gmfrm",
            "public_mfrm_partial_credit",
            "public_mfrm_rating_scale",
        ])
        @test all(row -> Bool(row[:information_criteria][:all_top_level_numeric_finite]),
            model_records)

        comparison = case[:model_comparison]
        @test length(comparison) == 3
        @test [Int(row[:rank]) for row in comparison] == [1, 2, 3]
        @test all(row -> String(row[:criterion]) == "waic", comparison)
        @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
            isfinite(Float64(row[:waic])), comparison)
        @test sum(Float64(row[:relative_weight]) for row in comparison) ≈ 1.0

        summary = case[:summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_observations]) == 36
        @test Bool(summary[:complete_crossing])
        @test Bool(summary[:validation_passed])
        @test Bool(summary[:guarded_fit_returned])
        @test Bool(summary[:baseline_fits_returned])
        @test Bool(summary[:pointwise_shape_valid])
        @test Bool(summary[:information_criteria_finite])
        @test Bool(summary[:model_comparison_finite])
        @test Bool(summary[:ppc_returned])
        @test Int(summary[:n_replicates]) == 24
        @test Bool(summary[:replicated_scores_in_categories])
        @test Bool(summary[:probability_sums_valid])
        @test Bool(summary[:summary_rows_finite])
        @test Bool(summary[:calibration_rows_finite])
        @test Float64(summary[:outside_interval_rate]) <=
            Float64(thresholds[:max_summary_outside_interval_rate])
        @test Float64(summary[:max_absolute_summary_error]) <=
            Float64(thresholds[:max_absolute_summary_error])
        @test Float64(summary[:max_absolute_calibration_error]) <=
            Float64(thresholds[:max_absolute_calibration_error])
    end

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_scalar_gmfrm_manuscript_claim_followup"
    @test String(decision[:interpretation]) ==
        "guarded_scalar_gmfrm_real_data_case_study_passed"
    @test String(decision[:required_followup]) ==
        "claim_level_recovery_and_reproduction_archive"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_cases]) == 2
    @test Int(summary[:n_passed_cases]) == 2
    @test Int(summary[:n_observations_total]) == 72
    @test Int(summary[:n_replicates_per_case]) == 24
    @test Bool(summary[:all_source_files_available])
    @test Bool(summary[:all_validations_passed])
    @test Bool(summary[:all_complete_crossing])
    @test Bool(summary[:all_guarded_fit_returned])
    @test Bool(summary[:all_baseline_fits_returned])
    @test Bool(summary[:all_pointwise_shapes_valid])
    @test Bool(summary[:all_information_criteria_finite])
    @test Bool(summary[:all_model_comparisons_finite])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_no_nonfinite_logdensity])
    @test Bool(summary[:all_no_nonfinite_direct_loglikelihood])
    @test Bool(summary[:all_ppc_returned])
    @test Bool(summary[:all_replicated_scores_in_categories])
    @test Bool(summary[:all_probability_sums_valid])
    @test Bool(summary[:all_summary_rows_finite])
    @test Bool(summary[:all_calibration_rows_finite])
    @test Float64(summary[:max_outside_interval_rate]) <=
        Float64(thresholds[:max_summary_outside_interval_rate])
    @test Float64(summary[:max_absolute_summary_error]) <=
        Float64(thresholds[:max_absolute_summary_error])
    @test Float64(summary[:max_absolute_calibration_error]) <=
        Float64(thresholds[:max_absolute_calibration_error])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["claim_level_recovery_and_reproduction_archive_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_claim_level_recovery_and_archive"
    @test String(summary[:next_gate]) ==
        "claim_level_recovery_and_reproduction_archive"
end

function check_gmfrm_claim_recovery_reproduction_archive_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_claim_recovery_reproduction_archive.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) ==
        "claim_recovery_reproduction_archive_recorded"
    @test String(fixture[:decision]) == "keep_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "scalar_gmfrm_claim_recovery_reproduction_archive_v1"
    @test String(protocol[:review_kind]) ==
        "local_claim_recovery_reproduction_archive"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:archive_scope]) ==
        "fast_and_full_local_reproduction_manifest"
    @test Bool(thresholds[:require_all_fixture_artifacts_present])
    @test Bool(thresholds[:require_all_expected_schemas])
    @test Bool(thresholds[:require_all_fixture_summaries_passed])
    @test Bool(thresholds[:require_all_generator_scripts_present])
    @test Bool(thresholds[:require_all_code_doc_references_present])
    @test Bool(thresholds[:require_all_external_sources_present])
    @test Bool(thresholds[:require_all_commands_local_only])
    @test Bool(thresholds[:require_no_publication_commands])
    @test Bool(thresholds[:require_guarded_exposure_review_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])

    fixture_records = fixture[:fixture_records]
    @test length(fixture_records) == 18
    @test Set(String(row[:artifact]) for row in fixture_records) == Set([
        "candidate_chain_study",
        "stress_chain_grid",
        "recovery_smoke_study",
        "baseline_comparison",
        "baseline_calibration_grid",
        "interval_decision_grid",
        "sparse_design_grid",
        "waic_influence_review",
        "psis_loo_review",
        "exact_loo_or_kfold_review",
        "guarded_fit_method_wiring",
        "experimental_fit_validation_grid",
        "posterior_predictive_grid",
        "sparse_pathology_recovery_grid",
        "prior_likelihood_sensitivity_grid",
        "real_data_case_study",
        "guarded_fit_api_dry_run",
        "guarded_exposure_review",
    ])
    for row in fixture_records
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test Bool(row[:generator_exists])
        @test occursin("julia --project=. scripts/generate_",
            String(row[:generation_command]))
        @test !isempty(String(row[:env_var]))
        if String(row[:artifact]) == "guarded_exposure_review"
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_archive_review_hash_cycle"
            @test isnothing(row[:sha256])
        else
            @test String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, String(row[:path])))
        end
    end

    source_records = fixture[:source_records]
    @test length(source_records) == 2
    @test Set(String(row[:path]) for row in source_records) == Set([
        "../Simulation/data/writing_long.csv",
        "../Simulation/data/speaking_long.csv",
    ])
    for row in source_records
        @test Bool(row[:exists])
        @test String(row[:hash_policy]) == "sha256_when_available"
        @test String(row[:sha256]) ==
            file_sha256(normpath(joinpath(root, String(row[:path]))))
        @test Int(row[:line_count]) > 100_000
    end

    code_doc_records = fixture[:code_doc_records]
    @test length(code_doc_records) == 13
    @test all(row -> Bool(row[:exists]), code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_gmfrm_claim_recovery_reproduction_archive.jl",
        code_doc_records)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(joinpath(root, String(row[:path]))), code_doc_records)

    full_commands = fixture[:full_regeneration_commands]
    @test length(full_commands) == 19
    @test [Int(row[:step]) for row in full_commands] == collect(1:19)
    @test all(row -> Bool(row[:local_only]), full_commands)
    @test String(full_commands[end - 1][:artifact]) ==
        "claim_recovery_reproduction_archive"
    @test String(full_commands[end][:artifact]) == "guarded_exposure_review"

    verification = fixture[:verification_commands]
    @test length(verification) == 4
    @test Set(String(row[:name]) for row in verification) == Set([
        "package_tests",
        "documentation_build",
        "local_pre_registration_gate",
        "whitespace_check",
    ])
    @test all(row -> Bool(row[:local_only]), verification)
    @test all(row -> String(row[:execution]) == "required_before_claim_use",
        verification)
    @test all(row -> !occursin("git push", String(row[:command])), verification)

    cycle_breaks = fixture[:cycle_break_references]
    @test length(cycle_breaks) == 1
    @test String(cycle_breaks[1][:artifact]) ==
        "test/fixtures/gmfrm_guarded_exposure_review.json"
    @test String(cycle_breaks[1][:hash_policy]) == "existence_only"

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed])
    @test Bool(decision[:experimental_keyword_enabled])
    @test String(decision[:public_exposure_support]) ==
        "satisfied_for_broader_experimental_exposure_decision_followup"
    @test String(decision[:interpretation]) ==
        "claim_level_recovery_reproduction_archive_recorded"
    @test String(decision[:required_followup]) ==
        "broader_experimental_exposure_decision_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Int(summary[:n_fixture_artifacts]) == length(fixture_records)
    @test Int(summary[:n_source_records]) == length(source_records)
    @test Int(summary[:n_code_doc_records]) == length(code_doc_records)
    @test Int(summary[:n_full_regeneration_commands]) == length(full_commands)
    @test Int(summary[:n_verification_commands]) == length(verification)
    @test Bool(summary[:all_fixture_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_fixture_summaries_passed])
    @test Bool(summary[:all_generator_scripts_present])
    @test Bool(summary[:all_code_doc_references_present])
    @test Bool(summary[:all_external_sources_present])
    @test Bool(summary[:all_commands_local_only])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:guarded_exposure_review_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["broader_experimental_exposure_decision_review_missing"])
    @test String(summary[:recommendation]) ==
        "keep_guarded_experimental_until_broader_exposure_decision_review"
    @test String(summary[:next_gate]) ==
        "broader_experimental_exposure_decision_review"
end

function check_gmfrm_full_paper_reproduction_archive_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_full_paper_reproduction_archive.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "full_paper_reproduction_archive"
    @test String(fixture[:status]) == "full_paper_reproduction_archive_recorded"
    @test String(fixture[:decision]) ==
        "archive_full_and_fast_reproduction_bundle_local_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_full_paper_reproduction_archive_v1"
    @test String(protocol[:review_kind]) ==
        "local_full_paper_reproduction_archive"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:archive_scope]) ==
        "full_and_fast_local_reproduction_manifest"
    @test Bool(thresholds[:require_all_fixture_artifacts_present])
    @test Bool(thresholds[:require_all_expected_schemas])
    @test Bool(thresholds[:require_all_fixture_summaries_passed])
    @test Bool(thresholds[:require_all_generator_scripts_present])
    @test Bool(thresholds[:require_all_code_doc_references_present])
    @test Bool(thresholds[:require_all_external_sources_present])
    @test Bool(thresholds[:require_full_regeneration_commands_recorded])
    @test Bool(thresholds[:require_verification_commands_recorded])
    @test Bool(thresholds[:require_all_commands_local_only])
    @test Bool(thresholds[:require_no_publication_commands])
    @test Bool(thresholds[:require_guarded_exposure_review_passed])
    @test Bool(thresholds[:require_broader_exposure_review_passed])
    @test Bool(thresholds[:require_manuscript_scale_simulation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])

    fixture_records = fixture[:fixture_records]
    expected_paths = Dict(
        "source_gmfrm_bridge_logdensity" =>
            "test/fixtures/source_gmfrm_bridge_logdensity.json",
        "source_mgmfrm_bridge_logdensity" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "candidate_chain_study" =>
            "test/fixtures/gmfrm_candidate_chain_study.json",
        "stress_chain_grid" =>
            "test/fixtures/gmfrm_stress_chain_grid.json",
        "recovery_smoke_study" =>
            "test/fixtures/gmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/gmfrm_baseline_comparison.json",
        "baseline_calibration_grid" =>
            "test/fixtures/gmfrm_baseline_calibration_grid.json",
        "interval_decision_grid" =>
            "test/fixtures/gmfrm_interval_decision_grid.json",
        "sparse_design_grid" =>
            "test/fixtures/gmfrm_sparse_design_grid.json",
        "waic_influence_review" =>
            "test/fixtures/gmfrm_waic_influence_review.json",
        "psis_loo_review" =>
            "test/fixtures/gmfrm_psis_loo_review.json",
        "exact_loo_or_kfold_review" =>
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        "experimental_fit_validation_grid" =>
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        "posterior_predictive_grid" =>
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        "sparse_pathology_recovery_grid" =>
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        "prior_likelihood_sensitivity_grid" =>
            "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        "real_data_case_study" =>
            "test/fixtures/gmfrm_real_data_case_study.json",
        "claim_recovery_reproduction_archive" =>
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        "broader_experimental_exposure_decision_review" =>
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "manuscript_scale_simulation_grid" =>
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        "guarded_exposure_review" =>
            "test/fixtures/gmfrm_guarded_exposure_review.json",
        "mgmfrm_candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "mgmfrm_recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "mgmfrm_baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "mgmfrm_guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        "mgmfrm_guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        "mgmfrm_guarded_fit_public_exposure_review" =>
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
    )
    @test length(fixture_records) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in fixture_records) ==
        Set(keys(expected_paths))
    for row in fixture_records
        artifact = String(row[:artifact])
        path = String(row[:path])
        @test expected_paths[artifact] == path
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test Bool(row[:generator_exists])
        @test !isempty(String(row[:env_var]))
        if artifact in (
                "broader_experimental_exposure_decision_review",
                "guarded_exposure_review",
                "manuscript_scale_simulation_grid")
            @test startswith(String(row[:hash_policy]),
                "existence_only_avoids_full_archive")
            @test isnothing(row[:sha256])
        else
            @test String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, path))
        end
    end

    code_doc_records = fixture[:code_doc_records]
    @test length(code_doc_records) == 27
    @test all(row -> Bool(row[:exists]), code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_gmfrm_full_paper_reproduction_archive.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_method_wiring.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_validation_grid.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_api_dry_run.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_mgmfrm_guarded_fit_public_exposure_review.jl",
        code_doc_records)
    @test any(row -> String(row[:path]) ==
        "scripts/generate_gmfrm_prediction_target_and_model_weight_policy.jl",
        code_doc_records)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(joinpath(root, String(row[:path]))), code_doc_records)

    source_records = fixture[:source_records]
    @test length(source_records) == 2
    @test Set(String(row[:path]) for row in source_records) == Set([
        "../Simulation/data/writing_long.csv",
        "../Simulation/data/speaking_long.csv",
    ])
    @test all(row -> Bool(row[:exists]), source_records)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(normpath(joinpath(root, String(row[:path])))),
        source_records)

    full_commands = fixture[:full_regeneration_commands]
    @test length(full_commands) == 33
    @test [Int(row[:step]) for row in full_commands] == collect(1:33)
    @test all(row -> Bool(row[:local_only]), full_commands)
    @test any(row -> String(row[:artifact]) ==
        "prediction_target_and_model_weight_policy", full_commands)
    @test String(full_commands[end - 3][:artifact]) ==
        "gmfrm_full_paper_reproduction_archive"
    @test String(full_commands[end][:artifact]) == "gmfrm_guarded_exposure_review"

    verification = fixture[:verification_commands]
    @test length(verification) == 4
    @test Set(String(row[:name]) for row in verification) == Set([
        "package_tests",
        "documentation_build",
        "local_pre_registration_gate",
        "whitespace_check",
    ])
    @test all(row -> Bool(row[:local_only]), verification)
    @test all(row -> String(row[:execution]) == "required_before_claim_use",
        verification)
    @test all(row -> !occursin("git push", String(row[:command])),
        verification)

    cycle_breaks = fixture[:cycle_break_references]
    @test length(cycle_breaks) == 3
    @test Set(String(row[:hash_policy]) for row in cycle_breaks) ==
        Set(["existence_only"])

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "full_paper_reproduction_archive_recorded_local_only"
    @test Bool(decision[:scalar_guarded_fit_allowed])
    @test Bool(decision[:broader_generalized_fit_allowed]) == false
    @test Bool(decision[:mgmfrm_fit_allowed]) == false
    @test Bool(decision[:manuscript_reproducibility_claims_supported])
    @test Bool(decision[:publication_or_registration_action]) == false
    @test String(decision[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Int(summary[:n_fixture_artifacts]) == length(fixture_records)
    @test Int(summary[:n_code_doc_records]) == length(code_doc_records)
    @test Int(summary[:n_source_records]) == length(source_records)
    @test Int(summary[:n_full_regeneration_commands]) == length(full_commands)
    @test Int(summary[:n_verification_commands]) == length(verification)
    @test Bool(summary[:all_fixture_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_fixture_summaries_passed])
    @test Bool(summary[:all_generator_scripts_present])
    @test Bool(summary[:all_code_doc_references_present])
    @test Bool(summary[:all_external_sources_present])
    @test Bool(summary[:full_regeneration_commands_recorded])
    @test Bool(summary[:verification_commands_recorded])
    @test Bool(summary[:all_commands_local_only])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:guarded_exposure_review_passed])
    @test Bool(summary[:broader_experimental_exposure_decision_review_passed])
    @test Bool(summary[:manuscript_scale_simulation_grid_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:manuscript_reproducibility_claims_supported])
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "full_paper_reproduction_archive_recorded_keep_publication_manual"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end

function check_gmfrm_dff_estimand_validation_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "dff_estimand_and_validation_grid"
    @test String(fixture[:status]) == "dff_estimand_validation_grid_recorded"
    @test String(fixture[:decision]) == "keep_dff_validation_only"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_dff_estimand_validation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_dff_estimand_and_validation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint_under_review]) ==
        "validate_design(data; bias = terms)"
    @test Int(protocol[:min_cell_count]) == 3
    @test Set(String(facet) for facet in protocol[:supported_validation_facets]) ==
        Set(["person", "rater", "item", "group"])
    @test Bool(thresholds[:require_estimands_predeclared])
    @test Bool(thresholds[:require_reporting_scales_predeclared])
    @test Bool(thresholds[:require_positive_control_passes_without_warnings])
    @test Bool(thresholds[:require_sparse_warning_detected])
    @test Bool(thresholds[:require_empty_and_confounded_warning_detected])
    @test Bool(thresholds[:require_unknown_facet_error_detected])
    @test Bool(thresholds[:require_valid_dff_terms_retained_as_validation_only])
    @test Bool(thresholds[:require_no_public_fit_or_model_effect_promotion])
    @test String(thresholds[:public_exposure_decision]) == "keep_validation_only"

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 3
    expected_reviewed = Dict(
        "test/fixtures/gmfrm_guarded_exposure_review.json" =>
            "existence_only_avoids_guarded_review_dff_cycle",
        "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json" =>
            "existence_only_avoids_broader_review_dff_cycle",
        "test/fixtures/mgmfrm_sparse_recovery_grid.json" => "sha256",
    )
    @test Set(String(row[:artifact]) for row in reviewed) ==
        Set(keys(expected_reviewed))
    for row in reviewed
        artifact = String(row[:artifact])
        @test Bool(row[:exists])
        @test String(row[:hash_policy]) == expected_reviewed[artifact]
        if expected_reviewed[artifact] == "sha256"
            @test String(row[:sha256]) == file_sha256(joinpath(root, artifact))
        else
            @test isnothing(row[:sha256])
        end
    end

    estimands = fixture[:estimand_rows]
    @test length(estimands) == 5
    @test Set(String(row[:estimand]) for row in estimands) == Set([
        "rater_by_group_dff",
        "item_by_group_dff",
        "rater_by_item_interaction",
        "threshold_by_group_dff",
        "discrimination_by_group_dff",
    ])
    @test all(row -> String(row[:primary_scale]) == "logit", estimands)
    @test all(row -> Set(String(scale) for scale in row[:reporting_scales]) ==
        Set(["logit", "expected_score"]), estimands)
    @test count(row -> String(row[:current_status]) == "validation_only",
        estimands) == 3
    @test any(row -> String(row[:estimand]) == "threshold_by_group_dff" &&
        String(row[:current_status]) ==
            "predeclared_not_validated_by_current_bias_api",
        estimands)
    @test any(row -> String(row[:estimand]) == "discrimination_by_group_dff" &&
        String(row[:current_status]) ==
            "predeclared_requires_future_generalized_fit_policy",
        estimands)

    scenarios = fixture[:scenario_rows]
    @test length(scenarios) == 4
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "balanced_group_crossed",
        "sparse_rater_group_cells",
        "empty_and_confounded_group_cells",
        "unknown_group_facet_rejected",
    ])
    @test all(row -> Bool(row[:summary][:passed]), scenarios)
    @test all(row -> Bool(row[:summary][:outcome_matches]), scenarios)
    @test all(row -> Bool(row[:summary][:validation_only_ok]), scenarios)

    balanced = only(row for row in scenarios
        if String(row[:scenario]) == "balanced_group_crossed")
    @test Bool(balanced[:validation][:passed])
    @test Int(balanced[:validation][:n_issues]) == 0
    @test String(balanced[:expected_support]) == "screening_supported"
    @test all(row -> String(row[:support]) == "screening_supported",
        balanced[:term_support])
    @test Bool(balanced[:spec_constraints][:spec_constructed])
    @test Bool(balanced[:spec_constraints][:all_dff_terms_validation_only])
    @test Set(String(block) for block in
        balanced[:spec_constraints][:validation_only_blocks]) == Set([
            "dff_item_group",
            "dff_rater_group",
            "dff_rater_item",
        ])

    sparse = only(row for row in scenarios
        if String(row[:scenario]) == "sparse_rater_group_cells")
    sparse_codes = Set(String(row[:code]) for row in sparse[:validation][:issue_counts])
    @test Bool(sparse[:validation][:passed])
    @test sparse_codes == Set(["sparse_dff_cell"])
    @test any(row -> String(row[:support]) == "sparse_screening_only",
        sparse[:term_support])

    empty = only(row for row in scenarios
        if String(row[:scenario]) == "empty_and_confounded_group_cells")
    empty_codes = Set(String(row[:code]) for row in empty[:validation][:issue_counts])
    @test Bool(empty[:validation][:passed])
    @test empty_codes == Set([
        "empty_dff_cell",
        "potential_dff_confounding",
        "sparse_dff_cell",
    ])
    @test any(row -> String(row[:support]) == "not_unpooled_estimable",
        empty[:term_support])

    unknown = only(row for row in scenarios
        if String(row[:scenario]) == "unknown_group_facet_rejected")
    unknown_codes =
        Set(String(row[:code]) for row in unknown[:validation][:issue_counts])
    @test Bool(unknown[:validation][:passed]) == false
    @test unknown_codes == Set(["unknown_bias_facet"])
    @test Bool(unknown[:spec_constraints][:spec_constructed]) == false

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_validation_only"
    @test Bool(decision[:dff_model_effects_allowed]) == false
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "dff_estimands_predeclared_validation_only"
    @test String(decision[:interpretation]) ==
        "dff_estimand_validation_grid_recorded_keep_model_effects_blocked"
    @test String(decision[:required_followup]) ==
        "manuscript_scale_simulation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Int(summary[:n_estimands]) == length(estimands)
    @test Int(summary[:n_predeclared_reporting_scales]) == 2
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_validation_passed_scenarios]) == 3
    @test Int(summary[:n_validation_error_scenarios]) == 1
    @test Int(summary[:n_sparse_warning_scenarios]) >= 1
    @test Int(summary[:n_empty_warning_scenarios]) >= 1
    @test Int(summary[:n_confounding_warning_scenarios]) >= 1
    @test Bool(summary[:all_expected_outcomes_matched])
    @test Bool(summary[:all_valid_dff_terms_retained_as_validation_only])
    @test Bool(summary[:all_estimands_predeclared])
    @test Bool(summary[:all_reporting_scales_predeclared])
    @test Bool(summary[:dff_model_effects_allowed]) == false
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "manuscript_scale_simulation_grid_missing",
            "full_paper_reproduction_archive_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_dff_validation_only_until_gate_e_and_archive_evidence"
    @test String(summary[:next_gate]) == "manuscript_scale_simulation_grid"
end

function check_gmfrm_manuscript_scale_simulation_grid_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_manuscript_scale_simulation_grid.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "manuscript_scale_simulation_grid"
    @test String(fixture[:status]) ==
        "manuscript_scale_simulation_grid_recorded"
    @test String(fixture[:decision]) ==
        "full_archive_recorded_keep_guarded_scalar_gmfrm_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false
    @test Bool(fixture[:manuscript_claims_allowed]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_manuscript_scale_simulation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_manuscript_scale_simulation_evidence_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:decision_target]) ==
        "gate_e_broader_generalized_claim_evidence"
    @test Bool(thresholds[:require_all_input_artifacts_present])
    @test Bool(thresholds[:require_all_expected_schemas])
    @test Bool(thresholds[:require_all_input_summaries_passed])
    @test Bool(thresholds[:require_scalar_fit_validation_grid_passed])
    @test Bool(thresholds[:require_posterior_predictive_grid_passed])
    @test Bool(thresholds[:require_sparse_pathology_recovery_grid_passed])
    @test Bool(thresholds[:require_prior_likelihood_sensitivity_grid_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])
    @test Bool(thresholds[:require_claim_archive_recorded])
    @test Bool(thresholds[:require_broader_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_dff_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_full_paper_reproduction_archive_passed])
    @test Int(thresholds[:require_minimum_total_evidence_cells]) == 60
    @test Bool(thresholds[:require_no_publication_commands])
    @test Bool(thresholds[:require_full_archive_before_claims]) == false

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "experimental_fit_validation_grid" =>
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        "posterior_predictive_grid" =>
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        "sparse_pathology_recovery_grid" =>
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        "prior_likelihood_sensitivity_grid" =>
            "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        "real_data_case_study" =>
            "test/fixtures/gmfrm_real_data_case_study.json",
        "claim_recovery_reproduction_archive" =>
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        "broader_experimental_exposure_decision_review" =>
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "full_paper_reproduction_archive" =>
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
    )
    @test length(input_artifacts) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test Bool(row[:summary][:all_primary_checks])
        if String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, String(row[:path])))
        else
            @test String(row[:hash_policy]) in (
                "existence_only_avoids_dry_run_claim_manuscript_grid_cycle",
                "existence_only_avoids_broader_review_manuscript_grid_cycle")
            @test isnothing(row[:sha256])
        end
    end

    evidence_rows = fixture[:evidence_rows]
    @test length(evidence_rows) == length(input_artifacts)
    @test all(row -> String(row[:status]) == "passed", evidence_rows)
    @test Int(sum(Int(row[:n_evidence_cells]) for row in evidence_rows)) == 136
    @test any(row -> String(row[:gate]) == "prior_likelihood_sensitivity_grid" &&
        Int(row[:n_evidence_cells]) == 45, evidence_rows)
    @test any(row -> String(row[:gate]) ==
        "prediction_target_and_model_weight_policy" &&
        Int(row[:n_evidence_cells]) == 6, evidence_rows)

    decisions = fixture[:claim_decision_rows]
    @test length(decisions) == 4
    @test any(row -> String(row[:claim]) == "guarded_scalar_gmfrm_fit" &&
        Bool(row[:public_claim_allowed]), decisions)
    @test any(row -> String(row[:claim]) ==
        "model_weights_or_sparse_mgmfrm_superiority" &&
        String(row[:decision]) ==
            "policy_recorded_keep_blocked_until_public_scope_review" &&
        String(row[:required_followup]) ==
            "manual_public_scope_review_for_mgmfrm_fit", decisions)
    @test all(row -> String(row[:claim]) == "guarded_scalar_gmfrm_fit" ||
        Bool(row[:public_claim_allowed]) == false, decisions)

    blockers = fixture[:blocker_rows]
    @test isempty(blockers)

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) ==
        "full_archive_recorded_keep_guarded_scalar_gmfrm_only"
    @test Bool(decision[:scalar_guarded_fit_allowed])
    @test Bool(decision[:broader_generalized_fit_allowed]) == false
    @test Bool(decision[:manuscript_claims_allowed]) == false
    @test String(decision[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:all_primary_checks_passed])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_evidence_rows]) == length(evidence_rows)
    @test Int(summary[:total_evidence_cells]) == 136
    @test Int(summary[:minimum_required_evidence_cells]) == 60
    @test Bool(summary[:scalar_fit_validation_grid_passed])
    @test Bool(summary[:posterior_predictive_grid_passed])
    @test Bool(summary[:sparse_pathology_recovery_grid_passed])
    @test Bool(summary[:prior_likelihood_sensitivity_grid_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:broader_experimental_exposure_decision_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:full_paper_reproduction_archive_passed])
    @test Bool(summary[:manuscript_claims_allowed]) == false
    @test Bool(summary[:no_publication_commands])
    @test Int(summary[:n_blockers]) == 0
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "full_archive_recorded_keep_broader_claims_manual_review"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end

function check_gmfrm_broader_experimental_exposure_decision_review_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_broader_experimental_exposure_decision_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "broader_generalized_exposure_decision"
    @test String(fixture[:status]) ==
        "broader_experimental_exposure_decision_review_recorded"
    @test String(fixture[:decision]) == "keep_guarded_scalar_gmfrm_only"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_broader_experimental_exposure_decision_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_broader_experimental_exposure_decision"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint_under_review]) ==
        "fit(spec; experimental = true)"
    @test Bool(thresholds[:require_guarded_exposure_review_passed])
    @test Bool(thresholds[:require_claim_recovery_reproduction_archive_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])
    @test Bool(thresholds[:require_mgmfrm_bridge_oracle_present])
    @test Bool(thresholds[:require_mgmfrm_candidate_chain_study_passed])
    @test Bool(thresholds[:require_mgmfrm_recovery_smoke_passed])
    @test Bool(thresholds[:require_mgmfrm_baseline_comparison_passed])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:require_manuscript_scale_simulation_grid_passed])
    @test Bool(thresholds[:require_full_paper_reproduction_archive_passed])
    @test Bool(thresholds[:require_scalar_guarded_fit_kept_enabled])
    @test Bool(thresholds[:require_mgmfrm_fit_kept_internal])
    @test Bool(thresholds[:require_broader_generalized_fit_blocked])
    @test Bool(thresholds[:require_dff_model_effects_blocked])
    @test Bool(thresholds[:require_model_weights_blocked])
    @test Bool(thresholds[:require_manuscript_claims_blocked])
    @test Bool(thresholds[:require_no_publication_commands])

    input_artifacts = fixture[:input_artifacts]
    @test length(input_artifacts) == 16
    expected_paths = Dict(
        "guarded_exposure_review" =>
            "test/fixtures/gmfrm_guarded_exposure_review.json",
        "claim_recovery_reproduction_archive" =>
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        "real_data_case_study" =>
            "test/fixtures/gmfrm_real_data_case_study.json",
        "mgmfrm_candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "mgmfrm_recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "mgmfrm_baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "mgmfrm_guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        "mgmfrm_guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        "mgmfrm_guarded_fit_public_exposure_review" =>
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "manuscript_scale_simulation_grid" =>
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        "full_paper_reproduction_archive" =>
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        "mgmfrm_bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
    )
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test expected_paths[artifact] == String(row[:path])
        if artifact == "guarded_exposure_review"
            @test String(row[:hash_policy]) ==
                "existence_only_avoids_broader_review_guarded_exposure_cycle"
            @test isnothing(row[:sha256])
        else
            @test String(row[:hash_policy]) == "sha256"
            @test String(row[:sha256]) ==
                file_sha256(joinpath(root, String(row[:path])))
        end
    end

    decisions = fixture[:scope_decision_rows]
    @test length(decisions) == 6
    scalar = only(row for row in decisions
        if String(row[:surface]) == "scalar_gmfrm_guarded_fit")
    @test String(scalar[:decision]) == "keep_enabled_guarded_experimental"
    @test Bool(scalar[:evidence])
    @test Bool(scalar[:public_fit])
    mgmfrm = only(row for row in decisions
        if String(row[:surface]) == "confirmatory_mgmfrm_fit")
    @test String(mgmfrm[:decision]) == "keep_internal"
    @test Bool(mgmfrm[:evidence])
    @test Bool(mgmfrm[:public_fit]) == false
    @test String(mgmfrm[:next_required_evidence]) ==
        "manual_public_scope_review_for_mgmfrm_fit"
    dff_surface = only(row for row in decisions
        if String(row[:surface]) == "dff_model_effects")
    @test String(dff_surface[:decision]) == "keep_blocked"
    @test Bool(dff_surface[:evidence])
    @test Bool(dff_surface[:public_fit]) == false
    @test String(dff_surface[:next_required_evidence]) ==
        "future_dff_model_effect_fit_policy"
    @test any(row -> String(row[:surface]) == "loo_or_stacking_model_weights" &&
        String(row[:decision]) == "policy_recorded_keep_public_claims_blocked" &&
        Bool(row[:evidence]) &&
        Bool(row[:public_fit]) == false, decisions)

    blockers = fixture[:blocker_rows]
    expected_blockers = Set{String}()
    @test isempty(blockers)

    cycle_breaks = fixture[:cycle_break_references]
    @test length(cycle_breaks) == 1
    @test String(cycle_breaks[1][:artifact]) ==
        "test/fixtures/gmfrm_guarded_exposure_review.json"
    @test String(cycle_breaks[1][:hash_policy]) == "existence_only"

    decision = fixture[:decision_record]
    @test Bool(decision[:scalar_guarded_fit_allowed])
    @test Bool(decision[:broader_generalized_fit_allowed]) == false
    @test String(decision[:public_exposure_support]) ==
        "guarded_scalar_gmfrm_only"
    @test String(decision[:interpretation]) ==
        "broader_exposure_review_recorded_full_archive_available_keep_broader_claims_blocked"
    @test String(decision[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_required_inputs_passed])
    @test Bool(summary[:guarded_exposure_review_passed])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:mgmfrm_bridge_oracle_present])
    @test Bool(summary[:mgmfrm_candidate_chain_study_passed])
    @test Bool(summary[:mgmfrm_recovery_smoke_passed])
    @test Bool(summary[:mgmfrm_baseline_comparison_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:manuscript_scale_simulation_grid_passed])
    @test Bool(summary[:full_paper_reproduction_archive_passed])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_scope_decisions]) == length(decisions)
    @test Int(summary[:n_risk_rows]) == length(fixture[:risk_rows])
    @test Int(summary[:n_blockers]) == length(blockers)
    @test Bool(summary[:scalar_guarded_fit_allowed])
    @test Bool(summary[:broader_generalized_fit_allowed]) == false
    @test Bool(summary[:mgmfrm_fit_allowed]) == false
    @test Bool(summary[:dff_model_effects_allowed]) == false
    @test Bool(summary[:model_weights_allowed]) == false
    @test Bool(summary[:manuscript_claims_allowed]) == false
    @test Bool(summary[:no_publication_commands])
    @test isempty(summary[:remaining_public_blockers])
    @test String(summary[:recommendation]) ==
        "full_archive_recorded_keep_guarded_scalar_gmfrm_only"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end

function check_gmfrm_guarded_exposure_review_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.gmfrm_guarded_exposure_review.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) == "scalar_gmfrm_fit_ready_candidate"
    @test String(fixture[:status]) == "guarded_exposure_review_recorded"
    @test String(fixture[:decision]) == "enable_guarded_experimental"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "scalar_gmfrm_guarded_exposure_review_v1"
    @test String(protocol[:review_kind]) == "local_guarded_exposure_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test String(protocol[:entrypoint_under_review]) == "fit(spec; experimental = true)"
    @test Bool(thresholds[:require_candidate_chain_passed])
    @test Bool(thresholds[:require_stress_chain_grid_passed])
    @test Bool(thresholds[:require_recovery_smoke_passed])
    @test Bool(thresholds[:require_baseline_comparison_passed])
    @test Bool(thresholds[:require_baseline_calibration_grid_passed])
    @test Bool(thresholds[:require_interval_decision_grid_passed])
    @test Bool(thresholds[:require_sparse_design_grid_passed])
    @test Bool(thresholds[:require_waic_influence_review_passed])
    @test Bool(thresholds[:require_psis_loo_review_passed])
    @test Bool(thresholds[:require_exact_loo_or_kfold_review_passed])
    @test Bool(thresholds[:require_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_experimental_fit_validation_grid_passed])
    @test Bool(thresholds[:require_posterior_predictive_grid_passed])
    @test Bool(thresholds[:require_sparse_pathology_recovery_grid_passed])
    @test Bool(thresholds[:require_prior_likelihood_sensitivity_grid_passed])
    @test Bool(thresholds[:require_real_data_case_study_passed])
    @test Bool(thresholds[:require_claim_recovery_reproduction_archive_passed])
    @test Bool(thresholds[:require_broader_experimental_exposure_decision_review_passed])
    @test Bool(thresholds[:require_mgmfrm_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_policy_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:high_variance_waic_blocks_public_exposure])
    @test Bool(thresholds[:psis_loo_or_exact_loo_required_before_exposure])
    @test Bool(thresholds[:high_pareto_k_blocks_public_exposure])
    @test Bool(thresholds[:exact_loo_or_kfold_required_before_exposure])
    @test Bool(thresholds[:guarded_fit_api_dry_run_required_before_exposure])
    @test Bool(thresholds[:guarded_fit_method_wiring_required_before_exposure])
    @test Bool(thresholds[:experimental_fit_validation_grid_required_before_exposure])
    @test Bool(thresholds[:posterior_predictive_grid_required_before_exposure])
    @test Bool(thresholds[:sparse_pathology_recovery_grid_required_before_exposure])
    @test Bool(thresholds[:prior_likelihood_sensitivity_grid_required_before_exposure])
    @test Bool(thresholds[:real_data_case_study_required_before_exposure])
    @test Bool(thresholds[:claim_level_recovery_and_reproduction_archive_required_before_exposure])
    @test Bool(thresholds[:broader_experimental_exposure_decision_review_required_before_exposure])

    reviewed = fixture[:reviewed_artifacts]
    @test length(reviewed) == 28
    expected_artifacts = Dict(
        "candidate_chain_study" =>
            "test/fixtures/gmfrm_candidate_chain_study.json",
        "stress_chain_grid" =>
            "test/fixtures/gmfrm_stress_chain_grid.json",
        "recovery_smoke_study" =>
            "test/fixtures/gmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/gmfrm_baseline_comparison.json",
        "baseline_calibration_grid" =>
            "test/fixtures/gmfrm_baseline_calibration_grid.json",
        "interval_decision_grid" =>
            "test/fixtures/gmfrm_interval_decision_grid.json",
        "sparse_design_grid" =>
            "test/fixtures/gmfrm_sparse_design_grid.json",
        "waic_influence_review" =>
            "test/fixtures/gmfrm_waic_influence_review.json",
        "psis_loo_review" =>
            "test/fixtures/gmfrm_psis_loo_review.json",
        "exact_loo_or_kfold_review" =>
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        "experimental_fit_validation_grid" =>
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        "posterior_predictive_grid" =>
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        "sparse_pathology_recovery_grid" =>
            "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        "prior_likelihood_sensitivity_grid" =>
            "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        "real_data_case_study" =>
            "test/fixtures/gmfrm_real_data_case_study.json",
        "claim_recovery_reproduction_archive" =>
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        "broader_experimental_exposure_decision_review" =>
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "mgmfrm_guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        "mgmfrm_guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        "mgmfrm_guarded_fit_public_exposure_review" =>
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        "prediction_target_and_model_weight_policy" =>
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        "manuscript_scale_simulation_grid" =>
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        "full_paper_reproduction_archive" =>
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
    )
    @test Set(String(row[:artifact]) for row in reviewed) ==
        Set(keys(expected_artifacts))
    for row in reviewed
        artifact = String(row[:artifact])
        path = String(row[:path])
        @test expected_artifacts[artifact] == path
        @test String(row[:sha256]) == file_sha256(joinpath(root, path))
        if artifact in ("mgmfrm_sparse_recovery_grid",
                "mgmfrm_guarded_fit_method_wiring",
                "mgmfrm_guarded_fit_validation_grid",
                "mgmfrm_guarded_fit_api_dry_run",
                "mgmfrm_guarded_fit_public_exposure_review")
            @test String(row[:family]) == "mgmfrm"
            @test String(row[:scope]) ==
                "minimal_confirmatory_mgmfrm_candidate"
        elseif artifact == "dff_estimand_validation_grid"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) ==
                "dff_estimand_and_validation_grid"
        elseif artifact == "prediction_target_and_model_weight_policy"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) ==
                "prediction_target_and_model_weight_policy"
        elseif artifact == "manuscript_scale_simulation_grid"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "manuscript_scale_simulation_grid"
        elseif artifact == "full_paper_reproduction_archive"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "full_paper_reproduction_archive"
        elseif artifact == "broader_experimental_exposure_decision_review"
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "broader_generalized_exposure_decision"
        else
            @test String(row[:family]) == "gmfrm"
            @test String(row[:scope]) == "scalar_gmfrm_fit_ready_candidate"
        end
        if artifact in (
                "guarded_fit_method_wiring",
                "experimental_fit_validation_grid",
                "posterior_predictive_grid",
                "sparse_pathology_recovery_grid",
                "prior_likelihood_sensitivity_grid",
                "real_data_case_study",
                "claim_recovery_reproduction_archive",
                "broader_experimental_exposure_decision_review",
                "prediction_target_and_model_weight_policy",
                "manuscript_scale_simulation_grid",
                "full_paper_reproduction_archive")
            @test Bool(row[:public_fit])
            @test Bool(row[:experimental_public])
            @test Bool(row[:fit_ready])
        else
            @test Bool(row[:public_fit]) == false
            @test Bool(row[:fit_ready]) == false
        end
    end

    chain = only(row for row in reviewed
        if String(row[:artifact]) == "candidate_chain_study")
    @test Bool(chain[:summary][:overall_passed])
    @test Int(chain[:summary][:n_divergences]) == 0
    @test Int(chain[:summary][:n_max_treedepth]) == 0
    stress = only(row for row in reviewed
        if String(row[:artifact]) == "stress_chain_grid")
    @test Bool(stress[:summary][:overall_passed])
    @test Int(stress[:summary][:n_scenarios]) == 3
    recovery = only(row for row in reviewed
        if String(row[:artifact]) == "recovery_smoke_study")
    @test Bool(recovery[:summary][:passed])
    @test String(recovery[:summary][:sampler_flag]) == "ok"
    baseline = only(row for row in reviewed
        if String(row[:artifact]) == "baseline_comparison")
    @test Bool(baseline[:summary][:passed])
    @test Bool(baseline[:summary][:any_high_variance_waic])
    grid = only(row for row in reviewed
        if String(row[:artifact]) == "baseline_calibration_grid")
    @test Bool(grid[:summary][:passed])
    @test Int(grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(grid[:summary][:any_high_variance_waic])
    interval_grid = only(row for row in reviewed
        if String(row[:artifact]) == "interval_decision_grid")
    @test Bool(interval_grid[:summary][:passed])
    @test Int(interval_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(interval_grid[:summary][:keep_internal_decision_count]) == 3
    @test String(interval_grid[:summary][:decision_stability]) ==
        "stable_keep_internal"
    @test Bool(interval_grid[:summary][:any_high_variance_waic])
    sparse_grid = only(row for row in reviewed
        if String(row[:artifact]) == "sparse_design_grid")
    @test Bool(sparse_grid[:summary][:passed])
    @test Int(sparse_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(sparse_grid[:summary][:n_sparse_validation_records]) == 3
    @test Bool(sparse_grid[:summary][:all_sparse_validations_passed])
    @test Bool(sparse_grid[:summary][:all_location_designs_full_rank])
    @test Int(sparse_grid[:summary][:keep_internal_decision_count]) == 3
    @test String(sparse_grid[:summary][:decision_stability]) ==
        "stable_keep_internal"
    @test String(sparse_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_waic_influence_review"
    waic_review = only(row for row in reviewed
        if String(row[:artifact]) == "waic_influence_review")
    @test Bool(waic_review[:summary][:passed])
    @test Int(waic_review[:summary][:n_scenario_reviews]) == 6
    @test Int(waic_review[:summary][:n_passed_scenarios]) == 6
    @test Int(waic_review[:summary][:n_flagged_model_observations]) > 0
    @test Int(waic_review[:summary][:n_best_model_changes_after_flagged_removal]) >= 1
    @test Bool(waic_review[:summary][:all_masked_comparisons_finite])
    @test String(waic_review[:summary][:next_gate]) ==
        "scalar_gmfrm_psis_loo_review"
    psis_review = only(row for row in reviewed
        if String(row[:artifact]) == "psis_loo_review")
    @test Bool(psis_review[:summary][:passed])
    @test Int(psis_review[:summary][:n_scenario_reviews]) == 6
    @test Int(psis_review[:summary][:n_passed_scenarios]) == 6
    @test Int(psis_review[:summary][:n_high_pareto_model_observations]) > 0
    @test Float64(psis_review[:summary][:max_pareto_k]) > 0.7
    @test Bool(psis_review[:summary][:all_loo_comparisons_finite])
    @test Bool(psis_review[:summary][:any_high_pareto_k])
    @test Bool(psis_review[:summary][:psis_smoothing_enabled]) == false
    @test String(psis_review[:summary][:next_gate]) ==
        "scalar_gmfrm_exact_loo_or_kfold_review"
    exact_review = only(row for row in reviewed
        if String(row[:artifact]) == "exact_loo_or_kfold_review")
    @test Bool(exact_review[:summary][:passed])
    @test Int(exact_review[:summary][:n_scenario_reviews]) == 6
    @test Int(exact_review[:summary][:n_passed_scenarios]) == 6
    @test Int(exact_review[:summary][:n_fold_model_records]) == 54
    @test Bool(exact_review[:summary][:all_observations_held_out_once])
    @test Bool(exact_review[:summary][:all_parameter_orders_matched])
    @test Bool(exact_review[:summary][:all_samplers_passed])
    @test Bool(exact_review[:summary][:all_kfold_comparisons_finite])
    @test String(exact_review[:summary][:next_gate]) ==
        "scalar_gmfrm_guarded_fit_api_dry_run"
    dry_run = only(row for row in reviewed
        if String(row[:artifact]) == "guarded_fit_api_dry_run")
    @test Bool(dry_run[:summary][:passed])
    @test Bool(dry_run[:summary][:dry_run_only])
    @test Bool(dry_run[:summary][:publication_or_registration_action]) == false
    @test Bool(dry_run[:summary][:entrypoint_enabled]) == false
    @test Bool(dry_run[:summary][:superseded_by_guarded_fit_method_wiring])
    @test Bool(dry_run[:summary][:public_fit_allowed]) == false
    @test Bool(dry_run[:summary][:experimental_keyword_enabled]) == false
    @test Bool(dry_run[:summary][:current_manifest_fit_allowed])
    @test Bool(dry_run[:summary][:current_manifest_experimental_keyword_enabled])
    @test Bool(dry_run[:summary][:fit_rejects_specified_only_gmfrm])
    @test Bool(dry_run[:summary][:fit_preview_rejects_experimental_keyword])
    @test Bool(dry_run[:summary][:artifact_contract_recorded])
    @test Bool(dry_run[:summary][:all_required_artifact_fields_recorded])
    @test Bool(dry_run[:summary][:all_required_provenance_artifacts_recorded])
    @test Bool(dry_run[:summary][:all_file_evidence_present])
    @test Bool(dry_run[:summary][:target_logdensity_finite])
    @test Bool(dry_run[:summary][:target_diagnostics_passed])
    @test Bool(dry_run[:summary][:superseded_by_real_data_case_study])
    @test Bool(dry_run[:summary][:superseded_by_claim_recovery_reproduction_archive])
    @test Bool(dry_run[:summary][:superseded_by_broader_experimental_exposure_decision_review])
    @test Bool(dry_run[:summary][:superseded_by_full_paper_reproduction_archive])
    @test String(dry_run[:summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
    method_wiring = only(row for row in reviewed
        if String(row[:artifact]) == "guarded_fit_method_wiring")
    @test Bool(method_wiring[:summary][:passed])
    @test Bool(method_wiring[:summary][:publication_or_registration_action]) == false
    @test Bool(method_wiring[:summary][:entrypoint_enabled])
    @test Bool(method_wiring[:summary][:public_fit_allowed])
    @test Bool(method_wiring[:summary][:experimental_keyword_enabled])
    @test Bool(method_wiring[:summary][:gmfrm_fit_returned])
    @test Bool(method_wiring[:summary][:artifact_contract_satisfied])
    @test Bool(method_wiring[:summary][:pointwise_loglikelihood_shape_valid])
    @test Bool(method_wiring[:summary][:waic_and_loo_finite])
    @test Bool(method_wiring[:summary][:all_unsupported_public_options_rejected])
    @test String(method_wiring[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    validation_grid = only(row for row in reviewed
        if String(row[:artifact]) == "experimental_fit_validation_grid")
    @test Bool(validation_grid[:summary][:passed])
    @test Bool(validation_grid[:summary][:publication_or_registration_action]) == false
    @test Int(validation_grid[:summary][:n_scenarios]) == 3
    @test Int(validation_grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(validation_grid[:summary][:all_guarded_fit_returned])
    @test Bool(validation_grid[:summary][:all_artifact_contracts_satisfied])
    @test Bool(validation_grid[:summary][:all_pointwise_shapes_valid])
    @test Bool(validation_grid[:summary][:all_information_criteria_finite])
    @test Bool(validation_grid[:summary][:all_no_divergences])
    @test Bool(validation_grid[:summary][:all_no_max_treedepth])
    @test Bool(validation_grid[:summary][:all_no_failed_direct_constraints])
    @test String(validation_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    posterior_predictive_grid = only(row for row in reviewed
        if String(row[:artifact]) == "posterior_predictive_grid")
    @test Bool(posterior_predictive_grid[:summary][:passed])
    @test Bool(posterior_predictive_grid[:summary][:publication_or_registration_action]) == false
    @test Int(posterior_predictive_grid[:summary][:n_scenarios]) == 3
    @test Int(posterior_predictive_grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(posterior_predictive_grid[:summary][:all_ppc_returned])
    @test Bool(posterior_predictive_grid[:summary][:all_replicated_scores_in_categories])
    @test Bool(posterior_predictive_grid[:summary][:all_probability_sums_valid])
    @test Bool(posterior_predictive_grid[:summary][:all_summary_rows_finite])
    @test Bool(posterior_predictive_grid[:summary][:all_calibration_rows_finite])
    @test Bool(posterior_predictive_grid[:summary][:all_mean_scores_inside_interval])
    @test String(posterior_predictive_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    sparse_pathology_grid = only(row for row in reviewed
        if String(row[:artifact]) == "sparse_pathology_recovery_grid")
    @test Bool(sparse_pathology_grid[:summary][:passed])
    @test Bool(sparse_pathology_grid[:summary][:publication_or_registration_action]) == false
    @test Int(sparse_pathology_grid[:summary][:n_scenarios]) == 3
    @test Int(sparse_pathology_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(sparse_pathology_grid[:summary][:n_replicates_per_scenario]) == 24
    @test Bool(sparse_pathology_grid[:summary][:all_validations_passed])
    @test Bool(sparse_pathology_grid[:summary][:all_location_designs_full_rank])
    @test Bool(sparse_pathology_grid[:summary][:all_guarded_fit_returned])
    @test Bool(sparse_pathology_grid[:summary][:all_pointwise_shapes_valid])
    @test Bool(sparse_pathology_grid[:summary][:all_information_criteria_finite])
    @test Bool(sparse_pathology_grid[:summary][:all_no_divergences])
    @test Bool(sparse_pathology_grid[:summary][:all_no_max_treedepth])
    @test Bool(sparse_pathology_grid[:summary][:all_no_failed_direct_constraints])
    @test Bool(sparse_pathology_grid[:summary][:all_ppc_returned])
    @test Bool(sparse_pathology_grid[:summary][:all_replicated_scores_in_categories])
    @test Bool(sparse_pathology_grid[:summary][:all_probability_sums_valid])
    @test Bool(sparse_pathology_grid[:summary][:all_summary_rows_finite])
    @test Bool(sparse_pathology_grid[:summary][:all_calibration_rows_finite])
    @test String(sparse_pathology_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_prior_likelihood_sensitivity_grid"
    prior_likelihood_grid = only(row for row in reviewed
        if String(row[:artifact]) == "prior_likelihood_sensitivity_grid")
    @test Bool(prior_likelihood_grid[:summary][:passed])
    @test Bool(prior_likelihood_grid[:summary][:publication_or_registration_action]) == false
    @test Int(prior_likelihood_grid[:summary][:n_scenarios]) == 3
    @test Int(prior_likelihood_grid[:summary][:n_passed_scenarios]) == 3
    @test Int(prior_likelihood_grid[:summary][:n_sensitivity_cells]) == 45
    @test Int(prior_likelihood_grid[:summary][:n_prior_profiles]) == 5
    @test Int(prior_likelihood_grid[:summary][:n_likelihood_powers]) == 3
    @test Bool(prior_likelihood_grid[:summary][:all_cells_finite])
    @test Bool(prior_likelihood_grid[:summary][:all_baseline_identity])
    @test Float64(prior_likelihood_grid[:summary][:min_weight_ess_rate]) >= 0.05
    @test Float64(prior_likelihood_grid[:summary][:max_weight]) <= 1.0
    @test Float64(prior_likelihood_grid[:summary][:max_direct_parameter_mean_shift]) <= 3.0
    @test Float64(prior_likelihood_grid[:summary][:max_direct_block_mean_shift]) <= 2.0
    @test Float64(prior_likelihood_grid[:summary][:max_expected_score_shift]) <= 1.25
    @test Float64(prior_likelihood_grid[:summary][:max_top_category_probability_shift]) <= 0.60
    @test Float64(prior_likelihood_grid[:summary][:max_loglikelihood_mean_shift]) <= 20.0
    @test Float64(prior_likelihood_grid[:summary][:max_logposterior_decomposition_error]) <=
        1.0e-8
    @test String(prior_likelihood_grid[:summary][:next_gate]) ==
        "scalar_gmfrm_real_data_case_study"
    real_data_case_study = only(row for row in reviewed
        if String(row[:artifact]) == "real_data_case_study")
    @test Bool(real_data_case_study[:summary][:passed])
    @test Bool(real_data_case_study[:summary][:publication_or_registration_action]) == false
    @test Int(real_data_case_study[:summary][:n_cases]) == 2
    @test Int(real_data_case_study[:summary][:n_passed_cases]) == 2
    @test Int(real_data_case_study[:summary][:n_observations_total]) == 72
    @test Int(real_data_case_study[:summary][:n_replicates_per_case]) == 24
    @test Bool(real_data_case_study[:summary][:all_source_files_available])
    @test Bool(real_data_case_study[:summary][:all_validations_passed])
    @test Bool(real_data_case_study[:summary][:all_complete_crossing])
    @test Bool(real_data_case_study[:summary][:all_guarded_fit_returned])
    @test Bool(real_data_case_study[:summary][:all_baseline_fits_returned])
    @test Bool(real_data_case_study[:summary][:all_pointwise_shapes_valid])
    @test Bool(real_data_case_study[:summary][:all_information_criteria_finite])
    @test Bool(real_data_case_study[:summary][:all_model_comparisons_finite])
    @test Bool(real_data_case_study[:summary][:all_no_divergences])
    @test Bool(real_data_case_study[:summary][:all_no_max_treedepth])
    @test Bool(real_data_case_study[:summary][:all_no_failed_direct_constraints])
    @test Bool(real_data_case_study[:summary][:all_no_nonfinite_logdensity])
    @test Bool(real_data_case_study[:summary][:all_no_nonfinite_direct_loglikelihood])
    @test Bool(real_data_case_study[:summary][:all_ppc_returned])
    @test Bool(real_data_case_study[:summary][:all_replicated_scores_in_categories])
    @test Bool(real_data_case_study[:summary][:all_probability_sums_valid])
    @test Bool(real_data_case_study[:summary][:all_summary_rows_finite])
    @test Bool(real_data_case_study[:summary][:all_calibration_rows_finite])
    @test String(real_data_case_study[:summary][:next_gate]) ==
        "claim_level_recovery_and_reproduction_archive"
    claim_archive = only(row for row in reviewed
        if String(row[:artifact]) == "claim_recovery_reproduction_archive")
    @test Bool(claim_archive[:summary][:passed])
    @test Bool(claim_archive[:summary][:publication_or_registration_action]) == false
    @test Bool(claim_archive[:summary][:local_only])
    @test Int(claim_archive[:summary][:n_fixture_artifacts]) == 18
    @test Int(claim_archive[:summary][:n_source_records]) == 2
    @test Int(claim_archive[:summary][:n_code_doc_records]) == 13
    @test Int(claim_archive[:summary][:n_full_regeneration_commands]) == 19
    @test Int(claim_archive[:summary][:n_verification_commands]) == 4
    @test Bool(claim_archive[:summary][:all_fixture_artifacts_present])
    @test Bool(claim_archive[:summary][:all_expected_schemas])
    @test Bool(claim_archive[:summary][:all_fixture_summaries_passed])
    @test Bool(claim_archive[:summary][:all_generator_scripts_present])
    @test Bool(claim_archive[:summary][:all_code_doc_references_present])
    @test Bool(claim_archive[:summary][:all_external_sources_present])
    @test Bool(claim_archive[:summary][:all_commands_local_only])
    @test Bool(claim_archive[:summary][:no_publication_commands])
    @test Bool(claim_archive[:summary][:guarded_exposure_review_passed])
    @test Bool(claim_archive[:summary][:real_data_case_study_passed])
    @test String(claim_archive[:summary][:next_gate]) ==
        "broader_experimental_exposure_decision_review"
    broader_review = only(row for row in reviewed
        if String(row[:artifact]) == "broader_experimental_exposure_decision_review")
    @test Bool(broader_review[:summary][:passed])
    @test Bool(broader_review[:summary][:publication_or_registration_action]) == false
    @test Bool(broader_review[:summary][:local_only])
    @test Bool(broader_review[:summary][:all_input_artifacts_present])
    @test Bool(broader_review[:summary][:all_expected_schemas])
    @test Bool(broader_review[:summary][:all_required_inputs_passed])
    @test Bool(broader_review[:summary][:guarded_exposure_review_passed])
    @test Bool(broader_review[:summary][:claim_recovery_reproduction_archive_passed])
    @test Bool(broader_review[:summary][:real_data_case_study_passed])
    @test Bool(broader_review[:summary][:mgmfrm_bridge_oracle_present])
    @test Bool(broader_review[:summary][:mgmfrm_candidate_chain_study_passed])
    @test Bool(broader_review[:summary][:mgmfrm_recovery_smoke_passed])
    @test Bool(broader_review[:summary][:mgmfrm_baseline_comparison_passed])
    @test Bool(broader_review[:summary][:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(broader_review[:summary][:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(broader_review[:summary][:prediction_target_and_model_weight_policy_passed])
    @test Bool(broader_review[:summary][:dff_estimand_validation_grid_passed])
    @test Bool(broader_review[:summary][:manuscript_scale_simulation_grid_passed])
    @test Bool(broader_review[:summary][:full_paper_reproduction_archive_passed])
    @test Int(broader_review[:summary][:n_input_artifacts]) == 16
    @test Int(broader_review[:summary][:n_scope_decisions]) == 6
    @test Int(broader_review[:summary][:n_risk_rows]) == 5
    @test Int(broader_review[:summary][:n_blockers]) == 0
    @test Bool(broader_review[:summary][:scalar_guarded_fit_allowed])
    @test Bool(broader_review[:summary][:broader_generalized_fit_allowed]) == false
    @test Bool(broader_review[:summary][:mgmfrm_fit_allowed]) == false
    @test Bool(broader_review[:summary][:dff_model_effects_allowed]) == false
    @test Bool(broader_review[:summary][:model_weights_allowed]) == false
    @test Bool(broader_review[:summary][:manuscript_claims_allowed]) == false
    @test Bool(broader_review[:summary][:no_publication_commands])
    @test String(broader_review[:summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
    dff_grid = only(row for row in reviewed
        if String(row[:artifact]) == "dff_estimand_validation_grid")
    @test Bool(dff_grid[:summary][:passed])
    @test Bool(dff_grid[:summary][:publication_or_registration_action]) == false
    @test Bool(dff_grid[:summary][:local_only])
    @test Int(dff_grid[:summary][:n_estimands]) == 5
    @test Int(dff_grid[:summary][:n_scenarios]) == 4
    @test Int(dff_grid[:summary][:n_passed_scenarios]) == 4
    @test Int(dff_grid[:summary][:n_validation_error_scenarios]) == 1
    @test Int(dff_grid[:summary][:n_sparse_warning_scenarios]) >= 1
    @test Int(dff_grid[:summary][:n_empty_warning_scenarios]) >= 1
    @test Bool(dff_grid[:summary][:all_expected_outcomes_matched])
    @test Bool(dff_grid[:summary][:all_valid_dff_terms_retained_as_validation_only])
    @test Bool(dff_grid[:summary][:dff_model_effects_allowed]) == false
    @test String(dff_grid[:summary][:next_gate]) ==
        "manuscript_scale_simulation_grid"
    manuscript_grid = only(row for row in reviewed
        if String(row[:artifact]) == "manuscript_scale_simulation_grid")
    @test Bool(manuscript_grid[:summary][:passed])
    @test Bool(manuscript_grid[:summary][:publication_or_registration_action]) == false
    @test Bool(manuscript_grid[:summary][:local_only])
    @test Bool(manuscript_grid[:summary][:all_input_artifacts_present])
    @test Bool(manuscript_grid[:summary][:all_expected_schemas])
    @test Bool(manuscript_grid[:summary][:all_input_summaries_passed])
    @test Bool(manuscript_grid[:summary][:all_primary_checks_passed])
    @test Int(manuscript_grid[:summary][:n_input_artifacts]) == 11
    @test Int(manuscript_grid[:summary][:total_evidence_cells]) == 136
    @test Int(manuscript_grid[:summary][:minimum_required_evidence_cells]) == 60
    @test Bool(manuscript_grid[:summary][:prediction_target_and_model_weight_policy_passed])
    @test Bool(manuscript_grid[:summary][:full_paper_reproduction_archive_passed])
    @test Bool(manuscript_grid[:summary][:manuscript_claims_allowed]) == false
    @test String(manuscript_grid[:summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
    full_archive = only(row for row in reviewed
        if String(row[:artifact]) == "full_paper_reproduction_archive")
    @test Bool(full_archive[:summary][:passed])
    @test Bool(full_archive[:summary][:publication_or_registration_action]) == false
    @test Bool(full_archive[:summary][:local_only])
    @test Bool(full_archive[:summary][:all_fixture_artifacts_present])
    @test Bool(full_archive[:summary][:all_expected_schemas])
    @test Bool(full_archive[:summary][:all_fixture_summaries_passed])
    @test Bool(full_archive[:summary][:all_code_doc_references_present])
    @test Bool(full_archive[:summary][:all_external_sources_present])
    @test Bool(full_archive[:summary][:all_commands_local_only])
    @test Bool(full_archive[:summary][:no_publication_commands])
    @test Int(full_archive[:summary][:n_fixture_artifacts]) == 33
    @test Int(full_archive[:summary][:n_code_doc_records]) == 27
    @test Int(full_archive[:summary][:n_full_regeneration_commands]) == 33
    @test Int(full_archive[:summary][:n_verification_commands]) == 4
    @test Bool(full_archive[:summary][:prediction_target_and_model_weight_policy_passed])
    @test Bool(full_archive[:summary][:manuscript_reproducibility_claims_supported])
    @test Int(full_archive[:summary][:n_blockers]) == 0
    @test String(full_archive[:summary][:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
    mgmfrm_sparse_grid = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_sparse_recovery_grid")
    @test Bool(mgmfrm_sparse_grid[:summary][:passed])
    @test Int(mgmfrm_sparse_grid[:summary][:n_scenarios]) == 3
    @test Int(mgmfrm_sparse_grid[:summary][:n_passed_scenarios]) == 3
    @test Bool(mgmfrm_sparse_grid[:summary][:all_validations_passed])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_location_designs_full_rank])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_parameter_orders_match_reference])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_sampler_passed])
    @test Bool(mgmfrm_sparse_grid[:summary][:all_waic_finite])
    @test Bool(mgmfrm_sparse_grid[:summary][:public_fit_allowed]) == false
    @test String(mgmfrm_sparse_grid[:summary][:next_gate]) ==
        "dff_estimand_and_validation_grid"
    mgmfrm_method = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_method_wiring")
    @test Bool(mgmfrm_method[:summary][:passed])
    @test Bool(mgmfrm_method[:summary][:entrypoint_enabled]) == false
    @test Bool(mgmfrm_method[:summary][:public_fit_allowed]) == false
    @test Bool(mgmfrm_method[:summary][:sampler_protocol_passed])
    @test Bool(mgmfrm_method[:summary][:artifact_contract_satisfied])
    @test Bool(mgmfrm_method[:summary][:all_current_public_fit_attempts_rejected])
    @test String(mgmfrm_method[:summary][:next_gate]) ==
        "mgmfrm_guarded_fit_validation_grid"
    mgmfrm_validation = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_validation_grid")
    @test Bool(mgmfrm_validation[:summary][:passed])
    @test Bool(mgmfrm_validation[:summary][:entrypoint_enabled]) == false
    @test Bool(mgmfrm_validation[:summary][:public_fit_allowed]) == false
    @test Bool(mgmfrm_validation[:summary][:all_validation_rows_passed])
    @test Bool(mgmfrm_validation[:summary][:guarded_fit_method_wiring_passed])
    @test Bool(mgmfrm_validation[:summary][:method_sampler_protocol_passed])
    @test Bool(mgmfrm_validation[:summary][:method_artifact_contract_satisfied])
    @test Bool(mgmfrm_validation[:summary][:method_current_public_fit_attempts_rejected])
    @test String(mgmfrm_validation[:summary][:next_gate]) ==
        "mgmfrm_guarded_fit_api_dry_run"
    mgmfrm_api_dry_run = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_api_dry_run")
    @test Bool(mgmfrm_api_dry_run[:summary][:passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:dry_run_only])
    @test Bool(mgmfrm_api_dry_run[:summary][:entrypoint_enabled]) == false
    @test Bool(mgmfrm_api_dry_run[:summary][:guarded_fit_validation_grid_passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:validation_grid_all_rows_passed])
    @test Bool(mgmfrm_api_dry_run[:summary][:all_current_public_fit_attempts_rejected])
    @test Bool(mgmfrm_api_dry_run[:summary][:artifact_contract_satisfied])
    @test Bool(mgmfrm_api_dry_run[:summary][:target_gradient_diagnostics_passed])
    @test String(mgmfrm_api_dry_run[:summary][:next_gate]) ==
        "mgmfrm_guarded_fit_public_exposure_review"
    mgmfrm_public_review = only(row for row in reviewed
        if String(row[:artifact]) == "mgmfrm_guarded_fit_public_exposure_review")
    @test Bool(mgmfrm_public_review[:summary][:passed])
    @test Bool(mgmfrm_public_review[:summary][:reviewed])
    @test Bool(mgmfrm_public_review[:summary][:publication_or_registration_action]) == false
    @test Bool(mgmfrm_public_review[:summary][:local_only])
    @test Bool(mgmfrm_public_review[:summary][:public_fit_allowed]) == false
    @test Bool(mgmfrm_public_review[:summary][:experimental_keyword_enabled]) == false
    @test Bool(mgmfrm_public_review[:summary][:all_input_artifacts_present])
    @test Bool(mgmfrm_public_review[:summary][:all_expected_schemas])
    @test Bool(mgmfrm_public_review[:summary][:all_input_summaries_passed])
    @test Bool(mgmfrm_public_review[:summary][:all_current_public_fit_attempts_rejected])
    @test Bool(mgmfrm_public_review[:summary][:current_manifest_keeps_internal])
    @test Bool(mgmfrm_public_review[:summary][:no_publication_commands])
    @test Bool(mgmfrm_public_review[:summary][:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(mgmfrm_public_review[:summary][:dff_estimand_validation_grid_passed])
    @test Int(mgmfrm_public_review[:summary][:n_input_artifacts]) == 9
    @test Int(mgmfrm_public_review[:summary][:n_blockers]) == 1
    @test String(mgmfrm_public_review[:summary][:next_gate]) ==
        "prediction_target_and_model_weight_policy"
    prediction_policy = only(row for row in reviewed
        if String(row[:artifact]) ==
            "prediction_target_and_model_weight_policy")
    @test Bool(prediction_policy[:summary][:passed])
    @test Bool(prediction_policy[:summary][:policy_recorded])
    @test Bool(prediction_policy[:summary][:same_data_waic_blocked])
    @test Bool(prediction_policy[:summary][:raw_psis_loo_blocked])
    @test Bool(prediction_policy[:summary][:heldout_kfold_selected])
    @test Bool(prediction_policy[:summary][:scalar_local_model_weight_reporting_allowed])
    @test Bool(prediction_policy[:summary][:mgmfrm_fit_allowed]) == false
    @test Bool(prediction_policy[:summary][:mgmfrm_weight_claims_allowed]) == false
    @test String(prediction_policy[:summary][:next_gate]) ==
        "manual_public_scope_review_for_mgmfrm_fit"

    review_rows = fixture[:review_rows]
    @test any(row -> String(row[:gate]) == "candidate_chain_study" &&
        String(row[:status]) == "passed", review_rows)
    @test any(row -> String(row[:gate]) == "baseline_calibration_grid" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "interval_decision_grid" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "sparse_design_grid" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "waic_influence_review" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "psis_loo_review" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "exact_loo_or_kfold_review" &&
        String(row[:status]) == "passed_with_caution", review_rows)
    @test any(row -> String(row[:gate]) == "guarded_fit_api_dry_run" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "guarded_fit_method_wiring" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "experimental_fit_validation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_posterior_predictive_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_sparse_pathology_recovery_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_prior_likelihood_sensitivity_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "scalar_gmfrm_real_data_case_study" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "claim_level_recovery_and_reproduction_archive" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "broader_experimental_exposure_decision_review" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_sparse_recovery_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_guarded_fit_method_wiring" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_guarded_fit_validation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "confirmatory_mgmfrm_guarded_fit_api_dry_run" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "confirmatory_mgmfrm_guarded_fit_public_exposure_review" &&
        String(row[:status]) == "passed_with_policy_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "prediction_target_and_model_weight_policy" &&
        String(row[:status]) == "passed_with_scope_blocker" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "dff_estimand_and_validation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "manuscript_scale_simulation_grid" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "full_paper_reproduction_archive" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)

    blocker_rows = fixture[:blocker_rows]
    @test isempty(blocker_rows)

    decision_record = fixture[:decision_record]
    @test String(decision_record[:public_exposure_support]) ==
        "guarded_scalar_gmfrm_only"
    @test String(decision_record[:interpretation]) ==
        "local_evidence_reviewed_full_archive_recorded_and_broader_exposure_decision_recorded"
    @test String(decision_record[:required_followup]) ==
        "manual_publication_or_registration_by_user_only"

    summary = fixture[:summary]
    @test Bool(summary[:reviewed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:all_local_evidence_passed])
    @test Bool(summary[:any_high_variance_waic])
    @test Bool(summary[:any_high_pareto_k])
    @test Bool(summary[:exact_loo_or_kfold_review_passed])
    @test Bool(summary[:guarded_fit_api_dry_run_passed])
    @test Bool(summary[:guarded_fit_method_wiring_passed])
    @test Bool(summary[:experimental_fit_validation_grid_passed])
    @test Bool(summary[:posterior_predictive_grid_passed])
    @test Bool(summary[:sparse_pathology_recovery_grid_passed])
    @test Bool(summary[:prior_likelihood_sensitivity_grid_passed])
    @test Bool(summary[:real_data_case_study_passed])
    @test Bool(summary[:claim_recovery_reproduction_archive_passed])
    @test Bool(summary[:broader_experimental_exposure_decision_review_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_public_exposure_review_passed])
    @test Bool(summary[:prediction_target_and_model_weight_policy_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:manuscript_scale_simulation_grid_passed])
    @test Bool(summary[:full_paper_reproduction_archive_passed])
    @test Bool(summary[:scalar_guarded_fit_allowed])
    @test Bool(summary[:broader_generalized_fit_allowed]) == false
    @test Bool(summary[:mgmfrm_fit_allowed]) == false
    @test Int(summary[:n_reviewed_artifacts]) == length(reviewed)
    @test Int(summary[:n_review_rows]) == length(review_rows)
    @test Int(summary[:n_blockers]) == length(blocker_rows)
    @test Bool(summary[:fit_allowed])
    @test Bool(summary[:experimental_keyword_enabled])
    @test String(summary[:recommendation]) ==
        "full_archive_recorded_keep_guarded_scalar_gmfrm_only"
    @test String(summary[:next_gate]) ==
        "manual_publication_or_registration_by_user_only"
end

function check_mgmfrm_recovery_smoke_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.mgmfrm_recovery_smoke.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_fit_ready_candidate"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test String(fixture[:target]) == "_source_fixture_logdensity"
    @test Int(fixture[:dimensions]) == 2
    @test json_bool_matrix(fixture[:q_matrix]) == Bool[1 0; 0 1]
    @test String(fixture[:latent_correlation]) == "identity_fixed"
    @test String(fixture[:ability_scale]) == "unit_variance_by_dimension"
    @test Float64(fixture[:source_scale]) == 1.7

    protocol = fixture[:protocol]
    grid = protocol[:grid]
    sampler = protocol[:sampler]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) == "confirmatory_mgmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260721
    @test Int(protocol[:sampler_seed]) == 20260722
    @test Int(grid[:persons]) == 4
    @test Int(grid[:items]) == 2
    @test Int(grid[:raters]) == 3
    @test Int(grid[:categories]) == 3
    @test Int(grid[:dimensions]) == 2
    @test json_bool_matrix(grid[:q_matrix]) == Bool[1 0; 0 1]
    @test String(grid[:rating_density]) == "full_crossed"
    @test Int(grid[:observations]) == 24
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:sampler]) == "nuts"
    @test Int(sampler[:chains]) == 2
    @test Int(sampler[:warmup]) == 32
    @test Int(sampler[:draws]) == 32
    @test Float64(sampler[:target_accept]) == 0.8
    @test Int(sampler[:max_depth]) == 8
    @test String(sampler[:metric]) == "unit"
    @test Float64(thresholds[:max_rhat]) == 1.35
    @test Float64(thresholds[:min_ess]) == 6.0
    @test Float64(thresholds[:min_ebfmi]) == 0.3
    @test Float64(thresholds[:max_block_mean_absolute_error]) == 0.9
    @test Float64(thresholds[:max_parameter_absolute_error]) == 1.8
    @test Float64(thresholds[:min_block_coverage_rate]) == 0.0

    raw_names = Vector{String}(fixture[:raw_parameter_order])
    direct_names = Vector{String}(fixture[:direct_parameter_order])
    @test length(raw_names) == 18
    @test length(direct_names) == 20
    @test String(fixture[:raw_parameter_order_sha256]) == test_parameter_order_hash(raw_names)
    @test String(fixture[:direct_parameter_order_sha256]) ==
        test_parameter_order_hash(direct_names)
    @test length(Vector{Float64}(fixture[:truth][:raw_parameter_values])) == length(raw_names)
    @test length(Vector{Float64}(fixture[:truth][:direct_parameter_values])) ==
        length(direct_names)

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == Int(grid[:observations])
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == Int(grid[:observations])
    @test Set(Int(row[:score]) for row in simulated[:score_counts]) == Set([0, 1, 2])
    @test length(simulated[:person_levels]) == Int(grid[:persons])
    @test length(simulated[:rater_levels]) == Int(grid[:raters])
    @test length(simulated[:item_levels]) == Int(grid[:items])

    sampler_summary = fixture[:sampler_summary]
    @test String(sampler_summary[:internal_flag]) == "ok"
    @test Bool(sampler_summary[:internal_passed])
    @test Int(sampler_summary[:n_chains]) == Int(sampler[:chains])
    @test Int(sampler_summary[:draws_per_chain]) == Int(sampler[:draws])
    @test Int(sampler_summary[:total_draws]) ==
        Int(sampler[:chains]) * Int(sampler[:draws])
    @test Float64(sampler_summary[:max_rhat]) <= Float64(thresholds[:max_rhat])
    @test Float64(sampler_summary[:min_ess]) >= Float64(thresholds[:min_ess])
    @test Float64(sampler_summary[:e_bfmi]) >= Float64(thresholds[:min_ebfmi])
    @test Int(sampler_summary[:n_divergences]) == 0
    @test Int(sampler_summary[:n_max_treedepth]) == 0
    @test Int(sampler_summary[:n_failed_direct_constraints]) == 0
    @test Int(sampler_summary[:n_nonfinite_logdensity]) == 0
    @test Int(sampler_summary[:n_nonfinite_direct_loglikelihood]) == 0

    recovery_rows = fixture[:recovery_rows]
    recovery_by_block = fixture[:recovery_by_block]
    @test length(recovery_rows) == length(direct_names)
    @test length(recovery_by_block) == 6
    @test Set(String(row[:group]) for row in recovery_by_block) == Set([
        "person",
        "rater",
        "item",
        "item_dimension_discrimination",
        "rater_consistency",
        "item_steps",
    ])
    @test all(row -> Float64(row[:absolute_bias]) <=
        Float64(thresholds[:max_parameter_absolute_error]), recovery_rows)
    @test all(row -> Float64(row[:mean_absolute_error]) <=
        Float64(thresholds[:max_block_mean_absolute_error]), recovery_by_block)
    @test all(row -> Float64(row[:coverage_rate]) >=
        Float64(thresholds[:min_block_coverage_rate]), recovery_by_block)

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_parameters]) == length(direct_names)
    @test Int(summary[:n_blocks]) == length(recovery_by_block)
    @test Float64(summary[:max_block_mean_absolute_error]) <=
        Float64(thresholds[:max_block_mean_absolute_error])
    @test Float64(summary[:max_parameter_absolute_error]) <=
        Float64(thresholds[:max_parameter_absolute_error])
    @test Float64(summary[:min_block_coverage_rate]) >=
        Float64(thresholds[:min_block_coverage_rate])
    @test String(fixture[:baseline_comparison][:status]) == "pending"
end

function check_mgmfrm_baseline_comparison_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.mgmfrm_baseline_comparison.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_baseline_comparison"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Int(fixture[:dimensions]) == 2
    @test [Bool.(row) for row in fixture[:q_matrix]] ==
        [[true, false], [false, true]]
    @test String(fixture[:latent_correlation]) == "identity_fixed"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_baseline_comparison_v1"
    @test String(protocol[:simulation_source]) ==
        "confirmatory_mgmfrm_recovery_smoke_v1"
    @test Int(protocol[:simulation_seed]) == 20260721
    @test Int(thresholds[:minimum_models]) == 3
    @test Int(thresholds[:n_observations]) == 24
    @test Bool(thresholds[:require_same_observations])
    @test Bool(thresholds[:require_finite_elpd])
    @test Bool(thresholds[:require_finite_weights])
    @test String(protocol[:mgmfrm_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:mgmfrm_sampler][:seed]) == 20260722
    @test Int(protocol[:mgmfrm_sampler][:draws]) == 32
    @test String(protocol[:baseline_sampler][:backend]) == "advancedhmc"
    @test Int(protocol[:baseline_sampler][:draws]) == 32
    @test Int(protocol[:baseline_sampler][:seeds][:partial_credit]) == 20260762
    @test Int(protocol[:baseline_sampler][:seeds][:rating_scale]) == 20260763

    simulated = fixture[:simulated_data]
    @test Int(simulated[:n_observations]) == 24
    @test sum(Int(row[:n]) for row in simulated[:score_counts]) == 24
    @test length(simulated[:person_levels]) == 4
    @test length(simulated[:rater_levels]) == 3
    @test length(simulated[:item_levels]) == 2
    @test Set(Int(level) for level in simulated[:category_levels]) == Set([0, 1, 2])
    @test String(simulated[:truth_source]) == "mgmfrm_recovery_smoke_truth"

    model_rows = fixture[:model_rows]
    @test length(model_rows) == 3
    @test [Int(row[:rank]) for row in model_rows] == [1, 2, 3]
    @test issorted([Float64(row[:elpd_waic]) for row in model_rows]; rev = true)
    @test Set(String(row[:model]) for row in model_rows) == Set([
        "mgmfrm_internal_candidate",
        "mfrm_partial_credit",
        "mfrm_rating_scale",
    ])
    @test all(row -> Int(row[:n_observations]) == 24, model_rows)
    @test all(row -> Int(row[:n_draws]) == 64, model_rows)
    @test all(row -> isfinite(Float64(row[:elpd_waic])) &&
        isfinite(Float64(row[:waic])), model_rows)
    @test all(row -> isfinite(Float64(row[:relative_weight])), model_rows)
    @test sum(Float64(row[:relative_weight]) for row in model_rows) ≈ 1.0
    @test all(row -> String(row[:criterion]) == "waic", model_rows)
    @test all(row -> String(row[:warning]) in ("ok", "high_loglik_variance"),
        model_rows)
    @test all(row -> Bool(row[:sampler_summary][:internal_passed]), model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_divergences]) == 0, model_rows)
    @test all(row -> Int(row[:sampler_summary][:n_max_treedepth]) == 0,
        model_rows)

    mgmfrm_row = only(row for row in model_rows
        if String(row[:model]) == "mgmfrm_internal_candidate")
    @test String(mgmfrm_row[:family]) == "mgmfrm"
    @test String(mgmfrm_row[:source]) == "internal_source_fixture_candidate"
    @test String(mgmfrm_row[:threshold_regime]) ==
        "confirmatory_fixed_q_multidimensional_partial_credit"
    @test Bool(mgmfrm_row[:public_fit]) == false
    @test Int(mgmfrm_row[:n_parameters]) == 18
    @test String(simulated[:raw_parameter_order_sha256]) ==
        String(mgmfrm_row[:parameter_order_sha256])
    @test String(simulated[:direct_parameter_order_sha256]) ==
        String(mgmfrm_row[:direct_parameter_order_sha256])
    @test Float64(mgmfrm_row[:elpd_difference]) <= 0.0

    baseline_rows = [row for row in model_rows if String(row[:family]) == "mfrm"]
    @test length(baseline_rows) == 2
    @test all(row -> String(row[:source]) == "public_minimal_fit", baseline_rows)
    @test all(row -> Bool(row[:public_fit]), baseline_rows)
    @test Set(String(row[:threshold_regime]) for row in baseline_rows) ==
        Set(["partial_credit", "rating_scale"])

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:comparison_executed])
    @test Int(summary[:n_models]) == length(model_rows)
    @test String(summary[:best_model]) == String(model_rows[1][:model])
    @test Int(summary[:mgmfrm_rank]) == Int(mgmfrm_row[:rank])
    @test Float64(summary[:mgmfrm_elpd_difference]) ≈
        Float64(mgmfrm_row[:elpd_difference])
    @test Float64(summary[:mgmfrm_relative_weight]) ≈
        Float64(mgmfrm_row[:relative_weight])
    @test Bool(summary[:any_high_variance_waic])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test String(summary[:recommendation]) == "keep_internal_until_sparse_recovery_grid"
    @test String(summary[:next_gate]) == "mgmfrm_sparse_recovery_grid"
end

function check_mgmfrm_sparse_recovery_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path = isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.mgmfrm_sparse_recovery_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "internal_sparse_recovery_grid"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Int(fixture[:dimensions]) == 2
    @test [Bool.(row) for row in fixture[:q_matrix]] ==
        [[true, false], [false, true]]
    @test String(fixture[:latent_correlation]) == "identity_fixed"

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    diagnostics = protocol[:diagnostics]
    recovery_thresholds = protocol[:recovery]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_sparse_recovery_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_sparse_recovery_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Int(thresholds[:n_scenarios]) == 3
    @test Int(thresholds[:min_observations]) == 16
    @test Int(thresholds[:max_observations]) == 20
    @test Bool(thresholds[:require_all_scenarios_passed])
    @test Bool(thresholds[:require_validation_passed])
    @test Bool(thresholds[:require_connected_design])
    @test Bool(thresholds[:require_full_location_rank])
    @test Bool(thresholds[:require_same_parameter_order])
    @test Bool(thresholds[:require_sampler_passed])
    @test Bool(thresholds[:require_finite_logdensity])
    @test Bool(thresholds[:require_finite_pointwise_loglikelihood])
    @test Bool(thresholds[:require_finite_waic])
    @test String(thresholds[:public_exposure_decision]) == "keep_internal"
    @test Float64(diagnostics[:max_rhat]) == 1.6
    @test Float64(diagnostics[:min_ess]) == 4.0
    @test Int(diagnostics[:n_divergences]) == 0
    @test Int(diagnostics[:n_max_treedepth]) == 0
    @test Float64(recovery_thresholds[:max_block_mean_absolute_error]) == 2.5
    @test Float64(recovery_thresholds[:max_parameter_absolute_error]) == 4.0

    reviewed = fixture[:reviewed_artifacts]
    @test Set(String(row[:artifact]) for row in reviewed) == Set([
        "test/fixtures/mgmfrm_recovery_smoke.json",
        "test/fixtures/mgmfrm_baseline_comparison.json",
    ])
    @test all(row -> Bool(row[:exists]), reviewed)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(joinpath(root, String(row[:artifact]))), reviewed)

    scenarios = fixture[:scenarios]
    @test length(scenarios) == 3
    @test Set(String(row[:scenario]) for row in scenarios) == Set([
        "rater_item_bridge_sparse",
        "alternating_dimension_bridge_sparse",
        "leave_one_pair_out_sparse",
    ])
    @test Set(String(row[:sparse_pattern]) for row in scenarios) == Set([
        "rater_item_bridge",
        "alternating_dimension_bridge",
        "leave_one_pair_out",
    ])
    for scenario in scenarios
        scenario_summary = scenario[:summary]
        validation = scenario[:validation]
        sampler = scenario[:sampler_summary]
        pointwise = scenario[:pointwise_loglikelihood_review]
        @test Bool(scenario_summary[:passed])
        @test Int(scenario_summary[:n_observations]) ==
            Int(scenario[:design_density][:n_observations])
        @test 16 <= Int(scenario_summary[:n_observations]) <= 20
        @test Bool(scenario_summary[:validation_passed])
        @test Bool(validation[:passed])
        @test Int(validation[:n_errors]) == 0
        @test Int(validation[:n_components]) == 1
        @test Bool(validation[:location_design_full_rank])
        @test Bool(scenario_summary[:parameter_order_matches_reference])
        @test String(scenario_summary[:sampler_flag]) == "ok"
        @test Bool(sampler[:internal_passed])
        @test Int(scenario_summary[:n_divergences]) == 0
        @test Int(scenario_summary[:n_max_treedepth]) == 0
        @test Int(scenario_summary[:n_failed_direct_constraints]) == 0
        @test Int(scenario_summary[:n_nonfinite_logdensity]) == 0
        @test Int(scenario_summary[:n_nonfinite_direct_loglikelihood]) == 0
        @test Float64(scenario_summary[:max_rhat]) <= 1.6
        @test Float64(scenario_summary[:min_ess]) >= 4.0
        @test Int(pointwise[:n_nonfinite]) == 0
        @test Bool(scenario_summary[:waic_finite])
        @test Float64(scenario_summary[:max_block_mean_absolute_error]) <=
            Float64(recovery_thresholds[:max_block_mean_absolute_error])
        @test Float64(scenario_summary[:max_parameter_absolute_error]) <=
            Float64(recovery_thresholds[:max_parameter_absolute_error])
        @test Float64(scenario_summary[:min_block_coverage_rate]) >=
            Float64(recovery_thresholds[:min_block_coverage_rate])
    end

    decision = fixture[:decision_record]
    @test String(decision[:selected_decision]) == "keep_internal"
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_for_mgmfrm_public_fit"
    @test String(decision[:interpretation]) ==
        "confirmatory_mgmfrm_sparse_recovery_grid_recorded_keep_internal"
    @test String(decision[:required_followup]) ==
        "dff_estimand_and_validation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Int(summary[:n_scenarios]) == length(scenarios)
    @test Int(summary[:n_passed_scenarios]) == length(scenarios)
    @test Int(summary[:n_observations_minimum]) >= 16
    @test Int(summary[:n_observations_maximum]) <= 20
    @test Bool(summary[:all_validations_passed])
    @test Bool(summary[:all_location_designs_full_rank])
    @test Bool(summary[:all_parameter_orders_match_reference])
    @test Bool(summary[:all_sampler_passed])
    @test Bool(summary[:all_no_divergences])
    @test Bool(summary[:all_no_max_treedepth])
    @test Bool(summary[:all_no_failed_direct_constraints])
    @test Bool(summary[:all_no_nonfinite_logdensity])
    @test Bool(summary[:all_no_nonfinite_direct_loglikelihood])
    @test Bool(summary[:all_waic_finite])
    @test Float64(summary[:max_block_mean_absolute_error]) <=
        Float64(recovery_thresholds[:max_block_mean_absolute_error])
    @test Float64(summary[:max_parameter_absolute_error]) <=
        Float64(recovery_thresholds[:max_parameter_absolute_error])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set([
            "dff_estimand_and_validation_evidence_missing",
            "manuscript_scale_simulation_grid_missing",
            "full_paper_reproduction_archive_missing",
        ])
    @test String(summary[:recommendation]) ==
        "keep_mgmfrm_internal_until_dff_and_gate_e_evidence"
    @test String(summary[:next_gate]) == "dff_estimand_and_validation_grid"
end

function check_mgmfrm_guarded_fit_method_wiring_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_method_wiring.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "guarded_fit_method_wiring_recorded"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:entrypoint_enabled]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_method_wiring_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_method_wiring"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:entrypoint_enabled]) == false
    rules = protocol[:decision_rules]
    @test Bool(rules[:require_entrypoint_stays_disabled])
    @test Bool(rules[:require_current_public_fit_rejection])
    @test Bool(rules[:require_artifact_contract_satisfied])
    @test Bool(rules[:validation_grid_required_before_public_entrypoint])

    target = fixture[:target_review]
    @test String(target[:constructor]) == "_source_fixture_logdensity"
    @test String(target[:family]) == "mgmfrm"
    @test String(target[:scope]) == "mgmfrm_source_aligned"
    @test Int(target[:n_raw_parameters]) == 12
    @test Int(target[:n_direct_parameters]) == 14

    sampler = fixture[:sampler_review]
    sampler_summary = sampler[:summary]
    @test String(sampler[:schema]) ==
        "bayesianmgmfrm.mgmfrm_confirmatory_candidate_sampler_diagnostics.v1"
    @test Bool(sampler[:protocol_passed])
    @test Bool(sampler_summary[:passed])
    @test Int(sampler_summary[:n_divergences]) == 0
    @test Int(sampler_summary[:n_failed_direct_constraints]) == 0
    @test Int(sampler_summary[:n_nonfinite_direct_loglikelihood]) == 0

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test Bool(contract[:public_fit]) == false
    @test Bool(contract[:experimental_public]) == false
    @test Bool(contract[:all_required_fields_present])
    @test Bool(contract[:all_required_provenance_recorded])

    preview = fixture[:fit_artifact_preview]
    @test String(preview[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_artifact_preview.v1"
    @test Bool(preview[:public_fit]) == false
    @test Bool(preview[:experimental_public]) == false
    @test Int(preview[:raw_parameter_count]) == 12
    @test Int(preview[:direct_parameter_count]) == 14
    @test Vector{Int}(preview[:pointwise_loglikelihood_shape]) == [64, 6]
    @test [Bool.(row) for row in preview[:q_matrix]] ==
        [[true, false], [false, true]]
    @test String(preview[:latent_correlation]) == "identity_fixed"
    @test String(preview[:ability_scale]) == "unit_variance_by_dimension"

    fixture_refs = fixture[:fixture_references]
    @test length(fixture_refs) == 5
    @test all(row -> Bool(row[:exists]), fixture_refs)
    @test all(row -> String(row[:sha256]) ==
        file_sha256(joinpath(root, String(row[:path]))), fixture_refs)

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 4
    @test all(row -> Bool(row[:rejected]), rejection_checks)

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:required_followup]) ==
        "mgmfrm_guarded_fit_validation_grid"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled]) == false
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Bool(summary[:target_constructor_available])
    @test Bool(summary[:raw_to_direct_transform_available])
    @test Bool(summary[:sampler_protocol_passed])
    @test Bool(summary[:artifact_contract_satisfied])
    @test Bool(summary[:pointwise_loglikelihood_shape_valid])
    @test Bool(summary[:all_current_public_fit_attempts_rejected])
    @test Bool(summary[:all_fixture_references_present])
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["mgmfrm_guarded_fit_validation_grid_missing"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_mgmfrm_guarded_fit_validation_grid"
    @test String(summary[:next_gate]) == "mgmfrm_guarded_fit_validation_grid"
end

function check_mgmfrm_guarded_fit_validation_grid_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_validation_grid.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "guarded_fit_validation_grid_recorded"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_validation_grid_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_validation_grid"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:entrypoint_enabled]) == false
    thresholds = protocol[:thresholds]
    @test Bool(thresholds[:require_bridge_oracle_present])
    @test Bool(thresholds[:require_candidate_chain_passed])
    @test Bool(thresholds[:require_recovery_smoke_passed])
    @test Bool(thresholds[:require_baseline_comparison_passed])
    @test Bool(thresholds[:require_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_sampler_protocol_passed])
    @test Bool(thresholds[:require_artifact_contract_satisfied])
    @test Bool(thresholds[:require_current_public_fit_rejections])
    @test Bool(thresholds[:require_entrypoint_stays_disabled])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
    )
    @test length(input_artifacts) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    validation_rows = fixture[:validation_rows]
    @test length(validation_rows) == 6
    @test Set(String(row[:scenario]) for row in validation_rows) == Set([
        "bridge_and_chain_oracles",
        "full_crossed_recovery_smoke",
        "baseline_model_comparison",
        "sparse_connected_recovery_grid",
        "guarded_method_contract",
        "current_public_fit_boundary",
    ])
    @test all(row -> Bool(row[:evidence]), validation_rows)

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "insufficient_until_mgmfrm_guarded_fit_api_dry_run"
    @test String(decision[:interpretation]) ==
        "confirmatory_mgmfrm_guarded_fit_validation_grid_recorded_entrypoint_disabled"
    @test String(decision[:required_followup]) ==
        "mgmfrm_guarded_fit_api_dry_run"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled]) == false
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:all_validation_rows_passed])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:bridge_oracle_present])
    @test Bool(summary[:candidate_chain_study_passed])
    @test Bool(summary[:recovery_smoke_passed])
    @test Bool(summary[:baseline_comparison_passed])
    @test Bool(summary[:sparse_recovery_grid_passed])
    @test Bool(summary[:guarded_fit_method_wiring_passed])
    @test Bool(summary[:sparse_grid_all_validations_passed])
    @test Bool(summary[:sparse_grid_all_sampler_passed])
    @test Bool(summary[:method_sampler_protocol_passed])
    @test Bool(summary[:method_artifact_contract_satisfied])
    @test Bool(summary[:method_current_public_fit_attempts_rejected])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_validation_rows]) == length(validation_rows)
    @test Int(summary[:n_passed_validation_rows]) == length(validation_rows)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["mgmfrm_guarded_fit_api_dry_run_missing"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_mgmfrm_guarded_fit_api_dry_run"
    @test String(summary[:next_gate]) == "mgmfrm_guarded_fit_api_dry_run"
end

function check_mgmfrm_guarded_fit_api_dry_run_fixture(fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_api_dry_run.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) == "guarded_fit_api_dry_run_recorded"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false
    @test Bool(fixture[:entrypoint_enabled]) == false

    protocol = fixture[:protocol]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_api_dry_run_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_api_contract_dry_run"
    @test Bool(protocol[:dry_run_only])
    @test Bool(protocol[:entrypoint_enabled]) == false
    rules = protocol[:decision_rules]
    @test Bool(rules[:require_validation_grid_passed])
    @test Bool(rules[:require_gradient_diagnostics_passed])
    @test Bool(rules[:public_exposure_review_required_before_public_entrypoint])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
    )
    @test length(input_artifacts) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 4
    @test all(row -> Bool(row[:rejected]), rejection_checks)

    contract = fixture[:artifact_contract_review]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test Bool(contract[:public_fit]) == false
    @test Bool(contract[:experimental_public]) == false
    @test Bool(contract[:all_required_fields_recorded])
    @test Bool(contract[:all_required_provenance_recorded])

    target = fixture[:target_dry_run]
    @test String(target[:target]) == "_source_fixture_logdensity"
    @test Int(target[:n_raw_parameters]) == 12
    @test Int(target[:n_direct_parameters]) == 14
    @test Int(target[:n_observations]) == 6
    @test Bool(target[:finite_logdensity])
    @test Bool(target[:finite_direct_parameters])
    @test Bool(target[:finite_pointwise_loglikelihood])
    gradient = target[:gradient_diagnostics]
    @test Bool(gradient[:passed])
    @test Int(gradient[:n_checked]) == 6
    @test Int(gradient[:n_failed]) == 0
    @test Float64(gradient[:max_abs_error]) <=
        Float64(gradient[:max_tolerance])

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test String(decision[:required_followup]) ==
        "mgmfrm_guarded_fit_public_exposure_review"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:dry_run_only])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:entrypoint_enabled]) == false
    @test Bool(summary[:guarded_fit_validation_grid_passed])
    @test Bool(summary[:validation_grid_all_rows_passed])
    @test Bool(summary[:all_current_public_fit_attempts_rejected])
    @test Bool(summary[:artifact_contract_satisfied])
    @test Bool(summary[:target_logdensity_finite])
    @test Bool(summary[:target_gradient_diagnostics_passed])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_rejection_checks]) == length(rejection_checks)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["mgmfrm_guarded_fit_public_exposure_review_missing"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_mgmfrm_guarded_fit_public_exposure_review"
    @test String(summary[:next_gate]) ==
        "mgmfrm_guarded_fit_public_exposure_review"
end

function check_mgmfrm_guarded_fit_public_exposure_review_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.mgmfrm_guarded_fit_public_exposure_review.v1"
    @test String(fixture[:family]) == "mgmfrm"
    @test String(fixture[:scope]) == "minimal_confirmatory_mgmfrm_candidate"
    @test String(fixture[:status]) ==
        "guarded_fit_public_exposure_review_recorded"
    @test String(fixture[:decision]) == "keep_internal"
    @test Bool(fixture[:public_fit]) == false
    @test Bool(fixture[:experimental_public]) == false
    @test Bool(fixture[:fit_ready]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "confirmatory_mgmfrm_guarded_fit_public_exposure_review_v1"
    @test String(protocol[:review_kind]) ==
        "local_confirmatory_mgmfrm_guarded_fit_public_exposure_review"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:entrypoint_under_review]) ==
        "fit(spec; experimental = true)"
    @test Bool(thresholds[:require_bridge_oracle_present])
    @test Bool(thresholds[:require_candidate_chain_study_passed])
    @test Bool(thresholds[:require_recovery_smoke_passed])
    @test Bool(thresholds[:require_baseline_comparison_passed])
    @test Bool(thresholds[:require_sparse_recovery_grid_passed])
    @test Bool(thresholds[:require_guarded_fit_method_wiring_passed])
    @test Bool(thresholds[:require_guarded_fit_validation_grid_passed])
    @test Bool(thresholds[:require_guarded_fit_api_dry_run_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:require_current_public_fit_rejections])
    @test Bool(thresholds[:require_manifest_keeps_mgmfrm_internal])
    @test Bool(thresholds[:require_prediction_target_and_model_weight_blocker])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "bridge_oracle" =>
            "test/fixtures/source_mgmfrm_bridge_logdensity.json",
        "candidate_chain_study" =>
            "test/fixtures/mgmfrm_candidate_chain_study.json",
        "recovery_smoke" =>
            "test/fixtures/mgmfrm_recovery_smoke.json",
        "baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        "guarded_fit_validation_grid" =>
            "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
    )
    @test length(input_artifacts) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    rejection_checks = fixture[:fit_rejection_checks]
    @test length(rejection_checks) == 4
    @test all(row -> Bool(row[:rejected]), rejection_checks)

    manifest = fixture[:manifest_snapshot]
    @test String(manifest[:candidate_status]) == "internal_fit_ready_candidate"
    @test String(manifest[:experimental_decision_status]) == "blocked"
    @test String(manifest[:experimental_decision]) == "keep_internal"
    @test Bool(manifest[:experimental_summary][:fit_allowed]) == false
    @test Bool(manifest[:experimental_summary][:experimental_keyword_enabled]) == false

    review_rows = fixture[:review_rows]
    @test length(review_rows) == 11
    @test any(row -> String(row[:gate]) == "guarded_fit_api_dry_run" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) == "current_public_fit_boundary" &&
        String(row[:status]) == "passed" &&
        Bool(row[:evidence]), review_rows)
    @test any(row -> String(row[:gate]) ==
        "prediction_target_and_model_weight_policy" &&
        String(row[:status]) == "blocked" &&
        Bool(row[:evidence]) == false, review_rows)

    blocker_rows = fixture[:blocker_rows]
    @test length(blocker_rows) == 1
    @test String(blocker_rows[1][:blocker]) ==
        "prediction_target_and_model_weight_policy_missing"
    @test String(blocker_rows[1][:severity]) == "blocking"

    decision = fixture[:decision_record]
    @test Bool(decision[:public_fit_allowed]) == false
    @test Bool(decision[:experimental_keyword_enabled]) == false
    @test Bool(decision[:current_manifest_fit_allowed]) == false
    @test Bool(decision[:current_manifest_experimental_keyword_enabled]) == false
    @test String(decision[:public_exposure_support]) ==
        "review_recorded_keep_internal_until_prediction_target_and_model_weight_policy"
    @test String(decision[:required_followup]) ==
        "prediction_target_and_model_weight_policy"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:reviewed])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:public_fit_allowed]) == false
    @test Bool(summary[:experimental_keyword_enabled]) == false
    @test Bool(summary[:current_manifest_fit_allowed]) == false
    @test Bool(summary[:current_manifest_experimental_keyword_enabled]) == false
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:all_current_public_fit_attempts_rejected])
    @test Bool(summary[:current_manifest_keeps_internal])
    @test Bool(summary[:no_publication_commands])
    @test Bool(summary[:bridge_oracle_present])
    @test Bool(summary[:mgmfrm_candidate_chain_study_passed])
    @test Bool(summary[:mgmfrm_recovery_smoke_passed])
    @test Bool(summary[:mgmfrm_baseline_comparison_passed])
    @test Bool(summary[:mgmfrm_sparse_recovery_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_method_wiring_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_validation_grid_passed])
    @test Bool(summary[:mgmfrm_guarded_fit_api_dry_run_passed])
    @test Bool(summary[:dff_estimand_validation_grid_passed])
    @test Bool(summary[:method_current_public_fit_attempts_rejected])
    @test Bool(summary[:validation_all_rows_passed])
    @test Bool(summary[:api_dry_run_gradient_diagnostics_passed])
    @test Bool(summary[:dff_model_effects_allowed]) == false
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_rejection_checks]) == length(rejection_checks)
    @test Int(summary[:n_review_rows]) == length(review_rows)
    @test Int(summary[:n_blockers]) == length(blocker_rows)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["prediction_target_and_model_weight_policy_missing"])
    @test String(summary[:recommendation]) ==
        "keep_internal_until_prediction_target_and_model_weight_policy"
    @test String(summary[:next_gate]) ==
        "prediction_target_and_model_weight_policy"
end

function check_gmfrm_prediction_target_and_model_weight_policy_fixture(
        fixture_path::AbstractString)
    root = dirname(@__DIR__)
    resolved_fixture_path =
        isabspath(fixture_path) ? fixture_path : joinpath(root, fixture_path)
    fixture = JSON3.read(read(resolved_fixture_path, String))
    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.gmfrm_prediction_target_and_model_weight_policy.v1"
    @test String(fixture[:family]) == "gmfrm"
    @test String(fixture[:scope]) ==
        "prediction_target_and_model_weight_policy"
    @test String(fixture[:status]) ==
        "prediction_target_and_model_weight_policy_recorded"
    @test String(fixture[:decision]) ==
        "select_heldout_kfold_for_local_weight_policy"
    @test Bool(fixture[:public_fit])
    @test Bool(fixture[:experimental_public])
    @test Bool(fixture[:fit_ready])
    @test Bool(fixture[:broader_public_fit]) == false
    @test Bool(fixture[:publication_or_registration_action]) == false

    protocol = fixture[:protocol]
    thresholds = protocol[:thresholds]
    @test String(protocol[:protocol_id]) ==
        "gmfrm_prediction_target_and_model_weight_policy_v1"
    @test String(protocol[:review_kind]) ==
        "local_prediction_target_and_model_weight_policy"
    @test Bool(protocol[:publication_or_registration_action]) == false
    @test Bool(protocol[:local_only])
    @test String(protocol[:primary_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(thresholds[:require_sparse_design_grid_passed])
    @test Bool(thresholds[:require_waic_influence_review_passed])
    @test Bool(thresholds[:require_psis_loo_review_passed])
    @test Bool(thresholds[:require_exact_loo_or_kfold_review_passed])
    @test Bool(thresholds[:require_guarded_scalar_fit_evidence_passed])
    @test Bool(thresholds[:require_mgmfrm_public_exposure_review_passed])
    @test Bool(thresholds[:require_dff_estimand_validation_grid_passed])
    @test Bool(thresholds[:require_same_data_waic_blocked_for_weight_claims])
    @test Bool(thresholds[:require_raw_psis_loo_blocked_for_weight_claims])
    @test Bool(thresholds[:require_heldout_kfold_target_selected])
    @test Bool(thresholds[:require_mgmfrm_weight_claims_blocked_until_public_scope_review])
    @test Bool(thresholds[:require_no_publication_or_registration_action])

    input_artifacts = fixture[:input_artifacts]
    expected_paths = Dict(
        "sparse_design_grid" =>
            "test/fixtures/gmfrm_sparse_design_grid.json",
        "waic_influence_review" =>
            "test/fixtures/gmfrm_waic_influence_review.json",
        "psis_loo_review" =>
            "test/fixtures/gmfrm_psis_loo_review.json",
        "exact_loo_or_kfold_review" =>
            "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        "guarded_fit_api_dry_run" =>
            "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        "guarded_fit_method_wiring" =>
            "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        "experimental_fit_validation_grid" =>
            "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        "posterior_predictive_grid" =>
            "test/fixtures/gmfrm_posterior_predictive_grid.json",
        "mgmfrm_baseline_comparison" =>
            "test/fixtures/mgmfrm_baseline_comparison.json",
        "mgmfrm_sparse_recovery_grid" =>
            "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        "mgmfrm_guarded_fit_public_exposure_review" =>
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        "dff_estimand_validation_grid" =>
            "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
    )
    @test length(input_artifacts) == length(expected_paths)
    @test Set(String(row[:artifact]) for row in input_artifacts) ==
        Set(keys(expected_paths))
    for row in input_artifacts
        artifact = String(row[:artifact])
        @test expected_paths[artifact] == String(row[:path])
        @test Bool(row[:exists])
        @test Bool(row[:schema_matches])
        @test Bool(row[:summary_passed])
        @test String(row[:sha256]) ==
            file_sha256(joinpath(root, String(row[:path])))
    end

    target_rows = fixture[:prediction_target_rows]
    @test length(target_rows) == 3
    @test any(row -> String(row[:target]) == "same_observation_waic" &&
        String(row[:status]) == "diagnostic_only" &&
        Bool(row[:allowed_for_model_weight_claims]) == false, target_rows)
    @test any(row -> String(row[:target]) == "raw_importance_loo" &&
        String(row[:status]) == "diagnostic_only" &&
        Bool(row[:allowed_for_model_weight_claims]) == false, target_rows)
    @test any(row -> String(row[:target]) == "heldout_observation_log_score" &&
        String(row[:status]) == "selected_primary_local_target" &&
        Bool(row[:allowed_for_model_weight_claims]) &&
        Bool(row[:evidence]), target_rows)

    policy_rows = fixture[:model_weight_policy_rows]
    @test length(policy_rows) == 3
    @test any(row -> String(row[:surface]) == "scalar_gmfrm_guarded_fit" &&
        Bool(row[:allowed_for_local_model_weight_reporting]) &&
        Bool(row[:evidence]), policy_rows)
    @test any(row -> String(row[:surface]) == "confirmatory_mgmfrm_fit" &&
        String(row[:status]) == "policy_recorded_keep_internal" &&
        Bool(row[:allowed_for_local_model_weight_reporting]) == false &&
        String(row[:required_followup]) ==
            "manual_public_scope_review_for_mgmfrm_fit", policy_rows)
    @test any(row -> String(row[:surface]) == "dff_model_effects" &&
        String(row[:status]) == "validation_only" &&
        Bool(row[:allowed_for_local_model_weight_reporting]) == false,
        policy_rows)

    blockers = fixture[:blocker_rows]
    @test length(blockers) == 1
    @test String(blockers[1][:blocker]) ==
        "manual_public_scope_review_for_mgmfrm_fit_missing"
    @test String(blockers[1][:severity]) == "blocking"

    decision = fixture[:decision_record]
    @test String(decision[:selected_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(decision[:same_data_waic_weight_claims_allowed]) == false
    @test Bool(decision[:raw_psis_loo_weight_claims_allowed]) == false
    @test Bool(decision[:scalar_local_model_weight_reporting_allowed])
    @test Bool(decision[:mgmfrm_weight_claims_allowed]) == false
    @test Bool(decision[:manuscript_sparse_mgmfrm_claims_allowed]) == false
    @test Bool(decision[:mgmfrm_fit_allowed]) == false
    @test String(decision[:required_followup]) ==
        "manual_public_scope_review_for_mgmfrm_fit"

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Bool(summary[:policy_recorded])
    @test Bool(summary[:publication_or_registration_action]) == false
    @test Bool(summary[:local_only])
    @test Bool(summary[:all_input_artifacts_present])
    @test Bool(summary[:all_expected_schemas])
    @test Bool(summary[:all_input_summaries_passed])
    @test Bool(summary[:same_data_waic_blocked])
    @test Bool(summary[:raw_psis_loo_blocked])
    @test Bool(summary[:heldout_kfold_selected])
    @test String(summary[:primary_prediction_target]) ==
        "heldout_observation_log_score"
    @test Bool(summary[:scalar_local_model_weight_reporting_allowed])
    @test Bool(summary[:public_model_weight_claims_allowed]) == false
    @test Bool(summary[:mgmfrm_fit_allowed]) == false
    @test Bool(summary[:mgmfrm_weight_claims_allowed]) == false
    @test Bool(summary[:manuscript_sparse_mgmfrm_claims_allowed]) == false
    @test Bool(summary[:current_mgmfrm_manifest_keeps_internal])
    @test Bool(summary[:no_publication_commands])
    @test Int(summary[:n_input_artifacts]) == length(input_artifacts)
    @test Int(summary[:n_prediction_target_rows]) == length(target_rows)
    @test Int(summary[:n_model_weight_policy_rows]) == length(policy_rows)
    @test Int(summary[:n_blockers]) == length(blockers)
    @test Set(String(blocker) for blocker in summary[:remaining_public_blockers]) ==
        Set(["manual_public_scope_review_for_mgmfrm_fit_missing"])
    @test String(summary[:recommendation]) ==
        "use_heldout_kfold_for_local_weights_keep_mgmfrm_claims_blocked"
    @test String(summary[:next_gate]) ==
        "manual_public_scope_review_for_mgmfrm_fit"
end

function test_logsumexp(vals)
    m = maximum(vals)
    return m + log(sum(exp(v - m) for v in vals))
end

function test_normal_logpdf(x, sd)
    z = x / sd
    return -log(sd) - 0.5 * (log(2.0 * pi) + z * z)
end

function test_sample_variance(vals)
    n = length(vals)
    m = sum(Float64, vals) / n
    return sum((Float64(v) - m)^2 for v in vals) / (n - 1)
end

function raw_pcm_pointwise(data, person, rater, item, steps_by_item)
    K = length(data.category_levels)
    out = Vector{Float64}(undef, data.n)
    for n in 1:data.n
        location = person[data.person[n]] - rater[data.rater[n]] - item[data.item[n]]
        steps = steps_by_item[data.item[n]]
        etas = [
            (category - 1) * location - sum(steps[1:(category - 1)]; init = 0.0)
            for category in 1:K
        ]
        out[n] = etas[data.category[n]] - test_logsumexp(etas)
    end
    return out
end

function scalar_validation_fixture_data(fixture)
    data = fixture[:data]
    return ScalarValidationData(
        X = Vector{Int}(data[:X]),
        examinee = Vector{Int}(data[:examinee]),
        rater = Vector{Int}(data[:rater]),
        J = Int(data[:J]),
        R = Int(data[:R]),
        K = Int(data[:K]),
        N = Int(data[:N]),
    )
end

function check_scalar_validation_stan_pair(known_fixture_path::AbstractString,
        stan_fixture_path::AbstractString;
        expected_size::Union{Nothing,String} = nothing,
        expected_counts::Union{Nothing,NTuple{4,Int}} = nothing)
    known = JSON3.read(read(known_fixture_path, String))
    @test String(known[:schema]) == "bayesianmgmfrm.scalar_validation_known_value.v1"
    if expected_size !== nothing
        @test String(known[:size]) == expected_size
    end
    fd = scalar_validation_fixture_data(known)
    if expected_counts !== nothing
        @test (fd.J, fd.R, fd.K, fd.N) == expected_counts
    end
    x = Vector{Float64}(known[:x])
    @test length(x) == scalar_validation_num_params(fd)
    lp, gradient = scalar_validation_logposterior_and_gradient(x, fd)
    known_tol = Float64(known[:tolerance])
    @test lp ≈ Float64(known[:log_density]) atol = known_tol rtol = known_tol
    @test maximum(abs.(gradient .- Vector{Float64}(known[:gradient]))) < known_tol

    stan = JSON3.read(read(stan_fixture_path, String))
    @test String(stan[:schema]) == "bayesianmgmfrm.scalar_stan_logdensity.v1"
    if expected_size !== nothing
        @test String(stan[:size]) == expected_size
    end
    @test Bool(stan[:propto]) == false
    @test Bool(stan[:jacobian]) == true
    @test String(stan[:stan_model]) == "test/stan/scalar_gmfrm.stan"
    @test String(stan[:stan_model_sha256]) ==
        file_sha256(joinpath(@__DIR__, "stan", "scalar_gmfrm.stan"))
    @test String(stan[:known_fixture]) ==
        "test/fixtures/$(basename(known_fixture_path))"
    @test String(stan[:known_fixture_sha256]) == file_sha256(known_fixture_path)
    stan_data = stan[:stan_data]
    @test (Int(stan_data[:J]), Int(stan_data[:R]), Int(stan_data[:K]), Int(stan_data[:N])) ==
        (fd.J, fd.R, fd.K, fd.N)
    @test Vector{Float64}(stan[:x]) == x
    @test length(Vector{String}(stan[:stan_parameter_order])) == length(x)
    stan_tol = Float64(stan[:tolerance])
    stan_lp = Float64(stan[:stan_log_density])
    stan_gradient = Vector{Float64}(stan[:stan_gradient])
    @test lp ≈ Float64(stan[:stan_log_density]) atol = stan_tol rtol = stan_tol
    @test maximum(abs.(gradient .- stan_gradient)) < max(stan_tol, 1e-9)
    validation_row = stan_validation_row(fd, x, stan_lp;
        stan_gradient,
        tolerance = stan_tol,
        label = expected_size === nothing ? :scalar_validation : Symbol("scalar_", expected_size),
        size = expected_size === nothing ? nothing : Symbol(expected_size),
        known_log_density = Float64(known[:log_density]),
        known_gradient = Vector{Float64}(known[:gradient]),
        known_tolerance = known_tol,
        fixture_path = relpath(stan_fixture_path, dirname(@__DIR__)),
        known_fixture_path = relpath(known_fixture_path, dirname(@__DIR__)),
        stan_model = String(stan[:stan_model]),
        fixture_sha256 = file_sha256(stan_fixture_path),
        known_fixture_sha256 = file_sha256(known_fixture_path),
        stan_model_sha256 = String(stan[:stan_model_sha256]),
    )
    @test validation_row.passed
    @test validation_row.gradient_checked
    @test validation_row.known_gradient_checked
    @test validation_row.n_observations == fd.N
    @test validation_row.n_parameters == length(x)
    return (;
        known,
        stan,
        data = fd,
        x,
        log_density = lp,
        gradient,
        validation_row,
    )
end

@testset "public docstrings" begin
    for name in (:FacetData, :ValidationIssue, :ValidationReport, :FacetSpec, :FacetDesign,
            :MFRMPrior, :MFRMLogDensity, :MFRMFit, :GMFRMFit, :MGMFRMFit,
            :anchor_linking_summary, :artifact_content_hash, :cached_fit,
            :benchmark_result_row, :benchmark_summary, :calibration_plot_data,
            :case_study_provenance_manifest,
            :constraint_table, :dff_report, :domain_compilation_summary,
            :expected_scores, :fair_average_summary,
            :falsification_rule_summary, :falsification_rules,
            :fit, :fit_archive_manifest, :fit_artifact, :fit_cache_key, :fit_metadata,
            :fit_reproduction_manifest,
            :fit_ready_parameter_layout, :fit_stats,
            :identification_declarations,
            :initial_params, :loglikelihood, :logposterior, :logprior,
            :kfold, :loo, :psis_loo, :loo_diagnostics,
            :linear_predictor_table, :linear_predictor_values,
            :calibration_table, :diagnostics,
            :comparison_evidence_row, :comparison_evidence_summary,
            :compare_kfold, :compare_models, :coverage_matrix, :coverage_summary, :design_row_table, :validate_design, :mcmc_diagnostics, :mfrm_spec, :getdesign,
            :model_equation, :model_ladder, :model_manifest, :parameter_block_diagnostics,
            :parameter_recovery, :parameter_recovery_plot_data, :parameter_recovery_summary,
            :pointwise_loglikelihood, :pointwise_loglikelihood_matrix, :posterior_predict,
            :posterior_predictive_check, :posterior_summary,
            :predictive_check_summary, :predictive_check_plot_data, :predictive_probabilities,
            :predictive_residuals, :predictive_variances,
            :prior_likelihood_sensitivity, :prior_predict, :prior_predictive_check,
            :fit_report_dossier, :fit_report_dossier_markdown,
            :fit_report_markdown, :fit_report_section, :fit_report_sections,
            :fit_report_rows,
            :load_fit_cache, :load_fit_report, :load_fit_report_dossier,
            :load_fit_report_bundle,
            :load_fit_report_tables, :rater_diagnostics, :rater_overlap,
            :residual_summary, :sampler_diagnostics, :save_fit_cache, :save_fit_report,
            :save_fit_report_dossier, :save_fit_report_dossier_markdown,
            :save_fit_report_bundle, :save_fit_report_markdown,
            :save_fit_report_tables,
            :sensitivity_comparison, :sensitivity_comparison_summary,
            :separation_reliability_summary, :simulation_grid,
            :simulation_grid_summary, :simulate_responses,
            :stan_validation_row, :stan_validation_summary,
            :threshold_map_data, :validation_suggestions, :evidence_metadata,
            :waic, :waic_diagnostics, :wright_map_data)
        @test has_doc(BayesianMGMFRM, name)
    end
    @test !isdefined(BayesianMGMFRM, :audit)
    @test !isdefined(BayesianMGMFRM, :AuditIssue)
    @test !isdefined(BayesianMGMFRM, :AuditReport)
end

@testset "FacetData long-format indexing" begin
    table = (
        examinee = ["E2", "E1", "E1", "E2", "E1", "E2", "E2", "E1"],
        rater = ["R2", "R1", "R2", "R1", "R1", "R2", "R1", "R2"],
        item = ["I2", "I1", "I1", "I2", "I2", "I1", "I1", "I2"],
        score = [2, 0, 1, 1, 2, 0, 1, 2],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)

    @test length(data) == 8
    @test data.person_levels == Any["E1", "E2"]
    @test data.rater_levels == Any["R1", "R2"]
    @test data.item_levels == Any["I1", "I2"]
    @test data.category_levels == [0, 1, 2]
    @test data.person == [2, 1, 1, 2, 1, 2, 2, 1]
    response_table = facet_response_table(data)
    @test response_table == (;
        person = table.examinee,
        rater = table.rater,
        item = table.item,
        score = table.score,
    )
    selected_response_table = facet_response_table(data; observations = [2, 5, 1])
    @test selected_response_table == (;
        person = ["E1", "E1", "E2"],
        rater = ["R1", "R1", "R2"],
        item = ["I1", "I2", "I2"],
        score = [0, 2, 2],
    )
    selected_roundtrip = FacetData(selected_response_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score)
    @test selected_roundtrip.person_levels == Any["E1", "E2"]
    @test selected_roundtrip.rater_levels == Any["R1", "R2"]
    @test selected_roundtrip.item_levels == Any["I1", "I2"]
    @test facet_response_table(data; observations = Int[]).score == Int[]
    @test_throws ArgumentError facet_response_table(data; observations = [1, 1])
    @test_throws ArgumentError facet_response_table(data; observations = [0])
    @test_throws ArgumentError facet_response_table(data; observations = [data.n + 1])
    @test_throws ArgumentError facet_response_table(data; observations = [true])

    reordered = (
        examinee = reverse(table.examinee),
        rater = reverse(table.rater),
        item = reverse(table.item),
        score = reverse(table.score),
    )
    data2 = FacetData(reordered; person = :examinee, rater = :rater, item = :item, score = :score)
    @test data2.person_levels == data.person_levels
    @test data2.rater_levels == data.rater_levels
    @test data2.item_levels == data.item_levels
    @test data2.category_levels == data.category_levels

    numeric_labels = (
        examinee = [1, 10, 2, 1],
        rater = ["R1", "R1", "R1", "R1"],
        item = ["I1", "I1", "I1", "I1"],
        score = [0, 1, 0, 1],
    )
    data3 = FacetData(numeric_labels; person = :examinee, rater = :rater, item = :item, score = :score)
    @test data3.person_levels == Any[1, 2, 10]

    optional_table = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R2"],
        item = ["I1", "I2", "I1", "I2"],
        score = [0, 1, 1, 2],
        treatment = ["A", "A", "B", "B"],
        task_name = ["T1", "T2", "T1", "T2"],
    )
    optional_data = FacetData(optional_table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :treatment,
        task = :task_name)
    optional_response_table =
        facet_response_table(optional_data; observations = [4, 2])
    @test propertynames(optional_response_table) ==
        (:person, :rater, :item, :score, :group, :task)
    @test optional_response_table.person == ["E2", "E1"]
    @test optional_response_table.rater == ["R2", "R2"]
    @test optional_response_table.item == ["I2", "I2"]
    @test optional_response_table.score == [2, 1]
    @test optional_response_table.group == ["B", "A"]
    @test optional_response_table.task == ["T2", "T2"]

    bool_scores = (
        examinee = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [false, true],
    )
    @test_throws ArgumentError FacetData(bool_scores; person = :examinee, rater = :rater, item = :item, score = :score)

    @test_throws ErrorException FacetData(ExplodingTable(); person = :examinee, rater = :rater, item = :item, score = :score)
    @test_throws MethodError FacetData(InternalMethodErrorTable(); person = :examinee, rater = :rater, item = :item, score = :score)
end

@testset "pre-fit validation" begin
    empty = (
        examinee = String[],
        rater = String[],
        item = String[],
        score = Int[],
    )
    empty_data = FacetData(empty; person = :examinee, rater = :rater, item = :item, score = :score)
    empty_report = validate_design(empty_data)
    @test !empty_report.passed
    @test has_issue(empty_report, :empty_data)

    connected = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    connected_data = FacetData(connected; person = :examinee, rater = :rater, item = :item, score = :score)
    connected_report = validate_design(connected_data)
    @test connected_report.passed
    @test !has_issue(connected_report, :disconnected_design)
    @test !has_issue(connected_report, :rank_deficient_design)
    @test has_issue(connected_report, :unobserved_item_category)

    rank_deficient_connected = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R2", "R2", "R1"],
        item = ["I1", "I1", "I2", "I2"],
        score = [0, 1, 2, 1],
    )
    rank_data = FacetData(rank_deficient_connected; person = :examinee, rater = :rater, item = :item, score = :score)
    rank_report = validate_design(rank_data)
    @test !rank_report.passed
    @test !has_issue(rank_report, :disconnected_design)
    @test has_issue(rank_report, :rank_deficient_design)
    @test_throws ArgumentError mfrm_spec(rank_data)

    disconnected = (
        examinee = ["E1", "E1", "E2", "E2"],
        rater = ["R1", "R1", "R2", "R2"],
        item = ["I1", "I1", "I2", "I2"],
        score = [0, 1, 0, 1],
    )
    disconnected_data = FacetData(disconnected; person = :examinee, rater = :rater, item = :item, score = :score)
    disconnected_report = validate_design(disconnected_data)
    @test !disconnected_report.passed
    @test has_issue(disconnected_report, :disconnected_design)
    @test_throws ArgumentError mfrm_spec(disconnected_data)

    skipped_category = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 2, 0, 2, 0, 2],
    )
    skipped_data = FacetData(skipped_category; person = :examinee, rater = :rater, item = :item, score = :score)
    skipped_report = validate_design(skipped_data)
    @test skipped_report.passed
    @test skipped_data.category_levels == [0, 1, 2]
    @test skipped_report.category_counts[1] == 0
    @test has_issue(skipped_report, :unused_interior_category)
    @test has_issue(skipped_report, :unobserved_item_category)

    optional_singleton = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "A", "B"],
        score = [0, 1, 2, 1, 0, 2],
    )
    optional_data = FacetData(optional_singleton;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    optional_report = validate_design(optional_data)
    @test has_issue(optional_report, :singleton_facet_level, :group)

    dff_empty = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    dff_data = FacetData(dff_empty;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    dff_report = validate_design(dff_data; bias = [(:rater, :group)])
    @test dff_report.passed
    @test has_issue(dff_report, :empty_dff_cell)
    @test has_issue(dff_report, :potential_dff_confounding)
    @test dff_report.dff_counts[(:rater, :group)][("R1", "B")] == 0
    dff_suggestions = validation_suggestions(dff_report)
    @test any(row -> row.code === :empty_dff_cell && row.action === :pool_or_remove_dff_term,
        dff_suggestions)
    @test all(row -> haskey(row.context, :term) || row.code !== :empty_dff_cell,
        dff_suggestions)

    invalid_bias_report = validate_design(connected_data; bias = [:rater])
    @test !invalid_bias_report.passed
    @test has_issue(invalid_bias_report, :invalid_bias_term)
    invalid_bias_suggestion = only(filter(row -> row.code === :invalid_bias_term,
        validation_suggestions(invalid_bias_report)))
    @test invalid_bias_suggestion.action === :fix_bias_syntax

    unknown_bias_report = validate_design(connected_data; bias = [(:rater, :group)])
    @test !unknown_bias_report.passed
    @test has_issue(unknown_bias_report, :unknown_bias_facet)

    sparse_dff_report = validate_design(dff_data; bias = [(:rater, :group)], min_cell_count = 3)
    @test sparse_dff_report.passed
    @test has_issue(sparse_dff_report, :sparse_dff_cell)
    @test_throws ArgumentError validate_design(connected_data; min_cell_count = 0)
end

@testset "minimal MFRM spec and design" begin
    table = (
        examinee = ["E1", "E1"],
        rater = ["R1", "R1"],
        item = ["I1", "I1"],
        score = [0, 1],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)
    spec = mfrm_spec(data; thresholds = :partial_credit)
    design = getdesign(spec)

    ladder = model_ladder()
    @test any(row -> row.family === :mfrm && row.estimation_status === :fit_supported, ladder)
    @test any(row -> row.family === :gmfrm &&
        row.estimation_status === :experimental_public &&
        row.experimental_public,
        ladder)
    @test any(row -> row.family === :mgmfrm &&
        row.estimation_status === :experimental_public &&
        row.experimental_public,
        ladder)
    @test any(row -> row.family === :gmfrm && row.estimation_status === :specified_only, ladder)
    @test any(row -> row.family === :mgmfrm && row.estimation_status === :specified_only, ladder)
    release_scope = release_scope_summary()
    @test release_scope.schema == "bayesianmgmfrm.release_scope_summary.v1"
    @test release_scope.summary.n_public_fit_surfaces == 3
    @test release_scope.summary.n_guarded_experimental_surfaces == 2
    @test release_scope.summary.minimal_mfrm_fit_allowed
    @test release_scope.summary.scalar_gmfrm_guarded_fit_allowed
    @test release_scope.summary.fixed_q_mgmfrm_guarded_fit_allowed
    @test !release_scope.summary.broader_generalized_fit_allowed
    @test !release_scope.summary.dff_model_effects_allowed
    @test !release_scope.summary.model_weight_claims_allowed
    @test !release_scope.summary.publication_or_registration_action
    @test isempty(release_scope.evidence_rows)
    @test any(row -> row.surface === :scalar_gmfrm_guarded_experimental &&
        row.entrypoint == "fit(spec; experimental = true)",
        release_scope.public_fit_surfaces)
    @test any(row -> row.family === :mgmfrm && row.option === :q_matrix &&
        row.status === :blocked,
        release_scope.blocked_public_options)
    @test any(row -> row.claim === :model_weight_or_superiority &&
        row.status === :blocked,
        release_scope.blocked_claims)
    release_scope_with_evidence = release_scope_summary(; include_evidence = true)
    @test release_scope_with_evidence.summary.n_evidence_rows ==
        length(release_scope_with_evidence.evidence_rows)
    @test release_scope_with_evidence.summary.n_evidence_rows >
        release_scope.summary.n_evidence_rows
    @test any(row -> row.family === :gmfrm &&
        row.evidence === :guarded_fit_method_wiring,
        release_scope_with_evidence.evidence_rows)
    @test any(row -> row.family === :mgmfrm &&
        row.evidence === :guarded_fit_public_exposure_review,
        release_scope_with_evidence.evidence_rows)
    case_provenance = case_study_provenance_manifest()
    @test case_provenance.schema ==
        "bayesianmgmfrm.case_study_provenance_manifest.v1"
    @test case_provenance.object === :case_study_provenance_manifest
    @test case_provenance.status === :synchronized
    @test case_provenance.summary.passed
    @test case_provenance.summary.n_source_records == 2
    @test case_provenance.summary.n_archive_records == 4
    @test case_provenance.summary.n_publication_facing_archives == 2
    @test case_provenance.summary.all_source_records_anonymized
    @test case_provenance.summary.all_license_records_declared
    @test case_provenance.summary.publication_archives_synchronized
    @test case_provenance.summary.no_public_source_release
    @test case_provenance.summary.no_publication_actions
    @test !case_provenance.summary.license_grant
    @test !case_provenance.summary.irb_determination
    @test !case_provenance.summary.publication_or_registration_action
    @test !case_provenance.summary.manuscript_claims_allowed
    @test any(row -> row.archive === :full_paper_reproduction_archive &&
        row.publication_facing &&
        row.provenance_sync_passed,
        case_provenance.archive_records)
    @test_throws ArgumentError case_study_provenance_manifest(
        source_records = NamedTuple[])
    incomplete_provenance = case_study_provenance_manifest(
        source_records = (;
            source_id = :local_case,
            license_status = :missing,
            anonymization_status = :pseudonymized,
            direct_identifiers_removed = true,
        ))
    @test incomplete_provenance.status === :incomplete
    @test !incomplete_provenance.summary.all_license_records_declared
    @test spec.family === :mfrm
    @test spec.dimensions == 1
    @test spec.discrimination === :none
    @test spec.estimation_status === :fit_supported
    @test spec.q_matrix === nothing
    equation = model_equation(spec)
    @test equation.schema == "bayesianmgmfrm.model_equation.v1"
    @test equation.family === :mfrm
    @test equation.probability_form === :adjacent_category_softmax
    @test equation.fit_ready
    @test isempty(equation.implementation_gaps)
    @test :threshold_steps in equation.required_blocks
    spec_constraints = constraint_table(spec)
    @test any(row -> row.block === :person && row.status === :implemented, spec_constraints)
    @test any(row -> row.block === :thresholds && row.constraint === :sum_to_zero, spec_constraints)
    spec_identification = identification_declarations(spec)
    @test any(row -> row.block === :rater && row.rule === :reference &&
        row.components == (:reference,), spec_identification)
    @test any(row -> row.block === :thresholds && row.rule === :sum_to_zero &&
        row.components == (:sum_to_zero,), spec_identification)
    design_constraints = constraint_table(design)
    @test any(row -> row.block === :person && row.n_parameters == 1 &&
        row.parameter_names == ["person[E1]"], design_constraints)
    design_identification = identification_declarations(design)
    @test any(row -> row.block === :person && row.rule === :free &&
        row.n_parameters == 1 &&
        row.parameter_names == ["person[E1]"], design_identification)
    @test any(row -> row.block === :rater && row.rule === :reference &&
        row.n_parameters == 0 &&
        isempty(row.parameter_names), design_identification)
    binary_layout = fit_ready_parameter_layout(spec)
    @test binary_layout.schema == "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test binary_layout.family === :mfrm
    @test binary_layout.fit_ready
    @test binary_layout.public_fit
    @test binary_layout.parameterization === :direct
    @test binary_layout.parameter_names == design.parameter_names
    @test binary_layout.raw_parameter_names == design.parameter_names
    @test binary_layout.constrained_parameter_names == design.parameter_names
    @test any(row -> row.raw_block === :person &&
        row.constrained_block === :person &&
        row.transform === :identity &&
        row.raw_parameter_names == ["person[E1]"],
        binary_layout.transforms)
    binary_domain = domain_compilation_summary(spec)
    @test any(row -> row.domain_option === :family &&
        row.compiled_role === :likelihood_kernel &&
        row.fit_ready &&
        row.public_fit,
        binary_domain)
    binary_scoring = only(filter(row -> row.compiled_role === :scoring_vector,
        binary_domain))
    @test binary_scoring.domain_option === :thresholds
    @test binary_scoring.block === :thresholds
    @test binary_scoring.scoring_vector == data.category_levels
    @test binary_scoring.constraint === :sum_to_zero
    @test binary_scoring.prior === :normal
    @test any(row -> row.block === :person &&
        row.compiled_role === :additive_block &&
        row.parameter_names == ["person[E1]"],
        binary_domain)

    data_manifest = model_manifest(data)
    @test data_manifest.schema == "bayesianmgmfrm.model_manifest.v1"
    @test data_manifest.object === :data
    @test data_manifest.data.n_observations == data.n
    @test data_manifest.data.columns.person === :examinee
    @test data_manifest.data.levels.category == data.category_levels

    @test design.parameter_names == ["person[E1]"]
    @test design.blocks[:person] == 1:1
    @test isempty(design.blocks[:rater])
    @test isempty(design.blocks[:item])
    @test isempty(design.blocks[:thresholds])
    @test design.identification[:person] === :free
    @test design.identification[:rater] === :reference_first
    @test design.identification[:item] === :reference_first
    @test design.identification[:thresholds] === :sum_to_zero

    params = [0.4]
    pointwise = pointwise_loglikelihood(design, params)
    binary_predictor_values = linear_predictor_values(design, params)
    location = 0.4
    eta0 = 0.0
    eta1 = location
    denom = log(exp(eta0) + exp(eta1))
    @test pointwise[1] ≈ eta0 - denom
    @test pointwise[2] ≈ eta1 - denom
    @test length(binary_predictor_values) == data.n * length(data.category_levels)
    @test binary_predictor_values[1].eta ≈ eta0
    @test binary_predictor_values[1].location_value ≈ location
    @test isempty(binary_predictor_values[1].step_values)
    @test binary_predictor_values[2].eta ≈ eta1
    @test binary_predictor_values[2].step_values == [0.0]
    @test binary_predictor_values[2].log_denominator ≈ denom
    @test binary_predictor_values[2].log_probability ≈ eta1 - denom

    summary = coverage_summary(spec)
    @test summary.n_ratings == 2
    @test summary.n_persons == 1
    @test summary.n_raters == 1
    @test summary.n_items == 1
    @test summary.validation.passed
    @test [row.category for row in summary.category_counts] == [0, 1]
    @test sum(row.count for row in summary.category_counts) == 2
    @test any(row -> row.facet === :person && row.n_levels == 1, summary.facet_summary)

    matrix = coverage_matrix(spec)
    @test matrix.row_facet === :rater
    @test matrix.column_facet === :person
    @test matrix.row_levels == Any["R1"]
    @test matrix.column_levels == Any["E1"]
    @test matrix.counts == reshape([2], 1, 1)

    binary_thresholds = threshold_map_data(design; params)
    @test length(binary_thresholds) == 1
    @test binary_thresholds[1].status === :fixed_zero
    @test binary_thresholds[1].value == 0.0
    binary_rows = design_row_table(design)
    @test length(binary_rows) == 2
    @test binary_rows[1].person_parameter_indices == [1]
    @test binary_rows[1].rater_parameter_index === missing
    @test isempty(binary_rows[1].threshold_path)
    @test isequal(binary_rows[2].threshold_parameter_indices, [missing])
    @test binary_rows[2].threshold_statuses == [:fixed_zero]

    identified = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        task = ["T1", "T1", "T2", "T1", "T2", "T2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    identified_data = FacetData(identified; person = :examinee, rater = :rater, item = :item, score = :score, task = :task)
    identified_spec = mfrm_spec(identified_data; thresholds = :partial_credit)
    identified_design = getdesign(identified_spec)
    spec_manifest = model_manifest(identified_spec)
    @test spec_manifest.object === :spec
    @test spec_manifest.spec.family === :mfrm
    @test spec_manifest.spec.scope === :minimal_mfrm_rsm_pcm
    @test spec_manifest.spec.thresholds === :partial_credit
    @test spec_manifest.spec.dimensions == 1
    @test spec_manifest.spec.discrimination === :none
    @test spec_manifest.spec.estimation_status === :fit_supported
    @test spec_manifest.spec.equation.fit_ready
    @test spec_manifest.spec.equation.kernel == model_equation(identified_spec).kernel
    @test any(row -> row.block === :thresholds && row.constraint === :sum_to_zero,
        spec_manifest.spec.constraints)
    @test any(row -> row.block === :item && row.rule === :reference,
        spec_manifest.spec.identification_declarations)
    @test spec_manifest.validation.passed
    @test spec_manifest.data.optional_facets == [:task]
    @test spec_manifest.data.levels.optional.task == identified_data.optional_levels[:task]
    design_manifest = model_manifest(identified_design)
    @test design_manifest.object === :design
    @test design_manifest.design.n_parameters == length(identified_design.parameter_names)
    @test design_manifest.design.parameter_names == identified_design.parameter_names
    @test any(row -> row.block === :thresholds && row.identification === :sum_to_zero,
        design_manifest.design.blocks)
    @test any(row -> row.block === :rater && row.n_parameters == 1,
        design_manifest.design.constraints)
    @test any(row -> row.block === :thresholds &&
        :sum_to_zero in row.components &&
        row.n_parameters == 2,
        design_manifest.design.identification_declarations)
    @test design_manifest.design.identification.rater === :reference_first
    @test design_manifest.design.raw_parameterization === nothing
    @test identified_design.parameter_names == [
        "person[E1]",
        "person[E2]",
        "rater[R2]",
        "item[I2]",
        "step[item=I1,1]",
        "step[item=I2,1]",
    ]
    identified_layout = fit_ready_parameter_layout(identified_design)
    @test identified_layout.n_parameters == length(identified_design.parameter_names)
    @test [row.block for row in identified_layout.blocks] ==
        sort([row.block for row in identified_layout.blocks]; by = string)
    @test any(row -> row.block === :thresholds &&
        row.parameter_names == ["step[item=I1,1]", "step[item=I2,1]"],
        identified_layout.blocks)
    @test any(row -> row.raw_block === :thresholds &&
        row.constrained_block === :thresholds &&
        row.constraint === :sum_to_zero,
        identified_layout.transforms)
    identified_domain = domain_compilation_summary(identified_spec)
    identified_design_domain = domain_compilation_summary(identified_design)
    @test length(identified_domain) == length(identified_design_domain)
    @test [row.compiled_role for row in identified_domain] ==
        [row.compiled_role for row in identified_design_domain]
    @test isequal(
        [row.block for row in identified_domain],
        [row.block for row in identified_design_domain],
    )
    identified_threshold_domain = only(filter(row ->
        row.compiled_role === :scoring_vector,
        identified_domain))
    @test identified_threshold_domain.block === :thresholds
    @test identified_threshold_domain.parameter_names ==
        ["step[item=I1,1]", "step[item=I2,1]"]
    @test identified_threshold_domain.scoring_vector == identified_data.category_levels
    @test identified_threshold_domain.validation_requirement === :ordinal_score_categories
    identified_item_domain = only(filter(row -> row.block === :item &&
        row.compiled_role === :additive_block,
        identified_domain))
    @test identified_item_domain.constraint === :reference_first
    @test identified_item_domain.prior_block === :item
    @test identified_item_domain.prior === :normal
    identified_validation_domain = only(filter(row ->
        row.domain_option === :validation &&
        row.compiled_role === :validation_requirement,
        identified_domain))
    @test identified_validation_domain.status === :passed
    @test identified_validation_domain.option_value.passed

    identified_params = [0.4, -0.1, 0.2, -0.3, 0.5, -0.25]
    identified_pointwise = pointwise_loglikelihood(identified_design, identified_params)
    row2_location = 0.4 - 0.2 - 0.0
    row2_etas = [0.0, row2_location - 0.5, 2row2_location]
    @test identified_pointwise[2] ≈ row2_etas[2] - (maximum(row2_etas) + log(sum(exp.(row2_etas .- maximum(row2_etas)))))
    row3_location = 0.4 - 0.0 - (-0.3)
    row3_etas = [0.0, row3_location - (-0.25), 2row3_location]
    @test identified_pointwise[3] ≈ row3_etas[3] - (maximum(row3_etas) + log(sum(exp.(row3_etas .- maximum(row3_etas)))))

    raw_person = [0.4, -0.1]
    raw_rater = [0.0, 0.2]
    raw_item = [0.0, -0.3]
    raw_steps = [[0.5, -0.5], [-0.25, 0.25]]
    @test identified_pointwise ≈ raw_pcm_pointwise(identified_data, raw_person, raw_rater, raw_item, raw_steps)

    rater_person = coverage_matrix(identified_spec; rows = :rater, columns = :person)
    @test rater_person.row_levels == Any["R1", "R2"]
    @test rater_person.column_levels == Any["E1", "E2"]
    @test rater_person.counts == [2 2; 1 1]
    task_rater = coverage_matrix(identified_data; rows = :task, columns = :rater)
    @test task_rater.row_levels == Any["T1", "T2"]
    @test task_rater.column_levels == Any["R1", "R2"]
    @test task_rater.counts == [2 1; 2 1]
    @test_throws ArgumentError coverage_matrix(data; rows = :task, columns = :rater)

    overlap = rater_overlap(identified_data)
    @test length(overlap) == 1
    @test overlap[1].rater_a == "R1"
    @test overlap[1].rater_b == "R2"
    @test overlap[1].shared_units == 2
    @test overlap[1].jaccard ≈ 2 / 4

    task_overlap = rater_overlap(identified_spec; unit = :person_task)
    @test only(task_overlap).shared_units == 2
    @test_throws ArgumentError rater_overlap(data; unit = :person_task)

    pcm_thresholds = threshold_map_data(identified_design; params = identified_params)
    @test length(pcm_thresholds) == 4
    @test pcm_thresholds[1].parameter_name == "step[item=I1,1]"
    @test pcm_thresholds[1].value == 0.5
    @test pcm_thresholds[2].status === :sum_to_zero_derived
    @test pcm_thresholds[2].value == -0.5
    @test pcm_thresholds[4].value == 0.25
    identified_rows = design_row_table(identified_spec)
    @test length(identified_rows) == identified_data.n
    @test identified_rows[2].person_parameter_indices == [1]
    @test identified_rows[2].rater_parameter_index == 3
    @test identified_rows[2].rater_parameter_name == "rater[R2]"
    @test identified_rows[2].item_parameter_index === missing
    @test identified_rows[2].threshold_parameter_indices == [5]
    @test identified_rows[2].threshold_parameter_names == ["step[item=I1,1]"]
    @test identified_rows[3].item_parameter_index == 4
    @test isequal(identified_rows[3].threshold_parameter_indices, [6, missing])
    @test identified_rows[3].threshold_statuses == [:free, :sum_to_zero_derived]
    @test isempty(identified_rows[3].loading_parameter_indices)
    @test isempty(identified_rows[3].discrimination_parameter_indices)
    identified_predictors = linear_predictor_table(identified_spec)
    identified_predictor_values = linear_predictor_values(identified_spec, identified_params)
    @test length(identified_predictors) == identified_data.n * length(identified_data.category_levels)
    @test length(identified_predictor_values) == length(identified_predictors)
    @test identified_predictors[1].kernel === :mfrm_additive
    @test identified_predictors[1].row == 1
    @test identified_predictors[1].category == 0
    @test identified_predictors[1].location_multiplier == 0
    @test isempty(identified_predictors[1].step_parameter_indices)
    @test identified_predictors[2].category == 1
    @test identified_predictors[2].location_multiplier == 1
    @test identified_predictors[2].step_parameter_names == ["step[item=I1,1]"]
    @test identified_predictors[3].category == 2
    @test identified_predictors[3].location_multiplier == 2
    @test isequal(identified_predictors[3].step_parameter_indices, [5, missing])
    @test identified_predictors[3].step_blocks == [:thresholds, :thresholds]
    @test only(filter(row -> row.row == 3 && row.category == 2, identified_predictors)).observed
    row2_cat1_value = only(filter(row -> row.row == 2 && row.category == 1, identified_predictor_values))
    @test row2_cat1_value.person_value ≈ 0.4
    @test row2_cat1_value.rater_value ≈ 0.2
    @test row2_cat1_value.item_value ≈ 0.0
    @test row2_cat1_value.location_value ≈ row2_location
    @test row2_cat1_value.step_values == [0.5]
    @test row2_cat1_value.step_sum ≈ 0.5
    @test row2_cat1_value.eta ≈ row2_etas[2]
    @test row2_cat1_value.log_probability ≈ identified_pointwise[2]
    row3_cat2_value = only(filter(row -> row.row == 3 && row.category == 2, identified_predictor_values))
    @test row3_cat2_value.location_value ≈ row3_location
    @test row3_cat2_value.step_values ≈ [-0.25, 0.25]
    @test row3_cat2_value.step_sum ≈ 0.0
    @test row3_cat2_value.eta ≈ row3_etas[3]
    @test row3_cat2_value.log_probability ≈ identified_pointwise[3]
    @test [row.log_probability for row in filter(row -> row.observed, identified_predictor_values)] ≈
        identified_pointwise

    shifted_person_rater = raw_pcm_pointwise(
        identified_data,
        raw_person .+ 1.3,
        raw_rater .+ 1.3,
        raw_item,
        raw_steps,
    )
    shifted_person_item = raw_pcm_pointwise(
        identified_data,
        raw_person .- 0.7,
        raw_rater,
        raw_item .- 0.7,
        raw_steps,
    )
    shifted_item_steps = raw_pcm_pointwise(
        identified_data,
        raw_person,
        raw_rater,
        [raw_item[1], raw_item[2] + 0.9],
        [raw_steps[1], raw_steps[2] .- 0.9],
    )
    @test identified_pointwise ≈ shifted_person_rater
    @test identified_pointwise ≈ shifted_person_item
    @test identified_pointwise ≈ shifted_item_steps

    rsm_spec = mfrm_spec(identified_data; thresholds = :rating_scale)
    rsm_design = getdesign(rsm_spec)
    @test rsm_design.parameter_names[end] == "step[1]"
    @test count(name -> startswith(name, "step"), rsm_design.parameter_names) == 1
    rsm_params = [0.4, -0.1, 0.2, -0.3, 0.5]
    rsm_pointwise = pointwise_loglikelihood(rsm_design, rsm_params)
    rsm_predictor_values = linear_predictor_values(rsm_design, rsm_params)
    rsm_row3_location = 0.4 - 0.0 - (-0.3)
    rsm_row3_etas = [0.0, rsm_row3_location - 0.5, 2rsm_row3_location]
    @test rsm_pointwise[3] ≈ rsm_row3_etas[3] - test_logsumexp(rsm_row3_etas)
    rsm_row3_cat2 = only(filter(row -> row.row == 3 && row.category == 2, rsm_predictor_values))
    @test rsm_row3_cat2.step_values ≈ [0.5, -0.5]
    @test rsm_row3_cat2.eta ≈ rsm_row3_etas[3]
    @test rsm_row3_cat2.log_probability ≈ rsm_pointwise[3]

    rsm_thresholds = threshold_map_data(rsm_design; params = rsm_params)
    @test length(rsm_thresholds) == 2
    @test rsm_thresholds[1].item === missing
    @test rsm_thresholds[1].value == 0.5
    @test rsm_thresholds[2].status === :sum_to_zero_derived
    @test rsm_thresholds[2].value == -0.5

    anchored_spec = mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [
            (block = :item, value = 0.0, type = :hard),
            (block = :rater, value = 0.0, type = :soft, scale = 0.25),
        ])
    @test anchored_spec.estimation_status === :specified_only
    anchored_identification = identification_declarations(anchored_spec)
    hard_anchor = only(filter(row -> row.rule === :hard_anchor, anchored_identification))
    @test hard_anchor.block === :item
    @test hard_anchor.components == (:hard_anchor, :fixed)
    @test hard_anchor.anchor_type === :hard_anchor
    @test hard_anchor.anchor_value == 0.0
    @test ismissing(hard_anchor.anchor_scale)
    soft_anchor = only(filter(row -> row.rule === :soft_anchor, anchored_identification))
    @test soft_anchor.block === :rater
    @test soft_anchor.anchor_type === :soft_anchor
    @test soft_anchor.anchor_value == 0.0
    @test soft_anchor.anchor_scale == 0.25
    @test any(row -> row.constraint === :hard_anchor, constraint_table(anchored_spec))
    @test any(row -> row.constraint === :soft_anchor, constraint_table(anchored_spec))
    @test_throws ArgumentError domain_compilation_summary(anchored_spec)
    anchored_domain = domain_compilation_summary(anchored_spec; preview = true)
    hard_anchor_domain = only(filter(row ->
        row.domain_option === :anchors &&
        row.constraint === :hard_anchor,
        anchored_domain))
    @test hard_anchor_domain.block === :item
    @test hard_anchor_domain.compiled_role === :constraint
    @test hard_anchor_domain.compiler_stage === :specified_only_preview
    @test !hard_anchor_domain.fit_ready
    soft_anchor_domain = only(filter(row ->
        row.domain_option === :anchors &&
        row.constraint === :soft_anchor,
        anchored_domain))
    @test soft_anchor_domain.block === :rater
    @test soft_anchor_domain.transform === :soft_anchor_prior
    @test soft_anchor_domain.validation_requirement === :anchor_declared
    anchor_linking = anchor_linking_summary(anchored_spec; min_shared_units = 2)
    @test anchor_linking.schema == "bayesianmgmfrm.anchor_linking_summary.v1"
    @test anchor_linking.passed
    @test anchor_linking.family === :mfrm
    @test anchor_linking.estimation_status === :specified_only
    @test anchor_linking.anchor_status === :declared
    @test anchor_linking.n_anchors == 2
    @test anchor_linking.n_hard_anchors == 1
    @test anchor_linking.n_soft_anchors == 1
    @test anchor_linking.n_anchor_target_failures == 0
    @test all(row -> row.passed, anchor_linking.anchor_rows)
    @test anchor_linking.rater_linking_status === :connected
    @test anchor_linking.n_rater_components == 1
    @test anchor_linking.rater_components == (("R1", "R2"),)
    @test anchor_linking.largest_rater_component == 2
    @test anchor_linking.n_links_at_or_above_min == 1
    @test anchor_linking.minimum_shared_units == 2
    @test anchor_linking.anchor_sensitivity_status === :not_supplied
    weak_linking = anchor_linking_summary(identified_spec; min_shared_units = 3)
    @test !weak_linking.passed
    @test weak_linking.rater_linking_status === :disconnected
    @test weak_linking.n_rater_components == 2
    @test weak_linking.n_weak_links == 1
    data_only_linking = anchor_linking_summary(identified_data)
    @test ismissing(data_only_linking.family)
    @test data_only_linking.anchor_status === :not_declared
    @test data_only_linking.n_anchors == 0
    targeted_anchor_spec = mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [(block = :rater, level = "R1", value = 0.0, type = :hard)])
    targeted_linking = anchor_linking_summary(targeted_anchor_spec)
    @test targeted_linking.passed
    @test only(targeted_linking.anchor_rows).target == "R1"
    @test only(targeted_linking.anchor_rows).target_found === true
    invalid_anchor_spec = mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [(block = :rater, level = "R-missing", value = 0.0, type = :hard)])
    invalid_linking = anchor_linking_summary(invalid_anchor_spec)
    @test !invalid_linking.passed
    @test invalid_linking.anchor_status === :invalid_targets
    @test invalid_linking.n_anchor_target_failures == 1
    @test only(invalid_linking.anchor_rows).status === :anchor_target_not_in_data
    @test_throws ArgumentError anchor_linking_summary(identified_spec; min_shared_units = 0)
    @test_throws ArgumentError mfrm_spec(identified_data;
        thresholds = :partial_credit,
        anchors = [(block = :item, value = 0.0, type = :soft)])

    gmfrm_spec = mfrm_spec(identified_data; family = :gmfrm, discrimination = :rater)
    @test gmfrm_spec.family === :gmfrm
    @test gmfrm_spec.dimensions == 1
    @test gmfrm_spec.discrimination === :rater
    @test gmfrm_spec.estimation_status === :specified_only
    @test any(row -> row.block === :item_discrimination && row.constraint === :geometric_mean_one,
        constraint_table(gmfrm_spec))
    @test any(row -> row.block === :rater_consistency && row.transform === :log_link,
        constraint_table(gmfrm_spec))
    @test any(row -> row.block === :rater_steps && row.constraint === :first_step_zero_sum_to_zero,
        constraint_table(gmfrm_spec))
    gmfrm_identification = identification_declarations(gmfrm_spec)
    @test any(row -> row.block === :item &&
        row.rule === :sum_to_zero,
        gmfrm_identification)
    @test any(row -> row.block === :item_discrimination &&
        row.rule === :geometric_mean_one &&
        row.components == (:geometric_mean_one,),
        gmfrm_identification)
    @test any(row -> row.block === :rater_steps &&
        row.rule === :fixed &&
        row.components == (:fixed, :sum_to_zero),
        gmfrm_identification)
    @test model_manifest(gmfrm_spec).spec.scope === :planned_generalized_mfrm
    gmfrm_equation = model_equation(gmfrm_spec)
    @test gmfrm_equation.family === :gmfrm
    @test !gmfrm_equation.fit_ready
    @test :item_discrimination in gmfrm_equation.required_blocks
    @test :rater_consistency in gmfrm_equation.required_blocks
    @test :identified_transform_for_item_discrimination_product_constraint in
        gmfrm_equation.implementation_gaps
    @test :literature_gmfrm_likelihood_kernel in
        gmfrm_equation.implementation_gaps
    gmfrm_preview = getdesign(gmfrm_spec; preview = true)
    @test gmfrm_preview.spec === gmfrm_spec
    @test gmfrm_preview.identification[:item] === :sum_to_zero
    @test gmfrm_preview.identification[:item_discrimination] === :geometric_mean_one
    @test gmfrm_preview.identification[:rater_consistency] === :positive
    @test gmfrm_preview.identification[:rater_steps] === :first_step_zero_sum_to_zero
    gmfrm_preview_identification = identification_declarations(gmfrm_preview)
    gmfrm_item_identification = only(filter(row ->
        row.block === :item && row.rule === :sum_to_zero,
        gmfrm_preview_identification))
    @test gmfrm_item_identification.n_parameters == 2
    @test gmfrm_item_identification.parameter_names == ["item[I1]", "item[I2]"]
    @test gmfrm_preview.parameter_names[gmfrm_preview.blocks[:item_discrimination]] == [
        "item_discrimination[item=I1]",
        "item_discrimination[item=I2]",
    ]
    @test gmfrm_preview.parameter_names[gmfrm_preview.blocks[:rater_consistency]] == [
        "rater_consistency[rater=R1]",
        "rater_consistency[rater=R2]",
    ]
    @test gmfrm_preview.parameter_names[gmfrm_preview.blocks[:rater_steps]] == [
        "rater_step[rater=R1,m=2]",
        "rater_step[rater=R2,m=2]",
    ]
    @test length(gmfrm_preview.parameter_names) == 12
    @test_throws ArgumentError design_row_table(gmfrm_spec)
    gmfrm_rows = design_row_table(gmfrm_spec; preview = true)
    @test gmfrm_rows[1].rater_parameter_name == "rater[R1]"
    @test gmfrm_rows[1].item_discrimination_parameter_name == "item_discrimination[item=I1]"
    @test gmfrm_rows[1].rater_consistency_parameter_name == "rater_consistency[rater=R1]"
    @test gmfrm_rows[2].rater_consistency_parameter_name == "rater_consistency[rater=R2]"
    @test gmfrm_rows[2].threshold_parameter_names == ["rater_step[rater=R2,m=2]"]
    @test gmfrm_rows[2].threshold_blocks == [:rater_steps]
    @test isempty(gmfrm_rows[2].discrimination_parameter_indices)
    @test isempty(gmfrm_rows[2].loading_parameter_indices)
    @test_throws ArgumentError linear_predictor_table(gmfrm_spec)
    gmfrm_predictors = linear_predictor_table(gmfrm_spec; preview = true)
    @test length(gmfrm_predictors) == identified_data.n * length(identified_data.category_levels)
    @test gmfrm_predictors[1].kernel === :gmfrm_source_aligned
    @test gmfrm_predictors[1].location_multiplier == 0
    @test isempty(gmfrm_predictors[1].step_parameter_indices)
    gmfrm_row2_cat1 = only(filter(row -> row.row == 2 && row.category == 1, gmfrm_predictors))
    @test gmfrm_row2_cat1.observed
    @test gmfrm_row2_cat1.location_multiplier == 1
    @test gmfrm_row2_cat1.rater_consistency_parameter_name == "rater_consistency[rater=R2]"
    @test gmfrm_row2_cat1.item_discrimination_parameter_name == "item_discrimination[item=I1]"
    @test gmfrm_row2_cat1.step_parameter_names == ["rater_step[rater=R2,m=2]"]
    gmfrm_row3_cat2 = only(filter(row -> row.row == 3 && row.category == 2, gmfrm_predictors))
    @test gmfrm_row3_cat2.location_multiplier == 2
    @test isequal(gmfrm_row3_cat2.step_parameter_names, ["rater_step[rater=R1,m=2]", missing])
    @test gmfrm_row3_cat2.step_blocks == [:rater_steps, :rater_steps]
    gmfrm_params = [
        0.3, -0.2,      # person locations
        0.1, -0.05,     # rater severities
        -0.2, 0.2,      # item difficulties, sum-to-zero
        2.0, 0.5,       # item discriminations, product-one
        1.2, 0.8,       # rater consistency values
        0.25, -0.1,     # free rater steps for m = 2
    ]
    gmfrm_raw_blueprint = BayesianMGMFRM._gmfrm_source_unconstrained_blueprint(gmfrm_preview)
    @test gmfrm_raw_blueprint.scope === :scalar_gmfrm_source_aligned
    @test gmfrm_raw_blueprint.status === :internal_source_fixture
    @test gmfrm_raw_blueprint.compiler_stage === :source_fixture
    @test gmfrm_raw_blueprint.fixture_only
    @test !gmfrm_raw_blueprint.fit_ready
    @test gmfrm_raw_blueprint.n_parameters == 10
    @test gmfrm_raw_blueprint.parameter_names[gmfrm_raw_blueprint.blocks[:item_free]] == ["raw_item[I1]"]
    @test gmfrm_raw_blueprint.parameter_names[gmfrm_raw_blueprint.blocks[:log_item_discrimination_free]] ==
        ["raw_log_item_discrimination[I1]"]
    gmfrm_fit_ready_blueprint =
        BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(gmfrm_preview)
    @test gmfrm_fit_ready_blueprint.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_fit_ready_blueprint.status === :internal_fit_ready_candidate
    @test gmfrm_fit_ready_blueprint.compiler_stage === :fit_ready_candidate
    @test !gmfrm_fit_ready_blueprint.fixture_only
    @test !gmfrm_fit_ready_blueprint.fit_ready
    @test gmfrm_fit_ready_blueprint.parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_fit_ready_blueprint.constrained_parameter_names ==
        gmfrm_raw_blueprint.constrained_parameter_names
    @test gmfrm_fit_ready_blueprint.blocks == gmfrm_raw_blueprint.blocks
    @test gmfrm_fit_ready_blueprint.constrained_blocks == gmfrm_raw_blueprint.constrained_blocks
    @test_throws ArgumentError fit_ready_parameter_layout(gmfrm_spec)
    gmfrm_layout = fit_ready_parameter_layout(gmfrm_spec; preview = true)
    @test gmfrm_layout.schema == "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test gmfrm_layout.family === :gmfrm
    @test gmfrm_layout.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_layout.status === :internal_fit_ready_candidate
    @test gmfrm_layout.parameterization === :raw_to_constrained
    @test gmfrm_layout.experimental_public
    @test !gmfrm_layout.public_fit
    @test !gmfrm_layout.fit_ready
    @test gmfrm_layout.raw_parameter_names == gmfrm_fit_ready_blueprint.parameter_names
    @test gmfrm_layout.constrained_parameter_names ==
        gmfrm_fit_ready_blueprint.constrained_parameter_names
    @test any(row -> row.block === :item_free &&
        row.parameter_names == ["raw_item[I1]"],
        gmfrm_layout.raw_blocks)
    @test any(row -> row.block === :item &&
        row.parameter_names == ["item[I1]", "item[I2]"],
        gmfrm_layout.constrained_blocks)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination &&
        row.transform === :geometric_mean_one_log_last,
        gmfrm_layout.transforms)
    @test_throws ArgumentError domain_compilation_summary(gmfrm_spec)
    gmfrm_domain = domain_compilation_summary(gmfrm_spec; preview = true)
    gmfrm_item_discrimination_domain = only(filter(row ->
        row.block === :item_discrimination &&
        row.compiled_role === :discrimination_block,
        gmfrm_domain))
    @test gmfrm_item_discrimination_domain.raw_block === :log_item_discrimination_free
    @test gmfrm_item_discrimination_domain.constraint === :geometric_mean_one
    @test gmfrm_item_discrimination_domain.prior_block === :log_item_discrimination
    @test gmfrm_item_discrimination_domain.prior === :lognormal_or_hierarchical
    @test !gmfrm_item_discrimination_domain.fit_ready
    @test gmfrm_item_discrimination_domain.experimental_public
    gmfrm_scoring_domain = only(filter(row ->
        row.compiled_role === :scoring_vector,
        gmfrm_domain))
    @test gmfrm_scoring_domain.block === :rater_steps
    @test gmfrm_scoring_domain.parameter_names == [
        "rater_step[rater=R1,m=2]",
        "rater_step[rater=R2,m=2]",
    ]
    @test gmfrm_scoring_domain.scoring_vector == identified_data.category_levels
    gmfrm_preview_manifest = model_manifest(gmfrm_preview)
    gmfrm_raw_manifest = gmfrm_preview_manifest.design.raw_parameterization
    @test gmfrm_raw_manifest.schema == "bayesianmgmfrm.raw_parameterization.v1"
    @test gmfrm_raw_manifest.family === :gmfrm
    @test gmfrm_raw_manifest.status === :internal_source_fixture
    @test gmfrm_raw_manifest.public_fit === false
    @test gmfrm_raw_manifest.fixture_only
    @test !gmfrm_raw_manifest.fit_ready
    @test gmfrm_raw_manifest.density_space === :raw_unconstrained
    @test gmfrm_raw_manifest.prior_policy === :independent_normal_raw_coordinates
    @test gmfrm_raw_manifest.jacobian_policy === :none_raw_coordinate_density
    @test gmfrm_raw_manifest.n_raw_parameters == gmfrm_raw_blueprint.n_parameters
    @test gmfrm_raw_manifest.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    gmfrm_item_transform = only(filter(row -> row.raw_block === :item_free,
        gmfrm_raw_manifest.transforms))
    @test gmfrm_item_transform.constrained_block === :item
    @test gmfrm_item_transform.transform === :sum_to_zero_last
    @test gmfrm_item_transform.constraint === :sum_to_zero
    @test gmfrm_item_transform.raw_parameter_names == ["raw_item[I1]"]
    @test gmfrm_item_transform.constrained_parameter_names == ["item[I1]", "item[I2]"]
    gmfrm_discrimination_transform = only(filter(row -> row.raw_block === :log_item_discrimination_free,
        gmfrm_raw_manifest.transforms))
    @test gmfrm_discrimination_transform.transform === :geometric_mean_one_log_last
    @test gmfrm_discrimination_transform.prior_block === :log_item_discrimination
    @test gmfrm_discrimination_transform.jacobian_policy === :none_raw_coordinate_density
    gmfrm_candidate_manifest = gmfrm_raw_manifest.promotion_candidate
    @test gmfrm_candidate_manifest.schema == "bayesianmgmfrm.gmfrm_promotion_candidate.v1"
    @test gmfrm_candidate_manifest.family === :gmfrm
    @test gmfrm_candidate_manifest.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_candidate_manifest.status === :internal_promotion_candidate
    @test gmfrm_candidate_manifest.public_fit === false
    @test !gmfrm_candidate_manifest.fit_ready
    @test !gmfrm_candidate_manifest.fixture_only
    @test gmfrm_candidate_manifest.compiler_stage === :fit_ready_candidate
    @test gmfrm_candidate_manifest.source_oracle === :scalar_gmfrm_source_aligned
    @test gmfrm_candidate_manifest.transform_ready
    @test gmfrm_candidate_manifest.logdensity_ready
    @test gmfrm_candidate_manifest.bridge_oracle_ready
    @test gmfrm_candidate_manifest.bridge_direct_ready
    @test gmfrm_candidate_manifest.direct_pointwise_ready
    @test gmfrm_candidate_manifest.sampler_smoke_ready
    @test gmfrm_candidate_manifest.production_diagnostics_ready
    @test gmfrm_candidate_manifest.candidate_chain_study_ready
    @test gmfrm_candidate_manifest.stress_chain_grid_ready
    @test gmfrm_candidate_manifest.recovery_smoke_ready
    @test gmfrm_candidate_manifest.baseline_comparison_ready
    @test gmfrm_candidate_manifest.baseline_calibration_grid_ready
    @test gmfrm_candidate_manifest.interval_decision_grid_ready
    @test gmfrm_candidate_manifest.sparse_design_grid_ready
    @test gmfrm_candidate_manifest.waic_influence_review_ready
    @test gmfrm_candidate_manifest.psis_loo_review_ready
    @test gmfrm_candidate_manifest.exact_loo_or_kfold_review_ready
    @test gmfrm_candidate_manifest.guarded_exposure_review_ready
    @test gmfrm_candidate_manifest.guarded_fit_api_dry_run_ready
    @test gmfrm_candidate_manifest.guarded_fit_method_wiring_ready
    @test gmfrm_candidate_manifest.experimental_fit_validation_grid_ready
    @test gmfrm_candidate_manifest.posterior_predictive_grid_ready
    @test gmfrm_candidate_manifest.sparse_pathology_recovery_grid_ready
    @test gmfrm_candidate_manifest.prior_likelihood_sensitivity_grid_ready
    @test gmfrm_candidate_manifest.real_data_case_study_ready
    @test gmfrm_candidate_manifest.claim_recovery_reproduction_archive_ready
    @test gmfrm_candidate_manifest.broader_experimental_exposure_decision_review_ready
    @test gmfrm_candidate_manifest.target_constructor === :_gmfrm_promotion_candidate_logdensity
    @test gmfrm_candidate_manifest.diagnostic_constructor === :_gmfrm_promotion_candidate_diagnostics
    @test gmfrm_candidate_manifest.sampler_diagnostic_constructor ===
        :_gmfrm_promotion_candidate_sampler_diagnostics
    @test gmfrm_candidate_manifest.pointwise_fixture_constructor === :_gmfrm_promotion_candidate_pointwise_fixture
    @test gmfrm_candidate_manifest.compiler_blueprint_constructor ===
        :_gmfrm_fit_ready_candidate_blueprint
    @test gmfrm_candidate_manifest.fit_ready_compiler_ready
    @test gmfrm_candidate_manifest.experimental_public_ready
    @test gmfrm_candidate_manifest.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    gmfrm_fit_ready_manifest = gmfrm_candidate_manifest.fit_ready_compiler
    @test gmfrm_fit_ready_manifest.schema ==
        "bayesianmgmfrm.gmfrm_fit_ready_compiler_candidate.v1"
    @test gmfrm_fit_ready_manifest.family === :gmfrm
    @test gmfrm_fit_ready_manifest.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_fit_ready_manifest.status === :internal_fit_ready_candidate
    @test !gmfrm_fit_ready_manifest.public_fit
    @test !gmfrm_fit_ready_manifest.fit_ready
    @test !gmfrm_fit_ready_manifest.fixture_only
    @test gmfrm_fit_ready_manifest.compiler_stage === :fit_ready_candidate
    @test gmfrm_fit_ready_manifest.source_oracle === :scalar_gmfrm_source_aligned
    @test gmfrm_fit_ready_manifest.direct_prior_policy ===
        :not_enabled_raw_coordinate_priors_only
    @test gmfrm_fit_ready_manifest.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_fit_ready_manifest.constrained_parameter_names == gmfrm_preview.parameter_names
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination &&
        row.constraint === :geometric_mean_one,
        gmfrm_fit_ready_manifest.constraints)
    @test :direct_scale_priors in gmfrm_fit_ready_manifest.unsupported_public_options
    gmfrm_direct_manifest = gmfrm_candidate_manifest.direct_parameterization
    @test gmfrm_direct_manifest.schema ==
        "bayesianmgmfrm.gmfrm_direct_parameterization_candidate.v1"
    @test gmfrm_direct_manifest.family === :gmfrm
    @test gmfrm_direct_manifest.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_direct_manifest.status === :internal_promotion_candidate
    @test !gmfrm_direct_manifest.fixture_only
    @test gmfrm_direct_manifest.density_space === :constrained_direct
    @test gmfrm_direct_manifest.prior_policy === :derived_from_raw_candidate_no_direct_prior
    @test gmfrm_direct_manifest.jacobian_policy === :not_applicable_for_direct_likelihood
    @test gmfrm_direct_manifest.parameter_names == gmfrm_raw_blueprint.constrained_parameter_names
    @test any(row -> row.block === :item_discrimination && row.parameter_names == [
            "item_discrimination[item=I1]",
            "item_discrimination[item=I2]",
        ], gmfrm_direct_manifest.blocks)
    @test any(row -> row.raw_block === :log_item_discrimination_free &&
        row.constrained_block === :item_discrimination,
        gmfrm_direct_manifest.source_transforms)
    @test any(row -> row.gate === :bridge_oracle_check && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :fit_ready_compiler_manifest && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :bridge_direct_parameter_check && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :direct_parameter_metadata && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :raw_to_direct_transform && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :direct_pointwise_fixture && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :public_fit_api && row.status === :blocked,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :production_diagnostics && row.status === :done,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :candidate_chain_study &&
        row.status === :done &&
        row.evidence === :gmfrm_candidate_chain_study_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :stress_chain_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_stress_chain_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :recovery_smoke_study &&
        row.status === :done &&
        row.evidence === :gmfrm_recovery_smoke_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :baseline_comparison &&
        row.status === :done &&
        row.evidence === :gmfrm_baseline_comparison_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :baseline_calibration_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_baseline_calibration_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :interval_decision_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_interval_decision_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :sparse_design_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_sparse_design_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :waic_influence_review &&
        row.status === :done &&
        row.evidence === :gmfrm_waic_influence_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :psis_loo_review &&
        row.status === :done &&
        row.evidence === :gmfrm_psis_loo_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :exact_loo_or_kfold_review &&
        row.status === :done &&
        row.evidence === :gmfrm_exact_loo_or_kfold_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :guarded_exposure_review &&
        row.status === :done &&
        row.evidence === :gmfrm_guarded_exposure_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :guarded_fit_api_dry_run &&
        row.status === :done &&
        row.evidence === :gmfrm_guarded_fit_api_dry_run_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :guarded_fit_method_wiring &&
        row.status === :done &&
        row.evidence === :gmfrm_guarded_fit_method_wiring_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :experimental_fit_validation_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_experimental_fit_validation_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :posterior_predictive_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_posterior_predictive_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :sparse_pathology_recovery_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_sparse_pathology_recovery_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :prior_likelihood_sensitivity_grid &&
        row.status === :done &&
        row.evidence === :gmfrm_prior_likelihood_sensitivity_grid_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :real_data_case_study &&
        row.status === :done &&
        row.evidence === :gmfrm_real_data_case_study_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :claim_recovery_reproduction_archive &&
        row.status === :done &&
        row.evidence === :gmfrm_claim_recovery_reproduction_archive_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :broader_experimental_exposure_decision_review &&
        row.status === :done &&
        row.evidence === :gmfrm_broader_experimental_exposure_decision_review_fixture,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :direct_scale_prior_jacobian_policy &&
        row.status === :done &&
        row.evidence === :raw_prior_jacobian_policy_decision,
        gmfrm_candidate_manifest.candidate_gates)
    @test any(row -> row.gate === :experimental_public_api &&
        row.status === :done &&
        row.evidence === :gmfrm_experimental_public_api_decision,
        gmfrm_candidate_manifest.candidate_gates)
    gmfrm_experimental_decision = gmfrm_candidate_manifest.experimental_public_api
    @test gmfrm_experimental_decision.schema ==
        "bayesianmgmfrm.gmfrm_experimental_public_api_decision.v1"
    @test gmfrm_experimental_decision.family === :gmfrm
    @test gmfrm_experimental_decision.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_experimental_decision.status === :experimental_public
    @test gmfrm_experimental_decision.decision === :enable_guarded_experimental
    @test gmfrm_experimental_decision.public_fit
    @test gmfrm_experimental_decision.experimental_public
    @test gmfrm_experimental_decision.fit_ready
    @test gmfrm_experimental_decision.proposed_entrypoint ==
        "fit(spec; experimental = true)"
    @test gmfrm_experimental_decision.candidate_chain_study_artifact ==
        "test/fixtures/gmfrm_candidate_chain_study.json"
    @test gmfrm_experimental_decision.stress_chain_grid_artifact ==
        "test/fixtures/gmfrm_stress_chain_grid.json"
    @test gmfrm_experimental_decision.recovery_smoke_artifact ==
        "test/fixtures/gmfrm_recovery_smoke.json"
    @test gmfrm_experimental_decision.baseline_comparison_artifact ==
        "test/fixtures/gmfrm_baseline_comparison.json"
    @test gmfrm_experimental_decision.baseline_calibration_grid_artifact ==
        "test/fixtures/gmfrm_baseline_calibration_grid.json"
    @test gmfrm_experimental_decision.interval_decision_grid_artifact ==
        "test/fixtures/gmfrm_interval_decision_grid.json"
    @test gmfrm_experimental_decision.sparse_design_grid_artifact ==
        "test/fixtures/gmfrm_sparse_design_grid.json"
    @test gmfrm_experimental_decision.waic_influence_review_artifact ==
        "test/fixtures/gmfrm_waic_influence_review.json"
    @test gmfrm_experimental_decision.psis_loo_review_artifact ==
        "test/fixtures/gmfrm_psis_loo_review.json"
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_artifact ==
        "test/fixtures/gmfrm_exact_loo_or_kfold_review.json"
    @test gmfrm_experimental_decision.guarded_exposure_review_artifact ==
        "test/fixtures/gmfrm_guarded_exposure_review.json"
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_artifact ==
        "test/fixtures/gmfrm_guarded_fit_api_dry_run.json"
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_artifact ==
        "test/fixtures/gmfrm_guarded_fit_method_wiring.json"
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_artifact ==
        "test/fixtures/gmfrm_experimental_fit_validation_grid.json"
    @test gmfrm_experimental_decision.posterior_predictive_grid_artifact ==
        "test/fixtures/gmfrm_posterior_predictive_grid.json"
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_artifact ==
        "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json"
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_artifact ==
        "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json"
    @test gmfrm_experimental_decision.real_data_case_study_artifact ==
        "test/fixtures/gmfrm_real_data_case_study.json"
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_artifact ==
        "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json"
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_artifact ==
        "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json"
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_artifact ==
        "test/fixtures/mgmfrm_baseline_comparison.json"
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_artifact ==
        "test/fixtures/mgmfrm_sparse_recovery_grid.json"
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_artifact ==
        "test/fixtures/gmfrm_dff_estimand_validation_grid.json"
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_artifact ==
        "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.status ===
        :initial_smoke_done
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.comparison_target ===
        :same_observation_waic
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.interpretation ===
        :inconclusive_high_variance_smoke
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.public_exposure_support ===
        :insufficient_alone
    @test gmfrm_experimental_decision.baseline_comparison_interpretation.required_followup ===
        :satisfied_by_baseline_calibration_grid_artifact
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.comparison_target ===
        :same_observation_waic_and_expected_score_calibration
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.interpretation ===
        :all_scenarios_passed_with_high_variance_waic_warnings
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.public_exposure_support ===
        :reviewed_insufficient_for_public_fit
    @test gmfrm_experimental_decision.baseline_calibration_grid_interpretation.required_followup ===
        :satisfied_by_interval_decision_grid_artifact
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.comparison_target ===
        :direct_parameter_interval_coverage_and_keep_internal_stability
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.interpretation ===
        :intervals_finite_and_keep_internal_decision_stable
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.public_exposure_support ===
        :satisfied_for_sparse_design_grid_followup
    @test gmfrm_experimental_decision.interval_decision_grid_interpretation.required_followup ===
        :satisfied_by_sparse_design_grid_artifact
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.comparison_target ===
        :sparse_connected_design_validation_interval_and_decision_stability
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.interpretation ===
        :sparse_designs_passed_with_recorded_validation_warnings
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.public_exposure_support ===
        :satisfied_for_waic_influence_followup
    @test gmfrm_experimental_decision.sparse_design_grid_interpretation.required_followup ===
        :satisfied_by_waic_influence_review_artifact
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.comparison_target ===
        :pointwise_waic_influence_and_flagged_observation_sensitivity
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.interpretation ===
        :flagged_observation_removal_changes_some_model_ranks
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.public_exposure_support ===
        :satisfied_for_psis_loo_followup
    @test gmfrm_experimental_decision.waic_influence_review_interpretation.required_followup ===
        :satisfied_by_psis_loo_review_artifact
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.comparison_target ===
        :raw_importance_loo_pareto_k_screen
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.interpretation ===
        :high_pareto_k_requires_exact_loo_or_kfold
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.public_exposure_support ===
        :satisfied_for_exact_loo_or_kfold_followup
    @test gmfrm_experimental_decision.psis_loo_review_interpretation.required_followup ===
        :satisfied_by_exact_loo_or_kfold_review_artifact
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.comparison_target ===
        :heldout_observation_kfold_refit_log_score
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.interpretation ===
        :kfold_refit_review_satisfied_exact_loo_followup
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.public_exposure_support ===
        :satisfied_for_guarded_fit_api_dry_run_followup
    @test gmfrm_experimental_decision.exact_loo_or_kfold_review_interpretation.required_followup ===
        :satisfied_by_guarded_fit_api_dry_run_artifact
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.status ===
        :review_recorded
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.review_target ===
        :experimental_public_scalar_gmfrm
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.interpretation ===
        :local_evidence_reviewed_full_archive_recorded_and_broader_exposure_decision_recorded
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.public_exposure_support ===
        :guarded_scalar_gmfrm_only
    @test gmfrm_experimental_decision.guarded_exposure_review_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.status ===
        :dry_run_recorded
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.interpretation ===
        :guarded_entrypoint_contract_dry_run_passed_but_method_not_wired
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.public_exposure_support ===
        :satisfied_by_guarded_fit_method_wiring
    @test gmfrm_experimental_decision.guarded_fit_api_dry_run_interpretation.required_followup ===
        :satisfied_by_guarded_fit_method_wiring
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.status ===
        :method_wired
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.interpretation ===
        :scalar_gmfrm_guarded_experimental_fit_method_enabled
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.public_exposure_support ===
        :satisfied_for_experimental_fit_validation_grid_followup
    @test gmfrm_experimental_decision.guarded_fit_method_wiring_interpretation.required_followup ===
        :experimental_fit_validation_grid
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_experimental_fit_validation_grid_passed_ppc_and_sparse_pathology_checked
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.public_exposure_support ===
        :satisfied_by_sparse_pathology_recovery_grid
    @test gmfrm_experimental_decision.experimental_fit_validation_grid_interpretation.required_followup ===
        :scalar_gmfrm_prior_likelihood_sensitivity_grid
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_posterior_predictive_grid_passed
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.public_exposure_support ===
        :satisfied_by_sparse_pathology_recovery_grid
    @test gmfrm_experimental_decision.posterior_predictive_grid_interpretation.required_followup ===
        :scalar_gmfrm_prior_likelihood_sensitivity_grid
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_sparse_pathology_recovery_grid_passed
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.public_exposure_support ===
        :satisfied_by_prior_likelihood_sensitivity_grid
    @test gmfrm_experimental_decision.sparse_pathology_recovery_grid_interpretation.required_followup ===
        :scalar_gmfrm_real_data_case_study
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.interpretation ===
        :guarded_scalar_gmfrm_prior_likelihood_sensitivity_grid_passed
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.public_exposure_support ===
        :satisfied_by_real_data_case_study
    @test gmfrm_experimental_decision.prior_likelihood_sensitivity_grid_interpretation.required_followup ===
        :claim_level_recovery_and_reproduction_archive
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.status ===
        :case_study_recorded
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_fit_entrypoint
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.interpretation ===
        :guarded_scalar_gmfrm_real_data_case_study_passed
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.public_exposure_support ===
        :satisfied_by_claim_recovery_reproduction_archive
    @test gmfrm_experimental_decision.real_data_case_study_interpretation.required_followup ===
        :broader_experimental_exposure_decision_review
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.status ===
        :archive_recorded
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.review_target ===
        :guarded_experimental_scalar_gmfrm_claim_support
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.interpretation ===
        :claim_level_recovery_reproduction_archive_recorded
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.public_exposure_support ===
        :satisfied_by_broader_experimental_exposure_decision_review
    @test gmfrm_experimental_decision.claim_recovery_reproduction_archive_interpretation.required_followup ===
        :satisfied_by_broader_experimental_exposure_decision_review
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.status ===
        :decision_recorded
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.review_target ===
        :broader_generalized_model_exposure
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.interpretation ===
        :broader_exposure_review_recorded_full_archive_available_keep_broader_claims_blocked
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.public_exposure_support ===
        :guarded_scalar_gmfrm_only
    @test gmfrm_experimental_decision.broader_experimental_exposure_decision_review_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.status ===
        :comparison_recorded
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.comparison_target ===
        :confirmatory_mgmfrm_same_observation_waic_against_mfrm_baselines
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.interpretation ===
        :baseline_comparison_recorded_keep_mgmfrm_internal
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.public_exposure_support ===
        :insufficient_for_mgmfrm_public_fit
    @test gmfrm_experimental_decision.mgmfrm_baseline_comparison_interpretation.required_followup ===
        :manual_public_scope_review_for_mgmfrm_fit
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.review_target ===
        :confirmatory_mgmfrm_sparse_connected_recovery
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.interpretation ===
        :sparse_recovery_grid_recorded_keep_mgmfrm_internal
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.public_exposure_support ===
        :insufficient_for_broader_public_claims
    @test gmfrm_experimental_decision.mgmfrm_sparse_recovery_grid_interpretation.required_followup ===
        :manual_public_scope_review_for_mgmfrm_fit
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.review_target ===
        :dff_estimand_validation_evidence
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.interpretation ===
        :dff_estimands_predeclared_keep_model_effects_validation_only
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.public_exposure_support ===
        :satisfied_for_gate_e_followup_without_dff_model_effect_fit
    @test gmfrm_experimental_decision.dff_estimand_validation_grid_interpretation.required_followup ===
        :future_dff_model_effect_fit_policy
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.status ===
        :grid_recorded
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.review_target ===
        :gate_e_broader_generalized_claim_evidence
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.interpretation ===
        :manuscript_scale_grid_recorded_full_archive_available
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.public_exposure_support ===
        :full_archive_recorded_without_broader_fit
    @test gmfrm_experimental_decision.manuscript_scale_simulation_grid_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.status ===
        :archive_recorded
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.review_target ===
        :full_local_reproduction_bundle
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.interpretation ===
        :full_archive_recorded_without_publication_or_registration
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.public_exposure_support ===
        :local_full_reproduction_archive_recorded
    @test gmfrm_experimental_decision.full_paper_reproduction_archive_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test gmfrm_experimental_decision.caveat_docs_artifact ==
        "docs/src/fitting.md#guarded-generalized-model-caveats"
    gmfrm_prior_policy = gmfrm_experimental_decision.prior_jacobian_policy
    @test gmfrm_prior_policy.schema ==
        "bayesianmgmfrm.generalized_raw_prior_jacobian_policy.v1"
    @test gmfrm_prior_policy.family === :gmfrm
    @test gmfrm_prior_policy.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_prior_policy.status === :policy_recorded
    @test gmfrm_prior_policy.prior_policy === :independent_normal_raw_coordinates
    @test !gmfrm_prior_policy.direct_scale_priors
    @test gmfrm_prior_policy.jacobian_policy === :none_raw_coordinate_density
    gmfrm_fit_artifact_contract =
        gmfrm_experimental_decision.fit_artifact_contract
    @test gmfrm_fit_artifact_contract.schema ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test gmfrm_fit_artifact_contract.family === :gmfrm
    @test gmfrm_fit_artifact_contract.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_fit_artifact_contract.status === :contract_recorded
    @test gmfrm_fit_artifact_contract.public_fit
    @test gmfrm_fit_artifact_contract.experimental_public
    @test gmfrm_fit_artifact_contract.artifact_kind ===
        :experimental_generalized_fit_artifact
    @test gmfrm_fit_artifact_contract.summary.enables_public_fit
    @test any(row -> row.field === :experimental_public &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :fixture_provenance &&
        row.status === :required,
        gmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.artifact === :candidate_chain_study &&
        row.value == "test/fixtures/gmfrm_candidate_chain_study.json",
        gmfrm_fit_artifact_contract.provenance_rows)
    @test any(row -> row.option === :family &&
        row.value === :gmfrm &&
        row.status === :candidate_only,
        gmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :entrypoint &&
        row.value == "fit(spec; experimental = true)" &&
        row.status === :enabled_guarded,
        gmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :family &&
        row.value === :mgmfrm &&
        row.status === :blocked,
        gmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :bias_or_dff_terms &&
        row.value === :model_effects &&
        row.status === :blocked &&
        row.blocker === :dff_model_effect_fit_policy_not_promoted,
        gmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.evidence === :candidate_chain_study &&
        row.status === :done,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :recovery_smoke_study &&
        row.status === :done,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :fit_artifact_manifest_for_experimental_public &&
        row.status === :done &&
        row.artifact === :experimental_public_fit_artifact_contract,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :stress_chain_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_stress_chain_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :baseline_comparison &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_baseline_comparison.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :baseline_calibration_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_baseline_calibration_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :interval_decision_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_interval_decision_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :sparse_design_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_sparse_design_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :waic_influence_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_waic_influence_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :psis_loo_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_psis_loo_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :exact_loo_or_kfold_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_exact_loo_or_kfold_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_exposure_review &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_guarded_exposure_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_api_dry_run &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_guarded_fit_api_dry_run.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_method_wiring &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_guarded_fit_method_wiring.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :experimental_fit_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_experimental_fit_validation_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :posterior_predictive_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_posterior_predictive_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :sparse_pathology_recovery_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_sparse_pathology_recovery_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :prior_likelihood_sensitivity_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_prior_likelihood_sensitivity_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :real_data_case_study &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_real_data_case_study.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :claim_recovery_reproduction_archive &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_claim_recovery_reproduction_archive.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :broader_experimental_exposure_decision_review &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :mgmfrm_baseline_comparison &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_baseline_comparison.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :mgmfrm_sparse_recovery_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :dff_estimand_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :manuscript_scale_simulation_grid &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :full_paper_reproduction_archive &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :direct_prior_jacobian_policy &&
        row.status === :done &&
        row.artifact === :generalized_raw_prior_jacobian_policy,
        gmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :public_caveat_docs &&
        row.status === :done &&
        row.artifact == "docs/src/fitting.md#guarded-generalized-model-caveats",
        gmfrm_experimental_decision.evidence_rows)
    @test !any(row -> row.blocker === :stress_chain_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :baseline_comparison_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :baseline_calibration_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :interval_coverage_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :decision_stability_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :guarded_exposure_review_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :high_variance_waic_requires_followup,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :high_variance_waic_requires_psis_loo_followup,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :high_pareto_k_requires_exact_loo_or_kfold_followup,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :guarded_fit_api_dry_run_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :guarded_fit_method_wiring_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :experimental_fit_validation_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_posterior_predictive_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_sparse_pathology_recovery_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_prior_likelihood_sensitivity_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :scalar_gmfrm_real_data_case_study_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :claim_level_recovery_and_reproduction_archive_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :broader_experimental_exposure_decision_review_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :mgmfrm_baseline_comparison_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :sparse_recovery_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :dff_estimand_and_validation_evidence_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :manuscript_scale_simulation_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :full_paper_reproduction_archive_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :sparse_design_grid_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :direct_prior_jacobian_policy_pending,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :public_fit_artifact_contract_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :public_caveat_docs_missing,
        gmfrm_experimental_decision.blocker_rows)
    @test gmfrm_experimental_decision.summary.fit_allowed
    @test gmfrm_experimental_decision.summary.experimental_keyword_enabled
    @test gmfrm_experimental_decision.summary.n_evidence_done >= 28
    @test gmfrm_experimental_decision.summary.n_evidence_pending == 0
    @test gmfrm_experimental_decision.summary.n_blockers == 0
    @test gmfrm_experimental_decision.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    gmfrm_raw_params = [
        0.3, -0.2,
        0.1, -0.05,
        -0.2,
        log(2.0),
        log(1.2), log(0.8),
        0.25, -0.1,
    ]
    @test BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params,
    ) ≈ gmfrm_params
    gmfrm_transform_diagnostics =
        BayesianMGMFRM._gmfrm_promotion_candidate_transform_diagnostics(
            gmfrm_preview,
            gmfrm_raw_params,
        )
    @test gmfrm_transform_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_transform_diagnostics.v1"
    @test gmfrm_transform_diagnostics.summary.passed
    @test gmfrm_transform_diagnostics.summary.flag === :ok
    @test gmfrm_transform_diagnostics.summary.n_raw_parameters == gmfrm_raw_blueprint.n_parameters
    @test gmfrm_transform_diagnostics.summary.n_direct_parameters == length(gmfrm_params)
    @test gmfrm_transform_diagnostics.direct_parameter_names == gmfrm_preview.parameter_names
    @test gmfrm_transform_diagnostics.direct_parameter_values ≈ gmfrm_params
    @test gmfrm_transform_diagnostics.raw_parameter_values ≈ gmfrm_raw_params
    @test gmfrm_transform_diagnostics.raw_pointwise_loglikelihood ≈
        gmfrm_transform_diagnostics.direct_pointwise_loglikelihood
    @test gmfrm_transform_diagnostics.summary.max_pointwise_abs_error <= 1e-10
    @test all(row -> row.passed, gmfrm_transform_diagnostics.constraint_rows)
    gmfrm_transform_item_block = only(filter(row -> row.block === :item,
        gmfrm_transform_diagnostics.direct_blocks))
    @test gmfrm_transform_item_block.values ≈ [-0.2, 0.2]
    gmfrm_transform_discrimination_block = only(filter(row -> row.block === :item_discrimination,
        gmfrm_transform_diagnostics.direct_blocks))
    @test gmfrm_transform_discrimination_block.values ≈ [2.0, 0.5]
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params[1:end-1],
    )
    for block in (:log_item_discrimination_free, :log_rater_consistency),
            boundary_value in (800.0, -1000.0)
        boundary_raw_params = copy(gmfrm_raw_params)
        boundary_raw_params[first(gmfrm_raw_blueprint.blocks[block])] = boundary_value
        @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_constrained_params_from_unconstrained(
            gmfrm_preview,
            boundary_raw_params,
        )
    end
    gmfrm_source_values = BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, gmfrm_params)
    gmfrm_source_pointwise =
        BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood(gmfrm_preview, gmfrm_params)
    gmfrm_direct_pointwise_fixture =
        BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(gmfrm_preview, gmfrm_params)
    @test gmfrm_direct_pointwise_fixture.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_pointwise_fixture.v1"
    @test gmfrm_direct_pointwise_fixture.summary.passed
    @test gmfrm_direct_pointwise_fixture.summary.flag === :ok
    @test gmfrm_direct_pointwise_fixture.density_space === :constrained_direct
    @test gmfrm_direct_pointwise_fixture.parameter_layout.scope ===
        :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_direct_pointwise_fixture.parameter_layout.constrained_parameter_names ==
        gmfrm_direct_pointwise_fixture.parameter_names
    @test gmfrm_direct_pointwise_fixture.parameter_names == gmfrm_preview.parameter_names
    @test gmfrm_direct_pointwise_fixture.parameter_values ≈ gmfrm_params
    @test gmfrm_direct_pointwise_fixture.summary.n_rows == length(gmfrm_predictors)
    @test gmfrm_direct_pointwise_fixture.summary.n_pointwise == identified_data.n
    @test gmfrm_direct_pointwise_fixture.pointwise_loglikelihood ≈ gmfrm_source_pointwise
    @test gmfrm_direct_pointwise_fixture.loglikelihood ≈ sum(gmfrm_source_pointwise)
    @test isequal(gmfrm_direct_pointwise_fixture.rows, gmfrm_source_values)
    @test all(row -> row.passed, gmfrm_direct_pointwise_fixture.constraint_rows)
    @test only(filter(row -> row.block === :rater_consistency,
        gmfrm_direct_pointwise_fixture.blocks)).values ≈ [1.2, 0.8]
    @test BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params,
    ) ≈ gmfrm_source_pointwise
    @test BayesianMGMFRM._gmfrm_source_loglikelihood_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params,
    ) ≈ sum(gmfrm_source_pointwise)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
        gmfrm_preview,
        gmfrm_raw_params[1:end-1],
    )
    source_prior = BayesianMGMFRM._SourceFixturePrior(;
        person_sd = 1.1,
        rater_sd = 1.2,
        item_sd = 1.3,
        log_discrimination_sd = 1.4,
        log_consistency_sd = 1.5,
        step_sd = 1.6,
    )
    gmfrm_target = BayesianMGMFRM._source_fixture_logdensity(gmfrm_preview; prior = source_prior)
    gmfrm_spec_target = BayesianMGMFRM._source_fixture_logdensity(gmfrm_spec; prior = source_prior)
    gmfrm_candidate =
        BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gmfrm_preview; prior = source_prior)
    gmfrm_spec_candidate =
        BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(gmfrm_spec; prior = source_prior)
    @test LogDensityProblems.dimension(gmfrm_target) == gmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(gmfrm_spec_target) == gmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(gmfrm_candidate) == gmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(gmfrm_spec_candidate) == gmfrm_raw_blueprint.n_parameters
    @test gmfrm_target.blueprint.status === :internal_source_fixture
    @test gmfrm_candidate.blueprint.status === :internal_fit_ready_candidate
    @test gmfrm_candidate.blueprint.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_candidate.blueprint.parameter_names == gmfrm_raw_blueprint.parameter_names
    @test LogDensityProblems.capabilities(typeof(gmfrm_target)) == LogDensityProblems.LogDensityOrder{0}()
    @test LogDensityProblems.capabilities(typeof(gmfrm_candidate)) == LogDensityProblems.LogDensityOrder{0}()
    @test initial_params(gmfrm_target; value = 0.05) == fill(0.05, gmfrm_raw_blueprint.n_parameters)
    @test initial_params(gmfrm_candidate; value = 0.05) == fill(0.05, gmfrm_raw_blueprint.n_parameters)
    @test occursin("SourceFixtureLogDensity(gmfrm", sprint(show, gmfrm_target))
    @test occursin("GMFRMPromotionCandidateLogDensity", sprint(show, gmfrm_candidate))
    gmfrm_prior_sds = [
        1.1, 1.1,
        1.2, 1.2,
        1.3,
        1.4,
        1.5, 1.5,
        1.6, 1.6,
    ]
    gmfrm_expected_prior = sum(test_normal_logpdf(x, sd)
        for (x, sd) in zip(gmfrm_raw_params, gmfrm_prior_sds))
    @test BayesianMGMFRM._source_fixture_logprior(gmfrm_target, gmfrm_raw_params) ≈
        gmfrm_expected_prior
    @test BayesianMGMFRM._source_fixture_loglikelihood(gmfrm_target, gmfrm_raw_params) ≈
        sum(gmfrm_source_pointwise)
    @test LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params) ≈
        sum(gmfrm_source_pointwise) + gmfrm_expected_prior
    @test LogDensityProblems.logdensity(gmfrm_spec_target, gmfrm_raw_params) ≈
        LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params)
    @test LogDensityProblems.logdensity(gmfrm_candidate, gmfrm_raw_params) ≈
        LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params)
    @test LogDensityProblems.logdensity(gmfrm_spec_candidate, gmfrm_raw_params) ≈
        LogDensityProblems.logdensity(gmfrm_candidate, gmfrm_raw_params)
    gmfrm_raw_pointwise_fixture =
        BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(
            gmfrm_candidate,
            gmfrm_raw_params,
        )
    @test gmfrm_raw_pointwise_fixture.summary.passed
    @test gmfrm_raw_pointwise_fixture.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_raw_pointwise_fixture.parameter_layout.raw_parameter_names ==
        gmfrm_raw_pointwise_fixture.raw_parameter_names
    @test gmfrm_raw_pointwise_fixture.raw_parameter_values ≈ gmfrm_raw_params
    @test gmfrm_raw_pointwise_fixture.parameter_values ≈ gmfrm_params
    @test gmfrm_raw_pointwise_fixture.pointwise_loglikelihood ≈ gmfrm_source_pointwise
    gmfrm_logp = x -> LogDensityProblems.logdensity(gmfrm_target, x)
    gmfrm_forward_gradient = check_forwarddiff_gradient(gmfrm_logp, gmfrm_raw_params)
    @test length(gmfrm_forward_gradient) == gmfrm_raw_blueprint.n_parameters
    gmfrm_candidate_diagnostics = BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params;
        finite_difference_coords = [1, first(gmfrm_raw_blueprint.blocks[:log_item_discrimination_free])],
    )
    @test gmfrm_candidate_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_diagnostics.v1"
    @test gmfrm_candidate_diagnostics.summary.passed
    @test gmfrm_candidate_diagnostics.summary.flag === :ok
    @test gmfrm_candidate_diagnostics.summary.n_checked == 2
    @test gmfrm_candidate_diagnostics.summary.n_failed == 0
    @test gmfrm_candidate_diagnostics.summary.finite_logdensity
    @test gmfrm_candidate_diagnostics.summary.finite_gradient
    @test length(gmfrm_candidate_diagnostics.gradient) == gmfrm_raw_blueprint.n_parameters
    @test all(row -> row.passed, gmfrm_candidate_diagnostics.finite_difference_rows)
    @test BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        gmfrm_spec,
        gmfrm_raw_params;
        prior = source_prior,
        finite_difference_coords = [1],
    ).summary.passed
    gmfrm_hmc_samples, gmfrm_hmc_stats = check_advancedhmc_smoke(
        gmfrm_target,
        gmfrm_raw_params;
        seed = 20260619,
    )
    @test length(gmfrm_hmc_samples) == length(gmfrm_hmc_stats) == 2
    gmfrm_sampler_diagnostics =
        BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
            gmfrm_candidate,
            gmfrm_raw_params;
            seed = 20260620,
            ndraws = 4,
            warmup = 2,
            chains = 2,
            step_size = 0.02,
            max_depth = 3,
            metric = :unit,
            rhat_threshold = 100.0,
            ess_threshold = 1.0,
        )
    @test gmfrm_sampler_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_promotion_candidate_sampler_diagnostics.v1"
    @test gmfrm_sampler_diagnostics.status === :internal_promotion_candidate
    @test gmfrm_sampler_diagnostics.public_fit === false
    @test gmfrm_sampler_diagnostics.fit_ready === false
    @test gmfrm_sampler_diagnostics.backend === :advancedhmc
    @test gmfrm_sampler_diagnostics.sampler === :nuts
    @test gmfrm_sampler_diagnostics.density_space === :raw_unconstrained
    @test gmfrm_sampler_diagnostics.raw_parameter_names == gmfrm_raw_blueprint.parameter_names
    @test gmfrm_sampler_diagnostics.direct_parameter_names ==
        gmfrm_raw_blueprint.constrained_parameter_names
    @test gmfrm_sampler_diagnostics.initial_raw_parameter_values ≈ gmfrm_raw_params
    @test gmfrm_sampler_diagnostics.initial_direct_parameter_values ≈ gmfrm_params
    @test isfinite(gmfrm_sampler_diagnostics.initial_logdensity)
    @test size(gmfrm_sampler_diagnostics.draws) ==
        (8, gmfrm_raw_blueprint.n_parameters)
    @test size(gmfrm_sampler_diagnostics.direct_draws) == (8, length(gmfrm_params))
    @test size(gmfrm_sampler_diagnostics.direct_pointwise_loglikelihood) ==
        (8, identified_data.n)
    @test length(gmfrm_sampler_diagnostics.direct_loglikelihood) == 8
    @test length(gmfrm_sampler_diagnostics.logdensity) == 8
    @test length(gmfrm_sampler_diagnostics.chain_ids) == 8
    @test length(gmfrm_sampler_diagnostics.iterations) == 8
    @test all(isfinite, gmfrm_sampler_diagnostics.draws)
    @test all(isfinite, gmfrm_sampler_diagnostics.direct_draws)
    @test all(isfinite, gmfrm_sampler_diagnostics.direct_pointwise_loglikelihood)
    @test all(isfinite, gmfrm_sampler_diagnostics.direct_loglikelihood)
    @test all(isfinite, gmfrm_sampler_diagnostics.logdensity)
    @test length(gmfrm_sampler_diagnostics.chain_acceptance_rate) == 2
    @test length(gmfrm_sampler_diagnostics.sampler_stats) == 8
    @test all(row -> row.chain in (1, 2), gmfrm_sampler_diagnostics.sampler_stats)
    @test all(row -> 1 <= row.iteration <= 4, gmfrm_sampler_diagnostics.sampler_stats)
    @test all(row -> isfinite(row.log_density), gmfrm_sampler_diagnostics.sampler_stats)
    @test length(gmfrm_sampler_diagnostics.sampler_rows) == 2
    @test all(row -> row.backend === :advancedhmc,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.sampler === :nuts,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.n_draws == 4,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.n_finite_logdensity == 4,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test all(row -> row.n_nonfinite_logdensity == 0,
        gmfrm_sampler_diagnostics.sampler_rows)
    @test length(gmfrm_sampler_diagnostics.parameter_rows) ==
        gmfrm_raw_blueprint.n_parameters
    @test [row.parameter for row in gmfrm_sampler_diagnostics.parameter_rows] ==
        gmfrm_raw_blueprint.parameter_names
    @test all(row -> row.n_chains == 2,
        gmfrm_sampler_diagnostics.parameter_rows)
    @test all(row -> row.draws_per_chain == 4,
        gmfrm_sampler_diagnostics.parameter_rows)
    @test all(row -> row.total_draws == 8,
        gmfrm_sampler_diagnostics.parameter_rows)
    @test length(gmfrm_sampler_diagnostics.block_rows) ==
        length(keys(gmfrm_raw_blueprint.blocks))
    @test any(row -> row.block === :log_item_discrimination_free &&
        row.parameter_names == ["raw_log_item_discrimination[I1]"],
        gmfrm_sampler_diagnostics.block_rows)
    @test all(row -> row.passed, gmfrm_sampler_diagnostics.direct_constraint_rows)
    @test length(gmfrm_sampler_diagnostics.direct_parameter_rows) == length(gmfrm_params)
    @test [row.parameter for row in gmfrm_sampler_diagnostics.direct_parameter_rows] ==
        gmfrm_preview.parameter_names
    @test any(row -> row.block === :item_discrimination &&
        row.parameter_names == [
            "item_discrimination[item=I1]",
            "item_discrimination[item=I2]",
        ], gmfrm_sampler_diagnostics.direct_block_rows)
    @test gmfrm_sampler_diagnostics.summary.n_chains == 2
    @test gmfrm_sampler_diagnostics.summary.draws_per_chain == 4
    @test gmfrm_sampler_diagnostics.summary.total_draws == 8
    @test gmfrm_sampler_diagnostics.summary.n_parameters ==
        gmfrm_raw_blueprint.n_parameters
    @test gmfrm_sampler_diagnostics.summary.n_direct_parameters == length(gmfrm_params)
    @test gmfrm_sampler_diagnostics.summary.n_nonfinite_logdensity == 0
    @test gmfrm_sampler_diagnostics.summary.n_nonfinite_direct_loglikelihood == 0
    @test gmfrm_sampler_diagnostics.summary.n_failed_direct_constraints == 0
    @test gmfrm_sampler_diagnostics.summary.n_divergences >= 0
    @test gmfrm_sampler_diagnostics.summary.n_max_treedepth >= 0
    @test gmfrm_sampler_diagnostics.summary.flag in
        (:ok, :direct_transform_warning, :sampler_warning, :mcmc_warning,
            :insufficient_chains)
    @test BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        gmfrm_spec,
        gmfrm_raw_params;
        prior = source_prior,
        seed = 20260621,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        metric = :unit,
    ).summary.n_chains == 1
    gmfrm_candidate_chain_study_fixture = optional_fixture_path("MFRM_GMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE", joinpath("test", "fixtures", "gmfrm_candidate_chain_study.json"))
    if !isempty(gmfrm_candidate_chain_study_fixture)
        check_gmfrm_candidate_chain_study_fixture(
            gmfrm_candidate_chain_study_fixture,
            gmfrm_candidate,
            gmfrm_raw_params,
        )
    end
    gmfrm_stress_chain_grid_fixture = optional_fixture_path("MFRM_GMFRM_STRESS_CHAIN_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_stress_chain_grid.json"))
    if !isempty(gmfrm_stress_chain_grid_fixture)
        check_gmfrm_stress_chain_grid_fixture(
            gmfrm_stress_chain_grid_fixture,
            gmfrm_candidate,
            gmfrm_raw_params,
        )
    end
    gmfrm_recovery_smoke_fixture = optional_fixture_path("MFRM_GMFRM_RECOVERY_SMOKE_FIXTURE", joinpath("test", "fixtures", "gmfrm_recovery_smoke.json"))
    if !isempty(gmfrm_recovery_smoke_fixture)
        check_gmfrm_recovery_smoke_fixture(gmfrm_recovery_smoke_fixture)
    end
    gmfrm_baseline_comparison_fixture = optional_fixture_path("MFRM_GMFRM_BASELINE_COMPARISON_FIXTURE", joinpath("test", "fixtures", "gmfrm_baseline_comparison.json"))
    if !isempty(gmfrm_baseline_comparison_fixture)
        check_gmfrm_baseline_comparison_fixture(gmfrm_baseline_comparison_fixture)
    end
    gmfrm_baseline_calibration_grid_fixture = optional_fixture_path("MFRM_GMFRM_BASELINE_CALIBRATION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_baseline_calibration_grid.json"))
    if !isempty(gmfrm_baseline_calibration_grid_fixture)
        check_gmfrm_baseline_calibration_grid_fixture(
            gmfrm_baseline_calibration_grid_fixture,
        )
    end
    gmfrm_interval_decision_grid_fixture = optional_fixture_path("MFRM_GMFRM_INTERVAL_DECISION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_interval_decision_grid.json"))
    if !isempty(gmfrm_interval_decision_grid_fixture)
        check_gmfrm_interval_decision_grid_fixture(
            gmfrm_interval_decision_grid_fixture,
        )
    end
    gmfrm_sparse_design_grid_fixture = optional_fixture_path("MFRM_GMFRM_SPARSE_DESIGN_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_sparse_design_grid.json"))
    if !isempty(gmfrm_sparse_design_grid_fixture)
        check_gmfrm_sparse_design_grid_fixture(
            gmfrm_sparse_design_grid_fixture,
        )
    end
    gmfrm_waic_influence_review_fixture = optional_fixture_path("MFRM_GMFRM_WAIC_INFLUENCE_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_waic_influence_review.json"))
    if !isempty(gmfrm_waic_influence_review_fixture)
        check_gmfrm_waic_influence_review_fixture(
            gmfrm_waic_influence_review_fixture,
        )
    end
    gmfrm_psis_loo_review_fixture = optional_fixture_path("MFRM_GMFRM_PSIS_LOO_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_psis_loo_review.json"))
    if !isempty(gmfrm_psis_loo_review_fixture)
        check_gmfrm_psis_loo_review_fixture(
            gmfrm_psis_loo_review_fixture,
        )
    end
    gmfrm_exact_loo_or_kfold_review_fixture = optional_fixture_path("MFRM_GMFRM_EXACT_LOO_OR_KFOLD_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_exact_loo_or_kfold_review.json"))
    if !isempty(gmfrm_exact_loo_or_kfold_review_fixture)
        check_gmfrm_exact_loo_or_kfold_review_fixture(
            gmfrm_exact_loo_or_kfold_review_fixture,
        )
    end
    gmfrm_guarded_fit_api_dry_run_fixture = optional_fixture_path("MFRM_GMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE", joinpath("test", "fixtures", "gmfrm_guarded_fit_api_dry_run.json"))
    if !isempty(gmfrm_guarded_fit_api_dry_run_fixture)
        check_gmfrm_guarded_fit_api_dry_run_fixture(
            gmfrm_guarded_fit_api_dry_run_fixture,
        )
    end
    gmfrm_guarded_fit_method_wiring_fixture = optional_fixture_path("MFRM_GMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE", joinpath("test", "fixtures", "gmfrm_guarded_fit_method_wiring.json"))
    if !isempty(gmfrm_guarded_fit_method_wiring_fixture)
        check_gmfrm_guarded_fit_method_wiring_fixture(
            gmfrm_guarded_fit_method_wiring_fixture,
        )
    end
    gmfrm_experimental_fit_validation_grid_fixture = optional_fixture_path("MFRM_GMFRM_EXPERIMENTAL_FIT_VALIDATION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_experimental_fit_validation_grid.json"))
    if !isempty(gmfrm_experimental_fit_validation_grid_fixture)
        check_gmfrm_experimental_fit_validation_grid_fixture(
            gmfrm_experimental_fit_validation_grid_fixture,
        )
    end
    gmfrm_posterior_predictive_grid_fixture = optional_fixture_path("MFRM_GMFRM_POSTERIOR_PREDICTIVE_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_posterior_predictive_grid.json"))
    if !isempty(gmfrm_posterior_predictive_grid_fixture)
        check_gmfrm_posterior_predictive_grid_fixture(
            gmfrm_posterior_predictive_grid_fixture,
        )
    end
    gmfrm_sparse_pathology_recovery_grid_fixture = optional_fixture_path("MFRM_GMFRM_SPARSE_PATHOLOGY_RECOVERY_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_sparse_pathology_recovery_grid.json"))
    if !isempty(gmfrm_sparse_pathology_recovery_grid_fixture)
        check_gmfrm_sparse_pathology_recovery_grid_fixture(
            gmfrm_sparse_pathology_recovery_grid_fixture,
        )
    end
    gmfrm_prior_likelihood_sensitivity_grid_fixture = optional_fixture_path("MFRM_GMFRM_PRIOR_LIKELIHOOD_SENSITIVITY_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_prior_likelihood_sensitivity_grid.json"))
    if !isempty(gmfrm_prior_likelihood_sensitivity_grid_fixture)
        check_gmfrm_prior_likelihood_sensitivity_grid_fixture(
            gmfrm_prior_likelihood_sensitivity_grid_fixture,
        )
    end
    gmfrm_real_data_case_study_fixture = optional_fixture_path("MFRM_GMFRM_REAL_DATA_CASE_STUDY_FIXTURE", joinpath("test", "fixtures", "gmfrm_real_data_case_study.json"))
    if !isempty(gmfrm_real_data_case_study_fixture)
        check_gmfrm_real_data_case_study_fixture(
            gmfrm_real_data_case_study_fixture,
        )
    end
    gmfrm_claim_recovery_reproduction_archive_fixture = optional_fixture_path(
        "MFRM_GMFRM_CLAIM_RECOVERY_REPRODUCTION_ARCHIVE_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_claim_recovery_reproduction_archive.json"))
    if !isempty(gmfrm_claim_recovery_reproduction_archive_fixture)
        check_gmfrm_claim_recovery_reproduction_archive_fixture(
            gmfrm_claim_recovery_reproduction_archive_fixture,
        )
    end
    gmfrm_full_paper_reproduction_archive_fixture = optional_fixture_path(
        "MFRM_GMFRM_FULL_PAPER_REPRODUCTION_ARCHIVE_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_full_paper_reproduction_archive.json"))
    if !isempty(gmfrm_full_paper_reproduction_archive_fixture)
        check_gmfrm_full_paper_reproduction_archive_fixture(
            gmfrm_full_paper_reproduction_archive_fixture,
        )
    end
    gmfrm_prediction_target_and_model_weight_policy_fixture = optional_fixture_path(
        "MFRM_GMFRM_PREDICTION_TARGET_AND_MODEL_WEIGHT_POLICY_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_prediction_target_and_model_weight_policy.json"))
    if !isempty(gmfrm_prediction_target_and_model_weight_policy_fixture)
        check_gmfrm_prediction_target_and_model_weight_policy_fixture(
            gmfrm_prediction_target_and_model_weight_policy_fixture,
        )
    end
    gmfrm_dff_estimand_validation_grid_fixture = optional_fixture_path("MFRM_GMFRM_DFF_ESTIMAND_VALIDATION_GRID_FIXTURE", joinpath("test", "fixtures", "gmfrm_dff_estimand_validation_grid.json"))
    if !isempty(gmfrm_dff_estimand_validation_grid_fixture)
        check_gmfrm_dff_estimand_validation_grid_fixture(
            gmfrm_dff_estimand_validation_grid_fixture,
        )
    end
    gmfrm_manuscript_scale_simulation_grid_fixture = optional_fixture_path(
        "MFRM_GMFRM_MANUSCRIPT_SCALE_SIMULATION_GRID_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_manuscript_scale_simulation_grid.json"))
    if !isempty(gmfrm_manuscript_scale_simulation_grid_fixture)
        check_gmfrm_manuscript_scale_simulation_grid_fixture(
            gmfrm_manuscript_scale_simulation_grid_fixture,
        )
    end
    gmfrm_broader_experimental_exposure_decision_review_fixture = optional_fixture_path(
        "MFRM_GMFRM_BROADER_EXPERIMENTAL_EXPOSURE_DECISION_REVIEW_FIXTURE",
        joinpath("test", "fixtures", "gmfrm_broader_experimental_exposure_decision_review.json"))
    if !isempty(gmfrm_broader_experimental_exposure_decision_review_fixture)
        check_gmfrm_broader_experimental_exposure_decision_review_fixture(
            gmfrm_broader_experimental_exposure_decision_review_fixture,
        )
    end
    gmfrm_guarded_exposure_review_fixture = optional_fixture_path("MFRM_GMFRM_GUARDED_EXPOSURE_REVIEW_FIXTURE", joinpath("test", "fixtures", "gmfrm_guarded_exposure_review.json"))
    if !isempty(gmfrm_guarded_exposure_review_fixture)
        check_gmfrm_guarded_exposure_review_fixture(
            gmfrm_guarded_exposure_review_fixture,
        )
    end
    gmfrm_bridge_fixture = optional_source_bridge_fixture_path(
        "MFRM_SOURCE_GMFRM_BRIDGESTAN_FIXTURE",
        joinpath("test", "fixtures", "source_gmfrm_bridge_logdensity.json"),
        joinpath("test", "stan", "source_gmfrm_fixture.stan"))
    if !isempty(gmfrm_bridge_fixture)
        check_source_bridge_fixture(
            gmfrm_bridge_fixture,
            gmfrm_target;
            expected_schema = "bayesianmgmfrm.source_gmfrm_bridge_logdensity.v1",
            expected_stan_model = "test/stan/source_gmfrm_fixture.stan",
        )
        check_gmfrm_bridge_direct_fixture(gmfrm_bridge_fixture, gmfrm_candidate)
    end
    @test_throws ArgumentError LogDensityProblems.logdensity(gmfrm_target, gmfrm_raw_params[1:end-1])
    @test_throws ArgumentError LogDensityProblems.logdensity(gmfrm_target, fill(Inf, gmfrm_raw_blueprint.n_parameters))
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params;
        finite_difference_coords = [0],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_transform_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(
        gmfrm_preview,
        gmfrm_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_pointwise_fixture(
        gmfrm_candidate,
        gmfrm_raw_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params[1:end-1],
    )
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_sampler_diagnostics(
        gmfrm_candidate,
        gmfrm_raw_params;
        rhat_threshold = 1.0,
    )
    @test_throws ArgumentError initial_params(gmfrm_target; value = Inf)
    @test_throws ArgumentError BayesianMGMFRM._SourceFixturePrior(; person_sd = 0.0)
    @test_throws ArgumentError BayesianMGMFRM._source_fixture_logdensity(identified_design)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(identified_design)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(identified_design)
    @test length(gmfrm_source_values) == length(gmfrm_predictors)
    @test all(row -> row.kernel === :gmfrm_source_aligned, gmfrm_source_values)
    @test all(row -> row.fixture_only && !row.fit_ready, gmfrm_source_values)
    gmfrm_row2_values = [0.0, 1.6 * (0.55 - (-0.1)), 1.6 * (0.55 - (-0.1)) + 1.6 * (0.55 - 0.1)]
    gmfrm_row2_value = only(filter(row -> row.row == 2 && row.category == 1, gmfrm_source_values))
    @test gmfrm_row2_value.observed
    @test gmfrm_row2_value.person_value ≈ 0.3
    @test gmfrm_row2_value.rater_value ≈ -0.05
    @test gmfrm_row2_value.item_value ≈ -0.2
    @test gmfrm_row2_value.location_value ≈ 0.55
    @test gmfrm_row2_value.item_discrimination_value ≈ 2.0
    @test gmfrm_row2_value.rater_consistency_value ≈ 0.8
    @test gmfrm_row2_value.scale_value ≈ 1.6
    @test gmfrm_row2_value.step_values ≈ [-0.1]
    @test gmfrm_row2_value.step_sum ≈ -0.1
    @test gmfrm_row2_value.scaled_step_sum ≈ -0.16
    @test gmfrm_row2_value.eta ≈ gmfrm_row2_values[2]
    @test gmfrm_row2_value.log_probability ≈ gmfrm_row2_values[2] - test_logsumexp(gmfrm_row2_values)
    gmfrm_row3_values = [0.0, 0.6 * (0.0 - 0.25), 0.6 * (0.0 - 0.25) + 0.6 * (0.0 - (-0.25))]
    gmfrm_row3_value = only(filter(row -> row.row == 3 && row.category == 2, gmfrm_source_values))
    @test gmfrm_row3_value.observed
    @test gmfrm_row3_value.scale_value ≈ 0.6
    @test gmfrm_row3_value.step_values ≈ [0.25, -0.25]
    @test gmfrm_row3_value.step_sum ≈ 0.0
    @test isapprox(gmfrm_row3_value.eta, gmfrm_row3_values[3]; atol = 1e-12)
    @test gmfrm_row3_value.log_probability ≈ gmfrm_row3_values[3] - test_logsumexp(gmfrm_row3_values)
    @test [row.log_probability for row in filter(row -> row.observed, gmfrm_source_values)] ≈
        gmfrm_source_pointwise
    bad_gmfrm_item_sum = copy(gmfrm_params)
    bad_gmfrm_item_sum[5] = -0.1
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, bad_gmfrm_item_sum)
    bad_gmfrm_product = copy(gmfrm_params)
    bad_gmfrm_product[7] = 1.8
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, bad_gmfrm_product)
    bad_gmfrm_consistency = copy(gmfrm_params)
    bad_gmfrm_consistency[9] = -0.1
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(gmfrm_preview, bad_gmfrm_consistency)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_source_fixture_values(identified_design, gmfrm_params)
    @test_throws ArgumentError linear_predictor_values(gmfrm_spec, zeros(length(gmfrm_preview.parameter_names)); preview = true)
    @test_throws ArgumentError linear_predictor_values(gmfrm_preview, zeros(length(gmfrm_preview.parameter_names)))
    @test_throws ArgumentError predictive_probabilities(gmfrm_preview, zeros(1, length(gmfrm_preview.parameter_names)))
    @test_throws ArgumentError getdesign(gmfrm_spec)
    @test_throws ArgumentError fit(gmfrm_spec; ndraws = 1, warmup = 0)
    gmfrm_experimental_fit = fit(gmfrm_spec;
        experimental = true,
        ndraws = 4,
        warmup = 4,
        chains = 2,
        step_size = 0.03,
        seed = 20260627,
        max_depth = 3,
        metric = :unit)
    @test gmfrm_experimental_fit isa GMFRMFit
    @test gmfrm_experimental_fit.design.spec.family === :gmfrm
    @test gmfrm_experimental_fit.design.spec.discrimination === :rater
    @test gmfrm_experimental_fit.backend === :advancedhmc
    @test gmfrm_experimental_fit.sampler === :nuts
    @test size(gmfrm_experimental_fit.draws, 1) == 8
    @test size(gmfrm_experimental_fit.draws, 2) ==
        length(gmfrm_experimental_fit.diagnostic_surface.raw_parameter_names)
    @test size(gmfrm_experimental_fit.direct_draws, 1) == 8
    @test size(gmfrm_experimental_fit.direct_pointwise_loglikelihood) ==
        (8, identified_data.n)
    @test all(isfinite, gmfrm_experimental_fit.log_posterior)
    @test pointwise_loglikelihood_matrix(gmfrm_experimental_fit) ==
        gmfrm_experimental_fit.direct_pointwise_loglikelihood
    gmfrm_direct_llmat = pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.direct_draws)
    gmfrm_raw_llmat = pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw)
    @test gmfrm_direct_llmat ≈
        gmfrm_experimental_fit.direct_pointwise_loglikelihood
    @test gmfrm_raw_llmat ≈
        gmfrm_experimental_fit.direct_pointwise_loglikelihood
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws)
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.direct_draws;
        parameter_space = :raw)
    @test loglikelihood(gmfrm_experimental_fit) ==
        gmfrm_experimental_fit.direct_loglikelihood
    @test logprior(gmfrm_experimental_fit) ≈
        gmfrm_experimental_fit.log_posterior .-
        gmfrm_experimental_fit.direct_loglikelihood
    @test logposterior(gmfrm_experimental_fit) ==
        gmfrm_experimental_fit.log_posterior
    @test loglikelihood(gmfrm_experimental_fit; draw_indices = [2, 1]) ==
        gmfrm_experimental_fit.direct_loglikelihood[[2, 1]]
    @test length(logprior(gmfrm_experimental_fit;
        ndraws = 2,
        rng = MersenneTwister(20260629))) == 2
    gmfrm_experimental_metadata = fit_metadata(gmfrm_experimental_fit)
    @test gmfrm_experimental_metadata.public_fit
    @test gmfrm_experimental_metadata.experimental_public
    @test gmfrm_experimental_metadata.scope === :scalar_gmfrm_fit_ready_candidate
    @test gmfrm_experimental_metadata.density_space === :raw_unconstrained
    @test gmfrm_experimental_metadata.n_direct_parameters ==
        size(gmfrm_experimental_fit.direct_draws, 2)
    gmfrm_experimental_diagnostics = diagnostics(gmfrm_experimental_fit)
    @test gmfrm_experimental_diagnostics.schema ==
        "bayesianmgmfrm.gmfrm_experimental_fit_diagnostics.v1"
    @test gmfrm_experimental_diagnostics.public_fit
    @test gmfrm_experimental_diagnostics.experimental_public
    @test gmfrm_experimental_diagnostics.summary.total_draws == 8
    @test length(sampler_diagnostics(gmfrm_experimental_fit)) == 2
    @test length(mcmc_diagnostics(gmfrm_experimental_fit)) ==
        size(gmfrm_experimental_fit.draws, 2)
    @test length(parameter_block_diagnostics(gmfrm_experimental_fit)) >= 1
    gmfrm_experimental_artifact =
        fit_artifact(gmfrm_experimental_fit; include_environment = false)
    @test gmfrm_experimental_artifact.schema ==
        "bayesianmgmfrm.gmfrm_experimental_fit_artifact.v1"
    @test gmfrm_experimental_artifact.public_fit
    @test gmfrm_experimental_artifact.experimental_public
    @test gmfrm_experimental_artifact.density_space === :raw_unconstrained
    @test gmfrm_experimental_artifact.raw_parameter_names ==
        gmfrm_experimental_fit.diagnostic_surface.raw_parameter_names
    @test gmfrm_experimental_artifact.direct_parameter_names ==
        gmfrm_experimental_fit.diagnostic_surface.direct_parameter_names
    @test size(gmfrm_experimental_artifact.pointwise_loglikelihood) ==
        (8, identified_data.n)
    @test !isempty(gmfrm_experimental_artifact.raw_to_direct_transform)
    @test !isempty(gmfrm_experimental_artifact.fixture_provenance)
    @test isnothing(gmfrm_experimental_artifact.raw_draws)
    @test isnothing(gmfrm_experimental_artifact.direct_draws)
    @test gmfrm_experimental_artifact.content_hash.value ==
        artifact_content_hash(gmfrm_experimental_artifact)
    @test gmfrm_experimental_artifact.archive_manifest.content_hash ==
        gmfrm_experimental_artifact.content_hash
    @test waic(gmfrm_experimental_fit).n_draws == 8
    @test waic(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.direct_draws).waic ≈
        waic(gmfrm_experimental_fit).waic
    @test waic(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw).waic ≈
        waic(gmfrm_experimental_fit).waic
    @test loo(gmfrm_experimental_fit).n_draws == 8
    @test loo(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw).looic ≈
        loo(gmfrm_experimental_fit).looic
    @test psis_loo(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw).looic ≈
        psis_loo(gmfrm_experimental_fit).looic
    gmfrm_comparison = compare_models(
        :gmfrm_a => gmfrm_experimental_fit,
        :gmfrm_b => gmfrm_experimental_fit;
        draw_indices = [1, 2])
    @test length(gmfrm_comparison) == 2
    @test all(row -> row.comparison_contract ===
        :same_observation_data_same_latent_dimensions, gmfrm_comparison)
    @test all(row -> row.model_family === :gmfrm, gmfrm_comparison)
    @test all(row -> row.thresholds === gmfrm_spec.thresholds, gmfrm_comparison)
    @test all(row -> row.dimensions == 1, gmfrm_comparison)
    @test all(row -> row.discrimination === :rater, gmfrm_comparison)
    @test all(row -> row.q_matrix === nothing, gmfrm_comparison)
    @test all(row -> row.data_signature ==
        gmfrm_spec.validation.data_signature, gmfrm_comparison)
    @test all(row -> row.category_levels ==
        identified_data.category_levels, gmfrm_comparison)
    @test length(waic_diagnostics(gmfrm_experimental_fit)) == identified_data.n
    @test length(waic_diagnostics(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw)) == identified_data.n
    @test length(loo_diagnostics(gmfrm_experimental_fit)) == identified_data.n
    @test length(loo_diagnostics(gmfrm_experimental_fit.design,
        gmfrm_experimental_fit.draws;
        parameter_space = :raw)) == identified_data.n
    gmfrm_probabilities =
        predictive_probabilities(gmfrm_experimental_fit; draw_indices = [1, 2])
    @test size(gmfrm_probabilities) ==
        (2, identified_data.n, length(identified_data.category_levels))
    @test all(draw -> all(row -> sum(gmfrm_probabilities[draw, row, :]) ≈ 1.0,
        1:identified_data.n), 1:2)
    @test all(row -> log(gmfrm_probabilities[1, row, identified_data.category[row]]) ≈
        gmfrm_experimental_fit.direct_pointwise_loglikelihood[1, row],
        1:identified_data.n)
    gmfrm_expected = expected_scores(gmfrm_experimental_fit; draw_indices = [1, 2])
    gmfrm_variances = predictive_variances(gmfrm_experimental_fit; draw_indices = [1, 2])
    gmfrm_residuals = predictive_residuals(gmfrm_experimental_fit; draw_indices = [1, 2])
    @test size(gmfrm_expected) == (2, identified_data.n)
    @test size(gmfrm_variances) == (2, identified_data.n)
    @test size(gmfrm_residuals) == (2, identified_data.n)
    @test all(>=(0.0), gmfrm_variances)
    for draw in 1:2, row in 1:identified_data.n
        manual_mean = sum(identified_data.category_levels[k] *
            gmfrm_probabilities[draw, row, k]
            for k in eachindex(identified_data.category_levels))
        manual_second = sum(identified_data.category_levels[k]^2 *
            gmfrm_probabilities[draw, row, k]
            for k in eachindex(identified_data.category_levels))
        @test gmfrm_expected[draw, row] ≈ manual_mean
        @test gmfrm_variances[draw, row] ≈ manual_second - manual_mean^2 atol = 1e-12
        @test gmfrm_residuals[draw, row] ≈ identified_data.score[row] - gmfrm_expected[draw, row]
    end
    gmfrm_residual_rows = residual_summary(gmfrm_experimental_fit;
        by = :rater,
        draw_indices = [1, 2])
    @test length(gmfrm_residual_rows) == length(identified_data.rater_levels)
    @test all(row -> row.facet === :rater, gmfrm_residual_rows)
    @test all(row -> row.n_draws == 2, gmfrm_residual_rows)
    @test all(row -> row.caveat ===
        :posterior_predictive_residual_screening_not_confirmatory,
        gmfrm_residual_rows)
    gmfrm_rater_diag = rater_diagnostics(gmfrm_experimental_fit;
        draw_indices = [1, 2])
    @test length(gmfrm_rater_diag) == length(identified_data.rater_levels)
    @test [row.level for row in gmfrm_rater_diag] == identified_data.rater_levels
    @test all(row -> row.facet === :rater, gmfrm_rater_diag)
    @test all(row -> row.model_family === :gmfrm, gmfrm_rater_diag)
    @test all(row -> row.method === :posterior_rater_diagnostics, gmfrm_rater_diag)
    @test all(row -> row.n_draws == 2, gmfrm_rater_diag)
    @test all(row -> row.discrimination_modeled == true, gmfrm_rater_diag)
    @test all(row -> row.discrimination_parameter === :rater_consistency,
        gmfrm_rater_diag)
    @test all(row -> row.discrimination_scale === :positive_consistency_multiplier,
        gmfrm_rater_diag)
    @test all(row -> row.fit_statistics_available == false, gmfrm_rater_diag)
    @test all(row -> row.infit_mean === missing && row.outfit_mean === missing,
        gmfrm_rater_diag)
    @test all(row -> row.fit_flag === missing, gmfrm_rater_diag)
    @test all(row -> row.caveat ===
        :rater_diagnostics_screening_not_confirmatory,
        gmfrm_rater_diag)
    for row in gmfrm_rater_diag
        level_index = findfirst(==(row.level), identified_data.rater_levels)
        obs = findall(==(level_index), identified_data.rater)
        severity_index = gmfrm_experimental_fit.design.blocks[:rater][level_index]
        consistency_index =
            gmfrm_experimental_fit.design.blocks[:rater_consistency][level_index]
        severity_by_draw = [
            Float64(gmfrm_experimental_fit.direct_draws[draw, severity_index])
            for draw in 1:2
        ]
        consistency_by_draw = [
            Float64(gmfrm_experimental_fit.direct_draws[draw, consistency_index])
            for draw in 1:2
        ]
        residual_row = only(filter(candidate -> candidate.level == row.level,
            gmfrm_residual_rows))
        @test row.rater == row.level
        @test row.rater_index == level_index
        @test row.n_observations == length(obs)
        @test row.severity_parameter_name ==
            gmfrm_experimental_fit.design.parameter_names[severity_index]
        @test row.discrimination_parameter_name ==
            gmfrm_experimental_fit.design.parameter_names[consistency_index]
        @test row.severity_mean ≈ sum(severity_by_draw) / length(severity_by_draw)
        @test row.discrimination_mean ≈
            sum(consistency_by_draw) / length(consistency_by_draw)
        @test row.discrimination_lower <=
            row.discrimination_median <= row.discrimination_upper
        @test row.residual_mean ≈ residual_row.residual_mean
        @test row.absolute_residual_mean ≈ residual_row.absolute_residual_mean
        @test row.rmse_mean ≈ residual_row.rmse_mean
        @test row.residual_flag === residual_row.flag
    end
    gmfrm_replicated = posterior_predict(gmfrm_experimental_fit;
        draw_indices = [1, 2],
        rng = MersenneTwister(20260628))
    @test size(gmfrm_replicated) == (2, identified_data.n)
    @test all(score -> score in identified_data.category_levels, gmfrm_replicated)
    gmfrm_ppc = posterior_predictive_check(gmfrm_experimental_fit;
        ndraws = 3,
        rng = MersenneTwister(20260629))
    @test size(gmfrm_ppc.replicated_scores) == (3, identified_data.n)
    @test gmfrm_ppc.category_levels == identified_data.category_levels
    @test gmfrm_ppc.person_levels == identified_data.person_levels
    @test gmfrm_ppc.rater_levels == identified_data.rater_levels
    @test gmfrm_ppc.item_levels == identified_data.item_levels
    gmfrm_ppc_summary = predictive_check_summary(gmfrm_ppc; interval = 0.8)
    expected_gmfrm_ppc_rows = 1 + length(identified_data.category_levels) +
        length(identified_data.person_levels) + length(identified_data.rater_levels) +
        length(identified_data.item_levels) +
        sum(length(levels) for levels in values(identified_data.optional_levels))
    @test length(gmfrm_ppc_summary) == expected_gmfrm_ppc_rows
    @test all(row -> row.n_replicates == 3, gmfrm_ppc_summary)
    @test all(row -> row.flag in (:ok, :outside_interval), gmfrm_ppc_summary)
    gmfrm_simulated_direct = simulate_responses(gmfrm_spec, gmfrm_params;
        preview = true,
        rng = MersenneTwister(20260631),
        output = :scores)
    gmfrm_simulated_raw = simulate_responses(gmfrm_spec, gmfrm_raw_params;
        preview = true,
        parameter_space = :raw,
        rng = MersenneTwister(20260631),
        output = :scores)
    @test gmfrm_simulated_direct == gmfrm_simulated_raw
    @test length(gmfrm_simulated_direct) == identified_data.n
    @test all(score -> score in identified_data.category_levels, gmfrm_simulated_direct)
    @test_throws ArgumentError simulate_responses(gmfrm_spec, gmfrm_params;
        output = :scores)
    gmfrm_design_recovery_direct = parameter_recovery(
        gmfrm_preview,
        reshape(gmfrm_params, 1, :),
        gmfrm_params)
    @test length(gmfrm_design_recovery_direct) == length(gmfrm_params)
    @test all(row -> row.model_family === :gmfrm, gmfrm_design_recovery_direct)
    @test all(row -> row.parameter_space === :direct, gmfrm_design_recovery_direct)
    @test all(row -> row.density_space === :constrained_direct,
        gmfrm_design_recovery_direct)
    @test [row.parameter for row in gmfrm_design_recovery_direct] ==
        gmfrm_preview.parameter_names
    gmfrm_design_recovery_raw = parameter_recovery(
        gmfrm_preview,
        reshape(gmfrm_raw_params, 1, :),
        gmfrm_raw_params;
        parameter_space = :raw)
    @test [row.parameter for row in gmfrm_design_recovery_raw] ==
        gmfrm_fit_ready_blueprint.parameter_names
    @test all(row -> row.parameter_space === :raw, gmfrm_design_recovery_raw)
    @test all(row -> row.density_space === :raw_unconstrained,
        gmfrm_design_recovery_raw)
    gmfrm_direct_truth = [
        sum(gmfrm_experimental_fit.direct_draws[:, col]) /
            size(gmfrm_experimental_fit.direct_draws, 1)
        for col in axes(gmfrm_experimental_fit.direct_draws, 2)
    ]
    gmfrm_fit_recovery_direct =
        parameter_recovery(gmfrm_experimental_fit, gmfrm_direct_truth)
    @test length(gmfrm_fit_recovery_direct) == length(gmfrm_params)
    @test all(row -> row.model_family === :gmfrm, gmfrm_fit_recovery_direct)
    @test all(row -> row.parameter_space === :direct, gmfrm_fit_recovery_direct)
    @test all(row -> row.fit_ready && row.public_fit && row.experimental_public,
        gmfrm_fit_recovery_direct)
    @test maximum(abs(row.bias) for row in gmfrm_fit_recovery_direct) < 1e-12
    gmfrm_raw_truth = [
        sum(gmfrm_experimental_fit.draws[:, col]) /
            size(gmfrm_experimental_fit.draws, 1)
        for col in axes(gmfrm_experimental_fit.draws, 2)
    ]
    gmfrm_fit_recovery_raw = parameter_recovery(gmfrm_experimental_fit,
        gmfrm_raw_truth;
        parameter_space = :raw)
    @test length(gmfrm_fit_recovery_raw) == gmfrm_raw_blueprint.n_parameters
    @test [row.parameter for row in gmfrm_fit_recovery_raw] ==
        gmfrm_fit_ready_blueprint.parameter_names
    @test all(row -> row.parameter_space === :raw, gmfrm_fit_recovery_raw)
    @test parameter_recovery_summary(gmfrm_experimental_fit, gmfrm_direct_truth;
        by = :all)[1].n_parameters == length(gmfrm_params)
    @test length(parameter_recovery_plot_data(gmfrm_experimental_fit,
        gmfrm_direct_truth)) == length(gmfrm_params)
    gmfrm_calibration = calibration_table(gmfrm_experimental_fit;
        draw_indices = [1, 2],
        bins = 3,
        interval = 0.8)
    @test length(gmfrm_calibration) == 3
    @test sum(row.n_observations for row in gmfrm_calibration) == identified_data.n
    @test all(row -> row.target === :expected_score, gmfrm_calibration)
    @test all(row -> row.flag in (:ok, :outside_interval), gmfrm_calibration)
    gmfrm_category_calibration = calibration_table(gmfrm_experimental_fit;
        target = :category_probability,
        category = last(identified_data.category_levels),
        draw_indices = [1, 2],
        bins = 2)
    @test length(gmfrm_category_calibration) == 2
    @test all(row -> row.target === :category_probability, gmfrm_category_calibration)
    @test all(row -> row.category == last(identified_data.category_levels),
        gmfrm_category_calibration)
    gmfrm_all_category_calibration = calibration_table(gmfrm_experimental_fit;
        target = :category_probability,
        category = :all,
        draw_indices = [1, 2],
        bins = 2)
    @test length(gmfrm_all_category_calibration) ==
        2 * length(identified_data.category_levels)
    @test Set(row.category for row in gmfrm_all_category_calibration) ==
        Set(identified_data.category_levels)
    @test all(row -> row.target === :category_probability,
        gmfrm_all_category_calibration)
    gmfrm_all_calibration = calibration_table(gmfrm_experimental_fit;
        target = :all,
        draw_indices = [1, 2],
        bins = 2)
    @test length(gmfrm_all_calibration) ==
        2 * (1 + length(identified_data.category_levels))
    @test all(row -> row.target === :expected_score,
        gmfrm_all_calibration[1:2])
    @test Set(row.category for row in gmfrm_all_calibration[3:end]) ==
        Set(identified_data.category_levels)
    @test_throws ArgumentError posterior_predict(gmfrm_experimental_fit; ndraws = 0)
    @test_throws ArgumentError posterior_predictive_check(gmfrm_experimental_fit;
        ndraws = 2,
        draw_indices = [1])
    @test_throws ArgumentError calibration_table(gmfrm_experimental_fit; bins = 0)
    @test_throws ArgumentError fit(gmfrm_spec;
        experimental = true,
        backend = :julia,
        ndraws = 1,
        warmup = 0)
    @test_throws ArgumentError fit(gmfrm_spec;
        experimental = true,
        prior = MFRMPrior(),
        ndraws = 1,
        warmup = 0)

    q_matrix = Bool[1 0; 0 1]
    mgmfrm_spec = mfrm_spec(identified_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix)
    @test mgmfrm_spec.family === :mgmfrm
    @test mgmfrm_spec.dimensions == 2
    @test mgmfrm_spec.estimation_status === :specified_only
    @test mgmfrm_spec.q_matrix == q_matrix
    @test_throws ArgumentError fit(mgmfrm_spec;
        experimental = true,
        backend = :julia,
        ndraws = 1,
        warmup = 0)
    @test any(row -> row.block === :item_dimension_discrimination && row.constraint === :confirmatory_q_mask,
        constraint_table(mgmfrm_spec))
    @test any(row -> row.block === :rater_consistency && row.constraint === :geometric_mean_one,
        constraint_table(mgmfrm_spec))
    @test any(row -> row.block === :item_steps && row.constraint === :first_step_zero_sum_to_zero,
        constraint_table(mgmfrm_spec))
    mgmfrm_identification = identification_declarations(mgmfrm_spec)
    @test any(row -> row.block === :person &&
        :multidimensional_gauge in row.components,
        mgmfrm_identification)
    @test any(row -> row.block === :q_matrix &&
        row.rule === :fixed &&
        :multidimensional_gauge in row.components,
        mgmfrm_identification)
    @test any(row -> row.block === :rater_consistency &&
        row.rule === :geometric_mean_one,
        mgmfrm_identification)
    mgmfrm_manifest = model_manifest(mgmfrm_spec)
    @test mgmfrm_manifest.spec.scope === :planned_multidimensional_gmfrm
    @test mgmfrm_manifest.spec.q_matrix == q_matrix
    @test any(row -> row.block === :q_matrix && row.rule === :fixed,
        mgmfrm_manifest.spec.identification_declarations)
    @test mgmfrm_manifest.spec.equation.family === :mgmfrm
    @test occursin("1.7 * alpha_r", mgmfrm_manifest.spec.equation.kernel)
    @test :item_dimension_discrimination in mgmfrm_manifest.spec.equation.required_blocks
    @test :multidimensional_ability_prior_and_gauge in
        mgmfrm_manifest.spec.equation.implementation_gaps
    mgmfrm_preview = getdesign(mgmfrm_spec; preview = true)
    @test mgmfrm_preview.spec === mgmfrm_spec
    @test mgmfrm_preview.identification[:person] === :multidimensional_location_gauge
    @test mgmfrm_preview.identification[:rater] === :sum_to_zero
    @test mgmfrm_preview.identification[:item_dimension_discrimination] === :confirmatory_q_mask
    @test mgmfrm_preview.identification[:rater_consistency] === :geometric_mean_one
    @test mgmfrm_preview.identification[:item_steps] === :first_step_zero_sum_to_zero
    mgmfrm_preview_identification = identification_declarations(mgmfrm_preview)
    q_identification = only(filter(row -> row.block === :q_matrix,
        mgmfrm_preview_identification))
    @test q_identification.rule === :fixed
    @test q_identification.n_parameters == 0
    @test isempty(q_identification.parameter_names)
    loading_identification = only(filter(row ->
        row.block === :item_dimension_discrimination,
        mgmfrm_preview_identification))
    @test :multidimensional_gauge in loading_identification.components
    @test loading_identification.n_parameters == count(q_matrix)
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:person]] == [
        "person[E1,dim=1]",
        "person[E1,dim=2]",
        "person[E2,dim=1]",
        "person[E2,dim=2]",
    ]
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:item_dimension_discrimination]] == [
        "item_dimension_discrimination[item=I1,dim=1]",
        "item_dimension_discrimination[item=I2,dim=2]",
    ]
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:rater_consistency]] == [
        "rater_consistency[rater=R1]",
        "rater_consistency[rater=R2]",
    ]
    @test mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:item_steps]] == [
        "item_step[item=I1,m=2]",
        "item_step[item=I2,m=2]",
    ]
    @test length(mgmfrm_preview.parameter_names) == 14
    mgmfrm_preview_constraints = constraint_table(mgmfrm_preview)
    item_dim_row = only(filter(row -> row.block === :item_dimension_discrimination, mgmfrm_preview_constraints))
    @test item_dim_row.n_parameters == count(q_matrix)
    @test item_dim_row.parameter_names == mgmfrm_preview.parameter_names[mgmfrm_preview.blocks[:item_dimension_discrimination]]
    q_row = only(filter(row -> row.block === :q_matrix, mgmfrm_preview_constraints))
    @test q_row.n_parameters == 0
    preview_manifest = model_manifest(mgmfrm_preview)
    @test preview_manifest.object === :design
    @test preview_manifest.spec.estimation_status === :specified_only
    @test preview_manifest.design.n_parameters == length(mgmfrm_preview.parameter_names)
    @test any(row -> row.block === :item_steps && row.n_parameters == 2,
        preview_manifest.design.blocks)
    @test preview_manifest.design.raw_parameterization.family === :mgmfrm
    @test preview_manifest.design.raw_parameterization.public_fit === false
    @test preview_manifest.design.raw_parameterization.jacobian_policy === :none_raw_coordinate_density
    @test preview_manifest.design.raw_parameterization.promotion_candidate === nothing
    mgmfrm_rows = design_row_table(mgmfrm_spec; preview = true)
    @test mgmfrm_rows[1].person_parameter_indices == [1, 2]
    @test mgmfrm_rows[1].loading_dimensions == [1]
    @test mgmfrm_rows[1].item_dimension_discrimination_parameter_names == ["item_dimension_discrimination[item=I1,dim=1]"]
    @test mgmfrm_rows[1].rater_consistency_parameter_name == "rater_consistency[rater=R1]"
    @test mgmfrm_rows[2].rater_parameter_name == "rater[R2]"
    @test mgmfrm_rows[3].loading_dimensions == [2]
    @test mgmfrm_rows[3].item_dimension_discrimination_parameter_names == ["item_dimension_discrimination[item=I2,dim=2]"]
    @test isequal(mgmfrm_rows[3].threshold_parameter_names, ["item_step[item=I2,m=2]", missing])
    @test mgmfrm_rows[3].threshold_blocks == [:item_steps, :item_steps]
    @test isempty(mgmfrm_rows[3].discrimination_parameter_indices)
    @test_throws ArgumentError linear_predictor_table(mgmfrm_spec)
    mgmfrm_predictors = linear_predictor_table(mgmfrm_spec; preview = true)
    @test length(mgmfrm_predictors) == identified_data.n * length(identified_data.category_levels)
    @test mgmfrm_predictors[1].kernel === :mgmfrm_source_aligned
    @test mgmfrm_predictors[1].active_dimensions == [1]
    @test mgmfrm_predictors[1].location_multiplier == 0
    mgmfrm_row3_cat2 = only(filter(row -> row.row == 3 && row.category == 2, mgmfrm_predictors))
    @test mgmfrm_row3_cat2.observed
    @test mgmfrm_row3_cat2.location_multiplier == 2
    @test mgmfrm_row3_cat2.active_dimensions == [2]
    @test mgmfrm_row3_cat2.item_dimension_discrimination_parameter_names == ["item_dimension_discrimination[item=I2,dim=2]"]
    @test mgmfrm_row3_cat2.rater_consistency_parameter_name == "rater_consistency[rater=R1]"
    @test isequal(mgmfrm_row3_cat2.step_parameter_names, ["item_step[item=I2,m=2]", missing])
    mgmfrm_params = [
        0.2, -0.1,      # E1 dimensions
        -0.3, 0.4,      # E2 dimensions
        0.15, -0.15,    # rater severities, sum-to-zero
        -0.2, 0.1,      # item difficulties
        1.5, 0.7,       # item-dimension discriminations under q_matrix
        1.25, 0.8,      # rater consistencies, product-one
        0.3, -0.2,      # free item steps for m = 2
    ]
    mgmfrm_raw_blueprint = BayesianMGMFRM._mgmfrm_source_unconstrained_blueprint(mgmfrm_preview)
    mgmfrm_fit_ready_blueprint =
        BayesianMGMFRM._mgmfrm_fit_ready_candidate_blueprint(mgmfrm_preview)
    @test mgmfrm_raw_blueprint.n_parameters == 12
    @test mgmfrm_raw_blueprint.scope === :mgmfrm_source_aligned
    @test mgmfrm_raw_blueprint.status === :internal_source_fixture
    @test mgmfrm_raw_blueprint.compiler_stage === :source_fixture
    @test mgmfrm_raw_blueprint.fixture_only
    @test mgmfrm_fit_ready_blueprint.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_fit_ready_blueprint.status === :internal_fit_ready_candidate
    @test mgmfrm_fit_ready_blueprint.compiler_stage === :fit_ready_candidate
    @test !mgmfrm_fit_ready_blueprint.fixture_only
    @test !mgmfrm_fit_ready_blueprint.fit_ready
    @test mgmfrm_fit_ready_blueprint.parameter_names == mgmfrm_raw_blueprint.parameter_names
    @test mgmfrm_fit_ready_blueprint.constrained_parameter_names ==
        mgmfrm_raw_blueprint.constrained_parameter_names
    @test mgmfrm_raw_blueprint.parameter_names[mgmfrm_raw_blueprint.blocks[:rater_free]] == ["raw_rater[R1]"]
    @test mgmfrm_raw_blueprint.parameter_names[mgmfrm_raw_blueprint.blocks[:log_rater_consistency_free]] ==
        ["raw_log_rater_consistency[R1]"]
    @test_throws ArgumentError fit_ready_parameter_layout(mgmfrm_spec)
    mgmfrm_layout = fit_ready_parameter_layout(mgmfrm_spec; preview = true)
    @test mgmfrm_layout.schema == "bayesianmgmfrm.fit_ready_parameter_layout.v1"
    @test mgmfrm_layout.family === :mgmfrm
    @test mgmfrm_layout.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_layout.status === :internal_fit_ready_candidate
    @test mgmfrm_layout.parameterization === :raw_to_constrained
    @test mgmfrm_layout.experimental_public
    @test !mgmfrm_layout.public_fit
    @test !mgmfrm_layout.fit_ready
    @test mgmfrm_layout.raw_parameter_names == mgmfrm_fit_ready_blueprint.parameter_names
    @test mgmfrm_layout.constrained_parameter_names ==
        mgmfrm_fit_ready_blueprint.constrained_parameter_names
    @test any(row -> row.block === :log_item_dimension_discrimination &&
        row.parameter_names == [
            "raw_log_item_dimension_discrimination[item=I1,dim=1]",
            "raw_log_item_dimension_discrimination[item=I2,dim=2]",
        ],
        mgmfrm_layout.raw_blocks)
    @test any(row -> row.block === :item_dimension_discrimination &&
        row.parameter_names == [
            "item_dimension_discrimination[item=I1,dim=1]",
            "item_dimension_discrimination[item=I2,dim=2]",
        ],
        mgmfrm_layout.constrained_blocks)
    @test any(row -> row.raw_block === :log_rater_consistency_free &&
        row.constrained_block === :rater_consistency &&
        row.constraint === :geometric_mean_one,
        mgmfrm_layout.transforms)
    @test_throws ArgumentError domain_compilation_summary(mgmfrm_spec)
    mgmfrm_domain = domain_compilation_summary(mgmfrm_spec; preview = true)
    mgmfrm_loading_block = only(filter(row ->
        row.block === :item_dimension_discrimination &&
        row.compiled_role === :loading_block,
        mgmfrm_domain))
    @test mgmfrm_loading_block.raw_block === :log_item_dimension_discrimination
    @test mgmfrm_loading_block.constraint === :confirmatory_q_mask
    @test mgmfrm_loading_block.prior_block === :log_item_dimension_discrimination
    @test mgmfrm_loading_block.parameter_names == [
        "item_dimension_discrimination[item=I1,dim=1]",
        "item_dimension_discrimination[item=I2,dim=2]",
    ]
    mgmfrm_loading_mask = only(filter(row ->
        row.compiled_role === :loading_mask,
        mgmfrm_domain))
    @test mgmfrm_loading_mask.domain_option === :q_matrix
    @test mgmfrm_loading_mask.block === :item_dimension_discrimination
    @test mgmfrm_loading_mask.loading_mask == q_matrix
    @test mgmfrm_loading_mask.validation_requirement === :fixed_q_matrix_validated
    @test !mgmfrm_loading_mask.fit_ready
    @test !mgmfrm_loading_mask.public_fit
    mgmfrm_scoring_domain = only(filter(row ->
        row.compiled_role === :scoring_vector,
        mgmfrm_domain))
    @test mgmfrm_scoring_domain.block === :item_steps
    @test mgmfrm_scoring_domain.parameter_names == [
        "item_step[item=I1,m=2]",
        "item_step[item=I2,m=2]",
    ]
    @test mgmfrm_scoring_domain.scoring_vector == identified_data.category_levels
    mgmfrm_raw_manifest = preview_manifest.design.raw_parameterization
    @test mgmfrm_raw_manifest.n_raw_parameters == mgmfrm_raw_blueprint.n_parameters
    @test mgmfrm_raw_manifest.raw_parameter_names == mgmfrm_raw_blueprint.parameter_names
    mgmfrm_rater_transform = only(filter(row -> row.raw_block === :rater_free,
        mgmfrm_raw_manifest.transforms))
    @test mgmfrm_rater_transform.constrained_block === :rater
    @test mgmfrm_rater_transform.transform === :sum_to_zero_last
    @test mgmfrm_rater_transform.raw_parameter_names == ["raw_rater[R1]"]
    @test mgmfrm_rater_transform.constrained_parameter_names == ["rater[R1]", "rater[R2]"]
    mgmfrm_consistency_transform = only(filter(row -> row.raw_block === :log_rater_consistency_free,
        mgmfrm_raw_manifest.transforms))
    @test mgmfrm_consistency_transform.transform === :geometric_mean_one_log_last
    @test mgmfrm_consistency_transform.constrained_block === :rater_consistency
    @test mgmfrm_consistency_transform.prior_block === :log_rater_consistency
    @test mgmfrm_raw_manifest.promotion_candidate === nothing
    mgmfrm_confirmatory_candidate = mgmfrm_raw_manifest.confirmatory_candidate
    @test mgmfrm_confirmatory_candidate.schema ==
        "bayesianmgmfrm.mgmfrm_confirmatory_candidate.v1"
    @test mgmfrm_confirmatory_candidate.family === :mgmfrm
    @test mgmfrm_confirmatory_candidate.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_confirmatory_candidate.status === :internal_fit_ready_candidate
    @test mgmfrm_confirmatory_candidate.public_fit
    @test mgmfrm_confirmatory_candidate.experimental_public
    @test mgmfrm_confirmatory_candidate.fit_ready
    @test !mgmfrm_confirmatory_candidate.fixture_only
    @test !mgmfrm_confirmatory_candidate.source_fixture_only
    @test mgmfrm_confirmatory_candidate.compiler_stage === :fit_ready_candidate
    @test mgmfrm_confirmatory_candidate.source_oracle === :mgmfrm_source_aligned
    @test mgmfrm_confirmatory_candidate.fit_ready_transform_ready
    @test mgmfrm_confirmatory_candidate.fit_ready_pointwise_oracle_ready
    @test mgmfrm_confirmatory_candidate.dimensions == 2
    @test mgmfrm_confirmatory_candidate.q_matrix == q_matrix
    @test mgmfrm_confirmatory_candidate.latent_correlation === :identity_fixed
    @test mgmfrm_confirmatory_candidate.ability_location === :zero_by_dimension
    @test mgmfrm_confirmatory_candidate.ability_scale === :unit_variance_by_dimension
    @test mgmfrm_confirmatory_candidate.source_scale == 1.7
    @test mgmfrm_confirmatory_candidate.interpreted_loading_sign === :positive
    @test mgmfrm_confirmatory_candidate.raw_parameter_names ==
        mgmfrm_raw_blueprint.parameter_names
    @test mgmfrm_confirmatory_candidate.constrained_parameter_names ==
        mgmfrm_preview.parameter_names
    @test any(row -> row.gauge === :q_matrix &&
        row.status === :fixed &&
        row.value == q_matrix,
        mgmfrm_confirmatory_candidate.gauge_rows)
    @test any(row -> row.gauge === :latent_correlation &&
        row.value === :identity,
        mgmfrm_confirmatory_candidate.gauge_rows)
    @test any(row -> row.block === :item_dimension_discrimination &&
        row.rule === :positive_interpreted_q_masked_loadings,
        mgmfrm_confirmatory_candidate.sign_positive_rules)
    @test any(row -> row.evidence === :bridgestan_source_oracle &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test any(row -> row.evidence === :fit_ready_bridge_pointwise_oracle &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test any(row -> row.evidence === :fit_ready_transform_manifest &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test any(row -> row.evidence === :fit_ready_pointwise_fixture &&
        row.status === :done &&
        row.artifact === :mgmfrm_confirmatory_candidate_pointwise_fixture,
        mgmfrm_confirmatory_candidate.evidence_rows)
    @test !any(row -> row.blocker === :fit_ready_mgmfrm_bridge_oracle_missing,
        mgmfrm_confirmatory_candidate.blocker_rows)
    @test !any(row -> row.blocker === :mgmfrm_sampler_diagnostics_missing,
        mgmfrm_confirmatory_candidate.blocker_rows)
    @test !any(row -> row.blocker === :mgmfrm_recovery_smoke_missing,
        mgmfrm_confirmatory_candidate.blocker_rows)
    @test isempty(mgmfrm_confirmatory_candidate.blocker_rows)
    @test any(row -> row.gate === :confirmatory_q_mask &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :fit_ready_raw_transform_manifest &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :fit_ready_pointwise_fixture &&
        row.status === :done &&
        row.evidence === :mgmfrm_confirmatory_candidate_pointwise_fixture,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :fit_ready_bridge_pointwise_oracle &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :sampler_diagnostic_study &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :recovery_smoke_study &&
        row.status === :done,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test any(row -> row.gate === :public_fit_api &&
        row.status === :done &&
        row.evidence === :mgmfrm_experimental_public_api_decision,
        mgmfrm_confirmatory_candidate.candidate_gates)
    @test mgmfrm_confirmatory_candidate.summary.candidate_frozen
    @test mgmfrm_confirmatory_candidate.summary.fit_allowed
    @test mgmfrm_confirmatory_candidate.summary.n_evidence_done >= 7
    @test mgmfrm_confirmatory_candidate.summary.n_evidence_pending == 0
    @test mgmfrm_confirmatory_candidate.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    mgmfrm_experimental_decision =
        mgmfrm_confirmatory_candidate.experimental_public_api_decision
    @test mgmfrm_experimental_decision.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_public_api_decision.v1"
    @test mgmfrm_experimental_decision.family === :mgmfrm
    @test mgmfrm_experimental_decision.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_experimental_decision.status === :experimental_public
    @test mgmfrm_experimental_decision.decision === :enable_guarded_experimental
    @test mgmfrm_experimental_decision.public_fit
    @test mgmfrm_experimental_decision.experimental_public
    @test mgmfrm_experimental_decision.fit_ready
    @test mgmfrm_experimental_decision.proposed_entrypoint ==
        "fit(spec; experimental = true)"
    @test mgmfrm_experimental_decision.guarded_local_entrypoint ===
        :_fit_guarded_mgmfrm
    @test mgmfrm_experimental_decision.guarded_local_fit_target_constructor ===
        :_mgmfrm_guarded_local_fit_logdensity
    @test mgmfrm_experimental_decision.guarded_local_fit_sampler_diagnostic_constructor ===
        :_mgmfrm_guarded_local_fit_sampler_diagnostics
    @test mgmfrm_experimental_decision.guarded_local_fit_artifact_schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_experimental_decision.experimental_fit_artifact_schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_experimental_decision.candidate_chain_study_artifact ==
        "test/fixtures/mgmfrm_candidate_chain_study.json"
    @test mgmfrm_experimental_decision.recovery_smoke_artifact ==
        "test/fixtures/mgmfrm_recovery_smoke.json"
    @test mgmfrm_experimental_decision.baseline_comparison_artifact ==
        "test/fixtures/mgmfrm_baseline_comparison.json"
    @test mgmfrm_experimental_decision.sparse_recovery_grid_artifact ==
        "test/fixtures/mgmfrm_sparse_recovery_grid.json"
    @test mgmfrm_experimental_decision.guarded_fit_method_wiring_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_method_wiring.json"
    @test mgmfrm_experimental_decision.guarded_fit_validation_grid_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_validation_grid.json"
    @test mgmfrm_experimental_decision.guarded_fit_api_dry_run_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json"
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_artifact ==
        "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json"
    @test mgmfrm_experimental_decision.dff_estimand_validation_grid_artifact ==
        "test/fixtures/gmfrm_dff_estimand_validation_grid.json"
    @test mgmfrm_experimental_decision.manuscript_scale_simulation_grid_artifact ==
        "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json"
    @test mgmfrm_experimental_decision.full_paper_reproduction_archive_artifact ==
        "test/fixtures/gmfrm_full_paper_reproduction_archive.json"
    @test mgmfrm_experimental_decision.caveat_docs_artifact ==
        "docs/src/fitting.md#guarded-generalized-model-caveats"
    mgmfrm_prior_policy = mgmfrm_experimental_decision.prior_jacobian_policy
    @test mgmfrm_prior_policy.schema ==
        "bayesianmgmfrm.generalized_raw_prior_jacobian_policy.v1"
    @test mgmfrm_prior_policy.family === :mgmfrm
    @test mgmfrm_prior_policy.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_prior_policy.status === :policy_recorded
    @test mgmfrm_prior_policy.prior_policy === :independent_normal_raw_coordinates
    @test !mgmfrm_prior_policy.direct_scale_priors
    @test mgmfrm_prior_policy.jacobian_policy === :none_raw_coordinate_density
    mgmfrm_fit_artifact_contract =
        mgmfrm_experimental_decision.fit_artifact_contract
    @test mgmfrm_fit_artifact_contract.schema ==
        "bayesianmgmfrm.experimental_generalized_fit_artifact_contract.v1"
    @test mgmfrm_fit_artifact_contract.family === :mgmfrm
    @test mgmfrm_fit_artifact_contract.scope === :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_fit_artifact_contract.status === :contract_recorded
    @test mgmfrm_fit_artifact_contract.public_fit
    @test mgmfrm_fit_artifact_contract.experimental_public
    @test mgmfrm_fit_artifact_contract.artifact_kind ===
        :experimental_generalized_fit_artifact
    @test mgmfrm_fit_artifact_contract.summary.enables_public_fit
    @test any(row -> row.field === :q_matrix &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.field === :latent_correlation &&
        row.status === :required,
        mgmfrm_fit_artifact_contract.required_fields)
    @test any(row -> row.artifact === :bridge_oracle &&
        row.value == "test/fixtures/source_mgmfrm_bridge_logdensity.json#confirmatory_candidate",
        mgmfrm_fit_artifact_contract.provenance_rows)
    @test any(row -> row.option === :q_matrix &&
        row.value === :fixed_confirmatory,
        mgmfrm_experimental_decision.accepted_candidate_options)
    @test any(row -> row.option === :latent_correlation &&
        row.value === :free &&
        row.status === :blocked,
        mgmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :sparse_design_claims &&
        row.value === :enabled &&
        row.status === :blocked_broader_claim &&
        row.blocker === :broader_sparse_mgmfrm_claim_scope_not_promoted,
        mgmfrm_experimental_decision.rejected_public_options)
    @test any(row -> row.option === :baseline_comparison &&
        row.value === :mfrm_rsm_pcm_comparison &&
        row.status === :evidence_only_for_guarded_fit &&
        row.blocker === :model_weight_or_superiority_claim_not_promoted,
        mgmfrm_experimental_decision.rejected_public_options)
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.status ===
        :review_recorded
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.review_target ===
        :confirmatory_mgmfrm_guarded_fit_public_exposure
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.public_exposure_support ===
        :supports_fixed_q_confirmatory_mgmfrm_experimental_fit
    @test mgmfrm_experimental_decision.guarded_fit_public_exposure_review_interpretation.required_followup ===
        :satisfied_by_prediction_target_and_model_weight_policy
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_artifact ==
        "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json"
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_interpretation.status ===
        :policy_recorded
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_interpretation.public_exposure_support ===
        :guarded_confirmatory_mgmfrm_fit_enabled_no_weight_claims
    @test mgmfrm_experimental_decision.prediction_target_and_model_weight_policy_interpretation.required_followup ===
        :manual_publication_or_registration_by_user_only
    @test any(row -> row.evidence === :bridgestan_fit_ready_oracle &&
        row.status === :done,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :candidate_chain_study &&
        row.status === :done,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :recovery_smoke_study &&
        row.status === :done,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :baseline_comparison &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_baseline_comparison.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :sparse_recovery_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_sparse_recovery_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_method_wiring &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_guarded_fit_method_wiring.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_guarded_fit_validation_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_api_dry_run &&
        row.status === :done &&
        row.artifact == "test/fixtures/mgmfrm_guarded_fit_api_dry_run.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_local_fit_entrypoint &&
        row.status === :done &&
        row.artifact === :_fit_guarded_mgmfrm,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :guarded_fit_public_exposure_review &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/mgmfrm_guarded_fit_public_exposure_review.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :prediction_target_and_model_weight_policy &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_prediction_target_and_model_weight_policy.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :dff_estimand_validation_grid &&
        row.status === :done &&
        row.artifact == "test/fixtures/gmfrm_dff_estimand_validation_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :manuscript_scale_simulation_grid &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_manuscript_scale_simulation_grid.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :full_paper_reproduction_archive &&
        row.status === :done &&
        row.artifact ==
            "test/fixtures/gmfrm_full_paper_reproduction_archive.json",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :public_caveat_docs &&
        row.status === :done &&
        row.artifact == "docs/src/fitting.md#guarded-generalized-model-caveats",
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :fit_artifact_manifest_for_experimental_public &&
        row.status === :done &&
        row.artifact === :experimental_public_fit_artifact_contract,
        mgmfrm_experimental_decision.evidence_rows)
    @test any(row -> row.evidence === :direct_prior_jacobian_policy &&
        row.status === :done &&
        row.artifact === :generalized_raw_prior_jacobian_policy,
        mgmfrm_experimental_decision.evidence_rows)
    @test !any(row -> row.blocker === :public_fit_artifact_contract_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :direct_prior_jacobian_policy_pending,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :public_caveat_docs_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :baseline_comparison_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :sparse_recovery_grid_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :dff_estimand_and_validation_evidence_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :manuscript_scale_simulation_grid_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :full_paper_reproduction_archive_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test !any(row -> row.blocker === :manual_public_scope_review_for_mgmfrm_fit_missing,
        mgmfrm_experimental_decision.blocker_rows)
    @test mgmfrm_experimental_decision.summary.n_evidence_done >= 17
    @test mgmfrm_experimental_decision.summary.n_evidence_pending == 0
    @test mgmfrm_experimental_decision.summary.n_evidence_blocked == 0
    @test mgmfrm_experimental_decision.summary.fit_allowed
    @test mgmfrm_experimental_decision.summary.experimental_keyword_enabled
    @test mgmfrm_experimental_decision.summary.n_blockers == 0
    @test mgmfrm_experimental_decision.summary.next_gate ===
        :manual_publication_or_registration_by_user_only
    mgmfrm_raw_params = [
        0.2, -0.1,
        -0.3, 0.4,
        0.15,
        -0.2, 0.1,
        log(1.5), log(0.7),
        log(1.25),
        0.3, -0.2,
    ]
    @test BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params,
    ) ≈ mgmfrm_params
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params[1:end-1],
    )
    for block in (:log_item_dimension_discrimination, :log_rater_consistency_free),
            boundary_value in (800.0, -1000.0)
        boundary_raw_params = copy(mgmfrm_raw_params)
        boundary_raw_params[first(mgmfrm_raw_blueprint.blocks[block])] = boundary_value
        @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_constrained_params_from_unconstrained(
            mgmfrm_preview,
            boundary_raw_params,
        )
    end
    mgmfrm_source_values = BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, mgmfrm_params)
    mgmfrm_source_pointwise =
        BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood(mgmfrm_preview, mgmfrm_params)
    mgmfrm_direct_pointwise_fixture =
        BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(
            mgmfrm_preview,
            mgmfrm_params,
        )
    @test mgmfrm_direct_pointwise_fixture.schema ==
        "bayesianmgmfrm.mgmfrm_confirmatory_candidate_pointwise_fixture.v1"
    @test mgmfrm_direct_pointwise_fixture.summary.passed
    @test mgmfrm_direct_pointwise_fixture.summary.flag === :ok
    @test mgmfrm_direct_pointwise_fixture.scope ===
        :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_direct_pointwise_fixture.density_space === :constrained_direct
    @test mgmfrm_direct_pointwise_fixture.q_matrix == q_matrix
    @test mgmfrm_direct_pointwise_fixture.latent_correlation === :identity_fixed
    @test mgmfrm_direct_pointwise_fixture.parameter_layout.scope ===
        :minimal_confirmatory_mgmfrm_candidate
    @test mgmfrm_direct_pointwise_fixture.parameter_layout.constrained_parameter_names ==
        mgmfrm_direct_pointwise_fixture.parameter_names
    @test mgmfrm_direct_pointwise_fixture.parameter_names ==
        mgmfrm_preview.parameter_names
    @test mgmfrm_direct_pointwise_fixture.parameter_values ≈ mgmfrm_params
    @test mgmfrm_direct_pointwise_fixture.summary.n_rows == length(mgmfrm_predictors)
    @test mgmfrm_direct_pointwise_fixture.summary.n_pointwise == identified_data.n
    @test mgmfrm_direct_pointwise_fixture.pointwise_loglikelihood ≈
        mgmfrm_source_pointwise
    @test mgmfrm_direct_pointwise_fixture.loglikelihood ≈
        sum(mgmfrm_source_pointwise)
    @test isequal(mgmfrm_direct_pointwise_fixture.rows, mgmfrm_source_values)
    @test all(row -> row.passed, mgmfrm_direct_pointwise_fixture.constraint_rows)
    @test only(filter(row -> row.block === :rater_consistency,
        mgmfrm_direct_pointwise_fixture.blocks)).values ≈ [1.25, 0.8]
    @test BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params,
    ) ≈ mgmfrm_source_pointwise
    @test BayesianMGMFRM._mgmfrm_source_loglikelihood_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params,
    ) ≈ sum(mgmfrm_source_pointwise)
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
        mgmfrm_preview,
        mgmfrm_raw_params[1:end-1],
    )
    mgmfrm_target = BayesianMGMFRM._source_fixture_logdensity(mgmfrm_preview; prior = source_prior)
    mgmfrm_spec_target = BayesianMGMFRM._source_fixture_logdensity(mgmfrm_spec; prior = source_prior)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(mgmfrm_preview)
    @test_throws ArgumentError BayesianMGMFRM._gmfrm_fit_ready_candidate_blueprint(mgmfrm_preview)
    @test LogDensityProblems.dimension(mgmfrm_target) == mgmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.dimension(mgmfrm_spec_target) == mgmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.capabilities(typeof(mgmfrm_target)) == LogDensityProblems.LogDensityOrder{0}()
    @test initial_params(mgmfrm_target; value = -0.05) == fill(-0.05, mgmfrm_raw_blueprint.n_parameters)
    @test occursin("SourceFixtureLogDensity(mgmfrm", sprint(show, mgmfrm_target))
    mgmfrm_prior_sds = [
        1.1, 1.1, 1.1, 1.1,
        1.2,
        1.3, 1.3,
        1.4, 1.4,
        1.5,
        1.6, 1.6,
    ]
    mgmfrm_expected_prior = sum(test_normal_logpdf(x, sd)
        for (x, sd) in zip(mgmfrm_raw_params, mgmfrm_prior_sds))
    @test BayesianMGMFRM._source_fixture_logprior(mgmfrm_target, mgmfrm_raw_params) ≈
        mgmfrm_expected_prior
    @test BayesianMGMFRM._source_fixture_loglikelihood(mgmfrm_target, mgmfrm_raw_params) ≈
        sum(mgmfrm_source_pointwise)
    @test LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params) ≈
        sum(mgmfrm_source_pointwise) + mgmfrm_expected_prior
    @test LogDensityProblems.logdensity(mgmfrm_spec_target, mgmfrm_raw_params) ≈
        LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params)
    mgmfrm_logp = x -> LogDensityProblems.logdensity(mgmfrm_target, x)
    mgmfrm_forward_gradient = check_forwarddiff_gradient(mgmfrm_logp, mgmfrm_raw_params)
    @test length(mgmfrm_forward_gradient) == mgmfrm_raw_blueprint.n_parameters
    mgmfrm_hmc_samples, mgmfrm_hmc_stats = check_advancedhmc_smoke(
        mgmfrm_target,
        mgmfrm_raw_params;
        seed = 20260620,
    )
    @test length(mgmfrm_hmc_samples) == length(mgmfrm_hmc_stats) == 2
    mgmfrm_guarded_target =
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
            mgmfrm_preview;
            prior = source_prior,
        )
    @test LogDensityProblems.dimension(mgmfrm_guarded_target) ==
        mgmfrm_raw_blueprint.n_parameters
    @test LogDensityProblems.logdensity(mgmfrm_guarded_target, mgmfrm_raw_params) ≈
        LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params)
    @test occursin("MGMFRMGuardedLocalFitLogDensity",
        sprint(show, mgmfrm_guarded_target))
    mgmfrm_raw_pointwise_fixture =
        BayesianMGMFRM._mgmfrm_confirmatory_candidate_pointwise_fixture(
            mgmfrm_guarded_target,
            mgmfrm_raw_params,
        )
    @test mgmfrm_raw_pointwise_fixture.summary.passed
    @test mgmfrm_raw_pointwise_fixture.raw_parameter_names ==
        mgmfrm_raw_blueprint.parameter_names
    @test mgmfrm_raw_pointwise_fixture.parameter_layout.raw_parameter_names ==
        mgmfrm_raw_pointwise_fixture.raw_parameter_names
    @test mgmfrm_raw_pointwise_fixture.raw_parameter_values ≈ mgmfrm_raw_params
    @test mgmfrm_raw_pointwise_fixture.parameter_values ≈ mgmfrm_params
    @test mgmfrm_raw_pointwise_fixture.pointwise_loglikelihood ≈
        mgmfrm_source_pointwise
    mgmfrm_guarded_fit =
        fit(
            mgmfrm_spec;
            experimental = true,
            init = mgmfrm_raw_params,
            seed = 20260630,
            ndraws = 2,
            warmup = 0,
            chains = 1,
            step_size = 0.02,
            max_depth = 2,
            metric = :unit,
        )
    @test mgmfrm_guarded_fit isa MGMFRMFit
    @test mgmfrm_guarded_fit.design.spec.family === :mgmfrm
    @test mgmfrm_guarded_fit.backend === :advancedhmc
    @test mgmfrm_guarded_fit.sampler === :nuts
    @test size(mgmfrm_guarded_fit.draws) ==
        (2, mgmfrm_raw_blueprint.n_parameters)
    @test size(mgmfrm_guarded_fit.direct_draws) == (2, length(mgmfrm_params))
    @test size(mgmfrm_guarded_fit.direct_pointwise_loglikelihood) ==
        (2, identified_data.n)
    @test all(isfinite, mgmfrm_guarded_fit.log_posterior)
    @test all(isfinite, mgmfrm_guarded_fit.direct_draws)
    @test pointwise_loglikelihood_matrix(mgmfrm_guarded_fit) ==
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood
    mgmfrm_direct_llmat = pointwise_loglikelihood_matrix(
        mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.direct_draws)
    mgmfrm_raw_llmat = pointwise_loglikelihood_matrix(
        mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws;
        parameter_space = :raw)
    @test mgmfrm_direct_llmat ≈
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood
    @test mgmfrm_raw_llmat ≈
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws)
    @test waic(mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.direct_draws).waic ≈
        waic(mgmfrm_guarded_fit).waic
    @test waic(mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws;
        parameter_space = :raw).waic ≈
        waic(mgmfrm_guarded_fit).waic
    @test length(waic_diagnostics(mgmfrm_guarded_fit.design,
        mgmfrm_guarded_fit.draws;
        parameter_space = :raw)) == identified_data.n
    @test loglikelihood(mgmfrm_guarded_fit) ==
        mgmfrm_guarded_fit.direct_loglikelihood
    @test logprior(mgmfrm_guarded_fit) ≈
        mgmfrm_guarded_fit.log_posterior .-
        mgmfrm_guarded_fit.direct_loglikelihood
    @test logposterior(mgmfrm_guarded_fit) ==
        mgmfrm_guarded_fit.log_posterior
    @test logposterior(mgmfrm_guarded_fit; draw_indices = [2, 1]) ==
        mgmfrm_guarded_fit.log_posterior[[2, 1]]
    mgmfrm_probabilities =
        predictive_probabilities(mgmfrm_guarded_fit; draw_indices = [1, 2])
    @test size(mgmfrm_probabilities) ==
        (2, identified_data.n, length(identified_data.category_levels))
    @test all(draw -> all(row -> sum(mgmfrm_probabilities[draw, row, :]) ≈ 1.0,
        1:identified_data.n), 1:2)
    @test all(row -> log(mgmfrm_probabilities[1, row, identified_data.category[row]]) ≈
        mgmfrm_guarded_fit.direct_pointwise_loglikelihood[1, row],
        1:identified_data.n)
    mgmfrm_expected = expected_scores(mgmfrm_guarded_fit; draw_indices = [1, 2])
    mgmfrm_variances = predictive_variances(mgmfrm_guarded_fit; draw_indices = [1, 2])
    mgmfrm_residuals = predictive_residuals(mgmfrm_guarded_fit; draw_indices = [1, 2])
    @test size(mgmfrm_expected) == (2, identified_data.n)
    @test size(mgmfrm_variances) == (2, identified_data.n)
    @test size(mgmfrm_residuals) == (2, identified_data.n)
    @test all(>=(0.0), mgmfrm_variances)
    for draw in 1:2, row in 1:identified_data.n
        manual_mean = sum(identified_data.category_levels[k] *
            mgmfrm_probabilities[draw, row, k]
            for k in eachindex(identified_data.category_levels))
        @test mgmfrm_expected[draw, row] ≈ manual_mean
        @test mgmfrm_residuals[draw, row] ≈
            identified_data.score[row] - mgmfrm_expected[draw, row]
    end
    mgmfrm_replicated = posterior_predict(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        rng = MersenneTwister(20260632))
    @test size(mgmfrm_replicated) == (2, identified_data.n)
    @test all(score -> score in identified_data.category_levels, mgmfrm_replicated)
    mgmfrm_ppc = posterior_predictive_check(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        rng = MersenneTwister(20260633))
    @test size(mgmfrm_ppc.replicated_scores) == (2, identified_data.n)
    @test mgmfrm_ppc.category_levels == identified_data.category_levels
    @test !isempty(predictive_check_summary(mgmfrm_ppc; include_grouped = true))
    mgmfrm_calibration = calibration_table(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        bins = 2)
    @test length(mgmfrm_calibration) == 2
    @test all(row -> row.target === :expected_score, mgmfrm_calibration)
    @test all(row -> row.n_draws == 2, mgmfrm_calibration)
    mgmfrm_all_calibration = calibration_table(mgmfrm_guarded_fit;
        target = :all,
        draw_indices = [1, 2],
        bins = 2)
    @test any(row -> row.target === :category_probability,
        mgmfrm_all_calibration)
    mgmfrm_report = fit_report(mgmfrm_guarded_fit;
        draw_indices = [1, 2],
        include_loo = false,
        artifact_include_environment = false)
    @test mgmfrm_report.schema == "bayesianmgmfrm.fit_report.v1"
    @test mgmfrm_report.family === :mgmfrm
    @test mgmfrm_report.metadata.guarded_local_fit
    @test mgmfrm_report.report_policy.resolved_draw_indices == [1, 2]
    @test mgmfrm_report.prior_predictive.status === :not_requested
    @test mgmfrm_report.posterior.status === :computed
    @test mgmfrm_report.direct_posterior.status === :computed
    @test mgmfrm_report.calibration.status === :computed
    @test mgmfrm_report.calibration.n_rows == identified_data.n
    @test mgmfrm_report.waic.status === :computed
    @test mgmfrm_report.loo.status === :not_requested
    @test mgmfrm_report.dff.status === :not_requested
    @test mgmfrm_report.artifact.status === :computed
    @test mgmfrm_report.artifact.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_report.artifact.artifact === nothing
    @test length(mgmfrm_report.artifact.content_hash.value) == 64
    mgmfrm_simulated_direct = simulate_responses(mgmfrm_spec, mgmfrm_params;
        preview = true,
        rng = MersenneTwister(20260634),
        output = :scores)
    mgmfrm_simulated_raw = simulate_responses(mgmfrm_spec, mgmfrm_raw_params;
        preview = true,
        parameter_space = :raw,
        rng = MersenneTwister(20260634),
        output = :scores)
    @test mgmfrm_simulated_direct == mgmfrm_simulated_raw
    @test length(mgmfrm_simulated_direct) == identified_data.n
    @test all(score -> score in identified_data.category_levels, mgmfrm_simulated_direct)
    @test_throws ArgumentError simulate_responses(mgmfrm_spec, mgmfrm_params;
        output = :scores)
    mgmfrm_design_recovery_direct = parameter_recovery(
        mgmfrm_preview,
        reshape(mgmfrm_params, 1, :),
        mgmfrm_params)
    @test length(mgmfrm_design_recovery_direct) == length(mgmfrm_params)
    @test all(row -> row.model_family === :mgmfrm, mgmfrm_design_recovery_direct)
    @test all(row -> row.parameter_space === :direct, mgmfrm_design_recovery_direct)
    @test all(row -> row.guarded_local_fit, mgmfrm_design_recovery_direct)
    @test [row.parameter for row in mgmfrm_design_recovery_direct] ==
        mgmfrm_preview.parameter_names
    mgmfrm_design_recovery_raw = parameter_recovery(
        mgmfrm_preview,
        reshape(mgmfrm_raw_params, 1, :),
        mgmfrm_raw_params;
        parameter_space = :raw)
    @test [row.parameter for row in mgmfrm_design_recovery_raw] ==
        mgmfrm_fit_ready_blueprint.parameter_names
    @test all(row -> row.density_space === :raw_unconstrained,
        mgmfrm_design_recovery_raw)
    mgmfrm_direct_truth = [
        sum(mgmfrm_guarded_fit.direct_draws[:, col]) /
            size(mgmfrm_guarded_fit.direct_draws, 1)
        for col in axes(mgmfrm_guarded_fit.direct_draws, 2)
    ]
    mgmfrm_fit_recovery_direct =
        parameter_recovery(mgmfrm_guarded_fit, mgmfrm_direct_truth)
    @test length(mgmfrm_fit_recovery_direct) == length(mgmfrm_params)
    @test all(row -> row.model_family === :mgmfrm, mgmfrm_fit_recovery_direct)
    @test all(row -> row.parameter_space === :direct, mgmfrm_fit_recovery_direct)
    @test all(row -> row.fit_ready && row.public_fit &&
        row.experimental_public && row.guarded_local_fit,
        mgmfrm_fit_recovery_direct)
    @test maximum(abs(row.bias) for row in mgmfrm_fit_recovery_direct) < 1e-12
    mgmfrm_raw_truth = [
        sum(mgmfrm_guarded_fit.draws[:, col]) /
            size(mgmfrm_guarded_fit.draws, 1)
        for col in axes(mgmfrm_guarded_fit.draws, 2)
    ]
    mgmfrm_fit_recovery_raw = parameter_recovery(mgmfrm_guarded_fit,
        mgmfrm_raw_truth;
        parameter_space = :raw)
    @test length(mgmfrm_fit_recovery_raw) == mgmfrm_raw_blueprint.n_parameters
    @test [row.parameter for row in mgmfrm_fit_recovery_raw] ==
        mgmfrm_fit_ready_blueprint.parameter_names
    @test parameter_recovery_summary(mgmfrm_guarded_fit, mgmfrm_direct_truth;
        by = :all)[1].n_parameters == length(mgmfrm_params)
    @test length(parameter_recovery_plot_data(mgmfrm_guarded_fit,
        mgmfrm_direct_truth)) == length(mgmfrm_params)
    mgmfrm_guarded_surface = mgmfrm_guarded_fit.diagnostic_surface
    @test mgmfrm_guarded_surface.schema ==
        "bayesianmgmfrm.mgmfrm_guarded_local_fit_sampler_diagnostics.v1"
    @test mgmfrm_guarded_surface.status === :guarded_local_fit
    @test mgmfrm_guarded_surface.public_fit
    @test mgmfrm_guarded_surface.experimental_public
    @test mgmfrm_guarded_surface.fit_ready
    @test mgmfrm_guarded_surface.target === :_mgmfrm_guarded_local_fit_logdensity
    @test mgmfrm_guarded_surface.summary.total_draws == 2
    @test mgmfrm_guarded_surface.summary.n_direct_parameters == length(mgmfrm_params)
    @test mgmfrm_guarded_surface.summary.n_failed_direct_constraints == 0
    @test all(row -> row.passed, mgmfrm_guarded_surface.direct_constraint_rows)
    @test [row.parameter for row in mgmfrm_guarded_surface.direct_parameter_rows] ==
        mgmfrm_preview.parameter_names
    mgmfrm_guarded_metadata = fit_metadata(mgmfrm_guarded_fit)
    @test mgmfrm_guarded_metadata.public_fit
    @test mgmfrm_guarded_metadata.experimental_public
    @test mgmfrm_guarded_metadata.fit_ready
    @test mgmfrm_guarded_metadata.guarded_local_fit
    @test mgmfrm_guarded_metadata.scope === :minimal_confirmatory_mgmfrm_candidate
    mgmfrm_guarded_diagnostics = diagnostics(mgmfrm_guarded_fit)
    @test mgmfrm_guarded_diagnostics.schema ==
        "bayesianmgmfrm.mgmfrm_guarded_local_fit_diagnostics.v1"
    @test mgmfrm_guarded_diagnostics.public_fit
    @test mgmfrm_guarded_diagnostics.experimental_public
    @test mgmfrm_guarded_diagnostics.fit_ready
    @test mgmfrm_guarded_diagnostics.guarded_local_fit
    @test length(sampler_diagnostics(mgmfrm_guarded_fit)) == 1
    @test length(mcmc_diagnostics(mgmfrm_guarded_fit)) ==
        size(mgmfrm_guarded_fit.draws, 2)
    @test length(parameter_block_diagnostics(mgmfrm_guarded_fit)) >= 1
    mgmfrm_guarded_artifact =
        fit_artifact(mgmfrm_guarded_fit; include_environment = false)
    @test mgmfrm_guarded_artifact.schema ==
        "bayesianmgmfrm.mgmfrm_experimental_fit_artifact.v1"
    @test mgmfrm_guarded_artifact.public_fit
    @test mgmfrm_guarded_artifact.experimental_public
    @test mgmfrm_guarded_artifact.guarded_local_fit
    @test mgmfrm_guarded_artifact.fit_ready
    @test mgmfrm_guarded_artifact.entrypoint == "fit(spec; experimental = true)"
    @test mgmfrm_guarded_artifact.guarded_local_entrypoint === :_fit_guarded_mgmfrm
    @test mgmfrm_guarded_artifact.target === :_mgmfrm_guarded_local_fit_logdensity
    @test size(mgmfrm_guarded_artifact.pointwise_loglikelihood) ==
        (2, identified_data.n)
    @test !isempty(mgmfrm_guarded_artifact.raw_to_direct_transform)
    @test !isempty(mgmfrm_guarded_artifact.fixture_provenance)
    @test isnothing(mgmfrm_guarded_artifact.raw_draws)
    @test isnothing(mgmfrm_guarded_artifact.direct_draws)
    @test mgmfrm_guarded_artifact.content_hash.value ==
        artifact_content_hash(mgmfrm_guarded_artifact)
    @test mgmfrm_guarded_artifact.archive_manifest.content_hash ==
        mgmfrm_guarded_artifact.content_hash
    @test waic(mgmfrm_guarded_fit).n_draws == 2
    @test length(waic_diagnostics(mgmfrm_guarded_fit)) == identified_data.n
    @test_throws ArgumentError compare_models(
        gmfrm_experimental_fit,
        mgmfrm_guarded_fit;
        draw_indices = [1, 2])
    @test_throws ArgumentError BayesianMGMFRM._fit_guarded_mgmfrm(
        gmfrm_spec;
        ndraws = 1,
        warmup = 0,
    )
    mgmfrm_bridge_fixture = optional_source_bridge_fixture_path(
        "MFRM_SOURCE_MGMFRM_BRIDGESTAN_FIXTURE",
        joinpath("test", "fixtures", "source_mgmfrm_bridge_logdensity.json"),
        joinpath("test", "stan", "source_mgmfrm_fixture.stan"))
    if !isempty(mgmfrm_bridge_fixture)
        check_source_bridge_fixture(
            mgmfrm_bridge_fixture,
            mgmfrm_target;
            expected_schema = "bayesianmgmfrm.source_mgmfrm_bridge_logdensity.v1",
            expected_stan_model = "test/stan/source_mgmfrm_fixture.stan",
        )
        check_mgmfrm_bridge_confirmatory_fixture(mgmfrm_bridge_fixture, mgmfrm_target)
    end
    mgmfrm_candidate_chain_study_fixture = optional_fixture_path("MFRM_MGMFRM_CANDIDATE_CHAIN_STUDY_FIXTURE", joinpath("test", "fixtures", "mgmfrm_candidate_chain_study.json"))
    if !isempty(mgmfrm_candidate_chain_study_fixture)
        check_mgmfrm_candidate_chain_study_fixture(
            mgmfrm_candidate_chain_study_fixture,
            mgmfrm_target,
            mgmfrm_raw_params,
        )
    end
    mgmfrm_recovery_smoke_fixture = optional_fixture_path("MFRM_MGMFRM_RECOVERY_SMOKE_FIXTURE", joinpath("test", "fixtures", "mgmfrm_recovery_smoke.json"))
    if !isempty(mgmfrm_recovery_smoke_fixture)
        check_mgmfrm_recovery_smoke_fixture(mgmfrm_recovery_smoke_fixture)
    end
    mgmfrm_baseline_comparison_fixture = optional_fixture_path("MFRM_MGMFRM_BASELINE_COMPARISON_FIXTURE", joinpath("test", "fixtures", "mgmfrm_baseline_comparison.json"))
    if !isempty(mgmfrm_baseline_comparison_fixture)
        check_mgmfrm_baseline_comparison_fixture(
            mgmfrm_baseline_comparison_fixture,
        )
    end
    mgmfrm_sparse_recovery_grid_fixture = optional_fixture_path("MFRM_MGMFRM_SPARSE_RECOVERY_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_sparse_recovery_grid.json"))
    if !isempty(mgmfrm_sparse_recovery_grid_fixture)
        check_mgmfrm_sparse_recovery_grid_fixture(
            mgmfrm_sparse_recovery_grid_fixture,
        )
    end
    mgmfrm_guarded_fit_method_wiring_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_FIT_METHOD_WIRING_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_fit_method_wiring.json"))
    if !isempty(mgmfrm_guarded_fit_method_wiring_fixture)
        check_mgmfrm_guarded_fit_method_wiring_fixture(
            mgmfrm_guarded_fit_method_wiring_fixture,
        )
    end
    mgmfrm_guarded_fit_validation_grid_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_FIT_VALIDATION_GRID_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_fit_validation_grid.json"))
    if !isempty(mgmfrm_guarded_fit_validation_grid_fixture)
        check_mgmfrm_guarded_fit_validation_grid_fixture(
            mgmfrm_guarded_fit_validation_grid_fixture,
        )
    end
    mgmfrm_guarded_fit_api_dry_run_fixture = optional_fixture_path("MFRM_MGMFRM_GUARDED_FIT_API_DRY_RUN_FIXTURE", joinpath("test", "fixtures", "mgmfrm_guarded_fit_api_dry_run.json"))
    if !isempty(mgmfrm_guarded_fit_api_dry_run_fixture)
        check_mgmfrm_guarded_fit_api_dry_run_fixture(
            mgmfrm_guarded_fit_api_dry_run_fixture,
        )
    end
    mgmfrm_guarded_fit_public_exposure_review_fixture = optional_fixture_path(
        "MFRM_MGMFRM_GUARDED_FIT_PUBLIC_EXPOSURE_REVIEW_FIXTURE",
        joinpath("test", "fixtures", "mgmfrm_guarded_fit_public_exposure_review.json"))
    if !isempty(mgmfrm_guarded_fit_public_exposure_review_fixture)
        check_mgmfrm_guarded_fit_public_exposure_review_fixture(
            mgmfrm_guarded_fit_public_exposure_review_fixture,
        )
    end
    @test_throws ArgumentError LogDensityProblems.logdensity(mgmfrm_target, mgmfrm_raw_params[1:end-1])
    @test_throws ArgumentError LogDensityProblems.logdensity(mgmfrm_target, fill(Inf, mgmfrm_raw_blueprint.n_parameters))
    @test length(mgmfrm_source_values) == length(mgmfrm_predictors)
    @test all(row -> row.kernel === :mgmfrm_source_aligned, mgmfrm_source_values)
    @test all(row -> row.fixture_only && !row.fit_ready, mgmfrm_source_values)
    mgmfrm_row2_values = [0.0, 1.36 * (0.65 - 0.3), 1.36 * (0.65 - 0.3) + 1.36 * (0.65 - (-0.3))]
    mgmfrm_row2_value = only(filter(row -> row.row == 2 && row.category == 1, mgmfrm_source_values))
    @test mgmfrm_row2_value.observed
    @test mgmfrm_row2_value.person_values ≈ [0.2, -0.1]
    @test mgmfrm_row2_value.active_dimensions == [1]
    @test mgmfrm_row2_value.active_dimension_values ≈ [0.2]
    @test mgmfrm_row2_value.item_dimension_discrimination_values ≈ [1.5]
    @test mgmfrm_row2_value.ability_score ≈ 0.3
    @test mgmfrm_row2_value.rater_value ≈ -0.15
    @test mgmfrm_row2_value.item_value ≈ -0.2
    @test mgmfrm_row2_value.rater_consistency_value ≈ 0.8
    @test mgmfrm_row2_value.source_scale ≈ 1.7
    @test mgmfrm_row2_value.scale_value ≈ 1.36
    @test mgmfrm_row2_value.location_value ≈ 0.65
    @test mgmfrm_row2_value.step_values ≈ [0.3]
    @test mgmfrm_row2_value.step_sum ≈ 0.3
    @test mgmfrm_row2_value.scaled_step_sum ≈ 0.408
    @test mgmfrm_row2_value.eta ≈ mgmfrm_row2_values[2]
    @test mgmfrm_row2_value.log_probability ≈ mgmfrm_row2_values[2] - test_logsumexp(mgmfrm_row2_values)
    mgmfrm_row3_values = [0.0, 2.125 * (-0.32 - (-0.2)), 2.125 * (-0.32 - (-0.2)) + 2.125 * (-0.32 - 0.2)]
    mgmfrm_row3_value = only(filter(row -> row.row == 3 && row.category == 2, mgmfrm_source_values))
    @test mgmfrm_row3_value.observed
    @test mgmfrm_row3_value.active_dimensions == [2]
    @test mgmfrm_row3_value.active_dimension_values ≈ [-0.1]
    @test mgmfrm_row3_value.item_dimension_discrimination_values ≈ [0.7]
    @test mgmfrm_row3_value.ability_score ≈ -0.07
    @test mgmfrm_row3_value.rater_value ≈ 0.15
    @test mgmfrm_row3_value.item_value ≈ 0.1
    @test mgmfrm_row3_value.scale_value ≈ 2.125
    @test mgmfrm_row3_value.location_value ≈ -0.32
    @test mgmfrm_row3_value.step_values ≈ [-0.2, 0.2]
    @test mgmfrm_row3_value.step_sum ≈ 0.0
    @test mgmfrm_row3_value.eta ≈ mgmfrm_row3_values[3]
    @test mgmfrm_row3_value.log_probability ≈ mgmfrm_row3_values[3] - test_logsumexp(mgmfrm_row3_values)
    @test [row.log_probability for row in filter(row -> row.observed, mgmfrm_source_values)] ≈
        mgmfrm_source_pointwise
    bad_mgmfrm_rater_sum = copy(mgmfrm_params)
    bad_mgmfrm_rater_sum[5] = 0.2
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, bad_mgmfrm_rater_sum)
    bad_mgmfrm_discrimination = copy(mgmfrm_params)
    bad_mgmfrm_discrimination[9] = -0.1
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, bad_mgmfrm_discrimination)
    bad_mgmfrm_consistency = copy(mgmfrm_params)
    bad_mgmfrm_consistency[11] = 1.1
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(mgmfrm_preview, bad_mgmfrm_consistency)
    @test_throws ArgumentError BayesianMGMFRM._mgmfrm_source_fixture_values(gmfrm_preview, mgmfrm_params)
    @test_throws ArgumentError linear_predictor_table(mgmfrm_preview; preview = true)
    @test_throws ArgumentError linear_predictor_values(mgmfrm_spec, zeros(length(mgmfrm_preview.parameter_names)); preview = true)
    @test_throws ArgumentError linear_predictor_values(mgmfrm_preview, zeros(length(mgmfrm_preview.parameter_names)))
    @test_throws ArgumentError predictive_probabilities(mgmfrm_preview, zeros(1, length(mgmfrm_preview.parameter_names)))
    @test_throws ArgumentError design_row_table(mgmfrm_preview; preview = true)
    @test_throws ArgumentError getdesign(mgmfrm_spec)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :mfrm, dimensions = 2)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :gmfrm)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :mgmfrm, dimensions = 2)
    @test_throws ArgumentError mfrm_spec(identified_data; family = :mgmfrm, dimensions = 2, q_matrix = Bool[1; 1])
    @test_throws ArgumentError mfrm_spec(identified_data; q_matrix = q_matrix)

    dff_empty = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        group = ["A", "A", "A", "A", "B", "A"],
        score = [0, 1, 2, 1, 0, 2],
    )
    dff_data = FacetData(dff_empty;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    plain_dff_report = validate_design(dff_data)
    @test_throws ArgumentError mfrm_spec(
        dff_data;
        thresholds = :partial_credit,
        bias = [(:rater, :group)],
        validation_report = plain_dff_report,
    )
    dff_report = validate_design(dff_data; bias = [(:rater, :group)])
    dff_spec = mfrm_spec(dff_data; thresholds = :partial_credit, validation_report = dff_report)
    @test haskey(dff_spec.validation.dff_counts, (:rater, :group))
    @test dff_spec.validation_bias_terms == [(:rater, :group)]
    @test any(row -> row.block === :dff_rater_group && row.status === :validation_only,
        constraint_table(dff_spec))
    @test dff_spec.validation.dff_counts[(:rater, :group)][("R1", "B")] == 0

    disconnected_same_n = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2"],
        rater = ["R1", "R1", "R1", "R2", "R2", "R2"],
        item = ["I1", "I1", "I1", "I2", "I2", "I2"],
        score = [0, 1, 2, 0, 1, 2],
    )
    stale_data = FacetData(disconnected_same_n; person = :examinee, rater = :rater, item = :item, score = :score)
    @test_throws ArgumentError mfrm_spec(stale_data; thresholds = :partial_credit, validation_report = validate_design(identified_data))
end

@testset "minimal Bayesian MFRM fitting" begin
    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
    )
    data = FacetData(table; person = :examinee, rater = :rater, item = :item, score = :score)
    spec = mfrm_spec(data; thresholds = :partial_credit)
    design = getdesign(spec)
    prior = MFRMPrior(; person_sd = 1.2, rater_sd = 0.8, item_sd = 0.9, step_sd = 0.7)
    init = zeros(length(design.parameter_names))

    @test initial_params(design) == init
    @test initial_params(spec) == init
    @test initial_params(design; value = 0.25) == fill(0.25, length(init))
    @test_throws ArgumentError initial_params(design; value = Inf)
    @test loglikelihood(design, init) ≈ sum(pointwise_loglikelihood(design, init))
    @test loglikelihood(spec, init) ≈ loglikelihood(design, init)
    @test logprior(spec, init, prior) ≈ logprior(design, init, prior)
    @test logposterior(design, init, prior) ≈ logposterior(spec, init, prior)
    @test logposterior(design, init, prior) ≈ loglikelihood(design, init) + logprior(design, init, prior)
    @test isfinite(logposterior(design, init, prior))
    @test_throws ArgumentError MFRMPrior(; person_sd = 0.0)
    @test_throws ArgumentError loglikelihood(design, [0.0])
    @test_throws ArgumentError logprior(design, [0.0], prior)
    @test_throws ArgumentError logposterior(design, [0.0], prior)
    @test_throws ArgumentError fit(design; ndraws = 0)
    @test_throws ArgumentError fit(design; warmup = -1)
    @test_throws ArgumentError fit(design; chains = 0)
    @test_throws ArgumentError fit(design; step_size = 0.0)
    @test_throws ArgumentError fit(design; seed = 1.5)
    @test_throws ArgumentError fit(design; backend = :stan)

    target = MFRMLogDensity(design; prior)
    spec_target = MFRMLogDensity(spec; prior)
    @test target.design === design
    @test target.prior === prior
    @test spec_target.design.parameter_names == design.parameter_names
    @test initial_params(target) == init
    @test occursin("MFRMLogDensity", sprint(show, target))
    @test LogDensityProblems.dimension(target) == length(design.parameter_names)
    @test LogDensityProblems.capabilities(typeof(target)) == LogDensityProblems.LogDensityOrder{0}()
    @test LogDensityProblems.logdensity(target, init) ≈ logposterior(design, init, prior)
    @test LogDensityProblems.logdensity(spec_target, init) ≈ logposterior(spec, init, prior)
    @test_throws ArgumentError LogDensityProblems.logdensity(target, [0.0])
    gradient_point = collect(range(-0.2, 0.2; length = length(init)))
    gradient_adapter =
        BayesianMGMFRM._logdensity_gradient_target(target, gradient_point, :ForwardDiff)
    @test gradient_adapter.ad_backend === :ForwardDiff
    @test gradient_adapter.gradient_backend === :ad
    gradient_lp, target_gradient =
        LogDensityProblems.logdensity_and_gradient(gradient_adapter.target, gradient_point)
    @test gradient_lp ≈ LogDensityProblems.logdensity(target, gradient_point)
    @test length(target_gradient) == length(init)
    @test all(isfinite, target_gradient)
    @test target_gradient ≈
        ForwardDiff.gradient(x -> LogDensityProblems.logdensity(target, x), gradient_point)
    reverse_adapter =
        BayesianMGMFRM._logdensity_gradient_target(target, gradient_point, :ReverseDiff)
    @test reverse_adapter.ad_backend === :ReverseDiff
    @test reverse_adapter.gradient_backend === :ad
    reverse_lp, reverse_gradient =
        LogDensityProblems.logdensity_and_gradient(reverse_adapter.target, gradient_point)
    @test reverse_lp ≈ gradient_lp atol = 1e-10 rtol = 1e-10
    @test reverse_gradient ≈ target_gradient atol = 1e-8 rtol = 1e-8
    @test_throws ArgumentError BayesianMGMFRM._logdensity_gradient_target(
        target,
        gradient_point,
        :analytic,
    )
    @test_throws ArgumentError BayesianMGMFRM._logdensity_gradient_target(
        target,
        gradient_point,
        :UnknownAD,
    )

    result = fit(design;
        prior,
        backend = :julia,
        ndraws = 8,
        warmup = 12,
        chains = 3,
        step_size = 0.04,
        init,
        seed = 20260618)
    @test result isa MFRMFit
    @test result.design === design
    @test result.prior === prior
    @test size(result.draws) == (24, length(design.parameter_names))
    @test length(result.log_posterior) == 24
    @test all(isfinite, result.log_posterior)
    @test 0.0 <= result.acceptance_rate <= 1.0
    @test result.backend === :julia
    @test result.sampler === :random_walk_metropolis
    @test result.warmup == 12
    @test result.step_size == 0.04
    @test result.chain_ids == vcat(fill(1, 8), fill(2, 8), fill(3, 8))
    @test result.iterations == vcat(1:8, 1:8, 1:8)
    @test length(result.chain_acceptance_rate) == 3
    @test all(rate -> 0.0 <= rate <= 1.0, result.chain_acceptance_rate)

    metadata = fit_metadata(result)
    @test metadata.n_observations == data.n
    @test metadata.n_persons == length(data.person_levels)
    @test metadata.n_raters == length(data.rater_levels)
    @test metadata.n_items == length(data.item_levels)
    @test metadata.n_categories == length(data.category_levels)
    @test metadata.category_levels == data.category_levels
    @test metadata.optional_facets == Symbol[]
    @test metadata.family === :mfrm
    @test metadata.dimensions == 1
    @test metadata.discrimination === :none
    @test metadata.thresholds === spec.thresholds
    @test metadata.estimation_status === :fit_supported
    @test metadata.n_parameters == length(design.parameter_names)
    @test metadata.n_draws == size(result.draws, 1)
    @test metadata.n_chains == 3
    @test metadata.draws_per_chain == 8
    @test metadata.n_log_posterior == length(result.log_posterior)
    @test metadata.backend === result.backend
    @test metadata.sampler === result.sampler
    @test metadata.warmup == result.warmup
    @test metadata.step_size == result.step_size
    @test metadata.acceptance_rate == result.acceptance_rate
    @test metadata.chain_acceptance_rate == result.chain_acceptance_rate
    @test metadata.sampler_controls.step_size == result.step_size
    @test metadata.sampler_controls.rng.algorithm === :MersenneTwister
    @test metadata.sampler_controls.rng.seed == 20260618
    @test metadata.sampler_controls.rng.replayable
    @test metadata.n_sampler_stats == size(result.draws, 1)
    @test metadata.prior.person_sd == prior.person_sd
    @test metadata.prior.rater_sd == prior.rater_sd
    @test metadata.prior.item_sd == prior.item_sd
    @test metadata.prior.step_sd == prior.step_sd
    @test metadata.data_signature == spec.validation.data_signature

    sampler_rows = sampler_diagnostics(result)
    @test length(sampler_rows) == 3
    @test [row.chain for row in sampler_rows] == [1, 2, 3]
    @test all(row -> row.backend === :julia, sampler_rows)
    @test all(row -> row.sampler === :random_walk_metropolis, sampler_rows)
    @test all(row -> row.n_draws == 8, sampler_rows)
    @test all(row -> row.warmup == 12, sampler_rows)
    @test all(row -> row.step_size == result.step_size, sampler_rows)
    @test all(row -> row.first_iteration == 1, sampler_rows)
    @test all(row -> row.last_iteration == 8, sampler_rows)
    @test [row.acceptance_rate for row in sampler_rows] == result.chain_acceptance_rate
    @test all(row -> row.n_finite_log_posterior == 8, sampler_rows)
    @test all(row -> row.n_nonfinite_log_posterior == 0, sampler_rows)
    @test all(row -> row.n_divergences == 0, sampler_rows)
    @test all(row -> ismissing(row.n_max_treedepth), sampler_rows)
    @test all(row -> row.mean_step_size == result.step_size, sampler_rows)
    @test all(row -> row.minimum_log_posterior <= row.mean_log_posterior <=
        row.maximum_log_posterior, sampler_rows)
    @test all(row -> row.flag in (:ok, :zero_acceptance, :all_accepted), sampler_rows)

    diagnostics = mcmc_diagnostics(result)
    @test length(diagnostics) == length(design.parameter_names)
    @test [row.parameter for row in diagnostics] == design.parameter_names
    @test all(row -> row.n_chains == 3, diagnostics)
    @test all(row -> row.draws_per_chain == 8, diagnostics)
    @test all(row -> row.diagnostic_chains == 6, diagnostics)
    @test all(row -> row.diagnostic_draws_per_chain == 4, diagnostics)
    @test all(row -> row.total_draws == 24, diagnostics)
    @test all(row -> row.split_chains, diagnostics)
    @test all(row -> row.flag in (:ok, :mcmc_warning, :degenerate_draws), diagnostics)
    @test all(row -> row.flag === :ok ?
        isfinite(row.rhat) && row.rhat <= 1.01 && isfinite(row.ess) && row.ess >= 400.0 :
        true, diagnostics)
    @test all(row -> (isfinite(row.rhat) && row.rhat > 1.01 ||
            isfinite(row.ess) && row.ess < 400.0) ?
        row.flag === :mcmc_warning :
        true, diagnostics)
    @test_throws ArgumentError mcmc_diagnostics(result; rhat_threshold = 1.0)
    @test_throws ArgumentError mcmc_diagnostics(result; ess_threshold = 0)
    unsplit_diagnostics = mcmc_diagnostics(result; split_chains = false)
    @test all(row -> row.diagnostic_chains == 3, unsplit_diagnostics)
    @test all(row -> row.diagnostic_draws_per_chain == 8, unsplit_diagnostics)
    @test all(row -> !row.split_chains, unsplit_diagnostics)

    block_rows = parameter_block_diagnostics(result)
    @test [row.block for row in block_rows] == sort(collect(keys(design.blocks)); by = string)
    @test sum(row.n_parameters for row in block_rows) == length(design.parameter_names)
    @test all(row -> row.n_chains == 3, block_rows)
    @test all(row -> row.draws_per_chain == 8, block_rows)
    @test all(row -> row.total_draws == 24, block_rows)
    @test all(row -> row.split_chains, block_rows)
    @test all(row -> row.rhat_threshold == 1.01, block_rows)
    @test all(row -> row.ess_threshold == 400.0, block_rows)
    @test all(row -> row.flag in (:ok, :mcmc_warning, :insufficient_chains, :degenerate_draws, :empty_block), block_rows)
    person_block_row = only(filter(row -> row.block === :person, block_rows))
    @test person_block_row.n_parameters == length(data.person_levels)
    @test person_block_row.parameter_names == design.parameter_names[design.blocks[:person]]
    threshold_block_row = only(filter(row -> row.block === :thresholds, block_rows))
    @test threshold_block_row.n_parameters == length(design.blocks[:thresholds])
    strict_block_rows = parameter_block_diagnostics(result; rhat_threshold = 1.1, ess_threshold = 2)
    @test all(row -> row.rhat_threshold == 1.1, strict_block_rows)
    @test all(row -> row.ess_threshold == 2.0, strict_block_rows)
    @test_throws ArgumentError parameter_block_diagnostics(result; rhat_threshold = 1.0)
    @test_throws ArgumentError parameter_block_diagnostics(result; ess_threshold = 0)

    diagnostic_surface = BayesianMGMFRM.diagnostics(result)
    @test diagnostic_surface.schema == "bayesianmgmfrm.diagnostics.v1"
    @test diagnostic_surface.backend === result.backend
    @test diagnostic_surface.sampler === result.sampler
    @test diagnostic_surface.summary.n_chains == 3
    @test diagnostic_surface.summary.draws_per_chain == 8
    @test diagnostic_surface.summary.n_parameters == length(design.parameter_names)
    @test diagnostic_surface.summary.flag in (:ok, :sampler_warning, :mcmc_warning, :insufficient_chains)
    @test diagnostic_surface.summary.n_divergences == 0
    @test ismissing(diagnostic_surface.summary.n_max_treedepth)
    @test ismissing(diagnostic_surface.summary.e_bfmi)
    @test diagnostic_surface.summary.n_block_warnings ==
        count(row -> row.flag in (:insufficient_chains, :degenerate_draws, :mcmc_warning), block_rows)
    @test diagnostic_surface.summary.n_empty_blocks == count(row -> row.flag === :empty_block, block_rows)
    @test isequal(diagnostic_surface.sampler_rows, sampler_rows)
    @test diagnostic_surface.parameter_rows == diagnostics
    @test diagnostic_surface.block_rows == block_rows
    @test_throws ArgumentError BayesianMGMFRM.diagnostics(result; rhat_threshold = 1.0)
    @test_throws ArgumentError BayesianMGMFRM.diagnostics(result; ess_threshold = 0)

    spec_result = fit(spec;
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 0,
        step_size = 0.04,
        init,
        rng = MersenneTwister(20260619))
    @test spec_result isa MFRMFit
    @test spec_result.design.parameter_names == design.parameter_names
    @test size(spec_result.draws) == (2, length(design.parameter_names))
    @test spec_result.sampler_controls.rng.seed === missing
    @test !spec_result.sampler_controls.rng.replayable
    single_chain_diagnostics = mcmc_diagnostics(spec_result)
    @test all(row -> row.flag === :insufficient_chains, single_chain_diagnostics)
    @test all(row -> isnan(row.rhat) && isnan(row.ess), single_chain_diagnostics)
    single_chain_block_rows = parameter_block_diagnostics(spec_result)
    @test all(row -> row.flag === :insufficient_chains, single_chain_block_rows)
    single_chain_surface = BayesianMGMFRM.diagnostics(spec_result)
    @test single_chain_surface.summary.n_insufficient_chains == length(design.parameter_names)
    @test single_chain_surface.summary.n_block_warnings == length(single_chain_block_rows)
    @test single_chain_surface.summary.flag in (:insufficient_chains, :sampler_warning)
    unseeded_artifact = fit_artifact(spec_result; include_environment = false)
    @test !unseeded_artifact.reproducibility.replayable_rng
    @test unseeded_artifact.reproducibility.rng.seed === missing

    rsm_spec = mfrm_spec(data; thresholds = :rating_scale)
    rsm_design = getdesign(rsm_spec)
    rsm_result = fit(rsm_design;
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 0,
        step_size = 0.04,
        init = initial_params(rsm_design),
        rng = MersenneTwister(20260621))
    @test rsm_result.design.spec.thresholds === :rating_scale
    @test size(rsm_result.draws) == (2, length(rsm_design.parameter_names))

    hmc_result = fit(design;
        prior,
        backend = :advancedhmc,
        ndraws = 3,
        warmup = 3,
        chains = 2,
        step_size = 0.03,
        max_depth = 3,
        target_accept = 0.8,
        init,
        rng = MersenneTwister(20260620))
    @test hmc_result isa MFRMFit
    @test hmc_result.design === design
    @test hmc_result.prior === prior
    @test hmc_result.backend === :advancedhmc
    @test hmc_result.sampler === :nuts
    @test size(hmc_result.draws) == (6, length(design.parameter_names))
    @test length(hmc_result.log_posterior) == 6
    @test all(isfinite, hmc_result.log_posterior)
    @test hmc_result.chain_ids == vcat(fill(1, 3), fill(2, 3))
    @test hmc_result.iterations == vcat(1:3, 1:3)
    @test hmc_result.sampler_controls.target_accept == 0.8
    @test hmc_result.sampler_controls.max_depth == 3
    @test hmc_result.sampler_controls.metric === :diagonal
    @test hmc_result.sampler_controls.ad_backend === :ForwardDiff
    @test hmc_result.sampler_controls.gradient_backend === :ad
    @test length(hmc_result.sampler_stats) == 6
    @test all(row -> row.chain in (1, 2), hmc_result.sampler_stats)
    @test all(row -> 1 <= row.iteration <= 3, hmc_result.sampler_stats)
    @test all(row -> isfinite(row.log_density), hmc_result.sampler_stats)
    @test all(row -> row.n_steps >= 1, hmc_result.sampler_stats)
    @test all(row -> 0 <= row.tree_depth <= 3, hmc_result.sampler_stats)
    @test all(row -> isfinite(row.step_size) && row.step_size > 0, hmc_result.sampler_stats)
    hmc_metadata = fit_metadata(hmc_result)
    @test hmc_metadata.backend === :advancedhmc
    @test hmc_metadata.sampler === :nuts
    @test hmc_metadata.n_sampler_stats == 6
    @test hmc_metadata.sampler_controls.max_depth == 3
    hmc_sampler_rows = sampler_diagnostics(hmc_result)
    @test length(hmc_sampler_rows) == 2
    @test all(row -> row.backend === :advancedhmc, hmc_sampler_rows)
    @test all(row -> row.sampler === :nuts, hmc_sampler_rows)
    @test all(row -> row.n_draws == 3, hmc_sampler_rows)
    @test all(row -> row.n_divergences >= 0, hmc_sampler_rows)
    @test all(row -> row.n_max_treedepth >= 0, hmc_sampler_rows)
    @test all(row -> row.mean_n_steps >= 1, hmc_sampler_rows)
    @test all(row -> 0 <= row.mean_tree_depth <= 3, hmc_sampler_rows)
    @test all(row -> 0 <= row.max_tree_depth <= 3, hmc_sampler_rows)
    @test all(row -> isfinite(row.mean_step_size) && row.mean_step_size > 0, hmc_sampler_rows)
    hmc_surface = BayesianMGMFRM.diagnostics(hmc_result)
    @test hmc_surface.backend === :advancedhmc
    @test hmc_surface.sampler === :nuts
    @test hmc_surface.summary.n_chains == 2
    @test hmc_surface.summary.draws_per_chain == 3
    @test hmc_surface.summary.n_divergences >= 0
    @test hmc_surface.summary.n_max_treedepth >= 0
    @test hmc_surface.summary.flag in (:ok, :sampler_warning, :mcmc_warning, :insufficient_chains)
    @test isequal(hmc_surface.sampler_rows, hmc_sampler_rows)
    hmc_block_rows = parameter_block_diagnostics(hmc_result)
    @test hmc_surface.block_rows == hmc_block_rows
    @test sum(row.n_parameters for row in hmc_block_rows) == length(design.parameter_names)
    @test all(row -> row.n_chains == 2, hmc_block_rows)

    turing_result = fit(design;
        prior,
        backend = :turing,
        ndraws = 2,
        warmup = 1,
        chains = 2,
        step_size = 0.03,
        max_depth = 4,
        target_accept = 0.8,
        init,
        seed = 20260623)
    @test turing_result isa MFRMFit
    @test turing_result.design === design
    @test turing_result.prior === prior
    @test turing_result.backend === :turing
    @test turing_result.sampler === :nuts
    @test size(turing_result.draws) == (4, length(design.parameter_names))
    @test length(turing_result.log_posterior) == 4
    @test all(isfinite, turing_result.log_posterior)
    @test turing_result.chain_ids == vcat(fill(1, 2), fill(2, 2))
    @test turing_result.iterations == vcat(1:2, 1:2)
    @test turing_result.sampler_controls.target_accept == 0.8
    @test turing_result.sampler_controls.max_depth == 4
    @test turing_result.sampler_controls.metric === :diagonal
    @test turing_result.sampler_controls.ad_backend === :ForwardDiff
    @test turing_result.sampler_controls.gradient_backend === :ad
    @test turing_result.sampler_controls.turing_model ===
        :mfrm_logdensity_flat_parameter_model
    @test turing_result.sampler_controls.chain_type === :raw_transitions
    @test turing_result.sampler_controls.discard_initial == 1
    @test turing_result.sampler_controls.rng.seed == 20260623
    @test length(turing_result.sampler_stats) == 4
    @test all(row -> row.chain in (1, 2), turing_result.sampler_stats)
    @test all(row -> 1 <= row.iteration <= 2, turing_result.sampler_stats)
    @test all(row -> isfinite(row.log_density), turing_result.sampler_stats)
    @test all(row -> row.n_steps >= 1, turing_result.sampler_stats)
    @test all(row -> 0 <= row.tree_depth <= 4, turing_result.sampler_stats)
    @test all(row -> isfinite(row.step_size) && row.step_size > 0, turing_result.sampler_stats)
    @test all(row -> isapprox(turing_result.log_posterior[row],
            logposterior(design, vec(turing_result.draws[row, :]), prior);
            atol = 1e-8,
            rtol = 1e-8),
        axes(turing_result.draws, 1))
    turing_metadata = fit_metadata(turing_result)
    @test turing_metadata.backend === :turing
    @test turing_metadata.sampler === :nuts
    @test turing_metadata.n_sampler_stats == 4
    @test turing_metadata.sampler_controls.discard_initial == 1
    turing_sampler_rows = sampler_diagnostics(turing_result)
    @test length(turing_sampler_rows) == 2
    @test all(row -> row.backend === :turing, turing_sampler_rows)
    @test all(row -> row.sampler === :nuts, turing_sampler_rows)
    @test all(row -> row.n_draws == 2, turing_sampler_rows)
    @test all(row -> row.n_divergences >= 0, turing_sampler_rows)
    @test all(row -> row.n_max_treedepth >= 0, turing_sampler_rows)
    @test all(row -> row.mean_n_steps >= 1, turing_sampler_rows)
    @test all(row -> 0 <= row.mean_tree_depth <= 4, turing_sampler_rows)
    @test all(row -> 0 <= row.max_tree_depth <= 4, turing_sampler_rows)
    @test all(row -> isfinite(row.mean_step_size) && row.mean_step_size > 0,
        turing_sampler_rows)
    turing_surface = BayesianMGMFRM.diagnostics(turing_result)
    @test turing_surface.backend === :turing
    @test turing_surface.sampler === :nuts
    @test turing_surface.summary.n_chains == 2
    @test turing_surface.summary.draws_per_chain == 2
    @test turing_surface.summary.n_divergences >= 0
    @test turing_surface.summary.n_max_treedepth >= 0
    @test turing_surface.summary.flag in (:ok, :sampler_warning, :mcmc_warning, :insufficient_chains)
    @test isequal(turing_surface.sampler_rows, turing_sampler_rows)
    turing_block_rows = parameter_block_diagnostics(turing_result)
    @test turing_surface.block_rows == turing_block_rows
    @test sum(row.n_parameters for row in turing_block_rows) == length(design.parameter_names)
    @test all(row -> row.n_chains == 2, turing_block_rows)

    reverse_hmc_result = fit(design;
        prior,
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        step_size = 0.03,
        max_depth = 2,
        metric = :unit,
        ad_backend = :ReverseDiff,
        init,
        rng = MersenneTwister(20260621))
    @test reverse_hmc_result.sampler_controls.ad_backend === :ReverseDiff
    @test reverse_hmc_result.sampler_controls.gradient_backend === :ad
    @test size(reverse_hmc_result.draws) == (1, length(design.parameter_names))
    @test all(isfinite, reverse_hmc_result.log_posterior)
    @test_throws ArgumentError fit(design; backend = :advancedhmc, target_accept = 1.0)
    @test_throws ArgumentError fit(design; backend = :advancedhmc, max_depth = 0)
    @test_throws ArgumentError fit(design; backend = :advancedhmc, max_energy_error = 0.0)
    @test_throws ArgumentError fit(design; backend = :advancedhmc, metric = :unknown)
    @test_throws ArgumentError fit(design; backend = :advancedhmc, ad_backend = :analytic)
    @test_throws ArgumentError fit(design; backend = :advancedhmc, ad_backend = :UnknownAD)
    @test_throws ArgumentError fit(design; backend = :turing, target_accept = 1.0)
    @test_throws ArgumentError fit(design; backend = :turing, max_depth = 0)
    @test_throws ArgumentError fit(design; backend = :turing, max_energy_error = 0.0)
    @test_throws ArgumentError fit(design; backend = :turing, metric = :unknown)
    @test_throws ArgumentError fit(design; backend = :turing, ad_backend = :ReverseDiff)
    @test_throws ArgumentError fit(design; backend = :turing, ad_backend = :analytic)
    @test_throws ArgumentError fit(design; backend = :turing, ad_backend = :UnknownAD)

    fit_manifest = model_manifest(result)
    @test fit_manifest.object === :fit
    @test fit_manifest.fit.n_draws == size(result.draws, 1)
    @test fit_manifest.fit.prior.person_sd == prior.person_sd
    @test fit_manifest.diagnostics.flag == diagnostic_surface.summary.flag
    @test fit_manifest.design.parameter_names == design.parameter_names

    compact_artifact = fit_artifact(result; include_environment = false)
    @test compact_artifact.schema == "bayesianmgmfrm.fit_artifact.v1"
    @test compact_artifact.object === :fit_artifact
    @test compact_artifact.manifest.object === :fit
    @test compact_artifact.manifest.fit.n_draws == size(result.draws, 1)
    @test isequal(compact_artifact.manifest.diagnostics, compact_artifact.diagnostics.summary)
    @test compact_artifact.reproducibility.data_signature == spec.validation.data_signature
    @test compact_artifact.reproducibility.rng.algorithm === :MersenneTwister
    @test compact_artifact.reproducibility.rng.seed == 20260618
    @test compact_artifact.reproducibility.replayable_rng
    @test compact_artifact.reproducibility.artifact_policy.draws === :omitted
    @test compact_artifact.reproducibility.artifact_policy.environment === :omitted
    @test compact_artifact.reproducibility.artifact_policy.package_status === :omitted
    @test compact_artifact.reproducibility.diagnostic_policy.rhat_threshold == 1.01
    @test compact_artifact.reproducibility.diagnostic_policy.ess_threshold == 400.0
    @test isnothing(compact_artifact.environment)
    @test isnothing(compact_artifact.draws)
    @test isnothing(compact_artifact.log_posterior)
    @test isnothing(compact_artifact.sampler_stats)
    @test length(compact_artifact.posterior_summary) == length(design.parameter_names)
    @test compact_artifact.content_hash.algorithm === :sha256
    @test compact_artifact.content_hash.scope === :artifact_without_hash_metadata
    @test length(compact_artifact.content_hash.value) == 64
    @test compact_artifact.content_hash.value == artifact_content_hash(compact_artifact)
    @test compact_artifact.archive_manifest.schema ==
        "bayesianmgmfrm.fit_archive_manifest.v1"
    @test compact_artifact.archive_manifest.object === :fit_archive_manifest
    @test compact_artifact.archive_manifest.content_hash == compact_artifact.content_hash
    @test compact_artifact.archive_manifest.artifact.schema == compact_artifact.schema
    @test compact_artifact.archive_manifest.manifest.n_draws == size(result.draws, 1)
    explicit_archive_manifest = fit_archive_manifest(
        compact_artifact;
        label = :unit_test_artifact,
        source_path = "memory://compact_artifact",
    )
    @test explicit_archive_manifest.label === :unit_test_artifact
    @test explicit_archive_manifest.source_path == "memory://compact_artifact"
    @test explicit_archive_manifest.content_hash.value == artifact_content_hash(compact_artifact)
    @test fit_archive_manifest(result; artifact = compact_artifact).content_hash.value ==
        compact_artifact.content_hash.value
    partial_reproduction_manifest = fit_reproduction_manifest(result;
        artifact = compact_artifact,
        source_path = "memory://compact_artifact")
    @test partial_reproduction_manifest.schema ==
        "bayesianmgmfrm.fit_reproduction_manifest.v1"
    @test partial_reproduction_manifest.object === :fit_reproduction_manifest
    @test partial_reproduction_manifest.status === :incomplete
    @test partial_reproduction_manifest.full_rerun.status === :ready
    @test partial_reproduction_manifest.full_rerun.replayable_rng
    @test partial_reproduction_manifest.fast_cached_draws.status === :not_provided
    @test partial_reproduction_manifest.missing_required_paths ==
        (:fast_cached_draws,)
    @test !partial_reproduction_manifest.publication_or_registration_action
    @test !partial_reproduction_manifest.manuscript_claims_allowed
    @test partial_reproduction_manifest.next_gate ===
        :manual_publication_or_registration_by_user_only
    @test partial_reproduction_manifest.content_hash.value ==
        artifact_content_hash(partial_reproduction_manifest)

    full_artifact = fit_artifact(result;
        include_environment = false,
        include_draws = true,
        include_sampler_stats = true,
        rhat_threshold = 1.1,
        ess_threshold = 2)
    @test full_artifact.manifest.diagnostics.rhat_threshold == 1.1
    @test full_artifact.manifest.diagnostics.ess_threshold == 2.0
    @test full_artifact.diagnostics.summary.rhat_threshold == 1.1
    @test full_artifact.diagnostics.summary.ess_threshold == 2.0
    @test full_artifact.reproducibility.artifact_policy.draws === :included
    @test full_artifact.reproducibility.artifact_policy.log_posterior === :included
    @test full_artifact.reproducibility.artifact_policy.sampler_stats === :included
    @test full_artifact.draws == result.draws
    @test full_artifact.log_posterior == result.log_posterior
    @test isequal(full_artifact.sampler_stats, result.sampler_stats)
    @test full_artifact.content_hash.value == artifact_content_hash(full_artifact)
    @test full_artifact.content_hash.value != compact_artifact.content_hash.value
    @test_throws ArgumentError fit_artifact(result; rhat_threshold = 1.0)
    @test_throws ArgumentError fit_artifact(result; ess_threshold = 0)

    report = fit_report(result;
        include_prior_predictive = true,
        prior_predictive_ndraws = 2,
        prior_predictive_rng = MersenneTwister(20260624),
        ndraws = 3,
        rng = MersenneTwister(20260625),
        calibration_bins = 2,
        artifact_include_environment = false)
    @test report.schema == "bayesianmgmfrm.fit_report.v1"
    @test report.object === :fit_report
    @test report.family === :mfrm
    @test report.metadata.n_draws == size(result.draws, 1)
    @test report.manifest.object === :fit
    @test report.diagnostics.summary.n_chains == 3
    @test report.prior_predictive.status === :computed
    @test report.prior_predictive.ndraws == 2
    @test report.prior_predictive.n_rows > 0
    @test report.posterior.status === :computed
    @test report.posterior.n_rows == length(design.parameter_names)
    @test report.direct_posterior.status === :not_requested
    @test report.posterior_predictive.status === :computed
    @test report.posterior_predictive.n_rows > 0
    @test report.calibration.status === :computed
    @test report.calibration.n_rows == 2
    @test report.waic.status === :computed
    @test report.waic.stat.criterion === :waic
    @test report.loo.status === :computed
    @test report.loo.stat.criterion === :loo
    @test report.dff.status === :not_requested
    report_with_dff = fit_report(result;
        include_posterior_predictive = false,
        include_calibration = false,
        include_waic = false,
        include_loo = false,
        include_dff = true,
        dff_terms = (:rater, :item),
        dff_expected_score_practical_threshold = 0.0,
        dff_logit_practical_threshold = 0.0,
        dff_practical_probability_threshold = 0.5,
        draw_indices = [1, 2],
        artifact_include_environment = false)
    @test report_with_dff.dff.status === :computed
    @test report_with_dff.dff.n_rows ==
        length(data.rater_levels) * length(data.item_levels)
    @test report_with_dff.report_policy.dff_terms === (:rater, :item)
    @test report_with_dff.report_policy.dff_expected_score_practical_threshold == 0.0
    @test report_with_dff.report_policy.dff_logit_practical_threshold == 0.0
    @test report_with_dff.report_policy.dff_practical_probability_threshold == 0.5
    @test all(row -> row.expected_score_dff_practical_threshold == 0.0,
        report_with_dff.dff.rows)
    @test all(row -> row.logit_dff_practical_threshold == 0.0,
        report_with_dff.dff.rows)
    @test report.artifact.status === :computed
    @test report.artifact.schema == compact_artifact.schema
    @test report.artifact.artifact === nothing
    @test length(report.artifact.content_hash.value) == 64
    report_hash = artifact_content_hash(report)
    @test length(report_hash) == 64
    @test report_hash == artifact_content_hash(merge(report, (;
        content_hash = (;
            algorithm = :sha256,
            value = report_hash,
            scope = :report_without_hash_metadata,
        ),
        archive_manifest = (;
            schema = "bayesianmgmfrm.fit_report_archive_manifest.v1",
            content_hash = (; value = "ignored"),
        ),
    )))
    @test report.report_policy.ndraws == 3
    @test length(report.report_policy.resolved_draw_indices) == 3
    @test report.posterior_predictive.draw_indices ==
        report.report_policy.resolved_draw_indices
    @test report.report_policy.include_artifact
    report_sections = fit_report_sections(report)
    report_section_names = [row.section for row in report_sections]
    @test :diagnostics in report_section_names
    @test :posterior in report_section_names
    @test :waic in report_section_names
    posterior_section = only(filter(row -> row.section === :posterior, report_sections))
    @test posterior_section.status === :computed
    @test posterior_section.row_fields == [:rows]
    @test posterior_section.n_rows == report.posterior.n_rows
    waic_section = only(filter(row -> row.section === :waic, report_sections))
    @test waic_section.status === :computed
    @test waic_section.row_fields == [:diagnostic_rows]
    @test waic_section.n_rows == report.waic.n_diagnostic_rows
    diagnostics_section = only(filter(row -> row.section === :diagnostics, report_sections))
    @test diagnostics_section.status === missing
    @test :parameter_rows in diagnostics_section.row_fields
    @test fit_report_section(report, :posterior) === report.posterior
    @test fit_report_section(report, "calibration") === report.calibration
    @test fit_report_rows(report, :posterior) === report.posterior.rows
    @test fit_report_rows(report, :waic) === report.waic.diagnostic_rows
    @test fit_report_rows(report, :diagnostics; row_field = :parameter_rows) ===
        report.diagnostics.parameter_rows
    @test_throws ArgumentError fit_report_section(report, :missing_section)
    @test_throws ArgumentError fit_report_rows(report, :artifact)
    @test_throws ArgumentError fit_report_rows(report, :posterior;
        row_field = :diagnostic_rows)
    report_dir = mktempdir()
    table_dir = joinpath(report_dir, "minimal_fit_report_tables")
    table_manifest = save_fit_report_tables(table_dir, report; label = :minimal)
    expected_table_count = sum(length(row.row_fields) for row in report_sections)
    @test table_manifest.schema == "bayesianmgmfrm.fit_report_table_export.v1"
    @test table_manifest.object === :fit_report_table_export
    @test table_manifest.label === :minimal
    @test table_manifest.report_schema == report.schema
    @test table_manifest.report_object === :fit_report
    @test table_manifest.report_content_hash.value == report_hash
    @test table_manifest.n_tables == expected_table_count
    @test table_manifest.n_rows >= report.posterior.n_rows
    @test length(table_manifest.content_hash.value) == 64
    @test isfile(joinpath(table_dir, "manifest.json"))
    posterior_table_row = only(filter(row ->
            row.section === :posterior && row.row_field === :rows,
        table_manifest.tables))
    @test posterior_table_row.filename == "posterior__rows.json"
    posterior_table = JSON3.read(read(joinpath(table_dir,
        posterior_table_row.filename), String), Dict{String,Any})
    @test posterior_table["schema"] == "bayesianmgmfrm.fit_report_table.v1"
    @test posterior_table["object"] == "fit_report_table"
    @test posterior_table["section"] == "posterior"
    @test posterior_table["row_field"] == "rows"
    @test posterior_table["n_rows"] == report.posterior.n_rows
    @test posterior_table["content_hash"]["value"] ==
        posterior_table_row.content_hash.value
    @test length(posterior_table["rows"]) == report.posterior.n_rows
    manifest_json = JSON3.read(read(joinpath(table_dir, "manifest.json"), String),
        Dict{String,Any})
    @test manifest_json["schema"] == table_manifest.schema
    @test manifest_json["n_tables"] == table_manifest.n_tables
    @test manifest_json["n_rows"] == table_manifest.n_rows
    loaded_tables = load_fit_report_tables(table_dir)
    @test length(loaded_tables) == table_manifest.n_tables
    loaded_posterior_table = only(filter(table ->
            table["section"] == "posterior" && table["row_field"] == "rows",
        loaded_tables))
    @test loaded_posterior_table["n_rows"] == report.posterior.n_rows
    @test length(loaded_posterior_table["rows"]) == report.posterior.n_rows
    loaded_tables_manifest = load_fit_report_tables(table_dir;
        return_manifest = true)
    @test loaded_tables_manifest["schema"] == table_manifest.schema
    @test loaded_tables_manifest["content_hash"]["value"] ==
        table_manifest.content_hash.value
    @test_throws ArgumentError save_fit_report_tables(table_dir, report)
    tampered_table_dir = joinpath(report_dir, "tampered_fit_report_tables")
    tampered_table_manifest = save_fit_report_tables(tampered_table_dir, report)
    tampered_table_row = only(filter(row ->
            row.section === :posterior && row.row_field === :rows,
        tampered_table_manifest.tables))
    tampered_table_path = joinpath(tampered_table_dir,
        tampered_table_row.filename)
    tampered_table = JSON3.read(read(tampered_table_path, String),
        Dict{String,Any})
    tampered_table["rows"][1]["parameter"] = "tampered"
    open(tampered_table_path, "w") do io
        JSON3.write(io, tampered_table)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_tables(tampered_table_dir)
    @test first(load_fit_report_tables(tampered_table_dir;
        verify_hash = false))["schema"] == "bayesianmgmfrm.fit_report_table.v1"
    unsafe_table_dir = joinpath(report_dir, "unsafe_fit_report_tables")
    save_fit_report_tables(unsafe_table_dir, report)
    unsafe_table_manifest_path = joinpath(unsafe_table_dir, "manifest.json")
    unsafe_table_manifest = JSON3.read(read(unsafe_table_manifest_path, String),
        Dict{String,Any})
    unsafe_table_row = only(filter(row ->
            row["section"] == "posterior" && row["row_field"] == "rows",
        unsafe_table_manifest["tables"]))
    unsafe_table_row["filename"] = "../posterior__rows.json"
    open(unsafe_table_manifest_path, "w") do io
        JSON3.write(io, unsafe_table_manifest)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_tables(unsafe_table_dir;
        verify_hash = false)
    tampered_table_manifest_metadata_dir = joinpath(report_dir,
        "tampered_fit_report_table_manifest_metadata")
    save_fit_report_tables(tampered_table_manifest_metadata_dir, report)
    tampered_table_manifest_metadata_path = joinpath(
        tampered_table_manifest_metadata_dir, "manifest.json")
    tampered_table_manifest_metadata = JSON3.read(
        read(tampered_table_manifest_metadata_path, String), Dict{String,Any})
    tampered_table_manifest_metadata["content_hash"]["scope"] = "wrong_scope"
    open(tampered_table_manifest_metadata_path, "w") do io
        JSON3.write(io, tampered_table_manifest_metadata)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_tables(
        tampered_table_manifest_metadata_dir;
        verify_hash = false,
        return_manifest = true)
    tampered_table_row_metadata_dir = joinpath(report_dir,
        "tampered_fit_report_table_row_metadata")
    save_fit_report_tables(tampered_table_row_metadata_dir, report)
    tampered_table_row_manifest_path = joinpath(tampered_table_row_metadata_dir,
        "manifest.json")
    tampered_table_row_manifest = JSON3.read(
        read(tampered_table_row_manifest_path, String), Dict{String,Any})
    tampered_table_row_metadata = only(filter(row ->
            row["section"] == "posterior" && row["row_field"] == "rows",
        tampered_table_row_manifest["tables"]))
    tampered_table_row_metadata["content_hash"]["algorithm"] = "sha1"
    open(tampered_table_row_manifest_path, "w") do io
        JSON3.write(io, tampered_table_row_manifest)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_tables(
        tampered_table_row_metadata_dir;
        verify_hash = false,
        return_manifest = true)
    tampered_table_record_metadata_dir = joinpath(report_dir,
        "tampered_fit_report_table_record_metadata")
    tampered_table_record_manifest = save_fit_report_tables(
        tampered_table_record_metadata_dir, report)
    tampered_table_record_row = only(filter(row ->
            row.section === :posterior && row.row_field === :rows,
        tampered_table_record_manifest.tables))
    tampered_table_record_path = joinpath(tampered_table_record_metadata_dir,
        tampered_table_record_row.filename)
    tampered_table_record_metadata = JSON3.read(
        read(tampered_table_record_path, String), Dict{String,Any})
    tampered_table_record_metadata["content_hash"]["canonicalization"] =
        "wrong_canonicalization"
    open(tampered_table_record_path, "w") do io
        JSON3.write(io, tampered_table_record_metadata)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_tables(
        tampered_table_record_metadata_dir;
        verify_hash = false)
    markdown = fit_report_markdown(report;
        title = "Minimal fit report",
        max_rows = 2)
    @test startswith(markdown, "# Minimal fit report")
    @test occursin("## Report Metadata", markdown)
    @test occursin("## Section Summary", markdown)
    @test occursin("### posterior / rows", markdown)
    @test occursin("person[E1]", markdown)
    @test occursin("additional row(s) omitted", markdown)
    markdown_path = joinpath(report_dir, "minimal_fit_report.md")
    markdown_export = save_fit_report_markdown(markdown_path, report;
        title = "Minimal fit report",
        max_rows = 2,
        label = :minimal)
    @test isfile(markdown_path)
    @test read(markdown_path, String) == markdown
    @test markdown_export.schema ==
        "bayesianmgmfrm.fit_report_markdown_export.v1"
    @test markdown_export.object === :fit_report_markdown_export
    @test markdown_export.label === :minimal
    @test markdown_export.report_schema == report.schema
    @test markdown_export.report_object === :fit_report
    @test markdown_export.report_content_hash.value == report_hash
    @test markdown_export.markdown_content_hash.value ==
        BayesianMGMFRM._fit_report_markdown_hash_record(markdown).value
    @test markdown_export.n_bytes == sizeof(markdown)
    @test_throws ArgumentError save_fit_report_markdown(markdown_path, report)
    @test_throws ArgumentError fit_report_markdown(report; max_rows = -1)
    report_path = joinpath(report_dir, "minimal_fit_report.json")
    report_export = save_fit_report(report_path, report)
    @test isfile(report_path)
    @test report_export.schema == "bayesianmgmfrm.fit_report_export.v1"
    @test report_export.object === :fit_report_export
    @test report_export.report_schema == report.schema
    @test report_export.report_object === :fit_report
    @test report_export.report_content_hash.value == report_hash
    @test report_export.json_content_hash.value ==
        BayesianMGMFRM._fit_report_json_hash_record(report_export.report).value
    loaded_report = load_fit_report(report_path)
    @test loaded_report["schema"] == report.schema
    @test loaded_report["object"] == "fit_report"
    @test loaded_report["posterior"]["n_rows"] == report.posterior.n_rows
    loaded_sections = fit_report_sections(loaded_report)
    loaded_posterior_section = only(filter(row -> row.section === :posterior,
        loaded_sections))
    @test loaded_posterior_section.status === :computed
    @test loaded_posterior_section.row_fields == [:rows]
    @test loaded_posterior_section.n_rows == report.posterior.n_rows
    @test fit_report_section(loaded_report, :posterior)["status"] == "computed"
    loaded_posterior_rows = fit_report_rows(loaded_report, "posterior")
    @test length(loaded_posterior_rows) == report.posterior.n_rows
    @test first(loaded_posterior_rows) isa AbstractDict
    @test length(fit_report_rows(loaded_report, :waic)) == report.waic.n_diagnostic_rows
    @test fit_report_rows(loaded_report, :waic) ==
        fit_report_rows(loaded_report, :waic; row_field = "diagnostic_rows")
    loaded_table_manifest = save_fit_report_tables(table_dir, loaded_report;
        overwrite = true,
        label = "loaded")
    @test loaded_table_manifest.label == "loaded"
    @test loaded_table_manifest.report_object === :fit_report
    @test loaded_table_manifest.n_tables == table_manifest.n_tables
    @test loaded_table_manifest.n_rows == table_manifest.n_rows
    loaded_markdown = fit_report_markdown(loaded_report;
        title = "Loaded fit report",
        max_rows = 1)
    @test startswith(loaded_markdown, "# Loaded fit report")
    @test occursin("### waic / diagnostic_rows", loaded_markdown)
    loaded_markdown_export = save_fit_report_markdown(markdown_path, loaded_report;
        overwrite = true,
        title = "Loaded fit report",
        max_rows = 1,
        label = "loaded")
    @test loaded_markdown_export.label == "loaded"
    @test loaded_markdown_export.report_object === :fit_report
    @test read(markdown_path, String) == loaded_markdown

    dossier_comparison_rows = compare_models(
        :minimal => result,
        :repeat => result;
        criterion = :waic,
        draw_indices = [1, 2, 3])
    dossier_sensitivity_rows = sensitivity_comparison(
        :minimal => result,
        :repeat => result;
        criterion = :waic,
        draw_indices = [1, 2, 3])
    dossier_evidence_rows = [(;
        evidence = :fit_report_review_bundle,
        status = :recorded,
        publication_or_registration_action = false,
    )]
    dossier = fit_report_dossier(
        :minimal => report,
        :loaded => loaded_report;
        comparison_rows = dossier_comparison_rows,
        sensitivity_rows = dossier_sensitivity_rows,
        evidence_rows = dossier_evidence_rows,
        label = :minimal_dossier)
    @test dossier.schema == "bayesianmgmfrm.fit_report_dossier.v1"
    @test dossier.object === :fit_report_dossier
    @test dossier.label === :minimal_dossier
    @test dossier.report_policy.rendering_scope === :review_dossier
    @test !dossier.report_policy.publication_or_registration_action
    @test !dossier.report_policy.manuscript_claims_allowed
    @test dossier.report_policy.next_gate ===
        :manual_publication_or_registration_by_user_only
    @test dossier.n_reports == 2
    @test dossier.models == ("minimal", "loaded")
    @test dossier.n_report_rows == 2
    @test dossier.n_section_rows == 2 * length(report_sections)
    @test dossier.n_comparison_rows == length(dossier_comparison_rows)
    @test dossier.n_sensitivity_rows == length(dossier_sensitivity_rows)
    @test dossier.n_evidence_rows == 1
    @test isnothing(dossier.reports)
    @test length(dossier.report_rows) == 2
    @test all(row -> length(row.report_content_hash.value) == 64,
        dossier.report_rows)
    @test first(dossier.report_rows).diagnostic_flag ==
        report.diagnostics.summary.flag
    @test any(row -> row.model == "minimal" && row.section === :posterior,
        dossier.section_rows)
    @test any(row -> row.model == "loaded" && row.section === :waic,
        dossier.section_rows)
    @test [row.model for row in dossier.comparison_rows] ==
        [row.model for row in dossier_comparison_rows]
    @test first(dossier.evidence_rows).publication_or_registration_action == false
    embedded_dossier = fit_report_dossier(report;
        names = [:minimal],
        include_reports = true)
    @test embedded_dossier.n_reports == 1
    @test length(embedded_dossier.reports) == 1
    @test_throws ArgumentError fit_report_dossier()
    @test_throws ArgumentError fit_report_dossier(report, loaded_report;
        names = [:dup, :dup])
    @test_throws ArgumentError fit_report_dossier(:bad => report;
        comparison_rows = [1])

    dossier_markdown = fit_report_dossier_markdown(dossier;
        title = "Minimal fit report dossier",
        max_rows = 1)
    @test startswith(dossier_markdown, "# Minimal fit report dossier")
    @test occursin("## Dossier Metadata", dossier_markdown)
    @test occursin("## Report Summary", dossier_markdown)
    @test occursin("## Section Summary", dossier_markdown)
    @test occursin("## Comparison Rows", dossier_markdown)
    @test occursin("Publication or registration action: false", dossier_markdown)
    @test_throws ArgumentError fit_report_dossier_markdown(dossier; max_rows = -1)

    dossier_path = joinpath(report_dir, "minimal_fit_report_dossier.json")
    dossier_export = save_fit_report_dossier(dossier_path, dossier;
        label = :minimal_dossier)
    @test isfile(dossier_path)
    @test dossier_export.schema ==
        "bayesianmgmfrm.fit_report_dossier_export.v1"
    @test dossier_export.object === :fit_report_dossier_export
    @test dossier_export.label === :minimal_dossier
    @test dossier_export.dossier_schema == dossier.schema
    @test dossier_export.dossier_object === :fit_report_dossier
    @test length(dossier_export.dossier_content_hash.value) == 64
    @test length(dossier_export.json_content_hash.value) == 64
    loaded_dossier = load_fit_report_dossier(dossier_path)
    @test loaded_dossier["schema"] == dossier.schema
    @test loaded_dossier["object"] == "fit_report_dossier"
    @test length(loaded_dossier["report_rows"]) == 2
    loaded_dossier_markdown = fit_report_dossier_markdown(loaded_dossier;
        title = "Loaded fit report dossier",
        max_rows = 1)
    @test startswith(loaded_dossier_markdown, "# Loaded fit report dossier")
    loaded_dossier_record = load_fit_report_dossier(dossier_path;
        return_record = true)
    @test loaded_dossier_record["schema"] == dossier_export.schema
    @test loaded_dossier_record["dossier_content_hash"]["value"] ==
        dossier_export.dossier_content_hash.value
    dossier_markdown_path = joinpath(report_dir, "minimal_fit_report_dossier.md")
    dossier_markdown_export = save_fit_report_dossier_markdown(
        dossier_markdown_path,
        dossier;
        title = "Minimal fit report dossier",
        max_rows = 1,
        label = :minimal_dossier)
    @test read(dossier_markdown_path, String) == dossier_markdown
    @test dossier_markdown_export.schema ==
        "bayesianmgmfrm.fit_report_dossier_markdown_export.v1"
    @test dossier_markdown_export.object === :fit_report_dossier_markdown_export
    @test dossier_markdown_export.label === :minimal_dossier
    @test dossier_markdown_export.markdown_content_hash.value ==
        BayesianMGMFRM._fit_report_dossier_markdown_hash_record(
            dossier_markdown).value
    @test_throws ArgumentError save_fit_report_dossier(dossier_path, dossier)
    @test_throws ArgumentError save_fit_report_dossier_markdown(
        dossier_markdown_path,
        dossier)

    tampered_dossier_record = deepcopy(loaded_dossier_record)
    tampered_dossier_record["dossier"]["report_rows"][1]["model"] = "tampered"
    tampered_dossier_path = joinpath(report_dir,
        "tampered_fit_report_dossier.json")
    open(tampered_dossier_path, "w") do io
        JSON3.write(io, tampered_dossier_record)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_dossier(tampered_dossier_path)
    @test load_fit_report_dossier(tampered_dossier_path;
        verify_hash = false)["schema"] == dossier.schema

    resaved_report_path = joinpath(report_dir, "minimal_fit_report_resaved.json")
    resaved_export = save_fit_report(resaved_report_path, loaded_report)
    @test resaved_export.report_object === :fit_report
    @test load_fit_report(resaved_report_path)["schema"] == report.schema
    bundle_dir = joinpath(report_dir, "minimal_fit_report_bundle")
    bundle_manifest = save_fit_report_bundle(bundle_dir, report;
        title = "Minimal fit report",
        max_rows = 2,
        label = :bundle)
    @test bundle_manifest.schema ==
        "bayesianmgmfrm.fit_report_bundle_export.v1"
    @test bundle_manifest.object === :fit_report_bundle_export
    @test bundle_manifest.label === :bundle
    @test bundle_manifest.report_content_hash.value == report_hash
    @test bundle_manifest.n_tables == table_manifest.n_tables
    @test bundle_manifest.n_rows == table_manifest.n_rows
    @test isfile(joinpath(bundle_dir, "fit_report.json"))
    @test isfile(joinpath(bundle_dir, "fit_report.md"))
    @test isfile(joinpath(bundle_dir, "tables", "manifest.json"))
    @test isfile(joinpath(bundle_dir, "manifest.json"))
    bundle_record = JSON3.read(read(joinpath(bundle_dir, "fit_report.json"),
        String), Dict{String,Any})
    @test bundle_record["schema"] == report_export.schema
    @test bundle_record["report"]["schema"] == report.schema
    bundle_manifest_json = JSON3.read(read(joinpath(bundle_dir, "manifest.json"),
        String), Dict{String,Any})
    @test bundle_manifest_json["schema"] == bundle_manifest.schema
    @test bundle_manifest_json["n_tables"] == table_manifest.n_tables
    @test bundle_manifest_json["content_hash"]["value"] ==
        bundle_manifest.content_hash.value
    @test any(file -> file["path"] == "fit_report.json",
        bundle_manifest_json["files"])
    @test any(file -> file["path"] == "tables/manifest.json",
        bundle_manifest_json["files"])
    @test any(file -> file["path"] == "fit_report.md",
        bundle_manifest_json["files"])
    loaded_bundle_report = load_fit_report_bundle(bundle_dir)
    @test loaded_bundle_report["schema"] == report.schema
    @test loaded_bundle_report["posterior"]["n_rows"] == report.posterior.n_rows
    loaded_bundle_manifest = load_fit_report_bundle(bundle_dir;
        return_manifest = true)
    @test loaded_bundle_manifest["schema"] == bundle_manifest.schema
    @test loaded_bundle_manifest["content_hash"]["value"] ==
        bundle_manifest.content_hash.value
    @test_throws ArgumentError save_fit_report_bundle(bundle_dir, report)
    loaded_bundle_dir = joinpath(report_dir, "loaded_fit_report_bundle")
    loaded_bundle = save_fit_report_bundle(loaded_bundle_dir, loaded_report;
        title = "Loaded fit report",
        max_rows = 1,
        label = "loaded")
    @test loaded_bundle.label == "loaded"
    @test loaded_bundle.report_object === :fit_report
    @test read(joinpath(loaded_bundle_dir, "fit_report.md"), String) ==
        loaded_markdown
    @test load_fit_report_bundle(loaded_bundle_dir)["schema"] == report.schema
    tampered_bundle_dir = joinpath(report_dir, "tampered_fit_report_bundle")
    save_fit_report_bundle(tampered_bundle_dir, loaded_report;
        title = "Loaded fit report",
        max_rows = 1)
    open(joinpath(tampered_bundle_dir, "fit_report.md"), "a") do io
        write(io, "\nTampered.\n")
    end
    @test_throws ArgumentError load_fit_report_bundle(tampered_bundle_dir)
    @test load_fit_report_bundle(tampered_bundle_dir;
        verify_hash = false)["schema"] == report.schema
    tampered_bundle_table_dir = joinpath(report_dir,
        "tampered_fit_report_bundle_table")
    save_fit_report_bundle(tampered_bundle_table_dir, loaded_report;
        title = "Loaded fit report",
        max_rows = 1)
    tampered_bundle_table_manifest = load_fit_report_tables(
        joinpath(tampered_bundle_table_dir, "tables");
        return_manifest = true)
    tampered_bundle_table_row = only(filter(row ->
            row["section"] == "posterior" && row["row_field"] == "rows",
        tampered_bundle_table_manifest["tables"]))
    tampered_bundle_table_path = joinpath(tampered_bundle_table_dir, "tables",
        tampered_bundle_table_row["filename"])
    tampered_bundle_table = JSON3.read(read(tampered_bundle_table_path, String),
        Dict{String,Any})
    tampered_bundle_table["rows"][1]["parameter"] = "tampered"
    open(tampered_bundle_table_path, "w") do io
        JSON3.write(io, tampered_bundle_table)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_bundle(tampered_bundle_table_dir)
    @test load_fit_report_bundle(tampered_bundle_table_dir;
        verify_hash = false)["schema"] == report.schema
    unsafe_bundle_dir = joinpath(report_dir, "unsafe_fit_report_bundle")
    save_fit_report_bundle(unsafe_bundle_dir, loaded_report;
        title = "Loaded fit report",
        max_rows = 1)
    unsafe_manifest_path = joinpath(unsafe_bundle_dir, "manifest.json")
    unsafe_manifest = JSON3.read(read(unsafe_manifest_path, String),
        Dict{String,Any})
    unsafe_report_file = only(filter(file -> file["role"] == "report_json",
        unsafe_manifest["files"]))
    unsafe_report_file["path"] = "../fit_report.json"
    open(unsafe_manifest_path, "w") do io
        JSON3.write(io, unsafe_manifest)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_bundle(unsafe_bundle_dir;
        verify_hash = false)
    tampered_bundle_manifest_metadata_dir = joinpath(report_dir,
        "tampered_fit_report_bundle_manifest_metadata")
    save_fit_report_bundle(tampered_bundle_manifest_metadata_dir, loaded_report;
        title = "Loaded fit report",
        max_rows = 1)
    tampered_bundle_manifest_metadata_path = joinpath(
        tampered_bundle_manifest_metadata_dir, "manifest.json")
    tampered_bundle_manifest_metadata = JSON3.read(
        read(tampered_bundle_manifest_metadata_path, String), Dict{String,Any})
    tampered_bundle_manifest_metadata["content_hash"]["scope"] = "wrong_scope"
    open(tampered_bundle_manifest_metadata_path, "w") do io
        JSON3.write(io, tampered_bundle_manifest_metadata)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_bundle(
        tampered_bundle_manifest_metadata_dir;
        verify_hash = false,
        return_manifest = true)
    tampered_bundle_file_metadata_dir = joinpath(report_dir,
        "tampered_fit_report_bundle_file_metadata")
    save_fit_report_bundle(tampered_bundle_file_metadata_dir, loaded_report;
        title = "Loaded fit report",
        max_rows = 1)
    tampered_bundle_file_metadata_path = joinpath(
        tampered_bundle_file_metadata_dir, "manifest.json")
    tampered_bundle_file_metadata = JSON3.read(
        read(tampered_bundle_file_metadata_path, String), Dict{String,Any})
    tampered_markdown_file = only(filter(file -> file["role"] == "markdown",
        tampered_bundle_file_metadata["files"]))
    tampered_markdown_file["content_hash"]["canonicalization"] =
        "cache_stable_string"
    open(tampered_bundle_file_metadata_path, "w") do io
        JSON3.write(io, tampered_bundle_file_metadata)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report_bundle(
        tampered_bundle_file_metadata_dir;
        verify_hash = false,
        return_manifest = true)
    loaded_record = load_fit_report(report_path; return_record = true)
    @test loaded_record["schema"] == report_export.schema
    @test loaded_record["object"] == "fit_report_export"
    @test loaded_record["report_content_hash"]["value"] ==
        report_export.report_content_hash.value
    @test loaded_record["json_content_hash"]["value"] == report_export.json_content_hash.value
    tampered_record_metadata = deepcopy(loaded_record)
    tampered_record_metadata["report_content_hash"]["value"] = "not-a-sha256"
    tampered_metadata_path = joinpath(report_dir,
        "tampered_fit_report_metadata.json")
    open(tampered_metadata_path, "w") do io
        JSON3.write(io, tampered_record_metadata)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(tampered_metadata_path;
        verify_hash = false)
    tampered_scope_record = deepcopy(loaded_record)
    tampered_scope_record["json_content_hash"]["scope"] = "wrong_scope"
    tampered_scope_path = joinpath(report_dir,
        "tampered_fit_report_hash_scope.json")
    open(tampered_scope_path, "w") do io
        JSON3.write(io, tampered_scope_record)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(tampered_scope_path;
        verify_hash = false)
    @test_throws ArgumentError fit_report_sections(loaded_record)
    @test_throws ArgumentError fit_report_markdown(loaded_record)
    @test_throws ArgumentError save_fit_report_tables(joinpath(report_dir,
        "invalid_tables"), loaded_record)
    @test_throws ArgumentError save_fit_report_markdown(joinpath(report_dir,
        "invalid.md"), loaded_record)
    @test_throws ArgumentError save_fit_report_bundle(joinpath(report_dir,
        "invalid_bundle"), loaded_record)
    @test_throws ArgumentError save_fit_report(report_path, report)

    convenience_path = joinpath(report_dir, "minimal_fit_report_from_fit.json")
    convenience_export = save_fit_report(convenience_path, result;
        include_loo = false,
        artifact_include_environment = false)
    @test convenience_export.report["loo"]["status"] == "not_requested"
    @test load_fit_report(convenience_path)["loo"]["status"] == "not_requested"
    convenience_table_manifest = save_fit_report_tables(joinpath(report_dir,
            "minimal_fit_report_tables_from_fit"), result;
        include_loo = false,
        artifact_include_environment = false)
    @test convenience_table_manifest.object === :fit_report_table_export
    @test any(row -> row.section === :posterior && row.row_field === :rows,
        convenience_table_manifest.tables)
    convenience_markdown_export = save_fit_report_markdown(joinpath(report_dir,
            "minimal_fit_report_from_fit.md"), result;
        include_loo = false,
        artifact_include_environment = false,
        max_rows = 1)
    @test convenience_markdown_export.object === :fit_report_markdown_export
    @test convenience_markdown_export.max_rows == 1
    convenience_bundle_manifest = save_fit_report_bundle(joinpath(report_dir,
            "minimal_fit_report_bundle_from_fit"), result;
        include_loo = false,
        artifact_include_environment = false,
        max_rows = 1)
    @test convenience_bundle_manifest.object === :fit_report_bundle_export
    @test convenience_bundle_manifest.n_tables > 0

    tampered_record = deepcopy(loaded_record)
    tampered_record["report"]["schema"] = "tampered.fit_report.v1"
    tampered_path = joinpath(report_dir, "tampered_fit_report.json")
    open(tampered_path, "w") do io
        JSON3.write(io, tampered_record)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(tampered_path)
    @test load_fit_report(tampered_path; verify_hash = false)["schema"] ==
        "tampered.fit_report.v1"

    too_short_report = fit_report(spec_result;
        artifact_include_environment = false)
    @test too_short_report.loo.status === :error
    @test too_short_report.loo.exception === :ArgumentError
    @test occursin("LOO requires at least three posterior draws",
        too_short_report.loo.message)
    @test_throws ArgumentError fit_report(result; on_section_error = :invalid)
    @test_throws ArgumentError fit_report(spec_result;
        artifact_include_environment = false,
        on_section_error = :throw)

    cache_key = fit_cache_key(design;
        prior,
        backend = :julia,
        ndraws = 8,
        warmup = 12,
        chains = 3,
        step_size = 0.04,
        init,
        seed = 20260618)
    @test length(cache_key) == 64
    @test cache_key == fit_cache_key(spec;
        prior,
        backend = :julia,
        ndraws = 8,
        warmup = 12,
        chains = 3,
        step_size = 0.04,
        init,
        seed = 20260618)
    @test cache_key != fit_cache_key(design;
        prior,
        backend = :julia,
        ndraws = 8,
        warmup = 12,
        chains = 3,
        step_size = 0.05,
        init,
        seed = 20260618)
    @test cache_key != fit_cache_key(design;
        prior,
        backend = :julia,
        ndraws = 8,
        warmup = 12,
        chains = 3,
        step_size = 0.04,
        init,
        seed = 20260619)
    turing_cache_key = fit_cache_key(design;
        prior,
        backend = :turing,
        ndraws = 2,
        warmup = 1,
        chains = 2,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 4,
        init,
        seed = 20260623)
    @test length(turing_cache_key) == 64
    @test turing_cache_key != cache_key
    @test turing_cache_key == fit_cache_key(spec;
        prior,
        backend = :turing,
        ndraws = 2,
        warmup = 1,
        chains = 2,
        step_size = 0.03,
        target_accept = 0.8,
        max_depth = 4,
        init,
        seed = 20260623)
    @test turing_cache_key != fit_cache_key(design;
        prior,
        backend = :turing,
        ndraws = 2,
        warmup = 1,
        chains = 2,
        step_size = 0.03,
        target_accept = 0.85,
        max_depth = 4,
        init,
        seed = 20260623)
    @test_throws ArgumentError fit_cache_key(design;
        prior,
        backend = :turing,
        ndraws = 2,
        warmup = 1,
        chains = 2,
        step_size = 0.03,
        ad_backend = :ReverseDiff,
        init,
        seed = 20260623)
    @test_throws ArgumentError fit_cache_key(design;
        prior,
        backend = :julia,
        ndraws = 8,
        warmup = 12,
        chains = 3,
        step_size = 0.04,
        init,
        rng = MersenneTwister(20260618))

    cache_dir = mktempdir()
    cache_path = joinpath(cache_dir, "minimal_fit.jls")
    cache_record = save_fit_cache(cache_path, result; cache_key)
    @test isfile(cache_path)
    @test cache_record.schema == "bayesianmgmfrm.fit_cache.v1"
    @test cache_record.object === :fit_cache
    @test cache_record.cache_key == cache_key
    @test cache_record.fit.draws == result.draws
    @test cache_record.artifact.schema == "bayesianmgmfrm.fit_artifact.v1"
    @test cache_record.artifact.reproducibility.artifact_policy.draws === :omitted
    @test cache_record.artifact_content_hash.value == artifact_content_hash(cache_record.artifact)
    @test cache_record.archive_manifest.schema ==
        "bayesianmgmfrm.fit_archive_manifest.v1"
    @test cache_record.archive_manifest.source_path == cache_path
    @test cache_record.archive_manifest.content_hash == cache_record.artifact_content_hash
    reproduction_manifest = fit_reproduction_manifest(result;
        artifact = compact_artifact,
        source_path = "memory://compact_artifact",
        cache_record,
        cache_path,
        report_bundle_manifest = bundle_manifest,
        report_bundle_path = bundle_dir)
    @test reproduction_manifest.status === :ready
    @test reproduction_manifest.n_ready_required_paths == 2
    @test isempty(reproduction_manifest.missing_required_paths)
    @test reproduction_manifest.full_rerun.status === :ready
    @test reproduction_manifest.full_rerun.content_hash ==
        compact_artifact.content_hash
    @test reproduction_manifest.fast_cached_draws.status === :ready
    @test reproduction_manifest.fast_cached_draws.cache_key == cache_key
    @test reproduction_manifest.fast_cached_draws.content_hash ==
        cache_record.artifact_content_hash
    @test reproduction_manifest.fast_cached_draws.source_path == cache_path
    @test reproduction_manifest.review_bundle.status === :ready
    @test reproduction_manifest.review_bundle.content_hash ==
        bundle_manifest.content_hash
    @test reproduction_manifest.content_hash.value ==
        artifact_content_hash(reproduction_manifest)
    loaded_fit = load_fit_cache(cache_path; expected_cache_key = cache_key)
    @test loaded_fit isa MFRMFit
    @test loaded_fit.draws == result.draws
    @test loaded_fit.log_posterior == result.log_posterior
    loaded_record = load_fit_cache(cache_path; expected_cache_key = cache_key, return_record = true)
    @test loaded_record.cache_key == cache_key
    @test isequal(loaded_record.artifact.diagnostics.summary, cache_record.artifact.diagnostics.summary)
    @test loaded_record.artifact_content_hash == cache_record.artifact_content_hash
    tampered_cache_path = joinpath(cache_dir, "tampered_minimal_fit.jls")
    tampered_cache_artifact = merge(cache_record.artifact, (;
        created_at = "tampered",
    ))
    tampered_cache_record = merge(cache_record, (;
        artifact = tampered_cache_artifact,
    ))
    open(tampered_cache_path, "w") do io
        serialize(io, tampered_cache_record)
    end
    @test_throws ArgumentError load_fit_cache(tampered_cache_path;
        expected_cache_key = cache_key)
    @test load_fit_cache(tampered_cache_path;
        expected_cache_key = cache_key,
        verify_hash = false).draws == result.draws
    tampered_cache_hash_metadata_path = joinpath(cache_dir,
        "tampered_minimal_fit_hash_metadata.jls")
    tampered_cache_hash_metadata = merge(cache_record, (;
        artifact_content_hash = merge(cache_record.artifact_content_hash, (;
            scope = :wrong_scope,
        )),
    ))
    open(tampered_cache_hash_metadata_path, "w") do io
        serialize(io, tampered_cache_hash_metadata)
    end
    @test_throws ArgumentError load_fit_cache(tampered_cache_hash_metadata_path;
        expected_cache_key = cache_key,
        verify_hash = false)
    tampered_cache_archive_metadata_path = joinpath(cache_dir,
        "tampered_minimal_fit_archive_metadata.jls")
    tampered_cache_archive_metadata = merge(cache_record, (;
        archive_manifest = merge(cache_record.archive_manifest, (;
            content_hash = merge(cache_record.archive_manifest.content_hash, (;
                algorithm = :sha1,
            )),
        )),
    ))
    open(tampered_cache_archive_metadata_path, "w") do io
        serialize(io, tampered_cache_archive_metadata)
    end
    @test_throws ArgumentError load_fit_cache(tampered_cache_archive_metadata_path;
        expected_cache_key = cache_key,
        verify_hash = false)
    tampered_cache_artifact_metadata_path = joinpath(cache_dir,
        "tampered_minimal_fit_artifact_metadata.jls")
    tampered_cache_artifact_metadata = merge(cache_record, (;
        artifact = merge(cache_record.artifact, (;
            content_hash = merge(cache_record.artifact.content_hash, (;
                canonicalization = :wrong_canonicalization,
            )),
        )),
    ))
    open(tampered_cache_artifact_metadata_path, "w") do io
        serialize(io, tampered_cache_artifact_metadata)
    end
    @test_throws ArgumentError load_fit_cache(tampered_cache_artifact_metadata_path;
        expected_cache_key = cache_key,
        verify_hash = false)
    @test_throws ArgumentError save_fit_cache(cache_path, result; cache_key)
    @test_throws ArgumentError load_fit_cache(cache_path; expected_cache_key = "not-the-key")
    @test_throws ArgumentError load_fit_cache(joinpath(cache_dir, "missing.jls"))
    @test_throws ArgumentError cached_fit(design;
        cache_path = joinpath(cache_dir, "unseeded_cached_fit.jls"),
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 2,
        step_size = 0.04,
        init,
        rng = MersenneTwister(20260703))

    cached_path = joinpath(cache_dir, "cached_fit.jls")
    cached_record = cached_fit(design;
        cache_path = cached_path,
        return_record = true,
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 2,
        step_size = 0.04,
        init,
        seed = 20260701)
    @test cached_record.object === :fit_cache
    @test isfile(cached_path)
    cached_hit = cached_fit(design;
        cache_path = cached_path,
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 2,
        step_size = 0.04,
        init,
        seed = 20260701)
    @test cached_hit.draws == cached_record.fit.draws
    @test cached_hit.log_posterior == cached_record.fit.log_posterior
    @test_throws ArgumentError cached_fit(design;
        cache_path = cached_path,
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 2,
        step_size = 0.04,
        init,
        seed = 20260702)
    refreshed_record = cached_fit(design;
        cache_path = cached_path,
        refresh = true,
        return_record = true,
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 2,
        step_size = 0.04,
        init,
        seed = 20260702)
    @test refreshed_record.cache_key != cached_record.cache_key
    @test load_fit_cache(cached_path; expected_cache_key = refreshed_record.cache_key).draws ==
        refreshed_record.fit.draws
    @test_throws ArgumentError cached_fit(design; prior)

    summary = posterior_summary(result)
    @test length(summary) == length(design.parameter_names)
    @test [row.parameter for row in summary] == design.parameter_names
    @test all(row -> isfinite(row.mean), summary)
    @test all(row -> row.lower <= row.median <= row.upper, summary)
    @test all(row -> length(row.intervals) == 3, summary)
    @test [interval.probability for interval in summary[1].intervals] ≈
        [0.66, 0.9, 0.95]
    @test summary[1].intervals[end].lower ≈ summary[1].lower
    @test summary[1].intervals[end].upper ≈ summary[1].upper
    @test all(interval -> interval.lower_probability ≈ (1 - interval.probability) / 2,
        summary[1].intervals)
    @test all(interval -> interval.upper_probability ≈ 1 - interval.lower_probability,
        summary[1].intervals)
    @test all(interval -> interval.width ≈ interval.upper - interval.lower,
        summary[1].intervals)
    @test all(row -> row.reference == 0.0, summary)
    @test all(row -> 0 <= row.probability_positive <= 1, summary)
    @test all(row -> 0 <= row.probability_negative <= 1, summary)
    @test all(row -> row.probability_of_direction ≈
        max(row.probability_positive, row.probability_negative), summary)
    @test all(row -> row.direction in (:positive, :negative, :undetermined), summary)
    @test all(row -> row.practical_equivalence === :not_requested, summary)
    @test all(row -> isnothing(row.probability_in_rope), summary)
    @test all(row -> row.n_draws == size(result.draws, 1), summary)
    first_values = Float64.(result.draws[:, 1])
    @test summary[1].probability_positive ≈ count(>(0.0), first_values) / length(first_values)
    @test summary[1].probability_negative ≈ count(<(0.0), first_values) / length(first_values)
    rope_summary = posterior_summary(result;
        intervals = (0.5,),
        reference = 0.25,
        rope = (-0.1, 0.1),
        rope_probability_threshold = 0.75)
    @test length(rope_summary[1].intervals) == 1
    @test rope_summary[1].intervals[1].probability ≈ 0.5
    @test all(row -> row.reference == 0.25, rope_summary)
    @test rope_summary[1].rope_lower == -0.1
    @test rope_summary[1].rope_upper == 0.1
    @test rope_summary[1].probability_in_rope ≈
        count(value -> -0.1 <= value <= 0.1, first_values) / length(first_values)
    @test rope_summary[1].probability_below_rope ≈
        count(<(-0.1), first_values) / length(first_values)
    @test rope_summary[1].probability_above_rope ≈
        count(>(0.1), first_values) / length(first_values)
    @test rope_summary[1].practical_equivalence in (:inside_rope, :outside_rope, :mixed)
    @test rope_summary[1].rope_probability_threshold == 0.75
    single_interval_summary = posterior_summary(result; intervals = 0.8)
    @test length(single_interval_summary[1].intervals) == 1
    @test single_interval_summary[1].intervals[1].probability ≈ 0.8
    @test_throws ArgumentError posterior_summary(result; lower = 0.6)
    @test_throws ArgumentError posterior_summary(result; upper = 0.4)
    @test_throws ArgumentError posterior_summary(result; intervals = (0.8, 1.2))
    @test_throws ArgumentError posterior_summary(result; reference = Inf)
    @test_throws ArgumentError posterior_summary(result; rope = -0.1)
    @test_throws ArgumentError posterior_summary(result; rope = (0.1, -0.1))
    @test_throws ArgumentError posterior_summary(result; rope_probability_threshold = 1.1)

    manual_wright_facet_values = function (facet, level_index)
        if facet === :person
            return [Float64(result.draws[draw, design.blocks[:person][level_index]])
                for draw in 1:2]
        elseif facet === :rater
            return level_index == 1 ? [0.0, 0.0] :
                [Float64(result.draws[draw, design.blocks[:rater][level_index - 1]])
                    for draw in 1:2]
        elseif facet === :item
            return level_index == 1 ? [0.0, 0.0] :
                [Float64(result.draws[draw, design.blocks[:item][level_index - 1]])
                    for draw in 1:2]
        end
        error("unexpected facet")
    end
    manual_wright_threshold_step = function (params, item_index, step)
        nsteps = length(data.category_levels) - 1
        free_steps = max(nsteps - 1, 0)
        free_steps == 0 && return 0.0
        step_range = design.blocks[:thresholds]
        if design.spec.thresholds === :rating_scale
            step <= free_steps && return Float64(params[step_range[step]])
            return -sum(Float64(params[step_range[s]]) for s in 1:free_steps)
        end
        offset = (item_index - 1) * free_steps
        step <= free_steps && return Float64(params[step_range[offset + step]])
        return -sum(Float64(params[step_range[offset + s]]) for s in 1:free_steps)
    end
    wright_rows = wright_map_data(result; draw_indices = [1, 2], interval = 0.8)
    wright_facet_rows = filter(row -> row.component === :facet_measure, wright_rows)
    wright_threshold_rows = filter(row -> row.component === :threshold, wright_rows)
    @test isequal(
        wright_map_data(design, result.draws[1:2, :]; interval = 0.8),
        wright_rows,
    )
    @test length(wright_facet_rows) ==
        length(data.person_levels) + length(data.rater_levels) + length(data.item_levels)
    @test length(wright_threshold_rows) ==
        length(data.item_levels) * (length(data.category_levels) - 1)
    @test all(row -> row.scale === :logit, wright_rows)
    @test all(row -> row.interval_probability == 0.8, wright_rows)
    @test all(row -> row.lower_probability ≈ 0.1, wright_rows)
    @test all(row -> row.upper_probability ≈ 0.9, wright_rows)
    @test all(row -> row.caveat === :wright_map_data_not_backend_rendering,
        wright_rows)
    for row in wright_facet_rows
        levels = row.facet === :person ? data.person_levels :
            row.facet === :rater ? data.rater_levels : data.item_levels
        level_index = findfirst(==(row.level), levels)
        values = manual_wright_facet_values(row.facet, level_index)
        expected_parameter_name = row.facet === :person ?
            design.parameter_names[design.blocks[:person][level_index]] :
            level_index == 1 ? missing :
            row.facet === :rater ?
            design.parameter_names[design.blocks[:rater][level_index - 1]] :
            design.parameter_names[design.blocks[:item][level_index - 1]]
        @test row.level_index == level_index
        @test row.n_draws == 2
        @test row.position_mean ≈ sum(values) / length(values)
        @test row.position_lower <= row.position_median <= row.position_upper
        @test isequal(row.parameter_name, expected_parameter_name)
        @test row.status === (level_index == 1 && row.facet !== :person ?
            :reference_zero : :estimated)
        @test row.flag === :ok
    end
    for row in wright_threshold_rows
        item_index = findfirst(==(row.item), data.item_levels)
        item_values = manual_wright_facet_values(:item, item_index)
        step_values = [
            manual_wright_threshold_step(@view(result.draws[draw, :]),
                item_index,
                row.step)
            for draw in 1:2
        ]
        positions = item_values .+ step_values
        @test row.item_index == item_index
        @test row.from_category == data.category_levels[row.step]
        @test row.to_category == data.category_levels[row.step + 1]
        @test row.position_mean ≈ sum(positions) / length(positions)
        @test row.item_measure_mean ≈ sum(item_values) / length(item_values)
        @test row.threshold_step_mean ≈ sum(step_values) / length(step_values)
        @test row.position_lower <= row.position_median <= row.position_upper
        @test row.threshold_parameter_index === row.parameter_index
        @test isequal(row.threshold_parameter_name, row.parameter_name)
        @test row.flag === :ok
    end
    person_wright = wright_map_data(result;
        facets = :person,
        include_thresholds = false,
        draw_indices = [1, 2])
    @test length(person_wright) == length(data.person_levels)
    @test all(row -> row.facet === :person, person_wright)
    @test_throws ArgumentError wright_map_data(result; facets = :category)
    @test_throws ArgumentError wright_map_data(result; facets = (:person, :person))
    @test_throws ArgumentError wright_map_data(result; interval = 1.0)
    @test_throws ArgumentError wright_map_data(result; draw_indices = [0])
    @test_throws ArgumentError wright_map_data(design, result.draws[1:2, 1:end-1])

    simulated_scores = simulate_responses(design, init; rng = MersenneTwister(8801), output = :scores)
    @test length(simulated_scores) == data.n
    @test all(score -> score in data.category_levels, simulated_scores)
    simulated_data = simulate_responses(design, init; rng = MersenneTwister(8801))
    @test simulated_data isa FacetData
    @test simulated_data.person == data.person
    @test simulated_data.rater == data.rater
    @test simulated_data.item == data.item
    @test simulated_data.score == simulated_scores
    @test simulated_data.category_levels == data.category_levels
    simulated_table = simulate_responses(spec, init; rng = MersenneTwister(8801), output = :table)
    @test simulated_table.person == [data.person_levels[index] for index in data.person]
    @test simulated_table.rater == [data.rater_levels[index] for index in data.rater]
    @test simulated_table.item == [data.item_levels[index] for index in data.item]
    @test simulated_table.score == simulated_scores
    @test_throws ArgumentError simulate_responses(design, init; output = :bad)
    @test_throws ArgumentError simulate_responses(design, init[1:end-1])

    sim_grid = simulation_grid(;
        densities = (:sparse, :near_complete),
        anchor_sizes = (0, 2),
        ratings_per_target = (1, 2),
        category_pathologies = (:none, :top_set),
        rater_noise = (:low, :high),
        dff = (:none, :rater_by_group),
        dimensionalities = (1, 2),
        misspecifications = (:none, :omitted_dff),
        repetitions = 2,
        base_seed = 700,
        grid_id = "unit",
        n_persons = 8,
        n_items = 3,
        n_raters = 2,
        n_categories = 3)
    @test length(sim_grid) == 2^8 * 2
    @test first(sim_grid).schema == "bayesianmgmfrm.simulation_grid.v1"
    @test first(sim_grid).object === :simulation_grid_row
    @test first(sim_grid).grid_id == "unit"
    @test first(sim_grid).row_index == 1
    @test first(sim_grid).scenario_index == 1
    @test first(sim_grid).replication == 1
    @test first(sim_grid).seed == 700
    @test first(sim_grid).n_persons == 8
    @test first(sim_grid).n_items == 3
    @test first(sim_grid).n_raters == 2
    @test first(sim_grid).target_units == 24
    @test first(sim_grid).max_ratings == 48
    @test first(sim_grid).planned_n_ratings == 24
    @test first(sim_grid).density_target ≈ 0.15
    @test first(sim_grid).planned_density ≈ 0.5
    @test first(sim_grid).simulation_status === :predeclared_not_run
    @test any(row -> row.anchor_size == 2 &&
        :anchor_linking in row.validation_focus, sim_grid)
    @test any(row -> row.category_pathology === :top_set &&
        :category_pathology in row.validation_focus, sim_grid)
    @test any(row -> row.rater_noise === :high &&
        row.rater_noise_sd ≈ 1.5, sim_grid)
    @test any(row -> row.dff === :rater_by_group && row.dff_active, sim_grid)
    @test any(row -> row.dimensionality == 2 &&
        row.fit_surface === :guarded_mgmfrm_preview, sim_grid)
    @test any(row -> row.misspecification === :omitted_dff &&
        row.misspecified, sim_grid)
    grid_summary = simulation_grid_summary(sim_grid)
    @test grid_summary.schema == "bayesianmgmfrm.simulation_grid_summary.v1"
    @test grid_summary.passed
    @test grid_summary.n_rows == length(sim_grid)
    @test grid_summary.n_scenarios == 2^8
    @test grid_summary.n_repetitions == 2
    @test grid_summary.first_seed == 700
    @test grid_summary.last_seed == 700 + length(sim_grid) - 1
    @test isempty(grid_summary.missing_required_axes)
    @test isempty(grid_summary.single_value_required_axes)
    @test grid_summary.varied_required_axes ==
        (:density, :anchor_size, :ratings_per_target, :category_pathology,
            :rater_noise, :dff, :dimensionality, :misspecification)
    compact_grid = simulation_grid(;
        densities = (:sparse,),
        anchor_sizes = (0,),
        ratings_per_target = (1,),
        category_pathologies = (:none,),
        rater_noise = (:low,),
        dff = (:none,),
        dimensionalities = (1,),
        misspecifications = (:none,),
        n_raters = 2)
    compact_summary = simulation_grid_summary(compact_grid)
    @test !compact_summary.passed
    @test compact_summary.single_value_required_axes ==
        (:density, :anchor_size, :ratings_per_target, :category_pathology,
            :rater_noise, :dff, :dimensionality, :misspecification)
    @test_throws ArgumentError simulation_grid(; densities = ())
    @test_throws ArgumentError simulation_grid(; ratings_per_target = (3,), n_raters = 2)
    @test_throws ArgumentError simulation_grid(; repetitions = 0)
    @test_throws ArgumentError simulation_grid_summary(NamedTuple[])
    @test_throws ArgumentError simulation_grid_summary(Any[1])

    rules = falsification_rules()
    @test length(rules) == 13
    @test first(rules).schema == "bayesianmgmfrm.falsification_rule.v1"
    @test first(rules).object === :falsification_rule
    @test first(rules).claim === :sparse_hierarchical_priors_stabilize_mgmfrm
    @test first(rules).status === :predeclared_not_evaluated
    @test all(row -> !row.manuscript_claim_allowed_if_triggered, rules)
    @test all(row -> row.caveat === :rule_predeclared_not_evidence, rules)
    @test only(filter(row -> row.rule_id === :grid_axes_incomplete,
        rules)).threshold ==
        (:density, :anchor_size, :ratings_per_target, :category_pathology,
            :rater_noise, :dff, :dimensionality, :misspecification)
    @test only(filter(row -> row.metric === :max_rhat, rules)).threshold == 1.01
    @test only(filter(row -> row.metric === :min_bulk_ess, rules)).threshold == 400.0
    @test only(filter(row -> row.rule_id === :divergences_or_treedepth,
        rules)).threshold == (divergences = 0, max_treedepth_hits = 0)
    @test only(filter(row -> row.domain === :baseline_comparison,
        rules)).required_evidence === :compare_kfold
    rule_summary = falsification_rule_summary(rules)
    @test rule_summary.schema == "bayesianmgmfrm.falsification_rule_summary.v1"
    @test rule_summary.passed
    @test rule_summary.status === :complete
    @test rule_summary.n_rules == length(rules)
    @test rule_summary.n_domains == 10
    @test isempty(rule_summary.missing_required_domains)
    @test rule_summary.present_required_domains ==
        (:simulation_grid, :design_validation, :computation, :recovery,
            :calibration, :predictive_check, :decision_stability,
            :sensitivity, :baseline_comparison, :reproducibility)
    incomplete_rules = filter(row -> row.domain !== :calibration, rules)
    incomplete_rule_summary = falsification_rule_summary(incomplete_rules)
    @test !incomplete_rule_summary.passed
    @test incomplete_rule_summary.status === :incomplete
    @test incomplete_rule_summary.missing_required_domains == (:calibration,)
    custom_rules = falsification_rules(;
        max_rhat = 1.05,
        min_bulk_ess = 200,
        min_interval_coverage = 0.8,
        required_grid_axes = (:density, :dff))
    @test only(filter(row -> row.metric === :max_rhat,
        custom_rules)).threshold == 1.05
    @test only(filter(row -> row.metric === :min_bulk_ess,
        custom_rules)).threshold == 200.0
    @test only(filter(row -> row.metric === :interval_coverage_rate,
        custom_rules)).threshold == 0.8
    @test only(filter(row -> row.rule_id === :grid_axes_incomplete,
        custom_rules)).threshold == (:density, :dff)
    @test_throws ArgumentError falsification_rules(; max_rhat = 0.99)
    @test_throws ArgumentError falsification_rules(; min_interval_coverage = 1.1)
    @test_throws ArgumentError falsification_rule_summary(NamedTuple[])
    @test_throws ArgumentError falsification_rule_summary(Any[1])

    validation_plan_script =
        joinpath(dirname(@__DIR__), "scripts", "generate_validation_plan.jl")
    @test isfile(validation_plan_script)
    validation_plan_path = tempname() * ".json"
    run(`$(Base.julia_cmd()) --startup-file=no --project=$(dirname(@__DIR__))
        $validation_plan_script --preset smoke --grid-id unit-plan
        --base-seed 8100 --output $validation_plan_path`)
    validation_plan = JSON3.read(read(validation_plan_path, String))
    @test String(validation_plan[:schema]) ==
        "bayesianmgmfrm.validation_plan_artifact.v1"
    @test String(validation_plan[:generator][:script]) ==
        "scripts/generate_validation_plan.jl"
    @test String(validation_plan[:controls][:preset]) == "smoke"
    @test String(validation_plan[:controls][:grid_id]) == "unit-plan"
    @test Int(validation_plan[:simulation_grid][:summary][:n_rows]) == 2^8
    @test Int(validation_plan[:simulation_grid][:summary][:first_seed]) == 8100
    @test Int(validation_plan[:simulation_grid][:summary][:last_seed]) ==
        8100 + 2^8 - 1
    @test Bool(validation_plan[:simulation_grid][:summary][:passed])
    @test String(validation_plan[:simulation_grid][:row_policy]) ==
        "omitted_regenerable_from_controls"
    @test isnothing(validation_plan[:simulation_grid][:rows])
    @test length(validation_plan[:simulation_grid][:row_samples]) == 4
    @test Bool(validation_plan[:falsification][:summary][:passed])
    @test Int(validation_plan[:falsification][:summary][:n_rules]) == 13
    @test length(validation_plan[:falsification][:rules]) == 13
    @test Bool(validation_plan[:execution_policy][:runs_simulations]) == false
    @test Bool(validation_plan[:execution_policy][:fits_models]) == false
    @test Bool(validation_plan[:execution_policy][:evaluates_claims]) == false
    @test String(validation_plan[:execution_policy][:next_gate]) ==
        "run_predeclared_grid_and_apply_falsification_rules"
    @test String(validation_plan[:content_hash][:algorithm]) == "sha256"
    @test length(String(validation_plan[:content_hash][:value])) == 64
    rm(validation_plan_path; force = true)

    comparison_rows = [
        comparison_evidence_row(;
            comparison_class = :stan,
            target_model = :scalar_gmfrm,
            comparator = :bridge_stan,
            metric = :max_log_density_abs_error,
            estimate = 1e-10,
            reference = 0.0,
            tolerance = 1e-8,
            evidence = :stan_validation_summary,
            artifact = "test/fixtures/scalar_validation_stan_logdensity.json"),
        comparison_evidence_row(;
            comparison_class = :facets,
            target_model = :mfrm_pcm,
            comparator = :facets_export,
            metric = :severity_correlation,
            estimate = 0.99,
            reference = 1.0,
            tolerance = 0.02,
            evidence = :external_tool_table),
        comparison_evidence_row(;
            comparison_class = :nested,
            target_model = :guarded_scalar_gmfrm,
            comparator = :mfrm_pcm_rsm_baseline,
            metric = :heldout_elpd_difference,
            estimate = 2.5,
            reference = 0.0,
            pass_if = :greater_equal,
            evidence = :compare_kfold),
    ]
    @test first(comparison_rows).schema == "bayesianmgmfrm.comparison_evidence_row.v1"
    @test first(comparison_rows).object === :comparison_evidence_row
    @test first(comparison_rows).comparison_class === :stan_faithful
    @test first(comparison_rows).status === :passed
    @test first(comparison_rows).absolute_difference ≈ 1e-10
    @test comparison_rows[2].comparison_class === :r_frequentist
    @test comparison_rows[3].comparison_class === :nested_model
    @test comparison_rows[3].pass_if === :greater_equal
    @test comparison_rows[3].difference ≈ 2.5
    comparison_summary = comparison_evidence_summary(comparison_rows)
    @test comparison_summary.schema ==
        "bayesianmgmfrm.comparison_evidence_summary.v1"
    @test comparison_summary.passed
    @test comparison_summary.status === :complete
    @test comparison_summary.required_classes ==
        (:stan_faithful, :r_frequentist, :nested_model)
    @test comparison_summary.observed_classes ==
        (:nested_model, :r_frequentist, :stan_faithful)
    @test isempty(comparison_summary.missing_required_classes)
    @test isempty(comparison_summary.failed_required_classes)
    @test comparison_summary.n_rows == 3
    @test comparison_summary.n_passed_rows == 3
    @test only(filter(row -> row.comparison_class === :stan_faithful,
        comparison_summary.class_rows)).artifacts ==
        ("test/fixtures/scalar_validation_stan_logdensity.json",)
    incomplete_comparison_summary = comparison_evidence_summary(
        filter(row -> row.comparison_class !== :r_frequentist, comparison_rows))
    @test !incomplete_comparison_summary.passed
    @test incomplete_comparison_summary.status === :incomplete
    @test incomplete_comparison_summary.missing_required_classes == (:r_frequentist,)
    custom_comparison_summary = comparison_evidence_summary(
        comparison_rows[1],
        comparison_rows[3];
        required_classes = (:stan, :nested))
    @test custom_comparison_summary.passed
    @test custom_comparison_summary.required_classes == (:stan_faithful, :nested_model)
    failed_comparison = comparison_evidence_row(;
        comparison_class = :facets,
        target_model = :mfrm_pcm,
        comparator = :facets_export,
        metric = :severity_correlation,
        estimate = 0.80,
        reference = 1.0,
        tolerance = 0.02,
        evidence = :external_tool_table)
    @test !failed_comparison.passed
    @test failed_comparison.status === :failed
    failed_comparison_summary = comparison_evidence_summary(
        comparison_rows[1],
        failed_comparison,
        comparison_rows[3])
    @test !failed_comparison_summary.passed
    @test failed_comparison_summary.failed_required_classes == (:r_frequentist,)
    @test_throws ArgumentError comparison_evidence_row(;
        comparison_class = :stan,
        target_model = :scalar_gmfrm,
        comparator = :bridge_stan,
        metric = :log_density,
        estimate = Inf,
        reference = 0.0)
    @test_throws ArgumentError comparison_evidence_row(;
        comparison_class = :stan,
        target_model = :scalar_gmfrm,
        comparator = :bridge_stan,
        metric = :log_density,
        estimate = 0.0,
        reference = 0.0,
        tolerance = -1)
    @test_throws ArgumentError comparison_evidence_row(;
        comparison_class = :stan,
        target_model = :scalar_gmfrm,
        comparator = :bridge_stan,
        metric = :log_density,
        estimate = 0.0,
        reference = 0.0,
        pass_if = :bad)
    @test_throws ArgumentError comparison_evidence_summary(NamedTuple[])
    @test_throws ArgumentError comparison_evidence_summary(Any[1])

    julia_benchmark = benchmark_result_row(;
        benchmark = :minimal_pcm_nuts,
        engine = :advancedhmc,
        model = :mfrm_pcm,
        elapsed_seconds = (9.0, 10.0, 11.0),
        effective_sample_sizes = (900.0, 1000.0, 1100.0),
        time_to_quality_seconds = (10.0, 11.0, 12.0),
        time_to_quality_threshold_seconds = 15.0,
        idle_machine = true,
        hardware = :local_idle_machine,
        software = :julia_1)
    stan_benchmark = benchmark_result_row(;
        benchmark = :minimal_pcm_nuts,
        engine = :cmdstan,
        model = :stan_pcm,
        elapsed_seconds = (18.0, 20.0, 22.0),
        effective_sample_sizes = (720.0, 800.0, 880.0),
        time_to_quality_seconds = (23.0, 24.0, 25.0),
        time_to_quality_threshold_seconds = 30.0,
        idle_machine = true,
        hardware = :local_idle_machine,
        software = :cmdstan)
    @test julia_benchmark.schema == "bayesianmgmfrm.benchmark_result_row.v1"
    @test julia_benchmark.object === :benchmark_result_row
    @test julia_benchmark.engine === :julia
    @test julia_benchmark.reported_engine === :advancedhmc
    @test julia_benchmark.n_repetitions == 3
    @test julia_benchmark.elapsed_median_seconds ≈ 10.0
    @test julia_benchmark.ess_per_second_median ≈ 100.0
    @test julia_benchmark.time_to_quality_median_seconds ≈ 11.0
    @test julia_benchmark.time_to_quality_passed === true
    @test julia_benchmark.status === :passed
    @test stan_benchmark.engine === :stan
    @test stan_benchmark.ess_per_second_median ≈ 40.0
    benchmark_gate = benchmark_summary(julia_benchmark, stan_benchmark)
    @test benchmark_gate.schema == "bayesianmgmfrm.benchmark_summary.v1"
    @test benchmark_gate.passed
    @test benchmark_gate.status === :complete
    @test benchmark_gate.required_engines == (:julia, :stan)
    @test benchmark_gate.observed_engines == (:julia, :stan)
    @test benchmark_gate.n_rows == 2
    @test benchmark_gate.n_benchmarks == 1
    @test benchmark_gate.all_idle
    @test benchmark_gate.failed_time_to_quality == 0
    ratio_row = only(benchmark_gate.benchmark_rows)
    @test ratio_row.benchmark === :minimal_pcm_nuts
    @test ratio_row.status === :complete
    @test ratio_row.stan_to_julia_elapsed_ratio ≈ 2.0
    @test ratio_row.julia_to_stan_ess_per_second_ratio ≈ 2.5
    missing_engine_gate = benchmark_summary([julia_benchmark])
    @test !missing_engine_gate.passed
    @test missing_engine_gate.status === :incomplete
    @test missing_engine_gate.missing_required_engines == (:stan,)
    custom_engine_gate = benchmark_summary(
        julia_benchmark;
        required_engines = (:advancedhmc,),
        min_repetitions = 3)
    @test custom_engine_gate.passed
    @test custom_engine_gate.required_engines == (:julia,)
    too_few_repeats = benchmark_summary(
        julia_benchmark,
        stan_benchmark;
        min_repetitions = 4)
    @test !too_few_repeats.passed
    @test too_few_repeats.rows_with_few_repetitions == 2
    failed_benchmark = benchmark_result_row(;
        benchmark = :minimal_pcm_nuts,
        engine = :advancedhmc,
        model = :mfrm_pcm,
        elapsed_seconds = (9.0, 10.0, 11.0),
        time_to_quality_seconds = (10.0, 11.0, 12.0),
        time_to_quality_threshold_seconds = 10.0)
    @test failed_benchmark.status === :failed
    failed_benchmark_gate = benchmark_summary(failed_benchmark, stan_benchmark)
    @test !failed_benchmark_gate.passed
    @test failed_benchmark_gate.failed_time_to_quality == 1
    @test_throws ArgumentError benchmark_result_row(;
        benchmark = :minimal_pcm_nuts,
        engine = :advancedhmc,
        model = :mfrm_pcm,
        elapsed_seconds = ())
    @test_throws ArgumentError benchmark_result_row(;
        benchmark = :minimal_pcm_nuts,
        engine = :advancedhmc,
        model = :mfrm_pcm,
        elapsed_seconds = (1.0, 2.0),
        effective_sample_sizes = (100.0,))
    @test_throws ArgumentError benchmark_result_row(;
        benchmark = :minimal_pcm_nuts,
        engine = :advancedhmc,
        model = :mfrm_pcm,
        elapsed_seconds = (1.0, 2.0),
        time_to_quality_seconds = (1.0,))
    @test_throws ArgumentError benchmark_summary(NamedTuple[])
    @test_throws ArgumentError benchmark_summary(Any[1])
    @test_throws ArgumentError benchmark_summary(julia_benchmark; min_repetitions = 0)

    truth = [row.mean for row in summary]
    recovery = parameter_recovery(result, truth; interval = 0.8)
    @test length(recovery) == length(design.parameter_names)
    @test [row.parameter for row in recovery] == design.parameter_names
    @test [row.parameter_index for row in recovery] == collect(eachindex(design.parameter_names))
    @test all(row -> row.block in keys(design.blocks), recovery)
    @test all(row -> row.interval_probability ≈ 0.8, recovery)
    @test all(row -> row.lower_probability ≈ 0.1, recovery)
    @test all(row -> row.upper_probability ≈ 0.9, recovery)
    @test all(row -> abs(row.bias) < 1e-12, recovery)
    @test all(row -> row.absolute_bias ≈ abs(row.bias), recovery)
    @test all(row -> row.squared_error ≈ row.bias^2, recovery)
    @test all(row -> row.interval_width ≈ row.posterior_upper - row.posterior_lower, recovery)
    @test [row.posterior_mean for row in recovery] ≈ truth
    design_recovery = parameter_recovery(design, result.draws, truth; interval = 0.8)
    @test [row.posterior_mean for row in design_recovery] ≈ [row.posterior_mean for row in recovery]
    recovery_by_block = parameter_recovery_summary(recovery; by = :block)
    @test sum(row.n_parameters for row in recovery_by_block) == length(recovery)
    @test all(row -> row.by === :block, recovery_by_block)
    @test all(row -> row.mean_absolute_error < 1e-12, recovery_by_block)
    @test all(row -> row.rmse < 1e-12, recovery_by_block)
    recovery_overall = parameter_recovery_summary(recovery; by = :all)
    @test length(recovery_overall) == 1
    @test recovery_overall[1].group === :all
    @test recovery_overall[1].n_parameters == length(recovery)
    recovery_plot = parameter_recovery_plot_data(recovery)
    @test length(recovery_plot) == length(recovery)
    @test [row.true_value for row in recovery_plot] ≈ [row.true_value for row in recovery]
    @test [row.estimate for row in recovery_plot] ≈ [row.posterior_mean for row in recovery]
    @test [row.interval_lower for row in recovery_plot] ≈ [row.posterior_lower for row in recovery]
    @test [row.interval_upper for row in recovery_plot] ≈ [row.posterior_upper for row in recovery]
    @test [row.reference for row in recovery_plot] ≈ [row.true_value for row in recovery]
    @test [row.estimate for row in parameter_recovery_plot_data(result, truth; interval = 0.8)] ≈
        [row.estimate for row in recovery_plot]
    @test_throws ArgumentError parameter_recovery(result, truth[1:end-1])
    @test_throws ArgumentError parameter_recovery(design, result.draws[1:0, :], truth)
    @test_throws ArgumentError parameter_recovery_summary(NamedTuple[])
    @test_throws ArgumentError parameter_recovery_summary(recovery; by = :missing_field)

    llmat = pointwise_loglikelihood_matrix(result)
    @test size(llmat) == (24, data.n)
    @test llmat[1, :] ≈ pointwise_loglikelihood(design, result.draws[1, :])
    @test pointwise_loglikelihood_matrix(design, result.draws) ≈ llmat
    @test_throws ArgumentError pointwise_loglikelihood_matrix(design, result.draws[:, 1:end-1])
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        design,
        result.draws;
        parameter_space = :raw)
    @test_throws ArgumentError pointwise_loglikelihood_matrix(
        design,
        result.draws;
        parameter_space = :missing)
    draw_loglik = loglikelihood(result)
    draw_logprior = logprior(result)
    draw_logposterior = logposterior(result)
    @test draw_loglik ≈ [sum(llmat[draw, :]) for draw in axes(llmat, 1)]
    @test draw_logprior ≈
        [logprior(design, @view(result.draws[draw, :]), prior) for draw in axes(result.draws, 1)]
    @test draw_logposterior == result.log_posterior
    @test draw_loglik .+ draw_logprior ≈ draw_logposterior
    @test loglikelihood(result; draw_indices = [3, 1]) ≈ draw_loglik[[3, 1]]
    @test logprior(result; draw_indices = [3, 1]) ≈ draw_logprior[[3, 1]]
    @test logposterior(result; draw_indices = [3, 1]) == result.log_posterior[[3, 1]]
    @test length(loglikelihood(result; ndraws = 2, rng = MersenneTwister(20260621))) == 2
    @test_throws ArgumentError loglikelihood(result; ndraws = 0)
    @test_throws ArgumentError logprior(result; draw_indices = Int[])
    @test_throws ArgumentError logposterior(result; ndraws = 1, draw_indices = [1])

    waic_result = waic(result; draw_indices = [1, 2, 3])
    manual_lppd = [test_logsumexp(@view llmat[1:3, row]) - log(3) for row in 1:data.n]
    manual_p_waic = [test_sample_variance(@view llmat[1:3, row]) for row in 1:data.n]
    manual_elpd = manual_lppd .- manual_p_waic
    manual_waic = -2 .* manual_elpd
    @test waic_result.criterion === :waic
    @test waic_result.n_draws == 3
    @test waic_result.n_observations == data.n
    @test waic_result.pointwise.lppd ≈ manual_lppd
    @test waic_result.pointwise.p_waic ≈ manual_p_waic
    @test waic_result.pointwise.elpd_waic ≈ manual_elpd
    @test waic_result.pointwise.waic ≈ manual_waic
    @test waic_result.lppd ≈ sum(manual_lppd)
    @test waic_result.p_waic ≈ sum(manual_p_waic)
    @test waic_result.elpd_waic ≈ sum(manual_elpd)
    @test waic_result.waic ≈ sum(manual_waic)
    @test waic_result.waic ≈ -2 * waic_result.elpd_waic
    @test waic_result.se_waic ≈ 2 * waic_result.se_elpd_waic
    @test waic_result.high_variance_count == count(>(0.4), manual_p_waic)
    @test waic_result.warning in (:ok, :high_loglik_variance)
    @test waic(design, result.draws[1:3, :]).waic ≈ waic_result.waic
    @test waic(llmat[1:3, :]).waic ≈ waic_result.waic
    @test_throws ArgumentError waic(result; ndraws = 1)
    @test_throws ArgumentError waic(result; ndraws = 2, draw_indices = [1])
    @test_throws ArgumentError waic(design, result.draws[1:3, 1:end-1])
    @test_throws ArgumentError waic(llmat[1:1, :])
    @test_throws ArgumentError waic([0.0 Inf; 1.0 2.0])

    loo_indices = collect(1:6)
    loo_loglik = llmat[loo_indices, :]
    loo_result = loo(result; draw_indices = loo_indices)
    manual_loo_lppd = [
        test_logsumexp(@view loo_loglik[:, row]) - log(length(loo_indices))
        for row in 1:data.n
    ]
    manual_elpd_loo = [
        -(test_logsumexp([-Float64(value) for value in @view loo_loglik[:, row]]) -
            log(length(loo_indices)))
        for row in 1:data.n
    ]
    manual_p_loo = manual_loo_lppd .- manual_elpd_loo
    manual_looic = -2 .* manual_elpd_loo
    @test loo_result.criterion === :loo
    @test loo_result.method === :raw_importance_sampling
    @test loo_result.psis_smoothing === false
    @test loo_result.pareto_k_estimator === :hill_log_tail
    @test loo_result.n_draws == length(loo_indices)
    @test loo_result.n_observations == data.n
    @test loo_result.pareto_k_threshold == 0.7
    @test loo_result.tail_fraction == 0.2
    @test loo_result.min_tail_draws == 5
    @test loo_result.pointwise.lppd ≈ manual_loo_lppd
    @test loo_result.pointwise.elpd_loo ≈ manual_elpd_loo
    @test loo_result.pointwise.p_loo ≈ manual_p_loo
    @test loo_result.pointwise.looic ≈ manual_looic
    @test loo_result.lppd ≈ sum(manual_loo_lppd)
    @test loo_result.p_loo ≈ sum(manual_p_loo)
    @test loo_result.elpd_loo ≈ sum(manual_elpd_loo)
    @test loo_result.looic ≈ sum(manual_looic)
    @test loo_result.looic ≈ -2 * loo_result.elpd_loo
    @test loo_result.se_looic ≈ 2 * loo_result.se_elpd_loo
    @test all(isfinite, loo_result.pointwise.pareto_k)
    @test all(k -> k >= 0, loo_result.pointwise.pareto_k)
    @test all(ess -> 1 <= ess <= loo_result.n_draws,
        loo_result.pointwise.effective_sample_size)
    @test all(draws -> 1 <= draws <= loo_result.n_draws - 1,
        loo_result.pointwise.tail_draws)
    @test loo_result.bad_pareto_k_count ==
        count(>(loo_result.pareto_k_threshold), loo_result.pointwise.pareto_k)
    @test loo_result.max_pareto_k == maximum(loo_result.pointwise.pareto_k)
    @test loo_result.min_effective_sample_size ==
        minimum(loo_result.pointwise.effective_sample_size)
    @test loo_result.warning in (:ok, :high_pareto_k)
    @test loo(design, result.draws[loo_indices, :]).looic ≈ loo_result.looic
    @test loo(loo_loglik).looic ≈ loo_result.looic
    @test_throws ArgumentError loo(result; ndraws = 2)
    @test_throws ArgumentError loo(result; ndraws = 3, draw_indices = [1])
    @test_throws ArgumentError loo(design, result.draws[loo_indices, 1:end-1])
    @test_throws ArgumentError loo(llmat[1:2, :])
    @test_throws ArgumentError loo([0.0 Inf; 1.0 2.0; 1.0 2.0])
    @test_throws ArgumentError loo(loo_loglik; pareto_k_threshold = -0.1)
    @test_throws ArgumentError loo(loo_loglik; tail_fraction = 1.0)
    @test_throws ArgumentError loo(loo_loglik; min_tail_draws = 0)

    psis_result = psis_loo(result; draw_indices = loo_indices)
    @test psis_result.criterion === :loo
    @test psis_result.method === :pareto_smoothed_importance_sampling
    @test psis_result.psis_smoothing === true
    @test psis_result.pareto_k_estimator === :hill_log_tail
    @test psis_result.n_draws == length(loo_indices)
    @test psis_result.n_observations == data.n
    @test psis_result.pareto_k_threshold == 0.7
    @test psis_result.tail_fraction == 0.2
    @test psis_result.min_tail_draws == 5
    @test psis_result.pointwise.lppd ≈ manual_loo_lppd
    @test psis_result.pointwise.p_loo ≈
        psis_result.pointwise.lppd .- psis_result.pointwise.elpd_loo
    @test psis_result.pointwise.looic ≈ -2 .* psis_result.pointwise.elpd_loo
    @test psis_result.lppd ≈ sum(manual_loo_lppd)
    @test psis_result.p_loo ≈ sum(psis_result.pointwise.p_loo)
    @test psis_result.elpd_loo ≈ sum(psis_result.pointwise.elpd_loo)
    @test psis_result.looic ≈ sum(psis_result.pointwise.looic)
    @test psis_result.looic ≈ -2 * psis_result.elpd_loo
    @test psis_result.se_looic ≈ 2 * psis_result.se_elpd_loo
    @test psis_result.pointwise.pareto_k ≈ loo_result.pointwise.pareto_k
    @test all(isfinite, psis_result.pointwise.elpd_loo)
    @test all(isfinite, psis_result.pointwise.pareto_k)
    @test all(k -> k >= 0, psis_result.pointwise.pareto_k)
    @test all(ess -> 1 <= ess <= psis_result.n_draws,
        psis_result.pointwise.effective_sample_size)
    @test all(draws -> 1 <= draws <= psis_result.n_draws - 1,
        psis_result.pointwise.tail_draws)
    @test psis_result.bad_pareto_k_count ==
        count(>(psis_result.pareto_k_threshold), psis_result.pointwise.pareto_k)
    @test psis_result.max_pareto_k == maximum(psis_result.pointwise.pareto_k)
    @test psis_result.min_effective_sample_size ==
        minimum(psis_result.pointwise.effective_sample_size)
    @test psis_result.warning in (:ok, :high_pareto_k)
    @test psis_loo(design, result.draws[loo_indices, :]).looic ≈
        psis_result.looic
    @test psis_loo(loo_loglik).looic ≈ psis_result.looic
    constant_loglik = fill(-1.2, length(loo_indices), 2)
    constant_raw_loo = loo(constant_loglik)
    constant_psis_loo = psis_loo(constant_loglik)
    @test constant_psis_loo.pointwise.elpd_loo ≈
        constant_raw_loo.pointwise.elpd_loo
    @test all(isapprox.(constant_psis_loo.pointwise.p_loo,
        constant_raw_loo.pointwise.p_loo; atol = eps()))
    @test all(iszero, constant_psis_loo.pointwise.pareto_k)
    @test_throws ArgumentError psis_loo(result; ndraws = 2)
    @test_throws ArgumentError psis_loo(result; ndraws = 3, draw_indices = [1])
    @test_throws ArgumentError psis_loo(design, result.draws[loo_indices, 1:end-1])
    @test_throws ArgumentError psis_loo(llmat[1:2, :])
    @test_throws ArgumentError psis_loo([0.0 Inf; 1.0 2.0; 1.0 2.0])
    @test_throws ArgumentError psis_loo(loo_loglik; pareto_k_threshold = -0.1)
    @test_throws ArgumentError psis_loo(loo_loglik; tail_fraction = 1.0)
    @test_throws ArgumentError psis_loo(loo_loglik; min_tail_draws = 0)

    loo_plan = loo_refit_plan(data)
    @test loo_plan.schema == "bayesianmgmfrm.loo_refit_plan.v1"
    @test loo_plan.object === :loo_refit_plan
    @test loo_plan.method === :deterministic_leave_one_observation_out_plan
    @test loo_plan.comparison_contract === :same_heldout_observation_folds
    @test loo_plan.group_by === :observation
    @test loo_plan.n_observations == data.n
    @test loo_plan.n_refits == data.n
    @test loo_plan.n_folds == data.n
    @test loo_plan.folds == collect(1:data.n)
    @test loo_plan.n_heldout_by_fold == fill(1, data.n)
    @test loo_plan.refits_per_model_required == data.n
    @test loo_plan.warning === :ok
    @test loo_plan.heldout_observation_indices == [[row] for row in 1:data.n]
    @test loo_plan.observation_fold == collect(1:data.n)
    @test length(loo_plan.fold_rows) == data.n
    @test first(loo_plan.fold_rows).heldout_observations == [1]
    @test first(loo_plan.fold_rows).training_observations == collect(2:data.n)
    @test all(row -> row.n_heldout_observations == 1, loo_plan.fold_rows)
    @test all(row -> row.n_training_observations == data.n - 1,
        loo_plan.fold_rows)
    planned_exact_loo = kfold([llmat[1:3, indices]
            for indices in loo_plan.heldout_observation_indices];
        fold_ids = loo_plan.folds,
        observation_indices = loo_plan.heldout_observation_indices)
    @test planned_exact_loo.n_folds == loo_plan.n_refits
    @test planned_exact_loo.n_heldout_by_fold == loo_plan.n_heldout_by_fold
    @test planned_exact_loo.observation_indices == collect(1:data.n)
    subset_loo_plan = loo_refit_plan(spec;
        observations = [2, 4],
        fold_ids = [:obs2, :obs4])
    @test subset_loo_plan.warning === :subset
    @test subset_loo_plan.n_refits == 2
    @test subset_loo_plan.folds == [:obs2, :obs4]
    @test subset_loo_plan.heldout_observation_indices == [[2], [4]]
    @test subset_loo_plan.observation_fold[1] === missing
    @test subset_loo_plan.observation_fold[2] === :obs2
    @test subset_loo_plan.observation_fold[4] === :obs4
    @test kfold_plan_diagnostics(design, subset_loo_plan;
        facets = :person).n_rows == subset_loo_plan.n_refits
    flagged_loo_result = (;
        loo_result...,
        pointwise = (;
            loo_result.pointwise...,
            pareto_k = [0.1, 0.8, 0.2, 1.1, fill(0.0, data.n - 4)...],
        ),
        pareto_k_threshold = 0.7,
        bad_pareto_k_count = 2,
        warning = :high_pareto_k,
    )
    flagged_loo_plan = loo_refit_plan(data, flagged_loo_result)
    @test flagged_loo_plan.warning === :subset
    @test flagged_loo_plan.n_refits == 2
    @test flagged_loo_plan.folds == [2, 4]
    @test flagged_loo_plan.heldout_observation_indices == [[2], [4]]
    @test flagged_loo_plan.observation_fold[1] === missing
    @test flagged_loo_plan.observation_fold[2] == 2
    @test flagged_loo_plan.observation_fold[4] == 4
    relaxed_loo_plan = loo_refit_plan(design, flagged_loo_result;
        threshold = 1.0,
        fold_ids = [:obs4])
    @test relaxed_loo_plan.folds == [:obs4]
    @test relaxed_loo_plan.heldout_observation_indices == [[4]]
    all_loo_plan = loo_refit_plan(spec, flagged_loo_result;
        only_flagged = false)
    @test all_loo_plan.warning === :ok
    @test all_loo_plan.n_refits == data.n
    no_flag_loo_result = (;
        flagged_loo_result...,
        pointwise = (;
            flagged_loo_result.pointwise...,
            pareto_k = fill(0.1, data.n),
        ),
        bad_pareto_k_count = 0,
        warning = :ok,
    )
    no_flag_loo_plan = loo_refit_plan(data, no_flag_loo_result)
    @test no_flag_loo_plan.warning === :no_refits_required
    @test no_flag_loo_plan.n_refits == 0
    @test no_flag_loo_plan.folds == Any[]
    @test no_flag_loo_plan.heldout_observation_indices == []
    @test no_flag_loo_plan.n_heldout_by_fold == Int[]
    @test isempty(no_flag_loo_plan.fold_rows)
    @test all(ismissing, no_flag_loo_plan.observation_fold)

    executed_loo_plan = loo_refit_plan(data; observations = [1, 2])
    executed_loo = loo_refit(
        spec,
        executed_loo_plan;
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 1,
        step_size = 0.02,
        init,
        seed = 111,
    )
    @test executed_loo.schema == "bayesianmgmfrm.loo_refit.v1"
    @test executed_loo.object === :loo_refit
    @test executed_loo.criterion === :kfold
    @test executed_loo.method === :heldout_refit_log_score
    @test executed_loo.refit_method === :exact_leave_one_observation_out_refit
    @test executed_loo.plan_schema == "bayesianmgmfrm.loo_refit_plan.v1"
    @test executed_loo.n_refits == 2
    @test executed_loo.n_folds == 2
    @test executed_loo.n_observations == 2
    @test executed_loo.n_total_observations == data.n
    @test executed_loo.folds == [1, 2]
    @test executed_loo.observation_indices == [1, 2]
    @test executed_loo.n_draws_by_fold == [3, 3]
    @test executed_loo.n_heldout_by_fold == [1, 1]
    @test length(executed_loo.fold_logliks) == 2
    @test all(matrix -> size(matrix) == (3, 1), executed_loo.fold_logliks)
    @test all(matrix -> all(isfinite, matrix), executed_loo.fold_logliks)
    @test length(executed_loo.fit_rows) == 2
    @test all(row -> row.n_training_observations == data.n - 1, executed_loo.fit_rows)
    @test all(row -> row.n_heldout_observations == 1, executed_loo.fit_rows)
    @test executed_loo.plan_diagnostics.passed
    @test isnothing(executed_loo.fold_fits)
    @test executed_loo.kfold_summary.criterion === :kfold

    executed_loo_with_fits = loo_refit(
        design,
        loo_refit_plan(data; observations = [1]);
        prior,
        return_fits = true,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init,
        seed = 112,
    )
    @test length(executed_loo_with_fits.fold_fits) == 1
    @test executed_loo_with_fits.fold_fits[1] isa MFRMFit

    no_refits_executed = loo_refit(
        data,
        no_flag_loo_plan;
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init,
        seed = 113,
    )
    @test no_refits_executed.object === :loo_refit
    @test no_refits_executed.criterion === :loo_refit
    @test no_refits_executed.method === :no_refits_required
    @test no_refits_executed.warning === :no_refits_required
    @test no_refits_executed.n_refits == 0
    @test isnothing(no_refits_executed.kfold_summary)

    blocked_loo_data = FacetData(
        (;
            person = ["P1", "P2"],
            rater = ["R1", "R1"],
            item = ["I1", "I1"],
            score = [0, 1],
        );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    blocked_loo_spec = mfrm_spec(blocked_loo_data)
    blocked_loo_plan = loo_refit_plan(blocked_loo_data; observations = [1])
    @test !kfold_plan_diagnostics(blocked_loo_data, blocked_loo_plan).passed
    @test_throws ArgumentError loo_refit(
        blocked_loo_spec,
        blocked_loo_plan;
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        seed = 114,
    )

    @test_throws ArgumentError loo_refit_plan(data; observations = Int[])
    @test_throws ArgumentError loo_refit_plan(data; observations = [1, 1])
    @test_throws ArgumentError loo_refit_plan(data; observations = [0])
    @test_throws ArgumentError loo_refit_plan(data; observations = [true])
    @test_throws ArgumentError loo_refit_plan(data; observations = [1, 2],
        fold_ids = [:only])
    @test_throws ArgumentError loo_refit_plan(data; observations = [1, 2],
        fold_ids = [:dup, :dup])
    @test_throws ArgumentError loo_refit_plan(data, waic_result)
    @test_throws ArgumentError loo_refit_plan(data, flagged_loo_result;
        threshold = -0.1)
    @test_throws ArgumentError loo_refit_plan(data, (;
        flagged_loo_result...,
        n_observations = data.n - 1,
    ))
    @test_throws ArgumentError loo_refit_plan(data, (;
        flagged_loo_result...,
        pointwise = (;
            flagged_loo_result.pointwise...,
            pareto_k = [fill(0.1, data.n - 1)...],
        ),
    ))

    kfold_folds = [llmat[1:3, 1:2], llmat[4:6, 3:data.n]]
    kfold_observation_indices = [1:2, 3:data.n]
    kfold_result = kfold(kfold_folds;
        fold_ids = [:fold_a, :fold_b],
        observation_indices = kfold_observation_indices)
    manual_kfold_elpd = Float64[]
    for fold_loglik in kfold_folds
        for heldout_index in axes(fold_loglik, 2)
            push!(manual_kfold_elpd,
                test_logsumexp(@view fold_loglik[:, heldout_index]) -
                log(size(fold_loglik, 1)))
        end
    end
    manual_kfoldic = -2 .* manual_kfold_elpd
    @test kfold_result.criterion === :kfold
    @test kfold_result.method === :heldout_refit_log_score
    @test kfold_result.prediction_target === :heldout_observation_log_score
    @test kfold_result.n_folds == 2
    @test kfold_result.n_observations == data.n
    @test kfold_result.n_draws_by_fold == [3, 3]
    @test kfold_result.n_heldout_by_fold == [2, data.n - 2]
    @test kfold_result.folds == [:fold_a, :fold_b]
    @test kfold_result.observation_indices == collect(1:data.n)
    @test kfold_result.pointwise.elpd_heldout ≈ manual_kfold_elpd
    @test kfold_result.pointwise.kfoldic ≈ manual_kfoldic
    @test kfold_result.pointwise.fold ==
        vcat(fill(:fold_a, 2), fill(:fold_b, data.n - 2))
    @test kfold_result.pointwise.observation == collect(1:data.n)
    @test kfold_result.elpd_kfold ≈ sum(manual_kfold_elpd)
    @test kfold_result.kfoldic ≈ sum(manual_kfoldic)
    @test kfold_result.kfoldic ≈ -2 * kfold_result.elpd_kfold
    @test kfold_result.se_kfoldic ≈ 2 * kfold_result.se_elpd_kfold
    @test kfold_result.warning === :ok
    kfold_rows = kfold_diagnostics(kfold_result)
    @test length(kfold_rows) == data.n
    @test [row.heldout_index for row in kfold_rows] == collect(1:data.n)
    @test [row.observation for row in kfold_rows] == collect(1:data.n)
    @test [row.fold for row in kfold_rows] ==
        vcat(fill(:fold_a, 2), fill(:fold_b, data.n - 2))
    @test [row.elpd_heldout for row in kfold_rows] ≈ manual_kfold_elpd
    @test [row.kfoldic for row in kfold_rows] ≈ manual_kfoldic
    @test all(row -> row.criterion === :kfold, kfold_rows)
    @test all(row -> row.method === :heldout_refit_log_score, kfold_rows)
    @test all(row -> row.prediction_target === :heldout_observation_log_score,
        kfold_rows)
    @test all(row -> row.flag === :ok, kfold_rows)
    kfold_data_rows = kfold_diagnostics(design, kfold_result)
    @test [row.observation for row in kfold_data_rows] == collect(1:data.n)
    @test [row.person for row in kfold_data_rows] ==
        [data.person_levels[data.person[row]] for row in 1:data.n]
    @test [row.rater for row in kfold_data_rows] ==
        [data.rater_levels[data.rater[row]] for row in 1:data.n]
    @test [row.item for row in kfold_data_rows] ==
        [data.item_levels[data.item[row]] for row in 1:data.n]
    @test [row.score for row in kfold_data_rows] == data.score
    @test [row.category for row in kfold_data_rows] ==
        [data.category_levels[data.category[row]] for row in 1:data.n]
    @test all(row -> row.optional == NamedTuple(), kfold_data_rows)
    @test [row.elpd_heldout for row in kfold_diagnostics(spec, kfold_result)] ≈
        manual_kfold_elpd

    fold_plan = kfold_plan(data; k = 3)
    @test fold_plan.schema == "bayesianmgmfrm.kfold_plan.v1"
    @test fold_plan.object === :kfold_plan
    @test fold_plan.method === :deterministic_balanced_fold_plan
    @test fold_plan.comparison_contract === :same_heldout_observation_folds
    @test fold_plan.group_by === :observation
    @test fold_plan.k == 3
    @test fold_plan.n_folds == 3
    @test fold_plan.n_observations == data.n
    @test fold_plan.n_units == data.n
    @test fold_plan.folds == [1, 2, 3]
    @test fold_plan.n_heldout_by_fold == [3, 3, 3]
    @test fold_plan.refits_per_model_required == 3
    @test fold_plan.warning === :ok
    @test length(fold_plan.fold_rows) == 3
    @test fold_plan.heldout_observation_indices ==
        [row.heldout_observations for row in fold_plan.fold_rows]
    @test sort(vcat(fold_plan.heldout_observation_indices...)) == collect(1:data.n)
    @test sort(vcat([row.training_observations for row in fold_plan.fold_rows]...)) ==
        vcat(fill.(collect(1:data.n), 2)...)
    @test all(row -> row.n_heldout_observations == 3, fold_plan.fold_rows)
    @test all(row -> row.n_training_observations == data.n - 3, fold_plan.fold_rows)
    @test all(row -> row.n_heldout_units == 3, fold_plan.fold_rows)
    first_fold_training_table = facet_response_table(data;
        observations = fold_plan.fold_rows[1].training_observations)
    first_fold_heldout_table = facet_response_table(data;
        observations = fold_plan.fold_rows[1].heldout_observations)
    @test length(first_fold_training_table.score) ==
        fold_plan.fold_rows[1].n_training_observations
    @test length(first_fold_heldout_table.score) ==
        fold_plan.fold_rows[1].n_heldout_observations
    @test first_fold_heldout_table.person ==
        [data.person_levels[data.person[row]]
            for row in fold_plan.fold_rows[1].heldout_observations]
    planned_kfold_folds =
        [llmat[1:3, indices] for indices in fold_plan.heldout_observation_indices]
    planned_kfold = kfold(planned_kfold_folds;
        fold_ids = fold_plan.folds,
        observation_indices = fold_plan.heldout_observation_indices)
    @test planned_kfold.n_folds == fold_plan.n_folds
    @test planned_kfold.n_heldout_by_fold == fold_plan.n_heldout_by_fold
    @test planned_kfold.observation_indices == vcat(fold_plan.heldout_observation_indices...)
    fold_plan_diagnostics = kfold_plan_diagnostics(data, fold_plan)
    @test fold_plan_diagnostics.schema ==
        "bayesianmgmfrm.kfold_plan_diagnostics.v1"
    @test fold_plan_diagnostics.object === :kfold_plan_diagnostics
    @test fold_plan_diagnostics.plan_schema == fold_plan.schema
    @test fold_plan_diagnostics.group_by === :observation
    @test fold_plan_diagnostics.facets == (:person, :rater, :item, :category)
    @test fold_plan_diagnostics.n_rows ==
        fold_plan.n_folds * length(fold_plan_diagnostics.facets)
    @test fold_plan_diagnostics.n_blocking_rows ==
        count(row -> row.refit_blocker, fold_plan_diagnostics.rows)
    @test fold_plan_diagnostics.passed ==
        (fold_plan_diagnostics.n_blocking_rows == 0)
    @test all(row -> row.status in (:ok, :heldout_only_levels),
        fold_plan_diagnostics.rows)
    @test kfold_plan_diagnostics(spec, fold_plan; facets = :person).n_rows ==
        fold_plan.n_folds

    kfold_refit_person = String[]
    kfold_refit_rater = String[]
    kfold_refit_item = String[]
    kfold_refit_score = Int[]
    for block in 1:3, person_index in 1:3, rater_index in 1:2, item_index in 1:2
        push!(kfold_refit_person, "P$person_index")
        push!(kfold_refit_rater, "R$rater_index")
        push!(kfold_refit_item, "I$item_index")
        push!(kfold_refit_score, mod(block + person_index + rater_index + item_index, 2))
    end
    kfold_refit_data = FacetData(
        (;
            person = kfold_refit_person,
            rater = kfold_refit_rater,
            item = kfold_refit_item,
            score = kfold_refit_score,
        );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    kfold_refit_spec = mfrm_spec(kfold_refit_data)
    kfold_refit_design = getdesign(kfold_refit_spec)
    kfold_refit_init = zeros(length(kfold_refit_design.parameter_names))
    kfold_refit_plan_for_execution = kfold_plan(kfold_refit_data; k = 3)
    @test kfold_plan_diagnostics(
        kfold_refit_data,
        kfold_refit_plan_for_execution,
    ).passed

    executed_kfold = kfold_refit(
        kfold_refit_spec,
        kfold_refit_plan_for_execution;
        prior,
        backend = :julia,
        ndraws = 3,
        warmup = 2,
        chains = 1,
        step_size = 0.02,
        init = kfold_refit_init,
        seed = 121,
    )
    @test executed_kfold.schema == "bayesianmgmfrm.kfold_refit.v1"
    @test executed_kfold.object === :kfold_refit
    @test executed_kfold.criterion === :kfold
    @test executed_kfold.method === :heldout_refit_log_score
    @test executed_kfold.refit_method === :automatic_kfold_refit
    @test executed_kfold.plan_schema == "bayesianmgmfrm.kfold_plan.v1"
    @test executed_kfold.group_by === :observation
    @test executed_kfold.n_refits == kfold_refit_plan_for_execution.n_folds
    @test executed_kfold.n_folds == kfold_refit_plan_for_execution.n_folds
    @test executed_kfold.n_observations == kfold_refit_data.n
    @test executed_kfold.n_total_observations == kfold_refit_data.n
    @test executed_kfold.folds == kfold_refit_plan_for_execution.folds
    @test executed_kfold.observation_indices ==
        vcat(kfold_refit_plan_for_execution.heldout_observation_indices...)
    @test executed_kfold.n_draws_by_fold ==
        fill(3, kfold_refit_plan_for_execution.n_folds)
    @test executed_kfold.n_heldout_by_fold ==
        kfold_refit_plan_for_execution.n_heldout_by_fold
    @test length(executed_kfold.fold_logliks) ==
        kfold_refit_plan_for_execution.n_folds
    @test [size(matrix, 1) for matrix in executed_kfold.fold_logliks] ==
        fill(3, kfold_refit_plan_for_execution.n_folds)
    @test [size(matrix, 2) for matrix in executed_kfold.fold_logliks] ==
        kfold_refit_plan_for_execution.n_heldout_by_fold
    @test all(matrix -> all(isfinite, matrix), executed_kfold.fold_logliks)
    @test length(executed_kfold.fit_rows) == kfold_refit_plan_for_execution.n_folds
    @test [row.n_training_observations for row in executed_kfold.fit_rows] ==
        [row.n_training_observations for row in kfold_refit_plan_for_execution.fold_rows]
    @test [row.n_heldout_observations for row in executed_kfold.fit_rows] ==
        [row.n_heldout_observations for row in kfold_refit_plan_for_execution.fold_rows]
    @test executed_kfold.plan_diagnostics.passed
    @test isnothing(executed_kfold.fold_fits)
    @test executed_kfold.kfold_summary.criterion === :kfold

    executed_kfold_with_fits = kfold_refit(
        kfold_refit_design,
        kfold_refit_plan_for_execution;
        prior,
        return_fits = true,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init = kfold_refit_init,
        seed = 122,
    )
    @test length(executed_kfold_with_fits.fold_fits) ==
        kfold_refit_plan_for_execution.n_folds
    @test all(fold_fit -> fold_fit isa MFRMFit, executed_kfold_with_fits.fold_fits)

    kfold_refit_seed_fit = fit(
        kfold_refit_spec;
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init = kfold_refit_init,
        seed = 123,
    )
    executed_kfold_from_fit = kfold_refit(
        kfold_refit_seed_fit,
        kfold_refit_plan_for_execution;
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init = kfold_refit_init,
        seed = 124,
    )
    @test executed_kfold_from_fit.object === :kfold_refit
    @test executed_kfold_from_fit.n_refits == kfold_refit_plan_for_execution.n_folds
    @test executed_kfold_from_fit.n_observations == kfold_refit_data.n

    gmfrm_refit_spec = mfrm_spec(
        kfold_refit_data;
        family = :gmfrm,
        discrimination = :rater,
    )
    @test_throws ArgumentError kfold_refit(
        gmfrm_refit_spec,
        kfold_refit_plan_for_execution;
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
        seed = 128,
    )
    executed_gmfrm_kfold = kfold_refit(
        gmfrm_refit_spec,
        kfold_refit_plan_for_execution;
        experimental = true,
        return_fits = true,
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
        seed = 129,
    )
    @test executed_gmfrm_kfold.object === :kfold_refit
    @test executed_gmfrm_kfold.n_refits == kfold_refit_plan_for_execution.n_folds
    @test executed_gmfrm_kfold.n_observations == kfold_refit_data.n
    @test all(row -> row.family === :gmfrm, executed_gmfrm_kfold.fit_rows)
    @test all(row -> row.experimental, executed_gmfrm_kfold.fit_rows)
    @test [size(matrix, 1) for matrix in executed_gmfrm_kfold.fold_logliks] ==
        fill(1, kfold_refit_plan_for_execution.n_folds)
    @test [size(matrix, 2) for matrix in executed_gmfrm_kfold.fold_logliks] ==
        kfold_refit_plan_for_execution.n_heldout_by_fold
    @test all(matrix -> all(isfinite, matrix), executed_gmfrm_kfold.fold_logliks)
    @test all(fold_fit -> fold_fit isa GMFRMFit, executed_gmfrm_kfold.fold_fits)

    mgmfrm_refit_spec = mfrm_spec(
        kfold_refit_data;
        family = :mgmfrm,
        dimensions = 2,
        q_matrix = Bool[1 0; 0 1],
    )
    mgmfrm_refit_loo_plan = loo_refit_plan(kfold_refit_data; observations = [1])
    @test_throws ArgumentError loo_refit(
        mgmfrm_refit_spec,
        mgmfrm_refit_loo_plan;
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
        seed = 130,
    )
    executed_mgmfrm_loo = loo_refit(
        mgmfrm_refit_spec,
        mgmfrm_refit_loo_plan;
        experimental = true,
        return_fits = true,
        backend = :advancedhmc,
        ndraws = 1,
        warmup = 0,
        chains = 1,
        step_size = 0.02,
        max_depth = 1,
        metric = :unit,
        seed = 131,
    )
    @test executed_mgmfrm_loo.object === :loo_refit
    @test executed_mgmfrm_loo.n_refits == 1
    @test executed_mgmfrm_loo.n_observations == 1
    @test only(executed_mgmfrm_loo.fit_rows).family === :mgmfrm
    @test only(executed_mgmfrm_loo.fit_rows).experimental
    @test all(matrix -> size(matrix) == (1, 1), executed_mgmfrm_loo.fold_logliks)
    @test all(matrix -> all(isfinite, matrix), executed_mgmfrm_loo.fold_logliks)
    @test only(executed_mgmfrm_loo.fold_fits) isa MGMFRMFit

    executed_kfold_comparison = kfold_refit_comparison(
        :spec => kfold_refit_spec,
        :design => kfold_refit_design;
        plan = kfold_refit_plan_for_execution,
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init = kfold_refit_init,
        seed = 126,
    )
    @test executed_kfold_comparison.schema ==
        "bayesianmgmfrm.kfold_refit_comparison.v1"
    @test executed_kfold_comparison.object === :kfold_refit_comparison
    @test executed_kfold_comparison.criterion === :kfold
    @test executed_kfold_comparison.refit_method === :automatic_kfold_refit
    @test executed_kfold_comparison.comparison_contract ===
        :same_heldout_observation_folds
    @test executed_kfold_comparison.plan_schema ==
        kfold_refit_plan_for_execution.schema
    @test executed_kfold_comparison.models == ("spec", "design")
    @test executed_kfold_comparison.n_refits_per_model ==
        fill(kfold_refit_plan_for_execution.n_folds, 2)
    @test executed_kfold_comparison.n_total_refits ==
        2 * kfold_refit_plan_for_execution.n_folds
    @test executed_kfold_comparison.n_observations == kfold_refit_data.n
    @test executed_kfold_comparison.n_total_observations == kfold_refit_data.n
    @test executed_kfold_comparison.folds == kfold_refit_plan_for_execution.folds
    @test executed_kfold_comparison.observation_indices ==
        vcat(kfold_refit_plan_for_execution.heldout_observation_indices...)
    @test length(executed_kfold_comparison.refit_rows) == 2
    @test all(row -> row.plan_diagnostics_passed,
        executed_kfold_comparison.refit_rows)
    @test length(executed_kfold_comparison.comparison_rows) == 2
    @test Set(row.model for row in executed_kfold_comparison.comparison_rows) ==
        Set(["spec", "design"])
    @test all(row -> row.criterion === :kfold,
        executed_kfold_comparison.comparison_rows)
    @test all(row -> row.n_draws_by_fold ==
        fill(2, kfold_refit_plan_for_execution.n_folds),
        executed_kfold_comparison.comparison_rows)
    @test sum(row.relative_weight
        for row in executed_kfold_comparison.comparison_rows) ≈ 1.0
    @test length(executed_kfold_comparison.sensitivity_rows) == 2
    @test all(row -> row.sensitivity_axis === :model,
        executed_kfold_comparison.sensitivity_rows)
    @test all(row -> row.baseline_model == "spec",
        executed_kfold_comparison.sensitivity_rows)
    @test isnothing(executed_kfold_comparison.refits)
    @test executed_kfold_comparison.warning === :ok

    loo_refit_comparison_plan = loo_refit_plan(kfold_refit_data; observations = [1])
    executed_loo_comparison = loo_refit_comparison(
        kfold_refit_spec,
        kfold_refit_design;
        names = [:spec, :design],
        plan = loo_refit_comparison_plan,
        prior,
        return_refits = true,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        init = kfold_refit_init,
        seed = 127,
    )
    @test executed_loo_comparison.schema ==
        "bayesianmgmfrm.loo_refit_comparison.v1"
    @test executed_loo_comparison.object === :loo_refit_comparison
    @test executed_loo_comparison.criterion === :kfold
    @test executed_loo_comparison.refit_method ===
        :exact_leave_one_observation_out_refit
    @test executed_loo_comparison.models == ("spec", "design")
    @test executed_loo_comparison.n_refits_per_model == [1, 1]
    @test executed_loo_comparison.n_total_refits == 2
    @test executed_loo_comparison.n_observations == 1
    @test executed_loo_comparison.n_total_observations == kfold_refit_data.n
    @test executed_loo_comparison.observation_indices == [1]
    @test length(executed_loo_comparison.comparison_rows) == 2
    @test all(row -> row.n_folds == 1, executed_loo_comparison.comparison_rows)
    @test length(executed_loo_comparison.sensitivity_rows) == 2
    @test length(executed_loo_comparison.refits) == 2
    @test all(refit -> refit.object === :loo_refit, executed_loo_comparison.refits)
    @test executed_loo_comparison.warning === :ok

    @test_throws ArgumentError kfold_refit_comparison(
        :only => kfold_refit_spec;
        plan = kfold_refit_plan_for_execution)
    @test_throws ArgumentError kfold_refit_comparison(
        :bad => waic_result,
        :good => kfold_refit_spec;
        plan = kfold_refit_plan_for_execution)
    @test_throws ArgumentError kfold_refit_comparison(
        :spec => kfold_refit_spec,
        :design => kfold_refit_design;
        plan = kfold_refit_plan_for_execution,
        k = 2)
    @test_throws ArgumentError loo_refit_comparison(
        :only => kfold_refit_spec;
        plan = loo_refit_comparison_plan)

    person_fold_plan = kfold_plan(design; k = 3, group_by = :person,
        fold_ids = [:person_a, :person_b, :person_c])
    @test person_fold_plan.group_by === :person
    @test person_fold_plan.folds == [:person_a, :person_b, :person_c]
    @test person_fold_plan.n_units == length(data.person_levels)
    @test person_fold_plan.n_heldout_by_fold == [3, 3, 3]
    @test sort(vcat(person_fold_plan.heldout_observation_indices...)) == collect(1:data.n)
    for person_index in eachindex(data.person_levels)
        observations = findall(==(person_index), data.person)
        @test length(unique(person_fold_plan.observation_fold[observations])) == 1
    end
    @test all(row -> row.n_heldout_units == 1, person_fold_plan.fold_rows)
    @test kfold_plan(spec; k = 3).heldout_observation_indices ==
        fold_plan.heldout_observation_indices
    person_fold_diagnostics = kfold_plan_diagnostics(design, person_fold_plan)
    @test person_fold_diagnostics.warning === :heldout_only_levels
    @test !person_fold_diagnostics.passed
    person_a_person_row = only(row for row in person_fold_diagnostics.rows
        if row.fold === :person_a && row.facet === :person)
    @test person_a_person_row.refit_blocker
    @test person_a_person_row.status === :heldout_only_levels
    @test person_a_person_row.heldout_only_levels == (data.person_levels[1],)
    @test person_a_person_row.n_training_levels == length(data.person_levels) - 1
    @test person_a_person_row.n_heldout_levels == 1
    @test person_a_person_row.training_levels ==
        Tuple(data.person_levels[2:end])
    @test person_a_person_row.heldout_levels == (data.person_levels[1],)
    @test_throws ArgumentError kfold_refit(
        blocked_loo_spec,
        kfold_plan(blocked_loo_data; k = 2, group_by = :person);
        prior,
        backend = :julia,
        ndraws = 2,
        warmup = 1,
        chains = 1,
        step_size = 0.02,
        seed = 125,
    )

    optional_cv_data = FacetData((
            examinee = ["E1", "E1", "E2", "E2"],
            rater = ["R1", "R2", "R1", "R2"],
            item = ["I1", "I2", "I1", "I2"],
            score = [0, 1, 1, 2],
            group = ["G1", "G1", "G2", "G2"],
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
        group = :group)
    optional_fold_plan = kfold_plan(optional_cv_data; k = 2, group_by = :group)
    @test optional_fold_plan.group_by === :group
    @test optional_fold_plan.n_units == 2
    @test optional_fold_plan.n_heldout_by_fold == [2, 2]
    optional_fold_diagnostics =
        kfold_plan_diagnostics(optional_cv_data, optional_fold_plan)
    @test optional_fold_diagnostics.facets ==
        (:person, :rater, :item, :category, :group)
    group_diagnostic_rows = filter(row -> row.facet === :group,
        optional_fold_diagnostics.rows)
    @test length(group_diagnostic_rows) == optional_fold_plan.n_folds
    @test all(row -> row.refit_blocker, group_diagnostic_rows)
    @test all(row -> row.n_heldout_only_levels == 1, group_diagnostic_rows)
    for group_index in eachindex(optional_cv_data.optional_levels[:group])
        observations = findall(==(group_index), optional_cv_data.optional[:group])
        @test length(unique(optional_fold_plan.observation_fold[observations])) == 1
    end
    shuffled_fold_plan = kfold_plan(data; k = 3, shuffle = true, rng = MersenneTwister(2026))
    @test shuffled_fold_plan.method === :randomized_balanced_fold_plan
    @test sort(vcat(shuffled_fold_plan.heldout_observation_indices...)) == collect(1:data.n)
    @test_throws ArgumentError kfold_plan(data; k = 1)
    @test_throws ArgumentError kfold_plan(data; k = data.n + 1)
    @test_throws ArgumentError kfold_plan(data; k = 3, group_by = :item)
    @test_throws ArgumentError kfold_plan(data; k = 2, group_by = :missing_role)
    @test_throws ArgumentError kfold_plan(data; k = 2, fold_ids = [:dup, :dup])
    @test_throws ArgumentError kfold_plan_diagnostics(data, fold_plan;
        facets = (:person, :person))
    @test_throws ArgumentError kfold_plan_diagnostics(data, fold_plan;
        facets = :missing_role)
    @test_throws ArgumentError kfold_plan_diagnostics(optional_cv_data, fold_plan)

    single_fold_kfold = kfold(llmat[1:3, 1:2];
        fold_ids = [:only],
        observation_indices = [:obs1, :obs2])
    @test single_fold_kfold.n_folds == 1
    @test single_fold_kfold.folds == [:only]
    @test single_fold_kfold.observation_indices == [:obs1, :obs2]
    @test_throws ArgumentError kfold_diagnostics(data, single_fold_kfold)
    @test_throws ArgumentError kfold_diagnostics(waic_result)

    shifted_kfold = kfold([fold_loglik .- 0.5 for fold_loglik in kfold_folds];
        fold_ids = [:fold_a, :fold_b],
        observation_indices = kfold_observation_indices)
    kfold_comparison = compare_kfold(:main => kfold_result, :shifted => shifted_kfold)
    @test length(kfold_comparison) == 2
    @test [row.model for row in kfold_comparison] == ["main", "shifted"]
    @test [row.rank for row in kfold_comparison] == [1, 2]
    @test all(row -> row.criterion === :kfold, kfold_comparison)
    @test all(row -> row.comparison_contract ===
        :same_heldout_observation_folds, kfold_comparison)
    @test all(row -> row.method === :heldout_refit_log_score, kfold_comparison)
    @test all(row -> row.prediction_target === :heldout_observation_log_score,
        kfold_comparison)
    @test kfold_comparison[1].elpd_difference ≈ 0.0
    @test kfold_comparison[1].kfoldic_difference ≈ 0.0
    @test kfold_comparison[2].elpd_difference ≈ -0.5 * data.n
    @test kfold_comparison[2].kfoldic_difference ≈ data.n
    @test sum(row.relative_weight for row in kfold_comparison) ≈ 1.0
    @test kfold_comparison[1].relative_weight >= kfold_comparison[2].relative_weight
    @test all(row -> row.n_folds == 2, kfold_comparison)
    @test all(row -> row.n_observations == data.n, kfold_comparison)
    @test all(row -> row.n_draws_by_fold == [3, 3], kfold_comparison)
    @test all(row -> row.n_heldout_by_fold == [2, data.n - 2], kfold_comparison)
    @test all(row -> row.folds == [:fold_a, :fold_b], kfold_comparison)
    @test all(row -> row.observation_indices == collect(1:data.n), kfold_comparison)
    kfold_stats = Dict("main" => kfold_result, "shifted" => shifted_kfold)
    best_kfold_stat = kfold_stats[kfold_comparison[1].model]
    best_kfold_elpd = best_kfold_stat.elpd_kfold
    manual_kfold_weights = Dict(
        name => exp(stat.elpd_kfold - best_kfold_elpd)
        for (name, stat) in kfold_stats
    )
    manual_kfold_weight_total = sum(values(manual_kfold_weights))
    for row in kfold_comparison
        stat = kfold_stats[row.model]
        pointwise_difference = stat.pointwise.elpd_heldout .-
            best_kfold_stat.pointwise.elpd_heldout
        @test row.elpd_kfold ≈ stat.elpd_kfold
        @test row.elpd_difference ≈ stat.elpd_kfold - best_kfold_stat.elpd_kfold
        @test row.se_elpd_difference ≈
            sqrt(length(pointwise_difference) *
                test_sample_variance(pointwise_difference))
        @test row.se_elpd_kfold ≈ stat.se_elpd_kfold
        @test row.kfoldic ≈ stat.kfoldic
        @test row.kfoldic_difference ≈ stat.kfoldic - best_kfold_stat.kfoldic
        @test row.se_kfoldic ≈ stat.se_kfoldic
        @test row.relative_weight ≈
            manual_kfold_weights[row.model] / manual_kfold_weight_total
        @test row.warning === stat.warning
    end
    named_kfold_comparison = compare_kfold(kfold_result, shifted_kfold;
        names = [:main, :shifted])
    @test [row.model for row in named_kfold_comparison] ==
        [row.model for row in kfold_comparison]
    @test [row.kfoldic for row in named_kfold_comparison] ≈
        [row.kfoldic for row in kfold_comparison]
    kfold_sensitivity = kfold_sensitivity_comparison(
        :main => kfold_result,
        :shifted => shifted_kfold;
        axis = :thresholds,
        values = (main = :partial_credit, shifted = :rating_scale),
        baseline = :main)
    @test length(kfold_sensitivity) == 2
    @test [row.model for row in kfold_sensitivity] ==
        [row.model for row in kfold_comparison]
    @test all(row -> row.criterion === :kfold, kfold_sensitivity)
    @test all(row -> row.sensitivity_axis === :thresholds,
        kfold_sensitivity)
    @test Set(row.sensitivity_value for row in kfold_sensitivity) ==
        Set([:partial_credit, :rating_scale])
    kfold_sensitivity_baseline = only(row for row in kfold_sensitivity
        if row.model == "main")
    kfold_sensitivity_candidate = only(row for row in kfold_sensitivity
        if row.model == "shifted")
    @test kfold_sensitivity_baseline.is_baseline
    @test !kfold_sensitivity_candidate.is_baseline
    @test kfold_sensitivity_candidate.sensitivity_contrast ==
        (candidate = :rating_scale, baseline = :partial_credit)
    @test kfold_sensitivity_baseline.elpd_difference_from_baseline ≈ 0.0
    @test kfold_sensitivity_baseline.information_criterion_difference_from_baseline ≈ 0.0
    @test kfold_sensitivity_candidate.elpd_difference_from_baseline ≈
        kfold_sensitivity_candidate.elpd_kfold - kfold_sensitivity_baseline.elpd_kfold
    @test kfold_sensitivity_candidate.information_criterion_difference_from_baseline ≈
        kfold_sensitivity_candidate.kfoldic - kfold_sensitivity_baseline.kfoldic
    model_axis_kfold_sensitivity =
        kfold_sensitivity_comparison(kfold_result, shifted_kfold;
            names = [:main, :shifted])
    @test [row.sensitivity_value for row in model_axis_kfold_sensitivity] ==
        ["main", "shifted"]
    @test sensitivity_comparison_summary(
        NamedTuple[kfold_sensitivity...];
        required_axes = (:thresholds,)).passed
    mismatched_kfold_observations = kfold(kfold_folds;
        fold_ids = [:fold_a, :fold_b],
        observation_indices = reverse(collect(1:data.n)))
    mismatched_kfold_folds = kfold(kfold_folds;
        fold_ids = [:fold_b, :fold_a],
        observation_indices = kfold_observation_indices)
    @test_throws ArgumentError kfold(Any[kfold_folds[1], [1, 2, 3]])
    @test_throws ArgumentError kfold([zeros(0, 1)])
    @test_throws ArgumentError kfold([0.0 Inf; 1.0 2.0])
    @test_throws ArgumentError kfold(kfold_folds; fold_ids = [:only])
    @test_throws ArgumentError kfold(kfold_folds; fold_ids = [:dup, :dup])
    @test_throws ArgumentError kfold(kfold_folds; observation_indices = [1, 2])
    @test_throws ArgumentError kfold(kfold_folds;
        observation_indices = vcat(1:(data.n - 1), data.n - 1))
    @test_throws ArgumentError kfold(kfold_folds; observation_indices = [1:1, 3:data.n])
    @test_throws ArgumentError compare_kfold()
    @test_throws ArgumentError compare_kfold(kfold_result)
    @test_throws ArgumentError compare_kfold(kfold_result, shifted_kfold;
        names = [:only])
    @test_throws ArgumentError compare_kfold(kfold_result, shifted_kfold;
        names = [:dup, :dup])
    @test_throws ArgumentError compare_kfold(:main => kfold_result,
        :bad => mismatched_kfold_observations)
    @test_throws ArgumentError compare_kfold(:main => kfold_result,
        :bad => mismatched_kfold_folds)
    @test_throws ArgumentError compare_kfold(:bad => waic_result,
        :good => kfold_result)
    @test_throws ArgumentError kfold_sensitivity_comparison(kfold_result)
    @test_throws ArgumentError kfold_sensitivity_comparison(kfold_result,
        shifted_kfold; names = [:only])
    @test_throws ArgumentError kfold_sensitivity_comparison(kfold_result,
        shifted_kfold; names = [:main, :shifted], axis = :thresholds)
    @test_throws ArgumentError kfold_sensitivity_comparison(:bad => waic_result,
        :good => kfold_result)

    waic_rows = waic_diagnostics(result; draw_indices = [1, 2, 3])
    @test length(waic_rows) == data.n
    @test [row.observation for row in waic_rows] == collect(1:data.n)
    @test [row.person for row in waic_rows] == [data.person_levels[index] for index in data.person]
    @test [row.rater for row in waic_rows] == [data.rater_levels[index] for index in data.rater]
    @test [row.item for row in waic_rows] == [data.item_levels[index] for index in data.item]
    @test [row.score for row in waic_rows] == data.score
    @test [row.category for row in waic_rows] == [data.category_levels[index] for index in data.category]
    @test all(row -> row.optional == NamedTuple(), waic_rows)
    @test [row.lppd for row in waic_rows] ≈ waic_result.pointwise.lppd
    @test [row.p_waic for row in waic_rows] ≈ waic_result.pointwise.p_waic
    @test [row.elpd_waic for row in waic_rows] ≈ waic_result.pointwise.elpd_waic
    @test [row.waic for row in waic_rows] ≈ waic_result.pointwise.waic
    @test all(row -> row.threshold == 0.4, waic_rows)
    @test all(row -> row.flag === (row.p_waic > 0.4 ? :high_loglik_variance : :ok),
        waic_rows)
    flagged_waic_rows = waic_diagnostics(result; draw_indices = [1, 2, 3], only_flagged = true)
    @test length(flagged_waic_rows) == waic_result.high_variance_count
    @test all(row -> row.flag === :high_loglik_variance, flagged_waic_rows)
    loglik_waic_rows = waic_diagnostics(llmat[1:3, :])
    @test [row.p_waic for row in loglik_waic_rows] ≈ waic_result.pointwise.p_waic
    @test !hasproperty(loglik_waic_rows[1], :person)
    @test_throws ArgumentError waic_diagnostics(result; threshold = -0.1)
    @test_throws ArgumentError waic_diagnostics(llmat[1:1, :])

    loo_rows = loo_diagnostics(result; draw_indices = loo_indices)
    @test length(loo_rows) == data.n
    @test [row.observation for row in loo_rows] == collect(1:data.n)
    @test [row.person for row in loo_rows] == [data.person_levels[index] for index in data.person]
    @test [row.rater for row in loo_rows] == [data.rater_levels[index] for index in data.rater]
    @test [row.item for row in loo_rows] == [data.item_levels[index] for index in data.item]
    @test [row.score for row in loo_rows] == data.score
    @test [row.category for row in loo_rows] == [data.category_levels[index] for index in data.category]
    @test all(row -> row.optional == NamedTuple(), loo_rows)
    @test all(row -> row.criterion === :loo, loo_rows)
    @test all(row -> row.method === :raw_importance_sampling, loo_rows)
    @test all(row -> row.psis_smoothing === false, loo_rows)
    @test [row.lppd for row in loo_rows] ≈ loo_result.pointwise.lppd
    @test [row.p_loo for row in loo_rows] ≈ loo_result.pointwise.p_loo
    @test [row.elpd_loo for row in loo_rows] ≈ loo_result.pointwise.elpd_loo
    @test [row.looic for row in loo_rows] ≈ loo_result.pointwise.looic
    @test [row.pareto_k for row in loo_rows] ≈ loo_result.pointwise.pareto_k
    @test [row.effective_sample_size for row in loo_rows] ≈
        loo_result.pointwise.effective_sample_size
    @test [row.tail_draws for row in loo_rows] ==
        loo_result.pointwise.tail_draws
    @test all(row -> row.threshold == 0.7, loo_rows)
    @test all(row -> row.flag ===
        (row.pareto_k > 0.7 ? :high_pareto_k : :ok), loo_rows)
    flagged_loo_rows = loo_diagnostics(result;
        draw_indices = loo_indices,
        only_flagged = true)
    @test length(flagged_loo_rows) == loo_result.bad_pareto_k_count
    @test all(row -> row.flag === :high_pareto_k, flagged_loo_rows)
    loglik_loo_rows = loo_diagnostics(loo_loglik)
    @test [row.pareto_k for row in loglik_loo_rows] ≈
        loo_result.pointwise.pareto_k
    @test !hasproperty(loglik_loo_rows[1], :person)
    psis_loo_rows = loo_diagnostics(result;
        draw_indices = loo_indices,
        psis_smoothing = true)
    @test length(psis_loo_rows) == data.n
    @test all(row -> row.criterion === :loo, psis_loo_rows)
    @test all(row -> row.method === :pareto_smoothed_importance_sampling,
        psis_loo_rows)
    @test all(row -> row.psis_smoothing === true, psis_loo_rows)
    @test [row.lppd for row in psis_loo_rows] ≈ psis_result.pointwise.lppd
    @test [row.p_loo for row in psis_loo_rows] ≈ psis_result.pointwise.p_loo
    @test [row.elpd_loo for row in psis_loo_rows] ≈
        psis_result.pointwise.elpd_loo
    @test [row.looic for row in psis_loo_rows] ≈ psis_result.pointwise.looic
    @test [row.pareto_k for row in psis_loo_rows] ≈
        psis_result.pointwise.pareto_k
    @test [row.effective_sample_size for row in psis_loo_rows] ≈
        psis_result.pointwise.effective_sample_size
    @test all(row -> row.flag ===
        (row.pareto_k > 0.7 ? :high_pareto_k : :ok), psis_loo_rows)
    @test_throws ArgumentError loo_diagnostics(result; threshold = -0.1)
    @test_throws ArgumentError loo_diagnostics(llmat[1:2, :])

    comparison = compare_models(result, spec_result; names = [:main, :short], draw_indices = [1, 2])
    comparison_stats = Dict(
        "main" => waic(result; draw_indices = [1, 2]),
        "short" => waic(spec_result; draw_indices = [1, 2]),
    )
    best_stat = comparison_stats[comparison[1].model]
    @test length(comparison) == 2
    @test [row.rank for row in comparison] == [1, 2]
    @test comparison[1].elpd_waic >= comparison[2].elpd_waic
    @test comparison[1].elpd_difference ≈ 0.0
    @test comparison[1].waic_difference ≈ 0.0
    @test comparison[2].elpd_difference <= 0
    @test comparison[2].waic_difference >= 0
    @test sum(row.relative_weight for row in comparison) ≈ 1.0
    @test comparison[1].relative_weight >= comparison[2].relative_weight
    @test all(row -> row.criterion === :waic, comparison)
    @test all(row -> row.comparison_contract ===
        :same_observation_data_same_latent_dimensions, comparison)
    @test all(row -> row.model_family === :mfrm, comparison)
    @test all(row -> row.thresholds === spec.thresholds, comparison)
    @test all(row -> row.dimensions == spec.dimensions, comparison)
    @test all(row -> row.discrimination === spec.discrimination, comparison)
    @test all(row -> row.q_matrix === nothing, comparison)
    @test all(row -> row.estimation_status === spec.estimation_status, comparison)
    @test all(row -> row.data_signature == spec.validation.data_signature, comparison)
    @test all(row -> row.n_categories == length(data.category_levels), comparison)
    @test all(row -> row.category_levels == data.category_levels, comparison)
    @test all(row -> row.n_persons == length(data.person_levels), comparison)
    @test all(row -> row.n_raters == length(data.rater_levels), comparison)
    @test all(row -> row.n_items == length(data.item_levels), comparison)
    @test all(row -> row.optional_facets == Symbol[], comparison)
    @test all(row -> row.n_observations == data.n, comparison)
    best_elpd = best_stat.elpd_waic
    manual_weights = Dict(
        name => exp(stat.elpd_waic - best_elpd)
        for (name, stat) in comparison_stats
    )
    manual_weight_total = sum(values(manual_weights))
    for row in comparison
        stat = comparison_stats[row.model]
        pointwise_difference = stat.pointwise.elpd_waic .- best_stat.pointwise.elpd_waic
        @test row.elpd_waic ≈ stat.elpd_waic
        @test row.elpd_difference ≈ stat.elpd_waic - best_stat.elpd_waic
        @test row.se_elpd_difference ≈ sqrt(length(pointwise_difference) * test_sample_variance(pointwise_difference))
        @test row.waic ≈ stat.waic
        @test row.waic_difference ≈ stat.waic - best_stat.waic
        @test row.p_waic ≈ stat.p_waic
        @test row.lppd ≈ stat.lppd
        @test row.relative_weight ≈ manual_weights[row.model] / manual_weight_total
        @test row.high_variance_count == stat.high_variance_count
        @test row.warning === stat.warning
    end
    pair_comparison = compare_models(:main => result, :short => spec_result; draw_indices = [1, 2])
    @test [row.model for row in pair_comparison] == [row.model for row in comparison]
    @test [row.waic for row in pair_comparison] ≈ [row.waic for row in comparison]

    threshold_sensitivity = sensitivity_comparison(
        :partial_credit => spec_result,
        :rating_scale => rsm_result;
        axis = :thresholds,
        baseline = :partial_credit,
        draw_indices = [1, 2])
    @test length(threshold_sensitivity) == 2
    @test [row.rank for row in threshold_sensitivity] == [1, 2]
    @test all(row -> row.sensitivity_axis === :thresholds, threshold_sensitivity)
    @test Set(row.sensitivity_value for row in threshold_sensitivity) ==
        Set([:partial_credit, :rating_scale])
    threshold_baseline = only(filter(row -> row.model == "partial_credit",
        threshold_sensitivity))
    threshold_candidate = only(filter(row -> row.model == "rating_scale",
        threshold_sensitivity))
    @test threshold_baseline.is_baseline
    @test !threshold_candidate.is_baseline
    @test threshold_baseline.baseline_model == "partial_credit"
    @test threshold_candidate.baseline_model == "partial_credit"
    @test threshold_baseline.baseline_value === :partial_credit
    @test threshold_candidate.baseline_value === :partial_credit
    @test threshold_baseline.contrast === :baseline
    @test threshold_candidate.contrast === :candidate_vs_baseline
    @test threshold_candidate.sensitivity_contrast ==
        (candidate = :rating_scale, baseline = :partial_credit)
    @test threshold_baseline.elpd_difference_from_baseline ≈ 0.0
    @test threshold_baseline.information_criterion_difference_from_baseline ≈ 0.0
    @test threshold_candidate.elpd_difference_from_baseline ≈
        threshold_candidate.elpd_waic - threshold_baseline.elpd_waic
    @test threshold_candidate.information_criterion_difference_from_baseline ≈
        threshold_candidate.waic - threshold_baseline.waic

    prior_sensitivity = sensitivity_comparison(result, spec_result;
        names = [:main, :short],
        axis = :prior,
        baseline = :main,
        draw_indices = [1, 2])
    @test all(row -> row.sensitivity_axis === :prior, prior_sensitivity)
    @test all(row -> row.baseline_model == "main", prior_sensitivity)
    @test all(row -> row.sensitivity_value.person_sd == prior.person_sd,
        prior_sensitivity)
    manual_logprior_draws = [
        logprior(design, view(result.draws, index, :), prior)
        for index in loo_indices
    ]
    manual_loglikelihood_draws = [
        sum(@view llmat[index, :])
        for index in loo_indices
    ]
    power_sensitivity = prior_likelihood_sensitivity(result;
        prior_powers = [1.0, 0.8],
        likelihood_powers = [1.0, 1.2],
        draw_indices = loo_indices)
    vector_power_sensitivity = prior_likelihood_sensitivity(
        manual_logprior_draws,
        manual_loglikelihood_draws;
        prior_powers = [1.0, 0.8],
        likelihood_powers = [1.0, 1.2])
    @test power_sensitivity.schema ==
        "bayesianmgmfrm.prior_likelihood_sensitivity.v1"
    @test power_sensitivity.object === :prior_likelihood_sensitivity
    @test power_sensitivity.method === :self_normalized_importance_reweighting
    @test power_sensitivity.comparison_scope === :local_power_scaling_grid
    @test power_sensitivity.input === :fit_object
    @test power_sensitivity.model_family === :mfrm
    @test power_sensitivity.n_draws == length(loo_indices)
    @test power_sensitivity.n_total_draws == size(result.draws, 1)
    @test power_sensitivity.n_cells == 4
    @test power_sensitivity.prior_powers == (1.0, 0.8)
    @test power_sensitivity.likelihood_powers == (1.0, 1.2)
    @test power_sensitivity.baseline_mean_logprior ≈
        sum(manual_logprior_draws) / length(manual_logprior_draws)
    @test power_sensitivity.baseline_mean_loglikelihood ≈
        sum(manual_loglikelihood_draws) / length(manual_loglikelihood_draws)
    @test power_sensitivity.min_effective_sample_size == 1.0
    @test vector_power_sensitivity.input === :draw_level_log_terms
    @test vector_power_sensitivity.n_cells == power_sensitivity.n_cells
    @test vector_power_sensitivity.baseline_mean_logprior ≈
        power_sensitivity.baseline_mean_logprior
    @test vector_power_sensitivity.baseline_mean_loglikelihood ≈
        power_sensitivity.baseline_mean_loglikelihood
    scalar_power_sensitivity = prior_likelihood_sensitivity(
        manual_logprior_draws,
        manual_loglikelihood_draws;
        prior_powers = 1.0,
        likelihood_powers = 1.0)
    @test scalar_power_sensitivity.n_cells == 1
    @test scalar_power_sensitivity.prior_powers == (1.0,)
    @test scalar_power_sensitivity.likelihood_powers == (1.0,)
    baseline_power_cell = only(row for row in power_sensitivity.rows
        if row.prior_power == 1.0 && row.likelihood_power == 1.0)
    @test baseline_power_cell.log_normalizing_ratio ≈ 0.0
    @test baseline_power_cell.effective_sample_size ≈ length(loo_indices)
    @test baseline_power_cell.effective_sample_size_ratio ≈ 1.0
    @test baseline_power_cell.weighted_mean_logprior ≈
        power_sensitivity.baseline_mean_logprior
    @test baseline_power_cell.weighted_mean_loglikelihood ≈
        power_sensitivity.baseline_mean_loglikelihood
    @test baseline_power_cell.logprior_mean_shift ≈ 0.0 atol = 1e-12
    @test baseline_power_cell.loglikelihood_mean_shift ≈ 0.0 atol = 1e-12
    target_power_cell = only(row for row in power_sensitivity.rows
        if row.prior_power == 0.8 && row.likelihood_power == 1.2)
    manual_log_weights = [
        (target_power_cell.prior_power - 1.0) * manual_logprior_draws[index] +
        (target_power_cell.likelihood_power - 1.0) * manual_loglikelihood_draws[index]
        for index in eachindex(manual_logprior_draws)
    ]
    manual_log_weight_total = test_logsumexp(manual_log_weights)
    manual_weights = exp.(manual_log_weights .- manual_log_weight_total)
    manual_weighted_logprior = sum(manual_weights .* manual_logprior_draws)
    manual_weighted_loglikelihood =
        sum(manual_weights .* manual_loglikelihood_draws)
    manual_ess = 1 / sum(weight^2 for weight in manual_weights)
    @test target_power_cell.log_normalizing_ratio ≈
        manual_log_weight_total - log(length(loo_indices))
    @test target_power_cell.effective_sample_size ≈ manual_ess
    @test target_power_cell.weighted_mean_logprior ≈ manual_weighted_logprior
    @test target_power_cell.weighted_mean_loglikelihood ≈
        manual_weighted_loglikelihood
    @test target_power_cell.logprior_mean_shift ≈
        manual_weighted_logprior - power_sensitivity.baseline_mean_logprior
    @test target_power_cell.loglikelihood_mean_shift ≈
        manual_weighted_loglikelihood -
        power_sensitivity.baseline_mean_loglikelihood
    @test power_sensitivity.min_effective_sample_size_observed ≈
        minimum(row.effective_sample_size for row in power_sensitivity.rows)
    @test power_sensitivity.max_abs_logprior_mean_shift ≈
        maximum(row.abs_logprior_mean_shift for row in power_sensitivity.rows)
    @test power_sensitivity.max_abs_loglikelihood_mean_shift ≈
        maximum(row.abs_loglikelihood_mean_shift for row in power_sensitivity.rows)
    high_threshold_power_sensitivity = prior_likelihood_sensitivity(
        manual_logprior_draws,
        manual_loglikelihood_draws;
        prior_powers = [1.0],
        likelihood_powers = [1.0],
        min_effective_sample_size = length(loo_indices) + 1)
    @test high_threshold_power_sensitivity.warning === :low_effective_sample_size
    @test high_threshold_power_sensitivity.low_effective_sample_size_count == 1
    @test_throws ArgumentError prior_likelihood_sensitivity([0.0], [0.0])
    @test_throws ArgumentError prior_likelihood_sensitivity([0.0, 1.0], [0.0])
    @test_throws ArgumentError prior_likelihood_sensitivity([0.0, Inf], [0.0, 1.0])
    @test_throws ArgumentError prior_likelihood_sensitivity([0.0, 1.0], [0.0, 1.0];
        prior_powers = [-0.1])
    @test_throws ArgumentError prior_likelihood_sensitivity([0.0, 1.0], [0.0, 1.0];
        likelihood_powers = Float64[])
    @test_throws ArgumentError prior_likelihood_sensitivity([0.0, 1.0], [0.0, 1.0];
        min_effective_sample_size = 0)
    custom_sensitivity = sensitivity_comparison(
        :main => result,
        :short => spec_result;
        axis = :prior_regime,
        values = (main = :seeded, short = :unseeded),
        baseline = :main,
        draw_indices = [1, 2])
    @test [row.sensitivity_axis for row in custom_sensitivity] ==
        fill(:prior_regime, length(custom_sensitivity))
    @test Set(row.sensitivity_value for row in custom_sensitivity) ==
        Set([:seeded, :unseeded])
    sensitivity_summary = sensitivity_comparison_summary(
        NamedTuple[threshold_sensitivity...; custom_sensitivity...];
        required_axes = (:threshold, :prior))
    @test sensitivity_summary.schema ==
        "bayesianmgmfrm.sensitivity_comparison_summary.v1"
    @test sensitivity_summary.passed
    @test sensitivity_summary.required_axes == (:thresholds, :prior_regime)
    @test sensitivity_summary.observed_axes == (:prior_regime, :thresholds)
    @test sensitivity_summary.missing_required_axes == ()
    @test sensitivity_summary.complete_required_axes == (:thresholds, :prior_regime)
    @test sensitivity_summary.n_rows ==
        length(threshold_sensitivity) + length(custom_sensitivity)
    @test sensitivity_summary.n_required_axes == 2
    @test sensitivity_summary.n_complete_required_axes == 2
    @test sensitivity_summary.criteria == (:waic,)
    @test Set(sensitivity_summary.baseline_models) ==
        Set(["main", "partial_credit"])
    threshold_axis_summary = only(filter(row -> row.axis === :thresholds,
        sensitivity_summary.axis_rows))
    @test threshold_axis_summary.present
    @test threshold_axis_summary.status === :complete
    @test threshold_axis_summary.models == ("partial_credit", "rating_scale")
    @test threshold_axis_summary.n_baseline_rows == 1
    @test threshold_axis_summary.n_candidate_rows == 1
    @test threshold_axis_summary.warnings == ()
    prior_axis_summary = only(filter(row -> row.axis === :prior_regime,
        sensitivity_summary.axis_rows))
    @test prior_axis_summary.present
    @test prior_axis_summary.baseline_models == ("main",)
    @test prior_axis_summary.n_candidate_rows == 1
    incomplete_sensitivity_summary = sensitivity_comparison_summary(
        threshold_sensitivity;
        required_axes = (:thresholds, :discrimination))
    @test !incomplete_sensitivity_summary.passed
    @test incomplete_sensitivity_summary.missing_required_axes == (:discrimination,)
    @test incomplete_sensitivity_summary.incomplete_required_axes == (:discrimination,)
    missing_axis_summary = only(filter(row -> row.axis === :discrimination,
        incomplete_sensitivity_summary.axis_rows))
    @test !missing_axis_summary.present
    @test missing_axis_summary.status === :missing
    vararg_sensitivity_summary = sensitivity_comparison_summary(
        threshold_sensitivity[1], threshold_sensitivity[2];
        required_axes = (:thresholds,))
    @test vararg_sensitivity_summary.passed

    required_sensitivity_axes = (
        :thresholds,
        :discrimination,
        :rater_pooling,
        :dff,
        :anchor,
        :dimensions,
        :prior_regime,
    )
    all_axis_sensitivity_rows = NamedTuple[]
    for axis in required_sensitivity_axes
        for row in threshold_sensitivity
            push!(all_axis_sensitivity_rows, merge(row, (;
                sensitivity_axis = axis,
                sensitivity_value = row.is_baseline ? :baseline : Symbol(axis, "_candidate"),
                baseline_value = :baseline,
                sensitivity_contrast = (;
                    candidate = row.is_baseline ? :baseline : Symbol(axis, "_candidate"),
                    baseline = :baseline),
            )))
        end
    end
    full_sensitivity_summary =
        sensitivity_comparison_summary(all_axis_sensitivity_rows)
    @test full_sensitivity_summary.passed
    @test full_sensitivity_summary.required_axes == required_sensitivity_axes
    @test [row.axis for row in full_sensitivity_summary.axis_rows] ==
        collect(required_sensitivity_axes)
    @test all(row -> row.status === :complete,
        full_sensitivity_summary.axis_rows)
    @test full_sensitivity_summary.n_complete_required_axes ==
        length(required_sensitivity_axes)
    @test full_sensitivity_summary.n_baseline_rows ==
        length(required_sensitivity_axes)
    @test full_sensitivity_summary.n_candidate_rows ==
        length(required_sensitivity_axes)
    anchor_sensitivity_linking = anchor_linking_summary(result.design;
        sensitivity_rows = all_axis_sensitivity_rows)
    @test anchor_sensitivity_linking.passed
    @test anchor_sensitivity_linking.anchor_sensitivity_status === :complete
    @test anchor_sensitivity_linking.anchor_sensitivity_passed === true
    @test anchor_sensitivity_linking.anchor_sensitivity_summary.required_axes == (:anchor,)
    loo_comparison = compare_models(result, hmc_result;
        names = [:main, :hmc],
        criterion = :loo,
        draw_indices = loo_indices)
    loo_comparison_stats = Dict(
        "main" => loo(result; draw_indices = loo_indices),
        "hmc" => loo(hmc_result; draw_indices = loo_indices),
    )
    best_loo_stat = loo_comparison_stats[loo_comparison[1].model]
    @test length(loo_comparison) == 2
    @test [row.rank for row in loo_comparison] == [1, 2]
    @test loo_comparison[1].elpd_loo >= loo_comparison[2].elpd_loo
    @test loo_comparison[1].elpd_difference ≈ 0.0
    @test loo_comparison[1].looic_difference ≈ 0.0
    @test loo_comparison[2].elpd_difference <= 0
    @test loo_comparison[2].looic_difference >= 0
    @test sum(row.relative_weight for row in loo_comparison) ≈ 1.0
    @test loo_comparison[1].relative_weight >= loo_comparison[2].relative_weight
    @test all(row -> row.criterion === :loo, loo_comparison)
    @test all(row -> row.comparison_contract ===
        :same_observation_data_same_latent_dimensions, loo_comparison)
    @test all(row -> row.model_family === :mfrm, loo_comparison)
    @test all(row -> row.dimensions == spec.dimensions, loo_comparison)
    @test all(row -> row.method === :raw_importance_sampling, loo_comparison)
    @test all(row -> row.psis_smoothing === false, loo_comparison)
    @test all(row -> row.n_observations == data.n, loo_comparison)
    best_loo_elpd = best_loo_stat.elpd_loo
    manual_loo_weights = Dict(
        name => exp(stat.elpd_loo - best_loo_elpd)
        for (name, stat) in loo_comparison_stats
    )
    manual_loo_weight_total = sum(values(manual_loo_weights))
    for row in loo_comparison
        stat = loo_comparison_stats[row.model]
        pointwise_difference = stat.pointwise.elpd_loo .-
            best_loo_stat.pointwise.elpd_loo
        @test row.elpd_loo ≈ stat.elpd_loo
        @test row.elpd_difference ≈ stat.elpd_loo - best_loo_stat.elpd_loo
        @test row.se_elpd_difference ≈
            sqrt(length(pointwise_difference) *
                test_sample_variance(pointwise_difference))
        @test row.looic ≈ stat.looic
        @test row.looic_difference ≈ stat.looic - best_loo_stat.looic
        @test row.p_loo ≈ stat.p_loo
        @test row.lppd ≈ stat.lppd
        @test row.relative_weight ≈
            manual_loo_weights[row.model] / manual_loo_weight_total
        @test row.max_pareto_k ≈ stat.max_pareto_k
        @test row.bad_pareto_k_count == stat.bad_pareto_k_count
        @test row.min_effective_sample_size ≈ stat.min_effective_sample_size
        @test row.warning === stat.warning
    end
    pair_loo_comparison = compare_models(:main => result, :hmc => hmc_result;
        criterion = :loo,
        draw_indices = loo_indices)
    @test [row.model for row in pair_loo_comparison] ==
        [row.model for row in loo_comparison]
    @test [row.looic for row in pair_loo_comparison] ≈
        [row.looic for row in loo_comparison]
    psis_comparison = compare_models(result, hmc_result;
        names = [:main, :hmc],
        criterion = :psis_loo,
        draw_indices = loo_indices)
    psis_comparison_stats = Dict(
        "main" => psis_loo(result; draw_indices = loo_indices),
        "hmc" => psis_loo(hmc_result; draw_indices = loo_indices),
    )
    @test length(psis_comparison) == 2
    @test [row.rank for row in psis_comparison] == [1, 2]
    @test all(row -> row.criterion === :loo, psis_comparison)
    @test all(row -> row.method === :pareto_smoothed_importance_sampling,
        psis_comparison)
    @test all(row -> row.psis_smoothing === true, psis_comparison)
    @test sum(row.relative_weight for row in psis_comparison) ≈ 1.0
    best_psis_stat = psis_comparison_stats[psis_comparison[1].model]
    for row in psis_comparison
        stat = psis_comparison_stats[row.model]
        @test row.elpd_loo ≈ stat.elpd_loo
        @test row.elpd_difference ≈ stat.elpd_loo - best_psis_stat.elpd_loo
        @test row.looic ≈ stat.looic
        @test row.looic_difference ≈ stat.looic - best_psis_stat.looic
        @test row.p_loo ≈ stat.p_loo
        @test row.max_pareto_k ≈ stat.max_pareto_k
        @test row.bad_pareto_k_count == stat.bad_pareto_k_count
        @test row.min_effective_sample_size ≈ stat.min_effective_sample_size
    end
    loo_sensitivity = sensitivity_comparison(:main => result, :hmc => hmc_result;
        axis = :sampler,
        baseline = :main,
        criterion = :loo,
        draw_indices = loo_indices)
    loo_sensitivity_baseline = only(filter(row -> row.model == "main",
        loo_sensitivity))
    loo_sensitivity_candidate = only(filter(row -> row.model == "hmc",
        loo_sensitivity))
    @test loo_sensitivity_baseline.sensitivity_value === :random_walk_metropolis
    @test loo_sensitivity_candidate.sensitivity_value === :nuts
    @test loo_sensitivity_candidate.elpd_difference_from_baseline ≈
        loo_sensitivity_candidate.elpd_loo - loo_sensitivity_baseline.elpd_loo
    @test loo_sensitivity_candidate.information_criterion_difference_from_baseline ≈
        loo_sensitivity_candidate.looic - loo_sensitivity_baseline.looic
    psis_sensitivity = sensitivity_comparison(:main => result, :hmc => hmc_result;
        axis = :sampler,
        baseline = :main,
        criterion = :psis_loo,
        draw_indices = loo_indices)
    psis_sensitivity_baseline = only(filter(row -> row.model == "main",
        psis_sensitivity))
    psis_sensitivity_candidate = only(filter(row -> row.model == "hmc",
        psis_sensitivity))
    @test all(row -> row.method === :pareto_smoothed_importance_sampling,
        psis_sensitivity)
    @test all(row -> row.psis_smoothing === true, psis_sensitivity)
    @test psis_sensitivity_candidate.elpd_difference_from_baseline ≈
        psis_sensitivity_candidate.elpd_loo - psis_sensitivity_baseline.elpd_loo
    @test psis_sensitivity_candidate.information_criterion_difference_from_baseline ≈
        psis_sensitivity_candidate.looic - psis_sensitivity_baseline.looic
    @test_throws ArgumentError compare_models(result; names = [:single])
    @test_throws ArgumentError compare_models(result, spec_result; names = [:only])
    @test_throws ArgumentError compare_models(result, spec_result; names = [:dup, :dup])
    @test_throws ArgumentError compare_models(result, spec_result; criterion = :bad)
    @test_throws ArgumentError compare_models(:bad => design, :good => result)
    @test_throws ArgumentError sensitivity_comparison(result; names = [:single])
    @test_throws ArgumentError sensitivity_comparison(result, spec_result; names = [:only])
    @test_throws ArgumentError sensitivity_comparison(result, spec_result;
        names = [:dup, :dup])
    @test_throws ArgumentError sensitivity_comparison(result, spec_result;
        names = [:main, :short],
        baseline = :missing)
    @test_throws ArgumentError sensitivity_comparison(result, spec_result;
        names = [:main, :short],
        axis = :anchor,
        draw_indices = [1, 2])
    @test_throws ArgumentError sensitivity_comparison(result, spec_result;
        names = [:main, :short],
        axis = :anchor,
        values = [:hard],
        draw_indices = [1, 2])
    @test_throws ArgumentError sensitivity_comparison(:bad => design, :good => result)
    @test_throws ArgumentError sensitivity_comparison_summary(NamedTuple[])
    @test_throws ArgumentError sensitivity_comparison_summary(
        NamedTuple[(; sensitivity_axis = :thresholds)])
    @test_throws ArgumentError sensitivity_comparison_summary(
        NamedTuple[merge(threshold_sensitivity[1], (; is_baseline = missing))];
        required_axes = (:thresholds,))

    altered_table = (
        examinee = table.examinee,
        rater = table.rater,
        item = table.item,
        score = reverse(table.score),
    )
    altered_data = FacetData(altered_table; person = :examinee, rater = :rater, item = :item, score = :score)
    altered_spec = mfrm_spec(altered_data; thresholds = :partial_credit)
    altered_fit = fit(altered_spec; prior, ndraws = 2, warmup = 1, step_size = 0.03, rng = MersenneTwister(1103))
    @test altered_data.n == data.n
    @test altered_spec.validation.data_signature != spec.validation.data_signature
    @test_throws ArgumentError compare_models(result, altered_fit; draw_indices = [1, 2])

    probabilities = zeros(Float64, length(data.category_levels))
    draw_params = @view result.draws[1, :]
    draw_loglik = pointwise_loglikelihood(design, draw_params)
    for row in 1:data.n
        BayesianMGMFRM._category_probabilities!(probabilities, design, draw_params, row)
        @test sum(probabilities) ≈ 1.0
        @test log(probabilities[data.category[row]]) ≈ draw_loglik[row]
    end

    prob_array = predictive_probabilities(result; draw_indices = [1, 2])
    @test size(prob_array) == (2, data.n, length(data.category_levels))
    @test predictive_probabilities(design, result.draws[1:2, :]) ≈ prob_array
    @test all(draw -> all(row -> sum(prob_array[draw, row, :]) ≈ 1.0, 1:data.n), 1:2)
    @test all(row -> log(prob_array[1, row, data.category[row]]) ≈ llmat[1, row], 1:data.n)
    @test_throws ArgumentError predictive_probabilities(result; ndraws = 0)
    @test_throws ArgumentError predictive_probabilities(result; ndraws = 2, draw_indices = [1])
    @test_throws ArgumentError predictive_probabilities(design, result.draws[:, 1:end-1])

    expected = expected_scores(result; draw_indices = [1, 2])
    variances = predictive_variances(result; draw_indices = [1, 2])
    residuals = predictive_residuals(result; draw_indices = [1, 2])
    @test size(expected) == (2, data.n)
    @test expected_scores(design, result.draws[1:2, :]) ≈ expected
    @test size(variances) == (2, data.n)
    @test predictive_variances(design, result.draws[1:2, :]) ≈ variances
    @test size(residuals) == (2, data.n)
    @test predictive_residuals(design, result.draws[1:2, :]) ≈ residuals
    for draw in 1:2, row in 1:data.n
        manual_mean = sum(data.category_levels[k] * prob_array[draw, row, k] for k in eachindex(data.category_levels))
        manual_second = sum(data.category_levels[k]^2 * prob_array[draw, row, k] for k in eachindex(data.category_levels))
        @test expected[draw, row] ≈ manual_mean
        @test variances[draw, row] ≈ manual_second - manual_mean^2 atol = 1e-12
        @test residuals[draw, row] ≈ data.score[row] - expected[draw, row]
    end
    @test all(>=(0.0), variances)
    @test_throws ArgumentError expected_scores(result; ndraws = 0)
    @test_throws ArgumentError predictive_variances(result; ndraws = 0)
    @test_throws ArgumentError predictive_residuals(result; ndraws = 0)

    manual_fair_expected = function (params, person_index, rater_index, item_index)
        reference_value = (block, level_index) -> level_index == 1 ? 0.0 : params[block[level_index - 1]]
        threshold_step = function (item, step)
            kminus1 = length(data.category_levels) - 1
            free_steps = max(kminus1 - 1, 0)
            free_steps == 0 && return 0.0
            step_range = design.blocks[:thresholds]
            if design.spec.thresholds === :rating_scale
                if step <= free_steps
                    return params[step_range[step]]
                end
                return -sum(params[step_range[s]] for s in 1:free_steps)
            end
            offset = (item - 1) * free_steps
            if step <= free_steps
                return params[step_range[offset + step]]
            end
            return -sum(params[step_range[offset + s]] for s in 1:free_steps)
        end
        location = params[design.blocks[:person][person_index]] -
            reference_value(design.blocks[:rater], rater_index) -
            reference_value(design.blocks[:item], item_index)
        etas = Float64[]
        step_sum = 0.0
        for category_index in eachindex(data.category_levels)
            if category_index > 1
                step_sum += threshold_step(item_index, category_index - 1)
            end
            push!(etas, (category_index - 1) * location - step_sum)
        end
        max_eta = maximum(etas)
        weights = [exp(eta - max_eta) for eta in etas]
        probabilities = weights ./ sum(weights)
        return sum(data.category_levels[category] * probabilities[category]
            for category in eachindex(data.category_levels))
    end

    person_fair = fair_average_summary(result;
        by = :person,
        draw_indices = [1, 2],
        interval = 0.8)
    @test length(person_fair) == length(data.person_levels)
    @test all(row -> row.facet === :person, person_fair)
    @test all(row -> row.method === :posterior_expected_score, person_fair)
    @test all(row -> row.reference === :balanced_facet_grid, person_fair)
    @test all(row -> row.n_draws == 2, person_fair)
    @test all(row -> row.n_reference_rows ==
        length(data.rater_levels) * length(data.item_levels), person_fair)
    @test all(row -> row.interval_probability == 0.8, person_fair)
    @test all(row -> row.lower_probability ≈ 0.1, person_fair)
    @test all(row -> row.upper_probability ≈ 0.9, person_fair)
    @test all(row -> row.caveat ===
        :balanced_reference_grid_not_population_standardization,
        person_fair)
    @test fair_average_summary(design, result.draws[1:2, :];
        by = :person,
        interval = 0.8) == person_fair
    for row in person_fair
        level_index = findfirst(==(row.level), data.person_levels)
        obs = findall(==(level_index), data.person)
        reference_rows = [
            (level_index, rater, item)
            for rater in eachindex(data.rater_levels)
            for item in eachindex(data.item_levels)
        ]
        fair_by_draw = [
            sum(manual_fair_expected(
                @view(result.draws[draw, :]),
                person,
                rater,
                item,
            ) for (person, rater, item) in reference_rows) / length(reference_rows)
            for draw in 1:2
        ]
        observed_mean = sum(data.score[observation] for observation in obs) / length(obs)
        adjustment_by_draw = fair_by_draw .- observed_mean
        @test row.n_observations == length(obs)
        @test row.observed_mean ≈ observed_mean
        @test row.fair_average_mean ≈ sum(fair_by_draw) / length(fair_by_draw)
        @test row.expected_score_mean ≈ row.fair_average_mean
        @test row.expected_score_median ≈ row.fair_average_median
        @test row.expected_score_lower ≈ row.fair_average_lower
        @test row.expected_score_upper ≈ row.fair_average_upper
        @test row.adjustment_mean ≈
            sum(adjustment_by_draw) / length(adjustment_by_draw)
        @test row.fair_average_lower <= row.fair_average_median <=
            row.fair_average_upper
        @test row.adjustment_lower <= row.adjustment_median <= row.adjustment_upper
        @test row.flag === :ok
    end
    rater_fair = fair_average_summary(result; by = :rater, draw_indices = [1, 2])
    @test length(rater_fair) == length(data.rater_levels)
    @test all(row -> row.n_reference_rows ==
        length(data.person_levels) * length(data.item_levels), rater_fair)
    item_fair = fair_average_summary(result; by = :item, draw_indices = [1, 2])
    @test length(item_fair) == length(data.item_levels)
    @test all(row -> row.n_reference_rows ==
        length(data.person_levels) * length(data.rater_levels), item_fair)
    sparse_fair = fair_average_summary(result;
        by = :person,
        draw_indices = [1, 2],
        min_n = data.n + 1)
    @test all(row -> row.flag === :below_min_n, sparse_fair)
    @test_throws ArgumentError fair_average_summary(result; by = :category)
    @test_throws ArgumentError fair_average_summary(result; interval = 1.0)
    @test_throws ArgumentError fair_average_summary(result; min_n = 0)
    @test_throws ArgumentError fair_average_summary(design, result.draws[1:2, 1:end-1])

    facet_values = function (facet, draw)
        params = @view result.draws[draw, :]
        if facet === :person
            return [Float64(params[design.blocks[:person][level]])
                for level in eachindex(data.person_levels)]
        elseif facet === :rater
            return [level == 1 ? 0.0 : Float64(params[design.blocks[:rater][level - 1]])
                for level in eachindex(data.rater_levels)]
        elseif facet === :item
            return [level == 1 ? 0.0 : Float64(params[design.blocks[:item][level - 1]])
                for level in eachindex(data.item_levels)]
        end
        error("unexpected facet")
    end
    sample_variance = function (values)
        m = sum(values) / length(values)
        return sum((value - m)^2 for value in values) / (length(values) - 1)
    end
    reliability_rows = separation_reliability_summary(result;
        draw_indices = [1, 2],
        interval = 0.8)
    @test [row.facet for row in reliability_rows] == [:person, :rater, :item]
    @test all(row -> row.method === :posterior_empirical_reliability,
        reliability_rows)
    @test all(row -> row.scale === :logit, reliability_rows)
    @test all(row -> row.n_draws == 2, reliability_rows)
    @test all(row -> row.interval_probability == 0.8, reliability_rows)
    @test all(row -> row.lower_probability ≈ 0.1, reliability_rows)
    @test all(row -> row.upper_probability ≈ 0.9, reliability_rows)
    @test all(row -> row.caveat ===
        :posterior_empirical_reliability_screening_not_generalizability_coefficient,
        reliability_rows)
    @test separation_reliability_summary(design, result.draws[1:2, :];
        interval = 0.8) == reliability_rows
    person_reliability_rows = separation_reliability_summary(result;
        facets = :person,
        draw_indices = [1, 2])
    @test length(person_reliability_rows) == 1
    @test [row.facet for row in separation_reliability_summary(result;
        facets = :all,
        draw_indices = [1, 2])] == [:person, :rater, :item]
    for row in reliability_rows
        levels = row.facet === :person ? data.person_levels :
            row.facet === :rater ? data.rater_levels : data.item_levels
        values_by_draw = [facet_values(row.facet, draw) for draw in 1:2]
        values_by_level = [
            [values_by_draw[draw][level] for draw in 1:2]
            for level in eachindex(levels)
        ]
        error_variance = sum(sample_variance(values) for values in values_by_level) /
            length(values_by_level)
        observed_variance_by_draw = [sample_variance(values) for values in values_by_draw]
        observed_sd_by_draw = sqrt.(observed_variance_by_draw)
        adjusted_variance_by_draw =
            [max(value - error_variance, 0.0) for value in observed_variance_by_draw]
        adjusted_sd_by_draw = sqrt.(adjusted_variance_by_draw)
        separation_by_draw =
            [sqrt(value / error_variance) for value in adjusted_variance_by_draw]
        reliability_by_draw =
            [value / (value + error_variance) for value in adjusted_variance_by_draw]
        @test row.n_levels == length(levels)
        @test row.observed_variance_mean ≈
            sum(observed_variance_by_draw) / length(observed_variance_by_draw)
        @test row.observed_sd_mean ≈
            sum(observed_sd_by_draw) / length(observed_sd_by_draw)
        @test row.error_variance_mean ≈ error_variance
        @test row.error_variance_lower ≈ error_variance
        @test row.error_variance_upper ≈ error_variance
        @test row.adjusted_variance_mean ≈
            sum(adjusted_variance_by_draw) / length(adjusted_variance_by_draw)
        @test row.adjusted_sd_mean ≈
            sum(adjusted_sd_by_draw) / length(adjusted_sd_by_draw)
        @test row.separation_mean ≈
            sum(separation_by_draw) / length(separation_by_draw)
        @test row.reliability_mean ≈
            sum(reliability_by_draw) / length(reliability_by_draw)
        @test row.observed_variance_lower <= row.observed_variance_median <=
            row.observed_variance_upper
        @test row.adjusted_variance_lower <= row.adjusted_variance_median <=
            row.adjusted_variance_upper
        @test row.separation_lower <= row.separation_median <= row.separation_upper
        @test row.reliability_lower <= row.reliability_median <= row.reliability_upper
        @test row.flag in (:ok, :no_adjusted_separation)
    end
    @test_throws ArgumentError separation_reliability_summary(result;
        facets = (:person, :person))
    @test_throws ArgumentError separation_reliability_summary(result; facets = :category)
    @test_throws ArgumentError separation_reliability_summary(result; interval = 1.0)
    @test_throws ArgumentError separation_reliability_summary(result; draw_indices = [1])
    @test_throws ArgumentError separation_reliability_summary(design, result.draws[1:2, 1:end-1])

    rater_residuals = residual_summary(result;
        by = :rater,
        draw_indices = [1, 2],
        interval = 0.8)
    @test length(rater_residuals) == length(data.rater_levels)
    @test all(row -> row.facet === :rater, rater_residuals)
    @test all(row -> row.method === :posterior_expected_score, rater_residuals)
    @test all(row -> row.n_draws == 2, rater_residuals)
    @test all(row -> row.interval_probability == 0.8, rater_residuals)
    @test all(row -> row.lower_probability ≈ 0.1, rater_residuals)
    @test all(row -> row.upper_probability ≈ 0.9, rater_residuals)
    @test all(row -> row.caveat ===
        :posterior_predictive_residual_screening_not_confirmatory,
        rater_residuals)
    @test residual_summary(design, result.draws[1:2, :];
        by = :rater,
        interval = 0.8) == rater_residuals
    for row in rater_residuals
        level_index = findfirst(==(row.level), data.rater_levels)
        obs = findall(==(level_index), data.rater)
        expected_by_draw = [
            sum(expected[draw, observation] for observation in obs) / length(obs)
            for draw in axes(expected, 1)
        ]
        residual_by_draw = [
            sum(residuals[draw, observation] for observation in obs) / length(obs)
            for draw in axes(residuals, 1)
        ]
        absolute_residual_by_draw = [
            sum(abs(residuals[draw, observation]) for observation in obs) / length(obs)
            for draw in axes(residuals, 1)
        ]
        rmse_by_draw = [
            sqrt(sum(residuals[draw, observation]^2 for observation in obs) / length(obs))
            for draw in axes(residuals, 1)
        ]
        @test row.n_observations == length(obs)
        @test row.observed_mean ≈
            sum(data.score[observation] for observation in obs) / length(obs)
        @test row.expected_mean ≈ sum(expected_by_draw) / length(expected_by_draw)
        @test row.residual_mean ≈ sum(residual_by_draw) / length(residual_by_draw)
        @test row.absolute_residual_mean ≈
            sum(absolute_residual_by_draw) / length(absolute_residual_by_draw)
        @test row.rmse_mean ≈ sum(rmse_by_draw) / length(rmse_by_draw)
        @test row.expected_lower <= row.expected_median <= row.expected_upper
        @test row.residual_lower <= row.residual_median <= row.residual_upper
        @test row.absolute_residual_lower <=
            row.absolute_residual_median <= row.absolute_residual_upper
        @test row.rmse_lower <= row.rmse_median <= row.rmse_upper
        @test row.residual_interval_excludes_zero ==
            (row.residual_lower > 0 || row.residual_upper < 0)
        @test row.flag === (row.residual_interval_excludes_zero ?
            :residual_interval_excludes_zero : :ok)
    end
    observation_residuals = residual_summary(result; draw_indices = [1, 2])
    @test length(observation_residuals) == data.n
    @test [row.level for row in observation_residuals] == collect(1:data.n)
    @test all(row -> row.facet === :observation, observation_residuals)
    @test all(row -> row.n_observations == 1, observation_residuals)
    sparse_residuals = residual_summary(result;
        by = :rater,
        draw_indices = [1, 2],
        min_n = data.n + 1)
    @test all(row -> row.flag === :below_min_n, sparse_residuals)
    @test_throws ArgumentError residual_summary(result; by = :unknown)
    @test_throws ArgumentError residual_summary(result; interval = 1.0)
    @test_throws ArgumentError residual_summary(result; min_n = 0)

    calibration = calibration_table(result; draw_indices = [1, 2], bins = 3, interval = 0.8)
    @test length(calibration) == 3
    @test sum(row.n_observations for row in calibration) == data.n
    @test [row.bin for row in calibration] == [1, 2, 3]
    @test all(row -> row.target === :expected_score, calibration)
    @test all(row -> row.category === missing, calibration)
    @test all(row -> row.n_draws == 2, calibration)
    @test all(row -> row.lower_probability ≈ 0.1, calibration)
    @test all(row -> row.upper_probability ≈ 0.9, calibration)
    @test all(row -> row.predicted_bin_lower <= row.predicted_bin_upper, calibration)
    @test all(row -> row.predicted_lower <= row.predicted_median <= row.predicted_upper, calibration)
    @test all(row -> row.calibration_error ≈ row.observed_mean - row.predicted_mean, calibration)
    @test all(row -> row.absolute_calibration_error ≈ abs(row.calibration_error), calibration)
    @test all(row -> row.flag in (:ok, :outside_interval), calibration)
    @test isequal(calibration_table(design, result.draws[1:2, :]; bins = 3, interval = 0.8), calibration)
    calibration_plot = calibration_plot_data(calibration)
    @test length(calibration_plot) == length(calibration)
    @test [row.predicted_mean for row in calibration_plot] ≈ [row.predicted_mean for row in calibration]
    @test [row.observed_mean for row in calibration_plot] ≈ [row.observed_mean for row in calibration]
    @test [row.reference for row in calibration_plot] ≈ [row.predicted_mean for row in calibration]
    @test [row.flag for row in calibration_plot] == [row.flag for row in calibration]

    category_calibration = calibration_table(result;
        target = :category_probability,
        category = last(data.category_levels),
        draw_indices = [1, 2],
        bins = 2)
    @test length(category_calibration) == 2
    @test all(row -> row.target === :category_probability, category_calibration)
    @test all(row -> row.category == last(data.category_levels), category_calibration)
    @test all(row -> 0 <= row.observed_mean <= 1, category_calibration)
    @test all(row -> 0 <= row.predicted_mean <= 1, category_calibration)
    default_category_calibration = calibration_table(result;
        target = :category_probability,
        draw_indices = [1, 2],
        bins = 2)
    @test [row.category for row in default_category_calibration] ==
        fill(last(data.category_levels), length(default_category_calibration))
    all_category_calibration = calibration_table(result;
        target = :category_probability,
        category = :all,
        draw_indices = [1, 2],
        bins = 2,
        interval = 0.8)
    @test length(all_category_calibration) == 2 * length(data.category_levels)
    @test [row.category for row in all_category_calibration[1:2]] ==
        fill(first(data.category_levels), 2)
    @test Set(row.category for row in all_category_calibration) == Set(data.category_levels)
    @test all(row -> row.target === :category_probability, all_category_calibration)
    @test all(row -> 0 <= row.observed_mean <= 1, all_category_calibration)
    @test all(row -> 0 <= row.predicted_mean <= 1, all_category_calibration)
    @test all(row -> row.lower_probability ≈ 0.1, all_category_calibration)
    all_calibration = calibration_table(result;
        target = :all,
        draw_indices = [1, 2],
        bins = 2,
        interval = 0.8)
    @test length(all_calibration) == 2 * (1 + length(data.category_levels))
    @test all(row -> row.target === :expected_score, all_calibration[1:2])
    @test all(row -> row.category === missing, all_calibration[1:2])
    @test all(row -> row.target === :category_probability, all_calibration[3:end])
    @test Set(row.category for row in all_calibration[3:end]) == Set(data.category_levels)
    @test length(calibration_table(result; draw_indices = [1, 2], bins = data.n + 10)) == data.n
    @test_throws ArgumentError calibration_table(result; bins = 0)
    @test_throws ArgumentError calibration_table(result; interval = 1.0)
    @test_throws ArgumentError calibration_table(result; draw_indices = [0])
    @test_throws ArgumentError calibration_table(result; target = :unknown)
    @test_throws ArgumentError calibration_table(result; target = :category_probability, category = :not_a_score)
    @test_throws ArgumentError calibration_table(result; target = :all, category = last(data.category_levels))
    @test_throws ArgumentError calibration_table(result; category = first(data.category_levels))
    @test_throws ArgumentError calibration_table(design, result.draws[1:0, :])

    rater_fit = fit_stats(result; by = :rater, draw_indices = [1, 2], interval = 0.8)
    @test length(rater_fit) == length(data.rater_levels)
    @test [row.level for row in rater_fit] == data.rater_levels
    @test all(row -> row.facet === :rater, rater_fit)
    @test all(row -> row.method === :posterior, rater_fit)
    @test all(row -> row.n_obs == count(==(findfirst(==(row.level), data.rater_levels)), data.rater), rater_fit)
    @test all(row -> row.lower_probability ≈ 0.1, rater_fit)
    @test all(row -> row.upper_probability ≈ 0.9, rater_fit)
    @test all(row -> row.flag in (:ok, :tiny_predictive_variance), rater_fit)
    @test all(row -> row.infit_lower <= row.infit_median <= row.infit_upper, rater_fit)
    @test all(row -> row.outfit_lower <= row.outfit_median <= row.outfit_upper, rater_fit)
    @test fit_stats(design, result.draws[1:2, :]; by = :rater, interval = 0.8) == rater_fit

    rater_diag = rater_diagnostics(result; draw_indices = [1, 2], interval = 0.8)
    @test length(rater_diag) == length(data.rater_levels)
    @test [row.level for row in rater_diag] == data.rater_levels
    @test all(row -> row.facet === :rater, rater_diag)
    @test all(row -> row.model_family === :mfrm, rater_diag)
    @test all(row -> row.method === :posterior_rater_diagnostics, rater_diag)
    @test all(row -> row.n_draws == 2, rater_diag)
    @test all(row -> row.interval_probability == 0.8, rater_diag)
    @test all(row -> row.lower_probability ≈ 0.1, rater_diag)
    @test all(row -> row.upper_probability ≈ 0.9, rater_diag)
    @test all(row -> row.caveat ===
        :rater_diagnostics_screening_not_confirmatory,
        rater_diag)
    @test isequal(
        rater_diagnostics(design, result.draws[1:2, :]; interval = 0.8),
        rater_diag,
    )
    category_midpoint =
        (minimum(data.category_levels) + maximum(data.category_levels)) / 2
    central_distances = [abs(level - category_midpoint) for level in data.category_levels]
    central_categories =
        data.category_levels[findall(==(minimum(central_distances)), central_distances)]
    for row in rater_diag
        level_index = findfirst(==(row.level), data.rater_levels)
        obs = findall(==(level_index), data.rater)
        scores = Float64[data.score[observation] for observation in obs]
        score_mean = sum(scores) / length(scores)
        score_sd = sqrt(sum((score - score_mean)^2 for score in scores) /
            (length(scores) - 1))
        counts = [
            count(observation -> data.category[observation] == category_index, obs)
            for category_index in eachindex(data.category_levels)
        ]
        proportions = counts ./ length(obs)
        rater_residual = only(filter(candidate -> candidate.level == row.level,
            rater_residuals))
        rater_fit_row = only(filter(candidate -> candidate.level == row.level,
            rater_fit))
        severity_by_draw = level_index == 1 ? [0.0, 0.0] :
            [Float64(result.draws[draw, design.blocks[:rater][level_index - 1]])
                for draw in 1:2]
        @test row.rater == row.level
        @test row.rater_index == level_index
        @test row.n_observations == length(obs)
        @test row.n_categories == length(data.category_levels)
        @test row.n_categories_used == count(>(0), counts)
        @test [entry.category for entry in row.category_counts] == data.category_levels
        @test [entry.count for entry in row.category_counts] == counts
        @test [entry.category for entry in row.category_proportions] == data.category_levels
        @test [entry.proportion for entry in row.category_proportions] ≈ proportions
        @test row.unused_categories ==
            [data.category_levels[index] for index in eachindex(counts) if counts[index] == 0]
        @test row.mean_score ≈ score_mean
        @test row.score_sd ≈ score_sd
        @test row.min_score ≈ minimum(scores)
        @test row.max_score ≈ maximum(scores)
        @test row.score_range ≈ maximum(scores) - minimum(scores)
        @test row.scale_midpoint ≈ category_midpoint
        @test row.central_categories == central_categories
        @test row.central_category_count ==
            sum(counts[findfirst(==(category), data.category_levels)]
                for category in central_categories)
        @test row.central_category_proportion ≈
            row.central_category_count / length(obs)
        @test row.severity_reference == (level_index == 1)
        @test row.severity_parameter_name ===
            (level_index == 1 ? missing :
             design.parameter_names[design.blocks[:rater][level_index - 1]])
        @test row.severity_mean ≈ sum(severity_by_draw) / length(severity_by_draw)
        @test row.severity_lower <= row.severity_median <= row.severity_upper
        @test row.discrimination_modeled == false
        @test row.discrimination_parameter === missing
        @test row.discrimination_parameter_name === missing
        @test row.discrimination_scale === :not_modeled
        @test row.discrimination_mean === missing
        @test row.residual_mean ≈ rater_residual.residual_mean
        @test row.absolute_residual_mean ≈ rater_residual.absolute_residual_mean
        @test row.rmse_mean ≈ rater_residual.rmse_mean
        @test row.residual_flag === rater_residual.flag
        @test row.fit_statistics_available == true
        @test row.infit_mean ≈ rater_fit_row.infit_mean
        @test row.outfit_mean ≈ rater_fit_row.outfit_mean
        @test row.fit_flag === rater_fit_row.flag
        @test row.flag === (rater_residual.flag !== :ok ? rater_residual.flag :
            rater_fit_row.flag)
    end
    sparse_rater_diag = rater_diagnostics(result;
        draw_indices = [1, 2],
        min_n = data.n + 1)
    @test all(row -> row.flag === :below_min_n, sparse_rater_diag)
    @test_throws ArgumentError rater_diagnostics(result; interval = 1.0)
    @test_throws ArgumentError rater_diagnostics(result; min_n = 0)
    @test_throws ArgumentError rater_diagnostics(result; draw_indices = [0])
    @test_throws ArgumentError rater_diagnostics(design, result.draws[1:2, 1:end-1])

    item_fit = fit_stats(result; by = :item, draw_indices = [1, 2])
    @test [row.level for row in item_fit] == data.item_levels
    category_fit = fit_stats(result; by = :category, draw_indices = [1, 2])
    @test [row.level for row in category_fit] == data.category_levels
    sparse_fit = fit_stats(result; by = :rater, draw_indices = [1, 2], min_n = data.n + 1)
    @test all(row -> row.flag === :below_min_n, sparse_fit)
    @test all(row -> isnan(row.infit_mean) && isnan(row.outfit_mean), sparse_fit)
    @test_throws ArgumentError fit_stats(result; by = :unknown)
    @test_throws ArgumentError fit_stats(result; method = :plugin)
    @test_throws ArgumentError fit_stats(result; interval = 1.0)
    @test_throws ArgumentError fit_stats(result; min_n = 0)

    prior_replicated = prior_predict(design; prior, ndraws = 5, rng = MersenneTwister(2234))
    @test size(prior_replicated) == (5, data.n)
    @test all(score -> score in data.category_levels, prior_replicated)
    prior_replicated_spec = prior_predict(spec; prior, ndraws = 2, rng = MersenneTwister(2235))
    @test size(prior_replicated_spec) == (2, data.n)
    @test_throws ArgumentError prior_predict(design; prior, ndraws = 0)

    prior_ppc = prior_predictive_check(design; prior, ndraws = 6, rng = MersenneTwister(6678))
    @test size(prior_ppc.replicated_scores) == (6, data.n)
    @test size(prior_ppc.parameter_draws) == (6, length(design.parameter_names))
    @test all(isfinite, prior_ppc.parameter_draws)
    @test prior_ppc.category_levels == data.category_levels
    @test prior_ppc.person_levels == data.person_levels
    @test prior_ppc.rater_levels == data.rater_levels
    @test prior_ppc.item_levels == data.item_levels
    @test isempty(prior_ppc.optional_levels)
    @test prior_ppc.grouped.schema == "bayesianmgmfrm.predictive_grouped_summary.v1"
    @test prior_ppc.grouped.n_dff_terms == 0
    @test prior_ppc.grouped.n_dff_cells == 0
    @test prior_ppc.grouped.n_sparse_design_blocks > 0
    @test any(row -> row.statistic === :sparse_design_block_mean,
        prior_ppc.grouped.rows)
    @test length(prior_ppc.observed.category_proportions) == length(data.category_levels)
    @test size(prior_ppc.replicated.category_proportions) == (6, length(data.category_levels))
    @test length(prior_ppc.observed.person_mean) == length(data.person_levels)
    @test size(prior_ppc.replicated.person_mean) == (6, length(data.person_levels))
    @test all(rep -> sum(prior_ppc.replicated.category_proportions[rep, :]) ≈ 1.0,
        axes(prior_ppc.replicated.category_proportions, 1))
    prior_implications = prior_ppc.implication_diagnostics
    @test prior_implications.schema ==
        "bayesianmgmfrm.prior_predictive_implication_diagnostics.v1"
    @test prior_implications.flag in (:ok, :prior_implication_warning)
    @test prior_implications.controls.min_category_probability == 0.01
    @test prior_implications.controls.prior_warning_probability == 0.95
    @test prior_implications.controls.wide_facet_range_fraction == 0.8
    @test length(prior_implications.category_rows) == length(data.category_levels)
    @test [row.category for row in prior_implications.category_rows] ==
        data.category_levels
    @test all(row -> row.n_replicates == 6, prior_implications.category_rows)
    @test all(row -> row.flag in (:ok, :prior_category_nonuse, :prior_category_sparse),
        prior_implications.category_rows)
    first_category_props = prior_ppc.replicated.category_proportions[:, 1]
    @test prior_implications.category_rows[1].probability_empty ≈
        count(==(0.0), first_category_props) / 6
    @test prior_implications.category_rows[1].probability_below_min_category_probability ≈
        count(<(0.01), first_category_props) / 6
    manual_used_categories = [
        count(>(0.0), @view prior_ppc.replicated.category_proportions[rep, :])
        for rep in axes(prior_ppc.replicated.category_proportions, 1)
    ]
    @test prior_implications.category_use.observed_n_categories_used ==
        count(>(0.0), prior_ppc.observed.category_proportions)
    @test prior_implications.category_use.n_categories == length(data.category_levels)
    @test prior_implications.category_use.n_replicates == 6
    @test prior_implications.category_use.probability_all_categories_used ≈
        count(==(length(data.category_levels)), manual_used_categories) / 6
    @test prior_implications.category_use.probability_missing_any_category ≈
        1 - prior_implications.category_use.probability_all_categories_used
    @test [row.facet for row in prior_implications.facet_range_rows] ==
        [:person, :rater, :item]
    @test all(row -> row.flag in (:ok, :prior_wide_facet_range),
        prior_implications.facet_range_rows)
    person_range_row = only(filter(row -> row.facet === :person,
        prior_implications.facet_range_rows))
    manual_person_ranges = [
        maximum(@view prior_ppc.replicated.person_mean[rep, :]) -
            minimum(@view prior_ppc.replicated.person_mean[rep, :])
        for rep in axes(prior_ppc.replicated.person_mean, 1)
    ]
    @test person_range_row.observed_range ≈
        maximum(prior_ppc.observed.person_mean) - minimum(prior_ppc.observed.person_mean)
    @test person_range_row.score_range == maximum(data.category_levels) - minimum(data.category_levels)
    @test person_range_row.wide_range_threshold ≈
        person_range_row.score_range * prior_implications.controls.wide_facet_range_fraction
    @test person_range_row.probability_wide_range ≈
        count(>=(person_range_row.wide_range_threshold), manual_person_ranges) / 6
    prior_ppc_spec = prior_predictive_check(spec; prior, ndraws = 2, rng = MersenneTwister(6679))
    @test size(prior_ppc_spec.replicated_scores) == (2, data.n)
    @test_throws ArgumentError prior_predictive_check(design; prior, ndraws = 0)
    @test_throws ArgumentError prior_predictive_check(design; prior, ndraws = 1,
        min_category_probability = -0.1)
    @test_throws ArgumentError prior_predictive_check(design; prior, ndraws = 1,
        prior_warning_probability = 0.0)
    @test_throws ArgumentError prior_predictive_check(design; prior, ndraws = 1,
        wide_facet_range_fraction = -0.1)

    prior_ppc_summary = predictive_check_summary(prior_ppc; interval = 0.8)
    expected_n_summary_rows = 1 + length(data.category_levels) + length(data.person_levels) +
        length(data.rater_levels) + length(data.item_levels)
    @test length(prior_ppc_summary) == expected_n_summary_rows
    @test prior_ppc_summary[1].statistic === :mean_score
    @test prior_ppc_summary[1].level === missing
    @test prior_ppc_summary[1].observed ≈ prior_ppc.observed.mean_score
    @test prior_ppc_summary[1].replicated_mean ≈ sum(prior_ppc.replicated.mean_score) / 6
    @test prior_ppc_summary[1].lower_probability ≈ 0.1
    @test prior_ppc_summary[1].upper_probability ≈ 0.9
    @test prior_ppc_summary[1].n_replicates == 6
    @test prior_ppc_summary[1].lower_tail_probability ≈
        count(<=(prior_ppc.observed.mean_score), prior_ppc.replicated.mean_score) / 6
    @test prior_ppc_summary[1].upper_tail_probability ≈
        count(>=(prior_ppc.observed.mean_score), prior_ppc.replicated.mean_score) / 6
    @test prior_ppc_summary[1].two_sided_tail_probability ≈
        min(1.0, 2 * min(prior_ppc_summary[1].lower_tail_probability,
                prior_ppc_summary[1].upper_tail_probability))
    @test all(row -> row.flag in (:ok, :outside_interval), prior_ppc_summary)
    @test any(row -> row.statistic === :category_proportion && row.level == first(data.category_levels),
        prior_ppc_summary)
    @test any(row -> row.statistic === :person_mean && row.level == first(data.person_levels),
        prior_ppc_summary)
    prior_ppc_plot = predictive_check_plot_data(prior_ppc_summary)
    @test length(prior_ppc_plot) == length(prior_ppc_summary)
    @test [row.statistic for row in prior_ppc_plot] == [row.statistic for row in prior_ppc_summary]
    @test [row.observed for row in prior_ppc_plot] ≈ [row.observed for row in prior_ppc_summary]
    @test [row.replicated_mean for row in prior_ppc_plot] ≈
        [row.replicated_mean for row in prior_ppc_summary]
    @test [row.flag for row in prior_ppc_plot] == [row.flag for row in prior_ppc_summary]
    @test_throws ArgumentError predictive_check_summary(prior_ppc; interval = 1.0)
    @test_throws ArgumentError predictive_check_summary((observed = prior_ppc.observed,))

    grouped_table = (
        examinee = table.examinee,
        rater = table.rater,
        item = table.item,
        score = table.score,
        group = ["A", "A", "B", "B", "A", "B", "A", "B", "B"],
    )
    grouped_data = FacetData(grouped_table; person = :examinee, rater = :rater, item = :item,
        score = :score, group = :group)
    grouped_validation = validate_design(grouped_data; bias = [(:rater, :group)])
    grouped_spec = mfrm_spec(grouped_data;
        thresholds = :partial_credit,
        validation_report = grouped_validation)
    grouped_ppc = prior_predictive_check(grouped_spec; prior, ndraws = 3, rng = MersenneTwister(6680))
    @test grouped_ppc.optional_levels[:group] == grouped_data.optional_levels[:group]
    @test size(grouped_ppc.replicated.optional_mean[:group]) == (3, length(grouped_data.optional_levels[:group]))
    @test grouped_ppc.grouped.n_dff_terms == 1
    @test grouped_ppc.grouped.n_dff_cells ==
        length(grouped_data.rater_levels) * length(grouped_data.optional_levels[:group])
    @test grouped_ppc.grouped.n_sparse_design_blocks > 0
    dff_grouped_rows = filter(row -> row.statistic === :dff_cell_mean,
        grouped_ppc.grouped.rows)
    @test length(dff_grouped_rows) == grouped_ppc.grouped.n_dff_cells
    @test any(row -> row.facet_a === :rater && row.facet_b === :group &&
        row.level_a == "R1" && row.level_b == "A",
        dff_grouped_rows)
    @test all(row -> length(row.replicated) == 3, dff_grouped_rows)
    @test any(row -> row.facet === :group,
        grouped_ppc.implication_diagnostics.facet_range_rows)
    grouped_summary = predictive_check_summary(grouped_ppc; interval = 0.8)
    @test any(row -> row.statistic === :group_mean && row.level == "A", grouped_summary)
    @test any(row -> row.statistic === :group_mean && row.level == "B", grouped_summary)
    grouped_summary_with_cells = predictive_check_summary(grouped_ppc;
        interval = 0.8,
        include_grouped = true)
    @test length(grouped_summary_with_cells) ==
        length(grouped_summary) + grouped_ppc.grouped.n_dff_cells +
        grouped_ppc.grouped.n_sparse_design_blocks
    @test any(row -> row.statistic === :dff_cell_mean &&
        row.facet_a === :rater && row.facet_b === :group &&
        row.n_observations > 0,
        grouped_summary_with_cells)
    @test any(row -> row.statistic === :sparse_design_block_mean &&
        row.block === :person_rater_item && row.n_observations >= 1,
        grouped_summary_with_cells)
    grouped_design = getdesign(grouped_spec)
    grouped_waic_rows = waic_diagnostics(grouped_design,
        zeros(2, length(grouped_design.parameter_names)))
    @test grouped_waic_rows[1].optional.group ==
        grouped_data.optional_levels[:group][grouped_data.optional[:group][1]]

    grouped_dff = dff_report(grouped_design, result.draws[1:2, :]; interval = 0.8)
    @test length(grouped_dff) ==
        length(grouped_data.rater_levels) * length(grouped_data.optional_levels[:group])
    @test isequal(
        dff_report(grouped_design, result.draws[1:2, :];
            terms = (:rater, :group),
            interval = 0.8),
        grouped_dff,
    )
    @test all(row -> row.term === (:rater, :group), grouped_dff)
    @test all(row -> row.focal_facet === :rater, grouped_dff)
    @test all(row -> row.comparison_facet === :group, grouped_dff)
    @test all(row -> row.method === :posterior_predictive_interaction_residual,
        grouped_dff)
    @test all(row -> row.logit_method ===
        :local_expected_score_residual_divided_by_predictive_variance,
        grouped_dff)
    @test all(row -> row.scale === :expected_score_and_logit, grouped_dff)
    @test all(row -> row.validation_status === :declared_validation_term,
        grouped_dff)
    @test all(row -> row.caveat === :dff_screening_not_fitted_dff_effect,
        grouped_dff)
    @test all(row -> row.n_draws == 2, grouped_dff)
    @test all(row -> row.interval_probability == 0.8, grouped_dff)
    @test all(row -> row.lower_probability ≈ 0.1, grouped_dff)
    @test all(row -> row.upper_probability ≈ 0.9, grouped_dff)

    grouped_expected = expected_scores(grouped_design, result.draws[1:2, :])
    grouped_residuals = predictive_residuals(grouped_design, result.draws[1:2, :])
    grouped_variances = predictive_variances(grouped_design, result.draws[1:2, :])
    @test grouped_expected ≈ expected
    @test grouped_residuals ≈ residuals
    @test grouped_variances ≈ variances
    mean_by_draw = function (values, observations)
        [sum(values[draw, observation] for observation in observations) /
            length(observations) for draw in axes(values, 1)]
    end
    logit_shift = function (residual_values, slope_values)
        [residual_values[index] / slope_values[index]
            for index in eachindex(residual_values)]
    end
    r1_a = only(row for row in grouped_dff
        if row.focal_level == "R1" && row.comparison_level == "A")
    rater_index = findfirst(==("R1"), grouped_data.rater_levels)
    group_index = findfirst(==("A"), grouped_data.optional_levels[:group])
    cell_observations = findall(row -> grouped_data.rater[row] == rater_index &&
        grouped_data.optional[:group][row] == group_index, 1:grouped_data.n)
    rater_observations = findall(==(rater_index), grouped_data.rater)
    group_observations = findall(==(group_index), grouped_data.optional[:group])
    all_observations = collect(1:grouped_data.n)
    cell_expected = mean_by_draw(grouped_expected, cell_observations)
    cell_residual = mean_by_draw(grouped_residuals, cell_observations)
    cell_logit = logit_shift(
        cell_residual,
        mean_by_draw(grouped_variances, cell_observations),
    )
    rater_residual = mean_by_draw(grouped_residuals, rater_observations)
    rater_logit = logit_shift(
        rater_residual,
        mean_by_draw(grouped_variances, rater_observations),
    )
    group_residual = mean_by_draw(grouped_residuals, group_observations)
    group_logit = logit_shift(
        group_residual,
        mean_by_draw(grouped_variances, group_observations),
    )
    grand_residual = mean_by_draw(grouped_residuals, all_observations)
    grand_logit = logit_shift(
        grand_residual,
        mean_by_draw(grouped_variances, all_observations),
    )
    expected_score_dff = cell_residual .- rater_residual .-
        group_residual .+ grand_residual
    logit_dff = cell_logit .- rater_logit .- group_logit .+ grand_logit
    @test r1_a.n_observations == length(cell_observations)
    @test r1_a.validation_cell_count == length(cell_observations)
    @test r1_a.observed_mean ≈
        sum(grouped_data.score[observation] for observation in cell_observations) /
        length(cell_observations)
    @test r1_a.expected_score_mean ≈ sum(cell_expected) / length(cell_expected)
    @test r1_a.expected_score_residual_mean ≈
        sum(cell_residual) / length(cell_residual)
    @test r1_a.logit_residual_mean ≈ sum(cell_logit) / length(cell_logit)
    @test r1_a.expected_score_dff_mean ≈
        sum(expected_score_dff) / length(expected_score_dff)
    @test r1_a.logit_dff_mean ≈ sum(logit_dff) / length(logit_dff)
    @test r1_a.expected_score_lower <=
        r1_a.expected_score_median <= r1_a.expected_score_upper
    @test r1_a.expected_score_dff_lower <=
        r1_a.expected_score_dff_median <= r1_a.expected_score_dff_upper
    @test r1_a.logit_dff_lower <= r1_a.logit_dff_median <= r1_a.logit_dff_upper
    @test r1_a.expected_score_dff_interval_excludes_zero ==
        (r1_a.expected_score_dff_lower > 0 || r1_a.expected_score_dff_upper < 0)
    @test r1_a.logit_dff_interval_excludes_zero ==
        (r1_a.logit_dff_lower > 0 || r1_a.logit_dff_upper < 0)
    @test isnothing(r1_a.expected_score_dff_practical_threshold)
    @test isnothing(r1_a.logit_dff_practical_threshold)
    @test isnothing(r1_a.expected_score_dff_probability_practically_positive)
    @test isnothing(r1_a.logit_dff_probability_practically_large)
    @test r1_a.expected_score_dff_practical_magnitude === :not_requested
    @test r1_a.logit_dff_practical_magnitude === :not_requested
    @test r1_a.flag in (:ok, :dff_interval_excludes_zero)

    practical_dff = dff_report(grouped_design, result.draws[1:2, :];
        interval = 0.8,
        expected_score_practical_threshold = 0.0,
        logit_practical_threshold = 0.0,
        practical_probability_threshold = 0.5)
    practical_r1_a = only(row for row in practical_dff
        if row.focal_level == "R1" && row.comparison_level == "A")
    practical_status = function (values, threshold, probability_threshold)
        positive = count(>(threshold), values) / length(values)
        negative = count(<(-threshold), values) / length(values)
        negligible = count(value -> -threshold <= value <= threshold, values) /
            length(values)
        status =
            positive >= probability_threshold ? :practically_positive :
            negative >= probability_threshold ? :practically_negative :
            negligible >= probability_threshold ? :practically_negligible :
            :mixed
        return (; positive, negative, negligible, large = positive + negative,
            status)
    end
    expected_practical = practical_status(expected_score_dff, 0.0, 0.5)
    logit_practical = practical_status(logit_dff, 0.0, 0.5)
    @test practical_r1_a.practical_probability_threshold == 0.5
    @test practical_r1_a.expected_score_dff_practical_threshold == 0.0
    @test practical_r1_a.logit_dff_practical_threshold == 0.0
    @test practical_r1_a.expected_score_dff_probability_practically_positive ≈
        expected_practical.positive
    @test practical_r1_a.expected_score_dff_probability_practically_negative ≈
        expected_practical.negative
    @test practical_r1_a.expected_score_dff_probability_practically_negligible ≈
        expected_practical.negligible
    @test practical_r1_a.expected_score_dff_probability_practically_large ≈
        expected_practical.large
    @test practical_r1_a.expected_score_dff_practical_magnitude ===
        expected_practical.status
    @test practical_r1_a.logit_dff_probability_practically_positive ≈
        logit_practical.positive
    @test practical_r1_a.logit_dff_probability_practically_negative ≈
        logit_practical.negative
    @test practical_r1_a.logit_dff_probability_practically_negligible ≈
        logit_practical.negligible
    @test practical_r1_a.logit_dff_probability_practically_large ≈
        logit_practical.large
    @test practical_r1_a.logit_dff_practical_magnitude === logit_practical.status

    sparse_dff = dff_report(grouped_design, result.draws[1:2, :];
        min_n = grouped_data.n + 1)
    @test all(row -> row.flag === :below_min_n, sparse_dff)
    ad_hoc_dff = dff_report(result; terms = (:rater, :item), draw_indices = [1, 2])
    @test length(ad_hoc_dff) ==
        length(data.rater_levels) * length(data.item_levels)
    @test all(row -> row.validation_status === :ad_hoc_term, ad_hoc_dff)
    @test_throws ArgumentError dff_report(result; draw_indices = [1, 2])
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        terms = [(:rater, :group), (:rater, :group)])
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        terms = (:rater, :unknown))
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        interval = 1.0)
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        min_n = 0)
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        expected_score_practical_threshold = -0.1)
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        logit_practical_threshold = Inf)
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, :];
        practical_probability_threshold = 1.1)
    @test_throws ArgumentError dff_report(grouped_design, result.draws[1:2, 1:end-1])

    replicated = posterior_predict(result; ndraws = 5, rng = MersenneTwister(1234))
    @test size(replicated) == (5, data.n)
    @test all(score -> score in data.category_levels, replicated)
    replicated_by_index = posterior_predict(result; draw_indices = [1, 2], rng = MersenneTwister(1235))
    @test size(replicated_by_index) == (2, data.n)
    @test_throws ArgumentError posterior_predict(result; ndraws = 0)
    @test_throws ArgumentError posterior_predict(result; ndraws = 2, draw_indices = [1])
    @test_throws ArgumentError posterior_predict(result; draw_indices = [0])

    ppc = posterior_predictive_check(result; ndraws = 6, rng = MersenneTwister(5678))
    @test size(ppc.replicated_scores) == (6, data.n)
    @test length(ppc.observed.category_proportions) == length(data.category_levels)
    @test sum(ppc.observed.category_proportions) ≈ 1.0
    @test size(ppc.replicated.category_proportions) == (6, length(data.category_levels))
    @test all(rep -> sum(ppc.replicated.category_proportions[rep, :]) ≈ 1.0,
        axes(ppc.replicated.category_proportions, 1))
    @test size(ppc.replicated.person_mean) == (6, length(data.person_levels))
    @test size(ppc.replicated.rater_mean) == (6, length(data.rater_levels))
    @test size(ppc.replicated.item_mean) == (6, length(data.item_levels))
    @test ppc.category_levels == data.category_levels
    @test ppc.person_levels == data.person_levels
    @test ppc.rater_levels == data.rater_levels
    @test ppc.item_levels == data.item_levels
    @test isempty(ppc.optional_levels)
    @test ppc.grouped.schema == "bayesianmgmfrm.predictive_grouped_summary.v1"
    @test ppc.grouped.n_dff_terms == 0
    @test ppc.grouped.n_dff_cells == 0
    @test ppc.grouped.n_sparse_design_blocks > 0
    ppc_summary = predictive_check_summary(ppc; interval = 0.8)
    @test length(ppc_summary) == expected_n_summary_rows
    @test [row.statistic for row in ppc_summary[1:4]] ==
        [:mean_score, :category_proportion, :category_proportion, :category_proportion]
    @test ppc_summary[1].observed ≈ ppc.observed.mean_score
    @test ppc_summary[1].replicated_lower <= ppc_summary[1].replicated_median <=
        ppc_summary[1].replicated_upper
    @test all(row -> row.n_replicates == 6, ppc_summary)
    ppc_summary_with_blocks = predictive_check_summary(ppc;
        interval = 0.8,
        include_grouped = true)
    @test length(ppc_summary_with_blocks) ==
        expected_n_summary_rows + ppc.grouped.n_sparse_design_blocks
    ppc_sparse_rows = filter(row -> row.statistic === :sparse_design_block_mean,
        ppc_summary_with_blocks)
    @test length(ppc_sparse_rows) == ppc.grouped.n_sparse_design_blocks
    @test all(row -> row.block === :person_rater_item && row.n_observations >= 1,
        ppc_sparse_rows)
    @test all(row -> row.n_replicates == 6, ppc_sparse_rows)
    ppc_by_index = posterior_predictive_check(result; draw_indices = [1, 2], rng = MersenneTwister(5679))
    @test size(ppc_by_index.replicated_scores) == (2, data.n)
    @test ppc_by_index.draw_indices == [1, 2]
    @test_throws ArgumentError posterior_predictive_check(result; ndraws = 0)
    @test_throws ArgumentError posterior_predictive_check(result; ndraws = 2, draw_indices = [1])
end

@testset "scalar validation analytic gradient" begin
    fixture_path = joinpath(@__DIR__, "fixtures", "scalar_validation_known_value.json")
    stan_model_path = joinpath(@__DIR__, "stan", "scalar_gmfrm.stan")
    @test isfile(stan_model_path)
    @test occursin("categorical_logit", read(stan_model_path, String))
    fixture = JSON3.read(read(fixture_path, String))
    @test String(fixture[:schema]) == "bayesianmgmfrm.scalar_validation_known_value.v1"

    fd = scalar_validation_fixture_data(fixture)
    x = Vector{Float64}(fixture[:x])
    expected_lp = Float64(fixture[:log_density])
    expected_gradient = Vector{Float64}(fixture[:gradient])
    fixture_tol = Float64(fixture[:tolerance])
    @test length(x) == scalar_validation_num_params(fd)

    logp = z -> scalar_validation_logposterior(z, fd)

    facet_data = FacetData((
            examinee = ["E1", "E1", "E2", "E2", "E3", "E3"],
            rater = ["R1", "R2", "R1", "R2", "R1", "R2"],
            item = ["I1", "I1", "I1", "I1", "I1", "I1"],
            score = [0, 1, 2, 0, 1, 2],
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score)
    facet_fd = ScalarValidationData(facet_data)
    @test facet_fd.X == facet_data.category
    @test facet_fd.examinee == facet_data.person
    @test facet_fd.rater == facet_data.rater
    @test (facet_fd.J, facet_fd.R, facet_fd.K, facet_fd.N) ==
        (3, 2, 3, length(facet_data))

    multi_item_data = FacetData((
            examinee = ["E1", "E1", "E2", "E2"],
            rater = ["R1", "R2", "R1", "R2"],
            item = ["I1", "I2", "I1", "I2"],
            score = [0, 1, 1, 0],
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score)
    @test_throws ArgumentError ScalarValidationData(multi_item_data)

    lp, g_analytic = scalar_validation_logposterior_and_gradient(x, fd)
    @test lp ≈ logp(x) atol = 1e-10 rtol = 1e-10
    @test lp ≈ expected_lp atol = fixture_tol rtol = fixture_tol
    @test maximum(abs.(g_analytic .- expected_gradient)) < fixture_tol
    o = scalar_validation_offsets(fd)

    stan_fixture_path = joinpath(@__DIR__, "fixtures", "scalar_validation_stan_logdensity.json")
    stan_fixture = JSON3.read(read(stan_fixture_path, String))
    @test String(stan_fixture[:schema]) == "bayesianmgmfrm.scalar_stan_logdensity.v1"
    @test Bool(stan_fixture[:propto]) == false
    @test Bool(stan_fixture[:jacobian]) == true
    @test String(stan_fixture[:stan_model]) == "test/stan/scalar_gmfrm.stan"
    @test String(stan_fixture[:stan_model_sha256]) == file_sha256(stan_model_path)
    @test String(stan_fixture[:known_fixture_sha256]) == file_sha256(fixture_path)
    @test Vector{Float64}(stan_fixture[:x]) == x
    @test Vector{String}(stan_fixture[:stan_parameter_order]) == [
        "theta.1.1",
        "theta.1.2",
        "theta.1.3",
        "theta.1.4",
        "theta.1.5",
        "alpha_i.1.1",
        "beta_i.1",
        "log_alpha_r.1",
        "log_alpha_r.2",
        "log_alpha_r.3",
        "beta_r.1",
        "beta_r.2",
        "beta_r.3",
        "beta_ik.1.1",
        "beta_ik.2.1",
        "beta_ik.3.1",
    ]
    stan_tol = Float64(stan_fixture[:tolerance])
    stan_lp = Float64(stan_fixture[:stan_log_density])
    stan_gradient = Vector{Float64}(stan_fixture[:stan_gradient])
    @test lp ≈ stan_lp atol = stan_tol rtol = stan_tol
    @test maximum(abs.(g_analytic .- stan_gradient)) < stan_tol
    @test LogDensityProblems.logdensity(ScalarValidationLogDensity(fd), x) ≈ lp atol = 1e-10 rtol = 1e-10
    small_stan_row = stan_validation_row(fd, x, stan_lp;
        stan_gradient,
        tolerance = stan_tol,
        label = :scalar_small,
        size = :small,
        known_log_density = expected_lp,
        known_gradient = expected_gradient,
        known_tolerance = fixture_tol,
        fixture_path = relpath(stan_fixture_path, dirname(@__DIR__)),
        known_fixture_path = relpath(fixture_path, dirname(@__DIR__)),
        stan_model = String(stan_fixture[:stan_model]),
        fixture_sha256 = file_sha256(stan_fixture_path),
        known_fixture_sha256 = file_sha256(fixture_path),
        stan_model_sha256 = String(stan_fixture[:stan_model_sha256]),
    )
    @test small_stan_row.passed
    @test small_stan_row.log_density_abs_error == 0.0
    @test small_stan_row.gradient_max_abs_error < stan_tol

    medium_pair = check_scalar_validation_stan_pair(
        joinpath(@__DIR__, "fixtures", "scalar_validation_medium_known_value.json"),
        joinpath(@__DIR__, "fixtures", "scalar_validation_medium_stan_logdensity.json");
        expected_size = "medium",
        expected_counts = (12, 6, 6, 72),
    )
    @test length(medium_pair.x) == 28
    @test medium_pair.data.N > fd.N
    @test medium_pair.data.J > fd.J
    @test medium_pair.log_density < lp
    stan_gate_summary = stan_validation_summary(small_stan_row, medium_pair.validation_row)
    @test stan_gate_summary.passed
    @test stan_gate_summary.n_rows == 2
    @test stan_gate_summary.n_passed_rows == 2
    @test stan_gate_summary.required_sizes == (:medium, :small)
    @test stan_gate_summary.observed_sizes == (:medium, :small)
    @test stan_gate_summary.missing_required_sizes == ()
    @test stan_gate_summary.all_gradient_checked
    @test stan_gate_summary.max_log_density_abs_error <= stan_tol
    @test stan_gate_summary.max_gradient_abs_error < max(stan_tol, 1e-9)
    @test stan_gate_summary.generalized_fit_comparison_status === :not_claimed
    incomplete_stan_gate_summary = stan_validation_summary(small_stan_row)
    @test !incomplete_stan_gate_summary.passed
    @test incomplete_stan_gate_summary.missing_required_sizes == (:medium,)
    @test_throws ArgumentError stan_validation_row(fd, x[1:end-1], stan_lp)
    @test_throws ArgumentError stan_validation_row(fd, x, stan_lp;
        stan_gradient = stan_gradient[1:end-1])
    @test_throws ArgumentError stan_validation_summary(NamedTuple[])

    decoded = scalar_validation_decode(x, fd)
    @test size(decoded.theta) == (1, fd.J)
    @test sum(log.(decoded.trans_alpha_r)) ≈ 0.0 atol = 1e-12
    @test sum(decoded.trans_beta_r) ≈ 0.0 atol = 1e-12
    @test decoded.category_prm[1][end] ≈ 0.0 atol = 1e-12

    Qr = zerosum_basis_fast(fd.R)
    Qs = zerosum_basis_fast(fd.K - 1)
    @test size(Qr) == (fd.R, fd.R - 1)
    @test size(Qs) == (fd.K - 1, fd.K - 2)
    @test maximum(abs.(sum(Qr; dims = 1))) < 1e-12
    @test maximum(abs.(sum(Qs; dims = 1))) < 1e-12
    @test Qr' * Qr ≈ Matrix{Float64}(I, fd.R - 1, fd.R - 1) atol = 1e-12 rtol = 1e-12
    @test Qs' * Qs ≈ Matrix{Float64}(I, fd.K - 2, fd.K - 2) atol = 1e-12 rtol = 1e-12

    @test scalar_validation_contrast_num_params(fd) == scalar_validation_num_params(fd)
    contrast_lp = scalar_validation_logposterior_contrast(x, fd, Qr, Qs)
    contrast_target = ScalarValidationContrastLogDensity(fd, Qr, Qs)
    @test isfinite(contrast_lp)
    @test LogDensityProblems.logdensity(contrast_target, x) ≈ contrast_lp atol = 1e-10 rtol = 1e-10
    contrast_decoded = scalar_validation_decode_contrast(x, fd)
    @test sum(log.(contrast_decoded.trans_alpha_r)) ≈ 0.0 atol = 1e-12
    @test sum(contrast_decoded.trans_beta_r) ≈ 0.0 atol = 1e-12
    @test contrast_decoded.category_prm[1][end] ≈ 0.0 atol = 1e-12

    x_contrast = copy(x)
    raw_log_alpha_r = log.(decoded.trans_alpha_r)
    raw_category_est = diff(decoded.category_prm[1])
    x_contrast[o.o_log_alpha_r:(o.o_log_alpha_r + fd.R - 2)] .= Qr' * raw_log_alpha_r
    x_contrast[o.o_beta_r:(o.o_beta_r + fd.R - 2)] .= Qr' * decoded.trans_beta_r
    x_contrast[o.o_beta_ik:(o.o_beta_ik + fd.K - 3)] .= Qs' * raw_category_est
    matched_contrast_decoded = scalar_validation_decode_contrast(x_contrast, fd)
    @test matched_contrast_decoded.theta ≈ decoded.theta atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.alpha_i ≈ decoded.alpha_i atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.beta_i ≈ decoded.beta_i atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.trans_alpha_r ≈ decoded.trans_alpha_r atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.trans_beta_r ≈ decoded.trans_beta_r atol = 1e-12 rtol = 1e-12
    @test matched_contrast_decoded.category_prm[1] ≈ decoded.category_prm[1] atol = 1e-12 rtol = 1e-12
    @test scalar_validation_logposterior_contrast(x_contrast, fd, Qr, Qs) ≈ lp atol = 1e-10 rtol = 1e-10

    g_reverse = ReverseDiff.gradient(logp, x)
    @test maximum(abs.(g_analytic .- g_reverse)) < 1e-8

    g_forward = ForwardDiff.gradient(logp, x)
    @test maximum(abs.(g_analytic .- g_forward)) < 1e-8

    analytic_target = ScalarValidationAnalyticLogDensity(fd)
    analytic_adapter =
        BayesianMGMFRM._logdensity_gradient_target(analytic_target, x, :analytic)
    @test analytic_adapter.target === analytic_target
    @test analytic_adapter.ad_backend === :analytic
    @test analytic_adapter.gradient_backend === :analytic
    lp_adapter, g_adapter =
        LogDensityProblems.logdensity_and_gradient(analytic_adapter.target, x)
    @test lp_adapter ≈ lp atol = 1e-10 rtol = 1e-10
    @test g_adapter ≈ g_analytic atol = 1e-10 rtol = 1e-10

    coords = unique(round.(Int, range(1, length(x), length = min(length(x), 12))))
    for i in coords
        @test g_analytic[i] ≈ central_difference(logp, x, i) atol = 1e-4 rtol = 1e-4
    end

    x_extreme = zeros(scalar_validation_num_params(fd))
    x_extreme[o.o_theta] = 10.0
    x_extreme[o.o_log_alpha_i] = 4.0
    lp_extreme = scalar_validation_logposterior(x_extreme, fd)
    lp_grad_extreme, _ = scalar_validation_logposterior_and_gradient(x_extreme, fd)
    @test isfinite(lp_extreme)
    @test lp_extreme ≈ lp_grad_extreme atol = 1e-8 rtol = 1e-8
    @test LogDensityProblems.logdensity(analytic_target, x_extreme) ≈
        first(LogDensityProblems.logdensity_and_gradient(analytic_target, x_extreme)) atol = 1e-8 rtol = 1e-8

    external_stan_fixture = get(ENV, "MFRM_STAN_LOGDENSITY_FIXTURE", "")
    if !isempty(external_stan_fixture)
        fixture = JSON3.read(read(external_stan_fixture, String))
        fd_stan = scalar_validation_fixture_data(fixture)
        x_stan = Vector{Float64}(fixture[:x])
        lp_stan = Float64(fixture[:stan_log_density])
        tol = haskey(fixture, :tolerance) ? Float64(fixture[:tolerance]) : 1e-6
        @test length(x_stan) == scalar_validation_num_params(fd_stan)
        lp_julia, g_julia = scalar_validation_logposterior_and_gradient(x_stan, fd_stan)
        @test lp_julia ≈ lp_stan atol = tol rtol = tol
        if haskey(fixture, :stan_gradient)
            g_stan = Vector{Float64}(fixture[:stan_gradient])
            @test maximum(abs.(g_julia .- g_stan)) < max(tol, 1e-6)
        end
    end
end
