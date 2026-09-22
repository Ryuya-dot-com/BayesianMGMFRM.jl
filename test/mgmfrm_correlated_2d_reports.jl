isdefined(@__MODULE__, :MGMFRMCorrelated2DFixtures) || include("mgmfrm_correlated_2d_fixtures.jl")
module MGMFRMCorrelated2DReportChecks
using Test, BayesianMGMFRM, Random, Statistics, Serialization
using ..MGMFRMCorrelated2DFixtures: target, synthetic_record
include("../scripts/public_language_gate.jl")
const B = BayesianMGMFRM
const E = B.Experimental
bytes(x) = (io = IOBuffer(); serialize(io, x); take!(io))

@testset "report JSON preserves signed zeros and integer identities" begin
    mktempdir() do dir
        path = joinpath(dir, "zeros.json")
        payload = Dict("negative" => -0.0, "positive" => 0.0, "integer" => 3,
            "large" => 9_007_199_254_740_993, "nested" => Dict("values" => Any[-0.0, 0.0, 9_007_199_254_740_993]),
            "text" => "-0.0", "flag" => false)
        B._write_json_record(path, payload)
        loaded = B._read_json_dict(path, "signed-zero regression")
        @test loaded["negative"] isa Float64 && signbit(loaded["negative"])
        @test !signbit(loaded["positive"])
        @test loaded["integer"] isa Integer && loaded["integer"] == 3
        @test loaded["large"] isa Integer && loaded["large"] == 9_007_199_254_740_993
        @test signbit(loaded["nested"]["values"][1]) && !signbit(loaded["nested"]["values"][2])
        @test loaded["nested"]["values"][3] isa Integer && loaded["nested"]["values"][3] == 9_007_199_254_740_993
        @test loaded["text"] == "-0.0" && loaded["flag"] === false
        @test B._cache_stable_string(B._json_hash_value(payload)) == B._cache_stable_string(B._json_hash_value(loaded))
    end
end

