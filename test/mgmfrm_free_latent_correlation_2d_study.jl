using Test
using BayesianMGMFRM
using SHA

const _FREE_CORRELATION_STUDY_TEST_PROVENANCE_CACHE = Dict{Symbol,Any}()

function _free_correlation_study_test_sample_bundle()
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_sample_bundle.v1",
        family = :mgmfrm,
        scope = :mgmfrm_2d_free_latent_correlation_candidate,
        status = :internal_execution_smoke,
        backend = :advancedhmc,
        sampler = :nuts,
        diagnostic_status = :not_evaluable_smoke,
        claim_scope = :execution_smoke_not_recovery,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        result_type = :named_tuple_only,
        convergence_evaluated = true,
        recovery_verified = false,
        raw_parameter_names = [:theta, :zrho],
        initial_raw_parameter_values = Float64[0.0, 0.1],
        initial_logdensity = -1.0,
        chain_initials = Float64[0.0 0.1; 0.0 -0.1],
        chain_initial_logdensity = Float64[-1.0, -1.1],
        draws = Float64[0.1 0.2; 0.2 0.3; -0.1 -0.2; -0.2 -0.3],
        base_draws = reshape(Float64[0.1, 0.2, -0.1, -0.2], 4, 1),
        zrho_draws = Float64[0.2, 0.3, -0.2, -0.3],
        rho_draws = tanh.(Float64[0.2, 0.3, -0.2, -0.3]),
        logdensity = Float64[-1.0, -1.1, -1.2, -1.3],
        reevaluated_logdensity = Float64[-1.0, -1.1, -1.2, -1.3],
        pointwise_loglikelihood = reshape(Float64[-0.1, -0.2, -0.3,
            -0.4, -0.2, -0.3, -0.4, -0.5], 4, 2),
        direct_draws = Float64[0.1 0.2; 0.2 0.3; -0.1 -0.2; -0.2 -0.3],
        direct_pointwise_loglikelihood = reshape(Float64[-0.1, -0.2,
            -0.3, -0.4, -0.2, -0.3, -0.4, -0.5], 4, 2),
        direct_loglikelihood = Float64[-0.3, -0.7, -0.5, -0.9],
        candidate_loglikelihood = Float64[-0.3, -0.7, -0.5, -0.9],
        chain_ids = Int[1, 1, 2, 2],
        iterations = Int[1, 2, 1, 2],
        chain_acceptance_rate = Float64[0.9, 0.91],
        sampler_controls = (; chains = 2, draws = 2, target_accept = 0.9),
        sampler_stats = ((; chain = 1, acceptance_rate = 0.9),
            (; chain = 2, acceptance_rate = 0.91)),
        sampler_rows = ((; chain = 1, n_divergences = 0),
            (; chain = 2, n_divergences = 0)),
        logdensity_revalidation = (; max_abs_error = 0.0, passed = true),
        direct_constraint_rows = ((; parameter = :theta, passed = true),),
        likelihood_identity = (; max_abs_error = 0.0, passed = true),
        pointwise_identity = (;
            max_sum_abs_error = 0.0,
            max_direct_abs_error = 0.0,
            passed = true,
        ),
        summary = (; passed = true, total_draws = 4),
    )
end

function _free_correlation_study_test_execution_environment()
    return get!(_FREE_CORRELATION_STUDY_TEST_PROVENANCE_CACHE,
        :execution_environment) do
        getfield(
            BayesianMGMFRM,
            :_free_correlation_study_execution_environment,
        )()
    end
end

function _free_correlation_study_test_provenance(
        plan,
        unit,
        status::Symbol;
        sample_bundle_returned::Bool = status in (
            :completed,
            :diagnostic_failed,
            :recovery_scoring_failed),
        authorization_decision_fingerprint = missing,
        generation_evidence = missing)
    constructor = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_execution_provenance,
    )
    execution_environment =
        _free_correlation_study_test_execution_environment()
    if sample_bundle_returned
        return constructor(
            plan,
            unit;
            authorization_decision_fingerprint,
            generation_evidence,
            sample_bundle = _free_correlation_study_test_sample_bundle(),
            execution_environment,
        )
    end
    return constructor(
        plan,
        unit;
        authorization_decision_fingerprint,
        generation_evidence,
        sample_bundle_unavailable_reason =
            status === :generation_failed ?
            :generation_failed_before_fit :
            :fit_failed_before_sample_bundle_returned,
        execution_environment,
    )
end

function _free_correlation_study_capture_error(f)
    try
        f()
        return nothing
    catch error
        return error
    end
end

function _free_correlation_study_result(plan, unit;
        status::Symbol = :completed,
        covered::Bool = true,
        posterior_median = unit.rho_truth,
        sample_bundle_returned::Bool = status in (
            :completed,
            :diagnostic_failed,
            :recovery_scoring_failed),
        authorization_decision_fingerprint = missing,
        generation_evidence_override = nothing)
    completed = status === :completed
    median = completed ? Float64(posterior_median) : missing
    if completed && !covered && median == unit.rho_truth
        median = iszero(unit.rho_truth) ? 0.3 : -unit.rho_truth
    end
    lower, upper = if completed && covered
        (
            max(-0.99, min(median, unit.rho_truth) - 0.05),
            min(0.99, max(median, unit.rho_truth) + 0.05),
        )
    elseif completed
        (max(-0.99, median - 0.05), min(0.99, median + 0.05))
    else
        (missing, missing)
    end
    interval_covered = completed ?
        lower <= unit.rho_truth <= upper : missing
    direction_matches_truth = !completed || iszero(unit.rho_truth) ?
        missing : sign(median) == sign(unit.rho_truth)
    realized_latent_correlation = clamp(
        unit.rho_truth + 0.01,
        -0.99,
        0.99,
    )
    execution_quality = status in (:completed, :recovery_scoring_failed) ? (;
        execution_passed = true,
        chain_layout_passed = true,
        diagnostics_passed = true,
        max_rank_normalized_rhat = 1.0,
        min_bulk_ess = 500.0,
        min_tail_ess = 500.0,
        min_e_bfmi = 0.5,
        n_divergences = 0,
        n_max_treedepth = 0,
    ) : status === :diagnostic_failed ? (;
        execution_passed = true,
        chain_layout_passed = true,
        diagnostics_passed = false,
        max_rank_normalized_rhat = 1.2,
        min_bulk_ess = 100.0,
        min_tail_ess = 100.0,
        min_e_bfmi = 0.2,
        n_divergences = 0,
        n_max_treedepth = 0,
    ) : status === :fit_failed ? (;
        execution_passed = false,
        chain_layout_passed = missing,
        diagnostics_passed = missing,
        max_rank_normalized_rhat = missing,
        min_bulk_ess = missing,
        min_tail_ess = missing,
        min_e_bfmi = missing,
        n_divergences = missing,
        n_max_treedepth = missing,
    ) : (;
        execution_passed = missing,
        chain_layout_passed = missing,
        diagnostics_passed = missing,
        max_rank_normalized_rhat = missing,
        min_bulk_ess = missing,
        min_tail_ess = missing,
        min_e_bfmi = missing,
        n_divergences = missing,
        n_max_treedepth = missing,
    )
    failure = status === :completed ? missing : (;
        stage = status === :generation_failed ? :generation :
            status === :fit_failed ? :fit :
            status === :diagnostic_failed ? :diagnostics : :recovery_scoring,
        error_type = status === :recovery_scoring_failed ?
            :recovery_scoring_exception :
            status === :fit_failed ? :sampler_exception :
            status === :generation_failed ? :generator_exception :
            :diagnostic_threshold_failure,
        message = "intentional $(status) test record",
    )
    generation_evidence = status === :generation_failed ? missing :
        generation_evidence_override === nothing ? (;
            fixture_schema =
                "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_known_truth_fixture.v1",
            data_signature = string(
                UInt64(unit.unit_index);
                base = 16,
                pad = 16,
            ),
            realized_latent_correlation,
            maximum_closed_form_oracle_error = 0.0,
        ) : generation_evidence_override
    execution_provenance = _free_correlation_study_test_provenance(
        plan,
        unit,
        status;
        sample_bundle_returned,
        authorization_decision_fingerprint,
        generation_evidence,
    )
    sample_digest_available =
        execution_provenance.sample_bundle.status === :available
    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_unit_result.v2",
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
        scientific_outcome = (;
            posterior_median = median,
            interval_lower = lower,
            interval_upper = upper,
            interval_covered,
            direction_matches_truth,
            truth_sign_probability = !completed || iszero(unit.rho_truth) ?
                missing : direction_matches_truth ? 0.9 : 0.1,
            realized_latent_correlation = completed ?
                realized_latent_correlation : missing,
        ),
        failure,
        dry_run = false,
        recovery_claimed = false,
        evidence = (;
            source = sample_digest_available ?
                :free_latent_correlation_2d_recovery_pilot :
                :study_single_unit_executor,
            reference = sample_digest_available ?
                "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_recovery_pilot.v1" :
                unit.unit_id,
            content_sha256 = execution_provenance.provenance_sha256,
        ),
    )
end

function _free_correlation_study_with_distinct_execution_environment(result)
    provenance = result.execution_provenance
    runtime = merge(provenance.runtime, (;
        n_threads = provenance.runtime.n_threads + 1,
    ))
    environment_identity_material = (;
        runtime,
        environment = provenance.environment,
        sources = provenance.sources,
    )
    material = (;
        schema = provenance.schema,
        runtime,
        environment = provenance.environment,
        sources = provenance.sources,
        execution_environment_sha256 =
            artifact_content_hash(environment_identity_material),
        execution_binding = provenance.execution_binding,
        sample_bundle = provenance.sample_bundle,
    )
    distinct_provenance = merge(material, (;
        provenance_sha256 = artifact_content_hash(material),
    ))
    return merge(result, (;
        execution_provenance = distinct_provenance,
        evidence = merge(result.evidence, (;
            content_sha256 = distinct_provenance.provenance_sha256,
        )),
    ))
end

function _free_correlation_study_materialize_evaluation(
        feasibility_ledger,
        authorization,
        result_factory)
    plan = feasibility_ledger.plan
    application_index = feasibility_ledger.summary.n_results_recorded
    rows = Any[]
    for row in feasibility_ledger.unit_rows
        if row.unit.phase === :feasibility
            push!(rows, row)
            continue
        end
        application_index += 1
        result = result_factory(row.unit)
        push!(rows, (;
            unit = row.unit,
            result,
            application_index,
            authorization_artifact = authorization,
            protocol_violations = (),
        ))
    end
    unit_rows = Tuple(rows)
    summarize = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_ledger_summary,
    )
    ledger_status = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_ledger_status,
    )
    summary = summarize(unit_rows, plan)
    return merge(feasibility_ledger, (;
        status = ledger_status(summary),
        unit_rows,
        summary,
    ))
end

function _free_correlation_study_wilson_lower(successes, trials, z)
    estimate = successes / trials
    z2 = z^2
    denominator = 1 + z2 / trials
    center = (estimate + z2 / (2trials)) / denominator
    half_width = z / denominator * sqrt(
        estimate * (1 - estimate) / trials + z2 / (4trials^2),
    )
    return max(0.0, center - half_width)
end

function _free_correlation_study_bigfloat_endpoint_candidates(
        values::Vector{Float64},
        n_planned::Int,
        support_lower::Float64,
        support_upper::Float64)
    return setprecision(BigFloat, 512) do
        observed = BigFloat.(values)
        observed_sum = sum(observed; init = BigFloat(0))
        observed_sum_of_squares = sum(abs2, observed; init = BigFloat(0))
        lower = BigFloat(support_lower)
        upper = BigFloat(support_upper)
        n_unresolved = n_planned - length(values)
        candidates = NamedTuple[]
        for n_upper in 0:n_unresolved
            n_lower = n_unresolved - n_upper
            total_sum = observed_sum + n_lower * lower + n_upper * upper
            total_sum_of_squares = observed_sum_of_squares +
                n_lower * lower^2 + n_upper * upper^2
            mean = total_sum / n_planned
            standard_error_squared = n_planned == 1 ? BigFloat(Inf) :
                (n_planned * total_sum_of_squares - total_sum^2) /
                (BigInt(n_planned)^2 * BigInt(n_planned - 1))
            push!(candidates, (;
                n_lower,
                n_upper,
                mean,
                standard_error_squared,
            ))
        end
        candidates
    end
end

function _free_correlation_study_bigfloat_endpoint_oracle(
        values::Vector{Float64},
        n_planned::Int,
        support_lower::Float64,
        support_upper::Float64,
        z::Float64;
        objective::Symbol)
    return setprecision(BigFloat, 512) do
        candidates = _free_correlation_study_bigfloat_endpoint_candidates(
            values,
            n_planned,
            support_lower,
            support_upper,
        )
        maximum((objective === :absolute_mean ? abs(candidate.mean) :
                candidate.mean) + BigFloat(z) *
                sqrt(candidate.standard_error_squared)
            for candidate in candidates)
    end
end

function _free_correlation_study_bigfloat_symmetry_oracle(
        negative_values::Vector{Float64},
        negative_n_planned::Int,
        negative_support::Tuple{Float64,Float64},
        positive_values::Vector{Float64},
        positive_n_planned::Int,
        positive_support::Tuple{Float64,Float64},
        z::Float64)
    return setprecision(BigFloat, 512) do
        negative_candidates =
            _free_correlation_study_bigfloat_endpoint_candidates(
                negative_values,
                negative_n_planned,
                negative_support...,
            )
        positive_candidates =
            _free_correlation_study_bigfloat_endpoint_candidates(
                positive_values,
                positive_n_planned,
                positive_support...,
            )
        maximum(abs(negative.mean + positive.mean) + BigFloat(z) *
                sqrt(negative.standard_error_squared +
                    positive.standard_error_squared)
            for negative in negative_candidates
            for positive in positive_candidates)
    end
end

