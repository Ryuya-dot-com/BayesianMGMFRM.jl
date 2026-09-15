module MFRMFixedQSampleChecks

using Test, BayesianMGMFRM, Serialization, Statistics, Random
const B = BayesianMGMFRM
include("test_groups.jl")
include("fixtures/fixed_q_report_bundle.jl")
include("fixtures/fixed_q_result.jl")

function sample_target(dimensions)
    cells = [(p, i, r) for p in 1:2 for i in 1:(2 * dimensions) for r in 1:3]
    data = FacetData((; person = [p for (p, i, r) in cells],
        item = [i for (p, i, r) in cells], rater = [Symbol("judge_$r") for (p, i, r) in cells],
        score = [mod(p + i + r, 4) for (p, i, r) in cells]);
        person = :person, item = :item, rater = :rater, score = :score, category_levels = 0:3)
    q = [cld(i, 2) == d for i in 1:(2 * dimensions), d in 1:dimensions]
    dimensions == 2 && (q[2, 2] = true)
    spec = mfrm_spec(data; family = :mgmfrm, dimensions,
        thresholds = :partial_credit, q_matrix = q,
        dimension_labels = ["Ability $d" for d in 1:dimensions])
    return B._MFRMFixedQReferenceLogDensity(spec;
        prior = MFRMPrior(person_sd = 0.7, rater_sd = 0.4, item_sd = 0.6, step_sd = 0.5))
end

const targets = [sample_target(d) for d in (2, 3)]
const controls = (; ndraws = 12, warmup = 10, chains = 2, seed = 9174,
    step_size = 0.03, max_depth = 4, init_jitter = 0.02)

# Independent unit-logit adjacent-category formula for this four-category fixture.
function unit_probabilities(target, draws)
    spec, blocks = target.base.design.spec, target.blueprint.blocks
    data = spec.data
    probabilities = zeros(size(draws, 1), data.n, 4)
    for (draw, params) in enumerate(eachrow(draws))
        theta = reshape(params[blocks[:person]], spec.dimensions, :)
        rater = [params[blocks[:rater_free]]; -sum(params[blocks[:rater_free]])]
        item = params[blocks[:item]]
        steps = reshape(params[blocks[:item_steps]], 2, :)
        for row in 1:data.n
            i, p, r = data.item[row], data.person[row], data.rater[row]
            location = sum(theta[d, p] for d in 1:spec.dimensions if spec.q_matrix[i, d]) - item[i] - rater[r]
            eta = [0.0; cumsum(location .- [steps[:, i]; -sum(steps[:, i])])]
            weights = exp.(eta .- maximum(eta))
            probabilities[draw, row, :] .= weights ./ sum(weights)
        end
    end
    return probabilities
end

@testset "fixed-Q MFRM unit-logit predictive probabilities (no fitting)" begin
    for target in targets
        p = B.LogDensityProblems.dimension(target)
        draws = reshape(sin.(1.0:(5p)), 5, p)
        direct = B._mfrm_fixed_q_predictive_draws(target, draws)
        probabilities = B._mgmfrm_predictive_probabilities_direct(target.base.design, direct)
        expected = unit_probabilities(target, draws)
        @test probabilities ≈ expected atol = 1e-12
        @test all(isfinite, probabilities) && all(0 .<= probabilities .<= 1)
        @test dropdims(sum(probabilities; dims = 3); dims = 3) ≈ ones(5, target.base.design.spec.data.n)
        for draw in 1:5
            @test log.([probabilities[draw, row, score + 1]
                for (row, score) in enumerate(target.base.design.spec.data.score)]) ≈
                B._mfrm_fixed_q_pointwise(target, draws[draw, :])
        end
        @test_throws ArgumentError B._mfrm_fixed_q_predictive_draws(target, zeros(0, p))
        @test_throws ArgumentError B._mfrm_fixed_q_predictive_draws(target, zeros(2, p - 1))
        @test_throws ArgumentError B._mfrm_fixed_q_predictive_draws(target, fill(NaN, 2, p))
        # Declared but unobserved categories must survive the shared check assembly.
        spec = deepcopy(target.base.design.spec)
        spec.data.score .= 0
        replicated = repeat(reshape(collect(0:3), 4, 1), 1, spec.data.n)
        check = B._posterior_predictive_check(spec, replicated, collect(1:4))
        rows = filter(row -> row.statistic === :category_proportion, predictive_check_summary(check))
        @test getproperty.(rows, :level) == [0, 1, 2, 3]
        @test getproperty.(rows, :observed) == [1, 0, 0, 0]
        @test getproperty.(rows, :replicated_mean) == fill(0.25, 4)
    end
