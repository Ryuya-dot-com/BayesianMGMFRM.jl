"""
    BayesianMGMFRM.plot_posterior(fit; scale = :model, interval = 0.95,
        block = nothing, dimension = nothing, parameters = nothing,
        max_parameters = 60, size = nothing)

Draw posterior medians and central credible intervals from an existing MFRM,
experimental GMFRM, or experimental fixed-Q MGMFRM fit. Load `CairoMakie` first.
The returned CairoMakie `Figure` is editable and can be displayed or saved with
`save("posterior.pdf", figure)` or `save("posterior.svg", figure)`. No fitting,
random draw selection, or report construction is performed.

`:model` uses model coordinates, including derived constraints and fixed
identification values. Diamonds marked "fixed" have no credible interval.
`:raw` uses the existing `posterior_summary` coordinates; for MFRM these are
already identified model coordinates, with fixed/derived coordinates omitted.
The numerical summary functions retain their existing defaults.

Select a model `block` (such as `:person`, `:rater`, or `:item`), an MGMFRM
dimension index or label, or exact `parameters` names in the desired order.
Blocks and dimensions have separate axes. More than `max_parameters` selected
coordinates raises an error rather than silently dropping rows; select a subset
or explicitly increase the limit. `size = (width, height)` overrides automatic
figure sizing. The diagnostic note always covers the whole fit.

This optional entry point is qualified, not exported. Generalized figures
retain the experimental status of their fitted models.
"""
function plot_posterior(fit::_ModelComparisonFit; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError(
        "plot_posterior requires CairoMakie; install it with Pkg.add(\"CairoMakie\") and run `using CairoMakie`"))
    return extension.plot_posterior(fit; kwargs...)
end

function _posterior_plot_coordinates(fit::MFRMFit, scale)
    design = fit.design
    block_for = Dict(name => block for (block, indices) in design.blocks
        for name in design.parameter_names[indices])
    rows = NamedTuple[(; parameter = name, values = view(fit.draws, :, index),
        block = block_for[name], dimension = nothing, fixed = false)
        for (index, name) in enumerate(design.parameter_names)]
    scale === :raw && return rows
    for fixed in _stable_fixed_coordinate_rows(design)
        push!(rows, (; parameter = "$(fixed.block)[$(fixed.level)]",
            values = fill(fixed.value, size(fit.draws, 1)),
            block = fixed.block, dimension = nothing, fixed = true))
    end
    # The final threshold is a deterministic sum-to-zero transform, not a new fit.
    nsteps = length(design.spec.data.category_levels) - 1
    items = design.spec.thresholds === :rating_scale ? (1:1) : eachindex(design.spec.data.item_levels)
    for item in items
        name = design.spec.thresholds === :rating_scale ? "step[$nsteps]" :
            "step[item=$(design.spec.data.item_levels[item]),$nsteps]"
        values = [Float64(_threshold_step(design, draw, item, nsteps)) for draw in eachrow(fit.draws)]
        push!(rows, (; parameter = name, values, block = :thresholds,
            dimension = nothing, fixed = nsteps == 1))
    end
    order = vcat(_person_parameter_names(design.spec),
        ["rater[$level]" for level in design.spec.data.rater_levels],
        ["item[$level]" for level in design.spec.data.item_levels],
        [design.spec.thresholds === :rating_scale ? "step[$step]" :
            "step[item=$(design.spec.data.item_levels[item]),$step]"
            for item in items for step in 1:nsteps])
    lookup = Dict(row.parameter => row for row in rows)
    return [lookup[name] for name in order]
end

