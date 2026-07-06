#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_fit_threshold_q_heldout_linkage.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_fit_metric_threshold_sensitivity,
        path =
            "test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_fit_metric_threshold_sensitivity.v1"),
    (name = :mgmfrm_empirical_q_matrix_recovery_simulation_grid,
        path =
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1"),
    (name = :mgmfrm_heldout_prediction_simulation_grid,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_simulation_grid.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_fold1_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_fold1_scoring.v1"),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_fit_threshold_q_heldout_linkage_v1",
    review_kind = :local_fit_threshold_q_heldout_linkage,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    decision_target =
        :connect_threshold_profiles_q_diagnostics_and_fold1_heldout_scores,
    linkage_scope =
        :fixed_q_confirmatory_mgmfrm_candidate_diagnostic_linkage,
    thresholds = (;
        require_fit_metric_threshold_sensitivity_passed = true,
        require_empirical_q_matrix_recovery_simulation_grid_passed = true,
        require_heldout_prediction_simulation_grid_passed = true,
        require_fold1_scoring_passed = true,
        require_all_scenario_link_rows_recorded = true,
        require_threshold_profile_link_rows_recorded = true,
        require_q_recovery_link_rows_recorded = true,
        require_parameter_absorption_rows_recorded = true,
        require_fold1_observed_rank_recorded = true,
        require_observed_vs_expected_rank_match_recorded = true,
        require_any_observed_expected_mismatch_flagged = true,
        require_anchor_limitations_recorded = true,
        require_no_single_threshold_profile_promoted = true,
        require_no_automatic_q_revision = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const SCENARIO_Q_LINKS = Dict(
    :well_specified_current_q => (;
        q_recovery_scenario = :well_separated_true_q_retained,
        q_risk = :false_positive_complexity_possible_in_fold1_pilot,
        threshold_regime = :balanced_reference,
        threshold_candidate_scenario =
            :extra_loading_candidate_cv_supported_manual_gate,
    ),
    :missing_loading_revised_q => (;
        q_recovery_scenario = :missing_loading_recovered_as_candidate,
        q_risk = :missing_loading_candidate_construct_review_needed,
        threshold_regime = :item3_secondary_dimension_signal,
        threshold_candidate_scenario =
            :missing_loading_candidate_cv_supported_manual_gate,
    ),
    :sparse_signal_current_q => (;
        q_recovery_scenario = :sparse_isolated_attribute_design_retained,
        q_risk = :sparse_dimension_support_can_shift_elpd_and_mae,
        threshold_regime = :balanced_reference,
        threshold_candidate_scenario =
            :extra_loading_candidate_cv_supported_manual_gate,
    ),
    :rater_method_noise => (;
        q_recovery_scenario =
            :rater_consistency_noise_false_positive_manual_only,
        q_risk = :rater_method_noise_can_mimic_q_signal,
        threshold_regime = :rater_method_noise,
        threshold_candidate_scenario =
            :missing_loading_candidate_cv_supported_manual_gate,
    ),
    :weak_dimension_ambiguous => (;
        q_recovery_scenario = :weak_dimension_design_deferred,
        q_risk = :weak_dimension_requires_construct_or_full_batch_followup,
        threshold_regime = :item3_secondary_dimension_signal,
        threshold_candidate_scenario =
            :extra_loading_candidate_cv_supported_manual_gate,
    ),
)

function usage()
    return """
    Generate the local MGMFRM fit-threshold/Q/heldout linkage artifact.

    This artifact links literature-motivated threshold profiles, empirical
    Q-matrix recovery diagnostics, heldout-prediction simulation expectations,
    and observed fold1 heldout scoring rows. It records where fold1 pilot
    rankings match or differ from the predeclared simulation expectation and
    keeps public fit, Q-revision, model-weight, and sparse-superiority claims
    blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_fit_threshold_q_heldout_linkage.jl [--output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return output
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
fixture_path(path::AbstractString) = normpath(joinpath(ROOT, path))

as_string(value) = String(value)
as_symbol(value) = Symbol(String(value))
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_fit_metric_threshold_sensitivity && return (;
        passed = as_bool(summary[:passed]),
        threshold_profiles_change_at_least_one_flag =
            as_bool(summary[:threshold_profiles_change_at_least_one_flag]),
        n_threshold_profiles = as_int(summary[:n_threshold_profiles]),
        n_metric_comparison_rows = as_int(summary[:n_metric_comparison_rows]),
        n_parameter_shift_rows = as_int(summary[:n_parameter_shift_rows]),
        no_single_threshold_profile_promoted =
            as_bool(summary[:no_single_threshold_profile_promoted]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
    )
    name === :mgmfrm_empirical_q_matrix_recovery_simulation_grid && return (;
        passed = as_bool(summary[:passed]),
        n_scenarios = as_int(summary[:n_scenarios]),
        n_candidate_exact_recoveries =
            as_int(summary[:n_candidate_exact_recoveries]),
        n_false_candidate_scenarios =
            as_int(summary[:n_false_candidate_scenarios]),
        n_deferred_scenarios = as_int(summary[:n_deferred_scenarios]),
        false_public_promotion_rate =
            as_float(summary[:false_public_promotion_rate]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        no_public_recovery_claim =
            as_bool(summary[:no_public_recovery_claim]),
    )
    name === :mgmfrm_heldout_prediction_simulation_grid && return (;
        passed = as_bool(summary[:passed]),
        n_scenarios = as_int(summary[:n_scenarios]),
        n_threshold_impact_rows =
            as_int(summary[:n_threshold_impact_rows]),
        n_rank_unstable_scenarios =
            as_int(summary[:n_rank_unstable_scenarios]),
        no_public_model_weight_claim =
            as_bool(summary[:no_public_model_weight_claim]),
        no_sparse_superiority_claim =
            as_bool(summary[:no_sparse_superiority_claim]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_fold1_scoring && return (;
        passed = as_bool(summary[:passed]),
        fold1_heldout_predictive_scores_computed =
            as_bool(summary[:fold1_heldout_predictive_scores_computed]),
        full_125_unit_batch_completed =
            as_bool(summary[:full_125_unit_batch_completed]),
        comparison_anchor_scores_computed =
            as_bool(summary[:comparison_anchor_scores_computed]),
        n_candidate_score_rows = as_int(summary[:n_candidate_score_rows]),
        n_candidate_rank_rows = as_int(summary[:n_candidate_rank_rows]),
        total_heldout_elpd = as_float(summary[:total_heldout_elpd]),
        n_blockers = as_int(summary[:n_blockers]),
        no_public_model_weight_claim =
            as_bool(summary[:no_public_model_weight_claim]),
        no_sparse_superiority_claim =
            as_bool(summary[:no_sparse_superiority_claim]),
    )
    return (; passed = as_bool(summary[:passed]))
end

function artifact_record(spec)
    path = fixture_path(spec.path)
    exists = isfile(path)
    if !exists
        return (;
            artifact = spec.name,
            path = spec.path,
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema = spec.expected_schema,
            schema_matches = false,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    fixture = JSON3.read(read(path, String))
    schema = as_string(fixture[:schema])
    summary = artifact_summary(spec.name, fixture[:summary])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = spec.expected_schema,
        schema_matches = schema == spec.expected_schema,
        summary_passed = summary.passed,
        summary,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

load_fixture(path::AbstractString) = JSON3.read(read(fixture_path(path), String))

function rows_by_symbol(rows, key::Symbol)
    result = Dict{Symbol, Any}()
    for row in rows
        result[as_symbol(row[key])] = row
    end
    return result
end

function rank_rows_by_scenario(rows)
    result = Dict{Symbol, Vector{Any}}()
    for row in rows
        scenario = as_symbol(row[:scenario])
        push!(get!(result, scenario, Any[]), row)
    end
    for rows_for_scenario in values(result)
        sort!(rows_for_scenario; by = row -> as_int(row[:rank]))
    end
    return result
end

function best_mae_row(rows)
    return first(sort(collect(rows); by = row -> as_float(row[:heldout_expected_score_mae])))
end

function threshold_row(metric_rows, scenario::Symbol, regime::Symbol)
    matches = [
        row for row in metric_rows
        if as_symbol(row[:scenario]) == scenario &&
            as_symbol(row[:regime]) == regime
    ]
    isempty(matches) && return nothing
    return first(matches)
end

function q_row(q_rows, scenario::Symbol)
    matches = [row for row in q_rows if as_symbol(row[:scenario]) == scenario]
    isempty(matches) && return nothing
    return first(matches)
end

function threshold_impact_rows(rows, scenario::Symbol)
    return [
        row for row in rows
        if as_symbol(row[:scenario]) == scenario
    ]
end

function scenario_link_rows(heldout_sim, fold1, fit_threshold, q_grid)
    scenario_rows = heldout_sim[:scenario_rows]
    scenario_by_name = rows_by_symbol(scenario_rows, :scenario)
    ranks_by_scenario = rank_rows_by_scenario(fold1[:candidate_rank_rows])
    q_rows = q_grid[:scenario_rows]
    metric_rows = fit_threshold[:metric_comparison_rows]

    rows = Any[]
    for scenario in sort(collect(keys(scenario_by_name)); by = string)
        expected = scenario_by_name[scenario]
        q_link = SCENARIO_Q_LINKS[scenario]
        ranks = get(ranks_by_scenario, scenario, Any[])
        best_elpd = isempty(ranks) ? nothing : first(ranks)
        best_mae = isempty(ranks) ? nothing : best_mae_row(ranks)
        expected_model = as_symbol(expected[:expected_best_model])
        observed_best_model =
            best_elpd === nothing ? missing : as_symbol(best_elpd[:model])
        expected_model_scored_fold1 =
            any(as_symbol(row[:model]) == expected_model for row in ranks)
        observed_matches_expected =
            expected_model_scored_fold1 && observed_best_model == expected_model
        q_evidence = q_row(q_rows, q_link.q_recovery_scenario)
        threshold_evidence = threshold_row(metric_rows,
            q_link.threshold_candidate_scenario, q_link.threshold_regime)
        push!(rows, (;
            scenario,
            expected_best_model = expected_model,
            observed_fold1_best_model = observed_best_model,
            observed_best_matches_expected = observed_matches_expected,
            expected_model_scored_fold1,
            observed_fold1_best_elpd =
                best_elpd === nothing ? missing : as_float(best_elpd[:heldout_elpd]),
            observed_fold1_best_delta_elpd_from_best =
                best_elpd === nothing ? missing :
                as_float(best_elpd[:delta_elpd_from_best]),
            observed_fold1_best_mae_model =
                best_mae === nothing ? missing : as_symbol(best_mae[:model]),
            observed_fold1_best_mae =
                best_mae === nothing ? missing :
                as_float(best_mae[:heldout_expected_score_mae]),
            q_recovery_scenario = q_link.q_recovery_scenario,
            q_action = q_evidence === nothing ? missing :
                as_symbol(q_evidence[:action]),
            q_candidate_exact_recovery = q_evidence === nothing ? missing :
                as_bool(q_evidence[:candidate_exact_recovery]),
            q_false_candidate = q_evidence === nothing ? missing :
                as_bool(q_evidence[:false_candidate]),
            q_public_recovery_allowed = q_evidence === nothing ? missing :
                as_bool(q_evidence[:public_recovery_allowed]),
            q_risk = q_link.q_risk,
            threshold_regime = q_link.threshold_regime,
            threshold_candidate_scenario = q_link.threshold_candidate_scenario,
            delta_elpd_waic = threshold_evidence === nothing ? missing :
                as_float(threshold_evidence[:delta_elpd_waic]),
            delta_elpd_loo = threshold_evidence === nothing ? missing :
                as_float(threshold_evidence[:delta_elpd_loo]),
            max_abs_common_direct_parameter_shift =
                threshold_evidence === nothing ? missing :
                as_float(threshold_evidence[:max_abs_common_direct_parameter_shift]),
            threshold_profile_sensitive =
                as_bool(expected[:threshold_profile_sensitive]),
            expected_rank_stable = as_bool(expected[:expected_rank_stable]),
            external_construct_validation_needed =
                as_bool(expected[:external_construct_validation_needed]),
            interpretation =
                observed_matches_expected ?
                :fold1_pilot_matches_predeclared_expected_best :
                :fold1_pilot_differs_or_expected_anchor_not_scored,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function threshold_profile_link_rows(heldout_sim, scenario_rows)
    scenario_by_name = Dict(row.scenario => row for row in scenario_rows)
    rows = Any[]
    for row in heldout_sim[:threshold_impact_rows]
        scenario = as_symbol(row[:scenario])
        link = scenario_by_name[scenario]
        push!(rows, (;
            scenario,
            threshold_profile = as_symbol(row[:threshold_profile]),
            ranking_stable_under_profile =
                as_bool(row[:ranking_stable_under_profile]),
            threshold_profile_sensitive =
                as_bool(row[:threshold_profile_sensitive]),
            observed_best_matches_expected =
                link.observed_best_matches_expected,
            expected_model_scored_fold1 = link.expected_model_scored_fold1,
            claim_decision = as_symbol(row[:claim_decision]),
            public_claim_allowed = false,
        ))
    end
    return rows
end

function q_recovery_link_rows(scenario_rows)
    return [
        (;
            scenario = row.scenario,
            q_recovery_scenario = row.q_recovery_scenario,
            q_action = row.q_action,
            q_candidate_exact_recovery = row.q_candidate_exact_recovery,
            q_false_candidate = row.q_false_candidate,
            q_public_recovery_allowed = row.q_public_recovery_allowed,
            observed_fold1_best_model = row.observed_fold1_best_model,
            observed_best_matches_expected = row.observed_best_matches_expected,
            external_construct_validation_needed =
                row.external_construct_validation_needed,
            q_risk = row.q_risk,
            q_revision_claim_allowed = false,
        )
        for row in scenario_rows
    ]
end

function parameter_absorption_rows(scenario_rows)
    return [
        (;
            scenario = row.scenario,
            threshold_candidate_scenario = row.threshold_candidate_scenario,
            threshold_regime = row.threshold_regime,
            max_abs_common_direct_parameter_shift =
                row.max_abs_common_direct_parameter_shift,
            delta_elpd_waic = row.delta_elpd_waic,
            delta_elpd_loo = row.delta_elpd_loo,
            observed_fold1_best_model = row.observed_fold1_best_model,
            observed_fold1_best_mae_model = row.observed_fold1_best_mae_model,
            parameter_shift_interpretation =
                row.max_abs_common_direct_parameter_shift === missing ?
                :not_available :
                :fit_metric_shift_changes_common_direct_parameter_blocks,
            public_fit_metric_claim_allowed = false,
        )
        for row in scenario_rows
    ]
end

function anchor_limitation_rows(fold1)
    return [
        (;
            blocker = as_symbol(row[:blocker]),
            blocks = as_symbol(row[:blocks]),
            resolved = as_bool(row[:resolved]),
            carried_into_linkage = true,
        )
        for row in fold1[:blocker_rows]
    ]
end

function generate_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    all_input_artifacts_present = all(record.exists for record in input_records)
    all_expected_schemas = all(record.schema_matches for record in input_records)
    all_input_summaries_passed =
        all(record.summary_passed for record in input_records)

    fit_threshold =
        load_fixture("test/fixtures/mgmfrm_fit_metric_threshold_sensitivity.json")
    q_grid =
        load_fixture("test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json")
    heldout_sim =
        load_fixture("test/fixtures/mgmfrm_heldout_prediction_simulation_grid.json")
    fold1 =
        load_fixture("test/fixtures/mgmfrm_full_heldout_mcmc_refit_fold1_scoring.json")

    fit_threshold_passed =
        record_by_name(input_records,
            :mgmfrm_fit_metric_threshold_sensitivity).summary_passed
    q_grid_passed =
        record_by_name(input_records,
            :mgmfrm_empirical_q_matrix_recovery_simulation_grid).summary_passed
    heldout_sim_passed =
        record_by_name(input_records,
            :mgmfrm_heldout_prediction_simulation_grid).summary_passed
    fold1_passed =
        record_by_name(input_records,
            :mgmfrm_full_heldout_mcmc_refit_fold1_scoring).summary_passed

    scenario_rows =
        scenario_link_rows(heldout_sim, fold1, fit_threshold, q_grid)
    threshold_rows =
        threshold_profile_link_rows(heldout_sim, scenario_rows)
    q_link_rows = q_recovery_link_rows(scenario_rows)
    absorption_rows = parameter_absorption_rows(scenario_rows)
    anchor_rows = anchor_limitation_rows(fold1)

    all_scenario_link_rows_recorded =
        length(scenario_rows) == length(heldout_sim[:scenario_rows])
    threshold_profile_link_rows_recorded =
        length(threshold_rows) == length(heldout_sim[:threshold_impact_rows])
    q_recovery_link_rows_recorded = length(q_link_rows) == length(scenario_rows)
    parameter_absorption_rows_recorded =
        length(absorption_rows) == length(scenario_rows)
    fold1_observed_rank_recorded =
        all(row.observed_fold1_best_model !== missing for row in scenario_rows)
    observed_vs_expected_rank_match_recorded =
        all(row.observed_best_matches_expected isa Bool for row in scenario_rows)
    any_observed_expected_mismatch_flagged =
        any(!row.observed_best_matches_expected for row in scenario_rows)
    anchor_limitations_recorded = !isempty(anchor_rows) &&
        all(!row.resolved for row in anchor_rows)

    no_single_threshold_profile_promoted =
        as_bool(fit_threshold[:summary][:no_single_threshold_profile_promoted])
    no_automatic_q_revision =
        as_bool(q_grid[:summary][:no_automatic_q_revision])
    no_public_fit_metric_claim =
        as_bool(fit_threshold[:summary][:no_public_fit_metric_claim]) &&
        as_bool(fold1[:summary][:no_public_fit_metric_claim])
    no_public_q_revision_claim =
        as_bool(fold1[:summary][:no_public_q_revision_claim]) &&
        as_bool(q_grid[:summary][:no_public_recovery_claim])
    no_public_model_weight_claim =
        as_bool(fold1[:summary][:no_public_model_weight_claim]) &&
        as_bool(heldout_sim[:summary][:no_public_model_weight_claim])
    no_sparse_superiority_claim =
        as_bool(fold1[:summary][:no_sparse_superiority_claim]) &&
        as_bool(heldout_sim[:summary][:no_sparse_superiority_claim])
    no_publication_or_registration_action = true

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        fit_threshold_passed &&
        q_grid_passed &&
        heldout_sim_passed &&
        fold1_passed &&
        all_scenario_link_rows_recorded &&
        threshold_profile_link_rows_recorded &&
        q_recovery_link_rows_recorded &&
        parameter_absorption_rows_recorded &&
        fold1_observed_rank_recorded &&
        observed_vs_expected_rank_match_recorded &&
        any_observed_expected_mismatch_flagged &&
        anchor_limitations_recorded &&
        no_single_threshold_profile_promoted &&
        no_automatic_q_revision &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication_or_registration_action

    n_observed_expected_matches =
        count(row -> row.observed_best_matches_expected, scenario_rows)
    n_expected_models_not_scored =
        count(row -> !row.expected_model_scored_fold1, scenario_rows)
    n_threshold_unstable_rows =
        count(row -> !row.ranking_stable_under_profile, threshold_rows)
    n_q_false_candidate_links =
        count(row -> row.q_false_candidate === true, q_link_rows)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_fit_threshold_q_heldout_linkage.v1",
        family = :mgmfrm,
        scope = :fit_threshold_q_heldout_linkage,
        status = :fit_threshold_q_heldout_linkage_recorded,
        decision =
            :record_fit_threshold_q_heldout_linkage_keep_public_claims_blocked,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        pilot_only = true,
        publication_or_registration_action = false,
        public_fit_metric_claim = false,
        public_q_revision_claim = false,
        public_model_weight_claim = false,
        sparse_mgmfrm_superiority_claim = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        scenario_link_rows = scenario_rows,
        threshold_profile_link_rows = threshold_rows,
        q_recovery_link_rows = q_link_rows,
        parameter_absorption_rows = absorption_rows,
        anchor_limitation_rows = anchor_rows,
        decision_record = (;
            selected_decision =
                :fit_threshold_q_heldout_linkage_recorded_local_only,
            threshold_profiles_promoted = false,
            automatic_q_revision_allowed = false,
            fold1_observed_scores_used_for_public_claims = false,
            observed_expected_mismatches_require_followup = true,
            scalar_and_null_anchor_scores_required = true,
            full_batch_required = true,
            external_construct_validation_required = true,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_or_external_construct_dataset,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            fit_metric_threshold_sensitivity_passed = fit_threshold_passed,
            empirical_q_matrix_recovery_simulation_grid_passed =
                q_grid_passed,
            heldout_prediction_simulation_grid_passed = heldout_sim_passed,
            fold1_scoring_passed = fold1_passed,
            all_scenario_link_rows_recorded,
            threshold_profile_link_rows_recorded,
            q_recovery_link_rows_recorded,
            parameter_absorption_rows_recorded,
            fold1_observed_rank_recorded,
            observed_vs_expected_rank_match_recorded,
            any_observed_expected_mismatch_flagged,
            anchor_limitations_recorded,
            no_single_threshold_profile_promoted,
            no_automatic_q_revision,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(input_records),
            n_scenario_link_rows = length(scenario_rows),
            n_threshold_profile_link_rows = length(threshold_rows),
            n_q_recovery_link_rows = length(q_link_rows),
            n_parameter_absorption_rows = length(absorption_rows),
            n_anchor_limitation_rows = length(anchor_rows),
            n_observed_expected_matches,
            n_observed_expected_mismatches =
                length(scenario_rows) - n_observed_expected_matches,
            n_expected_models_not_scored,
            n_threshold_unstable_rows,
            n_q_false_candidate_links,
            fold1_total_heldout_elpd =
                as_float(fold1[:summary][:total_heldout_elpd]),
            fold1_mean_heldout_log_predictive_density =
                as_float(fold1[:summary][:mean_heldout_log_predictive_density]),
            fold1_n_blockers = as_int(fold1[:summary][:n_blockers]),
            recommendation =
                :use_linkage_to_prioritize_full_batch_and_construct_validation_not_public_claims,
            next_gate =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_or_external_construct_dataset,
        ),
    )
end

function main(args = ARGS)
    output = parse_args(args)
    artifact = generate_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenario_link_rows,
        " mismatches=", artifact.summary.n_observed_expected_mismatches,
        " next_gate=", artifact.summary.next_gate)
    return artifact
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
