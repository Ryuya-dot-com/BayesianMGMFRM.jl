module PredictionMCSEChecks
using BayesianMGMFRM, Test, Random, Statistics, Serialization
import ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const K=CommonPredictionKfoldChecks

function scalar_checks()
    @testset "Log-score linearization, covariance, autocorrelation and failure bounds" begin
        # Known iid two-point likelihood, four separate deterministic RNG streams.
        n=8000; chains=4; delta=.15
        signs=reduce(vcat,[ifelse.(rand(MersenneTwister(1700+c),Bool,n),1.,-1.) for c in 1:chains])
        p=.5 .+ delta.*signs
        L=reshape(log.(p),:,1)
        compute(X,C=chains)=B._prediction_log_score_mcse(X,
            [B._logmeanexp(view(X,:,i)) for i in axes(X,2)],C)
        one=compute(L)
        @test one.status===:first_order_approximation
        @test one.value≈(delta/.5)/sqrt(n*chains) rtol=.12
        @test one.per_rating==one.value
        @test compute(hcat(L,L)).value≈2one.value rtol=1e-12
        @test compute(hcat(L,L)).per_rating≈one.value rtol=1e-12
        @test compute(L .- 1000).value≈one.value rtol=1e-10
        @test compute(L .- 1000).max_draw_probability_share≈one.max_draw_probability_share rtol=1e-10
        @test compute(L,1).status===:insufficient_chains
        @test compute(L[1:16,:],2).status===:insufficient_draws
        @test ismissing(compute(fill(-1.,80,3),2).value)
        @test compute(fill(-1.,80,3),2).status===:first_order_degenerate
        # Balanced opposed ratings have zero FIRST-order error, but the nonlinear
        # sum of log means is not constant under resampling; never report MCSE=0.
        balanced=repeat([.4,.6];outer=40)
        cancel=compute(log.(hcat(balanced,1 .- balanced)),2)
        @test cancel.status===:first_order_degenerate && ismissing(cancel.value)
        f(q)=log(q)+log(1-q)
        @test f(.51)!=f(.5)
        # Directional derivative of the actual weighted empirical functional,
        # independent of the production influence implementation.
        u=(p./mean(p).-1)
        direction=sin.(1:length(p));direction.-=mean(direction)
        h=1e-5
        weighted(e)=log(sum((1 .+ e.*direction).*p)/length(p))
        @test (weighted(h)-weighted(-h))/(2h)≈mean(direction.*u) atol=1e-9
        @test one.value≈B._posterior_mcse_value(reshape(u,n,chains),mean) rtol=1e-12
        # Stationary two-state Markov chain with rho=.8 and known asymptotic variance.
        z=Float64[]
        for c in 1:chains
            rng=MersenneTwister(3100+c);state=rand(rng,Bool) ? 1. : -1.
            for t in 1:n
                rand(rng)<.1 && (state=-state)
                push!(z,state)
            end
        end
        correlated=compute(reshape(log.(.5 .+ delta.*z),:,1))
        @test correlated.value > 2one.value
        @test correlated.value≈(delta/.5)*sqrt(9/(n*chains)) rtol=.2
    end
end

