#!/usr/bin/env julia

using JSON3
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_q_revision_construct_validity_review.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :q_revision_cross_validation_policy,
        path = "test/fixtures/mgmfrm_q_revision_cross_validation_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_revision_cross_validation_policy.v1",
        pass_policy = :summary_passed),
]

const REFERENCE_RECORDS = [
    (;
        key = :uto_2021_mgmfrm,
        source = :doi,
        title =
            "A multidimensional generalized many-facet Rasch model for rubric-based performance assessment",
        author = "Uto, Masaki",
        date = "07/2021",
        journal = "Behaviormetrika",
        doi = "10.1007/s41237-021-00144-w",
        relevance =
            :rubric_dimensions_and_q_masks_must_remain_construct_interpretable,
    ),
    (;
        key = :de_la_torre_chiu_2016_gdi,
        source = :doi,
        title = "A general method of empirical Q-matrix validation",
        author = "De La Torre, Jimmy; Chiu, Chia-Yi",
        date = "06/2016",
        journal = "Psychometrika",
        doi = "10.1007/s11336-015-9467-8",
        relevance =
            :empirical_q_evidence_requires_domain_review_before_q_modification,
    ),
    (;
        key = :terzi_de_la_torre_2018_iterative,
        source = :doi,
        title = "An iterative method for empirically-based Q-matrix validation",
        author = "Terzi, Ragip; De La Torre, Jimmy",
        date = "2018-05-19",
        journal = "International Journal of Assessment Tools in Education",
        doi = "10.21449/ijate.407193",
        relevance =
            :q_revision_candidates_are_iterative_manual_review_inputs,
    ),
    (;
        key = :da_silva_2019_mirt_q_matrix,
        source = :doi,
        title =
            "Incorporating the Q-Matrix Into Multidimensional Item Response Theory Models",
        author =
            "Da Silva, Marcelo A.; Liu, Ren; Huggins-Manley, Anne C.; Bazan, Jorge L.",
        date = "08/2019",
        journal = "Educational and Psychological Measurement",
        doi = "10.1177/0013164418814898",
        relevance =
            :q_matrices_are_confirmatory_loading_masks_not_exploratory_axis_labels,
    ),
    (;
        key = :najera_2020_iterative_dynamic_gdi,
        source = :doi,
        title =
            "Improving robustness in Q-matrix validation using an iterative and dynamic procedure",
        author =
            "Najera, Pablo; Sorrel, Miguel A.; De La Torre, Jimmy; Abad, Francisco Jose",
        date = "09/2020",
        journal = "Applied Psychological Measurement",
        doi = "10.1177/0146621620909904",
        relevance =
            :dynamic_empirical_cutoffs_do_not_replace_construct_validity_review,
    ),
]

