isdefined(@__MODULE__, :MFRMExchangeableRaterChecks) || include("mfrm_exchangeable_raters.jl")
module MFRMRaterPriorPredictiveChecks
using Test, BayesianMGMFRM, Random, Statistics, LinearAlgebra
using ..MFRMExchangeableRaterChecks: specification, target, reference, SCALES
const B = BayesianMGMFRM
const PRIOR = MFRMPrior(person_sd=SCALES.person_sd, rater_sd=SCALES.rater_kernel_sd,
    item_sd=SCALES.item_sd, step_sd=SCALES.step_sd)

@testset "exchangeable joint prior generation" begin
    for correlated in (false,true), R in (2,3,5)
        t = target(specification(R),correlated)
        rng = MersenneTwister(925+R)
        expected_rng = copy(rng)
        draws = B._fixed_q_prior_draws(t,30_000,rng)
        old = B._fixed_q_prior_draws(t.base,30_000,expected_rng)
        block = reference(t).blueprint.blocks[:rater_free]
        outside = setdiff(axes(draws,2),block)
        @test draws[:,outside] == old[:,outside]
        @test rand(rng) == rand(expected_rng)
        free = draws[:,block]
        full = hcat(free,-sum(free;dims=2))
        expected = SCALES.rater_kernel_sd^2 .* (Matrix{Float64}(I,R,R)-ones(R,R)/R)
        @test maximum(abs.(cov(full)-expected))/SCALES.rater_kernel_sd^2 < 0.025
        @test maximum(abs.(vec(mean(full;dims=1))))/SCALES.rater_kernel_sd < 0.025
        @test maximum(abs.(sum(full;dims=2))) < 1e-14
        for permutation in (reverse(1:R),[collect(2:R);1])
            @test maximum(abs.(cov(full[:,permutation])-expected))/SCALES.rater_kernel_sd^2 < 0.025
        end
        @test abs(cor(full[:,1],draws[:,1])) < 0.03
        if correlated
            rho = tanh.(draws[:,end])
            @test abs(mean(rho.^2)-1/7) < 0.008
            @test abs(cor(full[:,1],rho)) < 0.03
        end
        # Whiten the generated free severities with an independently evaluated
        # Gaussian covariance; check density including all normalization terms.
        sigma = SCALES.rater_kernel_sd^2 .* (Matrix{Float64}(I,R-1,R-1)-ones(R-1,R-1)/R)
        dist = B.Turing.MvNormal(zeros(R-1),sigma)
        for row in eachrow(draws[1:4,:])
            lp = logprior(t.base,row)-sum(B._normal_logpdf(v,SCALES.rater_kernel_sd) for v in row[block])
            @test logprior(t,row) ≈ lp+B.Turing.logpdf(dist,row[block]) atol=1e-10
        end
    end
    @test_throws ArgumentError B._fixed_q_prior_draws(target(specification(),false),0,MersenneTwister(1))
end

@testset "explicit scale matching and shared prior predictive checks" begin
    for correlated in (false,true), R in (2,3,5), K in (2,4),
            matching in (:mean_contrast_variance,:free_rater_marginal_sd)
        spec = specification(R,K)
        model = correlated ? B.Experimental.correlated(spec;lkj_eta=3) : spec
        comparison = B._mfrm_rater_prior_comparison(model;prior=PRIOR,matching,seed=91,ndraws=31)
        old, new = comparison.independent_free, comparison.exchangeable
        @test comparison.matching === matching
        @test old.target_identity != new.target_identity
        a,b = comparison.scales
        if matching === :mean_contrast_variance
            @test a.mean_contrast_variance ≈ b.mean_contrast_variance
            @test a.mean_marginal_variance ≈ b.mean_marginal_variance
        else
            @test a.first_rater_sd ≈ b.first_rater_sd
        end
        @test isequal(a.free_pair_contrast_sd, R==2 ? missing : sqrt(2)*PRIOR.rater_sd)
        if R==2
            @test a.last_rater_sd ≈ b.last_rater_sd
            @test old.parameter_draws ≈ new.parameter_draws atol=1e-14
            @test old.replicated_scores == new.replicated_scores
        end
        t = target(spec,correlated)
        outside = setdiff(axes(new.parameter_draws,2),reference(t).blueprint.blocks[:rater_free])
        @test old.parameter_draws[:,outside] == new.parameter_draws[:,outside]
        @test new.prior.schema == "bayesianmgmfrm.mfrm_exchangeable_raters.v1"
        @test size(new.replicated_scores) == (31,spec.data.n)
        @test all(in(spec.data.category_levels),new.replicated_scores)
        @test !isempty(predictive_check_summary(new;include_grouped=true))
        for check in (old,new)
            snapshot = deepcopy(check)
            pd = B._fixed_q_prior_plot_data(check;block=:rater)
            rd = B._prior_predictive_plot_data(check)
            @test startswith(B._prior_caption(pd),check.prior_label)
            @test startswith(B._prior_predictive_caption(rd),check.prior_label)
            @test occursin("Matching:",check.prior_label)
            @test isequal(check,snapshot)
        end
        # Direct unit-logit partial-credit calculation, independent of the shared
        # 1.7 adapter, checks new-prior draws in the response kernel.
        rows = new.model_coordinates
        theta = filter(r->r.block===:person,rows)
        items = filter(r->r.block===:item,rows)
        raters = filter(r->r.block===:rater,rows)
        steps = filter(r->r.block===:item_steps,rows)
        x = new.parameter_draws[1,:]
        pointwise = B._mfrm_fixed_q_pointwise(reference(t),x[1:B.LogDensityProblems.dimension(reference(t))])
        for n in 1:spec.data.n
            p,i,r = spec.data.person[n],spec.data.item[n],spec.data.rater[n]
            eta = sum(theta[(p-1)*2+d].values[1] for d in 1:2 if spec.q_matrix[i,d])-
                items[i].values[1]-raters[r].values[1]
            logits = cumsum([0.0;[eta-steps[(i-1)*K+k].values[1] for k in 2:K]])
            probs = exp.(logits.-maximum(logits)); probs ./= sum(probs)
            category = findfirst(==(spec.data.score[n]),spec.data.category_levels)
            @test pointwise[n] ≈ log(probs[category]) atol=1e-12
        end
    end
    spec = specification()
    options = (;prior=PRIOR,matching=:mean_contrast_variance,seed=392,ndraws=12)
    Random.seed!(154); expected = rand(); Random.seed!(154)
    result = B._mfrm_rater_prior_comparison(spec;options...)
    @test rand() == expected
    @test isequal(result,B._mfrm_rater_prior_comparison(spec;options...))
    source = spec.data
    data = FacetData((;person=source.person,item=source.item,rater=source.rater,
        score=(source.score.+1).%4);person=:person,item=:item,rater=:rater,score=:score,category_levels=0:3)
    changed = B._mfrm_rater_prior_comparison(mfrm_spec(data;dimensions=2,q_matrix=spec.q_matrix);options...)
    @test result.exchangeable.parameter_draws == changed.exchangeable.parameter_draws
    @test result.exchangeable.replicated_scores == changed.exchangeable.replicated_scores
    for override in ((;matching=:all_contrasts),(;seed=true),(;ndraws=0))
        @test_throws ArgumentError B._mfrm_rater_prior_comparison(spec;merge(options,override)...)
    end
    for s in (specification(;D=3),specification(;mixed=true))
        c = B._mfrm_rater_prior_comparison(s;options...)
        @test size(c.exchangeable.replicated_scores)==(12,s.data.n)
    end
end
end
