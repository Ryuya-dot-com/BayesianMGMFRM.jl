# Accept real saved fits as well as deterministic fixtures; never start a sampler.
function check_fixed_q_report(fit; directory = nothing)
    directory === nothing && return mktempdir(d -> check_fixed_q_report(fit; directory = d))
    record, run = fit.record, fit.record.run
    options = (; posterior_lower = 0.1, posterior_upper = 0.9,
        predictive_interval = 0.8, draw_indices = [size(run.draws, 1), 1, size(run.draws, 1)],
        seed = 42, include_full_artifact = true, require_complete = true)
    Random.seed!(719); expected = rand(); Random.seed!(719)
    report = fit_report(fit; options...)
    @test rand() == expected
    @test report.family === :mfrm && report.model === :mfrm_fixed_q
    @test report.estimation_status === :experimental
    @test report.report_status === :complete && fit_report_health(report).complete
    @test report.metadata.fitting_available === true
    @test report.metadata.dimension_labels == record.spec.dimension_labels
    @test report.metadata.target_identity == record.target_identity
    @test report.metadata.source_sample_content_hash == record.content_hash
    @test report.metadata.prior == record.prior
    @test report.metadata.scale_convention === :unit_logit
    @test report.metadata.diagnostic_settings == diagnostics(fit).diagnostic_settings
    @test isequal(report.diagnostics.model_parameter_rows, diagnostics(fit).model_parameter_rows)
    @test isequal(report.diagnostics.location_rows, diagnostics(fit).location_rows)
    @test report.rating_design.status === :computed
    audit = rating_design_audit(record.spec)
    @test isequal(report.rating_design.rows, collect(audit.rows))
    @test isequal(report.rating_design.summary, audit.summary)
    @test report.artifact.status === :computed
    artifact = report.artifact.artifact
    @test artifact.reproducibility.source_sample_content_hash == record.content_hash
    @test report.artifact.content_hash.value == artifact_content_hash(artifact)
    @test artifact.status === :experimental
    @test artifact.manifest.fit.estimation_status === :experimental
    @test artifact.draws === nothing
    @test all(row.n_draws == size(run.draws, 1) for row in report.posterior.rows)
    @test report.posterior_predictive.draw_indices == options.draw_indices
    @test report.posterior_predictive.chain_ids == run.chain_ids[options.draw_indices]
    @test report.posterior_predictive.iterations == run.iterations[options.draw_indices]
    for (row, source) in zip(report.direct_posterior.rows, B._mfrm_fixed_q_samples(fit).model_coordinates)
        @test row.lower ≈ quantile(source.values, 0.1)
        @test row.upper ≈ quantile(source.values, 0.9)
        @test (row.fixed, row.derived, row.dimension) == (source.fixed, source.derived, source.dimension)
    end
    for section in (:category_functioning, :rater_homogeneity, :mcmc_budget_guidance,
            :calibration, :waic, :loo, :dff)
        @test getproperty(report, section).status === :unsupported
        @test !isempty(getproperty(report, section).reason)
    end
    @test report.prior_predictive.status === :not_requested
    public = fit_report_public(report)
    @test public.status === :experimental
    @test public.metadata.estimation_status === :experimental
    @test public.metadata.fitting_available === true
    @test public.metadata.prior.scales == record.prior.scales
    @test public.metadata.diagnostic_settings == report.metadata.diagnostic_settings
    @test public.source_report.content_hash == B._public_fit_report_content_hash_record(report).value
    @test public.content_hash == B._public_fit_report_content_hash_record(public)
    @test B._assert_public_fit_report_language(public) === public
    @test public.rating_design.n_rows == report.rating_design.n_rows
    @test isequal(public.direct_posterior.rows, B._public_fit_report_project_value(report.direct_posterior.rows))
    public_artifact = B._public_fit_artifact_projection(artifact, fit)
    @test public_artifact.stability === public_artifact.status === :experimental
    @test public_artifact.model === :mfrm_fixed_q
    @test public_artifact.model_manifest.fit.estimation_status === :experimental
    @test public_artifact.model_manifest.fit.prior.scales == record.prior.scales
    @test public_artifact.model_manifest.spec.latent_correlation === :identity_fixed
    @test public_artifact.reproducibility.target_identity == record.target_identity
    @test public_artifact.reproducibility.source_sample_content_hash == record.content_hash
    @test public_artifact.source_artifact.hash == artifact.content_hash.value
    @test public_artifact.content_hash.value == artifact_content_hash(public_artifact)
    @test isequal(public_artifact.direct_posterior_summary, B._public_fit_report_project_value(artifact.direct_posterior_summary))
    exposed = fit_artifact(fit; view = :public, include_environment = false)
    @test isequal(exposed.reproducibility, public_artifact.reproducibility)
    @test exposed.content_hash.value == artifact_content_hash(exposed)

    cache = joinpath(directory, "report-fit.jls")
    save_fit_cache(cache, fit; artifact)
    saved_bytes = read(cache)
    restored = load_fit_cache(cache)
    replay = fit_report(restored; options...)
    for section in (:metadata, :rating_design, :diagnostics, :warmup, :prior_policy,
            :pooling_policy, :q_matrix, :fixed_coordinates, :posterior, :direct_posterior,
            :posterior_predictive, :report_policy)
        @test isequal(B._json_export_value(getproperty(report, section)),
            B._json_export_value(getproperty(replay, section)))
    end
    @test read(cache) == saved_bytes
    for label in ("full", "public")
        payload = label == "full" ? report : public
        destination = joinpath(directory, label)
        if label == "full"
            save_fit_report_bundle(destination, fit; options...)
        else
            save_fit_report_bundle(destination, payload; require_complete = true)
        end
        loaded = load_fit_report_bundle(destination; require_complete = true)
        @test loaded["metadata"]["source_sample_content_hash"] == record.content_hash
        @test loaded["direct_posterior"]["rows"] == B._json_export_value(payload.direct_posterior.rows)
        @test loaded["diagnostics"]["location_rows"] == B._json_export_value(payload.diagnostics.location_rows)
        @test occursin("unit logits", fit_report_markdown(loaded))
    end
    light = fit_report(fit; include_artifact = false, include_posterior_predictive = false)
    @test light.artifact.status === light.posterior_predictive.status === :not_requested
    @test fit_report(fit; view = :public, include_artifact = false,
        include_posterior_predictive = false).status === :experimental
    @test fit_report_public(fit; include_artifact = false,
        include_posterior_predictive = false).status === :experimental
    incomplete = fit_report(fit; include_artifact = false, ndraws = 0)
    @test incomplete.posterior_predictive.status === :error
    @test incomplete.report_status === :incomplete && !fit_report_health(incomplete).complete
    @test_throws ArgumentError fit_report(fit; include_artifact = false, ndraws = 0, require_complete = true)
    @test_throws ArgumentError fit_report(fit; include_artifact = false, ndraws = 0, on_section_error = :throw)
    for bad in ((; view = :invalid), (; posterior_lower = 0.2, posterior_upper = 0.9),
            (; posterior_lower = 0, posterior_upper = 1), (; posterior_lower = NaN),
            (; include_artifact = false, include_full_artifact = true),
            (; include_posterior_predictive = false, draw_indices = [1]),
            (; rhat_threshold = run.checked.rhat_threshold + 0.01))
        @test_throws ArgumentError fit_report(fit; bad...)
    end
    @test_throws MethodError fit_report(fit; posterior_interval = 0.8)
    settings = (; rhat_threshold = 1.1, ess_threshold = 5.0)
    tuned_run = merge(run, (; checked = settings, split_chains_requested = false, actual_split = false))
    tuned_record = merge(record, (; run = tuned_run))
    tuned_record = merge(tuned_record, (; content_hash = B._mgmfrm_normalized_sample_hash(tuned_record)))
    tuned = B.MultidimensionalMFRMFit(tuned_record; expected_identity = record.target_identity)
    tuned_report = fit_report(tuned; include_posterior_predictive = false, include_full_artifact = true)
    @test tuned_report.metadata.diagnostic_settings == (; settings..., split_chains = false)
    @test tuned_report.artifact.artifact.reproducibility.diagnostic_policy == tuned_report.metadata.diagnostic_settings
    @test record.content_hash == B._mgmfrm_normalized_sample_hash(record)
    return report
end
