#!/usr/bin/env julia

using Random
using SHA
using Statistics
using TOML

import BayesianMGMFRM

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_tam_overlap_baseline.json",
)
const DEFAULT_CSV_OUTPUT = joinpath(
    ROOT,
    "test",
    "fixtures",
    "mgmfrm_tam_overlap_baseline.csv",
)
const BASE_SEED = 20260711
const ORACLE_TOLERANCE = 1.0e-12

include(joinpath(@__DIR__, "local_json.jl"))

const TAM_REFERENCE_RECORDS = [
    (;
        citation_key = :tam_cran_package,
        source = :cran,
        title = "TAM: Test Analysis Modules",
        url = "https://cran.r-project.org/package=TAM",
        package = "TAM",
    ),
    (;
        citation_key = :tam_mml_reference,
        source = :pkgdown,
        title = "Test Analysis Modules: Marginal Maximum Likelihood Estimation",
        url = "https://alexanderrobitzsch.github.io/TAM/reference/tam.mml.html",
        function_name = "tam.mml.mfr",
    ),
    (;
        citation_key = :tam_simulated_multifaceted_data,
        source = :rdrr,
        title = "data.sim.mfr: Simulated Multifaceted Data",
        url = "https://rdrr.io/cran/TAM/man/data.sim.mfr.html",
        function_name = "tam.mml.mfr",
    ),
]

function usage()
    return """
    Generate the TAM overlap baseline fixture and long-format CSV.

    The fixture materializes a deterministic known-truth many-facet Rasch
    partial-credit baseline that is intended to overlap with TAM::tam.mml.mfr.
    It does not run R, install TAM, compare estimates, approve external
    validation claims, publish, register, push, or upload.

    Usage:
      julia --project=. scripts/generate_mgmfrm_tam_overlap_baseline.jl [--output PATH] [--csv-output PATH]
    """
end

function parse_args(args)
    output = DEFAULT_OUTPUT
    csv_output = DEFAULT_CSV_OUTPUT
    index = 1
    while index <= length(args)
        arg = args[index]
        if arg == "--output"
            index < length(args) || error("--output requires a path")
            output = abspath(args[index + 1])
            index += 2
        elseif arg == "--csv-output"
            index < length(args) || error("--csv-output requires a path")
            csv_output = abspath(args[index + 1])
            index += 2
        elseif arg in ("-h", "--help")
            println(usage())
            exit(0)
        else
            error("unknown argument: $arg")
        end
    end
    return (; output, csv_output)
end

project_version() =
    String(TOML.parsefile(joinpath(ROOT, "Project.toml"))["version"])

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function canonical_json_sha256(value)
    io = IOBuffer()
    write_json(io, value)
    return bytes2hex(sha256(take!(io)))
end

matrix_rows(matrix::AbstractMatrix) = [
    [matrix[row, column] for column in axes(matrix, 2)]
    for row in axes(matrix, 1)
]

function centered(values)
    output = collect(Float64, values)
    output .-= mean(output)
    return output
end

function softmax(values)
    shifted = values .- maximum(values)
    weights = exp.(shifted)
    return weights ./ sum(weights)
end

function item_step_matrix(rng::AbstractRNG, n_items::Int, categories::Int)
    kminus1 = categories - 1
    free_steps = max(kminus1 - 1, 0)
    steps = zeros(Float64, n_items, kminus1)
    for item in 1:n_items
        for step in 1:free_steps
            steps[item, step] = 0.35 * randn(rng)
        end
        free_steps > 0 && (steps[item, kminus1] = -sum(@view steps[item, 1:free_steps]))
    end
    return steps
end

function full_cross_columns(n_persons::Int, n_raters::Int, n_items::Int;
        scores = nothing, categories::Int)
    person = Int[]
    rater = Int[]
    item = Int[]
    score = Int[]
    row = 0
    for person_index in 1:n_persons,
            rater_index in 1:n_raters,
            item_index in 1:n_items
        row += 1
        push!(person, person_index)
        push!(rater, rater_index)
        push!(item, item_index)
        push!(score, scores === nothing ? mod(row - 1, categories) : Int(scores[row]))
    end
    return (; person, rater, item, score)
