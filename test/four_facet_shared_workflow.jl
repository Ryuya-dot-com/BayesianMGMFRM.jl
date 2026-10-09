# Opt-in engineering run, no statistical acceptance or automatic retries.
# Julia --project=. test/four_facet_shared_workflow.jl [fresh-output-directory]
# Set BAYESIANMGMFRM_SHARED_TASK_SAMPLING=true to run the declared small fit.
module FourFacetSharedWorkflowChecks
using Test, Random, Statistics, LinearAlgebra, SHA, Serialization, BayesianMGMFRM
import LogDensityProblems as L
const B = BayesianMGMFRM
include("../scripts/four_facet_shared_target.jl")
include("../scripts/four_facet_shared_workflow.jl")
const F,W = FourFacetSharedTarget,FourFacetSharedWorkflow
const PRIOR = (;person_sd=.8,task_kernel_sd=.4,rater_kernel_sd=.3,
    criterion_kernel_sd=.5,step_kernel_sd=.6,shared_sd_scale=.7)
const CONTROLS = (;ndraws=500,warmup=500,chains=4,seed=271003,
    target_accept=.9,max_depth=10,step_size=.03,init_jitter=.1)

function fixture(;K=4,scores=nothing,prior=PRIOR)
    cells = [(p,t,r,c) for p in 1:4 for t in 1:3 for r in 1:3 for c in 1:4]
    table = (;person=first.(cells),task=getindex.(cells,2),rater=getindex.(cells,3),
        criterion=last.(cells),response=["p$p-t$t" for (p,t,r,c) in cells],
        score=scores === nothing ? [mod(p+t+r+c,K) for (p,t,r,c) in cells] : scores)
    data = FacetData(table;person=:person,task=:task,rater=:rater,item=:criterion,
        response_id=:response,score=:score,category_levels=0:K-1)
    spec = mfrm_spec(data;dimensions=2,q_matrix=Bool[cld(c,2)==d for c in data.item_levels,d in 1:2],
        thresholds=:partial_credit)
    return F.SharedTaskTarget(spec;prior,category_direction=:higher_is_more)
end

estimate(values) = (;estimate=mean(values),mcse=std(values)/sqrt(length(values)),draws=length(values))

