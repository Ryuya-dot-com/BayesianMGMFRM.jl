using JSON3
using SHA
using Test

const LD1B1_SEMANTICS_REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))

include(joinpath(
    LD1B1_SEMANTICS_REPOSITORY_ROOT,
    "scripts",
    "local_dependence_pilot_calibration_semantics.jl",
))

const LD1B1CalibrationSemanticsForTest =
    LocalDependencePilotCalibrationSemantics

function ld1b1_semantics_generation_failure_record(plan;
        error_class::Symbol = :generator_exception)
    return ld1b1_semantics_failure_record(
        plan, :generation_failed; error_class)
end

function ld1b1_semantics_failure_record(plan, status::Symbol;
        error_class::Symbol = :synthetic_semantic_failure,
        failure_component::Symbol = :local_dependence_summary)
    status in (:generation_failed, :fit_failed, :diagnostic_failed) ||
        error("unsupported test failure status: $status")
    replication = lpad(string(plan.replication), 2, '0')
    scenario_index = lpad(string(plan.scenario_index), 2, '0')
    role = status === :generation_failed ? :generation_failure_record :
        status === :fit_failed ? :fit_failure_record :
        :diagnostic_failure_record
    stage = status === :generation_failed ? :generation :
        status === :fit_failed ? :fit : :diagnostic
    base = (;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_failure_record.v1",
        object = role,
        job_id = string(
            "ld1b1_pilot__rep", replication,
            "__s", scenario_index,
            "__", plan.scenario_id,
        ),
        row_index = plan.row_index,
        scenario_id = plan.scenario_id,
        replication = plan.replication,
        failure_stage = stage,
    )
    return merge(base, status === :diagnostic_failed ?
        (; failure_component, error_class, failure_recorded = true) :
        (; error_class, failure_recorded = true))
end

function ld1b1_semantics_archived_calibration_member(
        semantics, context, row_index::Int, status::Symbol;
        data_signature = string(UInt64(50_000 + row_index)))
    template = semantics._ld1b1_calibration_template(context, row_index)
    value = semantics.ld1b1_semantic_json_native(template.expected)
    shape = value["planning_shape"]
    has_simulation = status !== :generation_failed
    has_diagnostic = status === :completed
    signature = data_signature
    score_signature = bytes2hex(sha256(codeunits("score:$row_index")))
    design_signature = bytes2hex(sha256(codeunits("design:$row_index")))
    requested = template.plan.expected_requested_targets_eligible
    simulation_provenance = has_simulation ? Dict(
        "status" => "known_truth_generated",
        "data_signature" => signature,
        "score_signature" => score_signature,
        "observed_score_signature" => Dict(
            "algorithm" => "sha256", "value" => score_signature),
        "testlet_design_signature" => Dict(
            "algorithm" => "sha256", "value" => design_signature),
        "n_ratings" => 1,
        "planning_shape" => deepcopy(shape),
        "observed_shape" => Dict(
            "n_persons" => shape["n_persons"],
            "n_testlets" => shape["n_testlets"],
            "n_items" => shape["n_items"],
            "n_raters" => shape["n_raters"],
            "n_categories" => shape["n_categories"],
        ),
        "requested_targets_eligible" => requested,
        "future_fit_action" => requested ?
            "structurally_eligible_for_future_candidate" :
            "do_not_fit_underidentified_design",
    ) : nothing
    diagnostic_provenance = has_diagnostic ? Dict(
        "status" => "report_only",
        "profile" => String(context.calibration_contract.
            diagnostic_contract.profile),
        "n_draws" => 250,
        "data_signature" => signature,
        "observed_score_signature" => Dict(
            "algorithm" => "sha256", "value" => score_signature),
        "design_signature" => Dict(
            "algorithm" => "sha256", "value" => design_signature),
    ) : nothing
    families = (
        :single_rating_item_q3,
        :within_rater_item_q3,
        :rater_on_shared_response_criterion,
    )
    pair_evidence = has_diagnostic ? [Dict(
        "family" => "single_rating_item_q3",
        "testlet_id" => "testlet_1",
        "left" => "item_1",
        "right" => "item_2",
        "support_status" => "eligible_report_only",
        "eligible" => true,
        "posterior_predictive_tail_fraction" => 0.04,
        "bh_adjusted_tail_fraction" => 0.04,
        "candidate_raw_declared" => true,
        "candidate_bh_declared" => true,
    )] : Any[]
    family_evidence = has_diagnostic ? [family ===
            :single_rating_item_q3 ? Dict(
                "family" => String(family),
                "support_status" => "supported",
                "applicable" => true,
                "n_pair_rows" => 1,
                "n_eligible_pairs" => 1,
                "n_raw_declared" => 1,
                "n_bh_declared" => 1,
                "any_raw_declared" => true,
                "any_bh_declared" => true,
                "maximum_support_status" => "supported",
                "maximum_tail_fraction" => 0.04,
                "family_evaluable" => true,
                "candidate_family_declared" => true,
            ) : Dict(
                "family" => String(family),
                "support_status" => "not_applicable",
                "applicable" => false,
                "n_pair_rows" => 0,
                "n_eligible_pairs" => 0,
                "n_raw_declared" => 0,
                "n_bh_declared" => 0,
                "any_raw_declared" => nothing,
                "any_bh_declared" => nothing,
                "maximum_support_status" => "not_applicable",
                "maximum_tail_fraction" => nothing,
                "family_evaluable" => false,
                "candidate_family_declared" => nothing,
            ) for family in families] : Any[]
    global_evidence = has_diagnostic ? Dict(
        "support_status" => "supported",
        "n_overall_supported_pairs" => 1,
        "tail_fraction" => 0.04,
        "evaluable" => true,
        "candidate_global_declared" => true,
    ) : nothing
    value["status"] = String(status)
    value["failure_code"] = status in (
        :generation_failed, :fit_failed, :diagnostic_failed) ?
        "synthetic_semantic_failure" : nothing
    value["simulation_provenance"] = simulation_provenance
    value["diagnostic_provenance"] = diagnostic_provenance
    value["n_pair_evidence"] = length(pair_evidence)
    value["pair_evidence"] = pair_evidence
    value["family_evidence"] = family_evidence
    value["global_evidence"] = global_evidence
    return value
