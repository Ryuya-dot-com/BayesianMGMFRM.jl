# mgmfrm_free_correlation_study.jl -- quarantined replicated-study planning.

const _FREE_CORRELATION_STUDY_PLAN_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_plan.v2"
const _FREE_CORRELATION_STUDY_LEDGER_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_ledger.v2"
const _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_unit_result.v2"
const _FREE_CORRELATION_STUDY_EXECUTION_PROVENANCE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_execution_provenance.v2"
const _FREE_CORRELATION_STUDY_SAMPLE_DIGEST_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_sample_digest.v1"
const _FREE_CORRELATION_STUDY_SAMPLE_BUNDLE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_sample_bundle.v1"
const _FREE_CORRELATION_STUDY_UNIT_PREFLIGHT_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_unit_preflight.v2"
const _FREE_CORRELATION_STUDY_FEASIBILITY_DECISION_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_feasibility_decision.v2"
const _FREE_CORRELATION_STUDY_DRY_RUN_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_dry_run.v2"
const _FREE_CORRELATION_STUDY_PLAN_ID =
    "mgmfrm_free_latent_correlation_2d_recovery_study_v2"
const _FREE_CORRELATION_STUDY_V2_EXPECTED_PLAN_FINGERPRINT =
    "d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3"
const _FREE_CORRELATION_STUDY_V2_EXPECTED_UNIT_ROSTER_SHA256 =
    "0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08"
const _FREE_CORRELATION_STUDY_RHO_GRID = (-0.6, -0.3, 0.0, 0.3, 0.6)
const _FREE_CORRELATION_STUDY_FEASIBILITY_REPLICATIONS = 5
const _FREE_CORRELATION_STUDY_EVALUATION_REPLICATIONS = 100
const _FREE_CORRELATION_STUDY_DRY_RUN_HARD_MAX_UNITS = 10
const _FREE_CORRELATION_STUDY_TERMINAL_STATUSES = (
    :completed,
    :generation_failed,
    :fit_failed,
    :diagnostic_failed,
    :recovery_scoring_failed,
)
const _FREE_CORRELATION_STUDY_SOURCE_PATHS = (
    "src/BayesianMGMFRM.jl",
    "src/evidence_metadata.jl",
    "src/facet_workflow.jl",
    "src/model_contract.jl",
    "src/bayesian_fit.jl",
    "src/mgmfrm_free_correlation_candidate.jl",
    "src/mgmfrm_free_correlation_recovery.jl",
    "src/mgmfrm_free_correlation_study.jl",
    "src/mgmfrm_free_correlation_resource_probe.jl",
    "src/mgmfrm_free_correlation_study_scoring.jl",
    "src/experimental.jl",
)
const _FREE_CORRELATION_STUDY_SAMPLE_ARRAY_FIELDS = (
    :initial_raw_parameter_values,
    :chain_initials,
    :chain_initial_logdensity,
    :draws,
    :base_draws,
    :zrho_draws,
    :rho_draws,
    :logdensity,
    :reevaluated_logdensity,
    :pointwise_loglikelihood,
    :direct_draws,
    :direct_pointwise_loglikelihood,
    :direct_loglikelihood,
    :candidate_loglikelihood,
    :chain_ids,
    :iterations,
    :chain_acceptance_rate,
)
const _FREE_CORRELATION_STUDY_SAMPLE_TELEMETRY_FIELDS = (
    :sampler_controls,
    :sampler_stats,
    :sampler_rows,
    :logdensity_revalidation,
    :direct_constraint_rows,
    :likelihood_identity,
    :pointwise_identity,
    :summary,
)
const _FREE_CORRELATION_STUDY_SAMPLE_METADATA_FIELDS = (
    :schema,
    :family,
    :scope,
    :status,
    :backend,
    :sampler,
    :diagnostic_status,
    :claim_scope,
    :public_fit,
    :fit_ready,
    :cache_enabled,
    :result_type,
    :convergence_evaluated,
    :recovery_verified,
    :raw_parameter_names,
    :initial_logdensity,
)
const _FREE_CORRELATION_STUDY_SAMPLE_BUNDLE_FIELDS = (
    _FREE_CORRELATION_STUDY_SAMPLE_METADATA_FIELDS...,
    _FREE_CORRELATION_STUDY_SAMPLE_ARRAY_FIELDS...,
    _FREE_CORRELATION_STUDY_SAMPLE_TELEMETRY_FIELDS...,
)

function _free_correlation_study_rho_label(rho::Float64)
    rho == -0.6 && return "m060"
    rho == -0.3 && return "m030"
    rho == 0.0 && return "z000"
    rho == 0.3 && return "p030"
    rho == 0.6 && return "p060"
    throw(ArgumentError("rho is not in the frozen free-correlation study grid"))
end

function _free_correlation_study_unit_id(
        phase::Symbol,
        rho::Float64,
        replication::Int)
    phase in (:feasibility, :evaluation) || throw(ArgumentError(
        "study phase must be :feasibility or :evaluation",
    ))
    replication >= 1 || throw(ArgumentError(
        "study replication must be positive",
    ))
    return string(
        "mgmfrm_freecorr_",
        phase,
        "_rho_",
        _free_correlation_study_rho_label(rho),
        "_rep_",
        lpad(string(replication), 3, '0'),
    )
end

function _free_correlation_study_unit_rows()
    rows = NamedTuple[]
    unit_index = 0
    for (phase, replications) in (
            (:feasibility, _FREE_CORRELATION_STUDY_FEASIBILITY_REPLICATIONS),
            (:evaluation, _FREE_CORRELATION_STUDY_EVALUATION_REPLICATIONS))
        for (rho_index, rho_value) in
                pairs(_FREE_CORRELATION_STUDY_RHO_GRID)
            rho = Float64(rho_value)
            for replication in 1:replications
                unit_index += 1
                push!(rows, (;
                    unit_index,
                    unit_id = _free_correlation_study_unit_id(
                        phase,
                        rho,
                        replication,
                    ),
                    phase,
                    rho_index,
                    rho_truth = rho,
                    replication,
                    design = (;
                        n_persons = 300,
                        items_per_dimension = 6,
                        n_items = 12,
                        n_raters = 4,
                        n_categories = 4,
                        n_observations = 3_600,
                        n_probability_cells = 14_400,
                    ),
                    primary_lkj_eta = 2,
                    seeds = (;
                        ability = 410_000_000 + unit_index,
                        response = 520_000_000 + unit_index,
                        sampler_primary = 630_000_000 + unit_index,
                    ),
                    execution_status = :planned_not_run,
                ))
            end
        end
    end
    return Tuple(rows)
end

function _free_correlation_study_seed_checks(units)
    ability = Int[unit.seeds.ability for unit in units]
    response = Int[unit.seeds.response for unit in units]
    sampler_primary = Int[unit.seeds.sampler_primary for unit in units]
    sampler = sampler_primary
    all_values = vcat(ability, response, sampler)
    ability_unique = length(unique(ability)) == length(ability)
    response_unique = length(unique(response)) == length(response)
    sampler_unique = length(unique(sampler)) == length(sampler)
    ability_response_disjoint = isempty(intersect(Set(ability), Set(response)))
    ability_sampler_disjoint = isempty(intersect(Set(ability), Set(sampler)))
    response_sampler_disjoint = isempty(intersect(Set(response), Set(sampler)))
    all_active_seed_values_unique =
        length(unique(all_values)) == length(all_values)
    feasibility_values = Set(Int[value for unit in units
        for value in values(unit.seeds) if unit.phase === :feasibility])
    evaluation_values = Set(Int[value for unit in units
        for value in values(unit.seeds) if unit.phase === :evaluation])
    phase_namespaces_disjoint =
        isempty(intersect(feasibility_values, evaluation_values))
    passed = ability_unique && response_unique && sampler_unique &&
        ability_response_disjoint && ability_sampler_disjoint &&
        response_sampler_disjoint && all_active_seed_values_unique &&
        phase_namespaces_disjoint
    return (;
        ability_unique,
        response_unique,
        sampler_unique,
        ability_response_disjoint,
        ability_sampler_disjoint,
        response_sampler_disjoint,
        all_active_seed_values_unique,
        phase_namespaces_disjoint,
        n_units = length(units),
        n_ability_seeds = length(ability),
        n_response_seeds = length(response),
        n_sampler_seeds = length(sampler),
        passed,
    )
end

