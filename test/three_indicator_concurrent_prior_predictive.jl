module ThreeIndicatorConcurrentPriorPredictiveChecks
using BayesianMGMFRM, Test, Random, Statistics, JSON3
import ..ThreeIndicatorConcurrentChecks as Fixtures
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const C=T.Concurrent
const P=T.ConcurrentPriorPredictive
const R=T.ConcurrentReports

function checks()
    report=nothing
    @testset "Joint-prior replication and observation independence" begin
        input=T.ConcurrentInput(Fixtures.fixture();source_sha256="a"^64)
        for prior in (:reference,:steps,:combined),interaction in (:none,:diagonal,:full)
            t=getdesign(input;prior,interaction)
            r=prior_predictive_check(t;ndraws=12,seed=71)
            @test r.check_type=="prior_predictive" && r.parameter_source=="joint_prior"
            @test !r.data_used_to_estimate_parameters && !r.posterior_predictive_performed
            @test r.replications==12 && r.draw_ids==collect(1:12)
            @test r.sampling=="independent_joint_prior" && r.conditioning=="declared_design"
            @test r.model.interaction==string(interaction) && r.model.prior.name==string(prior)
            @test !r.scientific_acceptance && r.new_fits==0
            @test length(r.rows)==202 && r.denominators==[400,300]
            @test all(x->x.lower isa Integer && x.upper isa Integer && x.lower<=x.upper,r.rows)
        end
        t=getdesign(input;prior=:steps,interaction=:full)
        a=predictive_check(t;ndraws=12,seed=72)
        @test a==prior_predictive_check(t;ndraws=12,seed=72)
        changed=[merge(r,(;accentedness=10-r.accentedness,comprehensibility=10-r.comprehensibility,
            intelligibility_exact=1-r.intelligibility_exact)) for r in input.rows]
        other=getdesign(T.ConcurrentInput(changed;source_sha256="a"^64);prior=:steps,interaction=:full)
        b=prior_predictive_check(other;ndraws=12,seed=72)
        @test a.model.input_identity!=b.model.input_identity
        @test [x.observed for x in a.rows]!=[x.observed for x in b.rows]
        for k in (:mean,:mean_mcse,:conditional_expected_mean,:median,:lower,:upper,:lower_endpoint,:upper_endpoint)
            @test [x[k] for x in a.rows]==[x[k] for x in b.rows]
        end
        @test P.estimate(zeros(12)).mcse===nothing
        @test P.estimate(zeros(12);structural=true).mcse==0
        @test P.estimate([0.,1.,0.,1.]).mcse≈sqrt(1/12)
        @test P.endpoint([0.,0.,1.,1.],[0.,0.,1.,1.],.025,1).cdf_below.precision_status===:analytic_support
        @test P.endpoint([0.,0.,1.,1.],[0.,0.,1.,1.],.975,1).cdf_at.precision_status===:analytic_support
        for options in ((;ndraws=1,seed=1),(;ndraws=true,seed=1),(;ndraws=2,seed=true),
                        (;ndraws=2,seed=-1),(;ndraws=2,seed=1,interval=1.),
                        (;ndraws=2,seed=1,conditioning=:existing_levels))
            @test_throws ArgumentError prior_predictive_check(t;options...)
        end
        mktempdir() do dir
            path=joinpath(dir,"prior.json");receipt=save_report(path,a;return_receipt=true)
            @test load_report(path;expected_sha256=receipt.sha256)==a
            @test_throws ArgumentError load_report(path)
            @test_throws ArgumentError save_report(path,a)
            @test_throws ArgumentError load_report(path;expected_sha256=receipt.sha256,verify_hash=false)
            @test_throws ArgumentError save_report(joinpath(dir,"bad.json"),a;unexpected=true)
            for mutate in (d->(d["check_type"]="posterior_predictive"),d->(d["parameter_source"]="fitted_posterior"),
                    d->(d["data_used_to_estimate_parameters"]=true),d->(d["sampling"]="mcmc"),
                    d->(d["draw_ids"][1]=2),d->(d["rows"][1]["category"]=2),
                    d->(d["discrete_endpoints_unresolved"]+=1),d->(d["rows"][1]["outside_pointwise_interval"]=!d["rows"][1]["outside_pointwise_interval"]))
                d=R.normalized(a);mutate(d);delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d)
                @test_throws ArgumentError P.check_report(JSON3.read(JSON3.write(d)))
            end
        end
        report=a
    end
    target=getdesign(T.ConcurrentInput(Fixtures.fixture();source_sha256="a"^64);prior=:steps,interaction=:full)
    seed_checks(report,target)
    report
end

function seed_checks(report,t)
    @testset "Exact seed provenance regression" begin
        @test report.seed_encoding=="decimal_strings"
        master=parse(Int,report.seed)
        streams=parse.(Int,[report.parameter_seed,report.response_seed])
        @test streams==rand(MersenneTwister(master),0:typemax(Int),2)
        generated=P.replicate(t,report.replications,streams)
        @test [mean(Float64.(generated.counts[:,j])) for j in 1:202]==[x.mean for x in report.rows]
        large=prior_predictive_check(t;ndraws=2,seed=typemax(Int))
        @test parse(Int,large.seed)==typemax(Int)
        @test parse.(Int,[large.parameter_seed,large.response_seed])==rand(MersenneTwister(typemax(Int)),0:typemax(Int),2)
        changed=R.normalized(report);changed["parameter_seed"]=string(streams[1]+1)
        @test_throws ArgumentError P.check_report(JSON3.read(JSON3.write(changed)))
    end
end
end
