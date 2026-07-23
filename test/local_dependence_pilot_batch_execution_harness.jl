using JSON3
using SHA
using Test

if !isdefined(@__MODULE__, :ScientificPayloadDigest)
    include(joinpath(@__DIR__, "..", "scripts",
        "scientific_payload_digest.jl"))
end
const LD1B1HarnessScientificPayloadDigest = ScientificPayloadDigest

module LD1B1PilotBatchRunnerForTest

include(joinpath(@__DIR__, "..", "scripts",
    "run_local_dependence_calibration_pilot_batch.jl"))

# The production runner must continue to reject any source-byte drift.  This
# one-file binding exists only in this test module so the remainder of the
# harness can still be exercised after that fail-closed boundary is verified.
const _LD1B1_TEST_SOURCE_SHA_SHIM =
    Ref{Union{Nothing,NamedTuple}}(nothing)

_ld1b1_test_physical_file_sha256(path::AbstractString) =
    bytes2hex(open(sha256, path))

function _ld1b1_test_install_single_source_sha_shim!(
        absolute_path::AbstractString,
        recorded_sha256::AbstractString,
        current_sha256::AbstractString)
    isnothing(_LD1B1_TEST_SOURCE_SHA_SHIM[]) ||
        error("the test-only source SHA shim is already installed")
    normalized_path = normpath(abspath(String(absolute_path)))
    expected_path = normpath(abspath(joinpath(
        LD1B1_ROOT,
        "src",
        "bayesian_fit.jl",
    )))
    normalized_path == expected_path ||
        error("the test-only source SHA shim is limited to src/bayesian_fit.jl")
    recorded = String(recorded_sha256)
    current = String(current_sha256)
    occursin(r"^[0-9a-f]{64}$", recorded) ||
        error("the recorded test-only source SHA is not canonical")
    occursin(r"^[0-9a-f]{64}$", current) ||
        error("the current test-only source SHA is not canonical")
    recorded != current ||
        error("the test-only source SHA shim requires actual provenance drift")
    physical = _ld1b1_test_physical_file_sha256(normalized_path)
    physical == current ||
        error("the source changed before the test-only SHA shim was installed")
    binding = (;
        absolute_path = normalized_path,
        recorded_sha256 = recorded,
        current_sha256 = current,
    )
    _LD1B1_TEST_SOURCE_SHA_SHIM[] = binding
    return binding
end

function ld1b1_file_sha256(path::String)
    physical = _ld1b1_test_physical_file_sha256(path)
    binding = _LD1B1_TEST_SOURCE_SHA_SHIM[]
    if !isnothing(binding) &&
            normpath(abspath(path)) == binding.absolute_path
        physical == binding.current_sha256 || error(
            "the shimmed source changed after provenance classification")
        return binding.recorded_sha256
    end
    return physical