function _posterior_plot_coordinates(fit::Union{GMFRMFit,MGMFRMFit}, scale)
    layout = fit.diagnostic_surface.parameter_layout
    model = scale === :model
    names = model ? fit.diagnostic_surface.direct_parameter_names : fit.diagnostic_surface.raw_parameter_names
    draws = model ? fit.direct_draws : fit.draws
    blocks = model ? layout.constrained_blocks : layout.raw_blocks
    block_map = Dict(t.raw_block => t.constrained_block for t in layout.transforms)
    block_for = Dict(name => (model ? row.block : block_map[row.block])
        for row in blocks for name in row.parameter_names)
    fixed_names = Set(name for t in layout.transforms if t.raw_n_parameters == 0
        for name in t.constrained_parameter_names)
    dimensions = Dict{String,Int}()
    if fit isa MGMFRMFit
        spec = fit.design.spec
        for row in blocks
            block = model ? row.block : block_map[row.block]
            indices = block === :person ?
                repeat(collect(1:spec.dimensions), length(spec.data.person_levels)) :
                block === :item_dimension_discrimination ?
                [dim for item in axes(spec.q_matrix, 1) for dim in axes(spec.q_matrix, 2)
                    if spec.q_matrix[item, dim]] : Int[]
            isempty(indices) || length(indices) == length(row.parameter_names) ||
                throw(ArgumentError("dimension labels do not match fitted parameter layout"))
            merge!(dimensions, Dict(zip(row.parameter_names, indices)))
        end
    end
    rows = NamedTuple[(; parameter = name, values = view(draws, :, index),
        block = block_for[name], dimension = get(dimensions, name, nothing),
        fixed = model && name in fixed_names) for (index, name) in enumerate(names)]
    if model
        facet, block = fit isa GMFRMFit ? (:rater, :rater_steps) : (:item, :item_steps)
        levels = _separation_reliability_levels(fit.design.spec.data, facet)
        K = length(fit.design.spec.data.category_levels)
        for (index, level) in enumerate(levels), step in (1, K)
            name = "$(facet)_step[$facet=$level,m=$step]"
            values = [Float64(_source_step_value(fit.design, draw, block, index, step))
                for draw in eachrow(fit.direct_draws)]
            push!(rows, (; parameter = name, values, block, dimension = nothing,
                fixed = step == 1 || K == 2))
        end
        steps = Dict(row.parameter => row for row in rows if row.block === block)
        rows = vcat([row for row in rows if row.block !== block],
            [steps["$(facet)_step[$facet=$level,m=$step]"] for level in levels for step in 1:K])
    end
    return rows
end

function _posterior_plot_selection(fit::_ModelComparisonFit;
        scale::Symbol = :model, kwargs...)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    size(fit.draws, 1) > 0 && all(isfinite, fit.draws) ||
        throw(ArgumentError("posterior plotting requires nonempty finite draws"))
    if fit isa Union{GMFRMFit,MGMFRMFit}
        all(isfinite, fit.direct_draws) || throw(ArgumentError("model coordinates contain nonfinite draws"))
    end
    rows = _posterior_plot_coordinates(fit, scale)
    all(row -> length(row.values) == size(fit.draws, 1) && all(isfinite, row.values), rows) ||
        throw(ArgumentError("plot coordinates must be finite and aligned with retained draws"))
    return _select_posterior_coordinates(rows,
        fit isa MGMFRMFit ? fit.design.spec.dimension_labels : nothing; scale, kwargs...)
end

function _select_posterior_coordinates(rows::AbstractVector, dimension_labels;
        scale::Symbol = :model,
        block::Union{Nothing,Symbol} = nothing, dimension = nothing,
        parameters = nothing, max_parameters::Int = 60)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    max_parameters > 0 || throw(ArgumentError("max_parameters must be positive"))
    all(row -> !row.fixed || all(==(first(row.values)), row.values), rows) ||
        throw(ArgumentError("a structurally fixed parameter varies in the stored draws"))
    total = length(rows)
    if block !== nothing
        any(row -> row.block === block, rows) || throw(ArgumentError("unknown or empty parameter block: $block"))
        filter!(row -> row.block === block, rows)
    end
    if dimension !== nothing
        dimension_labels === nothing && throw(ArgumentError("dimension selection requires named dimensions"))
        (dimension isa Integer && !(dimension isa Bool)) || dimension isa Union{AbstractString,Symbol} ||
            throw(ArgumentError("dimension must be an integer index or label"))
        labels = dimension_labels
        index = dimension isa Integer && !(dimension isa Bool) ? Int(dimension) :
            findfirst(label -> string(label) == string(dimension), labels)
        index !== nothing && 1 <= index <= length(labels) || throw(ArgumentError("unknown dimension: $dimension"))
        filter!(row -> row.dimension == index, rows)
    end
    if parameters !== nothing
        selected = parameters isa AbstractString ? [String(parameters)] : collect(parameters)
        all(name -> name isa AbstractString, selected) || throw(ArgumentError("parameters must contain names as strings"))
        length(unique(selected)) == length(selected) || throw(ArgumentError("parameter names must be unique"))
        lookup = Dict(row.parameter => row for row in rows)
        all(name -> haskey(lookup, name), selected) || throw(ArgumentError("unknown parameter or parameter excluded by block/dimension selection"))
        rows = [lookup[name] for name in selected]
    end
    isempty(rows) && throw(ArgumentError("selection contains no parameters"))
    length(rows) <= max_parameters || throw(ArgumentError(
        "selected $(length(rows)) parameters (limit $max_parameters); select block, dimension, or parameters, or increase max_parameters"))
    return (; rows, total, scale)
