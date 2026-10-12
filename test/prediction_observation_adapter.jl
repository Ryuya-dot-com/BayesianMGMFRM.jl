module PredictionObservationAdapterChecks
using Test, BayesianMGMFRM, Random, Serialization, SHA
const B = BayesianMGMFRM
include("../scripts/prediction_observation_adapter.jl")
using .PredictionObservationAdapter
include("fixtures/reporting_fit.jl")
include("mgmfrm_correlated_2d_fixtures.jl")
const F = MGMFRMCorrelated2DFixtures

# Synthetic draws only; rebuild their normalized-target densities and records.
function normalized_fixture(record; model=:exchangeable)
    scales = record.prior.scales
    t = B._MGMFRMNormalizedPriorLogDensity(record.spec; prior_model=model, scales,
        source_rater=model === :source ? last(record.spec.data.rater_levels) : nothing)
    old = record.run
    draws = old.draws[:, 1:end-1]
    initial = initial_params(t)
    logdensities = [B.LogDensityProblems.logdensity(t, row) for row in eachrow(draws)]
    stats = NamedTuple[merge(s, (; log_density=lp),
        old.backend === :cmdstan ? (; stan_lp=lp) : (;)) for (s, lp) in zip(old.sampler_stats, logdensities)]
    run = merge(old, (; draws, nparams=length(initial), initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t, initial), logdensities,
        sampler_stats=stats, sampler_rows=B._generalized_candidate_sampler_rows(logdensities,
            old.iterations, old.chain_acceptance, stats, old.controls, old.backend)))
    r = (; schema="bayesianmgmfrm.normalized_fixed_q_samples.v2", spec=deepcopy(record.spec),
        prior=B._mgmfrm_normalized_prior_record(t), target_identity=B._mgmfrm_normalized_prior_identity(t), run)
    r = merge(r, (; content_hash=B._mgmfrm_normalized_sample_hash(r)))
    return B.Experimental.NormalizedMGMFRMFit(r; expected_identity=r.target_identity)
end

ids(fit) = ["outcome-$n" for n in 1:(fit isa B._ModelComparisonFit ?
    fit.design.spec.data.n : fit.record.spec.data.n)]
extract(fit; kwargs...) = prediction_observations(fit; dataset_id="synthetic-rating-panel",
    observation_ids=ids(fit), kwargs...)
bytes(x) = (io=IOBuffer(); serialize(io, x); take!(io))

@testset "Five fit types, native agreement, draw identity and cache replay" begin
    @info "Building deterministic prediction fixtures; no sampler runs"
    fits = Any[reporting_fit(f; chains=2, ndraws=20, warmup=0) for f in (:mfrm, :gmfrm, :mgmfrm)]
    for backend in (:advancedhmc, :cmdstan), K in (2, 4)
        t = F.target(; K, raters=K == 2 ? 1 : 3)
        r = F.synthetic_record(t; backend)
        push!(fits, B.Experimental.CorrelatedMGMFRMFit(r; expected_identity=r.target_identity))
        push!(fits, normalized_fixture(r))
        push!(fits, normalized_fixture(r; model=:source))
    end
    for fit in fits
        @info "Checking extraction and cache replay" fit_type=typeof(fit)
        before = bytes(fit)
        selection = [40, 1, 13, 1]
        bundle = extract(fit; draw_indices=selection)
        @test bundle.draw_indices == selection
        @test bundle.chain_ids == [2, 1, 1, 1]
        @test bundle.iterations == [20, 1, 13, 1]
        @test bundle.probabilities ≈ predictive_probabilities(fit; draw_indices=selection) atol=2e-14
        @test all(isapprox.(sum(bundle.probabilities; dims=3), 1.; atol=2e-14))
        if fit isa B._ModelComparisonFit
            native = pointwise_loglikelihood_matrix(fit)[selection, :]
            @test bundle.model.likelihood_scale == Dict(:mfrm=>1.0, :gmfrm=>1.0, :mgmfrm=>1.7)[fit.design.spec.family]
        else
            checked = B._recorded_mgmfrm_samples(fit)
            native = checked.diagnostics.direct_values.pointwise_loglikelihood[selection, :]
            @test bundle.source_sample_hash == fit.record.content_hash
            @test bundle.sampling_quality.flag == checked.diagnostics.flag
        end
        @test bundle.pointwise_loglikelihood ≈ native atol=2e-12
        @test vec(sum(bundle.pointwise_loglikelihood; dims=2)) ≈ vec(sum(native; dims=2)) atol=2e-12
        data = fit isa B._ModelComparisonFit ? fit.design.spec.data : fit.record.spec.data
        for n in 1:data.n
            @test log.(bundle.probabilities[:, n, data.category[n]]) ≈ bundle.pointwise_loglikelihood[:, n]
        end
        likelihood_only = extract(fit; draw_indices=selection, include_probabilities=false)
        @test likelihood_only.probabilities === nothing
        @test likelihood_only.pointwise_loglikelihood == bundle.pointwise_loglikelihood
        @test observation_alignment(bundle, likelihood_only) == collect(1:data.n)
        @test bytes(fit) == before
        @test isequal(extract(fit; ndraws=5, rng=MersenneTwister(19)),
                      extract(fit; ndraws=5, rng=MersenneTwister(19)))
        mktempdir() do dir
            path = joinpath(dir, "fit.jls")
            save_fit_cache(path, fit)
            restored = load_fit_cache(path)
            @test isequal(extract(restored; draw_indices=selection), bundle)
        end
    end
    a, b = extract(fits[1]), extract(fits[3])
    @test a.model.dimensions != b.model.dimensions
    @test observation_alignment(a, b) == collect(1:length(a.observation_ids))
    corrupt = deepcopy(last(fits))
    corrupt.record.run.draws[1, 1] += 1
    @test_throws ArgumentError extract(corrupt)