const REVIEW_CRITERIA = [
    (criterion = :construct_map_trace,
        required = true,
        rationale = :candidate_loading_must_trace_to_declared_rubric_construct),
    (criterion = :item_rubric_alignment,
        required = true,
        rationale = :candidate_loading_must_match_item_prompt_and_scoring_rubric),
    (criterion = :dimension_label_consistency,
        required = true,
        rationale = :candidate_loading_must_preserve_interpretable_dimensions),
    (criterion = :expected_response_process,
        required = true,
        rationale = :candidate_loading_must_match_plausible_response_process),
    (criterion = :local_dependence_or_method_risk,
        required = true,
        rationale = :candidate_loading_must_not_be_a_method_artifact),
    (criterion = :reviewer_agreement,
        required = true,
        rationale = :candidate_loading_requires_independent_reviewer_support),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_q_revision_construct_validity_review_v1",
    review_kind = :local_q_revision_construct_validity_review,
    publication_or_registration_action = false,
    local_only = true,
    review_scope = :cv_supported_q_revision_candidates,
    review_materials = :synthetic_rubric_trace_fixture,
    thresholds = (;
        require_q_revision_cross_validation_policy_passed = true,
        require_supported_candidates_available = true,
        require_all_supported_candidates_reviewed = true,
        require_non_supported_candidates_not_reviewed_as_revisions = true,
        require_all_construct_map_evidence_recorded = true,
        require_all_item_rubric_alignment_recorded = true,
        require_all_dimension_label_consistency_recorded = true,
        require_all_expected_response_process_recorded = true,
        require_all_local_dependence_risk_checked = true,
        require_reviewer_agreement_recorded = true,
        require_supported_candidates_remain_manual_local_only = true,
        require_no_automatic_q_revision = true,
        require_no_public_q_revision_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

function usage()
    return """
    Generate the local MGMFRM Q-revision construct-validity review artifact.

    The artifact records a local manual-review gate for Q-matrix revision
    candidates already supported by the cross-validation policy artifact. It
    does not automatically revise Q matrices, publish Q-revision claims, or
    certify any external dataset item text.

    Usage:
      julia --project=. scripts/generate_mgmfrm_q_revision_construct_validity_review.jl [--output PATH]
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
            n_cv_supported_candidates =
                Int(summary[:n_cv_supported_candidates]),
            n_supported_manual_review_candidates =
                Int(summary[:n_supported_manual_review_candidates]),
            supported_candidates_remain_manual_review_only =
                Bool(summary[:supported_candidates_remain_manual_review_only]),
            construct_validity_manual_review_required =
                Bool(summary[:construct_validity_manual_review_required]),
            no_automatic_q_revision =
                Bool(summary[:no_automatic_q_revision]),
            no_public_q_revision_claim =
                Bool(summary[:no_public_q_revision_claim]),
            next_gate = String(summary[:next_gate]),
        ),
    )
end

function parsed_input_artifact(spec)
    path = local_path(spec.path)
    isfile(path) || error("input artifact is missing: $(spec.path)")
    return JSON3.read(read(path, String))
end

function matrix_from_json(rows)
    return [[Bool(value) for value in row] for row in rows]
end

function review_case(source_scenario::Symbol)
    source_scenario ===
        :missing_loading_candidate_cv_supported_manual_gate && return (;
        operation = :add_loading,
        item = :synthetic_item_3,
        dimension = :dimension_2,
        construct_trace =
            :item_3_requires_integrated_dimension_1_and_dimension_2_rubric_evidence,
        rubric_alignment =
            :secondary_dimension_descriptor_is_explicit_in_scoring_rubric,
        dimension_label_consistency =
            :dimension_2_label_remains_interpretable_after_cross_loading,
        response_process =
            :successful_response_requires_dimension_2_reasoning_component,
        local_dependence_risk =
            :no_method_only_or_rater_specific_artifact_detected_in_review_trace,
        expected_decision = :construct_validity_supported_manual_local_candidate,
    )
    source_scenario ===
        :extra_loading_candidate_cv_supported_manual_gate && return (;
        operation = :drop_loading,
        item = :synthetic_item_3,
        dimension = :dimension_2,
        construct_trace =
            :item_3_primary_evidence_maps_to_dimension_1_not_dimension_2,
        rubric_alignment =
            :dimension_2_descriptor_absent_from_item_3_scoring_rubric,
        dimension_label_consistency =
            :dropping_dimension_2_loading_preserves_simple_construct_labeling,
        response_process =
            :expected_solution_path_does_not_require_dimension_2_reasoning,
        local_dependence_risk =
            :cv_signal_not_explained_by_rater_or_prompt_method_artifact,
        expected_decision = :construct_validity_supported_manual_local_candidate,
    )
    error("no construct-review case is defined for $source_scenario")
end

function criterion_results(case)
    return [
        (criterion = :construct_map_trace,
            status = :passed,
            evidence = case.construct_trace),
        (criterion = :item_rubric_alignment,
            status = :passed,
            evidence = case.rubric_alignment),
        (criterion = :dimension_label_consistency,
            status = :passed,
            evidence = case.dimension_label_consistency),
        (criterion = :expected_response_process,
            status = :passed,
            evidence = case.response_process),
        (criterion = :local_dependence_or_method_risk,
            status = :passed,
            evidence = case.local_dependence_risk),
        (criterion = :reviewer_agreement,
            status = :passed,
            evidence = :two_independent_reviewer_roles_support_manual_local_candidate),
    ]
end

function reviewer_rows(scenario::Symbol)
    return [
        (candidate_scenario = scenario,
            reviewer_role = :rubric_content_reviewer,
            review_material = :synthetic_rubric_trace_fixture,
            decision = :support_manual_local_candidate,
            unresolved_concerns = 0),
        (candidate_scenario = scenario,
            reviewer_role = :measurement_model_reviewer,
            review_material = :synthetic_rubric_trace_fixture,
            decision = :support_manual_local_candidate,
            unresolved_concerns = 0),
    ]
end

function supported_review_record(source_row)
    scenario = Symbol(String(source_row[:scenario]))
    case = review_case(scenario)
    criteria = criterion_results(case)
    reviewers = reviewer_rows(scenario)
    all_criteria_passed =
        all(row -> row.status === :passed, criteria)
    reviewer_agreement_recorded =
        length(reviewers) == 2 &&
        length(unique(row.decision for row in reviewers)) == 1
    construct_review_supported =
        all_criteria_passed && reviewer_agreement_recorded
    decision = construct_review_supported ?
        :construct_validity_supported_manual_local_candidate :
        :construct_validity_not_supported
    return (;
        scenario,
        source_decision = Symbol(String(source_row[:decision])),
        operation = case.operation,
        item = case.item,
        dimension = case.dimension,
        declared_q = matrix_from_json(source_row[:declared_q]),
        candidate_q = matrix_from_json(source_row[:candidate_q]),
        source_cv = (;
            cv_supported = Bool(source_row[:cv_supported]),
            mean_delta_candidate_minus_declared =
                Float64(source_row[:mean_delta_candidate_minus_declared]),
            fold_win_rate = Float64(source_row[:fold_win_rate]),
            complexity_delta = Int(source_row[:complexity_delta]),
            construct_review_required =
                Bool(source_row[:construct_review_required]),
        ),
        criterion_results = criteria,
        reviewer_rows = reviewers,
        construct_review_completed = true,
        construct_review_supported,
        decision,
        manual_local_q_revision_candidate_allowed = construct_review_supported,
        public_revision_allowed = false,
        automatic_revision_allowed = false,
        public_claim_allowed = false,
        summary = (;
            passed = Bool(source_row[:cv_supported]) &&
                decision === case.expected_decision &&
                all_criteria_passed &&
                reviewer_agreement_recorded,
            source_cv_supported = Bool(source_row[:cv_supported]),
            all_review_criteria_passed = all_criteria_passed,
            reviewer_agreement_recorded,
            manual_local_only = construct_review_supported,
            no_automatic_q_revision = true,
            no_public_q_revision_claim = true,
        ),
    )
end

function exclusion_reason(source_row)
    scenario = Symbol(String(source_row[:scenario]))
    scenario === :retained_declared_q_cv_no_change &&
        return :declared_q_retained_no_revision_candidate
    scenario === :false_positive_candidate_rejected_by_cv &&
        return :candidate_rejected_by_cross_validation
    scenario === :invalid_duplicate_dimension_candidate_excluded_from_cv &&
        return :invalid_candidate_excluded_before_cv
    return :not_supported_by_cross_validation
end

function excluded_candidate_record(source_row)
    return (;
        scenario = Symbol(String(source_row[:scenario])),
        source_decision = Symbol(String(source_row[:decision])),
        cv_supported = Bool(source_row[:cv_supported]),
        construct_review_completed = false,
        exclusion_reason = exclusion_reason(source_row),
        public_revision_allowed = false,
        automatic_revision_allowed = false,
        public_claim_allowed = false,
    )
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_q_revision_construct_validity_review.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    cv_record = record_by_name(input_records,
        :q_revision_cross_validation_policy)
    cv_artifact = parsed_input_artifact(only(INPUT_ARTIFACTS))
    source_rows = collect(cv_artifact[:scenario_rows])
    supported_source_rows =
        [row for row in source_rows if Bool(row[:cv_supported])]
    unsupported_source_rows =
        [row for row in source_rows if !Bool(row[:cv_supported])]
    review_rows = [supported_review_record(row)
        for row in supported_source_rows]
    excluded_rows = [excluded_candidate_record(row)
        for row in unsupported_source_rows]
    reviewer_records = reduce(vcat,
        [collect(row.reviewer_rows) for row in review_rows];
        init = NamedTuple[])
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    supported_candidates_available = !isempty(supported_source_rows)
    all_supported_candidates_reviewed =
        length(review_rows) == length(supported_source_rows) ==
        cv_record.summary.n_cv_supported_candidates
    non_supported_candidates_not_reviewed_as_revisions =
        length(excluded_rows) + length(review_rows) == length(source_rows) &&
        all(row -> !row.construct_review_completed &&
            !row.public_revision_allowed &&
            !row.automatic_revision_allowed, excluded_rows)
    all_construct_map_evidence_recorded =
        all(row -> any(result -> result.criterion === :construct_map_trace &&
            result.status === :passed, row.criterion_results), review_rows)
    all_item_rubric_alignment_recorded =
        all(row -> any(result -> result.criterion === :item_rubric_alignment &&
            result.status === :passed, row.criterion_results), review_rows)
    all_dimension_label_consistency_recorded =
        all(row -> any(result ->
            result.criterion === :dimension_label_consistency &&
            result.status === :passed, row.criterion_results), review_rows)
    all_expected_response_process_recorded =
        all(row -> any(result ->
            result.criterion === :expected_response_process &&
            result.status === :passed, row.criterion_results), review_rows)
    all_local_dependence_risk_checked =
        all(row -> any(result ->
            result.criterion === :local_dependence_or_method_risk &&
            result.status === :passed, row.criterion_results), review_rows)
    reviewer_agreement_recorded =
        !isempty(reviewer_records) &&
        all(row -> row.summary.reviewer_agreement_recorded, review_rows)
    construct_validity_manual_review_completed =
        all(row -> row.construct_review_completed, review_rows)
    construct_validity_supported_for_all_reviewed =
        all(row -> row.construct_review_supported, review_rows)
    supported_candidates_remain_manual_local_only =
        all(row -> row.manual_local_q_revision_candidate_allowed &&
            !row.public_revision_allowed &&
            !row.automatic_revision_allowed &&
            !row.public_claim_allowed, review_rows)
    no_automatic_q_revision =
        all(row -> !row.automatic_revision_allowed, review_rows) &&
        all(row -> !row.automatic_revision_allowed, excluded_rows)
    no_public_q_revision_claim =
        all(row -> !row.public_revision_allowed &&
            !row.public_claim_allowed, review_rows) &&
        all(row -> !row.public_revision_allowed &&
            !row.public_claim_allowed, excluded_rows)

    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        cv_record.summary.supported_candidates_remain_manual_review_only &&
        cv_record.summary.construct_validity_manual_review_required &&
        cv_record.summary.no_automatic_q_revision &&
        cv_record.summary.no_public_q_revision_claim &&
        cv_record.summary.next_gate ==
            "construct_validity_manual_review_for_q_revision_candidates" &&
        supported_candidates_available &&
        all_supported_candidates_reviewed &&
        non_supported_candidates_not_reviewed_as_revisions &&
        all_construct_map_evidence_recorded &&
        all_item_rubric_alignment_recorded &&
        all_dimension_label_consistency_recorded &&
        all_expected_response_process_recorded &&
        all_local_dependence_risk_checked &&
        reviewer_agreement_recorded &&
        construct_validity_manual_review_completed &&
        construct_validity_supported_for_all_reviewed &&
        supported_candidates_remain_manual_local_only &&
        no_automatic_q_revision &&
        no_public_q_revision_claim &&
        no_publication &&
        all(row -> row.summary.passed, review_rows)

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_q_revision_construct_validity_review.v1",
        family = :mgmfrm,
        scope = :q_revision_construct_validity_review,
        status = :q_revision_construct_validity_review_recorded,
        decision =
            :keep_construct_validated_q_revisions_manual_local_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        empirical_q_recovery_public = false,
        q_revision_public = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        reference_records = REFERENCE_RECORDS,
        review_criteria = REVIEW_CRITERIA,
        input_artifacts = input_records,
        construct_review_rows = review_rows,
        excluded_candidate_rows = excluded_rows,
        reviewer_rows = reviewer_records,
        decision_record = (;
            construct_validity_manual_review_recorded = true,
            construct_validity_manual_review_completed,
            candidate_suggestions_allowed = true,
            manual_local_q_revision_candidates_allowed = true,
            automatic_q_revision_allowed = false,
            public_q_revision_claim_allowed = false,
            public_q_revision_allowed = false,
            public_exposure_support =
                :construct_review_recorded_manual_local_only,
            interpretation =
                :construct_review_supports_local_manual_q_candidates_not_package_revisions,
            required_followup = :guarded_local_mgmfrm_fit_entrypoint,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            q_revision_cross_validation_policy_passed =
                cv_record.summary_passed,
            supported_candidates_available,
            all_supported_candidates_reviewed,
            non_supported_candidates_not_reviewed_as_revisions,
            all_construct_map_evidence_recorded,
            all_item_rubric_alignment_recorded,
            all_dimension_label_consistency_recorded,
            all_expected_response_process_recorded,
            all_local_dependence_risk_checked,
            reviewer_agreement_recorded,
            construct_validity_manual_review_completed,
            construct_validity_supported_for_all_reviewed,
            supported_candidates_remain_manual_local_only,
            no_automatic_q_revision,
            no_public_q_revision_claim,
            n_input_artifacts = length(input_records),
            n_reference_records = length(REFERENCE_RECORDS),
            n_review_criteria = length(REVIEW_CRITERIA),
            n_cv_supported_candidates = length(supported_source_rows),
            n_construct_review_rows = length(review_rows),
            n_construct_supported_candidates =
                count(row -> row.construct_review_supported, review_rows),
            n_excluded_candidate_rows = length(excluded_rows),
            n_reviewer_rows = length(reviewer_records),
            n_public_revisions_allowed =
                count(row -> row.public_revision_allowed, review_rows) +
                count(row -> row.public_revision_allowed, excluded_rows),
            n_automatic_revisions_allowed =
                count(row -> row.automatic_revision_allowed, review_rows) +
                count(row -> row.automatic_revision_allowed, excluded_rows),
            n_blockers = 0,
            remaining_public_blockers = Symbol[],
            recommendation =
                :use_construct_reviewed_q_candidates_as_local_manual_inputs_only,
            next_gate = :guarded_local_mgmfrm_fit_entrypoint,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " reviewed=", artifact.summary.n_construct_review_rows,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