end

function _plot_diagnostic_note(summary)
    return summary.flag === :ok ? "No warnings under the fit's MCMC diagnostic thresholds" :
        summary.flag === :insufficient_chains ? "MCMC diagnostics unavailable: too few chains" :
        summary.flag === :insufficient_draws ? "MCMC diagnostics unavailable: too few draws" :
        "MCMC warnings: inspect diagnostics(fit)"
end

function _posterior_plot_data(fit::_ModelComparisonFit; interval::Real = 0.95, kwargs...)
    _interval_probabilities(Float64(interval)) # Reject invalid requests before deriving coordinates/diagnostics.
    selected = _posterior_plot_selection(fit; kwargs...)
    summary = fit isa MFRMFit ? diagnostics(fit).summary : fit.diagnostic_surface.summary
    diagnostic = _plot_diagnostic_note(summary)
    constraints = fit isa MFRMFit ? Dict(block => replace(String(rule), '_' => ' ')
        for (block, rule) in fit.design.identification) :
        Dict(t.constrained_block => replace(String(t.constraint), '_' => ' ')
            for t in fit.diagnostic_surface.parameter_layout.transforms)
    return _posterior_interval_data(selected; interval, diagnostic, constraints)
end

function _posterior_interval_data(selected; interval::Real = 0.95, diagnostic, constraints)
    level = Float64(interval)
    isfinite(level) && 0 < level < 1 || throw(ArgumentError("interval must lie strictly between zero and one"))
    lower, upper = (1 - level) / 2, (1 + level) / 2
    rows = map(selected.rows) do coordinate
        row = only(_posterior_summary_rows(reshape(coordinate.values, :, 1), [coordinate.parameter];
            lower, upper, intervals = (), reference = 0.0, rope = nothing, rope_probability_threshold = 0.95))
        (; parameter = row.parameter, median = row.median, lower = row.lower, upper = row.upper,
            block = coordinate.block, dimension = coordinate.dimension, fixed = coordinate.fixed)
    end
    all(row -> isfinite(row.median) && isfinite(row.lower) && isfinite(row.upper), rows) ||
        throw(ArgumentError("posterior summaries contain nonfinite values"))
    groups = unique([(row.block, row.dimension) for row in rows])
    return (; rows, groups, total = selected.total, scale = selected.scale, interval = level, diagnostic, constraints)
end

"""
    BayesianMGMFRM.plot_diagnostics(fit; scale = :raw, block = nothing,
        dimension = nothing, parameters = nothing, max_parameters = 12,
        bins = 20, size = nothing)

Draw retained-chain traces and pooled-rank histograms directly from an MFRM,
experimental GMFRM, or experimental fixed-Q MGMFRM fit. Load `CairoMakie` first;
returns its editable `Figure`, supporting `display` and PDF/SVG `save`.
No sampling, thinning, warmup-draw reconstruction or random tie-breaking occurs.

The default `:raw` shows the stored computational coordinates; `:model` uses
identified/transformed coordinates, including fixed and derived constraints.
Selection uses the same block, dimension and exact parameter names as
[`BayesianMGMFRM.plot_posterior`](@ref), with a smaller default limit of 12.
All chains and retained iterations are shown, using their stored identities.

Ranks are pooled across chains separately for each coordinate, with average
ranks for ties. Each chain histogram is normalized to sum to one; the gray
reference is the pooled histogram, including its tie pattern. `bins` is a
positive integer, capped at the total draw count. Rank comparison is unavailable
for a single chain, fixed values, or constant sampled values. Matching rank
histograms alone do not establish convergence.

Parameter labels show existing rank-normalized R-hat and bulk/tail ESS where
available. Derived coordinates without stored diagnostic rows are explicitly
unavailable. The footer retains whole-fit diagnostics, including unselected
parameters, and per-chain sampler counts/coverage. Generalized diagnostic
settings are those stored with the fit; older incompatible records retain the
existing diagnostic-contract rejection. Warmup parameter draws are not stored;
inspect `sampler_diagnostics(fit; phase = :warmup)` for separate warmup summaries.
This optional entry point is qualified, not exported.
"""
function plot_diagnostics(fit::_ModelComparisonFit; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError(
        "plot_diagnostics requires CairoMakie; install it with Pkg.add(\"CairoMakie\") and run `using CairoMakie`"))
    return extension.plot_diagnostics(fit; kwargs...)
