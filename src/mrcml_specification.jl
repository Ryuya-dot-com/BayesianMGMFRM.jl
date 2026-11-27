# Included inside AdditiveFacets; no new module or saved type is introduced.
# Follow inputs -> coordinate blocks -> priors -> response operator -> specification.
include("mrcml_specification/inputs.jl")
include("mrcml_specification/blocks.jl")
include("mrcml_specification/finalize.jl")

function compile_structured_mrcml(table;
        person::Symbol = :person,
        score::Symbol = :score,
        facets::NamedTuple,
        steps = :global,
        prior_sd = nothing,
        default_prior::Bool = false,
        category_levels,
        levels = nothing,
        interactions = nothing,
        context_facets = nothing,
        random_effects = (;),
        lltm = nothing,
        fixed_calibration = nothing,
        calibration = nothing,
        intercept = nothing,
        performance::Union{Nothing,Symbol} = nothing,
        assessment::Union{Nothing,Symbol} = nothing,
        missing_audit = nothing)
    inputs = _prepare_structured_mrcml(table, (;
        person, score, facets, steps, prior_sd, default_prior, category_levels, levels,
        interactions, context_facets, random_effects, lltm, fixed_calibration, calibration,
        intercept, performance, assessment, missing_audit,
    ))

    # Block order fixes parameter names, raw ranges and the saved coordinate layout.
    layout = _build_mrcml_facet_layout!(inputs)
    layout = _append_mrcml_steps!(layout, inputs)
    layout = _append_mrcml_interactions!(layout, inputs)
    layout = _complete_mrcml_prior_layout!(layout, inputs)

    operator = _build_mrcml_response_operator(inputs, layout)
    return _finish_structured_mrcml(inputs, layout, operator)
end
