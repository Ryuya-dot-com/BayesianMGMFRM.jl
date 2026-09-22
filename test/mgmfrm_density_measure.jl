module MGMFRMDensityMeasureChecks

using Test, BayesianMGMFRM, ForwardDiff, ReverseDiff, LinearAlgebra
import JSON3
const B = BayesianMGMFRM
include("test_groups.jl")

# Independent category-score equation; do not use the target's layout, prior,
# transformation or likelihood helpers to construct the expected values.
function reference_case(q; categories = 4)
    J, I, R, K, D = 2, size(q, 1), 3, categories, size(q, 2)
    cells = [(p, i, r) for p in 1:J for i in 1:I for r in 1:R]
    data = FacetData((;
        person = ["P$p" for (p, i, r) in cells],
        item = ["I$i" for (p, i, r) in cells],
        rater = ["R$r" for (p, i, r) in cells],
        score = [mod(p + 2i + r, K) for (p, i, r) in cells],
    ); person = :person, item = :item, rater = :rater, score = :score,
        category_levels = 0:(K - 1))
    prior = B._SourceFixturePrior(1.2, 0.7, 1.1, 0.4, 0.6, 0.9)
    spec = mfrm_spec(data; family = :mgmfrm, dimensions = D,
        thresholds = :partial_credit, q_matrix = q)
    target = B._mgmfrm_guarded_local_fit_logdensity(spec; prior)
    loadings = [(i, d) for i in 1:I for d in 1:D if q[i, d]]
    counts = [J * D, R - 1, I, length(loadings), R - 1, I * (K - 2)]
    ends = cumsum(counts)
    ranges = [(last - count + 1):last for (last, count) in zip(ends, counts)]
    scales = [1.2, 0.7, 1.1, 0.4, 0.6, 0.9]
    sd = vcat([fill(scale, count) for (scale, count) in zip(scales, counts)]...)
    names = (:person, :rater_free, :item, :log_item_dimension_discrimination,
        :log_rater_consistency_free, :item_steps)
    function direct(x)
        person, severity, item, loading, consistency, steps = [x[r] for r in ranges]
        return vcat(person, severity, -sum(severity), item, exp.(loading),
            exp.(consistency), exp(-sum(consistency)), steps)
    end
    function pointwise(x)
        person, severity, item, loading, consistency, steps = [x[r] for r in ranges]
        severity = vcat(severity, -sum(severity))
        consistency = exp.(vcat(consistency, -sum(consistency)))
        return map(cells, data.category) do (p, i, r), category
            ability = sum(exp(loading[l]) * person[(p - 1) * D + d]
                for (l, (item_id, d)) in enumerate(loadings) if item_id == i)
            free = steps[((i - 1) * (K - 2) + 1):(i * (K - 2))]
            step_sums = cumsum(vcat(zero(eltype(x)), free, -sum(free)))
            eta = 1.7 * consistency[r] .* ((0:(K - 1)) .* (ability - item[i] - severity[r]) .- step_sums)
            largest = maximum(eta)
            eta[category] - largest - log(sum(exp.(eta .- largest)))
        end
    end
    logprior(x) = -sum(abs2, x ./ sd) / 2 - sum(log, sd) - length(sd) * log(2pi) / 2
    density(x) = sum(pointwise(x)) + logprior(x)
    mixed = [0.23sin(i) + 0.11cos(2i) for i in eachindex(sd)]
    points = [zeros(length(sd)), mixed,
        ([i in block ? mixed[i] : 0.0 for i in eachindex(sd)] for block in ranges)...]
    return (; target, names, ranges, sd, direct, pointwise, logprior, density, points)
end

const CASES = [reference_case(q) for q in
    (Bool[1 0; 1 0; 0 1; 0 1], Bool[1 0; 1 1; 0 1; 0 1])]