end

function ld1b1_semantics_local_summary_member(context, row_index::Int;
        data_signature = string(UInt64(50_000 + row_index)))
    families = (
        :single_rating_item_q3,
        :within_rater_item_q3,
        :rater_on_shared_response_criterion,
    )
    score_signature = bytes2hex(sha256(codeunits("score:$row_index")))
    design_signature = bytes2hex(sha256(codeunits("design:$row_index")))
    return Dict(
        "status" => "report_only",
        "profile" => String(context.calibration_contract.
            diagnostic_contract.profile),
        "n_draws" => 250,
        "data_signature" => data_signature,
        "observed_score_signature" => Dict(
            "algorithm" => "sha256", "value" => score_signature),
        "design_signature" => Dict(
            "algorithm" => "sha256", "value" => design_signature),
        "pair_rows" => [Dict(
            "family" => "single_rating_item_q3",
            "testlet_id" => "testlet_1",
            "left" => "item_1",
            "right" => "item_2",
            "status" => "eligible_report_only",
            "posterior_predictive_tail_fraction" => 0.04,
            "bh_adjusted_tail_fraction" => 0.04,
        )],
        "family_rows" => [Dict(
            "family" => String(family),
            "status" => family === :single_rating_item_q3 ?
                "supported" : "not_applicable",
        ) for family in families],
        "family_max_rows" => [Dict(
            "family" => String(family),
            "support_status" => family === :single_rating_item_q3 ?
                "supported" : "not_applicable",
            "posterior_predictive_tail_fraction" =>
                family === :single_rating_item_q3 ? 0.04 : nothing,
        ) for family in families],
        "global_evidence" => Dict(
            "support_status" => "supported",
            "n_overall_supported_pairs" => 1,
            "posterior_predictive_tail_fraction" => 0.04,
        ),
    )
end

function ld1b1_semantics_changed_top_level_fields(reference, candidate)
    return Set(
        key for key in keys(reference)
        if LD1B1CalibrationSemanticsForTest.ld1b1_normalized_json(
            reference[key],
        ) != LD1B1CalibrationSemanticsForTest.ld1b1_normalized_json(
            candidate[key],
        )
    )
end

