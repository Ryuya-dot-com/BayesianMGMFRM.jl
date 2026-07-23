#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "local_dependence_pilot_protocol_preflight.json",
)
const PILOT_SOURCE =
    joinpath(ROOT, "src", "local_dependence_calibration_pilot.jl")
const BAYESIAN_FIT_SOURCE =
    joinpath(ROOT, "src", "bayesian_fit.jl")
const CALIBRATION_SOURCE =
    joinpath(ROOT, "src", "local_dependence_calibration.jl")
const SIMULATION_SOURCE =
    joinpath(ROOT, "src", "local_dependence_simulation.jl")
const LD1A_FIXTURE = joinpath(
    ROOT, "test", "fixtures", "local_dependence_known_truth_preflight.json")
const LD1B0_FIXTURE = joinpath(
    ROOT, "test", "fixtures",
    "local_dependence_calibration_scorer_preflight.json")

include(joinpath(@__DIR__, "local_json.jl"))

function usage()
    return """
    Generate the deterministic, MCMC-free LD1b1 pilot-protocol preflight.

    The artifact materializes compact pilot jobs, reserves evaluation seed
    namespaces, and records execution-capability status. It does not generate
    response data, fit a model, run MCMC, compute a diagnostic, freeze a
    threshold profile, or provide calibration evidence.

    Usage:
      julia --project=. scripts/generate_local_dependence_pilot_protocol_preflight.jl [--output PATH]
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

function project_value(section::AbstractString, key::AbstractString)
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project[section][key])
end

project_version() = String(TOML.parsefile(
    joinpath(ROOT, "Project.toml"))["version"])

file_sha256(path::AbstractString) = bytes2hex(open(sha256, path))

function canonical_json_sha256(value)
    io = IOBuffer()
    write_canonical_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

function json_native(value)
    if value isa AbstractDict
        return Dict(String(key) => json_native(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractArray || value isa Tuple
        return [json_native(element) for element in value]
    end
    return value
end

function dependency_record(name::Symbol, path::AbstractString,
        expected_schema::AbstractString)
    parsed = JSON3.read(read(path, String))
    String(parsed[:schema]) == expected_schema || error(
        "unexpected dependency schema at $(relpath(path, ROOT))")
    native = json_native(parsed)
    haskey(native, "content_hash") || error(
        "dependency lacks content_hash: $(relpath(path, ROOT))")
    stored = String(native["content_hash"]["value"])
    delete!(native, "content_hash")
    recomputed = canonical_json_sha256(native)
    stored == recomputed || error(
        "dependency content hash mismatch: $(relpath(path, ROOT))")
    return (;
        artifact = name,
        path = relpath(path, ROOT),
        expected_schema,
        file_sha256 = file_sha256(path),
        content_hash = (;
            algorithm = :sha256,
            value = stored,
            verified = true,
            canonical_format = :local_json_sorted_compact,
        ),
    )
end

function replication_seed_rows(plan_rows)
    replications = sort(unique(row.replication for row in plan_rows))
    return Tuple((;
        replication,
        seed = only(unique(row.seed for row in plan_rows
            if row.replication == replication)),
    ) for replication in replications)
end

function evaluation_namespace_reservation(base_seed::Int,
        n_persons::Int, n_testlets::Int, items_per_testlet::Int,
        n_raters::Int, n_categories::Int)
    initial = BayesianMGMFRM.local_dependence_simulation_grid(;
        repetitions = 50,
        base_seed,
        phase = :evaluation,
        grid_id = "ld1b1_evaluation_initial_reserved",
        n_persons,
        n_testlets,
        items_per_testlet,
        n_raters,
        n_categories,
    )
    maximum = BayesianMGMFRM.local_dependence_simulation_grid(;
        repetitions = 100,
        base_seed,
        phase = :evaluation,
        grid_id = "ld1b1_evaluation_maximum_reserved",
        n_persons,
        n_testlets,
        items_per_testlet,
        n_raters,
        n_categories,
    )
    initial_seeds = replication_seed_rows(initial)
    maximum_seeds = replication_seed_rows(maximum)
    initial_prefix_matches = initial_seeds == maximum_seeds[1:50]
    return (;
        phase = :evaluation,
        initial_repetitions = 50,
        maximum_repetitions = 100,
        n_scenarios = 22,
        initial_plan_rows = length(initial),
        maximum_plan_rows = length(maximum),
        initial_replication_seeds = initial_seeds,
        maximum_replication_seeds = maximum_seeds,
        initial_is_prefix_of_maximum = initial_prefix_matches,
        seed_namespace_reserved = true,
        generated_data = false,
        model_fit_run = false,
        mcmc_run = false,
        diagnostic_run = false,
    )
end

function all_boolean_checks(checks)
    return all(value -> !(value isa Bool) || value, values(checks))
end

function build_artifact()
    base_seed = 20260720
    dimensions = (;
        n_persons = 40,
        n_testlets = 4,
        items_per_testlet = 3,
        n_raters = 4,
        n_categories = 4,
    )
    pilot_plan = BayesianMGMFRM.local_dependence_simulation_grid(;
        repetitions = 30,
        base_seed,
        phase = :pilot,
        grid_id = "ld1b1_pilot_protocol_preflight",
        dimensions...,
    )
    contract =
        BayesianMGMFRM.local_dependence_calibration_pilot_contract()
    preflight = BayesianMGMFRM.local_dependence_calibration_pilot_preflight(
        pilot_plan;
        contract,
    )
    reservation = evaluation_namespace_reservation(base_seed, values(dimensions)...)
    pilot_seeds = Set(row.seed for row in pilot_plan)
    evaluation_seeds = Set(row.seed
        for row in reservation.maximum_replication_seeds)
    dependencies = (
        dependency_record(
            :local_dependence_known_truth_preflight,
            LD1A_FIXTURE,
            "bayesianmgmfrm.local_dependence_known_truth_preflight.v1",
        ),
        dependency_record(
            :local_dependence_calibration_scorer_preflight,
            LD1B0_FIXTURE,
            "bayesianmgmfrm.local_dependence_calibration_scorer_preflight.v1",
        ),
    )

    checks = (;
        pilot = (;
            plan_rows = length(pilot_plan) == 660,
            preflight_rows = preflight.n_plan_rows == 660,
            scenarios = preflight.n_scenarios == 22,
            replications = preflight.n_replications == 30,
            fit_jobs = preflight.n_fit_jobs == 540,
            pre_fit_rejection_jobs =
                preflight.n_pre_fit_rejection_jobs == 120,
            compact_jobs_complete = length(preflight.job_rows) == 660,
            plan_checks_pass = all_boolean_checks(preflight.plan_checks),
            resource_checks_pass =
                all_boolean_checks(preflight.resource_summary.checks),
            seed_checks_pass = all_boolean_checks(preflight.seed_checks),
        ),
        evaluation = (;
            initial_rows = reservation.initial_plan_rows == 1_100,
            maximum_rows = reservation.maximum_plan_rows == 2_200,
            initial_seeds =
                length(reservation.initial_replication_seeds) == 50,
            maximum_seeds =
                length(reservation.maximum_replication_seeds) == 100,
            initial_prefix_matches =
                reservation.initial_is_prefix_of_maximum,
            pilot_seed_namespace_disjoint = isempty(
                intersect(pilot_seeds, evaluation_seeds)),
        ),
        dependencies = (;
            all_present = all(row -> isfile(joinpath(ROOT, row.path)),
                dependencies),
            all_content_hashes_verified = all(row ->
                row.content_hash.verified, dependencies),
        ),
        claim_boundary = (;
            execution_authorized =
                preflight.pilot_execution_authorized,
            capability_requirements_met =
                preflight.sampler_capability.requirement_met,
            capability_blockers_empty =
                isempty(preflight.capability_blockers),
            pilot_incomplete = !preflight.pilot_execution_completed,
            freeze_incomplete = !preflight.evaluation_profile_frozen,
            calibration_unavailable =
                !preflight.calibration_evidence_available,
            labels_unavailable =
                !preflight.diagnostic_decision_labels_available,
            mechanism_unavailable =
                !preflight.mechanism_interpretation_eligible,
        ),
    )
    passed = all(all_boolean_checks(section) for section in values(checks))

    artifact = (;
        schema =
            "bayesianmgmfrm.local_dependence_pilot_protocol_preflight.v1",
        family = :mfrm,
        scope = :ld1b1_pilot_execution_protocol_preflight_noncalibration,
        status = passed ? :pilot_protocol_preflight_passed :
            :pilot_protocol_preflight_failed,
        package = (;
            name = :BayesianMGMFRM,
            version = project_version(),
        ),
        generator = (;
            script =
                "scripts/generate_local_dependence_pilot_protocol_preflight.jl",
            script_source_sha256 = file_sha256(@__FILE__),
            pilot_source = "src/local_dependence_calibration_pilot.jl",
            pilot_source_sha256 = file_sha256(PILOT_SOURCE),
            diagnostic_source = "src/bayesian_fit.jl",
            diagnostic_source_sha256 = file_sha256(BAYESIAN_FIT_SOURCE),
            calibration_source = "src/local_dependence_calibration.jl",
            calibration_source_sha256 = file_sha256(CALIBRATION_SOURCE),
            simulation_source = "src/local_dependence_simulation.jl",
            simulation_source_sha256 = file_sha256(SIMULATION_SOURCE),
            environment_provenance = (;
                project = "Project.toml",
                project_sha256 = file_sha256(joinpath(ROOT, "Project.toml")),
                manifest = "Manifest.toml",
                manifest_sha256 = file_sha256(joinpath(ROOT, "Manifest.toml")),
                julia_compat = project_value("compat", "julia"),
                exact_runtime_version_recorded = false,
                cross_julia_bitwise_portability_claimed = false,
            ),
        ),
        dependencies,
        execution_scope = (;
            phase = :pilot,
            base_seed,
            dimensions,
            n_planned_jobs = 660,
            n_fit_jobs = 540,
            n_pre_fit_rejection_jobs = 120,
            generates_response_data = false,
            runs_design_preflight = false,
            runs_model_fit = false,
            runs_mcmc = false,
            runs_local_dependence_summary = false,
            stores_performance_rates = false,
            stores_mechanism_classifications = false,
        ),
        pilot_contract = contract,
        pilot_preflight = preflight,
        evaluation_namespace_reservation = reservation,
        precision_reference = preflight.precision_reference,
        capability_boundary = (;
            sampler_capability = preflight.sampler_capability,
            diagnostic_contract =
                preflight.sampler_capability.current_diagnostic_contract,
            diagnostic_contract_details =
                preflight.sampler_capability.current_diagnostic_contract_details,
            blockers = preflight.capability_blockers,
            pilot_execution_authorized =
                preflight.pilot_execution_authorized,
            required_capabilities = (;
                rank_normalized_rhat = true,
                bulk_ess = true,
                tail_ess = true,
                exact_diagnostic_contract = true,
                primary_diagnostic_fields = true,
                tail_probability = true,
                independent_chain_minimum = true,
                diagnostic_draw_minimum = true,
                complete_chain_e_bfmi = true,
            ),
        ),
        checks,
        evidence_status = (;
            pilot_execution_authorized =
                preflight.pilot_execution_authorized,
            pilot_execution_completed = false,
            evaluation_profile_frozen = false,
            evaluation_repetitions_selected = missing,
            repeated_calibration_completed = false,
            calibration_evidence_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
        ),
        summary = (;
            passed,
            n_planned_jobs = 660,
            n_fit_jobs = 540,
            n_pre_fit_rejection_jobs = 120,
            initial_evaluation_repetitions = 50,
            maximum_evaluation_repetitions = 100,
            runs_mcmc = false,
            pilot_execution_authorized =
                preflight.pilot_execution_authorized,
            pilot_execution_completed = false,
            evaluation_profile_frozen = false,
            calibration_evidence_available = false,
            diagnostic_decision_labels_available = false,
            mechanism_interpretation_eligible = false,
        ),
    )
    return merge(artifact, (;
        content_hash = (;
            algorithm = :sha256,
            value = canonical_json_sha256(artifact),
            covers = :artifact_without_content_hash,
            canonical_format = :local_json_sorted_compact,
        ),
    ))
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " jobs=", artifact.summary.n_planned_jobs,
        " fit_jobs=", artifact.summary.n_fit_jobs,
        " execution_authorized=",
        artifact.summary.pilot_execution_authorized,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
