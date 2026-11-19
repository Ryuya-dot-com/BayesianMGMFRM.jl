module FirstAnalysisFigureChecks
using BayesianMGMFRM, Test, SHA
using BayesianMGMFRM: JSON3
include("../examples/first_analysis_figures.jl")
const F = FirstMFRMFigures

function checks()
    @testset "Supplied fitted teaching result and portable figures" begin
        original = F.review()
        @test original.answer.data.origin == "fixed artificial teaching data"
        @test original.answer.mean == 0.1655665090364782
        @test original.answer.lower < 0 < original.answer.upper
        @test original.answer.numerically_qualified
        @test original.report["prior_predictive"]["status"] == "not_requested"
        @test original.report["posterior_predictive"]["status"] == "computed"
        @test sum(r.n_divergences for r in original.answer.sampler.warmup) == 16
        @test all(r.n_divergences == 0 for r in original.answer.sampler.retained)
        @test all(isfile, values(original.figures))
        mktempdir() do tmp
            first = F.main(; output_parent=tmp)
            second = F.main(; output_parent=tmp)
            @test first.directory != second.directory
            @test F.review(first.directory).report == original.report
            @test F.review(second.directory).answer == original.answer
            @test read(first.figures.posterior) == read(original.figures.posterior)
            write(first.figures.posterior, "changed figure")
            @test_throws ArgumentError F.review(first.directory)
            answer_path = joinpath(second.directory, "answer.json")
            answer = JSON3.read(read(answer_path, String), Dict{String,Any})
            answer["mean"] += 1
            write(answer_path, JSON3.write(answer))
            @test_throws ArgumentError F.review(second.directory)
            receipt_path = joinpath(second.directory, "provenance.json")
            receipt = JSON3.read(read(receipt_path, String), Dict{String,Any})
            receipt["sha256"]["answer.json"] = bytes2hex(sha256(read(answer_path)))
            write(receipt_path, JSON3.write(receipt))
            # Even a new file checksum cannot reconcile different reported estimates.
            @test_throws ArgumentError F.review(second.directory)
        end
    end
end
end
