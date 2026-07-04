#!/usr/bin/env julia

using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "mgmfrm_q_matrix_validation_expansion.json")

include(joinpath(@__DIR__, "local_json.jl"))

const RESEARCH_BASIS = [
    (;
        key = :uto_2021_mgmfrm,
        citation =
            "Uto (2021), A multidimensional generalized many-facet Rasch model for rubric-based performance assessment",
        url = "https://d-nb.info/1244896063/34",
        doi = "10.1007/s41237-021-00144-w",
        relevance =
            :multidimensional_rubric_items_require_interpretable_item_dimension_structure,
    ),
    (;
        key = :da_silva_2019_mirt_q_matrix,
        citation =
            "da Silva, Liu, Huggins-Manley, and Bazan (2019), Incorporating the Q-Matrix Into Multidimensional Item Response Theory Models",
        url = "https://doi.org/10.1177/0013164418814898",
        doi = "10.1177/0013164418814898",
        relevance =
            :q_matrix_as_confirmatory_mirt_loading_mask_and_identification_contract,
    ),
    (;
        key = :de_la_torre_chiu_2016_gdi,
        citation =
            "de la Torre and Chiu (2016), A General Method of Empirical Q-matrix Validation",
        url = "https://doi.org/10.1007/s11336-015-9467-8",
        doi = "10.1007/s11336-015-9467-8",
        relevance =
            :q_matrix_misspecification_requires_explicit_validation_not_silent_fitting,
    ),
    (;
        key = :terzi_de_la_torre_2018_iterative,
        citation =
            "Terzi and de la Torre (2018), An Iterative Method for Empirically-Based Q-Matrix Validation",
        url = "https://doi.org/10.21449/ijate.407193",
        doi = "10.21449/ijate.407193",
        relevance =
            :validation_should_record_actionable_item_level_failure_modes,
    ),
    (;
        key = :chalmers_2012_mirt,
        citation =
            "Chalmers (2012), mirt: A Multidimensional Item Response Theory Package for the R Environment",
        url = "https://www.jstatsoft.org/article/view/v048i06",
        doi = "10.18637/jss.v048.i06",
        relevance =
            :confirmatory_multidimensional_irt_uses_structured_loading_specifications,
    ),
]

const PROTOCOL = (;
    protocol_id = "confirmatory_mgmfrm_q_matrix_validation_expansion_v1",
    review_kind = :local_confirmatory_mgmfrm_q_matrix_validation_expansion,
    publication_or_registration_action = false,
    scenario_count = 13,
    thresholds = (;
        require_all_expected_validation_outcomes = true,
        require_all_expected_spec_outcomes = true,
        require_all_invalid_default_q_scenarios_blocked_before_fit = true,
        require_policy_validation_scenarios_recorded = true,
        require_warning_scenarios_not_rejected = true,
        require_valid_scenarios_preview_design = true,
        require_research_basis_recorded = true,
        public_exposure_decision = :guarded_fixed_q_only,
    ),
)

const SCENARIOS = [
    (;
        scenario = :valid_simple_2d,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = true,
        expected_spec_default = :succeeded,
        expected_error_checks = Symbol[],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :valid_confirmatory_cross_loading,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
            1 1
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = true,
        expected_spec_default = :succeeded,
        expected_error_checks = Symbol[],
        expected_warning_checks = [:cross_loading_policy],
    ),
    (;
        scenario = :missing_q_matrix,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = nothing,
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:required_q_matrix],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :non_matrix_q_matrix,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = "not_a_matrix",
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:matrix_schema],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :non_binary_entries,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Any[
            1 0
            0 2
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:binary_mask_schema],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :item_shape_mismatch,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:shape],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :dimension_shape_mismatch,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0 0
            0 1 0
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:shape],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :empty_item_row,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            0 1
            0 0
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:empty_item_rows],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :empty_dimension_column,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            1 0
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:empty_dimensions],
        expected_warning_checks = [:positive_loading_identification],
    ),
    (;
        scenario = :duplicate_dimension_columns,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 1
            1 1
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = false,
        expected_spec_default = :throws,
        expected_error_checks = [:duplicate_dimension_columns],
        expected_warning_checks = [:cross_loading_policy,
            :positive_loading_identification],
    ),
    (;
        scenario = :blocked_cross_loading_policy,
        data_kind = :connected_full_crossed,
        dimensions = 2,
        q_matrix = Bool[
            1 1
            0 1
        ],
        cross_loading_policy = :blocked_simple_structure,
        expected_validation_passed = false,
        expected_spec_default = :succeeded,
        expected_error_checks = [:cross_loading_policy],
        expected_warning_checks = Symbol[],
    ),
    (;
        scenario = :warning_no_single_loading_anchor,
        data_kind = :connected_full_crossed,
        dimensions = 3,
        q_matrix = Bool[
            1 1 0
            0 1 1
            1 0 1
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = true,
        expected_spec_default = :succeeded,
        expected_error_checks = Symbol[],
        expected_warning_checks = [:cross_loading_policy,
            :positive_loading_identification],
    ),
    (;
        scenario = :warning_dimension_facet_disconnected,
        data_kind = :dimension_disconnected,
        dimensions = 2,
        q_matrix = Bool[
            1 0
            1 0
            0 1
        ],
        cross_loading_policy = :confirmatory_fixed,
        expected_validation_passed = true,
        expected_spec_default = :not_checked,
        expected_error_checks = Symbol[],
        expected_warning_checks = [:dimension_facet_subgraph_coverage],
    ),
]