end

function _plot_rank_histogram(values, chain_ids, nchains, bins)
    sorted = sort(values)
    # Average ranks retain ties deterministically, including rejected MCMC steps.
    ranks = [(searchsortedfirst(sorted, value) + searchsortedlast(sorted, value)) / 2 for value in values]
    counts = zeros(Int, bins, nchains)
    for (rank, chain) in zip(ranks, chain_ids)
        bin = clamp(floor(Int, (rank - 0.5) * bins / length(values)) + 1, 1, bins)
        counts[bin, chain] += 1
    end
    frequencies = counts ./ sum(counts; dims = 1)
    return (; ranks, counts, frequencies, pooled = vec(sum(counts; dims = 2)) ./ length(values),
        edges = (0:bins) ./ bins)
end

_plot_metric(value) = ismissing(value) || !(value isa Real) || !isfinite(value) ?
    "unavailable" : value isa Integer ? string(value) : string(round(value; sigdigits = 4))

function _plot_diagnostic_surface(fit::_ModelComparisonFit)
    fit isa MFRMFit && return diagnostics(fit)
    stored = fit.diagnostic_surface.summary
    return diagnostics(fit; split_chains = _nt_get(stored, :split_chains_requested, true),
        rhat_threshold = _nt_get(stored, :rhat_threshold, 1.01),
        ess_threshold = _nt_get(stored, :ess_threshold, 400))
end

function _diagnostic_plot_data(fit::_ModelComparisonFit;
        scale::Symbol = :raw, max_parameters::Int = 12, bins = 20, kwargs...)
    bins isa Integer && !(bins isa Bool) && bins > 0 || throw(ArgumentError("bins must be a positive integer"))
    per_chain = _fit_draws_per_chain(fit)
    selected = _posterior_plot_selection(fit; scale, max_parameters, kwargs...)
    surface = _plot_diagnostic_surface(fit)
    nchains = length(fit.chain_acceptance_rate)
    metric_rows = fit isa MFRMFit || scale === :raw ? surface.parameter_rows : surface.direct_parameter_rows
    return _trace_rank_plot_data(selected, metric_rows, surface, fit; bins, nchains, per_chain)
end

function _trace_rank_plot_data(selected, metric_rows, surface, run;
        bins, nchains::Int, per_chain::Int,
        fixed_status = "Fixed identification value; diagnostics not applicable")
    summary = surface.summary
    metric_lookup = Dict(row.parameter => row for row in metric_rows)
    bins = Int(min(bins, length(run.chain_ids)))
    rows = map(selected.rows) do coordinate
        metric = get(metric_lookup, coordinate.parameter, nothing)
        status = coordinate.fixed ? fixed_status :
            metric === nothing ? "Derived coordinate; parameter diagnostics unavailable" :
            "R-hat $(_plot_metric(metric.rank_normalized_rhat)); bulk ESS $(_plot_metric(metric.bulk_ess)); " *
                "tail ESS $(_plot_metric(metric.tail_ess)) [$(replace(String(metric.flag), '_' => ' '))]"
        get(coordinate, :derived, false) && metric !== nothing &&
            (status = "Derived from retained draws; " * status)
        rank_note = coordinate.fixed ? "Fixed value: rank comparison not applicable" :
            nchains < 2 ? "Rank comparison unavailable: requires at least two chains" :
            all(==(first(coordinate.values)), coordinate.values) ? "Constant sampled values: rank comparison unavailable" : ""
        ranks = isempty(rank_note) ? _plot_rank_histogram(coordinate.values, run.chain_ids, nchains, bins) : nothing
        (; coordinate..., status, ranks, rank_note)
    end
    sampler_notes = map(surface.sampler_rows) do row
        stats = [stat for stat in run.sampler_stats if stat.chain == row.chain]
        complete = length(stats) == per_chain &&
            Set(stat.iteration for stat in stats) == Set(1:per_chain)
        nuts = run.sampler === :nuts
        divergence = nuts && complete ? _plot_metric(row.n_divergences) : "unavailable"
        depth = nuts && complete ? _plot_metric(row.n_max_treedepth) : "unavailable"
        energy = nuts && complete ? _plot_metric(row.e_bfmi) : "unavailable"
        nonfinite = _nt_get(row, :n_nonfinite_log_posterior, _nt_get(row, :n_nonfinite_logdensity, missing))
        "Chain $(row.chain): divergences $divergence; max-depth hits $depth; E-BFMI $energy; " *
            "nonfinite log density $(_plot_metric(nonfinite)) [event flag: $(replace(String(row.flag), '_' => ' '))]"
    end
    return (; rows, total = selected.total, scale = selected.scale, bins, nchains, per_chain,
        chain_ids = run.chain_ids, iterations = run.iterations, summary, sampler_notes,
        diagnostic = _plot_diagnostic_note(summary))
