module RaterDriftFittingChecks
# Fixed points and manufactured telemetry only; no model RNG or NUTS transition.
using Test, JSON3, SHA, Serialization, Statistics
using BayesianMGMFRM
const D=BayesianMGMFRM.Experimental.RaterDrift
const W=D.RaterDriftWorkflow
const R=W.R
const M=W.M
const B=W.B
const CALLS=Int[]
const CONTROLS=(;ndraws=64,warmup=2,step_size=.03,target_accept=.9,max_depth=10,
    metric=:diagonal,ad_backend=:ForwardDiff)
const PRECISION=(;mean_mcse_max=.02,endpoint_mcse_max=.03)
reseal(r;kw...)=R.seal(merge(Base.structdiff(r,(;content_hash=nothing)),(;kw...)))

function target(;parameterization=:noncentered,static=false,K=3)
    cells=[(p,r,t) for (j,t) in enumerate((1,3,4)) for p in [collect(1:6);collect(6j+1:6j+6)] for r in 1:4]
    M.Target(;P=24,R=4,K,person=first.(cells),rater=getindex.(cells,2),time=last.(cells),
        score=[mod(p+r+t,K) for (p,r,t) in cells],event=["event-$n" for n in eachindex(cells)],
        person_labels=["performance-$p" for p in 1:24],rater_labels=["judge-$r" for r in 1:4],
        time_ticks=collect(2024:2027),time_labels=["2024","2025 (unrated)","2026","2027"],
        time_unit="year",mu_sigma=-2.,parameterization,static)
end
function prepare(t;fixture=true)
    points=[[.1sin(j+.4c) for j in 1:M.L.dimension(t)] for c in 1:4]
    !t.static && foreach(q->q[end-t.R+1:end].-=2.,points)
    W.prepare(t;controls=CONTROLS,initial_points=points,chain_seeds=collect(11:14),
        reference="2024",panel_weights=fill(.25,4),epsilon=.2,interval=.9,precision=PRECISION,fixture)
end

function runner(t,initial;kwargs...)
    k=(;kwargs...);c=k.seed-10;push!(CALLS,c)
    @test 1<=c<=4 && k.chains==1 && k.init_jitter==0. && k.max_energy_error==1000.
    @test k.record_warmup && !k.progress && k.ad_backend===:ForwardDiff && k.metric===:diagonal
    @test k.rhat_threshold==1.01 && k.ess_threshold==400.
    @test initial==prepare(t).initial_points[c]
    n=k.ndraws;p=M.L.dimension(t)
    draws=[initial[j]+.15sin(.31i*j+c)+.08cos(i+.2j+2c) for i in 1:n,j in 1:p]
    logdensities=[M.L.logdensity(t,q) for q in eachrow(draws)]
    stats=[B._advancedhmc_stat_row((;is_adapt=false,acceptance_rate=.9,
        log_density=logdensities[i],hamiltonian_energy=sin(i),hamiltonian_energy_error=.01,
        max_hamiltonian_energy_error=.01,n_steps=7,tree_depth=i==1 ? 10 : 3,
        numerical_error=false,step_size=.03,nom_step_size=.03),1,i) for i in 1:n]
    controls=W.run_controls(prepare(t),c)
    iterations=collect(1:n);chain_acceptance=[B._stat_mean(stats,:acceptance_rate)]
    (;checked=(;rhat_threshold=k.rhat_threshold,ess_threshold=k.ess_threshold),nparams=p,
      initial=copy(initial),initial_logdensity=M.L.logdensity(t,initial),total_draws=n,draws,
      logdensities,chain_ids=ones(Int,n),iterations,chain_acceptance,sampler_stats=stats,controls,
      sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,chain_acceptance,stats,controls,:advancedhmc),
      backend=:advancedhmc,sampler=:nuts,split_chains_requested=true,actual_split=false,
      warmup_stats=[(;chain=1,iteration=i,divergent=i==1,tree_depth=10,nonfinite_logdensity=false) for i in 1:k.warmup])
end

