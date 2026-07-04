#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_empirical_q_matrix_recovery_simulation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

module FullArchiveJSON
include(joinpath(@__DIR__, "generate_gmfrm_full_paper_reproduction_archive.jl"))
end

const JSON = FullArchiveJSON

const INPUT_ARTIFACTS = [
    (name = :empirical_q_matrix_recovery_policy,
        path = "test/fixtures/mgmfrm_empirical_q_matrix_recovery_policy.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_policy.v1",
        pass_policy = :summary_passed),
]

const Q_MATRIX_REFERENCE_RECORDS = [
    (;
        key = :chiu_2013_q_matrix_refinement,
        source = :doi,
        title = "Statistical refinement of the q-matrix in cognitive diagnosis",
        item_type = :journalArticle,
        author = "Chiu, Chia-Yi",
        date = "11/2013",
        journal = "Applied Psychological Measurement",
        volume = "37",
        issue = "8",
        pages = "598-618",
        doi = "10.1177/0146621613488436",
        url = "https://journals.sagepub.com/doi/10.1177/0146621613488436",
        relevance =
            :expert_q_matrices_can_be_fallible_and_empirical_refinement_needs_error_control,
    ),
    (;
        key = :madison_bradshaw_2015_q_design,
        source = :doi,
        title =
            "The effects of Q-matrix design on classification accuracy in the log-linear cognitive diagnosis model",
        item_type = :journalArticle,
        author = "Madison, Matthew J.; Bradshaw, Laine P.",
        date = "06/2015",
        journal = "Educational and Psychological Measurement",
        volume = "75",
        issue = "3",
        pages = "491-511",
        doi = "10.1177/0013164414539162",
        url = "https://journals.sagepub.com/doi/10.1177/0013164414539162",
        relevance =
            :isolated_attribute_information_and_anchor_items_are_part_of_q_recovery_design,
    ),
    (;
        key = :de_la_torre_chiu_2016_gdi,
        source = :doi,
        title = "A general method of empirical Q-matrix validation",
        item_type = :journalArticle,
        author = "De La Torre, Jimmy; Chiu, Chia-Yi",
        date = "06/2016",
        journal = "Psychometrika",
        volume = "81",
        issue = "2",
        pages = "253-273",
        doi = "10.1007/s11336-015-9467-8",
        url =
            "https://www.cambridge.org/core/product/identifier/S0033312300020019/type/journal_article",
        relevance =
            :empirical_q_validation_should_identify_candidate_misspecified_cells,
    ),
    (;
        key = :chen_2017_residual_q_validation,
        source = :doi,
        title = "A residual-based approach to validate q-matrix specifications",
        item_type = :journalArticle,
        author = "Chen, Jinsong",
        date = "06/2017",
        journal = "Applied Psychological Measurement",
        volume = "41",
        issue = "4",
        pages = "277-293",
        doi = "10.1177/0146621616686021",
        url = "http://journals.sagepub.com/doi/10.1177/0146621616686021",
        relevance =
            :test_level_attribute_level_and_item_level_diagnostics_should_be_separated,
    ),
    (;
        key = :terzi_de_la_torre_2018_iterative,
        source = :doi,
        title = "An iterative method for empirically-based Q-matrix validation",
        item_type = :journalArticle,
        author = "Terzi, Ragip; De La Torre, Jimmy",
        date = "2018-05-19",
        journal = "International Journal of Assessment Tools in Education",
        volume = "5",
        issue = "2",
        pages = "248-262",
        doi = "10.21449/ijate.407193",
        url = "http://dergipark.org.tr/en/doi/10.21449/ijate.407193",
        relevance =
            :candidate_q_revisions_should_be_iterative_and_item_level,
    ),
    (;
        key = :da_silva_2019_mirt_q_matrix,
        source = :doi,
        title =
            "Incorporating the Q-Matrix Into Multidimensional Item Response Theory Models",
        item_type = :journalArticle,
        author =
            "Da Silva, Marcelo A.; Liu, Ren; Huggins-Manley, Anne C.; Bazan, Jorge L.",
        date = "08/2019",
        journal = "Educational and Psychological Measurement",
        volume = "79",
        issue = "4",
        pages = "665-687",
        doi = "10.1177/0013164418814898",
        url = "https://journals.sagepub.com/doi/10.1177/0013164418814898",
        relevance =
            :mirt_q_matrices_are_confirmatory_loading_masks_not_unrestricted_dimension_search,
    ),
    (;
        key = :najera_2020_iterative_dynamic_gdi,
        source = :doi,
        title =
            "Improving robustness in Q-matrix validation using an iterative and dynamic procedure",
        item_type = :journalArticle,
        author =
            "Najera, Pablo; Sorrel, Miguel A.; De La Torre, Jimmy; Abad, Francisco Jose",
        date = "09/2020",
        journal = "Applied Psychological Measurement",
        volume = "44",
        issue = "6",
        pages = "431-446",
        doi = "10.1177/0146621620909904",
        url = "https://journals.sagepub.com/doi/10.1177/0146621620909904",
        relevance =
            :dynamic_cutoffs_and_high_misspecification_uncertainty_block_automatic_public_q_revision,
    ),
]