end

"""
    BayesianMGMFRM.plot_predictive(fit; interval = 0.9, ndraws = nothing,
        draw_indices = nothing, seed = 1, size = nothing)

Compare observed category proportions with posterior predictive replicated
proportions for an MFRM, experimental GMFRM, or experimental fixed-Q MGMFRM fit.
Load `CairoMakie` first. Returns its editable `Figure`, supporting `display`
and PDF/SVG `save`. No MCMC or refitting is performed.

The check replicates the existing rating rows, conditional on their fitted
persons, items and raters. Every declared score category remains visible,
including categories with zero observed ratings. Diamonds show observed
proportions, circles show replicated means, and bars show pointwise central
predictive intervals. These are intervals for replicated category proportions,
not parameter intervals, simultaneous bands, or Monte Carlo error bars.

By default, generate one replicated dataset for every retained draw in stored
order. `ndraws` instead samples that many draw indices uniformly with replacement;
`draw_indices` supplies exact ordered indices (repeats allowed). Pass only one
of these selection options. The number of replications, distinct retained draws used and selection policy
appear in the figure. `interval` changes the summary, not the replicated data.

Each call creates a local MersenneTwister from the integer `seed` (default 1),
without advancing the global RNG. Reuse the same fit, seed and selection options
in the same Julia/package environment to regenerate the same result after
`load_fit_cache`. Numerical results are available through
`posterior_predictive_check(fit; rng = MersenneTwister(seed), ...)` followed by
`predictive_check_summary(...; interval)`.

The whole-fit MCMC diagnostic note remains visible. This same-data check does
not establish convergence or performance for new persons, items or raters.
This optional entry point is qualified, not exported.
"""
function plot_predictive(fit::_ModelComparisonFit; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError(
        "plot_predictive requires CairoMakie; install it with Pkg.add(\"CairoMakie\") and run `using CairoMakie`"))
    return extension.plot_predictive(fit; kwargs...)
end

function _predictive_plot_data(fit::_ModelComparisonFit; interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing, seed::Integer = 1)
    _interval_probabilities(interval)
    _fit_draws_per_chain(fit)
    size(fit.draws, 1) > 0 && all(isfinite, fit.draws) ||
        throw(ArgumentError("predictive plotting requires nonempty finite draws"))
    rng, rng_control = _fit_rng(Random.default_rng(), seed)
    surface = _plot_diagnostic_surface(fit)
    check = posterior_predictive_check(fit; ndraws, draw_indices, rng)
    return _category_predictive_plot_data(check; interval, ndraws, draw_indices,
        n_retained = size(fit.draws, 1), rng = rng_control,
        diagnostic = _plot_diagnostic_note(surface.summary))
end

function _category_predictive_plot_data(check; interval, ndraws, draw_indices,
        n_retained, rng, diagnostic)
    rows = predictive_check_plot_data(filter(row -> row.statistic === :category_proportion,
        predictive_check_summary(check; interval)))
    selection = draw_indices !== nothing ? "Explicit ordered draw indices" :
        ndraws === nothing ? "All retained draws in stored order" : "Draw indices sampled with replacement"
    return (; rows, interval = Float64(interval), draw_indices = check.draw_indices,
        n_replicates = length(check.draw_indices), n_observations = size(check.replicated_scores, 2),
        n_retained, n_unique_draws = length(unique(check.draw_indices)),
        selection, rng, diagnostic)
end

