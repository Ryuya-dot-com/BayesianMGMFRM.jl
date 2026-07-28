using JSON3
using Random
using SHA
using Test
using BayesianMGMFRM

if !isdefined(@__MODULE__, :ScientificPayloadDigest)
    include(joinpath(@__DIR__, "..", "scripts",
        "scientific_payload_digest.jl"))
end
const LD1B1HarnessScientificPayloadDigest = ScientificPayloadDigest

module LD1B1PilotBatchRunnerForTest

include(joinpath(@__DIR__, "..", "scripts",
    "run_local_dependence_calibration_pilot_batch.jl"))

end

module LD1B1PilotBatchHarnessGeneratorForTest

include(joinpath(@__DIR__, "..", "scripts",
    "generate_local_dependence_pilot_batch_execution_harness.jl"))

end

const LD1B1HarnessRunner = LD1B1PilotBatchRunnerForTest
const LD1B1HarnessGenerator = LD1B1PilotBatchHarnessGeneratorForTest
const LD1B1_HARNESS_TEST_RUNNER_PATH = joinpath(
    dirname(@__DIR__),
    "scripts",
    "run_local_dependence_calibration_pilot_job.jl",
)
const LD1B1_HARNESS_TEST_DIAGNOSTIC_DETAILS =
    LD1B1HarnessRunner.ld1b1_json_native(JSON3.read(read(
        LD1B1HarnessRunner.LD1B1_DEFAULT_PROTOCOL,
        String,
    ))[:pilot_contract][:quality_requirements][:diagnostic_contract_details])
const LD1B1_HARNESS_TEST_PROTOCOL =
    LD1B1HarnessRunner.ld1b1_json_native(JSON3.read(read(
        LD1B1HarnessRunner.LD1B1_DEFAULT_PROTOCOL,
        String,
    )))
const LD1B1_HARNESS_TEST_CALIBRATION_CONTRACT =
    LD1B1_HARNESS_TEST_PROTOCOL["pilot_contract"]["calibration_contract"]
const LD1B1_HARNESS_TEST_LOCAL_CONTRACT =
    LD1B1_HARNESS_TEST_CALIBRATION_CONTRACT["diagnostic_contract"]
const LD1B1_HARNESS_TEST_CALIBRATION_SEMANTIC_CONTEXT =
    LD1B1HarnessRunner.LD1B1CalibrationSemantics.
        ld1b1_load_calibration_semantic_context(
            LD1B1HarnessRunner.LD1B1_DEFAULT_PROTOCOL)

@testset "LD1b1 frozen code provenance remains fail-closed" begin
    runner = LD1B1HarnessRunner
    generator = LD1B1_HARNESS_TEST_PROTOCOL["generator"]
    references = (
        (field = :script_source_sha256,
            path = "scripts/generate_local_dependence_pilot_protocol_preflight.jl"),
        (field = :pilot_source_sha256,
            path = "src/local_dependence_calibration_pilot.jl"),
        (field = :diagnostic_source_sha256,
            path = "src/bayesian_fit.jl"),
        (field = :calibration_source_sha256,
            path = "src/local_dependence_calibration.jl"),
        (field = :simulation_source_sha256,
            path = "src/local_dependence_simulation.jl"),
    )
    source_rows = [(;
        reference...,
        absolute_path = joinpath(dirname(@__DIR__), reference.path),
        recorded_sha256 = String(generator[String(reference.field)]),
        current_sha256 = runner.ld1b1_file_sha256(
            joinpath(dirname(@__DIR__), reference.path)),
    ) for reference in references]

    @test length(source_rows) == 5
    @test count(row -> row.recorded_sha256 == row.current_sha256,
        source_rows) == 5

    diagnostic = only(row for row in source_rows
        if row.field === :diagnostic_source_sha256)
    synthetic_sha256 = diagnostic.current_sha256 == repeat("0", 64) ?
        repeat("1", 64) : repeat("0", 64)
    drift = merge(diagnostic, (; recorded_sha256 = synthetic_sha256))
    @test drift.field === :diagnostic_source_sha256
    @test drift.path == "src/bayesian_fit.jl"
    @test drift.recorded_sha256 != drift.current_sha256

    ordinary = LD1B1HarnessScientificPayloadDigest.
        reference_integrity_status(
            drift.recorded_sha256,
            drift.current_sha256;
            reference_kind = :code_doc,
            strict = false,
        )
    strict = LD1B1HarnessScientificPayloadDigest.reference_integrity_status(
        drift.recorded_sha256,
        drift.current_sha256;
        reference_kind = :code_doc,
        strict = true,
    )
    @test ordinary.status === :provenance_drift
    @test ordinary.provenance_policy_accepted
    @test !ordinary.exact_file_sha256_verified
    @test !ordinary.scientific_equivalence_verified
    @test ordinary.archive_refresh_required
    @test strict.status === :provenance_drift
    @test !strict.provenance_policy_accepted
    @test !strict.exact_file_sha256_verified
    @test strict.archive_refresh_required

    mktempdir() do temporary_directory
        drifted_protocol = deepcopy(LD1B1_HARNESS_TEST_PROTOCOL)
        drifted_protocol["generator"]["diagnostic_source_sha256"] =
            synthetic_sha256
        delete!(drifted_protocol, "content_hash")
        drifted_protocol["content_hash"] = Dict(
            "algorithm" => "sha256",
            "value" => runner.ld1b1_canonical_sha256(drifted_protocol),
            "covers" => "artifact_without_content_hash",
            "canonical_format" => "local_json_sorted_compact",
        )
        drifted_protocol_path = joinpath(
            temporary_directory,
            "local_dependence_pilot_protocol_preflight.json",
        )
        open(drifted_protocol_path, "w") do io
            runner.write_json(io, drifted_protocol)
            println(io)
        end

        strict_error = try
            runner.ld1b1_checked_protocol(
                drifted_protocol_path;
                job_runner_path = LD1B1_HARNESS_TEST_RUNNER_PATH,
            )
            nothing
        catch error
            error
        end
        @test strict_error isa ErrorException
        @test occursin(
            "protocol source identity mismatch: src/bayesian_fit.jl",
            sprint(showerror, strict_error),
        )
    end
end

@testset "LD1b1 canonical executor source pin is exact and fail-closed" begin
    runner = LD1B1HarnessRunner
    canonical_paths = (
        "src/bayesian_fit.jl",
        "scripts/local_json.jl",
    )
    noncanonical_paths = (
        "",
        ".",
        "..",
        "../src/bayesian_fit.jl",
        "src/../src/bayesian_fit.jl",
        "src//bayesian_fit.jl",
        "/src/bayesian_fit.jl",
        "C:/src/bayesian_fit.jl",
        "C:src/bayesian_fit.jl",
        raw"src\bayesian_fit.jl",
    )
    for path in canonical_paths
        @test runner.ld1b1_is_canonical_repository_relative_path(path)
    end
    for path in noncanonical_paths
        @test !runner.ld1b1_is_canonical_repository_relative_path(path)
    end

    protocol_native = deepcopy(LD1B1_HARNESS_TEST_PROTOCOL)
    as_json_object = value -> JSON3.read(JSON3.write(value))
    protocol = as_json_object(protocol_native)
    validated = runner.ld1b1_validate_canonical_executor_source_pin(protocol)
    @test validated.valid
    @test length(validated.source_rows) == 7
    @test all(row -> row.matches &&
        row.recorded_sha256 == row.actual_sha256, validated.source_rows)
    @test validated.execution_source_identity.job_runner_source_sha256 ==
        runner.ld1b1_file_sha256(LD1B1_HARNESS_TEST_RUNNER_PATH)
    @test validated.batch_harness_generator_source_sha256 ==
        runner.ld1b1_file_sha256(joinpath(
            dirname(@__DIR__),
            "scripts",
            "generate_local_dependence_pilot_batch_execution_harness.jl",
        ))

    extra_field = deepcopy(protocol_native)
    extra_field["canonical_executor_source_pin"]["unexpected"] = true
    @test_throws ErrorException begin
        runner.ld1b1_validate_canonical_executor_source_pin(
            as_json_object(extra_field))
    end

    reordered = deepcopy(protocol_native)
    rows = reordered["canonical_executor_source_pin"]["source_rows"]
    rows[1], rows[2] = rows[2], rows[1]
    @test_throws ErrorException begin
        runner.ld1b1_validate_canonical_executor_source_pin(
            as_json_object(reordered))
    end

    source_drift = deepcopy(protocol_native)
    source_drift["canonical_executor_source_pin"]["source_rows"][3][
        "sha256"] = repeat("0", 64)
    @test_throws ErrorException begin
        runner.ld1b1_validate_canonical_executor_source_pin(
            as_json_object(source_drift))
    end

    failed_check = deepcopy(protocol_native)
    failed_check["canonical_executor_source_pin"]["checks"][
        "source_sha256_matches"] = false
    @test_throws ErrorException begin
        runner.ld1b1_validate_canonical_executor_source_pin(
            as_json_object(failed_check))
    end

    overclaim = deepcopy(protocol_native)
    overclaim["canonical_executor_source_pin"]["evidence_boundary"][
        "bounded_canonical_smoke_passed"] = true
    @test_throws ErrorException begin
        runner.ld1b1_validate_canonical_executor_source_pin(
            as_json_object(overclaim))
    end

    forged_pin_id = deepcopy(protocol_native)
    forged_pin_id["canonical_executor_source_pin"]["pin_id"]["value"] =
        repeat("0", 64)
    @test_throws ErrorException begin
        runner.ld1b1_validate_canonical_executor_source_pin(
            as_json_object(forged_pin_id))
    end

    @test_throws MethodError begin
        runner.ld1b1_checked_protocol(
            runner.LD1B1_DEFAULT_PROTOCOL;
            final_worker_source_pinned_and_identities_regenerated = true,
        )
    end
    @test_throws MethodError begin
        runner.ld1b1_checked_protocol(
            runner.LD1B1_DEFAULT_PROTOCOL;
            bounded_canonical_smoke_passed = true,
        )
    end
    @test_throws MethodError begin
        runner.ld1b1_checked_protocol(
            runner.LD1B1_DEFAULT_PROTOCOL;
            interrupted_attempt_recovery_review_passed = true,
        )
    end
end

ld1b1_harness_test_sha256(text::AbstractString) =
    bytes2hex(sha256(codeunits(String(text))))

const LD1B1_HARNESS_TEST_OBSERVED_SIGNATURES = Dict{Int,String}()

function ld1b1_harness_test_signatures(job)
    observed_score_signature = get!(
            LD1B1_HARNESS_TEST_OBSERVED_SIGNATURES,
            job.resources.n_ratings,
        ) do
        observed_records = Tuple(fill((
            repr(1),
            repr(1),
            repr(1),
            repr(1),
            repr(1),
            0,
        ), job.resources.n_ratings))
        bytes2hex(sha256(codeunits(repr(observed_records))))
    end
    return (;
        data_signature = string(10_000 + job.row_index),
        score_signature = bytes2hex(sha256(codeunits(join(
            fill(0, job.resources.n_ratings), ',')))),
        observed_score_signature,
        design_signature = ld1b1_harness_test_sha256(
            "design:$(job.job_id)"),
        fit_artifact_content_hash = ld1b1_harness_test_sha256(
            "fit-artifact:$(job.job_id)"),
    )
end

const LD1B1_HARNESS_TEST_RETAINED_ARRAYS = Ref{Any}(nothing)

function ld1b1_harness_test_retained_arrays(runner, job)
    cached = LD1B1_HARNESS_TEST_RETAINED_ARRAYS[]
    cached === nothing || return cached
    sampler = job.sampler_contract
    n_draws = sampler.total_retained_draws
    draws = fill(0.0, n_draws)
    log_posterior = fill(-1.0, n_draws)
    sampler_stats = [Dict(
        "chain" => div(index - 1, sampler.draws_per_chain) + 1,
        "iteration" => mod(index - 1, sampler.draws_per_chain) + 1,
    ) for index in 1:n_draws]
    retained_draw_set_sha256 = runner.ld1b1_canonical_sha256((;
        draws,
        log_posterior,
        sampler_stats,
    ))
    result = (; draws, log_posterior, sampler_stats,
        retained_draw_set_sha256)
    LD1B1_HARNESS_TEST_RETAINED_ARRAYS[] = result
    return result
end

function ld1b1_harness_test_write_json(path::AbstractString, value)
    mkpath(dirname(path))
    open(path, "w") do io
        LD1B1HarnessRunner.write_json(io, value)
        println(io)
    end
    return path
end

function ld1b1_harness_test_rehash!(artifact::AbstractDict)
    pop!(artifact, "content_hash", nothing)
    artifact["content_hash"] = Dict(
        "algorithm" => "sha256",
        "value" => LD1B1HarnessRunner.ld1b1_canonical_sha256(artifact),
        "covers" => "artifact_without_content_hash",
        "canonical_format" => "local_json_sorted_compact",
    )
    return artifact
end

function ld1b1_harness_test_refresh_evidence_manifest!(runner,
        result_path::AbstractString, evidence_relative_path::AbstractString)
    result = runner.ld1b1_json_native(JSON3.read(read(result_path, String)))
    evidence_path = joinpath(dirname(result_path), evidence_relative_path)
    matched = false
    for row in result["file_manifest"]
        String(row["path"]) == evidence_relative_path || continue
        row["bytes"] = filesize(evidence_path)
        row["sha256"] = runner.ld1b1_file_sha256(evidence_path)
        matched = true
    end
    matched || error("test evidence path is absent from the result manifest")
    ld1b1_harness_test_rehash!(result)
    ld1b1_harness_test_write_json(result_path, result)
    return result
end

function ld1b1_harness_test_refresh_source_binding!(runner,
        result_path::AbstractString, evidence_relative_path::AbstractString)
    evidence_path = joinpath(dirname(result_path), evidence_relative_path)
    evidence = runner.ld1b1_json_native(
        JSON3.read(read(evidence_path, String)))
    source_path = joinpath(
        dirname(result_path), String(evidence["source_member"]["path"]))
    source_sha256 = runner.ld1b1_file_sha256(source_path)
    evidence["source_member"]["bytes"] = filesize(source_path)
    evidence["source_member"]["sha256"] = source_sha256
    role = Symbol(evidence["evidence_role"])
    digest_field = role === :generated_data ? "simulation_content_sha256" :
        role === :fit_result ? "fit_artifact_sha256" :
        role === :sampler_diagnostics ? "diagnostics_content_sha256" :
        role === :local_dependence_summary ? "summary_content_sha256" :
        role === :calibration_row ? "calibration_content_sha256" :
        role === :structural_rejection_audit ? "audit_content_sha256" :
        "failure_content_sha256"
    evidence["payload"][digest_field] = source_sha256
    ld1b1_harness_test_rehash!(evidence)
    ld1b1_harness_test_write_json(evidence_path, evidence)
    ld1b1_harness_test_refresh_evidence_manifest!(
        runner, result_path, evidence_relative_path)
    return (; evidence_path, source_path, evidence)
end

function ld1b1_harness_test_symbol_native(value)
    if value isa NamedTuple || value isa AbstractDict
        return Dict{Symbol,Any}(
            Symbol(key) => ld1b1_harness_test_symbol_native(element)
            for (key, element) in pairs(value))
    elseif value isa AbstractArray || value isa Tuple
        return [ld1b1_harness_test_symbol_native(element) for element in value]
    end
    return value
end

function ld1b1_harness_test_evidence_map(runner,
        result_path::AbstractString)
    result = JSON3.read(read(result_path, String))
    rows = Dict{Symbol,Any}()
    for manifest_row in result[:file_manifest]
        role = Symbol(manifest_row[:role])
        evidence_path = joinpath(
            dirname(result_path), String(manifest_row[:path]))
        evidence = JSON3.read(read(evidence_path, String))
        source_path = joinpath(
            dirname(result_path), String(evidence[:source_member][:path]))
        source_value = ld1b1_harness_test_symbol_native(
            JSON3.read(read(source_path, String)))
        role === :fit_result &&
            (source_value = source_value[:artifact])
        payload = Dict{Symbol,Any}(
            Symbol(key) => value for (key, value) in pairs(evidence[:payload]))
        rows[role] = (;
            payload,
            source_value,
            source_snapshot = (;
                sha256 = String(evidence[:source_member][:sha256]),
            ),
        )
    end
    return rows
end

function ld1b1_harness_test_protocol_copy()
    path = LD1B1HarnessRunner.LD1B1_DEFAULT_PROTOCOL
    return LD1B1HarnessRunner.ld1b1_json_native(
        JSON3.read(read(path, String)))
end

function ld1b1_harness_test_options(args, attempt_root::AbstractString)
    return LD1B1HarnessRunner.ld1b1_parse_args(vcat(
        String[
            "--attempt-root", attempt_root,
            "--runner", LD1B1_HARNESS_TEST_RUNNER_PATH,
        ],
        String.(args),
    ))
end

function ld1b1_harness_test_checked(runner)
    return runner.ld1b1_checked_protocol(
        runner.LD1B1_DEFAULT_PROTOCOL;
        job_runner_path = LD1B1_HARNESS_TEST_RUNNER_PATH,
    )
end

function ld1b1_harness_test_symlink_capability()
    return mktempdir() do root
        target = joinpath(root, "target.txt")
        link = joinpath(root, "link.txt")
        write(target, "probe")
        try
            symlink(target, link)
        catch error
            if Sys.iswindows() && error isa Base.IOError &&
                    error.code in (Base.UV_EPERM, Base.UV_EACCES)
                return (;
                    available = false,
                    reason = :windows_symlink_privilege,
                    code = error.code,
                )
            end
            rethrow()
        end
        islink(link) || error("symlink probe did not create a link")
        return (; available = true, reason = :available, code = nothing)
    end
end