function prior_checks(directory)
    moments = NamedTuple[]
    t = fixture()
    @testset "Prior generator, covariance and shared conditional replication" begin
        draws = W.prior_draws(MersenneTwister(271010),t,20000)
        @test size(draws) == (20000,L.dimension(t))
        @test W.prior_draws(MersenneTwister(5),t,2) == W.prior_draws(MersenneTwister(5),t,2)
        @test all(isfinite,F.logprior(t,x) for x in eachrow(draws))
        check(name,values,truth) = begin
            result = estimate(values)
            @test abs(result.estimate-truth) <= 7*result.mcse + 1e-14
            push!(moments,(;name,truth,result...))
        end
        for (name,sd) in ((:theta,.8),(:task,.4),(:rater,.3),(:criterion,.5),(:steps,.6),(:z,1.))
            values = vec(draws[:,getproperty(t.blocks,name)])
            check("$name mean",values,0.)
            check("$name second moment",values.^2,sd^2)
        end
        sigma = exp.(draws[:,end])
        check("shared SD mean",sigma,.7sqrt(2/pi))
        check("shared SD second moment",sigma.^2,.7^2)
        u1 = sigma .* draws[:,first(t.blocks.z)]
        u2 = sigma .* draws[:,first(t.blocks.z)+1]
        check("shared effect second moment",u1.^2,.7^2)
        check("different group effect cross moment",u1.*u2,0.)
        # The common random scale makes squared group effects dependent a priori.
        check("different group squared cross moment",(u1.*u2).^2,3*.7^4)
        H = [i<=j ? 1/sqrt(j*(j+1)) : i==j+1 ? -j/sqrt(j*(j+1)) : 0.
             for i in 1:3,j in 1:2]
        rater = draws[:,t.blocks.rater]*H'
        check("rater marginal second moment",rater[:,1].^2,.3^2*2/3)
        check("rater cross moment",rater[:,1].*rater[:,2],-.3^2/3)
        @test maximum(abs.(sum(rater;dims=2))) < 1e-14
        for K in (2,4)
            target = fixture(;K)
            @test all(isfinite,W.prior_draws(MersenneTwister(8),target,3))
            x = zeros(L.dimension(target))
            rng = MersenneTwister(37)
            expected = [floor(Int,K*rand(rng))+1 for _ in 1:target.input_spec.data.n]
            result = W.replicate(MersenneTwister(37),target,x)
            @test result.category_index == expected
            @test result.score == expected.-1
            x[target.blocks.z[1]] = 1.
            x[end] = log(.6)
            lp = F.category_logprobs(target,x)
            weights = exp.(.6 .* collect(0:K-1)); weights ./= sum(weights)
            @test all(n -> exp.(lp[n,:]) ≈ (target.group[n]==1 ? weights : fill(1/K,K)),1:size(lp,1))
            copy_target = fixture(;K,scores=reverse(target.input_spec.data.score))
            @test W.prior_draws(MersenneTwister(20),target,3) == W.prior_draws(MersenneTwister(20),copy_target,3)
            @test W.replicate(MersenneTwister(38),target,x) == W.replicate(MersenneTwister(38),copy_target,x)
        end
        for count in (0,-1,true)
            @test_throws ArgumentError W.prior_draws(MersenneTwister(1),t,count)
        end
        @test_throws ArgumentError W.replicate(MersenneTwister(1),t,zeros(2))
        @test_throws ArgumentError W.replicate(MersenneTwister(1),t,fill(NaN,L.dimension(t)))
        stale = deepcopy(t); stale.group[1] = 0
        @test_throws ArgumentError W.prior_draws(MersenneTwister(1),stale,1)
    end
    summaries = NamedTuple[]
    for A in (.35,.7,1.4)
        target = fixture(;prior=merge(PRIOR,(;shared_sd_scale=A)))
        draws = W.prior_draws(MersenneTwister(271020),target,2000)
        rng = MersenneTwister(271021)
        edge, concentrated, mean_scores = Float64[],Float64[],Float64[]
        for x in eachrow(draws)
            p = exp.(F.category_logprobs(target,x))
            push!(edge,mean(p[:,1]+p[:,end]))
            push!(concentrated,mean(vec(maximum(p;dims=2)).>=.95))
            push!(mean_scores,mean(W.replicate(rng,target,x).score))
        end
        push!(summaries,(;shared_sd_scale=A,edge_category_mass=estimate(edge),
            near_deterministic_row_fraction=estimate(concentrated),replicate_mean_score=estimate(mean_scores)))
    end
    B._write_json_record(joinpath(directory,"prior-predictive.json"),
        (;moment_seed=271010,moment_draws=20000,moments,summaries,
            parameter_seed=271020,replicate_seed=271021,common_random_numbers=true,
            mcse_unit=:independent_joint_prior_draw,scientific_prior_adoption=false))
end

