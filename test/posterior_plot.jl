module PosteriorPlotChecks
using Test, Statistics, BayesianMGMFRM, Random
const B = BayesianMGMFRM
include("fixtures/reporting_fit.jl")
const fits = Dict(family => reporting_fit(family) for family in (:mfrm, :gmfrm, :mgmfrm))

@testset "posterior figure coordinates without a renderer" begin
    @test :plot_posterior ∉ names(B)
    contract = B._root_api_contract()
    @test setdiff(Set(names(B)), Set([:BayesianMGMFRM])) ==
        union(Set(contract.stable), Set(contract.compatibility), Set(contract.research))
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        error = try B.plot_posterior(fits[:mfrm]); catch err; err; end
        @test error isa ArgumentError
        @test occursin("using CairoMakie", sprint(showerror, error))
    end
    for (family, fit) in fits, scale in (:model, :raw)
        data = B._posterior_plot_data(fit; scale, interval = 0.9)
        source = scale === :raw || family === :mfrm ? fit.draws : fit.direct_draws
        names = family === :mfrm ? fit.design.parameter_names : scale === :raw ?
            fit.diagnostic_surface.raw_parameter_names : fit.diagnostic_surface.direct_parameter_names
        lookup = Dict(row.parameter => row for row in data.rows)
        for (index, name) in enumerate(names)
            @test lookup[name].median ≈ median(source[:, index])
            @test lookup[name].lower ≈ quantile(source[:, index], 0.05)
            @test lookup[name].upper ≈ quantile(source[:, index], 0.95)
        end
        @test all(row -> row.lower <= row.median <= row.upper, data.rows)
        @test data.diagnostic != "No warnings under the fit's MCMC diagnostic thresholds"
        person = B._posterior_plot_data(fit; scale, block = :person)
        @test all(row -> row.block === :person, person.rows)
        names = reverse(getproperty.(person.rows, :parameter))
        selected = B._posterior_plot_data(fit; scale, parameters = names)
        @test getproperty.(selected.rows, :parameter) == names
        @test_throws ArgumentError B._posterior_plot_data(fit; scale, max_parameters = 1)
    end
    anchored = reporting_fit(:mfrm; anchors = [(; block = :rater, level = 2, value = 0.75, type = :hard)])
    anchor = only(row for row in B._posterior_plot_data(anchored; block = :rater).rows if row.fixed)
    @test (anchor.parameter, anchor.median, anchor.lower, anchor.upper) == ("rater[2]", 0.75, 0.75, 0.75)
    @test getproperty.(B._posterior_plot_data(fits[:mfrm]; block = :rater).rows, :parameter) == ["rater[1]", "rater[2]"]
    mfrm_steps = B._posterior_plot_data(fits[:mfrm]; block = :thresholds).rows
    for item in 1:2
        first_step = only(row for row in mfrm_steps if row.parameter == "step[item=$item,1]")
        last_step = only(row for row in mfrm_steps if row.parameter == "step[item=$item,2]")
        @test last_step.median ≈ -first_step.median
        @test last_step.lower ≈ -first_step.upper
        @test !last_step.fixed
    end
    rsm = B._posterior_plot_data(reporting_fit(:mfrm; thresholds = :rating_scale); block = :thresholds)
    @test getproperty.(rsm.rows, :parameter) == ["step[1]", "step[2]"]
    @test rsm.rows[2].lower ≈ -rsm.rows[1].upper
    binary = FacetData((; person = [1, 1, 2, 2], item = [1, 2, 1, 2],
        rater = [1, 2, 2, 1], score = [0, 1, 1, 0]);
        person = :person, item = :item, rater = :rater, score = :score)
    for family in (:mfrm, :gmfrm, :mgmfrm)
        block = family === :mfrm ? :thresholds : family === :gmfrm ? :rater_steps : :item_steps
        steps = B._posterior_plot_data(reporting_fit(family; data = binary); block).rows
        @test all(row -> row.fixed && row.lower == row.median == row.upper == 0, steps)
    end
    for family in (:gmfrm, :mgmfrm)
        block, facet = family === :gmfrm ? (:rater_steps, :rater) : (:item_steps, :item)
        rows = B._posterior_plot_data(fits[family]; block).rows
        @test getproperty.(rows, :parameter) ==
            ["$(facet)_step[$facet=$level,m=$m]" for level in 1:2 for m in 1:3]
        for level in 1:2
            steps = [only(row for row in rows if row.parameter == "$(facet)_step[$facet=$level,m=$m]") for m in 1:3]
            @test steps[1].fixed && steps[1].median == 0
            @test steps[3].median ≈ -steps[2].median
            @test steps[3].lower ≈ -steps[2].upper
            @test !steps[3].fixed
        end
    end
    labelled = reporting_fit(:mgmfrm; dimension_labels = ["Comprehensibility", "Accentedness"])
    for scale in (:model, :raw)
        selected = B._posterior_plot_data(labelled; scale, dimension = "Accentedness")
        @test all(row -> row.dimension == 2, selected.rows)
        @test selected.rows == B._posterior_plot_data(labelled; scale, dimension = 2).rows
        @test Set(selected.groups) == Set([(:person, 2), (:item_dimension_discrimination, 2)])
    end
    for options in ((; scale = :unknown), (; interval = NaN), (; interval = 0),
            (; interval = 1), (; block = :unknown), (; dimension = 1),
            (; parameters = ["absent"]), (; parameters = String[]),
            (; parameters = [1]), (; parameters = ["person[1]", "person[1]"]),
            (; max_parameters = 0))
        @test_throws ArgumentError B._posterior_plot_data(fits[:mfrm]; options...)
    end
    @test_throws ArgumentError B._posterior_plot_data(labelled; dimension = "absent")
    @test_throws MethodError B._posterior_plot_data(labelled; dimension_labels = ["override"])
    @test_throws ArgumentError B._posterior_plot_data(labelled; dimension = 0)
    @test_throws ArgumentError B._posterior_plot_data(labelled; block = :item, dimension = 2)
    invalid = deepcopy(fits[:mfrm]); invalid.draws[1, 1] = NaN
    @test_throws ArgumentError B._posterior_plot_data(invalid)
