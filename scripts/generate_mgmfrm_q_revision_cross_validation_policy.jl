#!/usr/bin/env julia

using JSON3
using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_q_revision_cross_validation_policy.json")

include(joinpath(@__DIR__, "local_json.jl"))

const INPUT_ARTIFACTS = [
    (name = :q_candidate_real_fit_diagnostic_linkage,
        path =
            "test/fixtures/mgmfrm_q_candidate_real_fit_diagnostic_linkage.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_candidate_real_fit_diagnostic_linkage.v1",
        pass_policy = :summary_passed),
]

const Q_MATRIX_REFERENCE_RECORDS = [
    (;
        key = :de_la_torre_chiu_2016_gdi,
        source = :doi,
        title = "A general method of empirical Q-matrix validation",
        author = "De La Torre, Jimmy; Chiu, Chia-Yi",
        date = "06/2016",
        journal = "Psychometrika",
        doi = "10.1007/s11336-015-9467-8",
        relevance =
            :empirical_q_candidates_are_supplemental_validation_evidence_not_replacements_for_expert_review,
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
            :q_revision_candidates_should_be_screened_iteratively_and_not_promoted_from_single_pass_noise,
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
            :mirt_q_matrices_encode_confirmatory_loading_masks_with_model_selection_diagnostics,
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
            :dynamic_cutoffs_and_domain_review_are_required_before_q_modifications_are_accepted,
    ),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_q_revision_cross_validation_policy_v1",
    review_kind = :local_q_revision_cross_validation_policy,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope =
        :fixed_q_candidate_revision_cross_validation_policy_for_mgmfrm,
    cross_validation = (;
        unit = :observation_fold,
        folds = 3,
        score = :deterministic_holdout_elpd_surrogate,
        comparison = :candidate_minus_declared,
    ),
    thresholds = (;
        require_q_candidate_real_fit_diagnostic_linkage_passed = true,
        require_public_reference_records_recorded = true,
        require_all_policy_scenarios_checked = true,
        require_all_candidate_q_validations_checked = true,
        require_all_cv_eligible_candidates_have_fold_rows = true,
        require_minimum_mean_holdout_elpd_delta = 0.20,
        require_minimum_fold_win_rate = 2 / 3,
        require_maximum_loading_complexity_increase = 1,
        require_false_positive_candidate_rejected = true,
        require_invalid_candidates_excluded_from_cv = true,
        require_supported_candidates_remain_manual_review_only = true,
        require_construct_validity_manual_review_before_public_revision = true,
        require_no_automatic_q_revision = true,
        require_no_public_q_revision_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const MIN_MEAN_HOLDOUT_ELPD_DELTA = 0.20
const MIN_FOLD_WIN_RATE = 2 / 3
const MAX_COMPLEXITY_INCREASE = 1

const POLICY_SCENARIOS = [
    (;
        scenario = :retained_declared_q_cv_no_change,
        source_linkage_scenario = :retained_declared_q_fit_linked,
        expected_decision = :retain_declared_q,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
        ],
        declared_q = Bool[
            1 0
            0 1
        ],
        candidate_q = Bool[
            1 0
            0 1
        ],
        candidate_fold_adjustments = [0.0, 0.0, 0.0],
        construct_review_available = false,
    ),
    (;
        scenario = :missing_loading_candidate_cv_supported_manual_gate,
        source_linkage_scenario = :missing_loading_candidate_fit_linked,
        expected_decision = :manual_review_candidate_supported_by_cv,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
            1 1
        ],
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
        candidate_fold_adjustments = [0.02, -0.01, 0.03],
        construct_review_available = false,
    ),
    (;
        scenario = :extra_loading_candidate_cv_supported_manual_gate,
        source_linkage_scenario = :extra_loading_candidate_fit_linked,
        expected_decision = :manual_review_candidate_supported_by_cv,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
            1 0
        ],
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
        candidate_fold_adjustments = [0.01, 0.00, 0.02],
        construct_review_available = false,
    ),
    (;
        scenario = :false_positive_candidate_rejected_by_cv,
        source_linkage_scenario = :false_positive_candidate_fit_diagnostic_only,
        expected_decision = :reject_candidate_not_cross_validated,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
            1 0
        ],
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
        candidate_fold_adjustments = [-0.02, 0.01, -0.01],
        construct_review_available = false,
    ),
    (;
        scenario = :invalid_duplicate_dimension_candidate_excluded_from_cv,
        source_linkage_scenario =
            :invalid_duplicate_dimension_candidate_blocked_before_fit,
        expected_decision = :exclude_invalid_candidate_before_cv,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
        ],
        declared_q = Bool[
            1 0
            0 1
        ],
        candidate_q = Bool[
            1 1
            1 1
        ],
        candidate_fold_adjustments = [0.0, 0.0, 0.0],
        construct_review_available = false,
    ),
]

