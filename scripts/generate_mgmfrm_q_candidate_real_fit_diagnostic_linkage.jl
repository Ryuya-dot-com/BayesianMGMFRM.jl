#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_q_candidate_real_fit_diagnostic_linkage.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :empirical_q_matrix_recovery_simulation_grid,
        path =
            "test/fixtures/mgmfrm_empirical_q_matrix_recovery_simulation_grid.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1",
        pass_policy = :summary_passed),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_q_candidate_real_fit_diagnostic_linkage_v1",
    review_kind = :local_q_candidate_real_fit_diagnostic_linkage,
    publication_or_registration_action = false,
    local_only = true,
    fit_kind = :guarded_confirmatory_mgmfrm_short_fit,
    entrypoint = "fit(spec; experimental = true)",
    diagnostic_surfaces = [
        :q_matrix_validation,
        :fit_metadata,
        :diagnostics,
        :fit_artifact,
        :waic,
    ],
    sampler = (;
        backend = :advancedhmc,
        sampler = :nuts,
        chains = 1,
        warmup = 0,
        draws = 2,
        step_size = 0.02,
        max_depth = 2,
        metric = :unit,
    ),
    thresholds = (;
        require_empirical_q_matrix_recovery_simulation_grid_passed = true,
        require_all_linkage_scenarios_checked = true,
        require_candidate_q_validation_checked = true,
        require_all_fit_attempts_succeeded = true,
        require_all_fit_terms_finite = true,
        require_all_direct_constraints_passed = true,
        require_fixed_q_diagnostic_rows_recorded = true,
        require_invalid_candidates_blocked_before_fit = true,
        require_no_automatic_q_revision = true,
        require_no_public_q_revision_claim = true,
        require_no_mcmc_convergence_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const LINKAGE_SCENARIOS = [
    (;
        scenario = :retained_declared_q_fit_linked,
        source_grid_scenario = :well_separated_true_q_retained,
        source_action = :retain_declared_q,
        dimensions = 2,
        n_items = 2,
        declared_q = Bool[
            1 0
            0 1
        ],
        candidate_q = Bool[
            1 0
            0 1
        ],
        expected_candidate_validation_passed = true,
        expected_fit_attempted = true,
        public_revision_allowed = false,
    ),
    (;
        scenario = :missing_loading_candidate_fit_linked,
        source_grid_scenario = :missing_loading_recovered_as_candidate,
        source_action = :flag_missing_loading_candidate,
        dimensions = 2,
        n_items = 3,
        declared_q = Bool[
            1 0
            0 1
            1 0
        ],
        candidate_q = Bool[
            1 0
            0 1
            1 1
        ],
        expected_candidate_validation_passed = true,
        expected_fit_attempted = true,
        public_revision_allowed = false,
    ),
    (;
        scenario = :extra_loading_candidate_fit_linked,
        source_grid_scenario = :extra_loading_removed_as_candidate,
        source_action = :flag_extra_loading_candidate,
        dimensions = 2,
        n_items = 3,
        declared_q = Bool[
            1 0
            0 1
            1 1
        ],
        candidate_q = Bool[
            1 0
            0 1
            1 0
        ],
        expected_candidate_validation_passed = true,
        expected_fit_attempted = true,
        public_revision_allowed = false,
    ),
    (;
        scenario = :false_positive_candidate_fit_diagnostic_only,
        source_grid_scenario = :high_noise_false_add_not_promoted,
        source_action = :flag_noisy_candidate_manual_review,
        dimensions = 2,
        n_items = 3,
        declared_q = Bool[
            1 0
            0 1
            1 0
        ],
        candidate_q = Bool[
            1 0
            0 1
            1 1
        ],
        expected_candidate_validation_passed = true,
        expected_fit_attempted = true,
        public_revision_allowed = false,
    ),
    (;
        scenario = :invalid_duplicate_dimension_candidate_blocked_before_fit,
        source_grid_scenario = :duplicate_dimension_false_add_blocked,
        source_action = :block_invalid_candidate_revision,
        dimensions = 2,
        n_items = 2,
        declared_q = Bool[
            1 0
            0 1
        ],
        candidate_q = Bool[
            1 1
            1 1
        ],
        expected_candidate_validation_passed = false,
        expected_fit_attempted = false,
        public_revision_allowed = false,
    ),
]

function usage()
    return """
    Generate the local MGMFRM Q-candidate real-fit diagnostic linkage artifact.

    The artifact links deterministic candidate-Q recovery scenarios to the
    guarded fixed-Q MGMFRM fit and diagnostic surfaces. It confirms that valid
    candidate masks can reach fit diagnostics, and that invalid or noisy
    candidates remain local diagnostics only.

    Usage:
      julia --project=. scripts/generate_mgmfrm_q_candidate_real_fit_diagnostic_linkage.jl [--output PATH]
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
local_path(path::AbstractString) = normpath(joinpath(ROOT, path))

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    if !exists
        return (;
            artifact = spec.name,
            path = spec.path,
            exists = false,
            sha256 = missing,
            expected_schema = spec.expected_schema,
            schema = missing,
            schema_matches = false,
            pass_policy = spec.pass_policy,
            summary_passed = false,
            summary = (; passed = false),
        )
    end
    parsed = JSON3.read(read(path, String))
    schema = String(parsed[:schema])
    schema_matches = schema == spec.expected_schema
    summary = parsed[:summary]
    summary_passed =
        spec.pass_policy === :summary_passed && Bool(summary[:passed])
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = file_sha256(path),
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        pass_policy = spec.pass_policy,
        summary_passed,
        summary = (;
            passed = Bool(summary[:passed]),
            candidate_suggestions_allowed =
                Bool(summary[:candidate_suggestions_allowed]),
            no_automatic_q_revision =
                Bool(summary[:no_automatic_q_revision]),
            no_public_recovery_claim =
                Bool(summary[:no_public_recovery_claim]),
            next_gate = String(summary[:next_gate]),
        ),
    )
end

function linked_table(n_items::Int)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for person in 1:4, rater_index in 1:3, item_index in 1:n_items
        push!(examinee, "E$person")
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, mod(person + 2 * rater_index + item_index, 3))
    end
    return (; examinee, rater, item, score)
end

function facet_data(table)
    return BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function matrix_rows(matrix)
    return [[matrix[row, col] for col in axes(matrix, 2)]
        for row in axes(matrix, 1)]
end

function compact_validation_rows(validation)
    return [
        (;
            check = row.check,
            status = row.status,
            severity = row.severity,
            item = row.item,
            dimension = row.dimension,
            n_active = row.n_active,
            n_components = row.n_components,
            note = row.note,
        )
        for row in validation.rows
    ]
end

function validation_record(data, scenario, q_matrix)
    validation = BayesianMGMFRM.q_matrix_validation(data;
        family = :mgmfrm,
        dimensions = scenario.dimensions,
        q_matrix,
        cross_loading_policy = :confirmatory_fixed,
    )
    return (;
        passed = validation.passed,
        n_rows = length(validation.rows),
        error_checks = sort(unique(Symbol(row.check) for row in validation.rows
            if row.severity === :error); by = string),
        warning_checks = sort(unique(Symbol(row.check) for row in validation.rows
            if row.severity === :warning); by = string),
        rows = compact_validation_rows(validation),
    )
end

function finite_or_missing(value)
    ismissing(value) && return missing
    return isfinite(Float64(value)) ? Float64(value) : missing
end

function role_fit_record(role::Symbol, data, scenario, q_matrix, seed::Int)
    validation = validation_record(data, scenario, q_matrix)
    if !validation.passed
        return (;
            role,
            q_matrix = matrix_rows(q_matrix),
            q_matrix_validation = validation,
            fit_attempted = false,
            fit_succeeded = false,
            fit_object = missing,
            public_fit = false,
            experimental_public = false,
            fit_ready = false,
            n_observations = data.n,
            n_raw_parameters = 0,
            n_direct_parameters = 0,
            finite_logposterior = false,
            finite_direct_loglikelihood = false,
            finite_pointwise_loglikelihood = false,
            direct_constraints_passed = false,
            fixed_q_diagnostic_rows_recorded = false,
            diagnostic_schema = missing,
            sampler_diagnostic_schema = missing,
            artifact_schema = missing,
            artifact_content_hash_recorded = false,
            waic_recorded = false,
            waic_elpd = missing,
            sampler_flag = missing,
            diagnostic_flag = missing,
            interpretation = :candidate_blocked_before_fit_by_q_validation,
        )
    end

    spec = BayesianMGMFRM.mfrm_spec(data;
        family = :mgmfrm,
        dimensions = scenario.dimensions,
        q_matrix,
    )
    fit = BayesianMGMFRM.fit(spec;
        experimental = true,
        seed,
        ndraws = PROTOCOL.sampler.draws,
        warmup = PROTOCOL.sampler.warmup,
        chains = PROTOCOL.sampler.chains,
        step_size = PROTOCOL.sampler.step_size,
        max_depth = PROTOCOL.sampler.max_depth,
        metric = PROTOCOL.sampler.metric,
    )
    diagnostics = BayesianMGMFRM.diagnostics(fit)
    artifact = BayesianMGMFRM.fit_artifact(fit; include_environment = false)
    metadata = BayesianMGMFRM.fit_metadata(fit)
    waic_result = BayesianMGMFRM.waic(fit)
    finite_logposterior = all(isfinite, fit.log_posterior)
    finite_direct_loglikelihood = all(isfinite, fit.direct_loglikelihood)
    finite_pointwise_loglikelihood =
        all(isfinite, fit.direct_pointwise_loglikelihood)
    direct_constraints_passed =
        fit.diagnostic_surface.summary.n_failed_direct_constraints == 0
    fixed_q_diagnostic_rows_recorded =
        any(row -> row.policy === :dimension_permutation &&
            row.status === :anchored_by_fixed_q_dimension_labels,
            diagnostics.fixed_q_invariance_rows) &&
        any(row -> row.policy === :loading_sign &&
            row.status === :fixed_positive,
            diagnostics.fixed_q_invariance_rows)
    artifact_content_hash_recorded =
        hasproperty(artifact, :content_hash) &&
        hasproperty(artifact.content_hash, :value) &&
        length(String(artifact.content_hash.value)) == 64
    return (;
        role,
        q_matrix = matrix_rows(q_matrix),
        q_matrix_validation = validation,
        fit_attempted = true,
        fit_succeeded = fit isa BayesianMGMFRM.MGMFRMFit,
        fit_object = :MGMFRMFit,
        public_fit = metadata.public_fit,
        experimental_public = metadata.experimental_public,
        fit_ready = metadata.fit_ready,
        n_observations = data.n,
        n_raw_parameters = size(fit.draws, 2),
        n_direct_parameters = size(fit.direct_draws, 2),
        n_chains = length(fit.chain_acceptance_rate),
        draws_per_chain = PROTOCOL.sampler.draws,
        total_draws = size(fit.draws, 1),
        finite_logposterior,
        finite_direct_loglikelihood,
        finite_pointwise_loglikelihood,
        direct_constraints_passed,
        n_failed_direct_constraints =
            fit.diagnostic_surface.summary.n_failed_direct_constraints,
        fixed_q_diagnostic_rows_recorded,
        diagnostic_schema = diagnostics.schema,
        sampler_diagnostic_schema = fit.diagnostic_surface.schema,
        artifact_schema = artifact.schema,
        artifact_content_hash_recorded,
        waic_recorded = hasproperty(waic_result, :elpd_waic),
        waic_elpd = finite_or_missing(waic_result.elpd_waic),
        sampler_flag = fit.diagnostic_surface.summary.flag,
        diagnostic_flag = diagnostics.summary.flag,
        convergence_claim_made = false,
        interpretation = :fit_diagnostics_shape_and_finiteness_recorded,
    )
end

function scenario_record(scenario, index::Int)
    data = facet_data(linked_table(scenario.n_items))
    declared = role_fit_record(
        :declared_q,
        data,
        scenario,
        scenario.declared_q,
        20260740 + 2 * index - 1,
    )
    candidate_validation = validation_record(data, scenario, scenario.candidate_q)
    candidate_fit_attempted =
        candidate_validation.passed && scenario.expected_fit_attempted
    candidate = candidate_fit_attempted ?
        role_fit_record(
            :candidate_q,
            data,
            scenario,
            scenario.candidate_q,
            20260740 + 2 * index,
        ) :
        (;
            role = :candidate_q,
            q_matrix = matrix_rows(scenario.candidate_q),
            q_matrix_validation = candidate_validation,
            fit_attempted = false,
            fit_succeeded = false,
            fit_object = missing,
            public_fit = false,
            experimental_public = false,
            fit_ready = false,
            n_observations = data.n,
            n_raw_parameters = 0,
            n_direct_parameters = 0,
            finite_logposterior = false,
            finite_direct_loglikelihood = false,
            finite_pointwise_loglikelihood = false,
            direct_constraints_passed = false,
            fixed_q_diagnostic_rows_recorded = false,
            diagnostic_schema = missing,
            sampler_diagnostic_schema = missing,
            artifact_schema = missing,
            artifact_content_hash_recorded = false,
            waic_recorded = false,
            waic_elpd = missing,
            sampler_flag = missing,
            diagnostic_flag = missing,
            convergence_claim_made = false,
            interpretation = :candidate_blocked_before_fit_by_q_validation,
        )
    candidate_validation_matches =
        candidate_validation.passed == scenario.expected_candidate_validation_passed
    fit_attempt_matches =
        Bool(candidate.fit_attempted) == scenario.expected_fit_attempted
    fit_terms_finite =
        (!candidate.fit_attempted ||
         (candidate.finite_logposterior &&
          candidate.finite_direct_loglikelihood &&
          candidate.finite_pointwise_loglikelihood)) &&
        declared.finite_logposterior &&
        declared.finite_direct_loglikelihood &&
        declared.finite_pointwise_loglikelihood
    direct_constraints_passed =
        (!candidate.fit_attempted || candidate.direct_constraints_passed) &&
        declared.direct_constraints_passed
    fixed_q_rows_recorded =
        (!candidate.fit_attempted ||
         candidate.fixed_q_diagnostic_rows_recorded) &&
        declared.fixed_q_diagnostic_rows_recorded
    invalid_candidate_blocked_before_fit =
        !candidate_validation.passed && !candidate.fit_attempted
    public_revision_allowed = scenario.public_revision_allowed
    automatic_revision_allowed = false
    return (;
        scenario = scenario.scenario,
        source_grid_scenario = scenario.source_grid_scenario,
        source_action = scenario.source_action,
        dimensions = scenario.dimensions,
        n_items = scenario.n_items,
        n_observations = data.n,
        declared_fit = declared,
        candidate_fit = candidate,
        public_revision_allowed,
        automatic_revision_allowed,
        public_claim_allowed = false,
        summary = (;
            passed = candidate_validation_matches &&
                fit_attempt_matches &&
                fit_terms_finite &&
                direct_constraints_passed &&
                fixed_q_rows_recorded &&
                !public_revision_allowed &&
                !automatic_revision_allowed,
            candidate_validation_matches,
            fit_attempt_matches,
            fit_terms_finite,
            direct_constraints_passed,
            fixed_q_rows_recorded,
            invalid_candidate_blocked_before_fit,
            candidate_fit_attempted = candidate.fit_attempted,
            candidate_fit_succeeded = candidate.fit_succeeded,
            declared_fit_succeeded = declared.fit_succeeded,
            candidate_convergence_claim_made =
                candidate.fit_attempted ? candidate.convergence_claim_made :
                false,
            interpretation =
                public_revision_allowed ?
                :unexpected_public_revision_allowed :
                :diagnostic_linkage_only_no_public_q_revision,
        ),
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_q_candidate_real_fit_diagnostic_linkage.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function decision_rows()
    return [
        (decision = :link_valid_candidate_q_to_guarded_fit_diagnostics,
            status = :recorded,
            public_claim_allowed = false,
            rationale =
                :valid_candidate_masks_can_reach_fit_diagnostics_without_becoming_revision_claims),
        (decision = :block_invalid_candidate_q_before_fit,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :candidate_masks_must_pass_fixed_q_validation_before_any_fit),
        (decision = :block_q_revision_from_short_fit_diagnostics,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :short_local_fit_finiteness_does_not_establish_construct_validity_or_cross_validated_revision),
    ]
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    simulation_grid =
        record_by_name(input_records, :empirical_q_matrix_recovery_simulation_grid)
    scenarios = [scenario_record(scenario, index)
        for (index, scenario) in enumerate(LINKAGE_SCENARIOS)]
    no_publication = no_publication_commands()
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    all_linkage_scenarios_checked =
        length(scenarios) == length(LINKAGE_SCENARIOS)
    candidate_q_validation_checked =
        all(row -> hasproperty(row.candidate_fit, :q_matrix_validation),
            scenarios)
    all_fit_attempts_succeeded =
        all(row -> !row.candidate_fit.fit_attempted ||
            row.candidate_fit.fit_succeeded, scenarios) &&
        all(row -> row.declared_fit.fit_succeeded, scenarios)
    all_fit_terms_finite = all(row -> row.summary.fit_terms_finite, scenarios)
    all_direct_constraints_passed =
        all(row -> row.summary.direct_constraints_passed, scenarios)
    fixed_q_diagnostic_rows_recorded =
        all(row -> row.summary.fixed_q_rows_recorded, scenarios)
    invalid_candidates_blocked_before_fit =
        all(row -> row.candidate_fit.q_matrix_validation.passed ||
            row.summary.invalid_candidate_blocked_before_fit, scenarios)
    no_automatic_q_revision =
        all(row -> !row.automatic_revision_allowed, scenarios)
    no_public_q_revision_claim =
        all(row -> !row.public_revision_allowed &&
            !row.public_claim_allowed, scenarios)
    no_mcmc_convergence_claim =
        all(row -> !row.summary.candidate_convergence_claim_made, scenarios)
    all_scenarios_passed = all(row -> row.summary.passed, scenarios)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        Bool(simulation_grid.summary.candidate_suggestions_allowed) &&
        Bool(simulation_grid.summary.no_automatic_q_revision) &&
        Bool(simulation_grid.summary.no_public_recovery_claim) &&
        simulation_grid.summary.next_gate ==
            "real_fit_diagnostic_linkage_for_q_candidates" &&
        all_linkage_scenarios_checked &&
        candidate_q_validation_checked &&
        all_fit_attempts_succeeded &&
        all_fit_terms_finite &&
        all_direct_constraints_passed &&
        fixed_q_diagnostic_rows_recorded &&
        invalid_candidates_blocked_before_fit &&
        no_automatic_q_revision &&
        no_public_q_revision_claim &&
        no_mcmc_convergence_claim &&
        no_publication &&
        all_scenarios_passed

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_q_candidate_real_fit_diagnostic_linkage.v1",
        family = :mgmfrm,
        scope = :q_candidate_real_fit_diagnostic_linkage,
        status = :q_candidate_real_fit_diagnostic_linkage_recorded,
        decision = :keep_candidate_q_fit_linkage_diagnostic_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        empirical_q_recovery_public = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        input_artifacts = input_records,
        scenario_rows = scenarios,
        decision_rows = decision_rows(),
        decision_record = (;
            real_fit_diagnostic_linkage_recorded = true,
            candidate_suggestions_allowed = true,
            automatic_q_revision_allowed = false,
            public_q_revision_claim_allowed = false,
            convergence_claim_allowed = false,
            public_exposure_support =
                :q_candidate_real_fit_diagnostic_linkage_recorded,
            interpretation =
                :valid_candidate_q_masks_link_to_fit_diagnostics_but_revision_claims_remain_blocked,
            required_followup =
                :cross_validated_q_revision_policy_for_q_candidates,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            empirical_q_matrix_recovery_simulation_grid_passed =
                simulation_grid.summary_passed,
            all_linkage_scenarios_checked,
            candidate_q_validation_checked,
            all_fit_attempts_succeeded,
            all_fit_terms_finite,
            all_direct_constraints_passed,
            fixed_q_diagnostic_rows_recorded,
            invalid_candidates_blocked_before_fit,
            no_automatic_q_revision,
            no_public_q_revision_claim,
            no_mcmc_convergence_claim,
            n_input_artifacts = length(input_records),
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(row -> row.summary.passed, scenarios),
            n_candidate_fit_attempts =
                count(row -> row.candidate_fit.fit_attempted, scenarios),
            n_candidate_fit_successes =
                count(row -> row.candidate_fit.fit_succeeded, scenarios),
            n_declared_fit_successes =
                count(row -> row.declared_fit.fit_succeeded, scenarios),
            n_invalid_candidates_blocked_before_fit =
                count(row -> row.summary.invalid_candidate_blocked_before_fit,
                    scenarios),
            n_public_revisions_allowed =
                count(row -> row.public_revision_allowed, scenarios),
            n_automatic_revisions_allowed =
                count(row -> row.automatic_revision_allowed, scenarios),
            remaining_public_blockers = [
                :cross_validated_q_revision_policy_missing,
                :construct_validity_manual_review_missing,
            ],
            recommendation =
                :use_candidate_q_real_fit_linkage_for_local_diagnostics_only,
            next_gate = :cross_validated_q_revision_policy_for_q_candidates,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " candidate_fit_attempts=",
        artifact.summary.n_candidate_fit_attempts,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
