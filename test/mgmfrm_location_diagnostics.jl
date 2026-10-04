module MGMFRMLocationChecks

using Test, Random, Statistics, BayesianMGMFRM
const B = BayesianMGMFRM

function specification(q)
    cells = [(p, i, r) for p in 1:3 for i in axes(q, 1) for r in 1:2]
    data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
        rater = last.(cells), score = [mod(sum(c), 3) for c in cells]);
        person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:2)
    return mfrm_spec(data; family = :mgmfrm, dimensions = size(q, 2),
        thresholds = :partial_credit, q_matrix = q,
        dimension_labels = ["Ability $d" for d in axes(q, 2)])
end

@testset "Loading-weighted locations preserve the response model" begin
    for q in (Bool[1 0; 1 0; 0 1; 0 1], Bool[1 0 0; 0 1 0; 0 0 1; 1 1 0; 1 1 1])
        spec = specification(q)
        target = B._mgmfrm_guarded_local_fit_logdensity(spec)
        design, bp = target.design, target.blueprint
        D = spec.dimensions
        raw = .2randn(MersenneTwister(214), 20, bp.n_parameters)
        direct = reduce(vcat, [permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(
            design, collect(row), bp)) for row in eachrow(raw)])
        coordinates = B._mgmfrm_location_coordinates(design, direct)
        @test length(coordinates) == D + 3size(q, 1)
        @test length(unique(r.parameter for r in coordinates)) == length(coordinates)
        @test [r.dimension_label for r in coordinates[1:D]] == spec.dimension_labels
        for i in axes(q, 1)
            # Independent item/person enumeration of the weighted population in
            # the linear predictor, before subtracting item/rater locations.
            weighted = zeros(size(raw, 1))
            active = [(j, d) for j in axes(q, 1) for d in axes(q, 2) if q[j, d]]
            for s in axes(raw, 1), p in 1:3, d in findall(q[i, :])
                a = exp(raw[s, bp.blocks[:log_item_dimension_discrimination][findfirst(==((i, d)), active)]])
                theta = raw[s, bp.blocks[:person][(p - 1) * D + d]]
                weighted[s] += a * theta / 3
            end
            rows = coordinates[D + 3(i - 1) + 1:D + 3i]
            @test rows[2].values ≈ weighted
            @test rows[3].values ≈ raw[:, bp.blocks[:item][i]] - weighted
            @test rows[3].dimension === (sum(q[i, :]) == 1 ? findfirst(q[i, :]) : nothing)
        end
        delta = collect(1:D) .* .3
        shifted = copy(raw)
        loading_indices = B._mgmfrm_source_loading_index_matrix(design)
        for p in 1:3, d in 1:D
            shifted[:, bp.blocks[:person][(p - 1) * D + d]] .+= delta[d]
        end
        for i in axes(q, 1), d in findall(q[i, :])
            shifted[:, bp.blocks[:item][i]] .+= direct[:, loading_indices[i, d]] .* delta[d]
        end
        shifted_direct = reduce(vcat, [permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(
            design, collect(row), bp)) for row in eachrow(shifted)])
        shifted_coordinates = B._mgmfrm_location_coordinates(design, shifted_direct)
        @test B._mgmfrm_predictive_probabilities_direct(design, direct) ≈
            B._mgmfrm_predictive_probabilities_direct(design, shifted_direct) atol = 1e-12
        for (a, b) in zip(coordinates, shifted_coordinates)
            a.block === :item_minus_loading_weighted_person_mean || continue
            @test a.values ≈ b.values atol = 1e-12
        end
        @test B._source_fixture_logprior(target, raw[1, :]) !=
            B._source_fixture_logprior(target, shifted[1, :])
        @test_throws ArgumentError B._mgmfrm_location_coordinates(design, direct[1:0, :])
        bad = copy(direct); bad[1, 1] = NaN
        @test_throws ArgumentError B._mgmfrm_location_coordinates(design, bad)
    end
end

@testset "Optional MGMFRM locations retain warnings and survive cache reload" begin
    fit = B.Experimental.fit(specification(Bool[1 0; 1 0; 0 1; 0 1]);
        ndraws = 12, warmup = 10, chains = 2, seed = 92123, max_depth = 3)
    baseline = diagnostics(fit)
    @test !hasproperty(baseline, :location_rows)
    extended = diagnostics(fit; include_location = true)
    @test extended.location_status === :computed
    @test length(extended.location_rows) == 14
    @test extended.summary == baseline.summary
    @test extended.parameter_rows == baseline.parameter_rows
    @test extended.sampler_rows == baseline.sampler_rows
    @test isequal(diagnostics(fit), baseline)
    @test all(r -> r.derived && !r.fixed, extended.location_rows)
    @test diagnostics(fit; view = :public, include_location = true).location_status === :computed
    @test_throws ArgumentError diagnostics(fit; include_location = true, rhat_threshold = 1.02)
    mktempdir() do directory
        path = joinpath(directory, "fit.jls")
        save_fit_cache(path, fit)
        restored = load_fit_cache(path)
        @test isequal(diagnostics(restored; include_location = true), extended)
        restored.direct_draws[1, first(restored.design.blocks[:item])] += .1
        @test_throws ArgumentError diagnostics(restored; include_location = true)
    end
    damaged = deepcopy(fit)
    reverse!(damaged.chain_ids)
    @test_throws ArgumentError diagnostics(damaged; include_location = true)
    empty!(extended.location_rows)
    @test length(diagnostics(fit; include_location = true).location_rows) == 14
end

end
