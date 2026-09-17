isdefined(@__MODULE__, :MFRMExchangeableSampleChecks) || include("mfrm_exchangeable_samples.jl")

module MFRMValidationPreparationChecks
using Test, Random, Statistics, LinearAlgebra, BayesianMGMFRM
using ..MFRMExchangeableSampleChecks: synthetic_record
include(joinpath(@__DIR__, "..", "scripts", "mfrm_validation_preparation.jl"))
const V = MFRMValidationPreparation
const B = BayesianMGMFRM
const E = B.Experimental

panel(; persons=4, rho=0.6, thin=false) = V.recovery_panel(MersenneTwister(19),
    MersenneTwister(31); persons, rho, thin)
function target(p; correlated=true, exchangeable=true)
    spec = V.specification(p)
    model = correlated ? E.correlated(spec; lkj_eta=2) : spec
    prior = exchangeable ? E.ExchangeablePrior(person_sd=1, rater_kernel_sd=0.5,
        item_sd=1, step_sd=0.5) : MFRMPrior(person_sd=1, rater_sd=0.5/sqrt(2), item_sd=1, step_sd=0.5)
    return B._fixed_q_prior_target(model, prior)
end

function truth_vector(t, truth)
    blocks = V.base_target(t).blueprint.blocks
    x = zeros(B.LogDensityProblems.dimension(t))
    x[blocks[:person]] = vec(permutedims(truth.theta))
    x[blocks[:rater_free]] = truth.r[1:3]
    x[blocks[:item]] = truth.b
    x[blocks[:item_steps]] = vec(permutedims(truth.steps[:, 2:3]))
    V.is_correlated(t) && (x[end] = atanh(truth.rho))
    return x
end

struct ZeroUniform <: AbstractRNG end
Random.rand(::ZeroUniform) = 0.0

@testset "independent fixed-coefficient response preparation" begin
    p = panel()
    spec = V.specification(p)
    @test p.data.n == 128
    @test p.data.category_levels == collect(0:3)
    @test p.truth.theta == panel().truth.theta
    @test p.data.score == panel().data.score
    @test p.truth.theta != panel(rho=0).truth.theta
    @test abs(mean(p.truth.theta[:, 1])) > 1e-6 # no empirical recentering
    large = panel(persons=8)
    thin = panel(thin=true)
    @test large.truth.theta[1:4, :] == p.truth.theta
    @test large.data.score[1:128] == p.data.score
    keep = [r-1 in (mod(i+j-2,4),mod(i+j-1,4))
        for (i,j,r) in zip(p.data.person, p.data.item, p.data.rater)]
    @test thin.data.score == p.data.score[keep]
    @test thin.data.n == 64
    @test all(count(==(r), thin.data.rater) == 16 for r in 1:4)
    # An inconvenient generated outcome is returned, never discarded/redrawn.
    single = V.recovery_panel(MersenneTwister(19), ZeroUniform(); persons=4, rho=0.6)
    @test all(iszero, single.data.score)
    @test single.data.category_levels == collect(0:3)
    @test_throws ArgumentError V.specification(single)
    Random.seed!(907)
    expected = rand()
    Random.seed!(907)
    panel()
    @test rand() == expected
    for n in (true, 1, 145)
        @test_throws ArgumentError V.recovery_panel(MersenneTwister(1), MersenneTwister(2); persons=n, rho=0.)
    end
    for rho in (NaN, Inf, 1., -1., true)
        @test_throws ArgumentError V.recovery_panel(MersenneTwister(1), MersenneTwister(2); persons=4, rho)
    end
    rng = MersenneTwister(1)
    @test_throws ArgumentError V.recovery_panel(rng, rng; persons=4, rho=0.)

    zero = merge(p.truth, (;theta=zeros(4,2), b=zeros(8), r=zeros(4), steps=zeros(8,4), rho=0.))
    @test V.log_probabilities(spec, zero) ≈ fill(-log(4),128,4)
    geometric = merge(zero, (;theta=fill(log(2),4,2)))
    @test exp.(V.log_probabilities(spec, geometric)) ≈ repeat([1. 2. 4. 8.]/15,128,1)
    tail = merge(zero, (;theta=fill(1000.,4,2)))
    tail_logs = V.log_probabilities(spec, tail)
    @test all(isfinite, tail_logs) && tail_logs[1,1] ≈ -3000
    @test tail_logs[1,4] == 0
    # Independent high-precision cumulative-logit oracle, not a fitted kernel.
    logs = V.log_probabilities(spec, p.truth)
    n=17; i=spec.data.item[n]; r=spec.data.rater[n]; person=spec.data.person[n]
    weights = setprecision(256) do
        eta=BigFloat(p.truth.theta[person,i<=4 ? 1 : 2]-p.truth.b[i]-p.truth.r[r])
        logits=[BigFloat(k)*eta-sum(BigFloat.(p.truth.steps[i,2:k+1]);init=BigFloat(0)) for k in 0:3]
        logits .- log(sum(exp,logits))
    end
    @test logs[n,:] ≈ Float64.(weights) atol=1e-12
    for bad in (merge(p.truth,(;person_levels=reverse(p.truth.person_levels))),
            merge(p.truth,(;category_levels=collect(1:4))),
            merge(p.truth,(;dimension_labels=reverse(p.truth.dimension_labels))),
            merge(p.truth,(;rho=1.)), merge(p.truth,(;r=ones(4))),
            merge(p.truth,(;steps=ones(8,4))), merge(p.truth,(;theta=fill(NaN,4,2))))
        @test_throws ArgumentError V.log_probabilities(spec,bad)
    end
