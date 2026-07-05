#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_refit_or_construct_validation_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_heldout_prediction_execution,
        path =
            "test/fixtures/mgmfrm_heldout_prediction_execution.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_heldout_prediction_execution.v1"),
    (name = :mgmfrm_q_revision_construct_validity_review,
        path =
            "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1"),
    (name = :mgmfrm_validation_split_model_comparison_policy,
        path =
            "test/fixtures/mgmfrm_validation_split_model_comparison_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_validation_split_model_comparison_policy.v1"),
]

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_full_heldout_refit_or_construct_validation_review_v1",
    review_kind =
        :local_full_heldout_refit_or_construct_validation_review,
    publication_or_registration_action = false,
    local_only = true,
    decision_scope =
        :requirements_before_public_mgmfrm_heldout_or_q_claims,
    next_execution_target =
        :full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review,
    thresholds = (;
        require_heldout_prediction_execution_passed = true,
        require_heldout_execution_next_gate_matched = true,
        require_full_mcmc_refit_required = true,
        require_observed_metric_cells_recorded = true,
        require_rank_instability_carried_forward = true,
        require_external_construct_validation_requirements_recorded = true,
        require_refit_execution_plan_recorded = true,
        require_model_claims_blocked_until_refit_and_validation = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM full-heldout-refit / construct-validation review.

    This artifact records the requirements that must be satisfied after the
    deterministic heldout execution smoke artifact and before any public
    fit-metric, Q-revision, model-weight, or sparse-superiority claim. It does
    not run a full MCMC refit and does not assert external construct validity.

    Usage:
      julia --project=. scripts/generate_mgmfrm_full_heldout_refit_or_construct_validation_review.jl [--output PATH]
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

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
fixture_path(path::AbstractString) = normpath(joinpath(ROOT, path))

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_symbol(value) = Symbol(String(value))

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_heldout_prediction_execution && return (;
        passed = as_bool(summary[:passed]),
        heldout_prediction_execution_completed =
            as_bool(summary[:heldout_prediction_execution_completed]),
        observed_heldout_results_recorded =
            as_bool(summary[:observed_heldout_results_recorded]),
        mcmc_refit_execution_completed =
            as_bool(summary[:mcmc_refit_execution_completed]),
        deterministic_synthetic_execution =
            as_bool(summary[:deterministic_synthetic_execution]),
        full_refit_execution_required =
            as_bool(summary[:full_refit_execution_required]),
        n_observed_metric_cells =
            as_int(summary[:n_observed_metric_cells]),
        n_rank_unstable_scenarios =
            as_int(summary[:n_rank_unstable_scenarios]),
        n_external_construct_validation_scenarios =
            as_int(summary[:n_external_construct_validation_scenarios]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_public_model_weight_claim =
            as_bool(summary[:no_public_model_weight_claim]),
        no_sparse_superiority_claim =
            as_bool(summary[:no_sparse_superiority_claim]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_q_revision_construct_validity_review && return (;
        passed = as_bool(summary[:passed]),
        construct_validity_manual_review_completed =
            as_bool(summary[:construct_validity_manual_review_completed]),
        construct_validity_supported_for_all_reviewed =
            as_bool(summary[:construct_validity_supported_for_all_reviewed]),
        supported_candidates_remain_manual_local_only =
            as_bool(summary[:supported_candidates_remain_manual_local_only]),
        no_automatic_q_revision =
            as_bool(summary[:no_automatic_q_revision]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_validation_split_model_comparison_policy && return (;
        passed = as_bool(summary[:passed]),
        primary_holdout_target_selected =
            as_bool(summary[:primary_holdout_target_selected]),
        split_policy_recorded = as_bool(summary[:split_policy_recorded]),
        comparison_model_set_recorded =
            as_bool(summary[:comparison_model_set_recorded]),
        all_metrics_predeclared =
            as_bool(summary[:all_metrics_predeclared]),
        all_leakage_guards_recorded =
            as_bool(summary[:all_leakage_guards_recorded]),
        no_public_fit_metric_claim =
            as_bool(summary[:no_public_fit_metric_claim]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_model_weight_or_sparse_superiority_claim =
            as_bool(summary[:no_model_weight_or_sparse_superiority_claim]),
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
    schema_matches = schema == spec.expected_schema
    summary = artifact_summary(spec.name, fixture[:summary])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema = spec.expected_schema,
        schema_matches,
        summary_passed = summary.passed,
        summary,
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function load_fixture(path::AbstractString)
    return JSON3.read(read(fixture_path(path), String))
end

rows_as_vector(fixture, key::Symbol) = [row for row in fixture[key]]

function best_model_by_scenario(execution)
    rows = rows_as_vector(execution, :scenario_model_summary_rows)
    return Dict(
        as_string(row[:scenario]) => row for row in rows
        if as_bool(row[:observed_primary_best])
    )
end

function refit_priority(rank_row)
    !as_bool(rank_row[:rank_stable_observed]) && return :highest
    as_bool(rank_row[:external_construct_validation_needed]) && return :high
    return :standard
end

function refit_scope(rank_row)
    !as_bool(rank_row[:rank_stable_observed]) &&
        return :rank_ambiguity_resolution_refit
    as_bool(rank_row[:external_construct_validation_needed]) &&
        return :construct_linked_refit_confirmation
    return :scenario_model_refit_confirmation
end

function refit_requirement_rows(execution)
    best = best_model_by_scenario(execution)
    rank_rows = rows_as_vector(execution, :rank_stability_rows)
    return [
        (scenario = as_symbol(row[:scenario]),
            observed_best_model =
                as_symbol(best[as_string(row[:scenario])][:model]),
            primary_metric = as_symbol(row[:primary_metric]),
            observed_rank_stable = as_bool(row[:rank_stable_observed]),
            n_unique_best_models = as_int(row[:n_unique_best_models]),
            external_construct_validation_required =
                as_bool(row[:external_construct_validation_needed]),
            full_mcmc_refit_required = true,
            full_mcmc_refit_completed = false,
            refit_scope = refit_scope(row),
            priority = refit_priority(row),
            public_claim_allowed = false)
        for row in rank_rows
    ]
end

function model_role(model::AbstractString)
    model == "scalar_gmfrm_baseline" && return :scalar_baseline
    model == "confirmatory_mgmfrm_current_q" && return :current_q_confirmatory
    model == "sparse_mgmfrm_current_q" && return :sparse_current_q
    model == "construct_reviewed_revised_q_mgmfrm" &&
        return :construct_reviewed_q_candidate
    return :null_reference
end

function model_refit_plan_rows(execution)
    rows = rows_as_vector(execution, :scenario_model_summary_rows)
    models = sort(unique(as_string(row[:model]) for row in rows))
    return [
        (model = Symbol(model),
            role = model_role(model),
            included_in_full_refit = true,
            refit_target = :heldout_observation_log_score,
            mcmc_refit_required = true,
            mcmc_refit_completed = false,
            minimum_chains = 4,
            minimum_draws_per_chain = 1000,
            required_diagnostics =
                [:rhat, :ess, :divergence_count, :posterior_predictive_check],
            deterministic_metric_reuse_for_public_claim = false,
            public_model_weight_claim_allowed = false)
        for model in models
    ]
end

function validation_target(scenario::AbstractString)
    scenario == "missing_loading_revised_q" &&
        return :external_alignment_of_construct_reviewed_loading
    scenario == "weak_dimension_ambiguous" &&
        return :weak_dimension_discriminant_construct_check
    return :construct_interpretability_check
end

function external_construct_validation_rows(execution)
    rank_rows = rows_as_vector(execution, :rank_stability_rows)
    return [
        (scenario = as_symbol(row[:scenario]),
            validation_target = validation_target(as_string(row[:scenario])),
            trigger = as_bool(row[:rank_stable_observed]) ?
                :construct_reviewed_q_claim_dependency :
                :rank_instability_and_construct_ambiguity,
            evidence_required =
                :external_construct_measure_or_independent_rubric_review,
            external_construct_validation_completed = false,
            public_q_revision_claim_allowed = false,
            public_model_superiority_claim_allowed = false)
        for row in rank_rows
        if as_bool(row[:external_construct_validation_needed])
    ]
end

function claim_rule_rows()
    return [
        (claim = :heldout_prediction_improvement,
            required_before_public_claim =
                :full_mcmc_refit_with_stable_heldout_rank,
            full_mcmc_refit_completed = false,
            external_construct_validation_completed = false,
            public_claim_allowed = false),
        (claim = :fit_metric_threshold_superiority,
            required_before_public_claim =
                :full_refit_threshold_sensitivity_and_scope_review,
            full_mcmc_refit_completed = false,
            external_construct_validation_completed = false,
            public_claim_allowed = false),
        (claim = :q_revision_improvement,
            required_before_public_claim =
                :full_refit_plus_external_construct_validation,
            full_mcmc_refit_completed = false,
            external_construct_validation_completed = false,
            public_claim_allowed = false),
        (claim = :model_weight_reporting,
            required_before_public_claim =
                :full_refit_rank_stability_and_weight_sensitivity_review,
            full_mcmc_refit_completed = false,
            external_construct_validation_completed = false,
            public_claim_allowed = false),
        (claim = :sparse_mgmfrm_superiority,
            required_before_public_claim =
                :full_refit_sparse_win_replication_and_scope_review,
            full_mcmc_refit_completed = false,
            external_construct_validation_completed = false,
            public_claim_allowed = false),
    ]
end

function blocker_rows()
    return [
        (blocker = :full_mcmc_refit_execution_missing,
            blocks = :public_heldout_prediction_claims,
            resolved = false),
        (blocker = :external_construct_validation_missing,
            blocks = :public_q_revision_claims,
            resolved = false),
        (blocker = :rank_ambiguity_resolution_refit_missing,
            blocks = :model_weight_or_sparse_superiority_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function evidence_link_rows(records)
    execution =
        record_by_name(records, :mgmfrm_heldout_prediction_execution)
    construct =
        record_by_name(records, :mgmfrm_q_revision_construct_validity_review)
    split_policy =
        record_by_name(records, :mgmfrm_validation_split_model_comparison_policy)
    return [
        (artifact = execution.artifact,
            path = execution.path,
            link_satisfied = Bool(execution.summary_passed) &&
                Bool(execution.summary.heldout_prediction_execution_completed) &&
                Bool(execution.summary.full_refit_execution_required),
            evidence_role =
                :supplies_observed_heldout_smoke_and_full_refit_blockers),
        (artifact = construct.artifact,
            path = construct.path,
            link_satisfied = Bool(construct.summary_passed) &&
                Bool(construct.summary.construct_validity_manual_review_completed) &&
                Bool(construct.summary.no_public_q_revision_claim),
            evidence_role =
                :supplies_manual_construct_review_context_for_external_validation),
        (artifact = split_policy.artifact,
            path = split_policy.path,
            link_satisfied = Bool(split_policy.summary_passed) &&
                Bool(split_policy.summary.primary_holdout_target_selected) &&
                Bool(split_policy.summary.comparison_model_set_recorded),
            evidence_role = :supplies_heldout_split_and_model_set_policy),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_full_heldout_refit_or_construct_validation_review.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    execution_record =
        record_by_name(records, :mgmfrm_heldout_prediction_execution)
    construct_record =
        record_by_name(records, :mgmfrm_q_revision_construct_validity_review)
    split_record =
        record_by_name(records, :mgmfrm_validation_split_model_comparison_policy)
    execution =
        load_fixture("test/fixtures/mgmfrm_heldout_prediction_execution.json")

    refit_requirements = refit_requirement_rows(execution)
    refit_plan = model_refit_plan_rows(execution)
    construct_validation = external_construct_validation_rows(execution)
    claim_rules = claim_rule_rows()
    blockers = blocker_rows()
    links = evidence_link_rows(records)
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    heldout_prediction_execution_passed = Bool(execution_record.summary.passed)
    heldout_execution_next_gate_matched =
        execution_record.summary.next_gate ==
            "full_heldout_mgmfrm_refit_or_external_construct_validation_review"
    full_mcmc_refit_required =
        Bool(execution_record.summary.full_refit_execution_required) &&
        !Bool(execution_record.summary.mcmc_refit_execution_completed)
    observed_metric_cells_recorded =
        Int(execution_record.summary.n_observed_metric_cells) == 625
    rank_instability_carried_forward =
        count(row -> !Bool(row.observed_rank_stable), refit_requirements) ==
            Int(execution_record.summary.n_rank_unstable_scenarios)
    external_construct_validation_requirements_recorded =
        length(construct_validation) ==
            Int(execution_record.summary.n_external_construct_validation_scenarios)
    refit_execution_plan_recorded = length(refit_plan) == 5 &&
        all(row -> Bool(row.mcmc_refit_required), refit_plan)
    all_claim_rules_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claim_rules)
    no_public_fit_metric_claim =
        Bool(execution_record.summary.no_public_fit_metric_claim) &&
        Bool(split_record.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(execution_record.summary.no_public_q_revision_claim) &&
        Bool(construct_record.summary.no_public_q_revision_claim) &&
        Bool(split_record.summary.no_public_q_revision_claim)
    no_public_model_weight_claim =
        Bool(execution_record.summary.no_public_model_weight_claim) &&
        Bool(split_record.summary.no_model_weight_or_sparse_superiority_claim)
    no_sparse_superiority_claim =
        Bool(execution_record.summary.no_sparse_superiority_claim) &&
        Bool(split_record.summary.no_model_weight_or_sparse_superiority_claim)
    all_evidence_links_satisfied = all(row -> Bool(row.link_satisfied), links)

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        heldout_prediction_execution_passed &&
        heldout_execution_next_gate_matched &&
        full_mcmc_refit_required &&
        observed_metric_cells_recorded &&
        rank_instability_carried_forward &&
        external_construct_validation_requirements_recorded &&
        refit_execution_plan_recorded &&
        all_claim_rules_block_public_claims &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        all_evidence_links_satisfied &&
        no_publication

    n_review_cells =
        length(refit_requirements) + length(refit_plan) +
        length(construct_validation) + length(claim_rules)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_refit_or_construct_validation_review.v1",
        family = :mgmfrm,
        scope = :full_heldout_refit_or_construct_validation_review,
        status = :full_refit_and_construct_validation_review_recorded,
        decision = :record_full_refit_and_construct_validation_requirements,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        heldout_prediction_execution_completed = true,
        full_mcmc_refit_execution_completed = false,
        external_construct_validation_completed = false,
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
        input_artifacts = records,
        refit_requirement_rows = refit_requirements,
        model_refit_plan_rows = refit_plan,
        external_construct_validation_rows = construct_validation,
        claim_rule_rows = claim_rules,
        blocker_rows = blockers,
        evidence_link_rows = links,
        decision_record = (;
            selected_decision =
                :record_full_refit_and_construct_validation_requirements,
            heldout_prediction_execution_completed = true,
            full_mcmc_refit_execution_completed = false,
            external_construct_validation_completed = false,
            refit_or_external_validation_review_completed = true,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            heldout_prediction_execution_passed,
            heldout_execution_next_gate_matched,
            construct_validity_review_passed = Bool(construct_record.summary.passed),
            validation_split_model_comparison_policy_passed =
                Bool(split_record.summary.passed),
            full_mcmc_refit_required,
            observed_metric_cells_recorded,
            rank_instability_carried_forward,
            external_construct_validation_requirements_recorded,
            refit_execution_plan_recorded,
            all_claim_rules_block_public_claims,
            all_evidence_links_satisfied,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            heldout_prediction_execution_completed = true,
            full_mcmc_refit_execution_completed = false,
            external_construct_validation_completed = false,
            refit_or_external_validation_review_completed = true,
            n_input_artifacts = length(records),
            n_refit_requirement_rows = length(refit_requirements),
            n_model_refit_plan_rows = length(refit_plan),
            n_external_construct_validation_rows = length(construct_validation),
            n_claim_rule_rows = length(claim_rules),
            n_blocker_rows = length(blockers),
            n_evidence_link_rows = length(links),
            n_review_cells,
            n_observed_metric_cells =
                Int(execution_record.summary.n_observed_metric_cells),
            n_rank_unstable_scenarios =
                Int(execution_record.summary.n_rank_unstable_scenarios),
            n_external_construct_validation_scenarios =
                Int(execution_record.summary.n_external_construct_validation_scenarios),
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !Bool(row.resolved)],
            recommendation =
                :execute_full_heldout_refit_or_attach_external_construct_validation_before_claims,
            next_gate =
                :full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " review_cells=", artifact.summary.n_review_cells,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
