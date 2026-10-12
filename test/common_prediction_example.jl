using Test, BayesianMGMFRM, SHA
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
include("../examples/common_prediction_observations.jl")
const E = CommonPredictionExample

@testset "Saved-fit user example; deterministic fixture, no sampling" begin
    help = IOBuffer()
    @test E.main(["--help"]; io=help) === nothing
    @test occursin("original fit row order", String(take!(help)))
    @test_throws ArgumentError E.main(["too", "few"])
    fit = reporting_fit(:mgmfrm; chains=2, ndraws=20, warmup=0)
    mktempdir() do directory
        path, ids_path = joinpath(directory, "fit.jls"), joinpath(directory, "ids.txt")
        save_fit_cache(path, fit)
        digest = bytes2hex(open(sha256, path))
        ids = ["rating-$n" for n in (4, 1, 6, 2, 5, 3)]
        write(ids_path, join(ids, '\n')*"\n")
        output = IOBuffer()
        result = E.main([path, "synthetic-example/v1", ids_path]; io=output)
        @test result.preview.observation_ids == ids
        @test size(result.preview.probabilities) == (1, 6, 3)
        @test size(result.evaluation.prediction.pointwise_loglikelihood) == (40, 6)
        @test result.evaluation.prediction.prediction_target === :training_rows_existing_levels
        @test result.evaluation.prediction.weighting === :equal_observation
        native = waic(pointwise_loglikelihood_matrix(fit))
        @test result.evaluation.scores.waic.elpd_waic ≈ native.elpd_waic rtol=1e-12
        @test result.evaluation.scores.waic.pointwise.p_waic ≈ native.pointwise.p_waic rtol=1e-12 atol=1e-15
        @test result.evaluation.sampling_warning
        @test occursin("Sampling warning: true", String(take!(output)))
        @test bytes2hex(open(sha256, path)) == digest
        @test sort(readdir(directory)) == ["fit.jls", "ids.txt"]
        for invalid in ([ids[1]; ids[1:end-1]], ids[1:end-1], [""; ids[2:end]])
            write(ids_path, join(invalid, '\n')*"\n")
            @test_throws ArgumentError E.main([path, "synthetic-example/v1", ids_path]; io=IOBuffer())
        end
    end
end
