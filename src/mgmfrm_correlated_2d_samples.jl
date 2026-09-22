# Private maintained-sampler records for the estimated-loading correlation target.
# Existing MGMFRMFit and public fit-cache schemas retain their independent meaning.
function _mgmfrm_correlated_2d_sample_blueprint(target)
    names = [target.base.blueprint.constrained_parameter_names;
        target.blueprint.derived_parameter_names]
    blocks = copy(target.base.blueprint.constrained_blocks)
    blocks[:latent_correlation] = length(names):length(names)
    return merge(target.blueprint, (; constrained_parameter_names = names,
        constrained_blocks = blocks))
end

function _generalized_candidate_direct_draw_values(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity, draws::AbstractMatrix{<:Real})
    direct = _mgmfrm_guarded_local_fit_direct_draw_values(target.base,
        view(draws, :, target.blueprint.base_parameter_range))
    return merge(direct, (; direct_draws = hcat(direct.direct_draws,
        tanh.(view(draws, :, target.blueprint.zrho_index)))))
end

function _generalized_candidate_direct_draw_constraint_rows(
        target::_MGMFRMFreeLatentCorrelation2DLogDensity, draws::AbstractMatrix{<:Real})
    return _mgmfrm_guarded_local_fit_direct_draw_constraint_rows(
        target.base.design, view(draws, :, 1:(size(draws, 2) - 1)))
end

function _mgmfrm_correlated_2d_samples(target, record::NamedTuple)
    run = record.run
    _check_generalized_sample_run(target, run)
    if run.backend === :cmdstan
        all(hasproperty(stat, :stan_lp) && isapprox(stat.stan_lp, lp; atol = 1e-8, rtol = 1e-8)
            for (stat, lp) in zip(run.sampler_stats, run.logdensities)) ||
            throw(ArgumentError("correlated MGMFRM retained Stan log posterior mismatch"))
    end
    blueprint = _mgmfrm_correlated_2d_sample_blueprint(target)
    tables = _generalized_candidate_diagnostic_tables(target, run, blueprint)
    tables.n_nonfinite_direct_loglikelihood == 0 && tables.n_failed_direct_constraints == 0 &&
        all(isfinite, tables.direct_values.direct_draws) ||
        throw(ArgumentError("correlated MGMFRM direct draw validation failed"))
    # Both spaces enter the common whole-result quality gate. rho is transformed
    # draw by draw; neither its MCSE nor its diagnostics are transformed from z.
    raw_spaces = [fill(:raw_unconstrained, run.nparams - 1); :fisher_z]
    direct_spaces = [fill(:direct_constrained, length(blueprint.constrained_parameter_names) - 1); :correlation]
    annotate(rows, spaces) = [merge(row, (; parameter_space = space))
        for (row, space) in zip(rows, spaces)]
    tables = merge(tables, (;
        parameter_rows = annotate(tables.parameter_rows, raw_spaces),
        direct_parameter_rows = annotate(tables.direct_parameter_rows, direct_spaces),
        block_rows = [merge(row, (; parameter_space = row.block === :z_latent_correlation ?
            :fisher_z : :raw_unconstrained)) for row in tables.block_rows],
        direct_block_rows = [merge(row, (; parameter_space = row.block === :latent_correlation ?
            :correlation : :direct_constrained)) for row in tables.direct_block_rows]))
    return (; record, model = :mgmfrm_correlated_2d_raw_prior, public_fit = false,
        target_contract = _mgmfrm_correlated_2d_contract(target),
        raw_parameter_names = copy(blueprint.parameter_names),
        direct_parameter_names = copy(blueprint.constrained_parameter_names),
        raw_parameter_spaces = raw_spaces, direct_parameter_spaces = direct_spaces,
        structurally_fixed_parameters = _structurally_fixed_constrained_parameter_names(blueprint),
        diagnostics = tables,
        warmup_diagnostics = _warmup_diagnostic_rows(run.warmup_stats, run.controls, run.backend))
end

