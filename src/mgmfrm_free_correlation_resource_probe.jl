# mgmfrm_free_correlation_resource_probe.jl -- MCMC-free operational profiling.

const _FREE_CORRELATION_STUDY_RESOURCE_PROBE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe.v1"

const _FREE_CORRELATION_STUDY_RESOURCE_PROBE_FIELDS = (
    :schema,
    :object,
    :status,
    :plan_id,
    :plan_fingerprint,
    :unit_id,
    :phase,
    :rho_truth,
    :replication,
    :execute_measurement,
    :repetitions,
    :policy,
    :measurement_plan,
    :runtime,
    :provenance,
    :measurement,
    :checks,
    :profile_thresholds_passed,
    :operational_execution_authorized,
    :scientific_execution_authorized,
    :blockers,
    :fixture_generated,
    :gradient_executed,
    :mcmc_executed,
    :recovery_evidence_available,
    :public_fit,
    :fit_ready,
    :cache_enabled,
    :promotion_effect,
    :artifact_sha256,
)

function _free_correlation_resource_probe_checked_repetitions(
        repetitions,
        policy)
    checked = _free_correlation_checked_integer(
        repetitions,
        :repetitions;
        minimum = policy.minimum_repetitions,
    )
    checked <= policy.maximum_repetitions || throw(ArgumentError(
        "repetitions exceeds the frozen resource-probe maximum",
    ))
    return checked
end

function _free_correlation_resource_probe_fixture_kwargs(unit)
    return (;
        n_persons = unit.design.n_persons,
        items_per_dimension = unit.design.items_per_dimension,
        n_raters = unit.design.n_raters,
        n_categories = unit.design.n_categories,
        rho_truth = unit.rho_truth,
        ability_seed = unit.seeds.ability,
        response_seed = unit.seeds.response,
        lkj_eta = unit.primary_lkj_eta,
        max_observations = unit.design.n_observations,
        max_probability_cells = unit.design.n_probability_cells,
    )
end

function _free_correlation_resource_probe_measurement_plan(
        unit,
        policy,
        repetitions::Int)
    return (;
        phase = policy.phase,
        fixture_kwargs = _free_correlation_resource_probe_fixture_kwargs(unit),
        operation = policy.operation,
        target_state = :candidate_initial_params,
        initial_value = 0.0,
        initial_zrho = 0.0,
        ad_backend = policy.ad_backend,
        adapter_validation_evaluations =
            policy.adapter_validation_evaluations,
        warmup_evaluations = policy.warmup_evaluations,
        timed_evaluations = repetitions,
        gc_before_each_timed_evaluation =
            policy.gc_before_each_timed_evaluation,
        mcmc_allowed = policy.mcmc_allowed,
    )
end