@testset "MGMFRM threshold reuse preserves pointwise density and derivatives" begin
    for categories in (2,3,4,5), q in (Bool[1 0; 1 0; 0 1; 0 1], Bool[1 0; 1 1; 0 1; 0 1])
        case = reference_case(q; categories)
        target = case.target
        fast = x -> B._source_fixture_loglikelihood(target, x)
        # The pointwise path constructs thresholds per observation. Sum in the
        # same order to detect changes hidden by approximate total comparisons.
        pointwise = x -> foldl(+, B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(
            target.design, x); init=zero(eltype(x)))
        for x in (case.points[1], case.points[2], 4 .* case.points[2], case.points[1])
            @test fast(x) == pointwise(x)
            @test ForwardDiff.gradient(fast,x) == ForwardDiff.gradient(pointwise,x)
            @test fast(x) ≈ sum(case.pointwise(x)) atol=1e-11
            @test ForwardDiff.gradient(fast,x) ≈ ForwardDiff.gradient(x -> sum(case.pointwise(x)),x) atol=1e-10
            @test ReverseDiff.gradient(fast,x) ≈ ForwardDiff.gradient(fast,x) atol=1e-10
        end
        @test ForwardDiff.hessian(fast,case.points[2]) ≈
            ForwardDiff.hessian(pointwise,case.points[2]) atol=1e-10
    end
end

# Independent multivariate-normal reference, including its full normalizer.
function centered_reference(v, sd, source_rater = 0)
    m = length(v)
    covariance = sd^2 * (Matrix{Float64}(I, m, m) - ones(m, m) / (m + 1))
    mu = source_rater == 0 ? zeros(m) :
        sd^2 .* (fill(1 / (m + 1), m) - [i == source_rater for i in 1:m])
    return -(dot(v - mu, covariance \ (v - mu)) + m * log(2pi) + logdet(covariance)) / 2
end

function normalized_case(case, model, source_rater, unit_scales)
    sd = unit_scales ? ones(length(case.sd)) : case.sd
    r = case.ranges
    scales = (; person_sd = sd[first(r[1])], rater_sd = sd[first(r[2])],
        item_sd = sd[first(r[3])], log_discrimination_sd = sd[first(r[4])],
        log_consistency_sd = sd[first(r[5])], step_sd = sd[first(r[6])])
    target = B._MGMFRMNormalizedPriorLogDensity(case.target.design.spec;
        prior_model = model, scales, source_rater)
    source_index = source_rater === nothing ? 0 :
        findfirst(isequal(source_rater), case.target.design.spec.data.rater_levels)
    function logprior(x)
        lp = sum(-sum(abs2, x[r[b]] ./ sd[r[b]]) / 2 - sum(log, sd[r[b]]) -
            length(r[b]) * log(2pi) / 2 for b in (1, 3, 4))
        lp += centered_reference(x[r[2]], scales.rater_sd)
        lp += centered_reference(x[r[5]], scales.log_consistency_sd, source_index)
        for steps in eachcol(reshape(x[r[6]], 2, 4)) # Four items, K=4 in reference_case.
            lp += centered_reference(steps, scales.step_sd)
        end
        return lp
    end
    density(x) = sum(case.pointwise(x)) + logprior(x)
    return merge(case, (; target, sd, logprior, density))
end

const NORMALIZED_CASES = [normalized_case(case, model, source_rater, unit_scales)
    for case in CASES for (model, source_rater, unit_scales) in
        ((:exchangeable, nothing, false), (:source, "R1", false),
         (:source, "R2", false), (:source, "R3", false), (:source, "R1", true))]

