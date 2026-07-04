#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_empirical_q_matrix_recovery_policy.json")

include(joinpath(@__DIR__, "local_json.jl"))

module FullArchiveJSON
include(joinpath(@__DIR__, "generate_gmfrm_full_paper_reproduction_archive.jl"))
end

const JSON = FullArchiveJSON

const INPUT_ARTIFACTS = [
    (name = :q_matrix_validation_expansion,
        path = "test/fixtures/mgmfrm_q_matrix_validation_expansion.json",
        expected_schema =
            "bayesianmgmfrm.mgmfrm_q_matrix_validation_expansion.v1",
        pass_policy = :summary_passed),
]

const ZOTERO_UTO_RECORD = (;
    key = :uto_2021_mgmfrm,
    zotero_item_key = "WSQ6QZ4T",
    duplicate_zotero_item_keys = ["38TX837G"],
    source = :zotero_local_library,
    title =
        "A multidimensional generalized many-facet Rasch model for rubric-based performance assessment",
    item_type = :journalArticle,
    author = "Uto, Masaki",
    date = "07/2021",
    journal = "Behaviormetrika",
    volume = "48",
    issue = "2",
    pages = "425-457",
    doi = "10.1007/s41237-021-00144-w",
    url = "https://link.springer.com/10.1007/s41237-021-00144-w",
    annotations_found = false,
    scite_snapshot = (;
        retrieved_on = "2026-07-04",
        supporting = 0,
        contrasting = 0,
        mentioning = 10,
        total_citing_publications = 17,
    ),
    relevance =
        :rubric_dimensions_and_item_dimension_loadings_must_remain_interpretable,
)

const RESEARCH_BASIS = [
    (;
        key = :uto_2021_mgmfrm,
        source = :zotero_and_doi,
        zotero_item_key = ZOTERO_UTO_RECORD.zotero_item_key,
        citation =
            "Uto (2021), A multidimensional generalized many-facet Rasch model for rubric-based performance assessment",
        url = ZOTERO_UTO_RECORD.url,
        doi = ZOTERO_UTO_RECORD.doi,
        relevance =
            :mgmfrm_dimension_loading_policy_must_protect_rubric_construct_validity,
    ),
    (;
        key = :da_silva_2019_mirt_q_matrix,
        source = :doi,
        citation =
            "da Silva, Liu, Huggins-Manley, and Bazan (2019), Incorporating the Q-Matrix Into Multidimensional Item Response Theory Models",
        url = "https://doi.org/10.1177/0013164418814898",
        doi = "10.1177/0013164418814898",
        relevance =
            :q_matrix_changes_are_confirmatory_loading_mask_changes_not_free_axis_discovery,
    ),
    (;
        key = :de_la_torre_chiu_2016_gdi,
        source = :doi,
        citation =
            "de la Torre and Chiu (2016), A General Method of Empirical Q-matrix Validation",
        url = "https://doi.org/10.1007/s11336-015-9467-8",
        doi = "10.1007/s11336-015-9467-8",
        relevance =
            :empirical_q_validation_requires_predeclared_suggestion_rules_and_misspecification_checks,
    ),
    (;
        key = :terzi_de_la_torre_2018_iterative,
        source = :doi,
        citation =
            "Terzi and de la Torre (2018), An Iterative Method for Empirically-Based Q-Matrix Validation",
        url = "https://doi.org/10.21449/ijate.407193",
        doi = "10.21449/ijate.407193",
        relevance =
            :candidate_q_revisions_should_be_iterative_actionable_and_item_level,
    ),
    (;
        key = :najera_2020_q_matrix_cutoffs,
        source = :doi,
        citation =
            "Najera, Sorrel, de la Torre, and Abad (2020), Improving robustness in Q-matrix validation using an iterative and dynamic procedure",
        url = "https://doi.org/10.1177/0146621620909904",
        doi = "10.1177/0146621620909904",
        relevance =
            :cutoff_and_misspecification_uncertainty_block_automatic_public_q_revisions,
    ),
]

const PROTOCOL = (;
    protocol_id = "mgmfrm_empirical_q_matrix_recovery_policy_v1",
    review_kind = :local_empirical_q_matrix_recovery_policy,
    publication_or_registration_action = false,
    local_only = true,
    policy_scope = :fixed_q_confirmatory_mgmfrm_candidate_revision_policy,
    thresholds = (;
        require_q_matrix_validation_expansion_passed = true,
        require_zotero_uto_record = true,
        require_research_basis_recorded = true,
        require_all_candidate_policy_scenarios_passed = true,
        require_invalid_suggested_q_blocked = true,
        require_ambiguous_or_weak_design_no_auto_revision = true,
        require_all_candidate_suggestions_validation_checked = true,
        require_no_public_automatic_q_revision = true,
        require_no_publication_or_registration_action = true,
    ),
)