end

@testset "fixed-Q MFRM unit-logit reconstruction (no fitting)" begin
    for target in targets
        p = B.LogDensityProblems.dimension(target)
        draws = reshape(sin.(1.0:(5p)), 5, p)
        rows = B._mfrm_fixed_q_model_coordinates(target, draws)
        lookup = Dict(row.parameter => row for row in rows)
        spec, blocks = target.base.design.spec, target.blueprint.blocks
        @test length(rows) == (spec.dimensions == 2 ? 35 : 48)
        for block in (:person, :item, :item_steps), i in blocks[block]
            row = lookup[target.blueprint.parameter_names[i]]
            @test row.values == draws[:, i]
            @test !row.fixed
        end
        raters = filter(row -> row.block === :rater, rows)
        @test getproperty.(raters, :parameter) == ["rater[judge_$r]" for r in 1:3]
        @test raters[1].values == draws[:, first(blocks[:rater_free])]
        @test raters[2].values == draws[:, last(blocks[:rater_free])]
        @test raters[3].values ≈ -vec(sum(draws[:, blocks[:rater_free]]; dims = 2))
        @test all(row -> !row.fixed, raters)
        @test getproperty.(raters, :derived) == [false, false, true]
        @test all(abs.(sum(row.values for row in raters)) .< 1e-12)
        for item in spec.data.item_levels
            steps = [lookup["item_step[item=$item,m=$m]"] for m in 1:4]
            @test steps[1].fixed && steps[1].values == zeros(5)
            @test !steps[4].fixed && steps[4].values == -(steps[2].values + steps[3].values)
            @test getproperty.(steps, :derived) == [false, false, false, true]
            @test all(abs.(sum(row.values for row in steps)) .< 1e-12)
        end
        coefficients = filter(row -> row.block in (:item_dimension_discrimination, :rater_consistency), rows)
        @test all(row -> row.fixed && row.values == ones(5), coefficients)
        @test count(row -> row.block === :item_dimension_discrimination, rows) == sum(spec.q_matrix)
        @test [row.dimension for row in rows if row.block === :person] == repeat(1:spec.dimensions, 2)
        @test_throws ArgumentError B._mfrm_fixed_q_model_coordinates(target, draws[:, 1:end-1])
        @test_throws ArgumentError B._mfrm_fixed_q_model_coordinates(target, fill(NaN, 5, p))
    end
end

@testset "fixed-Q MFRM controls and identities" begin
    @test B.LogDensityProblems.dimension.(targets) == [18, 26]
    for target in targets
        @test_throws ArgumentError B._mfrm_fixed_q_sample(target; backend = :julia)
        for backend in (:advancedhmc, :cmdstan)
            @test_throws ArgumentError B._mfrm_fixed_q_sample(target; backend, ndraws = 0)
            @test_throws ArgumentError B._mfrm_fixed_q_sample(target, [0.0]; backend)
            @test_throws ArgumentError B._mfrm_fixed_q_sample(target,
                fill(NaN, B.LogDensityProblems.dimension(target)); backend)
        end
        changed = B._MFRMFixedQReferenceLogDensity(target.base.design.spec;
            prior = MFRMPrior(person_sd = 0.8, rater_sd = 0.4, item_sd = 0.6, step_sd = 0.5))
        @test B._mfrm_fixed_q_identity(changed) != B._mfrm_fixed_q_identity(target)
        normalized = B._MGMFRMNormalizedPriorLogDensity(target.base.design.spec;
            prior_model = :exchangeable, scales = (; person_sd = 0.7, rater_sd = 0.4,
                item_sd = 0.6, log_discrimination_sd = 0.3, log_consistency_sd = 0.35, step_sd = 0.5))
        @test B._mfrm_fixed_q_identity(target) != B._mgmfrm_normalized_prior_identity(normalized)
    end
    @test B._mfrm_fixed_q_identity(targets[1]) != B._mfrm_fixed_q_identity(targets[2])