@testset "MGMFRM numerical snapshots and sampler-entry guards" begin
    for case in CASES
        design = deepcopy(case.target.design)
        target = B._mgmfrm_guarded_local_fit_logdensity(design; prior=case.target.prior)
        x = case.points[2]
        expected = B.LogDensityProblems.logdensity(target, x)
        design.spec.q_matrix .= false
        @test B.LogDensityProblems.logdensity(target, x) == expected
        @test_throws ArgumentError B._mgmfrm_guarded_local_fit_logdensity(design)
        # Standalone transformations/likelihoods keep their checked entry path.
        @test_throws ArgumentError B._mgmfrm_source_constrained_params_from_unconstrained(design, x)
        @test_throws ArgumentError B._mgmfrm_source_loglikelihood_from_unconstrained(design, x)
        for invalid in (x[1:end-1], fill(NaN, length(x)), fill(Inf, length(x)))
            @test_throws ArgumentError B.LogDensityProblems.logdensity(target, invalid)
        end
        overflow = copy(x)
        overflow[first(target.blueprint.blocks[:log_item_dimension_discrimination])] = 1000
        @test_throws ArgumentError B.LogDensityProblems.logdensity(target, overflow)

        # Modified owned designs must fail before either sampler or compiler runs.
        for mutate! in (d -> (d.spec.q_matrix .= false),
                d -> reverse!(d.parameter_names),
                d -> (d.spec.data.category[1] = 0))
            for runner in (B._mgmfrm_guarded_local_fit_sampler_diagnostics,
                    B._cmdstan_mgmfrm_sampler_diagnostics)
                bad = deepcopy(target)
                mutate!(bad.design)
                @test_throws ArgumentError runner(bad, x)
            end
            for backend in (:advancedhmc, :cmdstan)
                bad = B._MGMFRMNormalizedPriorLogDensity(target.design.spec;
                    prior_model=:exchangeable,
                    scales=B._source_fixture_prior_values(target.prior))
                mutate!(bad.base.design)
                @test_throws ArgumentError B._mgmfrm_normalized_prior_sample(bad, x; backend)
            end
        end
    end
end

@testset "MGMFRM blockwise raw measure and independent equation (no fitting)" begin
    for case in CASES
        (; target, names, ranges, sd, direct, pointwise, logprior, density, points) = case
        @test [target.blueprint.blocks[name] for name in names] == ranges
        @test B._cmdstan_mgmfrm_data(target).prior_sd == sd
        for x in points
            @test B._guarded_generalized_direct_params(target, x) ≈ direct(x) atol = 1e-12
            @test ForwardDiff.jacobian(z -> B._guarded_generalized_direct_params(target, z), x) ≈
                ForwardDiff.jacobian(direct, x) atol = 1e-12
            @test B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(target.design, x) ≈
                pointwise(x) atol = 1e-12
            @test B._source_fixture_logprior(target, x) ≈ logprior(x) atol = 1e-12
            @test ForwardDiff.gradient(z -> B._source_fixture_logprior(target, z), x) ≈
                -x ./ sd.^2 atol = 1e-12
            @test B.LogDensityProblems.logdensity(target, x) ≈ density(x) atol = 1e-11
            @test ForwardDiff.gradient(z -> B.LogDensityProblems.logdensity(target, z), x) ≈
                ForwardDiff.gradient(density, x) atol = 1e-10
        end
        x = points[2]
        # Free positive-coordinate chart, not the redundant full product-one vector.
        positive = vcat(collect(ranges[4]), collect(ranges[5]))
        z = x[positive]
        logjac = logabsdet(ForwardDiff.jacobian(v -> exp.(v), z))[1]
        @test logjac ≈ sum(z) atol = 1e-12
        positive_density(v) = -sum(abs2, log.(v) ./ sd[positive]) / 2 -
            sum(log, sd[positive]) - length(v) * log(2pi) / 2 - sum(log, v)
        pulled_back(v) = positive_density(exp.(v)) + sum(v)
        @test pulled_back(z) ≈ -sum(abs2, z ./ sd[positive]) / 2 -
            sum(log, sd[positive]) - length(z) * log(2pi) / 2 atol = 1e-12
        @test ForwardDiff.gradient(pulled_back, z) ≈ -z ./ sd[positive].^2 atol = 1e-12
        # Omitting the pullback adjustment changes every positive-block gradient by -1.
        @test ForwardDiff.gradient(v -> positive_density(exp.(v)), z) ≈
            -z ./ sd[positive].^2 .- 1 atol = 1e-12
        h = 1e-5
        finite_difference = [(density(x + h * e) - density(x - h * e)) / (2h)
            for e in eachcol(Matrix{Float64}(I, length(x), length(x)))]
        @test ForwardDiff.gradient(density, x) ≈ finite_difference atol = 1e-7 rtol = 1e-7
    end
