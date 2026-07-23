using Test

module ExistingApiDesignRobustnessRecoveryScorerForTest

include(joinpath(@__DIR__, "..", "scripts",
    "generate_existing_api_design_robustness_stress_grid.jl"))

end


const ExistingApiRecoveryScorer =
    ExistingApiDesignRobustnessRecoveryScorerForTest

function synthetic_blocks(family)
    family === :mfrm && return (:person, :rater, :item, :thresholds)
    family === :guarded_scalar_gmfrm && return (
        :person,
        :rater,
        :item,
        :item_discrimination,
        :rater_consistency,
        :rater_steps,
    )
    family === :guarded_fixed_q_mgmfrm && return (
        :person,
        :rater,
        :item,
        :item_dimension_discrimination,
        :rater_consistency,
        :item_steps,
    )
    error("unsupported synthetic family")
end

function synthetic_truth_contract(scorer, family;
        structurally_fixed = Set{String}())
    rows = [(;
        parameter = "$(block)[1]",
        raw_block = block,
        true_value = 0.0,
        quality_gate_applicable = !("$(block)[1]" in structurally_fixed),
        diagnostic_status = "$(block)[1]" in structurally_fixed ?
            :structurally_fixed : :rank_normalized_available,
    ) for block in synthetic_blocks(family)]
    payload = (; parameter_space = :direct, parameters = rows)
    return (;
        schema = "bayesianmgmfrm.existing_api_recovery_truth_contract.v1",
        payload,
        content_sha256 = scorer.portable_json_hash(payload),
    )
end

function synthetic_recovery_parameter(parameter, block, bias;
        true_value = 0.0,
        posterior_sd = 0.08,
        posterior_lower = -0.4,
        posterior_upper = 0.4,
        quality_gate_applicable = true,
        diagnostic_status = quality_gate_applicable ?
            :rank_normalized_available : :structurally_fixed)
    posterior_mean = true_value + bias
    covered = posterior_lower <= true_value <= posterior_upper
    return (;
        parameter,
        block,
        true_value,
        posterior_mean,
        posterior_sd,
        posterior_lower,
        posterior_upper,
        interval_probability = 0.90,
        lower_probability = 0.05,
        upper_probability = 0.95,
        bias,
        absolute_bias = abs(bias),
        squared_error = bias * bias,
        covered,
        interval_width = posterior_upper - posterior_lower,
        quality_gate_applicable,
        diagnostic_status,
    )
end

function synthetic_recovery_diagnostics(scorer;
        seed_namespace = :calibration_evaluation,
        passed = true)
    profile = seed_namespace === :smoke_wiring ? :smoke :
        seed_namespace === :pilot_threshold ? :pilot : :calibration
    contract = scorer.recovery_sampler_contract(
        scorer.profile_config(profile).sampler,
    ).payload
    return (;
        flag = passed ? :ok : :mcmc_warning,
        passed,
        diagnostic_contract = contract.diagnostic_contract,
        diagnostic_contract_details = contract.diagnostic_contract_details,
        n_chains = contract.n_chains,
        draws_per_chain = contract.draws_per_chain,
        total_draws = contract.total_draws,
        split_chains = contract.split_chains,
        rhat_threshold = contract.max_rhat,
        ess_threshold = contract.min_bulk_ess,
        max_rhat = passed ? min(1.005, contract.max_rhat) : 1.02,
        min_bulk_ess = passed ? max(450.0, contract.min_bulk_ess) : 200.0,
        min_tail_ess = passed ? max(425.0, contract.min_tail_ess) : 175.0,
        n_divergences = 0,
        n_max_treedepth = 0,
        e_bfmi = passed ? 0.70 : 0.20,
        n_e_bfmi_expected = contract.n_chains,
        n_e_bfmi_available = contract.n_chains,
        n_e_bfmi_unavailable = 0,
        e_bfmi_complete = true,
        n_nonfinite_logdensity = 0,
        n_failed_direct_constraints = 0,
    )
end

