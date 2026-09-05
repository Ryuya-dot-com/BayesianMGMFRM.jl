using Test

# M1 preparation only: reuse the standalone generator, not the fitting kernel.
# No MCMC, evaluation seeds, research fixtures, or new package API are needed.
module MFRMAnchorStandaloneDGP
include(joinpath(@__DIR__, "..", "src", "local_dependence_known_truth_dgp.jl"))
end

using BayesianMGMFRM

@testset "reference-valued anchor declarations share sampling targets" begin
    hard(block, level, value) = (; block, level, value, type = :hard)
    r1, r4 = hard(:rater, "R1", 0.0), hard(:rater, "R4", 1.5)
    i1, i4 = hard(:item, "I1", 0.0), hard(:item, "I4", 1.2)
    baseline = NamedTuple[]
    rater_pair, item_pair = [r1, r4], [i1, i4]
    equivalent_declarations = (
        (baseline, [r1]), (baseline, [i1]), (baseline, [r1, i1]),
        (rater_pair, [r1, r4, i1]), (item_pair, [i1, i4, r1]),
    )
    for thresholds in (:rating_scale, :partial_credit), sparse in (false, true)
        events = [(p, r, i) for p in 1:40 for r in 1:4 for i in 1:4
            if !sparse || r in (mod1(p, 4), mod1(p + 1, 4))]
        data = FacetData((;
            person = ["P$(lpad(string(p), 2, '0'))" for (p, r, i) in events],
            rater = ["R$r" for (p, r, i) in events],
            item = ["I$i" for (p, r, i) in events],
            score = [mod(p + r + i, 4) for (p, r, i) in events],
        ); person = :person, rater = :rater, item = :item,
            score = :score, category_levels = 0:3)
        @test data.n == (sparse ? 320 : 640)
        @test all(count(==(rater), data.rater) == (sparse ? 80 : 160)
            for rater in 1:4)
        for (canonical, declared) in equivalent_declarations
            reference = getdesign(mfrm_spec(data; thresholds, anchors = canonical))
            alias = getdesign(mfrm_spec(data; thresholds, anchors = declared))
            @test alias.parameter_names == reference.parameter_names
            n = length(reference.parameter_names)
            for params in (zeros(n), collect(range(-0.5, 0.5; length = n)),
                    collect(range(1.5, -1.5; length = n)))
                @test loglikelihood(alias, params) == loglikelihood(reference, params)
                for scale in (0.5, 1.0, 2.0)
                    prior = MFRMPrior(; person_sd = 1.5scale,
                        rater_sd = scale, item_sd = scale, step_sd = scale)
                    @test logprior(alias, params, prior) == logprior(reference, params, prior)
                end
            end
        end
        # R3-R2 and I3-I2 stay estimated in all four primary regimes. Endpoint
        # or fully fixed contrasts must not be scored as posterior coverage.
        for anchors in (baseline, rater_pair, item_pair, [r1, r4, i1, i4])
            design = getdesign(mfrm_spec(data; thresholds, anchors))
            @test all(name -> name in design.parameter_names,
                ("rater[R2]", "rater[R3]", "item[I2]", "item[I3]",
                    "person[P10]", "person[P30]"))
        end
        for (block, prefix, endpoints, interior) in (
                (:rater, "R", rater_pair,
                    [hard(:rater, "R2", 0.5), hard(:rater, "R3", 1.0)]),
                (:item, "I", item_pair,
                    [hard(:item, "I2", 0.4), hard(:item, "I3", 0.8)]))
            for anchors in (endpoints, interior)
                design = getdesign(mfrm_spec(data; thresholds, anchors))
                # The alternate 2-1 contrast is partially estimated under
                # either placement; it is not the fixed interior 3-2 contrast.
                @test count(level -> "$block[$prefix$level]" in design.parameter_names,
                    (1, 2)) == 1
                if anchors === interior
                    @test all(level -> "$block[$prefix$level]" ∉ design.parameter_names,
                        (2, 3))
                end
            end
        end
    end
    # This does not equate reports/cache metadata, shifted anchor values,
    # different reference levels, or priors in different coordinates.