function _mgmfrm_free_latent_correlation_2d_study_plan()
    units = _free_correlation_study_unit_rows()
    seed_checks = _free_correlation_study_seed_checks(units)
    seed_checks.passed || throw(ArgumentError(
        "internal free-correlation study seed namespaces overlap",
    ))
    n_feasibility = count(unit -> unit.phase === :feasibility, units)
    n_evaluation = count(unit -> unit.phase === :evaluation, units)
    unit_roster_sha256 = artifact_content_hash(units)
    unit_roster_sha256 ==
        _FREE_CORRELATION_STUDY_V2_EXPECTED_UNIT_ROSTER_SHA256 ||
        throw(AssertionError(
            "frozen free-correlation study v2 unit roster changed",
        ))
    design = (;
        dimensions = 2,
        n_persons = 300,
        items_per_dimension = 6,
        n_items = 12,
        n_raters = 4,
        n_categories = 4,
        n_observations_per_unit = 3_600,
        n_probability_cells_per_unit = 14_400,
        assignment = :all_person_by_item_latin_square_rater,
        q_structure = :six_pure_items_per_dimension,
        thresholds = :partial_credit,
        discrimination_selector = :none,
        kernel_discrimination = :estimated_positive_item_dimension_truth_one,
    )
    phases = (;
        feasibility = (;
            replications_per_rho =
                _FREE_CORRELATION_STUDY_FEASIBILITY_REPLICATIONS,
            n_units = n_feasibility,
            role = :computational_feasibility_only,
            recovery_claim_allowed = false,
            threshold_tuning_allowed = false,
            minimum_diagnostically_completed_per_rho = 4,
            maximum_categorized_failures_per_rho = 1,
            all_planned_units_must_be_terminal = true,
        ),
        evaluation = (;
            replications_per_rho =
                _FREE_CORRELATION_STUDY_EVALUATION_REPLICATIONS,
            n_units = n_evaluation,
            role = :frozen_replicated_recovery_evaluation,
            starts_only_after_feasibility_gate = true,
            starts_only_after_versioned_scorer_validation = true,
            result_ingestion_preserves_unauthorized_executions = true,
            mid_evaluation_extension_allowed = false,
        ),
    )
    sampler = (;
        backend = :advancedhmc,
        algorithm = :nuts,
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 500,
        total_retained_draws = 2_000,
        step_size = 0.03,
        target_accept = 0.90,
        max_depth = 10,
        max_energy_error = 1_000.0,
        metric = :diagonal,
        ad_backend = :ForwardDiff,
        split_chains = true,
        interval = 0.90,
    )
    quality_requirements = (;
        diagnostic_contract = _MCMC_DIAGNOSTIC_CONTRACT,
        maximum_rhat = 1.01,
        minimum_bulk_ess = 400.0,
        minimum_tail_ess = 400.0,
        minimum_e_bfmi = 0.30,
        maximum_divergences = 0,
        maximum_depth_hits = 0,
        execution_status_uses_computation_quality_only = true,
        interval_coverage_is_scientific_outcome_not_execution_status = true,
        direction_match_is_scientific_outcome_not_execution_status = true,
    )
    recovery_analysis = (;
        interval_probability = 0.90,
        primary_estimands = (
            :rho_bias,
            :rho_mean_absolute_error,
            :rho_rmse,
            :rho_interval_coverage,
            :rho_direction_recovery,
        ),
        rho_zero_direction_status = :not_applicable_missing,
        rho_zero_false_directional_exclusion = :interval_excludes_zero,
        weak_identification_strata = (0.0, -0.3, 0.3),
        weak_identification_claim_scope =
            :finite_near_null_operating_points_not_general_weak_identification,
        symmetry_pairs = ((-0.6, 0.6), (-0.3, 0.3)),
        symmetry_summary =
            :unpaired_signed_bias_and_coverage_difference_with_independent_se,
        fixed_evaluation_thresholds = (;
            scorer_status = :contract_frozen_scorer_implemented_and_validated,
            scorer_schema =
                "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_score.v2",
            aggregate_schema =
                "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_evaluation_aggregate.v2",
            algorithm =
                :wilson_unresolved_envelope_endpoint_enumerated_full_denominator_mcse_unpaired_symmetry_v2,
            implementation_change_policy =
                :schema_or_algorithm_version_bump_required,
            required_terminal_units_per_rho = 100,
            minimum_diagnostically_valid_units_per_rho = 95,
            minimum_scientifically_scored_units_per_rho = 95,
            two_sided_normal_quantile = 1.959963984540054,
            one_sided_normal_quantile = 1.6448536269514722,
            descriptive_interval_coverage_target = (0.85, 0.95),
            overcoverage_is_hard_failure = false,
            minimum_joint_valid_and_covered_per_rho = 0.80,
            minimum_equal_weight_aggregate_coverage_wilson_lower = 0.85,
            minimum_joint_valid_and_direction_matching_per_nonzero_rho = 0.70,
            minimum_aggregate_direction_wilson_lower = 0.80,
            maximum_rho_zero_unresolved_false_exclusion_upper = 0.20,
            maximum_abs_bias_upper = 0.10,
            maximum_rmse_upper = 0.20,
            maximum_abs_unpaired_symmetry_upper = 0.10,
            bias_guard =
                :endpoint_enumerated_full_denominator_unresolved_abs_mean_bias_plus_1_96_mcse_at_most_0_10,
            rmse_guard =
                :endpoint_enumerated_full_denominator_unresolved_sqrt_mse_plus_1_645_mcse_mse_at_most_0_20,
            unpaired_symmetry_guard =
                :endpoint_enumerated_full_denominator_unresolved_abs_contrast_plus_1_96_independent_se_at_most_0_10,
            interval_crossing_decision_boundary = :inconclusive_not_passed,
        ),
    )
    prior_sensitivity = (;
        status = :pending_separate_versioned_protocol,
        included_in_primary_unit_roster = false,
        included_in_primary_denominator = false,
        primary_lkj_eta = 2,
        future_sensitivity_lkj_etas = (1, 4),
        required_followup =
            :freeze_separate_prior_sensitivity_plan_and_denominator,
    )
    denominator_policy = (;
        evaluation_denominator = :all_planned_units_fixed,
        n_planned_evaluation_units = n_evaluation,
        n_planned_per_rho = _FREE_CORRELATION_STUDY_EVALUATION_REPLICATIONS,
        generation_failed_counts_in_denominator = true,
        fit_failed_counts_in_denominator = true,
        diagnostic_failed_counts_in_denominator = true,
        recovery_scoring_failed_counts_in_denominator = true,
        missing_units_may_not_be_dropped = true,
        completed_noncoverage_remains_completed = true,
    )
    seed_policy = (;
        generator = :deterministic_integer_namespaces,
        ability_namespace = 410_000_000,
        response_namespace = 520_000_000,
        sampler_primary_namespace = 630_000_000,
        roles_pairwise_disjoint = true,
        phases_disjoint = true,
        seeds_reused_across_units = false,
    )
    resource_policy = (;
        dry_run_phase = :feasibility,
        dry_run_default_units = 2,
        dry_run_hard_max_units = _FREE_CORRELATION_STUDY_DRY_RUN_HARD_MAX_UNITS,
        dry_run_max_observations = 36_000,
        dry_run_max_probability_cells = 144_000,
        dry_run_mcmc_allowed = false,
        estimated_raw_parameter_dimension_per_unit = 655,
        retained_raw_draw_cells_per_unit = 1_310_000,
        candidate_and_direct_pointwise_cells_per_unit = 14_400_000,
        estimated_peak_memory = :greater_than_200_megabytes_per_unit,
        full_sample_bundle_persistence_allowed = false,
        compact_result_and_external_digest_required = true,
        sample_bundle_digest_policy =
            :stream_numeric_array_bytes_and_digest_structured_telemetry,
        sample_bundle_stringification_allowed = false,
        initial_gradient_probe = (;
            schema =
                "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe.v1",
            phase = :feasibility,
            execute_measurement_default = false,
            default_repetitions = 3,
            minimum_repetitions = 1,
            maximum_repetitions = 5,
            operation = :initial_logdensity_and_gradient,
            ad_backend = :ForwardDiff,
            adapter_validation_evaluations = 1,
            warmup_evaluations = 1,
            gc_before_each_timed_evaluation = true,
            maximum_median_gradient_seconds = 0.10,
            maximum_median_allocated_bytes = 128 * 1024^2,
            maximum_median_gc_time_fraction = 0.50,
            minimum_free_memory_bytes = 8 * 1024^3,
            planning_gradients_per_transition = 32,
            planned_transitions_per_chain =
                sampler.warmup_per_chain + sampler.draws_per_chain,
            planned_chains = sampler.chains,
            planned_transitions_per_full_unit = sampler.chains *
                (sampler.warmup_per_chain + sampler.draws_per_chain),
            maximum_estimated_full_unit_seconds = 7_200.0,
            short_nuts_profile_required = true,
            atomic_runner_required = true,
            gradient_profile_alone_authorizes_scientific_execution = false,
            mcmc_allowed = false,
        ),
    )
    unit_result_contract = (;
        schema = _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA,
        primary_terminal_statuses = _FREE_CORRELATION_STUDY_TERMINAL_STATUSES,
        primary_attempt = 1,
        retry_overwrites_primary = false,
        dry_run_result_allowed = false,
        recovery_claim_allowed = false,
        raw_draws_allowed = false,
        execution_provenance_required = true,
        execution_provenance_schema =
            _FREE_CORRELATION_STUDY_EXECUTION_PROVENANCE_SCHEMA,
        execution_provenance_fields = (
            :schema,
            :runtime,
            :environment,
            :sources,
            :execution_environment_sha256,
            :execution_binding,
            :sample_bundle,
            :provenance_sha256,
        ),
        execution_binding_fields = (
            :plan_id,
            :plan_fingerprint,
            :unit_id,
            :phase,
            :rho_truth,
            :replication,
            :seeds,
            :authorization_decision_fingerprint,
            :attempt,
            :generation_evidence_sha256,
            :data_signature,
            :sampler_controls,
            :sample_aggregate_sha256,
        ),
        sampler_binding_fields = (
            :mode,
            :ndraws,
            :warmup,
            :chains,
            :seed,
            :step_size,
            :target_accept,
            :max_depth,
            :max_energy_error,
            :metric,
            :ad_backend,
            :init_jitter,
            :split_chains,
            :rhat_threshold,
            :ess_threshold,
            :min_e_bfmi,
            :interval,
            :progress,
        ),
        execution_environment_hash_material =
            (:runtime, :environment, :sources),
        evidence_content_hash = :execution_provenance_sha256,
        runtime_fields = (:julia_version, :n_threads, :os, :arch),
        environment_files = (:project, :manifest),
        source_paths = _FREE_CORRELATION_STUDY_SOURCE_PATHS,
        source_hashes_are_runtime_evidence_not_plan_fingerprint_material = true,
        sample_digest_schema = _FREE_CORRELATION_STUDY_SAMPLE_DIGEST_SCHEMA,
        sample_array_fields = _FREE_CORRELATION_STUDY_SAMPLE_ARRAY_FIELDS,
        sample_array_manifest_fields =
            (:field, :byte_order, :storage_order, :digest),
        sample_array_digest_fields = (:eltype, :size, :nbytes, :sha256),
        sample_array_byte_orders = (:little_endian, :big_endian),
        sample_array_storage_order = :julia_column_major,
        sample_telemetry_fields =
            _FREE_CORRELATION_STUDY_SAMPLE_TELEMETRY_FIELDS,
        sample_digest_required_after_bundle_return = true,
        sample_digest_unavailable_reasons = (
            :generation_failed_before_fit,
            :fit_failed_before_sample_bundle_returned,
        ),
    )
    checks = (;
        n_units = length(units),
        n_feasibility_units = n_feasibility,
        n_evaluation_units = n_evaluation,
        unit_ids_unique = length(unique(unit.unit_id for unit in units)) ==
            length(units),
        rho_grid_symmetric = all(rho -> -rho in
            _FREE_CORRELATION_STUDY_RHO_GRID,
            _FREE_CORRELATION_STUDY_RHO_GRID),
        rho_zero_included = 0.0 in _FREE_CORRELATION_STUDY_RHO_GRID,
        seeds_disjoint = seed_checks.passed,
        resource_probe_transition_count_exact =
            resource_policy.initial_gradient_probe.
                planned_transitions_per_full_unit ==
            sampler.chains *
                (sampler.warmup_per_chain + sampler.draws_per_chain),
        resource_probe_fail_closed =
            !resource_policy.initial_gradient_probe.
                gradient_profile_alone_authorizes_scientific_execution &&
            !resource_policy.initial_gradient_probe.mcmc_allowed &&
            resource_policy.initial_gradient_probe.short_nuts_profile_required &&
            resource_policy.initial_gradient_probe.atomic_runner_required,
        passed = length(units) == n_feasibility + n_evaluation &&
            n_feasibility == 25 && n_evaluation == 500 &&
            length(unique(unit.unit_id for unit in units)) == length(units) &&
            all(rho -> -rho in _FREE_CORRELATION_STUDY_RHO_GRID,
                _FREE_CORRELATION_STUDY_RHO_GRID) &&
            0.0 in _FREE_CORRELATION_STUDY_RHO_GRID && seed_checks.passed &&
            resource_policy.initial_gradient_probe.
                planned_transitions_per_full_unit ==
                sampler.chains *
                    (sampler.warmup_per_chain + sampler.draws_per_chain) &&
            !resource_policy.initial_gradient_probe.
                gradient_profile_alone_authorizes_scientific_execution &&
            !resource_policy.initial_gradient_probe.mcmc_allowed &&
            resource_policy.initial_gradient_probe.short_nuts_profile_required &&
            resource_policy.initial_gradient_probe.atomic_runner_required,
    )
    lineage = (;
        predecessor_plan_id =
            "mgmfrm_free_latent_correlation_2d_recovery_study_v1",
        predecessor_plan_fingerprint =
            "39a850946e48dee20839a2a68d585a4c190a8f1d18a0a4b366fef574786aa128",
        predecessor_unit_roster_sha256 =
            "67d620bd816a820d35302e43ca148ec247b86a7a050ea35535caee9201dbd1f4",
        predecessor_scientific_executions = 0,
        predecessor_primary_executions = 0,
        predecessor_status = :retired_before_scientific_execution,
        predecessor_execution_provenance_schema = missing,
        predecessor_execution_provenance_available = false,
        predecessor_plan_artifact_retained = false,
        predecessor_plan_hash_reconstructible_from_repository = false,
        predecessor_identity_evidence = :historical_recorded_output_only,
        amendment_reason =
            :execution_provenance_unit_binding_environment_identity_fail_closed_resource_contract_and_endpoint_enumerated_unresolved_envelope_scorer,
    )
    fixed_protocol = (;
        status = :locally_preregistered_execution_not_started,
        frozen = true,
        externally_registered = false,
        amendment_policy = :new_version_and_new_evaluation_seed_namespace,
        family = :mgmfrm,
        scope = :quarantined_2d_free_latent_correlation_recovery_study,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        promotion_effect = :none,
        result_type = :named_tuple_only,
        design,
        rho_grid = _FREE_CORRELATION_STUDY_RHO_GRID,
        phases,
        sampler,
        quality_requirements,
        recovery_analysis,
        prior_sensitivity,
        denominator_policy,
        seed_policy,
        resource_policy,
        unit_result_contract,
        lineage,
        units,
        seed_checks,
        checks,
        resource_probe_completed = false,
        short_nuts_resource_profile_completed = false,
        atomic_runner_ready = false,
        operational_execution_authorized = false,
        scientific_execution_authorized = false,
        feasibility_execution_completed = false,
        evaluation_execution_authorized = false,
        evaluation_execution_completed = false,
        replicated_recovery_verified = false,
        dry_run_is_recovery_evidence = false,
        next_gate = :initial_gradient_resource_probe_then_short_nuts_profile_and_atomic_runner,
    )
    fingerprint_material = (;
        schema = _FREE_CORRELATION_STUDY_PLAN_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_plan,
        plan_id = _FREE_CORRELATION_STUDY_PLAN_ID,
        version = 2,
        unit_roster_sha256,
        fixed_protocol...,
    )
    plan_fingerprint = artifact_content_hash(fingerprint_material)
    plan_fingerprint == _FREE_CORRELATION_STUDY_V2_EXPECTED_PLAN_FINGERPRINT ||
        throw(AssertionError(
            "frozen free-correlation study v2 fingerprint changed",
        ))
    return (;
        schema = _FREE_CORRELATION_STUDY_PLAN_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_plan,
        plan_id = _FREE_CORRELATION_STUDY_PLAN_ID,
        version = 2,
        plan_fingerprint,
        unit_roster_sha256,
        fixed_protocol...,
    )
end

function _validate_free_correlation_study_plan(plan)
    plan isa NamedTuple || throw(ArgumentError(
        "study plan must be a NamedTuple returned by the study-plan constructor",
    ))
    hasproperty(plan, :schema) &&
        plan.schema == _FREE_CORRELATION_STUDY_PLAN_SCHEMA ||
        throw(ArgumentError("free-correlation study plan has the wrong schema"))
    canonical = _mgmfrm_free_latent_correlation_2d_study_plan()
    isequal(plan, canonical) || throw(ArgumentError(
        "study plan must be the ordered, unmodified preregistered plan",
    ))
    return plan
end

function _free_correlation_study_unit(plan, unit_id::AbstractString)
    isempty(unit_id) && throw(ArgumentError("unit_id must not be empty"))
    matches = [unit for unit in plan.units if unit.unit_id == unit_id]
    length(matches) == 1 || throw(ArgumentError(
        "unit_id must identify exactly one planned study unit",
    ))
    return only(matches)
end

function _free_correlation_study_exact_fields(
        value,
        required::Tuple,
        label::AbstractString)
    value isa NamedTuple || throw(ArgumentError("$label must be a NamedTuple"))
    Set(propertynames(value)) == Set(required) || throw(ArgumentError(
        "$label fields do not match the frozen contract",
    ))
    return value
end

function _free_correlation_study_finite_float(value, label::AbstractString)
    value isa Real && !(value isa Bool) || throw(ArgumentError(
        "$label must be a real number, not Bool",
    ))
    converted = try
        Float64(value)
    catch
        throw(ArgumentError("$label must be convertible to Float64"))
    end
    isfinite(converted) || throw(ArgumentError("$label must be finite"))
    return converted
end

function _free_correlation_study_sha256(value, label::AbstractString)
    value isa AbstractString && occursin(r"^[0-9a-f]{64}$", value) ||
        throw(ArgumentError("$label must be a lowercase SHA-256 digest"))
    return String(value)
end

function _free_correlation_study_file_sha256(path::AbstractString)
    isfile(path) || throw(ArgumentError(
        "execution-provenance file does not exist: $(basename(path))",
    ))
    return bytes2hex(open(sha256, path))
end

function _free_correlation_study_environment_files()
    project_path = Base.active_project()
    if project_path === nothing || !isfile(project_path)
        project_path = normpath(joinpath(@__DIR__, "..", "Project.toml"))
    end
    environment_root = dirname(project_path)
    versioned_manifest = joinpath(
        environment_root,
        "Manifest-v$(VERSION.major).$(VERSION.minor).toml",
    )
    manifest_path = isfile(versioned_manifest) ? versioned_manifest :
        joinpath(environment_root, "Manifest.toml")
    isfile(manifest_path) || throw(ArgumentError(
        "execution provenance requires the Julia-version-appropriate Manifest",
    ))
    return (;
        project = (;
            path = basename(project_path),
            sha256 = _free_correlation_study_file_sha256(project_path),
        ),
        manifest = (;
            path = basename(manifest_path),
            sha256 = _free_correlation_study_file_sha256(manifest_path),
        ),
    )
end

function _free_correlation_study_source_digests()
    repository_root = normpath(joinpath(@__DIR__, ".."))
    return Tuple((;
        path = relative_path,
        sha256 = _free_correlation_study_file_sha256(
            joinpath(repository_root, split(relative_path, '/')...),
        ),
    ) for relative_path in _FREE_CORRELATION_STUDY_SOURCE_PATHS)
end

function _free_correlation_study_execution_environment()
    runtime = (;
        julia_version = string(VERSION),
        n_threads = Threads.nthreads(),
        os = string(Sys.KERNEL),
        arch = string(Sys.ARCH),
    )
    environment = _free_correlation_study_environment_files()
    sources = _free_correlation_study_source_digests()
    identity_material = (; runtime, environment, sources)
    return merge(identity_material, (;
        execution_environment_sha256 =
            artifact_content_hash(identity_material),
    ))
end

