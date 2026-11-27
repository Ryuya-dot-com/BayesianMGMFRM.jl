include("../first_analysis.jl")
FirstAnalysisChecks.checks()
include("../standard_onboarding.jl")
mktempdir(StandardOnboardingChecks.checks)
include("../first_analysis_figures.jl")
FirstAnalysisFigureChecks.checks()
include("../normalized_mgmfrm_example.jl")
NormalizedExampleChecks.checks()
include("../refit_plan_integrity.jl")
include("../common_prediction_refit.jl")
mktempdir(CommonPredictionRefitChecks.checks)
include("../common_prediction_kfold.jl")
include("../prediction_mcse.jl")
mktempdir() do directory
    PredictionMCSEChecks.checks(directory)
end
mktempdir(CommonPredictionKfoldChecks.checks)
include("../common_recovery_evaluation.jl")
mktempdir(CommonRecoveryEvaluationChecks.checks)
include("../common_recovery_replications.jl")
mktempdir(CommonRecoveryReplicationChecks.checks)
include("../recovery_planning.jl")
mktempdir(RecoveryPlanningChecks.checks)
mktempdir(RecoveryPlanningChecks.relocation_checks)
mktempdir(RecoveryPlanningChecks.sbc_checks)
mktempdir(RecoveryPlanningChecks.sbc_rank_checks)
include("../recovery_study_summary.jl")
mktempdir(RecoveryStudySummaryChecks.checks)
mktempdir(RecoveryStudySummaryChecks.multi_quantity_checks)
include("../recovery_execution_example.jl")
mktempdir(RecoveryExecutionExampleChecks.checks)
mktempdir(RecoveryExecutionExampleChecks.sbc_checks)
include("../refit_metadata.jl")
include("../prior_sensitivity.jl")
include("../mean_profile_sensitivity.jl")
include("../prior_power_sensitivity.jl")
include("../prior_sensitivity_roundoff.jl")
include("../prior_sensitivity_example.jl")
mktempdir(PriorSensitivityExampleChecks.checks)
include("../prior_predictive_sensitivity.jl")
include("../posterior_ranking.jl")
mktempdir(PosteriorRankingChecks.checks)
include("../posterior_classification.jl")
mktempdir(PosteriorClassificationChecks.checks)
include("../posterior_reliability.jl")
mktempdir(PosteriorReliabilityChecks.checks)
include("../rater_agreement.jl")
mktempdir(RaterAgreementChecks.checks)
include("../intraclass_correlation.jl")
IntraclassCorrelationChecks.finite_checks()
mktempdir() do directory
    IntraclassCorrelationChecks.report_checks(directory, CommonPredictionKfoldChecks.fixture_cases())
end
include("../krippendorff_alpha.jl")
KrippendorffAlphaChecks.finite_checks()
mktempdir() do directory
    KrippendorffAlphaChecks.report_checks(directory,CommonPredictionKfoldChecks.fixture_cases())
end
include("../dff_assignment.jl")
mktempdir(DFFAssignmentChecks.checks)
include("../category_report.jl")
mktempdir(CategoryReportChecks.checks)
include("../category_streaming.jl")
CategoryStreamingChecks.checks()
include("../mcmc_parameter_memory.jl")
MCMCParameterMemoryChecks.checks()
MCMCParameterMemoryChecks.lag_checks()
CategoryStreamingChecks.native_step_checks()
include("../category_report_d1.jl")
CategoryReportD1Checks.checks()
include("../saved_reporting.jl")
mktempdir(SavedReportingChecks.checks)
println("fitting_core runtime: CPU target=", Sys.CPU_NAME,
    "; Julia threads=", Threads.nthreads(), "; BLAS threads=", BLAS.get_num_threads())