function prepare_checks(output)
    ispath(output) && error("new output directory required");mkpath(output)
    receipts=NamedTuple[]
    tests=@testset "RW1 sampler connection with deterministic replacement" begin
        @test D.contract().fitting && D.contract().native_chain_import
        for (name,t) in (("noncentered",target()),("centered",target(parameterization=:centered)),
            ("static",target(static=true,parameterization=:centered)),("binary",target(K=2)))
            plan=prepare(t);real_plan=prepare(t;fixture=false)
            @test !hasproperty(plan,:truth) && plan.kind===:deterministic_fixture
            @test_throws ArgumentError W.run_chains(real_plan,joinpath(output,"must-not-run"))
            @test_throws ArgumentError W.run_chains(plan,joinpath(output,"must-not-run");sampling_authorized=true)
            @test_throws ArgumentError W.run_chains(real_plan,joinpath(output,"must-not-run");_runner=runner,sampling_authorized=true)
            @test !ispath(joinpath(output,"must-not-run"))
            # The exact production initializer/ForwardDiff bridge, without sample().
            for q in plan.initial_points
                @test W.B._check_source_fixture_raw_vector(t,q).severity==M.coordinates(t,q).severity
                ad=B._logdensity_gradient_target(t,q,:ForwardDiff)
                lp,g=M.L.logdensity_and_gradient(ad.target,q)
                @test lp≈M.L.logdensity(t,q) atol=1e-12
                @test length(g)==M.L.dimension(t) && all(isfinite,g)
            end
            empty!(CALLS)
            path=joinpath(output,name);saved=W.run_chains(plan,path;_runner=runner)
            @test CALLS==collect(1:4)
            @test isequal(W.load_completed(path),saved)
            empty!(CALLS)
            @test_throws ArgumentError W.run_chains(plan,path;_runner=runner)
            @test isempty(CALLS)
            report=W.report(saved)
            @test report.kind===:deterministic_fixture && !report.posterior && !report.numerical_qualified
            @test !report.statistical_acceptance && report.public_api && !report.forecast && !report.causal_effect
            @test report.sampler_passed && !report.parameter_passed
            @test report.n_max_treedepth==4
            @test all(w->w.n_divergences==1 && w.observed_iterations==2,report.warmup)
            @test all(w->w.n_divergences==0,report.sampler)
            @test report.chain_ids==repeat(1:4;inner=64) && report.iterations==repeat(1:64;outer=4)
            @test length(report.trajectory)==20
            if t.static
                @test all(x->x.structurally_fixed && x.summary===nothing && x.precision_passed===nothing,report.trajectory)
            else
                @test all(x->x.design_status=="process_only_endpoint",filter(x->x.tick==2025,report.trajectory))
                @test all(x->x.design_status=="linked",filter(x->x.tick==2027,report.trajectory))
                @test all(x->x.summary===nothing,filter(x->x.tick==2024,report.trajectory))
            end
            R.write_json(joinpath(output,name*"-report.json"),B._json_export_value(report))
            raw=reduce(vcat,[c.run.draws for c in saved.chains])
            R.write_json(joinpath(output,name*"-input.json"),(;target=plan.target,raw=collect.(eachrow(raw))))
            push!(receipts,(;name,plan_hash=plan.content_hash,chain_hashes=report.chain_hashes,
                report_hash=B._cache_hash(report),dimension=M.L.dimension(t)))
        end
        saved=W.load_completed(joinpath(output,"noncentered"));plan=saved.plan;r=saved.chains[1]
        for change in ((;context=merge(plan.context,(;julia="other"))),(;workflow_sha256="changed"),
            (;chain_seeds=[11,11,13,14]),(;initial_points=fill(plan.initial_points[1],4)),
            (;reference="missing"),(;panel_weights=[.5,.5,.5,.5]),(;epsilon=true),
            (;precision=(;mean_mcse_max=0.,endpoint_mcse_max=.03)),
            (;controls=merge(plan.controls,(;ndraws=9))),(;controls=merge(plan.controls,(;target_accept=true))))
            @test_throws ArgumentError W.check_plan(reseal(plan;change...))
        end
        for change in ((;chain=2),(;kind=:posterior),(;plan_hash="different"),
            (;run=merge(r.run,(;initial=plan.initial_points[2]))),
            (;run=merge(r.run,(;controls=merge(r.run.controls,(;rng=(;algorithm=:MersenneTwister,seed=123,replayable=true)))))),
            (;run=merge(r.run,(;warmup_stats=r.run.warmup_stats[1:1]))))
            @test_throws ArgumentError W.check_chain(plan,reseal(r;change...))
        end
        bad=deepcopy(r);bad.run.draws[1,1]+=.1
        @test_throws ArgumentError W.check_chain(plan,bad)
        @test_throws Exception W.check_chain(plan,reseal(bad))
        bad=deepcopy(r);bad.run.iterations[2]=1
        @test_throws ArgumentError W.check_chain(plan,reseal(bad))
        for chains in (saved.chains[1:3],reverse(saved.chains),fill(r,4))
            @test_throws ArgumentError W.report((;plan,chains))
        end
        good=(;rank_normalized_rhat=1.,bulk_ess=500.,tail_ess=500.)
        @test W.diagnostic_ok(good)
        for (k,v) in ((:rank_normalized_rhat,1.01),(:bulk_ess,399.),(:tail_ess,399.),
            (:rank_normalized_rhat,missing),(:bulk_ess,NaN),(:tail_ess,Inf))
            @test !W.diagnostic_ok(merge(good,NamedTuple{(k,)}((v,))))
        end
        sumgood=W.sampler_summary(r)
        for change in ((;n_divergences=1),(;n_nonfinite_logdensity=1),(;e_bfmi=.29),
            (;e_bfmi=missing),(;n_invalid_sampler_values=1))
            @test !W.sampler_ok(merge(sumgood,change))
        end
        s=(;precision=(;mean_mcse=.01,quantiles=[(;mcse=.02),(;mcse=.01),(;mcse=.03)]))
        @test W.precision_ok(s,PRECISION)
        for v in (missing,NaN,.031)
            @test !W.precision_ok((;precision=(;mean_mcse=.01,quantiles=[(;mcse=v),(;mcse=.01),(;mcse=.02)])),PRECISION)
        end
        # A complete chain containing a retained divergence is valid data, but fails qualification.
        stats=deepcopy(r.run.sampler_stats);stats[1]=merge(stats[1],(;numerical_error=true))
        run=merge(r.run,(;sampler_stats=stats,sampler_rows=B._generalized_candidate_sampler_rows(
            r.run.logdensities,r.run.iterations,r.run.chain_acceptance,stats,r.run.controls,:advancedhmc)))
        flagged=reseal(r;run)
        @test W.check_chain(plan,flagged)==flagged
        report=W.report((;plan,chains=[flagged;saved.chains[2:end]]))
        @test !report.sampler_passed && !report.numerical_qualified && report.sampler[1].n_divergences==1
        R.write_json(joinpath(output,"divergence-report.json"),B._json_export_value(report))
        for value in (NaN,0.)
            stats=deepcopy(r.run.sampler_stats);stats[1]=merge(stats[1],(;step_size=value))
            @test !W.sampler_ok(W.sampler_summary(merge(r,(;run=merge(r.run,(;sampler_stats=stats))))))
        end
        empty!(CALLS)
        failing=(t,q;kw...)->kw[:seed]==12 ? error("deliberate chain 2 fixture failure") : runner(t,q;kw...)
        partial=joinpath(output,"partial")
        @test_throws ErrorException W.run_chains(plan,partial;_runner=failing)
        @test CALLS==[1]
        @test length(W.load_completed(partial;require_complete=false).chains)==1
        @test_throws ArgumentError W.load_completed(partial)
        @test isfile(joinpath(partial,"chain-2-failed.jls")) && !ispath(joinpath(partial,"chain-3-started.jls"))
        empty!(CALLS)
        @test_throws ArgumentError W.run_chains(plan,partial;_runner=runner)
        @test isempty(CALLS)
        invalid=(t,q;kw...)->merge(runner(t,q;kw...),(;initial=zeros(length(q))))
        broken=joinpath(output,"invalid-output")
        @test_throws ArgumentError W.run_chains(plan,broken;_runner=invalid)
        @test isfile(joinpath(broken,"chain-1-returned.jls")) && isfile(joinpath(broken,"chain-1-failed.jls"))
        @test !isfile(joinpath(broken,"chain-1.jls"))
    end
    R.write_json(joinpath(output,"checks.json"),(;status="passed_deterministic_connection_only",
        assertions=tests.n_passed,receipts,context=R.context(),workflow_sha256=R.digest(joinpath(dirname(pathof(B)),"rater_drift","workflow.jl")),
        actual_sampling_calls=0,new_research_datasets=0,model_random_draws=0))