end

@testset "Complete normalized MGMFRM targets and prior identity (no fitting)" begin
    @test :_MGMFRMNormalizedPriorLogDensity ∉ names(B)
    identities = String[]
    for case in NORMALIZED_CASES
        target = case.target
        record = B._mgmfrm_normalized_prior_record(target)
        identity = B._mgmfrm_normalized_prior_identity(target)
        push!(identities, identity)
        @test initial_params(target) == initial_params(target.base)
        @test B.LogDensityProblems.dimension(target) == length(case.sd)
        payload = B._cmdstan_mgmfrm_data(target)
        @test payload.prior_model == (record.prior_model === :source ? 1 : 2)
        @test payload.source_rater == target.source_rater_index
        restored = B._MGMFRMNormalizedPriorLogDensity(target.base.design.spec, record;
            expected_identity = identity)
        @test B._mgmfrm_normalized_prior_identity(restored) == identity
        for x in case.points
            @test B.logprior(target, x) ≈ case.logprior(x) atol = 1e-11
            @test B.LogDensityProblems.logdensity(target, x) ≈ case.density(x) atol = 1e-11
            @test ForwardDiff.gradient(z -> B.LogDensityProblems.logdensity(target, z), x) ≈
                ForwardDiff.gradient(case.density, x) atol = 1e-10
            @test B.LogDensityProblems.logdensity(restored, x) == B.LogDensityProblems.logdensity(target, x)
        end
        # Raw and complete normalized targets cannot enter the same fit/cache path.
        @test_throws ArgumentError B.Experimental.fit(target.base.design.spec;
            prior = target, ndraws = 1, warmup = 0)
        @test_throws ArgumentError B.Experimental.fit_cache_key(target.base.design.spec;
            prior = record, seed = 23)
        @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(target.base.design.spec,
            merge(record, (; scales = merge(record.scales, (; step_sd = 2.3)))); expected_identity = identity)
        @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(target.base.design.spec,
            record; expected_identity = "wrong-target")
        for bad in (zeros(length(case.sd) - 1), fill(NaN, length(case.sd)), fill(Inf, length(case.sd)))
            @test_throws ArgumentError B.LogDensityProblems.logdensity(target, bad)
            @test_throws ArgumentError B.logprior(target, bad)
        end
    end
    @test length(unique(identities)) == length(identities)
    target = NORMALIZED_CASES[2].target
    spec = target.base.design.spec
    record = B._mgmfrm_normalized_prior_record(target)
    identity = B._mgmfrm_normalized_prior_identity(target)
    scales = record.scales
    @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec; prior_model = :raw, scales)
    @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec; prior_model = :source, scales)
    for id in ("absent", 1)
        @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec;
            prior_model = :source, scales, source_rater = id)
    end
    @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec;
        prior_model = :exchangeable, scales, source_rater = "R1")
    for bad_scales in ((; person_sd = 1.0), merge(scales, (; extra = 1.0)),
            (merge(scales, NamedTuple{(name,)}((bad,))) for name in keys(scales)
                for bad in (0.0, -1.0, Inf, NaN, big"1e-1000", big"1e1000"))...)
        @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec;
            prior_model = :source, scales = bad_scales, source_rater = "R1")
    end
    @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec; prior_model = :source,
        scales = merge(scales, (; log_consistency_sd = 1e200)), source_rater = "R1")
    for bad_record in (B._prior_cache_record(target.base.prior),
            merge(record, (; extra = true)), merge(record, (; schema = :unknown)),
            merge(record, (; scale_convention = :marginal_sd)),
            merge(record, (; parameter_measure = :positive_coordinates)),
            merge(record, (; prior_model = :unknown)), merge(record, (; source_rater = "R2")))
        @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(spec, bad_record;
            expected_identity = identity)
    end
    @test_throws ArgumentError B._MGMFRMNormalizedPriorLogDensity(CASES[2].target.design.spec,
        record; expected_identity = identity)
    # Changing the caller's labels after construction cannot move the source rater.
    caller_spec = deepcopy(spec)
    snapshot = B._MGMFRMNormalizedPriorLogDensity(caller_spec;
        prior_model = :source, scales, source_rater = "R1")
    caller_spec.data.rater_levels[1] = "changed"
    @test B._mgmfrm_normalized_prior_record(snapshot).source_rater == "R1"
    @test B._mgmfrm_normalized_prior_identity(snapshot) == identity

    # Relabel the actual ratings, transform both constrained rater blocks, and
    # carry the distinguished ID. Exchangeability is a prior property, not Q identification.
    data = spec.data
    renamed_data = FacetData((;
        person = [data.person_levels[p] for p in data.person],
        item = [data.item_levels[i] for i in data.item],
        rater = [reverse(data.rater_levels)[r] for r in data.rater],
        score = [data.category_levels[k] for k in data.category],
    ); person = :person, item = :item, rater = :rater, score = :score,
        category_levels = data.category_levels)
    renamed_spec = mfrm_spec(renamed_data; family = :mgmfrm, dimensions = 2,
        thresholds = :partial_credit, q_matrix = spec.q_matrix)
    raw = copy(CASES[1].points[2])
    renamed_raw = copy(raw)
    for block in (:rater_free, :log_rater_consistency_free)
        range = target.base.blueprint.blocks[block]
        renamed_raw[range] = reverse(vcat(raw[range], -sum(raw[range])))[1:end-1]
    end
    for (model, original_id, renamed_id) in ((:source, "R1", "R3"), (:exchangeable, nothing, nothing))
        original = B._MGMFRMNormalizedPriorLogDensity(spec; prior_model = model, scales, source_rater = original_id)
        renamed = B._MGMFRMNormalizedPriorLogDensity(renamed_spec; prior_model = model, scales, source_rater = renamed_id)
        @test B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(original.base.design, raw) ≈
            B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(renamed.base.design, renamed_raw)
        @test B.logprior(original, raw) ≈ B.logprior(renamed, renamed_raw) atol = 1e-12
        @test B.LogDensityProblems.logdensity(original, raw) ≈
            B.LogDensityProblems.logdensity(renamed, renamed_raw) atol = 1e-11
    end