# Include compilation of the large test expression, not only its timed body.
@time "fitting_core compile + execute" @eval begin
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
    @test target.design !== design
    @test BayesianMGMFRM.design_identity(target.design).value ==
        BayesianMGMFRM.design_identity(design).value
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
    @test isempty(RuntimePublicLanguagePolicy.runtime_language_violations([
        "actual MFRMFit show" => sprint(show, result),
        "actual MFRMFit text/plain" =>
            sprint(show, MIME"text/plain"(), result),
    ]))
    @test result.design !== design
    @test BayesianMGMFRM.design_identity(result.design).value ==
        BayesianMGMFRM.design_identity(design).value
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
    @test metadata.status_policy.status_label === :supported
    @test metadata.status_policy.public_fit
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
    @test isequal(metadata, fit_metadata(result; view = :full))
    public_metadata = fit_metadata(result; view = :public)
    @test public_metadata.schema ==
        "bayesianmgmfrm.fit_metadata_public.v1"
    @test public_metadata.family === :mfrm
    @test public_metadata.stability === :stable
    @test public_metadata.estimation_status === :supported
    @test isempty(intersect(
        Set(structured_field_names(public_metadata)),
        PRIVATE_READER_FIT_FIELDS,
    ))
    @test reader_payload_is_identity_free(public_metadata)
    @test_throws ArgumentError fit_metadata(result; view = :unknown)

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
    @test all(row -> row.diagnostic_row === :sampler_chain &&
        row.parameter_space === :identified &&
        row.diagnostic_method === :sampler_chain_summary &&
        row.diagnostic_status === :recorded,
        sampler_rows)

    diagnostics = mcmc_diagnostics(result)
    @test length(diagnostics) == length(design.parameter_names)
    @test [row.parameter for row in diagnostics] == design.parameter_names
    @test all(row -> row.n_chains == 3, diagnostics)
    @test all(row -> row.draws_per_chain == 8, diagnostics)
    @test all(row -> row.diagnostic_chains == 6, diagnostics)
    @test all(row -> row.diagnostic_draws_per_chain == 4, diagnostics)
    @test all(row -> row.total_draws == 24, diagnostics)
    @test all(row -> row.split_chains, diagnostics)
    @test all(row -> row.flag in
        (:ok, :mcmc_warning, :insufficient_draws, :nonfinite_draws,
            :degenerate_draws), diagnostics)
    @test all(row -> row.diagnostic_row === :parameter &&
        row.parameter_space === :identified &&
        row.diagnostic_contract === :rank_normalized_rhat_bulk_tail_ess_v1 &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status === :rank_normalized_available &&
        row.flag === row.rank_normalized_flag,
        diagnostics)
    @test all(row -> row.flag === :ok ?
        isfinite(row.rank_normalized_rhat) &&
            row.rank_normalized_rhat <= 1.01 &&
            isfinite(row.bulk_ess) && row.bulk_ess >= 400.0 &&
            isfinite(row.tail_ess) && row.tail_ess >= 400.0 :
        true, diagnostics)
    @test all(row -> row.flag === :mcmc_warning ?
        (isfinite(row.rank_normalized_rhat) &&
                row.rank_normalized_rhat > 1.01 ||
            isfinite(row.bulk_ess) && row.bulk_ess < 400.0 ||
            isfinite(row.tail_ess) && row.tail_ess < 400.0) :
        true, diagnostics)
    @test_throws ArgumentError mcmc_diagnostics(result; rhat_threshold = 1.0)
    @test_throws ArgumentError mcmc_diagnostics(result; ess_threshold = 0)
    unsplit_diagnostics = mcmc_diagnostics(result; split_chains = false)
    @test all(row -> row.diagnostic_chains == 3, unsplit_diagnostics)
    @test all(row -> row.diagnostic_draws_per_chain == 8, unsplit_diagnostics)
    @test all(row -> !row.split_chains, unsplit_diagnostics)
    @test all(row -> row.split_chains_requested === false &&
        row.diagnostic_method ===
            :rank_normalized_unsplit_rhat_bulk_tail_ess,
        unsplit_diagnostics)

    block_rows = parameter_block_diagnostics(result)
    @test [row.block for row in block_rows] == sort(collect(keys(design.blocks)); by = string)
    @test sum(row.n_parameters for row in block_rows) == length(design.parameter_names)
    @test all(row -> row.n_chains == 3, block_rows)
    @test all(row -> row.draws_per_chain == 8, block_rows)
    @test all(row -> row.total_draws == 24, block_rows)
    @test all(row -> row.split_chains, block_rows)
    @test all(row -> row.rhat_threshold == 1.01, block_rows)
    @test all(row -> row.ess_threshold == 400.0, block_rows)
    @test all(row -> row.flag in
        (:ok, :mcmc_warning, :insufficient_chains, :insufficient_draws,
            :nonfinite_draws, :degenerate_draws, :empty_block), block_rows)
    @test all(row -> row.diagnostic_row === :parameter_block &&
        row.parameter_space === :identified &&
        row.diagnostic_contract === :rank_normalized_rhat_bulk_tail_ess_v1 &&
        row.diagnostic_method === :rank_normalized_split_rhat_bulk_tail_ess &&
        row.diagnostic_status === :rank_normalized_available,
        block_rows)
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
    @test diagnostic_surface.diagnostic_row_policy.family === :mfrm
    @test diagnostic_surface.diagnostic_row_policy.parameter_spaces == (:identified,)
    @test diagnostic_surface.diagnostic_row_policy.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test diagnostic_surface.diagnostic_row_policy.rhat_method === :rank_normalized
    @test diagnostic_surface.diagnostic_row_policy.ess_method === :bulk_and_tail
    @test diagnostic_surface.diagnostic_row_policy.rank_normalized_rhat_available
    @test diagnostic_surface.diagnostic_row_policy.bulk_tail_ess_available
    @test diagnostic_surface.backend === result.backend
    @test diagnostic_surface.sampler === result.sampler
    @test diagnostic_surface.summary.n_chains == 3
    @test diagnostic_surface.summary.draws_per_chain == 8
    @test diagnostic_surface.summary.n_parameters == length(design.parameter_names)
    @test diagnostic_surface.summary.flag in
        (:ok, :sampler_warning, :mcmc_warning, :insufficient_chains,
            :insufficient_draws)
    @test diagnostic_surface.summary.n_divergences == 0
    @test ismissing(diagnostic_surface.summary.n_max_treedepth)
    @test ismissing(diagnostic_surface.summary.e_bfmi)
    @test diagnostic_surface.summary.n_block_warnings ==
        count(row -> row.flag in
            (:insufficient_chains, :insufficient_draws, :nonfinite_draws,
                :degenerate_draws, :mcmc_warning), block_rows)
    @test diagnostic_surface.summary.n_empty_blocks == count(row -> row.flag === :empty_block, block_rows)
    @test isequal(diagnostic_surface.sampler_rows, sampler_rows)
    @test isequal(diagnostic_surface.parameter_rows, diagnostics)
    @test isequal(diagnostic_surface.block_rows, block_rows)
    @test isequal(
        diagnostic_surface,
        BayesianMGMFRM.diagnostics(result; view = :full),
    )
    public_diagnostic_surface = BayesianMGMFRM.diagnostics(
        result;
        view = :public,
    )
    @test public_diagnostic_surface.schema ==
        "bayesianmgmfrm.diagnostics_public.v1"
    @test public_diagnostic_surface.family === :mfrm
    @test public_diagnostic_surface.stability === :stable
    @test isempty(intersect(
        Set(structured_field_names(public_diagnostic_surface)),
        PRIVATE_READER_FIT_FIELDS,
    ))
    @test reader_payload_is_identity_free(public_diagnostic_surface)
    @test_throws ArgumentError BayesianMGMFRM.diagnostics(
        result;
        view = :unknown,
    )
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
    @test hmc_result.design !== design
    @test BayesianMGMFRM.design_identity(hmc_result.design).value ==
        BayesianMGMFRM.design_identity(design).value
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
    @test hmc_surface.summary.flag in
        (:ok, :sampler_warning, :mcmc_warning, :insufficient_chains,
            :insufficient_draws)
    @test isequal(hmc_surface.sampler_rows, hmc_sampler_rows)
    hmc_block_rows = parameter_block_diagnostics(hmc_result)
    @test isequal(hmc_surface.block_rows, hmc_block_rows)
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
    @test turing_result.design !== design
    @test BayesianMGMFRM.design_identity(turing_result.design).value ==
        BayesianMGMFRM.design_identity(design).value
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
    @test turing_result.sampler_controls.discard_initial == 2
    @test turing_result.sampler_controls.nadapts == 1
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
    @test turing_metadata.sampler_controls.discard_initial == 2
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
    @test turing_surface.summary.flag in
        (:ok, :sampler_warning, :mcmc_warning, :insufficient_chains,
            :insufficient_draws)
    @test isequal(turing_surface.sampler_rows, turing_sampler_rows)
    turing_block_rows = parameter_block_diagnostics(turing_result)
    @test isequal(turing_surface.block_rows, turing_block_rows)
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
    @test fit_manifest.status_policy.status_label === :supported
    @test fit_manifest.status_policy.public_fit
    @test :real_data_validation in fit_manifest.status_policy.blocked_claims
    @test fit_manifest.fit.n_draws == size(result.draws, 1)
    @test fit_manifest.fit.prior.person_sd == prior.person_sd
    @test fit_manifest.diagnostics.flag == diagnostic_surface.summary.flag
    @test fit_manifest.design.parameter_names == design.parameter_names

    compact_artifact = fit_artifact(result; include_environment = false)
    @test compact_artifact.schema == "bayesianmgmfrm.fit_artifact.v1"
    @test compact_artifact.object === :fit_artifact
    @test compact_artifact.evidence_artifact_schema_policy.artifact_kind ===
        :fit_artifact
    @test compact_artifact.evidence_artifact_schema_policy.environment_policy.include_environment ===
        false
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
    @test compact_artifact.reproducibility.diagnostic_policy.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
    @test compact_artifact.reproducibility.diagnostic_policy.diagnostic_contract_details.id ===
        :rank_normalized_rhat_bulk_tail_ess_v1
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
    public_artifact = fit_artifact(result;
        view = :public,
        include_environment = false,
    )
    @test public_artifact.schema == "bayesianmgmfrm.fit_artifact_public.v1"
    @test public_artifact.stability === :stable
    @test public_artifact.content_hash.scope ===
        :artifact_without_hash_metadata
    @test public_artifact.content_hash.value ==
        artifact_content_hash(public_artifact)
    @test :environment ∉ keys(public_artifact)
    @test :archive_manifest ∉ keys(public_artifact)
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
    public_reproduction_manifest = fit_reproduction_manifest(result;
        view = :public,
        artifact = compact_artifact,
        source_path = "memory://compact_artifact")
    @test public_reproduction_manifest.schema ==
        "bayesianmgmfrm.fit_reproduction_manifest_public.v1"
    @test public_reproduction_manifest.object === :fit_reproduction_manifest
    @test public_reproduction_manifest.content_hash.scope ===
        :artifact_without_hash_metadata
    @test public_reproduction_manifest.content_hash.value ==
        artifact_content_hash(public_reproduction_manifest)
    @test :next_gate ∉ keys(public_reproduction_manifest)
    @test :archive_manifest ∉ keys(public_reproduction_manifest)

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
    @test report.report_status === :complete
    @test report.report_health.complete
    @test report.report_health.n_error_sections == 0
    @test fit_report_health(report) == report.report_health
    report_hash_before_public_projection = artifact_content_hash(report)
    public_report = fit_report_public(report)
    @test public_report.schema == "bayesianmgmfrm.fit_report_public.v1"
    @test public_report.object === :fit_report_public
    @test public_report.status === :supported
    @test public_report.source_report.content_hash ==
        BayesianMGMFRM._public_fit_report_content_hash_record(report).value
    @test artifact_content_hash(report) == report_hash_before_public_projection
    @test !hasproperty(public_report, :manifest)
    @test !hasproperty(public_report, :evidence_artifact_schema_policy)
    @test !hasproperty(public_report.rating_design, :audit)
    @test [row.audit for row in public_report.rating_design.rows] ==
        [row.audit for row in report.rating_design.rows]
    @test !occursin(r"experimental_public|guarded_local_fit|next_gate|test/fixtures/|scripts/generate_",
        JSON3.write(public_report))
    @test isempty(RuntimePublicLanguagePolicy.runtime_language_violations([
        "actual MFRM public report" => JSON3.write(public_report),
        "actual MFRM public Markdown" =>
            fit_report_markdown(public_report; max_rows = 2),
    ]))
    user_label_row = (;
        parameter = "person[_E1]",
        item = "_respondent",
        cell = ("_cell A", "internal consistency"),
        step_path = ["_category 1", "internal consistency"],
        label = (;
            display = "reader label",
            note = "internal_target_constructor",
        ),
        scientific_note = "internal consistency",
        documentation_url = "https://example.org/mnt/guide",
        private_note = "_θ",
        local_path = raw"C:\Temp\private.txt",
        network_path = raw"\\server\private\report.json",
        volume_path = "/Volumes/private/report.json",
        mount_path = "/mnt/private/report.json",
        maintenance_note = "registration\nhandoff",
    )
    user_label_report = merge(report, (;
        dimension_labels = ("_latent", "internal consistency"),
        posterior = merge(report.posterior, (;
            n_rows = 1,
            rows = [user_label_row],
        )),
    ))
    user_label_public_report = fit_report_public(user_label_report)
    @test user_label_public_report.dimension_labels ==
        ("_latent", "internal consistency")
    @test user_label_public_report.posterior.rows[1].parameter == "person[_E1]"
    @test user_label_public_report.posterior.rows[1].item == "_respondent"
    @test user_label_public_report.posterior.rows[1].cell ==
        ("_cell A", "internal consistency")
    @test user_label_public_report.posterior.rows[1].step_path ==
        Any["_category 1", "internal consistency"]
    @test user_label_public_report.posterior.rows[1].label.display ==
        "reader label"
    @test !hasproperty(user_label_public_report.posterior.rows[1].label, :note)
    @test user_label_public_report.posterior.rows[1].scientific_note ==
        "internal consistency"
    @test user_label_public_report.posterior.rows[1].documentation_url ==
        "https://example.org/mnt/guide"
    for field in (
            :private_note, :local_path, :network_path, :volume_path,
            :mount_path, :maintenance_note)
        @test !hasproperty(user_label_public_report.posterior.rows[1], field)
    end
    user_label_markdown = fit_report_markdown(user_label_public_report;
        max_rows = 2)
    for text in (
            "person[_E1]", "_respondent", "step_path", "_category 1",
            "internal consistency", "_latent", "_cell A", "reader label",
            "https://example.org/mnt/guide")
        @test occursin(text, user_label_markdown)
    end
    @test !occursin("_No rows to preview._", user_label_markdown)
    forged_label_row = merge(first(public_report.posterior.rows), (;
        label = (;
            display = "reader label",
            note = "internal_target_constructor",
        ),
    ))
    forged_label_payload = merge(public_report, (;
        posterior = merge(public_report.posterior, (;
            n_rows = 1,
            rows = [forged_label_row],
        )),
    ))
    forged_label_report = merge(forged_label_payload, (;
        content_hash = BayesianMGMFRM._public_fit_report_content_hash_record(
            forged_label_payload),
    ))
    @test_throws ArgumentError fit_report_public(forged_label_report)
    @test report.schema == "bayesianmgmfrm.fit_report.v1"
    @test report.object === :fit_report
    @test report.family === :mfrm
    @test report.status_policy.status_label === :supported
    @test report.status_policy === report.manifest.status_policy
    @test report.evidence_artifact_schema_policy.artifact_kind === :fit_report
    @test :model_weight_or_superiority in
        report.evidence_artifact_schema_policy.claim_policy.unsupported_claims
    @test report.metadata.status_policy == report.status_policy
    @test report.metadata.n_draws == size(result.draws, 1)
    @test report.prior_policy.status === :computed
    @test !report.prior_policy.summary.raw_coordinate_generalized_priors
    @test !report.prior_policy.summary.raw_prior_control_manifest_recorded
    @test ismissing(report.prior_policy.summary.raw_prior_control_all_active_scales_resolved)
    @test isnothing(report.prior_policy.raw_prior_control_manifest)
    @test report.prior_policy.summary.jacobian_policy === :identity
    @test all(row -> row.parameter_space === :identified_constrained_parameter,
        report.prior_policy.rows)
    @test any(row -> row.block === :person &&
        row.scale_parameter === :person_sd &&
        row.scale == prior.person_sd &&
        row.direct_scale_prior,
        report.prior_policy.rows)
    @test report.pooling_policy.status === :computed
    @test report.pooling_policy.summary.independent_priors_default
    @test !report.pooling_policy.summary.hierarchical_pooling_active
    @test any(row -> row.block === :rater_consistency &&
        row.status === :not_applicable,
        report.pooling_policy.rows)
    @test report.mcmc_budget_guidance.status === :unsupported
    @test occursin("guarded MGMFRM",
        report.mcmc_budget_guidance.reason)
    @test report.rating_design.status === :computed
    @test report.rating_design.schema == "bayesianmgmfrm.rating_design_audit.v1"
    @test report.rating_design.summary.nonignorable_assignment_flagged
    @test isequal(report.rating_design.audit, report.manifest.rating_design)
    @test any(row -> row.audit === :nonignorable_assignment &&
        row.status === :limitation,
        report.rating_design.rows)
    @test report.manifest.object === :fit
    @test isequal(report.manifest.rating_design, report.rating_design.audit)
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
    @test :rating_design in report_section_names
    @test :mcmc_budget_guidance in report_section_names
    @test :prior_policy in report_section_names
    @test :pooling_policy in report_section_names
    @test :posterior in report_section_names
    @test :waic in report_section_names
    prior_policy_section = only(filter(row -> row.section === :prior_policy,
        report_sections))
    @test prior_policy_section.status === :computed
    @test prior_policy_section.row_fields == [:rows]
    @test prior_policy_section.n_rows == report.prior_policy.n_rows
    pooling_policy_section = only(filter(row -> row.section === :pooling_policy,
        report_sections))
    @test pooling_policy_section.status === :computed
    @test pooling_policy_section.row_fields == [:rows]
    @test pooling_policy_section.n_rows == report.pooling_policy.n_rows
    mcmc_budget_section = only(filter(row ->
            row.section === :mcmc_budget_guidance,
        report_sections))
    @test mcmc_budget_section.status === :unsupported
    @test isempty(mcmc_budget_section.row_fields)
    @test mcmc_budget_section.n_rows == 0
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
    rating_design_section = only(filter(row -> row.section === :rating_design,
        report_sections))
    @test rating_design_section.status === :computed
    @test rating_design_section.row_fields == [:rows]
    @test rating_design_section.n_rows == report.rating_design.n_rows
    @test fit_report_section(report, :posterior) === report.posterior
    @test fit_report_section(report, :rating_design) === report.rating_design
    @test fit_report_section(report, "calibration") === report.calibration
    @test fit_report_rows(report, :posterior) === report.posterior.rows
    @test fit_report_rows(report, :rating_design) === report.rating_design.rows
    @test fit_report_rows(report, :prior_policy) === report.prior_policy.rows
    @test fit_report_rows(report, :pooling_policy) === report.pooling_policy.rows
    @test fit_report_rows(report, :waic) === report.waic.diagnostic_rows
    @test fit_report_rows(report, :diagnostics; row_field = :parameter_rows) ===
        report.diagnostics.parameter_rows
    @test_throws ArgumentError fit_report_section(report, :missing_section)
    @test_throws ArgumentError fit_report_rows(report, :artifact)
    @test_throws ArgumentError fit_report_rows(report, :posterior;
        row_field = :diagnostic_rows)
    report_dir = mktempdir()
    invalid_public_payload = merge(public_report, (;
        next_gate = :private_review_step,
    ))
    invalid_public_report = merge(invalid_public_payload, (;
        content_hash = BayesianMGMFRM._public_fit_report_content_hash_record(
            invalid_public_payload),
    ))
    invalid_public_json_path = joinpath(report_dir, "invalid_public.json")
    invalid_public_table_dir = joinpath(report_dir, "invalid_public_tables")
    invalid_public_markdown_path = joinpath(report_dir, "invalid_public.md")
    invalid_public_bundle_dir = joinpath(report_dir, "invalid_public_bundle")
    @test_throws ArgumentError save_fit_report(
        invalid_public_json_path, invalid_public_report)
    @test_throws ArgumentError save_fit_report_tables(
        invalid_public_table_dir, invalid_public_report)
    @test_throws ArgumentError fit_report_markdown(invalid_public_report)
    @test_throws ArgumentError save_fit_report_markdown(
        invalid_public_markdown_path, invalid_public_report)
    @test_throws ArgumentError save_fit_report_bundle(
        invalid_public_bundle_dir, invalid_public_report)
    @test_throws ArgumentError fit_report_dossier(
        :invalid => invalid_public_report)
    @test !ispath(invalid_public_json_path)
    @test !ispath(invalid_public_table_dir)
    @test !ispath(invalid_public_markdown_path)
    @test !ispath(invalid_public_bundle_dir)
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
    @test report_export.schema == "bayesianmgmfrm.fit_report_export.v2"
    @test report_export.object === :fit_report_export
    @test report_export.report_schema == report.schema
    @test report_export.report_object === :fit_report
    @test report_export.report_content_hash.value == report_hash
    @test report_export.json_content_hash.value ==
        BayesianMGMFRM._fit_report_json_hash_record(report_export.report;
            canonicalization = :cache_stable_string_exact_integers_v1).value
    @test public_report.source_report.content_hash ==
        BayesianMGMFRM._fit_report_json_hash_record(report_export.report).value
    loaded_report = load_fit_report(report_path)
    @test loaded_report["schema"] == report.schema
    @test loaded_report["object"] == "fit_report"
    @test loaded_report["posterior"]["n_rows"] == report.posterior.n_rows
    loaded_public_report = fit_report_public(loaded_report)
    @test !haskey(loaded_public_report.rating_design, "audit")
    @test [row["audit"] for row in
        loaded_public_report.rating_design["rows"]] ==
        [row["audit"] for row in loaded_report["rating_design"]["rows"]]
    public_report_path = joinpath(report_dir, "minimal_fit_report_public.json")
    public_report_export = save_fit_report(public_report_path, public_report)
    @test !hasproperty(public_report_export, :source_path)
    @test public_report_export.report_content_hash == public_report.content_hash
    @test load_fit_report(public_report_path)["schema"] == public_report.schema
    for invalid_nbytes in (true, -1, 1.5, "1", missing)
        invalid_hash_record = (;
            content_hash = (;
                algorithm = :sha256,
                value = repeat("0", 64),
                scope = :public_json_without_top_level_content_hash,
                canonicalization = :cache_stable_string,
                n_canonical_bytes = invalid_nbytes,
            ),
        )
        @test_throws ArgumentError BayesianMGMFRM._check_fit_report_hash_record(
            invalid_hash_record,
            :content_hash,
            "invalid hash byte count";
            expected_scope = :public_json_without_top_level_content_hash,
            expected_canonicalization = :cache_stable_string)
    end
    tampered_public_wrapper = JSON3.read(read(public_report_path, String),
        Dict{String,Any})
    tampered_public_wrapper["report_content_hash"]["value"] = repeat("0", 64)
    tampered_public_wrapper_path = joinpath(report_dir,
        "tampered_fit_report_public_wrapper.json")
    open(tampered_public_wrapper_path, "w") do io
        JSON3.write(io, tampered_public_wrapper)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(tampered_public_wrapper_path;
        verify_hash = false)
    invalid_hash_bytes_record = JSON3.read(read(public_report_path, String),
        Dict{String,Any})
    invalid_hash_bytes_record["json_content_hash"]["n_canonical_bytes"] = true
    invalid_hash_bytes_path = joinpath(report_dir,
        "invalid_fit_report_hash_bytes.json")
    open(invalid_hash_bytes_path, "w") do io
        JSON3.write(io, invalid_hash_bytes_record)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(invalid_hash_bytes_path;
        verify_hash = false)
    mismatched_hash_bytes_record = JSON3.read(read(public_report_path, String),
        Dict{String,Any})
    mismatched_hash_bytes_record["json_content_hash"]["n_canonical_bytes"] += 1
    mismatched_hash_bytes_path = joinpath(report_dir,
        "mismatched_fit_report_hash_bytes.json")
    open(mismatched_hash_bytes_path, "w") do io
        JSON3.write(io, mismatched_hash_bytes_record)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(mismatched_hash_bytes_path)
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
    @test propertynames(dossier.report_policy) ==
        (:include_reports, :rendering_scope, :require_complete)
    @test !dossier.report_policy.require_complete
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
    @test !hasproperty(first(dossier.evidence_rows),
        :publication_or_registration_action)
    dossier_json = JSON3.write(dossier)
    @test !occursin(
        r"publication_or_registration_action|manuscript_claims_allowed|next_gate|source_path",
        dossier_json)
    embedded_dossier = fit_report_dossier(report;
        names = [:minimal],
        include_reports = true)
    @test embedded_dossier.n_reports == 1
    @test length(embedded_dossier.reports) == 1
    @test only(embedded_dossier.reports).schema ==
        "bayesianmgmfrm.fit_report_public.v1"
    @test !occursin(
        r"publication_or_registration_action|manuscript_claims_allowed|next_gate|source_path",
        JSON3.write(embedded_dossier))
    @test_throws ArgumentError fit_report_dossier()
    @test_throws ArgumentError fit_report_dossier(report, loaded_report;
        names = [:dup, :dup])
    @test_throws ArgumentError fit_report_dossier(:bad => report;
        comparison_rows = [1])
    invalid_dossier = merge(dossier, (;
        next_gate = :manual_publication_or_registration_by_user_only,
    ))
    @test_throws ArgumentError fit_report_dossier_markdown(invalid_dossier)
    invalid_dossier_path = joinpath(report_dir, "invalid_fit_report_dossier.json")
    @test_throws ArgumentError save_fit_report_dossier(
        invalid_dossier_path, invalid_dossier)
    @test !ispath(invalid_dossier_path)

    dossier_markdown = fit_report_dossier_markdown(dossier;
        title = "Minimal fit report dossier",
        max_rows = 1)
    @test startswith(dossier_markdown, "# Minimal fit report dossier")
    @test occursin("## Dossier Metadata", dossier_markdown)
    @test occursin("## Report Summary", dossier_markdown)
    @test occursin("## Section Summary", dossier_markdown)
    @test occursin("## Comparison Rows", dossier_markdown)
    @test occursin("Interpret results within the documented model scope.",
        dossier_markdown)
    @test !occursin(r"publication_or_registration_action|manuscript_claims_allowed|next_gate",
        dossier_markdown)
    @test_throws ArgumentError fit_report_dossier_markdown(dossier; max_rows = -1)

    dossier_path = joinpath(report_dir, "minimal_fit_report_dossier.json")
    dossier_export = save_fit_report_dossier(dossier_path, dossier;
        label = :minimal_dossier)
    @test isfile(dossier_path)
    @test dossier_export.schema ==
        "bayesianmgmfrm.fit_report_dossier_export.v1"
    @test dossier_export.object === :fit_report_dossier_export
    @test dossier_export.label === :minimal_dossier
    @test !hasproperty(dossier_export, :source_path)
    @test dossier_export.dossier_schema == dossier.schema
    @test dossier_export.dossier_object === :fit_report_dossier
    @test length(dossier_export.dossier_content_hash.value) == 64
    @test length(dossier_export.json_content_hash.value) == 64
    @test !occursin(report_dir, read(dossier_path, String))
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
    @test !haskey(loaded_dossier_record, "source_path")
    @test loaded_dossier_record["dossier_content_hash"]["value"] ==
        BayesianMGMFRM._artifact_content_hash_record(loaded_dossier).value

    legacy_source_path = "/Users/legacy/private/minimal_fit_report_dossier.json"
    legacy_dossier = merge(embedded_dossier, (;
        report_policy = (;
            include_reports = true,
            rendering_scope = :review_dossier,
            publication_or_registration_action = false,
            manuscript_claims_allowed = false,
            next_gate = :manual_publication_or_registration_by_user_only,
        ),
        n_evidence_rows = 1,
        evidence_rows = [(;
            evidence = :fit_report_review_bundle,
            status = :recorded,
            publication_or_registration_action = false,
            next_gate = :manual_publication_or_registration_by_user_only,
            source_path = legacy_source_path,
        )],
        reports = (report,),
    ))
    legacy_json_dossier = BayesianMGMFRM._json_export_value(legacy_dossier)
    legacy_dossier_export = (;
        schema = "bayesianmgmfrm.fit_report_dossier_export.v1",
        object = :fit_report_dossier_export,
        created_at = dossier_export.created_at,
        label = :v0_1_0_compatibility,
        source_path = legacy_source_path,
        serialization = dossier_export.serialization,
        dossier_schema = legacy_dossier.schema,
        dossier_object = legacy_dossier.object,
        dossier_content_hash =
            BayesianMGMFRM._artifact_content_hash_record(legacy_dossier),
        json_content_hash =
            BayesianMGMFRM._fit_report_dossier_json_hash_record(
                legacy_json_dossier),
        dossier = legacy_json_dossier,
    )
    legacy_dossier_path = joinpath(report_dir,
        "v0_1_0_fit_report_dossier.json")
    open(legacy_dossier_path, "w") do io
        JSON3.write(io,
            BayesianMGMFRM._json_export_value(legacy_dossier_export))
        write(io, "\n")
    end
    loaded_legacy_dossier = load_fit_report_dossier(legacy_dossier_path)
    @test Set(keys(loaded_legacy_dossier["report_policy"])) ==
        Set(["include_reports", "rendering_scope", "require_complete"])
    @test loaded_legacy_dossier["report_policy"]["include_reports"]
    @test loaded_legacy_dossier["report_policy"]["rendering_scope"] ==
        "review_dossier"
    @test !loaded_legacy_dossier["report_policy"]["require_complete"]
    @test only(loaded_legacy_dossier["reports"])["schema"] ==
        "bayesianmgmfrm.fit_report_public.v1"
    @test only(loaded_legacy_dossier["reports"])["object"] ==
        "fit_report_public"
    loaded_legacy_json = JSON3.write(loaded_legacy_dossier)
    @test !occursin(legacy_source_path, loaded_legacy_json)
    @test !occursin(
        r"publication_or_registration_action|manuscript_claims_allowed|next_gate|source_path",
        loaded_legacy_json)
    loaded_legacy_record = load_fit_report_dossier(legacy_dossier_path;
        return_record = true)
    @test !haskey(loaded_legacy_record, "source_path")
    @test loaded_legacy_record["dossier"] == loaded_legacy_dossier
    @test loaded_legacy_record["dossier_content_hash"]["value"] ==
        BayesianMGMFRM._artifact_content_hash_record(
            loaded_legacy_dossier).value
    @test loaded_legacy_record["json_content_hash"]["value"] ==
        BayesianMGMFRM._fit_report_dossier_json_hash_record(
            loaded_legacy_dossier).value
    legacy_dossier_markdown = fit_report_dossier_markdown(
        loaded_legacy_dossier;
        title = "Loaded v0.1.0 fit report dossier",
        max_rows = 1)
    @test startswith(legacy_dossier_markdown,
        "# Loaded v0.1.0 fit report dossier")
    @test !occursin(
        r"publication_or_registration_action|manuscript_claims_allowed|next_gate|source_path|/Users/",
        legacy_dossier_markdown)
    legacy_resaved_path = joinpath(report_dir,
        "v0_1_0_fit_report_dossier_resaved.json")
    legacy_resaved_export = save_fit_report_dossier(
        legacy_resaved_path,
        loaded_legacy_dossier)
    @test !hasproperty(legacy_resaved_export, :source_path)
    @test !occursin(
        r"publication_or_registration_action|manuscript_claims_allowed|next_gate|source_path|/Users/",
        read(legacy_resaved_path, String))
    @test only(load_fit_report_dossier(
        legacy_resaved_path)["reports"])["schema"] ==
        "bayesianmgmfrm.fit_report_public.v1"

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
    @test !hasproperty(dossier_markdown_export, :source_path)
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
    @test_throws ArgumentError load_fit_report(tampered_path;
        verify_hash = false)

    tampered_record = deepcopy(loaded_record)
    tampered_record["report"]["created_at"] = "tampered"
    open(tampered_path, "w") do io
        JSON3.write(io, tampered_record)
        write(io, "\n")
    end
    @test_throws ArgumentError load_fit_report(tampered_path)
    @test load_fit_report(tampered_path;
        verify_hash = false)["created_at"] == "tampered"

    too_short_report = fit_report(spec_result;
        artifact_include_environment = false)
    @test too_short_report.loo.status === :error
    @test too_short_report.loo.exception === :ArgumentError
    @test occursin("LOO requires at least three posterior draws",
        too_short_report.loo.message)
    @test too_short_report.report_status === :incomplete
    @test !too_short_report.report_health.complete
    @test too_short_report.report_health.n_error_sections == 1
    @test only(too_short_report.report_health.error_sections).section === :loo
    @test_throws ArgumentError fit_report(result; on_section_error = :invalid)
    @test_throws ArgumentError fit_report(spec_result;
        artifact_include_environment = false,
        on_section_error = :throw)
    @test_throws ArgumentError fit_report(spec_result;
        artifact_include_environment = false,
        require_complete = true)

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
    @test_throws ArgumentError fit_reproduction_manifest(spec_result;
        cache_record,
        cache_path,
        include_environment = false)
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
    public_sim_grid = simulation_grid(;
        densities = (:sparse,),
        anchor_sizes = (0,),
        ratings_per_target = (1,),
        category_pathologies = (:none,),
        rater_noise = (:low,),
        dff = (:none,),
        dimensionalities = (1,),
        misspecifications = (:none,),
        n_raters = 2,
        view = :public,
    )
    @test first(public_sim_grid).schema ==
        "bayesianmgmfrm.simulation_grid_public.v1"
    @test :next_gate ∉ keys(first(public_sim_grid))
    public_mgmfrm_grid = simulation_grid(;
        densities = (:sparse,),
        anchor_sizes = (0,),
        ratings_per_target = (1,),
        category_pathologies = (:none,),
        rater_noise = (:low,),
        dff = (:none,),
        dimensionalities = (2,),
        misspecifications = (:none, :omitted_dff),
        n_raters = 2,
        view = :public,
    )
    @test any(row -> row.fit_surface ===
        :fixed_q_confirmatory_mgmfrm_preview, public_mgmfrm_grid)
    public_gmfrm_comparison_grid = simulation_grid(;
        densities = (:sparse,),
        anchor_sizes = (0,),
        ratings_per_target = (1,),
        category_pathologies = (:none,),
        rater_noise = (:low,),
        dff = (:none,),
        dimensionalities = (1,),
        misspecifications = (:omitted_dff,),
        n_raters = 2,
        view = :public,
    )
    @test only(public_gmfrm_comparison_grid).fit_surface ===
        :mfrm_baseline_or_experimental_gmfrm_comparison
    @test !occursin("guarded", JSON3.write(public_mgmfrm_grid))
    @test !occursin("guarded", JSON3.write(public_gmfrm_comparison_grid))
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
    @test isequal(grid_summary, simulation_grid_summary(sim_grid; view = :full))
    public_grid_summary = simulation_grid_summary(sim_grid; view = :public)
    @test public_grid_summary.schema ==
        "bayesianmgmfrm.simulation_grid_summary_public.v1"
    @test :next_gate ∉ keys(public_grid_summary)
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
    @test_throws ArgumentError simulation_grid(; view = :unknown)
    @test_throws ArgumentError simulation_grid_summary(NamedTuple[])
    @test_throws ArgumentError simulation_grid_summary(Any[1])
    @test_throws ArgumentError simulation_grid_summary(sim_grid; view = :unknown)

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
    @test isequal(
        rule_summary,
        falsification_rule_summary(rules; view = :full),
    )
    public_rule_summary = falsification_rule_summary(rules; view = :public)
    @test public_rule_summary.schema ==
        "bayesianmgmfrm.falsification_rule_summary_public.v1"
    @test :next_gate ∉ keys(public_rule_summary)
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
    @test_throws ArgumentError falsification_rule_summary(
        rules;
        view = :unknown,
    )

    active_test_project = Base.active_project()
    subprocess_project_dir = if isnothing(active_test_project)
        dirname(dirname(@__DIR__))
    else
        dirname(active_test_project)
    end

    validation_plan_script =
        joinpath(dirname(dirname(@__DIR__)), "scripts", "generate_validation_plan.jl")
    @test isfile(validation_plan_script)
    validation_plan_path = tempname() * ".json"
    run(`$(Base.julia_cmd()) --startup-file=no --project=$subprocess_project_dir
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

    if RUN_RESEARCH_EVIDENCE_TESTS
    design_robustness_script = joinpath(
        dirname(dirname(@__DIR__)),
        "scripts",
        "generate_existing_api_design_robustness_plan.jl",
    )
    design_robustness_fixture = joinpath(
        dirname(dirname(@__DIR__)),
        "test",
        "fixtures",
        "existing_api_design_robustness_plan.json",
    )
    @test isfile(design_robustness_script)
    @test isfile(design_robustness_fixture)
    design_robustness_path = tempname() * ".json"
    run(`$(Base.julia_cmd()) --startup-file=no --project=$subprocess_project_dir
        $design_robustness_script --output $design_robustness_path`)
    @test read(design_robustness_path, String) ==
        read(design_robustness_fixture, String)
    design_robustness = JSON3.read(read(design_robustness_path, String))
    @test String(design_robustness[:schema]) ==
        "bayesianmgmfrm.existing_api_design_robustness_plan.v1"
    @test String(design_robustness[:scope]) ==
        "existing_static_api_design_robustness"
    @test String(design_robustness[:status]) ==
        "deterministic_contract_checks_passed_recovery_not_run"
    @test Bool(design_robustness[:public_claim_release_allowed]) == false
    @test Bool(design_robustness[:publication_or_registration_action]) == false
    references = design_robustness[:reference_records]
    @test length(references) == 7
    @test all(row -> !haskey(row, :item_key) && !haskey(row, :zotero_key),
        references)
    @test Set(String(row[:source]) for row in references) == Set(["doi", "url"])
    current_evidence = design_robustness[:current_evidence_audit]
    @test length(current_evidence) == 2
    @test all(row -> Bool(row[:summary_passed]), current_evidence)
    @test all(row -> Bool(row[:design_robustness_claim_supported]) == false,
        current_evidence)
    @test Bool(design_robustness[:current_evidence_boundary][
        :generic_simulation_grid_runs_fits]) == false
    @test Bool(design_robustness[:current_evidence_boundary][
        :generic_anchor_size_materializes_linking_targets]) == false
    checks = design_robustness[:deterministic_contract_checks]
    @test length(checks) == 7
    @test all(row -> Bool(row[:passed]), checks)
    @test Set(String(row[:check_id]) for row in checks) == Set([
        "row_order_equivariance",
        "occasion_metadata_not_likelihood",
        "ability_nested_no_link_negative_control",
        "materialized_common_linking_fraction_5pct",
        "materialized_common_linking_fraction_10pct",
        "parameter_anchor_guard",
        "simulation_grid_anchor_size_is_planning_metadata",
    ])
    nested_check = only(row for row in checks
        if String(row[:check_id]) == "ability_nested_no_link_negative_control")
    row_order_check = only(row for row in checks
        if String(row[:check_id]) == "row_order_equivariance")
    @test Float64(row_order_check[:achieved_multiply_scored_target_fraction]) ==
        1.0
    @test Float64(row_order_check[:achieved_all_raters_common_target_fraction]) ==
        0.0
    @test Float64(row_order_check[:max_aligned_pointwise_loglikelihood_error]) ==
        0.0
    @test Float64(row_order_check[:absolute_total_loglikelihood_error]) == 0.0
    @test String(row_order_check[:error_normalization_policy]) ==
        "at_or_below_tolerance_reported_as_zero"
    @test Bool(nested_check[:validation_passed]) == false
    @test Bool(nested_check[:rating_design_audit_passed]) == false
    @test String(nested_check[:rater_linking_status]) == "disconnected"
    @test "rank_deficient_design" in
        String.(nested_check[:validation_issue_codes])
    linking_checks = filter(row -> startswith(
        String(row[:check_id]),
        "materialized_common_linking_fraction_",
    ), checks)
    @test Set(Float64(row[:achieved_multiply_scored_target_fraction])
        for row in linking_checks) == Set([0.05, 0.10])
    @test Set(Float64(row[:achieved_all_raters_common_target_fraction])
        for row in linking_checks) == Set([0.05, 0.10])
    @test all(row -> Float64(row[:controlled_benchmark_target_fraction]) == 0.0,
        linking_checks)
    @test all(row -> String(row[:rating_budget_policy]) == "additive",
        linking_checks)
    @test all(row -> Int(row[:parameter_anchor_count]) == 0, linking_checks)
    @test all(row -> Bool(row[:assignment_warning_retained]), linking_checks)
    anchor_guard = only(row for row in checks
        if String(row[:check_id]) == "parameter_anchor_guard")
    @test String(anchor_guard[:estimation_status]) == "specified_only"
    @test Bool(anchor_guard[:ordinary_design_compilation_blocked])
    @test String(anchor_guard[:interpretation]) ==
        "parameter_anchor_not_materialized_linking_response"
    scenarios = design_robustness[:mandatory_scenarios]
    @test length(scenarios) == 9
    @test Set(String(row[:scenario_id]) for row in scenarios) == Set([
        "C0_balanced_random_double_rated",
        "C0P_same_ratings_row_permuted",
        "C1_ability_nested_no_link",
        "C2A_nested_5pct_link_early_additive",
        "C2P_same_ratings_5pct_link_distributed",
        "C2F_nested_5pct_link_early_fixed_total",
        "C3A_nested_10pct_link_distributed_additive",
        "C3F_nested_10pct_link_distributed_fixed_total",
        "C4_ability_nested_10pct_narrow_support",
    ])
    @test Set(Float64(value) for value in
        design_robustness[:study_axes][:common_linking_target_fraction]) ==
        Set([0.0, 0.02, 0.05, 0.10, 0.20])
    @test Set(String(value) for value in
        design_robustness[:study_axes][:rating_budget_policy]) ==
        Set(["additive", "fixed_total_target_displacement"])
    @test Bool(design_robustness[:design_selection][:full_factorial_allowed]) ==
        false
    @test length(design_robustness[:order_misspecification_scenarios]) == 5
    baseline = only(row for row in scenarios
        if String(row[:scenario_id]) == "C0_balanced_random_double_rated")
    @test Float64(baseline[:planned_multiply_scored_target_fraction]) == 1.0
    @test Float64(baseline[:common_linking_target_fraction]) == 0.0
    @test Float64(baseline[:controlled_benchmark_target_fraction]) == 0.0
    fixed_budget = only(row for row in scenarios
        if String(row[:scenario_id]) ==
            "C3F_nested_10pct_link_distributed_fixed_total")
    @test String(fixed_budget[:rating_budget_policy]) ==
        "fixed_total_target_displacement"
    @test Int(fixed_budget[:planned_total_rating_events]) == 400
    @test Float64(fixed_budget[:planned_multiply_scored_target_fraction]) == 0.10
    @test Float64(fixed_budget[
        :planned_multiply_scored_target_fraction_observed]) == 0.20
    @test Float64(fixed_budget[:planned_dropped_target_fraction]) == 0.50
    stages = design_robustness[:execution_stages]
    @test String(stages[1][:status]) == "passed"
    @test String(stages[2][:status]) == "predeclared_not_run"
    @test Bool(design_robustness[:execution_policy][
        :deterministic_checks_executed])
    @test Bool(design_robustness[:execution_policy][
        :mcmc_fits_executed]) == false
    design_robustness_summary = design_robustness[:summary]
    @test Bool(design_robustness_summary[:passed])
    @test Int(design_robustness_summary[:n_deterministic_checks]) == 7
    @test Int(design_robustness_summary[:n_deterministic_checks_passed]) == 7
    @test Bool(design_robustness_summary[:paired_known_truth_recovery_completed]) == false
    @test Bool(design_robustness_summary[:design_robustness_claim_supported]) == false
    @test String(design_robustness_summary[:next_gate]) ==
        "existing_api_design_robustness_stress_grid"
    @test String(design_robustness[:content_hash][:algorithm]) == "sha256"
    @test length(String(design_robustness[:content_hash][:value])) == 64
    rm(design_robustness_path; force = true)

    design_stress_script = joinpath(
        dirname(dirname(@__DIR__)),
        "scripts",
        "generate_existing_api_design_robustness_stress_grid.jl",
    )
    design_stress_fixture = joinpath(
        dirname(dirname(@__DIR__)),
        "test",
        "fixtures",
        "existing_api_design_robustness_stress_grid.json",
    )
    @test isfile(design_stress_script)
    @test isfile(design_stress_fixture)
    protected_fixture_bytes = read(design_stress_fixture)
    blocked_fixture_output = IOBuffer()
    blocked_fixture_process = run(pipeline(ignorestatus(
        `$(Base.julia_cmd()) --startup-file=no --project=$subprocess_project_dir
            $design_stress_script --execute --output $design_stress_fixture`);
        stdout = blocked_fixture_output,
        stderr = blocked_fixture_output,
    ))
    @test !success(blocked_fixture_process)
    @test read(design_stress_fixture) == protected_fixture_bytes
    @test occursin(
        "--execute output must not resolve to the deterministic fixture",
        String(take!(blocked_fixture_output)),
    )
    design_stress_path = tempname() * ".json"
    run(`$(Base.julia_cmd()) --startup-file=no --project=$subprocess_project_dir
        $design_stress_script --output $design_stress_path`)
    design_stress = JSON3.read(read(design_stress_path, String))
    committed_design_stress = JSON3.read(read(design_stress_fixture, String))
    expected_package_version = string(pkgversion(BayesianMGMFRM))
    @test String(design_stress[:package][:version]) ==
        expected_package_version
    @test String(committed_design_stress[:package][:version]) ==
        expected_package_version
    committed_runtime = committed_design_stress[:runtime_provenance]
    @test String(committed_runtime[:julia_version]) == "1.10.8"
    @test String(committed_runtime[:manifest_file]) == "Manifest-v1.10.toml"
    @test String(committed_runtime[:manifest_toml_sha256]) == file_sha256(
        joinpath(dirname(dirname(@__DIR__)), "Manifest-v1.10.toml"),
    )
    function stress_local_json_value(value)
        if value isa AbstractDict
            materialized_pairs = collect(pairs(value))
            names = Tuple(Symbol(String(pair.first)) for pair in materialized_pairs)
            values = Tuple(stress_local_json_value(pair.second)
                for pair in materialized_pairs)
            return NamedTuple{names}(values)
        elseif value isa AbstractArray || value isa Tuple
            return [stress_local_json_value(element) for element in value]
        end
        return value
    end
    function stress_recomputed_content_hash(artifact)
        named = stress_local_json_value(artifact)
        without_hash = (; (key => value for (key, value) in pairs(named)
            if key !== :content_hash)...)
        io = IOBuffer()
        write_canonical_json(io, without_hash)
        return bytes2hex(sha256(take!(io)))
    end
    for artifact in (design_stress, committed_design_stress)
        @test String(artifact[:content_hash][:algorithm]) == "sha256"
        @test String(artifact[:content_hash][:covers]) ==
            "artifact_without_content_hash"
        @test String(artifact[:content_hash][:value]) ==
            stress_recomputed_content_hash(artifact)
    end
    stress_semantic_signature = artifact -> (;
        schema = String(artifact[:schema]),
        status = String(artifact[:status]),
        n_design_cells = Int(artifact[:summary][:n_design_cells]),
        n_model_design_cells = Int(artifact[:summary][:n_model_design_cells]),
        n_paired_replication_rows =
            Int(artifact[:summary][:n_paired_replication_rows]),
        deterministic_checks = [(String(row[:check]), Bool(row[:passed]))
            for row in artifact[:deterministic_checks]],
        placement_checks = [(String(row[:family]), Bool(row[:passed]))
            for row in artifact[:c2p_placement_contrast_checks]],
        recovery_completed = Bool(artifact[:summary][
            :paired_known_truth_recovery_completed]),
    )
    @test stress_semantic_signature(design_stress) ==
        stress_semantic_signature(committed_design_stress)
    function stress_evidence_projection(artifact)
        cells = artifact[:model_cell_preflight]
        cell = (cell_id, family) -> only(row for row in cells
            if String(row[:cell_id]) == cell_id &&
                String(row[:family]) == family)
        baseline = cell("C0_balanced_random_double_rated", "mfrm")[
            :design_metrics]
        f1 = cell("F1_mfrm_2pct_high_variance_random_order", "mfrm")[
            :design_metrics][:requested_vs_achieved]
        c3f = cell("C3F_nested_10pct_link_distributed_fixed_total", "mfrm")[
            :design_metrics]
        c2p = [(;
            family = String(row[:family]),
            passed = Bool(row[:passed]),
            same_event_set = Bool(row[:same_event_set]),
            same_common_target_rater_events =
                Bool(row[:same_common_target_rater_events]),
            same_named_truth = Bool(row[:same_named_truth]),
            same_uniform_score_assignment_by_named_event =
                Bool(row[:same_uniform_score_assignment_by_named_event]),
            positions_and_occasions_recomputed =
                Bool(row[:positions_and_occasions_recomputed]),
            distributed_spans_early_and_late =
                Bool(row[:distributed_spans_early_and_late]),
            event_hashes_match_within_artifact =
                String(row[:event_set_sha256_early]) ==
                    String(row[:event_set_sha256_distributed]),
            common_hashes_match_within_artifact =
                String(row[:common_target_rater_events_sha256_early]) ==
                    String(row[:common_target_rater_events_sha256_distributed]),
            truth_hashes_match_within_artifact =
                String(row[:named_truth_sha256_early]) ==
                    String(row[:named_truth_sha256_distributed]),
            assignment_hashes_match_within_artifact =
                String(row[:uniform_score_assignment_sha256_early]) ==
                    String(row[:uniform_score_assignment_sha256_distributed]),
        ) for row in artifact[:c2p_placement_contrast_checks]]
        skeletons = artifact[:all_requested_replication_skeleton_preflight]
        return (;
            c2p,
            f1 = (;
                status = String(f1[:status]),
                fit_eligible = Bool(f1[:fit_eligible]),
                support_passed = Bool(f1[:support_passed]),
                placement_passed = Bool(f1[:placement_passed]),
                rater_linking_passed = Bool(f1[:rater_linking_passed]),
            ),
            baseline_multi_planned = Float64(baseline[
                :achieved_multi_rated_target_fraction_planned_denominator]),
            baseline_multi_observed = Float64(baseline[
                :achieved_multi_rated_target_fraction_observed_denominator]),
            c3f_multi_planned = Float64(c3f[
                :achieved_multi_rated_target_fraction_planned_denominator]),
            c3f_multi_observed = Float64(c3f[
                :achieved_multi_rated_target_fraction_observed_denominator]),
            skeleton_preflight = (;
                requested_replications = Int(skeletons[:requested_replications]),
                n_rows = Int(skeletons[:n_candidate_family_replication_rows]),
                n_passed = Int(skeletons[:n_passed]),
                n_failed = Int(skeletons[:n_failed]),
                passed = Bool(skeletons[:passed]),
            ),
        )
    end
    @test stress_evidence_projection(design_stress) ==
        stress_evidence_projection(committed_design_stress)
    @test String(design_stress[:generator][:source_sha256]) ==
        file_sha256(design_stress_script)
    @test String(committed_design_stress[:generator][:source_sha256]) ==
        file_sha256(design_stress_script)
    @test String(design_stress[:prerequisite_plan][:sha256]) ==
        file_sha256(design_robustness_fixture)
    @test String(committed_design_stress[:prerequisite_plan][:sha256]) ==
        file_sha256(design_robustness_fixture)
    @test String(design_stress[:schema]) ==
        "bayesianmgmfrm.existing_api_design_robustness_stress_grid.v1"
    @test String(design_stress[:status]) ==
        "paired_known_truth_dry_run_passed_mcmc_not_run"
    @test Bool(design_stress[:execution][:execute_mcmc]) == false
    @test Int(design_stress[:execution][:n_fit_attempted]) == 0
    @test String(design_stress[:execution][:seed_namespace]) == "smoke_wiring"
    @test Bool(design_stress[:execution][
        :paired_fit_execution_completed]) == false
    @test Bool(design_stress[:execution][:full_gate_scorer_implemented]) == false
    @test Bool(design_stress[:execution][
        :all_requested_replication_skeletons_design_preflighted])
    @test Bool(design_stress[:execution][
        :all_requested_replication_skeletons_passed])
    skeleton_preflight = design_stress[
        :all_requested_replication_skeleton_preflight]
    @test Int(skeleton_preflight[:requested_replications]) == 1
    @test Int(skeleton_preflight[:n_candidate_family_replication_rows]) == 3
    @test Int(skeleton_preflight[:n_passed]) == 3
    @test Int(skeleton_preflight[:n_failed]) == 0
    @test Bool(skeleton_preflight[:passed])
    @test !haskey(design_stress[:package], :julia_version)
    @test !occursin('\\', String(design_stress[:prerequisite_plan][:path]))
    @test Bool(design_stress[:summary][:passed])
    @test Int(design_stress[:summary][:n_design_cells]) == 10
    @test Int(design_stress[:summary][:n_model_design_cells]) == 24
    @test Int(design_stress[:summary][:n_paired_replication_rows]) == 21
    @test Bool(design_stress[:summary][
        :paired_known_truth_recovery_completed]) == false
    @test Bool(design_stress[:summary][
        :design_robustness_claim_supported]) == false
    @test haskey(design_stress[:terminology],
        :inclusive_multiply_scored_target)
    @test !haskey(design_stress[:terminology],
        :ordinary_multiply_scored_target)
    @test all(row -> Bool(row[:passed]),
        design_stress[:deterministic_checks])
    skeleton_probe = design_stress[:replication_skeleton_resampling_probe]
    @test Bool(skeleton_probe[:passed])
    @test Bool(skeleton_probe[:event_assignment_changed])
    @test Bool(skeleton_probe[:within_rater_order_changed])
    permutation_checks = design_stress[:row_permutation_equivariance_checks]
    @test length(permutation_checks) == 6
    @test Set(String(row[:family]) for row in permutation_checks) == Set([
        "mfrm",
        "guarded_scalar_gmfrm",
        "guarded_fixed_q_mgmfrm",
    ])
    @test all(row -> Bool(row[:passed]) &&
        Float64(row[:maximum_aligned_pointwise_loglikelihood_error]) <=
            Float64(row[:tolerance]) &&
        Float64(row[:absolute_total_loglikelihood_error]) <=
            Float64(row[:total_reduction_tolerance]), permutation_checks)
    placement_checks = design_stress[:c2p_placement_contrast_checks]
    @test length(placement_checks) == 3
    @test all(row -> Bool(row[:passed]) && Bool(row[:same_event_set]) &&
        Bool(row[:same_common_target_rater_events]) &&
        Bool(row[:same_named_truth]) &&
        Bool(row[:same_uniform_score_assignment_by_named_event]) &&
        Bool(row[:positions_and_occasions_recomputed]) &&
        Bool(row[:distributed_spans_early_and_late]) &&
        String(row[:event_set_sha256_early]) ==
            String(row[:event_set_sha256_distributed]) &&
        String(row[:common_target_rater_events_sha256_early]) ==
            String(row[:common_target_rater_events_sha256_distributed]) &&
        String(row[:named_truth_sha256_early]) ==
            String(row[:named_truth_sha256_distributed]) &&
        String(row[:uniform_score_assignment_sha256_early]) ==
            String(row[:uniform_score_assignment_sha256_distributed]) &&
        Float64(row[:maximum_aligned_pointwise_loglikelihood_error]) <=
            Float64(row[:tolerance]), placement_checks)
    stress_cells = design_stress[:model_cell_preflight]
    stress_mfrm_cells = filter(row -> String(row[:family]) == "mfrm",
        stress_cells)
    baseline_stress = only(row for row in stress_mfrm_cells
        if String(row[:cell_id]) == "C0_balanced_random_double_rated")
    baseline_metrics = baseline_stress[:design_metrics]
    @test Float64(baseline_metrics[
        :achieved_multi_rated_target_fraction_planned_denominator]) == 1.0
    @test Float64(baseline_metrics[
        :achieved_multi_rated_target_fraction_observed_denominator]) == 1.0
    @test Float64(baseline_metrics[
        :achieved_common_linking_fraction_planned_denominator]) == 0.0
    @test String(baseline_metrics[:controlled_benchmark_status]) ==
        "not_materialized"
    f1_stress = only(row for row in stress_mfrm_cells
        if String(row[:cell_id]) ==
            "F1_mfrm_2pct_high_variance_random_order")
    f1_gate = f1_stress[:design_metrics][:requested_vs_achieved]
    @test String(f1_gate[:status]) == "underresolved_planned_only"
    @test Bool(f1_gate[:fit_eligible]) == false
    @test Bool(f1_gate[:support_passed]) == false
    @test Bool(f1_gate[:placement_passed]) == false
    @test Bool(f1_gate[:rater_linking_passed]) == false
    mgmfrm_stress = only(row for row in stress_cells
        if String(row[:cell_id]) == "C0_balanced_random_double_rated" &&
            String(row[:family]) == "guarded_fixed_q_mgmfrm")
    mgmfrm_order = mgmfrm_stress[:design_metrics][
        :mgmfrm_order_diagnostics]
    @test length(mgmfrm_order[:dimension_specific]) == 2
    @test all(row -> length(row[:by_rater]) == 4,
        mgmfrm_order[:dimension_specific])
    @test length(mgmfrm_order[:q_active_source][:by_rater]) == 4
    @test Bool(design_stress[:paired_dgp_contract][
        :condition_A_dgp_and_fit_share_package_likelihood_kernel])
    @test Bool(design_stress[:paired_dgp_contract][
        :independent_dgp_cross_check_completed]) == false
    @test Bool(design_stress[:evidence_boundary][
        :kernel_independent_validation_claim_supported]) == false
    for cell_id in (
        "C2F_nested_5pct_link_early_fixed_total",
        "C3F_nested_10pct_link_distributed_fixed_total",
    )
        cell = only(row for row in stress_mfrm_cells
            if String(row[:cell_id]) == cell_id)
        metrics = cell[:design_metrics]
        @test String(metrics[:rating_budget_implementation]) ==
            "fixed_total_target_displacement"
        @test Int(metrics[:n_rating_events]) ==
            Int(metrics[:planned_target_denominator])
        @test Int(metrics[:observed_target_denominator]) +
            Int(metrics[:n_displaced_operational_targets]) ==
            Int(metrics[:planned_target_denominator])
        @test isapprox(
            Float64(metrics[
                :achieved_common_linking_fraction_observed_denominator]),
            Int(metrics[:n_common_linking_targets]) /
                Int(metrics[:observed_target_denominator]);
            atol = 1.0e-12,
        )
        planned_multi = Float64(metrics[
            :achieved_multi_rated_target_fraction_planned_denominator])
        observed_multi = Float64(metrics[
            :achieved_multi_rated_target_fraction_observed_denominator])
        @test isapprox(planned_multi,
            Int(metrics[:n_multi_rated_targets]) /
                Int(metrics[:planned_target_denominator]); atol = 1.0e-12)
        @test isapprox(observed_multi,
            Int(metrics[:n_multi_rated_targets]) /
                Int(metrics[:observed_target_denominator]); atol = 1.0e-12)
        if cell_id == "C3F_nested_10pct_link_distributed_fixed_total"
            @test observed_multi > planned_multi
            @test isapprox(observed_multi - planned_multi,
                Int(metrics[:n_multi_rated_targets]) *
                    (1 / Int(metrics[:observed_target_denominator]) -
                        1 / Int(metrics[:planned_target_denominator]));
                atol = 1.0e-12)
        end
    end
    paired_stress_rows = design_stress[:paired_replication_rows]
    @test all(row -> Bool(row[:category_support_conditioning]) == false &&
        Bool(row[:category_support_resampling]) == false, paired_stress_rows)
    @test all(row -> length(row[:conditions]) == 2 &&
        String(row[:conditions][1][:condition]) == "A_well_specified_static" &&
        String(row[:conditions][2][:condition]) == "B_unmodeled_order_effect",
        paired_stress_rows)
    @test all(condition -> length(condition[:score_summary][
        :category_counts]) == 4,
        (condition for row in paired_stress_rows for condition in row[:conditions]))
    @test String(design_stress[:content_hash][:algorithm]) == "sha256"
    @test length(String(design_stress[:content_hash][:value])) == 64
    rm(design_stress_path; force = true)

    blocked_pilot_path = tempname() * ".json"
    blocked_pilot_output = IOBuffer()
    blocked_pilot_process = run(pipeline(ignorestatus(
        `$(Base.julia_cmd()) --startup-file=no --project=$subprocess_project_dir
            $design_stress_script --profile pilot --execute --allow-heavy
            --output $blocked_pilot_path`);
        stdout = blocked_pilot_output,
        stderr = blocked_pilot_output,
    ))
    @test !success(blocked_pilot_process)
    @test !isfile(blocked_pilot_path)
    @test occursin(
        "pilot/calibration MCMC is blocked until the declared full gate scorer is implemented",
        String(take!(blocked_pilot_output)),
    )

    calibration_skeleton_path = tempname() * ".json"
    run(`$(Base.julia_cmd()) --startup-file=no --project=$subprocess_project_dir
        $design_stress_script --profile calibration --replications 50
        --output $calibration_skeleton_path`)
    calibration_skeleton = JSON3.read(
        read(calibration_skeleton_path, String))
    calibration_preflight = calibration_skeleton[
        :all_requested_replication_skeleton_preflight]
    @test Bool(calibration_preflight[:passed])
    @test Int(calibration_preflight[:requested_replications]) == 50
    @test Int(calibration_preflight[:n_profile_fit_candidate_families]) == 21
    @test Int(calibration_preflight[:n_unique_design_skeletons]) == 450
    @test Int(calibration_preflight[
        :n_candidate_family_replication_rows]) == 1050
    @test Int(calibration_preflight[:n_passed]) == 1050
    @test Int(calibration_preflight[:n_failed]) == 0
    @test isempty(calibration_preflight[:failure_rows])
    calibration_f1_rows = [row for row in calibration_preflight[:rows]
        if String(row[:cell_id]) ==
            "F1_mfrm_2pct_high_variance_random_order"]
    @test length(calibration_f1_rows) == 50
    @test Set(Int(row[:replication]) for row in calibration_f1_rows) ==
        Set(1:50)
    @test all(row -> Bool(row[:passed]) &&
        Float64(row[:requested_vs_achieved][
            :achieved_ability_range_ratio]) >= 0.75 &&
        Float64(row[:requested_vs_achieved][
            :achieved_item_range_ratio]) >= 0.75,
        calibration_f1_rows)
    @test Int(calibration_skeleton[:summary][
        :n_paired_replication_rows]) == 21
    @test Int(calibration_skeleton[:execution][:n_fit_attempted]) == 0
    rm(calibration_skeleton_path; force = true)
    end

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
    @test isequal(
        comparison_summary,
        comparison_evidence_summary(comparison_rows; view = :full),
    )
    public_comparison_summary = comparison_evidence_summary(
        comparison_rows;
        view = :public,
    )
    @test public_comparison_summary.schema ==
        "bayesianmgmfrm.comparison_evidence_summary_public.v1"
    @test :next_gate ∉ keys(public_comparison_summary)
    @test only(filter(row -> row.comparison_class === :stan_faithful,
        public_comparison_summary.class_rows)).evidence ==
        (:stan_validation_summary,)
    path_comparison_rows = [
        comparison_evidence_row(;
            comparison_class = :stan,
            target_model = :scalar_gmfrm,
            comparator = :bridge_stan,
            metric = :log_density,
            estimate = 0.0,
            reference = 0.0,
            artifact = "private/results.json",
        ),
        comparison_evidence_row(;
            comparison_class = :facets,
            target_model = :mfrm_pcm,
            comparator = :facets_export,
            metric = :severity_correlation,
            estimate = 1.0,
            reference = 1.0,
            artifact = "/Users/example/private/results.json",
        ),
        comparison_evidence_row(;
            comparison_class = :nested,
            target_model = :scalar_gmfrm,
            comparator = :mfrm_pcm,
            metric = :heldout_elpd_difference,
            estimate = 1.0,
            reference = 0.0,
            pass_if = :greater_equal,
        ),
    ]
    path_free_comparison_summary = comparison_evidence_summary(
        path_comparison_rows;
        view = :public,
    )
    @test !occursin("private/results.json",
        JSON3.write(path_free_comparison_summary))
    @test all(row -> :artifacts ∉ keys(row),
        path_free_comparison_summary.class_rows)
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
    @test_throws ArgumentError comparison_evidence_summary(
        comparison_rows;
        view = :unknown,
    )

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
    @test isequal(
        benchmark_gate,
        benchmark_summary(julia_benchmark, stan_benchmark; view = :full),
    )
    public_benchmark_gate = benchmark_summary(
        julia_benchmark,
        stan_benchmark;
        view = :public,
    )
    @test public_benchmark_gate.schema ==
        "bayesianmgmfrm.benchmark_summary_public.v1"
    @test :next_gate ∉ keys(public_benchmark_gate)
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
    @test_throws ArgumentError benchmark_summary(
        julia_benchmark;
        view = :unknown,
    )

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

    psis_result = psis_loo(result)
    psis_loglik = pointwise_loglikelihood_matrix(design,result.draws)
    manual_psis_lppd = [BayesianMGMFRM._logmeanexp(c) for c in eachcol(psis_loglik)]
    @test psis_result.criterion === :loo
    @test psis_result.method === :pareto_smoothed_importance_sampling
    @test psis_result.psis_smoothing === true
    @test psis_result.pareto_k_estimator === :zhang_stephens
    @test psis_result.n_draws == size(result.draws,1)
    @test psis_result.n_observations == data.n
    @test psis_result.pareto_k_threshold == 0.7
    @test psis_result.pointwise.lppd ≈ manual_psis_lppd
    @test psis_result.pointwise.p_loo ≈
        psis_result.pointwise.lppd .- psis_result.pointwise.elpd_loo
    @test psis_result.pointwise.looic ≈ -2 .* psis_result.pointwise.elpd_loo
    @test psis_result.lppd ≈ sum(manual_psis_lppd)
    @test psis_result.p_loo ≈ sum(psis_result.pointwise.p_loo)
    @test psis_result.elpd_loo ≈ sum(psis_result.pointwise.elpd_loo)
    @test psis_result.looic ≈ sum(psis_result.pointwise.looic)
    @test psis_result.looic ≈ -2 * psis_result.elpd_loo
    @test psis_result.se_looic ≈ 2 * psis_result.se_elpd_loo
    @test all(isfinite, psis_result.pointwise.elpd_loo)
    # Short random-walk Metropolis chains with rejected proposals can exhibit a
    # constant tail (`pareto_k == Inf`) under Zhang-Stephens PSIS (`common_psis.jl`).
    @test all(k -> isfinite(k) || k == Inf, psis_result.pointwise.pareto_k)
    @test all(ess -> 0 < ess,
        psis_result.pointwise.effective_sample_size)
    @test all(draws -> 1 <= draws <= psis_result.n_draws - 1,
        psis_result.pointwise.tail_draws)
    @test psis_result.bad_pareto_k_count ==
        count(>(psis_result.pareto_k_threshold), psis_result.pointwise.pareto_k)
    @test psis_result.max_pareto_k == maximum(psis_result.pointwise.pareto_k)
    @test psis_result.min_effective_sample_size ==
        minimum(psis_result.pointwise.effective_sample_size)
    @test psis_result.warning in (:ok, :high_pareto_k)
    @test psis_loo(design, result.draws;chain_ids=result.chain_ids).looic ≈
        psis_result.looic
    @test psis_loo(psis_loglik;chain_ids=result.chain_ids).looic ≈ psis_result.looic
    constant_loglik = fill(-1.2, size(result.draws,1), 2)
    constant_raw_loo = loo(constant_loglik)
    constant_psis_loo = psis_loo(constant_loglik)
    @test constant_psis_loo.pointwise.elpd_loo ≈
        constant_raw_loo.pointwise.elpd_loo
    @test all(isapprox.(constant_psis_loo.pointwise.p_loo,
        constant_raw_loo.pointwise.p_loo; atol = eps()))
    @test all(isinf, constant_psis_loo.pointwise.pareto_k)
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
    psis_loo_rows = loo_diagnostics(result; psis_smoothing = true)
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
    @test isequal(
        sensitivity_summary,
        sensitivity_comparison_summary(
            NamedTuple[threshold_sensitivity...; custom_sensitivity...];
            required_axes = (:threshold, :prior),
            view = :full,
        ),
    )
    public_sensitivity_summary = sensitivity_comparison_summary(
        NamedTuple[threshold_sensitivity...; custom_sensitivity...];
        required_axes = (:threshold, :prior),
        view = :public,
    )
    @test public_sensitivity_summary.schema ==
        "bayesianmgmfrm.sensitivity_comparison_summary_public.v1"
    @test :next_gate ∉ keys(public_sensitivity_summary)
    @test public_sensitivity_summary.n_candidate_rows ==
        sensitivity_summary.n_candidate_rows
    @test [row.n_candidate_rows for row in
        public_sensitivity_summary.axis_rows] ==
        [row.n_candidate_rows for row in sensitivity_summary.axis_rows]
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
    @test_throws ArgumentError sensitivity_comparison_summary(
        threshold_sensitivity;
        view = :unknown,
    )

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
    @test_throws ArgumentError compare_models(result, hmc_result;
        names = [:main, :hmc],
        criterion = :psis_loo)
    hmc_psis_result = fit(design;
        prior,
        backend = :advancedhmc,
        ndraws = 8,
        warmup = 4,
        chains = 2,
        step_size = 0.03,
        max_depth = 3,
        target_accept = 0.8,
        init,
        rng = MersenneTwister(20260620))
    @test all(k -> isfinite(k) || k == Inf, psis_loo(hmc_psis_result).pointwise.pareto_k)
    psis_comparison = compare_models(result, hmc_psis_result;
        names = [:main, :hmc],
        criterion = :psis_loo)
    psis_comparison_stats = Dict(
        "main" => psis_loo(result),
        "hmc" => psis_loo(hmc_psis_result),
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
        @test isequal(row.max_pareto_k, stat.max_pareto_k)
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
    psis_sensitivity = sensitivity_comparison(:main => result, :hmc => hmc_psis_result;
        axis = :sampler,
        baseline = :main,
        criterion = :psis_loo)
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

    diagnostic_map = diagnostic_map_data(result;
        draw_indices = [1, 2],
        interval = 0.8)
    diagnostic_pathway_rows =
        filter(row -> row.map_layer === :pathway_fit, diagnostic_map)
    diagnostic_threshold_rows =
        filter(row -> row.map_layer === :threshold_position, diagnostic_map)
    @test length(diagnostic_pathway_rows) ==
        2 * (length(data.person_levels) + length(data.rater_levels) +
        length(data.item_levels))
    @test length(diagnostic_threshold_rows) ==
        length(data.item_levels) * (length(data.category_levels) - 1)
    @test Set(row.fit_metric for row in diagnostic_pathway_rows) ==
        Set((:infit, :outfit))
    @test all(row -> row.schema == "bayesianmgmfrm.diagnostic_map_data.v1",
        diagnostic_map)
    @test all(row -> row.object === :diagnostic_map_row, diagnostic_map)
    @test all(row -> row.model_family === :mfrm, diagnostic_map)
    @test all(row -> row.scale === :logit, diagnostic_map)
    @test all(row -> row.caveat === :diagnostic_map_screening_not_model_selection,
        diagnostic_map)
    @test all(row -> row.suggested_x == row.fit_value &&
        row.suggested_y == row.logit_position,
        diagnostic_pathway_rows)
    @test all(row -> ismissing(row.fit_metric) &&
        ismissing(row.suggested_x) &&
        row.suggested_y == row.logit_position,
        diagnostic_threshold_rows)
    r1_infit_map = only(row for row in diagnostic_pathway_rows
        if row.facet === :rater && row.level == "R1" &&
        row.fit_metric === :infit)
    r1_wright = only(row for row in wright_facet_rows
        if row.facet === :rater && row.level == "R1")
    r1_fit = only(row for row in rater_fit if row.level == "R1")
    @test r1_infit_map.logit_position ≈ r1_wright.position_mean
    @test r1_infit_map.logit_lower ≈ r1_wright.position_lower
    @test r1_infit_map.fit_value ≈ r1_fit.infit_mean
    @test r1_infit_map.fit_lower ≈ r1_fit.infit_lower
    @test r1_infit_map.fit_flag === r1_fit.flag
    @test r1_infit_map.position_flag === r1_wright.flag
    @test r1_infit_map.flag === (r1_wright.flag !== :ok ?
        r1_wright.flag : r1_fit.flag)
    rater_outfit_map = diagnostic_map_data(result;
        facets = :rater,
        include_thresholds = false,
        metrics = :outfit,
        draw_indices = [1, 2],
        interval = 0.8)
    @test length(rater_outfit_map) == length(data.rater_levels)
    @test all(row -> row.facet === :rater &&
        row.fit_metric === :outfit &&
        row.map_layer === :pathway_fit,
        rater_outfit_map)
    @test isequal(
        diagnostic_map_data(design, result.draws[1:2, :];
            facets = :rater,
            include_thresholds = false,
            metrics = :outfit,
            interval = 0.8),
        rater_outfit_map,
    )
    @test_throws ArgumentError diagnostic_map_data(result; metrics = :rmse)
    @test_throws ArgumentError diagnostic_map_data(result; metrics = (:infit, :infit))
    @test_throws ArgumentError diagnostic_map_data(result; facets = :category)
    @test_throws ArgumentError diagnostic_map_data(result; interval = 1.0)
    @test_throws ArgumentError diagnostic_map_data(result; min_n = 0)
    @test_throws ArgumentError diagnostic_map_data(result; draw_indices = [0])

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

    grouped_dff = dff_report(grouped_design, result.draws[1:2, :];
        adjustment = :observed_margins, interval = 0.8)
    @test length(grouped_dff) ==
        length(grouped_data.rater_levels) * length(grouped_data.optional_levels[:group])
    @test isequal(
        dff_report(grouped_design, result.draws[1:2, :];
            terms = (:rater, :group),
            adjustment = :observed_margins,
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
        adjustment = :observed_margins,
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
    fixture_path = joinpath(dirname(@__DIR__), "fixtures", "scalar_validation_known_value.json")
    stan_model_path = joinpath(dirname(@__DIR__), "stan", "scalar_gmfrm.stan")
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

    stan_fixture_path = joinpath(dirname(@__DIR__), "fixtures", "scalar_validation_stan_logdensity.json")
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
        fixture_path = relpath(stan_fixture_path, dirname(dirname(@__DIR__))),
        known_fixture_path = relpath(fixture_path, dirname(dirname(@__DIR__))),
        stan_model = String(stan_fixture[:stan_model]),
        fixture_sha256 = file_sha256(stan_fixture_path),
        known_fixture_sha256 = file_sha256(fixture_path),
        stan_model_sha256 = String(stan_fixture[:stan_model_sha256]),
    )
    @test small_stan_row.passed
    @test small_stan_row.log_density_abs_error == 0.0
    @test small_stan_row.gradient_max_abs_error < stan_tol

    medium_pair = check_scalar_validation_stan_pair(
        joinpath(dirname(@__DIR__), "fixtures", "scalar_validation_medium_known_value.json"),
        joinpath(dirname(@__DIR__), "fixtures", "scalar_validation_medium_stan_logdensity.json");
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
end