function _free_correlation_study_array_digest(
        field::Symbol,
        value)
    value isa Array && eltype(value) <: Number &&
        isbitstype(eltype(value)) || throw(ArgumentError(
        "sample bundle $field must be a dense isbits numerical Array",
    ))
    if field in (:chain_ids, :iterations)
        eltype(value) <: Integer && eltype(value) !== Bool ||
            throw(ArgumentError(
                "sample bundle $field must use a machine-integer eltype",
            ))
    else
        eltype(value) === Float64 || throw(ArgumentError(
            "sample bundle $field must use Float64 storage",
        ))
    end
    byte_view = reinterpret(UInt8, vec(value))
    context = SHA.SHA2_256_CTX()
    chunk_nbytes = 1 << 20
    for first_byte in 1:chunk_nbytes:length(byte_view)
        last_byte = min(first_byte + chunk_nbytes - 1, length(byte_view))
        SHA.update!(context, @view byte_view[first_byte:last_byte])
    end
    digest = (;
        eltype = string(eltype(value)),
        size = Tuple(size(value)),
        nbytes = length(byte_view),
        sha256 = bytes2hex(SHA.digest!(context)),
    )
    byte_order = Base.ENDIAN_BOM == 0x04030201 ? :little_endian :
        Base.ENDIAN_BOM == 0x01020304 ? :big_endian :
        throw(ArgumentError("unsupported execution-platform byte order"))
    return (;
        field,
        byte_order,
        storage_order = :julia_column_major,
        digest,
    )
end

function _free_correlation_study_sample_digest(sample_bundle)
    _free_correlation_study_exact_fields(
        sample_bundle,
        _FREE_CORRELATION_STUDY_SAMPLE_BUNDLE_FIELDS,
        "scientific pilot sample bundle",
    )
    sample_bundle.schema == _FREE_CORRELATION_STUDY_SAMPLE_BUNDLE_SCHEMA ||
        throw(ArgumentError("scientific pilot sample bundle has the wrong schema"))
    numeric_arrays = Tuple(
        _free_correlation_study_array_digest(
            field,
            getproperty(sample_bundle, field),
        ) for field in _FREE_CORRELATION_STUDY_SAMPLE_ARRAY_FIELDS
    )
    structured_telemetry = Tuple((;
        field,
        sha256 = artifact_content_hash(getproperty(sample_bundle, field)),
    ) for field in _FREE_CORRELATION_STUDY_SAMPLE_TELEMETRY_FIELDS)
    metadata = NamedTuple{_FREE_CORRELATION_STUDY_SAMPLE_METADATA_FIELDS}(
        Tuple(getproperty(sample_bundle, field)
            for field in _FREE_CORRELATION_STUDY_SAMPLE_METADATA_FIELDS),
    )
    material = (;
        schema = _FREE_CORRELATION_STUDY_SAMPLE_DIGEST_SCHEMA,
        status = :available,
        reason = missing,
        sample_bundle_schema = sample_bundle.schema,
        numeric_arrays,
        structured_telemetry,
        metadata_sha256 = artifact_content_hash(metadata),
    )
    return merge(material, (;
        aggregate_sha256 = artifact_content_hash(material),
    ))
end

function _free_correlation_study_missing_sample_digest(reason::Symbol)
    reason in (
        :generation_failed_before_fit,
        :fit_failed_before_sample_bundle_returned,
    ) || throw(ArgumentError("unsupported sample-bundle absence reason"))
    return (;
        schema = _FREE_CORRELATION_STUDY_SAMPLE_DIGEST_SCHEMA,
        status = :not_available,
        reason,
        sample_bundle_schema = missing,
        numeric_arrays = (),
        structured_telemetry = (),
        metadata_sha256 = missing,
        aggregate_sha256 = missing,
    )
end

function _free_correlation_study_sampler_binding(plan, unit)
    return (;
        mode = :scientific,
        ndraws = plan.sampler.draws_per_chain,
        warmup = plan.sampler.warmup_per_chain,
        chains = plan.sampler.chains,
        seed = unit.seeds.sampler_primary,
        step_size = plan.sampler.step_size,
        target_accept = plan.sampler.target_accept,
        max_depth = plan.sampler.max_depth,
        max_energy_error = plan.sampler.max_energy_error,
        metric = plan.sampler.metric,
        ad_backend = plan.sampler.ad_backend,
        init_jitter = 0.0,
        split_chains = plan.sampler.split_chains,
        rhat_threshold = plan.quality_requirements.maximum_rhat,
        ess_threshold = plan.quality_requirements.minimum_bulk_ess,
        min_e_bfmi = plan.quality_requirements.minimum_e_bfmi,
        interval = plan.recovery_analysis.interval_probability,
        progress = false,
    )
end

function _free_correlation_study_execution_binding(
        plan,
        unit,
        authorization_decision_fingerprint,
        generation_evidence,
        sample_digest;
        attempt::Integer = 1)
    generation_evidence_sha256 = ismissing(generation_evidence) ? missing :
        artifact_content_hash(generation_evidence)
    data_signature = ismissing(generation_evidence) ? missing :
        generation_evidence.data_signature
    sample_aggregate_sha256 = sample_digest.status === :available ?
        sample_digest.aggregate_sha256 : missing
    return (;
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        rho_truth = unit.rho_truth,
        replication = unit.replication,
        seeds = unit.seeds,
        authorization_decision_fingerprint,
        attempt = Int(attempt),
        generation_evidence_sha256,
        data_signature,
        sampler_controls = _free_correlation_study_sampler_binding(plan, unit),
        sample_aggregate_sha256,
    )
end

function _free_correlation_study_execution_provenance(
        plan,
        unit;
        authorization_decision_fingerprint = missing,
        generation_evidence = missing,
        attempt::Integer = 1,
        sample_bundle = nothing,
        sample_bundle_unavailable_reason = nothing,
        execution_environment =
            _free_correlation_study_execution_environment())
    sample_digest = if sample_bundle === nothing
        sample_bundle_unavailable_reason isa Symbol || throw(ArgumentError(
            "sample_bundle_unavailable_reason is required without a bundle",
        ))
        _free_correlation_study_missing_sample_digest(
            sample_bundle_unavailable_reason,
        )
    else
        sample_bundle_unavailable_reason === nothing || throw(ArgumentError(
            "sample_bundle_unavailable_reason must be omitted with a bundle",
        ))
        _free_correlation_study_sample_digest(sample_bundle)
    end
    execution_binding = _free_correlation_study_execution_binding(
        plan,
        unit,
        authorization_decision_fingerprint,
        generation_evidence,
        sample_digest;
        attempt,
    )
    material = (;
        schema = _FREE_CORRELATION_STUDY_EXECUTION_PROVENANCE_SCHEMA,
        runtime = execution_environment.runtime,
        environment = execution_environment.environment,
        sources = execution_environment.sources,
        execution_environment_sha256 =
            execution_environment.execution_environment_sha256,
        execution_binding,
        sample_bundle = sample_digest,
    )
    return merge(material, (;
        provenance_sha256 = artifact_content_hash(material),
    ))
end

function _validate_free_correlation_study_sample_digest(sample_digest)
    _free_correlation_study_exact_fields(
        sample_digest,
        (
            :schema,
            :status,
            :reason,
            :sample_bundle_schema,
            :numeric_arrays,
            :structured_telemetry,
            :metadata_sha256,
            :aggregate_sha256,
        ),
        "study unit sample digest",
    )
    sample_digest.schema == _FREE_CORRELATION_STUDY_SAMPLE_DIGEST_SCHEMA ||
        throw(ArgumentError("study unit sample digest has the wrong schema"))
    sample_digest.status in (:available, :not_available) ||
        throw(ArgumentError("study unit sample digest has an invalid status"))
    if sample_digest.status === :available
        ismissing(sample_digest.reason) || throw(ArgumentError(
            "available sample digest must not contain an absence reason",
        ))
        sample_digest.sample_bundle_schema ==
            _FREE_CORRELATION_STUDY_SAMPLE_BUNDLE_SCHEMA || throw(ArgumentError(
            "available sample digest has the wrong sample-bundle schema",
        ))
        sample_digest.numeric_arrays isa Tuple &&
            Tuple(row.field for row in sample_digest.numeric_arrays) ==
                _FREE_CORRELATION_STUDY_SAMPLE_ARRAY_FIELDS ||
            throw(ArgumentError(
                "sample digest numerical-array roster was modified",
            ))
        for row in sample_digest.numeric_arrays
            _free_correlation_study_exact_fields(
                row,
                (:field, :byte_order, :storage_order, :digest),
                "sample numerical-array manifest row",
            )
            row.byte_order in (:little_endian, :big_endian) ||
                throw(ArgumentError(
                    "sample numerical-array byte order is invalid",
                ))
            row.storage_order === :julia_column_major ||
                throw(ArgumentError(
                    "sample numerical-array storage order is invalid",
                ))
            digest = _free_correlation_study_exact_fields(
                row.digest,
                (:eltype, :size, :nbytes, :sha256),
                "sample numerical-array digest",
            )
            digest.eltype isa AbstractString && !isempty(digest.eltype) ||
                throw(ArgumentError("sample array eltype must be nonempty"))
            digest.size isa Tuple && all(dimension ->
                dimension isa Integer && !(dimension isa Bool) && dimension >= 0,
                digest.size) || throw(ArgumentError(
                "sample array size must contain nonnegative integer dimensions",
            ))
            digest.nbytes isa Integer && !(digest.nbytes isa Bool) &&
                digest.nbytes >= 0 || throw(ArgumentError(
                "sample array nbytes must be a nonnegative integer",
            ))
            element_nbytes = if row.field in (:chain_ids, :iterations)
                digest.eltype == "Int64" ? 8 :
                    digest.eltype == "Int32" ? 4 : 0
            else
                digest.eltype == "Float64" ? 8 : 0
            end
            element_nbytes > 0 || throw(ArgumentError(
                "sample array eltype does not match its frozen field",
            ))
            expected_nbytes = prod(
                BigInt(dimension) for dimension in digest.size;
                init = BigInt(1),
            ) * element_nbytes
            BigInt(digest.nbytes) == expected_nbytes || throw(ArgumentError(
                "sample array nbytes is inconsistent with eltype and size",
            ))
            _free_correlation_study_sha256(
                digest.sha256,
                "sample numerical-array hash",
            )
        end
        length(unique(row.byte_order for row in
            sample_digest.numeric_arrays)) == 1 || throw(ArgumentError(
            "sample numerical-array byte orders must be uniform",
        ))
        sample_digest.structured_telemetry isa Tuple &&
            Tuple(row.field for row in sample_digest.structured_telemetry) ==
                _FREE_CORRELATION_STUDY_SAMPLE_TELEMETRY_FIELDS ||
            throw(ArgumentError(
                "sample digest structured-telemetry roster was modified",
            ))
        for row in sample_digest.structured_telemetry
            _free_correlation_study_exact_fields(
                row,
                (:field, :sha256),
                "sample structured-telemetry digest row",
            )
            _free_correlation_study_sha256(
                row.sha256,
                "sample structured-telemetry hash",
            )
        end
        _free_correlation_study_sha256(
            sample_digest.metadata_sha256,
            "sample metadata hash",
        )
        _free_correlation_study_sha256(
            sample_digest.aggregate_sha256,
            "sample aggregate hash",
        )
        aggregate_material = (;
            schema = sample_digest.schema,
            status = sample_digest.status,
            reason = sample_digest.reason,
            sample_bundle_schema = sample_digest.sample_bundle_schema,
            numeric_arrays = sample_digest.numeric_arrays,
            structured_telemetry = sample_digest.structured_telemetry,
            metadata_sha256 = sample_digest.metadata_sha256,
        )
        sample_digest.aggregate_sha256 ==
            artifact_content_hash(aggregate_material) || throw(ArgumentError(
            "sample digest aggregate does not bind its compact manifest",
        ))
    else
        sample_digest.reason in (
            :generation_failed_before_fit,
            :fit_failed_before_sample_bundle_returned,
        ) || throw(ArgumentError(
            "unavailable sample digest has an invalid reason",
        ))
        ismissing(sample_digest.sample_bundle_schema) &&
            isempty(sample_digest.numeric_arrays) &&
            isempty(sample_digest.structured_telemetry) &&
            ismissing(sample_digest.metadata_sha256) &&
            ismissing(sample_digest.aggregate_sha256) || throw(ArgumentError(
            "unavailable sample digest must not claim bundle content",
        ))
    end
    return sample_digest
end