function check_report(fit)
    record = fit.record; snapshot = bytes(record)
    options = (; include_prior_predictive = true, prior_predictive_ndraws = 19,
        prior_interval = 0.8, posterior_lower = 0.1, posterior_upper = 0.9,
        predictive_interval = 0.7, draw_indices = [8, 1, 1, 3], seed = 73, include_artifact = false)
    Random.seed!(839); expected = rand(); Random.seed!(839)
    report = fit_report(fit; options..., view = :full, require_complete = true)
    @test rand() == expected
    @test report.schema == "bayesianmgmfrm.fit_report.v1"
    @test report.family === :mgmfrm && report.estimation_status === :experimental
    @test report.report_status === :complete && fit_report_health(report).complete
    @test !report.diagnostics.summary.passed && !isempty(report.diagnostics.warning_rows)
    @test report.diagnostics.summary.flag === diagnostics(fit).summary.flag
    @test report.diagnostics.correlation_rows == [last(diagnostics(fit).direct_parameter_rows)]
    @test report.warmup.rows == sampler_diagnostics(fit; phase = :warmup)
    @test report.metadata.prior == fit_metadata(fit).prior
    @test report.metadata.source_sample_content_hash == record.content_hash
    @test report.metadata.likelihood_scale == 1.7
    @test report.rating_design.status === :computed
    @test all(r -> r.active ? r.loading === :estimated_positive : r.loading === :fixed_zero, report.q_matrix.rows)
    @test all(r -> r.block !== :item_dimension_discrimination, report.fixed_coordinates.rows)
    for r in report.prior_policy.rows[1:6]
        @test r.value == getproperty(record.prior.scales, r.parameter) && !r.estimated
    end
    @test last(report.prior_policy.rows).value == record.prior.lkj_eta
    @test occursin("last rater", report.prior_policy.interpretation)
    rho = tanh.(record.run.draws[:, end])
    summary = only(report.direct_posterior.correlation_rows)
    @test summary.mean ≈ mean(rho)
    @test summary.lower ≈ quantile(rho, 0.1) && summary.upper ≈ quantile(rho, 0.9)
    @test summary.parameter_space === :correlation && summary.derived && !summary.fixed
    raw = last(report.posterior.rows)
    @test raw.parameter_space === :fisher_z && raw.mean ≈ mean(record.run.draws[:, end])
    mcse = only(report.direct_posterior.correlation_mcse_rows)
    original = last(posterior_mcse(fit; probabilities = (0.1, 0.5, 0.9)))
    for field in keys(original)
        @test isequal(getproperty(mcse, field), getproperty(original, field))
    end
    context = B._mgmfrm_correlated_2d_report_context(fit)
    coordinates = B._mgmfrm_correlated_2d_report_coordinates(context)
    for (row, c) in zip(report.direct_posterior.rows, coordinates)
        @test row.mean ≈ mean(c.values)
        @test row.lower ≈ quantile(c.values, 0.1) && row.upper ≈ quantile(c.values, 0.9)
        @test row.fixed == c.fixed
        if c.dimension !== nothing
            @test row.dimension_label == record.spec.dimension_labels[c.dimension]
        end
    end
    for item in record.spec.data.item_levels
        K = length(record.spec.data.category_levels)
        steps = [only(filter(c -> c.parameter == "item_step[item=$item,m=$k]", coordinates)) for k in 1:K]
        @test all(iszero, first(steps).values) && first(steps).fixed
        @test all(isapprox.(sum(c.values for c in steps), 0; atol = 1e-14))
        @test last(steps).derived && last(steps).fixed == (K == 2)
    end
    model = E.correlated(record.spec; lkj_eta = record.prior.lkj_eta)
    prior = E.GeneralizedPrior(; record.prior.scales...)
    before = E.prior_predictive_check(model; prior, ndraws = 19, rng = MersenneTwister(73))
    @test report.prior_predictive.prior == before.prior
    @test isequal(report.prior_predictive.rows, predictive_check_summary(before; interval = 0.7, include_grouped = true))
    @test report.prior_predictive.correlation_rows[1].lower ≈ quantile(before.direct_parameter_draws[:, end], 0.1)
    after = posterior_predictive_check(fit; draw_indices = options.draw_indices, rng = MersenneTwister(73))
    section = report.posterior_predictive
    @test isequal(section.rows, predictive_check_summary(after; interval = 0.7, include_grouped = true))
    @test section.draw_indices == options.draw_indices && section.n_unique_draws == 3
    @test section.chain_ids == record.run.chain_ids[options.draw_indices]
    @test section.iterations == record.run.iterations[options.draw_indices]
    @test section.prediction_target === :existing_rating_rows && section.rng.seed == 73
    skipped = fit_report(fit; options..., include_prior_predictive = false, view = :full)
    @test skipped.prior_predictive.status === :not_requested
    @test isequal(skipped.posterior_predictive, section)
    @test isequal(skipped.direct_posterior, report.direct_posterior)
    @test isequal(skipped.diagnostics, report.diagnostics)
    selected = fit_report(fit; options..., draw_indices = [2, 2], prior_predictive_ndraws = 7, view = :full)
    @test isequal(selected.direct_posterior, report.direct_posterior)
    @test isequal(selected.diagnostics, report.diagnostics)
    @test selected.prior_predictive.ndraws == 7 && selected.posterior_predictive.n_replicates == 2
    public = fit_report_public(report)
    @test public.schema == "bayesianmgmfrm.fit_report_public.v1" && public.status === :experimental
    @test public.diagnostics.summary.flag === report.diagnostics.summary.flag
    @test isequal(public.direct_posterior.correlation_rows, report.direct_posterior.correlation_rows)
    @test isequal(public.direct_posterior.correlation_mcse_rows, report.direct_posterior.correlation_mcse_rows)
    @test isempty(PublicLanguageGate.runtime_public_report_language_violations(["report" => public]))
    markdown = fit_report_markdown(public; max_rows = 1)
    @test occursin(summary.parameter, markdown) && occursin("mcse", lowercase(markdown))
    @test occursin("MCMC warnings", markdown) && occursin("Same-data agreement", markdown)
    @test !occursin("unit logits", lowercase(markdown))
    @test fit_report(fit; options...).schema == public.schema
    mktempdir() do directory
        for (name, value) in (("public", public), ("full", report))
            path = joinpath(directory, name)
            save_fit_report_bundle(path, value; require_complete = true)
            loaded = load_fit_report_bundle(path; require_complete = true)
            @test loaded["direct_posterior"] == B._json_export_value(value.direct_posterior)
            @test loaded["prior_predictive"] == B._json_export_value(value.prior_predictive)
            @test loaded["posterior_predictive"] == B._json_export_value(value.posterior_predictive)
            @test isfile(joinpath(path, "tables", "direct_posterior__mcse_rows.json"))
        end
        path = joinpath(directory, "fit-bundle")
        save_fit_report_bundle(path, fit; options..., require_complete = true)
        @test load_fit_report_bundle(path)["direct_posterior"] == B._json_export_value(public.direct_posterior)
        cache = joinpath(directory, "fit.jls"); save_fit_cache(cache, fit)
        cached = read(cache); loaded = load_fit_cache(cache)
        restored = fit_report(loaded; options..., view = :full)
        for name in (:posterior, :direct_posterior, :prior_predictive, :posterior_predictive, :diagnostics, :prior_policy, :q_matrix)
            @test isequal(getproperty(restored, name), getproperty(report, name))
        end
        @test read(cache) == cached
    end
    @test bytes(fit.record) == snapshot
    return (; report, context)