end

@testset "target binding, per-draw estimands and chain MCSE" begin
    p=panel(); spec=V.specification(p)
    for correlated in (false,true), exchangeable in (false,true)
        t=target(p;correlated,exchangeable)
        x=truth_vector(t,p.truth)
        state=only(V.model_states(t,reshape(x,1,:)))
        @test state.theta == p.truth.theta
        @test state.b == p.truth.b
        @test state.r ≈ p.truth.r
        @test state.steps == p.truth.steps
        @test state.rho ≈ (correlated ? p.truth.rho : 0.)
        logs=V.log_probabilities(spec,state)
        selected=[logs[n,p.data.category[n]] for n in 1:p.data.n]
        @test selected ≈ B._mfrm_fixed_q_pointwise(V.base_target(t),x[1:length(x)-Int(correlated)]) atol=1e-11
        e=V.estimands(spec,state;correlated)
        @test e.values[1:4] ≈ [1.2,0.4,2.,2.]
        @test e.values[7:8] ≈ [-0.35,0.7]
        @test length(e.names) == (correlated ? 10 : 9)
        @test ("rho" in e.names) == correlated
        shifted=merge(state,(;theta=state.theta .+ [0.5 -0.5], b=state.b+spec.q_matrix*[0.5,-0.5]))
        shifted_e=V.estimands(spec,shifted;correlated)
        @test shifted_e.values ≈ e.values atol=1e-12
        @test shifted_e.centered_theta ≈ e.centered_theta atol=1e-12
        @test shifted_e.centered_b ≈ e.centered_b atol=1e-12

        # Artificial independent draws exercise the plumbing, not convergence.
        draws=permutedims(x) .+ 0.2randn(MersenneTwister(57),80,length(x))
        kwargs=(;parameter_names=B._mfrm_fixed_q_parameter_names(t), chain_ids=repeat(1:4;inner=20),
            iterations=repeat(1:20;outer=4), diagnostic_flag=:ok, expected_target_identity=V.target_identity(t))
        scored=V.score_draws(p,t,draws;kwargs...)
        @test scored.status === :prepared
        @test !scored.scientific_acceptance && !scored.precision_threshold_applied
        @test length(scored.rows) == length(e.names)
        @test all(r.mcse.n_chains==4 && r.mcse.draws_per_chain==20 for r in scored.rows)
        @test [q.probability for q in first(scored.rows).mcse.quantiles] == [0.025,0.975]
        @test first(scored.rows).estimate ≈ mean(scored.estimand_draws[:,1])
        @test first(scored.rows).error ≈ first(scored.rows).estimate-1.2
        @test scored.mean_brier_regret >= 0
        @test scored.predictive.summary.mean_log_score_regret >= -1e-12
        reorder=randperm(MersenneTwister(59),80)
        shuffled=V.score_draws(p,t,draws[reorder,:];merge(kwargs,
            (;chain_ids=kwargs.chain_ids[reorder],iterations=kwargs.iterations[reorder]))...)
        @test isequal(scored.rows,shuffled.rows)
        @test isequal(scored.predictive,shuffled.predictive)
        @test shuffled.chain_order == invperm(reorder)
        warning=V.score_draws(p,t,draws;merge(kwargs,(;diagnostic_flag=:sampler_warning))...)
        @test warning.status === :diagnostic_warning
        degenerate=V.score_draws(p,t,repeat(permutedims(x),80);kwargs...)
        @test degenerate.status === :mcse_unavailable
        @test degenerate.mean_brier_regret ≈ 0 atol=1e-28
        @test degenerate.predictive.summary.mean_log_score_regret ≈ 0 atol=1e-12
        @test_throws ArgumentError V.score_draws(p,t,draws;merge(kwargs,(;expected_target_identity="wrong"))...)
        @test_throws ArgumentError V.score_draws(p,t,draws;merge(kwargs,(;parameter_names=reverse(kwargs.parameter_names)))...)
        duplicate=copy(kwargs.iterations); duplicate[1]=2
        @test_throws ArgumentError V.score_draws(p,t,draws;merge(kwargs,(;iterations=duplicate))...)
        @test_throws ArgumentError V.score_draws(p,t,draws;merge(kwargs,(;chain_ids=ones(Int,80)))...)
        @test_throws ArgumentError V.score_draws(p,t,fill(NaN,size(draws));kwargs...)
        @test_throws ArgumentError V.score_draws(p,t,draws[:,1:end-1];kwargs...)
        @test_throws ArgumentError V.score_draws(panel(thin=true),t,draws;kwargs...)
        changed=deepcopy(p)
        changed.data.score[1]=mod(changed.data.score[1]+1,4)
        changed.data.category[1]=changed.data.score[1]+1
        @test_throws ArgumentError V.score_draws(changed,t,draws;kwargs...)
        badtruth=merge(p,(;truth=merge(p.truth,(;item_levels=reverse(p.truth.item_levels)))))
        @test_throws ArgumentError V.score_draws(badtruth,t,draws;kwargs...)
        if exchangeable
            model=correlated ? E.correlated(spec) : spec
            for backend in (:advancedhmc,:cmdstan)
                record=synthetic_record(t,model,backend)
                fit=E.ExchangeableMFRMFit(record;expected_identity=record.target_identity)
                report=V.score_fit(p,fit;expected_target_identity=record.target_identity)
                @test report.status === :diagnostic_warning
                @test !report.scientific_acceptance
                @test_throws ArgumentError V.score_fit(p,fit;expected_target_identity="different_prior")
            end
        end
    end
