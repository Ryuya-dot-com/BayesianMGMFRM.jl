#!/usr/bin/env julia

# Generate a deterministic validation-plan artifact from the public
# simulation-grid and falsification-rule contracts. This does not run
# simulations or fit models; it records the predeclared plan that a later
# manuscript-scale evidence job must execute.

using Pkg
using SHA

const ROOT = abspath(normpath(joinpath(@__DIR__, "..")))
Pkg.activate(ROOT; io = devnull)

using BayesianMGMFRM

function usage()
    return """
    Usage:
      julia --project=. scripts/generate_validation_plan.jl [options]

    Options:
      --preset smoke|manuscript    Validation grid preset (default: smoke)
      --grid-id ID                 Grid identifier recorded in rows
      --base-seed SEED             First deterministic row seed
      --include-rows               Include every grid row in the artifact
      --output PATH                Write artifact to PATH instead of stdout
      --help                       Print this help text
    """
end

function take_option!(args::Vector{String}, name::String, default::String)
    index = findfirst(==(name), args)
    index === nothing && return default
    index == length(args) &&
        error("missing value after $name")
    value = args[index + 1]
    deleteat!(args, index:(index + 1))
    return value
end

function take_flag!(args::Vector{String}, name::String)
    index = findfirst(==(name), args)
    index === nothing && return false
    deleteat!(args, index)
    return true
end

function parse_args(raw_args)
    args = collect(String, raw_args)
    if take_flag!(args, "--help")
        print(usage())
        exit(0)
    end
    include_rows = take_flag!(args, "--include-rows")
    preset = take_option!(args, "--preset", "smoke")
    grid_id = take_option!(args, "--grid-id", preset * "-validation-plan")
    base_seed_text = take_option!(args, "--base-seed", "20260620")
    output = take_option!(args, "--output", "")
    isempty(args) || error("unknown argument(s): " * join(args, ", "))
    return (;
        preset = Symbol(preset),
        grid_id,
        base_seed = parse(Int, base_seed_text),
        include_rows,
        output,
    )
end

function preset_controls(preset::Symbol, grid_id::AbstractString, base_seed::Int)
    if preset === :smoke
        return (;
            preset,
            grid_id = String(grid_id),
            base_seed,
            densities = (:sparse, :near_complete),
            anchor_sizes = (0, 2),
            ratings_per_target = (1, 3),
            category_pathologies = (:none, :skipped_middle),
            rater_noise = (:low, :high),
            dff = (:none, :rater_by_group),
            dimensionalities = (1, 2),
            misspecifications = (:none, :omitted_dff),
            repetitions = 1,
            n_persons = 24,
            n_items = 6,
            n_raters = 3,
            n_categories = 4,
        )
    elseif preset === :manuscript
        return (;
            preset,
            grid_id = String(grid_id),
            base_seed,
            densities = (:sparse, :moderate, :near_complete),
            anchor_sizes = (0, 2, 5),
            ratings_per_target = (1, 2, 4),
            category_pathologies = (:none, :skipped_middle, :top_set),
            rater_noise = (:low, :moderate, :high),
            dff = (:none, :rater_by_group),
            dimensionalities = (1, 2),
            misspecifications = (:none, :wrong_thresholds, :omitted_dff),
            repetitions = 2,
            n_persons = 96,
            n_items = 18,
            n_raters = 6,
            n_categories = 4,
        )
    end
    error("unknown preset: $preset")
end

function build_grid(controls)
    return simulation_grid(;
        densities = controls.densities,
        anchor_sizes = controls.anchor_sizes,
        ratings_per_target = controls.ratings_per_target,
        category_pathologies = controls.category_pathologies,
        rater_noise = controls.rater_noise,
        dff = controls.dff,
        dimensionalities = controls.dimensionalities,
        misspecifications = controls.misspecifications,
        repetitions = controls.repetitions,
        base_seed = controls.base_seed,
        grid_id = controls.grid_id,
        n_persons = controls.n_persons,
        n_items = controls.n_items,
        n_raters = controls.n_raters,
        n_categories = controls.n_categories,
    )