function ld1b1_harness_test_evidence_payload(runner, job, role::Symbol,
        source_member_sha256::AbstractString;
        source_members = Dict{Symbol,Any}(),
        terminal_status = nothing)
    signatures = ld1b1_harness_test_signatures(job)
    retained = ld1b1_harness_test_retained_arrays(runner, job)
    role === :generated_data && return (;
        simulation_content_sha256 = source_member_sha256,
        n_response_rows = job.resources.n_ratings,
        n_probability_cells = job.resources.n_probability_cells,
        n_truth_cells = job.resources.n_truth_cells,
        data_signature = signatures.data_signature,
        score_signature = signatures.score_signature,
        testlet_design_signature_sha256 = signatures.design_signature,
        generation_completed = true,
    )
    role === :fit_result && return (;
        fit_artifact_sha256 = source_member_sha256,
        fit_artifact_content_hash = signatures.fit_artifact_content_hash,
        fit_artifact_json_content_hash = String(
            ld1b1_harness_test_source_member_value(job, :fit_result)[
                "json_content_hash"]["value"]),
        data_signature = signatures.data_signature,
        retained_draw_set_sha256 = retained.retained_draw_set_sha256,
        fit_seed = job.fit_seed,
        backend = job.sampler_contract.backend,
        algorithm = job.sampler_contract.algorithm,
        n_chains = job.sampler_contract.chains,
        warmup_per_chain = job.sampler_contract.warmup_per_chain,
        draws_per_chain = job.sampler_contract.draws_per_chain,
        total_retained_draws = job.sampler_contract.total_retained_draws,
        target_accept = job.sampler_contract.target_accept,
        max_depth = job.sampler_contract.max_depth,
        metric = job.sampler_contract.metric,
        ad_backend = job.sampler_contract.ad_backend,
        fit_completed = true,
    )
    role === :sampler_diagnostics && return (;
        diagnostics_content_sha256 = source_member_sha256,
        fit_artifact_sha256 = source_members[:fit_result].sha256,
        fit_artifact_content_hash = signatures.fit_artifact_content_hash,
        data_signature = signatures.data_signature,
        retained_draw_set_sha256 = retained.retained_draw_set_sha256,
        diagnostic_contract = job.quality_contract.diagnostic_contract,
        diagnostic_contract_details_sha256 =
            job.quality_contract.diagnostic_contract_details_sha256,
        n_chains = job.sampler_contract.chains,
        draws_per_chain = job.sampler_contract.draws_per_chain,
        total_draws = job.sampler_contract.total_retained_draws,
        split_chains_requested = job.sampler_contract.split_chains,
        split_chains = job.sampler_contract.split_chains,
        max_rank_normalized_rhat = 1.0,
        min_bulk_ess = 500.0,
        min_tail_ess = 500.0,
        n_divergences = 0,
        n_max_treedepth = 0,
        e_bfmi = 0.7,
        n_e_bfmi_expected = job.sampler_contract.chains,
        n_e_bfmi_available = job.sampler_contract.chains,
        n_e_bfmi_unavailable = 0,
        e_bfmi_complete = true,
        diagnostics_passed = true,
        diagnostics_flag = :ok,
        sampler_gate_passed = true,
    )
    role === :local_dependence_summary && return (;
        summary_content_sha256 = source_member_sha256,
        diagnostic_computed = true,
        n_diagnostic_draws = job.sampler_contract.diagnostic_draws,
        draw_selection_algorithm =
            runner.LD1B1_DRAW_SELECTION_ALGORITHM,
        draw_selection_seed = job.draw_selection_seed,
        posterior_predictive_seed = job.posterior_predictive_seed,
        replicates_per_draw =
            job.sampler_contract.posterior_predictive_replicates_per_draw,
        data_signature = signatures.data_signature,
        observed_score_signature_sha256 =
            signatures.observed_score_signature,
        design_signature_sha256 = signatures.design_signature,
        retained_draw_set_sha256 = retained.retained_draw_set_sha256,
        diagnostic_decision_labels_available = false,
        mechanism_interpretation_eligible = false,
    )
    if role === :calibration_row
        calibration_status = terminal_status === nothing ?
            (job.expected_action === :pre_fit_reject ?
                :pre_fit_rejected : :completed) : terminal_status
        has_simulation = calibration_status !== :generation_failed
        return (;
            calibration_content_sha256 = source_member_sha256,
            calibration_contract =
                "bayesianmgmfrm.local_dependence_calibration_row.v1",
            row_index = job.row_index,
            scenario_index = job.scenario_index,
            scenario_id = job.scenario_id,
            replication = job.replication,
            status = calibration_status,
            data_signature = has_simulation ?
                signatures.data_signature : missing,
            observed_score_signature_sha256 = has_simulation ?
                signatures.observed_score_signature : missing,
            design_signature_sha256 = has_simulation ?
                signatures.design_signature : missing,
            row_complete = true,
        )
    end
    role === :structural_rejection_audit && return (;
        audit_content_sha256 = source_member_sha256,
        simulation_content_sha256 = source_members[:generated_data].sha256,
        data_signature = signatures.data_signature,
        issue_code = :expected_structural_rejection,
        expected_action = :pre_fit_reject,
        rejection_confirmed = true,
    )
    failure_stage = role === :generation_failure_record ? :generation :
        role === :fit_failure_record ? :fit :
        role === :diagnostic_failure_record ? :diagnostic :
        error("unsupported test evidence role: $role")
    return (;
        failure_content_sha256 = source_member_sha256,
        failure_stage,
        (role === :diagnostic_failure_record ?
            (; failure_component = :local_dependence_summary) : (;))...,
        error_class = :synthetic_test_failure,
        failure_recorded = true,
    )
end

function ld1b1_harness_test_planning_fields(job;
        terminal_status = nothing,
        calibration_semantic_context =
            LD1B1_HARNESS_TEST_CALIBRATION_SEMANTIC_CONTEXT)
    if calibration_semantic_context !== nothing
        plan = calibration_semantic_context.plan_rows[job.row_index]
        plan.row_index == job.row_index &&
            plan.scenario_index == job.scenario_index &&
            plan.scenario_id === job.scenario_id &&
            plan.replication == job.replication || error(
            "semantic planning fixture does not match its canonical job")
        return (;
            profile = plan.profile,
            grid_id = plan.grid_id,
            base_seed = plan.base_seed,
            mechanism = plan.mechanism,
            magnitude_label = plan.magnitude_label,
            effect_scale = plan.effect_scale,
            design = plan.design,
            assignment = plan.assignment,
            order = plan.order,
            component_seeds = plan.component_seeds,
            planning_shape = Dict(
                "n_persons" => plan.n_persons,
                "n_testlets" => plan.n_testlets,
                "items_per_testlet" => plan.items_per_testlet,
                "n_items" => plan.n_testlets * plan.items_per_testlet,
                "n_raters" => plan.n_raters,
                "n_categories" => plan.n_categories,
                "audit_targets" => collect(plan.audit_targets),
                "expected_diagnostic_pair_support" =>
                    plan.expected_diagnostic_pair_support,
            ),
            truth = Dict(
                "generating_mechanism" => String(plan.mechanism),
                "pair_truth_oracle_available" => false,
            ),
        )
    end
    return (;
        profile = "ld1_preflight_v1",
        grid_id = "ld1_simulation_grid_v1",
        base_seed = job.seed,
        mechanism = String(job.scenario_id),
        magnitude_label = "synthetic_contract_fixture",
        effect_scale = 0.0,
        design = "complete_crossed_fixture",
        assignment = "deterministic_fixture",
        order = "canonical_fixture",
        component_seeds = Dict("response" => job.seed),
        planning_shape = Dict(
            "n_ratings" => job.resources.n_ratings,
            "n_probability_cells" => job.resources.n_probability_cells,
            "n_truth_cells" => job.resources.n_truth_cells,
        ),
        truth = Dict(
            "generating_mechanism" => String(job.scenario_id),
            "pair_truth_oracle_available" => false,
        ),
    )
end

function ld1b1_harness_test_canonical_calibration_member(job,
        terminal_status::Symbol, calibration_semantic_context)
    semantics = LD1B1HarnessRunner.LD1B1CalibrationSemantics
    template = semantics._ld1b1_calibration_template(
        calibration_semantic_context,
        job.row_index,
    )
    value = semantics.ld1b1_semantic_json_native(template.expected)
    signatures = ld1b1_harness_test_signatures(job)
    has_simulation = terminal_status !== :generation_failed
    has_diagnostic = terminal_status === :completed
    shape = value["planning_shape"]
    future_fit_action = job.expected_structural_eligibility ?
        "structurally_eligible_for_future_candidate" :
        "do_not_fit_underidentified_design"
    simulation_provenance = has_simulation ? Dict(
        "status" => "known_truth_generated",
        "data_signature" => signatures.data_signature,
        "score_signature" => signatures.score_signature,
        "observed_score_signature" => Dict(
            "algorithm" => "sha256",
            "value" => signatures.observed_score_signature,
        ),
        "testlet_design_signature" => Dict(
            "algorithm" => "sha256",
            "value" => signatures.design_signature,
        ),
        "n_ratings" => job.resources.n_ratings,
        "planning_shape" => deepcopy(shape),
        "observed_shape" => Dict(
            "n_persons" => shape["n_persons"],
            "n_testlets" => shape["n_testlets"],
            "n_items" => shape["n_items"],
            "n_raters" => shape["n_raters"],
            "n_categories" => shape["n_categories"],
        ),
        "requested_targets_eligible" =>
            job.expected_structural_eligibility,
        "future_fit_action" => future_fit_action,
    ) : nothing
    diagnostic_provenance = has_diagnostic ? Dict(
        "status" => "no_eligible_pairs",
        "profile" => String(
            calibration_semantic_context.calibration_contract.
                diagnostic_contract.profile),
        "n_draws" => job.sampler_contract.diagnostic_draws,
        "data_signature" => signatures.data_signature,
        "observed_score_signature" => Dict(
            "algorithm" => "sha256",
            "value" => signatures.observed_score_signature,
        ),
        "design_signature" => Dict(
            "algorithm" => "sha256",
            "value" => signatures.design_signature,
        ),
    ) : nothing
    families = (
        :single_rating_item_q3,
        :within_rater_item_q3,
        :rater_on_shared_response_criterion,
    )
    family_evidence = has_diagnostic ? [Dict(
        "family" => String(family),
        "support_status" => "not_applicable",
        "applicable" => false,
        "n_pair_rows" => 0,
        "n_eligible_pairs" => 0,
        "n_raw_declared" => 0,
        "n_bh_declared" => 0,
        "any_raw_declared" => nothing,
        "any_bh_declared" => nothing,
        "maximum_support_status" => "not_applicable",
        "maximum_tail_fraction" => nothing,
        "family_evaluable" => false,
        "candidate_family_declared" => nothing,
    ) for family in families] : Any[]
    global_evidence = has_diagnostic ? Dict(
        "support_status" => "not_applicable",
        "n_overall_supported_pairs" => 0,
        "tail_fraction" => nothing,
        "evaluable" => false,
        "candidate_global_declared" => nothing,
    ) : nothing

    value["status"] = String(terminal_status)
    value["failure_code"] = terminal_status in (
        :generation_failed, :fit_failed, :diagnostic_failed) ?
        "synthetic_test_failure" : nothing
    value["simulation_provenance"] = simulation_provenance
    value["diagnostic_provenance"] = diagnostic_provenance
    value["n_pair_evidence"] = 0
    value["pair_evidence"] = Any[]
    value["family_evidence"] = family_evidence
    value["global_evidence"] = global_evidence
    return value
end