end

@testset "posterior probabilities are averaged before predictive scoring" begin
    p=panel(); t=target(p); x=truth_vector(t,p.truth)
    delta=zeros(length(x)); delta[V.base_target(t).blueprint.blocks[:person]] .= 0.9
    draws=permutedims(hcat(x+delta,x-delta))
    score=V.score_draws(p,t,draws;parameter_names=B._mfrm_fixed_q_parameter_names(t),
        chain_ids=[1,2],iterations=[1,1],diagnostic_flag=:ok,expected_target_identity=V.target_identity(t))
    @test score.status === :mcse_unavailable
    states=V.model_states(t,draws); spec=V.specification(p)
    truth=exp.(V.log_probabilities(spec,p.truth))
    prediction=(exp.(V.log_probabilities(spec,states[1]))+exp.(V.log_probabilities(spec,states[2])))/2
    brier=mean(sum(abs2,prediction-truth;dims=2))
    kl=mean(sum(truth.*(log.(truth)-log.(prediction));dims=2))
    @test brier > 1e-5
    @test score.mean_brier_regret ≈ brier atol=1e-14
    @test score.predictive.summary.mean_log_score_regret ≈ kl atol=1e-12
    @test score.predictive.summary.n_prediction_draws == 2
end

@testset "primary denominators and unresolved scores" begin
    p=panel(); t=target(p); id=V.target_identity(t); x=truth_vector(t,p.truth)
    draws=permutedims(x) .+ 0.2randn(MersenneTwister(57),80,length(x))
    score=V.score_draws(p,t,draws;parameter_names=B._mfrm_fixed_q_parameter_names(t),
        chain_ids=repeat(1:4;inner=20),iterations=repeat(1:20;outer=4),
        diagnostic_flag=:ok,expected_target_identity=id)
    plan=[(;id="dataset-$i",target_identity=id) for i in 1:4]
    good=merge(plan[1],(;result=score))
    failed=merge(plan[2],(;result=(;status=:timeout)))
    warning=merge(plan[3],(;result=merge(score,(;status=:diagnostic_warning,diagnostic_flag=:sampler_warning))))
    a=V.summarize_attempts(plan,[good,failed,warning];parameter="r4-r1")
    @test a.planned==4 && a.usable==1 && a.unresolved==3
    @test a.reasons == Dict(:prepared=>1,:timeout=>1,:diagnostic_warning=>1,:missing_attempt=>1)
    c=Int(first(score.rows).covered)
    @test a.all_attempt_coverage_bounds == (c/4,(c+3)/4)
    @test a.coverage_wilson_envelope[1] <= c/4
    @test a.coverage_wilson_envelope[2] >= (c+3)/4
    @test ismissing(a.bias_mcse) && ismissing(a.rmse_mcse)
    empty=V.summarize_attempts(plan,NamedTuple[];parameter="r4-r1")
    @test empty.all_attempt_coverage_bounds == (0.,1.)
    @test ismissing(empty.conditional_rmse)
    complete=V.summarize_attempts(plan,[merge(p,(;result=score)) for p in plan];parameter="r4-r1")
    @test complete.usable == 4 && complete.unresolved == 0
    @test complete.conditional_bias ≈ first(score.rows).error
    @test complete.conditional_rmse ≈ abs(first(score.rows).error)
    @test complete.bias_mcse == 0
    for status in (:generation_error,:fit_error,:scoring_error,:interrupted,:missing_draws,:nonfinite_draws)
        r=V.summarize_attempts(plan,[merge(plan[1],(;result=(;status)))];parameter="r4-r1")
        @test r.usable==0 && r.unresolved==4 && r.reasons[status]==1
    end
    @test_throws ArgumentError V.summarize_attempts(plan,[good,good];parameter="r4-r1")
    @test_throws ArgumentError V.summarize_attempts([plan;plan[1]],[good];parameter="r4-r1")
    @test_throws ArgumentError V.summarize_attempts(plan,[merge(good,(;target_identity="wrong"))];parameter="r4-r1")
    @test_throws ArgumentError V.summarize_attempts(plan,[merge(good,(;id="replacement"))];parameter="r4-r1")
    partial=merge(failed,(;result=(;status=:interrupted,rows=score.rows)))
    @test_throws ArgumentError V.summarize_attempts(plan,[partial];parameter="r4-r1")
    @test_throws ArgumentError V.summarize_attempts(plan,[merge(good,(;result=(;status=:unknown)))];parameter="r4-r1")
