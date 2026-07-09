#!/usr/bin/env julia

using Dates
using JSON3
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const TRACKED_PLAN = joinpath(ROOT, "test", "fixtures",
    "mgmfrm_publication_grade_refit_batch_expansion_plan.json")
const LOCAL_READY_PLAN = joinpath(ROOT, "artifacts",
    "publication_grade_refit_pilot_remediation",
    "current_batch_expansion_plan.json")
const DEFAULT_PLAN = TRACKED_PLAN
const DEFAULT_GATE = joinpath(ROOT, "test", "fixtures",
    "mgmfrm_publication_grade_refit_gate.json")
const DEFAULT_RUNNER = joinpath(ROOT, "scripts",
    "run_mgmfrm_publication_grade_refit_job.jl")
const DEFAULT_MANIFEST = joinpath(ROOT, "artifacts",
    "publication_grade_refit_batch",
    "batch_orchestrator_manifest.json")
const DEFAULT_LOG_DIR = joinpath(ROOT, "artifacts",
    "publication_grade_refit_batch", "logs")

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Orchestrate local publication-grade MGMFRM refit batch jobs.

    This script reads the tracked 125-unit batch expansion plan by default and
    calls the single job runner in a resumable, local-only way. It is safe by
    default: without --execute or --materialize-dry-run-artifacts it only writes
    a manifest and runs no jobs. Execution modes require --max-jobs, --all, or
    explicit --execution-unit selection. Pass --plan explicitly to use an
    ignored local-ready plan.

    Usage:
      julia --project=. scripts/run_mgmfrm_publication_grade_refit_batch.jl [options]

    Options:
      --plan PATH                         Batch expansion plan path.
      --gate PATH                         Diagnostic gate fixture path.
      --runner PATH                       Single-job runner path.
      --output PATH                       Orchestrator manifest path.
      --log-dir PATH                      Per-job log directory.
      --execute                           Run selected jobs.
      --materialize-dry-run-artifacts     Run selected jobs with runner --dry-run.
      --max-jobs N                        Maximum selected jobs to act on.
      --all                               Act on all matching pending jobs.
      --execution-unit ID                 Limit to an execution unit; repeatable.
      --scenario CSV                      Limit to scenario name(s).
      --model CSV                         Limit to model name(s).
      --fold CSV                          Limit to fold number(s).
      --analytic-reference-only           Limit to analytic reference jobs.
      --mcmc-only                         Limit to MCMC refit jobs.
      --force                             Re-run even if output artifacts exist.
      --allow-blocked-plan                Allow action when plan summary is not ready.
      --continue-on-error                 Continue after a failed job.
      --ppc-draws N                       Override runner PPC draw cap.
      --progress                          Pass sampler progress through to runner.
    """
end

project_version() = String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])
as_string(value) = String(value)
as_bool(value) = Bool(value)
as_int(value) = Int(value)
as_float(value) = Float64(value)
as_symbol(value) = Symbol(String(value))

function load_json(path::AbstractString)
    return JSON3.read(read(path, String))
end

function rel(path::AbstractString)
    return relpath(path, ROOT)
end

function root_path(path::AbstractString)
    return isabspath(path) ? normpath(path) : normpath(joinpath(ROOT, path))
end

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

function split_csv!(values::Vector{String}, text::AbstractString)
    for part in split(text, ",")
        value = strip(part)
        isempty(value) || push!(values, String(value))
    end
    return values
end

function split_int_csv!(values::Vector{Int}, text::AbstractString)
    for part in split(text, ",")
        value = strip(part)
        isempty(value) || push!(values, parse(Int, value))
    end
    return values
end

function parse_args(args)
    plan = DEFAULT_PLAN
    gate = DEFAULT_GATE
    runner = DEFAULT_RUNNER
    output = DEFAULT_MANIFEST
    log_dir = DEFAULT_LOG_DIR
    action = :plan_only
    max_jobs = nothing
    run_all = false
    execution_units = String[]
    scenarios = String[]
    models = String[]
    folds = Int[]
    analytic_reference_only = false
    mcmc_only = false
    force = false
    allow_blocked_plan = false
    stop_on_error = true
    ppc_draws = nothing
    progress = false

    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--plan"
            index < length(args) || error("--plan requires a path")
            plan = abspath(args[index + 1])
            index += 2
        elseif arg == "--gate"
            index < length(args) || error("--gate requires a path")
            gate = abspath(args[index + 1])
            index += 2
        elseif arg == "--runner"
            index < length(args) || error("--runner requires a path")
            runner = abspath(args[index + 1])
            index += 2
        elseif arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--log-dir"
            index < length(args) || error("--log-dir requires a path")
            log_dir = abspath(args[index + 1])
            index += 2
        elseif arg == "--execute"
            action === :plan_only ||
                error("choose only one of --execute and --materialize-dry-run-artifacts")
            action = :execute
            index += 1
        elseif arg == "--materialize-dry-run-artifacts"
            action === :plan_only ||
                error("choose only one of --execute and --materialize-dry-run-artifacts")
            action = :materialize_dry_run_artifacts
            index += 1
        elseif arg == "--max-jobs"
            index < length(args) || error("--max-jobs requires an integer")
            max_jobs = parse(Int, args[index + 1])
            max_jobs >= 0 || error("--max-jobs must be non-negative")
            index += 2
        elseif arg == "--all"
            run_all = true
            index += 1
        elseif arg == "--execution-unit"
            index < length(args) || error("--execution-unit requires an id")
            push!(execution_units, String(args[index + 1]))
            index += 2
        elseif arg == "--scenario"
            index < length(args) || error("--scenario requires a CSV value")
            split_csv!(scenarios, args[index + 1])
            index += 2
        elseif arg == "--model"
            index < length(args) || error("--model requires a CSV value")
            split_csv!(models, args[index + 1])
            index += 2
        elseif arg == "--fold"
            index < length(args) || error("--fold requires a CSV value")
            split_int_csv!(folds, args[index + 1])
            index += 2
        elseif arg == "--analytic-reference-only"
            analytic_reference_only = true
            index += 1
        elseif arg == "--mcmc-only"
            mcmc_only = true
            index += 1
        elseif arg == "--force"
            force = true
            index += 1
        elseif arg == "--allow-blocked-plan"
            allow_blocked_plan = true
            index += 1
        elseif arg == "--continue-on-error"
            stop_on_error = false
            index += 1
        elseif arg == "--ppc-draws"
            index < length(args) || error("--ppc-draws requires an integer")
            ppc_draws = parse(Int, args[index + 1])
            ppc_draws >= 1 || error("--ppc-draws must be positive")
            index += 2
        elseif arg == "--progress"
            progress = true
            index += 1
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end

    analytic_reference_only && mcmc_only &&
        error("choose only one of --analytic-reference-only and --mcmc-only")
    if action !== :plan_only && !run_all && max_jobs === nothing &&
            isempty(execution_units)
        error("execution modes require --max-jobs N, --all, or --execution-unit")
    end

    return (;
        plan,
        gate,
        runner,
        output,
        log_dir,
        action,
        max_jobs,
        run_all,
        execution_units,
        scenarios,
        models,
        folds,
        analytic_reference_only,
        mcmc_only,
        force,
        allow_blocked_plan,
        stop_on_error,
        ppc_draws,
        progress,
    )
end

function require_batch_plan(plan, options)
    scope = as_symbol(json_get(plan, :scope, :unknown))
    scope === :publication_grade_refit_batch_expansion_plan ||
        error("plan is not a publication-grade refit batch expansion plan")
    ready = json_bool(plan[:summary], :batch_execution_ready_local_only, false)
    if options.action !== :plan_only && !ready && !options.allow_blocked_plan
        error("plan summary is not batch-execution-ready; pass a local-ready plan or --allow-blocked-plan")
    end
    return ready
end

function rows_as_vector(fixture, key::Symbol)
    return [row for row in fixture[key]]
end

function filtered_jobs(jobs, options)
    unit_filter = Set(options.execution_units)
    scenario_filter = Set(options.scenarios)
    model_filter = Set(options.models)
    fold_filter = Set(options.folds)
    return [job for job in jobs if
        (isempty(unit_filter) ||
            as_string(job[:execution_unit_id]) in unit_filter) &&
        (isempty(scenario_filter) ||
            as_string(job[:scenario]) in scenario_filter) &&
        (isempty(model_filter) ||
            as_string(job[:model]) in model_filter) &&
        (isempty(fold_filter) || as_int(job[:fold]) in fold_filter) &&
        (!options.analytic_reference_only ||
            as_string(job[:model]) == "null_or_intercept_reference") &&
        (!options.mcmc_only || as_bool(job[:mcmc_refit_required]))]
end

function artifact_paths(job)
    return (;
        result = root_path(as_string(job[:result_artifact_path])),
        diagnostics = root_path(as_string(job[:diagnostic_artifact_path])),
        heldout = root_path(as_string(job[:heldout_score_artifact_path])),
    )
end

function result_summary_state(path::AbstractString)
    isfile(path) || return (; executed = false, dry_run = false)
    try
        artifact = load_json(path)
        summary = artifact[:summary]
        return (;
            executed = json_bool(summary, :executed, false),
            dry_run = json_bool(summary, :dry_run, false),
        )
    catch
        return (; executed = false, dry_run = false)
    end
end

function artifact_state(job)
    paths = artifact_paths(job)
    result_exists = isfile(paths.result)
    diagnostics_exists = isfile(paths.diagnostics)
    heldout_exists = isfile(paths.heldout)
    summary = result_summary_state(paths.result)
    all_present = result_exists && diagnostics_exists && heldout_exists
    any_present = result_exists || diagnostics_exists || heldout_exists
    status =
        all_present && summary.executed ? :complete_executed :
        all_present && summary.dry_run ? :dry_run_artifacts_present :
        any_present ? :partial_artifacts_present :
        :pending
    return (;
        status,
        result_exists,
        diagnostics_exists,
        heldout_exists,
        executed = summary.executed,
        dry_run = summary.dry_run,
    )
end

function skip_existing(action::Symbol, state, force::Bool)
    force && return false
    action === :execute && return state.status === :complete_executed
    action === :materialize_dry_run_artifacts &&
        return state.status !== :pending
    return false
end

function julia_executable()
    return joinpath(Sys.BINDIR, Base.julia_exename())
end

function push_option!(args::Vector{String}, option::AbstractString, value)
    push!(args, option)
    push!(args, string(value))
    return args
end

function command_args(job, options)
    paths = artifact_paths(job)
    args = String[
        julia_executable(),
        string("--project=", ROOT),
        options.runner,
        "--plan",
        options.plan,
        "--gate",
        options.gate,
        "--execution-unit",
        as_string(job[:execution_unit_id]),
        "--output",
        paths.result,
    ]
    if as_bool(job[:mcmc_refit_required])
        push_option!(args, "--chains", as_int(job[:chains]))
        push_option!(args, "--warmup-per-chain",
            as_int(job[:warmup_per_chain]))
        push_option!(args, "--draws-per-chain",
            as_int(job[:draws_per_chain]))
        push_option!(args, "--target-acceptance",
            as_float(job[:target_acceptance]))
        push_option!(args, "--seed", as_int(job[:batch_seed]))
    else
        push!(args, "--analytic-reference")
    end
    options.action === :materialize_dry_run_artifacts &&
        push!(args, "--dry-run")
    options.ppc_draws === nothing ||
        push_option!(args, "--ppc-draws", options.ppc_draws)
    options.progress && push!(args, "--progress")
    return args
end

function shell_quote(value::AbstractString)
    return "'" * replace(value, "'" => "'\\''") * "'"
end

command_string(args::Vector{String}) = join(shell_quote.(args), " ")

function log_path(job, options)
    stamp = Dates.format(Dates.now(), dateformat"yyyymmdd_HHMMSS")
    unit = as_string(job[:execution_unit_id])
    return joinpath(options.log_dir, string(stamp, "__", unit, ".log"))
end

function run_command(args::Vector{String}, log_file::AbstractString)
    started_at = Dates.now()
    mkpath(dirname(log_file))
    ok = false
    error_text = missing
    try
        open(log_file, "w") do io
            println(io, "command=", command_string(args))
            println(io, "started_at=", started_at)
            flush(io)
            run(pipeline(Cmd(args); stdout = io, stderr = io))
        end
        ok = true
    catch err
        error_text = sprint(showerror, err)
    end
    finished_at = Dates.now()
    return (;
        ok,
        started_at = string(started_at),
        finished_at = string(finished_at),
        elapsed_ms = Dates.value(finished_at - started_at),
        error = error_text,
    )
end

function job_status_counts(jobs)
    states = [artifact_state(job).status for job in jobs]
    return (;
        complete_executed =
            count(status -> status === :complete_executed, states),
        dry_run_artifacts_present =
            count(status -> status === :dry_run_artifacts_present, states),
        partial_artifacts_present =
            count(status -> status === :partial_artifacts_present, states),
        pending = count(status -> status === :pending, states),
    )
end

function build_manifest(options)
    plan = load_json(options.plan)
    plan_ready = require_batch_plan(plan, options)
    jobs = rows_as_vector(plan, :batch_execution_job_rows)
    matching_jobs = filtered_jobs(jobs, options)
    limit =
        options.run_all || options.max_jobs === nothing ?
        length(matching_jobs) : Int(options.max_jobs)

    rows = NamedTuple[]
    selected_count = 0
    attempted_count = 0
    failed_count = 0
    stopped_after_failure = false

    for job in matching_jobs
        before = artifact_state(job)
        args = command_args(job, options)
        paths = artifact_paths(job)
        skip_reason = missing
        selected = false
        action_status = :skipped
        run_result = (;
            ok = missing,
            started_at = missing,
            finished_at = missing,
            elapsed_ms = missing,
            error = missing,
        )
        log_file = options.action === :plan_only ? missing : log_path(job, options)

        if stopped_after_failure
            skip_reason = :stopped_after_previous_failure
        elseif skip_existing(options.action, before, options.force)
            skip_reason = before.status
        elseif selected_count >= limit
            skip_reason = :max_jobs_reached
        else
            selected = true
            selected_count += 1
            if options.action === :plan_only
                action_status = :planned_not_run
            else
                attempted_count += 1
                run_result = run_command(args, log_file)
                if Bool(run_result.ok)
                    action_status = options.action === :execute ?
                        :executed : :dry_run_artifacts_materialized
                else
                    failed_count += 1
                    action_status = :failed
                    if options.stop_on_error
                        stopped_after_failure = true
                    end
                end
            end
        end

        after = artifact_state(job)
        push!(rows, (;
            execution_unit_id = as_symbol(job[:execution_unit_id]),
            scenario = as_symbol(job[:scenario]),
            model = as_symbol(job[:model]),
            fold = as_int(job[:fold]),
            mcmc_refit_required = as_bool(job[:mcmc_refit_required]),
            analytic_reference_scored =
                as_bool(job[:analytic_reference_scored]),
            target_acceptance =
                json_get(job, :target_acceptance, missing),
            status_before = before.status,
            status_after = after.status,
            selected_for_action = selected,
            skipped_reason = skip_reason,
            action_status,
            command = command_string(args),
            log_path = ismissing(log_file) ? missing : rel(log_file),
            result_artifact_path = rel(paths.result),
            diagnostic_artifact_path = rel(paths.diagnostics),
            heldout_score_artifact_path = rel(paths.heldout),
            result_exists_before = before.result_exists,
            diagnostics_exists_before = before.diagnostics_exists,
            heldout_exists_before = before.heldout_exists,
            result_exists_after = after.result_exists,
            diagnostics_exists_after = after.diagnostics_exists,
            heldout_exists_after = after.heldout_exists,
            command_started_at = run_result.started_at,
            command_finished_at = run_result.finished_at,
            command_elapsed_ms = run_result.elapsed_ms,
            command_error = run_result.error,
            public_claim_allowed = false,
        ))
    end

    status_after = job_status_counts(jobs)
    full_batch_completed =
        status_after.complete_executed == length(jobs) && length(jobs) == 125
    next_gate =
        failed_count > 0 ? :inspect_failed_publication_grade_refit_batch_logs :
        full_batch_completed ?
            :generate_publication_grade_refit_batch_results_review :
        attempted_count > 0 ?
            :run_remaining_publication_grade_refit_batch_jobs :
        :execute_publication_grade_refit_batch_locally

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_publication_grade_refit_batch_orchestrator_run.v1",
        family = :mgmfrm,
        scope = :publication_grade_refit_batch_orchestrator,
        status = :publication_grade_refit_batch_orchestrator_manifest_recorded,
        decision = :orchestrate_local_publication_grade_refit_batch,
        local_only = true,
        publication_or_registration_action = false,
        public_claim_allowed = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        generated_at = string(Dates.now()),
        input_artifacts = [
            (artifact = :mgmfrm_publication_grade_refit_batch_expansion_plan,
                path = rel(options.plan),
                exists = isfile(options.plan)),
            (artifact = :mgmfrm_publication_grade_refit_gate,
                path = rel(options.gate),
                exists = isfile(options.gate)),
            (artifact = :mgmfrm_publication_grade_refit_job_runner,
                path = rel(options.runner),
                exists = isfile(options.runner)),
        ],
        options = (;
            action = options.action,
            max_jobs = options.max_jobs,
            run_all = options.run_all,
            execution_units = options.execution_units,
            scenarios = options.scenarios,
            models = options.models,
            folds = options.folds,
            analytic_reference_only = options.analytic_reference_only,
            mcmc_only = options.mcmc_only,
            force = options.force,
            allow_blocked_plan = options.allow_blocked_plan,
            stop_on_error = options.stop_on_error,
            ppc_draws = options.ppc_draws,
            progress = options.progress,
        ),
        job_selection_rows = rows,
        summary = (;
            passed = failed_count == 0,
            plan_batch_execution_ready_local_only = plan_ready,
            action = options.action,
            n_plan_jobs = length(jobs),
            n_matching_jobs = length(matching_jobs),
            n_selected_for_action = selected_count,
            n_attempted_jobs = attempted_count,
            n_failed_jobs = failed_count,
            n_successful_action_jobs =
                count(row -> row.action_status in
                    (:executed, :dry_run_artifacts_materialized), rows),
            n_skipped_jobs =
                count(row -> row.action_status === :skipped, rows),
            status_after,
            full_125_unit_publication_grade_batch_completed =
                full_batch_completed,
            public_fit_metric_claim_allowed = false,
            public_model_weight_claim_allowed = false,
            sparse_superiority_claim_allowed = false,
            next_gate,
        ),
    )
end

function main(args)
    options = parse_args(args)
    artifact = build_manifest(options)
    write_artifact(options.output, artifact)
    println("wrote ", rel(options.output))
    println("action=", artifact.summary.action,
        " selected=", artifact.summary.n_selected_for_action,
        " attempted=", artifact.summary.n_attempted_jobs,
        " failed=", artifact.summary.n_failed_jobs,
        " complete=", artifact.summary.status_after.complete_executed,
        " next_gate=", artifact.summary.next_gate,
        " public_claim_allowed=false")
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
