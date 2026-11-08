module ThreeIndicatorFittingChecks
using BayesianMGMFRM, Test, Serialization
using BayesianMGMFRM: JSON3
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const W=T.W
const M=W.M
const CALLS=Int[]
reseal(x;kw...)=W.seal(merge(Base.structdiff(x,(;content_hash=nothing)),(;kw...)))
include("../examples/three_indicator_fit.jl")
const CONTROLS=(;ndraws=32,warmup=2,step_size=.03,target_accept=.9,max_depth=10,metric=:diagonal,ad_backend=:ForwardDiff)
function runner(t,initial;kwargs...)
    k=(;kwargs...);c=k.seed-40;push!(CALLS,c);n=k.ndraws;p=t.size
    @test k.chains==1 && k.init_jitter==0. && k.record_warmup && !k.progress
    draws=[initial[j]+.06sin(.31i*j+c)+.02cos(i+.2j+c) for i in 1:n,j in 1:p]
    logdensities=[M.L.logdensity(t,q) for q in eachrow(draws)]
    stats=[B._advancedhmc_stat_row((;is_adapt=false,acceptance_rate=.9,
        log_density=logdensities[i],hamiltonian_energy=sin(i),hamiltonian_energy_error=.01,
        max_hamiltonian_energy_error=.01,n_steps=7,tree_depth=i==1 ? 10 : 3,numerical_error=false,
        step_size=.03,nom_step_size=.03),1,i) for i in 1:n]
    controls=(;ndraws=k.ndraws,warmup=k.warmup,chains=1,step_size=k.step_size,target_accept=k.target_accept,
        max_depth=k.max_depth,max_energy_error=1000.,metric=k.metric,ad_backend=k.ad_backend,gradient_backend=:ad,
        rng=(;algorithm=:MersenneTwister,seed=k.seed,replayable=true),init_jitter=0.)
    iterations=collect(1:n);chain_acceptance=[B._stat_mean(stats,:acceptance_rate)]
    (;checked=(;rhat_threshold=k.rhat_threshold,ess_threshold=k.ess_threshold),nparams=p,
      initial=copy(initial),initial_logdensity=M.L.logdensity(t,initial),total_draws=n,draws,
      logdensities,chain_ids=ones(Int,n),iterations,chain_acceptance,sampler_stats=stats,controls,
      sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,chain_acceptance,stats,controls,:advancedhmc),
      backend=:advancedhmc,sampler=:nuts,split_chains_requested=true,actual_split=false,
      warmup_stats=[(;chain=1,iteration=i,divergent=i==1,tree_depth=10,nonfinite_logdensity=false) for i in 1:k.warmup])
end

