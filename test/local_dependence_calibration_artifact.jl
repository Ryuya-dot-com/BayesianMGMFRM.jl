function ld1b0_artifact_native(value)
    if value isa AbstractDict
        return Dict(String(key) => ld1b0_artifact_native(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractArray || value isa Tuple
        return [ld1b0_artifact_native(element) for element in value]
    end
    return value
end

@testset "LD1b0 committed calibration scorer preflight artifact" begin
    root = dirname(@__DIR__)
    fixture_path = joinpath(
        root,
        "test",
        "fixtures",
        "local_dependence_calibration_scorer_preflight.json",
    )
    fixture_text = read(fixture_path, String)
    fixture = JSON3.read(fixture_text)

    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.local_dependence_calibration_scorer_preflight.v1"
    @test String(fixture[:scope]) ==
        "ld1b0_calibration_scorer_protocol_preflight"
    @test String(fixture[:status]) == "scorer_protocol_preflight_passed"

    execution = fixture[:execution_scope]
    @test Int(execution[:n_planned_rows]) == 22
    @test Int(execution[:n_structurally_eligible_rows]) == 18
    @test Int(execution[:n_pre_fit_rejection_rows]) == 4
    @test Int(execution[:n_completed_diagnostic_rows]) == 0
    @test Bool(execution[:runs_known_truth_generation])
    @test Bool(execution[:runs_design_preflight])
    @test !Bool(execution[:runs_model_fit])
    @test !Bool(execution[:runs_mcmc])
    @test !Bool(execution[:runs_local_dependence_summary])
    @test !Bool(execution[:calibration_completed])

    contract = fixture[:protocol_contract]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.local_dependence_calibration_contract.v1"
    @test String(contract[:status]) == "protocol_preflight_only"
    @test String(contract[:monte_carlo_interval][:method]) == "wilson_score"
    @test String(contract[:monte_carlo_interval][:applies_to]) ==
        "replication_level_binary_rates_only"
    @test !Bool(contract[:target_evidence_available])
    @test !Bool(contract[:pair_truth_oracle_available])
    @test !Bool(contract[:pairwise_power_available])
    @test !Bool(contract[:repeated_calibration_completed])
    @test !Bool(contract[:calibration_evidence_available])
    @test !Bool(contract[:diagnostic_decision_labels_available])
    @test !Bool(contract[:mechanism_interpretation_eligible])

    planning_rows = fixture[:planning_rows]
    rejected_rows = fixture[:pre_fit_rejection_rows]
    @test length(planning_rows) == 22
    @test count(row -> Bool(row[:expected_structural_eligibility]),
        planning_rows) == 18
    @test length(rejected_rows) == 4
    @test all(row -> String(row[:status]) == "pre_fit_rejected",
        rejected_rows)
    @test all(row -> !Bool(row[:expected_structural_eligibility]),
        rejected_rows)
    @test all(row -> Int(row[:n_pair_evidence]) == 0, rejected_rows)
    @test all(row -> !isempty(String(
            row[:simulation_provenance][:data_signature])), rejected_rows)
    @test all(row -> !Bool(row[:calibration_evidence_available]) &&
        !Bool(row[:diagnostic_decision_labels_available]) &&
        !Bool(row[:mechanism_interpretation_eligible]), rejected_rows)

    scorer = fixture[:scorer_summary]
    @test Int(scorer[:n_plan_rows]) == 22
    @test Int(scorer[:n_result_rows]) == 4
    @test Int(scorer[:n_missing_result_rows]) == 18
    @test Int(scorer[:n_pair_evidence_rows]) == 0
    @test length(scorer[:scenario_rows]) == 22
    @test length(scorer[:family_rows]) == 66
    @test length(scorer[:global_rows]) == 22
    @test length(scorer[:matched_set_rows]) == 8
    status_counts = Dict(String(row[:status]) => Int(row[:n])
        for row in scorer[:status_rows])
    @test status_counts["completed"] == 0
    @test status_counts["pre_fit_rejected"] == 4
    @test status_counts["generation_failed"] == 0
    @test status_counts["fit_failed"] == 0
    @test status_counts["diagnostic_failed"] == 0
    @test all(row -> !Bool(row[:pooled_pair_raw][
            :wilson_interval_available]) &&
        !Bool(row[:pooled_pair_bh][:wilson_interval_available]),
        scorer[:scenario_rows])
    @test all(row -> !Bool(row[:pooled_pair_wilson_interval_available]),
        scorer[:family_rows])

    for section in (fixture[:checks][:contract], fixture[:checks][:scorer])
        @test all(Bool(value) for value in values(section))
    end
    evidence = fixture[:evidence_status]
    for field in (
            :target_evidence_available,
            :pair_truth_oracle_available,
            :pairwise_power_available,
            :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible,
        )
        @test !Bool(evidence[field])
    end

    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_planned_rows]) == 22
    @test Int(summary[:n_structurally_eligible_rows]) == 18
    @test Int(summary[:n_pre_fit_rejection_rows]) == 4
    @test !Bool(summary[:runs_mcmc])
    @test !Bool(summary[:calibration_completed])
    @test !Bool(summary[:calibration_evidence_available])
    @test !Bool(summary[:diagnostic_decision_labels_available])
    @test !Bool(summary[:mechanism_interpretation_eligible])
    @test String(summary[:subsequent_stage]) ==
        "ld1b_pilot_then_frozen_evaluation"

    generator = fixture[:generator]
    for (field, relative_path) in (
            (:script_source_sha256,
                "scripts/generate_local_dependence_calibration_scorer_preflight.jl"),
            (:calibration_source_sha256,
                "src/local_dependence_calibration.jl"),
            (:calibration_test_sha256,
                "test/local_dependence_calibration.jl"),
            (:known_truth_source_sha256,
                "src/local_dependence_known_truth_dgp.jl"),
            (:adapter_source_sha256,
                "src/local_dependence_simulation.jl"),
        )
        @test String(generator[field]) ==
            bytes2hex(open(sha256, joinpath(root, relative_path)))
    end
    @test !occursin(root, fixture_text)
    for token in (
            "internal",
            "public_claim_allowed",
            "public_claim_release_allowed",
            "next_gate",
        )
        @test !occursin(token, fixture_text)
    end

    native = ld1b0_artifact_native(fixture)
    stored_hash = String(native["content_hash"]["value"])
    delete!(native, "content_hash")
    io = IOBuffer()
    write_canonical_json(io, native)
    @test stored_hash == bytes2hex(sha256(take!(io)))
end