function synthetic_fit(scorer, family, replication, condition;
        seed_namespace = :calibration_evaluation,
        succeeded = true,
        truth_contract = synthetic_truth_contract(scorer, family),
        row_transform = identity,
        diagnostics = synthetic_recovery_diagnostics(
            scorer;
            seed_namespace,
        ))
    rows = NamedTuple[]
    if succeeded
        for (index, expected) in enumerate(truth_contract.payload.parameters)
            bias = condition === :A_well_specified_static ?
                0.08sin(0.71replication + 0.37index) :
                0.12cos(0.53replication + 0.29index)
            row = synthetic_recovery_parameter(
                expected.parameter,
                expected.raw_block,
                bias;
                true_value = expected.true_value,
                quality_gate_applicable = expected.quality_gate_applicable,
                diagnostic_status = expected.diagnostic_status,
                posterior_sd = expected.quality_gate_applicable ? 0.08 : 0.0,
                posterior_lower = expected.quality_gate_applicable ?
                    expected.true_value - 0.4 :
                    expected.true_value,
                posterior_upper = expected.quality_gate_applicable ?
                    expected.true_value + 0.4 :
                    expected.true_value,
            )
            push!(rows, row_transform(row))
        end
    end
    return (;
        status = succeeded ? :completed : :failed,
        succeeded,
        diagnostics = succeeded ? diagnostics : nothing,
        recovery_parameter_rows = rows,
    )
end

synthetic_hash(scorer, values...) = scorer.portable_json_hash(values)

function synthetic_pair(scorer, cell_id, family, replication;
        seed_namespace = :calibration_evaluation,
        fail_condition = nothing,
        omit_condition = nothing,
        pair_contract = nothing,
        truth_contract = synthetic_truth_contract(scorer, family),
        row_transform = identity,
        sampler_contract = scorer.recovery_sampler_contract(
            scorer.profile_config(seed_namespace === :smoke_wiring ? :smoke :
                seed_namespace === :pilot_threshold ? :pilot : :calibration).
                sampler,
        ))
    conditions = NamedTuple[]
    for condition in (
            :A_well_specified_static,
            :B_unmodeled_order_effect)
        condition === omit_condition && continue
        push!(conditions, (;
            condition,
            fit = synthetic_fit(
                scorer,
                family,
                replication,
                condition;
                seed_namespace,
                succeeded = condition !== fail_condition,
                truth_contract,
                row_transform,
            ),
        ))
    end
    return (;
        cell_id,
        family,
        replication,
        seed_namespace,
        rating_assignment_design_sha256 = pair_contract === nothing ?
            synthetic_hash(scorer, :design, cell_id, family, replication) :
            pair_contract.rating_assignment_design_sha256,
        event_set_sha256 = pair_contract === nothing ?
            synthetic_hash(scorer, :events, cell_id, family, replication) :
            pair_contract.event_set_sha256,
        ordered_event_skeleton_sha256 = pair_contract === nothing ?
            synthetic_hash(scorer, :ordered, cell_id, family, replication) :
            pair_contract.ordered_event_skeleton_sha256,
        direct_truth_sha256 = pair_contract === nothing ?
            synthetic_hash(scorer, :truth, cell_id, family, replication) :
            pair_contract.direct_truth_sha256,
        recovery_truth_contract = truth_contract,
        recovery_sampler_contract = sampler_contract,
        conditions,
    )
end

function synthetic_calibration_pairs(scorer, preflight)
    rows = NamedTuple[]
    for contract in preflight.rows
        push!(rows, synthetic_pair(
            scorer,
            contract.cell_id,
            contract.family,
            contract.replication;
            pair_contract = contract,
            truth_contract = contract.recovery_truth_contract,
        ))
    end
    return rows
end