function _free_correlation_resource_probe_measure_candidate(
        candidate::_MGMFRMFreeLatentCorrelation2DLogDensity,
        repetitions::Int;
        ad_backend::Symbol = :ForwardDiff,
        warmup_evaluations::Int = 1,
        gc_before_each_timed_evaluation::Bool = true)
    1 <= repetitions <= 5 || throw(ArgumentError(
        "internal resource-probe repetitions must be in 1:5",
    ))
    warmup_evaluations >= 1 || throw(ArgumentError(
        "resource-probe warmup_evaluations must be positive",
    ))
    initial = initial_params(candidate; value = 0.0, zrho = 0.0)
    dimension = LogDensityProblems.dimension(candidate)
    length(initial) == dimension || throw(ArgumentError(
        "resource-probe initial parameter dimension is inconsistent",
    ))
    adapter = _logdensity_gradient_target(
        candidate,
        initial,
        ad_backend,
    ).target
    for _ in 1:warmup_evaluations
        logdensity, gradient =
            LogDensityProblems.logdensity_and_gradient(adapter, initial)
        isfinite(logdensity) && length(gradient) == dimension &&
            all(isfinite, gradient) || throw(ArgumentError(
            "resource-probe warmup returned a non-finite gradient payload",
        ))
    end

    gc_before_each_timed_evaluation && GC.gc()
    free_memory_before = UInt64(Sys.free_memory())
    total_memory = UInt64(Sys.total_memory())
    rows = NamedTuple[]
    for repetition in 1:repetitions
        gc_before_each_timed_evaluation && GC.gc()
        timed = @timed LogDensityProblems.logdensity_and_gradient(
            adapter,
            initial,
        )
        logdensity, gradient = timed.value
        elapsed_seconds = Float64(timed.time)
        gc_seconds = Float64(timed.gctime)
        gc_time_fraction = iszero(elapsed_seconds) ? 0.0 :
            gc_seconds / elapsed_seconds
        push!(rows, (;
            repetition,
            elapsed_seconds,
            allocated_bytes = Int(timed.bytes),
            gc_seconds,
            gc_time_fraction,
            logdensity = Float64(logdensity),
            gradient_length = length(gradient),
            gradient_finite = all(isfinite, gradient),
            maximum_absolute_gradient =
                maximum(abs, gradient; init = 0.0),
        ))
    end
    free_memory_after = UInt64(Sys.free_memory())
    minimum_free_memory = min(free_memory_before, free_memory_after)
    timed_rows = Tuple(rows)
    return (;
        initial_parameter_dimension = dimension,
        adapter_validation_evaluations = 1,
        warmup_evaluations,
        timed_evaluations = repetitions,
        free_memory_bytes_before = free_memory_before,
        free_memory_bytes_after = free_memory_after,
        minimum_free_memory_bytes_observed = minimum_free_memory,
        total_memory_bytes = total_memory,
        timed_rows,
        median_gradient_seconds = median(
            row.elapsed_seconds for row in timed_rows
        ),
        median_allocated_bytes = median(
            row.allocated_bytes for row in timed_rows
        ),
        median_gc_time_fraction = median(
            row.gc_time_fraction for row in timed_rows
        ),
    )
end

function _free_correlation_resource_probe_runtime(profile)
    return (;
        julia_version = string(VERSION),
        n_threads = Threads.nthreads(),
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
        free_memory_bytes_before = profile.free_memory_bytes_before,
        free_memory_bytes_after = profile.free_memory_bytes_after,
        minimum_free_memory_bytes_observed =
            profile.minimum_free_memory_bytes_observed,
        total_memory_bytes = profile.total_memory_bytes,
    )
end

function _free_correlation_resource_probe_provenance(runtime)
    environment = _free_correlation_study_environment_files()
    sources = _free_correlation_study_source_digests()
    material = (;
        runtime,
        environment,
        sources,
        environment_sha256 = artifact_content_hash(environment),
        sources_sha256 = artifact_content_hash(sources),
    )
    return merge(material, (;
        provenance_sha256 = artifact_content_hash(material),
    ))
end

