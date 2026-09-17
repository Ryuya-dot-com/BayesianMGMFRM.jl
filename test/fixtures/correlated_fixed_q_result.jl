# Reuse synthetic or previously saved samples; never start a sampler here.
function check_correlated_fixed_q_result(result, directory; render = false)
    json(path) = B._read_json_dict(path, "correlated figure verification")
    fit = B._mfrm_correlated_2d_fit(result)
    record, run = result.record, result.record.run
    rho = last(result.model_coordinates)
    person = first(row.parameter for row in result.model_coordinates if row.block === :person && row.dimension == 2)
    fixed = first(row.parameter for row in result.model_coordinates if row.fixed)
    selection = (; parameters = [person, rho.parameter, fixed])
    indices = [size(run.draws, 1), 1, size(run.draws, 1), 2]
    options = (; view = :full, posterior_lower = 0.1, posterior_upper = 0.9, predictive_interval = 0.8, draw_indices = indices, seed = 42)
    metadata = fit_metadata(fit)
    @test metadata.model === :mfrm_fixed_q_correlated_2d
    @test metadata.latent_correlation === :free_2d
    @test metadata.dimension_labels == record.base_spec.dimension_labels
    @test metadata.prior.base == record.prior.base
    @test metadata.prior.correlation == metadata.correlation
    @test metadata.correlation == Base.structdiff(record.prior.correlation, (; fitting_available = nothing, cache_available = nothing))
    @test metadata.target_identity == record.target_identity
    @test metadata.public_fit && metadata.fitting_available && metadata.cache_available
    @test occursin("estimated rho; experimental", sprint(show, fit))
    @test fit_metadata(fit; view = :public).latent_correlation === :free_2d
    @test_throws ArgumentError B.MultidimensionalMFRMFit(record; expected_identity = record.target_identity)
    @test_throws ArgumentError B._CorrelatedMFRMFit(record; expected_identity = "independent")
    @test isequal(posterior_summary(fit; intervals = ()), result.posterior_summary)
    direct = B.direct_posterior_summary(fit; lower = 0.1, upper = 0.9)
    row = only(filter(r -> r.block === :latent_correlation, direct))
    @test row.parameter_space === :correlation
    @test row.derived && !row.fixed
    @test row.mean == mean(tanh.(run.draws[:, end]))
    @test row.lower ≈ quantile(tanh.(run.draws[:, end]), 0.1)
    @test row.upper ≈ quantile(tanh.(run.draws[:, end]), 0.9)
    @test all(r.dimension_label == "Second" for r in direct if r.block === :person && r.dimension == 2)
    diagnostic = diagnostics(fit)
    @test isequal(diagnostic.model_parameter_rows, result.diagnostics.model_parameter_rows)
    @test last(diagnostic.model_parameter_rows).parameter_space === :correlation
    @test all(!r.quality_gate_applicable for r in diagnostic.model_parameter_rows if r.parameter == fixed)
    @test_throws ArgumentError diagnostics(fit; rhat_threshold = 1.5)
    @test_throws ArgumentError diagnostics(fit; split_chains = !run.split_chains_requested)
    plotdata = B._mfrm_fixed_q_plot_data(result; selection..., interval = 0.8)
    @test getproperty.(plotdata.rows, :parameter) == selection.parameters
    @test plotdata.rows[2].parameter_space === :correlation
    @test plotdata.rows[2].lower ≈ row.lower
    @test plotdata.rows[2].upper ≈ row.upper
    @test all(r.dimension == 2 for r in B._mfrm_fixed_q_plot_data(result; block = :person, dimension = "Second").rows)
    tracedata = B._mfrm_fixed_q_diagnostic_plot_data(result; selection...)
    @test tracedata.rows[2].values == tanh.(run.draws[:, end])
    @test tracedata.rows[2].parameter_space === :correlation
    @test tracedata.chain_ids == run.chain_ids
    @test tracedata.iterations == run.iterations
    @test tracedata.rows[3].ranks === nothing
    @test_throws ArgumentError B._mfrm_fixed_q_plot_data(result; scale = :raw)
    @test_throws ArgumentError B._mfrm_fixed_q_plot_data(result; dimension = "missing")
    @test_throws ArgumentError B._mfrm_fixed_q_diagnostic_plot_data(result; bins = true)
    before = deepcopy(run)
    Random.seed!(918); next_random = rand(); Random.seed!(918)
    report = fit_report(fit; options..., require_complete = true)
    @test rand() == next_random
    @test isequal(run, before)
    @test report.report_status === :complete
    @test report.family === :mfrm && report.model === :mfrm_fixed_q_correlated_2d
    @test Base.structdiff(report.metadata, (; interpretation = nothing)) == metadata
    @test isequal(only(report.direct_posterior.correlation_rows), last(report.direct_posterior.rows))
    @test isequal(only(report.diagnostics.correlation_rows), last(report.diagnostics.model_parameter_rows))
    @test occursin("direct_posterior / correlation_rows", fit_report_markdown(report))
    @test occursin("diagnostics / correlation_rows", fit_report_markdown(report))
    @test report.posterior.rows[end].parameter_space === :fisher_z
    @test report.direct_posterior.rows[end].lower ≈ row.lower
    @test occursin("estimated population correlation", report.q_matrix.interpretation)
    @test !occursin("fixed to identity", fit_report_markdown(report))
    prior = report.prior_policy.rows
    @test first(prior).prior_family === :multivariate_normal
    @test !first(prior).independent_by_parameter
    @test first(prior).scale == record.prior.base.scales.person_sd
    @test last(prior).prior_family === :lkj_2d
    @test last(prior).shape == record.prior.correlation.lkj_eta
    @test ismissing(last(prior).scale)
    @test last(prior).jacobian_policy === :log_one_minus_rho_squared
    @test last(report.pooling_policy.rows).correlation_estimated
    @test last(report.pooling_policy.rows).shape == last(prior).shape
    @test report.posterior_predictive.draw_indices == indices
    @test report.posterior_predictive.chain_ids == run.chain_ids[indices]
    @test report.posterior_predictive.n_unique_draws == 3
    @test report.diagnostics.summary.flag == diagnostic.summary.flag
    @test length(report.diagnostics.warning_rows) == (diagnostic.summary.flag === :ok ? 0 : 1)
    predicted = B._mfrm_fixed_q_predictive_plot_data(result; interval = 0.8, draw_indices = indices, seed = 42)
    @test isequal(predicted, B._mfrm_fixed_q_predictive_plot_data(result; interval = 0.8, draw_indices = indices, seed = 42))
    @test predicted.diagnostic == plotdata.diagnostic == tracedata.diagnostic
    @test_throws ArgumentError fit_report(fit; posterior_lower = 0.0, posterior_upper = 1.0)
    @test_throws ArgumentError fit_report(fit; ndraws = 0, require_complete = true)
    samplepath = joinpath(directory, "samples.jls")
    B._save_mfrm_correlated_2d_samples(samplepath, fit)
    restored = B._mfrm_correlated_2d_fit(B._load_mfrm_correlated_2d_samples(samplepath; expected_identity = record.target_identity))
    @test isequal(B.direct_posterior_summary(restored), B.direct_posterior_summary(fit))
    @test isequal(diagnostics(restored), diagnostic)
    @test_throws ArgumentError B._load_mfrm_fixed_q_samples(samplepath; expected_identity = record.target_identity)
    path = joinpath(directory, "report")
    figures = render ? (; posterior = selection, diagnostics = selection, predictive = (;)) : nothing
    manifest = save_fit_report_bundle(path, restored; options..., figures, require_complete = true)
    loaded = load_fit_report_bundle(path; require_complete = true)
    @test loaded["metadata"] == B._json_export_value(report.metadata)
    @test loaded["direct_posterior"]["rows"] == B._json_export_value(report.direct_posterior.rows)
    @test loaded["posterior_predictive"] == B._json_export_value(report.posterior_predictive)
    @test loaded["prior_policy"] == B._json_export_value(report.prior_policy)
    extension = Base.get_extension(B, :BayesianMGMFRMCairoMakieExt)
    if extension === nothing
        for f in (B.plot_posterior, B.plot_diagnostics, B.plot_predictive)
            @test_throws ArgumentError f(fit)
        end
        @test_throws ArgumentError save_fit_report_bundle(joinpath(directory, "no-renderer"), fit; figures = (posterior = selection,))
        @test !ispath(joinpath(directory, "no-renderer"))
    end
    if render
        for entry in manifest.figures
            payload = json(joinpath(path, "figures", "$(entry.kind).json"))
            @test payload["family"] == "mfrm"
            @test payload["target_identity"] == record.target_identity
            @test payload["source_sample_content_hash"] == record.content_hash
            @test payload["report_content_hash"]["value"] == manifest.report_content_hash.value
            for file in entry.files
                @test bytes2hex(B.sha256(read(joinpath(path, file.path)))) == file.content_hash.value
            end
        end
        payload = json(joinpath(path, "figures/posterior.json"))["data"]
        @test payload == B._json_export_value(plotdata)
        @test json(joinpath(path, "figures/diagnostics.json"))["data"] == B._json_export_value(Base.structdiff(tracedata, (; summary = nothing)))
        @test json(joinpath(path, "figures/predictive.json"))["data"] == B._json_export_value(predicted)
        # Later-figure failures must leave a preexisting report and unrelated file intact.
        write(joinpath(path, "user-note.txt"), "Keep this file.")
        files() = Dict(relpath(joinpath(d,n), path) => read(joinpath(d,n)) for (d,_,ns) in walkdir(path) for n in ns)
        original = files()
        @test_throws ArgumentError save_fit_report_bundle(path, fit; overwrite = true,
            figures = (; posterior = selection, diagnostics = (; parameters = ["absent"])))
        @test files() == original
        for ext in ("pdf", "svg", "json")
            file = joinpath(path, "figures/posterior.$ext")
            bytes = read(file); write(file, vcat(bytes, UInt8[0x20]))
            @test_throws ArgumentError load_fit_report_bundle(path)
            write(file, bytes)
        end
        @test B.plot_posterior(fit; block = :person, dimension = "Second") isa extension.Figure
        @test B.plot_diagnostics(fit; selection...) isa extension.Figure
        @test B.plot_predictive(fit; draw_indices = indices, seed = 42) isa extension.Figure
    end
    # Detached ownership and fail-closed validation on every derived path.
    invalid = B._mfrm_correlated_2d_fit(result)
    invalid.record.run.draws[1, end] += 0.1
    @test record.run.draws == before.draws
    for f in (fit_metadata, posterior_summary, B.direct_posterior_summary, diagnostics, fit_report)
        @test_throws ArgumentError f(invalid)
    end
    original = read(samplepath)
    @test_throws ArgumentError B._save_mfrm_correlated_2d_samples(samplepath, invalid; overwrite = true)
    @test read(samplepath) == original
    @test_throws ArgumentError save_fit_report_bundle(path, invalid; overwrite = true)
    @test load_fit_report_bundle(path)["metadata"] == loaded["metadata"]
    return fit
end