const SCITE_Q_MATRIX_SNAPSHOT = [
    (key = :de_la_torre_chiu_2016_gdi, retrieved_on = "2026-07-04",
        supporting = 2, contrasting = 1, mentioning = 222,
        total_citing_publications = 245),
    (key = :terzi_de_la_torre_2018_iterative, retrieved_on = "2026-07-04",
        supporting = 0, contrasting = 0, mentioning = 10,
        total_citing_publications = 11),
    (key = :najera_2020_iterative_dynamic_gdi, retrieved_on = "2026-07-04",
        supporting = 1, contrasting = 0, mentioning = 15,
        total_citing_publications = 25),
    (key = :da_silva_2019_mirt_q_matrix, retrieved_on = "2026-07-04",
        supporting = 0, contrasting = 0, mentioning = 6,
        total_citing_publications = 18),
    (key = :chiu_2013_q_matrix_refinement, retrieved_on = "2026-07-04",
        supporting = 4, contrasting = 0, mentioning = 139,
        total_citing_publications = 132),
    (key = :chen_2017_residual_q_validation, retrieved_on = "2026-07-04",
        supporting = 0, contrasting = 0, mentioning = 28,
        total_citing_publications = 39),
    (key = :madison_bradshaw_2015_q_design, retrieved_on = "2026-07-04",
        supporting = 5, contrasting = 0, mentioning = 52,
        total_citing_publications = 59),
]

const RESEARCH_BASIS = [
    (;
        key = :chiu_2013_q_matrix_refinement,
        basis = :nonparametric_residual_refinement_simulation,
        simulation_implication =
            :include_false_add_and_false_drop_cases_with_known_truth,
    ),
    (;
        key = :madison_bradshaw_2015_q_design,
        basis = :q_design_affects_classification_accuracy,
        simulation_implication =
            :include_sparse_anchor_and_isolated_attribute_design_cases,
    ),
    (;
        key = :de_la_torre_chiu_2016_gdi,
        basis = :general_empirical_q_validation,
        simulation_implication =
            :include_candidate_cell_level_misspecification_detection,
    ),
    (;
        key = :chen_2017_residual_q_validation,
        basis = :residual_based_item_and_attribute_diagnostics,
        simulation_implication =
            :separate_item_level_candidates_from_attribute_level_design_risks,
    ),
    (;
        key = :terzi_de_la_torre_2018_iterative,
        basis = :iterative_empirical_q_validation,
        simulation_implication =
            :include_single_item_iterative_candidate_recovery,
    ),
    (;
        key = :da_silva_2019_mirt_q_matrix,
        basis = :q_matrix_as_mirt_loading_mask,
        simulation_implication =
            :treat_candidate_q_changes_as_confirmatory_mask_changes,
    ),
    (;
        key = :najera_2020_iterative_dynamic_gdi,
        basis = :iterative_dynamic_cutoff_robustness,
        simulation_implication =
            :include_high_noise_cases_that_must_not_be_publicly_promoted,
    ),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_empirical_q_matrix_recovery_simulation_grid_v1",
    review_kind = :local_empirical_q_matrix_recovery_simulation_grid,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope = :fixed_q_confirmatory_mgmfrm_candidate_recovery_simulation,
    thresholds = (;
        require_empirical_q_matrix_recovery_policy_passed = true,
        require_q_matrix_reference_records_recorded = true,
        require_research_basis_recorded = true,
        require_all_scenarios_passed = true,
        require_all_candidate_validations_checked = true,
        require_candidate_exactness_recorded = true,
        require_false_public_promotion_rate_zero = true,
        require_no_automatic_q_revision = true,
        require_no_public_recovery_claim = true,
        require_no_publication_or_registration_action = true,
    ),
)