function checks(output)
    tests=@testset "Optional K-fold numerical uncertainty" begin
        scalar_checks()
        cases=K.fixture_cases()
        @testset "All eight saved-fit families retain exact default behavior" begin
            @test length(unique(typeof(c.fit) for c in cases))==8
            for c in cases
                scores=K.score_case(c)
                legacy=B.prediction_kfold(c.prepared,scores)
                requested=B.prediction_kfold(c.prepared,scores;mcse=:delta)
                @test requested.elpd==legacy.elpd
                @test requested.pointwise_elpd==legacy.pointwise_elpd
                @test requested.sampling_warning==legacy.sampling_warning
                @test requested.mcmc_error.status===:fold_rng_independence_not_declared
                @test ismissing(requested.mcmc_error.value)
                @test all(r->hasproperty(r,:mcmc_error),requested.folds)
                @test requested.uncertainty.standard_error===:not_computed
                @test !hasproperty(legacy,:mcmc_error)
            end
        end
        c=first(cases);scores=K.score_case(c)
        # Synthetic distinct streams to test quadrature arithmetic; not fitted-posteriors.
        scores=[K.seal(merge(s,(;source_sample_hash="synthetic stream $i"))) for (i,s) in enumerate(scores)]
        p=c.prepared
        a=B.prediction_kfold(p,scores;mcse=:delta,independent_fold_rng=true)
        @test all(r->r.mcmc_error.status===:first_order_approximation,a.folds)
        @test a.mcmc_error.value≈hypot((r.mcmc_error.value for r in a.folds)...)
        @test a.mcmc_error.per_rating≈a.mcmc_error.value/length(a.observation_ids)
        @test !a.mcmc_error.independence_verified
        other=[K.seal(merge(s,(;source_sample_hash="other synthetic stream $i",
            pointwise_loglikelihood=s.pointwise_loglikelihood.-.1))) for (i,s) in enumerate(scores)]
        b=B.prediction_kfold(p,other;mcse=:delta,independent_fold_rng=true)
        cmp=B.compare_kfold_predictions("A"=>a,"B"=>b;comparison_axis=:model,independent_model_rng=true)
        @test cmp.rows[1].difference_mcmc_error.value==0
        @test cmp.rows[1].difference_mcmc_error.status===:baseline_exact_zero
        @test cmp.rows[2].difference_mcmc_error.value≈hypot(a.mcmc_error.value,b.mcmc_error.value)
        @test ismissing(cmp.rows[2].se_elpd_difference)
        @test cmp.uncertainty.standard_error===:not_computed
        @test cmp.model_selection===:not_performed
        undeclared=B.compare_kfold_predictions("A"=>a,"B"=>b;comparison_axis=:model)
        @test undeclared.mcse_warning
        @test undeclared.rows[2].difference_mcmc_error.status===:model_rng_independence_not_declared
        @test ismissing(undeclared.rows[2].difference_mcmc_error.value)
        partial=B.prediction_kfold(p,scores[1:1];mcse=:delta,independent_fold_rng=true,failures=[2=>"interrupted"])
        @test partial.mcmc_error.status===:incomplete
        @test partial.folds[2].mcmc_error.status===:not_scored
        @test partial.folds[2].failure_reason=="interrupted"
        incomplete=B.compare_kfold_predictions("A"=>a,"incomplete"=>partial;comparison_axis=:model)
        @test all(r->ismissing(r.difference_mcmc_error.value),incomplete.rows)
        legacy=B.prediction_kfold(p,scores)
        mixed=B.compare_kfold_predictions("legacy"=>legacy,"new"=>b;comparison_axis=:model,independent_model_rng=true)
        @test mixed.rows[2].difference_mcmc_error.status===:model_mcse_not_requested
        @test_throws ArgumentError B.prediction_kfold(p,scores;mcse=:iid)
        @test_throws ArgumentError B.prediction_kfold(p,scores;independent_fold_rng=true)
        @test_throws ArgumentError B.compare_kfold_predictions("A"=>legacy,"B"=>legacy;comparison_axis=:model,independent_model_rng=true)
        reused=[scores[1],K.seal(merge(scores[2],(;source_sample_hash=scores[1].source_sample_hash)))]
        @test_throws ArgumentError B.prediction_kfold(p,reused;mcse=:delta,independent_fold_rng=true)
        within_reuse=B.prediction_kfold(p,reused;mcse=:delta)
        model_only=B.compare_kfold_predictions("A"=>within_reuse,"B"=>b;
            comparison_axis=:model,independent_model_rng=true)
        @test model_only.rows[2].difference_mcmc_error.status===:model_mcse_unavailable
        @test_throws ArgumentError B.compare_kfold_predictions("A"=>a,"copy"=>a;comparison_axis=:model,independent_model_rng=true)
        @test_throws ArgumentError B.prediction_kfold(p,[merge(scores[1],(;pointwise_loglikelihood=zeros(size(scores[1].pointwise_loglikelihood)))),scores[2]];mcse=:delta)
        @test_throws ArgumentError B.compare_kfold_predictions("A"=>merge(a,(;mcmc_error=merge(a.mcmc_error,(;value=0.)))) ,"B"=>b;comparison_axis=:model)
        path=joinpath(output,"mcse-fixture.jls")
        serialize(path,(;prepared=p,scores,other,a,b,cmp))
        @test isequal(deserialize(path).cmp,cmp)
    end
    return tests
end
end