function ld1b1_harness_test_source_member_value(job, role::Symbol;
        source_members = Dict{Symbol,Any}(),
        terminal_status = nothing,
        calibration_semantic_context =
            LD1B1_HARNESS_TEST_CALIBRATION_SEMANTIC_CONTEXT)
    signatures = ld1b1_harness_test_signatures(job)
    planning = ld1b1_harness_test_planning_fields(
        job;
        terminal_status,
        calibration_semantic_context,
    )
    if role === :generated_data
        n = job.resources.n_ratings
        n_persons = get(planning.planning_shape, "n_persons", 40)
        n_testlets = get(planning.planning_shape, "n_testlets", 4)
        n_items = get(planning.planning_shape, "n_items", 12)
        n_raters = get(planning.planning_shape, "n_raters", 4)
        n_categories = get(planning.planning_shape, "n_categories", 4)
        table_fields = (
            "person", "rater", "item", "score", "task", "occasion",
            "response_id", "testlet_id", "sequence_index",
            "sequence_fraction", "sequence_phase", "event_id",
            "assignment_reason",
        )
        table = Dict(field => fill(1, n) for field in table_fields)
        table["score"] = fill(0, n)
        table["event_id"] = collect(1:n)
        row_truth_fields = (
            "event_id", "canonical_row", "person_index", "rater_index",
            "item_index", "testlet_index", "response_index",
            "sequence_index", "sequence_fraction", "response_uniform",
            "missingness_uniform", "observed_mask", "baseline_location",
            "person_testlet_shift", "response_occasion_shift",
            "rater_response_halo_shift", "rater_task_severity_shift",
            "multidimensional_shift", "temporal_severity_shift",
            "total_location",
        )
        row_truth = Dict(field => field == "observed_mask" ?
            fill(true, n) : fill(0.0, n) for field in row_truth_fields)
        row_truth["event_id"] = collect(1:n)
        row_truth["probabilities"] = fill(
            0.25, job.resources.n_probability_cells)
        future_fit_action = job.expected_structural_eligibility ?
            "structurally_eligible_for_future_candidate" :
            "do_not_fit_underidentified_design"
        return Dict(
            "schema" => "bayesianmgmfrm.local_dependence_simulation.v1",
            "object" => "local_dependence_simulation",
            "status" => "known_truth_generated",
            "profile" => planning.profile,
            "grid_id" => planning.grid_id,
            "scenario_id" => String(job.scenario_id),
            "matched_set_id" => String(job.matched_set_id),
            "replication" => job.replication,
            "phase" => String(job.phase),
            "base_seed" => planning.base_seed,
            "seed" => job.seed,
            "mechanism" => planning.mechanism,
            "magnitude_label" => planning.magnitude_label,
            "effect_scale" => planning.effect_scale,
            "design" => planning.design,
            "assignment" => planning.assignment,
            "order" => planning.order,
            "generator_contract" => Dict(
                "fitted_probability_or_likelihood_dependency" => "none",
            ),
            "data" => Dict("n" => n, "score" => fill(0, n)),
            "table" => table,
            "truth" => Dict(
                "schema" =>
                    "bayesianmgmfrm.local_dependence_known_truth.v1",
                "generating_mechanism" => planning.mechanism,
                "active_mechanisms" => Any[],
                "component_scales" => Dict("testlet" => 0.0),
                "component_seeds" => planning.component_seeds,
                "person_labels" => collect(1:n_persons),
                "testlet_labels" => collect(1:n_testlets),
                "item_labels" => collect(1:n_items),
                "rater_labels" => collect(1:n_raters),
                "intended_category_levels" => collect(0:(n_categories - 1)),
                "realized_category_levels" => collect(0:(n_categories - 1)),
                "category_support_complete" => true,
            ),
            "row_truth" => row_truth,
            "validation" => Dict(
                "data_signature" => signatures.data_signature),
            "design_support" => Dict(
                "requested_targets_eligible" =>
                    job.expected_structural_eligibility,
                "expected_requested_targets_eligible" =>
                    job.expected_structural_eligibility,
                "future_fit_action" => future_fit_action,
            ),
            "resource_counts" => Dict(
                "n_ratings" => job.resources.n_ratings,
                "n_probability_cells" => job.resources.n_probability_cells,
                "n_truth_cells" => job.resources.n_truth_cells,
            ),
            "checks" => Dict(
                "probabilities_finite" => true,
                "probabilities_nonnegative" => true,
                "score_support_valid" => true,
                "all_rows_observed" => true,
                "generator_checks_passed" => true,
            ),
            "data_signature" => signatures.data_signature,
            "testlet_design_signature" => Dict(
                "algorithm" => "sha256",
                "value" => signatures.design_signature,
            ),
            "score_signature" => signatures.score_signature,
            "truth_known_by_construction" => true,
            "calibration_status" => "evaluation_not_run",
            "calibration_evidence_available" => false,
            "diagnostic_decision_labels_available" => false,
            "observed_data_mechanism_interpretation_eligible" => false,
            "summary" => Dict(
                "passed" => true,
                "n_ratings" => job.resources.n_ratings,
                "n_persons" => n_persons,
                "n_raters" => n_raters,
                "n_items" => n_items,
                "n_testlets" => n_testlets,
                "intended_categories" => n_categories,
                "realized_categories" => n_categories,
                "category_support_complete" => true,
                "requested_targets_eligible" =>
                    job.expected_structural_eligibility,
                "future_fit_action" => future_fit_action,
            ),
            "caveat" =>
                "generator_and_preflight_evidence_not_calibration_or_mechanism_classification",
        )
    end
    if role === :fit_result
        retained = ld1b1_harness_test_retained_arrays(
            LD1B1HarnessRunner, job)
        sampler = job.sampler_contract
        controls = Dict(
            "ndraws" => sampler.draws_per_chain,
            "warmup" => sampler.warmup_per_chain,
            "chains" => sampler.chains,
            "step_size" => 0.1,
            "target_accept" => sampler.target_accept,
            "max_depth" => sampler.max_depth,
            "max_energy_error" => 1000.0,
            "metric" => String(sampler.metric),
            "ad_backend" => String(sampler.ad_backend),
            "gradient_backend" => "ad",
            "rng" => Dict(
                "algorithm" => "MersenneTwister",
                "seed" => job.fit_seed,
                "replayable" => true,
            ),
            "init_jitter" => 0.0,
        )
        fit_metadata = Dict(
            "n_observations" => job.resources.n_ratings,
            "family" => "mfrm",
            "n_parameters" => 1,
            "n_draws" => sampler.total_retained_draws,
            "n_chains" => sampler.chains,
            "draws_per_chain" => sampler.draws_per_chain,
            "n_log_posterior" => sampler.total_retained_draws,
            "backend" => String(sampler.backend),
            "sampler" => String(sampler.algorithm),
            "warmup" => sampler.warmup_per_chain,
            "sampler_controls" => controls,
            "n_sampler_stats" => sampler.total_retained_draws,
            "data_signature" => signatures.data_signature,
            "design_identity" => Dict(
                "data_signature" => signatures.data_signature),
        )
        content_hash = Dict(
            "algorithm" => "sha256",
            "value" => signatures.fit_artifact_content_hash,
            "scope" => "artifact_without_hash_metadata",
            "canonicalization" => "cache_stable_string",
            "n_canonical_bytes" => 1,
        )
        reproducibility = Dict(
            "data_signature" => signatures.data_signature,
            "rng" => controls["rng"],
            "replayable_rng" => true,
            "sampler_controls" => controls,
            "diagnostic_policy" => Dict(
                "diagnostic_contract" =>
                    String(job.quality_contract.diagnostic_contract),
            ),
            "artifact_policy" => Dict(
                "draws" => "included",
                "log_posterior" => "included",
                "sampler_stats" => "included",
                "environment" => "omitted",
                "package_status" => "omitted",
            ),
        )
        artifact = Dict(
            "schema" => "bayesianmgmfrm.fit_artifact.v1",
            "object" => "fit_artifact",
            "created_at" => "2026-07-21T00:00:00",
            "evidence_artifact_schema_policy" => Dict(
                "artifact_kind" => "fit_artifact"),
            "manifest" => Dict(
                "schema" => "bayesianmgmfrm.model_manifest.v1",
                "object" => "fit",
                "data" => Dict(
                    "data_signature" => signatures.data_signature),
                "validation" => Dict(
                    "data_signature" => signatures.data_signature),
                "fit" => fit_metadata,
                "rating_design" => Dict(
                    "data_signature" => signatures.data_signature,
                    "anchor_linking" => Dict(
                        "data_signature" => signatures.data_signature),
                ),
                "diagnostics" => Dict("flag" => "ok"),
            ),
            "diagnostics" => Dict("summary" => Dict("flag" => "ok")),
            "posterior_summary" => [Dict("parameter" => "fixture")],
            "reproducibility" => reproducibility,
            "environment" => nothing,
            "draws" => retained.draws,
            "log_posterior" => retained.log_posterior,
            "sampler_stats" => retained.sampler_stats,
            "content_hash" => content_hash,
            "archive_manifest" => Dict(
                "schema" => "bayesianmgmfrm.fit_archive_manifest.v1",
                "object" => "fit_archive_manifest",
                "content_hash" => content_hash,
                "artifact" => Dict(
                    "schema" => "bayesianmgmfrm.fit_artifact.v1"),
                "manifest" => Dict(
                    "n_draws" => sampler.total_retained_draws,
                    "data_signature" => signatures.data_signature),
                "reproducibility" => reproducibility,
                "archive_policy" => Dict(
                    "intended_use" => "long_term_export_manifest"),
            ),
        )
        json_content_hash = LD1B1HarnessRunner.ld1b1_json_content_hash_record(
            artifact; scope = :fit_artifact_json_payload)
        return Dict(
            "schema" =>
                "bayesianmgmfrm.local_dependence_pilot_fit_artifact_export.v1",
            "object" => "fit_artifact_export",
            "serialization" => Dict(
                "format" => "json",
                "projection" => "ld1b1_json_native_v1",
                "symbol_values" => "string",
                "missing_values" => "json_null",
                "nonfinite_numbers" => "rejected",
            ),
            "artifact_content_hash" => deepcopy(content_hash),
            "json_content_hash" =>
                LD1B1HarnessRunner.ld1b1_json_native(json_content_hash),
            "artifact" => artifact,
        )
    end
    role === :sampler_diagnostics && return Dict(
        "schema" =>
            "bayesianmgmfrm.local_dependence_pilot_sampler_diagnostics_bundle.v1",
        "object" => "sampler_diagnostics_bundle",
        "backend" => String(job.sampler_contract.backend),
        "sampler" => String(job.sampler_contract.algorithm),
        "fit_artifact_sha256" => source_members[:fit_result].sha256,
        "fit_artifact_content_hash" =>
            signatures.fit_artifact_content_hash,
        "data_signature" => signatures.data_signature,
        "retained_draw_set_sha256" =>
            ld1b1_harness_test_retained_arrays(
                LD1B1HarnessRunner, job).retained_draw_set_sha256,
        "chain_ids" => [div(index - 1,
            job.sampler_contract.draws_per_chain) + 1 for index in
            1:job.sampler_contract.total_retained_draws],
        "iterations" => [mod(index - 1,
            job.sampler_contract.draws_per_chain) + 1 for index in
            1:job.sampler_contract.total_retained_draws],
        "summary" => Dict(
            "diagnostic_contract" =>
                String(job.quality_contract.diagnostic_contract),
            "diagnostic_contract_details" =>
                deepcopy(LD1B1_HARNESS_TEST_DIAGNOSTIC_DETAILS),
            "flag" => "ok",
            "passed" => true,
            "n_chains" => job.sampler_contract.chains,
            "draws_per_chain" => job.sampler_contract.draws_per_chain,
            "total_draws" => job.sampler_contract.total_retained_draws,
            "split_chains_requested" => job.sampler_contract.split_chains,
            "split_chains" => job.sampler_contract.split_chains,
            "max_rank_normalized_rhat" => 1.0,
            "min_bulk_ess" => 500.0,
            "min_tail_ess" => 500.0,
            "n_divergences" => 0,
            "n_max_treedepth" => 0,
            "e_bfmi" => 0.7,
            "n_e_bfmi_expected" => job.sampler_contract.chains,
            "n_e_bfmi_available" => job.sampler_contract.chains,
            "n_e_bfmi_unavailable" => 0,
            "e_bfmi_complete" => true,
        ),
    )
    if role === :local_dependence_summary
        draw_indices = collect(LD1B1HarnessRunner.ld1b1_expected_draw_indices(
            job.draw_selection_seed,
            job.sampler_contract.total_retained_draws,
            job.sampler_contract.diagnostic_draws,
        ))
        semantic_completed = calibration_semantic_context !== nothing &&
            terminal_status === :completed
        families = (
            :single_rating_item_q3,
            :within_rater_item_q3,
            :rater_on_shared_response_criterion,
        )
        family_rows = semantic_completed ? [Dict(
            "family" => String(family),
            "status" => "not_applicable",
            "decision_available" => false,
            "mechanism_interpretation_eligible" => false,
        ) for family in families] : Any[]
        family_max_rows = semantic_completed ? [Dict(
            "family" => String(family),
            "support_status" => "not_applicable",
            "posterior_predictive_tail_fraction" => nothing,
            "decision_available" => false,
        ) for family in families] : Any[]
        global_evidence = semantic_completed ? Dict(
            "support_status" => "not_applicable",
            "n_overall_supported_pairs" => 0,
            "posterior_predictive_tail_fraction" => nothing,
            "decision_available" => false,
        ) : Dict("decision_available" => false)
        return Dict(
            "schema" =>
                "bayesianmgmfrm.local_dependence_pilot_summary_bundle.v1",
            "object" => "local_dependence_pilot_summary_bundle",
            "status" => "no_eligible_pairs",
            "family" => "mfrm",
            "model_thresholds" => "partial_credit",
            "profile" => String(LD1B1_HARNESS_TEST_LOCAL_CONTRACT["profile"]),
            "frozen_profile" => true,
            "calibration_status" =>
                "pending_independent_known_truth_simulation",
            "calibration_required" => true,
            "decision_labels_available" => false,
            "mechanism_interpretation_eligible" => false,
            "conditioning" => "observed_rows_and_fitted_latent_effects",
            "prediction_target" => "conditional_observed_cluster",
            "draw_source" => "distinct_posterior_draws",
            "draw_selection_algorithm" =>
                String(LD1B1HarnessRunner.LD1B1_DRAW_SELECTION_ALGORITHM),
            "draw_selection_seed" => job.draw_selection_seed,
            "posterior_predictive_seed" => job.posterior_predictive_seed,
            "draw_indices" => draw_indices,
            "chain_ids" => [div(index - 1,
                job.sampler_contract.draws_per_chain) + 1
                for index in draw_indices],
            "iterations" => [mod(index - 1,
                job.sampler_contract.draws_per_chain) + 1
                for index in draw_indices],
            "n_draws" => job.sampler_contract.diagnostic_draws,
            "replicated_datasets_per_parameter_draw" =>
                job.sampler_contract.posterior_predictive_replicates_per_draw,
            "replication_source" => "generated_from_parameter_draw",
            "interval_probability" => 0.95,
            "data_signature" => signatures.data_signature,
            "observed_score_signature" => Dict(
                "algorithm" => "sha256",
                "value" => signatures.observed_score_signature,
            ),
            "design_signature" => Dict(
                "algorithm" => "sha256",
                "value" => signatures.design_signature,
            ),
            "contract" => deepcopy(LD1B1_HARNESS_TEST_LOCAL_CONTRACT),
            "retained_draw_set_sha256" =>
                ld1b1_harness_test_retained_arrays(
                    LD1B1HarnessRunner, job).retained_draw_set_sha256,
            "diagnostic_thresholds" => deepcopy(
                LD1B1_HARNESS_TEST_LOCAL_CONTRACT["thresholds"]),
            "computational_support" => Dict("fixture" => true),
            "design_support" => Dict("schema_valid" => true),
            "selected_families" => [
                "single_rating_item_q3",
                "within_rater_item_q3",
                "rater_on_shared_response_criterion",
            ],
            "family_rows" => family_rows,
            "family_testlet_rows" => Any[],
            "pair_rows" => Any[],
            "family_max_rows" => family_max_rows,
            "global_evidence" => global_evidence,
            "residual_support" => Dict("fixture" => true),
            "n_pair_rows" => 0,
            "n_summary_supported_pairs" => 0,
            "decision" => nothing,
            "caveats" => [
                "posterior_predictive_tail_fractions_are_not_calibrated_decision_p_values",
            ],
        )
    end
    if role === :calibration_row
        value = Dict{String,Any}(
            String(field) => nothing for field in (
                :schema, :object, :profile, :planning_profile,
                :protocol_status, :status, :contract, :grid_id, :row_index,
                :scenario_index, :scenario_id, :matched_set_id, :replication,
                :phase, :base_seed, :seed, :component_seeds, :mechanism,
                :magnitude_label, :effect_scale, :design, :assignment, :order,
                :expected_structural_eligibility, :planning_shape, :truth,
                :execution_seeds, :failure_code, :simulation_provenance,
                :diagnostic_provenance, :n_pair_evidence, :pair_evidence,
                :family_evidence, :global_evidence, :target_evidence,
                :target_evidence_available, :pair_truth_oracle_available,
                :pairwise_power_available, :repeated_calibration_completed,
                :calibration_evidence_available,
                :diagnostic_decision_labels_available,
                :mechanism_interpretation_eligible, :caveat,
            )
        )
        calibration_status = terminal_status === nothing ?
            (job.expected_action === :pre_fit_reject ?
                :pre_fit_rejected : :completed) : terminal_status
        if calibration_semantic_context !== nothing
            return ld1b1_harness_test_canonical_calibration_member(
                job,
                calibration_status,
                calibration_semantic_context,
            )
        elseif calibration_status === :generation_failed
            error("generation-failure test source requires a semantic context")
        end
        has_simulation = calibration_status !== :generation_failed
        has_diagnostic = calibration_status === :completed
        future_fit_action = job.expected_structural_eligibility ?
            "structurally_eligible_for_future_candidate" :
            "do_not_fit_underidentified_design"
        simulation_provenance = has_simulation ? Dict(
            "status" => "known_truth_generated",
            "data_signature" => signatures.data_signature,
            "score_signature" => signatures.score_signature,
            "observed_score_signature" => Dict(
                "algorithm" => "sha256",
                "value" => signatures.observed_score_signature,
            ),
            "testlet_design_signature" => Dict(
                "algorithm" => "sha256",
                "value" => signatures.design_signature,
            ),
            "n_ratings" => job.resources.n_ratings,
            "planning_shape" => planning.planning_shape,
            "observed_shape" => Dict("n_ratings" =>
                job.resources.n_ratings),
            "requested_targets_eligible" =>
                job.expected_structural_eligibility,
            "future_fit_action" => future_fit_action,
        ) : nothing
        diagnostic_provenance = has_diagnostic ? Dict(
                "status" => "no_eligible_pairs",
                "profile" => String(
                    LD1B1_HARNESS_TEST_LOCAL_CONTRACT["profile"]),
                "n_draws" => job.sampler_contract.diagnostic_draws,
                "data_signature" => signatures.data_signature,
                "observed_score_signature" => Dict(
                    "algorithm" => "sha256",
                    "value" => signatures.observed_score_signature,
                ),
                "design_signature" => Dict(
                    "algorithm" => "sha256",
                    "value" => signatures.design_signature,
                ),
            ) : nothing
        merge!(value, Dict(
            "schema" =>
                "bayesianmgmfrm.local_dependence_calibration_row.v1",
            "object" => "local_dependence_calibration_row",
            "profile" => String(
                LD1B1_HARNESS_TEST_CALIBRATION_CONTRACT["profile"]),
            "planning_profile" => planning.profile,
            "protocol_status" => "protocol_preflight_only",
            "status" => String(calibration_status),
            "contract" => deepcopy(
                LD1B1_HARNESS_TEST_CALIBRATION_CONTRACT),
            "grid_id" => planning.grid_id,
            "row_index" => job.row_index,
            "scenario_index" => job.scenario_index,
            "scenario_id" => String(job.scenario_id),
            "matched_set_id" => String(job.matched_set_id),
            "replication" => job.replication,
            "phase" => String(job.phase),
            "base_seed" => planning.base_seed,
            "seed" => job.seed,
            "component_seeds" => planning.component_seeds,
            "mechanism" => planning.mechanism,
            "magnitude_label" => planning.magnitude_label,
            "effect_scale" => planning.effect_scale,
            "design" => planning.design,
            "assignment" => planning.assignment,
            "order" => planning.order,
            "expected_structural_eligibility" =>
                job.expected_structural_eligibility,
            "planning_shape" => planning.planning_shape,
            "truth" => planning.truth,
            "execution_seeds" => Dict(
                "fit" => job.fit_seed,
                "draw_selection" => job.draw_selection_seed,
                "posterior_predictive" => job.posterior_predictive_seed,
                "contract" => deepcopy(
                    LD1B1_HARNESS_TEST_CALIBRATION_CONTRACT[
                        "seed_contract"]),
            ),
            "failure_code" => calibration_status in (
                :generation_failed, :fit_failed, :diagnostic_failed) ?
                "synthetic_test_failure" : nothing,
            "simulation_provenance" => simulation_provenance,
            "diagnostic_provenance" => diagnostic_provenance,
            "n_pair_evidence" => 0,
            "pair_evidence" => Any[],
            "family_evidence" => Any[],
            "global_evidence" => has_diagnostic ?
                Dict("decision_available" => false) : nothing,
            "target_evidence" => nothing,
            "target_evidence_available" => false,
            "pair_truth_oracle_available" => false,
            "pairwise_power_available" => false,
            "repeated_calibration_completed" => false,
            "calibration_evidence_available" => false,
            "diagnostic_decision_labels_available" => false,
            "mechanism_interpretation_eligible" => false,
            "caveat" =>
                "candidate_diagnostic_decisions_for_protocol_preflight_only",
        ))
        return value
    end
    role === :structural_rejection_audit && return Dict(
        "schema" =>
            "bayesianmgmfrm.local_dependence_pilot_structural_rejection_audit.v1",
        "object" => "structural_rejection_audit",
        "job_id" => job.job_id,
        "row_index" => job.row_index,
        "scenario_id" => String(job.scenario_id),
        "replication" => job.replication,
        "simulation_content_sha256" =>
            source_members[:generated_data].sha256,
        "data_signature" => signatures.data_signature,
        "expected_action" => "pre_fit_reject",
        "issue_code" => "expected_structural_rejection",
        "rejection_confirmed" => true,
    )
    failure_stage = role === :generation_failure_record ? :generation :
        role === :fit_failure_record ? :fit :
        role === :diagnostic_failure_record ? :diagnostic :
        error("unsupported test source-member role: $role")
    value = Dict(
        "schema" => "bayesianmgmfrm.local_dependence_pilot_failure_record.v1",
        "object" => String(role),
        "job_id" => job.job_id,
        "row_index" => job.row_index,
        "scenario_id" => String(job.scenario_id),
        "replication" => job.replication,
        "failure_stage" => String(failure_stage),
        "error_class" => "synthetic_test_failure",
        "failure_recorded" => true,
    )
    role === :diagnostic_failure_record &&
        (value["failure_component"] = "local_dependence_summary")
    return value
end

function ld1b1_harness_test_write_source_member!(runner,
        attempt_dir::AbstractString, job, role::Symbol;
        source_members = Dict{Symbol,Any}(),
        terminal_status = nothing,
        calibration_semantic_context =
            LD1B1_HARNESS_TEST_CALIBRATION_SEMANTIC_CONTEXT)
    member_role = runner.ld1b1_evidence_member_role(role)
    extension = ".json"
    relative = joinpath("members", string(member_role, extension))
    path = joinpath(attempt_dir, relative)
    mkpath(dirname(path))
    ld1b1_harness_test_write_json(path,
        ld1b1_harness_test_source_member_value(
            job,
            role;
            source_members,
            terminal_status,
            calibration_semantic_context,
        ))
    return (;
        role = member_role,
        path = relative,
        media_type = runner.ld1b1_evidence_member_media_type(role),
        bytes = filesize(path),
        sha256 = runner.ld1b1_file_sha256(path),
    )
end

function ld1b1_harness_test_canonical_controller_receipts!(
        runner, identity, job, execution_root::AbstractString, attempt::Int)
    run_id = string("synthetic_terminal_", job.job_id, "_", attempt)
    setup = runner.ld1b1_publish_attempt_reservation_create_new(
        execution_root, identity, job, attempt, run_id)
    mkpath(dirname(setup.lineage.attempt_dir))
    mkdir(setup.lineage.attempt_dir)
    owner = runner.ld1b1_publish_canonical_owner_create_new(
        setup.lineage, execution_root)
    launch = runner.ld1b1_publish_child_launch_create_new(
        setup.lineage, owner.owner, 12_000 + attempt, execution_root)
    exit = runner.ld1b1_publish_child_exit_create_new(
        setup.lineage, launch.launch, 0, execution_root)
    return (; setup, owner, launch, exit)
end