function _mgmfrm_correlated_2d_sample(target::_MGMFRMFreeLatentCorrelation2DLogDensity,
        initial = nothing; backend::Symbol = :advancedhmc, record_warmup::Bool = true, kwargs...)
    runner = backend === :advancedhmc ? _run_generalized_candidate_advancedhmc :
        backend === :cmdstan ? _cmdstan_generalized_candidate_run :
        throw(ArgumentError("correlated MGMFRM sampling supports :advancedhmc or :cmdstan"))
    # Rebuild all mutable numerical views from the canonical design and prior.
    _require_canonical_design(target.base.design, "correlated MGMFRM sampling")
    target = _mgmfrm_free_latent_correlation_2d_logdensity(target.base.design.spec;
        prior = target.prior.source_prior, lkj_eta = target.prior.lkj_eta)
    raw_initial = initial === nothing ? initial_params(target) : initial
    raw_initial isa AbstractVector || throw(ArgumentError("initial must be a raw parameter vector or nothing"))
    run = runner(target, raw_initial; record_warmup, kwargs...)
    # Explicit missing coverage is preserved even when recording was disabled.
    run = merge(run, (; warmup_stats = get(run, :warmup_stats, nothing)))
    record = (; schema = "bayesianmgmfrm.correlated_mgmfrm_samples.v1",
        spec = deepcopy(target.base.design.spec),
        prior = (; scales = _source_fixture_prior_values(target.prior.source_prior),
            lkj_eta = target.prior.lkj_eta),
        target_identity = _mgmfrm_correlated_2d_identity(target), run)
    record = merge(record, (; content_hash = _mgmfrm_normalized_sample_hash(record)))
    return _mgmfrm_correlated_2d_samples(target, record)
end

function _restore_mgmfrm_correlated_2d_samples(record; expected_identity::AbstractString)
    record isa NamedTuple && keys(record) ==
        (:schema, :spec, :prior, :target_identity, :run, :content_hash) &&
        record.schema == "bayesianmgmfrm.correlated_mgmfrm_samples.v1" &&
        record.spec isa FacetSpec && record.prior isa NamedTuple && record.run isa NamedTuple &&
        record.target_identity == expected_identity ||
        throw(ArgumentError("correlated MGMFRM sample contract or target mismatch"))
    record.content_hash == _mgmfrm_normalized_sample_hash(record) ||
        throw(ArgumentError("correlated MGMFRM sample content hash mismatch"))
    keys(record.prior) == (:scales, :lkj_eta) && record.prior.scales isa NamedTuple &&
        keys(record.prior.scales) == fieldnames(_SourceFixturePrior) &&
        all(x -> x isa Real && isfinite(x) && x > 0, values(record.prior.scales)) &&
        record.prior.lkj_eta isa Int && hasproperty(record.run, :warmup_stats) ||
        throw(ArgumentError("invalid correlated MGMFRM prior or warmup record"))
    target = _mgmfrm_free_latent_correlation_2d_logdensity(record.spec;
        prior = _SourceFixturePrior(; record.prior.scales...), lkj_eta = record.prior.lkj_eta)
    _mgmfrm_correlated_2d_identity(target) == expected_identity ||
        throw(ArgumentError("correlated MGMFRM prior, measure or design mismatch"))
    return _mgmfrm_correlated_2d_samples(target, record)
end

# Trusted same-environment Serialization, separate from public fit caches.
# Only canonical inputs and the run are saved; all derived views are rebuilt.
function _save_mgmfrm_correlated_2d_samples(path::AbstractString, result::NamedTuple;
        overwrite::Bool = false)
    record = result.record
    _restore_mgmfrm_correlated_2d_samples(record; expected_identity = record.target_identity)
    return _save_serialized_record(path, record; overwrite)
end

function _load_mgmfrm_correlated_2d_samples(path::AbstractString; expected_identity::AbstractString)
    return _restore_mgmfrm_correlated_2d_samples(open(deserialize, path); expected_identity)
end

function _mgmfrm_correlated_2d_summary_input(result, parameter_space)
    selected = parameter_space === :auto ? :direct_constrained : parameter_space
    selected in (:direct_constrained, :raw_unconstrained) || throw(ArgumentError(
        "correlated MGMFRM parameter_space must be :auto, :direct_constrained, or :raw_unconstrained"))
    checked = _restore_mgmfrm_correlated_2d_samples(result.record;
        expected_identity = result.record.target_identity)
    raw = selected === :raw_unconstrained
    return (; checked, selected,
        draws = raw ? checked.record.run.draws : checked.diagnostics.direct_values.direct_draws,
        names = raw ? checked.raw_parameter_names : checked.direct_parameter_names,
        spaces = raw ? checked.raw_parameter_spaces : checked.direct_parameter_spaces,
        fixed = raw ? Set{String}() : checked.structurally_fixed_parameters)
end