end

@testset "MFRM anchor generator equation and category checks" begin
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    draw = MFRMAnchorStandaloneDGP._ld1_inverse_cdf
    # Adjacent-category odds: exp(theta - severity - difficulty - step).
    # Wind & Jones (2018), p. 686, Eq. 1, DOI: 10.1177/0013164417703733.
    # PCM changes step ownership, not this recurrence; see Linacre (2000),
    # https://www.rasch.org/rmt/rmt143k.htm (RSM shared / PCM item-specific).
    @test probability(log(2), zeros(3)) ≈ [1, 2, 4, 8] ./ 15 atol = 1e-14
    @test probability(0.0, [-log(2), 0.0, log(2)]) ≈ [1, 2, 2, 1] ./ 6 atol = 1e-14
    @test probability(0.0, [-log(3), log(3)]) ≈ [1, 3, 1] ./ 5 atol = 1e-14
    @test probability(0.0, [0.0]) == [0.5, 0.5]
    for location in (-1_000.0, 1_000.0)
        probabilities = probability(location, [-0.6, 0.1, 0.5])
        @test all(isfinite, probabilities)
        @test sum(probabilities) ≈ 1 atol = 1e-14
        @test probabilities[location < 0 ? 1 : end] == 1.0
    end
    # Half-open CDF bins, including zero-probability endpoints and labels
    # that differ from the zero-based category position in the equation.
    for first_category in (-2, 0, 1)
        levels = collect(first_category:(first_category + 3))
        @test draw(0.0, [0.0, 0.25, 0.75, 0.0], levels) == levels[2]
        @test draw(0.25, [0.0, 0.25, 0.75, 0.0], levels) == levels[3]
        @test draw(prevfloat(1.0), [0.0, 0.25, 0.75, 0.0], levels) == levels[3]
    end
    @test_throws ArgumentError draw(-eps(), [0.5, 0.5], [0, 1])
    @test_throws ArgumentError draw(1.0, [0.5, 0.5], [0, 1])

    source = joinpath(@__DIR__, "..", "src", "local_dependence_known_truth_dgp.jl")
    code = "include(ARGS[1]); @assert !isdefined(Main, :BayesianMGMFRM); " *
        "print(_ld1_pcm_probabilities(0.0, [0.0]))"
    command = addenv(`$(Base.julia_cmd()) --startup-file=no -e $code $source`,
        "JULIA_LOAD_PATH" => "@stdlib")
    @test read(command, String) == "[0.5, 0.5]"
end

