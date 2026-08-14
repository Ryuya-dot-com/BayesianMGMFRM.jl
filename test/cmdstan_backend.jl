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
    @test !contract.fit_backend_implemented
    @test !contract.core_install_requires_cmdstan
    @test contract.implemented_families == (:mfrm,)
    @test contract.model_source_status.gmfrm === :validation_reference_only
    mfrm_contract = BayesianMGMFRM.cmdstan_backend_contract(:mfrm)
    @test mfrm_contract.model_source_status === :package_model_and_cli_adapter
    @test mfrm_contract.fit_backend_implemented
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
    @test BayesianMGMFRM._cmdstan_chain_seeds(MersenneTwister(71), 4) ==
        BayesianMGMFRM._cmdstan_chain_seeds(MersenneTwister(71), 4)
    @test length(unique(BayesianMGMFRM._cmdstan_chain_seeds(
        MersenneTwister(72),
        4,
    ))) == 4
    mktempdir() do directory
        cd(directory) do
            @test isfile(BayesianMGMFRM._cmdstan_mfrm_source())
            @test BayesianMGMFRM._cmdstan_mfrm_data(pcm_design, prior).P == 7
        end
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
    @test_throws ArgumentError BayesianMGMFRM.fit(
        pcm_design;
        backend = :julia,
        cmdstan_path = missing_root,
    )
end
