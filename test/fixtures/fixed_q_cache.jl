# Saved/synthetic results only: this check never starts a sampler or loads a renderer.
function check_fixed_q_cache(fit; directory = nothing)
    directory === nothing && return mktempdir(d -> check_fixed_q_cache(fit; directory = d))
    record = fit.record
    path = joinpath(directory, "fit.jls")
    before = record.content_hash
    artifact = fit_artifact(fit; include_environment = false)
    @test artifact.schema == "bayesianmgmfrm.mfrm_fixed_q_fit_artifact.v1"
    @test artifact.family === :mfrm && artifact.model === :mfrm_fixed_q
    @test artifact.status === :private_reference
    @test artifact.reproducibility.target_identity == record.target_identity
    @test artifact.reproducibility.source_sample_content_hash == before
    @test isequal(artifact.manifest.fit, fit_metadata(fit))
    @test isequal(artifact.diagnostics, diagnostics(fit))
    @test isequal(artifact.posterior_summary, posterior_summary(fit))
    @test isequal(artifact.direct_posterior_summary, B.direct_posterior_summary(fit))
    @test artifact.draws === artifact.log_posterior === artifact.sampler_stats === artifact.warmup_stats === nothing
    @test artifact.environment === nothing
    @test artifact.content_hash.value == artifact_content_hash(artifact)
    saved = save_fit_cache(path, fit; cache_key = "manual-label", artifact)
    @test saved.schema == "bayesianmgmfrm.fit_cache.v2"
    @test saved.source_sample_schema == record.schema
    @test saved.source_sample_content_hash == before
    @test saved.fit.record.run.draws !== record.run.draws
    @test saved.fit.record.content_hash == before
    @test isequal(saved.artifact, artifact)
    bytes = read(path)
    loaded = load_fit_cache(path; expected_cache_key = "manual-label")
    @test loaded isa B.MultidimensionalMFRMFit
    @test isequal(fit_metadata(loaded), fit_metadata(fit))
    @test isequal(posterior_summary(loaded), posterior_summary(fit))
    @test isequal(B.direct_posterior_summary(loaded), B.direct_posterior_summary(fit))
    @test isequal(diagnostics(loaded), diagnostics(fit))
    @test isequal(load_fit_cache(path; return_record = true).artifact, artifact)
    @test load_fit_cache(path; verify_hash = false).record.content_hash == before
    @test_throws ArgumentError load_fit_cache(path; expected_cache_key = "wrong")
    @test_throws ArgumentError save_fit_cache(path, fit)
    @test read(path) == bytes
    @test_throws ArgumentError save_fit_cache(path, fit; artifact = "invalid", overwrite = true)
    @test read(path) == bytes
    @test_throws ArgumentError fit_artifact(fit; view = :invalid, include_environment = false)
    @test_throws ArgumentError fit_artifact(fit; include_environment = false,
        rhat_threshold = record.run.checked.rhat_threshold + 0.01)

    full_path = joinpath(directory, "full.jls")
    full = save_fit_cache(full_path, fit; artifact_include_draws = true,
        artifact_include_sampler_stats = true)
    @test ismissing(full.cache_key)
    @test full.artifact.draws == record.run.draws
    @test full.artifact.log_posterior == record.run.logdensities
    @test isequal(full.artifact.sampler_stats, record.run.sampler_stats)
    @test isequal(full.artifact.warmup_stats, get(record.run, :warmup_stats, nothing))
    @test load_fit_cache(full_path).record.content_hash == before
    @test full.artifact.draws !== full.fit.record.run.draws

    corrupt = B._mfrm_fixed_q_fit(B._mfrm_fixed_q_samples(fit))
    corrupt.record.run.draws[1,1] += 0.5
    @test_throws ArgumentError save_fit_cache(path, corrupt; overwrite = true)
    @test read(path) == bytes
    # A valid digest does not make incorrect model-dependent artifact values acceptable.
    wrong = merge(artifact, (; posterior_summary = reverse(artifact.posterior_summary)))
    wrong = B._with_archive_metadata(wrong; label = :mfrm_fixed_q_fit_artifact)
    @test_throws ArgumentError save_fit_cache(path, fit; artifact = wrong, overwrite = true)
    @test read(path) == bytes
    bad_path = joinpath(directory, "invalid.jls")
    variants = [merge(saved, (; model = :mgmfrm)),
        merge(saved, (; target_identity = "wrong")), merge(saved, (; source_sample_schema = "wrong")),
        merge(saved, (; source_sample_content_hash = missing)), merge(saved, (; artifact = wrong)),
        merge(saved, (; schema = "bayesianmgmfrm.fit_cache.v1")),
        merge(saved, (; serialization = merge(saved.serialization, (; format = :json)))),
        merge(saved, (; archive_manifest = merge(saved.archive_manifest, (; manifest = nothing)))),
        merge(saved, (; artifact_content_hash = merge(saved.artifact_content_hash, (; value = repeat("0",64))))),
        merge(saved, (; artifact = merge(artifact, (; content_hash = merge(artifact.content_hash, (; value = repeat("0",64))))))),
        merge(saved, (; fit = corrupt))]
    for bad in variants
        B._save_serialized_record(bad_path, bad; overwrite = true)
        for verify_hash in (true, false)
            @test_throws ArgumentError load_fit_cache(bad_path; verify_hash)
        end
    end
    save_fit_cache(path, fit; overwrite = true, artifact)
    @test load_fit_cache(path).record.content_hash == before
    @test record.content_hash == B._mgmfrm_normalized_sample_hash(record) == before
    return saved
end