@testset "MFRM anchor generator versus identified RSM and PCM" begin
    probability = MFRMAnchorStandaloneDGP._ld1_pcm_probabilities
    persons = ["P3", "P1", "P4", "P2"]
    raters = ["R3", "R1", "R2"]
    items = ["I3", "I1", "I2"]
    theta = Dict(zip(persons, [-0.9, -0.3, 0.3, 0.9]))
    severity = Dict(zip(raters, [-0.6, 0.1, 0.5]))
    difficulty = Dict(zip(items, [-0.4, 0.2, 0.7]))
    selected(mask, labels) = [label for (index, label) in pairs(labels)
        if !iszero(mask & (1 << (index - 1)))]

    # 2 families x 3 category counts x 2 designs x 8 x 8 anchor masks = 768.
    # Truth is assembled by semantic labels, never extracted from fit helpers.
    for thresholds in (:rating_scale, :partial_credit),
            (categories, first_category) in ((2, -2), (3, 1), (5, 0)),
            sparse in (false, true)
        levels = collect(first_category:(first_category + categories - 1))
        events = [(p, r, i) for p in 1:4 for r in 1:3 for i in 1:3
            if !sparse || r in (mod1(p, 3), mod1(p + 1, 3))]
        sparse && reverse!(events)
        table = (;
            person = [persons[p] for (p, r, i) in events],
            rater = [raters[r] for (p, r, i) in events],
            item = [items[i] for (p, r, i) in events],
            score = [levels[mod1(p + 2r + i, categories)] for (p, r, i) in events],
        )
        data = FacetData(table; person = :person, rater = :rater,
            item = :item, score = :score, category_levels = levels)
        steps = Dict{String,Vector{Float64}}()
        for (i, label) in pairs(items)
            owner = thresholds === :rating_scale ? 1 : i
            free = [0.15 * s - 0.11 * owner for s in 1:(categories - 2)]
            steps[label] = vcat(free, -sum(free))
        end
        expected = reduce(vcat, [permutedims(probability(
            theta[p] - severity[r] - difficulty[i], steps[i]))
            for (p, r, i) in zip(table.person, table.rater, table.item)])
        expected_loglikelihood = [log(expected[row, score - first_category + 1])
            for (row, score) in pairs(table.score)]

        for rater_mask in 0:7, item_mask in 0:7
            fixed_raters = selected(rater_mask, raters)
            fixed_items = selected(item_mask, items)
            # Common shifts remain compatible even with multiple anchors.
            # The untouched zero-centered priors are NOT claimed invariant.
            rater_shift = isempty(fixed_raters) ? -severity[first(data.rater_levels)] : 0.4
            item_shift = isempty(fixed_items) ? -difficulty[first(data.item_levels)] : -0.3
            anchors = vcat(
                [(; block = :rater, level, value = severity[level] + rater_shift,
                    type = :hard) for level in fixed_raters],
                [(; block = :item, level, value = difficulty[level] + item_shift,
                    type = :hard) for level in fixed_items])
            design = getdesign(mfrm_spec(data; thresholds, anchors))
            isempty(fixed_raters) && push!(fixed_raters, first(data.rater_levels))
            isempty(fixed_items) && push!(fixed_items, first(data.item_levels))
            values = Dict("person[$level]" => theta[level] + rater_shift + item_shift
                for level in persons)
            merge!(values, Dict("rater[$level]" => severity[level] + rater_shift
                for level in raters if level ∉ fixed_raters))
            merge!(values, Dict("item[$level]" => difficulty[level] + item_shift
                for level in items if level ∉ fixed_items))
            for label in (thresholds === :rating_scale ? items[1:1] : items),
                    step in 1:(categories - 2)
                name = thresholds === :rating_scale ? "step[$step]" : "step[item=$label,$step]"
                values[name] = steps[label][step]
            end
            @test Set(design.parameter_names) == Set(keys(values))
            params = [values[name] for name in design.parameter_names]
            actual = dropdims(predictive_probabilities(design, reshape(params, 1, :)); dims = 1)
            @test actual ≈ expected atol = 1e-12 rtol = 0
            @test pointwise_loglikelihood(design, params) ≈ expected_loglikelihood atol = 1e-12 rtol = 0
            if rater_mask == item_mask == 0b101
                # Differential error excludes the original truth. Cross signs
                # to check that opposite facet errors cannot cancel globally.
                for magnitude in (0.2, 0.8), rater_sign in (-1, 1), item_sign in (-1, 1)
                    dr, di = magnitude * rater_sign, magnitude * item_sign
                    perturbed = [merge(anchor, (; value = anchor.value +
                        (anchor.block === :rater && anchor.level == raters[3] ? dr :
                         anchor.block === :item && anchor.level == items[3] ? di : 0.0)))
                        for anchor in anchors]
                    constrained = getdesign(mfrm_spec(data; thresholds, anchors = perturbed))
                    constrained_params = [values[name] for name in constrained.parameter_names]
                    constrained_expected = reduce(vcat, [permutedims(probability(
                        theta[p] - severity[r] - difficulty[i] -
                        (r == raters[3] ? dr : 0.0) - (i == items[3] ? di : 0.0), steps[i]))
                        for (p, r, i) in zip(table.person, table.rater, table.item)])
                    constrained_actual = dropdims(predictive_probabilities(
                        constrained, reshape(constrained_params, 1, :)); dims = 1)
                    @test constrained_actual ≈ constrained_expected atol = 1e-12 rtol = 0
                    # Detect accidental equality, not a practical effect size.
                    @test maximum(abs.(constrained_expected .- expected)) > 1e-4
                end
            end
        end
    end
end
