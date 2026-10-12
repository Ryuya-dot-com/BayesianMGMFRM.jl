# Re-evaluate an actual byte-exact restored cache, never invoke a sampler.
include(joinpath(@__DIR__,"../scripts/run_mgmfrm_core_sbc.jl"))
const W=MGMFRMCoreSBCWorker
const E,P,B=W.E,W.P,W.B
using Test,JSON3,LinearAlgebra
parsed(x)=JSON3.read(JSON3.write(x),Dict{String,Any})

function main(restored,original,output)
    BLAS.set_num_threads(1)
    old=P.readjson(joinpath(original,"joint-001/worker-result.json"))
    c=W.context(original,"joint-001")
    reference=(;path=joinpath(restored,"joint-001/fit.jls"),sha256=String(old.reference.sha256),seed=Int(old.reference.seed))
    fit=E.read_fit(reference)
    checked=E.check_fit(c.plan,c.input,fit;seed=reference.seed)
    r=W.review(fit,checked,c.input;expected_names=String.(old.names))
    values=reshape(copy(reinterpret(Float64,read(joinpath(original,"joint-001/quantities.f64")))),16000,150)
    residuals=reshape(copy(reinterpret(Float64,read(joinpath(original,"joint-001/location-residuals.f64")))),16000,9)
    old_moments=P.readjson(joinpath(original,"joint-001/location-moments.json"))
    @testset "Restored original cache retains the complete SBC consumer" begin
        @test P.digest(reference.path)==old.reference.sha256
        @test size(fit.draws)==(16000,128)
        @test fit.chain_ids==repeat(1:4;inner=4000)
        @test fit.iterations==repeat(1:4000;outer=4)
        @test r.values==values
        @test r.truths==Float64.(old.truths)
        @test parsed(r.qualification)==parsed(old.qualification)
        @test parsed(r.precision)==parsed(old.precision)
        @test r.moments.residuals==residuals
        @test JSON3.read(JSON3.write(r.moments.rows),Vector{Dict{String,Any}})==JSON3.read(JSON3.write(old_moments.rows),Vector{Dict{String,Any}})
        @test r.qualification.qualified===true
        @test P.digest(joinpath(original,"joint-001/fit.jls"))==old.reference.sha256
    end
    P.writejson(output,(;julia_version=string(VERSION),assertions=12,tests_passed=true,
        raw_draws=16000,quantity_value_comparisons=16000*150,conditional_residual_comparisons=16000*9,
        qualification_and_precision_equal=true,new_sampler_runs=0,original_cache_unchanged=true,
        scientific_acceptance=false))
end
main(abspath(ARGS[1]),abspath(ARGS[2]),abspath(ARGS[3]))
