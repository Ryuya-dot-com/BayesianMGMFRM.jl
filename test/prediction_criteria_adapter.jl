# Run the existing extraction checks in the same Julia process before extensions.
include("prediction_observation_adapter.jl")
module PredictionCriteriaAdapterChecks
using Test, BayesianMGMFRM, Statistics, Serialization
const B = BayesianMGMFRM
using ..PredictionObservationAdapterChecks: reporting_fit, normalized_fixture, F, bytes
using ..PredictionObservationAdapterChecks.PredictionObservationAdapter
import ..PredictionObservationAdapterChecks.PredictionObservationAdapter as A
include("fixtures/prediction_fixed_fits.jl")
options(fit) = (; dataset_id="synthetic-panel", observation_ids=["rating-$n" for n in 1:A._fit_data(fit).n])

# Independent unit-logit equation: no production probability/1.7 transport helper.
function fixed_reference(reference, raw)
    spec, blocks = reference.design.spec, reference.blueprint.blocks
    data, q = spec.data, spec.q_matrix
    D, K, R, I = spec.dimensions, length(data.category_levels), length(data.rater_levels), length(data.item_levels)
    theta = reshape(raw[blocks[:person]], D, :)
    severity = [raw[blocks[:rater_free]]; -sum(raw[blocks[:rater_free]])]
    free_steps = reshape(raw[blocks[:item_steps]], K-2, I)
    out = zeros(data.n, K)
    for n in 1:data.n
        p, i, r = data.person[n], data.item[n], data.rater[n]
        location = sum(theta[:,p] .* q[i,:])-raw[blocks[:item][i]]-severity[r]
        steps = [free_steps[:,i]; -sum(free_steps[:,i])]
        eta = [0.; cumsum(location .- steps)]
        e = exp.(eta .- maximum(eta))
        out[n,:] = e ./ sum(e)
    end
    return out
end

@testset "Fixed-coefficient records, native likelihood and independent unit-logit equation" begin
    for kind in (:legacy, :independent, :correlated, :exchangeable, :exchangeable_correlated),
            backend in (:advancedhmc, :cmdstan), K in (2,4)
        f = prediction_fixed_fixture(kind; backend, K)
        fit, reference = f.fit, f.reference
        before = bytes(fit)
        selected = [40,1,13,1]
        result = prediction_observations(fit; options(fit)..., draw_indices=selected)
        @test result.model.family === :mfrm
        @test result.model.likelihood_scale == 1.
        @test result.model.target_contract.loading_policy === :fixed_q_coefficients
        @test result.model.latent_correlation === (kind in (:correlated, :exchangeable_correlated) ? :free_2d : :identity_fixed)
        @test result.model.native_metadata.source_sample_schema == fit.record.schema
        @test result.n_retained_draws == 40 && result.chain_ids == [2,1,1,1] && result.iterations == [20,1,13,1]
        for (s, source) in enumerate(selected)
            raw = fit.record.run.draws[source,1:B.LogDensityProblems.dimension(reference)]
            @test result.probabilities[s,:,:] ≈ fixed_reference(reference,raw) atol=2e-14
            @test result.pointwise_loglikelihood[s,:] ≈ B._mfrm_fixed_q_pointwise(reference,raw) atol=2e-12
        end
        @test bytes(fit) == before
        mktempdir() do dir
            path=joinpath(dir,"fit.jls")
            if kind === :legacy
                serialize(path,fit.record)
                restored=B.MultidimensionalMFRMFit(deserialize(path); expected_identity=fit.record.target_identity)
            else
                save_fit_cache(path,fit)
                restored=load_fit_cache(path)
            end
            @test isequal(result, prediction_observations(restored; options(fit)..., draw_indices=selected))
        end
        allrows = prediction_observations(fit; options(fit)..., include_probabilities=false)
        stat = prediction_criteria(allrows; criteria=(:waic,:raw_loo,:hill_smoothed_loo))
        @test stat.prediction === allrows
        @test isequal(stat.scores.waic,waic(allrows.pointwise_loglikelihood))
        @test isequal(stat.scores.raw_loo,loo(allrows.pointwise_loglikelihood))
        @test isequal(stat.scores.hill_smoothed_loo,psis_loo(allrows.pointwise_loglikelihood))
        @test stat.sampling_warning
        @test stat.reference_psis_validation === :not_established
        @test_throws ArgumentError prediction_criteria(result)
    end
    for (kind,D,mixed) in ((:independent,3,false), (:exchangeable,2,true))
        f = prediction_fixed_fixture(kind; D,mixed)
        p = prediction_observations(f.fit; options(f.fit)...)
        @test p.model.dimensions == D
        @test p.probabilities[1,:,:] ≈ fixed_reference(f.reference,f.fit.record.run.draws[1,:]) atol=2e-14
    end