function sampling_checks(directory;replay=nothing)
    template = fixture()
    truth = vec(W.prior_draws(MersenneTwister(271001),template,1))
    truth[end] = log(.4)
    generated = W.replicate(MersenneTwister(271002),template,truth)
    target = fixture(;scores=generated.score)
    plan = (;purpose=:engineering_connection,controls=CONTROLS,
        target_identity=B._cache_hash(F.target_record(target)),N=target.input_spec.data.n,D=L.dimension(target),
        truth,truth_seed=271001,response_seed=271002,true_shared_sd=.4,
        automatic_retry=false,wall_limit=nothing,scientific_acceptance=false,
        posterior_backend_comparison=false,replay_source=replay,
        source_sha256=Dict(path=>bytes2hex(sha256(read(path))) for path in
            (joinpath(@__DIR__,"../scripts/four_facet_shared_target.jl"),
             joinpath(@__DIR__,"../scripts/four_facet_shared_workflow.jl"),@__FILE__)))
    B._write_json_record(joinpath(directory,"sampling-plan.json"),plan)
    elapsed = @elapsed result = replay === nothing ? W.fit_julia(target;CONTROLS...) : W.load_result(replay)
    W.save_result(joinpath(directory,"samples.jls"),result)
    @testset "Shared-task sampler, diagnostics, saved results and prediction" begin
        @test result.target_identity == plan.target_identity
        @test result.run.controls.ndraws == CONTROLS.ndraws
        @test result.run.initial[1:end-1] == zeros(L.dimension(target)-1)
        @test result.run.initial[end] == log(PRIOR.shared_sd_scale)
        @test size(result.run.draws) == (2000,L.dimension(target))
        @test length(result.run.warmup_stats) == 2000
        @test result.run.chain_ids == repeat(1:4;inner=500)
        loaded = W.load_result(joinpath(directory,"samples.jls"))
        report = W.report(result)
        @test isequal(W.report(loaded),report)
        @test report.statistical_acceptance === false
        @test length(report.raw_diagnostics) == L.dimension(target)
        @test all(r->r.parameter_space==:model,report.model_diagnostics)
        @test any(r->r.parameter=="shared_sd",report.mcse)
        scale_row = only(filter(r->r.parameter=="shared_sd",report.posterior))
        @test ismissing(scale_row.probability_positive) && scale_row.direction === :not_applicable_positive_scale
        prediction = W.conditional_prediction(result)
        @test W.conditional_prediction(loaded) == prediction
        @test prediction.input_identity == result.target.input_identity
        @test prediction.new_levels === false && prediction.mcse_status === :not_computed
        @test prediction.observation_id == collect(1:target.input_spec.data.n)
        @test all(isapprox.(sum(prediction.probabilities;dims=2),1.;atol=1e-12,rtol=0))
        @test all(>=(0),prediction.probabilities)
        x = result.run.draws[1,:]
        @test W.replicate(MersenneTwister(70),W.restore(loaded),x) == W.replicate(MersenneTwister(70),target,x)
        @test F.pointwise_loglikelihood(W.restore(loaded),x) == F.pointwise_loglikelihood(target,x)
        @test_throws ArgumentError W.save_result(joinpath(directory,"samples.jls"),result)
        corrupt = deepcopy(result); corrupt.run.draws[1,1] += .1
        @test_throws ArgumentError W.restore(corrupt)
        forged = merge(corrupt,(;content_hash=B._cache_hash(Base.structdiff(corrupt,(;content_hash=nothing)))))
        @test_throws ArgumentError W.restore(forged) # Densities are replayed, not just checksummed.
        stale = deepcopy(result); stale.target.input_spec.data.score[1] = mod(stale.target.input_spec.data.score[1]+1,4)
        @test_throws ArgumentError W.restore(stale)
        B._write_json_record(joinpath(directory,"report.json"),report)
        B._write_json_record(joinpath(directory,"conditional-prediction.json"),prediction)
        B._write_json_record(joinpath(directory,"execution.json"),
            (;seconds=elapsed,new_fits=replay === nothing ? 1 : 0,scientific_acceptance=false,
                target_identity=result.target_identity,sample_sha256=bytes2hex(sha256(read(joinpath(directory,"samples.jls")))),
                raw_warning_parameters=[r.parameter for r in report.raw_diagnostics if r.flag != :ok],
                model_warning_parameters=[r.parameter for r in report.model_diagnostics if r.flag != :ok]))
    end
end

function main(directory)
    prior_checks(directory)
    replay = get(ENV,"BAYESIANMGMFRM_SHARED_TASK_REPLAY",nothing)
    if get(ENV,"BAYESIANMGMFRM_SHARED_TASK_SAMPLING","false") == "true" || replay !== nothing
        sampling_checks(directory;replay)
    end
end
if isempty(ARGS)
    mktempdir(main)
else
    length(ARGS)==1 || error("expected one fresh output directory")
    ispath(only(ARGS)) && error("select a fresh output directory")
    main(mkdir(only(ARGS)))
end
end