function synthetic_pilot_artifact(scorer)
    preflight = scorer._canonical_profile_fit_skeleton_preflight(:pilot, 30)
    paired_rows = [synthetic_pair(
        scorer,
        contract.cell_id,
        contract.family,
        contract.replication;
        seed_namespace = :pilot_threshold,
        pair_contract = contract,
        truth_contract = contract.recovery_truth_contract,
    ) for contract in preflight.rows]
    repeated_recovery = scorer.aggregate_repeated_recovery(paired_rows)
    repeated_recovery_gate = scorer._score_repeated_recovery_aggregate(
        repeated_recovery;
        stage = :pilot,
    )
    contract_rows = repeated_recovery.pair_contract_records
    artifact = (;
        schema =
            "bayesianmgmfrm.existing_api_design_robustness_stress_grid.v1",
        family = :mfrm_gmfrm_mgmfrm,
        scope = :existing_static_api_paired_known_truth_design_stress,
        publication_or_registration_action = false,
        public_claim_release_allowed = false,
        package = (;
            name = :BayesianMGMFRM,
            version = scorer.project_version(),
        ),
        generator = (;
            script =
                "scripts/generate_existing_api_design_robustness_stress_grid.jl",
            source_sha256 = scorer.file_sha256(joinpath(
                @__DIR__,
                "..",
                "scripts",
                "generate_existing_api_design_robustness_stress_grid.jl",
            )),
            deterministic_without_mcmc = true,
        ),
        runtime_provenance = scorer.package_runtime_provenance(),
        execution = (;
            profile = :pilot,
            execute_mcmc = true,
            requested_replications = 30,
            materialized_replications = 30,
            paired_fit_execution_completed = true,
            n_fit_failed = 0,
        ),
        summary = (; passed = true),
        repeated_recovery_gate,
        repeated_recovery = (;
            repeated_recovery...,
        ),
        paired_replication_rows = paired_rows,
        all_requested_replication_skeleton_preflight = preflight,
        deterministic_checks = [(;
            check,
            passed = true,
        ) for check in scorer.REQUIRED_DETERMINISTIC_CHECKS],
    )
    return merge(artifact, (;
        content_hash = (;
            algorithm = :sha256,
            value = scorer.portable_json_hash(artifact),
            covers = :artifact_without_content_hash,
        ),
    ))
end