function _mgmfrm_correlated_2d_posterior_summary(result::NamedTuple;
        parameter_space::Symbol = :auto, lower::Real = 0.025, upper::Real = 0.975,
        intervals = (0.66, 0.9, 0.95), reference::Real = 0.0, rope = nothing,
        rope_probability_threshold::Real = 0.95)
    input = _mgmfrm_correlated_2d_summary_input(result, parameter_space)
    rows = _posterior_summary_rows(input.draws, input.names;
        lower, upper, intervals, reference, rope, rope_probability_threshold)
    return [merge(row, (; parameter_space = space)) for (row, space) in zip(rows, input.spaces)]
end

function _mgmfrm_correlated_2d_posterior_mcse(result::NamedTuple;
        parameter_space::Symbol = :auto, probabilities = (0.025, 0.5, 0.975))
    input = _mgmfrm_correlated_2d_summary_input(result, parameter_space)
    rows = _posterior_mcse_rows(input.draws, input.names, input.checked.record.run.controls.chains;
        probabilities, parameter_space = input.selected, structurally_fixed_parameters = input.fixed)
    return [merge(row, (; parameter_space = space)) for (row, space) in zip(rows, input.spaces)]
end

# Explicit experimental wrappers; the base FacetSpec and MGMFRMFit still mean
# independent ability dimensions. The prior is required at the fitting boundary.
struct _CorrelatedMGMFRMSpec
    base_spec::FacetSpec
    lkj_eta::Int
    function _CorrelatedMGMFRMSpec(spec::FacetSpec; lkj_eta = 2)
        target = _mgmfrm_free_latent_correlation_2d_logdensity(spec; lkj_eta)
        return new(deepcopy(target.base.design.spec), target.prior.lkj_eta)
    end
end

struct _CorrelatedMGMFRMFit
    record::NamedTuple
    function _CorrelatedMGMFRMFit(record::NamedTuple; expected_identity::AbstractString)
        snapshot = deepcopy(record)
        _restore_mgmfrm_correlated_2d_samples(snapshot; expected_identity)
        return new(snapshot)
    end
end

function Base.show(io::IO, spec::_CorrelatedMGMFRMSpec)
    print(io, "Correlated MGMFRM (", join(spec.base_spec.dimension_labels, ", "),
        "; estimated loadings and consistency; LKJ eta = ", spec.lkj_eta, "; experimental)")
end

function _mgmfrm_correlated_2d_target(spec::_CorrelatedMGMFRMSpec, prior)
    prior isa GeneralizedPrior || throw(ArgumentError(
        "correlated MGMFRM requires an explicit prior = Experimental.GeneralizedPrior(...); " *
        "these are raw-coordinate scales, with correlated ability pairs and the specification's LKJ eta"))
    return _mgmfrm_free_latent_correlation_2d_logdensity(spec.base_spec;
        prior = _source_fixture_prior(prior), lkj_eta = spec.lkj_eta)
end

function _mgmfrm_correlated_2d_fit(spec::_CorrelatedMGMFRMSpec;
        prior = nothing, backend::Symbol = :advancedhmc, init = nothing, kwargs...)
    target = _mgmfrm_correlated_2d_target(spec, prior)
    init === nothing || init isa AbstractVector{<:Real} ||
        throw(ArgumentError("init must be a real raw-coordinate vector ending in Fisher z"))
    result = _mgmfrm_correlated_2d_sample(target, init; backend, kwargs...)
    return _CorrelatedMGMFRMFit(result.record; expected_identity = result.record.target_identity)
end

_mgmfrm_correlated_2d_samples(fit::_CorrelatedMGMFRMFit) =
    _restore_mgmfrm_correlated_2d_samples(fit.record; expected_identity = fit.record.target_identity)