function _free_correlation_resource_probe_checks(
        measurement,
        unit,
        policy,
        repetitions::Int)
    profile = measurement.gradient_profile
    rows = profile.timed_rows
    estimated_full_unit_seconds = profile.median_gradient_seconds *
        policy.planning_gradients_per_transition *
        policy.planned_transitions_per_full_unit
    timed_repetitions_exact = length(rows) == repetitions &&
        Tuple(row.repetition for row in rows) == Tuple(1:repetitions)
    all_gradients_finite = all(row ->
        row.gradient_finite && isfinite(row.logdensity) &&
            isfinite(row.maximum_absolute_gradient), rows)
    gradient_dimensions_exact = all(
        row -> row.gradient_length == profile.initial_parameter_dimension,
        rows,
    )
    fixture_counts_exact =
        measurement.data_counts == (;
            n_observations = unit.design.n_observations,
            n_probability_cells = unit.design.n_probability_cells,
        )
    candidate_dimension_exact =
        profile.initial_parameter_dimension ==
            policy.expected_raw_parameter_dimension
    fixture_schema_valid =
        measurement.fixture.schema == _FREE_CORRELATION_FIXTURE_SCHEMA &&
        measurement.fixture.status === :known_truth_generated
    fixture_data_signature_valid =
        measurement.fixture.data_signature isa AbstractString &&
        occursin(r"^[0-9a-f]{16}$", measurement.fixture.data_signature)
    fixture_oracle_identity_passed =
        measurement.fixture.maximum_closed_form_oracle_error isa Real &&
        isfinite(measurement.fixture.maximum_closed_form_oracle_error) &&
        0 <= measurement.fixture.maximum_closed_form_oracle_error <= 1e-12
    fixture_realized_correlation_valid =
        measurement.fixture.realized_latent_correlation isa Real &&
        isfinite(measurement.fixture.realized_latent_correlation) &&
        -1 < measurement.fixture.realized_latent_correlation < 1
    profile_summaries_exact =
        profile.median_gradient_seconds == median(
            row.elapsed_seconds for row in rows
        ) &&
        profile.median_allocated_bytes == median(
            row.allocated_bytes for row in rows
        ) &&
        profile.median_gc_time_fraction == median(
            row.gc_time_fraction for row in rows
        ) &&
        profile.minimum_free_memory_bytes_observed == min(
            profile.free_memory_bytes_before,
            profile.free_memory_bytes_after,
        )
    median_gradient_seconds_passed =
        profile.median_gradient_seconds <=
            policy.maximum_median_gradient_seconds
    median_allocated_bytes_passed =
        profile.median_allocated_bytes <=
            policy.maximum_median_allocated_bytes
    median_gc_time_fraction_passed =
        profile.median_gc_time_fraction <=
            policy.maximum_median_gc_time_fraction
    free_memory_passed =
        profile.minimum_free_memory_bytes_observed >=
            policy.minimum_free_memory_bytes
    estimated_full_unit_seconds_passed =
        estimated_full_unit_seconds <=
            policy.maximum_estimated_full_unit_seconds
    all_thresholds_passed = timed_repetitions_exact &&
        all_gradients_finite && gradient_dimensions_exact &&
        fixture_counts_exact && candidate_dimension_exact &&
        fixture_schema_valid && fixture_data_signature_valid &&
        fixture_oracle_identity_passed &&
        fixture_realized_correlation_valid && profile_summaries_exact &&
        median_gradient_seconds_passed &&
        median_allocated_bytes_passed &&
        median_gc_time_fraction_passed && free_memory_passed &&
        estimated_full_unit_seconds_passed
    return (;
        measurement_completed = true,
        timed_repetitions_exact,
        all_gradients_finite,
        gradient_dimensions_exact,
        fixture_counts_exact,
        candidate_dimension_exact,
        fixture_schema_valid,
        fixture_data_signature_valid,
        fixture_oracle_identity_passed,
        fixture_realized_correlation_valid,
        profile_summaries_exact,
        median_gradient_seconds_passed,
        median_allocated_bytes_passed,
        median_gc_time_fraction_passed,
        free_memory_passed,
        estimated_full_unit_seconds,
        estimated_full_unit_seconds_passed,
        all_thresholds_passed,
    )
end

function _free_correlation_resource_probe_not_measured_checks()
    return (;
        measurement_completed = false,
        timed_repetitions_exact = missing,
        all_gradients_finite = missing,
        gradient_dimensions_exact = missing,
        fixture_counts_exact = missing,
        candidate_dimension_exact = missing,
        fixture_schema_valid = missing,
        fixture_data_signature_valid = missing,
        fixture_oracle_identity_passed = missing,
        fixture_realized_correlation_valid = missing,
        profile_summaries_exact = missing,
        median_gradient_seconds_passed = missing,
        median_allocated_bytes_passed = missing,
        median_gc_time_fraction_passed = missing,
        free_memory_passed = missing,
        estimated_full_unit_seconds = missing,
        estimated_full_unit_seconds_passed = missing,
        all_thresholds_passed = false,
    )
end