@testset "LD1b1 pilot calibration semantic adapter" begin
    protocol_path = joinpath(
        LD1B1_SEMANTICS_REPOSITORY_ROOT,
        "test",
        "fixtures",
        "local_dependence_pilot_protocol_preflight.json",
    )
    semantics = LD1B1CalibrationSemanticsForTest
    context = semantics.ld1b1_load_calibration_semantic_context(
        protocol_path,
    )

    @testset "canonical public plan reconstruction" begin
        @test length(context.plan_rows) == semantics.LD1B1_EXPECTED_PLAN_ROWS
        @test Tuple(getproperty.(context.plan_rows, :row_index)) == Tuple(1:660)
        @test context.public_contract_sha256 ==
            semantics.LD1B1_PILOT_CONTRACT_SHA256
        @test context.artifact_contract_sha256 ==
            semantics.LD1B1_PILOT_CONTRACT_SHA256
        @test context.public_job_rows_sha256 ==
            semantics.LD1B1_ORDERED_JOB_ROWS_SHA256
        @test context.artifact_job_rows_sha256 ==
            semantics.LD1B1_ORDERED_JOB_ROWS_SHA256
        @test semantics.ld1b1_normalized_json(context.public_preflight) ==
            semantics.ld1b1_normalized_json(
                context.protocol[:pilot_preflight],
            )
    end

    @testset "data signatures use canonical decimal JSON strings" begin
        boundary_signatures = (
            UInt64(0),
            UInt64(typemax(Int64)),
            UInt64(typemax(Int64)) + UInt64(1),
            typemax(UInt64),
        )
        for signature in boundary_signatures
            expected = string(signature)
            @test semantics._ld1b1_data_signature(
                signature, "native signature") === signature
            @test semantics._ld1b1_data_signature(
                expected, "persisted signature") === signature

            native = (;
                data_signature = signature,
                unrelated_uint64 = signature,
            )
            persisted = Dict(
                "data_signature" => expected,
                "unrelated_uint64" => signature,
            )
            projected = semantics.ld1b1_semantic_json_native(native)
            @test projected["data_signature"] == expected
            @test projected["unrelated_uint64"] === signature
            @test semantics.ld1b1_normalized_json(native) ==
                semantics.ld1b1_normalized_json(persisted)
            @test semantics.ld1b1_normalized_json_sha256(native) ==
                semantics.ld1b1_normalized_json_sha256(persisted)

            typed = semantics._ld1b1_typed_json_value(Dict(
                "data_signature" => expected,
            ))
            @test typed.data_signature === signature

            decoded = JSON3.read(
                "{\"data_signature\":\"$expected\"}",
            )
            @test semantics.ld1b1_normalized_json(decoded) ==
                "{\"data_signature\":\"$expected\"}"
        end

        invalid_strings = (
            "",
            "00",
            "01",
            "+1",
            "-1",
            "1.0",
            "1e3",
            " 1",
            "1 ",
            "not-a-number",
            string(BigInt(typemax(UInt64)) + 1),
        )
        for value in invalid_strings
            @test_throws ArgumentError semantics._ld1b1_data_signature(
                value, "invalid persisted signature")
            @test_throws ArgumentError semantics.ld1b1_normalized_json(Dict(
                "data_signature" => value,
            ))
        end
        for value in (
                Int64(0),
                UInt32(1),
                1.0,
                true,
                nothing,
                missing,
            )
            @test_throws ArgumentError semantics._ld1b1_data_signature(
                value, "invalid numeric signature")
        end

        small_numeric_json = JSON3.read("{\"data_signature\":1}")
        large_numeric_json = JSON3.read(
            "{\"data_signature\":18446744073709551615}",
        )
        @test small_numeric_json[:data_signature] isa Int64
        @test large_numeric_json[:data_signature] isa Float64
        @test_throws ArgumentError semantics.ld1b1_normalized_json(
            small_numeric_json)
        @test_throws ArgumentError semantics.ld1b1_normalized_json(
            large_numeric_json)
    end

    @testset "canonical linked generation-failure row" begin
        row_index = 1
        plan = context.plan_rows[row_index]
        failure_record = ld1b1_semantics_generation_failure_record(plan)
        canonical = semantics.ld1b1_canonical_generation_failed_row(
            context,
            row_index;
            failure_record,
        )
        archived_member = JSON3.read(JSON3.write(canonical.expected))
        validated = semantics.ld1b1_validate_generation_failed_member(
            context,
            row_index,
            archived_member;
            failure_record,
        )

        @test validated.valid
        @test validated.failure_code === :generator_exception
        @test validated.expected.status === :generation_failed
        @test validated.expected.failure_code === :generator_exception
        @test validated.summary.n_plan_rows == 1
        @test validated.summary.n_result_rows == 1
        @test validated.summary.n_missing_result_rows == 0
        @test only(
            status.n for status in validated.summary.status_rows
            if status.status === :generation_failed
        ) == 1
        @test validated.member_sha256 ==
            semantics.ld1b1_normalized_json_sha256(archived_member)

        string_key_failure_record =
            semantics.ld1b1_semantic_json_native(failure_record)
        @test semantics.ld1b1_validate_generation_failed_member(
            context,
            row_index,
            archived_member;
            failure_record = string_key_failure_record,
        ).valid
        ambiguous_failure_record = Dict{Any,Any}(
            pairs(string_key_failure_record),
        )
        ambiguous_failure_record[:schema] =
            ambiguous_failure_record["schema"]
        @test_throws ArgumentError begin
            semantics.ld1b1_validate_generation_failed_member(
                context,
                row_index,
                archived_member;
                failure_record = ambiguous_failure_record,
            )
        end

        wrong_failure_code = merge(
            failure_record,
            (; error_class = :different_generator_exception),
        )
        @test_throws ArgumentError begin
            semantics.ld1b1_validate_generation_failed_member(
                context,
                row_index,
                archived_member;
                failure_record = wrong_failure_code,
            )
        end
    end

    @testset "all terminal statuses replay through the public contract" begin
        eligible_index = findfirst(
            row -> row.expected_requested_targets_eligible,
            context.plan_rows,
        )
        rejection_index = findfirst(
            row -> !row.expected_requested_targets_eligible,
            context.plan_rows,
        )
        status_rows = (
            (:completed, eligible_index),
            (:pre_fit_rejected, rejection_index),
            (:generation_failed, eligible_index),
            (:fit_failed, eligible_index),
            (:diagnostic_failed, eligible_index),
        )
        signature_by_status = Dict(
            :completed => string(typemax(UInt64)),
            :pre_fit_rejected =>
                string(UInt64(typemax(Int64)) + UInt64(1)),
            :generation_failed => string(typemax(UInt64)),
            :fit_failed => string(UInt64(typemax(Int64))),
            :diagnostic_failed => "0",
        )
        for (status, row_index) in status_rows
            archived = ld1b1_semantics_archived_calibration_member(
                semantics,
                context,
                row_index,
                status,
                data_signature = signature_by_status[status],
            )
            failure_record = status in (
                :generation_failed, :fit_failed, :diagnostic_failed) ?
                ld1b1_semantics_failure_record(
                    context.plan_rows[row_index], status) : nothing
            validation = semantics.ld1b1_validate_calibration_member(
                context,
                row_index,
                archived;
                expected_status = status,
                failure_record,
            )
            @test validation.valid
            @test validation.expected.status === status
            @test validation.summary.n_plan_rows == 1
            @test validation.summary.n_result_rows == 1
            @test validation.summary.n_missing_result_rows == 0
            @test validation.member_sha256 ==
                semantics.ld1b1_normalized_json_sha256(archived)
            if status !== :generation_failed
                expected_signature = parse(
                    UInt64,
                    signature_by_status[status],
                )
                @test validation.expected.simulation_provenance.
                    data_signature === expected_signature
                if status === :completed
                    @test validation.expected.diagnostic_provenance.
                        data_signature === expected_signature
                end
            end
        end

        completed = ld1b1_semantics_archived_calibration_member(
            semantics,
            context,
            eligible_index,
            :completed,
            data_signature = string(typemax(UInt64)),
        )
        local_summary = ld1b1_semantics_local_summary_member(
            context,
            eligible_index,
            data_signature = string(typemax(UInt64)),
        )
        linked = semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                local_summary,
            )
        @test linked.valid
        @test linked.n_pair_evidence == 1
        @test occursin(r"^[0-9a-f]{64}$", linked.pair_evidence_sha256)
        @test occursin(r"^[0-9a-f]{64}$", linked.family_evidence_sha256)
        @test occursin(r"^[0-9a-f]{64}$", linked.global_evidence_sha256)

        native_uint64_completed = ld1b1_semantics_archived_calibration_member(
            semantics,
            context,
            eligible_index,
            :completed,
            data_signature = typemax(UInt64),
        )
        native_uint64_local = ld1b1_semantics_local_summary_member(
            context,
            eligible_index,
            data_signature = typemax(UInt64),
        )
        @test semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            native_uint64_completed;
            expected_status = :completed,
        ).valid
        @test semantics.ld1b1_validate_completed_diagnostic_calibration_link(
            native_uint64_completed,
            native_uint64_local,
        ).valid
        native_projection = semantics.ld1b1_semantic_json_native(
            native_uint64_completed,
        )
        @test native_projection["simulation_provenance"]["data_signature"] ==
            string(typemax(UInt64))
        @test native_projection["diagnostic_provenance"]["data_signature"] ==
            string(typemax(UInt64))

        numeric_json_completed = deepcopy(completed)
        numeric_json_completed["simulation_provenance"]["data_signature"] =
            Int64(1)
        numeric_json_completed["diagnostic_provenance"]["data_signature"] =
            Int64(1)
        @test_throws ArgumentError semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            numeric_json_completed;
            expected_status = :completed,
        )
        numeric_json_local = deepcopy(local_summary)
        numeric_json_local["data_signature"] = Int64(1)
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                numeric_json_local,
            )
        for invalid in (
                "01",
                "not-a-number",
                string(BigInt(typemax(UInt64)) + 1),
            )
            invalid_calibration = deepcopy(completed)
            invalid_calibration["simulation_provenance"][
                "data_signature"] = invalid
            invalid_calibration["diagnostic_provenance"][
                "data_signature"] = invalid
            @test_throws ArgumentError semantics.
                ld1b1_validate_calibration_member(
                    context,
                    eligible_index,
                    invalid_calibration;
                    expected_status = :completed,
                )
            @test_throws ArgumentError semantics.
                ld1b1_validate_completed_diagnostic_calibration_link(
                    invalid_calibration,
                    local_summary,
                )

            invalid_local = deepcopy(local_summary)
            invalid_local["data_signature"] = invalid
            @test_throws ArgumentError semantics.
                ld1b1_validate_completed_diagnostic_calibration_link(
                    completed,
                    invalid_local,
                )
        end

        mismatched_local_signature = deepcopy(local_summary)
        mismatched_local_signature["data_signature"] =
            string(typemax(UInt64) - UInt64(1))
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                mismatched_local_signature,
            )

        mutated_calibration = deepcopy(completed)
        mutated_calibration["pair_evidence"][1][
            "candidate_raw_declared"] = false
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                mutated_calibration,
                local_summary,
            )
        @test_throws ArgumentError semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            mutated_calibration;
            expected_status = :completed,
        )

        mutated_summary = deepcopy(local_summary)
        mutated_summary["pair_rows"][1][
            "posterior_predictive_tail_fraction"] = 0.9
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                mutated_summary,
            )

        mutated_family_calibration = deepcopy(completed)
        mutated_family_calibration["family_evidence"][1][
            "candidate_family_declared"] = false
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                mutated_family_calibration,
                local_summary,
            )

        mutated_family_summary = deepcopy(local_summary)
        mutated_family_summary["family_max_rows"][1][
            "posterior_predictive_tail_fraction"] = 0.9
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                mutated_family_summary,
            )

        extra_family_summary = deepcopy(local_summary)
        push!(extra_family_summary["family_rows"], Dict(
            "family" => "unsupported_extra_family",
            "status" => "not_applicable",
        ))
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                extra_family_summary,
            )

        mutated_global_calibration = deepcopy(completed)
        mutated_global_calibration["global_evidence"][
            "candidate_global_declared"] = false
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                mutated_global_calibration,
                local_summary,
            )

        mutated_global_summary = deepcopy(local_summary)
        mutated_global_summary["global_evidence"][
            "posterior_predictive_tail_fraction"] = 0.9
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                mutated_global_summary,
            )

        mutated_diagnostic_provenance = deepcopy(completed)
        mutated_diagnostic_provenance["diagnostic_provenance"]["status"] =
            "no_eligible_pairs"
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                mutated_diagnostic_provenance,
                local_summary,
            )

        mutated_local_status = deepcopy(local_summary)
        mutated_local_status["status"] = "no_eligible_pairs"
        @test_throws ArgumentError semantics.
            ld1b1_validate_completed_diagnostic_calibration_link(
                completed,
                mutated_local_status,
            )
    end

    @testset "nonterminal artifact failures cannot become terminal rows" begin
        expected_codes = (
            :sampler_diagnostics_unavailable,
            :final_calibration_serialization_failed,
        )
        @test semantics.ld1b1_nonterminal_artifact_failure_codes() ==
            expected_codes
        eligible_index = findfirst(
            row -> row.expected_requested_targets_eligible,
            context.plan_rows,
        )
        plan = context.plan_rows[eligible_index]
        for status in (:generation_failed, :fit_failed, :diagnostic_failed)
            for code in expected_codes
                archived = ld1b1_semantics_archived_calibration_member(
                    semantics,
                    context,
                    eligible_index,
                    status,
                )
                archived["failure_code"] = String(code)
                failure_record = ld1b1_semantics_failure_record(
                    plan,
                    status;
                    error_class = code,
                )
                @test_throws ArgumentError semantics.
                    ld1b1_validate_calibration_member(
                        context,
                        eligible_index,
                        archived;
                        expected_status = status,
                        failure_record,
                    )
            end
        end
    end

    @testset "dynamic provenance field sets are exact" begin
        eligible_index = findfirst(
            row -> row.expected_requested_targets_eligible,
            context.plan_rows,
        )
        completed = ld1b1_semantics_archived_calibration_member(
            semantics,
            context,
            eligible_index,
            :completed,
        )

        extra_simulation_field = deepcopy(completed)
        extra_simulation_field["simulation_provenance"][
            "unexpected_field"] = "not emitted by the public constructor"
        @test_throws ArgumentError semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            extra_simulation_field;
            expected_status = :completed,
        )

        extra_diagnostic_field = deepcopy(completed)
        extra_diagnostic_field["diagnostic_provenance"][
            "unexpected_field"] = "not emitted by the public constructor"
        @test_throws ArgumentError semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            extra_diagnostic_field;
            expected_status = :completed,
        )

        missing_simulation_field = deepcopy(completed)
        pop!(missing_simulation_field["simulation_provenance"], "score_signature")
        @test_throws ArgumentError semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            missing_simulation_field;
            expected_status = :completed,
        )

        missing_diagnostic_field = deepcopy(completed)
        pop!(missing_diagnostic_field["diagnostic_provenance"], "status")
        @test_throws ArgumentError semantics.ld1b1_validate_calibration_member(
            context,
            eligible_index,
            missing_diagnostic_field;
            expected_status = :completed,
        )
    end

    @testset "all formerly unbound plan fields fail closed" begin
        row_index = 1
        plan = context.plan_rows[row_index]
        failure_record = ld1b1_semantics_generation_failure_record(plan)
        canonical = semantics.ld1b1_canonical_generation_failed_row(
            context,
            row_index;
            failure_record,
        )
        pristine = semantics.ld1b1_semantic_json_native(
            canonical.expected,
        )

        mutations = (
            (:profile, member ->
                (member["profile"] = "mutated_calibration_profile")),
            (:planning_profile, member ->
                (member["planning_profile"] = "mutated_planning_profile")),
            (:grid_id, member ->
                (member["grid_id"] = "mutated_grid")),
            (:base_seed, member ->
                (member["base_seed"] += 1)),
            (:component_seeds, member ->
                (member["component_seeds"]["design"] += 1)),
            (:mechanism, member ->
                (member["mechanism"] = "person_testlet")),
            (:magnitude_label, member ->
                (member["magnitude_label"] = "small")),
            (:effect_scale, member ->
                (member["effect_scale"] += 0.125)),
            (:design, member ->
                (member["design"] = "fully_crossed_raters")),
            (:assignment, member ->
                (member["assignment"] = "ability_informed")),
            (:order, member ->
                (member["order"] = "fixed")),
            (:planning_shape, member ->
                (member["planning_shape"]["n_persons"] += 1)),
            (:truth, member ->
                (member["truth"]["target_standard_deviation"] += 0.25)),
        )
        expected_fields = Set((
            :profile,
            :planning_profile,
            :grid_id,
            :base_seed,
            :component_seeds,
            :mechanism,
            :magnitude_label,
            :effect_scale,
            :design,
            :assignment,
            :order,
            :planning_shape,
            :truth,
        ))
        @test Set(first.(mutations)) == expected_fields

        for (field, mutate!) in mutations
            member = deepcopy(pristine)
            mutate!(member)
            @test ld1b1_semantics_changed_top_level_fields(
                pristine,
                member,
            ) == Set((String(field),))
            @test_throws ArgumentError begin
                semantics.ld1b1_validate_generation_failed_member(
                    context,
                    row_index,
                    member;
                    failure_record,
                )
            end
        end
    end
end