end

@testset "All fit families share criterion semantics and preserve warnings" begin
    r=F.synthetic_record(F.target())
    fits=Any[reporting_fit(f; chains=2, ndraws=20, warmup=0) for f in (:mfrm,:gmfrm,:mgmfrm)]
    append!(fits,[B.Experimental.CorrelatedMGMFRMFit(r; expected_identity=r.target_identity), normalized_fixture(r)])
    for fit in fits
        result=prediction_criteria(fit; options(fit)..., criteria=(:waic,:raw_loo,:hill_smoothed_loo))
        L=result.prediction.pointwise_loglikelihood
        @test result.prediction.probabilities === nothing
        @test isequal(result.scores.waic,waic(L))
        @test isequal(result.scores.raw_loo,loo(L))
        @test isequal(result.scores.hill_smoothed_loo,psis_loo(L))
        @test result.sampling_warning && result.scientific_acceptance === :not_established
        @test result.uncertainty.mcmc_mcse === :not_computed
        @test result.uncertainty.importance_ess === :weight_only_not_mcmc_adjusted
        @test result.loo_target === :single_rating_omission_fixed_specification
    end
    base=prediction_observations(first(fits); options(first(fits))...)
    L=fill(log(.2),40,length(base.observation_ids))
    # Independent constant-likelihood oracle: all predictive densities are .2.
    constant=prediction_criteria(merge(base,(;pointwise_loglikelihood=L)); criteria=(:waic,:raw_loo,:hill_smoothed_loo))
    @test constant.scores.waic.p_waic ≈ 0 atol=1e-12
    @test constant.scores.waic.elpd_waic ≈ size(L,2)*log(.2)
    @test constant.scores.raw_loo.elpd_loo ≈ size(L,2)*log(.2)
    @test constant.scores.hill_smoothed_loo.elpd_loo ≈ size(L,2)*log(.2)
    L[end,1]=-100.
    unstable=prediction_criteria(merge(base,(;pointwise_loglikelihood=L)); criteria=(:waic,:raw_loo,:hill_smoothed_loo))
    @test unstable.criterion_warnings.waic === :high_loglik_variance
    @test unstable.criterion_warnings.raw_loo === :high_pareto_k
    @test unstable.criterion_warnings.hill_smoothed_loo === :high_pareto_k
    @test all(v == [first(base.observation_ids)] for v in values(unstable.problem_observation_ids))
    @test size(unstable.prediction.pointwise_loglikelihood) == size(L)
    for bad in ((), (:waic,:waic), (:loo,), (:psis_loo,), (:unknown,))
        @test_throws ArgumentError prediction_criteria(base;criteria=bad)
    end
    @test_throws ArgumentError prediction_criteria(base; pareto_k_threshold=-1)
    for delta in ((;draw_indices=reverse(base.draw_indices)), (;n_retained_draws=41),
                  (;chain_ids=ones(Int,40)), (;iterations=reverse(base.iterations)),
                  (;weighting=:equal_person), (;prediction_target=:heldout))
        @test_throws ArgumentError prediction_criteria(merge(base,delta))
    end
    @test_throws ArgumentError prediction_criteria(Base.structdiff(base,(;n_retained_draws=nothing)))
    @test_throws MethodError prediction_criteria(first(fits); options(first(fits))..., ndraws=20)
end
end