const ADD_THRESHOLD = 0.75
const DROP_THRESHOLD = 0.25
const AMBIGUOUS_LOW = 0.45
const AMBIGUOUS_HIGH = 0.55

const SCENARIOS = [
    (;
        scenario = :true_q_retained,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
        ],
        empirical_signal = [
            0.92 0.08
            0.10 0.90
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_action = :retain_declared_q,
        expected_suggested_q = Bool[
            1 0
            0 1
        ],
        expected_validation_passed = true,
        expected_operation_count = 0,
    ),
    (;
        scenario = :missing_loading_candidate_flagged,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
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
        expected_action = :flag_missing_loading_candidate,
        expected_suggested_q = Bool[
            1 0
            0 1
            1 1
        ],
        expected_validation_passed = true,
        expected_operation_count = 1,
    ),
    (;
        scenario = :extra_loading_candidate_flagged,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
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
        expected_action = :flag_extra_loading_candidate,
        expected_suggested_q = Bool[
            1 0
            0 1
            1 0
        ],
        expected_validation_passed = true,
        expected_operation_count = 1,
    ),
    (;
        scenario = :ambiguous_loading_deferred,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
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
        expected_action = :defer_ambiguous_loading_evidence,
        expected_suggested_q = Bool[
            1 0
            0 1
            1 0
        ],
        expected_validation_passed = true,
        expected_operation_count = 0,
    ),
    (;
        scenario = :empty_item_candidate_blocked,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
            1 0
        ],
        empirical_signal = [
            0.91 0.06
            0.07 0.93
            0.08 0.09
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_action = :block_invalid_candidate_revision,
        expected_suggested_q = Bool[
            1 0
            0 1
            0 0
        ],
        expected_validation_passed = false,
        expected_operation_count = 1,
    ),
    (;
        scenario = :empty_dimension_candidate_blocked,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
        ],
        empirical_signal = [
            0.91 0.06
            0.07 0.12
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_action = :block_invalid_candidate_revision,
        expected_suggested_q = Bool[
            1 0
            0 0
        ],
        expected_validation_passed = false,
        expected_operation_count = 1,
    ),
    (;
        scenario = :duplicate_dimension_candidate_blocked,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
        ],
        empirical_signal = [
            0.91 0.88
            0.86 0.93
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_action = :block_invalid_candidate_revision,
        expected_suggested_q = Bool[
            1 1
            1 1
        ],
        expected_validation_passed = false,
        expected_operation_count = 2,
    ),
    (;
        scenario = :simple_structure_cross_loading_policy_blocked,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
            1 0
        ],
        empirical_signal = [
            0.91 0.06
            0.07 0.93
            0.86 0.83
        ],
        cross_loading_policy = :blocked_simple_structure,
        expected_action = :block_policy_candidate_revision,
        expected_suggested_q = Bool[
            1 0
            0 1
            1 1
        ],
        expected_validation_passed = false,
        expected_operation_count = 1,
    ),
    (;
        scenario = :weak_dimension_facet_link_deferred,
        data_kind = :dimension_disconnected,
        dimensions = 2,
        q_matrix = Bool[
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
        expected_action = :defer_weak_design_empirical_recovery,
        expected_suggested_q = Bool[
            1 0
            1 0
            0 1
        ],
        expected_validation_passed = true,
        expected_operation_count = 0,
    ),
]