end

struct BoundaryBeta <: AbstractRNG end
Random.rand(::BoundaryBeta, ::B.Turing.Beta) = 1.0

@testset "joint-prior generation and SBC quantity binding (no posterior sampling)" begin
    geometry=V._geometry(4)
    for correlated in (false,true), exchangeable in (false,true)
        prior=exchangeable ? E.ExchangeablePrior(person_sd=0.9,rater_kernel_sd=0.4,item_sd=0.7,step_sd=0.25) :
            MFRMPrior(person_sd=0.9,rater_sd=0.4/sqrt(2),item_sd=0.7,step_sd=0.25)
        eta=correlated ? 2 : nothing
        rng=MersenneTwister(821)
        # Distribution/moment checks of prior draws only; no SBC evaluations.
        states=[V._prior_state(geometry,rng,prior;correlated,lkj_eta=eta) for _ in 1:4000]
        raters=permutedims(hcat([s.r for s in states]...))
        C=[Matrix{Float64}(I,3,3); -ones(1,3)]
        expected=exchangeable ? 0.4^2 .* (Matrix{Float64}(I,4,4)-ones(4,4)/4) : prior.rater_sd^2 .* (C*C')
        se=sqrt.((diag(expected)*diag(expected)' + expected.^2)/4000)
        @test all(abs.(cov(raters)-expected) .< 6se)
        @test maximum(abs,vec(mean(raters;dims=1))) < 0.025
        @test maximum(abs,vec(sum(raters;dims=2))) < 1e-12
        @test var([s.b[1] for s in states]) ≈ 0.7^2 atol=0.065
        @test var([s.steps[1,2] for s in states]) ≈ 0.25^2 atol=0.01
        @test var([s.steps[1,4] for s in states]) ≈ 2*0.25^2 atol=0.02
        @test all(s.steps[1,1]==0 && abs(sum(s.steps[1,:])) < 1e-12 for s in states)
        @test var([s.theta[1,1] for s in states]) ≈ 0.9^2 atol=0.12
        @test var([s.theta[1,2] for s in states]) ≈ 0.9^2 atol=0.12
        @test abs(mean(s.theta[1,1]*s.theta[1,2]/0.9^2-s.rho for s in states)) < 0.08
        @test mean(abs(mean(s.theta[:,1])) for s in states) > 0.1 # not recentered
        if correlated
            @test abs(mean(s.rho for s in states)) < 0.04
            @test var([s.rho for s in states]) ≈ 1/5 atol=0.025
        else
            @test all(iszero(s.rho) for s in states)
        end
        make_panel()=V.prior_panel(MersenneTwister(831),MersenneTwister(832);
            persons=4,prior,correlated)
        p=make_panel(); spec=V.specification(p)
        @test p.truth == make_panel().truth && p.data.score == make_panel().data.score
        @test p.generation.kind === :joint_prior && p.generation.lkj_eta === eta
        @test p.truth.b != panel().truth.b && p.truth.r != panel().truth.r
        model=correlated ? E.correlated(spec;lkj_eta=2) : spec
        t=B._fixed_q_prior_target(model,prior)
        x=truth_vector(t,p.truth)
        reconstructed=only(V.model_states(t,reshape(x,1,:)))
        @test reconstructed.r ≈ p.truth.r
        @test reconstructed.steps == p.truth.steps
        @test isfinite(logprior(t,x))
        quantities=V.sbc_quantities(spec,p.truth;correlated)
        @test length(quantities.names)==(correlated ? 13 : 12)
        @test quantities.names[end-2:end] == ["theta11","b1","joint_log_likelihood"]
        @test quantities.values[end-2:end-1] == [p.truth.theta[1,1],p.truth.b[1]]
        @test last(quantities.values) ≈ sum(B._mfrm_fixed_q_pointwise(V.base_target(t),x[1:end-Int(correlated)])) atol=1e-11
        changed=deepcopy(p); changed.data.score .= mod.(changed.data.score .+ 1,4)
        changed.data.category .= changed.data.score .+ 1
        @test V.sbc_quantities(V.specification(changed),p.truth;correlated).values[1:end-1] == quantities.values[1:end-1]
        @test V.sbc_quantities(V.specification(changed),p.truth;correlated).values[end] != quantities.values[end]
        draws=permutedims(x) .+ 0.1randn(MersenneTwister(833),12,length(x))
        opts=(;parameter_names=B._mfrm_fixed_q_parameter_names(t),chain_ids=repeat(1:4;inner=3),
            iterations=repeat(1:3;outer=4),selected_iterations=[1,3],expected_target_identity=V.target_identity(t))
        result=V.sbc_draw_quantities(p,t,draws;opts...)
        @test size(result.draws)==(8,length(quantities.names))
        @test result.truth == quantities.values
        @test result.iterations == repeat([1,3];outer=4)
        @test result.selected_rows == [1,3,4,6,7,9,10,12]
        @test !result.independence_verified && !result.diagnostic_qualification_applied && !result.scientific_acceptance
        shuffled=reverse(1:12)
        other=V.sbc_draw_quantities(p,t,draws[shuffled,:];merge(opts,
            (;chain_ids=opts.chain_ids[shuffled],iterations=opts.iterations[shuffled]))...)
        @test result.draws == other.draws && result.chain_ids == other.chain_ids
        for selection in (Int[],[1,1],[3,1],[0],[4],[true])
            @test_throws ArgumentError V.sbc_draw_quantities(p,t,draws;merge(opts,(;selected_iterations=selection))...)
        end
        invalid=copy(draws);invalid[2,1]=NaN # invalid unselected draws also reject
        @test_throws ArgumentError V.sbc_draw_quantities(p,t,invalid;opts...)
        @test_throws ArgumentError V.sbc_draw_quantities((;p.data,p.truth),t,draws;opts...)
        @test_throws ArgumentError V.sbc_draw_quantities(changed,t,draws;opts...)
        wrong=merge(p,(;generation=merge(p.generation,(;prior=MFRMPrior()))))
        @test_throws ArgumentError V.sbc_draw_quantities(wrong,t,draws;opts...)
        wrong=merge(p,(;generation=merge(p.generation,(;correlated=!correlated,lkj_eta=correlated ? nothing : 2))))
        @test_throws ArgumentError V.sbc_draw_quantities(wrong,t,draws;opts...)
        if correlated
            wrong=merge(p,(;generation=merge(p.generation,(;lkj_eta=3))))
            @test_throws ArgumentError V.sbc_draw_quantities(wrong,t,draws;opts...)
        end
        single=V.prior_panel(MersenneTwister(831),ZeroUniform();persons=4,prior,correlated)
        @test all(iszero,single.data.score) && single.generation.kind === :joint_prior
    end
    prior=E.ExchangeablePrior(rater_kernel_sd=0.4)
    @test_throws ArgumentError V.prior_panel(BoundaryBeta(),ZeroUniform();persons=4,prior,correlated=true)
    @test_throws ArgumentError V.prior_panel(MersenneTwister(1),ZeroUniform();persons=4,prior,correlated=false,lkj_eta=2)
    @test_throws ArgumentError V.prior_panel(MersenneTwister(1),ZeroUniform();persons=4,prior,correlated=true,lkj_eta=true)
    @test_throws ArgumentError V.prior_panel(MersenneTwister(1),ZeroUniform();persons=4,prior=:wrong,correlated=false)
    rng=MersenneTwister(1)
    @test_throws ArgumentError V.prior_panel(rng,rng;persons=4,prior,correlated=true)
end

@testset "randomized ranks and full-denominator CDF envelopes" begin
    rng=MersenneTwister(841)
    @test V.randomized_rank(0.,[-1.,1.],rng).rank == 1
    @test V.randomized_rank(-2.,[-1.,1.],rng).rank == 0
    @test V.randomized_rank(2.,[-1.,1.],rng).rank == 2
    tie=V.randomized_rank(0.,[-1.,0.,0.,1.],rng)
    @test tie.lower==1 && tie.upper==3 && tie.ties==2 && 1 <= tie.rank <= 3
    @test V.randomized_rank(0.,[nextfloat(0.)],rng).rank == 0 # exact, not approximate ties
    all_ties=[V.randomized_rank(0.,zeros(3),rng).rank for _ in 1:4000]
    @test Set(all_ties)==Set(0:3)
    @test all(abs(count(==(k),all_ties)-1000)<130 for k in 0:3)
    @test V.randomized_rank(0.,zeros(3),MersenneTwister(42)) == V.randomized_rank(0.,zeros(3),MersenneTwister(42))
    for (truth,draws) in ((NaN,[0.]),(0.,[Inf]),(0.,Float64[]),(true,[0.]),(0.,[true]))
        @test_throws ArgumentError V.randomized_rank(truth,draws,rng)
    end
    balanced=V.rank_cdf(repeat(0:4;outer=100);n_draws=4,n_quantities=13)
    @test balanced.conditional_screen === :no_resolved_departure
    @test balanced.epsilon ≈ sqrt(log(520)/1000)
    @test !balanced.calibration_verified && !balanced.independence_verified
    biased=V.rank_cdf(zeros(Int,500);n_draws=4,n_quantities=13)
    @test biased.conditional_screen === :departure
    envelope=V.rank_cdf([0,missing,2,missing];n_draws=2,n_quantities=1)
    @test [(r.lower,r.upper) for r in envelope.rows] == [(0.25,0.75),(0.25,0.75),(1.,1.)]
    @test envelope.planned==4 && envelope.usable==2 && envelope.unresolved==2
    @test last(envelope.rows).band_lower == last(envelope.rows).band_upper == 1
    for a in 0:2,b in 0:2
        completed=V.rank_cdf([0,a,2,b];n_draws=2,n_quantities=1)
        @test all(lo.lower <= value.lower <= lo.upper for (lo,value) in zip(envelope.rows,completed.rows))
    end
    @test V.rank_cdf(fill(missing,500);n_draws=4,n_quantities=13).conditional_screen === :unresolved
    @test V.rank_cdf([0;fill(missing,499)];n_draws=4,n_quantities=13).conditional_screen === :no_resolved_departure
    @test V.rank_cdf([zeros(Int,250);fill(missing,250)];n_draws=4,n_quantities=13).conditional_screen === :departure
    for ranks in (Int[],[-1],[3],[NaN],[true],[0.5])
        @test_throws ArgumentError V.rank_cdf(ranks;n_draws=2,n_quantities=1)
    end
    for kwargs in ((;n_draws=0,n_quantities=1),(;n_draws=true,n_quantities=1),
            (;n_draws=2,n_quantities=0),(;n_draws=2,n_quantities=1,alpha=0.),
            (;n_draws=2,n_quantities=1,alpha=NaN))
        @test_throws ArgumentError V.rank_cdf([0];kwargs...)
    end
end

@testset "exact prior-only negative control for rank test quantities" begin
    # Finite two-point prior with the PCM response kernel, not the Gaussian
    # package target: enumerate the exact law, without MCMC or Monte Carlo error.
    probabilities=[8. 4. 2. 1.; 1. 2. 4. 8.]/15
    locations=[-log(2),log(2)]
    rank_laws=Dict((method,quantity)=>zeros(2) for method in (:prior_only,:posterior),quantity in (:parameter,:loglik))
    for truth in 1:2,y in 1:4,draw in 1:2,method in (:prior_only,:posterior),quantity in (:parameter,:loglik)
        draw_probability=method===:prior_only ? 0.5 : probabilities[draw,y]/sum(probabilities[:,y])
        weight=0.5*probabilities[truth,y]*draw_probability
        a,b=quantity===:parameter ? (locations[truth],locations[draw]) :
            (log(probabilities[truth,y]),log(probabilities[draw,y]))
        rank=V.randomized_rank(a,[b],MersenneTwister(851))
        for r in rank.lower:rank.upper
            rank_laws[(method,quantity)][r+1] += weight/(rank.upper-rank.lower+1)
        end
    end
    @test rank_laws[(:prior_only,:parameter)] ≈ [0.5,0.5]
    @test rank_laws[(:prior_only,:loglik)] ≈ [0.35,0.65]
    @test rank_laws[(:posterior,:parameter)] ≈ [0.5,0.5]
    @test rank_laws[(:posterior,:loglik)] ≈ [0.5,0.5]
end
end