end

const chain_fits = Dict(family => reporting_fit(family; chains = 2, ndraws = 20)
    for family in (:mfrm, :gmfrm, :mgmfrm))
@testset "retained trace and pooled-rank coordinates" begin
    @test :plot_diagnostics ∉ names(B)
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        error = try B.plot_diagnostics(fits[:mfrm]); catch err; err; end
        @test error isa ArgumentError
        @test occursin("using CairoMakie", sprint(showerror, error))
    end
    tied = B._plot_rank_histogram([1.0, 2, 2, 4, 5, 6], [1, 1, 1, 2, 2, 2], 2, 3)
    @test tied.ranks == [1, 2.5, 2.5, 4, 5, 6]
    @test tied.counts == [1 0; 2 1; 0 2]
    @test tied.frequencies == tied.counts ./ 3
    @test tied.pooled == [1, 3, 2] ./ 6
    @test vec(sum(tied.frequencies; dims = 1)) ≈ ones(2)
    mixed = B._plot_rank_histogram(repeat([1., 2, 3, 4], 2), repeat([1, 2]; inner = 4), 2, 4)
    @test mixed.frequencies[:, 1] == mixed.frequencies[:, 2]
    separated = B._plot_rank_histogram(collect(1.:8), repeat([1, 2]; inner = 4), 2, 4)
    @test separated.counts == [2 0; 2 0; 0 2; 0 2]
    for (family, fit) in chain_fits, scale in (:raw, :model)
        data = B._diagnostic_plot_data(fit; scale, block = :person)
        @test_throws MethodError B._diagnostic_plot_data(fit; dimension_labels = ["override"])
        source = family === :mfrm || scale === :raw ? fit.draws : fit.direct_draws
        @test data.nchains == 2 && data.per_chain == 20
        @test data.chain_ids == repeat([1, 2]; inner = 20)
        @test data.iterations == repeat(collect(1:20), 2)
        @test data.scale === scale
        @test isequal(data.summary, diagnostics(fit).summary)
        @test all(row -> row.values == source[:, findfirst(==(row.parameter),
            family === :mfrm ? fit.design.parameter_names : scale === :raw ?
            fit.diagnostic_surface.raw_parameter_names : fit.diagnostic_surface.direct_parameter_names)], data.rows)
        @test all(row -> vec(sum(row.ranks.counts; dims = 1)) == [20, 20], data.rows)
        @test all(row -> occursin("R-hat", row.status) && occursin("tail ESS", row.status), data.rows)
        names = reverse(getproperty.(data.rows, :parameter))
        @test getproperty.(B._diagnostic_plot_data(fit; scale, parameters = names).rows, :parameter) == names
        single = B._diagnostic_plot_data(fits[family]; scale, block = :person)
        @test all(row -> row.ranks === nothing && occursin("two chains", row.rank_note), single.rows)
        @test all(row -> occursin("unavailable", row.status), single.rows)
        broken = deepcopy(fit); broken.chain_ids[1] = 2
        @test_throws ArgumentError B._diagnostic_plot_data(broken; block = :person)
        broken = deepcopy(fit); broken.iterations[1] = 2
        @test_throws ArgumentError B._diagnostic_plot_data(broken; block = :person)
        absent = deepcopy(fit); empty!(absent.sampler_stats)
        @test all(note -> occursin("divergences unavailable", note) && occursin("E-BFMI unavailable", note),
            B._diagnostic_plot_data(absent; block = :person).sampler_notes)
    end
    fixed = B._diagnostic_plot_data(chain_fits[:mfrm]; scale = :model, parameters = "rater[1]")
    @test only(fixed.rows).fixed && only(fixed.rows).ranks === nothing
    @test occursin("not applicable", only(fixed.rows).status)
    derived = B._diagnostic_plot_data(chain_fits[:mfrm]; scale = :model, parameters = "step[item=1,2]")
    @test only(derived.rows).values == -chain_fits[:mfrm].draws[:, findfirst(==("step[item=1,1]"), chain_fits[:mfrm].design.parameter_names)]
    @test occursin("Derived coordinate", only(derived.rows).status)
    @test only(derived.rows).ranks !== nothing
    for (family, facet, block) in ((:gmfrm, :rater, :rater_steps), (:mgmfrm, :item, :item_steps))
        data = B._diagnostic_plot_data(chain_fits[family]; scale = :model, block)
        @test data.rows[1].fixed && data.rows[1].ranks === nothing
        @test data.rows[3].values == -data.rows[2].values
        @test occursin("Derived coordinate", data.rows[3].status)
    end
    constant = deepcopy(chain_fits[:mfrm]); constant.draws[:, 1] .= 0
    data = B._diagnostic_plot_data(constant; parameters = "person[1]")
    @test !only(data.rows).fixed && only(data.rows).ranks === nothing
    @test occursin("Constant sampled", only(data.rows).rank_note)
    @test occursin("degenerate", only(data.rows).status)
    warning = deepcopy(chain_fits[:mfrm])
    warning.sampler_stats[1] = merge(warning.sampler_stats[1], (; numerical_error = true))
    data = B._diagnostic_plot_data(warning; parameters = "person[2]")
    @test data.summary.flag === :sampler_warning
    @test occursin("divergences 1", data.sampler_notes[1])
    @test occursin("MCMC warnings", data.diagnostic)
    one_draw = B._diagnostic_plot_data(reporting_fit(:mfrm; chains = 2, ndraws = 1); block = :person)
    @test one_draw.bins == 2
    @test all(row -> occursin("unavailable", row.status), one_draw.rows)
    labelled = reporting_fit(:mgmfrm; chains = 2, ndraws = 20,
        dimension_labels = ["Comprehensibility", "Accentedness"])
    @test all(row -> row.dimension == 2, B._diagnostic_plot_data(labelled; dimension = "Accentedness").rows)
    for options in ((; bins = 0), (; bins = -2), (; bins = true), (; bins = 1.5), (; max_parameters = 1),
            (; scale = :unknown), (; parameters = ["absent"]), (; dimension = 1.5))
        @test_throws ArgumentError B._diagnostic_plot_data(chain_fits[:mfrm]; options...)
    end
    @test B._diagnostic_plot_data(chain_fits[:mfrm]; bins = 1000, block = :person).bins == 40
    for family in (:gmfrm, :mgmfrm)
        custom = reporting_fit(family; chains = 2, ndraws = 20, rhat_threshold = 1.05, ess_threshold = 10)
        data = B._diagnostic_plot_data(custom; block = :person)
        @test (data.summary.rhat_threshold, data.summary.ess_threshold) == (1.05, 10)
    end
    @test B._plot_rank_histogram(collect(1.:4), [1, 1, 2, 2], 2, 1).counts == [2 2]
    four_categories = FacetData((; person = [1, 1, 1, 2, 2, 2], item = [1, 1, 2, 1, 2, 2],
        rater = [1, 2, 1, 1, 2, 1], score = [0, 1, 2, 3, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score)
    overflow = reporting_fit(:mfrm; data = four_categories)
    overflow.draws[:, overflow.design.blocks[:thresholds]] .= floatmax(Float64)
    @test_throws ArgumentError B._diagnostic_plot_data(overflow; scale = :model, block = :thresholds)
    legacy = chain_fits[:gmfrm]
    surface = merge(legacy.diagnostic_surface, (; summary = merge(legacy.diagnostic_surface.summary,
        (; diagnostic_contract = :legacy))))
    stale = typeof(legacy)((field === :diagnostic_surface ? surface : getfield(legacy, field)
        for field in fieldnames(typeof(legacy)))...)
    @test_throws ArgumentError B._diagnostic_plot_data(stale; block = :person)
end

@testset "conditional category predictive figures" begin
    @test :plot_predictive ∉ names(B)
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        error = try B.plot_predictive(fits[:mfrm]); catch err; err; end
        @test error isa ArgumentError
        @test occursin("using CairoMakie", sprint(showerror, error))
    end
    for probabilities in ([NaN, NaN], [0., 0.], Float64[], [-0.1, 1.1], [0.1, 0.2], [Inf, 0.])
        rng = MersenneTwister(13)
        @test_throws ArgumentError B._sample_category_index(rng, probabilities)
        @test rand(rng) == rand(MersenneTwister(13))
    end
    probabilities = [0.1, 0.2, 0.7]
    rng = MersenneTwister(14)
    expected = searchsortedfirst.(Ref(cumsum(probabilities)), rand(MersenneTwister(14), 100))
    @test [B._sample_category_index(rng, probabilities) for _ in 1:100] == expected
    overflow = deepcopy(fits[:mfrm]); overflow.draws[:, 1] .= floatmax(Float64)
    @test_throws ArgumentError posterior_predict(overflow; draw_indices = [1], rng = MersenneTwister(15))
    for (family, fit) in fits
        original = copy(fit.draws)
        for selection in ((;), (; ndraws = 40), (; draw_indices = [4, 1, 4, 2]))
            data = B._predictive_plot_data(fit; seed = 42, interval = 0.8, selection...)
            check = posterior_predictive_check(fit; rng = MersenneTwister(42), selection...)
            summary = filter(row -> row.statistic === :category_proportion,
                predictive_check_summary(check; interval = 0.8))
            @test data.rows == predictive_check_plot_data(summary)
            @test data.draw_indices == check.draw_indices
            @test data.n_replicates == size(check.replicated_scores, 1)
            @test (data.n_retained, data.n_unique_draws) == (size(fit.draws, 1), length(unique(check.draw_indices)))
            @test data.n_observations == fit.design.spec.data.n
            @test (data.rng.algorithm, data.rng.seed, data.rng.replayable) == (:MersenneTwister, 42, true)
            @test data.rows == B._predictive_plot_data(fit; seed = 42, interval = 0.8, selection...).rows
            for (column, row) in enumerate(data.rows)
                category = fit.design.spec.data.category_levels[column]
                proportions = [count(==(category), scores) / length(scores) for scores in eachrow(check.replicated_scores)]
                @test row.level == category
                @test row.observed == count(==(category), fit.design.spec.data.score) / data.n_observations
                @test row.replicated_mean ≈ mean(proportions)
                @test row.replicated_lower ≈ quantile(proportions, 0.1)
                @test row.replicated_upper ≈ quantile(proportions, 0.9)
            end
            @test sum(row.observed for row in data.rows) ≈ 1
            @test sum(row.replicated_mean for row in data.rows) ≈ 1
            wider = B._predictive_plot_data(fit; seed = 42, interval = 0.95, selection...)
            @test wider.draw_indices == data.draw_indices
            @test all(a.replicated_mean == b.replicated_mean && a.replicated_lower <= b.replicated_lower &&
                a.replicated_upper >= b.replicated_upper for (a, b) in zip(wider.rows, data.rows))
        end
        @test fit.draws == original
        all_draws = B._predictive_plot_data(fit)
        @test all_draws.draw_indices == 1:size(fit.draws, 1)
        @test occursin("All retained", all_draws.selection)
        @test occursin("with replacement", B._predictive_plot_data(fit; ndraws = 5).selection)
        @test occursin("Explicit", B._predictive_plot_data(fit; draw_indices = [2, 2]).selection)
        @test all_draws.diagnostic != "No warnings under the fit's MCMC diagnostic thresholds"
        cmdstan_label = reporting_fit(family; backend = :cmdstan)
        @test B._predictive_plot_data(cmdstan_label).rows == all_draws.rows
    end
    Random.seed!(120)
    expected = rand()
    Random.seed!(120)
    B._predictive_plot_data(fits[:mfrm])
    @test rand() == expected
    unused_data = FacetData((; person = [1, 1, 1, 2, 2, 2], item = [1, 1, 2, 1, 2, 2],
        rater = [1, 2, 1, 1, 2, 1], score = [0, 2, 0, 2, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
    for family in (:mfrm, :gmfrm, :mgmfrm)
        unused = reporting_fit(family; data = unused_data)
        data = B._predictive_plot_data(unused; ndraws = 80, seed = 23)
        @test getproperty.(data.rows, :level) == [0, 1, 2, 3]
        @test getproperty.(data.rows[[2, 4]], :observed) == [0, 0]
        @test all(row -> row.replicated_mean > 0, data.rows[[2, 4]])
    end
    for options in ((; interval = NaN), (; interval = 0), (; interval = 1),
            (; ndraws = 0), (; ndraws = 2, draw_indices = [1]), (; draw_indices = Int[]),
            (; draw_indices = [0]), (; draw_indices = [5]))
        @test_throws ArgumentError B._predictive_plot_data(fits[:mfrm]; options...)
    end
    broken = deepcopy(fits[:mfrm]); broken.chain_ids[1] = 2
    @test_throws ArgumentError B._predictive_plot_data(broken)
    invalid = deepcopy(fits[:mfrm]); invalid.draws[1, 1] = NaN
    @test_throws ArgumentError B._predictive_plot_data(invalid)
    warning = deepcopy(chain_fits[:mfrm])
    warning.sampler_stats[1] = merge(warning.sampler_stats[1], (; numerical_error = true))
    @test occursin("MCMC warnings", B._predictive_plot_data(warning; draw_indices = [40]).diagnostic)
    @test all(row.n_replicates == 1 for row in B._predictive_plot_data(fits[:mfrm]; draw_indices = [2]).rows)
end

const wright_fits = let
    binary = FacetData((; person = [1, 1, 2, 2], item = [1, 2, 1, 2],
        rater = [1, 2, 2, 1], score = [0, 1, 1, 0]);
        person = :person, item = :item, rater = :rater, score = :score)
    anchors = [(; block = :rater, level = 2, value = 0.75, type = :hard),
        (; block = :item, level = 2, value = 1.25, type = :hard)]
    labelled = FacetData((; person = repeat(["Speaker with a longer label A", "Speaker with a longer label B"]; inner = 3),
        item = ["Word A", "Word A", "Word B", "Word A", "Word B", "Word B"],
        rater = ["Rater A", "Rater B", "Rater A", "Rater A", "Rater B", "Rater A"],
        score = [0, 2, 0, 2, 0, 2]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
    Dict(:pcm => fits[:mfrm], :rsm => reporting_fit(:mfrm; thresholds = :rating_scale),
        :binary => reporting_fit(:mfrm; data = binary),
        :anchored => reporting_fit(:mfrm; anchors),
        :binary_anchored => reporting_fit(:mfrm; data = binary, anchors),
        :labelled => reporting_fit(:mfrm; data = labelled))
end

@testset "shared-scale Wright-map coordinates" begin
    @test :plot_wright ∉ names(B)
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        error = try B.plot_wright(fits[:mfrm]); catch err; err; end
        @test error isa ArgumentError
        @test occursin("using CairoMakie", sprint(showerror, error))
    end
    for family in (:gmfrm, :mgmfrm)
        error = try B.plot_wright(fits[family]); catch err; err; end
        @test error isa ArgumentError
        @test occursin("stable MFRM", sprint(showerror, error))
    end
    for (name, fit) in wright_fits
        data = B._wright_plot_data(fit; interval = 0.8)
        @test isequal(data.rows, wright_map_data(fit; interval = 0.8))
        @test data.groups == [:person, :rater, :item, :threshold]
        @test data.n_draws == size(fit.draws, 1)
        @test data.diagnostic == B._plot_diagnostic_note(diagnostics(fit).summary)
        nsteps = length(fit.design.spec.data.category_levels) - 1
        for row in data.rows
            if row.component === :facet_measure
                values = ismissing(row.parameter_index) ? fill(row.fixed_value, data.n_draws) :
                    fit.draws[:, row.parameter_index]
            else
                item = only(r for r in data.rows if r.facet === :item && r.level_index == row.item_index)
                item_values = item.is_fixed ? fill(item.fixed_value, data.n_draws) : fit.draws[:, item.parameter_index]
                offset = fit.design.spec.thresholds === :rating_scale ? 0 : (row.item_index - 1) * (nsteps - 1)
                columns = fit.design.blocks[:thresholds][(offset + 1):(offset + nsteps - 1)]
                steps = nsteps == 1 ? zeros(data.n_draws) : row.step < nsteps ? fit.draws[:, columns[row.step]] :
                    -vec(sum(fit.draws[:, columns]; dims = 2))
                values = item_values + steps
                @test row.is_fixed == (item.is_fixed && nsteps == 1)
                @test isequal(row.fixed_value, row.is_fixed ? item.fixed_value : missing)
                @test (row.from_category, row.to_category) ==
                    (fit.design.spec.data.category_levels[row.step], fit.design.spec.data.category_levels[row.step + 1])
            end
            @test row.position_median ≈ median(values)
            @test row.position_lower ≈ quantile(values, 0.1)
            @test row.position_upper ≈ quantile(values, 0.9)
            @test !row.is_fixed || row.position_lower == row.position_upper == row.fixed_value
        end
        selected = B._wright_plot_data(fit; facets = (:item, :rater), include_thresholds = false)
        @test selected.groups == [:item, :rater]
        @test length(selected.rows) == 4
        @test length(B._wright_plot_data(fit; facets = :person).rows) == 2 + 2 * nsteps
    end
    # Correlated item/step draws: quantiles of their sums differ from sums of marginal quantiles.
    joint = deepcopy(wright_fits[:rsm])
    joint.draws[:, only(joint.design.blocks[:item])] = [0, 1, 2, 10]
    joint.draws[:, first(joint.design.blocks[:thresholds])] = [10, 2, 1, 0]
    row = only(r for r in B._wright_plot_data(joint).rows if r.facet === :threshold && r.item == 2 && r.step == 1)
    @test row.position_median == 6.5
    @test row.position_median != row.item_measure_median + row.threshold_step_median
    @test row.position_upper != row.item_measure_upper + row.threshold_step_upper
    @test !row.is_fixed
    constant = deepcopy(wright_fits[:binary]); constant.draws .= 0
    row = only(r for r in B._wright_plot_data(constant).rows if r.facet === :threshold && r.item == 2)
    @test !row.is_fixed && row.position_lower == row.position_upper
    for name in (:pcm, :rsm)
        fit = wright_fits[name]; design = fit.design
        params = copy(fit.draws[1, :])
        person = design.blocks[:person][2]; item = only(design.blocks[:item]); rater = only(design.blocks[:rater])
        step = params[design.spec.thresholds === :rating_scale ? first(design.blocks[:thresholds]) : last(design.blocks[:thresholds])]
        params[person] = params[item] + step + params[rater]
        p = predictive_probabilities(design, reshape(params, 1, :))
        @test p[1, 5, 1] ≈ p[1, 5, 2]
        for (column, sign) in ((person, 1), (item, -1), (rater, -1))
            shifted = copy(params); shifted[column] += 0.4
            q = predictive_probabilities(design, reshape(shifted, 1, :))
            @test log(q[1, 5, 2] / q[1, 5, 1]) ≈ sign * 0.4
        end
    end
    overflow = deepcopy(fits[:mfrm])
    overflow.draws[1, only(overflow.design.blocks[:item])] = floatmax(Float64)
    overflow.draws[1, last(overflow.design.blocks[:thresholds])] = floatmax(Float64)
    @test_throws ArgumentError wright_map_data(overflow)
    @test_throws ArgumentError diagnostic_map_data(overflow)
    @test_throws ArgumentError B._wright_plot_data(overflow)
    broken = deepcopy(fits[:mfrm]); broken.iterations[1] = 2
    @test_throws ArgumentError B._wright_plot_data(broken)
    invalid = deepcopy(fits[:mfrm]); invalid.draws[1, 1] = NaN
    @test_throws ArgumentError B._wright_plot_data(invalid)
    for options in ((; facets = :unknown), (; facets = ()), (; facets = (:item, :item)),
            (; interval = NaN), (; interval = 0), (; interval = 1),
            (; max_levels = 0), (; max_levels = true), (; max_levels = 1.5), (; max_levels = 2))
        @test_throws ArgumentError B._wright_plot_data(fits[:mfrm]; options...)
    end
    @test length(B._wright_plot_data(fits[:mfrm]; max_levels = 10).rows) == 10
    @test length(B._wright_plot_data(fits[:mfrm]; facets = :person, include_thresholds = false, max_levels = 2).rows) == 2
    warning = deepcopy(chain_fits[:mfrm])
    warning.sampler_stats[1] = merge(warning.sampler_stats[1], (; numerical_error = true))
    @test occursin("MCMC warnings", B._wright_plot_data(warning; facets = :person, include_thresholds = false).diagnostic)
    @test isequal(B._wright_plot_data(reporting_fit(:mfrm; backend = :cmdstan)).rows, B._wright_plot_data(fits[:mfrm]).rows)
    Random.seed!(121); expected = rand(); Random.seed!(121)
    B._wright_plot_data(fits[:mfrm])
    @test rand() == expected
end
end