function _validate_free_correlation_study_execution_provenance(provenance)
    _free_correlation_study_exact_fields(
        provenance,
        (
            :schema,
            :runtime,
            :environment,
            :sources,
            :execution_environment_sha256,
            :execution_binding,
            :sample_bundle,
            :provenance_sha256,
        ),
        "study unit execution_provenance",
    )
    provenance.schema == _FREE_CORRELATION_STUDY_EXECUTION_PROVENANCE_SCHEMA ||
        throw(ArgumentError("execution provenance has the wrong schema"))
    runtime = _free_correlation_study_exact_fields(
        provenance.runtime,
        (:julia_version, :n_threads, :os, :arch),
        "execution-provenance runtime",
    )
    runtime.julia_version isa AbstractString || throw(ArgumentError(
        "execution-provenance Julia version must be a string",
    ))
    runtime_version = try
        VersionNumber(runtime.julia_version)
    catch
        throw(ArgumentError("execution-provenance Julia version is invalid"))
    end
    runtime.n_threads isa Integer && !(runtime.n_threads isa Bool) &&
        runtime.n_threads >= 1 || throw(ArgumentError(
        "execution-provenance thread count must be positive",
    ))
    runtime.os isa AbstractString && !isempty(runtime.os) &&
        runtime.arch isa AbstractString && !isempty(runtime.arch) ||
        throw(ArgumentError("execution-provenance OS/architecture is invalid"))
    environment = _free_correlation_study_exact_fields(
        provenance.environment,
        (:project, :manifest),
        "execution-provenance environment",
    )
    for (label, file) in pairs(environment)
        _free_correlation_study_exact_fields(
            file,
            (:path, :sha256),
            "execution-provenance $(label) file",
        )
        file.path isa AbstractString && !isempty(file.path) &&
            basename(file.path) == file.path || throw(ArgumentError(
            "execution-provenance environment paths must be basenames",
        ))
        _free_correlation_study_sha256(
            file.sha256,
            "execution-provenance $(label) hash",
        )
    end
    environment.project.path == "Project.toml" || throw(ArgumentError(
        "execution-provenance Project path was modified",
    ))
    versioned_manifest_name =
        "Manifest-v$(runtime_version.major).$(runtime_version.minor).toml"
    environment.manifest.path in ("Manifest.toml", versioned_manifest_name) ||
        throw(ArgumentError(
            "execution-provenance Manifest is inappropriate for its Julia version",
        ))
    provenance.sources isa Tuple &&
        Tuple(row.path for row in provenance.sources) ==
            _FREE_CORRELATION_STUDY_SOURCE_PATHS || throw(ArgumentError(
        "execution-provenance source roster was modified",
    ))
    for row in provenance.sources
        _free_correlation_study_exact_fields(
            row,
            (:path, :sha256),
            "execution-provenance source row",
        )
        _free_correlation_study_sha256(
            row.sha256,
            "execution-provenance source hash",
        )
    end
    _free_correlation_study_sha256(
        provenance.execution_environment_sha256,
        "execution-provenance environment identity",
    )
    environment_identity_material = (;
        runtime = provenance.runtime,
        environment = provenance.environment,
        sources = provenance.sources,
    )
    provenance.execution_environment_sha256 ==
        artifact_content_hash(environment_identity_material) ||
        throw(ArgumentError(
            "execution environment identity does not bind runtime, environment, and sources",
        ))

    execution_binding = _free_correlation_study_exact_fields(
        provenance.execution_binding,
        (
            :plan_id,
            :plan_fingerprint,
            :unit_id,
            :phase,
            :rho_truth,
            :replication,
            :seeds,
            :authorization_decision_fingerprint,
            :attempt,
            :generation_evidence_sha256,
            :data_signature,
            :sampler_controls,
            :sample_aggregate_sha256,
        ),
        "execution-provenance unit binding",
    )
    execution_binding.plan_id isa AbstractString &&
        !isempty(execution_binding.plan_id) || throw(ArgumentError(
        "execution binding plan_id must be a nonempty string",
    ))
    _free_correlation_study_sha256(
        execution_binding.plan_fingerprint,
        "execution binding plan fingerprint",
    )
    execution_binding.unit_id isa AbstractString &&
        !isempty(execution_binding.unit_id) || throw(ArgumentError(
        "execution binding unit_id must be a nonempty string",
    ))
    execution_binding.phase in (:feasibility, :evaluation) ||
        throw(ArgumentError("execution binding phase is invalid"))
    bound_rho = _free_correlation_study_finite_float(
        execution_binding.rho_truth,
        "execution binding rho_truth",
    )
    -1 < bound_rho < 1 || throw(ArgumentError(
        "execution binding rho_truth must be in (-1, 1)",
    ))
    execution_binding.replication isa Integer &&
        !(execution_binding.replication isa Bool) &&
        execution_binding.replication >= 1 || throw(ArgumentError(
        "execution binding replication must be a positive integer",
    ))
    seeds = _free_correlation_study_exact_fields(
        execution_binding.seeds,
        (:ability, :response, :sampler_primary),
        "execution binding seeds",
    )
    all(seed -> seed isa Integer && !(seed isa Bool) && seed >= 0,
        values(seeds)) || throw(ArgumentError(
        "execution binding seeds must be nonnegative integers",
    ))
    if !ismissing(execution_binding.authorization_decision_fingerprint)
        _free_correlation_study_sha256(
            execution_binding.authorization_decision_fingerprint,
            "execution binding authorization fingerprint",
        )
    end
    execution_binding.attempt == 1 || throw(ArgumentError(
        "execution binding attempt must equal immutable primary attempt 1",
    ))
    generation_hash_missing =
        ismissing(execution_binding.generation_evidence_sha256)
    data_signature_missing = ismissing(execution_binding.data_signature)
    generation_hash_missing == data_signature_missing || throw(ArgumentError(
        "execution binding generation hash and data signature availability differ",
    ))
    if !generation_hash_missing
        _free_correlation_study_sha256(
            execution_binding.generation_evidence_sha256,
            "execution binding generation-evidence hash",
        )
        execution_binding.data_signature isa AbstractString &&
            occursin(r"^[0-9a-f]{16}$", execution_binding.data_signature) ||
            throw(ArgumentError(
                "execution binding data signature must be lowercase 16-hex",
            ))
    end
    sampler_controls = _free_correlation_study_exact_fields(
        execution_binding.sampler_controls,
        (
            :mode,
            :ndraws,
            :warmup,
            :chains,
            :seed,
            :step_size,
            :target_accept,
            :max_depth,
            :max_energy_error,
            :metric,
            :ad_backend,
            :init_jitter,
            :split_chains,
            :rhat_threshold,
            :ess_threshold,
            :min_e_bfmi,
            :interval,
            :progress,
        ),
        "execution binding sampler controls",
    )
    sampler_controls.seed isa Integer &&
        !(sampler_controls.seed isa Bool) || throw(ArgumentError(
        "execution binding sampler seed must be an integer",
    ))
    sampler_controls.seed == seeds.sampler_primary ||
        throw(ArgumentError(
            "execution binding sampler seed does not match seed lineage",
        ))
    sample_digest =
        _validate_free_correlation_study_sample_digest(provenance.sample_bundle)
    expected_sample_hash = sample_digest.status === :available ?
        sample_digest.aggregate_sha256 : missing
    isequal(execution_binding.sample_aggregate_sha256, expected_sample_hash) ||
        throw(ArgumentError(
            "execution binding sample hash does not match the nested sample digest",
        ))
    _free_correlation_study_sha256(
        provenance.provenance_sha256,
        "execution-provenance aggregate hash",
    )
    material = (;
        schema = provenance.schema,
        runtime = provenance.runtime,
        environment = provenance.environment,
        sources = provenance.sources,
        execution_environment_sha256 =
            provenance.execution_environment_sha256,
        execution_binding = provenance.execution_binding,
        sample_bundle = provenance.sample_bundle,
    )
    provenance.provenance_sha256 == artifact_content_hash(material) ||
        throw(ArgumentError(
            "execution-provenance aggregate does not bind its manifest",
        ))
    return (; provenance, sample_digest, execution_binding)
end

function _validate_free_correlation_study_unit_result(result, unit, plan)
    required = (
        :schema,
        :plan_id,
        :plan_fingerprint,
        :unit_id,
        :phase,
        :rho_truth,
        :replication,
        :seeds,
        :authorization_decision_fingerprint,
        :attempt,
        :primary_status,
        :execution_quality,
        :execution_provenance,
        :generation_evidence,
        :scientific_outcome,
        :failure,
        :dry_run,
        :recovery_claimed,
        :evidence,
    )
    _free_correlation_study_exact_fields(
        result,
        required,
        "study unit result",
    )
    result.schema == _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA ||
        throw(ArgumentError("study unit result has the wrong schema"))
    result.plan_id == plan.plan_id &&
        result.plan_fingerprint == plan.plan_fingerprint ||
        throw(ArgumentError("study unit result plan identity was modified"))
    result.unit_id == unit.unit_id && result.phase === unit.phase &&
        result.rho_truth == unit.rho_truth &&
        result.replication == unit.replication || throw(ArgumentError(
        "study unit result does not match its planned rho-by-replication unit",
    ))
    result.seeds == unit.seeds || throw(ArgumentError(
        "study unit result seed lineage does not match the plan",
    ))
    if unit.phase === :feasibility
        ismissing(result.authorization_decision_fingerprint) ||
            throw(ArgumentError(
                "feasibility results cannot contain evaluation authorization",
            ))
    else
        ismissing(result.authorization_decision_fingerprint) ||
            (result.authorization_decision_fingerprint isa AbstractString &&
                !isempty(result.authorization_decision_fingerprint)) ||
            throw(ArgumentError(
                "evaluation authorization fingerprint must be missing or nonempty",
            ))
    end
    result.attempt == 1 || throw(ArgumentError(
        "only immutable primary attempt = 1 results may enter this ledger",
    ))
    result.primary_status in _FREE_CORRELATION_STUDY_TERMINAL_STATUSES ||
        throw(ArgumentError("study unit result has an unsupported terminal status"))
    result.dry_run === false || throw(ArgumentError(
        "dry-run records cannot enter the scientific study ledger",
    ))
    result.recovery_claimed === false || throw(ArgumentError(
        "a unit result cannot claim replicated recovery",
    ))

    checked_provenance =
        _validate_free_correlation_study_execution_provenance(
            result.execution_provenance,
        )
    sample_digest = checked_provenance.sample_digest
    if result.primary_status in (
            :completed,
            :diagnostic_failed,
            :recovery_scoring_failed)
        sample_digest.status === :available || throw(ArgumentError(
            "post-MCMC study status requires a sample-bundle digest",
        ))
    elseif result.primary_status === :generation_failed
        sample_digest.status === :not_available &&
            sample_digest.reason === :generation_failed_before_fit ||
            throw(ArgumentError(
                "generation_failed sample-digest state is inconsistent",
            ))
    elseif sample_digest.status === :not_available
        sample_digest.reason === :fit_failed_before_sample_bundle_returned ||
            throw(ArgumentError(
                "fit_failed sample-digest absence reason is inconsistent",
            ))
    end

    quality = _free_correlation_study_exact_fields(
        result.execution_quality,
        (
            :execution_passed,
            :chain_layout_passed,
            :diagnostics_passed,
            :max_rank_normalized_rhat,
            :min_bulk_ess,
            :min_tail_ess,
            :min_e_bfmi,
            :n_divergences,
            :n_max_treedepth,
        ),
        "study unit execution_quality",
    )
    outcome = _free_correlation_study_exact_fields(
        result.scientific_outcome,
        (
            :posterior_median,
            :interval_lower,
            :interval_upper,
            :interval_covered,
            :direction_matches_truth,
            :truth_sign_probability,
            :realized_latent_correlation,
        ),
        "study unit scientific_outcome",
    )
    evidence = _free_correlation_study_exact_fields(
        result.evidence,
        (:source, :reference, :content_sha256),
        "study unit evidence",
    )
    evidence.source isa Symbol || throw(ArgumentError(
        "study unit evidence source must be a Symbol",
    ))
    evidence.reference isa AbstractString && !isempty(evidence.reference) ||
        throw(ArgumentError(
            "study unit evidence reference must be a nonempty string",
        ))
    _free_correlation_study_sha256(
        evidence.content_sha256,
        "study unit evidence content hash",
    )
    evidence.content_sha256 ==
        checked_provenance.provenance.provenance_sha256 ||
        throw(ArgumentError(
            "study unit evidence hash does not match execution provenance",
        ))
    if sample_digest.status === :available
        evidence.source === :free_latent_correlation_2d_recovery_pilot &&
            evidence.reference == _FREE_CORRELATION_PILOT_SCHEMA ||
            throw(ArgumentError(
                "sample-backed evidence must reference the scientific recovery pilot",
            ))
    else
        evidence.source === :study_single_unit_executor &&
            evidence.reference == unit.unit_id || throw(ArgumentError(
                "pre-sample failure evidence must reference its unit executor",
        ))
    end
    generation_evidence = if result.primary_status === :generation_failed
        ismissing(result.generation_evidence) || throw(ArgumentError(
            "generation_failed must not claim generation evidence",
        ))
        missing
    else
        generation = _free_correlation_study_exact_fields(
            result.generation_evidence,
            (
                :fixture_schema,
                :data_signature,
                :realized_latent_correlation,
                :maximum_closed_form_oracle_error,
            ),
            "study unit generation_evidence",
        )
        generation.fixture_schema == _FREE_CORRELATION_FIXTURE_SCHEMA ||
            throw(ArgumentError(
                "study unit generation evidence has the wrong fixture schema",
            ))
        generation.data_signature isa AbstractString &&
            occursin(r"^[0-9a-f]{16}$", generation.data_signature) ||
            throw(ArgumentError(
            "study unit generation evidence requires a lowercase 16-hex data_signature",
        ))
        generated_realized = _free_correlation_study_finite_float(
            generation.realized_latent_correlation,
            "generation realized_latent_correlation",
        )
        -1 < generated_realized < 1 || throw(ArgumentError(
            "generation realized_latent_correlation must be in (-1, 1)",
        ))
        oracle_error = _free_correlation_study_finite_float(
            generation.maximum_closed_form_oracle_error,
            "generation maximum_closed_form_oracle_error",
        )
        0 <= oracle_error <= 1e-12 || throw(ArgumentError(
            "generation closed-form oracle identity failed",
        ))
        generation
    end

    expected_execution_binding = _free_correlation_study_execution_binding(
        plan,
        unit,
        result.authorization_decision_fingerprint,
        generation_evidence,
        sample_digest;
        attempt = result.attempt,
    )
    isequal(
        checked_provenance.execution_binding,
        expected_execution_binding,
    ) || throw(ArgumentError(
        "execution provenance binding does not exactly match its result, unit, plan, generation evidence, and sample digest",
    ))

    if result.primary_status === :completed
        quality.execution_passed === true &&
            quality.chain_layout_passed === true &&
            quality.diagnostics_passed === true || throw(ArgumentError(
            "completed status requires successful execution and diagnostics",
        ))
        max_rhat = _free_correlation_study_finite_float(
            quality.max_rank_normalized_rhat,
            "max_rank_normalized_rhat",
        )
        min_bulk_ess = _free_correlation_study_finite_float(
            quality.min_bulk_ess,
            "min_bulk_ess",
        )
        min_tail_ess = _free_correlation_study_finite_float(
            quality.min_tail_ess,
            "min_tail_ess",
        )
        min_e_bfmi = _free_correlation_study_finite_float(
            quality.min_e_bfmi,
            "min_e_bfmi",
        )
        quality.n_divergences isa Integer &&
            !(quality.n_divergences isa Bool) &&
            quality.n_max_treedepth isa Integer &&
            !(quality.n_max_treedepth isa Bool) || throw(ArgumentError(
                "completed sampler event counts must be integers",
            ))
        quality.n_divergences >= 0 && quality.n_max_treedepth >= 0 ||
            throw(ArgumentError(
                "completed sampler event counts must be nonnegative",
            ))
        max_rhat <= plan.quality_requirements.maximum_rhat &&
            min_bulk_ess >= plan.quality_requirements.minimum_bulk_ess &&
            min_tail_ess >= plan.quality_requirements.minimum_tail_ess &&
            min_e_bfmi >= plan.quality_requirements.minimum_e_bfmi &&
            quality.n_divergences <=
                plan.quality_requirements.maximum_divergences &&
            quality.n_max_treedepth <=
                plan.quality_requirements.maximum_depth_hits ||
            throw(ArgumentError(
                "completed status does not satisfy frozen diagnostic thresholds",
            ))
        result.failure === missing || throw(ArgumentError(
            "completed unit result must not contain a failure record",
        ))
        median = _free_correlation_study_finite_float(
            outcome.posterior_median,
            "posterior_median",
        )
        lower = _free_correlation_study_finite_float(
            outcome.interval_lower,
            "interval_lower",
        )
        upper = _free_correlation_study_finite_float(
            outcome.interval_upper,
            "interval_upper",
        )
        -1 < lower <= median <= upper < 1 || throw(ArgumentError(
            "study unit posterior median and interval must be ordered inside (-1, 1)",
        ))
        evidence.source === :free_latent_correlation_2d_recovery_pilot &&
            evidence.reference == _FREE_CORRELATION_PILOT_SCHEMA ||
            throw(ArgumentError(
                "completed unit evidence must reference the scientific recovery pilot",
            ))
        outcome.interval_covered isa Bool || throw(ArgumentError(
            "completed unit interval_covered must be Bool",
        ))
        outcome.interval_covered === (lower <= unit.rho_truth <= upper) ||
            throw(ArgumentError(
                "study unit interval_covered does not match its interval",
            ))
        if iszero(unit.rho_truth)
            ismissing(outcome.direction_matches_truth) || throw(ArgumentError(
                "rho = 0 direction_matches_truth must be missing",
            ))
        else
            outcome.direction_matches_truth isa Bool || throw(ArgumentError(
                "nonzero-rho direction_matches_truth must be Bool",
            ))
            expected_direction = sign(median) == sign(unit.rho_truth)
            outcome.direction_matches_truth === expected_direction ||
                throw(ArgumentError(
                    "direction_matches_truth does not match posterior_median",
                ))
        end
        realized = _free_correlation_study_finite_float(
            outcome.realized_latent_correlation,
            "realized_latent_correlation",
        )
        -1 < realized < 1 || throw(ArgumentError(
            "realized_latent_correlation must be in (-1, 1)",
        ))
        realized == generation_evidence.realized_latent_correlation ||
            throw(ArgumentError(
                "scientific and generation realized correlations differ",
            ))
        if iszero(unit.rho_truth)
            ismissing(outcome.truth_sign_probability) || throw(ArgumentError(
                "rho = 0 truth_sign_probability must be missing",
            ))
        else
            sign_probability = _free_correlation_study_finite_float(
                outcome.truth_sign_probability,
                "truth_sign_probability",
            )
            0 <= sign_probability <= 1 || throw(ArgumentError(
                "truth_sign_probability must be in [0, 1]",
            ))
        end
    else
        all(ismissing, values(outcome)) || throw(ArgumentError(
            "failed unit results must not contain recovery outcomes",
        ))
        expected_stage = result.primary_status === :generation_failed ?
            :generation : result.primary_status === :fit_failed ?
            :fit : result.primary_status === :diagnostic_failed ?
            :diagnostics : :recovery_scoring
        failure = _free_correlation_study_exact_fields(
            result.failure,
            (:stage, :error_type, :message),
            "study unit failure",
        )
        failure.stage === expected_stage || throw(ArgumentError(
            "study unit failure stage does not match terminal status",
        ))
        failure.error_type isa Symbol || throw(ArgumentError(
            "study unit failure error_type must be a Symbol",
        ))
        failure.message isa AbstractString && !isempty(failure.message) ||
            throw(ArgumentError(
                "study unit failure message must be a nonempty string",
            ))
        if result.primary_status === :recovery_scoring_failed
            quality.execution_passed === true &&
                quality.chain_layout_passed === true &&
                quality.diagnostics_passed === true || throw(ArgumentError(
                "recovery_scoring_failed requires a diagnostically valid fit",
            ))
            max_rhat = _free_correlation_study_finite_float(
                quality.max_rank_normalized_rhat,
                "recovery_scoring_failed max_rank_normalized_rhat",
            )
            min_bulk_ess = _free_correlation_study_finite_float(
                quality.min_bulk_ess,
                "recovery_scoring_failed min_bulk_ess",
            )
            min_tail_ess = _free_correlation_study_finite_float(
                quality.min_tail_ess,
                "recovery_scoring_failed min_tail_ess",
            )
            min_e_bfmi = _free_correlation_study_finite_float(
                quality.min_e_bfmi,
                "recovery_scoring_failed min_e_bfmi",
            )
            quality.n_divergences isa Integer &&
                !(quality.n_divergences isa Bool) &&
                quality.n_max_treedepth isa Integer &&
                !(quality.n_max_treedepth isa Bool) &&
                quality.n_divergences >= 0 &&
                quality.n_max_treedepth >= 0 || throw(ArgumentError(
                "recovery_scoring_failed event counts must be nonnegative integers",
            ))
            max_rhat <= plan.quality_requirements.maximum_rhat &&
                min_bulk_ess >= plan.quality_requirements.minimum_bulk_ess &&
                min_tail_ess >= plan.quality_requirements.minimum_tail_ess &&
                min_e_bfmi >= plan.quality_requirements.minimum_e_bfmi &&
                quality.n_divergences <=
                    plan.quality_requirements.maximum_divergences &&
                quality.n_max_treedepth <=
                    plan.quality_requirements.maximum_depth_hits ||
                throw(ArgumentError(
                    "recovery_scoring_failed requires passing frozen diagnostics",
                ))
        elseif result.primary_status === :diagnostic_failed
            quality.execution_passed === true &&
                quality.chain_layout_passed isa Bool &&
                quality.diagnostics_passed === false || throw(ArgumentError(
                "diagnostic_failed requires an executed fit with failed diagnostics",
            ))
            all(value -> ismissing(value) ||
                (value isa Real && !(value isa Bool) && isfinite(Float64(value))),
                (
                    quality.max_rank_normalized_rhat,
                    quality.min_bulk_ess,
                    quality.min_tail_ess,
                    quality.min_e_bfmi,
                    quality.n_divergences,
                    quality.n_max_treedepth,
                )) || throw(ArgumentError(
                "diagnostic_failed metrics must be finite or missing",
            ))
        elseif result.primary_status === :fit_failed
            quality.execution_passed === false &&
                ismissing(quality.chain_layout_passed) &&
                ismissing(quality.diagnostics_passed) &&
                all(ismissing, (
                    quality.max_rank_normalized_rhat,
                    quality.min_bulk_ess,
                    quality.min_tail_ess,
                    quality.min_e_bfmi,
                    quality.n_divergences,
                    quality.n_max_treedepth,
                )) || throw(ArgumentError(
                "fit_failed execution-quality fields are inconsistent",
            ))
        else
            all(ismissing, values(quality)) || throw(ArgumentError(
                "generation_failed execution-quality fields must be missing",
            ))
        end
    end
    return result
