# Adapter checks accept an existing result; they never start a sampler.
function check_fixed_q_result(result)
    fit = B._mfrm_fixed_q_fit(result)
    record, run = result.record, result.record.run
    @test fit isa B.MultidimensionalMFRMFit
    @test fieldnames(typeof(fit)) == (:record,)
    @test !(fit isa B._ModelComparisonFit)
    @test :MultidimensionalMFRMFit ∉ names(B)
    @test !isdefined(B.Experimental, :MultidimensionalMFRMFit)
    @test fit.record.content_hash == record.content_hash
    @test fit.record.run.draws !== run.draws
    @test fit.record.spec.dimension_labels !== record.spec.dimension_labels
    metadata = fit_metadata(fit)
    @test metadata.family === :mfrm && metadata.model === :mfrm_fixed_q
    @test metadata.model_label == "Multidimensional MFRM (fixed coefficients)"
    @test !metadata.public_fit && metadata.estimation_status === :private_reference
    @test metadata.backend === run.backend && metadata.sampler === :nuts
    @test metadata.scale_convention === :unit_logit && metadata.parameter_space === :unit_logit_free
    @test metadata.location === :prior_anchored && metadata.latent_correlation === :identity_fixed
    @test metadata.prior == record.prior
    @test metadata.target_identity == record.target_identity
    @test metadata.source_sample_schema == record.schema
    @test metadata.source_sample_content_hash == record.content_hash
    @test metadata.dimension_labels == record.spec.dimension_labels
    @test metadata.q_matrix == record.spec.q_matrix
    @test metadata.item_structure == B._model_family_item_structure(record.spec)
    @test metadata.n_parameters == size(run.draws, 2)
    @test metadata.n_model_parameters == length(result.model_coordinates)
    @test metadata.n_draws == metadata.n_chains * metadata.draws_per_chain == size(run.draws, 1)
    @test occursin(metadata.model_label, sprint(show, fit))
    @test occursin(metadata.backend_label, sprint(show, fit))
    @test occursin("unit logits; private result", sprint(show, fit))

    options = (; lower = 0.1, upper = 0.8, intervals = (0.5, 0.8),
        reference = 0.2, rope = (-0.1, 0.3), rope_probability_threshold = 0.7)
    free = posterior_summary(fit; options...)
    direct = B.direct_posterior_summary(fit; options...)
    @test getproperty.(free, :parameter) == result.parameter_names
    @test getproperty.(direct, :parameter) == getproperty.(result.model_coordinates, :parameter)
    for (row, values) in [(free[i], run.draws[:, i]) for i in (1, size(run.draws, 2))]
        @test row.mean ≈ mean(values)
        @test row.lower ≈ quantile(values, 0.1)
        @test row.upper ≈ quantile(values, 0.8)
        @test row.n_draws == size(run.draws, 1)
        @test length(row.intervals) == 2
    end
    for (row, coordinate) in zip(direct, result.model_coordinates)
        @test row.mean ≈ mean(coordinate.values)
        @test (row.block, row.fixed, row.derived) == (coordinate.block, coordinate.fixed, coordinate.derived)
        @test isequal(row.dimension_label, coordinate.dimension === nothing ? missing : record.spec.dimension_labels[coordinate.dimension])
        if row.fixed
            @test row.lower == row.median == row.upper == first(coordinate.values)
        elseif row.derived
            @test row.lower ≈ quantile(coordinate.values, 0.1)
            @test row.upper ≈ quantile(coordinate.values, 0.8)
        end
    end
    diagnostic = diagnostics(fit)
    for key in (:parameter_rows, :model_parameter_rows, :sampler_rows, :summary)
        @test isequal(getproperty(diagnostic, key), getproperty(result.diagnostics, key))
    end
    @test isequal(diagnostic.warmup_rows, result.warmup_diagnostics)
    @test diagnostic.diagnostic_settings == metadata.diagnostic_settings
    @test isequal(diagnostics(fit; metadata.diagnostic_settings...), diagnostic)
    @test all(row.quality_gate_applicable == !coordinate.fixed
        for (row, coordinate) in zip(diagnostic.model_parameter_rows, result.model_coordinates))
    @test any(row.derived for row in direct)
    settings = (; rhat_threshold = 1.1, ess_threshold = 5.0)
    tuned_run = merge(run, (; checked = settings, split_chains_requested = false,
        actual_split = false, warmup_stats = nothing))
    tuned_record = merge(record, (; run = tuned_run))
    tuned_record = merge(tuned_record, (; content_hash = B._mgmfrm_normalized_sample_hash(tuned_record)))
    tuned = B.MultidimensionalMFRMFit(tuned_record; expected_identity = record.target_identity)
    @test diagnostics(tuned).diagnostic_settings == (; settings..., split_chains = false)
    if record.spec.family === :mfrm
        @test fit_archive_manifest(tuned; include_environment = false).reproducibility.diagnostic_policy ==
            diagnostics(tuned).diagnostic_settings
    end
    @test all(row.coverage === (run.controls.warmup == 0 ? :not_run : :not_recorded)
        for row in diagnostics(tuned).warmup_rows)
    @test_throws ArgumentError diagnostics(tuned; rhat_threshold = run.checked.rhat_threshold)

    # Caller-owned input and returned metadata/diagnostics cannot change the owned record.
    metadata.dimension_labels[1] = "changed"
    metadata.q_matrix[1, 1] = !metadata.q_matrix[1, 1]
    empty!(diagnostic.sampler_rows)
    @test fit_metadata(fit).dimension_labels == record.spec.dimension_labels
    @test fit_metadata(fit).q_matrix == record.spec.q_matrix
    @test isequal(diagnostics(fit).sampler_rows, result.diagnostics.sampler_rows)
    input = deepcopy(result)
    isolated = B._mfrm_fixed_q_fit(input)
    input.record.run.draws[1, 1] += 0.5
    @test isequal(posterior_summary(isolated; options...), free)
    stale = merge(result, (; model_coordinates = nothing, diagnostics = nothing, posterior_summary = nothing))
    rebuilt = B._mfrm_fixed_q_fit(stale)
    @test isequal(B.direct_posterior_summary(rebuilt; options...), direct)

    @test_throws ArgumentError B.MultidimensionalMFRMFit(record; expected_identity = "wrong")
    @test_throws ArgumentError B._mfrm_fixed_q_fit(merge(result, (; record = merge(record, (; content_hash = "wrong")))))
    bad = deepcopy(record)
    bad.run.draws[1, 1] += 0.5
    bad = merge(bad, (; content_hash = B._mgmfrm_normalized_sample_hash(bad)))
    @test_throws ArgumentError B.MultidimensionalMFRMFit(bad; expected_identity = record.target_identity)
    altered = B._mfrm_fixed_q_fit(result)
    altered.record.run.chain_ids[1] = 99
    for operation in (fit_metadata, posterior_summary, B.direct_posterior_summary, diagnostics)
        @test_throws ArgumentError operation(altered)
    end
    @test_throws ArgumentError sprint(show, altered)
    for operation in (posterior_summary, B.direct_posterior_summary)
        @test_throws ArgumentError operation(fit; lower = 0.9, upper = 0.1)
        @test_throws ArgumentError operation(fit; reference = NaN)
        @test_throws ArgumentError operation(fit; rope = -1)
    end
    @test_throws ArgumentError fit_metadata(fit; view = :public)
    @test_throws ArgumentError diagnostics(fit; view = :public)
    @test_throws ArgumentError diagnostics(fit; split_chains = !run.split_chains_requested)
    @test_throws ArgumentError diagnostics(fit; rhat_threshold = run.checked.rhat_threshold + 0.01)
    @test_throws ArgumentError diagnostics(fit; ess_threshold = run.checked.ess_threshold + 1)
    for operation in (loo, waic)
        @test !applicable(operation, fit)
    end
    for operation in (B.plot_posterior, B.plot_diagnostics, B.plot_predictive)
        @test applicable(operation, fit)
        if record.spec.family === :mgmfrm || Base.get_extension(B, :BayesianMGMFRMCairoMakieExt) === nothing
            @test_throws ArgumentError operation(fit)
        end
    end
    @test applicable(fit_artifact, fit)
    @test applicable(save_fit_cache, "not-written.jls", fit)
    if record.spec.family === :mgmfrm
        @test_throws ArgumentError fit_artifact(fit; include_environment = false)
        @test_throws ArgumentError fit_report(fit; include_artifact = false)
    end
    Random.seed!(73); expected = rand(); Random.seed!(73)
    fit_metadata(fit); posterior_summary(fit); B.direct_posterior_summary(fit); diagnostics(fit)
    @test rand() == expected
    @test fit.record.content_hash == B._mgmfrm_normalized_sample_hash(fit.record)
    return fit
end
