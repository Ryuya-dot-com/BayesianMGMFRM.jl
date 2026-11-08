module OptionalDependencyChecks
using Test, BayesianMGMFRM, SHA
using BayesianMGMFRM: JSON3
const B=BayesianMGMFRM

function availability_checks()
    @testset "Optional Turing availability and mathematical owners" begin
        @test !isdefined(B,:Turing)
        @test isfinite(B.SpecialFunctions.logbeta(.5,2.))
        @test B.Distributions.cdf(B.Distributions.Normal(),0.)==.5
        @test first(B.QuadGK.quadgk(x->x^2,0.,1.))≈1/3
        @test B._turing_discard_initial(0)==1
        @test B._turing_discard_initial(3)==4
        @test B._check_turing_ad_backend(:ForwardDiff)===nothing
        @test_throws ArgumentError B._check_turing_ad_backend(:analytic)
        if Base.get_extension(B,:BayesianMGMFRMTuringExt)===nothing
            err=try B._fit_turing();nothing catch e;e end
            @test err isa ArgumentError
            @test occursin("import Turing",sprint(showerror,err))
        end
    end
end

# The payloads below are artificial parser fixtures, not new posterior evidence.
function rw1_provenance_checks(saved_path)
    D=B.Experimental.RaterDrift
    @testset "RW1 retained and optional-dependency producer pairs" begin
        original=JSON3.read(read(saved_path,String),Dict{String,Any})
        @test original["adapter_sha256"]=="307a3450358926c4cfffcde4e55a6b9cd46c7726ccc599252af47a318e115159"
        for hash in (original["adapter_sha256"],bytes2hex(sha256(read(joinpath(pkgdir(B),"src/rater_drift/bridge.jl")))))
            x=deepcopy(original);x["adapter_sha256"]=hash
            text=JSON3.write(x);r=D.report(D.SavedReport(text,D._digest(text)))
            @test r.source.adapter_sha256==hash
            for change in (y->(y["adapter_sha256"]="0"^64),y->(y["context"]["target_sha256"]="0"^64))
                wrong=deepcopy(x);change(wrong);s=JSON3.write(wrong)
                @test_throws ArgumentError D.SavedReport(s,D._digest(s))
            end
        end
    end
end
end
