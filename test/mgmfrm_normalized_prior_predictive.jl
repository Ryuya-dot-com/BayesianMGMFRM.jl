module MGMFRMNormalizedPriorPredictiveChecks
using Test, BayesianMGMFRM, Random, LinearAlgebra, ForwardDiff, Serialization
const B = BayesianMGMFRM
const SCALES = (; person_sd=.8, rater_sd=.6, item_sd=.9,
    log_discrimination_sd=.3, log_consistency_sd=.4, step_sd=.7)

function specification(R=3, K=4; mixed=false, offset=0)
    q = mixed ? Bool[1 0 0; 1 1 0; 0 1 0; 0 0 1] : Bool[1 0; 1 0; 0 1; 0 1]
    cells = [(p, i, r) for p in 1:2 for i in 1:4 for r in 1:R]
    data = FacetData((; person=first.(cells), item=getindex.(cells, 2),
        rater=[Symbol("judge_$r") for (_, _, r) in cells],
        score=[mod(p+2i+r+offset, K) for (p, i, r) in cells]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=0:(K-1))
    return mfrm_spec(data; family=:mgmfrm, dimensions=size(q, 2),
        thresholds=:partial_credit, q_matrix=q)
end

target(spec, model, q=1) = B._MGMFRMNormalizedPriorLogDensity(spec;
    prior_model=model, scales=SCALES,
    source_rater=model === :source ? spec.data.rater_levels[q] : nothing)

# Drive the actual generator with zero and basis innovations: its mean and
# full linear map are checked exactly, without noisy Monte Carlo tolerances.
mutable struct BasisNormals <: AbstractRNG
    values::Vector{Float64}
    position::Int
end
function Random.randn(rng::BasisNormals)
    value = rng.values[rng.position]
    rng.position += 1
    return value
end

@testset "Normalized generator has the production Gaussian law" begin
    for (R, K, mixed) in ((1, 2, false), (2, 4, false), (3, 3, false), (5, 4, true))
        spec = specification(R, K; mixed)
        for (model, q) in ((:exchangeable, 1), (:source, 1), (:source, R))
            t = target(spec, model, q)
            p = B.LogDensityProblems.dimension(t)
            innovations = vcat(zeros(1, p), Matrix{Float64}(I, p, p))
            rng = BasisNormals(vec(permutedims(innovations)), 1)
            draws = B._guarded_generalized_prior_draws(t, p+1, rng)
            @test rng.position == (p+1)*p+1
            mu = vec(draws[1, :])
            A = permutedims(draws[2:end, :] .- permutedims(mu))
            covariance = inv(-ForwardDiff.hessian(x -> B.logprior(t, x), zeros(p)))
            @test A*A' ≈ covariance atol=1e-12
            @test mu ≈ covariance*ForwardDiff.gradient(x -> B.logprior(t, x), zeros(p)) atol=1e-12
            metadata = B._mgmfrm_normalized_prior_metadata(t)
            @test metadata.prior == B._mgmfrm_normalized_prior_record(t)
            @test metadata.model_family === :mgmfrm
            @test metadata.loading_policy === :estimated_positive_fixed_q
            @test metadata.latent_correlation === :identity_fixed
            @test metadata.likelihood_scale == 1.7
            @test metadata.q_matrix == spec.q_matrix
            @test !metadata.public_fit && metadata.scientific_acceptance === :not_established
            for (block, reported) in ((:rater_free, metadata.blocks.severity),
                    (:log_rater_consistency_free, metadata.blocks.log_consistency))
                indices = t.base.blueprint.blocks[block]
                C = vcat(Matrix{Float64}(I, R-1, R-1), -ones(1, R-1))
                full_covariance = C*covariance[indices, indices]*C'
                @test C*mu[indices] ≈ reported.mean atol=1e-12
                @test sqrt.(diag(full_covariance)) ≈ fill(reported.marginal_sd, R) atol=1e-12
                @test reported.scale_active == (R > 1)
                @test ismissing(reported.contrast_sd) == (R == 1)
                for r in 1:(R-1), s in (r+1):R
                    @test sqrt(full_covariance[r, r]+full_covariance[s, s]-2full_covariance[r, s]) ≈ reported.contrast_sd
                end
            end
            @test metadata.blocks.item_steps.free_dimension == K-2
            @test metadata.blocks.item_steps.scale_active == (K > 2)
            @test ismissing(metadata.blocks.item_steps.contrast_sd) == (K == 2)
            @test metadata.blocks.item_steps.marginal_sd ≈ SCALES.step_sd*sqrt((K-2)/(K-1))
            @test metadata.blocks.person.sd == SCALES.person_sd
            @test metadata.blocks.item.sd == SCALES.item_sd
            @test metadata.blocks.log_loading.sd == SCALES.log_discrimination_sd

            # Non-normalized blocks and the RNG stream retain their meanings.
            a, b = MersenneTwister(143), MersenneTwister(143)
            current = B._guarded_generalized_prior_draws(t, 9, a)
            raw = B._guarded_generalized_prior_draws(t.base, 9, b)
            for block in (:person, :item, :log_item_dimension_discrimination)
                @test current[:, t.base.blueprint.blocks[block]] == raw[:, t.base.blueprint.blocks[block]]
            end
            @test rand(a) == rand(b)
        end
    end
end

@testset "Prediction, labels and invalid-input boundaries" begin
    for (R, K, mixed) in ((1, 2, false), (2, 4, false), (5, 4, true)), model in (:exchangeable, :source)
        spec = specification(R, K; mixed)
        t = target(spec, model, R)
        before = deepcopy(B._mgmfrm_normalized_prior_metadata(t))
        rng = MersenneTwister(233)
        check = B._mgmfrm_normalized_prior_predictive_check(t; ndraws=13, rng)
        @test check.prior == before.prior
        @test isequal(check.prior_metadata, before)
        @test check.target_identity == before.target_identity
        @test check.schema == "bayesianmgmfrm.normalized_mgmfrm_prior_predictive_check.v1"
        @test check.parameter_space === :raw_unconstrained_coordinates
        @test !hasproperty(check.prior, :jacobian_policy)
        @test check.prior.prior_model === model
        @test size(check.replicated_scores) == (13, spec.data.n)
        @test all(in(spec.data.category_levels), check.replicated_scores)
        @test !isempty(predictive_check_summary(check; include_grouped=true))
        plot_data = B._prior_predictive_plot_data(check)
        @test startswith(B._prior_predictive_caption(plot_data), before.prior_label)
        @test occursin("kernel SDs", before.prior_label)
        @test isequal(before, B._mgmfrm_normalized_prior_metadata(t))
        # Scores compare with the prior; changing scores must not train it.
        changed = target(specification(R, K; mixed, offset=1), model, R)
        other = B._mgmfrm_normalized_prior_predictive_check(changed; ndraws=13, rng=MersenneTwister(233))
        @test other.raw_parameter_draws == check.raw_parameter_draws
        @test other.replicated_scores == check.replicated_scores
        @test other.target_identity != check.target_identity
        # Independently evaluate the category equation for every generated row.
        blocks = t.base.blueprint.blocks
        for (j, x) in enumerate(eachrow(check.raw_parameter_draws))
            theta = reshape(x[blocks[:person]], spec.dimensions, :)
            severity = vcat(x[blocks[:rater_free]], -sum(x[blocks[:rater_free]]))
            gamma = exp.(vcat(x[blocks[:log_rater_consistency_free]], -sum(x[blocks[:log_rater_consistency_free]])))
            loads = exp.(x[blocks[:log_item_dimension_discrimination]])
            active = [(i, d) for i in 1:4 for d in 1:spec.dimensions if spec.q_matrix[i, d]]
            direct = check.direct_parameter_draws[j:j, :]
            production = B._mgmfrm_predictive_probabilities_direct(t.base.design, direct)[1, :, :]
            for n in 1:spec.data.n
                p, i, r = spec.data.person[n], spec.data.item[n], spec.data.rater[n]
                eta = sum(loads[l]*theta[d, p] for (l, (ii, d)) in enumerate(active) if ii == i)-x[blocks[:item][i]]-severity[r]
                free = x[blocks[:item_steps][((i-1)*(K-2)+1):(i*(K-2))]]
                steps = vcat(free, -sum(free))
                logits = vcat(0., cumsum(1.7*gamma[r].*(eta.-steps)))
                probabilities = exp.(logits.-maximum(logits)); probabilities ./= sum(probabilities)
                @test production[n, :] ≈ probabilities atol=1e-12
            end
        end
    end
    t = target(specification(), :exchangeable)
    Random.seed!(875); expected = rand(); Random.seed!(875)
    B._mgmfrm_normalized_prior_predictive_check(t; ndraws=3, rng=MersenneTwister(63))
    @test rand() == expected
    for override in ((;ndraws=0), (;min_category_probability=-1.), (;prior_warning_probability=2.))
        rng = MersenneTwister(83); expected = rand(copy(rng))
        @test_throws ArgumentError B._mgmfrm_normalized_prior_predictive_check(t; rng, override...)
        @test rand(rng) == expected
    end
    spec = t.base.design.spec
    @test_throws ArgumentError B.Experimental.prior_predictive_check(spec; prior=t)
    @test_throws ArgumentError B._guarded_mgmfrm_prior(t)
    @test_throws ArgumentError B.Experimental.prior_predictive_check(spec;
        prior=B.Experimental.ExchangeablePrior(;rater_kernel_sd=.5))
end

# A serialization fixture, NOT posterior draws or evidence about NUTS. Construct
# both existing record versions without invoking either sampler or compiler.
function saved_record_fixture(t, version)
    initial = initial_params(t)
    nparams = length(initial)
    controls = (; ndraws=4, chains=2, warmup=0, step_size=.1, target_accept=.8,
        max_depth=4, max_energy_error=1000., init_jitter=0., ad_backend=:ForwardDiff,
        gradient_backend=B._gradient_backend_kind(:ForwardDiff), metric=:diagonal)
    draws = [.01sin(i+j) for i in 1:8, j in 1:nparams]
    logdensities = [B.LogDensityProblems.logdensity(t, row) for row in eachrow(draws)]
    chain_ids, iterations = repeat(1:2; inner=4), repeat(1:4, 2)
    stats = NamedTuple[B._advancedhmc_stat_row((;log_density=logdensities[i], step_size=.1,
        acceptance_rate=.75, hamiltonian_energy=Float64(i)), chain_ids[i], iterations[i]) for i in 1:8]
    chain_acceptance = fill(.75, 2)
    run = (; checked=B._check_diagnostic_thresholds(1.01, 400), nparams, initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t, initial), total_draws=8, draws,
        logdensities, chain_ids, iterations, chain_acceptance, sampler_stats=stats, controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities, iterations,
            chain_acceptance, stats, controls, :advancedhmc), backend=:advancedhmc, sampler=:nuts,
        split_chains_requested=true, actual_split=true)
    version == 2 && (run=merge(run, (;warmup_stats=NamedTuple[])))
    record = (; schema="bayesianmgmfrm.normalized_fixed_q_samples.v$version",
        spec=deepcopy(t.base.design.spec), prior=B._mgmfrm_normalized_prior_record(t),
        target_identity=B._mgmfrm_normalized_prior_identity(t), run)
    return merge(record, (;content_hash=B._mgmfrm_normalized_sample_hash(record)))
