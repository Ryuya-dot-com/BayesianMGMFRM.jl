#!/usr/bin/env julia

using SHA
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT =
    joinpath(ROOT, "test", "fixtures",
        "gmfrm_dff_estimand_validation_grid.json")

include(joinpath(@__DIR__, "local_json.jl"))

const ESTIMANDS = [
    (estimand = :rater_by_group_dff,
        term = (:rater, :group),
        target = :rater_severity_difference_by_group,
        primary_scale = :logit,
        reporting_scales = (:logit, :expected_score),
        current_status = :validation_only),
    (estimand = :item_by_group_dff,
        term = (:item, :group),
        target = :item_difficulty_difference_by_group,
        primary_scale = :logit,
        reporting_scales = (:logit, :expected_score),
        current_status = :validation_only),
    (estimand = :rater_by_item_interaction,
        term = (:rater, :item),
        target = :rater_item_bias_or_local_severity_shift,
        primary_scale = :logit,
        reporting_scales = (:logit, :expected_score),
        current_status = :validation_only),
    (estimand = :threshold_by_group_dff,
        term = (:thresholds, :group),
        target = :category_threshold_shift_by_group,
        primary_scale = :logit,
        reporting_scales = (:logit, :expected_score),
        current_status = :predeclared_not_validated_by_current_bias_api),
    (estimand = :discrimination_by_group_dff,
        term = (:discrimination, :group),
        target = :generalized_discrimination_shift_by_group,
        primary_scale = :logit,
        reporting_scales = (:logit, :expected_score),
        current_status = :predeclared_requires_future_generalized_fit_policy),
]

const PROTOCOL = (;
    protocol_id = "gmfrm_dff_estimand_validation_grid_v1",
    review_kind = :local_dff_estimand_and_validation_grid,
    publication_or_registration_action = false,
    local_only = true,
    decision_target = :dff_estimand_validation_evidence,
    entrypoint_under_review = "validate_design(data; bias = terms)",
    supported_validation_facets = (:person, :rater, :item, :group),
    min_cell_count = 3,
    practical_thresholds = (;
        logit_absolute_difference = 0.25,
        expected_score_absolute_difference = 0.10,
        minimum_cell_count_for_unpooled_screening = 3,
    ),
    thresholds = (;
        require_estimands_predeclared = true,
        require_reporting_scales_predeclared = true,
        require_positive_control_passes_without_warnings = true,
        require_sparse_warning_detected = true,
        require_empty_and_confounded_warning_detected = true,
        require_unknown_facet_error_detected = true,
        require_valid_dff_terms_retained_as_validation_only = true,
        require_no_public_fit_or_model_effect_promotion = true,
        public_exposure_decision = :keep_validation_only,
    ),
)

const SCENARIOS = [
    (scenario = :balanced_group_crossed,
        pattern = :balanced,
        with_group = true,
        bias_terms = ((:rater, :group), (:item, :group), (:rater, :item)),
        expected_passed = true,
        expected_issue_codes = Symbol[],
        expected_support = :screening_supported),
    (scenario = :sparse_rater_group_cells,
        pattern = :sparse,
        with_group = true,
        bias_terms = ((:rater, :group), (:item, :group), (:rater, :item)),
        expected_passed = true,
        expected_issue_codes = (:sparse_dff_cell,),
        expected_support = :sparse_screening_only),
    (scenario = :empty_and_confounded_group_cells,
        pattern = :empty_confounded,
        with_group = true,
        bias_terms = ((:rater, :group), (:item, :group), (:rater, :item)),
        expected_passed = true,
        expected_issue_codes =
            (:empty_dff_cell, :potential_dff_confounding, :sparse_dff_cell),
        expected_support = :not_unpooled_estimable),
    (scenario = :unknown_group_facet_rejected,
        pattern = :balanced,
        with_group = false,
        bias_terms = ((:rater, :group),),
        expected_passed = false,
        expected_issue_codes = (:unknown_bias_facet,),
        expected_support = :invalid_request_rejected),
]

