module MGMFRMLocationParameterizationChecks

using Test, Random, LinearAlgebra, Statistics, ForwardDiff, LogDensityProblems, BayesianMGMFRM
const B = BayesianMGMFRM
const L = LogDensityProblems

function specification(persons, q)
    cells = [(p, i, r) for p in 1:persons for i in axes(q, 1) for r in 1:3]
    data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
        rater = last.(cells), score = [mod(sum(c), 3) for c in cells]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:2)
    return mfrm_spec(data; family = :mgmfrm, dimensions = size(q, 2),
        thresholds = :partial_credit, q_matrix = q)
end

@testset "Location coordinates preserve the complete density and gradients" begin
    rng = MersenneTwister(9232026)
    for persons in (1, 2, 5), q in (Bool[1 0; 1 0; 0 1; 0 1],
            Bool[1 0 0; 0 1 0; 0 0 1; 1 1 0; 1 1 1])
        base = B._mgmfrm_guarded_local_fit_logdensity(specification(persons, q);
            prior = B._SourceFixturePrior(person_sd = 1.3, item_sd = .7))
        target = B._MGMFRMLocationLogDensity(base)
        n, D = L.dimension(target), size(q, 2)
        forward(x) = B._mgmfrm_location_to_raw(target, x)
        inverse(x) = B._mgmfrm_location_from_raw(target, x)
        density(x) = L.logdensity(target, x)
        for raw in (zeros(n), .4randn(rng, n), .9randn(rng, n))
            values = inverse(raw)
            @test forward(values) ≈ raw atol = 1e-12
            @test inverse(forward(values)) ≈ values atol = 1e-12
            @test density(values) ≈ L.logdensity(base, raw) atol = 1e-10
            J = ForwardDiff.jacobian(forward, values)
            @test abs(det(J)) ≈ 1 atol = 1e-10
            gradient = ForwardDiff.gradient(density, values)
            @test gradient ≈ J' * ForwardDiff.gradient(x -> L.logdensity(base, x), raw) atol = 1e-9
            h = 1e-5
            finite = [(density(values + h * e) - density(values - h * e)) / (2h)
                for e in eachcol(Matrix{Float64}(I, n, n))]
            @test gradient ≈ finite atol = 2e-6 rtol = 2e-6
            @test sum(abs2, values[base.blueprint.blocks[:person]]) ≈
                sum(abs2, raw[base.blueprint.blocks[:person]]) atol = 1e-12
            direct = B._mgmfrm_source_constrained_params_from_unconstrained(base.design, raw)
            A = zeros(size(q))
            offset = 0
            for i in axes(q, 1), d in 1:D
                q[i, d] || continue
                offset += 1
                A[i, d] = direct[base.design.blocks[:item_dimension_discrimination][offset]]
            end
            means = [mean(raw[base.blueprint.blocks[:person][d:D:end]]) for d in 1:D]
            @test values[base.blueprint.blocks[:person][1:D]] ≈ sqrt(persons) .* means atol = 1e-12
            @test values[base.blueprint.blocks[:item]] ≈ raw[base.blueprint.blocks[:item]] - A * means atol = 1e-12
            if !all(iszero, raw)
                # Independent normals on the new item offsets would CHANGE the prior.
                @test !isapprox(B._source_fixture_logprior(base, values),
                    B._source_fixture_logprior(base, raw); atol = 1e-8)
            end
        end
        @test_throws ArgumentError forward(zeros(n - 1))
        invalid = zeros(n); invalid[1] = Inf
        @test_throws ArgumentError inverse(invalid)
        @test all(iszero, B.initial_params(target))
    end
end

@testset "Location sampling restores canonical fit and cache semantics" begin
    spec = specification(3, Bool[1 0; 1 0; 0 1; 0 1])
    base = B._mgmfrm_guarded_local_fit_logdensity(spec)
    initial = .05randn(MersenneTwister(41), L.dimension(base))
    fit = B._fit_mgmfrm_location(spec; init = initial, ndraws = 16, warmup = 12,
        chains = 2, max_depth = 3, seed = 92311, init_jitter = .1)
    @test fit.sampler_controls.sampling_coordinates === :orthogonal_person_mean_item_offset
    @test fit.sampler_controls.stored_coordinates === :raw_unconstrained
    @test fit.sampler_controls.initialization_coordinates === :raw_unconstrained
    @test fit.diagnostic_surface.initialization_policy.initial_raw_hash == B._cache_hash(initial)
    @test fit.diagnostic_surface.initialization_policy.chain_initialization === :raw_initial_plus_per_chain_jitter
    @test [L.logdensity(base, row) for row in eachrow(fit.draws)] ≈ fit.log_posterior atol = 1e-10
    @test fit.diagnostic_surface.raw_parameter_names == base.blueprint.parameter_names
    @test length(diagnostics(fit; include_location = true).location_rows) == 14
    @test all(r -> r.observed_iterations == 12, B._fit_warmup_diagnostics(fit))
    mktempdir() do directory
        path = joinpath(directory, "fit.jls")
        save_fit_cache(path, fit)
        restored = load_fit_cache(path)
        @test isequal(restored.draws, fit.draws)
        @test isequal(restored.sampler_controls, fit.sampler_controls)
        @test isequal(diagnostics(restored; include_location = true), diagnostics(fit; include_location = true))
    end
end

end