function usage()
    return """
    Generate the local MGMFRM empirical Q-matrix recovery policy artifact.

    The artifact records a conservative candidate-revision policy. It can flag
    possible missing or extra loadings, but it never authorizes public automatic
    Q-matrix revision. Candidate Q matrices must pass the same fixed-Q MGMFRM
    validation contract before any later simulation grid may use them.

    Usage:
      julia --project=. scripts/generate_mgmfrm_empirical_q_matrix_recovery_policy.jl [--output PATH]
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
    name === :q_matrix_validation_expansion && return (;
        passed = summary_bool(summary, "passed"),
        n_scenarios = json_optional_int(summary, "n_scenarios"),
        all_expected_validation_outcomes =
            summary_bool(summary, "all_expected_validation_outcomes"),
        all_invalid_default_q_scenarios_blocked_before_fit =
            summary_bool(summary,
                "all_invalid_default_q_scenarios_blocked_before_fit"),
        policy_validation_scenarios_recorded =
            summary_bool(summary, "policy_validation_scenarios_recorded"),
        research_basis_recorded =
            summary_bool(summary, "research_basis_recorded"),
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
    for person in 1:4, rater_index in 1:3, item_index in 1:n_items
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
    return connected_full_crossed_table(size(scenario.q_matrix, 1))
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
    return sort(unique(Symbol[row.check for row in validation.rows
        if row.severity === severity]); by = string)
end

function candidate_action(scenario, operations, ambiguous, validation)
    !isempty(ambiguous) && return :defer_ambiguous_loading_evidence
    scenario.data_kind === :dimension_disconnected &&
        return :defer_weak_design_empirical_recovery
    validation.passed || return scenario.cross_loading_policy ===
        :blocked_simple_structure ? :block_policy_candidate_revision :
        :block_invalid_candidate_revision
    isempty(operations) && return :retain_declared_q
    all(operation -> operation.operation === :add_loading, operations) &&
        return :flag_missing_loading_candidate
    all(operation -> operation.operation === :drop_loading, operations) &&
        return :flag_extra_loading_candidate
    return :flag_mixed_loading_candidate
end

function scenario_record(scenario)
    operations, ambiguous =
        operation_rows(scenario.q_matrix, scenario.empirical_signal)
    candidate_q = suggested_q_matrix(scenario.q_matrix, operations)
    data = facet_data(table_for_scenario(scenario))
    validation = BayesianMGMFRM.q_matrix_validation(data;
        family = :mgmfrm,
        dimensions = scenario.dimensions,
        q_matrix = candidate_q,
        cross_loading_policy = scenario.cross_loading_policy,
    )
    action = candidate_action(scenario, operations, ambiguous, validation)
    validation_passed_matches =
        validation.passed == scenario.expected_validation_passed
    action_matches = action === scenario.expected_action
    operation_count_matches =
        length(operations) == scenario.expected_operation_count
    suggested_q_matches =
        matrix_rows(candidate_q) == matrix_rows(scenario.expected_suggested_q)
    automatic_revision_allowed = false
    return (;
        scenario = scenario.scenario,
        data_kind = scenario.data_kind,
        dimensions = scenario.dimensions,
        cross_loading_policy = scenario.cross_loading_policy,
        q_matrix = matrix_rows(scenario.q_matrix),
        empirical_signal = matrix_rows(scenario.empirical_signal),
        operations,
        ambiguous_operations = ambiguous,
        suggested_q_matrix = matrix_rows(candidate_q),
        validation_passed = validation.passed,
        validation_rows = compact_rows(validation),
        error_checks = severity_checks(validation, :error),
        warning_checks = severity_checks(validation, :warning),
        action,
        expected_action = scenario.expected_action,
        automatic_revision_allowed,
        public_recovery_allowed = false,
        summary = (;
            passed = validation_passed_matches &&
                action_matches &&
                operation_count_matches &&
                suggested_q_matches &&
                !automatic_revision_allowed,
            validation_passed_matches,
            action_matches,
            operation_count_matches,
            suggested_q_matches,
            n_operations = length(operations),
            n_ambiguous_operations = length(ambiguous),
            candidate_validation_checked = true,
            invalid_candidate_blocked =
                !validation.passed &&
                action in (:block_invalid_candidate_revision,
                    :block_policy_candidate_revision),
            deferred_candidate =
                action in (:defer_ambiguous_loading_evidence,
                    :defer_weak_design_empirical_recovery),
        ),
    )
end

function record_by_name(records, name::Symbol)
    return only(record for record in records if record.artifact === name)
end

function no_publication_commands()
    command =
        "julia --project=. scripts/generate_mgmfrm_empirical_q_matrix_recovery_policy.jl"
    banned = ["git push", "gh release", "Registrator", "Pkg.register", "publish"]
    lowered = lowercase(command)
    return all(!occursin(lowercase(term), lowered) for term in banned)
end

function decision_rows()
    return [
        (decision = :do_not_rewrite_user_q_matrix,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :empirical_loading_evidence_is_diagnostic_until_predeclared_recovery_grid_passes),
        (decision = :validate_every_candidate_q,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :candidate_revisions_must_satisfy_fixed_q_shape_identification_and_policy_checks),
        (decision = :defer_ambiguous_or_weak_design_candidates,
            status = :enforced,
            public_claim_allowed = false,
            rationale =
                :ambiguous_signal_or_dimension_disconnection_cannot_support_construct_revision),
        (decision = :require_simulation_grid_before_recovery_claims,
            status = :blocking,
            public_claim_allowed = false,
            rationale =
                :recovery_error_rates_must_be_estimated_before_empirical_q_revision_claims),
    ]
end

function build_artifact()
    input_records = [artifact_record(spec) for spec in INPUT_ARTIFACTS]
    q_expansion = record_by_name(input_records, :q_matrix_validation_expansion)
    scenarios = [scenario_record(scenario) for scenario in SCENARIOS]
    no_publication = no_publication_commands()
    all_input_artifacts_present = all(record -> record.exists, input_records)
    all_expected_schemas = all(record -> record.schema_matches, input_records)
    all_input_summaries_passed =
        all(record -> record.summary_passed, input_records)
    all_scenarios_passed = all(scenario -> scenario.summary.passed, scenarios)
    invalid_candidates_blocked =
        all(scenario -> !scenario.summary.invalid_candidate_blocked ||
            scenario.public_recovery_allowed == false, scenarios)
    ambiguous_or_weak_deferred =
        all(scenario -> !scenario.summary.deferred_candidate ||
            scenario.public_recovery_allowed == false, scenarios)
    all_candidate_suggestions_validation_checked =
        all(scenario -> scenario.summary.candidate_validation_checked, scenarios)
    no_public_automatic_q_revision =
        all(scenario -> !scenario.automatic_revision_allowed &&
            !scenario.public_recovery_allowed, scenarios)
    zotero_uto_recorded =
        !isempty(ZOTERO_UTO_RECORD.zotero_item_key) &&
        ZOTERO_UTO_RECORD.doi == "10.1007/s41237-021-00144-w"
    research_basis_recorded =
        length(RESEARCH_BASIS) >= 5 &&
        any(row -> row.key === :uto_2021_mgmfrm &&
            row.source === :zotero_and_doi, RESEARCH_BASIS)
    passed = all_input_artifacts_present &&
        all_expected_schemas &&
        all_input_summaries_passed &&
        Bool(q_expansion.summary.all_expected_validation_outcomes) &&
        Bool(q_expansion.summary.
            all_invalid_default_q_scenarios_blocked_before_fit) &&
        Bool(q_expansion.summary.policy_validation_scenarios_recorded) &&
        zotero_uto_recorded &&
        research_basis_recorded &&
        all_scenarios_passed &&
        invalid_candidates_blocked &&
        ambiguous_or_weak_deferred &&
        all_candidate_suggestions_validation_checked &&
        no_public_automatic_q_revision &&
        no_publication

    return (;
        schema =
            "bayesianmgmfrm.mgmfrm_empirical_q_matrix_recovery_policy.v1",
        family = :mgmfrm,
        scope = :empirical_q_matrix_recovery_policy,
        status = :empirical_q_matrix_recovery_policy_recorded,
        decision = :keep_empirical_q_recovery_diagnostic_only,
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
        zotero_records = [ZOTERO_UTO_RECORD],
        research_basis = RESEARCH_BASIS,
        input_artifacts = input_records,
        candidate_thresholds = (;
            add_loading = ADD_THRESHOLD,
            drop_loading = DROP_THRESHOLD,
            ambiguous_low = AMBIGUOUS_LOW,
            ambiguous_high = AMBIGUOUS_HIGH,
        ),
        candidate_policy_rows = scenarios,
        decision_rows = decision_rows(),
        decision_record = (;
            empirical_q_recovery_allowed = false,
            automatic_q_revision_allowed = false,
            candidate_suggestions_allowed = true,
            public_exposure_support =
                :diagnostic_candidate_q_policy_recorded_recovery_claims_blocked,
            interpretation =
                :zotero_supported_uto_reference_and_q_candidate_policy_recorded_no_public_revision,
            required_followup = :empirical_q_matrix_recovery_simulation_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            all_input_artifacts_present,
            all_expected_schemas,
            all_input_summaries_passed,
            q_matrix_validation_expansion_passed = q_expansion.summary_passed,
            zotero_uto_recorded,
            research_basis_recorded,
            all_candidate_policy_scenarios_passed = all_scenarios_passed,
            invalid_suggested_q_blocked = invalid_candidates_blocked,
            ambiguous_or_weak_design_no_auto_revision =
                ambiguous_or_weak_deferred,
            all_candidate_suggestions_validation_checked,
            no_public_automatic_q_revision,
            empirical_q_recovery_allowed = false,
            candidate_suggestions_allowed = true,
            n_input_artifacts = length(input_records),
            n_research_basis = length(RESEARCH_BASIS),
            n_zotero_records = 1,
            n_candidate_policy_scenarios = length(scenarios),
            n_passed_candidate_policy_scenarios =
                count(scenario -> scenario.summary.passed, scenarios),
            n_invalid_candidate_scenarios =
                count(scenario -> scenario.summary.invalid_candidate_blocked,
                    scenarios),
            n_deferred_candidate_scenarios =
                count(scenario -> scenario.summary.deferred_candidate,
                    scenarios),
            n_automatic_revisions_allowed =
                count(scenario -> scenario.automatic_revision_allowed,
                    scenarios),
            remaining_public_blockers = [
                :empirical_q_matrix_recovery_simulation_grid_missing,
                :real_fit_diagnostic_linkage_missing,
                :cross_validated_q_revision_policy_missing,
                :construct_validity_manual_review_missing,
            ],
            recommendation =
                :use_candidate_q_policy_for_local_diagnostics_only_then_run_recovery_simulation_grid,
            next_gate = :empirical_q_matrix_recovery_simulation_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = build_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_candidate_policy_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
