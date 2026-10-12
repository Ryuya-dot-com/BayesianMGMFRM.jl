# Opt-in actual-fit integration: julia --project=. test/common_refit_workflow.jl OUTPUT
# OUTPUT must be new. This is not a scientific replication or a precision check.
using BayesianMGMFRM, Test, Serialization, TOML, SHA
include("../examples/synthetic_kfold_workflow.jl")

function check_saved_workflow(directory)
    B, E = BayesianMGMFRM, BayesianMGMFRM.Experimental
    input = deserialize(joinpath(directory, "inputs.jls"))
    expected = deserialize(joinpath(directory, "comparison.jls"))
    @test isequal(replay_synthetic_kfold_workflow(directory), expected)
    @test expected.complete
    @test expected.comparison_axis === :dimensions
    @test expected.model_selection === :not_performed
    @test expected.scientific_acceptance === :not_established
    @test expected.uncertainty.standard_error === :not_computed
    types = (MFRMFit, GMFRMFit, MGMFRMFit, E.NormalizedMGMFRMFit,
        E.CorrelatedMGMFRMFit, E.MultidimensionalMFRMFit,
        E.CorrelatedMFRMFit, E.ExchangeableMFRMFit)
    @test length(input.plans) == length(types) == 8
    @test length(unique(p.split_binding for p in input.plans)) == 1
    fit_count = 0
    for (i, prepared) in enumerate(input.plans)
        @test length(prepared.folds) == 2
        manual_elpd = 0.0
        for (j, request) in enumerate(prepared.folds)
            fit_count += 1
            fitted = load_fit_cache(joinpath(directory, "model-$i-fold-$j.jls"))
            saved = deserialize(joinpath(directory, "model-$i-fold-$j-output.jls"))
            @test fitted isa types[i]
            @test isequal(fit_metadata(fitted), saved.metadata)
            @test isequal(diagnostics(fitted), saved.diagnostics)
            @test isequal(posterior_mcse(fitted), saved.parameter_mcse)
            @test !isempty(saved.parameter_mcse)
            scored = B.prediction_fold_observations(fitted, request; include_probabilities=false)
            @test isequal(scored, saved.score)
            @test scored.n_retained_draws == input.sampler.chains * input.sampler.ndraws
            @test size(scored.pointwise_loglikelihood) == (16, 48)
            @test length(scored.training_observation_ids) == 48
            @test isempty(intersect(scored.observation_ids, scored.training_observation_ids))
            data = request.source_spec.data
            groups = data.optional[:response_id]
            @test isempty(intersect(groups[request.training_observations], groups[request.heldout_observations]))
            @test expected.rows[i].folds[j].sampling_warning ==
                (get(scored.sampling_quality, :flag, :unknown) !== :ok ||
                 (get(scored.sampling_quality, :location_summary, nothing) !== nothing &&
                  scored.sampling_quality.location_summary.flag !== :ok))
            matrix = scored.pointwise_loglikelihood
            manual_elpd += sum(eachcol(matrix)) do column
                largest = maximum(column)
                largest + log(sum(exp.(column .- largest)) / length(column))
            end
            # A real fit from the other fold cannot satisfy this request.
            @test_throws ArgumentError B.prediction_fold_observations(fitted, prepared.folds[3-j])
        end
        @test expected.rows[i].elpd ≈ manual_elpd atol=1e-10
        @test expected.rows[i].elpd_difference ≈
            expected.rows[i].elpd - expected.rows[1].elpd atol=1e-10
        @test ismissing(expected.rows[i].se_elpd_difference)
    end
    @test fit_count == 16
    @test expected.status === :warning # Tiny smoke draws must not become a clean recommendation.
    @test any(row -> row.sampling_warning, expected.rows)
    return nothing
end

directory = abspath(ARGS[1])
replay = length(ARGS) == 2 && ARGS[2] == "--replay"
checks = @testset "Actual public refit, cache and heldout workflow" begin
    if !replay
        result = synthetic_kfold_workflow(directory;
            sampler=(; chains=2, warmup=10, ndraws=8, max_depth=3))
        @test length(result.rows) == 8
        @test_throws ArgumentError synthetic_kfold_workflow(directory;
            sampler=(; chains=2, warmup=10, ndraws=8, max_depth=3))
    end
    check_saved_workflow(directory)
    if !replay
        before = Dict(name => bytes2hex(sha256(read(joinpath(directory, name))))
            for name in readdir(directory))
        project = dirname(@__DIR__)
        log = directory * "-replay.log"
        GC.gc()
        open(log, "w") do io
            process = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$project $(@__FILE__) $directory --replay`;
                stdout=io, stderr=io); wait=false)
            wait(process)
            flush(io)
            print(read(log, String))
            @test success(process)
        end
        @test before == Dict(name => bytes2hex(sha256(read(joinpath(directory, name))))
            for name in readdir(directory))
    end
end
counts = Test.get_test_counts(checks)
open(directory * (replay ? "-replay.toml" : "-verification.toml"), "w") do io
    TOML.print(io, Dict("status"=>"passed", "assertions"=>counts.passes+counts.cumulative_passes,
        "pid"=>getpid(), "new_posterior_fits"=>replay ? 0 : 16,
        "formal_simulation_replications"=>0, "formal_sbc_replications"=>0,
        "scope"=>"Actual short AdvancedHMC fits and public workflow compatibility; no accuracy, calibration, timing or model recommendation."))
end