function ld1b1_harness_test_terminal_result!(runner, identity, job,
        execution_root::AbstractString, attempt::Int, status::Symbol;
        retry_reason = nothing,
        retry_of_attempt = nothing,
        primary_result_sha256 = nothing,
        lineage_valid::Bool = true,
        publish_seal::Bool = true,
        canonical_controller_receipts::Bool = publish_seal,
        calibration_semantic_context =
            LD1B1_HARNESS_TEST_CALIBRATION_SEMANTIC_CONTEXT,
        runner_source_sha256 =
            identity.execution_source_identity.job_runner_source_sha256)
    attempt_dir = runner.ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    controller_receipts = canonical_controller_receipts ?
        ld1b1_harness_test_canonical_controller_receipts!(
            runner, identity, job, execution_root, attempt) : nothing
    manifest = NamedTuple[]
    evidence_hashes = Dict{Symbol,String}()
    source_members = Dict{Symbol,Any}()
    for role in runner.ld1b1_required_evidence_roles(status)
        member = ld1b1_harness_test_write_source_member!(
            runner, attempt_dir, job, role; source_members,
            terminal_status = status,
            calibration_semantic_context,
        )
        source_members[role] = member
        dependencies = Tuple((;
            role = dependency_role,
            content_hash = evidence_hashes[dependency_role],
        ) for dependency_role in
            runner.ld1b1_expected_evidence_dependencies(status, role))
        relative = string(role, ".json")
        path = joinpath(attempt_dir, relative)
        evidence = runner.ld1b1_evidence_envelope(
            identity,
            job,
            attempt,
            status,
            role,
            ld1b1_harness_test_evidence_payload(
                runner, job, role, member.sha256; source_members,
                terminal_status = status);
            member,
            dependencies,
            runner_source_sha256,
        )
        ld1b1_harness_test_write_json(path, evidence)
        evidence_hashes[role] = evidence.content_hash.value
        push!(manifest, (;
            role,
            path = relative,
            bytes = filesize(path),
            sha256 = runner.ld1b1_file_sha256(path),
        ))
    end
    artifact = runner.ld1b1_result_envelope(
        identity,
        job,
        attempt,
        status;
        retry_reason,
        retry_of_attempt,
        primary_result_sha256,
        file_manifest = Tuple(manifest),
        lineage_valid,
        runner_source_sha256,
    )
    path = runner.ld1b1_result_path(
        execution_root, job.job_id, attempt)
    runner.ld1b1_atomic_write_artifact(path, artifact; overwrite = false)
    seal = publish_seal ?
        runner.ld1b1_publish_completed_attempt_seal(
            path,
            identity,
            job,
            attempt;
            calibration_semantic_context,
        ) : nothing
    return (; artifact, path, seal, controller_receipts)
end

function ld1b1_harness_test_recovery_receipts!(runner, identity, job,
        execution_root::AbstractString, attempt::Int; with_exit::Bool = true)
    recovery = runner.LD1B1Recovery
    attempt_dir = runner.ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    mkpath(attempt_dir)
    identity_args = (;
        plan_identity = runner.ld1b1_result_plan_identity(identity),
        execution_source_identity = identity.execution_source_identity,
        job_identity = runner.ld1b1_result_job_identity(job),
        attempt_number = attempt,
        attempt_role = attempt == 1 ? :primary : :remediation,
    )
    owner = recovery.ld1b_attempt_owner_precommit(;
        identity_args...,
        controller_host = "synthetic-controller-host",
        controller_run_id = "synthetic-controller-run",
        controller_pid = 12001,
        recorded_at_utc = "2026-07-27T00:00:00Z",
    )
    owner_path = ld1b1_harness_test_write_json(joinpath(
        attempt_dir, recovery.LD1B_ATTEMPT_OWNER_FILENAME), owner)
    owner_sha256 = runner.ld1b1_file_sha256(owner_path)
    launch = recovery.ld1b_child_launch_receipt(;
        identity_args...,
        owner_artifact = owner,
        owner_receipt_sha256 = owner_sha256,
        child_pid = 12002,
        recorded_at_utc = "2026-07-27T00:00:01Z",
    )
    launch_path = ld1b1_harness_test_write_json(joinpath(
        attempt_dir, recovery.LD1B_CHILD_LAUNCH_FILENAME), launch)
    launch_sha256 = runner.ld1b1_file_sha256(launch_path)
    exit = nothing
    exit_path = nothing
    exit_sha256 = nothing
    if with_exit
        exit = recovery.ld1b_child_exit_receipt(;
            identity_args...,
            owner_artifact = owner,
            owner_receipt_sha256 = owner_sha256,
            launch_artifact = launch,
            launch_receipt_sha256 = launch_sha256,
            exit_code = 137,
            recorded_at_utc = "2026-07-27T00:00:02Z",
        )
        exit_path = ld1b1_harness_test_write_json(joinpath(
            attempt_dir, recovery.LD1B_CHILD_EXIT_FILENAME), exit)
        exit_sha256 = runner.ld1b1_file_sha256(exit_path)
    end
    return (; identity_args, attempt_dir, owner, owner_path, owner_sha256,
        launch, launch_path, launch_sha256, exit, exit_path, exit_sha256)
end

function ld1b1_harness_test_external_review!(runner, identity, job,
        execution_root::AbstractString, attempt::Int,
        external_path::AbstractString;
        calibration_semantic_context =
            LD1B1_HARNESS_TEST_CALIBRATION_SEMANTIC_CONTEXT,
        with_exit::Bool = true)
    receipts = ld1b1_harness_test_recovery_receipts!(
        runner, identity, job, execution_root, attempt; with_exit)
    observation = runner.ld1b1_interrupted_attempt_observation(
        execution_root,
        identity,
        job,
        attempt;
        calibration_semantic_context,
    )
    inventory = runner.LD1B1Recovery.
        ld1b_inventory_before_interruption_review(receipts.attempt_dir)
    mode = with_exit ? :validated_exit_receipt :
        :external_process_identity_review
    external_process_identity_review = with_exit ? nothing : (;
        evidence_source = "synthetic independent process-table review",
        controller_process_identity = "controller start-token absent",
        child_process_identity = "child start-token absent",
        observed_at_utc = "2026-07-27T00:04:00Z",
    )
    review = runner.LD1B1Recovery.
        ld1b_stopped_process_interruption_review(;
            receipts.identity_args...,
            owner_artifact = receipts.owner,
            owner_receipt_sha256 = receipts.owner_sha256,
            launch_artifact = receipts.launch,
            launch_receipt_sha256 = receipts.launch_sha256,
            exit_artifact = receipts.exit,
            exit_receipt_sha256 = receipts.exit_sha256,
            inventory_before_review = inventory,
            mode,
            retirement_reason_code = observation.retirement_reason_code,
            observed_attempt_state = (;
                result_present = observation.result_present,
                result_file_sha256 = observation.result_file_sha256,
                result_semantic_assessment =
                    observation.result_semantic_assessment,
            ),
            review_host = "synthetic-review-host",
            reviewer = "synthetic-reviewer",
            reviewed_at_utc = "2026-07-27T00:05:00Z",
            controller_confirmed_stopped = true,
            child_confirmed_stopped = true,
            external_process_identity_review,
        )
    ld1b1_harness_test_write_json(external_path, review)
    return (; receipts, observation, review, external_path)
end

function ld1b1_harness_test_publish_structural_seal!(
        runner, identity, job, result_path::AbstractString,
        attempt::Int, terminal_status::Symbol)
    execution_root = runner.ld1b1_result_execution_root(result_path)
    result_snapshot = runner.ld1b1_regular_file_snapshot(
        result_path,
        execution_root,
        "test job-result envelope",
    )
    result = JSON3.read(String(result_snapshot.bytes))
    manifest = runner.ld1b1_validate_manifest_files(
        result,
        result_path,
        identity,
        job,
        attempt,
        terminal_status,
        result_snapshot,
    )
    attempt_role = attempt == 1 ? :primary : :remediation
    publication = runner.LD1B1AttemptArchive.
        ld1b_publish_completed_attempt_seal(
            dirname(result_path);
            plan_identity = runner.ld1b1_result_plan_identity(identity),
            execution_source_identity = identity.execution_source_identity,
            job_identity = runner.ld1b1_result_job_identity(job),
            attempt_number = attempt,
            attempt_role,
            terminal_status,
            terminal_outcome_code = terminal_status,
            evidence_manifest_sha256 =
                manifest.evidence_manifest_sha256,
            staging_dir = runner.ld1b1_seal_staging_dir(execution_root),
            boundary = execution_root,
        )
    validation = runner.LD1B1AttemptArchive.
        ld1b_validate_completed_attempt_seal(
            dirname(result_path);
            plan_identity = runner.ld1b1_result_plan_identity(identity),
            execution_source_identity = identity.execution_source_identity,
            job_identity = runner.ld1b1_result_job_identity(job),
            attempt_number = attempt,
            attempt_role,
            terminal_status,
            terminal_outcome_code = terminal_status,
        )
    return (; publication, validation, manifest)
end

function ld1b1_harness_test_fixture_fit(data; n_draws::Int = 4)
    design = getdesign(mfrm_spec(data; thresholds = :partial_credit))
    draws = zeros(n_draws, length(design.parameter_names))
    for draw in 2:n_draws
        draws[draw, :] .= range(
            -0.02 * draw,
            0.02 * draw;
            length = size(draws, 2),
        )
    end
    return MFRMFit(
        design,
        MFRMPrior(),
        draws,
        zeros(n_draws),
        1.0,
        ones(Int, n_draws),
        collect(1:n_draws),
        [1.0],
        :fixture,
        :fixture,
        0,
        0.1,
    )
end

@testset "LD1b1 five terminal statuses preserve the public denominator" begin
    grid = local_dependence_simulation_grid(
        repetitions = 1,
        base_seed = 91_301,
        phase = :pilot,
        grid_id = "ld1b1-five-status-fixture",
        n_persons = 8,
        n_testlets = 4,
        items_per_testlet = 2,
        n_raters = 2,
        n_categories = 3,
    )
    eligible = [row for row in grid
        if row.expected_requested_targets_eligible]
    rejection = first(row for row in grid
        if !row.expected_requested_targets_eligible)
    plans = [eligible[1], rejection, eligible[2], eligible[3], eligible[4]]

    diagnostic_contract = local_dependence_contract(
        profile = :custom_unvalidated,
        min_common_units = 2,
        min_eligible_draws = 2,
        min_eligible_draw_fraction = 0.5,
    )
    contract = local_dependence_calibration_contract(;
        diagnostic_contract)
    completed_simulation = simulate_local_dependence(plans[1])
    completed_diagnostic = local_dependence_summary(
        ld1b1_harness_test_fixture_fit(completed_simulation.data);
        contract = diagnostic_contract,
        draw_indices = 1:4,
        rng = MersenneTwister(91_302),
    )
    rejection_simulation = simulate_local_dependence(plans[2])
    fit_failure_simulation = simulate_local_dependence(plans[4])
    diagnostic_failure_simulation = simulate_local_dependence(plans[5])
    results = [
        local_dependence_calibration_row(
            plans[1]; contract, simulation = completed_simulation,
            diagnostic = completed_diagnostic),
        local_dependence_calibration_row(
            plans[2]; contract, status = :pre_fit_rejected,
            simulation = rejection_simulation),
        local_dependence_calibration_row(
            plans[3]; contract, status = :generation_failed,
            failure_code = :synthetic_generation_failure),
        local_dependence_calibration_row(
            plans[4]; contract, status = :fit_failed,
            simulation = fit_failure_simulation,
            failure_code = :synthetic_fit_failure),
        local_dependence_calibration_row(
            plans[5]; contract, status = :diagnostic_failed,
            simulation = diagnostic_failure_simulation,
            failure_code = :synthetic_diagnostic_failure),
    ]

    summary = local_dependence_calibration_summary(plans, results; contract)
    status_count(status) = only(row.n for row in summary.status_rows
        if row.status === status)
    @test summary.n_plan_rows == 5
    @test summary.n_result_rows == 5
    @test summary.n_missing_result_rows == 0
    @test sum(row.n_planned for row in summary.scenario_rows) == 5
    @test sum(row.n_results for row in summary.scenario_rows) == 5
    @test sum(row.n_missing_results for row in summary.scenario_rows) == 0
    @test all(status_count(status) == 1 for status in (
        :completed,
        :pre_fit_rejected,
        :generation_failed,
        :fit_failed,
        :diagnostic_failed,
    ))
end