end

function fixed_reference_case(case)
    spec = case.target.design.spec
    data, q = spec.data, spec.q_matrix
    J, I, R, K, D = length(data.person_levels), size(q, 1),
        length(data.rater_levels), length(data.category_levels), size(q, 2)
    prior = MFRMPrior(0.8, 0.5, 0.9, 0.6)
    target = B._MFRMFixedQReferenceLogDensity(spec; prior)
    counts = [J * D, R - 1, I, I * (K - 2)]
    ends = cumsum(counts)
    ranges = [(last - count + 1):last for (last, count) in zip(ends, counts)]
    sd = vcat([fill(scale, count) for (scale, count) in
        zip((prior.person_sd, prior.rater_sd, prior.item_sd, prior.step_sd), counts)]...)
    function pointwise(x)
        theta, severity, item, steps = [x[r] for r in ranges]
        severity = vcat(severity, -sum(severity))
        return map(1:data.n) do n
            p, i, r = data.person[n], data.item[n], data.rater[n]
            ability = sum(q[i, d] * theta[(p - 1) * D + d] for d in 1:D)
            free = steps[((i - 1) * (K - 2) + 1):(i * (K - 2))]
            eta = (0:(K - 1)) .* (ability - item[i] - severity[r]) .-
                cumsum(vcat(zero(eltype(x)), free, -sum(free)))
            largest = maximum(eta)
            eta[data.category[n]] - largest - log(sum(exp.(eta .- largest)))
        end
    end
    prior_density(x) = -sum(abs2, x ./ sd) / 2 - sum(log, sd) - length(sd) * log(2pi) / 2
    density(x) = sum(pointwise(x)) + prior_density(x)
    mixed = [0.23sin(i) + 0.11cos(2i) for i in eachindex(sd)]
    points = [zeros(length(sd)), mixed,
        ([i in block ? mixed[i] : 0.0 for i in eachindex(sd)] for block in ranges)...]
    return (; target, ranges, sd, pointwise, prior_density, density, points)
