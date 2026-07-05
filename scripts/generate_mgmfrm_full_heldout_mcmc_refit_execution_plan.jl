#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_mcmc_refit_execution_plan.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_full_heldout_refit_or_construct_validation_review,
        path =
            "test/fixtures/mgmfrm_full_heldout_refit_or_construct_validation_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_refit_or_construct_validation_review.v1"),
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
    protocol_id = "mgmfrm_full_heldout_mcmc_refit_execution_plan_v1",
    review_kind = :local_full_heldout_mcmc_refit_execution_plan,
    publication_or_registration_action = false,
    local_only = true,
    decision_scope =
        :materialize_full_mcmc_refit_workload_before_public_claims,
    refit_split = :observation_kfold,
    target_execution_unit = :scenario_model_fold,
    next_execution_target =
        :full_heldout_mgmfrm_mcmc_refit_batch_execution_or_external_construct_dataset_attachment,
    thresholds = (;
        require_full_refit_review_passed = true,
        require_heldout_prediction_execution_passed = true,
        require_validation_split_policy_passed = true,
        require_construct_validity_review_passed = true,
        require_full_mcmc_refit_required = true,
        require_all_scenario_model_fold_units_materialized = true,
        require_diagnostic_thresholds_recorded = true,
        require_execution_budget_recorded = true,
        require_external_construct_dataset_review_recorded = true,
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
    Generate the local MGMFRM full-heldout MCMC refit execution plan.

    This artifact materializes the scenario x model x fold workload that must
    be executed after the deterministic heldout smoke artifact and the full
    refit / construct-validation review. It does not run MCMC and it does not
    attach external construct-validation evidence.

    Usage:
      julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_execution_plan.jl [--output PATH]
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
    name === :mgmfrm_full_heldout_refit_or_construct_validation_review &&
        return (;
            passed = as_bool(summary[:passed]),
            refit_or_external_validation_review_completed =
                as_bool(summary[:refit_or_external_validation_review_completed]),
            full_mcmc_refit_required =
                as_bool(summary[:full_mcmc_refit_required]),
            full_mcmc_refit_execution_completed =
                as_bool(summary[:full_mcmc_refit_execution_completed]),
            external_construct_validation_completed =
                as_bool(summary[:external_construct_validation_completed]),
            refit_execution_plan_recorded =
                as_bool(summary[:refit_execution_plan_recorded]),
            all_claim_rules_block_public_claims =
                as_bool(summary[:all_claim_rules_block_public_claims]),
            no_public_fit_metric_claim =
                as_bool(summary[:no_public_fit_metric_claim]),
            no_public_q_revision_claim =
                as_bool(summary[:no_public_q_revision_claim]),
            no_public_model_weight_claim =
                as_bool(summary[:no_public_model_weight_claim]),
            no_sparse_superiority_claim =
                as_bool(summary[:no_sparse_superiority_claim]),
            n_model_refit_plan_rows =
                as_int(summary[:n_model_refit_plan_rows]),
            n_external_construct_validation_rows =
                as_int(summary[:n_external_construct_validation_rows]),
            next_gate = as_string(summary[:next_gate]),
        )
    name === :mgmfrm_heldout_prediction_execution && return (;
        passed = as_bool(summary[:passed]),
        heldout_prediction_execution_completed =
            as_bool(summary[:heldout_prediction_execution_completed]),
        observed_heldout_results_recorded =
            as_bool(summary[:observed_heldout_results_recorded]),
        mcmc_refit_execution_completed =
            as_bool(summary[:mcmc_refit_execution_completed]),
        full_refit_execution_required =
            as_bool(summary[:full_refit_execution_required]),
        fold_assignments_materialized =
            as_bool(summary[:fold_assignments_materialized]),
        all_observations_held_out_once =
            as_bool(summary[:all_observations_held_out_once]),
        n_scenarios = as_int(summary[:n_scenarios]),
        n_models = as_int(summary[:n_models]),
        n_folds = as_int(summary[:n_folds]),
        n_fold_assignment_rows =
            as_int(summary[:n_fold_assignment_rows]),
        n_observed_metric_cells =
            as_int(summary[:n_observed_metric_cells]),
        n_rank_unstable_scenarios =
            as_int(summary[:n_rank_unstable_scenarios]),
        n_external_construct_validation_scenarios =
            as_int(summary[:n_external_construct_validation_scenarios]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_q_revision_construct_validity_review && return (;
        passed = as_bool(summary[:passed]),
        construct_validity_manual_review_completed =
            as_bool(summary[:construct_validity_manual_review_completed]),
        construct_validity_supported_for_all_reviewed =
            as_bool(summary[:construct_validity_supported_for_all_reviewed]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
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

function model_plan_by_model(review)
    return Dict(as_string(row[:model]) => row
        for row in rows_as_vector(review, :model_refit_plan_rows))
end

function refit_requirement_by_scenario(review)
    return Dict(as_string(row[:scenario]) => row
        for row in rows_as_vector(review, :refit_requirement_rows))
end

function fold_assignment_by_scenario_fold(execution)
    return Dict((as_string(row[:scenario]), as_int(row[:fold])) => row
        for row in rows_as_vector(execution, :fold_assignment_rows))
end

function execution_unit_rows(execution, review)
    folds = fold_assignment_by_scenario_fold(execution)
    plans = model_plan_by_model(review)
    requirements = refit_requirement_by_scenario(review)
    scenarios = sort(unique(as_string(row[:scenario])
        for row in rows_as_vector(execution, :fold_assignment_rows)))
    models = sort(collect(keys(plans)))
    fold_ids = sort(unique(as_int(row[:fold])
        for row in rows_as_vector(execution, :fold_assignment_rows)))
    rows = NamedTuple[]
    for (scenario_index, scenario) in enumerate(scenarios)
        requirement = requirements[scenario]
        for (model_index, model) in enumerate(models)
            plan = plans[model]
            for fold in fold_ids
                fold_row = folds[(scenario, fold)]
                seed = 2026070500 + scenario_index * 1000 +
                    model_index * 100 + fold
                push!(rows, (;
                    execution_unit_id =
                        Symbol("$(scenario)__$(model)__fold$(fold)"),
                    scenario = Symbol(scenario),
                    model = Symbol(model),
                    fold,
                    split = as_symbol(fold_row[:split]),
                    n_train_observations =
                        as_int(fold_row[:n_train_observations]),
                    n_heldout_observations =
                        as_int(fold_row[:n_heldout_observations]),
                    heldout_observations =
                        [as_int(value) for value in fold_row[:heldout_observations]],
                    primary_metric =
                        as_symbol(requirement[:primary_metric]),
                    refit_target = as_symbol(plan[:refit_target]),
                    minimum_chains = as_int(plan[:minimum_chains]),
                    minimum_draws_per_chain =
                        as_int(plan[:minimum_draws_per_chain]),
                    minimum_warmup_per_chain = 500,
                    random_seed = seed,
                    rank_ambiguity_resolution_required =
                        !as_bool(requirement[:observed_rank_stable]),
                    external_construct_validation_required =
                        as_bool(requirement[
                            :external_construct_validation_required]),
                    execution_status = :planned_not_executed,
                    full_mcmc_refit_completed = false,
                    diagnostics_observed = false,
                    pointwise_loglikelihood_required = true,
                    posterior_predictive_check_required = true,
                    deterministic_metric_reuse_for_public_claim = false,
                    public_claim_allowed = false,
                ))
            end
        end
    end
    return rows
end

function diagnostic_threshold_rows()
    return [
        (diagnostic = :rhat_max, threshold = 1.01,
            comparison = :less_or_equal, required = true,
            observed = false, public_claim_blocked_if_missing = true),
        (diagnostic = :ess_bulk_min, threshold = 400.0,
            comparison = :greater_or_equal, required = true,
            observed = false, public_claim_blocked_if_missing = true),
        (diagnostic = :ess_tail_min, threshold = 400.0,
            comparison = :greater_or_equal, required = true,
            observed = false, public_claim_blocked_if_missing = true),
        (diagnostic = :divergence_count_max, threshold = 0.0,
            comparison = :equal, required = true,
            observed = false, public_claim_blocked_if_missing = true),
        (diagnostic = :max_treedepth_count_max, threshold = 0.0,
            comparison = :equal, required = true,
            observed = false, public_claim_blocked_if_missing = true),
        (diagnostic = :pointwise_loglikelihood_finite, threshold = 1.0,
            comparison = :boolean_true, required = true,
            observed = false, public_claim_blocked_if_missing = true),
        (diagnostic = :posterior_predictive_check_recorded, threshold = 1.0,
            comparison = :boolean_true, required = true,
            observed = false, public_claim_blocked_if_missing = true),
    ]
end

function execution_budget_rows(units, review)
    plans = rows_as_vector(review, :model_refit_plan_rows)
    return [
        begin
            model = as_string(plan[:model])
            model_units = [
                row for row in units if String(row.model) == model
            ]
            (model = Symbol(model),
                role = as_symbol(plan[:role]),
                n_execution_units = length(model_units),
                n_scenarios = length(unique(row.scenario for row in model_units)),
                n_folds = length(unique(row.fold for row in model_units)),
                chains_per_unit = as_int(plan[:minimum_chains]),
                draws_per_chain = as_int(plan[:minimum_draws_per_chain]),
                warmup_per_chain = 500,
                planned_posterior_draws =
                    length(model_units) * as_int(plan[:minimum_chains]) *
                    as_int(plan[:minimum_draws_per_chain]),
                planned_warmup_iterations =
                    length(model_units) * as_int(plan[:minimum_chains]) * 500,
                batch_runner_required = true,
                full_mcmc_refit_completed = false)
        end
        for plan in plans
    ]
end

function external_construct_dataset_review_rows(review)
    return [
        (scenario = as_symbol(row[:scenario]),
            validation_target = as_symbol(row[:validation_target]),
            trigger = as_symbol(row[:trigger]),
            evidence_required = as_symbol(row[:evidence_required]),
            external_dataset_attached = false,
            external_dataset_review_completed = false,
            mcmc_refit_can_proceed_without_public_q_claim = true,
            public_q_revision_claim_allowed = false,
            public_model_superiority_claim_allowed = false)
        for row in rows_as_vector(review, :external_construct_validation_rows)
    ]
end

function claim_rule_rows(review)
    return [
        (claim = as_symbol(row[:claim]),
            required_before_public_claim =
                as_symbol(row[:required_before_public_claim]),
            execution_plan_recorded = true,
            full_mcmc_refit_completed = false,
            external_construct_validation_completed = false,
            public_claim_allowed = false)
        for row in rows_as_vector(review, :claim_rule_rows)
    ]
end

function blocker_rows()
    return [
        (blocker = :full_mcmc_refit_batches_not_executed,
            blocks = :public_heldout_prediction_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_q_revision_claims,
            resolved = false),
        (blocker = :convergence_diagnostics_not_observed,
            blocks = :public_fit_metric_and_model_weight_claims,
            resolved = false),
        (blocker = :posterior_predictive_refit_checks_missing,
            blocks = :public_model_comparison_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function evidence_link_rows(records)
    review =
        record_by_name(records,
            :mgmfrm_full_heldout_refit_or_construct_validation_review)
    execution = record_by_name(records, :mgmfrm_heldout_prediction_execution)
    construct =
        record_by_name(records, :mgmfrm_q_revision_construct_validity_review)
    split_policy =
        record_by_name(records, :mgmfrm_validation_split_model_comparison_policy)
    return [
        (artifact = review.artifact,
            path = review.path,
            link_satisfied = Bool(review.summary_passed) &&
                Bool(review.summary.refit_execution_plan_recorded) &&
                Bool(review.summary.full_mcmc_refit_required),
            evidence_role =
                :supplies_full_refit_requirements_and_claim_blockers),
        (artifact = execution.artifact,
            path = execution.path,
            link_satisfied = Bool(execution.summary_passed) &&
                Bool(execution.summary.fold_assignments_materialized) &&
                Bool(execution.summary.all_observations_held_out_once),
            evidence_role =
                :supplies_observation_kfold_execution_units),
        (artifact = construct.artifact,
            path = construct.path,
            link_satisfied = Bool(construct.summary_passed) &&
                Bool(construct.summary.construct_validity_manual_review_completed),
            evidence_role =
                :supplies_construct_context_for_external_dataset_review),
        (artifact = split_policy.artifact,
            path = split_policy.path,
            link_satisfied = Bool(split_policy.summary_passed) &&
                Bool(split_policy.summary.primary_holdout_target_selected) &&
                Bool(split_policy.summary.comparison_model_set_recorded),
            evidence_role = :supplies_split_and_comparison_model_policy),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_execution_plan.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    review_record =
        record_by_name(records,
            :mgmfrm_full_heldout_refit_or_construct_validation_review)
    execution_record =
        record_by_name(records, :mgmfrm_heldout_prediction_execution)
    construct_record =
        record_by_name(records, :mgmfrm_q_revision_construct_validity_review)
    split_record =
        record_by_name(records, :mgmfrm_validation_split_model_comparison_policy)
    review =
        load_fixture(
            "test/fixtures/mgmfrm_full_heldout_refit_or_construct_validation_review.json")
    execution =
        load_fixture("test/fixtures/mgmfrm_heldout_prediction_execution.json")

    units = execution_unit_rows(execution, review)
    diagnostics = diagnostic_threshold_rows()
    budgets = execution_budget_rows(units, review)
    external_reviews = external_construct_dataset_review_rows(review)
    claim_rules = claim_rule_rows(review)
    blockers = blocker_rows()
    links = evidence_link_rows(records)
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    full_refit_review_passed = Bool(review_record.summary.passed)
    heldout_prediction_execution_passed = Bool(execution_record.summary.passed)
    validation_split_policy_passed = Bool(split_record.summary.passed)
    construct_validity_review_passed = Bool(construct_record.summary.passed)
    prior_review_next_gate_matched =
        review_record.summary.next_gate ==
            "full_heldout_mgmfrm_mcmc_refit_execution_or_external_construct_dataset_review"
    full_mcmc_refit_required =
        Bool(review_record.summary.full_mcmc_refit_required) &&
        !Bool(review_record.summary.full_mcmc_refit_execution_completed)
    expected_units =
        Int(execution_record.summary.n_scenarios) *
        Int(execution_record.summary.n_models) *
        Int(execution_record.summary.n_folds)
    all_scenario_model_fold_units_materialized =
        length(units) == expected_units &&
        all(row -> row.split === :observation_kfold, units) &&
        all(row -> !Bool(row.full_mcmc_refit_completed), units)
    diagnostic_thresholds_recorded =
        length(diagnostics) == 7 &&
        all(row -> Bool(row.required), diagnostics)
    execution_budget_recorded =
        length(budgets) == Int(review_record.summary.n_model_refit_plan_rows) &&
        sum(row.n_execution_units for row in budgets) == length(units)
    external_construct_dataset_review_recorded =
        length(external_reviews) ==
            Int(review_record.summary.n_external_construct_validation_rows) &&
        all(row -> !Bool(row.external_dataset_review_completed),
            external_reviews)
    all_claim_rules_block_public_claims =
        all(row -> !Bool(row.public_claim_allowed), claim_rules)
    all_evidence_links_satisfied = all(row -> Bool(row.link_satisfied), links)
    no_public_fit_metric_claim =
        Bool(review_record.summary.no_public_fit_metric_claim) &&
        Bool(split_record.summary.no_public_fit_metric_claim)
    no_public_q_revision_claim =
        Bool(review_record.summary.no_public_q_revision_claim) &&
        Bool(construct_record.summary.no_public_q_revision_claim) &&
        Bool(split_record.summary.no_public_q_revision_claim)
    no_public_model_weight_claim =
        Bool(review_record.summary.no_public_model_weight_claim) &&
        Bool(split_record.summary.no_model_weight_or_sparse_superiority_claim)
    no_sparse_superiority_claim =
        Bool(review_record.summary.no_sparse_superiority_claim) &&
        Bool(split_record.summary.no_model_weight_or_sparse_superiority_claim)

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        full_refit_review_passed &&
        heldout_prediction_execution_passed &&
        validation_split_policy_passed &&
        construct_validity_review_passed &&
        prior_review_next_gate_matched &&
        full_mcmc_refit_required &&
        all_scenario_model_fold_units_materialized &&
        diagnostic_thresholds_recorded &&
        execution_budget_recorded &&
        external_construct_dataset_review_recorded &&
        all_claim_rules_block_public_claims &&
        all_evidence_links_satisfied &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_review_cells =
        length(units) + length(diagnostics) + length(budgets) +
        length(external_reviews) + length(claim_rules)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1",
        family = :mgmfrm,
        scope = :full_heldout_mcmc_refit_execution_plan,
        status = :full_mcmc_refit_workload_materialized,
        decision = :record_full_mcmc_refit_execution_workload,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        heldout_prediction_execution_completed = true,
        full_mcmc_refit_execution_plan_recorded = true,
        full_mcmc_refit_execution_completed = false,
        external_construct_dataset_attached = false,
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
        execution_unit_rows = units,
        diagnostic_threshold_rows = diagnostics,
        execution_budget_rows = budgets,
        external_construct_dataset_review_rows = external_reviews,
        claim_rule_rows = claim_rules,
        blocker_rows = blockers,
        evidence_link_rows = links,
        decision_record = (;
            selected_decision =
                :record_full_mcmc_refit_execution_workload,
            full_mcmc_refit_execution_plan_recorded = true,
            full_mcmc_refit_execution_completed = false,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_batch_execution_or_external_construct_dataset_attachment,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            full_refit_review_passed,
            heldout_prediction_execution_passed,
            validation_split_policy_passed,
            construct_validity_review_passed,
            prior_review_next_gate_matched,
            full_mcmc_refit_required,
            full_mcmc_refit_execution_plan_recorded = true,
            full_mcmc_refit_execution_completed = false,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            all_scenario_model_fold_units_materialized,
            diagnostic_thresholds_recorded,
            execution_budget_recorded,
            external_construct_dataset_review_recorded,
            all_claim_rules_block_public_claims,
            all_evidence_links_satisfied,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(records),
            n_execution_unit_rows = length(units),
            n_diagnostic_threshold_rows = length(diagnostics),
            n_execution_budget_rows = length(budgets),
            n_external_construct_dataset_review_rows =
                length(external_reviews),
            n_claim_rule_rows = length(claim_rules),
            n_blocker_rows = length(blockers),
            n_evidence_link_rows = length(links),
            n_review_cells,
            n_scenarios = Int(execution_record.summary.n_scenarios),
            n_models = Int(execution_record.summary.n_models),
            n_folds = Int(execution_record.summary.n_folds),
            n_planned_chains =
                sum(row.minimum_chains for row in units),
            n_planned_posterior_draws =
                sum(row.minimum_chains * row.minimum_draws_per_chain
                    for row in units),
            n_planned_warmup_iterations =
                sum(row.minimum_chains * row.minimum_warmup_per_chain
                    for row in units),
            n_external_construct_validation_scenarios =
                length(external_reviews),
            n_rank_ambiguity_execution_units =
                count(row -> Bool(row.rank_ambiguity_resolution_required),
                    units),
            n_external_construct_execution_units =
                count(row -> Bool(row.external_construct_validation_required),
                    units),
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !Bool(row.resolved)],
            recommendation =
                :execute_refit_batches_or_attach_external_construct_dataset_before_public_claims,
            next_gate =
                :full_heldout_mgmfrm_mcmc_refit_batch_execution_or_external_construct_dataset_attachment,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " execution_units=", artifact.summary.n_execution_unit_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