"""
    BayesianMGMFRM.plot_wright(fit; facets = :all, include_thresholds = true,
        interval = 0.95, max_levels = 60, size = nothing)

Draw a Wright map from a stable MFRM rating-scale or partial-credit fit.
Load `CairoMakie` first; returns its editable `Figure` for `display` and PDF/SVG
`save`. Experimental GMFRM/MGMFRM fits are unsupported. All retained draws are
used without refitting, random selection, or recentering.

Facet panels share a vertical logit scale. Higher person ability increases
adjacent-category log odds; higher rater severity or item difficulty decreases
them. Points show medians and bars show central credible intervals. Diamonds
identify fixed references or hard anchors; their external uncertainty is excluded.

The optional boundary panel shows item difficulty plus category step, summed
draw by draw with their joint uncertainty. These are adjacent-category
equal-probability boundaries at zero rater severity, not expected-score
half-points or 50% marginal category probabilities. A fixed step does not make
the boundary fixed when the item is estimated. Whole-fit MCMC warnings remain
visible; the map is not a convergence or model-fit check.

`facets` accepts `:all`, a single `:person`, `:rater` or `:item`, or an ordered
tuple of these facets. `include_thresholds = true` adds boundaries for all items,
independently of facet selection. Original level/category labels and order are
preserved. More than `max_levels` displayed positions raises an error: narrow
facets, omit boundaries, or increase the limit and Figure `size` explicitly.
No positions are silently omitted. Reuse the same options after `load_fit_cache`
to regenerate the map. [`wright_map_data`](@ref) returns its numerical inputs.
This optional entry point is qualified, not exported.
"""
function plot_wright(fit::_ModelComparisonFit; kwargs...)
    fit isa MFRMFit || throw(ArgumentError("plot_wright supports stable MFRM fits only; generalized scales are unsupported"))
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError(
        "plot_wright requires CairoMakie; install it with Pkg.add(\"CairoMakie\") and run `using CairoMakie`"))
    return extension.plot_wright(fit; kwargs...)
end

function _wright_plot_data(fit::MFRMFit; facets = :all, include_thresholds::Bool = true,
        interval::Real = 0.95, max_levels = 60)
    max_levels isa Integer && !(max_levels isa Bool) && max_levels > 0 ||
        throw(ArgumentError("max_levels must be a positive integer"))
    _fit_draws_per_chain(fit)
    rows = wright_map_data(fit; facets, include_thresholds, interval)
    length(rows) <= max_levels || throw(ArgumentError(
        "selected $(length(rows)) positions (limit $max_levels); narrow facets, set include_thresholds=false, or increase max_levels and figure size"))
    all(row -> isfinite(row.position_median) && isfinite(row.position_lower) &&
        isfinite(row.position_upper), rows) || throw(ArgumentError("Wright-map summaries must be finite"))
    return (; rows, groups = unique(getproperty.(rows, :facet)), interval = Float64(interval),
        n_draws = size(fit.draws, 1), diagnostic = _plot_diagnostic_note(diagnostics(fit).summary))
end

const _FIT_REPORT_FIGURE_KINDS = (:posterior, :diagnostics, :predictive, :wright)

function _fit_report_figure_file_hash(bytes)
    return (; algorithm = :sha256, value = bytes2hex(sha256(bytes)),
        scope = :fit_report_figure_file, canonicalization = :raw_bytes,
        n_canonical_bytes = length(bytes))
end

# Bundle readers remain usable without loading CairoMakie or a saved fit.
function _check_fit_report_figure_entries(manifest, directory; verify_hash::Bool)
    if manifest["schema"] == "bayesianmgmfrm.fit_report_bundle_export.v1"
        haskey(manifest, "figures") && throw(ArgumentError("figure entries require bundle schema v2"))
        return nothing
    end
    rows = get(manifest, "figures", nothing)
    rows isa AbstractVector && 1 <= length(rows) <= 4 ||
        throw(ArgumentError("figure bundle must contain one to four figure entries"))
    seen = Set{Symbol}()
    for row in rows
        kind = _report_symbol_value(_report_lookup(row, :kind, nothing))
        kind in _FIT_REPORT_FIGURE_KINDS && !(kind in seen) ||
            throw(ArgumentError("unsupported or duplicate bundle figure kind"))
        push!(seen, kind)
        files = _report_lookup(row, :files, nothing)
        files isa AbstractVector && length(files) == 3 ||
            throw(ArgumentError("each figure requires PDF, SVG and JSON inputs"))
        paths = [_report_lookup(file, :path, nothing) for file in files]
        Set(paths) == Set("figures/$kind.$ext" for ext in ("pdf", "svg", "json")) ||
            throw(ArgumentError("unexpected figure file paths"))
        islink(joinpath(directory, "figures")) &&
            throw(ArgumentError("figure directory must not be a symlink"))
        for file in files
            path = _fit_report_bundle_file_path(directory, file, "bundle figure")
            islink(path) && throw(ArgumentError("figure files must not be symlinks"))
            _check_fit_report_hash_record(file, :content_hash, "bundle figure";
                expected_scope = :fit_report_figure_file, expected_canonicalization = :raw_bytes)
            if verify_hash
                isfile(path) || throw(ArgumentError("bundle figure file is missing: $path"))
                _fit_report_hash_record_matches_actual(file, :content_hash,
                    _fit_report_figure_file_hash(read(path)), "bundle figure";
                    expected_scope = :fit_report_figure_file, expected_canonicalization = :raw_bytes)
            end
        end
    end
    return nothing