end

function replay(input,output)
    expected=JSON3.read(read(joinpath(input,"checks.json"),String))
    tests=@testset "RW1 fresh-process complete-chain restoration" begin
        for item in expected.receipts
            saved=W.load_completed(joinpath(input,String(item.name)))
            @test saved.plan.content_hash==item.plan_hash
            @test [c.content_hash for c in saved.chains]==item.chain_hashes
            report=W.report(saved)
            @test B._cache_hash(report)==item.report_hash
            @test !report.posterior && !report.numerical_qualified
        end
        @test length(W.load_completed(joinpath(input,"partial");require_complete=false).chains)==1
        @test_throws ArgumentError W.load_completed(joinpath(input,"partial"))
        @test isempty(CALLS)
    end
    R.write_json(output,(;assertions=tests.n_passed,actual_sampling_calls=0,model_random_draws=0,
        report_hashes=[x.report_hash for x in expected.receipts]))
end

const H=D.RaterDriftBridge
function bridge_unit_checks()
    @testset "RW1 bridge full-lag reference" begin
        x=[sin(.003i+.17c)+.0002c*i for i in 1:1200,c in 1:4]
        d=D.RaterDriftBridge.diagnostics(x)
        @test d.mcse≈.1360754930334213 rtol=1e-10
        @test d.rhat≈1.4298914894477248 rtol=1e-10
        @test d.bulk_ess≈8.269374479336422 rtol=1e-10
        @test d.tail_ess≈27.01079727947117 rtol=1e-10
        @test !D.RaterDriftBridge.diagnostic_ok(d)
    end
    @testset "RW1 conditional bridge numerics and rejected scopes" begin
        mu=fill(.3,32,4);sd=fill(.7,32,4)
        for p in (.001,.025,.5,.975,.999)
            @test isapprox(H.mixture_quantile(mu,sd,p),.3+.7H.D.quantile(H.D.Normal(),p);atol=1e-12,rtol=0)
        end
        for p in (0.,1.,NaN)
            @test_throws ArgumentError H.mixture_quantile(mu,sd,p)
        end
        @test_throws ArgumentError H.mixture_quantile(mu,zero(sd),.5)
        @test_throws ArgumentError H.mixture_quantile(mu,fill(NaN,size(sd)),.5)
        @test_throws ArgumentError H.mixture_quantile(mu,ones(32,3),.5)
        # Dense precision / independent quadrature proofs are retained upstream;
        # these fixed mixture values additionally check the Julia root solver.
        mm=[-.8 .1;.4 1.3];ss=[.2 .9;.5 .4]
        for (p,q) in ((.025,-1.1948575807013524),(.5,.28814829441252643),(.975,1.8777403191670268))
            @test isapprox(H.mixture_quantile(mm,ss,p),q;atol=2e-10,rtol=0)
        end
        x=[sin(i/17+c)+.01c for i in 1:800,c in 1:4]
        for b in (20,40,80)
            a=div(800,b);variance=0.
            for c in 1:4
                means=[sum(x[(j-1)*b+1:j*b,c])/b for j in 1:a]
                variance+=sum((z-sum(means)/a)^2 for z in means)/(a*(a-1)*16)
            end
            @test isapprox(H.batch_mcse(x,b),sqrt(variance);atol=1e-14,rtol=0)
            @test isapprox(H.batch_mcse(x,b),H.batch_mcse(reverse(x;dims=1),b);atol=1e-14,rtol=0)
        end
        @test H.batch_mcse(x,40)>3H.batch_mcse(x,1)
        for b in (0,3,800)
            @test_throws ArgumentError H.batch_mcse(x,b)
        end
        t=(;static=false,time_ticks=collect(2024:2027))
        rated=Bool[1 0 1 1;1 0 1 1]
        @test H.eligible(t,2,1,[.5,.5],rated)
        @test !H.eligible(t,1,3,[.5,.5],rated)
        @test !H.eligible(t,4,1,[.5,.5],rated)
        @test !H.eligible(t,2,2,[.5,.5],rated)
        @test !H.eligible(merge(t,(;static=true)),2,1,[.5,.5],rated)
        @test !H.eligible(t,2,1,[0.,0.],rated)
        bad=copy(rated);bad[1,2]=true
        @test !H.eligible(t,2,1,[.5,.5],bad)
        bad=copy(rated);bad[1,3]=false
        @test !H.eligible(t,2,1,[.5,.5],bad)
        # Saturated CDF tails remain explicitly unavailable, with unrounded z.
        mm=[.1sin(.17i+.4c) for i in 1:8000,c in 1:4]
        ss=[exp(3sin(.13i+.3c)-2) for i in 1:8000,c in 1:4]
        d=H.cdf_diagnostics(mm,ss,1.)
        @test d.exact_ones>0
        @test d.tail_status===:rounded_constant_indicator
        @test isnothing(d.cdf.tail_ess)
        @test isfinite(d.unrounded.tail_ess)
        @test !H.diagnostic_ok((;rhat=nothing,bulk_ess=1000.,tail_ess=1000.))
        @test !H.diagnostic_ok((;rhat=1.,bulk_ess=399.,tail_ess=1000.))
    end