end

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
    "run_local_dependence_calibration_pilot_batch.jl",
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
        current_sha256 = runner._ld1b1_test_physical_file_sha256(
            joinpath(dirname(@__DIR__), reference.path)),
    ) for reference in references]
    drift_rows = [row for row in source_rows
        if row.recorded_sha256 != row.current_sha256]

    @test length(source_rows) == 5
    @test count(row -> row.recorded_sha256 == row.current_sha256,
        source_rows) == 4
    @test length(drift_rows) == 1
    length(drift_rows) == 1 || error(
        "the temporary test-only provenance shim requires exactly one drift")
    drift = only(drift_rows)
    @test drift.field === :diagnostic_source_sha256
    @test drift.path == "src/bayesian_fit.jl"

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

    strict_error = try
        runner.ld1b1_checked_protocol(
            runner.LD1B1_DEFAULT_PROTOCOL;
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

    binding = runner._ld1b1_test_install_single_source_sha_shim!(
        drift.absolute_path,
        drift.recorded_sha256,
        drift.current_sha256,
    )
    @test binding.absolute_path == normpath(abspath(drift.absolute_path))
    @test runner._ld1b1_test_physical_file_sha256(drift.absolute_path) ==
        drift.current_sha256
    @test runner.ld1b1_file_sha256(drift.absolute_path) ==
        drift.recorded_sha256
    @test_throws ErrorException begin
        runner._ld1b1_test_install_single_source_sha_shim!(
            drift.absolute_path,
            drift.recorded_sha256,
            drift.current_sha256,
        )
    end
end

ld1b1_harness_test_sha256(text::AbstractString) =
    bytes2hex(sha256(codeunits(String(text))))

function ld1b1_harness_test_signatures(job)
    return (;
        data_signature = 10_000 + job.row_index,
        score_signature = bytes2hex(sha256(codeunits(join(
            fill(0, job.resources.n_ratings), ',')))),
        observed_score_signature = ld1b1_harness_test_sha256(
            "observed-score:$(job.job_id)"),
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
        source_value = JSON3.read(read(source_path, String))
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
        source_members = Dict{Symbol,Any}())
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
    role === :calibration_row && return (;
        calibration_content_sha256 = source_member_sha256,
        calibration_contract =
            "bayesianmgmfrm.local_dependence_calibration_row.v1",
        row_index = job.row_index,
        scenario_index = job.scenario_index,
        scenario_id = job.scenario_id,
        replication = job.replication,
        status = job.expected_action === :pre_fit_reject ?
            :pre_fit_rejected : :completed,
        data_signature = signatures.data_signature,
        observed_score_signature_sha256 =
            signatures.observed_score_signature,
        design_signature_sha256 = signatures.design_signature,
        row_complete = true,
    )
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

function ld1b1_harness_test_planning_fields(job)
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

function ld1b1_harness_test_source_member_value(job, role::Symbol;
        source_members = Dict{Symbol,Any}())
    signatures = ld1b1_harness_test_signatures(job)
    planning = ld1b1_harness_test_planning_fields(job)
    if role === :generated_data
        n = job.resources.n_ratings
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
                "person_labels" => collect(1:40),
                "testlet_labels" => collect(1:4),
                "item_labels" => collect(1:12),
                "rater_labels" => collect(1:4),
                "intended_category_levels" => collect(0:3),
                "realized_category_levels" => collect(0:3),
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
                "requested_targets_eligible" =>
                    job.expected_structural_eligibility,
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
            "gradient_backend" => "analytic",
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
                "validation" => Dict(
                    "data_signature" => signatures.data_signature),
                "fit" => fit_metadata,
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
                    "n_draws" => sampler.total_retained_draws),
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
            "family_rows" => Any[],
            "family_testlet_rows" => Any[],
            "pair_rows" => Any[],
            "family_max_rows" => Any[],
            "global_evidence" => Dict("decision_available" => false),
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
        calibration_status = job.expected_action === :pre_fit_reject ?
            "pre_fit_rejected" : "completed"
        future_fit_action = job.expected_structural_eligibility ?
            "structurally_eligible_for_future_candidate" :
            "do_not_fit_underidentified_design"
        simulation_provenance = Dict(
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
        )
        diagnostic_provenance = job.expected_action === :pre_fit_reject ?
            nothing : Dict(
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
            )
        merge!(value, Dict(
            "schema" =>
                "bayesianmgmfrm.local_dependence_calibration_row.v1",
            "object" => "local_dependence_calibration_row",
            "profile" => String(
                LD1B1_HARNESS_TEST_CALIBRATION_CONTRACT["profile"]),
            "planning_profile" => planning.profile,
            "protocol_status" => "protocol_preflight_only",
            "status" => calibration_status,
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
            "failure_code" => nothing,
            "simulation_provenance" => simulation_provenance,
            "diagnostic_provenance" => diagnostic_provenance,
            "n_pair_evidence" => 0,
            "pair_evidence" => Any[],
            "family_evidence" => Any[],
            "global_evidence" => job.expected_action === :pre_fit_reject ?
                nothing : Dict("decision_available" => false),
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
        source_members = Dict{Symbol,Any}())
    member_role = runner.ld1b1_evidence_member_role(role)
    extension = ".json"
    relative = joinpath("members", string(member_role, extension))
    path = joinpath(attempt_dir, relative)
    mkpath(dirname(path))
    ld1b1_harness_test_write_json(path,
        ld1b1_harness_test_source_member_value(
            job, role; source_members))
    return (;
        role = member_role,
        path = relative,
        media_type = runner.ld1b1_evidence_member_media_type(role),
        bytes = filesize(path),
        sha256 = runner.ld1b1_file_sha256(path),
    )
end

function ld1b1_harness_test_terminal_result!(runner, identity, job,
        execution_root::AbstractString, attempt::Int, status::Symbol;
        retry_reason = nothing,
        retry_of_attempt = nothing,
        primary_result_sha256 = nothing,
        lineage_valid::Bool = true,
        runner_source_sha256 =
            identity.execution_source_identity.job_runner_source_sha256)
    attempt_dir = runner.ld1b1_attempt_dir(
        execution_root, job.job_id, attempt)
    manifest = NamedTuple[]
    evidence_hashes = Dict{Symbol,String}()
    source_members = Dict{Symbol,Any}()
    for role in runner.ld1b1_required_evidence_roles(status)
        member = ld1b1_harness_test_write_source_member!(
            runner, attempt_dir, job, role; source_members)
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
                runner, job, role, member.sha256; source_members);
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
    return (; artifact, path)