end

function _fit_report_figure_options(figures)
    figures isa NamedTuple && !isempty(figures) ||
        throw(ArgumentError("figures must be a nonempty NamedTuple of plot options, such as (posterior = (block = :rater,),)"))
    allowed = (;
        posterior = (:scale, :block, :dimension, :parameters, :max_parameters, :size),
        diagnostics = (:scale, :block, :dimension, :parameters, :max_parameters, :bins, :size),
        predictive = (:size,),
        wright = (:facets, :include_thresholds, :max_levels, :size))
    for (kind, options) in pairs(figures)
        kind in _FIT_REPORT_FIGURE_KINDS || throw(ArgumentError("unknown figure kind: $kind"))
        options isa NamedTuple && all(key -> key in getproperty(allowed, kind), keys(options)) ||
            throw(ArgumentError("unsupported $kind figure options; set posterior_lower/posterior_upper, predictive_interval, ndraws/draw_indices and seed on save_fit_report_bundle"))
    end
    return figures
end

function _report_predictive_plot_data(fit, report, kwargs, seed)
    section = report.posterior_predictive
    section.status === :computed || throw(ArgumentError("predictive figure requires a computed posterior_predictive report section"))
    indices = section.draw_indices
    rows = predictive_check_plot_data(filter(row -> row.statistic === :category_proportion, section.rows))
    selection = get(kwargs, :draw_indices, nothing) !== nothing ? "Explicit ordered draw indices" :
        get(kwargs, :ndraws, nothing) === nothing ? "All retained draws in stored order" :
        "Draw indices sampled with replacement"
    return (; rows, interval = report.report_policy.predictive_interval, draw_indices = indices,
        n_replicates = length(indices), n_observations = fit.design.spec.data.n,
        n_retained = size(fit.draws, 1), n_unique_draws = length(unique(indices)),
        selection, rng = (; seed), diagnostic = _plot_diagnostic_note(_plot_diagnostic_surface(fit).summary))
end