end

function _free_correlation_study_feasibility_gate(
        unit_rows,
        plan;
        maximum_application_index::Int = typemax(Int))
    rows = Tuple((;
        rho_truth = rho,
        planned = count(row -> row.unit.phase === :feasibility &&
            row.unit.rho_truth == rho, unit_rows),
        recorded = count(row -> row.unit.phase === :feasibility &&
            row.unit.rho_truth == rho &&
            !ismissing(row.application_index) &&
            row.application_index <= maximum_application_index,
            unit_rows),
        completed = count(row -> row.unit.phase === :feasibility &&
            row.unit.rho_truth == rho &&
            !ismissing(row.application_index) &&
            row.application_index <= maximum_application_index &&
            row.result.primary_status === :completed,
            unit_rows),
        categorized_failures = count(row ->
            row.unit.phase === :feasibility &&
            row.unit.rho_truth == rho &&
            !ismissing(row.application_index) &&
            row.application_index <= maximum_application_index &&
            row.result.primary_status !== :completed,
            unit_rows),
    ) for rho in plan.rho_grid)
    all_terminal = all(row -> row.recorded == row.planned, rows)
    computational_gate_passed = all_terminal && all(row ->
        row.completed >= plan.phases.feasibility.
            minimum_diagnostically_completed_per_rho &&
        row.categorized_failures <= plan.phases.feasibility.
            maximum_categorized_failures_per_rho,
        rows)
    return (;
        decision_available = all_terminal,
        all_planned_feasibility_units_terminal = all_terminal,
        computation_quality_only = true,
        recovery_outcomes_used = false,
        rho_rows = rows,
        passed = computational_gate_passed,
    )
end

function _free_correlation_study_phase_rho_rows(unit_rows, plan)
    rows = NamedTuple[]
    for phase in (:feasibility, :evaluation), rho in plan.rho_grid
        selected = [row for row in unit_rows
            if row.unit.phase === phase && row.unit.rho_truth == rho]
        planned = length(selected)
        recorded = count(row -> !ismissing(row.result), selected)
        completed_rows = [row for row in selected
            if !ismissing(row.result) &&
                row.result.primary_status === :completed]
        n_completed = length(completed_rows)
        n_generation_failed = count(row -> !ismissing(row.result) &&
            row.result.primary_status === :generation_failed, selected)
        n_fit_failed = count(row -> !ismissing(row.result) &&
            row.result.primary_status === :fit_failed, selected)
        n_diagnostic_failed = count(row -> !ismissing(row.result) &&
            row.result.primary_status === :diagnostic_failed, selected)
        n_recovery_scoring_failed = count(row -> !ismissing(row.result) &&
            row.result.primary_status === :recovery_scoring_failed, selected)
        pending = planned - recorded
        covered = count(row ->
            row.result.scientific_outcome.interval_covered,
            completed_rows)
        direction_applicable = !iszero(rho)
        direction_matches = direction_applicable ? count(row ->
            row.result.scientific_outcome.direction_matches_truth,
            completed_rows) : missing
        push!(rows, (;
            phase,
            rho_truth = rho,
            planned_denominator = planned,
            n_results_recorded = recorded,
            n_pending = pending,
            n_completed,
            n_generation_failed,
            n_fit_failed,
            n_diagnostic_failed,
            n_recovery_scoring_failed,
            n_categorized_failures = n_generation_failed + n_fit_failed +
                n_diagnostic_failed + n_recovery_scoring_failed,
            n_valid_and_covered = covered,
            conditional_coverage_among_completed = n_completed == 0 ?
                missing : covered / n_completed,
            joint_valid_and_covered_lower_bound = covered / planned,
            joint_valid_and_covered_upper_bound =
                (covered + pending) / planned,
            joint_valid_and_covered_fixed_denominator = pending == 0 ?
                covered / planned : missing,
            direction_applicable,
            n_valid_and_direction_matching = direction_matches,
            conditional_direction_match_among_completed =
                !direction_applicable || n_completed == 0 ? missing :
                direction_matches / n_completed,
            joint_valid_and_direction_matching_lower_bound =
                direction_applicable ? direction_matches / planned : missing,
            joint_valid_and_direction_matching_upper_bound =
                direction_applicable ?
                (direction_matches + pending) / planned : missing,
            joint_valid_and_direction_matching_fixed_denominator =
                direction_applicable && pending == 0 ?
                direction_matches / planned : missing,
            fixed_denominator_evaluable = pending == 0,
        ))
    end
    return Tuple(rows)
end

function _free_correlation_study_ledger_summary(unit_rows, plan)
    n_planned = length(unit_rows)
    n_recorded = count(row -> !ismissing(row.result), unit_rows)
    n_completed = count(row -> !ismissing(row.result) &&
        row.result.primary_status === :completed, unit_rows)
    n_generation_failed = count(row -> !ismissing(row.result) &&
        row.result.primary_status === :generation_failed, unit_rows)
    n_fit_failed = count(row -> !ismissing(row.result) &&
        row.result.primary_status === :fit_failed, unit_rows)
    n_diagnostic_failed = count(row -> !ismissing(row.result) &&
        row.result.primary_status === :diagnostic_failed, unit_rows)
    n_recovery_scoring_failed = count(row -> !ismissing(row.result) &&
        row.result.primary_status === :recovery_scoring_failed, unit_rows)
    n_protocol_violations = sum(
        length(row.protocol_violations) for row in unit_rows;
        init = 0,
    )
    execution_environment_identities = unique(String(
        row.result.execution_provenance.execution_environment_sha256,
    ) for row in unit_rows if !ismissing(row.result))
    execution_environment_identity_count =
        length(execution_environment_identities)
    execution_environment_homogeneous =
        execution_environment_identity_count <= 1
    execution_environment_identity =
        execution_environment_identity_count == 1 ?
        only(execution_environment_identities) : missing
    feasibility_gate = _free_correlation_study_feasibility_gate(
        unit_rows,
        plan,
    )
    phase_rho_rows = _free_correlation_study_phase_rho_rows(unit_rows, plan)
    evaluation_rows = [row for row in phase_rho_rows
        if row.phase === :evaluation]
    evaluation_all_terminal = all(row -> row.n_pending == 0, evaluation_rows)
    protocol_integrity_passed = n_protocol_violations == 0 &&
        execution_environment_homogeneous
    scorer_implemented_validated_frozen =
        plan.recovery_analysis.fixed_evaluation_thresholds.scorer_status ===
            :contract_frozen_scorer_implemented_and_validated
    return (;
        n_planned_units = n_planned,
        n_results_recorded = n_recorded,
        n_pending_units = n_planned - n_recorded,
        n_completed,
        n_generation_failed,
        n_fit_failed,
        n_diagnostic_failed,
        n_recovery_scoring_failed,
        n_categorized_failures = n_generation_failed + n_fit_failed +
            n_diagnostic_failed + n_recovery_scoring_failed,
        n_protocol_violations,
        execution_environment_identity_count,
        execution_environment_homogeneous,
        execution_environment_identity,
        all_planned_units_retained = n_planned == length(plan.units),
        primary_attempts_overwritten = false,
        all_phase_planned_units = n_planned,
        feasibility_planned_units =
            plan.phases.feasibility.n_units,
        primary_evaluation_fixed_denominator =
            plan.denominator_policy.n_planned_evaluation_units,
        phase_rho_rows,
        feasibility_gate,
        evaluation_all_terminal,
        protocol_integrity_passed,
        scorer_implemented_validated_frozen,
        aggregate_ready = feasibility_gate.passed &&
            evaluation_all_terminal && protocol_integrity_passed &&
            scorer_implemented_validated_frozen,
        replicated_recovery_verified = false,
    )
end

function _free_correlation_study_ledger_status(summary)
    summary.n_results_recorded == 0 && return :study_ledger_initialized
    summary.aggregate_ready && return :study_units_recorded_pending_scoring
    summary.feasibility_gate.decision_available &&
        !summary.feasibility_gate.passed &&
        return :feasibility_gate_failed_evaluation_not_authorized
    return :study_ledger_in_progress
end

function _mgmfrm_free_latent_correlation_2d_study_ledger(plan)
    checked_plan = _validate_free_correlation_study_plan(plan)
    unit_rows = Tuple((;
        unit,
        result = missing,
        application_index = missing,
        authorization_artifact = missing,
        protocol_violations = (),
    ) for unit in checked_plan.units)
    summary = _free_correlation_study_ledger_summary(unit_rows, checked_plan)
    return (;
        schema = _FREE_CORRELATION_STUDY_LEDGER_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_ledger,
        status = _free_correlation_study_ledger_status(summary),
        plan_id = checked_plan.plan_id,
        plan_fingerprint = checked_plan.plan_fingerprint,
        plan = checked_plan,
        unit_rows,
        summary,
        public_fit = false,
        cache_enabled = false,
        promotion_effect = :none,
        replicated_recovery_verified = false,
    )
end