function checks(out)
    @testset "Three-outcome public preparation and artificial failure handling" begin
        p=prepare_three_indicator_example(;controls=CONTROLS,chain_seeds=collect(41:44))
        @test p.kind===:posterior && p.prior==M.REFERENCE_PRIOR
        @test length(p.initial_points)==4 && length(first(p.initial_points))==297
        @test T.contract().fitting && T.contract().native_chain_import && !T.contract().historical_native_import
        input=JSON3.read(p.input_json)
        @test_throws ArgumentError T.prepare(input;prior=merge(p.prior,(;beta_sd=.2)),controls=p.controls,chain_seeds=p.chain_seeds,focal=p.focal)
        wrong=JSON3.read(p.input_json,Dict{String,Any});wrong["X"][1][1]=0
        @test_throws ArgumentError T.prepare(JSON3.read(JSON3.write(wrong));prior=p.prior,controls=p.controls,chain_seeds=p.chain_seeds,focal=p.focal)
        bad=reseal(p;input_json=JSON3.write(wrong))
        @test_throws ArgumentError T.fit(bad;directory=joinpath(out,"invalid"))
        @test !ispath(joinpath(out,"invalid"))
        # Existing output independently prevents a real sampler call in this test.
        mkpath(out)
        @test_throws ArgumentError T.fit(p;directory=out)
        @test isempty(readdir(out))
        @test_throws ArgumentError T.load_fit(out;require_complete=1)
        @test_throws ArgumentError W.check_plan(reseal(p;context=merge(p.context,(;julia="other"))))
        # Matrix input is serialized as rows, not flattened by JSON3.
        native=merge((;pairs(input)...),(;X=M.mat(input.X),y=M.mat(input.y),l1_contrast=M.mat(input.l1_contrast),token_lookup=M.mat(input.token_lookup)))
        n=T.prepare(native;prior=p.prior,controls=p.controls,chain_seeds=p.chain_seeds,focal=p.focal)
        @test W.check_plan(n).data==W.check_plan(p).data
        fixture=W.prepare(input;controls=p.controls,initial_points=p.initial_points,chain_seeds=p.chain_seeds,focal=p.focal,fixture=true)
        @test_throws ArgumentError T.fit(fixture;directory=joinpath(out,"fixture-rejected"))
        empty!(CALLS)
        failrunner(t,q;kw...)=((;kw...).seed==42 ? error("manufactured interruption") : runner(t,q;kw...))
        directory=joinpath(out,"artificial-interruption")
        @test_throws ErrorException W.run_chains(fixture,directory;_runner=failrunner)
        @test CALLS==[1]
        @test isfile(joinpath(directory,"chain-1.jls")) && isfile(joinpath(directory,"chain-2-failed.jls"))
        @test !ispath(joinpath(directory,"chain-2.jls"))
        partial=W.load_completed(directory;require_complete=false)
        @test length(partial.chains)==1 && partial.plan.kind===:deterministic_fixture
        @test_throws ArgumentError T.load_fit(directory;require_complete=false)
        @test_throws ArgumentError W.load_completed(directory)
        @test_throws ArgumentError W.report(partial)
        tampered=deepcopy(partial.chains[1]);tampered.run.draws[1,1]+=.1
        @test_throws ArgumentError W.check_chain(fixture,tampered)
        for op in (T.prepare,T.fit,T.load_fit,T.summarize)
            @test Base.Docs.doc(op)!==nothing
        end
    end
end

function context_checks()
    @testset "Listener contrast position support before fitting" begin
        p=@test_logs (:warn,r"pair_1_3_CHN_at_half.*left.*extrapolation") (:warn,r"pair_1_3_CHN_at_half.*right.*extrapolation") prepare_three_indicator_example(;controls=CONTROLS,chain_seeds=collect(41:44))
        review=T.report(p);rows=review.listener_support.rows
        @test review.kind===:prepared_plan && !review.scientific_acceptance
        @test review.listener_support.status===:recorded
        @test getproperty.(rows,:status)==[:within_observed_range,:within_observed_range,:outside_observed_range,:outside_observed_range]
        @test getproperty.(rows,:observations)==[15,15,12,12]
        @test getproperty.(rows,:lower)==[-.4,-.4,-.4,-.4]
        @test getproperty.(rows,:upper)==[.3,.4,.4,.4]
        @test length(review.warnings)==2
        @test review.focal_definitions==p.focal
        @test_throws ArgumentError T.report(merge(p,(;content_hash="0"^64)))
        d=W.check_plan(p).data
        for position in (-.4,.4)
            f=merge(p.focal,(;listener_pairs=[merge(p.focal.listener_pairs[2],(;time=position))]))
            @test all(r->r.status===:within_observed_range,T._listener_support(d,f))
        end
        f=merge(p.focal,(;listener_pairs=[merge(p.focal.listener_pairs[2],(;time=-.5))]))
        @test all(r->r.status===:outside_observed_range,T._listener_support(d,f))
        # Artificial metadata only: exercise an absent listener/L1 context,
        # without calling it a validated input or generating any responses.
        absent=merge(d,(;l1=[d.rater[n]==1 ? 1 : d.l1[n] for n in 1:d.N]))
        a=T._listener_support(absent,p.focal)[1]
        @test a.status===:unobserved_context && a.observations==0
        @test a.lower===nothing && a.upper===nothing
        @test occursin("no observations",only(T._support_warnings([a])))
        @test Base.Docs.doc(T.report)!==nothing
    end
end
end
