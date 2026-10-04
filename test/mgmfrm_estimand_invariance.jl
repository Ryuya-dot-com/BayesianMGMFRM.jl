module MGMFRMEstimandInvarianceChecks

using Test, Statistics, BayesianMGMFRM
const B = BayesianMGMFRM

# Deterministic model coordinates, not simulated ratings or posterior draws.
function fixture(q, K)
    cells = [(p, i, r) for p in 1:3 for i in axes(q, 1) for r in 1:3]
    data = FacetData((; person = first.(cells), item = getindex.(cells, 2),
        rater = last.(cells), score = [mod(sum(c), K) for c in cells]);
        person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:(K - 1))
    spec = mfrm_spec(data; family = :mgmfrm, dimensions = size(q, 2),
        thresholds = :partial_credit, q_matrix = q)
    target = B._mgmfrm_guarded_local_fit_logdensity(spec)
    bp = target.blueprint
    raw = [.17sin(j) for j in 1:bp.n_parameters]
    raw[bp.blocks[:item][1:2]] .= [.2, .1]
    raw[bp.blocks[:log_item_dimension_discrimination][1:2]] .= log.([.8, 1.6])
    return (; target, raw, cells, q, K)
end

function parts(case, raw)
    bp, q, K = case.target.blueprint, case.q, case.K
    D, I = size(q, 2), size(q, 1)
    theta = permutedims(reshape(raw[bp.blocks[:person]], D, 3))
    a = zeros(I, D)
    active = [(i, d) for i in 1:I for d in 1:D if q[i, d]]
    for (j, (i, d)) in enumerate(active)
        a[i, d] = exp(raw[bp.blocks[:log_item_dimension_discrimination][j]])
    end
    free_severity = raw[bp.blocks[:rater_free]]
    free_log_gamma = raw[bp.blocks[:log_rater_consistency_free]]
    free_steps = permutedims(reshape(raw[bp.blocks[:item_steps]], K - 2, I))
    return (; theta, a, b = raw[bp.blocks[:item]],
        severity = vcat(free_severity, -sum(free_severity)),
        gamma = exp.(vcat(free_log_gamma, -sum(free_log_gamma))),
        steps = hcat(free_steps, -sum(free_steps; dims = 2)), active)
end

function transformed(case, raw, t, c)
    bp = case.target.blueprint
    x = parts(case, raw)
    out = copy(raw)
    out[bp.blocks[:person]] = vec(permutedims(x.theta .* t' .+ c'))
    for (j, (_, d)) in enumerate(x.active)
        out[bp.blocks[:log_item_dimension_discrimination][j]] -= log(t[d])
    end
    out[bp.blocks[:item]] += x.a * (c ./ t)
    return out
end

direct(case, raw) = B._mgmfrm_source_constrained_params_from_unconstrained(
    case.target.design, raw, case.target.blueprint)
probabilities(case, raw) = B._mgmfrm_predictive_probabilities_direct(
    case.target.design, permutedims(direct(case, raw)))[1, :, :]