function _validate_free_correlation_study_ledger(ledger)
    ledger isa NamedTuple || throw(ArgumentError(
        "study ledger must be returned by the study-ledger constructor",
    ))
    required = (
        :schema,
        :object,
        :status,
        :plan_id,
        :plan_fingerprint,
        :plan,
        :unit_rows,
        :summary,
        :public_fit,
        :cache_enabled,
        :promotion_effect,
        :replicated_recovery_verified,
    )
    _free_correlation_study_exact_fields(ledger, required, "study ledger")
    ledger.schema == _FREE_CORRELATION_STUDY_LEDGER_SCHEMA ||
        throw(ArgumentError("study ledger has the wrong schema"))
    plan = _validate_free_correlation_study_plan(ledger.plan)
    ledger.plan_id == plan.plan_id &&
        ledger.plan_fingerprint == plan.plan_fingerprint ||
        throw(ArgumentError("study ledger plan identity was modified"))
    ledger.public_fit === false && ledger.cache_enabled === false &&
        ledger.promotion_effect === :none &&
        ledger.replicated_recovery_verified === false ||
        throw(ArgumentError("study ledger quarantine flags were modified"))
    length(ledger.unit_rows) == length(plan.units) || throw(ArgumentError(
        "study ledger must retain every planned unit",
    ))

    application_indices = Int[]
    authorization_cache = Dict{String, Any}()
    authorization_source_sha256 = nothing
    for (index, row) in pairs(ledger.unit_rows)
        _free_correlation_study_exact_fields(
            row,
            (
                :unit,
                :result,
                :application_index,
                :authorization_artifact,
                :protocol_violations,
            ),
            "study ledger unit row",
        )
        isequal(row.unit, plan.units[index]) || throw(ArgumentError(
            "study ledger unit roster or order was modified",
        ))
        row.protocol_violations isa Tuple || throw(ArgumentError(
            "study ledger protocol_violations must be a Tuple",
        ))
        all(violation -> violation ===
            :evaluation_result_without_valid_execution_authorization,
            row.protocol_violations) || throw(ArgumentError(
            "study ledger contains an unsupported protocol violation",
        ))
        if ismissing(row.result)
            ismissing(row.application_index) &&
                ismissing(row.authorization_artifact) &&
                isempty(row.protocol_violations) || throw(ArgumentError(
                "pending study units cannot have application metadata",
            ))
        else
            row.application_index isa Int && row.application_index >= 1 ||
                throw(ArgumentError(
                    "recorded study results require a positive application_index",
                ))
            push!(application_indices, row.application_index)
            _validate_free_correlation_study_unit_result(
                row.result,
                row.unit,
                plan,
            )
            if row.unit.phase === :feasibility
                ismissing(row.authorization_artifact) &&
                    ismissing(row.result.authorization_decision_fingerprint) ||
                    throw(ArgumentError(
                        "feasibility ledger rows cannot bind evaluation authorization",
                    ))
            elseif ismissing(row.authorization_artifact)
                row.protocol_violations ==
                    (:evaluation_result_without_valid_execution_authorization,) ||
                    throw(ArgumentError(
                        "unauthorized evaluation result must remain visibly classified",
                    ))
            else
                hasproperty(
                    row.authorization_artifact,
                    :decision_fingerprint,
                ) || throw(ArgumentError(
                    "evaluation authorization artifact lacks a fingerprint",
                ))
                authorization_fingerprint =
                    row.authorization_artifact.decision_fingerprint
                authorization_fingerprint isa String || throw(ArgumentError(
                    "evaluation authorization fingerprint must be a String",
                ))
                checked_authorization = if haskey(
                        authorization_cache,
                        authorization_fingerprint)
                    cached = authorization_cache[authorization_fingerprint]
                    isequal(row.authorization_artifact, cached) ||
                        throw(ArgumentError(
                            "one authorization fingerprint names different artifacts",
                        ))
                    cached
                else
                    validated =
                        _validate_free_correlation_study_feasibility_decision(
                            row.authorization_artifact,
                            plan,
                        )
                    authorization_cache[authorization_fingerprint] = validated
                    validated
                end
                if authorization_source_sha256 === nothing
                    source_rows =
                        _free_correlation_study_feasibility_result_rows(
                            ledger.unit_rows,
                        )
                    authorization_source_sha256 =
                        artifact_content_hash(source_rows)
                end
                checked_authorization.evaluation_execution_authorized &&
                    checked_authorization.protocol_integrity_evidence.passed &&
                    checked_authorization.feasibility_result_set_sha256 ==
                        authorization_source_sha256 &&
                    row.result.authorization_decision_fingerprint ==
                        checked_authorization.decision_fingerprint &&
                    isempty(row.protocol_violations) || throw(ArgumentError(
                    "evaluation result authorization binding is invalid",
                ))
            end
        end
    end
    sort(application_indices) == collect(1:length(application_indices)) ||
        throw(ArgumentError(
            "study ledger application indexes must be unique and consecutive",
        ))

    recomputed_summary = _free_correlation_study_ledger_summary(
        ledger.unit_rows,
        plan,
    )
    isequal(ledger.summary, recomputed_summary) || throw(ArgumentError(
        "study ledger summary does not match its complete unit roster",
    ))
    ledger.status === _free_correlation_study_ledger_status(
        recomputed_summary,
    ) || throw(ArgumentError("study ledger status was modified"))
    return ledger
end

function _mgmfrm_free_latent_correlation_2d_study_apply_result(
        ledger,
        result;
        authorization = nothing)
    checked_ledger = _validate_free_correlation_study_ledger(ledger)
    plan = checked_ledger.plan
    result isa NamedTuple && hasproperty(result, :unit_id) ||
        throw(ArgumentError("study result must contain unit_id"))
    result.unit_id isa AbstractString || throw(ArgumentError(
        "study result unit_id must be a string",
    ))
    unit = _free_correlation_study_unit(plan, result.unit_id)
    checked_result = _validate_free_correlation_study_unit_result(
        result,
        unit,
        plan,
    )
    target_index = only(index for (index, row) in
        pairs(checked_ledger.unit_rows) if row.unit.unit_id == unit.unit_id)
    ismissing(checked_ledger.unit_rows[target_index].result) ||
        throw(ArgumentError(
            "primary unit results are immutable and cannot be overwritten",
        ))
    checked_authorization = if unit.phase === :feasibility
        authorization === nothing || throw(ArgumentError(
            "feasibility results do not accept evaluation authorization",
        ))
        nothing
    elseif authorization === nothing
        nothing
    else
        try
            candidate_authorization =
                _validate_free_correlation_study_feasibility_decision(
                    authorization,
                    plan,
                )
            candidate_authorization.evaluation_execution_authorized &&
                candidate_authorization.protocol_integrity_evidence.passed &&
                candidate_authorization.feasibility_result_set_sha256 ==
                    artifact_content_hash(
                        _free_correlation_study_feasibility_result_rows(
                            checked_ledger.unit_rows,
                        ),
                    ) &&
                checked_result.authorization_decision_fingerprint ==
                    candidate_authorization.decision_fingerprint ?
                candidate_authorization : nothing
        catch
            nothing
        end
    end
    protocol_violations = unit.phase === :evaluation &&
        checked_authorization === nothing ?
        (:evaluation_result_without_valid_execution_authorization,) : ()
    application_index = checked_ledger.summary.n_results_recorded + 1
    updated_rows = Any[checked_ledger.unit_rows...]
    updated_rows[target_index] = (;
        unit,
        result = checked_result,
        application_index,
        authorization_artifact = checked_authorization === nothing ?
            missing : checked_authorization,
        protocol_violations,
    )
    unit_rows = Tuple(updated_rows)
    summary = _free_correlation_study_ledger_summary(unit_rows, plan)
    return merge(checked_ledger, (;
        status = _free_correlation_study_ledger_status(summary),
        unit_rows,
        summary,
    ))
end

function _free_correlation_study_feasibility_result_rows(unit_rows)
    rows = NamedTuple[]
    for row in unit_rows
        row.unit.phase === :feasibility || continue
        ismissing(row.result) && throw(ArgumentError(
            "feasibility authorization requires every planned result",
        ))
        push!(rows, (;
            unit_id = row.unit.unit_id,
            rho_truth = row.unit.rho_truth,
            replication = row.unit.replication,
            primary_status = row.result.primary_status,
            application_index = row.application_index,
            execution_environment_sha256 = row.result.execution_provenance.
                execution_environment_sha256,
            unit_result_sha256 = artifact_content_hash(row.result),
        ))
    end
    return Tuple(rows)
end

function _free_correlation_study_protocol_integrity_evidence(
        unit_rows,
        feasibility_result_rows)
    n_protocol_violations_at_freeze = sum(
        length(row.protocol_violations) for row in unit_rows;
        init = 0,
    )
    n_evaluation_results_recorded_at_freeze = count(
        row -> row.unit.phase === :evaluation && !ismissing(row.result),
        unit_rows,
    )
    identities = unique([
        String(row.execution_environment_sha256)
        for row in feasibility_result_rows
    ])
    execution_environment_identity_count = length(identities)
    execution_environment_homogeneous =
        execution_environment_identity_count == 1
    execution_environment_identity = execution_environment_homogeneous ?
        only(identities) : missing
    passed = n_protocol_violations_at_freeze == 0 &&
        n_evaluation_results_recorded_at_freeze == 0 &&
        execution_environment_homogeneous
    return (;
        n_protocol_violations_at_freeze,
        n_evaluation_results_recorded_at_freeze,
        execution_environment_identity_count,
        execution_environment_homogeneous,
        execution_environment_identity,
        passed,
    )
end

function _free_correlation_study_decision_payload(
        plan,
        feasibility_gate,
        feasibility_result_rows,
        protocol_integrity_evidence)
    decision_basis = Tuple((;
        unit_id = row.unit_id,
        rho_truth = row.rho_truth,
        replication = row.replication,
        primary_status = row.primary_status,
        application_index = row.application_index,
    ) for row in feasibility_result_rows)
    scorer_implemented_validated_frozen =
        plan.recovery_analysis.fixed_evaluation_thresholds.scorer_status ===
            :contract_frozen_scorer_implemented_and_validated
    evaluation_execution_authorized = feasibility_gate.passed &&
        protocol_integrity_evidence.passed &&
        scorer_implemented_validated_frozen
    return (;
        schema = _FREE_CORRELATION_STUDY_FEASIBILITY_DECISION_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_feasibility_decision,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_roster_sha256 = plan.unit_roster_sha256,
        frozen = true,
        computation_quality_only = true,
        recovery_outcomes_used = false,
        feasibility_result_rows,
        feasibility_result_set_sha256 =
            artifact_content_hash(feasibility_result_rows),
        decision_basis_sha256 = artifact_content_hash(decision_basis),
        feasibility_gate,
        protocol_integrity_evidence,
        protocol_integrity_at_freeze = protocol_integrity_evidence.passed,
        scorer_implemented_validated_frozen,
        evaluation_seed_namespace = plan.seed_policy.sampler_primary_namespace,
        evaluation_execution_authorized,
        status = evaluation_execution_authorized ?
            :evaluation_execution_authorized :
            :evaluation_execution_not_authorized,
        recovery_claimed = false,
    )
end

function _mgmfrm_free_latent_correlation_2d_study_feasibility_decision(
        ledger)
    checked_ledger = _validate_free_correlation_study_ledger(ledger)
    gate = checked_ledger.summary.feasibility_gate
    gate.decision_available || throw(ArgumentError(
        "feasibility decision requires all planned feasibility units to be terminal",
    ))
    result_rows = _free_correlation_study_feasibility_result_rows(
        checked_ledger.unit_rows,
    )
    protocol_integrity_evidence =
        _free_correlation_study_protocol_integrity_evidence(
            checked_ledger.unit_rows,
            result_rows,
        )
    payload = _free_correlation_study_decision_payload(
        checked_ledger.plan,
        gate,
        result_rows,
        protocol_integrity_evidence,
    )
    return merge(payload, (;
        decision_fingerprint = artifact_content_hash(payload),
    ))
end