end

@testset "Source IDs, row alignment and invalid comparisons" begin
    rows = (; person=[1,1,1,2,2,2], item=[1,1,2,1,2,2], rater=[1,2,1,1,2,1],
        score=[0,1,2,1,0,2], response=["A","A","A","B","B","B"])
    data(table) = FacetData(table; person=:person, item=:item, rater=:rater, score=:score,
        response_id=:response, category_levels=0:2)
    fit = reporting_fit(:mfrm; data=data(rows), chains=2, ndraws=20, warmup=0, amplitude=0.)
    a = extract(fit)
    perm = [6,2,4,1,5,3]
    changed = reporting_fit(:mfrm; data=data(map(x -> x[perm], rows)), chains=2,
        ndraws=20, warmup=0, amplitude=0.)
    b = prediction_observations(changed; dataset_id=a.dataset_id, observation_ids=ids(fit)[perm])
    order = observation_alignment(a, b)
    @test b.observation_ids[order] == a.observation_ids
    @test b.probabilities[:, order, :] == a.probabilities
    @test b.pointwise_loglikelihood[:, order] == a.pointwise_loglikelihood
    @test a.training_binding == b.training_binding
    @test_throws ArgumentError prediction_observations(fit; dataset_id=" ", observation_ids=ids(fit))
    for bad in (fill("same-response", 6), ["one"], ["", ids(fit)[2:end]...], collect(1:6))
        @test_throws ArgumentError prediction_observations(fit; dataset_id=a.dataset_id, observation_ids=bad)
    end
    @test_throws ArgumentError extract(fit; draw_indices=[1], ndraws=1)
    @test_throws ArgumentError extract(fit; draw_indices=[41])
    @test_throws ArgumentError extract(fit; draw_indices=Int[])
    for delta in ((; dataset_id="other"), (; category_levels=[1,2,3]),
                  (; conditioning=:new_person), (; weighting=:equal_person),
                  (; training_binding="other"), (; prediction_target=:heldout))
        @test_throws ArgumentError observation_alignment(a, merge(b, delta))
    end
    wrong = reporting_fit(:mfrm; data=data(merge(rows, (; score=[1,1,2,1,0,2]))),
        chains=2, ndraws=20, warmup=0)
    @test_throws ArgumentError observation_alignment(a, extract(wrong))
    @test_throws MethodError prediction_observations(fit; dataset_id=a.dataset_id,
        observation_ids=ids(fit), newdata=data(rows))
end

@testset "Underflowed category probability retains finite log likelihood" begin
    fit = reporting_fit(:mfrm; amplitude=1000., chains=2, ndraws=20, warmup=0)
    b = extract(fit)
    @test any(iszero, b.probabilities)
    @test all(isfinite, b.pointwise_loglikelihood)
    @test minimum(b.pointwise_loglikelihood) < -1000
    @test b.pointwise_loglikelihood ≈ pointwise_loglikelihood_matrix(fit) atol=1e-10
end

if haskey(ENV, "MGMFRM_ADAPTER_REPLAY")
    @testset "Read-only replay of a saved normalized posterior" begin
        path = ENV["MGMFRM_ADAPTER_REPLAY"]
        before = bytes2hex(sha256(read(path)))
        record = deserialize(path)
        fit = B.Experimental.NormalizedMGMFRMFit(record; expected_identity=record.target_identity)
        data = record.spec.data
        outcome_ids = ["$(data.person[n])/$(data.item[n])/$(data.rater[n])" for n in 1:data.n]
        selection = [size(record.run.draws, 1), 1, 13, 1]
        actual = prediction_observations(fit; dataset_id=record.target_identity,
            observation_ids=outcome_ids, draw_indices=selection)
        expected = B._recorded_mgmfrm_samples(fit).diagnostics.direct_values.pointwise_loglikelihood
        @test actual.pointwise_loglikelihood ≈ expected[selection, :] atol=2e-12
        @test actual.probabilities ≈ predictive_probabilities(fit; draw_indices=selection) atol=2e-14
        @test actual.chain_ids == record.run.chain_ids[selection]
        @test actual.source_sample_hash == record.content_hash
        @test bytes2hex(sha256(read(path))) == before
        @info "Saved posterior replayed without fitting or rewriting" source_sha256=before observations=data.n
    end
end
end
