#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_pilot_plan.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :mgmfrm_publication_grade_refit_gate,
        path = "test/fixtures/mgmfrm_publication_grade_refit_gate.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_gate.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_execution_plan,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"),
    (name = :mgmfrm_full_heldout_mcmc_refit_anchor_scoring,
        path =
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_anchor_scoring.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_anchor_scoring.v1"),
]

const PILOT_MODELS = (
    :scalar_gmfrm_baseline,
    :confirmatory_mgmfrm_current_q,
    :sparse_mgmfrm_current_q,
    :construct_reviewed_revised_q_mgmfrm,
    :null_or_intercept_reference,
)

const PROTOCOL = (;
    protocol_id = "mgmfrm_publication_grade_refit_pilot_plan_v1",
    review_kind = :local_publication_grade_refit_pilot_plan,
    publication_or_registration_action = false,
    local_only = true,
    pilot_only = true,
    execution_scope = :single_scenario_single_fold_all_comparison_models,
    selected_scenario = :well_specified_current_q,
    selected_fold = 1,
    selected_models = PILOT_MODELS,
    source_gate = :mgmfrm_publication_grade_refit_gate,
    source_execution_plan =
        :mgmfrm_full_heldout_mcmc_refit_execution_plan,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 1000,
        target_acceptance = 0.8,
        seed_offset = 300000,
    ),
    thresholds = (;
        require_gate_passed = true,
        require_execution_plan_passed = true,
        require_anchor_scoring_passed = true,
        require_selected_units_recorded = true,
        require_all_five_models_selected = true,
        require_publication_grade_controls_match_gate = true,
        require_diagnostic_placeholders_recorded = true,
        require_pilot_execution_not_yet_run = true,
        require_full_batch_not_yet_run = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM publication-grade refit pilot plan artifact.

    This artifact selects the first publication-grade pilot cell:
    `well_specified_current_q`, fold 1, and all five comparison models. It
    records the exact publication-grade controls and diagnostic placeholders
    before running heavy MCMC. It does not execute the pilot.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_pilot_plan.jl [--output PATH]
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
    name === :mgmfrm_publication_grade_refit_gate && return (;
        passed = as_bool(summary[:passed]),
        publication_grade_gate_defined =
            as_bool(summary[:publication_grade_gate_defined]),
        publication_grade_pilot_required =
            as_bool(summary[:publication_grade_pilot_required]),
        publication_grade_pilot_executed =
            as_bool(summary[:publication_grade_pilot_executed]),
        diagnostic_gate_rows_recorded =
            as_bool(summary[:diagnostic_gate_rows_recorded]),
        metric_profile_rows_recorded =
            as_bool(summary[:metric_profile_rows_recorded]),
        pilot_scope_recorded = as_bool(summary[:pilot_scope_recorded]),
        next_gate = as_string(summary[:next_gate]),
        planned_chains_per_unit = as_int(summary[:planned_chains_per_unit]),
        planned_draws_per_chain = as_int(summary[:planned_draws_per_chain]),
        planned_warmup_per_chain =
            as_int(summary[:planned_warmup_per_chain]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_execution_plan && return (;
        passed = as_bool(summary[:passed]),
        full_mcmc_refit_execution_plan_recorded =
            as_bool(summary[:full_mcmc_refit_execution_plan_recorded]),
        all_scenario_model_fold_units_materialized =
            as_bool(summary[:all_scenario_model_fold_units_materialized]),
        n_execution_unit_rows = as_int(summary[:n_execution_unit_rows]),
    )
    name === :mgmfrm_full_heldout_mcmc_refit_anchor_scoring && return (;
        passed = as_bool(summary[:passed]),
        full_125_unit_scoring_completed =
            as_bool(summary[:full_125_unit_scoring_completed]),
        comparison_anchor_scores_computed =
            as_bool(summary[:comparison_anchor_scores_computed]),
        publication_grade_diagnostics_blocked =
            as_bool(summary[:publication_grade_diagnostics_blocked]),
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

function selected_execution_units(execution_plan)
    units = rows_as_vector(execution_plan, :execution_unit_rows)
    selected = [
        row for row in units
        if as_symbol(row[:scenario]) === PROTOCOL.selected_scenario &&
           as_int(row[:fold]) == PROTOCOL.selected_fold &&
           as_symbol(row[:model]) in PROTOCOL.selected_models
    ]
    order = Dict(model => index for (index, model) in enumerate(PILOT_MODELS))
    return sort(selected; by = row -> order[as_symbol(row[:model])])
end

function selected_pilot_unit_rows(execution_plan)
    rows = NamedTuple[]
    for row in selected_execution_units(execution_plan)
        model = as_symbol(row[:model])
        reference_model = model === :null_or_intercept_reference
        seed = as_int(row[:random_seed]) + PROTOCOL.fit_controls.seed_offset
        push!(rows, (;
            execution_unit_id = as_symbol(row[:execution_unit_id]),
            scenario = as_symbol(row[:scenario]),
            model,
            fold = as_int(row[:fold]),
            split = as_symbol(row[:split]),
            n_train_observations = as_int(row[:n_train_observations]),
            n_heldout_observations = as_int(row[:n_heldout_observations]),
            heldout_observations =
                [as_int(value) for value in row[:heldout_observations]],
            pilot_role = reference_model ?
                :analytic_reference_anchor : :publication_grade_mcmc_refit,
            mcmc_refit_required = !reference_model,
            analytic_reference_scored = reference_model,
            planned_chains = reference_model ? 0 : PROTOCOL.fit_controls.chains,
            planned_warmup_per_chain =
                reference_model ? 0 : PROTOCOL.fit_controls.warmup_per_chain,
            planned_draws_per_chain =
                reference_model ? 0 : PROTOCOL.fit_controls.draws_per_chain,
            planned_posterior_draws =
                reference_model ? 0 :
                PROTOCOL.fit_controls.chains *
                PROTOCOL.fit_controls.draws_per_chain,
            planned_warmup_iterations =
                reference_model ? 0 :
                PROTOCOL.fit_controls.chains *
                PROTOCOL.fit_controls.warmup_per_chain,
            pilot_seed = reference_model ? missing : seed,
            execution_status = :planned_not_executed,
            publication_grade_pilot_executed = false,
            diagnostics_observed = false,
            heldout_predictive_score_required = true,
            posterior_predictive_check_required = !reference_model,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function execution_control_rows(units)
    return [
        (model = row.model,
            pilot_role = row.pilot_role,
            mcmc_refit_required = row.mcmc_refit_required,
            backend = row.mcmc_refit_required ?
                PROTOCOL.fit_controls.backend : :not_applicable,
            sampler = row.mcmc_refit_required ?
                PROTOCOL.fit_controls.sampler : :not_applicable,
            chains = row.planned_chains,
            warmup_per_chain = row.planned_warmup_per_chain,
            draws_per_chain = row.planned_draws_per_chain,
            target_acceptance = row.mcmc_refit_required ?
                PROTOCOL.fit_controls.target_acceptance : missing,
            pilot_seed = row.pilot_seed,
            execution_status = row.execution_status,
            public_claim_allowed = false)
        for row in units
    ]
end

function diagnostic_placeholder_rows(units, gate)
    gate_diagnostics = [
        as_symbol(row[:diagnostic])
        for row in gate[:diagnostic_gate_rows]
    ]
    rows = NamedTuple[]
    for unit in units
        for diagnostic in gate_diagnostics
            applicable =
                unit.mcmc_refit_required ||
                diagnostic in (
                    :pointwise_loglikelihood_finite,
                    :expected_score_calibration_recorded,
                )
            push!(rows, (;
                execution_unit_id = unit.execution_unit_id,
                scenario = unit.scenario,
                model = unit.model,
                fold = unit.fold,
                diagnostic,
                applicable,
                observed = false,
                passed = false,
                blocks_public_claim = true,
            ))
        end
    end
    return rows
end

function blocker_rows()
    return [
        (blocker = :publication_grade_pilot_not_executed,
            blocks = :pilot_runtime_and_diagnostic_assessment,
            resolved = false),
        (blocker = :diagnostics_not_observed,
            blocks = :public_fit_metric_and_model_comparison_claims,
            resolved = false),
        (blocker = :full_125_unit_publication_grade_batch_not_executed,
            blocks = :public_kfold_model_comparison_claims,
            resolved = false),
        (blocker = :external_construct_dataset_missing,
            blocks = :public_construct_or_q_revision_claims,
            resolved = false),
        (blocker = :independent_public_scope_review_missing,
            blocks = :all_public_mgmfrm_claims,
            resolved = false),
    ]
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_publication_grade_refit_pilot_plan.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function build_artifact()
    records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    gate_record =
        record_by_name(records, :mgmfrm_publication_grade_refit_gate)
    execution_record =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_execution_plan)
    anchor_record =
        record_by_name(records,
            :mgmfrm_full_heldout_mcmc_refit_anchor_scoring)
    gate = load_fixture("test/fixtures/mgmfrm_publication_grade_refit_gate.json")
    execution_plan =
        load_fixture(
            "test/fixtures/mgmfrm_full_heldout_mcmc_refit_execution_plan.json")

    units = selected_pilot_unit_rows(execution_plan)
    controls = execution_control_rows(units)
    diagnostics = diagnostic_placeholder_rows(units, gate)
    blockers = blocker_rows()
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    gate_passed = Bool(gate_record.summary.passed)
    execution_plan_passed = Bool(execution_record.summary.passed)
    anchor_scoring_passed = Bool(anchor_record.summary.passed)
    selected_units_recorded =
        length(units) == length(PILOT_MODELS) &&
        Set(row.model for row in units) == Set(PILOT_MODELS) &&
        all(row -> row.scenario === PROTOCOL.selected_scenario, units) &&
        all(row -> row.fold == PROTOCOL.selected_fold, units)
    publication_grade_controls_match_gate =
        PROTOCOL.fit_controls.chains ==
            Int(gate_record.summary.planned_chains_per_unit) &&
        PROTOCOL.fit_controls.draws_per_chain ==
            Int(gate_record.summary.planned_draws_per_chain) &&
        PROTOCOL.fit_controls.warmup_per_chain ==
            Int(gate_record.summary.planned_warmup_per_chain)
    diagnostic_placeholders_recorded =
        length(diagnostics) ==
            length(units) * length(gate[:diagnostic_gate_rows]) &&
        all(row -> Bool(row.blocks_public_claim), diagnostics)
    publication_grade_pilot_executed = false
    full_125_unit_publication_grade_batch_completed = false
    no_public_fit_metric_claim = true
    no_public_q_revision_claim = true
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        gate_passed &&
        execution_plan_passed &&
        anchor_scoring_passed &&
        selected_units_recorded &&
        publication_grade_controls_match_gate &&
        diagnostic_placeholders_recorded &&
        !publication_grade_pilot_executed &&
        !full_125_unit_publication_grade_batch_completed &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_mcmc_units = count(row -> Bool(row.mcmc_refit_required), units)
    n_review_cells = length(units) + length(controls) + length(diagnostics)

    return (;
        schema = "bayesianmgmfrm.mgmfrm_publication_grade_refit_pilot_plan.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_pilot_plan,
        status = :publication_grade_refit_pilot_planned_not_executed,
        decision =
            :record_single_cell_publication_grade_refit_pilot_plan,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        local_only = true,
        pilot_only = true,
        publication_or_registration_action = false,
        publication_grade_gate_defined = true,
        publication_grade_pilot_plan_recorded = true,
        publication_grade_pilot_executed,
        full_125_unit_publication_grade_batch_completed,
        external_construct_dataset_attached = false,
        external_construct_validation_completed = false,
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
        selected_pilot_unit_rows = units,
        execution_control_rows = controls,
        diagnostic_placeholder_rows = diagnostics,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_publication_grade_single_cell_pilot_before_heavy_refit,
            publication_grade_gate_defined = true,
            publication_grade_pilot_plan_recorded = true,
            publication_grade_pilot_executed,
            full_125_unit_publication_grade_batch_completed,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup =
                :execute_publication_grade_refit_pilot_or_attach_external_construct_dataset,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            pilot_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            gate_passed,
            execution_plan_passed,
            anchor_scoring_passed,
            publication_grade_gate_defined = true,
            publication_grade_pilot_plan_recorded = true,
            selected_units_recorded,
            all_five_models_selected =
                Set(row.model for row in units) == Set(PILOT_MODELS),
            selected_scenario = PROTOCOL.selected_scenario,
            selected_fold = PROTOCOL.selected_fold,
            publication_grade_controls_match_gate,
            diagnostic_placeholders_recorded,
            publication_grade_pilot_executed,
            full_125_unit_publication_grade_batch_completed,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            external_construct_dataset_still_required = true,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(records),
            n_selected_pilot_unit_rows = length(units),
            n_mcmc_pilot_units = n_mcmc_units,
            n_analytic_reference_units = length(units) - n_mcmc_units,
            n_execution_control_rows = length(controls),
            n_diagnostic_placeholder_rows = length(diagnostics),
            n_blocker_rows = length(blockers),
            n_review_cells,
            planned_chains =
                n_mcmc_units * PROTOCOL.fit_controls.chains,
            planned_posterior_draws =
                n_mcmc_units * PROTOCOL.fit_controls.chains *
                PROTOCOL.fit_controls.draws_per_chain,
            planned_warmup_iterations =
                n_mcmc_units * PROTOCOL.fit_controls.chains *
                PROTOCOL.fit_controls.warmup_per_chain,
            n_blockers = length(blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !row.resolved],
            recommendation =
                :run_single_cell_publication_grade_pilot_then_compare_to_smoke_anchor_scoring,
            next_gate =
                :execute_publication_grade_refit_pilot_or_attach_external_construct_dataset,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=$(artifact.summary.passed) units=$(artifact.summary.n_selected_pilot_unit_rows) next_gate=$(artifact.summary.next_gate)")
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