function _validate_free_correlation_study_feasibility_decision(
        authorization,
        plan)
    authorization isa NamedTuple || throw(ArgumentError(
        "evaluation execution requires a frozen feasibility decision artifact",
    ))
    required = (
        :schema,
        :object,
        :plan_id,
        :plan_fingerprint,
        :unit_roster_sha256,
        :frozen,
        :computation_quality_only,
        :recovery_outcomes_used,
        :feasibility_result_rows,
        :feasibility_result_set_sha256,
        :decision_basis_sha256,
        :feasibility_gate,
        :protocol_integrity_evidence,
        :protocol_integrity_at_freeze,
        :scorer_implemented_validated_frozen,
        :evaluation_seed_namespace,
        :evaluation_execution_authorized,
        :status,
        :recovery_claimed,
        :decision_fingerprint,
    )
    _free_correlation_study_exact_fields(
        authorization,
        required,
        "feasibility decision",
    )
    authorization.schema ==
        _FREE_CORRELATION_STUDY_FEASIBILITY_DECISION_SCHEMA ||
        throw(ArgumentError("feasibility decision has the wrong schema"))
    authorization.object ===
        :mgmfrm_free_latent_correlation_2d_study_feasibility_decision ||
        throw(ArgumentError("feasibility decision has the wrong object tag"))
    authorization.plan_id == plan.plan_id &&
        authorization.plan_fingerprint == plan.plan_fingerprint &&
        authorization.unit_roster_sha256 == plan.unit_roster_sha256 ||
        throw(ArgumentError("feasibility decision plan identity was modified"))
    authorization.frozen === true &&
        authorization.computation_quality_only === true &&
        authorization.recovery_outcomes_used === false &&
        authorization.recovery_claimed === false || throw(ArgumentError(
            "feasibility decision claim boundary was modified",
        ))
    authorization.protocol_integrity_at_freeze isa Bool || throw(ArgumentError(
        "feasibility decision protocol-integrity flag must be Bool",
    ))
    authorization.decision_fingerprint isa AbstractString &&
        occursin(r"^[0-9a-f]{64}$", authorization.decision_fingerprint) ||
        throw(ArgumentError(
            "feasibility decision fingerprint must be lowercase SHA-256",
        ))
    payload = Base.structdiff(authorization, (; decision_fingerprint = nothing))
    authorization.decision_fingerprint == artifact_content_hash(payload) ||
        throw(ArgumentError("feasibility decision fingerprint was modified"))
    expected_units = Tuple(unit for unit in plan.units
        if unit.phase === :feasibility)
    rows = authorization.feasibility_result_rows
    rows isa Tuple && length(rows) == length(expected_units) ||
        throw(ArgumentError(
            "feasibility decision must retain all 25 planned feasibility results",
        ))
    application_indices = Int[]
    for row in rows
        _free_correlation_study_exact_fields(
            row,
            (
                :unit_id,
                :rho_truth,
                :replication,
                :primary_status,
                :application_index,
                :execution_environment_sha256,
                :unit_result_sha256,
            ),
            "feasibility decision result row",
        )
        row.unit_id isa AbstractString || throw(ArgumentError(
            "feasibility decision unit_id must be a string",
        ))
        unit = _free_correlation_study_unit(plan, row.unit_id)
        unit.phase === :feasibility && row.rho_truth == unit.rho_truth &&
            row.replication == unit.replication || throw(ArgumentError(
            "feasibility decision row does not match the canonical unit roster",
        ))
        row.primary_status in _FREE_CORRELATION_STUDY_TERMINAL_STATUSES ||
            throw(ArgumentError(
                "feasibility decision row has a nonterminal status",
            ))
        row.application_index isa Int && row.application_index >= 1 ||
            throw(ArgumentError(
                "feasibility decision application index must be positive",
            ))
        push!(application_indices, row.application_index)
        _free_correlation_study_sha256(
            row.execution_environment_sha256,
            "feasibility decision execution-environment identity",
        )
        row.unit_result_sha256 isa AbstractString &&
            occursin(r"^[0-9a-f]{64}$", row.unit_result_sha256) ||
            throw(ArgumentError(
                "feasibility decision unit result digest must be lowercase SHA-256",
            ))
    end
    length(unique(row.unit_id for row in rows)) == length(rows) ||
        throw(ArgumentError(
            "feasibility decision contains duplicate unit IDs",
        ))
    Tuple(row.unit_id for row in rows) ==
        Tuple(unit.unit_id for unit in expected_units) || throw(ArgumentError(
        "feasibility decision rows must retain canonical plan order",
    ))
    length(unique(application_indices)) == length(application_indices) ||
        throw(ArgumentError(
            "feasibility decision application indices must be unique",
        ))
    Set(row.unit_id for row in rows) ==
        Set(unit.unit_id for unit in expected_units) || throw(ArgumentError(
        "feasibility decision unit roster is incomplete",
    ))
    integrity_evidence = _free_correlation_study_exact_fields(
        authorization.protocol_integrity_evidence,
        (
            :n_protocol_violations_at_freeze,
            :n_evaluation_results_recorded_at_freeze,
            :execution_environment_identity_count,
            :execution_environment_homogeneous,
            :execution_environment_identity,
            :passed,
        ),
        "feasibility decision protocol-integrity evidence",
    )
    for (field, label) in (
            (:n_protocol_violations_at_freeze, "protocol violation count"),
            (:n_evaluation_results_recorded_at_freeze,
                "evaluation result count"),
            (:execution_environment_identity_count,
                "execution-environment identity count"))
        value = getproperty(integrity_evidence, field)
        value isa Integer && !(value isa Bool) && value >= 0 ||
            throw(ArgumentError(
                "feasibility decision $label must be a nonnegative integer",
            ))
    end
    integrity_evidence.execution_environment_homogeneous isa Bool &&
        integrity_evidence.passed isa Bool || throw(ArgumentError(
        "feasibility decision protocol-integrity flags must be Bool",
    ))
    environment_identities = unique([
        String(row.execution_environment_sha256) for row in rows
    ])
    expected_environment_identity_count = length(environment_identities)
    expected_environment_homogeneous =
        expected_environment_identity_count == 1
    expected_environment_identity = expected_environment_homogeneous ?
        only(environment_identities) : missing
    integrity_evidence.execution_environment_identity_count ==
        expected_environment_identity_count &&
        integrity_evidence.execution_environment_homogeneous ===
            expected_environment_homogeneous &&
        isequal(
            integrity_evidence.execution_environment_identity,
            expected_environment_identity,
        ) || throw(ArgumentError(
        "feasibility decision environment identity evidence does not match all 25 result rows",
    ))
    minimum_prior_evaluation_results = max(
        maximum(application_indices) - length(rows),
        0,
    )
    integrity_evidence.n_evaluation_results_recorded_at_freeze >=
        minimum_prior_evaluation_results || throw(ArgumentError(
        "feasibility decision understates evaluation results recorded before feasibility freeze",
    ))
    expected_integrity_passed =
        integrity_evidence.n_protocol_violations_at_freeze == 0 &&
        integrity_evidence.n_evaluation_results_recorded_at_freeze == 0 &&
        expected_environment_homogeneous &&
        sort(application_indices) == collect(1:length(rows))
    integrity_evidence.passed === expected_integrity_passed ||
        throw(ArgumentError(
            "feasibility decision protocol-integrity result is inconsistent with its evidence",
        ))
    authorization.protocol_integrity_at_freeze ===
        integrity_evidence.passed || throw(ArgumentError(
        "feasibility decision protocol-integrity flag is not evidence-backed",
    ))
    authorization.feasibility_result_set_sha256 == artifact_content_hash(rows) ||
        throw(ArgumentError(
            "feasibility result-set digest does not match its rows",
        ))
    authorization.feasibility_result_set_sha256 isa AbstractString &&
        occursin(
            r"^[0-9a-f]{64}$",
            authorization.feasibility_result_set_sha256,
        ) || throw(ArgumentError(
        "feasibility result-set digest must be lowercase SHA-256",
    ))
    decision_basis = Tuple((;
        unit_id = row.unit_id,
        rho_truth = row.rho_truth,
        replication = row.replication,
        primary_status = row.primary_status,
        application_index = row.application_index,
    ) for row in rows)
    authorization.decision_basis_sha256 == artifact_content_hash(decision_basis) ||
        throw(ArgumentError(
            "feasibility execution-only decision basis digest is inconsistent",
        ))
    authorization.decision_basis_sha256 isa AbstractString &&
        occursin(r"^[0-9a-f]{64}$", authorization.decision_basis_sha256) ||
        throw(ArgumentError(
            "feasibility decision-basis digest must be lowercase SHA-256",
        ))
    projected_unit_rows = Tuple((;
        unit = _free_correlation_study_unit(plan, row.unit_id),
        result = (; primary_status = row.primary_status),
        application_index = row.application_index,
    ) for row in rows)
    recomputed_gate = _free_correlation_study_feasibility_gate(
        projected_unit_rows,
        plan,
    )
    isequal(authorization.feasibility_gate, recomputed_gate) ||
        throw(ArgumentError(
            "feasibility decision gate does not match its execution-only basis",
        ))
    expected_scorer_ready =
        plan.recovery_analysis.fixed_evaluation_thresholds.scorer_status ===
            :contract_frozen_scorer_implemented_and_validated
    authorization.scorer_implemented_validated_frozen ===
        expected_scorer_ready || throw(ArgumentError(
        "feasibility decision scorer-readiness flag is inconsistent",
    ))
    expected_authorized = authorization.feasibility_gate.passed &&
        integrity_evidence.passed && expected_scorer_ready
    authorization.evaluation_execution_authorized === expected_authorized ||
        throw(ArgumentError(
            "feasibility decision authorization flag is inconsistent",
        ))
    authorization.status === (expected_authorized ?
        :evaluation_execution_authorized :
        :evaluation_execution_not_authorized) || throw(ArgumentError(
        "feasibility decision status is inconsistent",
    ))
    authorization.evaluation_seed_namespace ==
        plan.seed_policy.sampler_primary_namespace || throw(ArgumentError(
        "feasibility decision evaluation seed namespace was modified",
    ))
    return authorization
end

function _free_correlation_study_result_contract_record()
    return (;
        schema = _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA,
        required_fields = (
            :schema,
            :plan_id,
            :plan_fingerprint,
            :unit_id,
            :phase,
            :rho_truth,
            :replication,
            :seeds,
            :authorization_decision_fingerprint,
            :attempt,
            :primary_status,
            :execution_quality,
            :execution_provenance,
            :generation_evidence,
            :scientific_outcome,
            :failure,
            :dry_run,
            :recovery_claimed,
            :evidence,
        ),
        execution_provenance_fields = (
            :schema,
            :runtime,
            :environment,
            :sources,
            :execution_environment_sha256,
            :execution_binding,
            :sample_bundle,
            :provenance_sha256,
        ),
        execution_binding_fields = (
            :plan_id,
            :plan_fingerprint,
            :unit_id,
            :phase,
            :rho_truth,
            :replication,
            :seeds,
            :authorization_decision_fingerprint,
            :attempt,
            :generation_evidence_sha256,
            :data_signature,
            :sampler_controls,
            :sample_aggregate_sha256,
        ),
        sampler_binding_fields = (
            :mode,
            :ndraws,
            :warmup,
            :chains,
            :seed,
            :step_size,
            :target_accept,
            :max_depth,
            :max_energy_error,
            :metric,
            :ad_backend,
            :init_jitter,
            :split_chains,
            :rhat_threshold,
            :ess_threshold,
            :min_e_bfmi,
            :interval,
            :progress,
        ),
        execution_environment_hash_material =
            (:runtime, :environment, :sources),
        sampler_binding_matches_pilot_kwargs = true,
        runtime_fields = (:julia_version, :n_threads, :os, :arch),
        environment_files = (:project, :manifest),
        source_paths = _FREE_CORRELATION_STUDY_SOURCE_PATHS,
        sample_array_fields = _FREE_CORRELATION_STUDY_SAMPLE_ARRAY_FIELDS,
        sample_array_manifest_fields =
            (:field, :byte_order, :storage_order, :digest),
        sample_array_digest_fields = (:eltype, :size, :nbytes, :sha256),
        sample_array_byte_orders = (:little_endian, :big_endian),
        sample_array_storage_order = :julia_column_major,
        sample_telemetry_fields =
            _FREE_CORRELATION_STUDY_SAMPLE_TELEMETRY_FIELDS,
        sample_bundle_digest_required_after_bundle_return = true,
        sample_bundle_is_never_stringified = true,
        execution_quality_fields = (
            :execution_passed,
            :chain_layout_passed,
            :diagnostics_passed,
            :max_rank_normalized_rhat,
            :min_bulk_ess,
            :min_tail_ess,
            :min_e_bfmi,
            :n_divergences,
            :n_max_treedepth,
        ),
        scientific_outcome_fields = (
            :posterior_median,
            :interval_lower,
            :interval_upper,
            :interval_covered,
            :direction_matches_truth,
            :truth_sign_probability,
            :realized_latent_correlation,
        ),
        generation_evidence_fields = (
            :fixture_schema,
            :data_signature,
            :realized_latent_correlation,
            :maximum_closed_form_oracle_error,
        ),
        terminal_statuses = _FREE_CORRELATION_STUDY_TERMINAL_STATUSES,
        completed_status_uses_diagnostics_only = true,
        noncoverage_remains_completed = true,
        direction_mismatch_remains_completed = true,
        rho_zero_direction_is_missing = true,
        raw_draws_allowed = false,
        evidence_reference_is_not_a_content_digest = true,
        evidence_content_hash = :execution_provenance_sha256,
    )
end