const ADD_THRESHOLD = 0.75
const DROP_THRESHOLD = 0.25
const AMBIGUOUS_LOW = 0.45
const AMBIGUOUS_HIGH = 0.55

const SCENARIOS = [
    (;
        scenario = :well_separated_true_q_retained,
        literature_focus = :mirt_loading_mask_confirmatory_retention,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
        ],
        declared_q = Bool[
            1 0
            0 1
        ],
        empirical_signal = [
            0.92 0.08
            0.10 0.90
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :balanced,
        expected_action = :retain_declared_q,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :missing_loading_recovered_as_candidate,
        literature_focus = :cell_level_missing_loading_detection,
        data_kind = :connected_full_crossed,
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
        empirical_signal = [
            0.91 0.06
            0.07 0.93
            0.86 0.83
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :balanced,
        expected_action = :flag_missing_loading_candidate,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :extra_loading_removed_as_candidate,
        literature_focus = :cell_level_extra_loading_detection,
        data_kind = :connected_full_crossed,
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
        empirical_signal = [
            0.91 0.06
            0.07 0.93
            0.88 0.11
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :balanced,
        expected_action = :flag_extra_loading_candidate,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :ambiguous_cross_loading_deferred,
        literature_focus = :dynamic_cutoff_uncertainty,
        data_kind = :connected_full_crossed,
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
        empirical_signal = [
            0.91 0.06
            0.07 0.93
            0.79 0.51
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :balanced,
        expected_action = :defer_ambiguous_loading_evidence,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :high_noise_false_add_not_promoted,
        literature_focus = :robustness_under_high_misspecification_uncertainty,
        data_kind = :connected_full_crossed,
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
        empirical_signal = [
            0.90 0.08
            0.09 0.91
            0.84 0.82
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :noisy_high_false_positive,
        expected_action = :flag_noisy_candidate_manual_review,
        expected_candidate_exact = false,
        expected_validation_passed = true,
    ),
    (;
        scenario = :low_signal_false_drop_not_promoted,
        literature_focus = :residual_signal_false_negative_guardrail,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
            1 1
        ],
        declared_q = Bool[
            1 0
            0 1
            1 1
        ],
        empirical_signal = [
            0.91 0.07
            0.06 0.92
            0.85 0.18
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :noisy_high_false_negative,
        expected_action = :flag_noisy_candidate_manual_review,
        expected_candidate_exact = false,
        expected_validation_passed = true,
    ),
    (;
        scenario = :duplicate_dimension_false_add_blocked,
        literature_focus = :attribute_level_design_risk,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        true_q = Bool[
            1 0
            0 1
        ],
        declared_q = Bool[
            1 0
            0 1
        ],
        empirical_signal = [
            0.91 0.88
            0.86 0.93
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :duplicated_dimension_noise,
        expected_action = :block_invalid_candidate_revision,
        expected_candidate_exact = false,
        expected_validation_passed = false,
    ),
    (;
        scenario = :weak_dimension_design_deferred,
        literature_focus = :q_design_anchor_information,
        data_kind = :dimension_disconnected,
        dimensions = 2,
        true_q = Bool[
            1 0
            1 0
            0 1
        ],
        declared_q = Bool[
            1 0
            1 0
            0 1
        ],
        empirical_signal = [
            0.92 0.06
            0.90 0.08
            0.09 0.91
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :dimension_facet_disconnected,
        expected_action = :defer_weak_design_empirical_recovery,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :iterative_single_item_missing_loading_candidate,
        literature_focus = :iterative_item_level_candidate_recovery,
        data_kind = :connected_full_crossed,
        dimensions = 3,
        true_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 1 0
        ],
        declared_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 0 0
        ],
        empirical_signal = [
            0.92 0.08 0.07
            0.06 0.91 0.09
            0.07 0.10 0.93
            0.86 0.81 0.12
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :balanced_iterative,
        expected_action = :flag_missing_loading_candidate,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :rater_consistency_noise_false_positive_manual_only,
        literature_focus = :manual_construct_review_required,
        data_kind = :connected_full_crossed,
        dimensions = 3,
        true_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 0 0
        ],
        declared_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 0 0
        ],
        empirical_signal = [
            0.92 0.08 0.07
            0.06 0.91 0.09
            0.07 0.10 0.93
            0.85 0.80 0.11
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :single_rater_pattern_false_positive,
        expected_action = :flag_noisy_candidate_manual_review,
        expected_candidate_exact = false,
        expected_validation_passed = true,
    ),
    (;
        scenario = :three_dimension_anchor_recovery_retained,
        literature_focus = :isolated_attribute_anchor_design,
        data_kind = :connected_full_crossed,
        dimensions = 3,
        true_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 1 0
            0 1 1
        ],
        declared_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 1 0
            0 1 1
        ],
        empirical_signal = [
            0.92 0.08 0.05
            0.06 0.91 0.07
            0.05 0.08 0.92
            0.83 0.80 0.12
            0.10 0.82 0.84
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :balanced_with_anchor_items,
        expected_action = :retain_declared_q,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
    (;
        scenario = :sparse_isolated_attribute_design_retained,
        literature_focus = :sparse_anchor_q_design,
        data_kind = :connected_full_crossed,
        dimensions = 3,
        true_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 1 1
        ],
        declared_q = Bool[
            1 0 0
            0 1 0
            0 0 1
            1 1 1
        ],
        empirical_signal = [
            0.93 0.08 0.06
            0.07 0.92 0.09
            0.06 0.09 0.91
            0.78 0.79 0.80
        ],
        cross_loading_policy = :confirmatory_fixed,
        rater_consistency_profile = :sparse_anchor_supported,
        expected_action = :retain_declared_q,
        expected_candidate_exact = true,
        expected_validation_passed = true,
    ),
]

function usage()
    return """
    Generate the local MGMFRM empirical Q-matrix recovery simulation grid.

    The artifact records deterministic candidate-Q recovery scenarios anchored
    in DOI-indexed Q-matrix validation literature. It is a local diagnostic grid: it
    validates candidate suggestions, estimates known-truth cell recovery, and
    explicitly blocks automatic or public Q-matrix revision claims.

    Usage:
      julia --project=. scripts/generate_mgmfrm_empirical_q_matrix_recovery_simulation_grid.jl [--output PATH]
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

function summary_bool(summary::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Bool = false)
    summary === nothing && return default
    value = JSON.json_optional_bool(summary, key)
    return value === missing ? default : Bool(value)
end

function json_optional_int(text::Union{Nothing,AbstractString},
        key::AbstractString,
        default::Int = 0)
    text === nothing && return default
    value = JSON.json_value_for_key(text, key)
    value === nothing && return default
    return parse(Int, value)
end

function summary_passed(summary::Union{Nothing,AbstractString}, policy::Symbol)
    policy === :schema_only && return true
    summary === nothing && return false
    policy === :summary_passed && return summary_bool(summary, "passed")
    policy === :summary_overall_passed &&
        return summary_bool(summary, "overall_passed")
    throw(ArgumentError("unknown pass policy: $policy"))
end

function artifact_summary(name::Symbol, summary::Union{Nothing,AbstractString})
    name === :empirical_q_matrix_recovery_policy && return (;
        passed = summary_bool(summary, "passed"),
        n_candidate_policy_scenarios =
            json_optional_int(summary, "n_candidate_policy_scenarios"),
        all_candidate_policy_scenarios_passed =
            summary_bool(summary, "all_candidate_policy_scenarios_passed"),
        no_public_automatic_q_revision =
            summary_bool(summary, "no_public_automatic_q_revision"),
        empirical_q_recovery_allowed =
            summary_bool(summary, "empirical_q_recovery_allowed"),
        next_gate = JSON.json_string(summary, "next_gate"),
    )
    return (; passed = summary_bool(summary, "passed"))
end

function artifact_record(spec)
    path = local_path(spec.path)
    exists = isfile(path)
    text = exists ? read(path, String) : ""
    schema = exists ? JSON.json_string(text, "schema") : missing
    schema_matches = exists && schema == spec.expected_schema
    summary_text = exists ? JSON.json_summary(text) : nothing
    parsed_summary = artifact_summary(spec.name, summary_text)
    passed = exists && schema_matches &&
        summary_passed(summary_text, spec.pass_policy)
    return (;
        artifact = spec.name,
        path = spec.path,
        exists,
        sha256 = exists ? file_sha256(path) : missing,
        expected_schema = spec.expected_schema,
        schema,
        schema_matches,
        pass_policy = spec.pass_policy,
        summary_passed = passed,
        summary = parsed_summary,
    )
end

function connected_full_crossed_table(n_items::Int)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for person in 1:5, rater_index in 1:4, item_index in 1:n_items
        push!(examinee, "E$person")
        push!(rater, "R$rater_index")
        push!(item, "I$item_index")
        push!(score, mod(length(score), 3))
    end
    return (; examinee, rater, item, score)
end

function dimension_disconnected_table()
    return (;
        examinee = ["E1", "E1", "E2", "E2", "E3", "E3"],
        rater = ["R1", "R2", "R3", "R4", "R1", "R4"],
        item = ["I1", "I1", "I2", "I2", "I3", "I3"],
        score = [0, 1, 0, 1, 0, 1],
    )
end

function table_for_scenario(scenario)
    scenario.data_kind === :dimension_disconnected &&
        return dimension_disconnected_table()
    return connected_full_crossed_table(size(scenario.declared_q, 1))
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

function compact_rows(validation)
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

function operation_rows(q_matrix::AbstractMatrix{Bool},
        signal::AbstractMatrix{<:Real})
    operations = NamedTuple[]
    ambiguous = NamedTuple[]
    for row in axes(q_matrix, 1), col in axes(q_matrix, 2)
        value = Float64(signal[row, col])
        if Bool(q_matrix[row, col]) && value < DROP_THRESHOLD
            push!(operations, (;
                operation = :drop_loading,
                item = row,
                dimension = col,
                signal = value,
            ))
        elseif !Bool(q_matrix[row, col]) && value > ADD_THRESHOLD
            push!(operations, (;
                operation = :add_loading,
                item = row,
                dimension = col,
                signal = value,
            ))
        elseif AMBIGUOUS_LOW <= value <= AMBIGUOUS_HIGH
            push!(ambiguous, (;
                operation = :ambiguous_loading_evidence,
                item = row,
                dimension = col,
                signal = value,
            ))
        end
    end
    return operations, ambiguous
end

function suggested_q_matrix(q_matrix::AbstractMatrix{Bool}, operations)
    suggested = copy(q_matrix)
    for operation in operations
        if operation.operation === :add_loading
            suggested[operation.item, operation.dimension] = true
        elseif operation.operation === :drop_loading
            suggested[operation.item, operation.dimension] = false
        end
    end
    return suggested
end

function severity_checks(validation, severity::Symbol)
    return sort(unique([Symbol(row.check) for row in validation.rows
        if row.severity === severity]); by = string)
end

function q_metrics(candidate::AbstractMatrix{Bool},
        truth::AbstractMatrix{Bool})
    size(candidate) == size(truth) ||
        throw(ArgumentError("candidate and truth Q matrices must match"))
    true_positive = 0
    false_positive = 0
    false_negative = 0
    true_negative = 0
    item_exact = 0
    for row in axes(candidate, 1)
        row_exact = true
        for col in axes(candidate, 2)
            predicted = Bool(candidate[row, col])
            actual = Bool(truth[row, col])
            if predicted && actual
                true_positive += 1
            elseif predicted && !actual
                false_positive += 1
                row_exact = false
            elseif !predicted && actual
                false_negative += 1
                row_exact = false
            else
                true_negative += 1
            end
        end
        item_exact += row_exact ? 1 : 0
    end
    precision_den = true_positive + false_positive
    recall_den = true_positive + false_negative
    precision = precision_den == 0 ? 1.0 : true_positive / precision_den
    recall = recall_den == 0 ? 1.0 : true_positive / recall_den
    f1 = precision + recall == 0 ? 0.0 :
        2 * precision * recall / (precision + recall)
    return (;
        true_positive,
        false_positive,
        false_negative,
        true_negative,
        precision = round(precision; digits = 6),
        recall = round(recall; digits = 6),
        f1 = round(f1; digits = 6),
        exact_match = candidate == truth,
        item_exact_rate =
            round(item_exact / size(candidate, 1); digits = 6),
    )
end

function operation_truth_counts(declared_q::AbstractMatrix{Bool},
        truth::AbstractMatrix{Bool},
        operations)
    true_operations = 0
    false_operations = 0
    for operation in operations
        declared = Bool(declared_q[operation.item, operation.dimension])
        actual = Bool(truth[operation.item, operation.dimension])
        operation_true =
            operation.operation === :add_loading ? (!declared && actual) :
            operation.operation === :drop_loading ? (declared && !actual) :
            false
        if operation_true
            true_operations += 1
        else
            false_operations += 1
        end
    end
    return (;
        n_true_operations = true_operations,
        n_false_operations = false_operations,
    )
end

function candidate_action(scenario, operations, ambiguous, validation,
        candidate_q)
    !isempty(ambiguous) && return :defer_ambiguous_loading_evidence
    scenario.data_kind === :dimension_disconnected &&
        return :defer_weak_design_empirical_recovery
    validation.passed || return :block_invalid_candidate_revision
    isempty(operations) && return :retain_declared_q
    if candidate_q == scenario.true_q
        all(operation -> operation.operation === :add_loading, operations) &&
            return :flag_missing_loading_candidate
        all(operation -> operation.operation === :drop_loading, operations) &&
            return :flag_extra_loading_candidate
        return :flag_mixed_loading_candidate
    end
    return :flag_noisy_candidate_manual_review
end

function scenario_record(scenario)
    operations, ambiguous =
        operation_rows(scenario.declared_q, scenario.empirical_signal)
    candidate_q = suggested_q_matrix(scenario.declared_q, operations)
    data = facet_data(table_for_scenario(scenario))
    validation = BayesianMGMFRM.q_matrix_validation(data;
        family = :mgmfrm,
        dimensions = scenario.dimensions,
        q_matrix = candidate_q,
        cross_loading_policy = scenario.cross_loading_policy,
    )
    action =
        candidate_action(scenario, operations, ambiguous, validation, candidate_q)
    declared_metrics = q_metrics(scenario.declared_q, scenario.true_q)
    candidate_metrics = q_metrics(candidate_q, scenario.true_q)
    operation_counts =
        operation_truth_counts(scenario.declared_q, scenario.true_q, operations)
    validation_passed_matches =
        validation.passed == scenario.expected_validation_passed
    action_matches = action === scenario.expected_action
    candidate_exact_matches =
        candidate_metrics.exact_match == scenario.expected_candidate_exact
    automatic_revision_allowed = false
    public_recovery_allowed = false
    candidate_validation_checked = true
    return (;
        scenario = scenario.scenario,
        literature_focus = scenario.literature_focus,
        data_kind = scenario.data_kind,
        dimensions = scenario.dimensions,
        cross_loading_policy = scenario.cross_loading_policy,
        rater_consistency_profile = scenario.rater_consistency_profile,
        true_q_matrix = matrix_rows(scenario.true_q),
        declared_q_matrix = matrix_rows(scenario.declared_q),
        empirical_signal = matrix_rows(scenario.empirical_signal),
        operations,
        ambiguous_operations = ambiguous,
        candidate_q_matrix = matrix_rows(candidate_q),
        declared_metrics,
        candidate_metrics,
        operation_truth_counts = operation_counts,
        candidate_improves_f1 =
            candidate_metrics.f1 > declared_metrics.f1 + 1.0e-8,
        candidate_exact_recovery = candidate_metrics.exact_match,
        false_candidate =
            !candidate_metrics.exact_match && !isempty(operations),
        validation_passed = validation.passed,
        validation_rows = compact_rows(validation),
        error_checks = severity_checks(validation, :error),
        warning_checks = severity_checks(validation, :warning),
        action,
        expected_action = scenario.expected_action,
        expected_candidate_exact = scenario.expected_candidate_exact,
        automatic_revision_allowed,
        public_recovery_allowed,
        public_claim_allowed = false,
        summary = (;
            passed = validation_passed_matches &&
                action_matches &&
                candidate_exact_matches &&
                candidate_validation_checked &&
                !automatic_revision_allowed &&
                !public_recovery_allowed,
            validation_passed_matches,
            action_matches,
            candidate_exact_matches,
            candidate_validation_checked,
            n_operations = length(operations),
            n_ambiguous_operations = length(ambiguous),
            n_true_operations = operation_counts.n_true_operations,
            n_false_operations = operation_counts.n_false_operations,
            candidate_validation_passed = validation.passed,
            invalid_candidate_blocked =
                !validation.passed &&
                action === :block_invalid_candidate_revision,
            deferred_candidate =
                action in (:defer_ambiguous_loading_evidence,
                    :defer_weak_design_empirical_recovery),
            false_candidate_manual_only =
                action === :flag_noisy_candidate_manual_review &&
                !public_recovery_allowed,
        ),
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_empirical_q_matrix_recovery_simulation_grid.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function decision_rows()
    return [
        (decision = :allow_local_candidate_q_diagnostics,
            status = :enabled,
            public_claim_allowed = false,
            rationale =
                :known_truth_simulation_grid_supports_candidate_screening_only),
        (decision = :block_automatic_q_rewrite,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :false_candidate_and_ambiguous_signal_cases_remain_possible),
        (decision = :require_candidate_q_validation,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :candidate_q_matrices_must_pass_fixed_q_mgmfrm_validation),
        (decision = :require_real_fit_diagnostic_linkage,
            status = :blocking,
            public_claim_allowed = false,
            rationale =
                :known_truth_recovery_does_not_establish_real_data_construct_revision),
    ]
end

function mean(values)
    isempty(values) && return 0.0
    return sum(values) / length(values)
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    policy =
        record_by_name(input_records, :empirical_q_matrix_recovery_policy)
    scenarios = [scenario_record(scenario) for scenario in SCENARIOS]
    no_publication = no_publication_commands()
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    all_scenarios_passed = all(scenario -> scenario.summary.passed, scenarios)
    all_candidate_validations_checked =
        all(scenario -> scenario.summary.candidate_validation_checked, scenarios)
    candidate_exactness_recorded =
        all(scenario -> hasproperty(scenario, :candidate_exact_recovery),
            scenarios)
    false_public_promotions =
        count(scenario -> scenario.false_candidate &&
            scenario.public_recovery_allowed, scenarios)
    false_public_promotion_rate =
        count(scenario -> scenario.false_candidate, scenarios) == 0 ? 0.0 :
        false_public_promotions /
        count(scenario -> scenario.false_candidate, scenarios)
    false_public_promotion_rate_zero = false_public_promotion_rate == 0.0
    no_automatic_q_revision =
        all(scenario -> !scenario.automatic_revision_allowed, scenarios)
    no_public_recovery_claim =
        all(scenario -> !scenario.public_recovery_allowed &&
            !scenario.public_claim_allowed, scenarios)
    reference_dois = Set(row.doi for row in Q_MATRIX_REFERENCE_RECORDS)
    q_matrix_reference_records_recorded =
        length(Q_MATRIX_REFERENCE_RECORDS) >= 7 &&
        all(doi -> doi in reference_dois,
            ["10.1007/s11336-015-9467-8",
                "10.1177/0013164418814898",
                "10.21449/ijate.407193",
                "10.1177/0146621620909904",
                "10.1177/0146621613488436",
                "10.1177/0146621616686021",
                "10.1177/0013164414539162"])
    research_basis_recorded =
        length(RESEARCH_BASIS) == length(Q_MATRIX_REFERENCE_RECORDS)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        Bool(policy.summary.all_candidate_policy_scenarios_passed) &&
        Bool(policy.summary.no_public_automatic_q_revision) &&
        !Bool(policy.summary.empirical_q_recovery_allowed) &&
        q_matrix_reference_records_recorded &&
        research_basis_recorded &&
        all_scenarios_passed &&
        all_candidate_validations_checked &&
        candidate_exactness_recorded &&
        false_public_promotion_rate_zero &&
        no_automatic_q_revision &&
        no_public_recovery_claim &&
        no_publication

    candidate_f1_values =
        [scenario.candidate_metrics.f1 for scenario in scenarios]
    declared_f1_values =
        [scenario.declared_metrics.f1 for scenario in scenarios]

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_simulation_grid.v1",
        family = :mgmfrm,
        scope = :empirical_q_matrix_recovery_simulation_grid,
        status = :empirical_q_matrix_recovery_simulation_grid_recorded,
        decision = :keep_empirical_q_recovery_local_diagnostic_only,
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
        q_matrix_reference_records = Q_MATRIX_REFERENCE_RECORDS,
        scite_q_matrix_snapshot = SCITE_Q_MATRIX_SNAPSHOT,
        research_basis = RESEARCH_BASIS,
        input_artifacts = input_records,
        candidate_thresholds = (;
            add_loading = ADD_THRESHOLD,
            drop_loading = DROP_THRESHOLD,
            ambiguous_low = AMBIGUOUS_LOW,
            ambiguous_high = AMBIGUOUS_HIGH,
        ),
        scenario_rows = scenarios,
        decision_rows = decision_rows(),
        decision_record = (;
            empirical_q_recovery_allowed = false,
            automatic_q_revision_allowed = false,
            candidate_suggestions_allowed = true,
            public_recovery_claim_allowed = false,
            public_exposure_support =
                :doi_backed_q_candidate_simulation_grid_recorded,
            interpretation =
                :q_candidate_recovery_scenarios_passed_but_public_q_revision_remains_blocked,
            required_followup = :real_fit_diagnostic_linkage_for_q_candidates,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            empirical_q_matrix_recovery_policy_passed = policy.summary_passed,
            q_matrix_reference_records_recorded,
            research_basis_recorded,
            all_scenarios_passed,
            all_candidate_validations_checked,
            candidate_exactness_recorded,
            false_public_promotion_rate_zero,
            no_automatic_q_revision,
            no_public_recovery_claim,
            empirical_q_recovery_allowed = false,
            candidate_suggestions_allowed = true,
            n_input_artifacts = length(input_records),
            n_q_matrix_reference_records = length(Q_MATRIX_REFERENCE_RECORDS),
            n_scite_q_matrix_snapshots = length(SCITE_Q_MATRIX_SNAPSHOT),
            n_research_basis = length(RESEARCH_BASIS),
            n_scenarios = length(scenarios),
            n_passed_scenarios =
                count(scenario -> scenario.summary.passed, scenarios),
            n_candidate_exact_recoveries =
                count(scenario -> scenario.candidate_exact_recovery, scenarios),
            n_candidate_improved_over_declared =
                count(scenario -> scenario.candidate_improves_f1, scenarios),
            n_false_candidate_scenarios =
                count(scenario -> scenario.false_candidate, scenarios),
            n_deferred_scenarios =
                count(scenario -> scenario.summary.deferred_candidate,
                    scenarios),
            n_blocked_scenarios =
                count(scenario -> scenario.summary.invalid_candidate_blocked,
                    scenarios),
            n_public_revisions_allowed =
                count(scenario -> scenario.public_recovery_allowed, scenarios),
            n_automatic_revisions_allowed =
                count(scenario -> scenario.automatic_revision_allowed,
                    scenarios),
            false_public_promotion_rate =
                round(false_public_promotion_rate; digits = 6),
            mean_declared_cell_f1 =
                round(mean(declared_f1_values); digits = 6),
            mean_candidate_cell_f1 =
                round(mean(candidate_f1_values); digits = 6),
            min_candidate_cell_f1 =
                round(minimum(candidate_f1_values); digits = 6),
            remaining_public_blockers = [
                :real_fit_diagnostic_linkage_missing,
                :cross_validated_q_revision_policy_missing,
                :construct_validity_manual_review_missing,
            ],
            recommendation =
                :use_q_recovery_simulation_grid_for_local_candidate_diagnostics_only,
            next_gate = :real_fit_diagnostic_linkage_for_q_candidates,
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
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