function fit_metadata(fit::_CorrelatedMGMFRMFit; view::Symbol = :full)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    checked = _mgmfrm_correlated_2d_samples(fit)
    record, run = checked.record, checked.record.run
    spec, data = record.spec, record.spec.data
    metadata = (; family = :mgmfrm, model = checked.model,
        model_label = "Correlated MGMFRM (estimated loadings and consistency)",
        status = :experimental, estimation_status = :experimental,
        public_fit = true, experimental_public = true, fitting_available = true,
        dimensions = 2, dimension_labels = copy(spec.dimension_labels),
        q_matrix = _q_matrix_manifest(spec.q_matrix), item_structure = :between_item,
        thresholds = spec.thresholds, likelihood_scale = 1.7,
        loading_policy = :estimated_positive_fixed_q, rater_consistency = :positive_product_one,
        location = :prior_anchored, latent_correlation = :free_2d,
        parameter_space = :raw_unconstrained_and_fisher_z,
        raw_parameter_names = copy(checked.raw_parameter_names),
        direct_parameter_names = copy(checked.direct_parameter_names),
        prior = (; scales = record.prior.scales, ability = :conditional_bivariate_normal,
            other_free_coordinates = :independent_normal_raw_coordinates,
            correlation = :normalized_lkj_2d, lkj_eta = record.prior.lkj_eta,
            correlation_prior_measure = :d_rho, density_measure = :d_raw_d_zrho,
            correlation_log_jacobian = :log_one_minus_rho_squared),
        target_identity = record.target_identity, target_contract = checked.target_contract,
        n_observations = data.n, n_persons = length(data.person_levels),
        n_items = length(data.item_levels), n_raters = length(data.rater_levels),
        n_categories = length(data.category_levels), category_levels = copy(data.category_levels),
        n_parameters = run.nparams, n_direct_parameters = length(checked.direct_parameter_names),
        n_draws = run.total_draws, n_chains = run.controls.chains,
        draws_per_chain = run.controls.ndraws, warmup = run.controls.warmup,
        backend = run.backend, sampler = run.sampler, sampler_controls = deepcopy(run.controls),
        diagnostic_settings = (; run.checked..., split_chains = run.split_chains_requested),
        data_signature = spec.validation.data_signature,
        # Frozen v1 artifact baseline; live capabilities belong to surface_contract.
        supported_operations = (:posterior_summary, :direct_posterior_summary, :posterior_mcse,
            :diagnostics, :sampler_diagnostics, :fit_metadata, :fit_artifact,
            :fit_archive_manifest, :save_fit_cache, :load_fit_cache),
        scientific_acceptance = :not_established)
    return view === :full ? metadata : _public_reader_payload(metadata;
        schema = "bayesianmgmfrm.fit_metadata_public.v1", family = :mgmfrm, stability = :experimental)
end

function Base.show(io::IO, fit::_CorrelatedMGMFRMFit)
    metadata = fit_metadata(fit)
    print(io, metadata.model_label, " (", metadata.n_draws, " retained draws; ",
        metadata.backend, "; estimated rho; experimental)")
end

posterior_summary(fit::_CorrelatedMGMFRMFit; kwargs...) =
    _mgmfrm_correlated_2d_posterior_summary((; record = fit.record);
        parameter_space = :raw_unconstrained, kwargs...)
direct_posterior_summary(fit::_CorrelatedMGMFRMFit; kwargs...) =
    _mgmfrm_correlated_2d_posterior_summary((; record = fit.record);
        parameter_space = :direct_constrained, kwargs...)
posterior_mcse(fit::_CorrelatedMGMFRMFit; kwargs...) =
    _mgmfrm_correlated_2d_posterior_mcse((; record = fit.record); kwargs...)

function diagnostics(fit::_CorrelatedMGMFRMFit; view::Symbol = :full,
        split_chains::Bool = fit.record.run.split_chains_requested,
        rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        ess_threshold::Real = fit.record.run.checked.ess_threshold)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    checked = _mgmfrm_correlated_2d_samples(fit)
    run, tables = checked.record.run, checked.diagnostics
    thresholds = _check_diagnostic_thresholds(rhat_threshold, ess_threshold)
    split_chains == run.split_chains_requested && thresholds == run.checked ||
        throw(ArgumentError("diagnostics must use the stored split_chains, rhat_threshold and ess_threshold settings"))
    summary = (; diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
        diagnostic_contract_details = _mcmc_diagnostic_contract_record(),
        flag = tables.flag, passed = tables.flag === :ok,
        n_chains = run.controls.chains, draws_per_chain = run.controls.ndraws,
        total_draws = run.total_draws, tables.metric_fields...,
        n_sampler_warnings = tables.n_sampler_warnings,
        n_failed_direct_constraints = tables.n_failed_direct_constraints,
        n_divergences = tables.n_divergences, n_max_treedepth = tables.n_max_treedepth,
        tables.e_bfmi_coverage...)
    value = merge(Base.structdiff(tables, (; direct_values = nothing)), (;
        model = checked.model, backend = run.backend, summary,
        diagnostic_settings = (; thresholds..., split_chains),
        sampler_rows = run.sampler_rows,
        warmup_rows = checked.warmup_diagnostics))
    return view === :full ? deepcopy(value) : _public_reader_payload(value;
        schema = "bayesianmgmfrm.diagnostics_public.v1", family = :mgmfrm, stability = :experimental)