function _free_correlation_resource_probe_artifact(
        plan,
        unit,
        repetitions::Int;
        runtime = missing,
        provenance = missing,
        measurement = missing)
    executed = !ismissing(measurement)
    policy = merge(plan.resource_policy.initial_gradient_probe, (;
        expected_raw_parameter_dimension =
            plan.resource_policy.estimated_raw_parameter_dimension_per_unit,
    ))
    checks = executed ? _free_correlation_resource_probe_checks(
        measurement,
        unit,
        policy,
        repetitions,
    ) : _free_correlation_resource_probe_not_measured_checks()
    profile_thresholds_passed = checks.all_thresholds_passed
    blockers = !executed ? (
        :initial_gradient_resource_probe_not_measured,
        :resource_profile_and_atomic_runner_pending,
    ) : profile_thresholds_passed ? (
        :resource_profile_and_atomic_runner_pending,
    ) : (
        :initial_gradient_resource_thresholds_not_met,
        :resource_profile_and_atomic_runner_pending,
    )
    status = !executed ?
        :resource_probe_planned_measurement_not_executed :
        profile_thresholds_passed ?
            :initial_gradient_profile_passed_operational_gate_still_blocked :
            :initial_gradient_profile_failed_operational_gate_blocked
    material = (;
        schema = _FREE_CORRELATION_STUDY_RESOURCE_PROBE_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_resource_probe,
        status,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        rho_truth = unit.rho_truth,
        replication = unit.replication,
        execute_measurement = executed,
        repetitions,
        policy,
        measurement_plan = _free_correlation_resource_probe_measurement_plan(
            unit,
            policy,
            repetitions,
        ),
        runtime,
        provenance,
        measurement,
        checks,
        profile_thresholds_passed,
        operational_execution_authorized = false,
        scientific_execution_authorized = false,
        blockers,
        fixture_generated = executed,
        gradient_executed = executed,
        mcmc_executed = false,
        recovery_evidence_available = false,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        promotion_effect = :none,
    )
    return merge(material, (;
        artifact_sha256 = artifact_content_hash(material),
    ))
end

