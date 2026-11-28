module StandardOnboardingChecks
using Test, SHA, BayesianMGMFRM
const B = BayesianMGMFRM
include("../examples/first_analysis.jl")
include("../examples/minimal.jl")
const A = FirstMFRMAnalysis

module InterruptedAnalysis
include("../examples/first_analysis_v02.jl")
FirstMFRMAnalysisV02.result(::FirstMFRMAnalysisV02.BayesianMGMFRM.AdditiveFacets.Fit, prepared) =
    error("injected standard-example reporting failure")
end

function checks(directory; teaching_fit = nothing, minimal_fit = nothing)
    prepared = A.inputs()
    @testset "Standard onboarding: inputs and explicit model identity" begin
        @test A === FirstMFRMAnalysisV02
        @test prepared.spec isa B.AdditiveFacets.MRCMLTarget
        @test prepared.validation.passed
        @test MinimalMFRM.inputs().spec isa B.AdditiveFacets.MRCMLTarget
        @test_throws ArgumentError A.main(["--unknown"]; output_parent = joinpath(directory, "invalid"))
        @test_throws ArgumentError MinimalMFRM.main(["--cmdstan"]; output_parent = joinpath(directory, "invalid"))
        @test !ispath(joinpath(directory, "invalid"))
    end
    if teaching_fit === nothing
        teaching_fit = fit(prepared.spec; chains = 2, warmup = 64, ndraws = 64,
            seed = 2026112601, chain_execution = :serial, progress = false)
    end
    if minimal_fit === nothing
        minimal_fit = fit(MinimalMFRM.inputs().spec; chains = 2, warmup = 50, ndraws = 50,
            seed = 102, chain_execution = :serial, progress = false)
    end
    original = joinpath(directory, "original.jls")
    save_fit(original, teaching_fit)
    original_hash = sha256(read(original))
    @testset "Standard onboarding: reporting and portable checkpoint" begin
        @test A.check_input(teaching_fit, prepared) === teaching_fit
        @test_throws ArgumentError A.result(nothing, prepared)
        @test_throws ArgumentError A.result(minimal_fit, prepared)
        invalid = joinpath(directory, "mismatched")
        @test_throws ArgumentError MinimalMFRM.main(["--saved-fit", original]; output_parent = invalid)
        @test !ispath(invalid)
        answer = open(joinpath(directory, "report.log"), "w") do io
            redirect_stdout(io) do
                A.main(["--saved-fit", original]; output_parent = joinpath(directory, "reports"))
            end
        end
        @test sha256(read(original)) == original_hash
        @test isequal(posterior_summary(answer.fitted), posterior_summary(teaching_fit))
        @test !answer.result.numerically_qualified
        @test occursin("Withhold", answer.result.interpretation)
        @test answer.result.ppc.ndraws == 1000
        @test isfile(joinpath(answer.directory, "fit.jls"))
        @test isfile(joinpath(answer.directory, "handoff.json"))
        @test occursin("Whole-fit qualification: failed", read(joinpath(answer.directory, "answer.txt"), String))
        portable = B.PortableHandoff.load_handoff(joinpath(answer.directory, "handoff.json"))
        @test portable.record.handoff_bundle_sha256 == answer.handoff.record.handoff_bundle_sha256
    end
    @testset "Standard onboarding: preserve fit before a reporting failure" begin
        output = joinpath(directory, "interrupted")
        failure = open(joinpath(directory, "interrupted.log"), "w") do io
            redirect_stdout(io) do
                try
                    InterruptedAnalysis.FirstMFRMAnalysisV02.main(["--saved-fit", original]; output_parent = output)
                catch err
                    err
                end
            end
        end
        @test failure isa ErrorException
        @test sprint(showerror, failure) == "injected standard-example reporting failure"
        checkpoint = only(readdir(output; join = true))
        @test !isfile(joinpath(checkpoint, "answer.txt"))
        @test isequal(posterior_summary(load_fit(joinpath(checkpoint, "fit.jls"))), posterior_summary(teaching_fit))
        @test B.PortableHandoff.load_handoff(joinpath(checkpoint, "handoff.json")).record.handoff_bundle_sha256 ==
            B.PortableHandoff.export_handoff(teaching_fit).record.handoff_bundle_sha256
        @test sha256(read(original)) == original_hash
    end
    @testset "Standard onboarding: minimal saved-fit path" begin
        input = joinpath(directory, "minimal-original.jls")
        save_fit(input, minimal_fit)
        input_hash = sha256(read(input))
        output = open(joinpath(directory, "minimal.log"), "w") do io
            redirect_stdout(io) do
                MinimalMFRM.main(["--saved-fit", input]; output_parent = joinpath(directory, "minimal"))
            end
        end
        @test output.fitted isa AbstractMFRMFit
        @test isequal(posterior_summary(output.fitted), posterior_summary(minimal_fit))
        @test !output.qualification.qualified
        @test isfile(joinpath(output.directory, "handoff.json"))
        @test sha256(read(input)) == input_hash
    end
end
end