end

_fit_warmup_diagnostics(fit::_CorrelatedMGMFRMFit) =
    _mgmfrm_correlated_2d_samples(fit).warmup_diagnostics
function sampler_diagnostics(fit::_CorrelatedMGMFRMFit; phase::Symbol = :retained)
    phase in (:retained, :warmup) || throw(ArgumentError("phase must be :retained or :warmup"))
    checked = _mgmfrm_correlated_2d_samples(fit)
    return deepcopy(phase === :warmup ? checked.warmup_diagnostics : checked.record.run.sampler_rows)
end

function _mgmfrm_correlated_2d_artifact_payload(fit::_CorrelatedMGMFRMFit;
        include_draws::Bool, include_log_posterior::Bool, include_sampler_stats::Bool,
        include_environment::Bool, include_packages::Bool, kwargs...)
    metadata = fit_metadata(fit)
    diagnostic = diagnostics(fit; kwargs...)
    record, run = fit.record, fit.record.run
    policy = (; draws = _artifact_inclusion_flag(include_draws),
        log_posterior = _artifact_inclusion_flag(include_log_posterior),
        sampler_stats = _artifact_inclusion_flag(include_sampler_stats),
        environment = _artifact_inclusion_flag(include_environment),
        package_status = _artifact_inclusion_flag(include_environment && include_packages))
    return (; schema = "bayesianmgmfrm.correlated_mgmfrm_fit_artifact.v1",
        object = :fit_artifact, family = :mgmfrm, model = metadata.model, status = :experimental,
        manifest = (; object = :fit, family = :mgmfrm, model = metadata.target_contract,
            fit = metadata, diagnostics = diagnostic.summary),
        diagnostics = diagnostic, posterior_summary = posterior_summary(fit),
        direct_posterior_summary = direct_posterior_summary(fit),
        reproducibility = (; data_signature = metadata.data_signature,
            target_identity = record.target_identity, source_sample_schema = record.schema,
            source_sample_content_hash = record.content_hash, prior = metadata.prior,
            sampler_controls = deepcopy(run.controls), diagnostic_policy = metadata.diagnostic_settings,
            artifact_policy = policy),
        draws = include_draws ? copy(run.draws) : nothing,
        log_posterior = include_log_posterior ? copy(run.logdensities) : nothing,
        sampler_stats = include_sampler_stats ? deepcopy(run.sampler_stats) : nothing,
        warmup_stats = include_sampler_stats ? deepcopy(run.warmup_stats) : nothing)
end

function fit_artifact(fit::_CorrelatedMGMFRMFit; view::Symbol = :full,
        include_draws::Bool = false, include_log_posterior::Bool = include_draws,
        include_sampler_stats::Bool = false, include_environment::Bool = true,
        include_packages::Bool = false, include_environment_paths::Bool = false, kwargs...)
    view === :full || throw(ArgumentError("correlated MGMFRM fit_artifact currently supports view = :full only"))
    payload = _mgmfrm_correlated_2d_artifact_payload(fit; include_draws, include_log_posterior,
        include_sampler_stats, include_environment, include_packages, kwargs...)
    environment = include_environment ? evidence_metadata(;
        include_packages, include_paths = include_environment_paths) : nothing
    return _with_archive_metadata(merge(payload, (; created_at = string(now()), environment));
        label = :correlated_mgmfrm_fit_artifact)
end

function fit_archive_manifest(fit::_CorrelatedMGMFRMFit;
        label = nothing, source_path = nothing, artifact = nothing, kwargs...)
    value = artifact === nothing ? fit_artifact(fit; kwargs...) : artifact
    return fit_archive_manifest(value; label, source_path)
end

function save_fit_cache(path::AbstractString, fit::_CorrelatedMGMFRMFit;
        artifact_split_chains::Bool = fit.record.run.split_chains_requested,
        artifact_rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        artifact_ess_threshold::Real = fit.record.run.checked.ess_threshold, kwargs...)
    snapshot = _CorrelatedMGMFRMFit(fit.record; expected_identity = fit.record.target_identity)
    return _save_fit_cache(path, snapshot; artifact_split_chains,
        artifact_rhat_threshold, artifact_ess_threshold, kwargs...)
end