@testset "MGMFRM estimands under location and positive scale changes (no fitting)" begin
    for q in (Bool[1 0; 1 0; 0 1; 0 1],
            Bool[1 0 0; 0 1 0; 0 0 1; 1 1 0; 1 1 1]), K in (2, 3, 4)
        case = fixture(q, K)
        raw, base = case.raw, case.target
        x = parts(case, raw)
        D = size(q, 2)
        prob = probabilities(case, raw)
        @test all(>(0), prob)
        @test vec(sum(prob; dims = 2)) ≈ ones(length(case.cells)) atol = 1e-13
        # Independently evaluate every adjacent log odds, including the last
        # reconstructed step; observed scores do not select the checked category.
        G = zeros(3, size(q, 1), 3, K - 1)
        for (row, (p, i, r)) in enumerate(case.cells), h in 1:(K - 1)
            G[p, i, r, h] = log(prob[row, h + 1] / prob[row, h]) / 1.7
            expected = x.gamma[r] * (sum(x.a[i, :] .* x.theta[p, :]) -
                x.b[i] - x.severity[r] - x.steps[i, h])
            @test G[p, i, r, h] ≈ expected atol = 1e-12
        end
        for (t, c) in ((ones(D), [.6d for d in 1:D]),
                ([.6 + .4d for d in 1:D], zeros(D)),
                ([.7 + .4d for d in 1:D], [.5d for d in 1:D]))
            changed = transformed(case, raw, t, c)
            y = parts(case, changed)
            @test probabilities(case, changed) ≈ prob atol = 1e-12
            @test B._source_fixture_loglikelihood(base, changed) ≈
                B._source_fixture_loglikelihood(base, raw) atol = 1e-11
            @test !isapprox(B._source_fixture_logprior(base, changed),
                B._source_fixture_logprior(base, raw); atol = 1e-10)
            @test y.theta[1, :] - y.theta[2, :] ≈ t .* (x.theta[1, :] - x.theta[2, :])
            @test sign.(y.theta[1, :] - y.theta[2, :]) == sign.(x.theta[1, :] - x.theta[2, :])
            @test (y.theta .- mean(y.theta; dims = 1)) ./ std(y.theta; dims = 1) ≈
                (x.theta .- mean(x.theta; dims = 1)) ./ std(x.theta; dims = 1)
            @test y.severity == x.severity && y.gamma == x.gamma && y.steps == x.steps
            @test y.theta * y.a' .- y.b' ≈ x.theta * x.a' .- x.b'
            before = B._mgmfrm_location_coordinates(base.design, permutedims(direct(case, raw)))
            after = B._mgmfrm_location_coordinates(base.design, permutedims(direct(case, changed)))
            for (left, right) in zip(before, after)
                left.block === :item_minus_loading_weighted_person_mean || continue
                @test left.values ≈ right.values atol = 1e-12
            end
            if all(sum(q; dims = 2) .== 1)
                @test y.a[1, 1] / y.a[2, 1] ≈ x.a[1, 1] / x.a[2, 1]
                @test y.b[1] / y.a[1, 1] - y.b[2] / y.a[2, 1] ≈
                    t[1] * (x.b[1] / x.a[1, 1] - x.b[2] / x.a[2, 1])
            end
        end
        if all(sum(q; dims = 2) .== 1)
            # Reconstruct the uniquely determined blocks from production
            # probabilities, without using the original parameter values.
            delta = G[1, 1, :, 1] - G[2, 1, :, 1]
            gamma = exp.(log.(abs.(delta)) .- mean(log.(abs.(delta))))
            U = G ./ reshape(gamma, 1, 1, 3, 1)
            severity = mean(U) .- vec(mean(U; dims = (1, 2, 4)))
            V = dropdims(mean(U; dims = (3, 4)); dims = (3, 4))
            steps = dropdims(mean(reshape(V, 3, size(q, 1), 1, 1) .- U;
                dims = (1, 3)); dims = (1, 3))
            @test gamma ≈ x.gamma atol = 1e-12
            @test severity ≈ x.severity atol = 1e-12
            @test V ≈ x.theta * x.a' .- x.b' atol = 1e-12
            @test steps ≈ x.steps atol = 1e-12
            for d in 1:D
                items = findall(q[:, d])
                centered = V[:, items] .- mean(V[:, items]; dims = 1)
                # This normalized representation is derived for the check,
                # never imposed on the model prior or saved parameter values.
                theta = centered[:, 1] / std(centered[:, 1])
                a = vec(theta' * centered) / sum(abs2, theta)
                @test a ≈ x.a[items, d] .* std(x.theta[:, d]) atol = 1e-12
                @test theta ≈ (x.theta[:, d] .- mean(x.theta[:, d])) ./ std(x.theta[:, d]) atol = 1e-12
            end
        end
    end
end

@testset "Counterexamples to origin-free difficulty and unconditional identification" begin
    case = fixture(Bool[1 0; 1 0; 0 1; 0 1], 4)
    x = parts(case, case.raw)
    shifted = transformed(case, case.raw, ones(2), [1., 0.])
    y = parts(case, shifted)
    @test x.b[1] - x.b[2] ≈ .1
    @test y.b[1] - y.b[2] ≈ -.7
    @test probabilities(case, shifted) ≈ probabilities(case, case.raw) atol = 1e-12
    # Omitting the loading weight from the shift must change probabilities.
    wrong = copy(case.raw)
    bp = case.target.blueprint
    wrong[bp.blocks[:person]] = shifted[bp.blocks[:person]]
    wrong[bp.blocks[:item][1:2]] .+= 1
    @test maximum(abs, probabilities(case, wrong) - probabilities(case, case.raw)) > .01
    # Without ability variation in D2, change just one D2 loading and offset.
    # Its ratio to the other loading changes with identical probabilities.
    constant = copy(case.raw)
    constant[bp.blocks[:person][2:2:end]] .= .6
    altered = copy(constant)
    altered[bp.blocks[:log_item_dimension_discrimination][3]] += log(2.)
    altered[bp.blocks[:item][3]] += .6 * x.a[3, 2]
    @test probabilities(case, altered) ≈ probabilities(case, constant) atol = 1e-12
    @test parts(case, altered).a[3, 2] / parts(case, altered).a[4, 2] ≈
        2 * x.a[3, 2] / x.a[4, 2]
end

end