function usage()
    return """
    Generate the local DFF estimand and validation grid artifact.

    Usage:
      julia --project=. scripts/generate_gmfrm_dff_estimand_validation_grid.jl [--output PATH]
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

function file_sha256(path::AbstractString)
    return bytes2hex(open(sha256, path))
end

function fixture_reference(path::AbstractString; hash_policy::Symbol = :sha256)
    local_path = joinpath(ROOT, path)
    should_hash = hash_policy === :sha256 && isfile(local_path)
    return (;
        artifact = path,
        exists = isfile(local_path),
        hash_policy,
        sha256 = should_hash ? file_sha256(local_path) : missing,
    )
end

function score_for(person::AbstractString, rater::AbstractString, item::AbstractString)
    return mod(3 * sum(codeunits(person)) +
        5 * sum(codeunits(rater)) +
        7 * sum(codeunits(item)), 3)
end

function row(person, rater, item, group)
    return (person = person,
        rater = rater,
        item = item,
        score = score_for(person, rater, item),
        group = group)
end

function rows_for_pattern(pattern::Symbol)
    pattern === :balanced && return [
        row(person, rater, item, person in ("E1", "E2") ? "A" : "B")
        for person in ("E1", "E2", "E3", "E4")
        for rater in ("R1", "R2", "R3")
        for item in ("I1", "I2")
    ]
    pattern === :sparse && return vcat(
        [
            row(person, rater, item, "A")
            for person in ("E1", "E2")
            for rater in ("R1", "R2", "R3")
            for item in ("I1", "I2")
        ],
        [
            row(person, "R1", item, "B")
            for person in ("E3", "E4")
            for item in ("I1", "I2")
        ],
        [
            row(person, "R2", "I1", "B")
            for person in ("E3", "E4")
        ],
        [row("E3", "R3", "I1", "B")],
    )
    pattern === :empty_confounded && return vcat(
        [
            row(person, rater, item, "A")
            for person in ("E1", "E2")
            for rater in ("R1", "R3")
            for item in ("I1", "I2")
        ],
        [
            row(person, rater, item, "B")
            for person in ("E3", "E4")
            for rater in ("R2", "R3")
            for item in ("I1", "I2")
        ],
    )
    throw(ArgumentError("unknown DFF scenario pattern: $pattern"))
end

function table_from_rows(rows)
    return (;
        person = [row.person for row in rows],
        rater = [row.rater for row in rows],
        item = [row.item for row in rows],
        score = [row.score for row in rows],
        group = [row.group for row in rows],
    )
end

function facet_data_for_scenario(spec)
    table = table_from_rows(rows_for_pattern(spec.pattern))
    return spec.with_group ?
        BayesianMGMFRM.FacetData(
            table;
            person = :person,
            rater = :rater,
            item = :item,
            score = :score,
            group = :group,
        ) :
        BayesianMGMFRM.FacetData(
            table;
            person = :person,
            rater = :rater,
            item = :item,
            score = :score,
        )
end

function issue_record(issue)
    return (;
        code = issue.code,
        severity = issue.severity,
        message = issue.message,
        context_keys = sort([String(key) for key in keys(issue.context)]),
    )
end

function suggestion_record(suggestion)
    return (;
        code = suggestion.code,
        severity = suggestion.severity,
        action = suggestion.action,
        message = suggestion.message,
        suggestion = suggestion.suggestion,
        context_keys = sort([String(key) for key in keys(suggestion.context)]),
    )
end

function issue_count_rows(report)
    codes = sort(unique(issue.code for issue in report.issues); by = string)
    return [
        (code = code,
            n = count(issue -> issue.code === code, report.issues),
            severity = first(issue.severity for issue in report.issues
                if issue.code === code))
        for code in codes
    ]
end

function facet_count_rows(report)
    rows = NamedTuple[]
    for facet in sort(collect(keys(report.facet_counts)); by = string)
        counts = report.facet_counts[facet]
        for level in sort(collect(keys(counts)); by = string)
            push!(rows, (; facet, level, n = counts[level]))
        end
    end
    return rows
end

function category_count_rows(report)
    return [
        (category = category, n = report.category_counts[category])
        for category in sort(collect(keys(report.category_counts)))
    ]
end

function dff_cell_count_rows(report)
    rows = NamedTuple[]
    for term in sort(collect(keys(report.dff_counts)); by = string)
        left, right = term
        counts = report.dff_counts[term]
        for ((left_level, right_level), n) in sort(collect(counts); by = string)
            push!(rows, (;
                left_facet = left,
                right_facet = right,
                left_level,
                right_level,
                n,
            ))
        end
    end
    return rows
end

function term_support(term, counts, min_cell_count::Int)
    cell_counts = collect(values(counts))
    positive = [n for n in cell_counts if n > 0]
    n_empty = count(==(0), cell_counts)
    n_sparse = count(n -> 0 < n < min_cell_count, cell_counts)
    support = n_empty > 0 ?
        :not_unpooled_estimable :
        n_sparse > 0 ?
        :sparse_screening_only :
        :screening_supported
    return (;
        term,
        n_cells = length(cell_counts),
        n_empty_cells = n_empty,
        n_sparse_cells = n_sparse,
        minimum_cell_count = isempty(cell_counts) ? 0 : minimum(cell_counts),
        minimum_positive_cell_count = isempty(positive) ? 0 : minimum(positive),
        maximum_cell_count = isempty(cell_counts) ? 0 : maximum(cell_counts),
        support,
    )
end

function term_support_rows(report, min_cell_count::Int)
    return [
        term_support(term, report.dff_counts[term], min_cell_count)
        for term in sort(collect(keys(report.dff_counts)); by = string)
    ]
end

function spec_constraint_record(data, report)
    report.passed || return (;
        spec_constructed = false,
        validation_only_blocks = Symbol[],
        retained_bias_terms = Tuple{Symbol,Symbol}[],
        all_dff_terms_validation_only = false,
    )
    spec = BayesianMGMFRM.mfrm_spec(
        data;
        thresholds = :partial_credit,
        validation_report = report,
    )
    constraints = BayesianMGMFRM.constraint_table(spec)
    validation_only = [
        row for row in constraints
        if haskey(row, :status) && row.status === :validation_only
    ]
    expected_blocks = [
        Symbol("dff_", term[1], "_", term[2])
        for term in sort(collect(keys(report.dff_counts)); by = string)
    ]
    observed_blocks = [row.block for row in validation_only]
    return (;
        spec_constructed = true,
        validation_only_blocks = observed_blocks,
        retained_bias_terms = copy(spec.validation_bias_terms),
        all_dff_terms_validation_only =
            Set(observed_blocks) == Set(expected_blocks),
    )
end

function support_matches(expected_support::Symbol, rows)
    expected_support === :invalid_request_rejected && return isempty(rows)
    supports = Set(row.support for row in rows)
    expected_support === :screening_supported &&
        return supports == Set([:screening_supported])
    expected_support === :sparse_screening_only &&
        return :sparse_screening_only in supports
    expected_support === :not_unpooled_estimable &&
        return :not_unpooled_estimable in supports
    return false
end

function scenario_record(spec)
    data = facet_data_for_scenario(spec)
    report = BayesianMGMFRM.validate_design(
        data;
        bias = collect(spec.bias_terms),
        min_cell_count = PROTOCOL.min_cell_count,
    )
    issue_codes = Set(issue.code for issue in report.issues)
    expected_codes = Set(spec.expected_issue_codes)
    term_support = term_support_rows(report, PROTOCOL.min_cell_count)
    constraints = spec_constraint_record(data, report)
    outcome_matches =
        report.passed == spec.expected_passed &&
        issue_codes == expected_codes &&
        support_matches(spec.expected_support, term_support)
    validation_only_ok =
        report.passed ?
        constraints.all_dff_terms_validation_only :
        !constraints.spec_constructed
    passed = outcome_matches && validation_only_ok
    return (;
        scenario = spec.scenario,
        pattern = spec.pattern,
        with_group = spec.with_group,
        bias_terms = spec.bias_terms,
        expected_passed = spec.expected_passed,
        expected_issue_codes = spec.expected_issue_codes,
        expected_support = spec.expected_support,
        data_summary = (;
            n_observations = data.n,
            n_persons = length(data.person_levels),
            n_raters = length(data.rater_levels),
            n_items = length(data.item_levels),
            n_categories = length(data.category_levels),
            optional_facets = sort(collect(keys(data.optional)); by = string),
            category_counts = category_count_rows(report),
            facet_counts = facet_count_rows(report),
        ),
        validation = (;
            passed = report.passed,
            n_issues = length(report.issues),
            n_errors = count(issue -> issue.severity === :error, report.issues),
            n_warnings = count(issue -> issue.severity === :warning, report.issues),
            issue_counts = issue_count_rows(report),
            issues = [issue_record(issue) for issue in report.issues],
            suggestions = [
                suggestion_record(suggestion)
                for suggestion in BayesianMGMFRM.validation_suggestions(report)
            ],
        ),
        dff_cell_counts = dff_cell_count_rows(report),
        term_support,
        spec_constraints = constraints,
        summary = (;
            passed,
            outcome_matches,
            validation_only_ok,
            validation_passed = report.passed,
            n_errors = count(issue -> issue.severity === :error, report.issues),
            n_warnings = count(issue -> issue.severity === :warning, report.issues),
            n_dff_terms = length(keys(report.dff_counts)),
            n_empty_terms =
                count(row -> row.support === :not_unpooled_estimable,
                    term_support),
            n_sparse_terms =
                count(row -> row.support === :sparse_screening_only,
                    term_support),
            spec_constructed = constraints.spec_constructed,
            all_dff_terms_validation_only =
                constraints.all_dff_terms_validation_only,
        ),
    )
end

function dff_artifact()
    scenarios = [scenario_record(spec) for spec in SCENARIOS]
    passed = all(scenario -> scenario.summary.passed, scenarios)
    valid_scenarios = [
        scenario for scenario in scenarios
        if scenario.summary.validation_passed
    ]
    return (;
        schema = "bayesianmgmfrm.gmfrm_dff_estimand_validation_grid.v1",
        family = :gmfrm,
        scope = :dff_estimand_and_validation_grid,
        status = :dff_estimand_validation_grid_recorded,
        decision = :keep_dff_validation_only,
        public_fit = false,
        experimental_public = false,
        fit_ready = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = PROTOCOL,
        reviewed_artifacts = [
            fixture_reference(
                "test/fixtures/gmfrm_guarded_exposure_review.json";
                hash_policy = :existence_only_avoids_guarded_review_dff_cycle,
            ),
            fixture_reference(
                "test/fixtures/gmfrm_broader_experimental_exposure_decision_review.json";
                hash_policy = :existence_only_avoids_broader_review_dff_cycle,
            ),
            fixture_reference("test/fixtures/mgmfrm_sparse_recovery_grid.json"),
        ],
        estimand_rows = ESTIMANDS,
        scenario_rows = scenarios,
        decision_record = (;
            selected_decision = :keep_validation_only,
            dff_model_effects_allowed = false,
            public_fit_allowed = false,
            experimental_keyword_enabled = false,
            public_exposure_support =
                :dff_estimands_predeclared_validation_only,
            interpretation =
                :dff_estimand_validation_grid_recorded_keep_model_effects_blocked,
            required_followup = :manuscript_scale_simulation_grid,
        ),
        summary = (;
            passed,
            publication_or_registration_action = false,
            local_only = true,
            n_estimands = length(ESTIMANDS),
            n_predeclared_reporting_scales =
                length(unique(vcat([collect(row.reporting_scales)
                    for row in ESTIMANDS]...))),
            n_scenarios = length(scenarios),
            n_passed_scenarios =
                count(scenario -> scenario.summary.passed, scenarios),
            n_validation_passed_scenarios = length(valid_scenarios),
            n_validation_error_scenarios =
                count(scenario -> scenario.summary.n_errors > 0, scenarios),
            n_sparse_warning_scenarios =
                count(scenario -> any(
                        row -> row.code === :sparse_dff_cell,
                        scenario.validation.issue_counts),
                    scenarios),
            n_empty_warning_scenarios =
                count(scenario -> any(
                        row -> row.code === :empty_dff_cell,
                        scenario.validation.issue_counts),
                    scenarios),
            n_confounding_warning_scenarios =
                count(scenario -> any(
                        row -> row.code === :potential_dff_confounding,
                        scenario.validation.issue_counts),
                    scenarios),
            all_expected_outcomes_matched =
                all(scenario -> scenario.summary.outcome_matches, scenarios),
            all_valid_dff_terms_retained_as_validation_only =
                all(scenario -> scenario.summary.all_dff_terms_validation_only,
                    valid_scenarios),
            all_estimands_predeclared = length(ESTIMANDS) >= 5,
            all_reporting_scales_predeclared =
                all(row -> :logit in row.reporting_scales &&
                    :expected_score in row.reporting_scales,
                    ESTIMANDS),
            dff_model_effects_allowed = false,
            public_fit_allowed = false,
            experimental_keyword_enabled = false,
            remaining_public_blockers = [
                :manuscript_scale_simulation_grid_missing,
                :full_paper_reproduction_archive_missing,
            ],
            recommendation =
                :keep_dff_validation_only_until_gate_e_and_archive_evidence,
            next_gate = :manuscript_scale_simulation_grid,
        ),
    )
end

function main(args)
    output = parse_args(args)
    artifact = dff_artifact()
    write_artifact(output, artifact)
    println("wrote ", relpath(output, ROOT))
    println("passed=", artifact.summary.passed,
        " scenarios=", artifact.summary.n_scenarios,
        " next_gate=", artifact.summary.next_gate)
    return nothing
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main(ARGS)
end
