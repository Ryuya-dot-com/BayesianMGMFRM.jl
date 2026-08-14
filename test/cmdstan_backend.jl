using Test
using Random

import BayesianMGMFRM

function captured_cmdstan_error(operation)
    try
        operation()
    catch error
        return error
    end
    return nothing
end

@testset "CmdStan backend contract and portable runtime check" begin
    contract = BayesianMGMFRM.cmdstan_backend_contract()
    @test contract.release_requirement === :required_before_stable_promotion
    @test !contract.release_gate_satisfied
    @test contract.fit_backend_implemented
    @test !contract.core_install_requires_cmdstan
    @test contract.implemented_families == (:mfrm, :gmfrm, :mgmfrm)
    @test contract.model_source_status.gmfrm === :package_model_and_cli_adapter
    mfrm_contract = BayesianMGMFRM.cmdstan_backend_contract(:mfrm)
    @test mfrm_contract.model_source_status === :package_model_and_cli_adapter
    @test mfrm_contract.fit_backend_implemented
    gmfrm_contract = BayesianMGMFRM.cmdstan_backend_contract(:gmfrm)
    @test gmfrm_contract.model_source_status === :package_model_and_cli_adapter
    @test gmfrm_contract.fit_backend_implemented
    mgmfrm_contract = BayesianMGMFRM.cmdstan_backend_contract(:mgmfrm)
    @test mgmfrm_contract.model_source_status ===
        :package_model_and_cli_adapter
    @test mgmfrm_contract.fit_backend_implemented
    @test_throws ArgumentError BayesianMGMFRM.cmdstan_backend_contract(
        :exploratory,
    )

    missing_root = joinpath(tempdir(),
        "bayesian-mgmfrm-cmdstan-preflight-missing")
    missing = BayesianMGMFRM.cmdstan_backend_check(;
        cmdstan_path = missing_root,
    )
    @test missing.status === :runtime_unavailable
    @test !missing.runtime_ready
    @test missing.discovery_source === :argument
    @test missing.cmdstan_root === nothing
    @test missing.cmdstan_root_basename === basename(missing_root)
    @test :root_directory in missing.failed_checks
    @test missing.stable_mfrm_fit_implemented
    @test missing.guarded_gmfrm_fit_implemented
    @test missing.guarded_mgmfrm_fit_implemented
    error = captured_cmdstan_error() do
        BayesianMGMFRM.cmdstan_backend_check(;
            cmdstan_path = missing_root,
            require_ready = true,
        )
    end
    @test error isa BayesianMGMFRM.CmdStanError
    @test error.stage === :runtime_check
    @test error.reason === :runtime_unavailable

    discovered = BayesianMGMFRM.cmdstan_backend_check()
    @test discovered.status in (:runtime_ready, :runtime_unavailable)
    @test discovered.runtime_ready == isempty(discovered.failed_checks)
    @test discovered.cmdstan_root === nothing
    @test !discovered.release_gate_satisfied
    if discovered.runtime_ready
        @test discovered.cmdstan_version !== nothing
        @test discovered.discovery_source in
            (:env_cmdstan, :env_cmdstan_home, :default_install)
    end

    table = (
        examinee = ["E1", "E1", "E1", "E2", "E2", "E2", "E3", "E3", "E3"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2, 1, 2, 0],
    )
    data = BayesianMGMFRM.FacetData(
        table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    pcm_design = BayesianMGMFRM.getdesign(BayesianMGMFRM.mfrm_spec(
        data;
        thresholds = :partial_credit,
    ))
    rsm_design = BayesianMGMFRM.getdesign(BayesianMGMFRM.mfrm_spec(
        data;
        thresholds = :rating_scale,
    ))
    prior = BayesianMGMFRM.MFRMPrior()
    pcm_payload = BayesianMGMFRM._cmdstan_mfrm_data(pcm_design, prior)
    rsm_payload = BayesianMGMFRM._cmdstan_mfrm_data(rsm_design, prior)
    @test pcm_payload.threshold_model == 2
    @test pcm_payload.free_steps == 1
    @test pcm_payload.P == length(pcm_design.parameter_names) == 7
    @test pcm_payload.PersonID == data.person
    @test pcm_payload.RaterID == data.rater
    @test pcm_payload.ItemID == data.item
    @test pcm_payload.X == data.category
    @test pcm_payload.prior_sd == [1.5, 1.5, 1.5, 1.0, 1.0, 1.0, 1.0]
    @test rsm_payload.threshold_model == 1
    @test rsm_payload.P == length(rsm_design.parameter_names) == 6
    gmfrm_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    gmfrm_design = BayesianMGMFRM.getdesign(gmfrm_spec; preview = true)
    gmfrm_target = BayesianMGMFRM._gmfrm_promotion_candidate_logdensity(
        gmfrm_design,
    )
    gmfrm_payload = BayesianMGMFRM._cmdstan_gmfrm_data(gmfrm_target)
    @test gmfrm_payload.P == gmfrm_target.blueprint.n_parameters == 11
    @test gmfrm_payload.free_steps == 1
    @test gmfrm_payload.prior_sd ==
        [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 1.0, 1.0]
    mgmfrm_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 0; 0 1],
    )
    mgmfrm_design = BayesianMGMFRM.getdesign(mgmfrm_spec; preview = true)
    mgmfrm_target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
        mgmfrm_design,
    )
    mgmfrm_payload = BayesianMGMFRM._cmdstan_mgmfrm_data(mgmfrm_target)
    @test mgmfrm_payload.P == mgmfrm_target.blueprint.n_parameters == 14
    @test mgmfrm_payload.NLoadings == 2
    @test mgmfrm_payload.LoadingItem == [1, 2]
    @test mgmfrm_payload.LoadingDim == [1, 2]
    @test mgmfrm_payload.prior_sd ==
        [fill(1.0, 9); fill(0.5, 3); fill(1.0, 2)]
    crossloading_spec = BayesianMGMFRM.mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[1 1; 0 1],
    )
    crossloading_target =
        BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(
            BayesianMGMFRM.getdesign(crossloading_spec; preview = true),
        )
    crossloading_payload =
        BayesianMGMFRM._cmdstan_mgmfrm_data(crossloading_target)
    @test crossloading_payload.NLoadings == 3
    @test crossloading_payload.LoadingItem == [1, 1, 2]
    @test crossloading_payload.LoadingDim == [1, 2, 2]
    @test crossloading_payload.P == 15
    @test BayesianMGMFRM._cmdstan_chain_seeds(MersenneTwister(71), 4) ==
        BayesianMGMFRM._cmdstan_chain_seeds(MersenneTwister(71), 4)
    @test length(unique(BayesianMGMFRM._cmdstan_chain_seeds(
        MersenneTwister(72),
        4,
    ))) == 4
    mktempdir() do directory
        cd(directory) do
            @test isfile(BayesianMGMFRM._cmdstan_mfrm_source())
            @test isfile(BayesianMGMFRM._cmdstan_gmfrm_source())
            @test isfile(BayesianMGMFRM._cmdstan_mgmfrm_source())
            @test BayesianMGMFRM._cmdstan_mfrm_data(pcm_design, prior).P == 7
        end
    end


    gmfrm_zero = zeros(gmfrm_target.blueprint.n_parameters)
    gmfrm_pointwise =
        BayesianMGMFRM._gmfrm_source_pointwise_loglikelihood_from_unconstrained(
            gmfrm_design,
            gmfrm_zero,
        )
    gmfrm_header = [
        "lp__",
        "accept_stat__",
        "stepsize__",
        "treedepth__",
        "n_leapfrog__",
        "divergent__",
        "energy__",
        ["beta.$index" for index in eachindex(gmfrm_zero)]...,
        ["log_lik.$observation" for observation in 1:data.n]...,
    ]
    gmfrm_csv_values = [
        -2.0,
        0.85,
        0.05,
        1.0,
        1.0,
        0.0,
        6.0,
        gmfrm_zero...,
        gmfrm_pointwise...,
    ]
    mktempdir() do directory
        csv_path = joinpath(directory, "gmfrm-chain.csv")
        write(csv_path, join(gmfrm_header, ',') * "\n" *
            join(gmfrm_csv_values, ',') * "\n")
        parsed = BayesianMGMFRM._cmdstan_gmfrm_chain_result(
            csv_path,
            gmfrm_target,
            1,
            1,
        )
        @test parsed.draws == permutedims(gmfrm_zero)
        @test parsed.logps == [BayesianMGMFRM.LogDensityProblems.logdensity(
            gmfrm_target,
            gmfrm_zero,
        )]
        @test only(parsed.stats).stan_lp == -2.0
    end

    mgmfrm_zero = zeros(mgmfrm_target.blueprint.n_parameters)
    mgmfrm_pointwise =
        BayesianMGMFRM._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
            mgmfrm_design,
            mgmfrm_zero,
        )
    mgmfrm_header = [
        "lp__",
        "accept_stat__",
        "stepsize__",
        "treedepth__",
        "n_leapfrog__",
        "divergent__",
        "energy__",
        ["beta.$index" for index in eachindex(mgmfrm_zero)]...,
        ["log_lik.$observation" for observation in 1:data.n]...,
    ]
    mgmfrm_csv_values = [
        -3.0,
        0.8,
        0.04,
        1.0,
        1.0,
        0.0,
        7.0,
        mgmfrm_zero...,
        mgmfrm_pointwise...,
    ]
    mktempdir() do directory
        csv_path = joinpath(directory, "mgmfrm-chain.csv")
        write(csv_path, join(mgmfrm_header, ',') * "\n" *
            join(mgmfrm_csv_values, ',') * "\n")
        parsed = BayesianMGMFRM._cmdstan_mgmfrm_chain_result(
            csv_path,
            mgmfrm_target,
            1,
            1,
        )
        @test parsed.draws == permutedims(mgmfrm_zero)
        @test parsed.logps == [BayesianMGMFRM.LogDensityProblems.logdensity(
            mgmfrm_target,
            mgmfrm_zero,
        )]
        @test only(parsed.stats).stan_lp == -3.0
    end

    zero_params = zeros(length(pcm_design.parameter_names))
    pointwise = BayesianMGMFRM.pointwise_loglikelihood(pcm_design, zero_params)
    header = [
        "lp__",
        "accept_stat__",
        "stepsize__",
        "treedepth__",
        "n_leapfrog__",
        "divergent__",
        "energy__",
        ["beta.$index" for index in eachindex(zero_params)]...,
        ["log_lik.$observation" for observation in 1:data.n]...,
    ]
    csv_values = [
        -1.0,
        0.9,
        0.1,
        2.0,
        3.0,
        0.0,
        5.0,
        zero_params...,
        pointwise...,
    ]
    mktempdir() do directory
        csv_path = joinpath(directory, "chain.csv")
        write(csv_path, join(header, ',') * "\n" *
            join(csv_values, ',') * "\n")
        parsed = BayesianMGMFRM._cmdstan_chain_result(
            csv_path,
            pcm_design,
            prior,
            1,
            1,
        )
        @test parsed.draws == permutedims(zero_params)
        @test parsed.logps == [BayesianMGMFRM.logposterior(
            pcm_design,
            zero_params,
            prior,
        )]
        @test only(parsed.stats).stan_lp == -1.0
        @test only(parsed.stats).acceptance_rate == 0.9

        mismatched = copy(csv_values)
        mismatched[end] += 0.1
        write(csv_path, join(header, ',') * "\n" *
            join(mismatched, ',') * "\n")
        mismatch_error = captured_cmdstan_error() do
            BayesianMGMFRM._cmdstan_chain_result(
                csv_path,
                pcm_design,
                prior,
                1,
                1,
            )
        end
        @test mismatch_error isa BayesianMGMFRM.CmdStanError
        @test mismatch_error.reason === :pointwise_loglikelihood_mismatch
    end

    fit_error = captured_cmdstan_error() do
        BayesianMGMFRM.fit(
            pcm_design;
            backend = :cmdstan,
            ndraws = 1,
            warmup = 1,
            cmdstan_path = missing_root,
        )
    end
    @test fit_error isa BayesianMGMFRM.CmdStanError
    @test fit_error.stage === :runtime_check
    gmfrm_fit_error = captured_cmdstan_error() do
        BayesianMGMFRM.Experimental.fit(
            gmfrm_spec;
            backend = :cmdstan,
            ndraws = 1,
            warmup = 1,
            cmdstan_path = missing_root,
        )
    end
    @test gmfrm_fit_error isa BayesianMGMFRM.CmdStanError
    @test gmfrm_fit_error.stage === :runtime_check
    mgmfrm_fit_error = captured_cmdstan_error() do
        BayesianMGMFRM.Experimental.fit(
            mgmfrm_spec;
            backend = :cmdstan,
            ndraws = 1,
            warmup = 1,
            cmdstan_path = missing_root,
        )
    end
    @test mgmfrm_fit_error isa BayesianMGMFRM.CmdStanError
    @test mgmfrm_fit_error.stage === :runtime_check
    @test_throws ArgumentError BayesianMGMFRM.fit(
        pcm_design;
        backend = :julia,
        cmdstan_path = missing_root,
    )
end