end

@testset "fixed-Q MFRM CmdStan parser checks both densities (synthetic)" begin
    target = first(targets)
    params = collect(range(-0.3, 0.4; length = B.LogDensityProblems.dimension(target)))
    pointwise = B._mfrm_fixed_q_pointwise(target, params)
    lp = B.LogDensityProblems.logdensity(target, params)
    header = ["lp__", "accept_stat__", "stepsize__", "treedepth__",
        "n_leapfrog__", "divergent__", "energy__",
        ["beta.$i" for i in eachindex(params)]..., ["log_lik.$i" for i in eachindex(pointwise)]...]
    values = [lp, 0.8, 0.03, 1.0, 1.0, 0.0, 10.0, params..., pointwise...]
    mktempdir() do directory
        path = joinpath(directory, "synthetic.csv")
        write_csv() = write(path, join(header, ',') * "\n" * join(values, ',') * "\n")
        write_csv()
        parsed = B._cmdstan_generalized_chain_result(path, target, 2, 1)
        @test parsed.draws == reshape(params, 1, :)
        @test parsed.logps ≈ [lp]
        @test only(parsed.stats).stan_lp == lp
        values[1] += 0.5
        write_csv()
        error = try
            B._cmdstan_generalized_chain_result(path, target, 2, 1)
            nothing
        catch err
            err
        end
        @test error isa CmdStanError && error.reason === :log_posterior_mismatch
        values[1] = lp
        values[end] += 0.5
        write_csv()
        @test_throws CmdStanError B._cmdstan_generalized_chain_result(path, target, 2, 1)
    end
end