end

function public_checks(output)
@testset "Public RW1 planning and fallback boundaries" begin
    t=target()
    args=(;controls=CONTROLS,chain_seeds=collect(11:14),reference="2024",panel_weights=fill(.25,4),epsilon=.2,interval=.9,precision=PRECISION)
    p=D.prepare(t;args...)
    @test p.kind===:posterior
    @test p.initial_points==prepare(t).initial_points
    @test D.RaterDriftWorkflow.check_plan(p).mu_sigma==-2.
    @test D.prepare(target(static=true,parameterization=:centered);args...).target.static
    @test_throws ArgumentError D.prepare(target(parameterization=:centered);args...)
    @test_throws ArgumentError D.prepare(t;args...,initial_points=fill(zeros(D.M.L.dimension(t)),4))
    @test_throws ArgumentError D.NativeFit(D.RaterDriftWorkflow.load_completed(joinpath(output,"deterministic/noncentered")))
    @test_throws ArgumentError D.fit(prepare(t);directory=joinpath(output,"must-not-run"))
    @test !ispath(joinpath(output,"must-not-run"))
    @test_throws ArgumentError D.load_fit("does-not-exist";require_complete=1)
    # Fixed traces and manufactured telemetry, never posterior evidence.
    fixed=D.RaterDriftWorkflow.load_completed(joinpath(output,"deterministic/noncentered"))
    r=D.RaterDriftBridge.report(fixed)
    @test r.count_integrated==0 && !r.posterior && !r.numerical_qualified
    @test count(x->x.integration_status===:insufficient_retained_batches,r.trajectory)==5
    @test all(x->x.estimator===:joint_draws,filter(x->!x.structurally_fixed,r.trajectory))
    text=JSON3.write(B._json_export_value(r))
    @test_throws ArgumentError D.SavedReport(text,bytes2hex(sha256(text)))
    # No isolated bin is a valid report, with unchanged original summaries.
    full=D.RaterDriftWorkflow.R.target(merge(fixed.plan.target,(;time=[v==3 ? 2 : v==4 ? 3 : v for v in fixed.plan.target.time],time_ticks=[2024,2025,2026],time_labels=["2024","2025","2026"])))
    fixture=prepare(full)
    s=D.RaterDriftWorkflow.run_chains(fixture,joinpath(output,"no-empty-fixture");_runner=runner)
    rr=D.RaterDriftBridge.report(s)
    @test rr.count_integrated==0
    @test all(x->x.integration_status===:not_applicable,rr.trajectory)
    @test all(isequal(x.summary,y.summary) for (x,y) in zip(rr.trajectory,rr.original_report.trajectory))
    for name in (:prepare,:fit,:load_fit,:summarize)
        @test Base.Docs.doc(getproperty(D,name))!==nothing
    end
end
end

end