end

@testset "correlated MGMFRM report, model coordinates, MCSE and persistence" begin
    for K in (2, 4), backend in (:advancedhmc, :cmdstan)
        t = target(; K, raters = K == 2 ? 1 : 3)
        r = synthetic_record(t; backend)
        fit = E.CorrelatedMGMFRMFit(r; expected_identity = r.target_identity)
        report, context = check_report(fit)
        for scale in (:model, :raw)
            plotted = B._mgmfrm_correlated_2d_plot_data(context; scale, block = :latent_correlation, interval = 0.8)
            row = only(plotted.rows)
            values = scale === :model ? tanh.(r.run.draws[:, end]) : r.run.draws[:, end]
            @test row.lower ≈ quantile(values, 0.1) && row.upper ≈ quantile(values, 0.9)
            @test plotted.backend === backend && occursin("MCMC", plotted.diagnostic)
            traces = B._mgmfrm_correlated_2d_diagnostic_plot_data(context; scale, block = :latent_correlation)
            @test only(traces.rows).values == values
            @test occursin("R-hat", only(traces.rows).status)
            @test traces.chain_ids == r.run.chain_ids && traces.iterations == r.run.iterations
        end
        for block in (:person, :item_dimension_discrimination)
            plotted = B._mgmfrm_correlated_2d_plot_data(context; block, dimension = "Second")
            @test all(row -> row.dimension == 2 && row.block === block, plotted.rows)
        end
        predictive = B._mgmfrm_correlated_2d_predictive_plot_data(context, report.posterior_predictive; interval = 0.7)
        @test predictive.rows == predictive_check_plot_data(filter(row -> row.statistic === :category_proportion, report.posterior_predictive.rows))
        @test predictive.draw_indices == report.posterior_predictive.draw_indices
        @test predictive.rng == report.posterior_predictive.rng && predictive.n_unique_draws == 3
        for kwargs in ((; dimension = "absent"), (; block = :wrong), (; parameters = ["absent"]),
                (; scale = :unknown), (; max_parameters = 1), (; interval = 1))
            @test_throws ArgumentError B._mgmfrm_correlated_2d_plot_data(context; kwargs...)
        end
        @test_throws ArgumentError B._mgmfrm_correlated_2d_diagnostic_plot_data(context; view = :location)
        @test_throws ArgumentError B._mgmfrm_correlated_2d_diagnostic_plot_data(context; bins = true)
    end
end

@testset "report failures stay explicit without replacing saved results" begin
    t = target(); r = synthetic_record(t); fit = E.CorrelatedMGMFRMFit(r; expected_identity = r.target_identity)
    for kwargs in ((; include_prior_predictive = true, prior_predictive_ndraws = 0), (; draw_indices = [0]))
        report = fit_report(fit; kwargs..., view = :full, include_artifact = false)
        @test report.report_status === :incomplete && !fit_report_health(report).complete
        @test_throws ArgumentError fit_report(fit; kwargs..., on_section_error = :throw)
        @test_throws ArgumentError fit_report(fit; kwargs..., require_complete = true)
        public = fit_report_public(report)
        @test public.report_status === :incomplete
        mktempdir() do dir
            @test_throws ArgumentError save_fit_report_bundle(dir, fit; kwargs..., require_complete = true)
            @test isempty(readdir(dir))
        end
    end
    for kwargs in ((; view = :wrong), (; posterior_lower = 0.2), (; prior_interval = 1),
            (; predictive_interval = NaN), (; seed = true), (; on_section_error = :ignore),
            (; include_posterior_predictive = false, ndraws = 1),
            (; include_artifact = false, include_full_artifact = true), (; rhat_threshold = 1.5))
        @test_throws ArgumentError fit_report(fit; kwargs...)
    end
    withartifact = fit_report(fit; include_full_artifact = true, view = :full)
    @test withartifact.artifact.artifact.reproducibility.target_identity == r.target_identity
    bad = deepcopy(fit); bad.record.run.draws[1, end] += 0.3
    @test_throws ArgumentError fit_report(bad)
    if Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        for plot in (B.plot_posterior, B.plot_diagnostics, B.plot_predictive)
            @test_throws ArgumentError plot(fit)
        end
        mktempdir() do dir
            @test_throws ArgumentError save_fit_report_bundle(dir, fit; figures = (; posterior = (; block = :latent_correlation)))
            @test isempty(readdir(dir))
        end
    end
end
end
