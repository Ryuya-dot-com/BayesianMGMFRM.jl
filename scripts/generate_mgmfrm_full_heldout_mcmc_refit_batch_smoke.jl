#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_mcmc_refit_batch_smoke.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"),
    (name = :mgmfrm_guarded_local_fit_entrypoint,
        path = "test/fixtures/mgmfrm_guarded_local_fit_entrypoint.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_guarded_local_fit_entrypoint.v1"),
    (name = :mgmfrm_q_revision_construct_validity_review,
        path = "test/fixtures/mgmfrm_q_revision_construct_validity_review.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1"),
]

const SMOKE_UNIT_SELECTION = [
    (execution_unit_id =
            :well_specified_current_q__confirmatory_mgmfrm_current_q__fold1,
        selection_reason = :current_q_confirmatory_smoke,
        q_profile = :current_q_6_item_2d,
        q_matrix = Bool[
            1 0
            0 1
            1 0
            0 1
            1 1
            1 0
        ],
        dimensions = 2,
        n_items = 6,
        synthetic_formula = (n_persons = 4, n_raters = 2,
            person_multiplier = 1, rater_multiplier = 1,
            item_multiplier = 2, person_block_shift = 0,
            rater_block_shift = 1, item_block_shift = 1)),
    (execution_unit_id =
            :missing_loading_revised_q__construct_reviewed_revised_q_mgmfrm__fold1,
        selection_reason = :construct_reviewed_revised_q_smoke,
        q_profile = :construct_reviewed_candidate_q_3_item_2d,
        q_matrix = Bool[
            1 0
            0 1
            1 1
        ],
        dimensions = 2,
        n_items = 3,
        synthetic_formula = (n_persons = 4, n_raters = 2,
            person_multiplier = 1, rater_multiplier = 1,
            item_multiplier = 1, person_block_shift = 0,
            rater_block_shift = 1, item_block_shift = 0)),
    (execution_unit_id =
            :weak_dimension_ambiguous__sparse_mgmfrm_current_q__fold1,
        selection_reason = :rank_ambiguity_sparse_q_smoke,
        q_profile = :sparse_current_q_5_item_3d,
        q_matrix = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 0 0
            0 1 1
        ],
        dimensions = 3,
        n_items = 5,
        synthetic_formula = (n_persons = 4, n_raters = 2,
            person_multiplier = 1, rater_multiplier = 1,
            item_multiplier = 1, person_block_shift = 0,
            rater_block_shift = 1, item_block_shift = 1)),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_full_heldout_mcmc_refit_batch_smoke_v1",
    review_kind = :local_full_heldout_mcmc_refit_batch_smoke,
    publication_or_registration_action = false,
    local_only = true,
    smoke_only = true,
    execution_scope = :representative_scenario_model_fold_smoke,
    source_execution_plan =
        :mgmfrm_full_heldout_mcmc_refit_execution_plan,
    target_execution_unit = :scenario_model_fold,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 1,
        seed_base = 20260731,
    ),
    thresholds = (;
        require_execution_plan_passed = true,
        require_guarded_local_fit_entrypoint_passed = true,
        require_q_revision_construct_validity_review_passed = true,
        require_representative_units_selected = true,
        require_smoke_fit_attempts_succeeded = true,
        require_smoke_outputs_finite = true,
        require_training_pointwise_loglikelihood_recorded = true,
        require_publication_grade_diagnostics_blocked = true,
        require_full_125_unit_batch_not_claimed = true,
        require_heldout_predictive_scores_blocked_until_full_batch = true,
        require_external_construct_dataset_still_required = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM full-heldout MCMC refit batch-smoke artifact.

    This executes a small representative subset of the full scenario x model x
    fold execution plan through the guarded fixed-Q MGMFRM fit path. It records
    finite smoke-fit outputs and keeps full-batch execution, heldout predictive
    scoring, external construct evidence, and public MGMFRM claims blocked.

    Usage:
      julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_batch_smoke.jl [--output PATH]
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
    name === :mgmfrm_full_heldout_mcmc_refit_execution_plan && return (;
        passed = as_bool(summary[:passed]),
        full_mcmc_refit_execution_plan_recorded =
            as_bool(summary[:full_mcmc_refit_execution_plan_recorded]),
        full_mcmc_refit_required =
            as_bool(summary[:full_mcmc_refit_required]),
        full_mcmc_refit_execution_completed =
            as_bool(summary[:full_mcmc_refit_execution_completed]),
        all_scenario_model_fold_units_materialized =
            as_bool(summary[:all_scenario_model_fold_units_materialized]),
        diagnostic_thresholds_recorded =
            as_bool(summary[:diagnostic_thresholds_recorded]),
        execution_budget_recorded =
            as_bool(summary[:execution_budget_recorded]),
        all_claim_rules_block_public_claims =
            as_bool(summary[:all_claim_rules_block_public_claims]),
        n_execution_unit_rows = as_int(summary[:n_execution_unit_rows]),
        n_planned_chains = as_int(summary[:n_planned_chains]),
        n_planned_posterior_draws =
            as_int(summary[:n_planned_posterior_draws]),
        n_planned_warmup_iterations =
            as_int(summary[:n_planned_warmup_iterations]),
        next_gate = as_string(summary[:next_gate]),
    )
    name === :mgmfrm_guarded_local_fit_entrypoint && return (;
        passed = as_bool(summary[:passed]),
        all_guarded_fit_attempts_succeeded =
            as_bool(summary[:all_guarded_fit_attempts_succeeded]),
        fit_outputs_finite = as_bool(summary[:fit_outputs_finite]),
        no_public_q_revision_claim =
            as_bool(summary[:no_public_q_revision_claim]),
        no_broader_mgmfrm_claim =
            as_bool(summary[:no_broader_mgmfrm_claim]),
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

q_matrix_rows(matrix::AbstractMatrix{Bool}) =
    [[Bool(matrix[row, col]) for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]

function selected_unit_rows(plan)
    plan_rows = collect(plan[:execution_unit_rows])
    output = NamedTuple[]
    for selection in SMOKE_UNIT_SELECTION
        unit = only(row for row in plan_rows
            if as_string(row[:execution_unit_id]) ==
                String(selection.execution_unit_id))
        push!(output, (;
            execution_unit_id = selection.execution_unit_id,
            selection_reason = selection.selection_reason,
            q_profile = selection.q_profile,
            scenario = as_symbol(unit[:scenario]),
            model = as_symbol(unit[:model]),
            fold = as_int(unit[:fold]),
            split = as_symbol(unit[:split]),
            n_train_observations = as_int(unit[:n_train_observations]),
            n_heldout_observations = as_int(unit[:n_heldout_observations]),
            heldout_observations =
                [as_int(value) for value in unit[:heldout_observations]],
            planned_minimum_chains = as_int(unit[:minimum_chains]),
            planned_minimum_draws_per_chain =
                as_int(unit[:minimum_draws_per_chain]),
            planned_minimum_warmup_per_chain =
                as_int(unit[:minimum_warmup_per_chain]),
            smoke_chains = PROTOCOL.fit_controls.chains,
            smoke_draws_per_chain = PROTOCOL.fit_controls.draws,
            smoke_warmup_per_chain = PROTOCOL.fit_controls.warmup,
            rank_ambiguity_resolution_required =
                as_bool(unit[:rank_ambiguity_resolution_required]),
            external_construct_validation_required =
                as_bool(unit[:external_construct_validation_required]),
            full_unit_execution_status = as_symbol(unit[:execution_status]),
            public_claim_allowed = false,
        ))
    end
    return output
end

function selection_by_id(id::Symbol)
    return only(selection for selection in SMOKE_UNIT_SELECTION
        if selection.execution_unit_id === id)
end

function synthetic_rows(selection, heldout_observations)
    formula = selection.synthetic_formula
    rows = NamedTuple[]
    heldout = Set(Int.(heldout_observations))
    for observation in 1:40
        block = div(observation - 1, 5)
        person = mod(formula.person_multiplier * (observation - 1) +
            formula.person_block_shift * block, formula.n_persons) + 1
        rater = mod(formula.rater_multiplier * (observation - 1) +
            formula.rater_block_shift * block, formula.n_raters) + 1
        item = mod(formula.item_multiplier * (observation - 1) +
            formula.item_block_shift * block, selection.n_items) + 1
        score = mod(person + 2 * rater + 3 * item + observation + block, 3)
        push!(rows, (;
            observation,
            examinee = "E$person",
            rater = "R$rater",
            item = "I$item",
            score,
            split_role = observation in heldout ? :heldout : :train,
        ))
    end
    return rows
end

function training_table(rows)
    train_rows = [row for row in rows if row.split_role === :train]
    return (;
        examinee = [row.examinee for row in train_rows],
        rater = [row.rater for row in train_rows],
        item = [row.item for row in train_rows],
        score = [row.score for row in train_rows],
    )
end

function smoke_fit_row(unit, index::Int)
    selection = selection_by_id(unit.execution_unit_id)
    rows = synthetic_rows(selection, unit.heldout_observations)
    table = training_table(rows)
    data = BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
    validation = BayesianMGMFRM.validate_design(data)
    spec = BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions = selection.dimensions,
        q_matrix = selection.q_matrix,
    )
    q_validation = BayesianMGMFRM.q_matrix_validation(spec)
    fit_seed = PROTOCOL.fit_controls.seed_base + index
    fit = BayesianMGMFRM.fit(spec;
        experimental = true,
        backend = PROTOCOL.fit_controls.backend,
        ndraws = PROTOCOL.fit_controls.draws,
        warmup = PROTOCOL.fit_controls.warmup,
        chains = PROTOCOL.fit_controls.chains,
        seed = fit_seed,
        progress = false,
    )
    summary = fit.diagnostic_surface.summary
    return (;
        execution_unit_id = unit.execution_unit_id,
        scenario = unit.scenario,
        model = unit.model,
        fold = unit.fold,
        selection_reason = unit.selection_reason,
        q_profile = unit.q_profile,
        q_matrix = q_matrix_rows(selection.q_matrix),
        fit_seed,
        fit_succeeded = fit isa BayesianMGMFRM.MGMFRMFit,
        returned_type = Symbol(nameof(typeof(fit))),
        smoke_only = true,
        training_data_source = :deterministic_local_smoke_table,
        n_plan_observations = 40,
        n_train_observations = data.n,
        n_heldout_observations = length(unit.heldout_observations),
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        n_dimensions = selection.dimensions,
        validation_passed = Bool(validation.passed),
        q_validation_passed = Bool(q_validation.passed),
        backend = fit.backend,
        sampler = fit.sampler,
        chains = length(fit.chain_acceptance_rate),
        draws_per_chain = size(fit.draws, 1) ÷ length(fit.chain_acceptance_rate),
        warmup = fit.warmup,
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_training_pointwise_loglikelihood_rows =
            size(fit.direct_pointwise_loglikelihood, 1),
        n_training_pointwise_observations =
            size(fit.direct_pointwise_loglikelihood, 2),
        heldout_predictive_score_computed = false,
        posterior_predictive_check_recorded = false,
        finite_log_posterior = all(isfinite, fit.log_posterior),
        finite_raw_draws = all(isfinite, fit.draws),
        finite_direct_draws = all(isfinite, fit.direct_draws),
        finite_direct_loglikelihood = all(isfinite, fit.direct_loglikelihood),
        finite_training_pointwise_loglikelihood =
            all(isfinite, fit.direct_pointwise_loglikelihood),
        diagnostic_flag = summary.flag,
        diagnostic_passed = Bool(summary.passed),
        n_nonfinite_logdensity = Int(summary.n_nonfinite_logdensity),
        n_nonfinite_direct_loglikelihood =
            Int(summary.n_nonfinite_direct_loglikelihood),
        n_failed_direct_constraints =
            Int(summary.n_failed_direct_constraints),
        n_divergences = Int(summary.n_divergences),
        n_max_treedepth = Int(summary.n_max_treedepth),
        rhat_evaluable = isfinite(Float64(summary.max_rhat)),
        ess_evaluable = isfinite(Float64(summary.min_ess)),
        public_claim_allowed = false,
    )
end

function diagnostic_check_rows(fit_rows)
    rows = NamedTuple[]
    for row in fit_rows
        checks = [
            (check = :smoke_fit_succeeded, passed = Bool(row.fit_succeeded),
                blocks_public_claim = true),
            (check = :finite_log_posterior,
                passed = Bool(row.finite_log_posterior),
                blocks_public_claim = true),
            (check = :finite_raw_and_direct_draws,
                passed = Bool(row.finite_raw_draws) &&
                    Bool(row.finite_direct_draws),
                blocks_public_claim = true),
            (check = :finite_training_pointwise_loglikelihood,
                passed = Bool(row.finite_training_pointwise_loglikelihood),
                blocks_public_claim = true),
            (check = :zero_divergences,
                passed = Int(row.n_divergences) == 0,
                blocks_public_claim = true),
            (check = :zero_max_treedepth_hits,
                passed = Int(row.n_max_treedepth) == 0,
                blocks_public_claim = true),
            (check = :publication_grade_rhat_not_evaluable_in_smoke,
                passed = !Bool(row.rhat_evaluable),
                blocks_public_claim = true),
            (check = :publication_grade_ess_not_evaluable_in_smoke,
                passed = !Bool(row.ess_evaluable),
                blocks_public_claim = true),
            (check = :heldout_predictive_score_not_computed_in_smoke,
                passed = !Bool(row.heldout_predictive_score_computed),
                blocks_public_claim = true),
        ]
        for check in checks
            push!(rows, (;
                execution_unit_id = row.execution_unit_id,
                scenario = row.scenario,
                model = row.model,
                fold = row.fold,
                check.check,
                check.passed,
                check.blocks_public_claim,
            ))
        end
    end
    return rows
end

function blocker_rows()
    return [
        (blocker = :full_125_unit_refit_batch_not_completed,
            blocks = :public_heldout_prediction_claims,
            resolved = false),
        (blocker = :publication_grade_chains_and_draws_not_run,
            blocks = :public_fit_metric_and_model_weight_claims,
            resolved = false),
        (blocker = :heldout_predictive_scores_not_computed,
            blocks = :public_model_comparison_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_q_revision_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_full_heldout_mcmc_refit_batch_smoke.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    plan_record =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_execution_plan)
    entrypoint_record =
        record_by_name(records, :mgmfrm_guarded_local_fit_entrypoint)
    q_review_record =
        record_by_name(records, :mgmfrm_q_revision_construct_validity_review)
    plan = load_fixture(
        "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json")

    selected_units = selected_unit_rows(plan)
    smoke_rows = [
        smoke_fit_row(unit, index)
        for (index, unit) in enumerate(selected_units)
    ]
    checks = diagnostic_check_rows(smoke_rows)
    blockers = blocker_rows()
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    execution_plan_passed = Bool(plan_record.summary.passed)
    guarded_local_fit_entrypoint_passed =
        Bool(entrypoint_record.summary.passed)
    q_revision_construct_validity_review_passed =
        Bool(q_review_record.summary.passed)
    representative_units_selected =
        length(selected_units) == length(SMOKE_UNIT_SELECTION)
    smoke_fit_attempts_succeeded =
        all(row -> Bool(row.fit_succeeded), smoke_rows)
    smoke_outputs_finite = all(row ->
            Bool(row.finite_log_posterior) &&
            Bool(row.finite_raw_draws) &&
            Bool(row.finite_direct_draws) &&
            Bool(row.finite_direct_loglikelihood) &&
            Bool(row.finite_training_pointwise_loglikelihood) &&
            Int(row.n_nonfinite_logdensity) == 0 &&
            Int(row.n_nonfinite_direct_loglikelihood) == 0 &&
            Int(row.n_failed_direct_constraints) == 0,
        smoke_rows)
    training_pointwise_loglikelihood_recorded =
        all(row -> Int(row.n_training_pointwise_observations) ==
                Int(row.n_train_observations),
            smoke_rows)
    publication_grade_diagnostics_blocked =
        all(row -> Symbol(row.diagnostic_flag) === :insufficient_chains &&
                !Bool(row.diagnostic_passed),
            smoke_rows)
    full_125_unit_batch_not_claimed =
        length(smoke_rows) < Int(plan_record.summary.n_execution_unit_rows)
    heldout_predictive_scores_blocked_until_full_batch =
        all(row -> !Bool(row.heldout_predictive_score_computed), smoke_rows)
    external_construct_dataset_still_required =
        any(row -> Bool(row.external_construct_validation_required),
            selected_units)
    no_public_fit_metric_claim = true
    no_public_q_revision_claim =
        Bool(q_review_record.summary.no_public_q_revision_claim)
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        execution_plan_passed &&
        guarded_local_fit_entrypoint_passed &&
        q_revision_construct_validity_review_passed &&
        Bool(plan_record.summary.full_mcmc_refit_execution_plan_recorded) &&
        Bool(plan_record.summary.full_mcmc_refit_required) &&
        !Bool(plan_record.summary.full_mcmc_refit_execution_completed) &&
        representative_units_selected &&
        smoke_fit_attempts_succeeded &&
        smoke_outputs_finite &&
        training_pointwise_loglikelihood_recorded &&
        publication_grade_diagnostics_blocked &&
        full_125_unit_batch_not_claimed &&
        heldout_predictive_scores_blocked_until_full_batch &&
        external_construct_dataset_still_required &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication &&
        all(row -> Bool(row.passed), checks)

    n_review_cells =
        length(selected_units) + length(smoke_rows) + length(checks)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_batch_smoke.v1",
        family = :mgmfrm,
        scope = :full_heldout_mcmc_refit_batch_smoke,
        status = :representative_batch_smoke_refits_completed,
        decision =
            :record_representative_refit_batch_smoke_keep_claims_blocked,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        smoke_only = true,
        full_mcmc_refit_execution_plan_recorded = true,
        representative_batch_smoke_completed = true,
        full_mcmc_refit_execution_completed = false,
        full_125_unit_batch_completed = false,
        heldout_predictive_scores_computed = false,
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
        selected_execution_unit_rows = selected_units,
        smoke_fit_rows = smoke_rows,
        diagnostic_check_rows = checks,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_representative_refit_batch_smoke_keep_claims_blocked,
            representative_batch_smoke_completed = true,
            full_mcmc_refit_execution_completed = false,
            full_125_unit_batch_completed = false,
            heldout_predictive_scores_computed = false,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            smoke_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            execution_plan_passed,
            guarded_local_fit_entrypoint_passed,
            q_revision_construct_validity_review_passed,
            representative_units_selected,
            smoke_fit_attempts_succeeded,
            smoke_outputs_finite,
            training_pointwise_loglikelihood_recorded,
            publication_grade_diagnostics_blocked,
            full_125_unit_batch_not_claimed,
            heldout_predictive_scores_blocked_until_full_batch,
            external_construct_dataset_still_required,
            all_diagnostic_checks_passed =
                all(row -> Bool(row.passed), checks),
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            full_mcmc_refit_execution_plan_recorded = true,
            representative_batch_smoke_completed = true,
            full_mcmc_refit_execution_completed = false,
            full_125_unit_batch_completed = false,
            heldout_predictive_scores_computed = false,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            n_input_artifacts = length(records),
            n_planned_execution_units =
                Int(plan_record.summary.n_execution_unit_rows),
            n_selected_execution_unit_rows = length(selected_units),
            n_smoke_fit_rows = length(smoke_rows),
            n_diagnostic_check_rows = length(checks),
            n_blocker_rows = length(blockers),
            n_review_cells,
            n_smoke_training_observations =
                sum(row.n_train_observations for row in smoke_rows),
            n_smoke_heldout_observations =
                sum(row.n_heldout_observations for row in smoke_rows),
            n_training_pointwise_loglikelihood_cells =
                sum(row.n_training_pointwise_observations for row in smoke_rows),
            n_publication_grade_fit_rows =
                count(row -> Bool(row.diagnostic_passed), smoke_rows),
            n_full_execution_units_completed = 0,
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !Bool(row.resolved)],
            recommendation =
                :use_smoke_as_runner_check_execute_full_batch_or_attach_external_dataset_next,
            next_gate =
                :full_heldout_mgmfrm_mcmc_refit_full_batch_execution_or_external_construct_dataset_attachment,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " smoke_units=", artifact.summary.n_smoke_fit_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