function _save_fit_report_figure_bundle(directory, fit, figures;
        seed, report_kwargs, overwrite, label, title, max_rows, include_empty, require_complete)
    _fit_report_figure_options(figures)
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("figure seed must be an integer"))
    any(key -> haskey(report_kwargs, key), (:rng, :prior_predictive_rng)) &&
        throw(ArgumentError("use seed instead of rng/prior_predictive_rng for reproducible figure bundles"))
    fit isa MFRMFit || !haskey(figures, :wright) ||
        throw(ArgumentError("Wright-map bundles support stable MFRM fits only"))
    extension = _check_fit_report_figure_destination(directory, figures; overwrite, max_rows)

    # Existing plots use these diagnostic settings; do not give the report a different gate.
    stored = fit isa MFRMFit ? (; split_chains_requested = true, rhat_threshold = 1.01, ess_threshold = 400) :
        fit.diagnostic_surface.summary
    diagnostic_options = (; split_chains = _nt_get(stored, :split_chains_requested, true),
        rhat_threshold = _nt_get(stored, :rhat_threshold, 1.01),
        ess_threshold = _nt_get(stored, :ess_threshold, 400))
    for (key, value) in pairs(diagnostic_options)
        get(report_kwargs, key, value) == value ||
            throw(ArgumentError("figure bundles require $key = $value to match the fit's plotting diagnostics"))
    end
    lower, upper = get(report_kwargs, :posterior_lower, 0.025), get(report_kwargs, :posterior_upper, 0.975)
    interval = upper - lower
    if haskey(figures, :posterior) || haskey(figures, :wright)
        0 < interval < 1 && isapprox(lower + upper, 1; atol = 8eps(Float64), rtol = 0) ||
            throw(ArgumentError("posterior and Wright figures require central posterior_lower/posterior_upper bounds"))
    end
    report = fit_report(fit; report_kwargs..., diagnostic_options..., view = :full,
        rng = MersenneTwister(seed), prior_predictive_rng = MersenneTwister(seed), require_complete)
    view = get(report_kwargs, :view, :full)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    exported_report = view === :public ? fit_report_public(report) : report
    identity = (; family = fit.design.spec.family, dimension_labels = fit.design.spec.dimension_labels)
    return _write_fit_report_figures(directory, exported_report, figures;
            identity, seed, overwrite, label, title, max_rows, include_empty, require_complete) do kind, numerical, size
        data = kind === :posterior ? _posterior_plot_data(fit; numerical..., interval) :
            kind === :diagnostics ? _diagnostic_plot_data(fit; numerical...) :
            kind === :wright ? _wright_plot_data(fit; numerical..., interval) :
            _report_predictive_plot_data(fit, report, report_kwargs, seed)
        figure = getproperty(extension, Symbol("_render_", kind))(fit, data; size)
        (; data, figure)
    end
end

function _check_fit_report_figure_destination(directory, figures; overwrite, max_rows)
    max_rows >= 0 || throw(ArgumentError("max_rows must be non-negative"))
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("figure bundles require CairoMakie; install it and run `using CairoMakie`"))
    _check_fit_report_bundle_directory(directory; overwrite)
    islink(directory) && throw(ArgumentError("figure bundle destination must not be a symlink"))
    islink(joinpath(directory, "figures")) && throw(ArgumentError("figure directory must not be a symlink"))
    ispath(joinpath(directory, "figures")) && !isdir(joinpath(directory, "figures")) &&
        throw(ArgumentError("figure directory path is not a directory"))
    for kind in keys(figures), ext in ("pdf", "svg", "json")
        path = joinpath(directory, "figures", "$kind.$ext")
        (islink(path) || (ispath(path) && !isfile(path))) &&
            throw(ArgumentError("figure output must be a regular file: $path"))
    end
    return extension
end

function _write_fit_report_figures(prepare, directory, report, figures;
        identity, seed, overwrite, label, title, max_rows, include_empty, require_complete)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    # Render all optional outputs first. A renderer/selection failure cannot replace an existing bundle.
    return mktempdir() do staging
        mkpath(joinpath(staging, "figures"))
        entries = NamedTuple[]
        markdown = IOBuffer()
        println(markdown, "\n## Figures\n")
        for (kind, options) in pairs(figures)
            numerical = Base.structdiff(options, (; size = nothing))
            data, figure = prepare(kind, numerical, get(options, :size, nothing))
            caption = getproperty(extension, Symbol("_", kind, "_caption"))(data)
            exported_data = kind === :diagnostics ? Base.structdiff(data, (; summary = nothing)) : data
            payload = (; schema = "bayesianmgmfrm.fit_report_figure_data.v1", kind,
                identity...,
                report_content_hash = _fit_report_content_hash_record(report),
                caption, options, seed, data = exported_data)
            _write_json_record(joinpath(staging, "figures", "$kind.json"), payload)
            for ext in ("pdf", "svg")
                extension.save(joinpath(staging, "figures", "$kind.$ext"), figure)
            end
            files = [(; path = "figures/$kind.$ext",
                content_hash = _fit_report_figure_file_hash(read(joinpath(staging, "figures", "$kind.$ext"))))
                for ext in ("pdf", "svg", "json")]
            push!(entries, (; kind, caption, files))
            heading = uppercasefirst(String(kind))
            println(markdown, "### $heading\n\n![$heading figure](figures/$kind.svg)\n")
            println(markdown, caption, "\n\n[PDF](figures/$kind.pdf) · [SVG](figures/$kind.svg) · [Numerical inputs](figures/$kind.json)\n")
        end
        return _save_fit_report_bundle(directory, report;
            overwrite, label, title, max_rows, include_empty, require_complete,
            figure_bundle = (; directory = staging, rows = entries, markdown = String(take!(markdown))))
    end
end