end

function facet_data(columns)
    return BayesianMGMFRM.FacetData((;
            examinee = columns.person,
            rater = columns.rater,
            item = columns.item,
            score = columns.score,
        );
        person = :examinee,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

function tam_overlap_truth(rng::AbstractRNG, n_persons::Int, n_raters::Int,
        n_items::Int, categories::Int)
    rater_severity = [0.0; centered(randn(rng, n_raters - 1))]
    item_difficulty = [0.0; centered(randn(rng, n_items - 1))]
    return (;
        person_ability = randn(rng, n_persons),
        rater_severity,
        item_difficulty,
        item_steps = item_step_matrix(rng, n_items, categories),
    )
end

function mfrm_probability(truth, person::Int, rater::Int, item::Int,
        categories::Int)
    location = truth.person_ability[person] - truth.rater_severity[rater] -
        truth.item_difficulty[item]
    eta = zeros(Float64, categories)
    step_sum = 0.0
    for category in 1:categories
        if category > 1
            step_sum += truth.item_steps[item, category - 1]
        end
        eta[category] = (category - 1) * location - step_sum
    end
    return softmax(eta)
end

function sample_score(rng::AbstractRNG, probabilities, category_levels)
    draw = rand(rng)
    cumulative = 0.0
    for category in eachindex(probabilities)
        cumulative += probabilities[category]
        draw <= cumulative && return category_levels[category]
    end
    return last(category_levels)
end

function mfrm_direct_params(design, truth)
    params = zeros(Float64, length(design.parameter_names))
    data = design.spec.data
    for (index, level) in pairs(data.person_levels)
        params[design.blocks[:person][index]] = truth.person_ability[Int(level)]
    end
    for (index, level) in pairs(data.rater_levels)
        index == 1 && continue
        params[design.blocks[:rater][index - 1]] = truth.rater_severity[Int(level)]
    end
    for (index, level) in pairs(data.item_levels)
        index == 1 && continue
        params[design.blocks[:item][index - 1]] = truth.item_difficulty[Int(level)]
    end
    free_steps = max(length(data.category_levels) - 2, 0)
    for item in eachindex(data.item_levels), step in 1:free_steps
        offset = (item - 1) * free_steps
        params[design.blocks[:thresholds][offset + step]] =
            truth.item_steps[item, step]
    end
    return params
end

function oracle_probability_matrix(design, direct_params)
    probabilities = BayesianMGMFRM.predictive_probabilities(
        design,
        reshape(direct_params, 1, :),
    )
    return dropdims(probabilities; dims = 1)
end

function probability_check_rows(columns, independent, oracle)
    indices = unique([1, cld(length(columns.person), 2), length(columns.person)])
    return [(;
        row,
        person = columns.person[row],
        rater = columns.rater[row],
        item = columns.item[row],
        independent_generator_probabilities = vec(independent[row, :]),
        package_mfrm_oracle_probabilities = vec(oracle[row, :]),
        max_abs_error = maximum(abs.(independent[row, :] .- oracle[row, :])),
    ) for row in indices]
end

function category_count_rows(scores, category_levels)
    return [(; category, count = count(==(category), scores))
        for category in category_levels]
end

function observation_sha256(columns)
    io = IOBuffer()
    println(io, "person,rater,item,score")
    for row in eachindex(columns.person)
        println(io, columns.person[row], ',', columns.rater[row], ',',
            columns.item[row], ',', columns.score[row])
    end
    return bytes2hex(sha256(take!(io)))
end

function write_tam_csv(path::AbstractString, columns)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "person,rater,item,score")
        for row in eachindex(columns.person)
            println(io, columns.person[row], ',', columns.rater[row], ',',
                columns.item[row], ',', columns.score[row])
        end
    end
    return path
end