function _fit_cache_record(fit::_CorrelatedMGMFRMFit; cache_key, artifact, source_path = nothing)
    artifact isa NamedTuple || throw(ArgumentError("correlated MGMFRM cache artifact must be a NamedTuple"))
    archive_manifest = fit_archive_manifest(artifact; label = :fit_cache_artifact, source_path)
    record = (; schema = "bayesianmgmfrm.correlated_mgmfrm_fit_cache.v1", object = :fit_cache,
        created_at = string(now()), serialization = (; format = :julia_serialization,
            julia_version = string(VERSION), portability = :same_julia_major_minor_recommended),
        cache_key = cache_key === nothing ? missing : String(cache_key),
        target_identity = fit.record.target_identity,
        source_sample_content_hash = fit.record.content_hash,
        artifact_content_hash = archive_manifest.content_hash, archive_manifest, fit, artifact)
    context = source_path === nothing ? "correlated MGMFRM fit cache" : String(source_path)
    _check_fit_cache_record(record, context)
    return _verify_fit_cache_record(record, context)
end

Base.@nospecializeinfer function _check_mgmfrm_correlated_2d_cache_record(@nospecialize(record::NamedTuple), path)
    keys(record) == (:schema, :object, :created_at, :serialization, :cache_key,
        :target_identity, :source_sample_content_hash, :artifact_content_hash,
        :archive_manifest, :fit, :artifact) && record.fit isa _CorrelatedMGMFRMFit &&
        record.artifact isa NamedTuple && record.created_at isa AbstractString &&
        (ismissing(record.cache_key) || record.cache_key isa AbstractString) ||
        throw(ArgumentError("invalid correlated MGMFRM fit-cache contract at $path"))
    checked = _mgmfrm_correlated_2d_samples(record.fit)
    record.target_identity == checked.record.target_identity &&
        record.source_sample_content_hash == checked.record.content_hash ||
        throw(ArgumentError("correlated MGMFRM cache source/target mismatch at $path"))
    serialization = record.serialization
    serialization isa NamedTuple && keys(serialization) == (:format, :julia_version, :portability) &&
        serialization.format === :julia_serialization && serialization.julia_version isa AbstractString &&
        serialization.portability === :same_julia_major_minor_recommended ||
        throw(ArgumentError("invalid correlated MGMFRM serialization metadata at $path"))
    artifact = record.artifact
    reproducibility = _nt_get(artifact, :reproducibility, nothing)
    policy = reproducibility isa NamedTuple ? _nt_get(reproducibility, :artifact_policy, nothing) : nothing
    policy isa NamedTuple && keys(policy) == (:draws, :log_posterior, :sampler_stats, :environment, :package_status) &&
        all(flag -> flag isa Symbol && flag in (:included, :omitted), values(policy)) &&
        _nt_get(artifact, :created_at, nothing) isa AbstractString && hasproperty(artifact, :environment) ||
        throw(ArgumentError("invalid correlated MGMFRM artifact policy at $path"))
    (policy.environment === :included ? artifact.environment isa AbstractDict : artifact.environment === nothing) ||
        throw(ArgumentError("correlated MGMFRM artifact environment policy mismatch at $path"))
    expected = _mgmfrm_correlated_2d_artifact_payload(record.fit;
        include_draws = policy.draws === :included, include_log_posterior = policy.log_posterior === :included,
        include_sampler_stats = policy.sampler_stats === :included, include_environment = policy.environment === :included,
        include_packages = policy.package_status === :included)
    excluded = (; created_at = nothing, environment = nothing, content_hash = nothing, archive_manifest = nothing)
    isequal(Base.structdiff(artifact, excluded), expected) ||
        throw(ArgumentError("correlated MGMFRM artifact does not match its saved fit at $path"))
    for (archive, label) in ((record.archive_manifest, :fit_cache_artifact),
            (_nt_get(artifact, :archive_manifest, nothing), :correlated_mgmfrm_fit_artifact))
        archive isa NamedTuple && _nt_get(archive, :created_at, nothing) isa AbstractString &&
            hasproperty(archive, :source_path) && (ismissing(archive.source_path) || archive.source_path isa AbstractString) ||
            throw(ArgumentError("invalid correlated MGMFRM archive at $path"))
        fields = (; created_at = nothing, source_path = nothing)
        isequal(Base.structdiff(archive, fields),
            Base.structdiff(fit_archive_manifest(artifact; label), fields)) ||
            throw(ArgumentError("correlated MGMFRM archive does not match its artifact at $path"))
    end
    return record
end