function _validate_free_correlation_study_resource_probe(
        artifact,
        plan,
        unit_id)
    checked_plan = _validate_free_correlation_study_plan(plan)
    unit_id isa AbstractString || throw(ArgumentError(
        "resource-probe unit_id must be a string",
    ))
    unit = _free_correlation_study_unit(checked_plan, unit_id)
    unit.phase === checked_plan.resource_policy.initial_gradient_probe.phase ||
        throw(ArgumentError(
            "resource probing is restricted to the frozen feasibility phase",
        ))
    _free_correlation_study_exact_fields(
        artifact,
        _FREE_CORRELATION_STUDY_RESOURCE_PROBE_FIELDS,
        "free-correlation resource-probe artifact",
    )
    artifact.schema == _FREE_CORRELATION_STUDY_RESOURCE_PROBE_SCHEMA ||
        throw(ArgumentError("resource-probe artifact has the wrong schema"))
    artifact.object ===
        :mgmfrm_free_latent_correlation_2d_study_resource_probe ||
        throw(ArgumentError("resource-probe object was modified"))
    artifact.plan_id == checked_plan.plan_id &&
        artifact.plan_fingerprint == checked_plan.plan_fingerprint ||
        throw(ArgumentError("resource-probe plan binding was modified"))
    artifact.unit_id == unit.unit_id && artifact.phase === unit.phase &&
        artifact.rho_truth == unit.rho_truth &&
        artifact.replication == unit.replication || throw(ArgumentError(
        "resource-probe unit binding was modified",
    ))
    repetitions = _free_correlation_resource_probe_checked_repetitions(
        artifact.repetitions,
        checked_plan.resource_policy.initial_gradient_probe,
    )
    expected_policy = merge(
        checked_plan.resource_policy.initial_gradient_probe,
        (;
            expected_raw_parameter_dimension = checked_plan.resource_policy.
                estimated_raw_parameter_dimension_per_unit,
        ),
    )
    isequal(artifact.policy, expected_policy) || throw(ArgumentError(
        "resource-probe policy was modified",
    ))
    isequal(
        artifact.measurement_plan,
        _free_correlation_resource_probe_measurement_plan(
            unit,
            expected_policy,
            repetitions,
        ),
    ) || throw(ArgumentError("resource-probe measurement plan was modified"))
    artifact.mcmc_executed === false &&
        artifact.recovery_evidence_available === false &&
        artifact.operational_execution_authorized === false &&
        artifact.scientific_execution_authorized === false &&
        artifact.public_fit === false && artifact.fit_ready === false &&
        artifact.cache_enabled === false &&
        artifact.promotion_effect === :none || throw(ArgumentError(
        "resource-probe quarantine flags were modified",
    ))

    if artifact.execute_measurement === false
        ismissing(artifact.runtime) && ismissing(artifact.provenance) &&
            ismissing(artifact.measurement) || throw(ArgumentError(
            "unexecuted resource probe must not contain measurements",
        ))
    elseif artifact.execute_measurement === true
        runtime = _free_correlation_study_exact_fields(
            artifact.runtime,
            (
                :julia_version,
                :n_threads,
                :os,
                :arch,
                :free_memory_bytes_before,
                :free_memory_bytes_after,
                :minimum_free_memory_bytes_observed,
                :total_memory_bytes,
            ),
            "resource-probe runtime",
        )
        VersionNumber(runtime.julia_version)
        runtime.n_threads isa Integer && !(runtime.n_threads isa Bool) &&
            runtime.n_threads >= 1 || throw(ArgumentError(
            "resource-probe thread count is invalid",
        ))
        for field in (
                :free_memory_bytes_before,
                :free_memory_bytes_after,
                :minimum_free_memory_bytes_observed,
                :total_memory_bytes)
            value = getproperty(runtime, field)
            value isa Integer && !(value isa Bool) && value >= 0 ||
                throw(ArgumentError(
                    "resource-probe memory fields must be nonnegative integers",
                ))
        end
        runtime.minimum_free_memory_bytes_observed == min(
            runtime.free_memory_bytes_before,
            runtime.free_memory_bytes_after,
        ) || throw(ArgumentError(
            "resource-probe minimum free-memory field is inconsistent",
        ))
        provenance = _free_correlation_study_exact_fields(
            artifact.provenance,
            (
                :runtime,
                :environment,
                :sources,
                :environment_sha256,
                :sources_sha256,
                :provenance_sha256,
            ),
            "resource-probe provenance",
        )
        isequal(provenance.runtime, runtime) || throw(ArgumentError(
            "resource-probe runtime is not bound into provenance",
        ))
        provenance.sources isa Tuple &&
            Tuple(row.path for row in provenance.sources) ==
                _FREE_CORRELATION_STUDY_SOURCE_PATHS || throw(ArgumentError(
            "resource-probe source roster was modified",
        ))
        provenance.environment_sha256 ==
            artifact_content_hash(provenance.environment) &&
            provenance.sources_sha256 ==
                artifact_content_hash(provenance.sources) ||
            throw(ArgumentError("resource-probe provenance digests were modified"))
        for digest in (
                provenance.environment_sha256,
                provenance.sources_sha256,
                provenance.provenance_sha256)
            _free_correlation_study_sha256(
                digest,
                "resource-probe provenance hash",
            )
        end
        provenance_material = Base.structdiff(
            provenance,
            (; provenance_sha256 = nothing),
        )
        provenance.provenance_sha256 ==
            artifact_content_hash(provenance_material) || throw(ArgumentError(
            "resource-probe provenance aggregate was modified",
        ))
        measurement = _free_correlation_study_exact_fields(
            artifact.measurement,
            (:fixture, :data_counts, :gradient_profile),
            "resource-probe measurement",
        )
        fixture = _free_correlation_study_exact_fields(
            measurement.fixture,
            (
                :schema,
                :status,
                :data_signature,
                :realized_latent_correlation,
                :maximum_closed_form_oracle_error,
            ),
            "resource-probe fixture measurement",
        )
        fixture.schema == _FREE_CORRELATION_FIXTURE_SCHEMA &&
            fixture.status === :known_truth_generated || throw(ArgumentError(
            "resource-probe fixture identity was modified",
        ))
        fixture.data_signature isa AbstractString &&
            occursin(r"^[0-9a-f]{16}$", fixture.data_signature) ||
            throw(ArgumentError(
                "resource-probe data_signature must be lowercase 16-hex",
            ))
        fixture.realized_latent_correlation isa Real &&
            isfinite(fixture.realized_latent_correlation) &&
            -1 < fixture.realized_latent_correlation < 1 ||
            throw(ArgumentError(
                "resource-probe realized correlation is invalid",
            ))
        fixture.maximum_closed_form_oracle_error isa Real &&
            isfinite(fixture.maximum_closed_form_oracle_error) &&
            0 <= fixture.maximum_closed_form_oracle_error <= 1e-12 ||
            throw(ArgumentError(
                "resource-probe fixture oracle identity is invalid",
            ))
        _free_correlation_study_exact_fields(
            measurement.data_counts,
            (:n_observations, :n_probability_cells),
            "resource-probe data counts",
        )
        measurement.data_counts == (;
            n_observations = unit.design.n_observations,
            n_probability_cells = unit.design.n_probability_cells,
        ) || throw(ArgumentError(
            "resource-probe data counts do not match the fixed unit",
        ))
        profile = _free_correlation_study_exact_fields(
            measurement.gradient_profile,
            (
                :initial_parameter_dimension,
                :adapter_validation_evaluations,
                :warmup_evaluations,
                :timed_evaluations,
                :free_memory_bytes_before,
                :free_memory_bytes_after,
                :minimum_free_memory_bytes_observed,
                :total_memory_bytes,
                :timed_rows,
                :median_gradient_seconds,
                :median_allocated_bytes,
                :median_gc_time_fraction,
            ),
            "resource-probe gradient profile",
        )
        profile.adapter_validation_evaluations ==
            expected_policy.adapter_validation_evaluations &&
            profile.warmup_evaluations ==
                expected_policy.warmup_evaluations &&
            profile.timed_evaluations == repetitions &&
            profile.initial_parameter_dimension ==
                expected_policy.expected_raw_parameter_dimension ||
            throw(ArgumentError(
            "resource-probe evaluation counts were modified",
        ))
        profile.free_memory_bytes_before ==
            runtime.free_memory_bytes_before &&
            profile.free_memory_bytes_after ==
                runtime.free_memory_bytes_after &&
            profile.minimum_free_memory_bytes_observed ==
                runtime.minimum_free_memory_bytes_observed &&
            profile.total_memory_bytes == runtime.total_memory_bytes ||
            throw(ArgumentError(
                "resource-probe profile memory is not bound to runtime",
            ))
        profile.timed_rows isa Tuple &&
            length(profile.timed_rows) == repetitions || throw(ArgumentError(
            "resource-probe timed rows were modified",
        ))
        for (index, row) in pairs(profile.timed_rows)
            _free_correlation_study_exact_fields(
                row,
                (
                    :repetition,
                    :elapsed_seconds,
                    :allocated_bytes,
                    :gc_seconds,
                    :gc_time_fraction,
                    :logdensity,
                    :gradient_length,
                    :gradient_finite,
                    :maximum_absolute_gradient,
                ),
                "resource-probe timed row",
            )
            row.repetition == index &&
                row.elapsed_seconds isa Real &&
                isfinite(row.elapsed_seconds) && row.elapsed_seconds >= 0 &&
                row.allocated_bytes isa Integer &&
                !(row.allocated_bytes isa Bool) && row.allocated_bytes >= 0 &&
                row.gc_seconds isa Real && isfinite(row.gc_seconds) &&
                row.gc_seconds >= 0 &&
                row.gc_time_fraction isa Real &&
                isfinite(row.gc_time_fraction) &&
                row.gc_time_fraction >= 0 &&
                row.gradient_length == profile.initial_parameter_dimension &&
                row.gradient_finite === true || throw(ArgumentError(
                "resource-probe timed row is invalid",
            ))
        end
        isequal(
            artifact.checks,
            _free_correlation_resource_probe_checks(
                measurement,
                unit,
                expected_policy,
                repetitions,
            ),
        ) || throw(ArgumentError("resource-probe checks were modified"))
    else
        throw(ArgumentError("execute_measurement must be Bool"))
    end

    expected = _free_correlation_resource_probe_artifact(
        checked_plan,
        unit,
        repetitions;
        runtime = artifact.runtime,
        provenance = artifact.provenance,
        measurement = artifact.measurement,
    )
    isequal(
        Base.structdiff(artifact, (; artifact_sha256 = nothing)),
        Base.structdiff(expected, (; artifact_sha256 = nothing)),
    ) || throw(ArgumentError("resource-probe derived fields were modified"))
    _free_correlation_study_sha256(
        artifact.artifact_sha256,
        "resource-probe artifact hash",
    )
    artifact.artifact_sha256 == artifact_content_hash(
        Base.structdiff(artifact, (; artifact_sha256 = nothing)),
    ) || throw(ArgumentError("resource-probe artifact hash was modified"))
    return artifact