@testset "quarantined replicated free-correlation study ledger" begin
    experimental = BayesianMGMFRM.Experimental
    plan = experimental.free_latent_correlation_2d_study_plan()
    replay = experimental.free_latent_correlation_2d_study_plan()

    @test plan isa NamedTuple
    @test isequal(plan, replay)
    @test plan.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_plan.v2"
    @test plan.object === :mgmfrm_free_latent_correlation_2d_study_plan
    @test plan.plan_id ==
        "mgmfrm_free_latent_correlation_2d_recovery_study_v2"
    @test plan.version == 2
    @test plan.plan_fingerprint ==
        "d3f39355bf16c8ae984b58f5b2c52b5ab81ccbbe26a68379e31d0281b2beb4e3"
    @test plan.unit_roster_sha256 ==
        "0c4939ab76a0e5f78c2dd13896446c51a7faecdff65288b5b94c9c957cc62d08"
    @test plan.lineage.predecessor_plan_id ==
        "mgmfrm_free_latent_correlation_2d_recovery_study_v1"
    @test plan.lineage.predecessor_plan_fingerprint ==
        "39a850946e48dee20839a2a68d585a4c190a8f1d18a0a4b366fef574786aa128"
    @test plan.lineage.predecessor_unit_roster_sha256 ==
        "67d620bd816a820d35302e43ca148ec247b86a7a050ea35535caee9201dbd1f4"
    @test plan.lineage.predecessor_scientific_executions == 0
    @test plan.lineage.predecessor_primary_executions == 0
    @test plan.lineage.predecessor_status ===
        :retired_before_scientific_execution
    @test ismissing(plan.lineage.predecessor_execution_provenance_schema)
    @test !plan.lineage.predecessor_execution_provenance_available
    @test !plan.lineage.predecessor_plan_artifact_retained
    @test !plan.lineage.
        predecessor_plan_hash_reconstructible_from_repository
    @test plan.lineage.predecessor_identity_evidence ===
        :historical_recorded_output_only
    @test plan.lineage.amendment_reason ===
        :execution_provenance_unit_binding_environment_identity_fail_closed_resource_contract_and_endpoint_enumerated_unresolved_envelope_scorer
    @test plan.status === :locally_preregistered_execution_not_started
    @test plan.frozen
    @test !plan.externally_registered
    @test plan.family === :mgmfrm
    @test plan.scope ===
        :quarantined_2d_free_latent_correlation_recovery_study
    @test !plan.public_fit
    @test !plan.fit_ready
    @test !plan.cache_enabled
    @test plan.promotion_effect === :none
    @test plan.result_type === :named_tuple_only
    @test !plan.feasibility_execution_completed
    @test !plan.evaluation_execution_authorized
    @test !plan.evaluation_execution_completed
    @test !plan.replicated_recovery_verified
    @test !plan.dry_run_is_recovery_evidence
    @test !plan.resource_probe_completed
    @test !plan.short_nuts_resource_profile_completed
    @test !plan.atomic_runner_ready
    @test !plan.operational_execution_authorized
    @test !plan.scientific_execution_authorized
    @test plan.next_gate ===
        :initial_gradient_resource_probe_then_short_nuts_profile_and_atomic_runner

    @test isdefined(experimental, :free_latent_correlation_2d_study_plan)
    for name in (
            :free_latent_correlation_2d_study_plan,
            :free_latent_correlation_2d_study_ledger,
            :free_latent_correlation_2d_study_apply_result,
            :free_latent_correlation_2d_study_feasibility_decision,
            :free_latent_correlation_2d_study_unit_preflight,
            :free_latent_correlation_2d_study_resource_probe,
            :free_latent_correlation_2d_study_run_unit,
            :free_latent_correlation_2d_study_dry_run,
            :free_latent_correlation_2d_study_score)
        @test name ∉ names(experimental)
        @test name ∉ names(BayesianMGMFRM)
    end
    for name in (
            :_mgmfrm_free_latent_correlation_2d_study_plan,
            :_mgmfrm_free_latent_correlation_2d_study_ledger,
            :_mgmfrm_free_latent_correlation_2d_study_apply_result,
            :_mgmfrm_free_latent_correlation_2d_study_feasibility_decision,
            :_mgmfrm_free_latent_correlation_2d_study_unit_preflight,
            :_mgmfrm_free_latent_correlation_2d_study_resource_probe,
            :_mgmfrm_free_latent_correlation_2d_study_run_unit,
            :_mgmfrm_free_latent_correlation_2d_study_dry_run,
            :_mgmfrm_free_latent_correlation_2d_study_score)
        @test name ∉ names(BayesianMGMFRM)
    end

    @test plan.rho_grid == (-0.6, -0.3, 0.0, 0.3, 0.6)
    @test plan.phases.feasibility.replications_per_rho == 5
    @test plan.phases.feasibility.n_units == 25
    @test plan.phases.feasibility.role === :computational_feasibility_only
    @test !plan.phases.feasibility.recovery_claim_allowed
    @test !plan.phases.feasibility.threshold_tuning_allowed
    @test plan.phases.evaluation.replications_per_rho == 100
    @test plan.phases.evaluation.n_units == 500
    @test plan.phases.evaluation.role ===
        :frozen_replicated_recovery_evaluation
    @test plan.phases.evaluation.starts_only_after_feasibility_gate
    @test !plan.phases.evaluation.mid_evaluation_extension_allowed
    @test length(plan.units) == 525
    @test plan.checks.n_units == 525
    @test plan.checks.n_feasibility_units == 25
    @test plan.checks.n_evaluation_units == 500
    @test plan.checks.unit_ids_unique
    @test plan.checks.rho_grid_symmetric
    @test plan.checks.rho_zero_included
    @test plan.checks.seeds_disjoint
    @test plan.checks.passed
    @test plan.design.dimensions == 2
    @test plan.design.n_persons == 300
    @test plan.design.items_per_dimension == 6
    @test plan.design.n_items == 12
    @test plan.design.n_raters == 4
    @test plan.design.n_categories == 4
    @test plan.design.n_observations_per_unit == 3_600
    @test plan.design.n_probability_cells_per_unit == 14_400
    @test all(unit -> unit.design == (;
            n_persons = 300,
            items_per_dimension = 6,
            n_items = 12,
            n_raters = 4,
            n_categories = 4,
            n_observations = 3_600,
            n_probability_cells = 14_400,
        ), plan.units)

    unit_ids = [unit.unit_id for unit in plan.units]
    @test length(unique(unit_ids)) == length(unit_ids)
    @test first(unit_ids) ==
        "mgmfrm_freecorr_feasibility_rho_m060_rep_001"
    @test unit_ids[25] ==
        "mgmfrm_freecorr_feasibility_rho_p060_rep_005"
    @test unit_ids[26] ==
        "mgmfrm_freecorr_evaluation_rho_m060_rep_001"
    @test last(unit_ids) ==
        "mgmfrm_freecorr_evaluation_rho_p060_rep_100"
    @test [unit.unit_index for unit in plan.units] == collect(1:525)
    @test all(unit -> unit.execution_status === :planned_not_run,
        plan.units)

    for (phase, replications) in ((:feasibility, 5), (:evaluation, 100))
        phase_units = filter(unit -> unit.phase === phase, plan.units)
        @test length(phase_units) == 5 * replications
        for rho in plan.rho_grid
            cell = filter(unit -> unit.rho_truth == rho, phase_units)
            @test length(cell) == replications
            @test [unit.replication for unit in cell] ==
                collect(1:replications)
        end
    end

    @test all(unit -> unit.primary_lkj_eta == 2, plan.units)
    @test plan.prior_sensitivity.status ===
        :pending_separate_versioned_protocol
    @test !plan.prior_sensitivity.included_in_primary_unit_roster
    @test !plan.prior_sensitivity.included_in_primary_denominator
    @test plan.prior_sensitivity.future_sensitivity_lkj_etas == (1, 4)
    @test plan.unit_result_contract.primary_terminal_statuses == (
        :completed,
        :generation_failed,
        :fit_failed,
        :diagnostic_failed,
        :recovery_scoring_failed,
    )
    @test !plan.unit_result_contract.raw_draws_allowed
    @test plan.unit_result_contract.execution_provenance_required
    @test plan.unit_result_contract.execution_provenance_schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_execution_provenance.v2"
    @test plan.unit_result_contract.execution_environment_hash_material ==
        (:runtime, :environment, :sources)
    @test plan.unit_result_contract.evidence_content_hash ===
        :execution_provenance_sha256
    @test plan.unit_result_contract.runtime_fields ==
        (:julia_version, :n_threads, :os, :arch)
    @test plan.unit_result_contract.environment_files == (:project, :manifest)
    @test plan.unit_result_contract.source_paths == (
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
    @test plan.unit_result_contract.
        source_hashes_are_runtime_evidence_not_plan_fingerprint_material
    @test plan.unit_result_contract.sample_array_digest_fields ==
        (:eltype, :size, :nbytes, :sha256)
    @test plan.unit_result_contract.sample_array_manifest_fields ==
        (:field, :byte_order, :storage_order, :digest)
    @test plan.unit_result_contract.sample_array_byte_orders ==
        (:little_endian, :big_endian)
    @test plan.unit_result_contract.sample_array_storage_order ===
        :julia_column_major
    @test plan.unit_result_contract.sample_digest_required_after_bundle_return
    @test !plan.resource_policy.sample_bundle_stringification_allowed
    @test plan.resource_policy.sample_bundle_digest_policy ===
        :stream_numeric_array_bytes_and_digest_structured_telemetry
    probe_policy = plan.resource_policy.initial_gradient_probe
    @test probe_policy.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe.v1"
    @test probe_policy.phase === :feasibility
    @test !probe_policy.execute_measurement_default
    @test probe_policy.default_repetitions == 3
    @test probe_policy.minimum_repetitions == 1
    @test probe_policy.maximum_repetitions == 5
    @test probe_policy.operation === :initial_logdensity_and_gradient
    @test probe_policy.ad_backend === :ForwardDiff
    @test probe_policy.adapter_validation_evaluations == 1
    @test probe_policy.warmup_evaluations == 1
    @test probe_policy.gc_before_each_timed_evaluation
    @test probe_policy.maximum_median_gradient_seconds == 0.10
    @test probe_policy.maximum_median_allocated_bytes == 128 * 1024^2
    @test probe_policy.maximum_median_gc_time_fraction == 0.50
    @test probe_policy.minimum_free_memory_bytes == 8 * 1024^3
    @test probe_policy.planning_gradients_per_transition == 32
    @test probe_policy.planned_transitions_per_chain == 1_000
    @test probe_policy.planned_chains == 4
    @test probe_policy.planned_transitions_per_full_unit == 4_000
    @test probe_policy.maximum_estimated_full_unit_seconds == 7_200.0
    @test probe_policy.short_nuts_profile_required
    @test probe_policy.atomic_runner_required
    @test !probe_policy.gradient_profile_alone_authorizes_scientific_execution
    @test !probe_policy.mcmc_allowed
    @test plan.checks.resource_probe_transition_count_exact
    @test plan.checks.resource_probe_fail_closed

    primary_seed_fields = (:ability, :response, :sampler_primary)
    for field in primary_seed_fields
        values_for_role = [getproperty(unit.seeds, field) for unit in plan.units]
        @test length(unique(values_for_role)) == length(plan.units)
    end
    for first_index in 1:(length(primary_seed_fields) - 1)
        for second_index in (first_index + 1):length(primary_seed_fields)
            first_values = Set(getproperty(unit.seeds,
                primary_seed_fields[first_index]) for unit in plan.units)
            second_values = Set(getproperty(unit.seeds,
                primary_seed_fields[second_index]) for unit in plan.units)
            @test isempty(intersect(first_values, second_values))
        end
    end
    all_reserved_seeds = Int[
        seed
        for unit in plan.units
        for seed in values(unit.seeds)
    ]
    @test length(unique(all_reserved_seeds)) == length(all_reserved_seeds)
    feasibility_seeds = Set(Int[
        seed
        for unit in plan.units if unit.phase === :feasibility
        for seed in values(unit.seeds)
    ])
    evaluation_seeds = Set(Int[
        seed
        for unit in plan.units if unit.phase === :evaluation
        for seed in values(unit.seeds)
    ])
    @test isempty(intersect(feasibility_seeds, evaluation_seeds))
    @test plan.seed_checks.ability_unique
    @test plan.seed_checks.response_unique
    @test plan.seed_checks.sampler_unique
    @test plan.seed_checks.all_active_seed_values_unique
    @test plan.seed_checks.phase_namespaces_disjoint
    @test plan.seed_checks.passed
    @test plan.seed_policy.ability_namespace == 410_000_000
    @test plan.seed_policy.response_namespace == 520_000_000
    @test plan.seed_policy.sampler_primary_namespace == 630_000_000

    @test plan.denominator_policy.evaluation_denominator ===
        :all_planned_units_fixed
    @test plan.denominator_policy.n_planned_evaluation_units == 500
    @test plan.denominator_policy.n_planned_per_rho == 100
    @test plan.denominator_policy.generation_failed_counts_in_denominator
    @test plan.denominator_policy.fit_failed_counts_in_denominator
    @test plan.denominator_policy.diagnostic_failed_counts_in_denominator
    @test plan.denominator_policy.
        recovery_scoring_failed_counts_in_denominator
    @test plan.denominator_policy.missing_units_may_not_be_dropped
    @test plan.denominator_policy.completed_noncoverage_remains_completed
    @test plan.quality_requirements.
        execution_status_uses_computation_quality_only
    @test plan.quality_requirements.
        interval_coverage_is_scientific_outcome_not_execution_status
    @test plan.quality_requirements.
        direction_match_is_scientific_outcome_not_execution_status
    @test plan.recovery_analysis.rho_zero_direction_status ===
        :not_applicable_missing
    @test plan.recovery_analysis.fixed_evaluation_thresholds.scorer_status ===
        :contract_frozen_scorer_implemented_and_validated
    scorer_contract =
        plan.recovery_analysis.fixed_evaluation_thresholds
    @test scorer_contract.algorithm ===
        :wilson_unresolved_envelope_endpoint_enumerated_full_denominator_mcse_unpaired_symmetry_v2
    @test scorer_contract.bias_guard ===
        :endpoint_enumerated_full_denominator_unresolved_abs_mean_bias_plus_1_96_mcse_at_most_0_10
    @test scorer_contract.rmse_guard ===
        :endpoint_enumerated_full_denominator_unresolved_sqrt_mse_plus_1_645_mcse_mse_at_most_0_20
    @test scorer_contract.unpaired_symmetry_guard ===
        :endpoint_enumerated_full_denominator_unresolved_abs_contrast_plus_1_96_independent_se_at_most_0_10

    continuous_bounds_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_continuous_bounds,
    )
    endpoint_mcse_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_endpoint_imputed_mcse_upper,
    )
    exact_rational_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_exact_rational,
    )
    rational_from_record_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_rational_from_record,
    )
    exact_statistics_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_exact_sufficient_statistics,
    )
    exact_statistics_record_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_exact_statistics_record,
    )
    symmetry_endpoint_mcse_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_symmetry_endpoint_imputed_mcse_upper,
    )
    directed_rational_sqrt_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_directed_rational_sqrt_float64,
    )
    binary_summary_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_binary_summary,
    )
    @test exact_rational_helper(0.1) ==
        BigInt(3_602_879_701_896_397) // BigInt(36_028_797_018_963_968)
    @test exact_rational_helper(-0.1) ==
        -BigInt(3_602_879_701_896_397) // BigInt(36_028_797_018_963_968)
    minimum_subnormal = nextfloat(0.0)
    minimum_subnormal_exact = BigInt(1) // (BigInt(1) << 1074)
    @test exact_rational_helper(minimum_subnormal) ==
        minimum_subnormal_exact
    @test exact_rational_helper(-minimum_subnormal) ==
        -minimum_subnormal_exact
    maximum_float_exact = (BigInt(2)^53 - 1) << 971
    @test exact_rational_helper(floatmax(Float64)) == maximum_float_exact
    @test exact_rational_helper(-floatmax(Float64)) == -maximum_float_exact
    @test iszero(exact_rational_helper(0.0))
    @test iszero(exact_rational_helper(-0.0))
    for value in (
            0.1,
            -0.1,
            minimum_subnormal,
            -minimum_subnormal,
            floatmax(Float64),
            -floatmax(Float64))
        @test Float64(exact_rational_helper(value)) == value
    end
    @test_throws ArgumentError binary_summary_helper(
        0,
        0,
        0,
        scorer_contract.two_sided_normal_quantile,
    )
    @test_throws MethodError binary_summary_helper(
        true,
        1,
        1,
        scorer_contract.two_sided_normal_quantile,
    )
    @test_throws ArgumentError continuous_bounds_helper(Float64[], 0.0, 0)
    @test_throws ArgumentError continuous_bounds_helper(
        zeros(Float64, 2),
        0.0,
        1,
    )
    @test_throws ArgumentError continuous_bounds_helper(Float64[], NaN, 100)
    @test_throws ArgumentError continuous_bounds_helper(Float64[], 1.0, 100)
    @test_throws ArgumentError continuous_bounds_helper(
        Float64[NaN],
        0.0,
        100,
    )
    @test_throws ArgumentError continuous_bounds_helper(
        Float64[1.01],
        0.0,
        100,
    )
    all_unresolved_bounds = continuous_bounds_helper(Float64[], 0.0, 100)
    @test all_unresolved_bounds.n_unresolved == 100
    @test all_unresolved_bounds.bias.lower == -1.0
    @test all_unresolved_bounds.bias.upper == 1.0
    one_observed_bounds =
        continuous_bounds_helper(Float64[0.0], 0.0, 100)
    @test one_observed_bounds.n_unresolved == 99
    @test all(isfinite, (
        one_observed_bounds.bias.lower,
        one_observed_bounds.bias.upper,
        one_observed_bounds.root_mean_squared_error.lower,
        one_observed_bounds.root_mean_squared_error.upper,
    ))
    boundary_bounds = continuous_bounds_helper(zeros(Float64, 90), 0.0, 100)
    exact_one_tenth = BigInt(1) // BigInt(10)
    @test exact_rational_helper(boundary_bounds.bias.upper) >= exact_one_tenth
    @test exact_rational_helper(prevfloat(boundary_bounds.bias.upper)) <
        exact_one_tenth
    @test BigFloat(boundary_bounds.bias.upper) >=
        BigFloat(1) / BigFloat(10)
    @test boundary_bounds.numerical_policy ===
        :exact_rational_bounds_then_directed_float64_conversion

    all_unresolved_endpoint = endpoint_mcse_helper(
        Float64[],
        100,
        -1.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    @test all_unresolved_endpoint.n_observed == 0
    @test all_unresolved_endpoint.endpoint_configurations_evaluated == 101
    @test isfinite(all_unresolved_endpoint.upper)
    @test all_unresolved_endpoint.method ===
        :exact_rational_support_endpoint_enumeration_full_planned_denominator_mcse
    @test all_unresolved_endpoint.numerical_policy ===
        :smallest_float64_not_below_exact_rational_upper_using_exact_comparison
    one_observed_endpoint = endpoint_mcse_helper(
        Float64[0.0],
        100,
        -1.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    @test one_observed_endpoint.n_observed == 1
    @test one_observed_endpoint.endpoint_configurations_evaluated == 100
    @test isfinite(one_observed_endpoint.upper)
    rho_zero_one_unresolved_bias = endpoint_mcse_helper(
        zeros(Float64, 99),
        100,
        -1.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    rho_zero_one_unresolved_mse = endpoint_mcse_helper(
        zeros(Float64, 99),
        100,
        0.0,
        1.0,
        scorer_contract.one_sided_normal_quantile;
        objective = :mean,
    )
    @test rho_zero_one_unresolved_bias.upper <
        scorer_contract.maximum_abs_bias_upper
    @test sqrt(rho_zero_one_unresolved_mse.upper) <
        scorer_contract.maximum_rmse_upper
    no_unresolved_values = collect(range(-0.05, 0.05; length = 100))
    no_unresolved_endpoint = endpoint_mcse_helper(
        no_unresolved_values,
        100,
        -1.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    no_unresolved_mean = sum(no_unresolved_values) / 100
    no_unresolved_sd = sqrt(sum(
        (value - no_unresolved_mean)^2
        for value in no_unresolved_values
    ) / 99)
    @test isapprox(
        no_unresolved_endpoint.upper,
        abs(no_unresolved_mean) +
            scorer_contract.two_sided_normal_quantile *
            no_unresolved_sd / sqrt(100);
        atol = 1e-15,
        rtol = 0.0,
    )
    @test no_unresolved_endpoint.method ===
        :exact_rational_support_endpoint_enumeration_full_planned_denominator_mcse
    @test no_unresolved_endpoint.endpoint_configurations_evaluated == 1

    single_unresolved_endpoint = endpoint_mcse_helper(
        Float64[],
        1,
        -1.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    @test single_unresolved_endpoint.endpoint_configurations_evaluated == 2
    @test isinf(single_unresolved_endpoint.standard_error_at_maximum)
    @test isinf(single_unresolved_endpoint.upper)
    @test ismissing(single_unresolved_endpoint.objective_rational_upper)
    @test single_unresolved_endpoint.numerical_policy ===
        :single_planned_unit_mcse_is_infinite
    tiny_observation = Float64(2.0^-600)
    tiny_standard_error_squared = exact_rational_helper(tiny_observation)^2 /
        BigInt(4)
    @test Float64(tiny_standard_error_squared) == 0.0
    @test directed_rational_sqrt_helper(
        tiny_standard_error_squared,
        :up,
    ) == Float64(2.0^-601)
    @test directed_rational_sqrt_helper(
        tiny_standard_error_squared,
        :down,
    ) == Float64(2.0^-601)
    tiny_endpoint = endpoint_mcse_helper(
        Float64[0.0, tiny_observation],
        2,
        0.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :mean,
    )
    @test tiny_endpoint.standard_error_squared_exact ==
        (;
            numerator = string(numerator(tiny_standard_error_squared)),
            denominator = string(denominator(tiny_standard_error_squared)),
        )
    @test tiny_endpoint.standard_error_at_maximum == Float64(2.0^-601)
    @test_throws ArgumentError endpoint_mcse_helper(
        Float64[Inf],
        2,
        -1.0,
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    @test_throws ArgumentError endpoint_mcse_helper(
        Float64[],
        2,
        -1.0,
        1.0,
        NaN;
        objective = :absolute_mean,
    )

    cancellation_values = vcat(
        fill(1.0, 98),
        Float64[prevfloat(1.0)],
    )
    cancellation_endpoint = endpoint_mcse_helper(
        cancellation_values,
        100,
        prevfloat(1.0),
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    cancellation_oracle = _free_correlation_study_bigfloat_endpoint_oracle(
        cancellation_values,
        100,
        prevfloat(1.0),
        1.0,
        scorer_contract.two_sided_normal_quantile;
        objective = :absolute_mean,
    )
    @test BigFloat(cancellation_endpoint.upper) >= cancellation_oracle
    @test BigFloat(cancellation_endpoint.upper) - cancellation_oracle <=
        8 * BigFloat(eps(cancellation_endpoint.upper))
    cancellation_objective_upper = rational_from_record_helper(
        cancellation_endpoint.objective_rational_upper,
    )
    @test exact_rational_helper(cancellation_endpoint.upper) >=
        cancellation_objective_upper
    @test exact_rational_helper(prevfloat(cancellation_endpoint.upper)) <
        cancellation_objective_upper

    negative_symmetry_values = vcat(
        fill(-0.4, 97),
        Float64[-0.4000000000000001],
    )
    positive_symmetry_values = vcat(
        fill(0.4, 96),
        Float64[0.3999999999999999],
    )
    negative_symmetry_support = (-0.6, 0.4)
    positive_symmetry_support = (-0.4, 0.6)
    negative_symmetry_statistics = exact_statistics_record_helper(
        exact_statistics_helper(
            negative_symmetry_values,
            100,
            negative_symmetry_support...,
        ),
    )
    positive_symmetry_statistics = exact_statistics_record_helper(
        exact_statistics_helper(
            positive_symmetry_values,
            100,
            positive_symmetry_support...,
        ),
    )
    symmetry_endpoint = symmetry_endpoint_mcse_helper(
        negative_symmetry_statistics,
        positive_symmetry_statistics,
        scorer_contract.two_sided_normal_quantile,
    )
    symmetry_oracle = _free_correlation_study_bigfloat_symmetry_oracle(
        negative_symmetry_values,
        100,
        negative_symmetry_support,
        positive_symmetry_values,
        100,
        positive_symmetry_support,
        scorer_contract.two_sided_normal_quantile,
    )
    @test symmetry_endpoint.endpoint_configurations_evaluated == 12
    @test symmetry_endpoint.method ===
        :exact_rational_support_endpoint_enumeration_full_planned_denominator_independent_mcse
    @test BigFloat(symmetry_endpoint.upper) >= symmetry_oracle
    @test BigFloat(symmetry_endpoint.upper) - symmetry_oracle <=
        8 * BigFloat(eps(symmetry_endpoint.upper))
    symmetry_objective_upper = rational_from_record_helper(
        symmetry_endpoint.objective_rational_upper,
    )
    @test exact_rational_helper(symmetry_endpoint.upper) >=
        symmetry_objective_upper
    @test exact_rational_helper(prevfloat(symmetry_endpoint.upper)) <
        symmetry_objective_upper

    ledger0 = experimental.free_latent_correlation_2d_study_ledger(plan)
    @test ledger0.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_ledger.v2"
    @test ledger0.object ===
        :mgmfrm_free_latent_correlation_2d_study_ledger
    @test ledger0.status === :study_ledger_initialized
    @test ledger0.plan_id == plan.plan_id
    @test ledger0.plan_fingerprint == plan.plan_fingerprint
    @test isequal(ledger0.plan, plan)
    @test !ledger0.public_fit
    @test !ledger0.cache_enabled
    @test ledger0.promotion_effect === :none
    @test !ledger0.replicated_recovery_verified
    @test length(ledger0.unit_rows) == 525
    @test all(row -> ismissing(row.result) &&
        ismissing(row.application_index) &&
        ismissing(row.authorization_artifact) &&
        isempty(row.protocol_violations),
    ledger0.unit_rows)
    @test ledger0.summary.n_planned_units == 525
    @test ledger0.summary.n_results_recorded == 0
    @test ledger0.summary.n_pending_units == 525
    @test ledger0.summary.all_phase_planned_units == 525
    @test ledger0.summary.primary_evaluation_fixed_denominator == 500
    @test ledger0.summary.all_planned_units_retained
    @test !ledger0.summary.primary_attempts_overwritten
    @test ledger0.summary.execution_environment_identity_count == 0
    @test ledger0.summary.execution_environment_homogeneous
    @test ismissing(ledger0.summary.execution_environment_identity)
    @test !ledger0.summary.aggregate_ready
    @test !ledger0.summary.replicated_recovery_verified

    evaluation_ids_before = Tuple(unit.unit_id for unit in plan.units
        if unit.phase === :evaluation)
    evaluation_seeds_before = Tuple(unit.seeds for unit in plan.units
        if unit.phase === :evaluation)
    first_evaluation_unit = only(unit for unit in plan.units
        if unit.phase === :evaluation && unit.rho_truth == -0.6 &&
            unit.replication == 1)
    unauthorized_evaluation_result =
        _free_correlation_study_result(plan, first_evaluation_unit)
    unauthorized_ledger = experimental.
        free_latent_correlation_2d_study_apply_result(
            ledger0,
            unauthorized_evaluation_result,
        )
    unauthorized_row = only(row for row in unauthorized_ledger.unit_rows
        if row.unit.unit_id == first_evaluation_unit.unit_id)
    @test isequal(unauthorized_row.result, unauthorized_evaluation_result)
    @test ismissing(unauthorized_row.authorization_artifact)
    @test unauthorized_row.protocol_violations ==
        (:evaluation_result_without_valid_execution_authorization,)
    @test unauthorized_ledger.summary.n_protocol_violations == 1
    @test unauthorized_ledger.summary.all_phase_planned_units == 525
    @test unauthorized_ledger.summary.primary_evaluation_fixed_denominator ==
        500
    @test unauthorized_ledger.summary.all_planned_units_retained
    @test !unauthorized_ledger.summary.protocol_integrity_passed
    @test !unauthorized_ledger.summary.aggregate_ready

    feasibility_units = [unit for unit in plan.units
        if unit.phase === :feasibility]
    zero_feasibility_unit = only(unit for unit in feasibility_units
        if iszero(unit.rho_truth) && unit.replication == 1)
    failure_results = (
        _free_correlation_study_result(
            plan,
            feasibility_units[1];
            status = :generation_failed,
        ),
        _free_correlation_study_result(
            plan,
            feasibility_units[2];
            status = :fit_failed,
        ),
        _free_correlation_study_result(
            plan,
            feasibility_units[3];
            status = :diagnostic_failed,
        ),
        _free_correlation_study_result(
            plan,
            feasibility_units[4];
            status = :completed,
            covered = false,
        ),
        _free_correlation_study_result(
            plan,
            feasibility_units[5];
            status = :recovery_scoring_failed,
        ),
        _free_correlation_study_result(
            plan,
            zero_feasibility_unit;
            status = :completed,
        ),
    )
    ledger = foldl(
        (current, result) -> experimental.
            free_latent_correlation_2d_study_apply_result(current, result),
        failure_results;
        init = ledger0,
    )
    @test ledger.summary.n_planned_units == 525
    @test ledger.summary.all_phase_planned_units == 525
    @test ledger.summary.primary_evaluation_fixed_denominator == 500
    @test ledger.summary.n_results_recorded == 6
    @test ledger.summary.n_pending_units == 519
    @test ledger.summary.n_completed == 2
    @test ledger.summary.n_generation_failed == 1
    @test ledger.summary.n_fit_failed == 1
    @test ledger.summary.n_diagnostic_failed == 1
    @test ledger.summary.n_recovery_scoring_failed == 1
    @test ledger.summary.n_categorized_failures == 4
    @test ledger.summary.all_planned_units_retained
    @test !ledger.summary.aggregate_ready
    @test all(row -> ismissing(row.result), ledger0.unit_rows)
    @test count(row -> ismissing(row.result), ledger.unit_rows) == 519

    recorded = [row for row in ledger.unit_rows if !ismissing(row.result)]
    @test Set(row.result.primary_status for row in recorded) == Set((
        :completed,
        :generation_failed,
        :fit_failed,
        :diagnostic_failed,
        :recovery_scoring_failed,
    ))
    @test all(row -> row.result.evidence.content_sha256 ==
            row.result.execution_provenance.provenance_sha256,
        recorded)
    @test all(row -> row.result.execution_provenance.sample_bundle.status ===
            :available,
        (row for row in recorded if row.result.primary_status in (
            :completed,
            :diagnostic_failed,
            :recovery_scoring_failed,
        )))
    fit_failure = only(row for row in recorded
        if row.result.primary_status === :fit_failed)
    @test fit_failure.result.failure.error_type === :sampler_exception
    scoring_failure = only(row for row in recorded
        if row.result.primary_status === :recovery_scoring_failed)
    @test scoring_failure.result.failure.stage === :recovery_scoring
    @test scoring_failure.result.execution_quality.diagnostics_passed
    @test all(ismissing,
        values(scoring_failure.result.scientific_outcome))
    noncoverage = only(row for row in recorded
        if row.unit.unit_id == feasibility_units[4].unit_id)
    @test noncoverage.result.primary_status === :completed
    @test noncoverage.result.execution_quality.diagnostics_passed
    @test !noncoverage.result.scientific_outcome.interval_covered
    @test ledger.summary.n_diagnostic_failed == 1
    zero_result = only(row for row in recorded
        if row.unit.unit_id == zero_feasibility_unit.unit_id)
    @test zero_result.result.primary_status === :completed
    @test ismissing(
        zero_result.result.scientific_outcome.direction_matches_truth,
    )

    evaluation_ids_after = Tuple(row.unit.unit_id for row in ledger.unit_rows
        if row.unit.phase === :evaluation)
    evaluation_seeds_after = Tuple(row.unit.seeds for row in ledger.unit_rows
        if row.unit.phase === :evaluation)
    @test evaluation_ids_after == evaluation_ids_before
    @test evaluation_seeds_after == evaluation_seeds_before
    @test all(row -> ismissing(row.result),
        (row for row in ledger.unit_rows
            if row.unit.phase === :evaluation))

    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_apply_result(
            ledger,
            first(failure_results),
        )
    unknown_result = merge(first(failure_results), (;
        unit_id = "unknown-free-correlation-study-unit",
    ))
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_apply_result(ledger, unknown_result)

    clean_unit = feasibility_units[6]
    clean_result = _free_correlation_study_result(plan, clean_unit)
    provenance = clean_result.execution_provenance
    @test provenance.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_execution_provenance.v2"
    @test VersionNumber(provenance.runtime.julia_version) == VERSION
    @test provenance.runtime.n_threads == Threads.nthreads()
    @test provenance.runtime.os == string(Sys.KERNEL)
    @test provenance.runtime.arch == string(Sys.ARCH)
    @test provenance.environment.project.path == "Project.toml"
    @test provenance.environment.manifest.path ==
        (isfile(joinpath(dirname(Base.active_project()),
            "Manifest-v$(VERSION.major).$(VERSION.minor).toml")) ?
            "Manifest-v$(VERSION.major).$(VERSION.minor).toml" :
            "Manifest.toml")
    @test all(file -> occursin(r"^[0-9a-f]{64}$", file.sha256),
        values(provenance.environment))
    @test Tuple(row.path for row in provenance.sources) ==
        plan.unit_result_contract.source_paths
    @test all(row -> occursin(r"^[0-9a-f]{64}$", row.sha256),
        provenance.sources)
    repository_root = normpath(joinpath(dirname(pathof(BayesianMGMFRM)), ".."))
    @test all(row -> row.sha256 == bytes2hex(open(
            sha256,
            joinpath(repository_root, split(row.path, '/')...),
        )), provenance.sources)
    environment_identity_material = (;
        runtime = provenance.runtime,
        environment = provenance.environment,
        sources = provenance.sources,
    )
    @test provenance.execution_environment_sha256 ==
        artifact_content_hash(environment_identity_material)
    execution_binding = provenance.execution_binding
    @test execution_binding.plan_id == plan.plan_id
    @test execution_binding.plan_fingerprint == plan.plan_fingerprint
    @test execution_binding.unit_id == clean_unit.unit_id
    @test execution_binding.phase === clean_unit.phase
    @test execution_binding.rho_truth == clean_unit.rho_truth
    @test execution_binding.replication == clean_unit.replication
    @test execution_binding.seeds == clean_unit.seeds
    @test ismissing(execution_binding.authorization_decision_fingerprint)
    @test execution_binding.attempt == 1
    @test execution_binding.generation_evidence_sha256 ==
        artifact_content_hash(clean_result.generation_evidence)
    @test execution_binding.data_signature ==
        clean_result.generation_evidence.data_signature
    @test execution_binding.sampler_controls == experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            clean_unit.unit_id,
        ).pilot_kwargs
    @test propertynames(execution_binding.sampler_controls) ==
        plan.unit_result_contract.sampler_binding_fields
    sample_digest = provenance.sample_bundle
    @test sample_digest.status === :available
    @test ismissing(sample_digest.reason)
    @test sample_digest.sample_bundle_schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_sample_bundle.v1"
    @test Tuple(row.field for row in sample_digest.numeric_arrays) ==
        plan.unit_result_contract.sample_array_fields
    @test Tuple(row.field for row in sample_digest.structured_telemetry) ==
        plan.unit_result_contract.sample_telemetry_fields
    synthetic_bundle = _free_correlation_study_test_sample_bundle()
    draws_digest = only(row for row in sample_digest.numeric_arrays
        if row.field === :draws)
    @test draws_digest.byte_order ===
        (Base.ENDIAN_BOM == 0x04030201 ? :little_endian : :big_endian)
    @test draws_digest.storage_order === :julia_column_major
    draws_digest = draws_digest.digest
    @test propertynames(draws_digest) == (:eltype, :size, :nbytes, :sha256)
    @test draws_digest.eltype == string(eltype(synthetic_bundle.draws))
    @test draws_digest.size == size(synthetic_bundle.draws)
    @test draws_digest.nbytes ==
        sizeof(eltype(synthetic_bundle.draws)) * length(synthetic_bundle.draws)
    @test draws_digest.sha256 == bytes2hex(sha256(
        reinterpret(UInt8, vec(synthetic_bundle.draws)),
    ))
    sampler_stats_digest = only(row for row in
        sample_digest.structured_telemetry
        if row.field === :sampler_stats)
    @test sampler_stats_digest.sha256 ==
        artifact_content_hash(synthetic_bundle.sampler_stats)
    @test occursin(r"^[0-9a-f]{64}$", sample_digest.aggregate_sha256)
    @test execution_binding.sample_aggregate_sha256 ==
        sample_digest.aggregate_sha256
    @test clean_result.evidence.reference ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_recovery_pilot.v1"
    @test clean_result.evidence.content_sha256 ==
        provenance.provenance_sha256
    @test clean_result.evidence.reference !=
        clean_result.evidence.content_sha256

    generation_result = first(failure_results)
    @test generation_result.execution_provenance.sample_bundle.status ===
        :not_available
    @test generation_result.execution_provenance.sample_bundle.reason ===
        :generation_failed_before_fit
    @test generation_result.evidence.content_sha256 ==
        generation_result.execution_provenance.provenance_sha256
    @test ismissing(generation_result.execution_provenance.
        execution_binding.generation_evidence_sha256)
    @test ismissing(generation_result.execution_provenance.
        execution_binding.data_signature)
    @test ismissing(generation_result.execution_provenance.
        execution_binding.sample_aggregate_sha256)
    @test generation_result.execution_provenance.
        execution_environment_sha256 == provenance.execution_environment_sha256
    @test generation_result.execution_provenance.provenance_sha256 !=
        provenance.provenance_sha256
    fit_before_bundle = failure_results[2]
    @test fit_before_bundle.execution_provenance.sample_bundle.status ===
        :not_available
    @test fit_before_bundle.execution_provenance.sample_bundle.reason ===
        :fit_failed_before_sample_bundle_returned
    fit_after_bundle_unit = feasibility_units[7]
    fit_after_bundle = _free_correlation_study_result(
        plan,
        fit_after_bundle_unit;
        status = :fit_failed,
        sample_bundle_returned = true,
    )
    ledger_with_fit_after_bundle = experimental.
        free_latent_correlation_2d_study_apply_result(ledger, fit_after_bundle)
    fit_after_bundle_row = only(row for row in
        ledger_with_fit_after_bundle.unit_rows
        if row.unit.unit_id == fit_after_bundle_unit.unit_id)
    @test fit_after_bundle_row.result.execution_provenance.sample_bundle.status ===
        :available
    @test fit_after_bundle_row.result.evidence.content_sha256 ==
        fit_after_bundle_row.result.execution_provenance.provenance_sha256

    validator = getfield(
        BayesianMGMFRM,
        :_validate_free_correlation_study_unit_result,
    )
    completed_without_bundle = merge(clean_result, (;
        execution_provenance = fit_before_bundle.execution_provenance,
        evidence = (;
            source = :study_single_unit_executor,
            reference = clean_unit.unit_id,
            content_sha256 = fit_before_bundle.execution_provenance.
                provenance_sha256,
        ),
    ))
    @test_throws ArgumentError validator(
        completed_without_bundle,
        clean_unit,
        plan,
    )
    generation_with_bundle = merge(generation_result, (;
        execution_provenance = clean_result.execution_provenance,
        evidence = clean_result.evidence,
    ))
    @test_throws ArgumentError validator(
        generation_with_bundle,
        feasibility_units[1],
        plan,
    )
    fit_wrong_absence_reason = merge(fit_before_bundle, (;
        execution_provenance = generation_result.execution_provenance,
        evidence = (;
            source = :study_single_unit_executor,
            reference = feasibility_units[2].unit_id,
            content_sha256 = generation_result.execution_provenance.
                provenance_sha256,
        ),
    ))
    @test_throws ArgumentError validator(
        fit_wrong_absence_reason,
        feasibility_units[2],
        plan,
    )
    replay_target_unit = feasibility_units[8]
    replay_target = _free_correlation_study_result(plan, replay_target_unit)
    cross_unit_replay = merge(replay_target, (;
        execution_provenance = clean_result.execution_provenance,
        evidence = merge(replay_target.evidence, (;
            content_sha256 = clean_result.execution_provenance.
                provenance_sha256,
        )),
    ))
    @test_throws ArgumentError validator(
        cross_unit_replay,
        replay_target_unit,
        plan,
    )

    tampered_runtime = merge(provenance, (;
        runtime = merge(provenance.runtime, (;
            n_threads = provenance.runtime.n_threads + 1,
        )),
    ))
    tampered_source_rows = Base.setindex(
        provenance.sources,
        merge(first(provenance.sources), (; sha256 = repeat("0", 64))),
        1,
    )
    tampered_sources = merge(provenance, (; sources = tampered_source_rows))
    tampered_array_rows = Base.setindex(
        sample_digest.numeric_arrays,
        merge(first(sample_digest.numeric_arrays), (;
            digest = merge(first(sample_digest.numeric_arrays).digest,
                (; sha256 = repeat("0", 64))),
        )),
        1,
    )
    tampered_sample_array = merge(provenance, (;
        sample_bundle = merge(sample_digest, (;
            numeric_arrays = tampered_array_rows,
        )),
    ))
    tampered_telemetry_rows = Base.setindex(
        sample_digest.structured_telemetry,
        merge(first(sample_digest.structured_telemetry), (;
            sha256 = repeat("0", 64),
        )),
        1,
    )
    tampered_sample_telemetry = merge(provenance, (;
        sample_bundle = merge(sample_digest, (;
            structured_telemetry = tampered_telemetry_rows,
        )),
    ))
    tampered_byte_order_rows = Base.setindex(
        sample_digest.numeric_arrays,
        merge(first(sample_digest.numeric_arrays), (;
            byte_order = :middle_endian,
        )),
        1,
    )
    tampered_byte_order = merge(provenance, (;
        sample_bundle = merge(sample_digest, (;
            numeric_arrays = tampered_byte_order_rows,
        )),
    ))
    tampered_storage_order_rows = Base.setindex(
        sample_digest.numeric_arrays,
        merge(first(sample_digest.numeric_arrays), (;
            storage_order = :row_major,
        )),
        1,
    )
    tampered_storage_order = merge(provenance, (;
        sample_bundle = merge(sample_digest, (;
            numeric_arrays = tampered_storage_order_rows,
        )),
    ))
    tampered_results = (
        merge(clean_result, (; phase = :evaluation)),
        merge(clean_result, (; rho_truth = clean_result.rho_truth + 0.01)),
        merge(clean_result, (; replication = clean_result.replication + 1)),
        merge(clean_result, (;
            seeds = merge(clean_result.seeds, (;
                sampler_primary = clean_result.seeds.sampler_primary + 1,
            )),
        )),
        merge(clean_result, (; attempt = 2)),
        merge(clean_result, (; plan_fingerprint = "tampered")),
        merge(clean_result, (; recovery_claimed = true)),
        merge(clean_result, (; dry_run = true)),
        merge(clean_result, (; execution_provenance = tampered_runtime)),
        merge(clean_result, (; execution_provenance = tampered_sources)),
        merge(clean_result, (; execution_provenance = tampered_sample_array)),
        merge(clean_result, (;
            execution_provenance = tampered_sample_telemetry,
        )),
        merge(clean_result, (; execution_provenance = tampered_byte_order)),
        merge(clean_result, (; execution_provenance = tampered_storage_order)),
        merge(clean_result, (;
            evidence = merge(clean_result.evidence, (;
                content_sha256 = repeat("0", 64),
            )),
        )),
        merge(clean_result, (;
            execution_provenance = generation_result.execution_provenance,
            evidence = generation_result.evidence,
        )),
        merge(clean_result, (;
            execution_quality = merge(
                clean_result.execution_quality,
                (; diagnostics_passed = false),
            ),
        )),
        merge(clean_result, (;
            scientific_outcome = merge(
                clean_result.scientific_outcome,
                (; interval_covered = false),
            ),
        )),
    )
    for tampered in tampered_results
        @test_throws ArgumentError experimental.
            free_latent_correlation_2d_study_apply_result(ledger, tampered)
        @test ledger.summary.n_planned_units == 525
        @test ledger.summary.all_phase_planned_units == 525
        @test ledger.summary.primary_evaluation_fixed_denominator == 500
        @test ledger.summary.n_results_recorded == 6
    end
    nonfinite_completed_results = (
        merge(clean_result, (;
            scientific_outcome = merge(
                clean_result.scientific_outcome,
                (; posterior_median = NaN),
            ),
        )),
        merge(clean_result, (;
            scientific_outcome = merge(
                clean_result.scientific_outcome,
                (; truth_sign_probability = Inf),
            ),
        )),
    )
    for nonfinite_result in nonfinite_completed_results
        @test_throws ArgumentError experimental.
            free_latent_correlation_2d_study_apply_result(
                ledger,
                nonfinite_result,
            )
    end
    tampered_zero_direction = merge(
        _free_correlation_study_result(plan, zero_feasibility_unit),
        (;
            scientific_outcome = merge(
                _free_correlation_study_result(
                    plan,
                    zero_feasibility_unit,
                ).scientific_outcome,
                (; direction_matches_truth = false),
            ),
        ),
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_apply_result(
            ledger0,
            tampered_zero_direction,
        )

    duplicated_plan = merge(plan, (; units = (plan.units..., first(plan.units))))
    modified_rho_plan = merge(plan, (;
        rho_grid = (-0.6, 0.0, 0.6),
    ))
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_ledger(duplicated_plan)
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_ledger(modified_rho_plan)

    # Feasibility authorization is computation-only: radically different
    # coverage/direction outcomes with identical successful diagnostics must
    # produce the same frozen evaluation decision and preserve its roster.
    feasibility_covered = ledger0
    feasibility_adverse = ledger0
    for unit in feasibility_units
        covered_result = _free_correlation_study_result(plan, unit)
        adverse_result = iszero(unit.rho_truth) ? covered_result :
            _free_correlation_study_result(
                plan,
                unit;
                covered = false,
                posterior_median = -unit.rho_truth,
            )
        feasibility_covered = experimental.
            free_latent_correlation_2d_study_apply_result(
                feasibility_covered,
                covered_result,
            )
        feasibility_adverse = experimental.
            free_latent_correlation_2d_study_apply_result(
                feasibility_adverse,
                adverse_result,
            )
    end
    decision_covered = experimental.
        free_latent_correlation_2d_study_feasibility_decision(
            feasibility_covered,
        )
    decision_adverse = experimental.
        free_latent_correlation_2d_study_feasibility_decision(
            feasibility_adverse,
        )
    validate_feasibility_decision = getfield(
        BayesianMGMFRM,
        :_validate_free_correlation_study_feasibility_decision,
    )
    @test isequal(
        validate_feasibility_decision(decision_covered, plan),
        decision_covered,
    )
    @test decision_covered.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_feasibility_decision.v2"
    @test decision_covered.evaluation_execution_authorized
    @test decision_adverse.evaluation_execution_authorized
    @test decision_covered.computation_quality_only
    @test !decision_covered.recovery_outcomes_used
    @test !decision_covered.recovery_claimed
    @test decision_covered.scorer_implemented_validated_frozen
    @test isequal(
        decision_covered.feasibility_gate,
        decision_adverse.feasibility_gate,
    )
    @test decision_covered.evaluation_execution_authorized ===
        decision_adverse.evaluation_execution_authorized
    @test decision_covered.status === decision_adverse.status
    @test decision_covered.protocol_integrity_at_freeze ===
        decision_adverse.protocol_integrity_at_freeze
    @test decision_covered.protocol_integrity_evidence.passed
    @test decision_covered.protocol_integrity_evidence.
        n_protocol_violations_at_freeze == 0
    @test decision_covered.protocol_integrity_evidence.
        n_evaluation_results_recorded_at_freeze == 0
    @test decision_covered.protocol_integrity_evidence.
        execution_environment_identity_count == 1
    @test decision_covered.protocol_integrity_evidence.
        execution_environment_homogeneous
    @test decision_covered.protocol_integrity_evidence.
        execution_environment_identity ==
        feasibility_covered.summary.execution_environment_identity
    @test all(row -> row.execution_environment_sha256 ==
            decision_covered.protocol_integrity_evidence.
                execution_environment_identity,
        decision_covered.feasibility_result_rows)
    @test decision_covered.decision_basis_sha256 ==
        decision_adverse.decision_basis_sha256
    @test decision_covered.feasibility_result_rows !=
        decision_adverse.feasibility_result_rows
    @test decision_covered.feasibility_result_set_sha256 !=
        decision_adverse.feasibility_result_set_sha256
    @test decision_covered.decision_fingerprint !=
        decision_adverse.decision_fingerprint
    @test feasibility_covered.summary.all_phase_planned_units == 525
    @test feasibility_covered.summary.primary_evaluation_fixed_denominator ==
        500
    @test feasibility_covered.summary.execution_environment_identity_count == 1
    @test feasibility_covered.summary.execution_environment_homogeneous
    @test feasibility_covered.summary.execution_environment_identity ==
        _free_correlation_study_test_execution_environment().
            execution_environment_sha256
    @test feasibility_adverse.summary.all_phase_planned_units == 525
    @test feasibility_adverse.summary.primary_evaluation_fixed_denominator ==
        500
    @test Tuple(row.unit.unit_id for row in feasibility_adverse.unit_rows
        if row.unit.phase === :evaluation) == evaluation_ids_before

    mixed_environment_ledger = ledger0
    for (index, unit) in enumerate(feasibility_units)
        result = _free_correlation_study_result(plan, unit)
        if index == 1
            result = _free_correlation_study_with_distinct_execution_environment(
                result,
            )
        end
        mixed_environment_ledger = experimental.
            free_latent_correlation_2d_study_apply_result(
                mixed_environment_ledger,
                result,
            )
    end
    @test mixed_environment_ledger.summary.
        execution_environment_identity_count == 2
    @test !mixed_environment_ledger.summary.
        execution_environment_homogeneous
    @test ismissing(mixed_environment_ledger.summary.
        execution_environment_identity)
    @test mixed_environment_ledger.summary.feasibility_gate.passed
    @test !mixed_environment_ledger.summary.protocol_integrity_passed
    @test !mixed_environment_ledger.summary.aggregate_ready
    mixed_environment_decision = experimental.
        free_latent_correlation_2d_study_feasibility_decision(
            mixed_environment_ledger,
        )
    @test isequal(
        validate_feasibility_decision(mixed_environment_decision, plan),
        mixed_environment_decision,
    )
    @test !mixed_environment_decision.protocol_integrity_at_freeze
    @test !mixed_environment_decision.protocol_integrity_evidence.passed
    @test mixed_environment_decision.protocol_integrity_evidence.
        execution_environment_identity_count == 2
    @test !mixed_environment_decision.protocol_integrity_evidence.
        execution_environment_homogeneous
    @test ismissing(mixed_environment_decision.protocol_integrity_evidence.
        execution_environment_identity)
    @test !mixed_environment_decision.evaluation_execution_authorized
    @test mixed_environment_decision.status ===
        :evaluation_execution_not_authorized

    early_evaluation_ledger = unauthorized_ledger
    for unit in feasibility_units
        early_evaluation_ledger = experimental.
            free_latent_correlation_2d_study_apply_result(
                early_evaluation_ledger,
                _free_correlation_study_result(plan, unit),
            )
    end
    early_evaluation_decision = experimental.
        free_latent_correlation_2d_study_feasibility_decision(
            early_evaluation_ledger,
        )
    @test isequal(
        validate_feasibility_decision(early_evaluation_decision, plan),
        early_evaluation_decision,
    )
    @test early_evaluation_decision.feasibility_gate.passed
    @test early_evaluation_decision.protocol_integrity_evidence.
        n_protocol_violations_at_freeze == 1
    @test early_evaluation_decision.protocol_integrity_evidence.
        n_evaluation_results_recorded_at_freeze == 1
    @test !early_evaluation_decision.protocol_integrity_evidence.passed
    @test !early_evaluation_decision.protocol_integrity_at_freeze
    @test !early_evaluation_decision.evaluation_execution_authorized

    authorized_evaluation_result = _free_correlation_study_result(
        plan,
        first_evaluation_unit;
        authorization_decision_fingerprint =
            decision_covered.decision_fingerprint,
    )
    authorized_ledger = experimental.
        free_latent_correlation_2d_study_apply_result(
            feasibility_covered,
            authorized_evaluation_result;
            authorization = decision_covered,
        )
    authorized_row = only(row for row in authorized_ledger.unit_rows
        if row.unit.unit_id == first_evaluation_unit.unit_id)
    @test isequal(authorized_row.result, authorized_evaluation_result)
    @test authorized_row.authorization_artifact == decision_covered
    @test isempty(authorized_row.protocol_violations)
    @test authorized_ledger.summary.n_planned_units == 525
    @test authorized_ledger.summary.primary_evaluation_fixed_denominator == 500

    cross_ledger_authorization = experimental.
        free_latent_correlation_2d_study_apply_result(
            feasibility_adverse,
            authorized_evaluation_result;
            authorization = decision_covered,
        )
    cross_ledger_row = only(row for row in
        cross_ledger_authorization.unit_rows
        if row.unit.unit_id == first_evaluation_unit.unit_id)
    @test isequal(cross_ledger_row.result, authorized_evaluation_result)
    @test ismissing(cross_ledger_row.authorization_artifact)
    @test cross_ledger_row.protocol_violations ==
        (:evaluation_result_without_valid_execution_authorization,)
    @test cross_ledger_authorization.summary.n_protocol_violations == 1
    @test cross_ledger_authorization.summary.
        primary_evaluation_fixed_denominator == 500

    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_feasibility_decision(ledger0)

    # Any malformed ledger is rejected before another result can be applied;
    # the original fixed roster and denominator remain untouched.
    tampered_ledgers = (
        merge(ledger, (;
            summary = merge(ledger.summary, (; n_pending_units = 518)),
        )),
        merge(ledger, (; unit_rows = ledger.unit_rows[1:end-1])),
        merge(ledger, (;
            plan_fingerprint = "tampered-ledger-plan-fingerprint",
        )),
    )
    for tampered_ledger in tampered_ledgers
        @test_throws ArgumentError experimental.
            free_latent_correlation_2d_study_apply_result(
                tampered_ledger,
                clean_result,
            )
        @test ledger.summary.n_planned_units == 525
        @test ledger.summary.primary_evaluation_fixed_denominator == 500
        @test ledger.summary.n_results_recorded == 6
    end

    for result in failure_results
        retained = only(row for row in ledger.unit_rows
            if row.unit.unit_id == result.unit_id)
        @test isequal(retained.result, result)
        @test retained.application_index isa Int
    end
    pending_row = only(row for row in ledger.unit_rows
        if row.unit.unit_id == clean_unit.unit_id)
    @test ismissing(pending_row.result)
    @test ismissing(pending_row.application_index)
    @test ismissing(pending_row.authorization_artifact)
    @test isempty(pending_row.protocol_violations)

    initial_evaluation_cells = [row for row in ledger0.summary.phase_rho_rows
        if row.phase === :evaluation]
    @test length(initial_evaluation_cells) == 5
    @test all(row -> row.planned_denominator == 100,
        initial_evaluation_cells)
    @test sum(row.planned_denominator for row in initial_evaluation_cells) ==
        500
    @test all(row -> row.n_pending == 100,
        initial_evaluation_cells)

    # The default run-unit path is a pure preflight. It cannot generate data,
    # invoke MCMC, cache a fit, promote the candidate, or claim recovery.
    first_feasibility_unit = first(feasibility_units)
    preflight = experimental.free_latent_correlation_2d_study_unit_preflight(
        plan,
        first_feasibility_unit.unit_id,
    )
    @test preflight.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_unit_preflight.v2"
    @test preflight.object ===
        :mgmfrm_free_latent_correlation_2d_study_unit_preflight
    @test preflight.status ===
        :single_unit_preflight_passed_execution_blocked_by_operational_gate
    @test preflight.unit == first_feasibility_unit
    @test preflight.plan_id == plan.plan_id
    @test preflight.plan_fingerprint == plan.plan_fingerprint
    @test preflight.fixture_kwargs.n_persons == 300
    @test preflight.fixture_kwargs.items_per_dimension == 6
    @test preflight.fixture_kwargs.n_raters == 4
    @test preflight.fixture_kwargs.n_categories == 4
    @test preflight.fixture_kwargs.rho_truth == first_feasibility_unit.rho_truth
    @test preflight.fixture_kwargs.ability_seed ==
        first_feasibility_unit.seeds.ability
    @test preflight.fixture_kwargs.response_seed ==
        first_feasibility_unit.seeds.response
    @test preflight.fixture_kwargs.lkj_eta == 2
    @test preflight.fixture_kwargs.max_observations == 3_600
    @test preflight.fixture_kwargs.max_probability_cells == 14_400
    @test preflight.pilot_kwargs.chains == 4
    @test preflight.pilot_kwargs.warmup == 500
    @test preflight.pilot_kwargs.ndraws == 500
    @test preflight.pilot_kwargs.seed ==
        first_feasibility_unit.seeds.sampler_primary
    @test preflight.phase_gate == (;
        required = false,
        authorization_present = false,
        authorization_valid = true,
        protocol_execution_authorized = true,
        blockers = (),
    )
    @test preflight.resource_checks_scope ===
        :static_workload_shape_and_quarantine_caps_only
    @test propertynames(preflight.resource_checks) == (
        :observation_count_exact,
        :probability_cell_count_exact,
        :fixture_observation_cap_within_quarantine,
        :fixture_probability_cap_within_quarantine,
        :passed,
    )
    @test preflight.resource_checks.passed
    @test !preflight.runtime_resource_profile_included
    @test preflight.protocol_execution_authorized
    @test !preflight.operational_execution_authorized
    @test !preflight.execution_authorized
    @test preflight.operational_gate == (;
        initial_gradient_resource_probe = :pending,
        short_nuts_resource_profile = :pending,
        atomic_runner = :pending,
        operational_execution_authorized = false,
        blockers = (:resource_profile_and_atomic_runner_pending,),
    )
    @test preflight.blockers ==
        (:resource_profile_and_atomic_runner_pending,)
    @test !preflight.data_generated
    @test !preflight.mcmc_executed
    @test !preflight.recovery_evidence_available
    @test !preflight.public_fit
    @test !preflight.cache_enabled
    @test preflight.promotion_effect === :none
    @test preflight.result_contract.noncoverage_remains_completed
    @test preflight.result_contract.rho_zero_direction_is_missing
    @test !preflight.result_contract.raw_draws_allowed

    run_default = experimental.free_latent_correlation_2d_study_run_unit(
        plan,
        first_feasibility_unit.unit_id,
    )
    run_explicit_false = experimental.
        free_latent_correlation_2d_study_run_unit(
            plan,
            first_feasibility_unit.unit_id;
            execute_mcmc = false,
        )
    @test isequal(run_default, preflight)
    @test isequal(run_explicit_false, preflight)
    @test !run_default.data_generated
    @test !run_default.mcmc_executed
    blocked_execution_error = _free_correlation_study_capture_error(() ->
        experimental.free_latent_correlation_2d_study_run_unit(
            plan,
            first_feasibility_unit.unit_id;
            execute_mcmc = true,
        ))
    @test blocked_execution_error isa ArgumentError
    @test occursin(
        "preflight-only entry point",
        sprint(showerror, blocked_execution_error),
    )

    blocked_evaluation = experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            first_evaluation_unit.unit_id,
        )
    @test blocked_evaluation.status ===
        :single_unit_preflight_passed_execution_blocked_by_protocol_and_operational_gates
    @test blocked_evaluation.phase_gate.required
    @test !blocked_evaluation.phase_gate.authorization_present
    @test !blocked_evaluation.phase_gate.authorization_valid
    @test !blocked_evaluation.phase_gate.protocol_execution_authorized
    @test blocked_evaluation.phase_gate.blockers ==
        (:frozen_feasibility_authorization_missing_or_failed,)
    @test !blocked_evaluation.execution_authorized
    @test !blocked_evaluation.protocol_execution_authorized
    @test !blocked_evaluation.operational_execution_authorized
    @test blocked_evaluation.blockers == (
        :frozen_feasibility_authorization_missing_or_failed,
        :resource_profile_and_atomic_runner_pending,
    )
    @test !blocked_evaluation.data_generated
    @test !blocked_evaluation.mcmc_executed
    @test isequal(
        experimental.free_latent_correlation_2d_study_run_unit(
            plan,
            first_evaluation_unit.unit_id,
        ),
        blocked_evaluation,
    )

    authorized_preflight = experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            first_evaluation_unit.unit_id;
            authorization = decision_covered,
        )
    @test !authorized_preflight.execution_authorized
    @test authorized_preflight.protocol_execution_authorized
    @test !authorized_preflight.operational_execution_authorized
    @test authorized_preflight.phase_gate.required
    @test authorized_preflight.phase_gate.authorization_present
    @test authorized_preflight.phase_gate.authorization_valid
    @test authorized_preflight.phase_gate.protocol_execution_authorized
    @test isempty(authorized_preflight.phase_gate.blockers)
    @test authorized_preflight.blockers ==
        (:resource_profile_and_atomic_runner_pending,)
    @test !authorized_preflight.data_generated
    @test !authorized_preflight.mcmc_executed
    @test isequal(
        experimental.free_latent_correlation_2d_study_run_unit(
            plan,
            first_evaluation_unit.unit_id;
            execute_mcmc = false,
            authorization = decision_covered,
        ),
        authorized_preflight,
    )

    tampered_decision = merge(
        decision_covered,
        (; decision_fingerprint = "tampered-decision-fingerprint"),
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            first_evaluation_unit.unit_id;
            authorization = tampered_decision,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            first_feasibility_unit.unit_id;
            authorization = decision_covered,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_unit_preflight(
            plan,
            "unknown-free-correlation-study-unit",
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_unit_preflight(plan, :not_a_string)
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_unit_preflight(
            modified_rho_plan,
            first_feasibility_unit.unit_id,
        )

    # The resource probe is inert by default. The explicit path measures only
    # the initial ForwardDiff log-density-and-gradient and remains incapable of
    # authorizing or invoking MCMC.
    contract = experimental.free_latent_correlation_2d_contract()
    @test occursin(
        "free_latent_correlation_2d_study_resource_probe",
        contract.study_resource_probe_entrypoint,
    )
    @test contract.replicated_study_resource_probe_enabled
    @test !contract.
        replicated_study_resource_probe_default_executes_measurement
    @test !contract.replicated_study_resource_probe_executes_mcmc
    @test !contract.replicated_study_operational_execution_authorized

    probe_plan = experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            first_feasibility_unit.unit_id,
        )
    @test probe_plan.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_resource_probe.v1"
    @test probe_plan.object ===
        :mgmfrm_free_latent_correlation_2d_study_resource_probe
    @test probe_plan.status ===
        :resource_probe_planned_measurement_not_executed
    @test probe_plan.plan_id == plan.plan_id
    @test probe_plan.plan_fingerprint == plan.plan_fingerprint
    @test probe_plan.unit_id == first_feasibility_unit.unit_id
    @test probe_plan.phase === :feasibility
    @test !probe_plan.execute_measurement
    @test probe_plan.repetitions == 3
    @test probe_plan.policy.expected_raw_parameter_dimension == 655
    @test probe_plan.measurement_plan.operation ===
        :initial_logdensity_and_gradient
    @test probe_plan.measurement_plan.timed_evaluations == 3
    @test !probe_plan.measurement_plan.mcmc_allowed
    @test ismissing(probe_plan.runtime)
    @test ismissing(probe_plan.provenance)
    @test ismissing(probe_plan.measurement)
    @test !probe_plan.checks.measurement_completed
    @test !probe_plan.checks.all_thresholds_passed
    @test !probe_plan.profile_thresholds_passed
    @test !probe_plan.fixture_generated
    @test !probe_plan.gradient_executed
    @test !probe_plan.mcmc_executed
    @test !probe_plan.operational_execution_authorized
    @test !probe_plan.scientific_execution_authorized
    @test !probe_plan.recovery_evidence_available
    @test probe_plan.blockers == (
        :initial_gradient_resource_probe_not_measured,
        :resource_profile_and_atomic_runner_pending,
    )
    @test occursin(r"^[0-9a-f]{64}$", probe_plan.artifact_sha256)
    @test isequal(
        probe_plan,
        experimental.free_latent_correlation_2d_study_resource_probe(
            plan,
            first_feasibility_unit.unit_id,
        ),
    )

    validate_probe = getfield(
        BayesianMGMFRM,
        :_validate_free_correlation_study_resource_probe,
    )
    @test isequal(
        validate_probe(probe_plan, plan, first_feasibility_unit.unit_id),
        probe_plan,
    )
    @test_throws ArgumentError validate_probe(
        merge(probe_plan, (; artifact_sha256 = repeat("0", 64))),
        plan,
        first_feasibility_unit.unit_id,
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            first_feasibility_unit.unit_id;
            repetitions = 0,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            first_feasibility_unit.unit_id;
            repetitions = true,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            first_feasibility_unit.unit_id;
            repetitions = 6,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            first_evaluation_unit.unit_id,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_resource_probe(
            modified_rho_plan,
            first_feasibility_unit.unit_id,
        )

    measured_probe = experimental.
        free_latent_correlation_2d_study_resource_probe(
            plan,
            first_feasibility_unit.unit_id;
            execute_measurement = true,
            repetitions = 1,
        )
    @test measured_probe.execute_measurement
    @test measured_probe.repetitions == 1
    @test measured_probe.status in (
        :initial_gradient_profile_passed_operational_gate_still_blocked,
        :initial_gradient_profile_failed_operational_gate_blocked,
    )
    @test measured_probe.fixture_generated
    @test measured_probe.gradient_executed
    @test !measured_probe.mcmc_executed
    @test !measured_probe.operational_execution_authorized
    @test !measured_probe.scientific_execution_authorized
    @test !measured_probe.recovery_evidence_available
    @test measured_probe.checks.measurement_completed
    @test measured_probe.profile_thresholds_passed ===
        measured_probe.checks.all_thresholds_passed
    @test :resource_profile_and_atomic_runner_pending in
        measured_probe.blockers
    @test measured_probe.measurement.fixture.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_known_truth_fixture.v1"
    @test occursin(
        r"^[0-9a-f]{16}$",
        measured_probe.measurement.fixture.data_signature,
    )
    @test measured_probe.measurement.data_counts == (;
        n_observations = 3_600,
        n_probability_cells = 14_400,
    )
    gradient_profile = measured_probe.measurement.gradient_profile
    @test gradient_profile.initial_parameter_dimension == 655
    @test gradient_profile.adapter_validation_evaluations == 1
    @test gradient_profile.warmup_evaluations == 1
    @test gradient_profile.timed_evaluations == 1
    @test length(gradient_profile.timed_rows) == 1
    measured_row = only(gradient_profile.timed_rows)
    @test measured_row.repetition == 1
    @test isfinite(measured_row.elapsed_seconds)
    @test measured_row.elapsed_seconds >= 0
    @test measured_row.allocated_bytes >= 0
    @test isfinite(measured_row.gc_seconds)
    @test measured_row.gc_seconds >= 0
    @test measured_row.gradient_length == 655
    @test measured_row.gradient_finite
    @test isfinite(measured_row.logdensity)
    @test gradient_profile.median_gradient_seconds ==
        measured_row.elapsed_seconds
    @test gradient_profile.median_allocated_bytes ==
        measured_row.allocated_bytes
    @test gradient_profile.median_gc_time_fraction ==
        measured_row.gc_time_fraction
    @test measured_probe.checks.estimated_full_unit_seconds ==
        gradient_profile.median_gradient_seconds * 32 * 4_000
    @test measured_probe.runtime.julia_version == string(VERSION)
    @test measured_probe.runtime.n_threads == Threads.nthreads()
    @test measured_probe.runtime.minimum_free_memory_bytes_observed == min(
        measured_probe.runtime.free_memory_bytes_before,
        measured_probe.runtime.free_memory_bytes_after,
    )
    @test measured_probe.runtime.total_memory_bytes > 0
    @test measured_probe.provenance.sources_sha256 == artifact_content_hash(
        measured_probe.provenance.sources,
    )
    @test measured_probe.provenance.environment_sha256 ==
        artifact_content_hash(measured_probe.provenance.environment)
    @test Tuple(row.path for row in measured_probe.provenance.sources) ==
        plan.unit_result_contract.source_paths
    @test isequal(
        validate_probe(
            measured_probe,
            plan,
            first_feasibility_unit.unit_id,
        ),
        measured_probe,
    )

    tampered_fixture = merge(
        measured_probe.measurement.fixture,
        (; data_signature = "NOT-LOWER-16HEX"),
    )
    tampered_measurement = merge(
        measured_probe.measurement,
        (; fixture = tampered_fixture),
    )
    tampered_probe_material = merge(
        Base.structdiff(measured_probe, (; artifact_sha256 = nothing)),
        (; measurement = tampered_measurement),
    )
    tampered_signature_probe = merge(
        tampered_probe_material,
        (;
            artifact_sha256 =
                artifact_content_hash(tampered_probe_material),
        ),
    )
    @test_throws ArgumentError validate_probe(
        tampered_signature_probe,
        plan,
        first_feasibility_unit.unit_id,
    )

    # The actual fixture signature passes through the production generation-
    # evidence normalizer and can enter a synthetic terminal result without MCMC.
    measured_fixture = measured_probe.measurement.fixture
    actual_generation_evidence = (;
        fixture_schema = measured_fixture.schema,
        data_signature = measured_fixture.data_signature,
        realized_latent_correlation =
            measured_fixture.realized_latent_correlation,
        maximum_closed_form_oracle_error =
            measured_fixture.maximum_closed_form_oracle_error,
    )
    actual_signature_result = _free_correlation_study_result(
        plan,
        first_feasibility_unit;
        status = :fit_failed,
        generation_evidence_override = actual_generation_evidence,
    )
    actual_signature_ledger = experimental.
        free_latent_correlation_2d_study_apply_result(
            ledger0,
            actual_signature_result,
        )
    actual_signature_row = only(row for row in
        actual_signature_ledger.unit_rows
        if row.unit.unit_id == first_feasibility_unit.unit_id)
    @test actual_signature_row.result.generation_evidence.data_signature ==
        measured_fixture.data_signature
    @test actual_signature_row.result.execution_provenance.execution_binding.
        generation_evidence_sha256 ==
        artifact_content_hash(actual_generation_evidence)
    @test actual_signature_row.result.execution_provenance.execution_binding.
        data_signature == measured_fixture.data_signature
    @test actual_signature_row.result.evidence.content_sha256 ==
        actual_signature_row.result.execution_provenance.provenance_sha256
    invalid_signature_result = merge(
        actual_signature_result,
        (;
            generation_evidence = merge(
                actual_generation_evidence,
                (; data_signature = "ABCDEF0123456789"),
            ),
        ),
    )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_apply_result(
            ledger0,
            invalid_signature_result,
        )

    # A dry-run creates only a bounded deterministic feasibility fixture
    # subset. The frozen 525-unit plan and all 500 evaluation denominators are
    # retained unchanged, and no scientific sampler path is entered.
    dry_run = experimental.free_latent_correlation_2d_study_dry_run(
        plan;
        max_units = 2,
    )
    @test dry_run.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_dry_run.v2"
    @test dry_run.object ===
        :mgmfrm_free_latent_correlation_2d_study_dry_run
    @test dry_run.status === :bounded_feasibility_fixture_dry_run_passed
    @test dry_run.plan_id == plan.plan_id
    @test dry_run.plan_fingerprint == plan.plan_fingerprint
    @test dry_run.unit_roster_sha256 == plan.unit_roster_sha256
    @test dry_run.phase === :feasibility
    @test dry_run.n_planned_units == 525
    @test dry_run.planned_unit_ids == Tuple(unit_ids)
    @test dry_run.all_planned_units_retained
    @test dry_run.max_units_requested == 2
    @test dry_run.n_units == 2
    @test dry_run.total_observations == 7_200
    @test dry_run.total_probability_cells == 28_800
    @test Tuple(row.unit_id for row in dry_run.unit_rows) == (
        "mgmfrm_freecorr_feasibility_rho_m060_rep_001",
        "mgmfrm_freecorr_feasibility_rho_m030_rep_001",
    )
    @test all(row -> row.phase === :feasibility, dry_run.unit_rows)
    @test all(row -> row.replication == 1, dry_run.unit_rows)
    @test all(row -> row.fixture_generated, dry_run.unit_rows)
    @test all(row -> !row.mcmc_executed, dry_run.unit_rows)
    @test all(row -> !row.recovery_evidence_available, dry_run.unit_rows)
    @test all(row -> row.maximum_closed_form_oracle_error <= 1e-12,
        dry_run.unit_rows)
    @test dry_run.fixture_generation_executed
    @test !dry_run.mcmc_executed
    @test dry_run.dry_run
    @test !dry_run.dry_run_is_recovery_evidence
    @test !dry_run.recovery_evidence_available
    @test !dry_run.public_fit
    @test !dry_run.cache_enabled
    @test dry_run.promotion_effect === :none
    @test dry_run.summary.passed
    @test dry_run.summary.planned_units_retained == 525
    @test dry_run.summary.evaluation_units_materialized == 0
    @test dry_run.summary.mcmc_units_executed == 0
    @test dry_run.summary.next_gate ===
        :fixed_unit_initial_gradient_resource_probe
    @test isequal(plan, replay)
    @test length(plan.units) == 525
    @test Tuple(unit.unit_id for unit in plan.units
        if unit.phase === :evaluation) == evaluation_ids_before
    @test Tuple(unit.seeds for unit in plan.units
        if unit.phase === :evaluation) == evaluation_seeds_before
    @test ledger0.summary.n_pending_units == 525
    @test ledger0.summary.primary_evaluation_fixed_denominator == 500

    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_dry_run(plan; max_units = 0)
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_dry_run(plan; max_units = true)
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_dry_run(
            plan;
            max_units = plan.resource_policy.dry_run_hard_max_units + 1,
        )
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_dry_run(modified_rho_plan)

    # The frozen scorer blocks cleanly until every authorized evaluation unit
    # is terminal. A blocked score is still deterministic and nonpromoting.
    blocked_score = experimental.free_latent_correlation_2d_study_score(ledger0)
    @test blocked_score.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_score.v2"
    @test blocked_score.object ===
        :mgmfrm_free_latent_correlation_2d_study_score
    @test blocked_score.status === :evaluation_scoring_blocked
    @test !blocked_score.evaluated
    @test blocked_score.decision === :inconclusive_not_passed
    @test !blocked_score.passed
    @test :feasibility_decision_not_available in
        Set(row.code for row in blocked_score.blockers)
    @test :evaluation_units_not_all_terminal in
        Set(row.code for row in blocked_score.blockers)
    @test !blocked_score.aggregate.ready
    @test isempty(blocked_score.aggregate.per_rho_rows)
    @test ismissing(blocked_score.aggregate.overall)
    @test !blocked_score.public_fit
    @test !blocked_score.fit_ready
    @test !blocked_score.cache_enabled
    @test blocked_score.promotion_effect === :none
    @test !blocked_score.recovery_claimed
    @test !blocked_score.replicated_recovery_verified
    @test isequal(
        blocked_score,
        experimental.free_latent_correlation_2d_study_score(ledger0),
    )

    all_pass_ledger = _free_correlation_study_materialize_evaluation(
        feasibility_covered,
        decision_covered,
        unit -> _free_correlation_study_result(
            plan,
            unit;
            authorization_decision_fingerprint =
                decision_covered.decision_fingerprint,
        ),
    )
    @test all_pass_ledger.status === :study_units_recorded_pending_scoring
    @test all_pass_ledger.summary.n_planned_units == 525
    @test all_pass_ledger.summary.n_results_recorded == 525
    @test all_pass_ledger.summary.n_pending_units == 0
    @test all_pass_ledger.summary.n_completed == 525
    @test all_pass_ledger.summary.primary_evaluation_fixed_denominator == 500
    @test all_pass_ledger.summary.evaluation_all_terminal
    @test all_pass_ledger.summary.protocol_integrity_passed
    @test all_pass_ledger.summary.scorer_implemented_validated_frozen
    @test all_pass_ledger.summary.aggregate_ready

    all_pass_score = experimental.free_latent_correlation_2d_study_score(
        all_pass_ledger,
    )
    @test all_pass_score.status === :evaluation_scoring_passed
    @test all_pass_score.evaluated
    @test all_pass_score.decision === :passed
    @test all_pass_score.passed
    @test isempty(all_pass_score.blockers)
    @test isempty(all_pass_score.hard_failure_rows)
    @test isempty(all_pass_score.uncertainty_blocker_rows)
    @test all_pass_score.aggregate.ready
    @test all_pass_score.aggregate.schema ==
        "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_evaluation_aggregate.v2"
    @test length(all_pass_score.aggregate.per_rho_rows) == 5
    @test all(row -> row.n_planned == 100 && row.n_terminal == 100 &&
        row.n_scientifically_scored == 100 &&
        row.coverage.n_successes == 100 &&
        row.coverage.joint_fixed_denominator_wilson.trials == 100,
    all_pass_score.aggregate.per_rho_rows)
    @test all(row -> iszero(row.mean_bias) &&
        iszero(row.root_mean_squared_error),
    all_pass_score.aggregate.per_rho_rows)
    all_pass_zero_row = only(row for row in
        all_pass_score.aggregate.per_rho_rows if iszero(row.rho_truth))
    @test !all_pass_zero_row.direction_applicable
    @test ismissing(all_pass_zero_row.direction)
    @test all_pass_zero_row.rho_zero_false_exclusion.n_planned == 100
    @test all_pass_zero_row.rho_zero_false_exclusion.n_successes == 0
    @test all_pass_score.aggregate.overall.coverage.n_planned == 500
    @test all_pass_score.aggregate.overall.coverage.n_successes == 500
    @test all_pass_score.aggregate.overall.direction_nonzero_rho.n_planned ==
        400
    @test all_pass_score.aggregate.overall.direction_nonzero_rho.n_successes ==
        400
    @test !all_pass_score.public_fit
    @test !all_pass_score.fit_ready
    @test !all_pass_score.cache_enabled
    @test all_pass_score.promotion_effect === :none
    @test !all_pass_score.recovery_claimed
    @test !all_pass_score.replicated_recovery_verified

    decision_rows_helper = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_decision_rows,
    )
    replace_rho_row = function (aggregate, replacement)
        index = only(index for (index, row) in
            pairs(aggregate.per_rho_rows)
            if row.rho_truth == replacement.rho_truth)
        return merge(aggregate, (;
            per_rho_rows = Base.setindex(
                aggregate.per_rho_rows,
                replacement,
                index,
            ),
        ))
    end
    zero_base_row = only(row for row in
        all_pass_score.aggregate.per_rho_rows if iszero(row.rho_truth))
    crossing_continuous_row = merge(zero_base_row, (;
        n_valid = 99,
        n_diagnostically_valid = 99,
        n_scientifically_scored = 99,
        n_scientifically_unresolved = 1,
        absolute_mean_bias = 0.15,
        root_mean_squared_error = 0.25,
        continuous_unresolved_bounds = merge(
            zero_base_row.continuous_unresolved_bounds,
            (;
                bias = (; lower = -0.05, upper = 0.20),
                root_mean_squared_error =
                    (; lower = 0.15, upper = 0.30),
            ),
        ),
        continuous_unresolved_worst_case = merge(
            zero_base_row.continuous_unresolved_worst_case,
            (;
                minimum_absolute_mean_bias = 0.0,
                absolute_mean_bias_envelope_plus_mcse_upper = 0.20,
                root_mean_squared_error_envelope_plus_mcse_upper = 0.30,
            ),
        ),
    ))
    crossing_continuous_decisions = decision_rows_helper(
        replace_rho_row(
            all_pass_score.aggregate,
            crossing_continuous_row,
        ),
    )
    crossing_continuous_hard_codes = Set(row.code for row in
        crossing_continuous_decisions.hard_failure_rows)
    crossing_continuous_uncertainty_codes = Set(row.code for row in
        crossing_continuous_decisions.uncertainty_blocker_rows)
    @test :absolute_mean_bias_exceeds_limit ∉
        crossing_continuous_hard_codes
    @test :rmse_exceeds_limit ∉ crossing_continuous_hard_codes
    @test :absolute_mean_bias_unresolved_envelope_crosses_limit in
        crossing_continuous_uncertainty_codes
    @test :rmse_unresolved_envelope_crosses_limit in
        crossing_continuous_uncertainty_codes

    hard_continuous_row = merge(crossing_continuous_row, (;
        continuous_unresolved_bounds = merge(
            crossing_continuous_row.continuous_unresolved_bounds,
            (;
                bias = (; lower = 0.11, upper = 0.20),
                root_mean_squared_error =
                    (; lower = 0.21, upper = 0.30),
            ),
        ),
        continuous_unresolved_worst_case = merge(
            crossing_continuous_row.continuous_unresolved_worst_case,
            (; minimum_absolute_mean_bias = 0.11),
        ),
    ))
    hard_continuous_decisions = decision_rows_helper(
        replace_rho_row(all_pass_score.aggregate, hard_continuous_row),
    )
    hard_continuous_codes = Set(row.code for row in
        hard_continuous_decisions.hard_failure_rows)
    @test :absolute_mean_bias_unresolved_envelope_lower_exceeds_limit in
        hard_continuous_codes
    @test :rmse_unresolved_envelope_lower_exceeds_limit in
        hard_continuous_codes

    base_symmetry_row = first(
        all_pass_score.aggregate.unpaired_symmetry_rows,
    )
    crossing_symmetry_row = merge(base_symmetry_row, (;
        absolute_signed_bias_contrast = 0.15,
        n_scientifically_unresolved = 1,
        signed_bias_contrast_unresolved_bounds =
            (; lower = -0.05, upper = 0.20),
        minimum_absolute_signed_bias_contrast = 0.0,
        absolute_signed_bias_contrast_unresolved_plus_mcse_upper = 0.20,
    ))
    crossing_symmetry_aggregate = merge(all_pass_score.aggregate, (;
        unpaired_symmetry_rows = Base.setindex(
            all_pass_score.aggregate.unpaired_symmetry_rows,
            crossing_symmetry_row,
            1,
        ),
    ))
    crossing_symmetry_decisions =
        decision_rows_helper(crossing_symmetry_aggregate)
    crossing_symmetry_hard_codes = Set(row.code for row in
        crossing_symmetry_decisions.hard_failure_rows)
    crossing_symmetry_uncertainty_codes = Set(row.code for row in
        crossing_symmetry_decisions.uncertainty_blocker_rows)
    @test :unpaired_bias_symmetry_contrast_exceeds_limit ∉
        crossing_symmetry_hard_codes
    @test :unpaired_bias_symmetry_unresolved_envelope_crosses_limit in
        crossing_symmetry_uncertainty_codes
    hard_symmetry_row = merge(crossing_symmetry_row, (;
        signed_bias_contrast_unresolved_bounds =
            (; lower = 0.11, upper = 0.20),
        minimum_absolute_signed_bias_contrast = 0.11,
    ))
    hard_symmetry_decisions = decision_rows_helper(
        merge(all_pass_score.aggregate, (;
            unpaired_symmetry_rows = Base.setindex(
                all_pass_score.aggregate.unpaired_symmetry_rows,
                hard_symmetry_row,
                1,
            ),
        )),
    )
    @test :unpaired_bias_symmetry_unresolved_envelope_lower_exceeds_limit in
        Set(row.code for row in hard_symmetry_decisions.hard_failure_rows)

    false_exclusion_decisions = function (lower, upper)
        false_exclusion = merge(
            zero_base_row.rho_zero_false_exclusion,
            (;
                n_unresolved = 5,
                unresolved_bounds = merge(
                    zero_base_row.rho_zero_false_exclusion.unresolved_bounds,
                    (; lower, upper),
                ),
                unresolved_false_exclusion_upper = upper,
            ),
        )
        replacement = merge(zero_base_row, (;
            rho_zero_false_exclusion = false_exclusion,
        ))
        return decision_rows_helper(
            replace_rho_row(all_pass_score.aggregate, replacement),
        )
    end
    false_exclusion_pass = false_exclusion_decisions(0.10, 0.20)
    false_exclusion_crossing = false_exclusion_decisions(0.20, 0.25)
    false_exclusion_hard = false_exclusion_decisions(0.21, 0.25)
    false_exclusion_code =
        :rho_zero_false_exclusion_unresolved_upper_crosses_limit
    false_exclusion_hard_code =
        :rho_zero_false_exclusion_observed_lower_exceeds_limit
    @test false_exclusion_code ∉ Set(row.code for row in
        false_exclusion_pass.uncertainty_blocker_rows)
    @test false_exclusion_hard_code ∉ Set(row.code for row in
        false_exclusion_pass.hard_failure_rows)
    @test false_exclusion_code in Set(row.code for row in
        false_exclusion_crossing.uncertainty_blocker_rows)
    @test false_exclusion_hard_code ∉ Set(row.code for row in
        false_exclusion_crossing.hard_failure_rows)
    @test false_exclusion_hard_code in Set(row.code for row in
        false_exclusion_hard.hard_failure_rows)

    insufficient_diagnostic_row = merge(zero_base_row, (;
        n_diagnostically_valid = 94,
    ))
    insufficient_diagnostic_decisions = decision_rows_helper(
        replace_rho_row(
            all_pass_score.aggregate,
            insufficient_diagnostic_row,
        ),
    )
    @test :insufficient_diagnostically_valid_units in Set(
        row.code for row in insufficient_diagnostic_decisions.hard_failure_rows
    )

    all_failure_rho = -0.6
    all_failure_unit_rows = Tuple(begin
        if row.unit.phase === :evaluation &&
                row.unit.rho_truth == all_failure_rho
            failed_result = _free_correlation_study_result(
                plan,
                row.unit;
                status = :fit_failed,
                authorization_decision_fingerprint =
                    decision_covered.decision_fingerprint,
            )
            merge(row, (; result = failed_result))
        else
            row
        end
    end for row in all_pass_ledger.unit_rows)
    summarize_ledger = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_ledger_summary,
    )
    ledger_status = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_ledger_status,
    )
    all_failure_summary = summarize_ledger(all_failure_unit_rows, plan)
    all_failure_ledger = merge(all_pass_ledger, (;
        status = ledger_status(all_failure_summary),
        unit_rows = all_failure_unit_rows,
        summary = all_failure_summary,
    ))
    all_failure_score = experimental.free_latent_correlation_2d_study_score(
        all_failure_ledger,
    )
    @test all_failure_score.evaluated
    @test all_failure_score.decision === :failed
    @test all_failure_score.status === :evaluation_scoring_failed
    all_failure_hard_codes = Set(row.code for row in
        all_failure_score.hard_failure_rows)
    @test :insufficient_diagnostically_valid_units in
        all_failure_hard_codes
    @test :insufficient_scientifically_scored_units in
        all_failure_hard_codes
    all_failure_row = only(row for row in
        all_failure_score.aggregate.per_rho_rows
        if row.rho_truth == all_failure_rho)
    @test all_failure_row.n_scientifically_scored == 0
    @test all_failure_row.n_scientifically_unresolved == 100
    @test isfinite(all_failure_row.continuous_unresolved_worst_case.
        absolute_mean_bias_envelope_plus_mcse_upper)
    @test isfinite(all_failure_row.continuous_unresolved_worst_case.
        root_mean_squared_error_envelope_plus_mcse_upper)
    all_failure_symmetry_row = only(row for row in
        all_failure_score.aggregate.unpaired_symmetry_rows
        if all_failure_rho in row.rho_pair)
    @test isfinite(all_failure_symmetry_row.
        absolute_signed_bias_contrast_unresolved_plus_mcse_upper)
    @test isfinite(all_failure_symmetry_row.
        endpoint_imputed_full_denominator_mcse.upper)

    biased_unit_rows = Tuple(begin
        if row.unit.phase === :evaluation && row.unit.rho_truth == 0.6
            biased_result = _free_correlation_study_result(
                plan,
                row.unit;
                covered = false,
                posterior_median = 0.9,
                authorization_decision_fingerprint =
                    decision_covered.decision_fingerprint,
            )
            merge(row, (; result = biased_result))
        else
            row
        end
    end for row in all_pass_ledger.unit_rows)
    biased_summary = getfield(
        BayesianMGMFRM,
        :_free_correlation_study_ledger_summary,
    )(biased_unit_rows, plan)
    biased_ledger = merge(all_pass_ledger, (;
        status = getfield(
            BayesianMGMFRM,
            :_free_correlation_study_ledger_status,
        )(biased_summary),
        unit_rows = biased_unit_rows,
        summary = biased_summary,
    ))
    @test biased_ledger.summary.n_results_recorded == 525
    @test biased_ledger.summary.n_completed == 525
    @test biased_ledger.summary.primary_evaluation_fixed_denominator == 500
    biased_score = experimental.free_latent_correlation_2d_study_score(
        biased_ledger,
    )
    @test biased_score.evaluated
    @test biased_score.status === :evaluation_scoring_failed
    @test biased_score.decision === :failed
    @test !biased_score.passed
    biased_hard_codes = Set(row.code for row in biased_score.hard_failure_rows)
    @test :absolute_mean_bias_exceeds_limit in biased_hard_codes
    @test :rmse_exceeds_limit in biased_hard_codes
    @test :unpaired_bias_symmetry_contrast_exceeds_limit in biased_hard_codes
    @test !biased_score.recovery_claimed
    @test !biased_score.replicated_recovery_verified
    @test !biased_score.public_fit
    @test biased_score.promotion_effect === :none

    # Every categorized failure remains in the 100-per-rho denominator. The
    # completed interval miss at rho=.6 remains completed, not diagnostic_failed.
    failure_ledger = _free_correlation_study_materialize_evaluation(
        feasibility_covered,
        decision_covered,
        unit -> begin
            status = if unit.replication != 1
                :completed
            elseif unit.rho_truth == -0.6
                :generation_failed
            elseif unit.rho_truth == -0.3
                :fit_failed
            elseif iszero(unit.rho_truth)
                :diagnostic_failed
            elseif unit.rho_truth == 0.3
                :recovery_scoring_failed
            else
                :completed
            end
            noncoverage = unit.rho_truth == 0.6 && unit.replication == 1
            _free_correlation_study_result(
                plan,
                unit;
                status,
                covered = !noncoverage,
                posterior_median = noncoverage ?
                    unit.rho_truth + 0.06 : unit.rho_truth,
                authorization_decision_fingerprint =
                    decision_covered.decision_fingerprint,
            )
        end,
    )
    @test failure_ledger.summary.n_results_recorded == 525
    @test failure_ledger.summary.n_pending_units == 0
    @test failure_ledger.summary.n_generation_failed == 1
    @test failure_ledger.summary.n_fit_failed == 1
    @test failure_ledger.summary.n_diagnostic_failed == 1
    @test failure_ledger.summary.n_recovery_scoring_failed == 1
    @test failure_ledger.summary.n_categorized_failures == 4
    @test failure_ledger.summary.primary_evaluation_fixed_denominator == 500
    completed_noncoverage_row = only(row for row in failure_ledger.unit_rows
        if row.unit.phase === :evaluation && row.unit.rho_truth == 0.6 &&
            row.unit.replication == 1)
    @test completed_noncoverage_row.result.primary_status === :completed
    @test completed_noncoverage_row.result.execution_quality.diagnostics_passed
    @test !completed_noncoverage_row.result.scientific_outcome.interval_covered

    failure_score = experimental.free_latent_correlation_2d_study_score(
        failure_ledger,
    )
    @test failure_score.evaluated
    @test failure_score.decision === :inconclusive_not_passed
    @test failure_score.status ===
        :evaluation_scoring_inconclusive_not_passed
    @test isempty(failure_score.hard_failure_rows)
    @test :rmse_unresolved_envelope_crosses_limit in Set(
        row.code for row in failure_score.uncertainty_blocker_rows
    )
    @test failure_score.aggregate.overall.coverage.n_planned == 500
    @test failure_score.aggregate.overall.coverage.n_valid == 496
    @test failure_score.aggregate.overall.coverage.n_unresolved == 4
    @test failure_score.aggregate.overall.coverage.n_successes == 495
    @test failure_score.aggregate.overall.direction_nonzero_rho.n_planned == 400
    failure_rows = failure_score.aggregate.per_rho_rows
    @test all(row -> row.n_planned == 100 && row.n_terminal == 100,
        failure_rows)
    negative_high_failure_row = only(row for row in failure_rows
        if row.rho_truth == -0.6)
    negative_low_failure_row = only(row for row in failure_rows
        if row.rho_truth == -0.3)
    @test negative_high_failure_row.n_generation_failed == 1
    @test negative_low_failure_row.n_fit_failed == 1
    failure_zero_row = only(row for row in failure_rows
        if iszero(row.rho_truth))
    @test failure_zero_row.n_diagnostic_failed == 1
    @test !failure_zero_row.direction_applicable
    @test ismissing(failure_zero_row.direction)
    @test failure_zero_row.rho_zero_false_exclusion.n_planned == 100
    @test failure_zero_row.rho_zero_false_exclusion.n_unresolved == 1
    @test failure_zero_row.rho_zero_false_exclusion.
        unresolved_false_exclusion_upper == 0.01
    positive_low_failure_row = only(row for row in failure_rows
        if row.rho_truth == 0.3)
    @test positive_low_failure_row.n_recovery_scoring_failed == 1
    positive_high_row = only(row for row in failure_rows
        if row.rho_truth == 0.6)
    @test positive_high_row.n_valid == 100
    @test positive_high_row.coverage.n_successes == 99
    @test positive_high_row.coverage.joint_fixed_denominator_rate == 0.99

    for row in failure_rows
        bounds = row.continuous_unresolved_bounds
        for interval in (
                bounds.bias,
                bounds.mean_absolute_error,
                bounds.mean_squared_error,
                bounds.root_mean_squared_error)
            @test isfinite(interval.lower)
            @test isfinite(interval.upper)
            @test interval.lower <= interval.upper
        end
        combined = row.continuous_unresolved_worst_case
        @test combined.method ===
            :endpoint_enumerated_full_planned_denominator_mcse_with_exact_rational_arithmetic
        @test !combined.guard_uses_conditional_completion_pattern_mcse
        @test !combined.conditional_on_realized_completion_pattern.
            used_for_guard
        @test isfinite(combined.completed_fraction)
        @test isfinite(combined.fixed_denominator_bias_mcse)
        @test isfinite(
            combined.fixed_denominator_mean_squared_error_mcse,
        )
        @test isfinite(combined.absolute_mean_bias_upper)
        @test isfinite(
            combined.absolute_mean_bias_envelope_plus_mcse_upper,
        )
        @test isfinite(combined.root_mean_squared_error_upper)
        @test isfinite(
            combined.root_mean_squared_error_envelope_plus_mcse_upper,
        )
        @test combined.absolute_mean_bias_upper <=
            combined.absolute_mean_bias_envelope_plus_mcse_upper
        @test combined.root_mean_squared_error_upper <=
            combined.root_mean_squared_error_envelope_plus_mcse_upper
        if row.n_scientifically_unresolved > 0
            @test row.endpoint_mcse_sufficient_statistics.schema ===
                :exact_float64_rational_sufficient_statistics_v1
            @test row.endpoint_mcse_sufficient_statistics.observed_sum.
                numerator isa String
            @test row.endpoint_mcse_sufficient_statistics.observed_sum.
                denominator isa String
            @test combined.absolute_mean_bias_envelope_plus_mcse_upper <=
                scorer_contract.maximum_abs_bias_upper
            @test combined.root_mean_squared_error_upper <=
                scorer_contract.maximum_rmse_upper
            @test combined.bias_endpoint_enumeration.
                endpoint_configurations_evaluated ==
                row.n_scientifically_unresolved + 1
            @test combined.mean_squared_error_endpoint_enumeration.
                endpoint_configurations_evaluated ==
                row.n_scientifically_unresolved + 1
        end
    end
    for row in failure_score.aggregate.unpaired_symmetry_rows
        bounds = row.signed_bias_contrast_unresolved_bounds
        @test isfinite(bounds.lower)
        @test isfinite(bounds.upper)
        @test bounds.lower <= bounds.upper
        @test isfinite(row.absolute_signed_bias_contrast_unresolved_upper)
        @test isfinite(
            row.fixed_denominator_independent_bias_standard_error,
        )
        @test isfinite(
            row.absolute_signed_bias_contrast_unresolved_plus_mcse_upper,
        )
        @test row.absolute_signed_bias_contrast_unresolved_upper <=
            row.absolute_signed_bias_contrast_unresolved_plus_mcse_upper
        @test row.endpoint_imputed_full_denominator_mcse.
            endpoint_configurations_evaluated ==
            (row.n_scientifically_unresolved == 1 ? 2 : 4)
        @test row.endpoint_imputed_full_denominator_mcse.method ===
            :exact_rational_support_endpoint_enumeration_full_planned_denominator_independent_mcse
        @test row.signed_bias_contrast_bounds_numerical_policy ===
            :exact_rational_bounds_then_directed_float64_conversion
        @test row.signed_bias_contrast_unresolved_bounds_exact.lower.
            numerator isa String
        @test row.signed_bias_contrast_unresolved_bounds_exact.upper.
            denominator isa String
    end

    one_unresolved_per_rho_ledger =
        _free_correlation_study_materialize_evaluation(
            feasibility_covered,
            decision_covered,
            unit -> _free_correlation_study_result(
                plan,
                unit;
                status = unit.replication == 1 ? :fit_failed : :completed,
                authorization_decision_fingerprint =
                    decision_covered.decision_fingerprint,
            ),
        )
    one_unresolved_per_rho_score = experimental.
        free_latent_correlation_2d_study_score(
            one_unresolved_per_rho_ledger,
        )
    @test one_unresolved_per_rho_score.evaluated
    @test one_unresolved_per_rho_score.decision ===
        :inconclusive_not_passed
    @test isempty(one_unresolved_per_rho_score.hard_failure_rows)
    one_unresolved_rows =
        one_unresolved_per_rho_score.aggregate.per_rho_rows
    @test all(row -> row.n_valid == 99 &&
            row.n_scientifically_unresolved == 1 &&
            row.n_fit_failed == 1,
        one_unresolved_rows)
    one_unresolved_rmse_blockers = [row for row in
        one_unresolved_per_rho_score.uncertainty_blocker_rows
        if row.code === :rmse_unresolved_envelope_crosses_limit]
    @test issubset(
        Set((-0.6, 0.6)),
        Set(row.coordinate for row in one_unresolved_rmse_blockers),
    )
    @test all(row -> row.continuous_unresolved_worst_case.
            mean_squared_error_endpoint_enumeration.
                endpoint_configurations_evaluated == 2,
        one_unresolved_rows)

    five_unresolved_per_rho_ledger =
        _free_correlation_study_materialize_evaluation(
            feasibility_covered,
            decision_covered,
            unit -> _free_correlation_study_result(
                plan,
                unit;
                status = unit.replication <= 5 ? :fit_failed : :completed,
                authorization_decision_fingerprint =
                    decision_covered.decision_fingerprint,
            ),
        )
    five_unresolved_per_rho_score = experimental.
        free_latent_correlation_2d_study_score(
            five_unresolved_per_rho_ledger,
        )
    @test five_unresolved_per_rho_score.evaluated
    @test five_unresolved_per_rho_score.decision ===
        :inconclusive_not_passed
    @test five_unresolved_per_rho_score.status ===
        :evaluation_scoring_inconclusive_not_passed
    @test isempty(five_unresolved_per_rho_score.hard_failure_rows)
    five_unresolved_codes = Set(row.code for row in
        five_unresolved_per_rho_score.uncertainty_blocker_rows)
    @test :rmse_unresolved_envelope_crosses_limit in
        five_unresolved_codes
    five_unresolved_rows =
        five_unresolved_per_rho_score.aggregate.per_rho_rows
    @test all(row -> row.n_planned == 100 &&
            row.n_scientifically_scored == 95 &&
            row.n_scientifically_unresolved == 5 &&
            row.n_fit_failed == 5 &&
            row.coverage.joint_fixed_denominator_rate == 0.95 &&
            (!row.direction_applicable ||
                row.direction.joint_fixed_denominator_rate == 0.95),
        five_unresolved_rows)
    @test all(row -> iszero(row.mean_bias) &&
            iszero(row.root_mean_squared_error),
        five_unresolved_rows)
    @test all(row ->
            row.continuous_unresolved_worst_case.
                root_mean_squared_error_envelope_plus_mcse_upper >
                scorer_contract.maximum_rmse_upper,
        five_unresolved_rows)
    for row in five_unresolved_per_rho_score.aggregate.
            unpaired_symmetry_rows
        bounds = row.signed_bias_contrast_unresolved_bounds
        @test all(isfinite, (bounds.lower, bounds.upper))
        @test bounds.lower <= bounds.upper
        @test row.n_scientifically_unresolved == 10
        @test isfinite(
            row.absolute_signed_bias_contrast_unresolved_plus_mcse_upper,
        )
        @test row.absolute_signed_bias_contrast_unresolved_upper <=
            row.absolute_signed_bias_contrast_unresolved_plus_mcse_upper
    end

    # Adjacent fixed-denominator counts straddle the frozen one-sided Wilson
    # boundary: 435/500 is inconclusive, while 440/500 passes it.
    wilson_boundary_score = covered_per_rho -> begin
        ledger_for_boundary = _free_correlation_study_materialize_evaluation(
            feasibility_covered,
            decision_covered,
            unit -> begin
                covered = unit.replication <= covered_per_rho
                _free_correlation_study_result(
                    plan,
                    unit;
                    covered,
                    posterior_median = covered ? unit.rho_truth :
                        unit.rho_truth + 0.06,
                    authorization_decision_fingerprint =
                        decision_covered.decision_fingerprint,
                )
            end,
        )
        return experimental.free_latent_correlation_2d_study_score(
            ledger_for_boundary,
        )
    end
    wilson_87 = wilson_boundary_score(87)
    @test wilson_87.evaluated
    @test wilson_87.decision === :inconclusive_not_passed
    @test wilson_87.status ===
        :evaluation_scoring_inconclusive_not_passed
    @test isempty(wilson_87.hard_failure_rows)
    @test :aggregate_coverage_wilson_lower_crosses_minimum in Set(
        row.code for row in wilson_87.uncertainty_blocker_rows
    )
    coverage_87 = wilson_87.aggregate.overall.coverage
    @test coverage_87.n_successes == 435
    @test coverage_87.n_planned == 500
    @test isapprox(
        coverage_87.equal_weight_joint_fixed_denominator_rate,
        0.87;
        atol = 1e-15,
        rtol = 0.0,
    )
    scoring_one_sided_z = plan.recovery_analysis.
        fixed_evaluation_thresholds.one_sided_normal_quantile
    @test isapprox(
        coverage_87.one_sided_wilson_lower,
        _free_correlation_study_wilson_lower(
            435,
            500,
            scoring_one_sided_z,
        );
        atol = 1e-14,
        rtol = 0.0,
    )
    @test coverage_87.one_sided_wilson_lower < 0.85

    wilson_88 = wilson_boundary_score(88)
    @test wilson_88.evaluated
    @test wilson_88.decision === :passed
    @test wilson_88.status === :evaluation_scoring_passed
    @test isempty(wilson_88.hard_failure_rows)
    @test isempty(wilson_88.uncertainty_blocker_rows)
    coverage_88 = wilson_88.aggregate.overall.coverage
    @test coverage_88.n_successes == 440
    @test coverage_88.n_planned == 500
    @test isapprox(
        coverage_88.equal_weight_joint_fixed_denominator_rate,
        0.88;
        atol = 1e-15,
        rtol = 0.0,
    )
    @test coverage_88.one_sided_wilson_lower > 0.85
    @test_throws ArgumentError experimental.
        free_latent_correlation_2d_study_score(first(tampered_ledgers))
end