function usage()
    return """
    Generate the local MGMFRM Q-revision cross-validation policy artifact.

    The artifact records a local policy for screening candidate Q-matrix
    revisions with deterministic fold-level holdout evidence. It does not
    automatically revise Q matrices, publish revision claims, or replace
    construct-validity review.

    Usage:
      julia --project=. scripts/generate_mgmfrm_q_revision_cross_validation_policy.jl [--output PATH]
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

function linked_table(n_items::Int)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for person in 1:4, rater_index in 1:3, item_index in 1:n_items
        push!(examinee, "E$person")
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, mod(person + rater_index + 2 * item_index, 3))
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

loading_complexity(q_matrix::AbstractMatrix{Bool}) = count(identity, q_matrix)

function q_error_counts(q_matrix::AbstractMatrix{Bool},
        true_q::AbstractMatrix{Bool})
    missing_loadings = 0
    extra_loadings = 0
    for row in axes(q_matrix, 1), col in axes(q_matrix, 2)
        if Bool(true_q[row, col]) && !Bool(q_matrix[row, col])
            missing_loadings += 1
        elseif !Bool(true_q[row, col]) && Bool(q_matrix[row, col])
            extra_loadings += 1
        end
    end
    return (; missing_loadings, extra_loadings)
end

function q_loss(q_matrix::AbstractMatrix{Bool}, true_q::AbstractMatrix{Bool})
    errors = q_error_counts(q_matrix, true_q)
    return 0.85 * errors.missing_loadings +
        0.40 * errors.extra_loadings +
        0.02 * loading_complexity(q_matrix)
end

function holdout_score(q_matrix::AbstractMatrix{Bool},
        true_q::AbstractMatrix{Bool},
        fold::Int,
        scenario_index::Int,
        adjustment::Float64)
    base = -8.0 - 0.17 * fold - 0.05 * scenario_index
    return base - q_loss(q_matrix, true_q) + adjustment
end

function cv_fold_rows(scenario, scenario_index::Int)
    rows = NamedTuple[]
    for fold in 1:PROTOCOL.cross_validation.folds
        declared_score = holdout_score(
            scenario.declared_q,
            scenario.true_q,
            fold,
            scenario_index,
            0.0,
        )
        candidate_score = holdout_score(
            scenario.candidate_q,
            scenario.true_q,
            fold,
            scenario_index,
            Float64(scenario.candidate_fold_adjustments[fold]),
        )
        delta = candidate_score - declared_score
        push!(rows, (;
            fold,
            n_holdout_observations = 8 + fold,
            declared_holdout_elpd = declared_score,
            candidate_holdout_elpd = candidate_score,
            delta_candidate_minus_declared = delta,
            candidate_wins = delta > 0,
        ))
    end
    return rows
end

function source_row_by_name(linkage_artifact, scenario::Symbol)
    for row in linkage_artifact[:scenario_rows]
        String(row[:scenario]) == String(scenario) && return row
    end
    error("source linkage scenario not found: $scenario")
end

function policy_decision(cv_attempted::Bool,
        candidate_validation_passed::Bool,
        mean_delta::Float64,
        fold_win_rate::Float64,
        complexity_delta::Int,
        construct_review_available::Bool,
        same_q::Bool)
    !candidate_validation_passed && return :exclude_invalid_candidate_before_cv
    same_q && return :retain_declared_q
    !cv_attempted && return :exclude_invalid_candidate_before_cv
    cv_supported =
        mean_delta >= MIN_MEAN_HOLDOUT_ELPD_DELTA &&
        fold_win_rate >= MIN_FOLD_WIN_RATE &&
        complexity_delta <= MAX_COMPLEXITY_INCREASE
    cv_supported && construct_review_available &&
        return :public_revision_candidate_supported_by_cv_and_review
    cv_supported && return :manual_review_candidate_supported_by_cv
    return :reject_candidate_not_cross_validated
end

function scenario_record(scenario, scenario_index::Int, linkage_artifact)
    data = facet_data(linked_table(size(scenario.declared_q, 1)))
    candidate_validation = validation_record(data, scenario, scenario.candidate_q)
    source = source_row_by_name(
        linkage_artifact, scenario.source_linkage_scenario)
    source_candidate_fit = source[:candidate_fit]
    source_summary = source[:summary]
    source_candidate_fit_succeeded =
        Bool(source_candidate_fit[:fit_succeeded])
    source_invalid_blocked =
        Bool(source_summary[:invalid_candidate_blocked_before_fit])
    source_linkage_passed = Bool(source_summary[:passed])
    same_q = scenario.declared_q == scenario.candidate_q
    cv_attempted =
        Bool(candidate_validation.passed) &&
        (source_candidate_fit_succeeded || same_q)
    folds = cv_attempted ? cv_fold_rows(scenario, scenario_index) :
        NamedTuple[]
    mean_delta = isempty(folds) ? 0.0 :
        sum(row.delta_candidate_minus_declared for row in folds) /
        length(folds)
    n_winning_folds = count(row -> row.candidate_wins, folds)
    fold_win_rate = isempty(folds) ? 0.0 : n_winning_folds / length(folds)
    declared_complexity = loading_complexity(scenario.declared_q)
    candidate_complexity = loading_complexity(scenario.candidate_q)
    complexity_delta = candidate_complexity - declared_complexity
    decision = policy_decision(
        cv_attempted,
        Bool(candidate_validation.passed),
        mean_delta,
        fold_win_rate,
        complexity_delta,
        Bool(scenario.construct_review_available),
        same_q,
    )
    cv_supported =
        decision in (
            :manual_review_candidate_supported_by_cv,
            :public_revision_candidate_supported_by_cv_and_review,
        )
    public_revision_allowed =
        decision === :public_revision_candidate_supported_by_cv_and_review
    automatic_revision_allowed = false
    false_positive_rejected =
        scenario.scenario === :false_positive_candidate_rejected_by_cv &&
        decision === :reject_candidate_not_cross_validated
    invalid_candidate_excluded =
        !candidate_validation.passed &&
        !cv_attempted &&
        source_invalid_blocked &&
        decision === :exclude_invalid_candidate_before_cv
    supported_manual_only =
        cv_supported &&
        !public_revision_allowed &&
        !Bool(scenario.construct_review_available)
    decision_matches = decision === scenario.expected_decision
    return (;
        scenario = scenario.scenario,
        source_linkage_scenario = scenario.source_linkage_scenario,
        source_linkage = (;
            passed = source_linkage_passed,
            candidate_fit_succeeded = source_candidate_fit_succeeded,
            invalid_candidate_blocked_before_fit = source_invalid_blocked,
        ),
        dimensions = scenario.dimensions,
        true_q = matrix_rows(scenario.true_q),
        declared_q = matrix_rows(scenario.declared_q),
        candidate_q = matrix_rows(scenario.candidate_q),
        candidate_q_validation = candidate_validation,
        cv_attempted,
        cv_fold_rows = folds,
        declared_complexity,
        candidate_complexity,
        complexity_delta,
        mean_delta_candidate_minus_declared = mean_delta,
        n_winning_folds,
        fold_win_rate,
        cv_supported,
        construct_review_available =
            Bool(scenario.construct_review_available),
        construct_review_required = cv_supported,
        decision,
        public_revision_allowed,
        automatic_revision_allowed,
        public_claim_allowed = false,
        summary = (;
            passed = source_linkage_passed &&
                decision_matches &&
                !automatic_revision_allowed &&
                !public_revision_allowed &&
                (!cv_supported || supported_manual_only) &&
                (scenario.scenario !==
                    :false_positive_candidate_rejected_by_cv ||
                 false_positive_rejected) &&
                (scenario.scenario !==
                    :invalid_duplicate_dimension_candidate_excluded_from_cv ||
                 invalid_candidate_excluded),
            decision_matches,
            candidate_validation_checked = true,
            source_linkage_passed,
            cv_rows_recorded = cv_attempted ?
                length(folds) == PROTOCOL.cross_validation.folds : true,
            threshold_mean_delta_met =
                mean_delta >= MIN_MEAN_HOLDOUT_ELPD_DELTA,
            threshold_fold_win_rate_met =
                fold_win_rate >= MIN_FOLD_WIN_RATE,
            threshold_complexity_met =
                complexity_delta <= MAX_COMPLEXITY_INCREASE,
            false_positive_rejected,
            invalid_candidate_excluded_from_cv = invalid_candidate_excluded,
            supported_manual_only,
        ),
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_q_revision_cross_validation_policy.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function policy_rows()
    return [
        (policy = :kfold_holdout_delta,
            status = :recorded,
            threshold = MIN_MEAN_HOLDOUT_ELPD_DELTA,
            public_revision_allowed = false,
            rationale = :candidate_q_must_improve_heldout_score),
        (policy = :fold_win_rate,
            status = :recorded,
            threshold = MIN_FOLD_WIN_RATE,
            public_revision_allowed = false,
            rationale = :candidate_q_must_be_stable_across_folds),
        (policy = :loading_complexity_guard,
            status = :recorded,
            threshold = MAX_COMPLEXITY_INCREASE,
            public_revision_allowed = false,
            rationale = :candidate_q_must_not_add_unbounded_complexity),
        (policy = :construct_validity_manual_review,
            status = :required_before_public_revision,
            threshold = missing,
            public_revision_allowed = false,
            rationale = :statistical_q_screening_does_not_replace_domain_review),
    ]
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    linkage =
        record_by_name(input_records, :q_candidate_real_fit_diagnostic_linkage)
    linkage_artifact = parsed_input_artifact(only(INPUT_ARTIFACTS))
    scenarios = [scenario_record(scenario, index, linkage_artifact)
        for (index, scenario) in enumerate(POLICY_SCENARIOS)]
    no_publication = no_publication_commands()

    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    public_reference_records_recorded =
        length(Q_MATRIX_REFERENCE_RECORDS) == 4 &&
        all(row -> hasproperty(row, :doi), Q_MATRIX_REFERENCE_RECORDS)
    all_policy_scenarios_checked =
        length(scenarios) == length(POLICY_SCENARIOS)
    all_candidate_q_validations_checked =
        all(row -> row.summary.candidate_validation_checked, scenarios)
    all_cv_eligible_candidates_have_fold_rows =
        all(row -> !row.cv_attempted ||
            length(row.cv_fold_rows) == PROTOCOL.cross_validation.folds,
            scenarios)
    false_positive_candidate_rejected =
        any(row -> row.summary.false_positive_rejected, scenarios)
    invalid_candidates_excluded_from_cv =
        any(row -> row.summary.invalid_candidate_excluded_from_cv, scenarios)
    supported_candidates_remain_manual_review_only =
        all(row -> !row.cv_supported || row.summary.supported_manual_only,
            scenarios)
    no_automatic_q_revision =
        all(row -> !row.automatic_revision_allowed, scenarios)
    no_public_q_revision_claim =
        all(row -> !row.public_revision_allowed &&
            !row.public_claim_allowed, scenarios)
    all_scenarios_passed = all(row -> row.summary.passed, scenarios)
    construct_validity_manual_review_required =
        any(row -> row.construct_review_required, scenarios)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        linkage.summary.no_automatic_q_revision &&
        linkage.summary.no_public_q_revision_claim &&
        linkage.summary.next_gate ==
            "cross_validated_q_revision_policy_for_q_candidates" &&
        public_reference_records_recorded &&
        all_policy_scenarios_checked &&
        all_candidate_q_validations_checked &&
        all_cv_eligible_candidates_have_fold_rows &&
        false_positive_candidate_rejected &&
        invalid_candidates_excluded_from_cv &&
        supported_candidates_remain_manual_review_only &&
        construct_validity_manual_review_required &&
        no_automatic_q_revision &&
        no_public_q_revision_claim &&
        no_publication &&
        all_scenarios_passed

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_q_revision_cross_validation_policy.v1",
        family = :mgmfrm,
        scope = :q_revision_cross_validation_policy,
        status = :q_revision_cross_validation_policy_recorded,
        decision = :keep_cross_validated_q_revision_manual_review_only,
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
        reference_records = Q_MATRIX_REFERENCE_RECORDS,
        input_artifacts = input_records,
        scenario_rows = scenarios,
        policy_rows = policy_rows(),
        decision_record = (;
            cross_validated_q_revision_policy_recorded = true,
            candidate_suggestions_allowed = true,
            manual_review_candidates_allowed = true,
            automatic_q_revision_allowed = false,
            public_q_revision_claim_allowed = false,
            public_q_revision_allowed = false,
            construct_validity_manual_review_required = true,
            public_exposure_support =
                :cross_validated_q_revision_policy_recorded_manual_only,
            interpretation =
                :cv_supported_q_candidates_are_manual_review_inputs_not_public_revisions,
            required_followup =
                :construct_validity_manual_review_for_q_revision_candidates,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            q_candidate_real_fit_diagnostic_linkage_passed =
                linkage.summary_passed,
            public_reference_records_recorded,
            all_policy_scenarios_checked,
            all_candidate_q_validations_checked,
            all_cv_eligible_candidates_have_fold_rows,
            false_positive_candidate_rejected,
            invalid_candidates_excluded_from_cv,
            supported_candidates_remain_manual_review_only,
            construct_validity_manual_review_required,
            no_automatic_q_revision,
            no_public_q_revision_claim,
            n_input_artifacts = length(input_records),
            n_reference_records = length(Q_MATRIX_REFERENCE_RECORDS),
            n_scenarios = length(scenarios),
            n_passed_scenarios = count(row -> row.summary.passed, scenarios),
            n_cv_attempted_scenarios = count(row -> row.cv_attempted, scenarios),
            n_cv_fold_rows =
                sum(length(row.cv_fold_rows) for row in scenarios),
            n_cv_supported_candidates =
                count(row -> row.cv_supported, scenarios),
            n_supported_manual_review_candidates =
                count(row -> row.summary.supported_manual_only, scenarios),
            n_false_positive_candidates_rejected =
                count(row -> row.summary.false_positive_rejected, scenarios),
            n_invalid_candidates_excluded_from_cv =
                count(row -> row.summary.invalid_candidate_excluded_from_cv,
                    scenarios),
            n_public_revisions_allowed =
                count(row -> row.public_revision_allowed, scenarios),
            n_automatic_revisions_allowed =
                count(row -> row.automatic_revision_allowed, scenarios),
            remaining_public_blockers = [
                :construct_validity_manual_review_missing,
            ],
            recommendation =
                :use_cross_validated_q_policy_for_manual_review_candidates_only,
            next_gate =
                :construct_validity_manual_review_for_q_revision_candidates,
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
        " cv_supported=", artifact.summary.n_cv_supported_candidates,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
