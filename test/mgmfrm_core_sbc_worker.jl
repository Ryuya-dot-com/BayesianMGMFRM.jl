# Actual saved draws exercise the new consumer without invoking a sampler.
include(joinpath(@__DIR__,"../scripts/run_mgmfrm_core_sbc.jl"))
const W=MGMFRMCoreSBCWorker
const E,P,B=W.E,W.P,W.B
using Test,JSON3,LinearAlgebra
BLAS.set_num_threads(1)
function main(root,output)
    old=P.readjson(joinpath(root,"review.json"));id="prior-002"
    inputs=P.readjson(joinpath(dirname(root),"20260923-core-sbc-01/inputs.json"))
    entry=only(filter(r->r.id==id,inputs.inputs))
    plan=E.evaluation_plan([id];mode=:prior,backend=:cmdstan,retained_per_chain=4000,
        generator_sha256=P.digest(joinpath(P.REPO,"scripts/mgmfrm_core_reference.py")))
    hashes=(;(k=>String(getproperty(entry.hashes,k)) for k in (:generation,:raw_truth,:truth,:observed))...)
    input=E.bind_panel(plan,id;directory=String(entry.directory),hashes)
    ref=(;path=String(old.reference.path),sha256=String(old.reference.sha256),seed=Int(old.reference.seed))
    fit=E.read_fit(ref);checked=E.check_fit(plan,input,fit;seed=ref.seed)
    r=W.review(fit,checked,input;expected_names=String.(old.export_record.names))
    bytes=E.checked_bytes(String(old.export_record.path),String(old.export_record.sha256))
    previous=reshape(copy(reinterpret(Float64,bytes)),16000,150)
    moments=P.readjson(joinpath(root,"location.json"))
    @testset "New all-quantity worker reproduces the saved 16000-draw consumer" begin
        @test r.values==previous
        @test r.qualification.qualified==old.qualification.qualified==true
        @test length(r.qualification.location_rows)==17
        @test length(r.qualification.diagnostic_rows.focal)==155
        @test length(unique(row.parameter for row in r.qualification.diagnostic_rows.focal))==155
        @test all(row.parameter in getproperty.(r.qualification.diagnostic_rows.focal,:parameter)
            for row in r.qualification.location_rows)
        @test r.truths==Float64[q.truth for q in old.review.rows]
        @test (r.precision.total_draws,r.precision.n_chains,r.precision.draws_per_chain)==(16000,4,4000)
        for (new,prior) in zip(r.precision.rows,old.review.rows)
            @test new.parameter==prior.parameter
            for q in new.quantiles
                orig=only(filter(v->v.probability==q.probability,prior.precision.quantiles))
                @test q.estimate==orig.estimate
                @test q.mcse==orig.mcse
            end
        end
        for (a,b) in zip(r.moments.rows,moments.moments)
            @test a.parameter==b.parameter
            @test a.estimate≈b.estimate atol=1e-15
            @test a.precision.mean_mcse≈b.precision.mean_mcse atol=1e-15
        end
        @test_throws ErrorException W.review(fit,checked,input;expected_names=reverse(r.names))
        setting=P.readjson(joinpath(P.REPO,"results/workflows/20260923-core-sbc-execution-design-01/execution-setting.json"))
        @test all(getproperty(P.prior(),k)==v for (k,v) in pairs(setting.prior))
        @test all(getproperty(P.CRITERIA,k)==v for (k,v) in pairs(setting.criteria))
    end
    P.writejson(output,(;julia_version=string(VERSION),new_sampler_runs=0,tests_passed=true,
        saved_fit_sha256=ref.sha256,quantities=150,conditional_moments=9,scientific_acceptance=false))
end
main(abspath(ARGS[1]),abspath(ARGS[2]))
