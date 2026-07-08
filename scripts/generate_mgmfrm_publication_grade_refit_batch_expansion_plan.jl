#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_batch_expansion_plan.json")
const DEFAULT_EXECUTION_PLAN =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_full_heldout_mcmc_refit_execution_plan.json")
const DEFAULT_GATE =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_gate.json")
const DEFAULT_SCALAR_COMPARISON =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_publication_grade_refit_scalar_remediation_comparison.json")
const RUNNER_SCRIPT = "scripts/run_mgmfrm_publication_grade_refit_job.jl"

include(joinpath(@__DIR__, "local_json.jl"))

const EXECUTION_PLAN_SCHEMA =
    "bayesianmgmfrm.mgmfrm_full_heldout_mcmc_refit_execution_plan.v1"
const GATE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_gate.v1"
const SCALAR_COMPARISON_SCHEMA =
    "bayesianmgmfrm.mgmfrm_publication_grade_refit_scalar_remediation_comparison.v1"

const PROTOCOL = (;
    protocol_id =
        "mgmfrm_publication_grade_refit_batch_expansion_plan_v1",
    review_kind =
        :local_publication_grade_refit_batch_expansion_plan,
    publication_or_registration_action = false,
    local_only = true,
    execution_scope = :full_scenario_model_fold_publication_grade_batch,
    trigger_gate =
        :expand_publication_grade_batch_with_scalar_target_acceptance_0p90_local_only,
    source_execution_plan =
        :mgmfrm_full_heldout_mcmc_refit_execution_plan,
    source_gate = :mgmfrm_publication_grade_refit_gate,
    source_scalar_policy =
        :mgmfrm_publication_grade_refit_scalar_remediation_comparison,
    result_root = "artifacts/publication_grade_refit_batch",
    runner_script = RUNNER_SCRIPT,
    fit_controls = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 4,
        warmup_per_chain = 500,
        draws_per_chain = 1000,
        default_target_acceptance = 0.8,
        scalar_remediated_target_acceptance = 0.9,
        seed_offset = 300000,
    ),
    thresholds = (;
        require_execution_plan_passed = true,
        require_gate_passed = true,
        require_scalar_remediation_comparison_passed = true,
        require_batch_unit_rows_recorded = true,
        require_all_125_units_materialized = true,
        require_scalar_target_acceptance_policy_recorded = true,
        require_command_templates_recorded = true,
        require_result_artifact_targets_recorded = true,
        require_diagnostic_capture_manifest_recorded = true,
        require_runner_adapter_state_recorded = true,
        require_batch_execution_not_yet_run = true,
        require_no_public_fit_metric_claim = true,
        require_no_public_q_revision_claim = true,
        require_no_public_model_weight_claim = true,
        require_no_sparse_superiority_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM publication-grade refit batch expansion plan.

    This artifact expands the publication-grade pilot into the full
    scenario x model x fold batch. It records scalar GMFRM target acceptance
    escalation policy, command templates, result targets, and diagnostic
    capture rows, but it does not run MCMC.

    Usage:
      julia --project=. scripts/generate_mgmfrm_publication_grade_refit_batch_expansion_plan.jl [--output PATH]

    Options:
      --output PATH              Review fixture path.
      --execution-plan PATH      Full heldout MCMC execution plan.
      --gate PATH                Publication-grade refit gate fixture.
      --scalar-comparison PATH   Scalar remediation comparison fixture.
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    execution_plan = DEFAULT_EXECUTION_PLAN
    gate = DEFAULT_GATE
    scalar_comparison = DEFAULT_SCALAR_COMPARISON
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--execution-plan"
            index < length(args) || error("--execution-plan requires a path")
            execution_plan = abspath(args[index + 1])
            index += 2
        elseif arg == "--gate"
            index < length(args) || error("--gate requires a path")
            gate = abspath(args[index + 1])
            index += 2
        elseif arg == "--scalar-comparison"
            index < length(args) ||
                error("--scalar-comparison requires a path")
            scalar_comparison = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, execution_plan, gate, scalar_comparison)
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))
rel(path::AbstractString) = relpath(path, ROOT)

as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