function _mgmfrm_free_latent_correlation_2d_study_unit_preflight(
        plan,
        unit_id;
        authorization = nothing)
    checked_plan = _validate_free_correlation_study_plan(plan)
    unit_id isa AbstractString || throw(ArgumentError(
        "unit_id must be a string",
    ))
    unit = _free_correlation_study_unit(checked_plan, unit_id)
    phase_gate = if unit.phase === :feasibility
        authorization === nothing || throw(ArgumentError(
            "feasibility units do not accept an evaluation authorization artifact",
        ))
        (;
            required = false,
            authorization_present = false,
            authorization_valid = true,
            protocol_execution_authorized = true,
            blockers = (),
        )
    else
        checked_authorization = authorization === nothing ? nothing :
            _validate_free_correlation_study_feasibility_decision(
                authorization,
                checked_plan,
            )
        authorized = checked_authorization !== nothing &&
            checked_authorization.evaluation_execution_authorized
        (;
            required = true,
            authorization_present = checked_authorization !== nothing,
            authorization_valid = checked_authorization !== nothing,
            protocol_execution_authorized = authorized,
            blockers = authorized ? () :
                (:frozen_feasibility_authorization_missing_or_failed,),
        )
    end
    fixture_kwargs = (;
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
    pilot_kwargs = (;
        mode = :scientific,
        ndraws = checked_plan.sampler.draws_per_chain,
        warmup = checked_plan.sampler.warmup_per_chain,
        chains = checked_plan.sampler.chains,
        seed = unit.seeds.sampler_primary,
        step_size = checked_plan.sampler.step_size,
        target_accept = checked_plan.sampler.target_accept,
        max_depth = checked_plan.sampler.max_depth,
        max_energy_error = checked_plan.sampler.max_energy_error,
        metric = checked_plan.sampler.metric,
        ad_backend = checked_plan.sampler.ad_backend,
        init_jitter = 0.0,
        split_chains = checked_plan.sampler.split_chains,
        rhat_threshold = checked_plan.quality_requirements.maximum_rhat,
        ess_threshold = checked_plan.quality_requirements.minimum_bulk_ess,
        min_e_bfmi = checked_plan.quality_requirements.minimum_e_bfmi,
        interval = checked_plan.recovery_analysis.interval_probability,
        progress = false,
    )
    resource_checks = (;
        observation_count_exact = unit.design.n_observations ==
            unit.design.n_persons * unit.design.n_items,
        probability_cell_count_exact = unit.design.n_probability_cells ==
            unit.design.n_observations * unit.design.n_categories,
        fixture_observation_cap_within_quarantine =
            unit.design.n_observations <=
                _FREE_CORRELATION_HARD_MAX_OBSERVATIONS,
        fixture_probability_cap_within_quarantine =
            unit.design.n_probability_cells <=
                _FREE_CORRELATION_HARD_MAX_PROBABILITY_CELLS,
    )
    resources_passed = all(values(resource_checks))
    resources_passed || throw(ArgumentError(
        "planned unit workload does not satisfy quarantine caps",
    ))
    protocol_execution_authorized =
        phase_gate.protocol_execution_authorized && resources_passed
    operational_gate = (;
        initial_gradient_resource_probe = :pending,
        short_nuts_resource_profile = :pending,
        atomic_runner = :pending,
        operational_execution_authorized = false,
        blockers = (:resource_profile_and_atomic_runner_pending,),
    )
    operational_execution_authorized = false
    execution_authorized = protocol_execution_authorized &&
        operational_execution_authorized
    blockers = (
        phase_gate.blockers...,
        operational_gate.blockers...,
    )
    return (;
        schema = _FREE_CORRELATION_STUDY_UNIT_PREFLIGHT_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_unit_preflight,
        status = protocol_execution_authorized ?
            :single_unit_preflight_passed_execution_blocked_by_operational_gate :
            :single_unit_preflight_passed_execution_blocked_by_protocol_and_operational_gates,
        plan_id = checked_plan.plan_id,
        plan_fingerprint = checked_plan.plan_fingerprint,
        unit,
        fixture_kwargs,
        pilot_kwargs,
        result_contract = _free_correlation_study_result_contract_record(),
        phase_gate,
        resource_checks_scope =
            :static_workload_shape_and_quarantine_caps_only,
        resource_checks = merge(resource_checks, (; passed = resources_passed)),
        runtime_resource_profile_included = false,
        operational_gate,
        protocol_execution_authorized,
        operational_execution_authorized,
        execution_authorized,
        blockers,
        data_generated = false,
        response_data_generated = false,
        model_fit_run = false,
        mcmc_executed = false,
        mcmc_run = false,
        recovery_evidence_available = false,
        public_fit = false,
        cache_enabled = false,
        promotion_effect = :none,
    )
end

function _free_correlation_study_missing_execution_quality(
        execution_passed = missing)
    return (;
        execution_passed,
        chain_layout_passed = missing,
        diagnostics_passed = missing,
        max_rank_normalized_rhat = missing,
        min_bulk_ess = missing,
        min_tail_ess = missing,
        min_e_bfmi = missing,
        n_divergences = missing,
        n_max_treedepth = missing,
    )
end

function _free_correlation_study_missing_scientific_outcome()
    return (;
        posterior_median = missing,
        interval_lower = missing,
        interval_upper = missing,
        interval_covered = missing,
        direction_matches_truth = missing,
        truth_sign_probability = missing,
        realized_latent_correlation = missing,
    )
end

function _free_correlation_study_failure_result(
        plan,
        unit,
        status::Symbol,
        error;
        execution_quality = _free_correlation_study_missing_execution_quality(),
        generation_evidence = missing,
        sample_bundle = nothing,
        authorization_decision_fingerprint = missing)
    status in (:generation_failed, :fit_failed) || throw(ArgumentError(
        "failure-result helper accepts generation_failed or fit_failed",
    ))
    stage = status === :generation_failed ? :generation : :fit
    status === :generation_failed && sample_bundle !== nothing &&
        throw(ArgumentError(
            "generation_failed cannot contain a returned sample bundle",
        ))
    execution_provenance = if sample_bundle === nothing
        _free_correlation_study_execution_provenance(
            plan,
            unit;
            authorization_decision_fingerprint,
            generation_evidence,
            sample_bundle_unavailable_reason =
                status === :generation_failed ?
                :generation_failed_before_fit :
                :fit_failed_before_sample_bundle_returned,
        )
    else
        _free_correlation_study_execution_provenance(
            plan,
            unit;
            authorization_decision_fingerprint,
            generation_evidence,
            sample_bundle,
        )
    end
    has_sample_digest =
        execution_provenance.sample_bundle.status === :available
    result = (;
        schema = _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        rho_truth = unit.rho_truth,
        replication = unit.replication,
        seeds = unit.seeds,
        authorization_decision_fingerprint,
        attempt = 1,
        primary_status = status,
        execution_quality,
        execution_provenance,
        generation_evidence,
        scientific_outcome =
            _free_correlation_study_missing_scientific_outcome(),
        failure = (;
            stage,
            error_type = Symbol(nameof(typeof(error))),
            message = sprint(showerror, error),
        ),
        dry_run = false,
        recovery_claimed = false,
        evidence = (;
            source = has_sample_digest ?
                :free_latent_correlation_2d_recovery_pilot :
                :study_single_unit_executor,
            reference = has_sample_digest ?
                _FREE_CORRELATION_PILOT_SCHEMA : unit.unit_id,
            content_sha256 = execution_provenance.provenance_sha256,
        ),
    )
    return _validate_free_correlation_study_unit_result(result, unit, plan)
end

function _free_correlation_study_generation_evidence(fixture)
    return (;
        fixture_schema = fixture.schema,
        data_signature = _free_correlation_study_data_signature_hex(
            fixture.spec.validation.data_signature,
        ),
        realized_latent_correlation =
            fixture.truth.realized_latent_correlation,
        maximum_closed_form_oracle_error =
            fixture.likelihood_identity.maximum_closed_form_oracle_error,
    )
end

function _free_correlation_study_finite_or_missing(value)
    ismissing(value) && return missing
    value isa Real && !(value isa Bool) || return missing
    converted = Float64(value)
    return isfinite(converted) ? converted : missing
end

function _free_correlation_study_data_signature_hex(value)
    value isa Integer && !(value isa Bool) || throw(ArgumentError(
        "fixture data_signature must be an unsigned-compatible integer",
    ))
    converted = try
        UInt64(value)
    catch
        throw(ArgumentError(
            "fixture data_signature must be representable as UInt64",
        ))
    end
    return string(converted; base = 16, pad = 16)
end

function _free_correlation_study_pilot_execution_quality(pilot)
    metrics = pilot.diagnostics.metrics
    e_bfmi = pilot.diagnostics.e_bfmi.e_bfmi
    return (;
        execution_passed = pilot.summary.execution_passed,
        chain_layout_passed = pilot.summary.chain_layout_passed,
        diagnostics_passed = pilot.summary.diagnostics_passed,
        max_rank_normalized_rhat = _free_correlation_study_finite_or_missing(
            metrics.max_rank_normalized_rhat,
        ),
        min_bulk_ess = _free_correlation_study_finite_or_missing(
            metrics.min_bulk_ess,
        ),
        min_tail_ess = _free_correlation_study_finite_or_missing(
            metrics.min_tail_ess,
        ),
        min_e_bfmi = _free_correlation_study_finite_or_missing(e_bfmi),
        n_divergences = pilot.diagnostics.n_divergences,
        n_max_treedepth = pilot.diagnostics.n_max_treedepth,
    )
end

function _free_correlation_study_scoring_failure_result(
        plan,
        unit,
        pilot,
        quality,
        error;
        authorization_decision_fingerprint = missing)
    generation_evidence =
        _free_correlation_study_generation_evidence(pilot.fixture)
    execution_provenance = _free_correlation_study_execution_provenance(
        plan,
        unit;
        authorization_decision_fingerprint,
        generation_evidence,
        sample_bundle = pilot.sample_bundle,
    )
    result = (;
        schema = _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        rho_truth = unit.rho_truth,
        replication = unit.replication,
        seeds = unit.seeds,
        authorization_decision_fingerprint,
        attempt = 1,
        primary_status = :recovery_scoring_failed,
        execution_quality = quality,
        execution_provenance,
        generation_evidence,
        scientific_outcome =
            _free_correlation_study_missing_scientific_outcome(),
        failure = (;
            stage = :recovery_scoring,
            error_type = Symbol(nameof(typeof(error))),
            message = sprint(showerror, error),
        ),
        dry_run = false,
        recovery_claimed = false,
        evidence = (;
            source = :free_latent_correlation_2d_recovery_pilot,
            reference = _FREE_CORRELATION_PILOT_SCHEMA,
            content_sha256 = execution_provenance.provenance_sha256,
        ),
    )
    return _validate_free_correlation_study_unit_result(result, unit, plan)
end

function _free_correlation_study_diagnostic_failure_result(
        plan,
        unit,
        pilot,
        error;
        authorization_decision_fingerprint = missing)
    generation_evidence =
        _free_correlation_study_generation_evidence(pilot.fixture)
    execution_provenance = _free_correlation_study_execution_provenance(
        plan,
        unit;
        authorization_decision_fingerprint,
        generation_evidence,
        sample_bundle = pilot.sample_bundle,
    )
    result = (;
        schema = _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        rho_truth = unit.rho_truth,
        replication = unit.replication,
        seeds = unit.seeds,
        authorization_decision_fingerprint,
        attempt = 1,
        primary_status = :diagnostic_failed,
        execution_quality = (;
            execution_passed = true,
            chain_layout_passed = false,
            diagnostics_passed = false,
            max_rank_normalized_rhat = missing,
            min_bulk_ess = missing,
            min_tail_ess = missing,
            min_e_bfmi = missing,
            n_divergences = missing,
            n_max_treedepth = missing,
        ),
        execution_provenance,
        generation_evidence,
        scientific_outcome =
            _free_correlation_study_missing_scientific_outcome(),
        failure = (;
            stage = :diagnostics,
            error_type = Symbol(nameof(typeof(error))),
            message = sprint(showerror, error),
        ),
        dry_run = false,
        recovery_claimed = false,
        evidence = (;
            source = :free_latent_correlation_2d_recovery_pilot,
            reference = _FREE_CORRELATION_PILOT_SCHEMA,
            content_sha256 = execution_provenance.provenance_sha256,
        ),
    )
    return _validate_free_correlation_study_unit_result(result, unit, plan)
end

function _free_correlation_study_result_from_pilot(
        plan,
        unit,
        pilot;
        authorization_decision_fingerprint = missing,
        execution_quality = nothing)
    pilot.schema == _FREE_CORRELATION_PILOT_SCHEMA &&
        pilot.mode === :scientific &&
        pilot.status === :internal_single_dataset_scientific_pilot ||
        throw(ArgumentError(
            "single-unit executor received an invalid scientific pilot payload",
        ))
    quality = execution_quality === nothing ?
        _free_correlation_study_pilot_execution_quality(pilot) :
        execution_quality
    if quality.execution_passed !== true
        return _free_correlation_study_failure_result(
            plan,
            unit,
            :fit_failed,
            ErrorException(
                "scientific pilot returned without successful execution",
            );
            execution_quality =
                _free_correlation_study_missing_execution_quality(false),
            generation_evidence =
                _free_correlation_study_generation_evidence(pilot.fixture),
            sample_bundle = pilot.sample_bundle,
            authorization_decision_fingerprint,
        )
    end
    diagnostics_passed = quality.execution_passed === true &&
        quality.chain_layout_passed === true &&
        quality.diagnostics_passed === true
    status = diagnostics_passed ? :completed : :diagnostic_failed
    scientific_outcome = diagnostics_passed ? (;
        posterior_median = pilot.recovery.rho_row.posterior_median,
        interval_lower = pilot.recovery.rho_row.posterior_lower,
        interval_upper = pilot.recovery.rho_row.posterior_upper,
        interval_covered = pilot.recovery.rho_row.covered,
        direction_matches_truth =
            pilot.recovery.sign_probabilities.direction_matches_truth,
        truth_sign_probability = pilot.summary.truth_sign_probability,
        realized_latent_correlation =
            pilot.summary.realized_latent_correlation,
    ) : _free_correlation_study_missing_scientific_outcome()
    failure = diagnostics_passed ? missing : (;
        stage = :diagnostics,
        error_type = :DiagnosticGateFailure,
        message = "scientific pilot failed its frozen computation-quality gate",
    )
    generation_evidence =
        _free_correlation_study_generation_evidence(pilot.fixture)
    execution_provenance = _free_correlation_study_execution_provenance(
        plan,
        unit;
        authorization_decision_fingerprint,
        generation_evidence,
        sample_bundle = pilot.sample_bundle,
    )
    result = (;
        schema = _FREE_CORRELATION_STUDY_UNIT_RESULT_SCHEMA,
        plan_id = plan.plan_id,
        plan_fingerprint = plan.plan_fingerprint,
        unit_id = unit.unit_id,
        phase = unit.phase,
        rho_truth = unit.rho_truth,
        replication = unit.replication,
        seeds = unit.seeds,
        authorization_decision_fingerprint,
        attempt = 1,
        primary_status = status,
        execution_quality = quality,
        execution_provenance,
        generation_evidence,
        scientific_outcome,
        failure,
        dry_run = false,
        recovery_claimed = false,
        evidence = (;
            source = :free_latent_correlation_2d_recovery_pilot,
            reference = _FREE_CORRELATION_PILOT_SCHEMA,
            content_sha256 = execution_provenance.provenance_sha256,
        ),
    )
    return _validate_free_correlation_study_unit_result(result, unit, plan)
end

function _mgmfrm_free_latent_correlation_2d_study_run_unit(
        plan,
        unit_id;
        execute_mcmc::Bool = false,
        authorization = nothing)
    preflight = _mgmfrm_free_latent_correlation_2d_study_unit_preflight(
        plan,
        unit_id;
        authorization,
    )
    execute_mcmc && throw(ArgumentError(
        "scientific execution is unavailable from this preflight-only " *
        "entry point; use the future atomic single-unit scientific worker",
    ))
    return preflight
end

function _mgmfrm_free_latent_correlation_2d_study_dry_run(
        plan;
        max_units = 2)
    checked_plan = _validate_free_correlation_study_plan(plan)
    checked_max = _free_correlation_checked_integer(
        max_units,
        :max_units,
    )
    checked_max <= checked_plan.resource_policy.dry_run_hard_max_units ||
        throw(ArgumentError(
            "max_units exceeds the frozen bounded dry-run limit",
        ))
    feasibility_units = sort(
        [unit for unit in checked_plan.units
            if unit.phase === :feasibility];
        by = unit -> (unit.replication, unit.rho_index),
    )
    selected = feasibility_units[1:min(checked_max, length(feasibility_units))]
    total_observations = sum(unit.design.n_observations for unit in selected)
    total_probability_cells = sum(
        unit.design.n_probability_cells for unit in selected
    )
    total_observations <=
        checked_plan.resource_policy.dry_run_max_observations &&
        total_probability_cells <=
            checked_plan.resource_policy.dry_run_max_probability_cells ||
        throw(ArgumentError("bounded dry-run workload exceeds its frozen caps"))
    rows = NamedTuple[]
    for unit in selected
        preflight = _mgmfrm_free_latent_correlation_2d_study_unit_preflight(
            checked_plan,
            unit.unit_id,
        )
        fixture = _mgmfrm_free_latent_correlation_2d_known_truth_fixture(;
            preflight.fixture_kwargs...,
        )
        _validate_free_correlation_known_truth_fixture(fixture)
        push!(rows, (;
            unit_id = unit.unit_id,
            phase = unit.phase,
            rho_truth = unit.rho_truth,
            replication = unit.replication,
            seeds = unit.seeds,
            fixture_status = fixture.status,
            fixture_summary = fixture.summary,
            data_signature = _free_correlation_study_data_signature_hex(
                fixture.spec.validation.data_signature,
            ),
            maximum_closed_form_oracle_error =
                fixture.likelihood_identity.maximum_closed_form_oracle_error,
            fixture_generated = true,
            mcmc_executed = false,
            recovery_evidence_available = false,
        ))
    end
    return (;
        schema = _FREE_CORRELATION_STUDY_DRY_RUN_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_dry_run,
        status = :bounded_feasibility_fixture_dry_run_passed,
        plan_id = checked_plan.plan_id,
        plan_fingerprint = checked_plan.plan_fingerprint,
        unit_roster_sha256 = checked_plan.unit_roster_sha256,
        phase = :feasibility,
        n_planned_units = length(checked_plan.units),
        planned_unit_ids = Tuple(unit.unit_id for unit in checked_plan.units),
        all_planned_units_retained = length(checked_plan.units) == 525 &&
            artifact_content_hash(checked_plan.units) ==
                checked_plan.unit_roster_sha256,
        max_units_requested = checked_max,
        n_units = length(rows),
        total_observations,
        total_probability_cells,
        unit_rows = Tuple(rows),
        fixture_generation_executed = true,
        mcmc_executed = false,
        dry_run = true,
        dry_run_is_recovery_evidence = false,
        recovery_evidence_available = false,
        public_fit = false,
        cache_enabled = false,
        promotion_effect = :none,
        summary = (;
            passed = all(row -> row.fixture_generated &&
                !row.mcmc_executed &&
                !row.recovery_evidence_available,
                rows) && length(checked_plan.units) == 525,
            planned_units_retained = length(checked_plan.units),
            evaluation_units_materialized = 0,
            mcmc_units_executed = 0,
            next_gate = :fixed_unit_initial_gradient_resource_probe,
        ),
    )
end