end

function grid_samples(rows)
    isempty(rows) && return NamedTuple[]
    indices = unique([1, min(length(rows), 2), max(1, length(rows) - 1), length(rows)])
    return [rows[index] for index in indices]
end

function compact_rule_rows(rules)
    return [(;
        rule_index = row.rule_index,
        rule_id = row.rule_id,
        domain = row.domain,
        metric = row.metric,
        fail_if = row.fail_if,
        threshold = row.threshold,
        required_evidence = row.required_evidence,
        action_if_triggered = row.action_if_triggered,
    ) for row in rules]
end

function build_artifact(controls; include_rows::Bool = false)
    rows = build_grid(controls)
    grid_summary = simulation_grid_summary(rows)
    rules = falsification_rules()
    rule_summary = falsification_rule_summary(rules)
    artifact = (;
        schema = "bayesianmgmfrm.validation_plan_artifact.v1",
        object = :validation_plan_artifact,
        generator = (;
            script = "scripts/generate_validation_plan.jl",
            package = :BayesianMGMFRM,
            deterministic = true,
        ),
        controls,
        simulation_grid = (;
            row_schema = "bayesianmgmfrm.simulation_grid.v1",
            summary = grid_summary,
            row_samples = grid_samples(rows),
            rows = include_rows ? rows : nothing,
            row_policy = include_rows ? :included : :omitted_regenerable_from_controls,
        ),
        falsification = (;
            rule_schema = "bayesianmgmfrm.falsification_rule.v1",
            summary = rule_summary,
            rules = compact_rule_rows(rules),
        ),
        execution_policy = (;
            runs_simulations = false,
            fits_models = false,
            evaluates_claims = false,
            next_gate = :run_predeclared_grid_and_apply_falsification_rules,
        ),
    )
    payload = json(artifact)
    return merge(artifact, (content_hash = (;
        algorithm = :sha256,
        value = bytes2hex(sha256(payload)),
        covers = :artifact_without_content_hash,
    ),))
end

function json_string(value::AbstractString)
    out = IOBuffer()
    print(out, '"')
    for char in value
        if char == '\\'
            print(out, "\\\\")
        elseif char == '"'
            print(out, "\\\"")
        elseif char == '\n'
            print(out, "\\n")
        elseif char == '\r'
            print(out, "\\r")
        elseif char == '\t'
            print(out, "\\t")
        else
            print(out, char)
        end
    end
    print(out, '"')
    return String(take!(out))
end

json(value::Symbol) = json_string(String(value))
json(value::AbstractString) = json_string(value)
json(value::Integer) = string(value)
json(value::AbstractFloat) = isfinite(value) ? string(value) : "null"
json(value::Bool) = value ? "true" : "false"
json(::Nothing) = "null"
json(::Missing) = "null"

function json(value::NamedTuple)
    fields = String[]
    for name in keys(value)
        push!(fields, json_string(String(name)) * ":" * json(getproperty(value, name)))
    end
    return "{" * join(fields, ",") * "}"
end

function json(value::AbstractDict)
    fields = String[]
    for key in sort!(collect(keys(value)); by = string)
        push!(fields, json_string(String(key)) * ":" * json(value[key]))
    end
    return "{" * join(fields, ",") * "}"
end

function json(value)
    if value isa AbstractVector || value isa Tuple
        return "[" * join((json(entry) for entry in value), ",") * "]"
    end
    error("cannot encode value of type $(typeof(value)) as JSON")
end

function main()
    options = parse_args(ARGS)
    controls = preset_controls(options.preset, options.grid_id, options.base_seed)
    artifact = build_artifact(controls; include_rows = options.include_rows)
    payload = json(artifact) * "\n"
    if isempty(options.output)
        print(payload)
    else
        output = abspath(options.output)
        mkpath(dirname(output))
        write(output, payload)
    end
    return nothing
end

main()