function json_get(object, key::Symbol, default = missing)
    haskey(object, key) || return default
    value = object[key]
    value === nothing && return default
    ismissing(value) && return default
    return value
end

function json_bool(object, key::Symbol, default::Bool = false)
    value = json_get(object, key, missing)
    ismissing(value) && return default
    return Bool(value)
end

function json_int(object, key::Symbol, default::Int = 0)
    value = json_get(object, key, missing)
    ismissing(value) && return default
    return Int(value)
end

function json_float_or_missing(object, key::Symbol)
    value = json_get(object, key, missing)
    ismissing(value) && return missing
    return Float64(value)
end

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

rows_as_vector(fixture, key::Symbol) = [row for row in fixture[key]]

function artifact_summary(name::Symbol, summary)
    name === :mgmfrm_full_heldout_mcmc_refit_execution_plan && return (;
        passed = json_bool(summary, :passed),
        full_mcmc_refit_execution_plan_recorded =
            json_bool(summary, :full_mcmc_refit_execution_plan_recorded),
        full_mcmc_refit_execution_completed =
            json_bool(summary, :full_mcmc_refit_execution_completed),
        all_scenario_model_fold_units_materialized =
            json_bool(summary, :all_scenario_model_fold_units_materialized),
        n_execution_unit_rows = json_int(summary, :n_execution_unit_rows),
        n_scenarios = json_int(summary, :n_scenarios),
        n_models = json_int(summary, :n_models),
        n_folds = json_int(summary, :n_folds),
    )
    name === :mgmfrm_publication_grade_refit_gate && return (;
        passed = json_bool(summary, :passed),
        publication_grade_gate_defined =
            json_bool(summary, :publication_grade_gate_defined),
        diagnostic_gate_rows_recorded =
            json_bool(summary, :diagnostic_gate_rows_recorded),
        planned_chains_per_unit =
            json_int(summary, :planned_chains_per_unit),
        planned_draws_per_chain =
            json_int(summary, :planned_draws_per_chain),
        planned_warmup_per_chain =
            json_int(summary, :planned_warmup_per_chain),
    )
    name === :mgmfrm_publication_grade_refit_scalar_remediation_comparison &&
        return (;
            passed = json_bool(summary, :passed),
            comparison_observed =
                json_bool(summary, :comparison_observed),
            remediation_success_observed =
                json_bool(summary, :remediation_success_observed),
            scalar_batch_target_acceptance_policy_recorded =
                json_bool(summary,
                    :scalar_batch_target_acceptance_policy_recorded),
            scalar_batch_target_acceptance =
                json_float_or_missing(summary, :scalar_batch_target_acceptance),
            scalar_batch_expansion_allowed_local_only =
                json_bool(summary,
                    :scalar_batch_expansion_allowed_local_only),
            no_public_fit_metric_claim =
                json_bool(summary, :no_public_fit_metric_claim),
        )
    return (; passed = json_bool(summary, :passed))
end

