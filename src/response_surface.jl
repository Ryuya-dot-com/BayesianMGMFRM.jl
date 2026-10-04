"""
    BayesianMGMFRM.item_response_surface(fit::MGMFRMFit; item, rater,
        dimensions = (1, 2), x = range(-3, 3; length = 41),
        y = range(-3, 3; length = 41), fixed_abilities = Dict(),
        category = :all, interval = 0.9, draw_indices = nothing)

Summarize a conditional item response surface from an existing independent
fixed-Q MGMFRM fit, without fitting or requiring a renderer. Select item and
rater by their stored labels. The two ability dimensions accept indices or
stored labels; specify every remaining dimension in `fixed_abilities`.
Axes are abilities on the fitted model's scale, not estimated person scores.

By default, `category = :all` returns response probabilities for all stored
category values. With `category = nothing`, the surface is the expected rating
using the actual numeric category levels. A stored category value instead
selects its response probability. Each grid point is evaluated for every selected joint posterior
draw before taking its mean and central credible interval. These intervals
describe uncertainty in a probability or conditional expectation, not in an
individual future rating, and are pointwise rather than simultaneous bands.
No averaging over raters, ability populations, or unplotted dimensions occurs.

The result contains `x`, `y`, `mean`, `lower`, `upper`, `interval_width`, labels,
selection metadata and the whole-fit diagnostic note. Arrays use `[x,y,k]`
indexing for `:all`, with `k` indexing `category_levels`, and `[x,y]` otherwise.
All retained draws are used unless unique `draw_indices` are supplied;
the indices are retained in the result. No random subsampling occurs. The
default ability range is a display choice, not evidence of data support there.
This qualified, unexported entry point retains MGMFRM's experimental status.
"""
function item_response_surface(fit::MGMFRMFit; item, rater, dimensions = (1, 2),
        x = range(-3, 3; length = 41), y = range(-3, 3; length = 41),
        fixed_abilities = Dict(), category = :all, interval::Real = 0.9,
        draw_indices = nothing)
    lower_p, upper_p = _interval_probabilities(interval)
    spec, design = fit.design.spec, fit.design
    data = spec.data
    labels = spec.dimension_labels
    dimension_index(value) = begin
        index = value isa Integer && !(value isa Bool) ? Int(value) :
            value isa Union{AbstractString,Symbol} ? findfirst(==(string(value)), string.(labels)) : nothing
        index !== nothing && 1 <= index <= spec.dimensions ||
            throw(ArgumentError("unknown ability dimension: $value"))
        index
    end
    length(dimensions) == 2 || throw(ArgumentError("select exactly two ability dimensions"))
    dims = dimension_index.(collect(dimensions))
    allunique(dims) || throw(ArgumentError("ability dimensions must differ"))
    function grid(values)
        values = collect(values)
        length(values) >= 2 && all(v -> v isa Real && !(v isa Bool) && isfinite(v), values) ||
            throw(ArgumentError("ability grids need at least two finite real values"))
        result = Float64.(values)
        all(isfinite, result) && all(>(0), diff(result)) ||
            throw(ArgumentError("ability grids must be finite and strictly increasing"))
        result
    end
    xs, ys = grid(x), grid(y)
    fixed = Dict{Int,Float64}()
    for (dimension, value) in pairs(fixed_abilities)
        d = dimension_index(dimension)
        d ∉ dims && !haskey(fixed, d) || throw(ArgumentError("duplicate or plotted fixed ability dimension"))
        value isa Real && !(value isa Bool) && isfinite(value) && isfinite(Float64(value)) ||
            throw(ArgumentError("fixed abilities must be finite real values"))
        fixed[d] = Float64(value)
    end
    Set(keys(fixed)) == setdiff(Set(1:spec.dimensions), Set(dims)) ||
        throw(ArgumentError("specify every unplotted dimension in fixed_abilities"))
    item_index = findfirst(==(string(item)), string.(data.item_levels))
    rater_index = findfirst(==(string(rater)), string.(data.rater_levels))
    item_index !== nothing && rater_index !== nothing || throw(ArgumentError("unknown item or rater label"))
    category_index = category === nothing ? nothing : findfirst(==(category), data.category_levels)
    category in (nothing, :all) || (category isa Integer && !(category isa Bool) && category_index !== nothing) ||
        throw(ArgumentError("category must be :all, nothing, or a stored numeric category value"))
    selected = draw_indices === nothing ? collect(axes(fit.direct_draws, 1)) : collect(draw_indices)
    all(i -> i isa Integer && !(i isa Bool), selected) || throw(ArgumentError("draw_indices must be integers"))
    indices = _validate_draw_indices(fit, selected)
    allunique(indices) || throw(ArgumentError("draw_indices must be unique"))
    draws = _mgmfrm_direct_draws_for_prediction(design, fit.direct_draws[indices, :], "item_response_surface")
    loading_indices = _mgmfrm_source_loading_index_matrix(design)
    n, K = size(draws, 1), length(data.category_levels)
    loadings = [iszero(loading_indices[item_index, d]) ? 0.0 : draws[s, loading_indices[item_index, d]]
                for s in 1:n, d in 1:spec.dimensions]
    offsets = draws[:, design.blocks[:item][item_index]] + draws[:, design.blocks[:rater][rater_index]]
    for (d, value) in fixed
        offsets .-= loadings[:, d] .* value
    end
    scales = 1.7 .* draws[:, design.blocks[:rater_consistency][rater_index]]
    steps = [_source_step_value(design, view(draws, s, :), :item_steps, item_index, k)
             for s in 1:n, k in 1:K]
    shape = category === :all ? (length(xs), length(ys), K) : (length(xs), length(ys))
    means, lowers, uppers = (zeros(shape) for _ in 1:3)
    values, probs = zeros(n, category === :all ? K : 1), zeros(K)
    for (j, yvalue) in enumerate(ys), (i, xvalue) in enumerate(xs)
        for s in 1:n
            location = loadings[s, dims[1]] * xvalue + loadings[s, dims[2]] * yvalue - offsets[s]
            probs[1] = 0.0
            for k in 2:K
                probs[k] = probs[k-1] + scales[s] * (location - steps[s, k])
            end
            all(isfinite, probs) || throw(ArgumentError("nonfinite response surface logits; reduce the ability range"))
            _softmax_eta!(probs)
            if category === :all
                values[s, :] = probs
            else
                values[s, 1] = category === nothing ? dot(data.category_levels, probs) : probs[category_index]
            end
        end
        for k in axes(values, 2)
            means[i,j,k] = mean(view(values, :, k))
            lowers[i,j,k], uppers[i,j,k] = quantile(view(values, :, k), [lower_p, upper_p])
        end
    end
    fixed_rows = [(; dimension = d, label = labels[d], value = fixed[d]) for d in sort!(collect(keys(fixed)))]
    quantity_label = category === nothing ? "Expected rating" :
        category === :all ? "Category probability" : "Probability of rating $category"
    diagnostic = _plot_diagnostic_note(fit.diagnostic_surface.summary)
    return (; x = xs, y = ys, mean = means, lower = lowers, upper = uppers,
        interval_width = uppers - lowers, interval = Float64(interval),
        item = data.item_levels[item_index], rater = data.rater_levels[rater_index],
        dimensions = Tuple(dims), dimension_labels = Tuple(labels[dims]), fixed_abilities = fixed_rows,
        category, category_levels = copy(data.category_levels), quantity_label,
        active_dimensions = Tuple(Bool(spec.q_matrix[item_index, d]) for d in dims),
        draw_indices = collect(indices), n_draws = n, total_draws = size(fit.direct_draws, 1),
        diagnostic, diagnostic_flag = fit.diagnostic_surface.summary.flag)
end

"""
    BayesianMGMFRM.plot_response_surface(fit::MGMFRMFit; item, rater,
        size = nothing, azimuth = 1.275pi, elevation = pi/7, kwargs...)

Display editable 3D posterior-mean category probability wireframes, with a
fixed color and legend entry for each stored rating value. Axes use numbered
abilities (θ₁, θ₂, …), independently of stored dimension names. Companion
heatmaps show each category's pointwise central credible interval width on a
shared scale. Select a numeric `category` for one filled probability surface,
or `category = nothing` for an expected-rating surface. Load `CairoMakie` first. All
other keywords are forwarded to [`BayesianMGMFRM.item_response_surface`](@ref).
The figure retains the whole-fit diagnostic note and the selected item, rater,
dimensions, fixed abilities, interval and draw count. `azimuth` and `elevation`
control the static viewing angle in radians. Save with CairoMakie's `save`.
This does not refit, simulate future ratings, or add a report-bundle section.
"""
function plot_response_surface(fit::MGMFRMFit; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("plot_response_surface requires `using CairoMakie`"))
    extension.plot_response_surface(fit; kwargs...)
end