end

const FIXED_REFERENCES = fixed_reference_case.([CASES...,
    reference_case(Bool[1 0 0; 1 0 0; 0 1 0; 0 1 0; 0 0 1; 0 0 1])])

@testset "Fixed-coefficient MFRM reduced coordinates and unit-logit measure (no fitting)" begin
    for case in FIXED_REFERENCES
        (; target, ranges, sd, pointwise, prior_density, density, points) = case
        base, prior = target.base, target.prior
        spec, data = base.design.spec, base.design.spec.data
        q, D = spec.q_matrix, spec.dimensions
        J, I, R = length(data.person_levels), length(data.item_levels), length(data.rater_levels)
        @test B.LogDensityProblems.dimension(target) == length(sd) ==
            B.LogDensityProblems.dimension(base) - count(q) - (R - 1)
        @test [target.blueprint.blocks[b] for b in (:person, :rater_free, :item, :item_steps)] == ranges
        @test initial_params(target) == zeros(length(sd))
        @test !any(n -> occursin("discrimination", n) || occursin("consistency", n),
            target.blueprint.parameter_names)
        for x in points
            raw = B._mfrm_fixed_q_reference_raw(target, x)
            @test raw[base.blueprint.blocks[:log_item_dimension_discrimination]] == zeros(count(q))
            @test raw[base.blueprint.blocks[:log_rater_consistency_free]] == zeros(R - 1)
            direct = B._guarded_generalized_direct_params(base, raw)
            @test all(isone, direct[base.design.blocks[:item_dimension_discrimination]])
            @test all(isone, direct[base.design.blocks[:rater_consistency]])
            @test B._mgmfrm_source_pointwise_loglikelihood_from_unconstrained(base.design, raw) ≈
                pointwise(x) atol = 1e-12
            @test logprior(target, x) ≈ prior_density(x) atol = 1e-12
            @test B.LogDensityProblems.logdensity(target, x) ≈ density(x) atol = 1e-11
            @test ForwardDiff.gradient(z -> B.LogDensityProblems.logdensity(target, z), x) ≈
                ForwardDiff.gradient(density, x) atol = 1e-10
        end
        x = points[2]
        # A change from a scaled source-coordinate prior needs both the SD mapping
        # and its constant Jacobian. The reference declares its prior on x instead.
        scaled = B._mgmfrm_guarded_local_fit_logdensity(spec; prior = B._SourceFixturePrior(
            person_sd = prior.person_sd / 1.7, rater_sd = prior.rater_sd / 1.7,
            item_sd = prior.item_sd / 1.7, step_sd = prior.step_sd / 1.7))
        fixed = setdiff(1:B.LogDensityProblems.dimension(base), target.blueprint.base_indices)
        constant = sum(B._normal_logpdf(0.0, B._source_fixture_prior_sd(scaled, i)) for i in fixed)
        @test B._source_fixture_logprior(scaled, B._mfrm_fixed_q_reference_raw(target, x)) -
            constant - length(x) * log(1.7) ≈ logprior(target, x) atol = 1e-11
        # Fixed slopes remove scale freedom, but likelihood location shifts remain.
        shift = [0.2d for d in 1:D]
        moved = copy(x)
        moved[ranges[1]] .+= repeat(shift, J)
        moved[ranges[3]] .+= q * shift
        @test pointwise(moved) ≈ pointwise(x) atol = 1e-12
        @test !isapprox(logprior(target, moved), logprior(target, x); atol = 1e-5)
        for bad in (x[1:end-1], [x; 0.0], fill(NaN, length(x)), fill(Inf, length(x)))
            @test_throws ArgumentError B.LogDensityProblems.logdensity(target, bad)
        end

        if all(sum(q; dims = 2) .== 1)
            # A single scalar design leaves D-1 unfixed location directions.
            scalar_data = FacetData((; person = ["P$(data.person[n])-D$(findfirst(q[data.item[n], :]))"
                for n in 1:data.n], item = data.item, rater = data.rater,
                score = data.category .- 1); person = :person, item = :item,
                rater = :rater, score = :score, category_levels = 0:(length(data.category_levels) - 1))
            @test_throws ArgumentError mfrm_spec(scalar_data; thresholds = :partial_credit)
            rater = vcat(x[ranges[2]], -sum(x[ranges[2]]))
            item = x[ranges[3]]
            total = 0.0
            for d in 1:D
                rows = findall(n -> q[data.item[n], d], 1:data.n)
                subset = FacetData((; person = data.person[rows], item = data.item[rows],
                    rater = data.rater[rows], score = data.category[rows] .- 1);
                    person = :person, item = :item, rater = :rater, score = :score,
                    category_levels = 0:(length(data.category_levels) - 1))
                scalar = getdesign(mfrm_spec(subset; thresholds = :partial_credit))
                items = Int.(subset.item_levels)
                origin = item[first(items)]
                scalar_x = zeros(length(scalar.parameter_names))
                scalar_x[scalar.blocks[:person]] = [x[(p - 1) * D + d] - origin - rater[1]
                    for p in subset.person_levels]
                scalar_x[scalar.blocks[:rater]] = rater[2:end] .- rater[1]
                scalar_x[scalar.blocks[:item]] = item[items[2:end]] .- origin
                scalar_x[scalar.blocks[:thresholds]] = vec(reshape(x[ranges[4]], :, I)[:, items])
                @test B._pointwise_loglikelihood_unchecked(scalar, scalar_x) ≈ pointwise(x)[rows] atol = 1e-12
                total += loglikelihood(scalar, scalar_x)
            end
            @test total ≈ sum(pointwise(x)) atol = 1e-11 # Conditional likelihood only.
        end
    end
