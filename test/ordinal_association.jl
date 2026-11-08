module OrdinalAssociationTests
using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Serialization, JSON3, Statistics
import LogDensityProblems as L
const B=BayesianMGMFRM
const J=B.Experimental.JointRatings
const S=J.S
const A=J.OrdinalAssociation
include("joint_ratings_fixture.jl")

function fixture(;K=3,sparse=true)
    b=static_fixture(;K,shared=false,predictors=false,sparse)
    prior=merge(Base.structdiff(b.prior,(;beta_sd=nothing)),
        (;intercept_sd=1.5,person_log_sd_mean=log(.5),person_log_sd_sd=.5,lambda_sd=.5))
    A.model(b.data.rows;criteria=b.data.criteria,prior)
end

function finite_checks()
    tests=@testset "Ordinal association target, identity and score" begin
        for K in (3,9)
            t=fixture(;K);x=A.initial(t);x.+=.07sin.(eachindex(x))
            value,g=L.logdensity_and_gradient(t,x)
            @test value≈L.logdensity(t,x) atol=1e-12
            @test g≈ForwardDiff.gradient(z->L.logdensity(t,z),x) atol=2e-9 rtol=2e-9
            r=A.target_record(t)
            @test isequal(A.target_record(A.from_record(r)),r)
            @test !A.contract().scientific_acceptance
            for u in ([0.,0.],[.4,-.7])
                e=A.effects(t,x,u);v=A.representative(t,x)
                @test vec(sum(e.word;dims=2))≈zeros(2) atol=1e-12
                @test e.theta.-e.word[:,1].+e.intercept≈v.theta.-v.coordinates.task[:,1] atol=1e-12
            end
            bad=deepcopy(t);bad.layout.hp[1,1]+=.1
            @test_throws ArgumentError A.target_record(bad)
            bad=deepcopy(t);bad.layout.original.events[1]=(1,-1,-1)
            @test_throws ArgumentError A.target_record(bad)
            bad=deepcopy(t);bad.layout.original.base.mean[1]=.1
            @test_throws ArgumentError A.target_record(bad)
            q=copy(x);q[1]=NaN
            @test L.logdensity(t,q)==-Inf
            @test_throws ArgumentError L.logdensity(t,x[1:end-1])
            for scale in (0.,-1.,Inf,NaN,true)
                @test_throws ArgumentError A.model(r.rows;criteria=r.criteria,
                    prior=merge(r.prior,(;lambda_sd=scale)))
            end
            @test_throws ArgumentError A.fit(t;ndraws=4,warmup=4,chains=2,seed=5,reconstruction_seed=5)
        end
        @test_throws ArgumentError fixture(;K=2)
        b=static_fixture(;shared=true,predictors=false)
        pr=merge(Base.structdiff(b.prior,(;beta_sd=nothing)),
            (;intercept_sd=1.5,person_log_sd_mean=log(.5),person_log_sd_sd=.5,lambda_sd=.5))
        @test_throws ArgumentError A.model(b.data.rows;criteria=b.data.criteria,prior=pr)
        for name in (:model,:fit,:report,:contrast,:event_probabilities,:save_result,:load_result,:save_report,:contract)
            @test Base.Docs.doc(getfield(A,name))!==nothing
        end
    end
    tests.n_passed
end

# One deliberately short plumbing run. It cannot qualify posterior inference.
function operation_checks(directory)
    tests=@testset "Ordinal association fit/report/persistence plumbing" begin
        t=fixture();sample=A.fit(t;ndraws=20,warmup=20,chains=2,seed=2026102907,
            reconstruction_seed=2026102908,target_accept=.9,max_depth=5)
        @test sample.run.total_draws==40 && size(sample.locations)==(40,2)
        @test length(sample.run.warmup_stats)==40
        path=joinpath(directory,"smoke.jls")
        A.save_result(path,sample);loaded=A.load_result(path)
        @test isequal(loaded,sample)
        @test_throws ArgumentError A.save_result(path,sample)
        report=A.report(sample)
        @test !report.result.scientific_acceptance
        @test report.result.focal_precision_qualification==:not_assessed
        @test length(report.result.diagnostics.conditional)==2
        @test report.result.diagnostics.sampler==sample.run.sampler_rows
        @test report.warnings==sample.warnings
        c=A.contrast(sample;facet=:person,criterion="a",left="p1",right="p2")
        @test c.result.positive_difference==:higher_canonical_trait
        m=A.model_draws(t,sample.run.draws,sample.locations)
        @test c.result.summary.mean≈mean(m.values[:,1]-m.values[:,3])
        @test_throws ArgumentError A.contrast(sample;facet=:person,criterion="a",left="p1",right="p1")
        e=A.event_probabilities(sample;rating_event_id=first(t.layout.original.base.data.rows).rating_event_id)
        @test length(e.result.cells)==9
        @test sum(r.mean for r in e.result.posterior)≈1. atol=1e-12
        @test e.result.conditioning==:existing_fitted_effects
        out=joinpath(directory,"smoke-report.json");A.save_report(out,report)
        @test JSON3.read(read(out,String)).data.source_sample_content_hash==sample.content_hash
        @test_throws ArgumentError A.save_report(out,report)
        bad=deepcopy(sample);bad.locations[1,1]+=.1
        @test_throws ArgumentError A.restore(bad)
        bad=deepcopy(sample);bad.run.chain_ids[1]=2
        @test_throws ArgumentError A.restore(bad)
        @test_throws ArgumentError A.restore(merge(sample,(;source=merge(sample.source,(;julia="different")))))
    end
    tests.n_passed
end
end
