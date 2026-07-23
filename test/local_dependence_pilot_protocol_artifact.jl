using JSON3
using SHA
using Test

if !isdefined(@__MODULE__, :ScientificPayloadDigest)
    include(joinpath(
        @__DIR__,
        "..",
        "scripts",
        "scientific_payload_digest.jl",
    ))
end

const LD1B1ScientificPayloadDigest = ScientificPayloadDigest

function ld1b1_artifact_native(value)
    if value isa AbstractDict
        return Dict(String(key) => ld1b1_artifact_native(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractArray || value isa Tuple
        return [ld1b1_artifact_native(element) for element in value]
    end
    return value
end

function ld1b1_canonical_hash_without_content_hash(value)
    native = ld1b1_artifact_native(value)
    stored = String(native["content_hash"]["value"])
    delete!(native, "content_hash")
    io = IOBuffer()
    write_canonical_json(io, native)
    return (; stored, recomputed = bytes2hex(sha256(take!(io))))
end

function ld1b1_wilson_reference(successes::Int, trials::Int)
    z = 1.959963984540054
    proportion = successes / trials
    z2 = z^2
    denominator = 1 + z2 / trials
    center = (proportion + z2 / (2trials)) / denominator
    half = z * sqrt(
        (proportion * (1 - proportion) + z2 / (4trials)) / trials,
    ) / denominator
    return (lower = max(0.0, center - half),
        upper = min(1.0, center + half))
end

@testset "LD1b1 committed pilot protocol preflight artifact" begin
    root = dirname(@__DIR__)
    fixture_path = joinpath(
        root,
        "test",
        "fixtures",
        "local_dependence_pilot_protocol_preflight.json",
    )
    fixture_text = read(fixture_path, String)
    fixture = JSON3.read(fixture_text)

    @test String(fixture[:schema]) ==
        "bayesianmgmfrm.local_dependence_pilot_protocol_preflight.v1"
    @test String(fixture[:scope]) ==
        "ld1b1_pilot_execution_protocol_preflight_noncalibration"
    @test String(fixture[:status]) == "pilot_protocol_preflight_passed"
    @test String(fixture[:family]) == "mfrm"

    contract = fixture[:pilot_contract]
    @test String(contract[:schema]) ==
        "bayesianmgmfrm.local_dependence_calibration_pilot_contract.v1"
    @test String(contract[:object]) ==
        "local_dependence_calibration_pilot_contract"
    @test String(contract[:profile]) == "ld1b1_pilot_protocol_v1"
    @test String(contract[:status]) == "pilot_protocol_preflight_only"
    planning = contract[:planning]
    @test String(planning[:phase]) == "pilot"
    @test Int(planning[:pilot_repetitions]) == 30
    @test Int.(planning[:evaluation_repetition_candidates]) == [50, 100]
    @test Bool(planning[:evaluation_repetitions_selected_before_evaluation])
    @test !Bool(planning[:mid_evaluation_extension_allowed])
    @test Int(planning[:n_scenarios]) == 22
    @test Int(planning[:n_structurally_eligible_scenarios]) == 18
    @test Int(planning[:n_structural_rejection_scenarios]) == 4
    @test Int(planning[:n_jobs]) == 660
    @test Int(planning[:n_fit_jobs]) == 540
    @test Int(planning[:n_pre_fit_rejection_jobs]) == 120
    @test Bool(planning[:complete_scenario_by_replication_cross_required])

    sampler = contract[:sampler]
    @test String(sampler[:backend]) == "advancedhmc"
    @test String(sampler[:algorithm]) == "nuts"
    @test Int(sampler[:chains]) == 4
    @test Int(sampler[:warmup_per_chain]) == 500
    @test Int(sampler[:draws_per_chain]) == 500
    @test Int(sampler[:total_retained_draws]) == 2_000
    @test Int(sampler[:diagnostic_draws]) == 250
    @test String(sampler[:diagnostic_draw_policy]) ==
        "distinct_without_replacement"
    quality = contract[:quality_requirements]
    @test String(quality[:diagnostic_contract]) ==
        "rank_normalized_rhat_bulk_tail_ess_v1"
    diagnostic_contract_details = quality[:diagnostic_contract_details]
    @test String(diagnostic_contract_details[:id]) ==
        "rank_normalized_rhat_bulk_tail_ess_v1"
    @test String(diagnostic_contract_details[:dependency][:package]) ==
        "MCMCDiagnosticTools"
    @test Int(diagnostic_contract_details[:minimum_independent_chains]) == 2
    @test Int(diagnostic_contract_details[:split_factor]) == 2
    @test String(diagnostic_contract_details[:split_request_field]) ==
        "split_chains_requested"
    @test String(diagnostic_contract_details[:split_applied_field]) ==
        "split_chains"
    @test String(diagnostic_contract_details[:odd_draw_policy]) ==
        "bulk_trim_fold_before_trim_tail_quantile_before_split"
    @test Float64(diagnostic_contract_details[:tail_probability]) == 0.10
    @test String(diagnostic_contract_details[
        :autocovariance_maxlag_policy]) == "all_available_lags"
    @test Int(diagnostic_contract_details[
        :minimum_draws_per_diagnostic_chain_for_ess]) == 5
    @test Bool(diagnostic_contract_details[:sampler_fields][
        :complete_chain_coverage_required])
    @test String(quality[:rhat_method]) == "rank_normalized"
    @test String(quality[:primary_rhat_field]) == "rank_normalized_rhat"
    @test String(quality[:ess_method]) == "bulk_and_tail"
    @test Tuple(String.(quality[:primary_ess_fields])) ==
        ("bulk_ess", "tail_ess")
    @test String(quality[:primary_flag_field]) == "rank_normalized_flag"
    @test Float64(quality[:tail_probability]) == 0.10
    @test Float64(quality[:maximum_rhat]) == 1.01
    @test Int(quality[:minimum_bulk_ess]) == 400
    @test Int(quality[:minimum_tail_ess]) == 400
    @test Int(quality[:maximum_divergences]) == 0
    @test Int(quality[:maximum_depth_hits]) == 0
    @test String(quality[:e_bfmi_field]) == "e_bfmi"
    @test String(quality[:e_bfmi_completeness_field]) ==
        "e_bfmi_complete"
    @test Bool(quality[:e_bfmi_chain_coverage_required])

    operational = contract[:operational_requirements]
    @test Int(operational[:minimum_completed_per_eligible_scenario]) == 27
    @test Int(operational[
        :maximum_categorized_failures_per_eligible_scenario]) == 3
    @test Tuple(String.(operational[:categorized_failure_statuses])) == (
        "generation_failed",
        "fit_failed",
        "diagnostic_failed",
    )
    @test Int(operational[:required_missing_results]) == 0
    @test Int(operational[
        :required_pre_fit_rejections_per_rejection_scenario]) == 30
    @test Int(operational[:primary_attempt]) == 1
    @test !Bool(operational[:primary_outcomes_overwritable_by_retries])
    @test String(operational[:retry_role]) ==
        "separate_remediation_record_only"

    precision_policy = contract[:precision_policy]
    @test String(precision_policy[:method]) == "wilson_score"
    @test Float64(precision_policy[:confidence]) == 0.95
    @test String(precision_policy[:applies_to]) ==
        "replication_level_binary_rates_only"
    @test Float64(precision_policy[:pilot_maximum_half_width]) == 0.18
    @test Float64(precision_policy[:evaluation_target_half_width]) == 0.10
    @test !Bool(precision_policy[:pooled_pair_interval_available])

    resource_policy = contract[:resource_policy]
    expected = resource_policy[:expected_totals]
    caps = resource_policy[:total_caps]
    per_dataset_caps = resource_policy[:per_dataset_caps]
    @test Bool(resource_policy[:positive_total_headroom_required])
    @test Int(expected[:n_jobs]) == 660 < Int(caps[:n_jobs]) == 700
    @test Int(expected[:n_fit_jobs]) == 540 <
        Int(caps[:n_fit_jobs]) == 600
    for field in (:n_ratings, :n_probability_cells, :n_truth_cells)
        @test 0 < Int(expected[field]) < Int(caps[field])
        @test Int(per_dataset_caps[field]) > 0
    end

    preflight = fixture[:pilot_preflight]
    @test String(preflight[:schema]) ==
        "bayesianmgmfrm.local_dependence_calibration_pilot_preflight.v1"
    @test String(preflight[:object]) ==
        "local_dependence_calibration_pilot_preflight"
    @test String(preflight[:status]) == "pilot_plan_preflight_passed"
    @test isequal(
        ld1b1_artifact_native(preflight[:contract]),
        ld1b1_artifact_native(contract),
    )
    @test String(preflight[:phase]) == "pilot"
    @test Int(preflight[:n_plan_rows]) == 660
    @test Int(preflight[:n_scenarios]) == 22
    @test Int(preflight[:n_replications]) == 30
    @test Int(preflight[:n_fit_jobs]) == 540
    @test Int(preflight[:n_pre_fit_rejection_jobs]) == 120
    @test isnothing(preflight[:evaluation_repetitions_selected])
    @test String(preflight[:evaluation_repetition_selection_status]) ==
        "pending_pilot_results"

    jobs = preflight[:job_rows]
    @test length(jobs) == 660
    @test [Int(row[:row_index]) for row in jobs] == collect(1:660)
    @test count(row -> String(row[:expected_action]) ==
        "fit_and_score_diagnostic", jobs) == 540
    @test count(row -> String(row[:expected_action]) ==
        "pre_fit_reject", jobs) == 120
    @test all(row -> Bool(row[:expected_structural_eligibility]) ==
        (String(row[:expected_action]) == "fit_and_score_diagnostic"), jobs)
    @test all(row -> String(row[:phase]) == "pilot", jobs)
    @test all(row -> Int(row[:primary_attempt]) == 1, jobs)
    @test all(row -> !Bool(
        row[:primary_outcome_overwritable_by_retries]), jobs)
    @test all(row -> String(row[:execution_status]) == "not_executed", jobs)
    @test Set(Int(row[:replication]) for row in jobs) == Set(1:30)
    @test all(replication -> count(row ->
        Int(row[:replication]) == replication, jobs) == 22, 1:30)
    @test all(replication -> count(row ->
        Int(row[:replication]) == replication &&
        String(row[:expected_action]) == "fit_and_score_diagnostic",
        jobs) == 18, 1:30)
    @test all(replication -> count(row ->
        Int(row[:replication]) == replication &&
        String(row[:expected_action]) == "pre_fit_reject",
        jobs) == 4, 1:30)
    @test length(unique(String(row[:scenario_id]) for row in jobs)) == 22
    @test all(scenario -> count(row ->
        String(row[:scenario_id]) == scenario, jobs) == 30,
        unique(String(row[:scenario_id]) for row in jobs))

    root_seeds = Int[row[:seed] for row in jobs]
    fit_seeds = Int[row[:fit_seed] for row in jobs]
    draw_seeds = Int[row[:draw_selection_seed] for row in jobs]
    predictive_seeds = Int[row[:posterior_predictive_seed] for row in jobs]
    @test length(unique(root_seeds)) == 30
    @test length(unique(fit_seeds)) == 660
    @test length(unique(draw_seeds)) == 660
    @test length(unique(predictive_seeds)) == 660
    @test length(unique(vcat(fit_seeds, draw_seeds, predictive_seeds))) ==
        1_980
    @test all(row -> length(unique(Int[
        row[:fit_seed],
        row[:draw_selection_seed],
        row[:posterior_predictive_seed],
    ])) == 3, jobs)

    resource = preflight[:resource_summary]
    actual = resource[:actual]
    @test Int(actual[:n_jobs]) == length(jobs)
    @test Int(actual[:n_fit_jobs]) == 540
    @test Int(actual[:n_pre_fit_rejection_jobs]) == 120
    for field in (:n_ratings, :n_probability_cells, :n_truth_cells)
        @test Int(actual[field]) == sum(
            Int(row[:resources][field]) for row in jobs)
        @test Int(actual[field]) == Int(expected[field])
        @test Int(resource[:maxima][field]) == maximum(
            Int(row[:resources][field]) for row in jobs)
        @test Int(resource[:maxima][field]) <=
            Int(resource[:per_dataset_caps][field])
        @test Int(actual[field]) < Int(resource[:caps][field])
    end
    @test all(Bool(value) for value in values(resource[:checks]))
    @test all(Bool(value) for value in values(preflight[:plan_checks]))
    seed_checks = preflight[:seed_checks]
    for field in (
            :pilot_root_unique_by_replication,
            :scenario_specific_execution_seeds,
            :pilot_execution_seed_values_unique,
            :root_namespaces_disjoint,
            :component_namespaces_disjoint,
            :execution_namespaces_disjoint,
            :passed,
        )
        @test Bool(seed_checks[field])
    end
    @test Int(seed_checks[:n_unique_pilot_root_seeds]) == 30
    @test Int(seed_checks[:n_unique_pilot_execution_seed_values]) == 1_980
    @test Int(seed_checks[:n_evaluation_replications_checked]) == 100

    reservation = fixture[:evaluation_namespace_reservation]
    @test String(reservation[:phase]) == "evaluation"
    @test Int(reservation[:initial_repetitions]) == 50
    @test Int(reservation[:maximum_repetitions]) == 100
    @test Int(reservation[:initial_plan_rows]) == 1_100
    @test Int(reservation[:maximum_plan_rows]) == 2_200
    initial_seeds = reservation[:initial_replication_seeds]
    maximum_seeds = reservation[:maximum_replication_seeds]
    @test length(initial_seeds) == 50
    @test length(maximum_seeds) == 100
    @test [Int(row[:replication]) for row in initial_seeds] == collect(1:50)
    @test [Int(row[:replication]) for row in maximum_seeds] == collect(1:100)
    @test [Int(row[:seed]) for row in initial_seeds] ==
        [Int(row[:seed]) for row in maximum_seeds[1:50]]
    @test isempty(intersect(
        Set(root_seeds),
        Set(Int(row[:seed]) for row in maximum_seeds),
    ))
    @test Bool(reservation[:initial_is_prefix_of_maximum])
    @test Bool(reservation[:seed_namespace_reserved])
    for field in (:generated_data, :model_fit_run, :mcmc_run, :diagnostic_run)
        @test !Bool(reservation[field])
    end

    precision = fixture[:precision_reference]
    @test Int.(getindex.(precision, :replications)) == [30, 50, 100]
    @test String.(getindex.(precision, :role)) ==
        ["pilot", "evaluation_candidate", "evaluation_candidate"]
    for row in precision
        n = Int(row[:replications])
        successes = Int(row[:worst_case_successes])
        reference = ld1b1_wilson_reference(successes, n)
        @test successes == fld(n, 2)
        @test Float64(row[:estimate]) == successes / n
        @test Float64(row[:lower]) ≈ reference.lower
        @test Float64(row[:upper]) ≈ reference.upper
        @test Float64(row[:half_width]) ≈
            (reference.upper - reference.lower) / 2
    end
    @test Bool(precision[1][:precision_requirement_met])
    @test !Bool(precision[2][:precision_requirement_met])
    @test Bool(precision[3][:precision_requirement_met])
    @test Float64(precision[1][:maximum_half_width]) == 0.18
    @test all(Float64(row[:maximum_half_width]) == 0.10
        for row in precision[2:3])

    capability = preflight[:sampler_capability]
    @test String(capability[:current_rhat_method]) == "rank_normalized"
    @test String(capability[:current_ess_method]) == "bulk_and_tail"
    @test String(capability[:current_rhat_ess_status]) ==
        "rank_normalized_available"
    @test String(capability[:current_diagnostic_contract]) ==
        "rank_normalized_rhat_bulk_tail_ess_v1"
    @test String(capability[:required_diagnostic_contract]) ==
        "rank_normalized_rhat_bulk_tail_ess_v1"
    @test isequal(
        ld1b1_artifact_native(
            capability[:current_diagnostic_contract_details]),
        ld1b1_artifact_native(
            capability[:required_diagnostic_contract_details]),
    )
    @test isequal(
        ld1b1_artifact_native(
            capability[:current_diagnostic_contract_details]),
        ld1b1_artifact_native(diagnostic_contract_details),
    )
    @test Bool(capability[:rank_normalized_rhat_available])
    @test Bool(capability[:bulk_tail_ess_available])
    @test String(capability[:required_rhat_method]) == "rank_normalized"
    @test String(capability[:required_ess_method]) == "bulk_and_tail"
    @test Bool(capability[:rhat_method_matches_requirement])
    @test Bool(capability[:ess_method_matches_requirement])
    @test Bool(capability[:diagnostic_contract_matches_requirement])
    @test Bool(capability[:diagnostic_contract_details_match_requirement])
    @test Bool(capability[:primary_fields_match_requirement])
    @test Bool(capability[:tail_probability_matches_requirement])
    @test Bool(capability[:e_bfmi_contract_matches_requirement])
    @test Int(capability[:minimum_independent_chains]) == 2
    @test Int(capability[:planned_independent_chains]) == 4
    @test Bool(capability[:independent_chain_requirement_met])
    @test Int(capability[:minimum_draws_per_diagnostic_chain]) == 5
    @test Int(capability[:planned_draws_per_diagnostic_chain]) == 250
    @test Bool(capability[:diagnostic_draw_requirement_met])
    @test Bool(capability[:requirement_met])
    @test isempty(capability[:blockers])
    @test isempty(preflight[:capability_blockers])
    boundary = fixture[:capability_boundary]
    @test String(boundary[:diagnostic_contract]) ==
        "rank_normalized_rhat_bulk_tail_ess_v1"
    @test isequal(
        ld1b1_artifact_native(boundary[:diagnostic_contract_details]),
        ld1b1_artifact_native(diagnostic_contract_details),
    )
    for field in (
            :rank_normalized_rhat,
            :bulk_ess,
            :tail_ess,
            :exact_diagnostic_contract,
            :primary_diagnostic_fields,
            :tail_probability,
            :independent_chain_minimum,
            :diagnostic_draw_minimum,
            :complete_chain_e_bfmi,
        )
        @test Bool(boundary[:required_capabilities][field])
    end
    @test isempty(boundary[:blockers])
    @test Bool(boundary[:pilot_execution_authorized])

    execution = fixture[:execution_scope]
    @test Int(execution[:n_planned_jobs]) == 660
    @test Int(execution[:n_fit_jobs]) == 540
    @test Int(execution[:n_pre_fit_rejection_jobs]) == 120
    for field in (
            :generates_response_data,
            :runs_design_preflight,
            :runs_model_fit,
            :runs_mcmc,
            :runs_local_dependence_summary,
            :stores_performance_rates,
            :stores_mechanism_classifications,
        )
        @test !Bool(execution[field])
    end
    evidence = fixture[:evidence_status]
    @test Bool(evidence[:pilot_execution_authorized])
    for field in (
            :pilot_execution_completed,
            :evaluation_profile_frozen,
            :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible,
        )
        @test !Bool(evidence[field])
    end
    @test isnothing(evidence[:evaluation_repetitions_selected])
    @test Bool(preflight[:pilot_execution_authorized])
    for field in (
            :pilot_execution_completed,
            :evaluation_profile_frozen,
            :repeated_calibration_completed,
            :calibration_evidence_available,
            :diagnostic_decision_labels_available,
            :mechanism_interpretation_eligible,
        )
        @test !Bool(preflight[field])
    end

    for section in values(fixture[:checks])
        @test all(Bool(value) for value in values(section))
    end
    summary = fixture[:summary]
    @test Bool(summary[:passed])
    @test Int(summary[:n_planned_jobs]) == 660
    @test Int(summary[:n_fit_jobs]) == 540
    @test Int(summary[:n_pre_fit_rejection_jobs]) == 120
    @test Int(summary[:initial_evaluation_repetitions]) == 50
    @test Int(summary[:maximum_evaluation_repetitions]) == 100
    @test !Bool(summary[:runs_mcmc])
    @test Bool(summary[:pilot_execution_authorized])
    @test !Bool(summary[:pilot_execution_completed])
    @test !Bool(summary[:evaluation_profile_frozen])
    @test !Bool(summary[:calibration_evidence_available])
    @test !Bool(summary[:diagnostic_decision_labels_available])
    @test !Bool(summary[:mechanism_interpretation_eligible])

    dependencies = fixture[:dependencies]
    @test length(dependencies) == 2
    dependency_paths = Dict(
        "local_dependence_known_truth_preflight" =>
            "test/fixtures/local_dependence_known_truth_preflight.json",
        "local_dependence_calibration_scorer_preflight" =>
            "test/fixtures/local_dependence_calibration_scorer_preflight.json",
    )
    for row in dependencies
        artifact = String(row[:artifact])
        relative = dependency_paths[artifact]
        path = joinpath(root, relative)
        @test String(row[:path]) == relative
        @test String(row[:file_sha256]) == bytes2hex(open(sha256, path))
        dependency = JSON3.read(read(path, String))
        @test String(row[:expected_schema]) == String(dependency[:schema])
        @test String(row[:content_hash][:algorithm]) == "sha256"
        @test Bool(row[:content_hash][:verified])
        @test String(row[:content_hash][:value]) ==
            String(dependency[:content_hash][:value])
        dependency_hash =
            ld1b1_canonical_hash_without_content_hash(dependency)
        @test dependency_hash.stored == dependency_hash.recomputed
    end

    generator = fixture[:generator]
    for (field, relative_path) in (
            (:script_source_sha256,
                "scripts/generate_local_dependence_pilot_protocol_preflight.jl"),
            (:pilot_source_sha256,
                "src/local_dependence_calibration_pilot.jl"),
            (:diagnostic_source_sha256,
                "src/bayesian_fit.jl"),
            (:calibration_source_sha256,
                "src/local_dependence_calibration.jl"),
            (:simulation_source_sha256,
                "src/local_dependence_simulation.jl"),
        )
        recorded_sha256 = String(generator[field])
        current_sha256 =
            bytes2hex(open(sha256, joinpath(root, relative_path)))
        integrity = LD1B1ScientificPayloadDigest.reference_integrity_status(
            recorded_sha256,
            current_sha256;
            reference_kind = :code_doc,
            strict = false,
        )
        @test integrity.provenance_policy_accepted
        @test integrity.status in (:exact_file_match, :provenance_drift)
        @test !integrity.scientific_equivalence_verified
        @test integrity.archive_refresh_required ==
            (integrity.status === :provenance_drift)
        strict_integrity =
            LD1B1ScientificPayloadDigest.reference_integrity_status(
                recorded_sha256,
                current_sha256;
                reference_kind = :code_doc,
                strict = true,
            )
        @test strict_integrity.provenance_policy_accepted ==
            strict_integrity.exact_file_sha256_verified
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
    @test !haskey(fixture, :performance_rates)
    @test !haskey(fixture, :mechanism_classifications)

    artifact_hash = ld1b1_canonical_hash_without_content_hash(fixture)
    @test artifact_hash.stored == artifact_hash.recomputed
end