function tam_runner_template(csv_relpath::AbstractString)
    return [
        "library(TAM)",
        "dat <- read.csv(\"$csv_relpath\")",
        "resp <- data.frame(score = dat\$score)",
        "facets <- data.frame(item = factor(dat\$item), rater = factor(dat\$rater))",
        "pid <- dat\$person",
        "formulaA <- ~ item + rater + item:step",
        "fit <- TAM::tam.mml.mfr(resp = resp, facets = facets, pid = pid, formulaA = formulaA, constraint = \"cases\", verbose = FALSE)",
        "saveRDS(fit, \"mgmfrm_tam_overlap_baseline_fit.rds\")",
    ]
end

function build_artifact(csv_output::AbstractString)
    truth_seed = BASE_SEED + 1000 + 1
    response_seed = BASE_SEED + 1000 + 3
    n_persons, n_items, n_raters, categories = 40, 5, 4, 4
    category_levels = collect(0:(categories - 1))
    truth_rng = MersenneTwister(truth_seed)
    response_rng = MersenneTwister(response_seed)
    truth = tam_overlap_truth(truth_rng, n_persons, n_raters, n_items, categories)
    dummy = full_cross_columns(n_persons, n_raters, n_items; categories)
    independent = zeros(Float64, length(dummy.person), categories)
    for row in eachindex(dummy.person)
        independent[row, :] = mfrm_probability(
            truth,
            dummy.person[row],
            dummy.rater[row],
            dummy.item[row],
            categories,
        )
    end
    spec = BayesianMGMFRM.mfrm_spec(facet_data(dummy); thresholds = :partial_credit)
    design = BayesianMGMFRM.getdesign(spec)
    direct_params = mfrm_direct_params(design, truth)
    oracle = oracle_probability_matrix(design, direct_params)
    oracle_error = maximum(abs.(independent .- oracle))
    oracle_error <= ORACLE_TOLERANCE ||
        error("standalone TAM-overlap MFRM generator disagrees with package oracle: $oracle_error")
    scores = [sample_score(response_rng, @view(independent[row, :]), category_levels)
        for row in axes(independent, 1)]
    observations = full_cross_columns(n_persons, n_raters, n_items;
        scores,
        categories,
    )
    counts = category_count_rows(scores, category_levels)
    all(row -> row.count > 0, counts) ||
        error("TAM overlap pilot did not realize every category")
    write_tam_csv(csv_output, observations)
    truth_record = (;
        person_ability = truth.person_ability,
        rater_severity = truth.rater_severity,
        item_difficulty = truth.item_difficulty,
        item_steps = matrix_rows(truth.item_steps),
    )
    csv_relpath = relpath(csv_output, ROOT)
    return (;
        schema = "bayesianmgmfrm.mgmfrm_tam_overlap_baseline.v1",
        family = :mfrm,
        scope = :tam_overlap_baseline,
        status = :tam_overlap_dataset_prepared,
        decision = :prepare_tam_overlap_baseline_do_not_claim_validation,
        local_only = true,
        synthetic_data_only = true,
        external_software = :tam,
        external_software_validation_completed = false,
        tam_execution_completed = false,
        parameter_comparison_completed = false,
        public_claim_release_allowed = false,
        publication_or_registration_action = false,
        package = (;
            name = "BayesianMGMFRM",
            version = project_version(),
            julia_version = string(VERSION),
        ),
        protocol = (;
            protocol_id = :mgmfrm_tam_overlap_baseline_v1,
            generator = :standalone_mfrm_overlap_generator,
            generator_independence_scope =
                :response_sampling_does_not_call_package_probability_or_simulation_helpers,
            package_oracle_checked_before_write = true,
            generator_source = "scripts/generate_mgmfrm_tam_overlap_baseline.jl",
            generator_source_sha256 = file_sha256(@__FILE__),
            rng = :Random_MersenneTwister,
            base_seed = BASE_SEED,
            truth_seed,
            response_seed,
        ),
        reference_records = TAM_REFERENCE_RECORDS,
        overlap_target = (;
            software = :tam,
            r_package = "TAM",
            target_function = "TAM::tam.mml.mfr",
            target_model = :many_facet_rasch_partial_credit,
            tam_formulaA = "~ item + rater + item:step",
            tam_constraint = "cases",
            response_format = :single_column_long_response_with_pid_and_facets,
            package_family = :mfrm,
            package_thresholds = :partial_credit,
            excluded_from_overlap = [
                :item_discrimination,
                :rater_consistency,
                :multidimensional_loading,
                :free_latent_correlation,
                :construct_validity_claim,
            ],
        ),
        design = (;
            n_persons,
            n_items,
            n_raters,
            n_dimensions = 1,
            category_levels,
            assignment = :fully_crossed,
            n_observations = length(scores),
        ),
        equation = (;
            implementation = :standalone_adjacent_category_softmax,
            location = :person_ability_minus_rater_severity_minus_item_difficulty,
            adjacent_increment =
                :location_minus_item_partial_credit_step_under_unit_discrimination,
            item_discrimination = 1.0,
            rater_consistency = 1.0,
            package_generator_called = false,
        ),
        parameter_generation = [
            (block = :person_ability, draw = :normal_0_1,
                transform = :none, tam_overlap_role = :latent_distribution),
            (block = :rater_severity, draw = :normal_0_1,
                transform = :first_rater_reference_zero,
                tam_overlap_role = :rater_facet),
            (block = :item_difficulty, draw = :normal_0_1,
                transform = :first_item_reference_zero,
                tam_overlap_role = :item_facet),
            (block = :item_steps_free, draw = :normal_0_0_35,
                transform = :final_step_negative_free_sum_by_item,
                tam_overlap_role = :item_step_interaction),
        ],
        truth = truth_record,
        observations,
        tam_export = (;
            path = csv_relpath,
            format = :csv_header_then_integer_rows_lf,
            sha256 = file_sha256(csv_output),
            columns = [:person, :rater, :item, :score],
            person_column = :person,
            response_column = :score,
            facet_columns = [:item, :rater],
            runner_template = tam_runner_template(csv_relpath),
            runner_template_status = :not_executed,
        ),
        checksums = (;
            observations_sha256 = observation_sha256(observations),
            truth_canonical_format = :local_json_compact_named_record,
            truth_sha256 = canonical_json_sha256(truth_record),
        ),
        generator_checks = (;
            package_oracle = :predictive_probabilities_mfrm_partial_credit,
            tolerance = ORACLE_TOLERANCE,
            max_abs_probability_error = oracle_error,
            selected_rows = probability_check_rows(dummy, independent, oracle),
        ),
        claim_limits = [
            :tam_export_prepared_not_executed,
            :no_tam_parameter_estimate_comparison,
            :no_facets_or_conquest_comparison,
            :no_generalized_gmfrm_or_mgmfrm_overlap_claim,
            :no_external_construct_validity_claim,
            :no_public_claim_release,
        ],
        summary = (;
            passed = oracle_error <= ORACLE_TOLERANCE &&
                all(row -> row.count > 0, counts),
            n_reference_records = length(TAM_REFERENCE_RECORDS),
            n_observations = length(scores),
            category_counts = counts,
            all_categories_observed = all(row -> row.count > 0, counts),
            tam_csv_written = true,
            tam_csv_sha256 = file_sha256(csv_output),
            tam_execution_completed = false,
            external_software_validation_completed = false,
            public_claim_release_allowed = false,
            next_gate = :run_tam_mml_mfr_and_compare_parameter_table_under_recorded_adapter,
        ),
    )
end

function main(args)
    parsed = parse_args(args)
    artifact = build_artifact(parsed.csv_output)
    write_artifact(parsed.output, artifact)
    println("wrote ", relpath(parsed.output, ROOT))
    println("wrote ", relpath(parsed.csv_output, ROOT))
    println(
        "passed=", artifact.summary.passed,
        " observations=", artifact.summary.n_observations,
        " tam_run=", artifact.summary.tam_execution_completed,
    )
    return nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