end

# Explicit standalone invocation uses the existing CmdStan opt-in. No sampling,
# new runtime dependency, retained binary or regenerated historical fixture.
if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "MGMFRM production CmdStan raw density and gradient (no fitting)" begin
        check = cmdstan_backend_check(; require_ready = true, include_paths = true)
        @info "Production density comparison" julia=VERSION cmdstan=check.cmdstan_version
        mktempdir() do directory
            compiled = B._cmdstan_compile_mgmfrm(check; cache_dir = joinpath(directory, "build"))
            for case in (CASES..., NORMALIZED_CASES...)
                data_path = joinpath(directory, "data.json")
                points_path = joinpath(directory, "points.json")
                output_path = joinpath(directory, "density.csv")
                write(data_path, JSON3.write(B._cmdstan_mgmfrm_data(case.target)))
                write(points_path, JSON3.write((; params_r = case.points)))
                results = map((0, 1)) do jacobian
                    B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$output_path sig_figs=18 refresh=0`, :density_check)
                    csv = B._cmdstan_read_csv(output_path, length(case.points))
                    @test csv.header == ["lp__"; ["g_beta.$i" for i in eachindex(case.sd)]]
                    @test all(isfinite, csv.values)
                    expected_lp = case.density.(case.points)
                    # CmdStan log_prob uses propto=true: remove only the known,
                    # fixed normalizing constant, and also compare density differences.
                    constant = -sum(log, case.sd) - length(case.sd) * log(2pi) / 2
                    @test csv.values[:, 1] .+ constant ≈ expected_lp atol = 1e-9 rtol = 1e-10
                    @test csv.values[:, 1] .- csv.values[1, 1] ≈
                        expected_lp .- expected_lp[1] atol = 1e-9 rtol = 1e-10
                    gradient_error = 0.0
                    for (row, x) in enumerate(case.points)
                        expected_gradient = ForwardDiff.gradient(z ->
                            B.LogDensityProblems.logdensity(case.target, z), x)
                        @test all(isapprox.(csv.values[row, 2:end], expected_gradient;
                            atol = 1e-8, rtol = 1e-9))
                        gradient_error = max(gradient_error,
                            maximum(abs.(csv.values[row, 2:end] .- expected_gradient)))
                    end
                    @info "CmdStan comparison errors" parameters=length(case.sd) jacobian max_density_error=maximum(abs.(csv.values[:, 1] .+ constant .- expected_lp)) max_gradient_error=gradient_error
                    csv.values
                end
                @test results[1] == results[2] # Stan beta itself has no bounds.
            end
            case = first(NORMALIZED_CASES)
            payload = B._cmdstan_mgmfrm_data(case.target)
            bad_payloads = [merge(payload, (; prior_model = 3)),
                merge(payload, (; prior_model = 1, source_rater = 0)),
                merge(payload, (; prior_model = 2, source_rater = 1)),
                merge(payload, (; prior_model = 0, source_rater = 1))]
            for block in (2, 5, 6)
                nonuniform = copy(payload.prior_sd)
                nonuniform[last(case.ranges[block])] *= 2
                push!(bad_payloads, merge(payload, (; prior_sd = nonuniform)))
                nonpositive = copy(payload.prior_sd)
                nonpositive[case.ranges[block]] .= 0
                push!(bad_payloads, merge(payload, (; prior_sd = nonpositive)))
            end
            overflow = copy(payload.prior_sd)
            overflow[case.ranges[5]] .= 1e200
            push!(bad_payloads, merge(payload, (; prior_model = 1, source_rater = 1,
                prior_sd = overflow)))
            points_path = joinpath(directory, "invalid-points.json")
            write(points_path, JSON3.write((; params_r = case.points)))
            for bad_payload in bad_payloads
                data_path, output_path = joinpath(directory, "invalid-data.json"), joinpath(directory, "invalid.csv")
                write(data_path, JSON3.write(bad_payload))
                @test_throws B.CmdStanError B._cmdstan_run(`$(compiled.path) log_prob unconstrained_params=$points_path jacobian=1 data file=$data_path output file=$output_path`, :density_check)
            end
        end
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "Fixed-coefficient MFRM CmdStan reduced density and gradient (no fitting)" begin
        check = cmdstan_backend_check(; require_ready = true, include_paths = true)
        mktempdir() do directory
            compiled = B._cmdstan_compile_model(check, :mfrm_fixed_q;
                cache_dir = joinpath(directory, "build"))
            executable = compiled.path
            for case in FIXED_REFERENCES
                data_path, points_path, output_path = [joinpath(directory, name)
                    for name in ("data.json", "points.json", "density.csv")]
                write(data_path, JSON3.write(B._cmdstan_generalized_data(case.target)))
                write(points_path, JSON3.write((; params_r = case.points)))
                results = map((0, 1)) do jacobian
                    B._cmdstan_run(`$executable log_prob unconstrained_params=$points_path jacobian=$jacobian data file=$data_path output file=$output_path sig_figs=18 refresh=0`, :density_check)
                    csv = B._cmdstan_read_csv(output_path, length(case.points))
                    @test csv.header == ["lp__"; ["g_beta.$i" for i in eachindex(case.sd)]]
                    @test csv.values[:, 1] ≈ case.density.(case.points) atol = 1e-9 rtol = 1e-10
                    for (row, x) in enumerate(case.points)
                        @test csv.values[row, 2:end] ≈ ForwardDiff.gradient(z ->
                            B.LogDensityProblems.logdensity(case.target, z), x) atol = 1e-8 rtol = 1e-9
                    end
                    csv.values
                end
                @test results[1] == results[2]
            end
        end
    end
end

end # module