@testset "LD1b1 pilot batch canonical plan and generated harness" begin
    runner = LD1B1HarnessRunner
    checked = runner.ld1b1_checked_protocol(
        runner.LD1B1_DEFAULT_PROTOCOL;
        consume_bounded_smoke_receipt = false,
    )
    specs = runner.ld1b1_job_specs(checked)

    @test length(specs) == 660
    @test count(job -> job.expected_action === :fit_and_score_diagnostic,
        specs) == 540
    @test count(job -> job.expected_action === :pre_fit_reject,
        specs) == 120
    @test length(unique(job.job_id for job in specs)) == 660
    @test all(occursin(
        r"^ld1b1_pilot__rep[0-9]{2}__s[0-9]{2}__[a-z0-9_]+$",
        job.job_id,
    ) for job in specs)
    @test [job.row_index for job in specs] == collect(1:660)
    @test all(job -> job.primary_attempt == 1 &&
        !job.primary_outcome_overwritable_by_retries, specs)
    failure_semantics = runner.ld1b1_failure_semantics()
    @test failure_semantics.terminal_diagnostic_failures.
        sampler_quality_gate.terminal_status === :diagnostic_failed
    @test !failure_semantics.terminal_diagnostic_failures.
        sampler_quality_gate.sampler_gate_passed
    @test failure_semantics.terminal_diagnostic_failures.
        local_dependence_summary.sampler_gate_passed
    @test ismissing(failure_semantics.nonterminal_artifact_failures.
        sampler_diagnostics_unavailable.terminal_status)
    @test failure_semantics.nonterminal_artifact_failures.
        sampler_diagnostics_unavailable.archive_state === :partial_attempt
    @test ismissing(failure_semantics.nonterminal_artifact_failures.
        final_calibration_serialization_failed.terminal_status)
    @test !failure_semantics.
        incomplete_artifact_failure_counts_toward_scientific_denominator
    @test !failure_semantics.
        incomplete_artifact_failure_may_publish_completed_seal

    protocol = checked.protocol
    @test runner.ld1b1_verify_content_hash(
        protocol; label = "test protocol") ==
        checked.identity.protocol_content_hash
    @test runner.ld1b1_file_sha256(runner.LD1B1_DEFAULT_PROTOCOL) ==
        checked.identity.protocol_file_sha256
    @test runner.ld1b1_canonical_sha256(runner.ld1b1_json_native(
        checked.preflight[:job_rows])) ==
        checked.identity.ordered_job_rows_sha256
    @test checked.identity.ordered_job_rows_sha256 ==
        runner.LD1B1_ORDERED_JOB_ROWS_SHA256
    @test runner.ld1b1_canonical_sha256(runner.ld1b1_json_native(
        protocol[:pilot_contract])) == checked.identity.pilot_contract_sha256
    @test checked.identity.pilot_contract_sha256 ==
        runner.LD1B1_PILOT_CONTRACT_SHA256
    protocol_plan_material = (;
        protocol_file_sha256 = checked.identity.protocol_file_sha256,
        protocol_content_hash = checked.identity.protocol_content_hash,
        ordered_job_rows_sha256 =
            checked.identity.ordered_job_rows_sha256,
        pilot_contract_sha256 = checked.identity.pilot_contract_sha256,
        canonical_executor_source_pin_id =
            checked.identity.canonical_executor_source_pin_id,
        project_toml_sha256 = checked.identity.project_toml_sha256,
        manifest_toml = checked.identity.manifest_toml,
        manifest_toml_sha256 = checked.identity.manifest_toml_sha256,
        source_rows = checked.identity.source_rows,
    )
    @test checked.identity.protocol_plan_id ==
        runner.ld1b1_canonical_sha256(protocol_plan_material)
    @test checked.identity.plan_id == runner.ld1b1_canonical_sha256((;
        protocol_plan_id = checked.identity.protocol_plan_id,
        execution_source_identity = checked.identity.execution_source_identity,
    ))
    @test checked.identity.plan_identity_valid
    @test !checked.identity.execution_plan_complete
    @test checked.identity.execution_plan_assessment ===
        :incomplete_operational_readiness
    @test !checked.identity.readiness.operational_execution_authorized
    @test checked.identity.readiness.canonical_executor_materialized
    @test checked.identity.readiness.
        final_worker_source_pinned_and_identities_regenerated
    @test checked.identity.readiness.canonical_executor_source_pinned
    @test !(:final_worker_source_pinned_and_identities_regenerated in
        checked.identity.readiness.blockers)
    @test !(:canonical_executor_source_pinned in
        checked.identity.readiness.blockers)
    @test :bounded_canonical_smoke_passed in
        checked.identity.readiness.blockers
    @test checked.identity.readiness.
        completed_attempt_archive_seal_supported
    @test !(:completed_attempt_archive_seal_supported in
        checked.identity.readiness.blockers)
    @test :interrupted_attempt_recovery_review_passed in
        checked.identity.readiness.blockers
    @test checked.identity.readiness.canonical_execution_root_bound
    @test all(row -> row.matches &&
        row.recorded_sha256 == row.actual_sha256,
        checked.identity.source_rows)
    @test checked.identity.project_toml_sha256 ==
        runner.ld1b1_file_sha256(joinpath(dirname(@__DIR__), "Project.toml"))
    @test checked.identity.manifest_toml == "Manifest-v1.10.toml"
    @test checked.identity.manifest_toml_sha256 ==
        runner.ld1b1_file_sha256(joinpath(dirname(@__DIR__),
            checked.identity.manifest_toml))
    @test Set(propertynames(
        checked.identity.execution_source_identity)) == Set((
        :batch_runner_source_sha256,
        :local_json_source_sha256,
        :job_runner_source_sha256,
        :attempt_archive_source_sha256,
        :local_dependence_pilot_recovery_source_sha256,
        :local_dependence_pilot_calibration_semantics_source_sha256,
    ))
    @test checked.identity.execution_source_identity.
        attempt_archive_source_sha256 ==
        runner.ld1b1_file_sha256(joinpath(
            dirname(@__DIR__),
            "scripts",
            "local_dependence_pilot_attempt_archive.jl",
        ))
    @test checked.identity.execution_source_identity.
        local_dependence_pilot_recovery_source_sha256 ==
        runner.ld1b1_file_sha256(joinpath(
            dirname(@__DIR__),
            "scripts",
            "local_dependence_pilot_recovery.jl",
        ))
    @test checked.identity.execution_source_identity.
        local_dependence_pilot_calibration_semantics_source_sha256 ==
        runner.ld1b1_file_sha256(joinpath(
            dirname(@__DIR__),
            "scripts",
            "local_dependence_pilot_calibration_semantics.jl",
        ))
    @test checked.identity.batch_harness_generator_source_sha256 ==
        runner.ld1b1_file_sha256(joinpath(
            dirname(@__DIR__),
            "scripts",
            "generate_local_dependence_pilot_batch_execution_harness.jl",
        ))
    generator_metadata = (;
        path =
            "scripts/generate_local_dependence_pilot_batch_execution_harness.jl",
        source_sha256 =
            checked.identity.batch_harness_generator_source_sha256,
        batch_runner_path =
            "scripts/run_local_dependence_calibration_pilot_batch.jl",
        batch_runner_source_sha256 = checked.identity.
            execution_source_identity.batch_runner_source_sha256,
    )
    @test runner.ld1b1_validate_harness_generator_metadata(
        generator_metadata, checked.identity) == generator_metadata
    for forged in (
            merge(generator_metadata, (; path = "scripts/other.jl")),
            merge(generator_metadata, (; source_sha256 = repeat("0", 64))),
            merge(generator_metadata,
                (; batch_runner_path = "scripts/other.jl")),
            merge(generator_metadata,
                (; batch_runner_source_sha256 = repeat("0", 64))),
            merge(generator_metadata, (; unexpected = true)),
        )
        @test_throws ErrorException runner.ld1b1_validate_harness_generator_metadata(
            forged, checked.identity)
    end
    @test all(row -> row.matches &&
        row.recorded_sha256 == row.actual_sha256,
        checked.identity.canonical_executor_source_pin_source_rows)
    @test length(checked.calibration_semantic_context.plan_rows) == 660

    fixture_path = get(
        ENV,
        "MFRM_LOCAL_DEPENDENCE_PILOT_BATCH_EXECUTION_HARNESS_FIXTURE",
        joinpath(dirname(@__DIR__), "test", "fixtures",
            "local_dependence_pilot_batch_execution_harness.json"),
    )
    @test isfile(fixture_path)
    if isfile(fixture_path)
        fixture = JSON3.read(read(fixture_path, String))
        @test String(fixture[:schema]) == runner.LD1B1_HARNESS_SCHEMA
        @test String(fixture[:scope]) ==
            "ld1b1_pilot_batch_harness_preflight_noncalibration"
        @test runner.ld1b1_verify_content_hash(
            fixture; label = "generated LD1b1 batch harness") ==
            String(fixture[:content_hash][:value])
        @test String(fixture[:protocol_artifact][:file_sha256]) ==
            checked.identity.protocol_file_sha256
        @test String(fixture[:protocol_artifact][:content_hash]) ==
            checked.identity.protocol_content_hash
        fixture_identity = fixture[:plan_identity]
        for field in (
                :plan_id,
                :protocol_plan_id,
                :protocol_file_sha256,
                :protocol_content_hash,
                :ordered_job_rows_sha256,
                :pilot_contract_sha256,
                :canonical_executor_source_pin_id,
                :project_toml_sha256,
                :manifest_toml,
                :manifest_toml_sha256,
            )
            @test String(fixture_identity[field]) ==
                String(getproperty(checked.identity, field))
        end
        @test runner.ld1b1_canonical_sha256(runner.ld1b1_json_native(
            fixture_identity[:execution_source_identity])) ==
            runner.ld1b1_canonical_sha256(
                checked.identity.execution_source_identity)
        @test length(fixture[:job_rows]) == 660
        @test length(unique(String(row[:job_id]) for row in
            fixture[:job_rows])) == 660
        summary = fixture[:summary]
        @test Bool(summary[:passed])
        @test Int(summary[:n_plan_jobs]) == 660
        @test Int(summary[:n_fit_jobs]) == 540
        @test Int(summary[:n_pre_fit_rejection_jobs]) == 120
        @test Int(summary[:n_duplicate_job_ids]) == 0
        @test String(summary[:job_runner_availability]) == "available"
        @test String(summary[:execution_capability_status]) == "available"
        @test Bool(summary[
            :final_worker_source_pinned_and_identities_regenerated])
        @test Bool(summary[:canonical_executor_source_pinned])
        @test !Bool(summary[:bounded_canonical_smoke_passed])
        @test !Bool(summary[:interrupted_attempt_recovery_review_passed])
        @test !Bool(summary[:response_data_generated])
        @test !Bool(summary[:model_fit_run])
        @test !Bool(summary[:mcmc_run])
        @test !Bool(summary[:pilot_execution_completed])
        @test !Bool(summary[:calibration_evidence_available])
        @test Int(fixture[:runner][:subprocesses_started]) == 0
        @test String(fixture[:aggregate][:scan_assessment]) == "not_scanned"
        @test fixture[:aggregate][:state_digest] === nothing
        @test fixture[:aggregate][:observed_primary_result_set_sha256] === nothing
        @test String(summary[:attempt_archive_assessment]) == "not_assessed"
        @test summary[:attempt_archive_integrity_passed] === nothing
        harness_contract = fixture[:harness_contract]
        @test Bool(harness_contract[
            :status_specific_hashed_evidence_roles_required])
        @test !Bool(harness_contract[:empty_file_manifest_accepted])
        @test !Bool(harness_contract[
            :symbolic_links_allowed_in_attempt_tree])
        @test Bool(harness_contract[
            :status_specific_semantic_evidence_envelopes_required])
        @test Bool(harness_contract[
            :terminal_evidence_role_sets_must_match_exactly])
        @test !Bool(harness_contract[
            :unmanifested_attempt_files_accepted])
        @test Bool(harness_contract[
            :aggregate_binds_primary_result_and_evidence_digests])
        @test Bool(harness_contract[
            :one_source_artifact_required_per_evidence_role])
        @test Bool(harness_contract[
            :evidence_dependency_content_hashes_required])
        @test Bool(harness_contract[
            :generated_resource_counts_must_match_frozen_jobs])
        @test Bool(harness_contract[
            :generated_response_probability_and_truth_arrays_validated])
        @test Bool(harness_contract[
            :fit_source_requires_structured_json_artifact])
        @test Bool(harness_contract[
            :fit_source_requires_native_and_json_content_hashes])
        @test Bool(harness_contract[
            :fit_json_content_hash_recomputed])
        @test Bool(harness_contract[
            :fit_native_hash_pre_projection_executor_verification_required])
        @test Bool(harness_contract[
            :cross_evidence_data_design_draw_lineage_validated])
        @test Bool(harness_contract[
            :local_summary_execution_seeds_source_bound])
        @test Bool(harness_contract[
            :draw_selection_seed_to_indices_recomputed])
        @test !Bool(harness_contract[
            :posterior_predictive_seed_to_result_replay_verified])
        @test Bool(harness_contract[
            :pre_fit_rejection_requires_simulation_and_calibration_provenance])
        @test Bool(harness_contract[
            :diagnostic_failure_component_must_match_sampler_gate])
        @test !Bool(harness_contract[
            :unavailable_sampler_diagnostics_is_terminal])
        @test !Bool(harness_contract[
            :final_calibration_serialization_failure_is_terminal])
        @test Bool(harness_contract[
            :incomplete_artifact_failure_requires_recovery_disposition])
        @test String(harness_contract[:failure_semantics][:schema]) ==
            "bayesianmgmfrm.local_dependence_pilot_failure_semantics.v1"
        @test Bool(harness_contract[
            :sampler_controls_and_quality_gates_frozen])
        @test !Bool(harness_contract[
            :hard_links_allowed_in_attempt_tree])
        @test Bool(harness_contract[
            :file_snapshot_rechecked_against_attempt_inventory])
        @test !Bool(harness_contract[:archive_validation_is_atomic])
        @test Bool(harness_contract[
            :completed_attempt_archive_seal_supported])
        @test Bool(harness_contract[
            :completed_attempt_seal_create_new_publication_required])
        @test !Bool(harness_contract[
            :result_without_completed_attempt_seal_is_terminal])
        @test Bool(harness_contract[
            :completed_attempt_seal_and_result_semantics_both_required])
        @test Set(String.(harness_contract[:terminal_evidence_roles][
            :completed])) == Set([
            "generated_data",
            "fit_result",
            "sampler_diagnostics",
            "local_dependence_summary",
            "calibration_row",
        ])
        @test String.(harness_contract[:terminal_evidence_roles][
            :pre_fit_rejected]) == [
            "generated_data",
            "structural_rejection_audit",
            "calibration_row",
        ]
        generator = fixture[:artifact_generator]
        @test Set(Symbol.(keys(generator))) == Set((
            :path,
            :source_sha256,
            :batch_runner_path,
            :batch_runner_source_sha256,
            :canonical_executor_source_pin_id,
        ))
        @test String(generator[:canonical_executor_source_pin_id]) ==
            checked.identity.canonical_executor_source_pin_id
        for (field, relative_path) in (
                (:source_sha256,
                    "scripts/generate_local_dependence_pilot_batch_execution_harness.jl"),
                (:batch_runner_source_sha256,
                    "scripts/run_local_dependence_calibration_pilot_batch.jl"),
            )
            @test String(generator[field]) == runner.ld1b1_file_sha256(
                joinpath(dirname(@__DIR__), relative_path))
        end
    end
end

@testset "LD1b1 tracked harness canonicalizes portable path separators" begin
    generator = LD1B1HarnessGenerator
    windows_shaped = (;
        path = raw"scripts\run_local_dependence_calibration_pilot_batch.jl",
        command = raw"'julia' 'scripts\run_local_dependence_calibration_pilot_batch.jl'",
        attempt_roots = [raw"repro\attempts", raw"repro\bounded-smoke"],
        nested = ((;
            attempt_directory = raw"repro\attempts\job-0001",
        ),),
        note = raw"preserve\nonpath",
    )
    portable = generator.ld1b1_portable_harness_value(windows_shaped)
    @test portable.path ==
        "scripts/run_local_dependence_calibration_pilot_batch.jl"
    @test portable.command ==
        "'julia' 'scripts/run_local_dependence_calibration_pilot_batch.jl'"
    @test portable.attempt_roots ==
        ["repro/attempts", "repro/bounded-smoke"]
    @test only(portable.nested).attempt_directory ==
        "repro/attempts/job-0001"
    @test portable.note == raw"preserve\nonpath"
end

@testset "LD1b1 tracked harness ignores dynamic smoke state" begin
    generator = LD1B1HarnessGenerator
    mktempdir() do directory
        output = joinpath(directory, "portable_harness.json")
        generator.ld1b1_harness_generator_main(["--output", output])
        generated = JSON3.read(read(output, String))
        tracked_path = joinpath(
            dirname(@__DIR__),
            "test",
            "fixtures",
            "local_dependence_pilot_batch_execution_harness.json",
        )
        @test read(output) == read(tracked_path)
        @test !Bool(generated[:summary][:bounded_canonical_smoke_passed])
        @test "bounded_canonical_smoke_passed" in String.(
            generated[:summary][:operational_execution_blockers])
        @test String(generated[:plan_identity][
            :bounded_smoke_receipt_validation][:assessment]) ==
            "not_present"
    end
end

@testset "LD1b1 JSON scalar types fail closed" begin
    runner = LD1B1HarnessRunner
    @test runner.ld1b1_int(1) == 1
    @test runner.ld1b1_bool(true)
    @test_throws ErrorException runner.ld1b1_int(true)
    @test_throws ErrorException runner.ld1b1_int(1.0)
    @test_throws ErrorException runner.ld1b1_bool(1)
    @test_throws ErrorException runner.ld1b1_bool(1.0)
    artifact = runner.ld1b1_with_content_hash((; value = 1))
    @test runner.ld1b1_verify_content_hash(
        artifact; label = "test artifact") == artifact.content_hash.value
    extra_metadata = runner.ld1b1_json_native(artifact)
    extra_metadata["content_hash"]["unexpected"] = true
    @test_throws ErrorException runner.ld1b1_verify_content_hash(
        extra_metadata; label = "extra-metadata artifact")
    wrong_coverage = runner.ld1b1_json_native(artifact)
    wrong_coverage["content_hash"]["covers"] = "different_scope"
    @test_throws ErrorException runner.ld1b1_verify_content_hash(
        wrong_coverage; label = "wrong-coverage artifact")
end

@testset "LD1b1 pilot batch plan rejects mutation and shape changes" begin
    runner = LD1B1HarnessRunner
    mktempdir() do directory
        @test_throws ErrorException runner.ld1b1_checked_protocol(
            joinpath(directory, "missing_protocol.json"))

        tampered = ld1b1_harness_test_protocol_copy()
        tampered["pilot_preflight"]["job_rows"][1]["fit_seed"] += 1
        tampered_path = joinpath(directory, "tampered_protocol.json")
        ld1b1_harness_test_write_json(tampered_path, tampered)
        @test_throws ErrorException runner.ld1b1_checked_protocol(tampered_path)

        missing_row = ld1b1_harness_test_protocol_copy()
        pop!(missing_row["pilot_preflight"]["job_rows"])
        ld1b1_harness_test_rehash!(missing_row)
        missing_row_path = joinpath(directory, "missing_row_protocol.json")
        ld1b1_harness_test_write_json(missing_row_path, missing_row)
        @test_throws ErrorException runner.ld1b1_checked_protocol(
            missing_row_path)

        duplicate = ld1b1_harness_test_protocol_copy()
        duplicate["pilot_preflight"]["job_rows"][2] = deepcopy(
            duplicate["pilot_preflight"]["job_rows"][1])
        ld1b1_harness_test_rehash!(duplicate)
        duplicate_path = joinpath(directory, "duplicate_protocol.json")
        ld1b1_harness_test_write_json(duplicate_path, duplicate)
        @test_throws ErrorException runner.ld1b1_checked_protocol(
            duplicate_path)

        sampler_mutation = ld1b1_harness_test_protocol_copy()
        sampler_mutation["pilot_contract"]["sampler"]["chains"] = 3
        ld1b1_harness_test_rehash!(sampler_mutation)
        sampler_mutation_path = joinpath(
            directory, "sampler_mutation_protocol.json")
        ld1b1_harness_test_write_json(
            sampler_mutation_path, sampler_mutation)
        @test_throws ErrorException runner.ld1b1_checked_protocol(
            sampler_mutation_path)

        operational_mutation = ld1b1_harness_test_protocol_copy()
        operational_mutation["pilot_contract"]["operational_requirements"][
            "minimum_completed_per_eligible_scenario"] = 30
        ld1b1_harness_test_rehash!(operational_mutation)
        operational_mutation_path = joinpath(
            directory, "operational_mutation_protocol.json")
        ld1b1_harness_test_write_json(
            operational_mutation_path, operational_mutation)
        @test_throws ErrorException runner.ld1b1_checked_protocol(
            operational_mutation_path)

        action_swap = ld1b1_harness_test_protocol_copy()
        rows = action_swap["pilot_preflight"]["job_rows"]
        eligible_index = findfirst(row ->
            row["expected_action"] == "fit_and_score_diagnostic", rows)
        rejection_index = findfirst(row ->
            row["expected_action"] == "pre_fit_reject", rows)
        rows[eligible_index]["expected_action"],
            rows[rejection_index]["expected_action"] =
            rows[rejection_index]["expected_action"],
            rows[eligible_index]["expected_action"]
        ld1b1_harness_test_rehash!(action_swap)
        action_swap_path = joinpath(directory, "action_swap_protocol.json")
        ld1b1_harness_test_write_json(action_swap_path, action_swap)
        @test_throws ErrorException runner.ld1b1_checked_protocol(
            action_swap_path)
    end
end

@testset "LD1b1 pilot batch selectors fail closed" begin
    runner = LD1B1HarnessRunner
    checked = runner.ld1b1_checked_protocol(runner.LD1B1_DEFAULT_PROTOCOL)
    specs = runner.ld1b1_job_specs(checked)
    for args in (
            ["--mode", "status", "--job-id", "not_a_planned_job"],
            ["--mode", "status", "--row-index", "661"],
            ["--mode", "status", "--scenario", "not_a_scenario"],
            ["--mode", "status", "--replication", "31"],
            ["--mode", "execute-primary", "--max-jobs", "0"],
        )
        options = runner.ld1b1_parse_args(args)
        @test_throws ErrorException runner.ld1b1_selected_jobs(
            specs, options)
    end
    review_path = joinpath(tempdir(), "ld1b1-synthetic-review.json")
    @test_throws ErrorException runner.ld1b1_parse_args([
        "--mode", "retire-interrupted",
        "--job-id", first(specs).job_id,
        "--retirement-reason", "interrupted_without_result",
    ])
    @test_throws ErrorException runner.ld1b1_parse_args([
        "--mode", "retire-interrupted",
        "--job-id", first(specs).job_id,
        "--job-id", specs[2].job_id,
        "--retirement-reason", "interrupted_without_result",
        "--stopped-process-review", review_path,
    ])
    @test_throws ErrorException runner.ld1b1_parse_args([
        "--mode", "retire-interrupted",
        "--job-id", first(specs).job_id,
        "--max-jobs", "1",
        "--retirement-reason", "interrupted_without_result",
        "--stopped-process-review", review_path,
    ])
    @test_throws ErrorException runner.ld1b1_parse_args([
        "--mode", "retire-interrupted",
        "--job-id", first(specs).job_id,
        "--retirement-reason", "reservation_interrupted_before_precommit",
        "--stopped-process-review", review_path,
    ])
    valid_retirement = runner.ld1b1_parse_args([
        "--mode", "retire-interrupted",
        "--job-id", first(specs).job_id,
        "--attempt", "2",
        "--retirement-reason", "interrupted_without_result",
        "--stopped-process-review", review_path,
    ])
    @test valid_retirement.mode === :retire_interrupted
    @test valid_retirement.attempt == 2
    @test valid_retirement.retirement_reason === :interrupted_without_result
end

@testset "LD1b1 sampler gate distinguishes completed and diagnostic failure" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :fit_and_score_diagnostic)
    payload = Dict{Symbol,Any}(key => value for (key, value) in pairs(
        ld1b1_harness_test_evidence_payload(
            runner, job, :sampler_diagnostics, repeat("a", 64);
            source_members = Dict(
                :fit_result => (; sha256 = repeat("f", 64))))))
    payload[:max_rank_normalized_rhat] = 1.02
    payload[:diagnostics_passed] = false
    payload[:diagnostics_flag] = "mcmc_warning"
    payload[:sampler_gate_passed] = false
    @test runner.ld1b1_validate_evidence_payload(
        payload, :sampler_diagnostics, job, :diagnostic_failed)
    @test_throws ErrorException runner.ld1b1_validate_evidence_payload(
        payload, :sampler_diagnostics, job, :completed)
    payload[:e_bfmi] = nothing
    payload[:n_e_bfmi_available] = 0
    payload[:n_e_bfmi_unavailable] = job.sampler_contract.chains
    payload[:e_bfmi_complete] = false
    @test runner.ld1b1_validate_evidence_payload(
        payload, :sampler_diagnostics, job, :diagnostic_failed)