function usage()
    return """
    Generate the local fixed-Q MGMFRM Q-matrix validation expansion artifact.

    The artifact records valid, warning-only, and invalid Q-matrix scenarios.
    It verifies that invalid structural Q contracts are rejected before any
    guarded MGMFRM sampler can run. It does not estimate empirical Q revisions.

    Usage:
      julia --project=. scripts/generate_mgmfrm_q_matrix_validation_expansion.jl [--output PATH]
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

function project_version()
    project = TOML.parsefile(joinpath(ROOT, "Project.toml"))
    return String(project["version"])
end

function q_matrix_rows(q_matrix)
    q_matrix isa AbstractMatrix || return nothing
    return [
        [q_matrix[row, col] for col in axes(q_matrix, 2)]
        for row in axes(q_matrix, 1)
    ]
end

function connected_full_crossed_table(n_items::Int)
    examinee = String[]
    rater = String[]
    item = String[]
    score = Int[]
    for person in 1:3, rater_index in 1:2, item_index in 1:n_items
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
    if scenario.data_kind === :dimension_disconnected
        return dimension_disconnected_table()
    end
    if scenario.scenario === :item_shape_mismatch
        return connected_full_crossed_table(2)
    end
    n_items = scenario.q_matrix isa AbstractMatrix ?
        size(scenario.q_matrix, 1) : 2
    return connected_full_crossed_table(n_items)
end

function facet_data(table)
    return BayesianMGMFRM.FacetData(table;
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function compact_rows(validation)
    return [
        (;
            check = row.check,
            status = row.status,
            severity = row.severity,
            item = row.item,
            dimension = row.dimension,
            dimension_label = row.dimension_label,
            n_items = row.n_items,
            n_dimensions = row.n_dimensions,
            n_active = row.n_active,
            n_components = row.n_components,
            note = row.note,
        )
        for row in validation.rows
    ]
end

function checks_with_severity(validation, severity::Symbol)
    return sort(unique(Symbol[row.check for row in validation.rows
        if row.severity === severity]); by = string)
end

function matching_expected(actual::Vector{Symbol}, expected::Vector{Symbol})
    return all(check -> check in actual, expected)
end

function spec_default_record(data, scenario)
    try
        spec = BayesianMGMFRM.mfrm_spec(data;
            thresholds = :partial_credit,
            family = :mgmfrm,
            dimensions = scenario.dimensions,
            q_matrix = scenario.q_matrix,
        )
        design = BayesianMGMFRM.getdesign(spec; preview = true)
        return (;
            outcome = :succeeded,
            error_contains_invalid_q = false,
            preview_design_succeeded = true,
            n_parameters = length(design.parameter_names),
            message = "",
        )
    catch error
        message = sprint(showerror, error)
        return (;
            outcome = :throws,
            error_contains_invalid_q =
                occursin("invalid fixed-Q MGMFRM q_matrix", message),
            preview_design_succeeded = false,
            n_parameters = 0,
            message,
        )
    end
end

function scenario_record(scenario)
    table = table_for_scenario(scenario)
    data = facet_data(table)
    validation = BayesianMGMFRM.q_matrix_validation(data;
        family = :mgmfrm,
        dimensions = scenario.dimensions,
        q_matrix = scenario.q_matrix,
        cross_loading_policy = scenario.cross_loading_policy,
    )
    spec_default = spec_default_record(data, scenario)
    error_checks = checks_with_severity(validation, :error)
    warning_checks = checks_with_severity(validation, :warning)
    validation_outcome_matches =
        validation.passed == scenario.expected_validation_passed &&
        matching_expected(error_checks, scenario.expected_error_checks) &&
        matching_expected(warning_checks, scenario.expected_warning_checks)
    spec_outcome_matches = scenario.expected_spec_default === :not_checked ||
        spec_default.outcome === scenario.expected_spec_default
    default_prefit_block_required = scenario.expected_spec_default === :throws
    default_prefit_blocked = default_prefit_block_required ?
        spec_default.outcome === :throws &&
            spec_default.error_contains_invalid_q : nothing
    policy_validation_only =
        !scenario.expected_validation_passed && !default_prefit_block_required
    warning_only =
        validation.passed && !isempty(warning_checks)
    valid_no_warning = validation.passed && isempty(warning_checks)
    return (;
        scenario = scenario.scenario,
        data_kind = scenario.data_kind,
        dimensions = scenario.dimensions,
        q_matrix = q_matrix_rows(scenario.q_matrix),
        q_matrix_repr = repr(scenario.q_matrix),
        cross_loading_policy = scenario.cross_loading_policy,
        expected_validation_passed = scenario.expected_validation_passed,
        expected_spec_default = scenario.expected_spec_default,
        validation_passed = validation.passed,
        validation_rows = compact_rows(validation),
        error_checks,
        warning_checks,
        validation_summary = validation.summary,
        spec_default,
        summary = (;
            passed = validation_outcome_matches &&
                spec_outcome_matches &&
                (default_prefit_blocked === nothing ||
                    default_prefit_blocked),
            validation_outcome_matches,
            spec_outcome_matches,
            default_prefit_block_required,
            default_prefit_blocked,
            policy_validation_only,
            warning_only,
            valid_no_warning,
            n_error_checks = length(error_checks),
            n_warning_checks = length(warning_checks),
        ),
    )
end

function grid_artifact()
    scenarios = [scenario_record(scenario) for scenario in SCENARIOS]
    error_scenarios = [
        scenario for scenario in scenarios
        if !scenario.expected_validation_passed
    ]
    invalid_default_q_scenarios = [
        scenario for scenario in scenarios
        if scenario.summary.default_prefit_block_required
    ]
    policy_validation_scenarios = [
        scenario for scenario in scenarios
        if scenario.summary.policy_validation_only
    ]
    warning_scenarios = [
        scenario for scenario in scenarios
        if scenario.summary.warning_only
    ]
    valid_scenarios = [
        scenario for scenario in scenarios
        if scenario.expected_validation_passed &&
            scenario.expected_spec_default === :succeeded
    ]
    warning_spec_scenarios = [
        scenario for scenario in warning_scenarios
        if scenario.expected_spec_default === :succeeded
    ]
    passed = all(scenario -> scenario.summary.passed, scenarios) &&
        all(scenario -> scenario.summary.default_prefit_blocked === true,
            invalid_default_q_scenarios) &&
        all(scenario -> scenario.validation_passed == false,
            policy_validation_scenarios) &&
        all(scenario -> scenario.spec_default.outcome === :succeeded,
            warning_spec_scenarios) &&
        all(scenario -> scenario.spec_default.preview_design_succeeded,
            valid_scenarios) &&
        length(RESEARCH_BASIS) >= 5
    return (;
        schema = "bayesianmgmfrm.mgmfrm_q_matrix_validation_expansion.v1",
        family = :mgmfrm,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        status = :q_matrix_validation_expansion_recorded,
        decision = :keep_guarded_fixed_q_only,
        public_fit = true,
        experimental_public = true,
        fit_ready = true,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        research_basis = RESEARCH_BASIS,
        scenarios,
        decision_record = (;
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            public_exposure_support =
                :supports_guarded_fixed_q_validation_contract,
            interpretation =
                :fixed_q_structural_validation_and_prefit_blocking_recorded,
            required_followup = :empirical_q_matrix_recovery_policy,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            n_scenarios = length(scenarios),
            n_passed_scenarios =
                count(scenario -> scenario.summary.passed, scenarios),
            n_validation_passed =
                count(scenario -> scenario.validation_passed, scenarios),
            n_validation_failed =
                count(scenario -> !scenario.validation_passed, scenarios),
            n_spec_default_succeeded =
                count(scenario -> scenario.spec_default.outcome === :succeeded,
                    scenarios),
            n_spec_default_threw =
                count(scenario -> scenario.spec_default.outcome === :throws,
                    scenarios),
            all_expected_validation_outcomes =
                all(scenario -> scenario.summary.validation_outcome_matches,
                    scenarios),
            all_expected_spec_outcomes =
                all(scenario -> scenario.summary.spec_outcome_matches, scenarios),
            all_invalid_default_q_scenarios_blocked_before_fit =
                all(scenario -> scenario.summary.default_prefit_blocked === true,
                    invalid_default_q_scenarios),
            n_invalid_default_q_scenarios = length(invalid_default_q_scenarios),
            policy_validation_scenarios_recorded =
                all(scenario -> scenario.validation_passed == false,
                    policy_validation_scenarios),
            n_policy_validation_scenarios =
                length(policy_validation_scenarios),
            warning_scenarios_not_rejected =
                all(scenario -> scenario.spec_default.outcome === :succeeded,
                    warning_spec_scenarios),
            valid_scenarios_preview_design =
                all(scenario -> scenario.spec_default.preview_design_succeeded,
                    valid_scenarios),
            research_basis_recorded = length(RESEARCH_BASIS) >= 5,
            structural_checks_covered = sort(unique(vcat(
                [row.check for scenario in scenarios
                    for row in scenario.validation_rows],
            )); by = string),
            public_fit_allowed = true,
            experimental_keyword_enabled = true,
            remaining_public_blockers = [
                :empirical_q_matrix_recovery_policy_missing,
                :free_latent_correlation_policy_missing,
                :exploratory_loading_policy_missing,
                :broad_generalized_mgmfrm_validation_missing,
            ],
            recommendation =
                :keep_fixed_q_confirmatory_guarded_continue_empirical_q_policy,
            next_gate = :empirical_q_matrix_recovery_policy,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = grid_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