end

@testset "Saved versions derive the same prior explanation after reload" begin
    for model in (:exchangeable, :source), version in (1, 2)
        t = target(specification(), model, 3)
        check = B._mgmfrm_normalized_prior_predictive_check(t; ndraws=2, rng=MersenneTwister(24))
        record = saved_record_fixture(t, version)
        restored = B._restore_mgmfrm_normalized_prior_samples(record; expected_identity=record.target_identity)
        @test restored.prior_metadata == check.prior_metadata
        @test !hasproperty(record, :prior_metadata)
        @test isequal(restored.record, record)
        mktempdir() do dir
            oldpath = joinpath(dir, "old-record.jls")
            serialize(oldpath, record)
            loaded = B._load_mgmfrm_normalized_prior_samples(oldpath; expected_identity=record.target_identity)
            @test loaded.prior_metadata == check.prior_metadata
            path = joinpath(dir, "saved.jls")
            B._save_mgmfrm_normalized_prior_samples(path, restored)
            # FacetSpec owns mutable data, so object equality across deserialize
            # is not content equality. Compare the existing serialized format.
            @test read(path) == read(oldpath)
            @test_throws ArgumentError B._save_mgmfrm_normalized_prior_samples(path, restored)
            @test_throws ArgumentError B._load_mgmfrm_normalized_prior_samples(path; expected_identity="wrong")
            @test_throws ArgumentError load_fit_cache(path)
            bad = merge(record, (; prior=merge(record.prior, (;scale_convention=:marginal_sd))))
            bad = merge(bad, (;content_hash=B._mgmfrm_normalized_sample_hash(bad)))
            @test_throws ArgumentError B._restore_mgmfrm_normalized_prior_samples(bad; expected_identity=record.target_identity)
        end
    end
end
end