end

@testset "LD1b1 pilot batch immutable attempts and resume scan" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    specs = runner.ld1b1_job_specs(checked)
    eligible = [job for job in specs
        if job.expected_action === :fit_and_score_diagnostic]

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        empty_scan = runner.ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test empty_scan.summary.n_jobs == 660
        @test empty_scan.summary.n_primary_attempts_observed == 0
        @test empty_scan.summary.n_missing_primary_outcomes == 660
        @test empty_scan.summary.n_retry_attempts_observed == 0
        @test empty_scan.summary.clean_attempt_tree
        @test !empty_scan.summary.pilot_execution_completed
        @test !empty_scan.summary.aggregate_ready
        @test all(row -> row.state === :absent, empty_scan.job_state_rows)

        primary_job = eligible[1]
        primary_record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, primary_job, execution_root, 1,
            :completed;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        primary = primary_record.artifact
        primary_path = primary_record.path
        primary_validation = runner.ld1b1_validate_result(
            primary_path,
            checked.identity,
            primary_job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test primary_validation.valid
        @test primary_validation.terminal_status === :completed
        @test primary_validation.result_sha256 ==
            runner.ld1b1_file_sha256(primary_path)
        @test_throws ErrorException runner.ld1b1_atomic_write_artifact(
            primary_path, primary; overwrite = false)

        primary_options = ld1b1_harness_test_options([
            "--mode", "execute-primary",
            "--job-id", primary_job.job_id,
        ], attempt_root)
        @test_throws ErrorException runner.ld1b1_require_attempt_available(
            primary_job,
            checked.identity,
            execution_root,
            primary_options;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )

        primary_sha = runner.ld1b1_file_sha256(primary_path)
        remediation_record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, primary_job, execution_root, 2,
            :completed;
            retry_reason = "verified_scheduler_interruption",
            retry_of_attempt = 1,
            primary_result_sha256 = primary_sha,
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        remediation = remediation_record.artifact
        remediation_path = remediation_record.path
        remediation_validation = runner.ld1b1_validate_result(
            remediation_path,
            checked.identity,
            primary_job,
            2;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test remediation_validation.valid
        @test remediation.attempt.role === :remediation
        @test !remediation.attempt.counts_toward_primary
        @test remediation.attempt.retry_of_attempt == 1
        @test remediation.attempt.primary_result_sha256 == primary_sha
        @test !remediation.primary_outcome_replaced

        retry_options = ld1b1_harness_test_options([
            "--mode", "execute-retry",
            "--job-id", primary_job.job_id,
            "--attempt", "2",
            "--retry-of", "1",
            "--retry-reason", "verified_scheduler_interruption",
        ], attempt_root)
        @test_throws ErrorException runner.ld1b1_require_attempt_available(
            primary_job,
            checked.identity,
            execution_root,
            retry_options;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        next_retry_options = ld1b1_harness_test_options([
            "--mode", "execute-retry",
            "--job-id", primary_job.job_id,
            "--attempt", "3",
            "--retry-of", "1",
            "--retry-reason", "verified_filesystem_interruption",
        ], attempt_root)
        @test runner.ld1b1_require_attempt_available(
            primary_job,
            checked.identity,
            execution_root,
            next_retry_options;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        ) == runner.ld1b1_attempt_dir(
            execution_root, primary_job.job_id, 3)

        scan_specs = eligible[1:4]
        checkpoint_scan = runner.ld1b1_scan_attempts(
            scan_specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        checkpoint = runner.ld1b1_checkpoint_artifact(
            checked.identity,
            checkpoint_scan;
            generated_at = "2026-07-21T00:00:00",
        )
        checkpoint_path = joinpath(execution_root, "checkpoint.json")
        runner.ld1b1_atomic_write_artifact(
            checkpoint_path, checkpoint; overwrite = false)
        @test runner.ld1b1_verify_content_hash(
            JSON3.read(read(checkpoint_path, String));
            label = "test checkpoint",
        ) == checkpoint.content_hash.value

        partial_job = eligible[2]
        mkpath(runner.ld1b1_attempt_dir(
            execution_root, partial_job.job_id, 1))

        corrupt_job = eligible[3]
        corrupt_path = runner.ld1b1_result_path(
            execution_root, corrupt_job.job_id, 1)
        mkpath(dirname(corrupt_path))
        open(corrupt_path, "w") do io
            write(io, "{not-valid-json\n")
        end

        lineage_job = eligible[4]
        lineage = runner.ld1b1_result_envelope(
            checked.identity,
            lineage_job,
            1,
            :completed;
            lineage_valid = false,
            runner_source_sha256 =
                checked.identity.execution_source_identity.job_runner_source_sha256,
        )
        lineage_path = runner.ld1b1_result_path(
            execution_root, lineage_job.job_id, 1)
        runner.ld1b1_atomic_write_artifact(
            lineage_path, lineage; overwrite = false)

        rescanned = runner.ld1b1_scan_attempts(
            scan_specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        by_job = Dict(row.job_id => row for row in rescanned.job_state_rows)
        @test by_job[primary_job.job_id].state ===
            :complete_verified_with_remediation
        @test by_job[primary_job.job_id].primary_valid
        @test by_job[primary_job.job_id].retry_attempts == 1
        @test by_job[partial_job.job_id].state === :partial
        @test by_job[corrupt_job.job_id].state === :corrupt
        @test by_job[lineage_job.job_id].state === :lineage_mismatch
        @test rescanned.summary.n_primary_attempts_observed == 1
        @test rescanned.summary.n_retry_attempts_observed == 1
        @test rescanned.summary.n_partial_attempts == 1
        @test rescanned.summary.n_invalid_attempts == 2
        @test rescanned.summary.n_lineage_mismatches == 1
        @test rescanned.summary.n_missing_primary_outcomes == 3
        @test !rescanned.summary.clean_attempt_tree
        @test !rescanned.summary.aggregate_ready

        resume = runner.ld1b1_resume_state(
            checkpoint_path, checked.identity, rescanned)
        @test resume.checkpoint_present
        @test resume.checkpoint_verified
        @test resume.checkpoint_stale
        @test resume.stored_state_digest == checkpoint_scan.state_digest
        @test resume.rescanned_state_digest == rescanned.state_digest
        @test resume.resume_uses_rescanned_attempts

        for (name, mutate!) in (
                ("execution_source", value ->
                    value["plan_identity"]["execution_source_identity"][
                        "job_runner_source_sha256"] = repeat("0", 64)),
                ("harness_generator", value ->
                    value["plan_identity"][
                        "batch_harness_generator_source_sha256"] =
                            repeat("0", 64)),
                ("source_pin", value ->
                    value["plan_identity"][
                        "canonical_executor_source_pin_id"] =
                            repeat("0", 64)),
            )
            forged = runner.ld1b1_json_native(
                JSON3.read(read(checkpoint_path, String)))
            mutate!(forged)
            ld1b1_harness_test_rehash!(forged)
            forged_path = joinpath(
                execution_root, "checkpoint_forged_$(name).json")
            ld1b1_harness_test_write_json(forged_path, forged)
            @test_throws ErrorException runner.ld1b1_resume_state(
                forged_path, checked.identity, rescanned)
        end

        aggregate_options = ld1b1_harness_test_options([
            "--mode", "aggregate-only",
        ], attempt_root)
        aggregate = runner.ld1b1_build_harness(
            aggregate_options;
            generated_at = "2026-07-21T00:00:00",
        )
        @test aggregate.summary.mode === :aggregate_only
        @test !aggregate.summary.passed
        @test !aggregate.summary.aggregate_ready
        @test aggregate.summary.n_primary_attempts_observed == 1
        @test aggregate.summary.n_retry_attempts_observed == 1
        @test aggregate.summary.n_partial_attempts == 1
        @test aggregate.summary.n_missing_primary_outcomes == 659
        @test aggregate.aggregate.aggregate_only
        @test aggregate.aggregate.attempt_tree_scanned
        @test isempty(aggregate.command_rows)
        @test isempty(aggregate.execution_rows)
        @test aggregate.runner.subprocesses_started == 0
        @test !aggregate.evidence_boundary.response_data_generated
        @test !aggregate.evidence_boundary.model_fit_run
        @test !aggregate.evidence_boundary.mcmc_run
        @test !aggregate.evidence_boundary.pilot_execution_completed
        @test !aggregate.evidence_boundary.calibration_evidence_available
        @test !aggregate.evidence_boundary.diagnostic_decision_labels_available
        @test !aggregate.evidence_boundary.mechanism_interpretation_eligible
        aggregate_without_hash = (; (
            key => value for (key, value) in pairs(aggregate)
            if key !== :content_hash
        )...)
        @test runner.ld1b1_canonical_sha256(aggregate_without_hash) ==
            aggregate.content_hash.value
    end
end

@testset "LD1b1 completed-attempt seal is the terminal boundary" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :fit_and_score_diagnostic)

    for status in (
            :completed,
            :pre_fit_rejected,
            :generation_failed,
            :fit_failed,
            :diagnostic_failed,
        )
        @test runner.ld1b1_terminal_outcome_code(status) === status
    end
    @test_throws ErrorException runner.ld1b1_terminal_outcome_code(
        :interrupted)
    @test_throws ErrorException runner.ld1b1_result_envelope(
        checked.identity,
        job,
        1,
        :completed;
        terminal_outcome_code = :fit_failed,
        runner_source_sha256 =
            checked.identity.execution_source_identity.
                job_runner_source_sha256,
    )

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner,
            checked.identity,
            job,
            execution_root,
            1,
            :completed;
            publish_seal = false,
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        semantic = runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test semantic.valid
        @test semantic.terminal_outcome_code === :completed
        @test record.artifact.terminal_outcome_code === :completed
        @test !ispath(runner.ld1b1_seal_path(
            execution_root, job.job_id, 1))

        unsealed_scan = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        unsealed_job = only(unsealed_scan.job_state_rows)
        unsealed_attempt = only(unsealed_job.attempt_result_rows)
        @test unsealed_job.state === :partial
        @test !unsealed_job.primary_valid
        @test unsealed_attempt.archive_state === :partial
        @test ismissing(unsealed_attempt.terminal_status)
        @test ismissing(unsealed_attempt.terminal_outcome_code)
        @test ismissing(unsealed_attempt.seal_file_sha256)
        @test unsealed_scan.summary.n_primary_attempts_observed == 0
        @test unsealed_scan.summary.n_partial_primary_attempts == 1
        @test unsealed_scan.summary.n_missing_primary_outcomes == 1

        review_source = joinpath(attempt_root, "review-source.json")
        review = ld1b1_harness_test_external_review!(
            runner,
            checked.identity,
            job,
            execution_root,
            1,
            review_source;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test review.observation.retirement_reason_code ===
            :interrupted_with_semantically_valid_unsealed_result
        recovery_options = ld1b1_harness_test_options([
            "--mode", "retire-interrupted",
            "--job-id", job.job_id,
            "--attempt", "1",
            "--retirement-reason",
                "interrupted_with_semantically_valid_unsealed_result",
            "--stopped-process-review", review_source,
        ], attempt_root)
        recovery_artifact = runner.ld1b1_build_harness(
            recovery_options;
            generated_at = "2026-07-27T00:06:00Z",
        )
        @test recovery_artifact.summary.passed
        @test recovery_artifact.summary.mode === :retire_interrupted
        @test isempty(recovery_artifact.command_rows)
        @test isempty(recovery_artifact.execution_rows)
        @test length(recovery_artifact.recovery_rows) == 1
        @test only(recovery_artifact.recovery_rows).action_status ===
            :retired_interruption_verified
        @test !only(recovery_artifact.recovery_rows).subprocess_started
        @test !only(recovery_artifact.recovery_rows).mcmc_run

        retired_scan = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        retired_job = only(retired_scan.job_state_rows)
        retired_attempt = only(retired_job.attempt_result_rows)
        @test retired_job.state === :primary_retired_interrupted
        @test !retired_job.primary_valid
        @test retired_job.primary_disposed
        @test retired_attempt.archive_state === :retired_interrupted
        @test retired_attempt.retirement_reason_code ===
            :interrupted_with_semantically_valid_unsealed_result
        @test retired_scan.summary.n_primary_attempts_observed == 0
        @test retired_scan.summary.n_retired_primary_attempts == 1
        @test retired_scan.summary.n_partial_primary_attempts == 0
        @test retired_scan.summary.n_missing_primary_outcomes == 1
        @test retired_scan.summary.all_primary_attempts_disposed
        @test !retired_scan.summary.all_primary_outcomes_recorded
        @test retired_scan.summary.attempt_archive_integrity_passed
        @test !retired_scan.summary.aggregate_ready
        @test retired_scan.observed_primary_result_set_sha256 ==
            unsealed_scan.observed_primary_result_set_sha256
        @test retired_scan.observed_primary_disposition_set_sha256 !=
            unsealed_scan.observed_primary_disposition_set_sha256
        @test retired_scan.state_digest != unsealed_scan.state_digest
        @test_throws ErrorException runner.
            ld1b1_publish_completed_attempt_seal(
                record.path,
                checked.identity,
                job,
                1;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        before = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(before.job_state_rows).primary_valid
        open(record.path, "a") do io
            write(io, " ")
        end
        @test runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        ).valid
        @test_throws ErrorException runner.ld1b1_validate_completed_attempt(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        after = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(after.job_state_rows).state === :corrupt
        @test !only(after.job_state_rows).primary_valid
        @test after.summary.n_invalid_primary_attempts == 1
        @test after.summary.n_primary_attempts_observed == 0
        @test after.state_digest != before.state_digest
        @test after.observed_primary_result_set_sha256 !=
            before.observed_primary_result_set_sha256
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner,
            checked.identity,
            job,
            execution_root,
            1,
            :completed;
            publish_seal = false,
        )
        result = runner.ld1b1_json_native(
            JSON3.read(read(record.path, String)))
        delete!(result, "terminal_outcome_code")
        ld1b1_harness_test_rehash!(result)
        ld1b1_harness_test_write_json(record.path, result)
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    for field in (
            "attempt_archive_source_sha256",
            "local_dependence_pilot_recovery_source_sha256",
            "local_dependence_pilot_calibration_semantics_source_sha256",
        )
        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            record = ld1b1_harness_test_terminal_result!(
                runner,
                checked.identity,
                job,
                execution_root,
                1,
                :completed;
                publish_seal = false,
            )
            result = runner.ld1b1_json_native(
                JSON3.read(read(record.path, String)))
            delete!(result["execution_source_identity"], field)
            ld1b1_harness_test_rehash!(result)
            ld1b1_harness_test_write_json(record.path, result)
            @test_throws ErrorException runner.ld1b1_validate_result(
                record.path,
                checked.identity,
                job,
                1;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
        end
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner,
            checked.identity,
            job,
            execution_root,
            1,
            :completed;
            publish_seal = false,
        )
        evidence_relative_path = "calibration_row.json"
        evidence_path = joinpath(
            dirname(record.path), evidence_relative_path)
        evidence = runner.ld1b1_json_native(
            JSON3.read(read(evidence_path, String)))
        delete!(
            evidence["execution_source_identity"],
            "local_dependence_pilot_calibration_semantics_source_sha256",
        )
        ld1b1_harness_test_rehash!(evidence)
        ld1b1_harness_test_write_json(evidence_path, evidence)
        ld1b1_harness_test_refresh_evidence_manifest!(
            runner,
            record.path,
            evidence_relative_path,
        )
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end
end

@testset "LD1b1 interruption review retires without completing the denominator" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    specs = runner.ld1b1_job_specs(checked)
    job = first(job for job in specs
        if job.expected_action === :fit_and_score_diagnostic)

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        review_source = joinpath(attempt_root, "no-result-review.json")
        review = ld1b1_harness_test_external_review!(
            runner,
            checked.identity,
            job,
            execution_root,
            1,
            review_source;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test review.observation.retirement_reason_code ===
            :interrupted_without_result
        before = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(before.job_state_rows).state === :partial
        @test before.summary.n_partial_primary_attempts == 1
        checkpoint = runner.ld1b1_checkpoint_artifact(
            checked.identity, before;
            generated_at = "2026-07-27T00:03:00Z",
        )
        checkpoint_path = joinpath(execution_root, "checkpoint.json")
        runner.ld1b1_atomic_write_artifact(
            checkpoint_path, checkpoint; overwrite = false)

        attempt_dir = runner.ld1b1_attempt_dir(
            execution_root, job.job_id, 1)
        published_review = runner.ld1b1_publish_external_interruption_review(
            review_source,
            attempt_dir,
            execution_root,
            checked.identity,
            job,
            1,
        )
        @test published_review.publication.published
        pending = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(pending.job_state_rows).state ===
            :reviewed_pending_retirement
        @test only(only(pending.job_state_rows).attempt_result_rows).
            archive_state === :reviewed_pending_retirement
        @test pending.summary.n_reviewed_pending_retirement_attempts == 1
        @test pending.summary.n_partial_attempts == 1
        @test pending.state_digest != before.state_digest

        options = ld1b1_harness_test_options([
            "--mode", "retire-interrupted",
            "--job-id", job.job_id,
            "--attempt", "1",
            "--retirement-reason", "interrupted_without_result",
            "--stopped-process-review", review_source,
        ], attempt_root)
        selection = runner.ld1b1_selected_jobs(specs, options)
        recovery_rows = runner.ld1b1_retire_interrupted_selected(
            selection, checked, execution_root, options)
        @test only(recovery_rows).action_status ===
            :retired_interruption_verified
        @test !only(recovery_rows).subprocess_started
        retired = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        retired_job = only(retired.job_state_rows)
        @test retired_job.state === :primary_retired_interrupted
        @test retired_job.primary_disposed
        @test !retired_job.primary_valid
        @test retired.summary.n_retired_attempts == 1
        @test retired.summary.n_retired_primary_attempts == 1
        @test retired.summary.n_missing_primary_outcomes == 1
        @test retired.summary.attempt_archive_integrity_passed
        @test !retired.summary.pilot_execution_completed
        @test !retired.summary.aggregate_ready
        @test retired.observed_primary_result_set_sha256 ==
            before.observed_primary_result_set_sha256
        @test retired.observed_primary_disposition_set_sha256 !=
            before.observed_primary_disposition_set_sha256
        resume = runner.ld1b1_resume_state(
            checkpoint_path, checked.identity, retired)
        @test resume.checkpoint_stale

        repeated = runner.ld1b1_retire_interrupted_selected(
            selection, checked, execution_root, options)
        @test only(repeated).review_publication === :reused_existing
        @test only(repeated).retirement_publication === :reused_existing
        @test !only(repeated).mcmc_run
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        receipts = ld1b1_harness_test_recovery_receipts!(
            runner, checked.identity, job, execution_root, 1)
        marker = runner.LD1B1AttemptArchive.
            ld1b_publish_attempt_retirement_marker(
                receipts.attempt_dir;
                plan_identity =
                    runner.ld1b1_result_plan_identity(checked.identity),
                execution_source_identity =
                    checked.identity.execution_source_identity,
                job_identity = runner.ld1b1_result_job_identity(job),
                attempt_number = 1,
                attempt_role = :primary,
                retirement_reason_code = :interrupted_without_result,
                review_record_sha256 = repeat("a", 64),
                process_confirmed_stopped = true,
                staging_dir = runner.ld1b1_retirement_staging_dir(
                    execution_root),
                boundary = execution_root,
            )
        @test marker.validation.valid
        invalid = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(invalid.job_state_rows).state === :corrupt
        @test invalid.summary.n_invalid_primary_attempts == 1
        @test invalid.summary.n_retired_attempts == 0
        @test !invalid.summary.attempt_archive_integrity_passed
    end
end

@testset "LD1b1 pilot batch dry-run remains MCMC-free" begin
    runner = LD1B1HarnessRunner
    mktempdir() do attempt_root
        options = ld1b1_harness_test_options([
            "--mode", "dry-run",
            "--max-jobs", "2",
        ], attempt_root)
        artifact = runner.ld1b1_build_harness(
            options;
            scan_results = false,
            generated_at = "2026-07-21T00:00:00",
        )
        @test artifact.summary.passed
        @test artifact.summary.mode === :dry_run
        @test !artifact.summary.execution_plan_complete
        @test artifact.summary.execution_plan_assessment ===
            :incomplete_operational_readiness
        @test !artifact.summary.operational_execution_authorized
        @test artifact.summary.canonical_executor_materialized
        @test artifact.summary.
            final_worker_source_pinned_and_identities_regenerated
        @test artifact.summary.canonical_executor_source_pinned
        @test !(:canonical_executor_source_pinned in
            artifact.summary.operational_execution_blockers)
        @test :bounded_canonical_smoke_passed in
            artifact.summary.operational_execution_blockers
        @test artifact.summary.completed_attempt_archive_seal_supported
        @test !(:completed_attempt_archive_seal_supported in
            artifact.summary.operational_execution_blockers)
        @test :interrupted_attempt_recovery_review_passed in
            artifact.summary.operational_execution_blockers
        @test :canonical_execution_root_bound in
            artifact.summary.operational_execution_blockers
        @test artifact.summary.n_plan_jobs == 660
        @test artifact.summary.n_fit_jobs == 540
        @test artifact.summary.n_pre_fit_rejection_jobs == 120
        @test artifact.summary.n_duplicate_job_ids == 0
        @test artifact.selection.n_selected_jobs == 2
        @test length(artifact.command_rows) == 2
        @test all(row -> row.attempt == 1 &&
            row.attempt_role === :primary && row.counts_toward_primary,
            artifact.command_rows)
        archive_sha256 = artifact.plan_identity.execution_source_identity.
            attempt_archive_source_sha256
        recovery_sha256 = artifact.plan_identity.execution_source_identity.
            local_dependence_pilot_recovery_source_sha256
        semantics_sha256 = artifact.plan_identity.execution_source_identity.
            local_dependence_pilot_calibration_semantics_source_sha256
        batch_sha256 = artifact.plan_identity.execution_source_identity.
            batch_runner_source_sha256
        local_json_sha256 = artifact.plan_identity.execution_source_identity.
            local_json_source_sha256
        worker_sha256 = artifact.plan_identity.execution_source_identity.
            job_runner_source_sha256
        @test all(row ->
            occursin(artifact.plan_identity.plan_id, row.command) &&
                occursin(
                    artifact.plan_identity.protocol_content_hash,
                    row.command,
                ) &&
                occursin("--batch-runner-source-sha256", row.command) &&
                occursin(batch_sha256, row.command) &&
                occursin("--local-json-source-sha256", row.command) &&
                occursin(local_json_sha256, row.command) &&
                occursin("--runner-source-sha256", row.command) &&
                occursin(worker_sha256, row.command) &&
                occursin("--attempt-archive-source-sha256", row.command) &&
                occursin(archive_sha256, row.command) &&
                occursin(
                    "--local-dependence-pilot-recovery-source-sha256",
                    row.command,
                ) &&
                occursin(recovery_sha256, row.command) &&
                occursin(
                    "--local-dependence-pilot-calibration-semantics-source-sha256",
                    row.command,
                ) &&
                occursin(semantics_sha256, row.command),
            artifact.command_rows)
        @test isempty(artifact.execution_rows)
        @test artifact.runner.subprocesses_started == 0
        @test !artifact.summary.response_data_generated
        @test !artifact.summary.model_fit_run
        @test !artifact.summary.mcmc_run
        @test !artifact.summary.pilot_execution_completed
        @test !artifact.summary.aggregate_ready
        @test ismissing(artifact.summary.n_primary_attempts_observed)
        @test ismissing(artifact.summary.n_missing_primary_outcomes)
        @test artifact.summary.scan_assessment === :not_scanned
        @test artifact.summary.attempt_archive_assessment === :not_assessed
        @test ismissing(artifact.summary.attempt_archive_integrity_passed)
        @test ismissing(artifact.aggregate.state_digest)
        @test !ispath(attempt_root) || isempty(readdir(attempt_root))
    end
end

@testset "LD1b1 execute mode fails before attempt-root creation" begin
    runner = LD1B1HarnessRunner
    mktempdir() do parent
        attempt_root = joinpath(parent, "must_not_be_created")
        options = ld1b1_harness_test_options([
            "--mode", "execute-primary",
            "--row-index", "5",
        ], attempt_root)
        @test !ispath(attempt_root)
        @test_throws ErrorException runner.ld1b1_build_harness(
            options;
            generated_at = "2026-07-27T00:00:00",
        )
        @test !ispath(attempt_root)
    end
end

@testset "LD1b1 aggregate uses the complete primary denominator only" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    specs = runner.ld1b1_job_specs(checked)
    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        for job in specs
            status = job.expected_action === :pre_fit_reject ?
                :pre_fit_rejected : :completed
            ld1b1_harness_test_terminal_result!(
                runner,
                checked.identity,
                job,
                execution_root,
                1,
                status;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
        end

        scan = runner.ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test scan.summary.n_primary_attempts_observed == 660
        @test scan.summary.n_completed_primary_outcomes == 540
        @test scan.summary.n_pre_fit_rejected_primary_outcomes == 120
        @test scan.summary.n_categorized_primary_failures == 0
        @test scan.summary.n_missing_primary_outcomes == 0
        @test scan.summary.n_retry_attempts_observed == 0
        @test all(row -> row.primary_terminal_outcome_code ===
            row.primary_terminal_status, scan.job_state_rows)
        @test scan.summary.clean_attempt_tree
        @test scan.summary.pilot_execution_completed
        @test scan.summary.operational_gate_passed
        @test scan.summary.aggregate_ready
        @test all(row -> row.operational_gate_passed,
            scan.scenario_status_rows)

        aggregate_options = ld1b1_harness_test_options([
            "--mode", "aggregate-only",
        ], attempt_root)
        aggregate = runner.ld1b1_build_harness(
            aggregate_options;
            generated_at = "2026-07-21T00:00:00",
        )
        @test aggregate.summary.passed
        @test aggregate.summary.aggregate_ready
        @test aggregate.summary.pilot_execution_completed
        @test !aggregate.evidence_boundary.response_data_generated
        @test !aggregate.evidence_boundary.model_fit_run
        @test !aggregate.evidence_boundary.mcmc_run
        @test !aggregate.evidence_boundary.evaluation_profile_frozen
        @test !aggregate.evidence_boundary.calibration_evidence_available
        @test !aggregate.evidence_boundary.pairwise_power_available
        @test !aggregate.evidence_boundary.diagnostic_decision_labels_available
        @test !aggregate.evidence_boundary.mechanism_interpretation_eligible

        # A damaged remediation record is retained as an archive-integrity
        # failure, but it cannot replace or reduce the complete primary
        # scientific denominator.
        mkpath(runner.ld1b1_attempt_dir(
            execution_root, first(specs).job_id, 2))
        remediation_scan = runner.ld1b1_scan_attempts(
            specs,
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test remediation_scan.summary.primary_attempt_tree_clean
        @test !remediation_scan.summary.remediation_archive_clean
        @test !remediation_scan.summary.attempt_archive_integrity_passed
        @test remediation_scan.summary.pilot_execution_completed
        @test remediation_scan.summary.operational_gate_passed
        @test remediation_scan.summary.aggregate_ready
        @test remediation_scan.summary.n_partial_primary_attempts == 0
        @test remediation_scan.summary.n_partial_remediation_attempts == 1
        remediation_aggregate = runner.ld1b1_build_harness(
            aggregate_options;
            generated_at = "2026-07-21T00:00:01",
        )
        @test !remediation_aggregate.summary.passed
        @test remediation_aggregate.summary.aggregate_ready
        @test !remediation_aggregate.summary.attempt_archive_integrity_passed
    end
end

@testset "LD1b1 attempt scan rejects numbering gaps" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :fit_and_score_diagnostic)
    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        primary_path = runner.ld1b1_result_path(
            execution_root, job.job_id, 1)
        primary_record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        primary_path = primary_record.path
        remediation_record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 3, :completed;
            retry_reason = "recorded_second_remediation",
            retry_of_attempt = 1,
            primary_result_sha256 = runner.ld1b1_file_sha256(primary_path),
        )
        scan = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(scan.job_state_rows).state === :noncontiguous_attempts
        @test scan.summary.n_primary_attempts_observed == 1
        @test scan.summary.n_retry_attempts_observed == 1
        @test scan.summary.n_unexpected_attempt_tree_entries == 1
        @test !scan.summary.clean_attempt_tree
        @test !scan.summary.aggregate_ready
    end
end

@testset "LD1b1 result evidence and symlink containment fail closed" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :fit_and_score_diagnostic)
    rejection_job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :pre_fit_reject)

    for status in (
            :completed,
            :pre_fit_rejected,
            :generation_failed,
            :fit_failed,
            :diagnostic_failed,
        )
        status_job = status === :pre_fit_rejected ? rejection_job : job
        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            record = ld1b1_harness_test_terminal_result!(
                runner,
                checked.identity,
                status_job,
                execution_root,
                1,
                status;
                publish_seal = false,
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            @test_throws ErrorException runner.ld1b1_validate_result(
                record.path, checked.identity, status_job, 1)
            @test_throws ErrorException runner.
                ld1b1_publish_completed_attempt_seal(
                    record.path, checked.identity, status_job, 1)
            @test_throws ErrorException runner.ld1b1_scan_attempts(
                [status_job], checked.identity, execution_root)
            @test_throws ErrorException runner.
                ld1b1_interrupted_attempt_observation(
                    execution_root, checked.identity, status_job, 1)
            if status === :completed
                @test_throws ErrorException runner.
                    ld1b1_validate_completed_attempt(
                        record.path, checked.identity, status_job, 1)
                @test_throws ErrorException runner.
                    ld1b1_require_attempt_available(
                        status_job,
                        checked.identity,
                        execution_root,
                        (; attempt = 2),
                    )
                wrong_hash_context = merge(
                    checked.calibration_semantic_context,
                    (; public_job_rows_sha256 = repeat("0", 64)),
                )
                @test_throws ErrorException runner.ld1b1_validate_result(
                    record.path,
                    checked.identity,
                    status_job,
                    1;
                    calibration_semantic_context = wrong_hash_context,
                )
                canonical_plan = checked.calibration_semantic_context.
                    plan_rows[status_job.row_index]
                changed_plan_rows = Base.setindex(
                    checked.calibration_semantic_context.plan_rows,
                    merge(canonical_plan, (; seed = canonical_plan.seed + 1)),
                    status_job.row_index,
                )
                wrong_plan_context = merge(
                    checked.calibration_semantic_context,
                    (; plan_rows = changed_plan_rows),
                )
                @test_throws ErrorException runner.ld1b1_validate_result(
                    record.path,
                    checked.identity,
                    status_job,
                    1;
                    calibration_semantic_context = wrong_plan_context,
                )
                changed_grid_plan_rows = Base.setindex(
                    checked.calibration_semantic_context.plan_rows,
                    merge(canonical_plan, (;
                        grid_id = string(canonical_plan.grid_id, "-changed"),
                    )),
                    status_job.row_index,
                )
                wrong_grid_context = merge(
                    checked.calibration_semantic_context,
                    (; plan_rows = changed_grid_plan_rows),
                )
                @test_throws ErrorException runner.
                    ld1b1_validate_calibration_semantic_context_identity(
                        wrong_grid_context,
                        checked.identity,
                        status_job,
                    )
                wrong_preflight_context = merge(
                    checked.calibration_semantic_context,
                    (; public_preflight = merge(
                        checked.calibration_semantic_context.public_preflight,
                        (; status = :changed_preflight_status),
                    )),
                )
                @test_throws ErrorException runner.
                    ld1b1_validate_calibration_semantic_context_identity(
                        wrong_preflight_context,
                        checked.identity,
                        status_job,
                    )
            end
        end
    end

    expected_failure_roles = Dict(
        :generation_failed => (
            :generation_failure_record,
            :calibration_row,
        ),
        :fit_failed => (
            :generated_data,
            :fit_failure_record,
            :calibration_row,
        ),
        :diagnostic_failed => (
            :generated_data,
            :fit_result,
            :sampler_diagnostics,
            :diagnostic_failure_record,
            :calibration_row,
        ),
    )
    for status in (:generation_failed, :fit_failed, :diagnostic_failed)
        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            record = ld1b1_harness_test_terminal_result!(
                runner,
                checked.identity,
                job,
                execution_root,
                1,
                status;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            validated = runner.ld1b1_validate_result(
                record.path,
                checked.identity,
                job,
                1;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            @test validated.terminal_status === status
            @test validated.terminal_outcome_code === status
            @test record.artifact.terminal_outcome_code === status
            @test Set(validated.evidence_roles) ==
                Set(expected_failure_roles[status])
            evidence_map = ld1b1_harness_test_evidence_map(
                runner, record.path)
            calibration = evidence_map[:calibration_row]
            @test Symbol(calibration.payload[:status]) === status
            @test Symbol(calibration.source_value[:failure_code]) ===
                :synthetic_test_failure
            @test ismissing(runner.ld1b1_get(
                calibration.source_value, :diagnostic_provenance, missing))
            @test isempty(calibration.source_value[:pair_evidence])
            @test isempty(calibration.source_value[:family_evidence])
            @test ismissing(runner.ld1b1_get(
                calibration.source_value, :global_evidence, missing))
            if status === :generation_failed
                @test all(field -> ismissing(runner.ld1b1_get(
                    calibration.payload, field, missing)), (
                    :data_signature,
                    :observed_score_signature_sha256,
                    :design_signature_sha256,
                ))
                @test ismissing(runner.ld1b1_get(
                    calibration.source_value,
                    :simulation_provenance,
                    missing,
                ))
                canonical = runner.LD1B1CalibrationSemantics.
                    ld1b1_canonical_generation_failed_row(
                        checked.calibration_semantic_context,
                        job.row_index;
                        failure_record = evidence_map[
                            :generation_failure_record].source_value,
                    )
                @test runner.LD1B1CalibrationSemantics.
                    ld1b1_normalized_json(calibration.source_value) ==
                    runner.LD1B1CalibrationSemantics.
                        ld1b1_normalized_json(canonical.expected)
                @test runner.ld1b1_validate_completed_attempt(
                    record.path,
                    checked.identity,
                    job,
                    1;
                    calibration_semantic_context =
                        checked.calibration_semantic_context,
                ).archive_state === :verified_terminal
            else
                @test !ismissing(runner.ld1b1_get(
                    calibration.source_value,
                    :simulation_provenance,
                    missing,
                ))
                @test calibration.payload[:data_signature] ==
                    evidence_map[:generated_data].payload[:data_signature]
            end
        end
    end

    planned_field_mutations = (
        (:profile, member ->
            (member["profile"] = "mutated_calibration_profile")),
        (:component_seeds, member ->
            (member["component_seeds"]["design"] += 1)),
        (:truth, member ->
            (member["truth"]["target_standard_deviation"] += 0.25)),
    )
    for (field, mutate!) in planned_field_mutations
        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            record = ld1b1_harness_test_terminal_result!(
                runner,
                checked.identity,
                job,
                execution_root,
                1,
                :generation_failed;
                publish_seal = false,
                canonical_controller_receipts = true,
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            evidence_path = joinpath(
                dirname(record.path), "calibration_row.json")
            evidence = runner.ld1b1_json_native(
                JSON3.read(read(evidence_path, String)))
            source_path = joinpath(
                dirname(record.path),
                String(evidence["source_member"]["path"]),
            )
            source = runner.ld1b1_json_native(
                JSON3.read(read(source_path, String)))
            mutate!(source)
            ld1b1_harness_test_write_json(source_path, source)
            ld1b1_harness_test_refresh_source_binding!(
                runner,
                record.path,
                "calibration_row.json",
            )

            sealed = ld1b1_harness_test_publish_structural_seal!(
                runner,
                checked.identity,
                job,
                record.path,
                1,
                :generation_failed,
            )
            @test sealed.validation.valid
            @test occursin(
                r"^[0-9a-f]{64}$",
                sealed.validation.seal_file_sha256,
            )
            failure = try
                runner.ld1b1_validate_completed_attempt(
                    record.path,
                    checked.identity,
                    job,
                    1;
                    calibration_semantic_context =
                        checked.calibration_semantic_context,
                )
                nothing
            catch err
                err
            end
            @test failure isa ErrorException
            @test occursin(
                "calibration semantic replay failed for generation_failed",
                sprint(showerror, failure),
            )
            scan = runner.ld1b1_scan_attempts(
                [job],
                checked.identity,
                execution_root;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            @test only(scan.job_state_rows).state === :corrupt
            @test scan.summary.n_invalid_primary_attempts == 1
            @test field in (:profile, :component_seeds, :truth)
        end
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        empty_evidence = runner.ld1b1_result_envelope(
            checked.identity,
            job,
            1,
            :completed;
            runner_source_sha256 =
                checked.identity.execution_source_identity.job_runner_source_sha256,
        )
        result_path = runner.ld1b1_result_path(
            execution_root, job.job_id, 1)
        runner.ld1b1_atomic_write_artifact(
            result_path, empty_evidence; overwrite = false)
        @test_throws ErrorException runner.ld1b1_validate_result(
            result_path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        scan = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(scan.job_state_rows).state === :corrupt
        @test scan.summary.n_invalid_primary_attempts == 1
        @test !scan.summary.primary_attempt_tree_clean
        @test !scan.summary.aggregate_ready
    end


    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        primary = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        attempt_two_path = runner.ld1b1_result_path(
            execution_root, job.job_id, 2)
        mkpath(dirname(attempt_two_path))
        write(attempt_two_path, "{invalid-remediation\n")
        retry_options = ld1b1_harness_test_options([
            "--mode", "execute-retry",
            "--job-id", job.job_id,
            "--attempt", "3",
            "--retry-of", "1",
            "--retry-reason", "recorded_followup",
        ], attempt_root)
        @test isfile(primary.path)
        @test_throws Exception runner.ld1b1_require_attempt_available(
            job,
            checked.identity,
            execution_root,
            retry_options;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    symlink_capability = ld1b1_harness_test_symlink_capability()
    if symlink_capability.available
        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            record = ld1b1_harness_test_terminal_result!(
                runner, checked.identity, job, execution_root, 1, :completed)
            evidence_path = joinpath(
                dirname(record.path), "calibration_row.json")
            external_path = joinpath(
                attempt_root, "external_generated_data.json")
            write(external_path, read(evidence_path, String))
            rm(evidence_path)
            symlink(external_path, evidence_path)
            @test_throws ErrorException runner.ld1b1_validate_result(
                record.path,
                checked.identity,
                job,
                1;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
        end

        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            jobs_root = joinpath(execution_root, "jobs")
            mkpath(jobs_root)
            external_job_dir = joinpath(attempt_root, "external_job")
            mkpath(external_job_dir)
            symlink(external_job_dir, joinpath(jobs_root, job.job_id))
            scan = runner.ld1b1_scan_attempts(
                [job],
                checked.identity,
                execution_root;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            @test scan.summary.n_unexpected_plan_entries == 1
            @test !scan.summary.primary_attempt_tree_clean
            @test !scan.summary.aggregate_ready
            @test only(scan.job_state_rows).state === :absent
        end


        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            mkpath(execution_root)
            jobs_root = joinpath(execution_root, "jobs")
            dangling_target = joinpath(attempt_root, "missing_jobs_target")
            symlink(dangling_target, jobs_root)
            @test islink(jobs_root)
            @test !ispath(jobs_root)
            scan = runner.ld1b1_scan_attempts(
                [job],
                checked.identity,
                execution_root;
                calibration_semantic_context =
                    checked.calibration_semantic_context,
            )
            @test scan.summary.n_unexpected_plan_entries == 1
            @test !scan.summary.primary_attempt_tree_clean
            @test !scan.summary.aggregate_ready
            @test only(scan.job_state_rows).state === :absent
            unexpected = only(scan.unexpected_plan_entries)
            @test unexpected.path == "jobs"
            @test unexpected.kind === :symbolic_link
            @test unexpected.bytes == ncodeunits(dangling_target)
            @test unexpected.sha256 ==
                bytes2hex(sha256(codeunits(dangling_target)))
        end
    else
        @info "symlink containment tests unavailable at environment boundary" capability = symlink_capability
        @test Sys.iswindows()
        @test !symlink_capability.available
        @test symlink_capability.reason === :windows_symlink_privilege
        @test symlink_capability.code in (Base.UV_EPERM, Base.UV_EACCES)
    end
end

@testset "LD1b1 source artifacts and semantic lineage fail closed" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    specs = runner.ld1b1_job_specs(checked)
    eligible = first(job for job in specs
        if job.expected_action === :fit_and_score_diagnostic)
    rejection = first(job for job in specs
        if job.expected_action === :pre_fit_reject)

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, eligible, execution_root, 1,
            :completed)
        evidence_map = ld1b1_harness_test_evidence_map(runner, record.path)
        @test runner.ld1b1_validate_cross_evidence_lineage(
            evidence_map, :completed, eligible)
        string_keyed_evidence = copy(evidence_map)
        for role in (
                :fit_result,
                :sampler_diagnostics,
                :local_dependence_summary,
            )
            row = evidence_map[role]
            string_keyed_evidence[role] = merge(row, (;
                source_value = runner.ld1b1_json_native(row.source_value),
            ))
        end
        @test runner.ld1b1_validate_cross_evidence_lineage(
            string_keyed_evidence, :completed, eligible)
        observed_data_signature = evidence_map[
            :local_dependence_summary].payload[:data_signature]
        evidence_map[:local_dependence_summary].payload[:data_signature] =
            string(parse(UInt64, observed_data_signature) + UInt64(1))
        @test_throws ErrorException runner.ld1b1_validate_cross_evidence_lineage(
            evidence_map, :completed, eligible)

        simulation_lineage_mutations = (
            evidence -> (evidence[:calibration_row].source_value[
                :simulation_provenance][:status] = :different_status),
            evidence -> (evidence[:calibration_row].source_value[
                :simulation_provenance][:score_signature] = repeat("0", 64)),
            evidence -> (evidence[:calibration_row].source_value[
                :simulation_provenance][:observed_score_signature][:value] =
                    repeat("0", 64)),
            evidence -> (evidence[:calibration_row].source_value[
                :simulation_provenance][:observed_shape][:n_raters] += 1),
            evidence -> (evidence[:calibration_row].source_value[
                :simulation_provenance][:future_fit_action] =
                    :do_not_fit_category_support_incomplete),
        )
        for mutate! in simulation_lineage_mutations
            mutated = ld1b1_harness_test_evidence_map(runner, record.path)
            mutate!(mutated)
            @test_throws ErrorException runner.
                ld1b1_validate_cross_evidence_lineage(
                    mutated, :completed, eligible)
        end
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, eligible, execution_root, 1,
            :diagnostic_failed)
        evidence_map = ld1b1_harness_test_evidence_map(runner, record.path)
        @test runner.ld1b1_validate_cross_evidence_lineage(
            evidence_map, :diagnostic_failed, eligible)
        evidence_map[:diagnostic_failure_record].payload[
            :error_class] = :different_failure
        @test_throws ErrorException runner.ld1b1_validate_cross_evidence_lineage(
            evidence_map, :diagnostic_failed, eligible)
        evidence_map[:diagnostic_failure_record].payload[
            :error_class] = :synthetic_test_failure
        evidence_map[:diagnostic_failure_record].payload[
            :failure_component] = :sampler_quality_gate
        @test_throws ErrorException runner.ld1b1_validate_cross_evidence_lineage(
            evidence_map, :diagnostic_failed, eligible)
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, rejection, execution_root, 1,
            :pre_fit_rejected)
        validated = runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            rejection,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test Set(validated.evidence_roles) == Set((
            :generated_data,
            :structural_rejection_audit,
            :calibration_row,
        ))
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, rejection, execution_root, 1,
            :generation_failed;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            rejection,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        ).terminal_status ===
            :generation_failed
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, eligible, execution_root, 1,
            :completed)
        evidence = JSON3.read(read(joinpath(
            dirname(record.path), "fit_result.json"), String))
        source_path = joinpath(
            dirname(record.path), String(evidence[:source_member][:path]))
        write(source_path, "7JL arbitrary bytes are not a fit artifact\n")
        ld1b1_harness_test_refresh_source_binding!(
            runner, record.path, "fit_result.json")
        @test_throws Exception runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            eligible,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, eligible, execution_root, 1,
            :completed)
        evidence = JSON3.read(read(joinpath(
            dirname(record.path), "generated_data.json"), String))
        source_path = joinpath(
            dirname(record.path), String(evidence[:source_member][:path]))
        source = runner.ld1b1_json_native(
            JSON3.read(read(source_path, String)))
        source["table"]["event_id"] = [1]
        ld1b1_harness_test_write_json(source_path, source)
        ld1b1_harness_test_refresh_source_binding!(
            runner, record.path, "generated_data.json")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            eligible,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

end

@testset "LD1b1 fit-export hashes and summary seeds reject direct substitutions" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :fit_and_score_diagnostic)
    json_bytes(value) = Vector{UInt8}(codeunits(JSON3.write(value)))

    fit_source = ld1b1_harness_test_source_member_value(job, :fit_result)
    fit_payload = ld1b1_harness_test_evidence_payload(
        runner, job, :fit_result, repeat("a", 64))
    validated_fit = runner.ld1b1_validate_source_member_json(
        json_bytes(fit_source), :fit_result, job, fit_payload, :completed)
    @test String(validated_fit[:schema]) ==
        "bayesianmgmfrm.fit_artifact.v1"

    changed_json = deepcopy(fit_source)
    changed_json["artifact"]["created_at"] = "2026-07-21T00:00:01"
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_json), :fit_result, job, fit_payload, :completed)

    changed_native = deepcopy(fit_source)
    changed_native["artifact_content_hash"]["value"] = repeat("0", 64)
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_native), :fit_result, job, fit_payload, :completed)

    changed_json_length = deepcopy(fit_source)
    changed_json_length["json_content_hash"]["n_canonical_bytes"] += 1
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_json_length), :fit_result, job, fit_payload,
        :completed)

    local_source = ld1b1_harness_test_source_member_value(
        job, :local_dependence_summary)
    local_payload = ld1b1_harness_test_evidence_payload(
        runner, job, :local_dependence_summary, repeat("b", 64))
    @test String(runner.ld1b1_validate_source_member_json(
        json_bytes(local_source), :local_dependence_summary,
        job, local_payload, :completed)[:schema]) ==
        "bayesianmgmfrm.local_dependence_pilot_summary_bundle.v1"

    for seed_field in ("draw_selection_seed", "posterior_predictive_seed")
        changed_seed = deepcopy(local_source)
        changed_seed[seed_field] += 1
        @test_throws ErrorException runner.ld1b1_validate_source_member_json(
            json_bytes(changed_seed), :local_dependence_summary,
            job, local_payload, :completed)
    end

    changed_selection = deepcopy(local_source)
    changed_selection["draw_indices"][1:2] =
        reverse(changed_selection["draw_indices"][1:2])
    changed_selection["chain_ids"][1:2] =
        reverse(changed_selection["chain_ids"][1:2])
    changed_selection["iterations"][1:2] =
        reverse(changed_selection["iterations"][1:2])
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_selection), :local_dependence_summary,
        job, local_payload, :completed)