end

function _mgmfrm_free_latent_correlation_2d_study_resource_probe(
        plan,
        unit_id;
        execute_measurement::Bool = false,
        repetitions = 3)
    checked_plan = _validate_free_correlation_study_plan(plan)
    unit_id isa AbstractString || throw(ArgumentError(
        "resource-probe unit_id must be a string",
    ))
    unit = _free_correlation_study_unit(checked_plan, unit_id)
    policy = checked_plan.resource_policy.initial_gradient_probe
    unit.phase === policy.phase || throw(ArgumentError(
        "resource probing is restricted to the frozen feasibility phase",
    ))
    checked_repetitions =
        _free_correlation_resource_probe_checked_repetitions(
            repetitions,
            policy,
        )
    if !execute_measurement
        artifact = _free_correlation_resource_probe_artifact(
            checked_plan,
            unit,
            checked_repetitions,
        )
        return _validate_free_correlation_study_resource_probe(
            artifact,
            checked_plan,
            unit.unit_id,
        )
    end

    fixture = _mgmfrm_free_latent_correlation_2d_known_truth_fixture(;
        _free_correlation_resource_probe_fixture_kwargs(unit)...,
    )
    profile = _free_correlation_resource_probe_measure_candidate(
        fixture.candidate,
        checked_repetitions;
        ad_backend = policy.ad_backend,
        warmup_evaluations = policy.warmup_evaluations,
        gc_before_each_timed_evaluation =
            policy.gc_before_each_timed_evaluation,
    )
    runtime = _free_correlation_resource_probe_runtime(profile)
    provenance = _free_correlation_resource_probe_provenance(runtime)
    generation_evidence =
        _free_correlation_study_generation_evidence(fixture)
    measurement = (;
        fixture = (;
            schema = generation_evidence.fixture_schema,
            status = fixture.status,
            data_signature = generation_evidence.data_signature,
            realized_latent_correlation =
                generation_evidence.realized_latent_correlation,
            maximum_closed_form_oracle_error =
                generation_evidence.maximum_closed_form_oracle_error,
        ),
        data_counts = (;
            n_observations = fixture.data.n,
            n_probability_cells =
                fixture.data.n * length(fixture.data.category_levels),
        ),
        gradient_profile = profile,
    )
    artifact = _free_correlation_resource_probe_artifact(
        checked_plan,
        unit,
        checked_repetitions;
        runtime,
        provenance,
        measurement,
    )
    return _validate_free_correlation_study_resource_probe(
        artifact,
        checked_plan,
        unit.unit_id,
    )
end