end

@testset "LD1b1 pilot batch canonical plan and generated harness" begin
    runner = LD1B1HarnessRunner
    checked = runner.ld1b1_checked_protocol(runner.LD1B1_DEFAULT_PROTOCOL)
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
        project_toml_sha256 = checked.identity.project_toml_sha256,
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
        :incomplete_missing_job_runner
    @test all(row -> row.matches &&
        row.recorded_sha256 == row.actual_sha256,
        checked.identity.source_rows)
    @test checked.identity.project_toml_sha256 ==
        runner.ld1b1_file_sha256(joinpath(dirname(@__DIR__), "Project.toml"))
    @test checked.identity.manifest_toml_sha256 ==
        runner.ld1b1_file_sha256(joinpath(dirname(@__DIR__), "Manifest.toml"))

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
                :project_toml_sha256,
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
        @test String(summary[:job_runner_availability]) ==
            "unavailable_missing_file"
        @test String(summary[:execution_capability_status]) == "unavailable"
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
        @test Bool(harness_contract[
            :sampler_controls_and_quality_gates_frozen])
        @test !Bool(harness_contract[
            :hard_links_allowed_in_attempt_tree])
        @test Bool(harness_contract[
            :file_snapshot_rechecked_against_attempt_inventory])
        @test !Bool(harness_contract[:archive_validation_is_atomic])
        @test !Bool(harness_contract[
            :completed_attempt_archive_seal_supported])
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
            specs, checked.identity, execution_root)
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
            :completed)
        primary = primary_record.artifact
        primary_path = primary_record.path
        primary_validation = runner.ld1b1_validate_result(
            primary_path, checked.identity, primary_job, 1)
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
            primary_options,
        )

        primary_sha = runner.ld1b1_file_sha256(primary_path)
        remediation_record = ld1b1_harness_test_terminal_result!(
            runner, checked.identity, primary_job, execution_root, 2,
            :completed;
            retry_reason = "verified_scheduler_interruption",
            retry_of_attempt = 1,
            primary_result_sha256 = primary_sha,
        )
        remediation = remediation_record.artifact
        remediation_path = remediation_record.path
        remediation_validation = runner.ld1b1_validate_result(
            remediation_path, checked.identity, primary_job, 2)
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
            retry_options,
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
            next_retry_options,
        ) == runner.ld1b1_attempt_dir(
            execution_root, primary_job.job_id, 3)

        scan_specs = eligible[1:4]
        checkpoint_scan = runner.ld1b1_scan_attempts(
            scan_specs, checked.identity, execution_root)
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
            scan_specs, checked.identity, execution_root)
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
        @test artifact.summary.execution_plan_complete
        @test artifact.summary.execution_plan_assessment === :complete
        @test artifact.summary.n_plan_jobs == 660
        @test artifact.summary.n_fit_jobs == 540
        @test artifact.summary.n_pre_fit_rejection_jobs == 120
        @test artifact.summary.n_duplicate_job_ids == 0
        @test artifact.selection.n_selected_jobs == 2
        @test length(artifact.command_rows) == 2
        @test all(row -> row.attempt == 1 &&
            row.attempt_role === :primary && row.counts_toward_primary,
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
                runner, checked.identity, job, execution_root, 1, status)
        end

        scan = runner.ld1b1_scan_attempts(
            specs, checked.identity, execution_root)
        @test scan.summary.n_primary_attempts_observed == 660
        @test scan.summary.n_completed_primary_outcomes == 540
        @test scan.summary.n_pre_fit_rejected_primary_outcomes == 120
        @test scan.summary.n_categorized_primary_failures == 0
        @test scan.summary.n_missing_primary_outcomes == 0
        @test scan.summary.n_retry_attempts_observed == 0
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
            specs, checked.identity, execution_root)
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
            [job], checked.identity, execution_root)
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

    for status in (:generation_failed, :fit_failed, :diagnostic_failed)
        mktempdir() do attempt_root
            execution_root = runner.ld1b1_execution_root(
                attempt_root, checked.identity.plan_id)
            record = ld1b1_harness_test_terminal_result!(
                runner, checked.identity, job, execution_root, 1, status)
            @test runner.ld1b1_validate_result(
                record.path, checked.identity, job, 1).terminal_status === status
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
            result_path, checked.identity, job, 1)
        scan = runner.ld1b1_scan_attempts(
            [job], checked.identity, execution_root)
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
            job, checked.identity, execution_root, retry_options)
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
                record.path, checked.identity, job, 1)
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
                [job], checked.identity, execution_root)
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
                [job], checked.identity, execution_root)
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
        evidence_map[:local_dependence_summary].payload[:data_signature] += 1
        @test_throws ErrorException runner.ld1b1_validate_cross_evidence_lineage(
            evidence_map, :completed, eligible)
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
            record.path, checked.identity, rejection, 1)
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
            :generation_failed)
        @test runner.ld1b1_validate_result(
            record.path, checked.identity, rejection, 1).terminal_status ===
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
            record.path, checked.identity, eligible, 1)
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
            record.path, checked.identity, eligible, 1)
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
        json_bytes(fit_source), :fit_result, job, fit_payload)
    @test String(validated_fit[:schema]) ==
        "bayesianmgmfrm.fit_artifact.v1"

    changed_json = deepcopy(fit_source)
    changed_json["artifact"]["created_at"] = "2026-07-21T00:00:01"
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_json), :fit_result, job, fit_payload)

    changed_native = deepcopy(fit_source)
    changed_native["artifact_content_hash"]["value"] = repeat("0", 64)
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_native), :fit_result, job, fit_payload)

    changed_json_length = deepcopy(fit_source)
    changed_json_length["json_content_hash"]["n_canonical_bytes"] += 1
    @test_throws ErrorException runner.ld1b1_validate_source_member_json(
        json_bytes(changed_json_length), :fit_result, job, fit_payload)

    local_source = ld1b1_harness_test_source_member_value(
        job, :local_dependence_summary)
    local_payload = ld1b1_harness_test_evidence_payload(
        runner, job, :local_dependence_summary, repeat("b", 64))
    @test String(runner.ld1b1_validate_source_member_json(
        json_bytes(local_source), :local_dependence_summary,
        job, local_payload)[:schema]) ==
        "bayesianmgmfrm.local_dependence_pilot_summary_bundle.v1"

    for seed_field in ("draw_selection_seed", "posterior_predictive_seed")
        changed_seed = deepcopy(local_source)
        changed_seed[seed_field] += 1
        @test_throws ErrorException runner.ld1b1_validate_source_member_json(
            json_bytes(changed_seed), :local_dependence_summary,
            job, local_payload)
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
        job, local_payload)
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
            [job], checked.identity, execution_root)
        first_entry = only(first_scan.unexpected_plan_entries)
        @test first_entry.path == joinpath("jobs", "unexpected.txt")
        @test !isabspath(first_entry.path)
        @test first_entry.kind === :file
        @test first_entry.bytes == 5
        @test first_entry.sha256 == runner.ld1b1_file_sha256(unexpected_path)

        write(unexpected_path, "omega")
        second_scan = runner.ld1b1_scan_attempts(
            [job], checked.identity, execution_root)
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
            record.path, checked.identity, job, 1)
        @test occursin(r"^[0-9a-f]{64}$",
            validated.evidence_manifest_sha256)
        @test validated.runner_source_sha256 ==
            checked.identity.execution_source_identity.job_runner_source_sha256

        before = runner.ld1b1_scan_attempts(
            [job], checked.identity, execution_root)
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
        runner.ld1b1_validate_result(
            record.path, checked.identity, job, 1)
        after = runner.ld1b1_scan_attempts(
            [job], checked.identity, execution_root)
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
            record.path, checked.identity, job, 1)
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
            record.path, checked.identity, job, 1)
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
            record.path, checked.identity, job, 1)
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
            record.path, checked.identity, job, 1)
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
            record.path, checked.identity, job, 1)
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
            record.path, checked.identity, job, 1)
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