@testset "existing-API repeated recovery scorer" begin
    scorer = ExistingApiRecoveryScorer

    @test scorer.RECOVERY_GATE_SCORER_IMPLEMENTED
    @test !scorer.PREDICTIVE_GATE_SCORER_IMPLEMENTED
    @test !scorer.DECISION_GATE_SCORER_IMPLEMENTED
    @test !scorer.FULL_GATE_SCORER_IMPLEMENTED
    capabilities = scorer.design_robustness_scorer_capabilities()
    @test capabilities.recovery.implemented
    @test !capabilities.prediction.implemented
    @test !capabilities.decision.implemented
    @test !capabilities.full_gate_scorer_implemented
    @test :item_discrimination in scorer.FOCAL_RECOVERY_BLOCKS
    @test scorer.wilson_upper(135, 150, 3.5) > 0.90
    @test scorer.wilson_upper(0, 150, 3.5) < 0.90
    @test scorer.nearest_rank_quantile([1, 2, 3, 100], 0.75) == 3.0
    @test scorer.nearest_rank_quantile([1, 2, 3, 100], 0.99) == 100.0

    @test scorer.canonical_model_family(:mfrm) === :mfrm
    @test scorer.canonical_model_family(:guarded_scalar_gmfrm) === :gmfrm
    @test scorer.canonical_model_family(:guarded_fixed_q_mgmfrm) === :mgmfrm
    @test scorer.canonical_recovery_block(:mfrm, :thresholds) === :thresholds
    @test scorer.canonical_recovery_block(
        :guarded_scalar_gmfrm, :rater_steps) === :thresholds
    @test scorer.canonical_recovery_block(
        :guarded_fixed_q_mgmfrm,
        :item_dimension_discrimination,
    ) === :fixed_q_dimension_parameters
    @test_throws ArgumentError scorer.canonical_model_family(:unknown)
    @test_throws ArgumentError scorer.canonical_recovery_block(:mfrm, :unknown)

    basic_pairs = [
        synthetic_pair(scorer, :C0_balanced_random_double_rated, :mfrm, 1),
        synthetic_pair(scorer, :C0_balanced_random_double_rated, :mfrm, 2),
    ]
    aggregate = scorer.aggregate_repeated_recovery(basic_pairs)
    @test aggregate.schema ==
        "bayesianmgmfrm.existing_api_repeated_recovery.v2"
    @test aggregate.summary.n_paired_replications == 2
    @test aggregate.summary.n_expected_condition_fits == 4
    @test aggregate.summary.n_recovery_complete == 4
    @test aggregate.summary.n_fit_failed == 0
    @test aggregate.summary.n_recovery_empty_or_incomplete == 0
    @test aggregate.summary.n_sampler_gate_failed == 0
    @test aggregate.summary.n_uncertainty_rows == 8
    @test aggregate.summary.n_uncertainty_rows_computed == 8
    @test aggregate.summary.all_expected_recovery_fits_completed
    @test aggregate.summary.all_sampler_gates_passed
    @test aggregate.summary.all_structurally_fixed_coordinates_exact
    @test length(aggregate.parameter_replication_rows) == 16
    @test length(aggregate.block_rows) == 8

    person_static = only(row for row in aggregate.block_rows
        if row.condition === :A_well_specified_static &&
            row.canonical_block === :person_ability)
    @test person_static.raw_blocks == (:person,)
    @test person_static.n_expected_replications == 2
    @test person_static.n_fit_replications == 2
    @test person_static.n_parameter_replication_rows == 2
    @test person_static.n_scored_parameter_replication_rows == 2
    @test person_static.coverage_rate == 1.0
    @test person_static.recovery_complete
    @test person_static.sampler_gate_passed
    person_uncertainty = only(row for row in aggregate.uncertainty_rows
        if row.condition === :A_well_specified_static &&
            row.canonical_block === :person_ability)
    @test person_uncertainty.n_replications == 2
    @test person_uncertainty.n_expected_replications == 2
    @test person_uncertainty.status === :computed

    smoke = scorer.score_repeated_recovery_gate(basic_pairs; stage = :smoke)
    @test !smoke.evaluated
    @test ismissing(smoke.passed)
    @test smoke.status === :wiring_only_not_recovery_evidence
    pilot = scorer.score_repeated_recovery_gate(basic_pairs; stage = :pilot)
    @test !pilot.evaluated
    @test ismissing(pilot.passed)
    @test pilot.threshold_results === nothing
    @test pilot.status ===
        :pilot_threshold_freeze_candidate_not_pass_fail_evidence

    unfrozen = scorer.score_repeated_recovery_gate(
        basic_pairs;
        stage = :calibration,
    )
    @test !unfrozen.evaluated
    @test ismissing(unfrozen.passed)
    @test unfrozen.status ===
        :calibration_blocked_frozen_gate_contract_missing
    @test !unfrozen.recovery_claim_supported
    @test_throws MethodError scorer.score_repeated_recovery_gate(
        basic_pairs;
        stage = :calibration,
        thresholds_frozen = true,
    )

    failed = scorer.aggregate_repeated_recovery([
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1;
            fail_condition = :A_well_specified_static,
        ),
        synthetic_pair(scorer, :C0_balanced_random_double_rated, :mfrm, 2),
    ])
    @test !failed.summary.all_expected_recovery_fits_completed
    @test !failed.summary.all_sampler_gates_passed
    @test failed.summary.n_fit_failed == 1

    missing_condition = scorer.aggregate_repeated_recovery([
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1;
            omit_condition = :B_unmodeled_order_effect,
        ),
    ])
    @test missing_condition.summary.n_fit_or_condition_missing == 1
    @test !missing_condition.summary.all_expected_recovery_fits_completed

    missing_parameter_pair = synthetic_pair(
        scorer,
        :C0_balanced_random_double_rated,
        :mfrm,
        1;
        row_transform = identity,
    )
    first_condition = missing_parameter_pair.conditions[1]
    short_fit = merge(first_condition.fit, (;
        recovery_parameter_rows = first_condition.fit.
            recovery_parameter_rows[1:end-1],
    ))
    short_pair = merge(missing_parameter_pair, (;
        conditions = [
            merge(first_condition, (; fit = short_fit)),
            missing_parameter_pair.conditions[2],
        ],
    ))
    short_aggregate = scorer.aggregate_repeated_recovery([short_pair])
    @test !short_aggregate.summary.all_expected_recovery_fits_completed
    @test short_aggregate.summary.n_recovery_empty_or_incomplete == 1

    bad_bias = row -> merge(row, (; bias = row.bias + 1.0))
    @test_throws ArgumentError scorer.aggregate_repeated_recovery([
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1;
            row_transform = bad_bias,
        ),
    ])
    negative_sd = row -> merge(row, (; posterior_sd = -1.0))
    @test_throws ArgumentError scorer.aggregate_repeated_recovery([
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1;
            row_transform = negative_sd,
        ),
    ])
    false_coverage = row -> merge(row, (; covered = !row.covered))
    @test_throws ArgumentError scorer.aggregate_repeated_recovery([
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1;
            row_transform = false_coverage,
        ),
    ])
    false_applicability = row -> merge(row, (;
        quality_gate_applicable = false,
        diagnostic_status = :structurally_fixed,
        posterior_sd = 0.0,
        posterior_lower = row.true_value,
        posterior_upper = row.true_value,
        interval_width = 0.0,
    ))
    @test_throws ArgumentError scorer.aggregate_repeated_recovery([
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1;
            row_transform = false_applicability,
        ),
    ])

    duplicated = [
        synthetic_pair(scorer, :C0_balanced_random_double_rated, :mfrm, 1),
        synthetic_pair(scorer, :C0_balanced_random_double_rated, :mfrm, 1),
    ]
    @test_throws ArgumentError scorer.aggregate_repeated_recovery(duplicated)
    @test_throws ArgumentError scorer.recovery_scorer_stage_contract(:unknown)

    json_pair = scorer.JSON3.read(scorer.JSON3.write(
        synthetic_pair(
            scorer,
            :C0_balanced_random_double_rated,
            :mfrm,
            1,
        ),
    ))
    json_aggregate = scorer.aggregate_repeated_recovery([json_pair])
    @test json_aggregate.summary.n_recovery_complete == 2
    @test json_aggregate.summary.all_sampler_gates_passed

    synthetic_preflight = scorer._canonical_profile_fit_skeleton_preflight(
        :calibration,
        50,
    )
    calibration_pairs = synthetic_calibration_pairs(
        scorer,
        synthetic_preflight,
    )
    calibration_aggregate = scorer.aggregate_repeated_recovery(
        calibration_pairs,
    )
    @test calibration_aggregate.summary.n_paired_replications == 1050
    @test calibration_aggregate.summary.all_expected_recovery_fits_completed
    @test calibration_aggregate.summary.all_sampler_gates_passed
    pilot_artifact = synthetic_pilot_artifact(scorer)
    @test_throws ArgumentError scorer._validated_pilot_artifact_content_hash(
        merge(pilot_artifact, (;
            deterministic_checks = [(;
                check = :synthetic_contract_check,
                passed = true,
            )],
        )),
    )
    @test_throws ArgumentError scorer._validated_pilot_artifact_content_hash(
        merge(pilot_artifact, (;
            repeated_recovery = merge(
                pilot_artifact.repeated_recovery,
                (;
                    summary = merge(
                        pilot_artifact.repeated_recovery.summary,
                        (; n_fit_failed = 999),
                    ),
                ),
            ),
        )),
    )
    sampler_contract = scorer.recovery_sampler_contract(
        scorer.profile_config(:calibration).sampler,
    )
    freeze_input = scorer.calibration_recovery_freeze_input(
        synthetic_preflight,
    )
    @test freeze_input.payload.response_data_generated === false
    @test freeze_input.payload.mcmc_executed === false
    @test length(freeze_input.payload.expected_pair_contracts) == 1050
    @test freeze_input.payload.sampler_contract_sha256 ==
        sampler_contract.content_sha256
    thresholds = (;
        nominal_interval_coverage = 0.90,
        max_block_mae_quantile = 0.35,
        max_focal_absolute_error_quantile = 0.75,
        min_empirical_to_posterior_sd_ratio_quantile = 0.50,
        max_empirical_to_posterior_sd_ratio_quantile = 2.00,
    )
    pilot_threshold_decision =
        scorer.pilot_recovery_threshold_freeze_decision(
            pilot_artifact;
            thresholds,
            decision_revision = "test-pilot-threshold-review",
            decided_at_utc = "2026-07-20T23:59:00Z",
        )
    freeze = scorer.recovery_gate_freeze_contract(;
        pilot_threshold_decision,
        freeze_source_revision = "test-revision",
        frozen_at_utc = "2026-07-21T00:00:00Z",
        freeze_input,
    )
    @test freeze.payload.pre_response_freeze_input_content_sha256 ==
        freeze_input.content_sha256
    post_response_payload = merge(freeze_input.payload, (;
        response_data_generated = true,
    ))
    post_response_freeze_input = (;
        schema = freeze_input.schema,
        payload = post_response_payload,
        content_sha256 = scorer.portable_json_hash(post_response_payload),
    )
    @test_throws ArgumentError scorer.recovery_gate_freeze_contract(;
        pilot_threshold_decision,
        freeze_source_revision = "test-revision",
        frozen_at_utc = "2026-07-21T00:00:00Z",
        freeze_input = post_response_freeze_input,
    )
    forged_digest_payload = merge(freeze_input.payload, (;
        source_preflight_content_sha256 = repeat("a", 64),
        source_pair_contract_manifest_sha256 = repeat("b", 64),
    ))
    forged_digest_freeze_input = (;
        schema = freeze_input.schema,
        payload = forged_digest_payload,
        content_sha256 = scorer.portable_json_hash(forged_digest_payload),
    )
    @test_throws ArgumentError scorer.recovery_gate_freeze_contract(;
        pilot_threshold_decision,
        freeze_source_revision = "test-revision",
        frozen_at_utc = "2026-07-21T00:00:00Z",
        freeze_input = forged_digest_freeze_input,
    )
    calibration = scorer.score_repeated_recovery_gate(
        calibration_pairs;
        stage = :calibration,
        frozen_gate_contract = freeze,
        pilot_artifact,
    )
    @test calibration.evaluated
    @test calibration.passed
    @test calibration.freeze_contract_valid
    @test calibration.pilot_artifact_contract_consistent
    @test !calibration.pilot_artifact_verified
    @test calibration.expected_grid_exact
    @test calibration.uncertainty_complete
    @test all(values(calibration.threshold_results))
    @test calibration.
        well_specified_static_distributional_gate_passed_under_contract
    @test !calibration.distributional_recovery_gate_supported
    @test !calibration.recovery_claim_supported
    @test !calibration.all_conditions_recovery_claim_supported
    @test !calibration.full_design_robustness_claim_supported
    @test !calibration.public_claim_release_allowed
    forged_policy = merge(
        pilot_threshold_decision.payload.pilot_statistical_gate_policy,
        (; coverage_method = :forged_policy),
    )
    forged_policy_payload = merge(pilot_threshold_decision.payload, (;
        pilot_statistical_gate_policy = forged_policy,
        pilot_statistical_gate_policy_sha256 =
            scorer.portable_json_hash(forged_policy),
    ))
    forged_policy_decision = (;
        schema = pilot_threshold_decision.schema,
        payload = forged_policy_payload,
        content_sha256 = scorer.portable_json_hash(forged_policy_payload),
    )
    forged_policy_freeze = scorer.recovery_gate_freeze_contract(;
        pilot_threshold_decision = forged_policy_decision,
        freeze_source_revision = "test-forged-policy",
        frozen_at_utc = "2026-07-21T00:00:00Z",
        freeze_input,
    )
    forged_policy_gate = scorer.score_repeated_recovery_gate(
        calibration_pairs;
        stage = :calibration,
        frozen_gate_contract = forged_policy_freeze,
        pilot_artifact,
    )
    @test !forged_policy_gate.pilot_threshold_source_exact
    @test !forged_policy_gate.evaluated
    @test forged_policy_gate.status ===
        :calibration_blocked_pilot_threshold_source_mismatch
    @test_throws ArgumentError scorer.recovery_gate_freeze_contract(;
        pilot_threshold_decision,
        freeze_source_revision = "test-time-order",
        frozen_at_utc = "2026-07-20T23:58:00Z",
        freeze_input,
    )

    sentinel_pairs = copy(calibration_pairs)
    sentinel_pair = sentinel_pairs[1]
    sentinel_condition = sentinel_pair.conditions[1]
    sentinel_fit = sentinel_condition.fit
    sentinel_rows = copy(sentinel_fit.recovery_parameter_rows)
    sentinel_row = sentinel_rows[1]
    sentinel_rows[1] = merge(sentinel_row, (;
        posterior_mean = sentinel_row.true_value + 1.50,
        bias = 1.50,
        absolute_bias = 1.50,
        squared_error = 2.25,
    ))
    sentinel_pairs[1] = merge(sentinel_pair, (;
        conditions = [
            merge(sentinel_condition, (;
                fit = merge(sentinel_fit, (;
                    recovery_parameter_rows = sentinel_rows,
                )),
            )),
            sentinel_pair.conditions[2],
        ],
    ))
    sentinel_gate = scorer.score_repeated_recovery_gate(
        sentinel_pairs;
        stage = :calibration,
        frozen_gate_contract = freeze,
        pilot_artifact,
    )
    @test sentinel_gate.passed
    @test sentinel_gate.observed.maximum_focal_absolute_error_sentinel == 1.50
    @test sentinel_gate.observed.focal_absolute_error_q99 <=
        sentinel_gate.thresholds.max_focal_absolute_error_quantile

    tampered_pairs = copy(calibration_pairs)
    tampered_pairs[1] = merge(tampered_pairs[1], (;
        rating_assignment_design_sha256 = repeat("f", 64),
    ))
    tampered_gate = scorer.score_repeated_recovery_gate(
        tampered_pairs;
        stage = :calibration,
        frozen_gate_contract = freeze,
        pilot_artifact,
    )
    @test !tampered_gate.evaluated
    @test ismissing(tampered_gate.passed)
    @test tampered_gate.status ===
        :calibration_blocked_expected_grid_mismatch
    @test !tampered_gate.recovery_claim_supported

    @test_throws ArgumentError scorer.recovery_gate_freeze_contract(;
        pilot_threshold_decision,
        freeze_source_revision = "test-revision",
        frozen_at_utc = "2026-07-21T00:00:00Z",
        freeze_input = merge(freeze_input, (;
            content_sha256 = repeat("0", 64),
        )),
    )
    lax_thresholds = merge(thresholds, (;
        nominal_interval_coverage = 0.10,
    ))
    @test_throws ArgumentError scorer.pilot_recovery_threshold_freeze_decision(
        pilot_artifact;
        thresholds = lax_thresholds,
        decision_revision = "test-lax-thresholds",
        decided_at_utc = "2026-07-20T23:59:00Z",
    )

    freeze_json = scorer.JSON3.read(scorer.JSON3.write(freeze))
    normalized_freeze = scorer._validated_recovery_gate_freeze(freeze_json)
    @test normalized_freeze.expected_pair_keys == freeze.payload.
        expected_pair_keys

    diagnostic_record = scorer.diagnostic_summary_record(
        synthetic_recovery_diagnostics(scorer);
        family = :mfrm,
    )
    @test diagnostic_record.min_bulk_ess >= 400.0
    @test diagnostic_record.min_tail_ess >= 400.0
    @test diagnostic_record.min_ess >= 400.0
    @test diagnostic_record.e_bfmi_complete
    @test diagnostic_record.diagnostic_contract ===
        :rank_normalized_rhat_bulk_tail_ess_v1
end