function input_record(name::Symbol, path::AbstractString,
        expected_schema::AbstractString)
    exists = isfile(path)
    if !exists
        return (;
            artifact = name,
            path = rel(path),
            exists = false,
            sha256 = missing,
            schema = missing,
            expected_schema,
            schema_matches = false,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    artifact = load_json(path)
    schema = as_string(artifact[:schema])
    summary = artifact_summary(name, artifact[:summary])
    return (;
        artifact = name,
        path = rel(path),
        exists,
        sha256 = file_sha256(path),
        schema,
        expected_schema,
        schema_matches = schema == expected_schema,
        summary_passed = summary.passed,
        summary,
    )
end

function scalar_policy(comparison)
    policy = comparison[:batch_sampler_policy_row]
    selected =
        json_float_or_missing(policy, :selected_batch_target_acceptance)
    fallback =
        json_float_or_missing(policy, :fallback_batch_target_acceptance)
    target = ismissing(selected) ? fallback : selected
    ismissing(target) &&
        error("scalar comparison policy lacks target acceptance fallback")
    return (;
        selected_batch_target_acceptance = selected,
        fallback_batch_target_acceptance = target,
        effective_scalar_target_acceptance = target,
        selection_basis = as_symbol(policy[:selection_basis]),
        batch_expansion_allowed_for_scalar =
            json_bool(policy, :batch_expansion_allowed_for_scalar),
        public_claim_allowed = json_bool(policy, :public_claim_allowed),
    )
end

function gate_controls(gate)
    controls = gate[:protocol][:fit_controls]
    return (;
        backend = as_symbol(controls[:backend]),
        sampler = as_symbol(controls[:sampler]),
        chains = as_int(controls[:chains]),
        warmup_per_chain = as_int(controls[:warmup_per_chain]),
        draws_per_chain = as_int(controls[:draws_per_chain]),
        target_acceptance = as_float(controls[:target_acceptance]),
    )
end

function unit_target_acceptance(model::Symbol, policy, controls)
    model === :null_or_intercept_reference && return missing
    model === :scalar_gmfrm_baseline &&
        return policy.effective_scalar_target_acceptance
    return controls.target_acceptance
end

function target_acceptance_source(model::Symbol, policy)
    model === :null_or_intercept_reference && return :not_applicable
    model === :scalar_gmfrm_baseline &&
        return policy.batch_expansion_allowed_for_scalar ?
            :scalar_remediation_observed_policy :
            :scalar_remediation_fallback_pending_observation
    return :publication_grade_gate_default
end

function batch_unit_rows(execution_plan, controls, policy)
    rows = NamedTuple[]
    for row in rows_as_vector(execution_plan, :execution_unit_rows)
        unit_id = as_symbol(row[:execution_unit_id])
        model = as_symbol(row[:model])
        reference_model = model === :null_or_intercept_reference
        mcmc_required = !reference_model
        target_acceptance = unit_target_acceptance(model, policy, controls)
        unit_path = joinpath(PROTOCOL.result_root, String(unit_id))
        seed = mcmc_required ?
            as_int(row[:random_seed]) + PROTOCOL.fit_controls.seed_offset :
            missing
        push!(rows, (;
            execution_job_id =
                Symbol("publication_grade_batch__", String(unit_id)),
            execution_unit_id = unit_id,
            scenario = as_symbol(row[:scenario]),
            model,
            fold = as_int(row[:fold]),
            split = as_symbol(row[:split]),
            job_kind = mcmc_required ?
                :publication_grade_mcmc_refit :
                :analytic_reference_rescore,
            mcmc_refit_required = mcmc_required,
            analytic_reference_scored = reference_model,
            backend = mcmc_required ? controls.backend : :not_applicable,
            sampler = mcmc_required ? controls.sampler : :not_applicable,
            chains = mcmc_required ? controls.chains : 0,
            warmup_per_chain =
                mcmc_required ? controls.warmup_per_chain : 0,
            draws_per_chain =
                mcmc_required ? controls.draws_per_chain : 0,
            target_acceptance,
            target_acceptance_source =
                target_acceptance_source(model, policy),
            batch_seed = seed,
            n_train_observations = as_int(row[:n_train_observations]),
            n_heldout_observations = as_int(row[:n_heldout_observations]),
            heldout_observations =
                [as_int(value) for value in row[:heldout_observations]],
            result_artifact_path = string(unit_path, "_result.json"),
            diagnostic_artifact_path =
                string(unit_path, "_diagnostics.json"),
            heldout_score_artifact_path =
                string(unit_path, "_heldout_score.json"),
            execution_status = :planned_not_executed,
            execute_now = false,
            full_batch_execution_observed = false,
            diagnostics_observed = false,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function target_acceptance_policy_rows(policy, controls)
    return [
        (model_group = :scalar_gmfrm_baseline,
            target_acceptance = policy.effective_scalar_target_acceptance,
            source = policy.batch_expansion_allowed_for_scalar ?
                :scalar_remediation_observed_policy :
                :scalar_remediation_fallback_pending_observation,
            policy_ready_local_only =
                policy.batch_expansion_allowed_for_scalar,
            public_claim_allowed = false),
        (model_group = :mgmfrm_mcmc_candidates,
            target_acceptance = controls.target_acceptance,
            source = :publication_grade_gate_default,
            policy_ready_local_only = true,
            public_claim_allowed = false),
        (model_group = :null_or_intercept_reference,
            target_acceptance = missing,
            source = :analytic_reference_no_mcmc,
            policy_ready_local_only = true,
            public_claim_allowed = false),
    ]
end

function batch_command_template(job, plan_path::AbstractString)
    base = "julia --project=. $(RUNNER_SCRIPT) --execution-unit $(job.execution_unit_id)"
    if job.mcmc_refit_required
        return string(base,
            " --plan ", plan_path,
            " --chains $(job.chains)",
            " --warmup-per-chain $(job.warmup_per_chain)",
            " --draws-per-chain $(job.draws_per_chain)",
            " --target-acceptance $(job.target_acceptance)",
            " --seed $(job.batch_seed)",
            " --output $(job.result_artifact_path)")
    end
    return string(base,
        " --plan ", plan_path,
        " --analytic-reference",
        " --output $(job.result_artifact_path)")
end

function command_template_rows(jobs, output_path::AbstractString)
    runner_path = joinpath(ROOT, RUNNER_SCRIPT)
    runner_exists = isfile(runner_path)
    runner_text = runner_exists ? read(runner_path, String) : ""
    runner_adapter_materialized =
        runner_exists &&
        occursin("\"--plan\"", runner_text) &&
        occursin("batch_execution_job_rows", runner_text)
    plan_path = rel(output_path)
    return [
        (execution_job_id = job.execution_job_id,
            execution_unit_id = job.execution_unit_id,
            scenario = job.scenario,
            model = job.model,
            fold = job.fold,
            runner_script = RUNNER_SCRIPT,
            runner_script_exists = runner_exists,
            runner_batch_plan_adapter_materialized =
                runner_adapter_materialized,
            command_template = batch_command_template(job, plan_path),
            command_status = runner_adapter_materialized ?
                :ready_not_executed : :planned_batch_runner_adapter_pending,
            execute_now = false,
            local_only = true,
            publication_or_registration_action = false,
            public_claim_allowed = false)
        for job in jobs
    ]
end

function result_artifact_target_rows(jobs)
    targets = (
        (target = :fit_result, suffix = "_result.json"),
        (target = :diagnostic_summary, suffix = "_diagnostics.json"),
        (target = :heldout_score_summary, suffix = "_heldout_score.json"),
    )
    rows = NamedTuple[]
    for job in jobs
        for target in targets
            push!(rows, (;
                execution_job_id = job.execution_job_id,
                execution_unit_id = job.execution_unit_id,
                model = job.model,
                fold = job.fold,
                artifact_target = target.target,
                path = string(joinpath(PROTOCOL.result_root,
                    String(job.execution_unit_id)), target.suffix),
                exists = false,
                required_before_public_claim = true,
                public_claim_allowed = false,
            ))
        end
    end
    return rows
end

function diagnostic_capture_rows(jobs, gate)
    gate_diagnostics = [
        as_symbol(row[:diagnostic])
        for row in gate[:diagnostic_gate_rows]
    ]
    rows = NamedTuple[]
    for job in jobs
        for diagnostic in gate_diagnostics
            applicable =
                job.mcmc_refit_required ||
                diagnostic in (
                    :pointwise_loglikelihood_finite,
                    :expected_score_calibration_recorded,
                )
            push!(rows, (;
                execution_job_id = job.execution_job_id,
                execution_unit_id = job.execution_unit_id,
                scenario = job.scenario,
                model = job.model,
                fold = job.fold,
                diagnostic,
                applicable,
                observed = false,
                passed = false,
                diagnostic_artifact_path = job.diagnostic_artifact_path,
                blocks_public_claim = true,
            ))
        end
    end
    return rows
end

function model_budget_rows(jobs)
    models = sort(unique(job.model for job in jobs); by = String)
    rows = NamedTuple[]
    for model in models
        model_jobs = [job for job in jobs if job.model === model]
        mcmc_jobs = [job for job in model_jobs if job.mcmc_refit_required]
        push!(rows, (;
            model,
            n_execution_units = length(model_jobs),
            n_mcmc_execution_units = length(mcmc_jobs),
            n_analytic_reference_units =
                length(model_jobs) - length(mcmc_jobs),
            target_acceptance =
                isempty(mcmc_jobs) ? missing : first(mcmc_jobs).target_acceptance,
            planned_chains = sum((job.chains for job in mcmc_jobs); init = 0),
            planned_posterior_draws =
                sum((job.chains * job.draws_per_chain for job in mcmc_jobs);
                    init = 0),
            planned_warmup_iterations =
                sum((job.chains * job.warmup_per_chain for job in mcmc_jobs);
                    init = 0),
            full_batch_execution_observed = false,
            public_claim_allowed = false,
        ))
    end
    return rows
end

function comparison_hook_rows()
    return [
        (hook = :publication_grade_batch_vs_deterministic_125_unit_anchor_scores,
            source_artifact =
                :mgmfrm_full_heldout_mcmc_refit_anchor_scoring,
            target_artifact =
                :mgmfrm_publication_grade_refit_batch_results_review,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :scalar_remediation_policy_reapplied_to_all_scalar_folds,
            source_artifact =
                :mgmfrm_publication_grade_refit_scalar_remediation_comparison,
            target_artifact =
                :mgmfrm_publication_grade_refit_batch_results_review,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :fit_threshold_shift_under_publication_grade_draws,
            source_artifact = :mgmfrm_fit_threshold_q_heldout_linkage,
            target_artifact =
                :mgmfrm_publication_grade_refit_batch_results_review,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
        (hook = :scenario_level_model_weight_sensitivity,
            source_artifact =
                :mgmfrm_validation_split_model_comparison_policy,
            target_artifact =
                :mgmfrm_publication_grade_refit_batch_results_review,
            comparison_status = :planned_not_executed,
            public_claim_allowed = false),
    ]
end

function blocker_rows(scalar_ready::Bool, runner_adapter_ready::Bool)
    rows = NamedTuple[]
    push!(rows, (blocker = :scalar_remediation_comparison_not_observed,
        blocks = :scalar_batch_sampler_policy_finalization,
        resolved = scalar_ready))
    push!(rows, (blocker = :publication_grade_batch_runner_adapter_not_materialized,
        blocks = :full_125_unit_publication_grade_batch_execution,
        resolved = runner_adapter_ready))
    push!(rows, (blocker = :full_125_unit_publication_grade_batch_not_executed,
        blocks = :public_kfold_model_comparison_claims,
        resolved = false))
    push!(rows, (blocker = :external_construct_dataset_missing,
        blocks = :public_construct_or_q_revision_claims,
        resolved = false))
    push!(rows, (blocker = :independent_public_scope_review_missing,
        blocks = :all_public_mgmfrm_claims,
        resolved = false))
    return rows
end

function no_publication_commands(commands)
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    return all(commands) do row
        lowered = lowercase(String(row.command_template))
        Bool(row.local_only) &&
            !Bool(row.publication_or_registration_action) &&
            all(!occursin(lowercase(term), lowered) for term in banned)
    end
end

function build_artifact(options)
    records = [
        input_record(:mgmfrm_full_heldout_mcmc_refit_execution_plan,
            options.execution_plan, EXECUTION_PLAN_SCHEMA),
        input_record(:mgmfrm_publication_grade_refit_gate,
            options.gate, GATE_SCHEMA),
        input_record(:mgmfrm_publication_grade_refit_scalar_remediation_comparison,
            options.scalar_comparison, SCALAR_COMPARISON_SCHEMA),
    ]
    execution_record = records[1]
    gate_record = records[2]
    scalar_record = records[3]
    execution_plan = load_json(options.execution_plan)
    gate = load_json(options.gate)
    scalar_comparison = load_json(options.scalar_comparison)
    controls = gate_controls(gate)
    policy = scalar_policy(scalar_comparison)

    jobs = batch_unit_rows(execution_plan, controls, policy)
    target_policies = target_acceptance_policy_rows(policy, controls)
    commands = command_template_rows(jobs, options.output)
    targets = result_artifact_target_rows(jobs)
    diagnostics = diagnostic_capture_rows(jobs, gate)
    budgets = model_budget_rows(jobs)
    comparisons = comparison_hook_rows()
    runner_adapter_ready =
        all(row -> Bool(row.runner_batch_plan_adapter_materialized), commands)
    scalar_ready = policy.batch_expansion_allowed_for_scalar
    blockers = blocker_rows(scalar_ready, runner_adapter_ready)

    all_input_artifacts_present = all(record -> record.exists, records)
    all_expected_schemas = all(record -> record.schema_matches, records)
    all_input_summaries_passed = all(record -> record.summary_passed, records)
    execution_plan_passed = Bool(execution_record.summary.passed)
    gate_passed = Bool(gate_record.summary.passed)
    scalar_remediation_comparison_passed =
        Bool(scalar_record.summary.passed)
    scalar_target_acceptance_policy_recorded =
        Bool(scalar_record.summary.scalar_batch_target_acceptance_policy_recorded)
    expected_units =
        Int(execution_record.summary.n_scenarios) *
        Int(execution_record.summary.n_models) *
        Int(execution_record.summary.n_folds)
    batch_unit_rows_recorded = !isempty(jobs)
    all_125_units_materialized =
        length(jobs) == expected_units &&
        length(jobs) == 125 &&
        count(job -> job.model === :scalar_gmfrm_baseline, jobs) == 25 &&
        count(job -> job.model === :null_or_intercept_reference, jobs) == 25
    command_templates_recorded =
        length(commands) == length(jobs) &&
        all(row -> !Bool(row.execute_now), commands)
    result_artifact_targets_recorded =
        length(targets) == 3 * length(jobs) &&
        all(row -> Bool(row.required_before_public_claim), targets)
    diagnostic_capture_manifest_recorded =
        length(diagnostics) ==
            length(jobs) * length(gate[:diagnostic_gate_rows]) &&
        all(row -> Bool(row.blocks_public_claim), diagnostics)
    runner_adapter_state_recorded =
        all(row -> haskey(row, :runner_batch_plan_adapter_materialized),
            commands)
    full_125_unit_publication_grade_batch_completed = false
    no_public_fit_metric_claim = true
    no_public_q_revision_claim = true
    no_public_model_weight_claim = true
    no_sparse_superiority_claim = true
    no_publication = no_publication_commands(commands)

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        execution_plan_passed &&
        gate_passed &&
        scalar_remediation_comparison_passed &&
        batch_unit_rows_recorded &&
        all_125_units_materialized &&
        scalar_target_acceptance_policy_recorded &&
        command_templates_recorded &&
        result_artifact_targets_recorded &&
        diagnostic_capture_manifest_recorded &&
        runner_adapter_state_recorded &&
        !full_125_unit_publication_grade_batch_completed &&
        no_public_fit_metric_claim &&
        no_public_q_revision_claim &&
        no_public_model_weight_claim &&
        no_sparse_superiority_claim &&
        no_publication

    n_mcmc_jobs = count(job -> Bool(job.mcmc_refit_required), jobs)
    n_scalar_jobs = count(job -> job.model === :scalar_gmfrm_baseline, jobs)
    n_reference_jobs =
        count(job -> job.model === :null_or_intercept_reference, jobs)
    batch_sampler_policy_ready_local_only =
        scalar_ready &&
        all(row -> Bool(row.policy_ready_local_only), target_policies)
    batch_execution_ready_local_only =
        batch_sampler_policy_ready_local_only && runner_adapter_ready
    recommendation = batch_execution_ready_local_only ?
        :execute_publication_grade_batch_locally_keep_claims_blocked :
        (!batch_sampler_policy_ready_local_only ?
            :attach_local_scalar_remediation_comparison_before_batch_execution :
            :materialize_batch_runner_adapter_keep_claims_blocked)
    next_gate = batch_execution_ready_local_only ?
        :execute_publication_grade_refit_batch_locally :
        (!batch_sampler_policy_ready_local_only ?
            :attach_local_scalar_remediation_comparison_before_batch_execution :
            :materialize_publication_grade_batch_runner_adapter)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_expansion_plan.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_batch_expansion_plan,
        status =
            :publication_grade_refit_batch_expansion_plan_recorded,
        decision =
            :record_publication_grade_refit_batch_expansion_plan,
        public_fit = true,
        experimental_public = true,
        fit_ready = false,
        harness_ready = true,
        execution_ready = batch_execution_ready_local_only,
        local_only = true,
        publication_or_registration_action = false,
        publication_grade_batch_plan_recorded = true,
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
        target_acceptance_policy_rows = target_policies,
        batch_execution_job_rows = jobs,
        command_template_rows = commands,
        result_artifact_target_rows = targets,
        diagnostic_capture_rows = diagnostics,
        model_budget_rows = budgets,
        comparison_hook_rows = comparisons,
        blocker_rows = blockers,
        decision_record = (;
            selected_decision =
                :record_full_batch_expansion_plan_before_heavy_execution,
            publication_grade_batch_plan_recorded = true,
            scalar_remediation_comparison_observed =
                Bool(scalar_record.summary.comparison_observed),
            scalar_target_acceptance =
                policy.effective_scalar_target_acceptance,
            scalar_batch_sampler_policy_ready_local_only =
                batch_sampler_policy_ready_local_only,
            batch_runner_adapter_materialized = runner_adapter_ready,
            batch_execution_ready_local_only,
            full_125_unit_publication_grade_batch_completed,
            public_fit_metric_claim_allowed = false,
            public_q_revision_claim_allowed = false,
            model_weight_or_sparse_superiority_claim_allowed = false,
            required_followup = next_gate,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            execution_plan_passed,
            gate_passed,
            scalar_remediation_comparison_passed,
            scalar_remediation_comparison_observed =
                Bool(scalar_record.summary.comparison_observed),
            scalar_remediation_success_observed =
                Bool(scalar_record.summary.remediation_success_observed),
            scalar_target_acceptance_policy_recorded,
            scalar_target_acceptance =
                policy.effective_scalar_target_acceptance,
            scalar_batch_sampler_policy_ready_local_only =
                batch_sampler_policy_ready_local_only,
            batch_unit_rows_recorded,
            all_125_units_materialized,
            command_templates_recorded,
            result_artifact_targets_recorded,
            diagnostic_capture_manifest_recorded,
            runner_adapter_state_recorded,
            batch_runner_adapter_materialized = runner_adapter_ready,
            batch_execution_ready_local_only,
            full_125_unit_publication_grade_batch_completed,
            external_construct_dataset_attached = false,
            external_construct_validation_completed = false,
            no_public_fit_metric_claim,
            no_public_q_revision_claim,
            no_public_model_weight_claim,
            no_sparse_superiority_claim,
            n_input_artifacts = length(records),
            n_batch_execution_job_rows = length(jobs),
            n_mcmc_execution_jobs = n_mcmc_jobs,
            n_scalar_execution_jobs = n_scalar_jobs,
            n_scalar_target_acceptance_0p90_jobs =
                count(job -> job.model === :scalar_gmfrm_baseline &&
                    !ismissing(job.target_acceptance) &&
                    Float64(job.target_acceptance) == 0.9,
                    jobs),
            n_mgmfrm_target_acceptance_0p80_jobs =
                count(job -> job.model !== :scalar_gmfrm_baseline &&
                    job.model !== :null_or_intercept_reference &&
                    !ismissing(job.target_acceptance) &&
                    Float64(job.target_acceptance) == 0.8,
                    jobs),
            n_analytic_reference_jobs = n_reference_jobs,
            n_command_template_rows = length(commands),
            n_result_artifact_target_rows = length(targets),
            n_diagnostic_capture_rows = length(diagnostics),
            n_model_budget_rows = length(budgets),
            n_comparison_hook_rows = length(comparisons),
            n_blocker_rows = length(blockers),
            n_review_cells =
                length(jobs) + length(commands) + length(targets) +
                length(diagnostics) + length(budgets) + length(comparisons),
            planned_chains = sum(job.chains for job in jobs),
            planned_posterior_draws =
                sum(job.chains * job.draws_per_chain for job in jobs),
            planned_warmup_iterations =
                sum(job.chains * job.warmup_per_chain for job in jobs),
            n_blockers = count(row -> !row.resolved, blockers),
            remaining_public_blockers =
                [row.blocker for row in blockers if !row.resolved],
            recommendation,
            next_gate,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_artifact(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("passed=", artifact.summary.passed,
        " jobs=", artifact.summary.n_batch_execution_job_rows,
        " scalar_ta=", artifact.summary.scalar_target_acceptance,
        " execution_ready=",
        artifact.summary.batch_execution_ready_local_only,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
