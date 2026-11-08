module FirstAnalysisChecks
using Test, BayesianMGMFRM, SHA
const B=BayesianMGMFRM
include("../examples/first_analysis.jl")
const A=FirstMFRMAnalysis
include("fixtures/reporting_fit.jl")

# Keep the injected reporting failure separate from the ordinary example module.
module InterruptedAnalysis
include("../examples/first_analysis.jl")
FirstMFRMAnalysis.result(::FirstMFRMAnalysis.MFRMFit, prepared) =
    error("injected first-analysis reporting failure")
end

function checkpoint_checks(fitted)
    @testset "First analysis: preserve a fit when reporting fails" begin
        mktempdir() do directory
            input=joinpath(directory,"original.jls")
            save_fit_cache(input,fitted)
            original_hash=bytes2hex(sha256(read(input)))
            outputs=joinpath(directory,"outputs")
            captured=joinpath(directory,"stdout.txt")
            failure=open(captured,"w") do io
                redirect_stdout(io) do
                    try
                        InterruptedAnalysis.FirstMFRMAnalysis.main(["--saved-fit",input]; output_parent=outputs)
                    catch err
                        err
                    end
                end
            end
            @test failure isa ErrorException
            @test sprint(showerror,failure)=="injected first-analysis reporting failure"
            out=only(readdir(outputs;join=true))
            cache=joinpath(out,"fit.jls")
            @test isfile(cache)
            @test occursin("Saved fit: "*abspath(cache),read(captured,String))
            @test !isfile(joinpath(out,"answer.txt")) && !isfile(joinpath(out,"answer.json"))
            @test bytes2hex(sha256(read(input)))==original_hash
            if isfile(cache)
                restored=load_fit_cache(cache)
                @test restored.draws==fitted.draws
                @test restored.chain_ids==fitted.chain_ids && restored.iterations==fitted.iterations
                @test isequal(restored.sampler_stats,fitted.sampler_stats)
                @test restored.prior==fitted.prior
                @test design_identity(restored.design)==design_identity(fitted.design)
                @test isequal(fit_metadata(restored),fit_metadata(fitted))
            end
        end
    end
end

function checks()
    @testset "First analysis: explicit input and interpretation boundaries" begin
        p=A.inputs()
        @test p.data.n==72
        @test length(p.data.person_levels)==12 && length(p.data.item_levels)==4 && length(p.data.rater_levels)==3
        @test p.data.category_levels==collect(0:3)
        @test p.spec.validation.passed
        @test p.controls.chains==4 && p.controls.ndraws==p.controls.warmup==1000
        @test p.controls.backend===:advancedhmc && p.controls.seed==2026101402
        @test all(iszero,p.controls.init)
        mcse=(;mcse_status=:available,mean_mcse=.01,
            quantiles=((;mcse=.02),(;mcse=.001),(;mcse=.02)))
        @test A.numerical_checks_pass(true,mcse)
        @test !A.numerical_checks_pass(false,mcse)
        @test !A.numerical_checks_pass(true,merge(mcse,(;mean_mcse=.01001)))
        @test !A.numerical_checks_pass(true,merge(mcse,(;quantiles=((;mcse=.02001),(;mcse=.001),(;mcse=.02)))))
        @test !A.numerical_checks_pass(true,merge(mcse,(;quantiles=((;mcse=.02),(;mcse=.001),(;mcse=.02001)))))
        @test !A.numerical_checks_pass(true,merge(mcse,(;mcse_status=:insufficient_draws)))
        for bad in (missing,NaN,Inf,-.01,true)
            @test !A.numerical_checks_pass(true,merge(mcse,(;mean_mcse=bad)))
        end
        @test occursin("Do not interpret",A.interpretation(false,.1,.9))
        @test occursin("more severe",A.interpretation(true,.1,.9))
        @test occursin("less severe",A.interpretation(true,-.9,-.1))
        @test occursin("does not show",A.interpretation(true,-.5,.9))
        @test occursin("includes zero",A.interpretation(true,0.,.9))
        @test_throws ArgumentError A.main(["--unknown"])
    end
    # Fixed deterministic values test persistence, not posterior precision.
    checkpoint_checks(reporting_fit(:mfrm))
    @testset "First analysis: retain numerical context in the answer" begin
        for recorded in (true, false)
            # Fixed diagnostic fixtures, not posterior or calibration evidence.
            fitted=reporting_fit(:mfrm;data=A.inputs().data,recorded)
            prepared=(;data=fitted.design.spec.data,spec=fitted.design.spec,prior=fitted.prior)
            answer=A.result(fitted,prepared)
            @test !answer.numerically_qualified
            @test occursin("Do not interpret",answer.interpretation)
            @test isequal(answer.diagnostics.summary,diagnostics(fitted;view=:public).summary)
            @test isequal(answer.sampler.retained,sampler_diagnostics(fitted))
            @test isequal(answer.sampler.warmup,sampler_diagnostics(fitted;phase=:warmup))
            @test answer.numerical_criteria.mean_mcse_limit==.01
            @test answer.numerical_criteria.endpoint_mcse_limit==.02
            row=only(answer.sampler.warmup)
            @test row.coverage== (recorded ? :recorded : :not_recorded)
            @test isequal(row.n_divergences,recorded ? 1 : missing)
            output=sprint(io->A.print_result(io,answer))
            @test occursin("Numerical checks: need attention",output)
            @test occursin("MCSE (logit): mean=",output)
            @test occursin("These are not scientific effect-size thresholds.",output)
            @test occursin("separate from retained draws; no warmup pass/fail rule",output)
            @test occursin(recorded ? "recorded/expected iterations=3/3; divergences=1" :
                "coverage=not_recorded; recorded/expected iterations=unavailable/3; divergences=unavailable",output)
            restored=B.JSON3.read(B.JSON3.write(answer))
            @test restored.sampler.warmup[1].coverage==String(row.coverage)
            @test isequal(restored.sampler.warmup[1].n_divergences,recorded ? 1 : nothing)
        end
    end
end
end
