# Uses saved or synthetic fits. No posterior sampling and no extra likelihood.
function check_fixed_q_prior_report(fit; directory = nothing, render = false, view = :public)
    directory === nothing && return mktempdir(d -> check_fixed_q_prior_report(fit; directory = d, render, view))
    record = fit.record
    correlated = fit isa B.Experimental.CorrelatedMFRMFit
    spec = correlated ? record.base_spec : record.spec
    model = correlated ? B.Experimental.correlated(spec; lkj_eta = record.prior.correlation.lkj_eta) : spec
    prior = MFRMPrior(; (correlated ? record.prior.base.scales : record.prior.scales)...)
    check = B.Experimental.prior_predictive_check(model; prior, ndraws = 19, rng = MersenneTwister(73))
    options = (; include_prior_predictive = true, prior_predictive_ndraws = 19,
        prior_interval = 0.8, predictive_interval = 0.7, seed = 73, include_artifact = false)
    Random.seed!(890); next = rand(); Random.seed!(890)
    report = fit_report(fit; options..., view = :full, require_complete = true)
    @test rand() == next
    section = report.prior_predictive
    @test section.status === :computed && report.report_status === :complete
    @test section.prior == check.prior
    @test section.rng.seed == 73 && section.ndraws == 19
    @test section.n_observations == spec.data.n
    @test isequal(section.rows, predictive_check_summary(check; interval = 0.7, include_grouped = true))
    @test isequal(section.implication_diagnostics, check.implication_diagnostics)
    @test section.parameter_interval == 0.8 && section.predictive_interval == 0.7
    @test length(section.parameter_rows) == length(check.model_coordinates)
    for (row, coordinate) in zip(section.parameter_rows, check.model_coordinates)
        @test row.lower ≈ quantile(coordinate.values, 0.1)
        @test row.upper ≈ quantile(coordinate.values, 0.9)
        @test (row.fixed, row.derived) == (coordinate.fixed, coordinate.derived)
    end
    @test length(section.correlation_rows) == Int(correlated)
    if correlated
        @test only(section.correlation_rows).parameter_space === :correlation
        @test occursin("prior_predictive / correlation_rows", fit_report_markdown(report))
    end
    @test occursin("prior_predictive / parameter_rows", fit_report_markdown(report))
    baseline = fit_report(fit; view = :full, seed = 73, predictive_interval = 0.7, include_artifact = false)
    @test baseline.prior_predictive.status === :not_requested
    @test isequal(baseline.posterior_predictive, report.posterior_predictive)
    @test isequal(baseline.diagnostics, report.diagnostics)
    changed = fit_report(fit; options..., prior_predictive_ndraws = 7, view = :full)
    @test changed.prior_predictive.ndraws == 7
    @test isequal(changed.posterior_predictive, report.posterior_predictive)
    @test isequal(changed.posterior, report.posterior)
    prior_only = fit_report(fit; options..., include_posterior_predictive = false, view = :full)
    @test prior_only.posterior_predictive.status === :not_requested
    @test isequal(prior_only.prior_predictive, section)
    failed = fit_report(fit; options..., prior_predictive_ndraws = 0, view = :full)
    @test failed.prior_predictive.status === :error && failed.report_status === :incomplete
    @test_throws ArgumentError fit_report(fit; options..., prior_predictive_ndraws = 0, on_section_error = :throw)
    @test_throws ArgumentError fit_report(fit; options..., prior_predictive_ndraws = 0, require_complete = true)
    @test_throws ArgumentError fit_report(fit; options..., prior_interval = 1)
    public = fit_report_public(report)
    @test isequal(public.prior_predictive.parameter_rows, section.parameter_rows)
    @test isequal(public.prior_predictive.rows, section.rows)
    @test B._assert_public_fit_report_language(public) === public
    block = correlated ? :latent_correlation : :person
    parameter_data = B._report_prior_plot_data(section, :prior; block)
    @test isequal(parameter_data, B._fixed_q_prior_plot_data(check; block, interval = 0.8))
    @test B._report_prior_plot_data(section, :prior_predictive) == B._prior_predictive_plot_data(check; interval = 0.7)
    @test_throws ArgumentError B._report_prior_plot_data(baseline.prior_predictive, :prior)
    @test_throws ArgumentError B._fit_report_figure_options((; prior = (; interval = 0.8)))
    @test_throws ArgumentError B._fit_report_figure_options((; prior_predictive = (; ndraws = 19)))
    # Both portable reports preserve the newly computed rows.
    for (label, value) in (("full", report), ("public", public))
        path = joinpath(directory, label)
        save_fit_report_bundle(path, value; require_complete = true)
        loaded = load_fit_report_bundle(path; require_complete = true)
        @test loaded["prior_predictive"] == B._json_export_value(value.prior_predictive)
    end
    @test record.content_hash == B._mgmfrm_normalized_sample_hash(record)
    path = joinpath(directory, "figures")
    if render
        choices = (; prior = (; block), prior_predictive = (;),
            posterior = (; block), diagnostics = (; block), predictive = (;))
        manifest = save_fit_report_bundle(path, fit; options..., figures = choices, view, require_complete = true)
        loaded = load_fit_report_bundle(path; require_complete = true)
        expected = view === :public ? public : report
        @test loaded["prior_predictive"] == B._json_export_value(expected.prior_predictive)
        @test length(manifest.figures) == 5
        for kind in (:prior, :prior_predictive)
            payload = B._read_json_dict(joinpath(path, "figures", "$kind.json"), "prior figure test")
            data = kind === :prior ? parameter_data : B._prior_predictive_plot_data(check; interval = 0.7)
            @test payload["data"] == B._json_export_value(data)
            @test payload["report_content_hash"]["value"] == manifest.report_content_hash.value
            @test payload["source_sample_content_hash"] == record.content_hash
            @test !occursin("retained", payload["caption"])
            @test occursin("prior", payload["caption"])
        end
        write(joinpath(path, "user-note.txt"), "Preserve this note.")
        files() = Dict(relpath(joinpath(d,n), path) => read(joinpath(d,n)) for (d,_,ns) in walkdir(path) for n in ns)
        original = files()
        @test_throws ArgumentError save_fit_report_bundle(path, fit; options..., view, overwrite = true,
            figures = (; prior_predictive = (;), prior = (; parameters = ["absent"])))
        @test files() == original
        @test_throws ArgumentError save_fit_report_bundle(path, fit; include_prior_predictive = false,
            figures = (; prior_predictive = (;)), view, overwrite = true)
        @test files() == original
        for kind in (:prior, :prior_predictive), suffix in ("pdf", "svg", "json")
            file = joinpath(path, "figures", "$kind.$suffix")
            bytes = read(file); write(file, vcat(bytes, UInt8[0x20]))
            @test_throws ArgumentError load_fit_report_bundle(path)
            write(file, bytes)
        end
        @test files() == original
    elseif Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
        @test_throws ArgumentError save_fit_report_bundle(path, fit; options..., figures = (; prior = (;)))
        @test !ispath(path)
    end
    return report
end