function check_samples(target, backend, directory; record_warmup = true)
    options = backend === :cmdstan ? (; cmdstan_cache_dir = joinpath(directory, "compile")) : (;)
    result = B._mfrm_fixed_q_sample(target; backend, record_warmup, controls..., options...)
    (; record) = result
    run, identity = record.run, B._mfrm_fixed_q_identity(target)
    @test !result.public_fit && result.parameter_space === :unit_logit
    @test result.parameter_names == target.blueprint.parameter_names
    @test size(run.draws) == (24, length(result.parameter_names))
    @test run.chain_ids == repeat(1:2; inner = 12)
    @test run.iterations == repeat(1:12; outer = 2)
    @test run.backend === backend && run.sampler === :nuts
    @test [row.parameter for row in result.posterior_summary] == result.parameter_names
    @test [row.mean for row in result.posterior_summary] ≈ vec(mean(run.draws; dims = 1))
    @test all(row -> row.parameter_space === :unit_logit, result.diagnostics.parameter_rows)
    @test any(row -> row.flag !== :ok, result.diagnostics.parameter_rows)
    @test all(row -> row.coverage === (record_warmup ? :recorded : :not_recorded),
        result.warmup_diagnostics)
    for (i, params) in enumerate(eachrow(run.draws))
        @test run.logdensities[i] ≈ B.LogDensityProblems.logdensity(target, params) atol = 1e-9
        @test run.logdensities[i] ≈ sum(B._mfrm_fixed_q_pointwise(target, params)) +
            logprior(target, params) atol = 1e-9
        if backend === :cmdstan
            @test run.sampler_stats[i].stan_lp ≈ run.logdensities[i] atol = 1e-8
        end
    end
    path = joinpath(directory, "samples.jls")
    B._save_mfrm_fixed_q_samples(path, result)
    loaded = B._load_mfrm_fixed_q_samples(path; expected_identity = identity)
    @test isequal(loaded.record.run, run)
    @test isequal(loaded.record.prior, record.prior)
    @test isequal(loaded.posterior_summary, result.posterior_summary)
    @test isequal(loaded.diagnostics, result.diagnostics)
    @test isequal(loaded.warmup_diagnostics, result.warmup_diagnostics)
    @test loaded.parameter_names == result.parameter_names
    @test loaded.model === :mfrm_fixed_q
    @test isequal(loaded.model_coordinates, result.model_coordinates)
    @test isequal(loaded.model_posterior_summary, result.model_posterior_summary)
    check_fixed_q_result(loaded)
    model_metrics = Dict(row.parameter => row for row in result.diagnostics.model_parameter_rows)
    for row in result.model_coordinates
        @test model_metrics[row.parameter].quality_gate_applicable == !row.fixed
        if row.fixed
            @test model_metrics[row.parameter].flag === :structurally_fixed
        end
    end
    plot_data = B._mfrm_fixed_q_plot_data(result; interval = 0.9)
    @test plot_data.model === :mfrm_fixed_q && plot_data.target_identity == identity
    @test plot_data.backend === backend && plot_data.diagnostic != B._plot_diagnostic_note((; flag = :ok))
    @test isequal(B._mfrm_fixed_q_plot_data(loaded; interval = 0.9), plot_data)
    values = Dict(row.parameter => row.values for row in result.model_coordinates)
    for row in plot_data.rows
        @test row.median ≈ median(values[row.parameter])
        @test row.lower ≈ quantile(values[row.parameter], 0.05)
        @test row.upper ≈ quantile(values[row.parameter], 0.95)
    end
    selected = B._mfrm_fixed_q_plot_data(result; block = :person, dimension = 2)
    @test length(selected.rows) == 2 && all(row -> row.dimension == 2, selected.rows)
    @test selected.rows == B._mfrm_fixed_q_plot_data(result; block = :person,
        dimension = string(target.base.design.spec.dimension_labels[2])).rows
    @test selected.diagnostic == plot_data.diagnostic # Warnings include unselected parameters.
    reversed = reverse([row.parameter for row in selected.rows])
    @test [row.parameter for row in B._mfrm_fixed_q_plot_data(result; parameters = reversed).rows] == reversed
    for options in ((; interval = NaN), (; scale = :raw), (; scale = :unknown),
            (; dimension = 0), (; dimension = true), (; block = :rater, dimension = 2),
            (; parameters = ["missing"]), (; parameters = String[]),
            (; parameters = [first(reversed), first(reversed)]), (; max_parameters = 1))
        @test_throws ArgumentError B._mfrm_fixed_q_plot_data(result; options...)
    end
    tampered = deepcopy(result)
    tampered.model_coordinates[1].values[1] = NaN
    @test isequal(B._mfrm_fixed_q_plot_data(tampered; interval = 0.9), plot_data)
    @test_throws MethodError B.plot_posterior(result) # Public fit support has not changed.
    @test_throws MethodError B._mfrm_fixed_q_plot_data(result; dimension_labels = ["override"])
    derived_names = ["rater[judge_3]", "item_step[item=1,m=4]"]
    traces = B._mfrm_fixed_q_diagnostic_plot_data(result; parameters = derived_names, bins = 1000)
    @test traces.model === :mfrm_fixed_q && traces.backend === backend
    @test traces.target_identity == identity && traces.scale === :model
    @test traces.nchains == 2 && traces.per_chain == controls.ndraws && traces.bins == 24
    @test traces.chain_ids == run.chain_ids && traces.iterations == run.iterations
    @test isequal(traces.summary, result.diagnostics.summary)
    @test isequal(B._mfrm_fixed_q_diagnostic_plot_data(loaded;
        parameters = derived_names, bins = 1000), traces)
    @test [row.parameter for row in traces.rows] == derived_names
    @test length(traces.sampler_notes) == 2 && all(note -> occursin("divergences", note) &&
        occursin("max-depth hits", note) && occursin("E-BFMI", note), traces.sampler_notes)
    for row in traces.rows
        @test row.derived && !row.fixed && row.values == values[row.parameter]
        @test startswith(row.status, "Derived from retained draws; R-hat")
        @test row.ranks.ranks == [count(v -> v < x, row.values) + (count(==(x), row.values) + 1) / 2
            for x in row.values]
        @test vec(sum(row.ranks.counts; dims = 1)) == [12, 12]
        @test vec(sum(row.ranks.frequencies; dims = 1)) ≈ ones(2)
        @test sum(row.ranks.pooled) ≈ 1
    end
    fixed = B._mfrm_fixed_q_diagnostic_plot_data(result; parameters = "item_step[item=1,m=1]")
    @test only(fixed.rows).fixed && !only(fixed.rows).derived && only(fixed.rows).ranks === nothing
    @test occursin("baseline step", only(fixed.rows).status) && occursin("not applicable", only(fixed.rows).rank_note)
    @test fixed.diagnostic == traces.diagnostic && isequal(fixed.summary, traces.summary)
    person_traces = B._mfrm_fixed_q_diagnostic_plot_data(result; block = :person,
        dimension = string(target.base.design.spec.dimension_labels[2]))
    @test length(person_traces.rows) == 2 && all(row -> row.dimension == 2, person_traces.rows)
    @test person_traces.diagnostic == traces.diagnostic
    @test isequal(B._mfrm_fixed_q_diagnostic_plot_data(tampered;
        parameters = derived_names, bins = 1000), traces)
    bad_chains = deepcopy(result)
    bad_chains.record.run.chain_ids[1] = 99
    @test_throws ArgumentError B._mfrm_fixed_q_diagnostic_plot_data(bad_chains; parameters = derived_names)
    for options in ((; bins = 0), (; bins = -1), (; bins = true), (; bins = 1.5),
            (; scale = :raw), (; scale = :unknown), (; max_parameters = 1),
            (; dimension = true), (; dimension = "missing"))
        @test_throws ArgumentError B._mfrm_fixed_q_diagnostic_plot_data(result; parameters = derived_names, options...)
    end
    @test_throws MethodError B._mfrm_fixed_q_diagnostic_plot_data(result; dimension_labels = ["override"])
    @test_throws MethodError B.plot_diagnostics(result)
    for selection in ((;), (; ndraws = 5), (; draw_indices = [24, 1, 24, 2]))
        check = B._mfrm_fixed_q_predictive_check(result; seed = 42, selection...)
        prediction = B._mfrm_fixed_q_predictive_plot_data(result; seed = 42, interval = 0.8, selection...)
        manual_rng = MersenneTwister(42)
        indices = haskey(selection, :draw_indices) ? selection.draw_indices :
            haskey(selection, :ndraws) ? rand(manual_rng, 1:24, selection.ndraws) : collect(1:24)
        probabilities = unit_probabilities(target, run.draws[indices, :])
        expected = Matrix{Int}(undef, length(indices), record.spec.data.n)
        for draw in eachindex(indices), row in axes(expected, 2)
            category = searchsortedfirst(cumsum(probabilities[draw, row, :]), rand(manual_rng))
            expected[draw, row] = record.spec.data.category_levels[category]
        end
        @test check.replicated_scores == expected
        @test check.draw_indices == prediction.draw_indices == indices
        @test check.chain_ids == prediction.chain_ids == run.chain_ids[indices]
        @test check.iterations == prediction.iterations == run.iterations[indices]
        @test check.model === :mfrm_fixed_q && check.backend === backend && check.target_identity == identity
        @test isequal(check.diagnostics, result.diagnostics)
        @test prediction.diagnostic == check.diagnostic == traces.diagnostic
        @test (prediction.n_retained, prediction.n_replicates, prediction.n_unique_draws) ==
            (24, length(indices), length(unique(indices)))
        @test prediction.n_observations == record.spec.data.n
        @test (check.rng.algorithm, check.rng.seed, check.rng.replayable) == (:MersenneTwister, 42, true)
        @test isequal(B._mfrm_fixed_q_predictive_check(loaded; seed = 42, selection...), check)
        @test isequal(B._mfrm_fixed_q_predictive_check(tampered; seed = 42, selection...), check)
        @test prediction.rows == predictive_check_plot_data(filter(row -> row.statistic === :category_proportion,
            predictive_check_summary(check; interval = 0.8)))
        for (column, row) in enumerate(prediction.rows)
            proportions = vec(sum(expected .== row.level; dims = 2)) ./ size(expected, 2)
            @test row.observed == count(==(row.level), record.spec.data.score) / record.spec.data.n
            @test row.replicated_mean ≈ mean(proportions)
            @test row.replicated_lower ≈ quantile(proportions, 0.1)
            @test row.replicated_upper ≈ quantile(proportions, 0.9)
        end
        wider = B._mfrm_fixed_q_predictive_plot_data(result; seed = 42, interval = 0.95, selection...)
        @test wider.draw_indices == indices && all(a.replicated_mean == b.replicated_mean &&
            a.replicated_lower <= b.replicated_lower && a.replicated_upper >= b.replicated_upper
            for (a, b) in zip(wider.rows, prediction.rows))
        @test !isempty(predictive_check_summary(check; include_grouped = true))
    end
    Random.seed!(183); expected_random = rand(); Random.seed!(183)
    B._mfrm_fixed_q_predictive_check(result)
    @test rand() == expected_random
    for options in ((; ndraws = 0), (; ndraws = 2, draw_indices = [1]),
            (; draw_indices = Int[]), (; draw_indices = [0]), (; draw_indices = [25]))
        @test_throws ArgumentError B._mfrm_fixed_q_predictive_check(result; options...)
    end
    for interval in (NaN, 0, 1)
        @test_throws ArgumentError B._mfrm_fixed_q_predictive_plot_data(result; interval)
    end
    @test_throws ArgumentError B._mfrm_fixed_q_predictive_check(bad_chains)
    @test_throws MethodError B._mfrm_fixed_q_predictive_check(result; dimension = 1)
    @test_throws MethodError B.plot_predictive(result)
    @test_throws MethodError posterior_predictive_check(result)
    options = (; posterior_interval = 0.8, predictive_interval = 0.8,
        seed = 42, draw_indices = [24, 1, 24, 2], require_complete = true)
    report = B._mfrm_fixed_q_report(result; options...)
    @test report.family === :mfrm_fixed_q && report.estimation_status === :private_reference
    @test report.metadata.backend === backend && report.metadata.scale_convention === :unit_logit
    @test report.metadata.target_identity == identity && report.metadata.source_sample_content_hash == record.content_hash
    @test isequal(report.metadata.prior, record.prior) && report.metadata.sampler_controls == run.controls
    @test report.metadata.diagnostic_settings == (; run.checked..., split_chains = run.split_chains_requested)
    @test report.report_status === :complete && fit_report_health(report).n_unsupported_sections == 10
    @test Set(row.section for row in fit_report_sections(report)) == Set(B._FIT_REPORT_SECTION_ORDER)
    @test isequal(report.diagnostics.parameter_rows, result.diagnostics.parameter_rows)
    @test isequal(report.diagnostics.model_parameter_rows, result.diagnostics.model_parameter_rows)
    @test isequal(report.diagnostics.summary, result.diagnostics.summary)
    @test isequal(report.warmup.rows, result.warmup_diagnostics)
    @test !isempty(report.diagnostics.warning_rows)
    @test all(row.fixed && row.value in (0, 1) for row in report.fixed_coordinates.rows)
    @test length(report.q_matrix.rows) == length(record.spec.q_matrix)
    @test sum(row.loading for row in report.q_matrix.rows) == sum(record.spec.q_matrix)
    @test [row.scale for row in report.prior_policy.rows] == [0.7, 0.4, 0.6, 0.5]
    @test [row.block for row in report.prior_policy.rows] == [:person, :rater_free, :item, :item_steps]
    @test all(row -> row.parameter_space === :unit_logit_free, report.prior_policy.rows)
    for (row, name) in zip(report.posterior.rows, result.parameter_names)
        column = findfirst(==(name), result.parameter_names)
        @test row.lower ≈ quantile(run.draws[:, column], 0.1)
    end
    for row in report.direct_posterior.rows
        @test row.lower ≈ quantile(values[row.parameter], 0.1)
        @test row.upper ≈ quantile(values[row.parameter], 0.9)
        if row.dimension !== nothing
            @test row.dimension_label == record.spec.dimension_labels[row.dimension]
        end
    end
    @test isequal(report.posterior_predictive.rows, predictive_check_summary(
        B._mfrm_fixed_q_predictive_check(result; seed = 42, draw_indices = options.draw_indices);
        interval = 0.8, include_grouped = true))
    @test report.report_policy.resolved_draw_indices == report.posterior_predictive.draw_indices == options.draw_indices
    @test report.posterior_predictive.chain_ids == run.chain_ids[options.draw_indices]
    @test report.posterior_predictive.iterations == run.iterations[options.draw_indices]
    untimed(r) = Base.structdiff(r, (; created_at = nothing))
    @test isequal(untimed(B._mfrm_fixed_q_report(loaded; options...)), untimed(report))
    @test isequal(untimed(B._mfrm_fixed_q_report(tampered; options...)), untimed(report))
    bundle = joinpath(directory, "report")
    save_fit_report_bundle(bundle, report; require_complete = true)
    saved_report = load_fit_report_bundle(bundle; require_complete = true)
    @test saved_report == B._json_export_value(report)
    tables = load_fit_report_tables(joinpath(bundle, "tables"))
    @test only(t for t in tables if t["section"] == "diagnostics" &&
        t["row_field"] == "model_parameter_rows")["rows"] == saved_report["diagnostics"]["model_parameter_rows"]
    for markdown in (fit_report_markdown(report), fit_report_markdown(saved_report; max_rows = 0))
        for text in ("Fixed-coefficient multidimensional MFRM", report.metadata.backend_label,
                identity, record.content_hash, "Sampled free coordinates in unit logits",
                "Conditional on the existing rating rows", "4 replicated datasets", "seed 42",
                "MCMC warnings", "Fixed point intervals", "induced dependent priors",
                "WAIC is not connected", "does not certify MCMC quality")
            @test occursin(text, markdown)
        end
    end
    no_predictive = B._mfrm_fixed_q_report(result; include_posterior_predictive = false)
    @test no_predictive.posterior_predictive.status === :not_requested && no_predictive.report_status === :complete
    default_report = B._mfrm_fixed_q_report(result)
    @test all(a.mean == b.mean && a.lower ≈ b.lower && a.upper ≈ b.upper
        for (a, b) in zip(default_report.posterior.rows, result.posterior_summary))
    @test default_report.report_policy.resolved_draw_indices == collect(1:24)
    failed = B._mfrm_fixed_q_report(result; ndraws = 0)
    @test failed.report_status === :incomplete && failed.posterior_predictive.status === :error
    @test_throws ArgumentError B._mfrm_fixed_q_report(result; ndraws = 0, require_complete = true)
    @test_throws ArgumentError B._mfrm_fixed_q_report(result; ndraws = 0, on_section_error = :throw)
    for kwargs in ((; posterior_interval = 1), (; predictive_interval = NaN), (; seed = true),
            (; include_posterior_predictive = false, draw_indices = [1]), (; on_section_error = :ignore))
        @test_throws ArgumentError B._mfrm_fixed_q_report(result; kwargs...)
    end
    @test_throws MethodError B._mfrm_fixed_q_report(result; view = :public)
    Random.seed!(184); expected_random = rand(); Random.seed!(184)
    B._mfrm_fixed_q_report(result; ndraws = 5)
    @test rand() == expected_random
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError B._plot_mfrm_fixed_q(result)
        @test_throws ArgumentError B._plot_mfrm_fixed_q_diagnostics(result)
        @test_throws ArgumentError B._plot_mfrm_fixed_q_predictive(result)
    end
    check_fixed_q_report_bundle(result, dirname(path))
    @test loaded.record.spec.data.rater_levels == [:judge_1, :judge_2, :judge_3]
    @test_throws ArgumentError load_fit_cache(path)
    @test_throws ArgumentError B._load_mgmfrm_normalized_prior_samples(path; expected_identity = identity)
    @test_throws ArgumentError B._load_mfrm_fixed_q_samples(path; expected_identity = "wrong")
    original = read(path)
    @test_throws ArgumentError B._save_mfrm_fixed_q_samples(path, result)
    @test read(path) == original
    B._save_mfrm_fixed_q_samples(path, result; overwrite = true)
    @test isequal(B._load_mfrm_fixed_q_samples(path; expected_identity = identity).record.run, run)

    # Rehash malformed records so semantic checks, as well as corruption checks, run.
    rehash(r) = merge(r, (; content_hash = B._mgmfrm_normalized_sample_hash(r)))
    changed_draws = copy(run.draws)
    changed_draws[1, 1] += 0.5
    changed_spec = deepcopy(record.spec)
    changed_spec.data.rater_levels[1] = :changed
    bad_records = [merge(record, (; content_hash = "wrong")),
        merge(record, (; spec = changed_spec)),
        rehash(merge(record, (; schema = "bayesianmgmfrm.normalized_fixed_q_samples.v2"))),
        rehash(merge(record, (; prior = merge(record.prior, (; scale_convention = :source_1_7))))),
        rehash(merge(record, (; prior = merge(record.prior, (; scales =
            merge(record.prior.scales, (; rater_sd = 0.9))))))),
        rehash(merge(record, (; run = merge(run, (; draws = changed_draws))))),
        rehash(merge(record, (; run = merge(run, (; chain_ids = reverse(run.chain_ids))))))]
    if record_warmup
        push!(bad_records, rehash(merge(record, (; run = merge(run,
            (; warmup_stats = run.warmup_stats[2:end]))))))
    end
    if backend === :cmdstan
        stats = copy(run.sampler_stats)
        stats[1] = merge(stats[1], (; stan_lp = stats[1].stan_lp + 0.5))
        push!(bad_records, rehash(merge(record, (; run = merge(run, (; sampler_stats = stats))))))
    end
    for bad in bad_records
        @test_throws ArgumentError B.MultidimensionalMFRMFit(bad; expected_identity = identity)
        bad_path = joinpath(directory, "invalid.jls")
        serialize(bad_path, bad)
        @test_throws ArgumentError B._load_mfrm_fixed_q_samples(bad_path; expected_identity = identity)
        @test_throws ArgumentError B._save_mfrm_fixed_q_samples(path,
            merge(result, (; record = bad)); overwrite = true)
        @test read(path) == original
        report_path = joinpath(directory, "invalid-report")
        @test_throws ArgumentError save_fit_report_bundle(report_path,
            B._mfrm_fixed_q_report(merge(result, (; record = bad))); require_complete = true)
        @test !ispath(report_path)
    end
    return result
end

@testset "fixed-Q MFRM Julia NUTS and saved unit-logit samples (operability only)" begin
    for (i, target) in enumerate(targets)
        mktempdir(directory -> check_samples(target, :advancedhmc, directory; record_warmup = i == 1))
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "fixed-Q MFRM CmdStan NUTS and saved unit-logit samples (operability only)" begin
        for (i, target) in enumerate(targets)
            mktempdir(directory -> check_samples(target, :cmdstan, directory; record_warmup = i == 1))
        end
    end
end

end
