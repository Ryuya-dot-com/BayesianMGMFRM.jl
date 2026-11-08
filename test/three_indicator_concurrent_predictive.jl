module ThreeIndicatorConcurrentPredictiveChecks
using BayesianMGMFRM, Test, Random, Statistics, JSON3
import ..ThreeIndicatorConcurrentChecks as Fixtures
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const P=T.ConcurrentPredictive
const F=T.ConcurrentWorkflow
const R=T.ConcurrentReports

function checks()
    @testset "Posterior response law, chart invariance and discrete support" begin
        input=T.ConcurrentInput(Fixtures.fixture();source_sha256="a"^64)
        uniforms=[(mod(31n+17a,997)+.5)/997 for n in 1:700,a in 1:3]
        for prior in (:reference,:steps,:combined), interaction in (:none,:diagonal,:full)
            t=getdesign(input;prior,interaction);q=initial_params(t)+.03sin.(1:t.size)
            design=P.layout(t);counts=zeros(UInt16,202);mu=zeros(202);v=zeros(202)
            P.state!(counts,mu,v,t,q,design.panel,MersenneTwister(1);uniforms)
            expected=zeros(Int,202);z=T.Concurrent.reconstruct(t,q);p=R.blank();buffer=zeros(9)
            for n in 1:700
                R.probabilities!(p,buffer,t,z,n)
                y=[min(searchsortedlast(cumsum(p[a]),uniforms[n,a])+1,length(p[a])) for a in 1:3]
                for a in 1:3;expected[P.index(design.panel[n],a,y[a])]+=1;end
                expected[P.joint(design.panel[n],y[1],y[2])]+=1
            end
            @test counts==expected
            @test design.denominators==[400,300]
            for g in 1:2
                ix=P.joint(g,1,1):P.joint(g,9,9)
                @test sum(counts[ix])==design.denominators[g]
                @test sum(mu[ix])≈design.denominators[g] atol=1e-10
            end
            @test all(isfinite,P.maxima(design.observed,counts,mu,v))
            if interaction===:full
                plan=prepare_fit(t;ndraws=10,warmup=10,chains=2,seed=11,parameterization=:pair_132)
                q132=T.ConcurrentCoordinates.convert_coordinates(T.ConcurrentCoordinates.Target(t),q)
                c2=similar(counts);m2=similar(mu);v2=similar(v)
                P.state!(c2,m2,v2,t,F.native_point(plan,t,q132),design.panel,MersenneTwister(1);uniforms)
                @test c2==counts
                @test m2≈mu atol=1e-10
                @test v2≈v atol=1e-10
            end
        end
        @test mean([.9^2,.1^2])≈.41
        @test mean([.9,.1])^2≈.25
        @test P.mean_mcse(ones(40),2)===nothing
        @test P.estimate(ones(40),2;structural=true).mcse==0.
        x=repeat([0.,1.],20)
        lower=P.endpoint(x,sort(x),.025,1,2);upper=P.endpoint(x,sort(x),.975,1,2)
        @test lower.count==0 && upper.count==1
        @test lower.cdf_below.precision_status===:analytic_support
        @test upper.cdf_at.precision_status===:analytic_support
        @test lower.quantile_mcse===nothing && upper.quantile_mcse===nothing
        t=getdesign(input;prior=:steps,interaction=:full)
        plan=prepare_fit(t;ndraws=10,warmup=10,chains=2,seed=11)
        partial=F.Fit(plan,NamedTuple[])
        @test_throws ArgumentError predictive_check(partial;seed=1)
        @test_throws ArgumentError predictive_check(partial;seed=true)
        @test_throws ArgumentError predictive_check(partial;seed=-1)
        @test_throws ArgumentError predictive_check(partial;seed=1,conditioning=:new_levels)
    end
end

function operation_checks(dir)
    @testset "Explicit posterior provenance and shared save/reopen" begin
        t=getdesign(T.ConcurrentInput(Fixtures.fixture();source_sha256="a"^64);prior=:steps,interaction=:full)
        f=fit(t;directory=joinpath(dir,"fit"),chains=2,warmup=10,ndraws=10,seed=20261103,max_depth=1)
        report=predictive_check(f;seed=103)
        @test report.check_type=="posterior_predictive"
        @test report.parameter_source=="fitted_posterior"
        @test report.data_used_to_estimate_parameters && !report.prior_predictive_performed
        @test !report.posterior_fit_qualified && !report.scientific_acceptance
        @test P.FIT_WARNING in report.warnings
        @test report.chain_ids==repeat(1:2;inner=10)
        @test report.iterations==repeat(1:10;outer=2)
        @test length(report.rows)==202 && length(report.joint)==2
        @test report.source_fit_hash==F.identity(f)
        @test report==B.posterior_predictive_check(f;seed=103)
        qualification=event_probabilities(f;rows=[1])
        cached=predictive_check(f;seed=103,qualification_report=qualification)
        @test cached.qualification_source=="validated_same_fit_report"
        @test cached.qualification_report_hash==qualification.content_hash
        @test cached.rows==report.rows && cached.joint==report.joint
        @test !cached.posterior_fit_qualified
        @test_throws ArgumentError predictive_check(f;seed=103,interval=1.)
        bad=R.normalized(qualification);bad["source_fit_hash"]="0"^64
        delete!(bad,"content_hash");bad["content_hash"]=B._cache_hash(bad)
        @test_throws ArgumentError predictive_check(f;seed=103,qualification_report=JSON3.read(JSON3.write(bad)))
        receipt=save_report(joinpath(dir,"posterior-predictive.json"),report;return_receipt=true)
        @test load_report(receipt.path;expected_sha256=receipt.sha256)==report
        @test_throws ArgumentError load_report(receipt.path)
        @test_throws ArgumentError save_report(receipt.path,report)
        @test_throws ArgumentError load_report(receipt.path;expected_sha256=receipt.sha256,verify_hash=false)
        for mutate in (d->(d["check_type"]="prior_predictive"),d->(d["parameter_source"]="prior"),
                d->(d["prior_predictive_performed"]=true),d->(d["chain_ids"][1]=2),
                d->(d["rows"][1]["category"]=2),d->(d["discrete_endpoints_unresolved"]+=1),
                d->(d["rows"][1]["outside_pointwise_interval"]=!d["rows"][1]["outside_pointwise_interval"]))
            d=R.normalized(report);mutate(d);delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d)
            @test_throws ArgumentError P.check_report(JSON3.read(JSON3.write(d)))
        end
        open(joinpath(dir,"report-receipt.json"),"w") do io;JSON3.write(io,receipt);end
        # Keep the fitted record and qualification evidence in the operation-test directory.
        save_report(joinpath(dir,"qualification.json"),qualification)
        (;fit=f,report)
    end
end
end