end

@testset "LD1b1 unexpected-entry digests bind archive-relative contents" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(runner.ld1b1_job_specs(checked))
    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        jobs_root = joinpath(execution_root, "jobs")
        mkpath(jobs_root)
        unexpected_path = joinpath(jobs_root, "unexpected.txt")
        write(unexpected_path, "alpha")
        first_scan = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        first_entry = only(first_scan.unexpected_plan_entries)
        @test first_entry.path == joinpath("jobs", "unexpected.txt")
        @test !isabspath(first_entry.path)
        @test first_entry.kind === :file
        @test first_entry.bytes == 5
        @test first_entry.sha256 == runner.ld1b1_file_sha256(unexpected_path)

        write(unexpected_path, "omega")
        second_scan = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        second_entry = only(second_scan.unexpected_plan_entries)
        @test second_entry.path == first_entry.path
        @test second_entry.bytes == first_entry.bytes
        @test second_entry.sha256 != first_entry.sha256
        @test second_scan.state_digest != first_scan.state_digest
    end
end


@testset "LD1b1 semantic evidence and aggregate digests are source-bound" begin
    runner = LD1B1HarnessRunner
    checked = ld1b1_harness_test_checked(runner)
    job = first(job for job in runner.ld1b1_job_specs(checked)
        if job.expected_action === :fit_and_score_diagnostic)

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        validated = runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test occursin(r"^[0-9a-f]{64}$",
            validated.evidence_manifest_sha256)
        @test validated.runner_source_sha256 ==
            checked.identity.execution_source_identity.job_runner_source_sha256

        before = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        checkpoint_path = joinpath(execution_root, "checkpoint.json")
        checkpoint = runner.ld1b1_checkpoint_artifact(
            checked.identity,
            before;
            generated_at = "2026-07-21T00:00:00",
        )
        runner.ld1b1_atomic_write_artifact(
            checkpoint_path, checkpoint; overwrite = false)
        evidence_path = joinpath(dirname(record.path), "calibration_row.json")
        evidence = runner.ld1b1_json_native(
            JSON3.read(read(evidence_path, String)))
        source_path = joinpath(
            dirname(record.path), String(evidence["source_member"]["path"]))
        source = runner.ld1b1_json_native(
            JSON3.read(read(source_path, String)))
        source["family_evidence"] = [Dict(
            "status" => "second_valid_snapshot",
            "decision_available" => false,
        )]
        ld1b1_harness_test_write_json(source_path, source)
        source_sha256 = runner.ld1b1_file_sha256(source_path)
        evidence["source_member"]["bytes"] = filesize(source_path)
        evidence["source_member"]["sha256"] = source_sha256
        evidence["payload"]["calibration_content_sha256"] = source_sha256
        ld1b1_harness_test_rehash!(evidence)
        ld1b1_harness_test_write_json(evidence_path, evidence)
        ld1b1_harness_test_refresh_evidence_manifest!(
            runner, record.path, "calibration_row.json")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        after = runner.ld1b1_scan_attempts(
            [job],
            checked.identity,
            execution_root;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
        @test only(after.job_state_rows).state === :corrupt
        @test after.summary.n_invalid_primary_attempts == 1
        @test before.state_digest != after.state_digest
        @test before.observed_primary_result_set_sha256 !=
            after.observed_primary_result_set_sha256
        resume = runner.ld1b1_resume_state(
            checkpoint_path, checked.identity, after)
        @test resume.checkpoint_stale
        @test resume.stored_state_digest == before.state_digest
        @test resume.rescanned_state_digest == after.state_digest

        write(joinpath(dirname(record.path), "unmanifested.txt"), "unexpected")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        evidence_path = joinpath(dirname(record.path), "generated_data.json")
        ld1b1_harness_test_write_json(evidence_path, Dict(
            "role" => "generated_data",
            "recorded" => true,
        ))
        ld1b1_harness_test_refresh_evidence_manifest!(
            runner, record.path, "generated_data.json")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        evidence_path = joinpath(dirname(record.path), "generated_data.json")
        evidence = runner.ld1b1_json_native(
            JSON3.read(read(evidence_path, String)))
        evidence["payload"]["n_response_rows"] = 1
        ld1b1_harness_test_rehash!(evidence)
        ld1b1_harness_test_write_json(evidence_path, evidence)
        ld1b1_harness_test_refresh_evidence_manifest!(
            runner, record.path, "generated_data.json")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        evidence_path = joinpath(dirname(record.path), "calibration_row.json")
        evidence = runner.ld1b1_json_native(
            JSON3.read(read(evidence_path, String)))
        evidence["dependencies"][1]["content_hash"] = repeat("0", 64)
        ld1b1_harness_test_rehash!(evidence)
        ld1b1_harness_test_write_json(evidence_path, evidence)
        ld1b1_harness_test_refresh_evidence_manifest!(
            runner, record.path, "calibration_row.json")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        evidence_path = joinpath(
            dirname(record.path), "sampler_diagnostics.json")
        evidence = runner.ld1b1_json_native(
            JSON3.read(read(evidence_path, String)))
        evidence["payload"]["max_rank_normalized_rhat"] = 1.02
        ld1b1_harness_test_rehash!(evidence)
        ld1b1_harness_test_write_json(evidence_path, evidence)
        ld1b1_harness_test_refresh_evidence_manifest!(
            runner, record.path, "sampler_diagnostics.json")
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do attempt_root
        execution_root = runner.ld1b1_execution_root(
            attempt_root, checked.identity.plan_id)
        record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, job, execution_root, 1, :completed)
        evidence = JSON3.read(read(
            joinpath(dirname(record.path), "generated_data.json"), String))
        member_path = joinpath(
            dirname(record.path), String(evidence[:source_member][:path]))
        hardlink(member_path, joinpath(attempt_root, "linked_member.json"))
        @test_throws ErrorException runner.ld1b1_validate_result(
            record.path,
            checked.identity,
            job,
            1;
            calibration_semantic_context =
                checked.calibration_semantic_context,
        )
    end

    mktempdir() do directory
        runner_a = joinpath(directory, "runner_a.jl")
        runner_b = joinpath(directory, "runner_b.jl")
        write(runner_a, "# runner a\n")
        write(runner_b, "# runner b\n")
        checked_a = runner.ld1b1_checked_protocol(
            runner.LD1B1_DEFAULT_PROTOCOL; job_runner_path = runner_a)
        checked_b = runner.ld1b1_checked_protocol(
            runner.LD1B1_DEFAULT_PROTOCOL; job_runner_path = runner_b)
        @test checked_a.identity.protocol_plan_id ==
            checked_b.identity.protocol_plan_id
        @test checked_a.identity.plan_id != checked_b.identity.plan_id
        job_a = first(runner.ld1b1_job_specs(checked_a))
        @test_throws ErrorException runner.ld1b1_result_envelope(
            checked_a.identity,
            job_a,
            1,
            job_a.expected_action === :pre_fit_reject ?
                :pre_fit_rejected : :completed;
            runner_source_sha256 =
                checked_b.identity.execution_source_identity.job_runner_source_sha256,
        )
    end
end


@testset "LD1b1 tracked harness sanitizer rejects release-only leakage" begin
    generator = LD1B1HarnessGenerator
    @test isnothing(generator.ld1b1_assert_tracked_harness(Dict(
        "reader_status" => "dry run only",
        "relative_path" => "test/fixtures/example.json",
    )))
    for artifact in (
            Dict("internal_notes" => "remove before release"),
            Dict("reader_note" => "internal only"),
            Dict("worklog" => "pending"),
            Dict("reader_note" => "TODO before release"),
            Dict("path" => "C:\\private\\result.json"),
            Dict("path" => "\\\\server\\share\\result.json"),
        )
        @test_throws ErrorException generator.ld1b1_assert_tracked_harness(
            artifact)
    end
end
