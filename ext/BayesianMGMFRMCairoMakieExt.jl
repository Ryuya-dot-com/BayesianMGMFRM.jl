module BayesianMGMFRMCairoMakieExt

using BayesianMGMFRM, CairoMakie
const B = BayesianMGMFRM

function _annotation_offset(annotation_io)
    annotation_io === nothing && return 1
    annotation_io isa IO && iswritable(annotation_io) ||
        throw(ArgumentError("annotation_io must be nothing or a writable IO stream"))
    return 0
end

function _figure_text!(fig, title, caption; annotation_io, bottom_row, columns = 1,
        title_fontsize = 21, title_bold = true)
    if annotation_io === nothing
        Label(fig[1, 1:columns], title; fontsize = title_fontsize,
            font = title_bold ? :bold : :regular, tellwidth = false, word_wrap = true)
        Label(fig[bottom_row, 1:columns], caption; fontsize = 12, tellwidth = false,
            justification = :left, halign = :left, word_wrap = true)
    else
        # One title line, followed by the complete note, also consumed by report bundles.
        println(annotation_io, replace(title, '\n' => ' '), "\n\nNote. ", caption)
    end
    return fig
end

# Category identity follows the full stored scale, even when only one is plotted.
_response_category_colors(n) = n <= 7 ? Makie.wong_colors()[1:n] :
    Makie.distinguishable_colors(n, [RGBf(1,1,1), RGBf(0,0,0)]; dropseed = true)
_ability_axis(d) = "θ" * join(Char(0x2080 + Int(c - '0')) for c in string(d))

function plot_response_surface(fit; size = nothing, azimuth = 1.275pi,
        elevation = pi/7, annotation_io = stdout, kwargs...)
    offset = _annotation_offset(annotation_io)
    data = B.item_response_surface(fit; kwargs...)
    all_categories = data.category === :all
    probabilities = data.category !== nothing
    category_indices = all_categories ? collect(eachindex(data.category_levels)) :
        probabilities ? [findfirst(==(data.category), data.category_levels)] : [1]
    colors = _response_category_colors(length(data.category_levels))
    panels = length(category_indices)
    plot_row = (probabilities ? 2 : 1) + offset
    fig = Figure(; size = something(size, (1200, all_categories ? max(620 + 180offset, 240cld(panels,2)+60+180offset) : 520 + 180offset)), fontsize = 14)
    title = "Experimental MGMFRM item response surface\nItem $(data.item) · Rater $(data.rater)"
    xlabel, ylabel = _ability_axis.(data.dimensions)
    ax = Axis3(fig[plot_row, 1]; xlabel, ylabel, zlabel = data.quantity_label,
        title = "Posterior mean", azimuth, elevation, protrusions = (80, 30, 50, 30))
    bounds = probabilities ? (0.0, 1.0) : extrema(data.category_levels)
    if all_categories
        for k in category_indices
            wireframe!(ax, data.x, data.y, data.mean[:,:,k]; color = colors[k], linewidth = 1.1)
        end
    elseif probabilities
        surface!(ax, data.x, data.y, data.mean; color = colors[only(category_indices)])
    else
        surface!(ax, data.x, data.y, data.mean; colormap = :viridis, colorrange = bounds)
    end
    zlims!(ax, bounds...)
    if probabilities
        Legend(fig[1 + offset, 1:2], [LineElement(; color = colors[k], linewidth = 3) for k in category_indices],
            ["Rating $(data.category_levels[k])" for k in category_indices];
            orientation = :horizontal, nbanks = cld(panels, 6), tellwidth = false)
    end
    uncertainty = GridLayout(fig[plot_row, 2])
    upper = maximum(data.interval_width)
    for (panel, k) in enumerate(category_indices)
        panel_title = all_categories ? "Rating $(data.category_levels[k])" : "Pointwise uncertainty"
        width = Axis(uncertainty[cld(panel, 2), mod1(panel, 2)]; xlabel, ylabel, title = panel_title,
            titlecolor = all_categories ? colors[k] : :black)
        values = all_categories ? data.interval_width[:,:,k] : data.interval_width
        heatmap!(width, data.x, data.y, values; colormap = :magma,
            colorrange = (0.0, iszero(upper) ? 1.0 : upper))
    end
    Colorbar(uncertainty[cld(panels,2)+1, 1:min(panels,2)]; colormap = :magma,
        limits = (0.0, iszero(upper) ? 1.0 : upper), vertical = false,
        label = "$(round(100data.interval; digits=2))% pointwise interval width")
    fixed = isempty(data.fixed_abilities) ? "No additional ability dimensions." :
        "Fixed abilities: " * join(["$(_ability_axis(r.dimension))=$(r.value)" for r in data.fixed_abilities], ", ") * "."
    inactive = [_ability_axis(data.dimensions[i]) for i in 1:2 if !data.active_dimensions[i]]
    qnote = isempty(inactive) ? "" : " Q excludes " * join(inactive, ", ") * "; the surface is flat along that axis."
    caption = "$(data.quantity_label); $(data.n_draws) of $(data.total_draws) retained joint draws. $fixed$qnote\n" *
        "Pointwise intervals describe uncertainty in the conditional mean/probability, not future individual ratings.\n" *
        "Ability ranges are display choices; they do not establish data support.\n" * data.diagnostic * " (whole fit)."
    _figure_text!(fig, title, caption; annotation_io, bottom_row = plot_row + 1,
        columns = 2, title_bold = false)
end

function plot_posterior(fit; size = nothing, annotation_io = stdout, kwargs...)
    return _render_posterior(fit, B._posterior_plot_data(fit; kwargs...); size, annotation_io)
end

function _render_posterior(fit, data; size = nothing, annotation_io = stdout)
    family = uppercase(String(fit.design.spec.family))
    title = (fit isa B.MFRMFit ? "" : "Experimental ") * family * " posterior intervals"
    xlabel = data.scale === :model ? "Model coordinate" :
        fit isa B.MFRMFit ? "Free identified coordinate" : "Raw computational coordinate"
    return _render_posterior(data; title, xlabel,
        dimension_labels = fit.design.spec.dimension_labels, size, annotation_io)
end

function _render_posterior(data; title, dimension_labels, xlabel, size = nothing,
        caption = _posterior_caption(data), annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    groups = [[row for row in data.rows if (row.block, row.dimension) == key] for key in data.groups]
    figure_size = size === nothing ? (850, 30 * length(data.rows) + 95 * length(groups) + 40 + 120offset) : size
    fig = Figure(; size = figure_size, fontsize = 15)
    for (index, rows) in enumerate(groups)
        block, dimension = data.groups[index]
        heading = get(Dict(:person => "Person ability", :rater => "Rater severity",
            :item => "Item difficulty", :thresholds => "Threshold steps",
            :item_dimension_discrimination => "Item discrimination"), block,
            uppercasefirst(replace(String(block), '_' => ' ')))
        dimension === nothing || (heading *= " - " * string(dimension_labels[dimension]))
        if data.scale === :model
            rule = get(data.constraints, block, "")
            rule = get(Dict("reference first" => "first level fixed",
                "hard anchor" => "fixed anchors",
                "multidimensional location gauge" => "population location/scale specified",
                "confirmatory q mask" => "fixed Q structure",
                "first step zero sum to zero" => "first step fixed; remaining steps sum to 0"), rule, rule)
            rule in ("", "free") || (heading *= "\n" * rule)
        end
        labels = [row.parameter * (row.fixed ? " (fixed)" : "") for row in rows]
        ax = Axis(fig[index + offset, 1]; title = heading, yticks = (1:length(rows), labels),
            yreversed = true, xlabel = xlabel isa AbstractDict ? get(xlabel, block, "Unit logits") : xlabel,
            xgridvisible = true, ygridvisible = false)
        for (position, row) in enumerate(rows)
            if row.fixed
                scatter!(ax, [row.median], [position]; marker = :diamond, color = :black, markersize = 10)
            else
                rangebars!(ax, [position], [row.lower], [row.upper]; direction = :x,
                    color = :steelblue4, linewidth = 2, whiskerwidth = 8)
                scatter!(ax, [row.median], [position]; color = :steelblue4, markersize = 8)
            end
        end
        ylims!(ax, length(rows) + 0.6, 0.4)
        data.scale === :model && block === :latent_correlation && xlims!(ax, -1, 1)
        rowsize!(fig.layout, index + offset, Auto(length(rows)))
    end
    return _figure_text!(fig, title, caption; annotation_io, bottom_row = length(groups) + 2)
end

function plot_diagnostics(fit; size = nothing, annotation_io = stdout, kwargs...)
    return _render_diagnostics(fit, B._diagnostic_plot_data(fit; kwargs...); size, annotation_io)
end

function _render_diagnostics(fit, data; size = nothing, annotation_io = stdout)
    family = (fit isa B.MFRMFit ? "" : "Experimental ") * uppercase(String(fit.design.spec.family))
    scale = data.scale === :model ? "model coordinates" : fit isa B.MFRMFit ?
        "free identified coordinates" : "raw computational coordinates"
    return _render_diagnostics(data; title = "$family chain diagnostics\n$scale", size, annotation_io)
end

function _render_diagnostics(data; title, ylabel = "Value", size = nothing, annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    fig = Figure(; size = size === nothing ? (1100, 285 * length(data.rows) + 120 + 190offset + 22 * data.nchains +
        (hasproperty(data, :location_note) ? 90offset : 0)) : size,
        fontsize = 14)
    colors = Makie.wong_colors()
    styles = (:solid, :dash, :dot, :dashdot, :dashdotdot)
    for (index, row) in enumerate(data.rows)
        position = 2 * index - 1 + offset
        Label(fig[position, 1:2], get(row, :label, row.parameter) * "\n" * row.status;
            fontsize = 14, tellwidth = false, word_wrap = true)
        trace = Axis(fig[position + 1, 1]; xlabel = "Retained iteration (warmup excluded)",
            ylabel = ylabel isa AbstractDict ? get(ylabel, row.block, "Unit logits") : ylabel, title = "Trace")
        rank = Axis(fig[position + 1, 2]; xlabel = "Pooled rank / total draws", ylabel = "Fraction in bin", title = "Rank histogram")
        for chain in 1:data.nchains
            indices = findall(==(chain), data.chain_ids)
            color, linestyle = colors[mod1(chain, length(colors))], styles[mod1(chain, length(styles))]
            if row.fixed
                chain == 1 && hlines!(trace, [first(row.values)]; color = :black)
            else
                data.per_chain == 1 ?
                    scatter!(trace, data.iterations[indices], row.values[indices]; color, marker = :circle) :
                    lines!(trace, data.iterations[indices], row.values[indices]; color, linestyle, linewidth = 1.4)
            end
            if row.ranks !== nothing
                stairs!(rank, row.ranks.edges, vcat(row.ranks.frequencies[:, chain], row.ranks.frequencies[end, chain]);
                    step = :post, color, linestyle, linewidth = 2)
            end
        end
        xlims!(trace, 0.5, data.per_chain + 0.5)
        data.scale === :model && row.block === :latent_correlation && ylims!(trace, -1, 1)
        if row.ranks === nothing
            hidedecorations!(rank); hidespines!(rank)
            text!(rank, 0.5, 0.5; text = replace(row.rank_note, ": " => ":\n"), space = :relative,
                align = (:center, :center), fontsize = 14)
        else
            stairs!(rank, row.ranks.edges, vcat(row.ranks.pooled, last(row.ranks.pooled));
                step = :post, color = :gray50, linewidth = 1.5)
            xlims!(rank, 0, 1)
        end
    end
    elements = [LineElement(; color = colors[mod1(chain, length(colors))],
        linestyle = styles[mod1(chain, length(styles))], linewidth = 2) for chain in 1:data.nchains]
    labels = ["Chain $chain" for chain in 1:data.nchains]
    if all(row -> row.fixed, data.rows)
        empty!(elements); empty!(labels)
    end
    if any(row -> row.fixed, data.rows)
        push!(elements, LineElement(; color = :black, linewidth = 1.5)); push!(labels, "Fixed value")
    end
    if any(row -> row.ranks !== nothing, data.rows)
        push!(elements, LineElement(; color = :gray50, linewidth = 1.5)); push!(labels, "Pooled ranks")
    end
    footer_row = 2 * length(data.rows) + 1 + offset
    Legend(fig[footer_row, 1:2], elements, labels; orientation = :horizontal, nbanks = cld(length(labels), 6), tellwidth = false)
    caption = _diagnostics_caption(data)
    return _figure_text!(fig, title, caption; annotation_io, bottom_row = footer_row + 1,
        columns = 2, title_fontsize = 20)
end

function plot_predictive(fit; size = nothing, annotation_io = stdout, kwargs...)
    return _render_predictive(fit, B._predictive_plot_data(fit; kwargs...); size, annotation_io)
end

function _render_predictive(fit, data; size = nothing, annotation_io = stdout)
    family = (fit isa B.MFRMFit ? "" : "Experimental ") * uppercase(String(fit.design.spec.family))
    return _render_predictive(data; title = "$family posterior predictive check\nCategory proportions", size, annotation_io)
end

function _render_predictive(data; title, size = nothing, caption = _predictive_caption(data), annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    n = length(data.rows)
    fig = Figure(; size = size === nothing ? (900, max(340 + 140offset, 50 * n + 140 + 160offset)) : size, fontsize = 15)
    ax = Axis(fig[1 + offset, 1]; xlabel = "Proportion of ratings", ylabel = "Score category",
        yticks = (1:n, string.(getproperty.(data.rows, :level))), ygridvisible = false)
    positions = collect(1:n)
    level = round(100 * data.interval; digits = 4)
    bars = rangebars!(ax, positions .+ 0.12, getproperty.(data.rows, :replicated_lower),
        getproperty.(data.rows, :replicated_upper); direction = :x, color = :steelblue4,
        linewidth = 2, whiskerwidth = 10)
    predicted = scatter!(ax, getproperty.(data.rows, :replicated_mean), positions .+ 0.12;
        color = :steelblue4, marker = :circle, markersize = 10)
    observed = scatter!(ax, getproperty.(data.rows, :observed), positions .- 0.12;
        color = :black, marker = :diamond, markersize = 12)
    xlims!(ax, -0.03, 1.03); ylims!(ax, n + 0.6, 0.4)
    Legend(fig[2 + offset, 1], [observed, predicted, bars],
        ["Observed", "Replicated mean", "$(level)% predictive interval"];
        orientation = :horizontal, tellwidth = false)
    return _figure_text!(fig, title, caption; annotation_io, bottom_row = 4)
end

function plot_wright(fit; size = nothing, annotation_io = stdout, kwargs...)
    return _render_wright(fit, B._wright_plot_data(fit; kwargs...); size, annotation_io)
end

function _render_wright(fit, data; size = nothing, annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    groups = [[row for row in data.rows if row.facet === facet] for facet in data.groups]
    fig = Figure(; size = size === nothing ? (max(1000, 65 * data.n_individual_positions + 200), 560 + 200offset) : size, fontsize = 14)
    title = "MFRM Wright map\nShared logit scale"
    headings = Dict(:person => "+ Person ability", :rater => "- Rater severity",
        :item => "- Item difficulty", :threshold => "Item + step\n(rater severity = 0)")
    axes = Axis[]
    for (column, rows) in enumerate(groups)
        if data.groups[column] === :person && data.histogram !== nothing
            h = data.histogram
            centers = h.edges[1:end-1] .+ diff(h.edges) ./ 2
            tick_step = max(1, ceil(Int, maximum(h.counts) / 4))
            ax = Axis(fig[1 + offset, column]; title = "+ Person ability\nN = $(h.n_persons)",
                ylabel = column == 1 ? "Logit position" : "", xlabel = "Number of persons",
                xticks = 0:tick_step:maximum(h.counts), xgridvisible = false)
            push!(axes, ax)
            barplot!(ax, centers, h.counts; direction = :x, width = diff(h.edges), gap = 0,
                color = :steelblue4, strokecolor = :white, strokewidth = 0.5)
            hlines!(ax, [0]; color = :gray70, linestyle = :dash)
            xlims!(ax, 0, 1.08 * maximum(h.counts))
            colsize!(fig.layout, column, Auto(4))
            continue
        end
        labels = [row.component === :threshold ? "$(row.item)\n$(row.from_category) -> $(row.to_category)" :
            string(row.level) for row in rows]
        ax = Axis(fig[1 + offset, column]; title = headings[data.groups[column]],
            ylabel = column == 1 ? "Logit position" : "", xticks = (1:length(rows), labels),
            xticklabelrotation = pi / 2, xgridvisible = false)
        push!(axes, ax)
        hlines!(ax, [0]; color = :gray70, linestyle = :dash)
        for (position, row) in enumerate(rows)
            if row.is_fixed
                scatter!(ax, [position], [row.position_median]; marker = :diamond, color = :black, markersize = 11)
            else
                rangebars!(ax, [position], [row.position_lower], [row.position_upper];
                    color = :steelblue4, linewidth = 2, whiskerwidth = 8)
                scatter!(ax, [position], [row.position_median]; color = :steelblue4, markersize = 8)
            end
        end
        xlims!(ax, 0.4, length(rows) + 0.6)
        colsize!(fig.layout, column, Auto(max(2, length(rows))))
    end
    linkyaxes!(axes...)
    individual_rows = filter(row -> data.histogram === nothing || row.facet !== :person, data.rows)
    lo = minimum((row.position_lower for row in individual_rows); init = 0.0)
    hi = maximum((row.position_upper for row in individual_rows); init = 0.0)
    if data.histogram !== nothing
        lo = min(lo, first(data.histogram.edges))
        hi = max(hi, last(data.histogram.edges))
    end
    pad = hi > lo ? 0.08 * (hi - lo) : 0.1
    ylims!(first(axes), lo - pad, hi + pad)
    caption = _wright_caption(data)
    return _figure_text!(fig, title, caption; annotation_io, bottom_row = 3, columns = length(groups))
end

function plot_pathway(fit; size = nothing, annotation_io = stdout, kwargs...)
    return _render_pathway(fit, B._pathway_plot_data(fit; kwargs...); size, annotation_io)
end

function _render_pathway(fit, data; size = nothing, annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    fig = Figure(; size = size === nothing ? (max(550, 440length(data.groups)), 560 + 240offset) : size, fontsize = 15)
    headings = Dict(:person => "+ Person ability", :rater => "- Rater severity", :item => "- Item difficulty")
    axes = Axis[]
    for (column, facet) in enumerate(data.groups)
        ax = Axis(fig[1 + offset, column]; title = headings[facet],
            xlabel = "$(uppercasefirst(String(data.metric))) mean square",
            ylabel = column == 1 ? "Location (logits)" : "")
        push!(axes, ax)
        vlines!(ax, [1.0]; color = :gray50, linestyle = :dash)
        for (index, row) in enumerate(filter(row -> row.facet === facet, data.rows))
            x, y = row.fit_median, row.logit_median
            color = row.flag === :ok ? :steelblue4 : :darkorange3
            rangebars!(ax, [y], [row.fit_lower], [row.fit_upper];
                direction = :x, color, whiskerwidth = 8, linewidth = 2)
            row.is_fixed || rangebars!(ax, [x], [row.logit_lower], [row.logit_upper];
                color, whiskerwidth = 8, linewidth = 2)
            scatter!(ax, [x], [y]; color, marker = row.is_fixed ? :diamond : :circle, markersize = 10)
        end
        # Keep labels above every interval, including neighbouring levels' bars.
        for (index, row) in enumerate(filter(row -> row.facet === facet, data.rows))
            label = "$(row.level) (n=$(row.n_observations))" * (row.flag === :ok ? "" : "*")
            text!(ax, row.fit_median, row.logit_median; text = label,
                offset = (8, isodd(index) ? 8 : -8),
                align = (:left, isodd(index) ? :bottom : :top), fontsize = 12)
        end
    end
    linkyaxes!(axes...); linkxaxes!(axes...)
    lo, hi = extrema(vcat(getproperty.(data.rows, :logit_lower), getproperty.(data.rows, :logit_upper)))
    pad = hi > lo ? 0.12 * (hi - lo) : 0.1
    ylims!(first(axes), lo - pad, hi + pad)
    xlims!(first(axes), 0, max(1.2, maximum(row.fit_upper for row in data.rows) * 1.35))
    return _figure_text!(fig, "MFRM Pathway map", _pathway_caption(data);
        annotation_io, bottom_row = 3, columns = length(data.groups))
end

function _pathway_caption(data)
    percentage = round(100 * data.interval; digits = 4)
    flags = ["$(row.facet) $(row.level): fit=$(row.fit_flag), position=$(row.position_flag)"
        for row in data.rows if row.flag !== :ok]
    return "Marginal medians and $(percentage)% central intervals on each axis; not a joint credible region. All $(data.n_draws) retained draws.\n" *
        "Diamonds: fixed reference/anchor locations; horizontal fit intervals still reflect uncertainty. External anchor uncertainty excluded.\n" *
        "Labels give contributing rating counts (n). + Ability raises adjacent-category log odds; - severity/difficulty lower them. No recentering.\n" *
        (isempty(flags) ? "Numerical row flags: none.\n" : "Orange points with *: " * join(flags, "; ") * ". Tiny predictive variances are clipped; inspect diagnostic_map_data before interpretation.\n") *
        "$(uppercasefirst(String(data.metric))) = 1 is a mean-square reference, not an acceptance threshold or a ZSTD cutoff.\n" *
        data.diagnostic * " (whole fit). Same-data residual screening; not convergence or model-selection evidence."
end

function _posterior_caption(data)
    percentage = round(100 * data.interval; digits = 4)
    return (hasproperty(data, :prior_label) ? data.prior_label * "\n" : "") * "Medians and $(percentage)% central credible intervals; $(length(data.rows)) of $(data.total) coordinates shown.\n" *
        get(data, :fixed_note, "Diamonds: fixed identification values; anchor uncertainty excluded.") * "\n" *
        data.diagnostic * " (whole fit). Intervals do not establish convergence."
end

function _diagnostics_caption(data)
    s = data.summary
    scope = hasproperty(data, :location_note) ? "parameters and sampler" : "whole fit"
    return (hasproperty(data, :prior_label) ? data.prior_label * "\n" : "") * "$(length(data.rows)) of $(data.total) coordinates; all $(data.nchains) chains and $(data.per_chain) retained draws per chain. " *
        "$(data.bins) rank bins; ties use average ranks.\n" *
        data.diagnostic * " ($scope). R-hat max $(B._plot_metric(s.max_rank_normalized_rhat)); " *
        "bulk/tail ESS min $(B._plot_metric(s.min_bulk_ess)) / $(B._plot_metric(s.min_tail_ess)).\n" *
        join(data.sampler_notes, "\n") * "\n" *
        (hasproperty(data, :location_note) ? data.location_note * "\n" : "") *
        "Similar ranks do not establish convergence. Warmup parameter draws are not stored."
end

function _predictive_caption(data)
    return (hasproperty(data, :prior_label) ? data.prior_label * "\n" : "") * "$(data.n_replicates) replicated datasets of $(data.n_observations) ratings each; seed $(data.rng.seed).\n" *
        "$(data.n_unique_draws) distinct posterior draws from $(data.n_retained) retained; " * data.selection * ".\n" *
        "Same rating rows and fitted persons, items and raters.\n" *
        "Bars: pointwise central predictive intervals for category proportions.\n" *
        data.diagnostic * " (whole fit).\n" *
        "Same-data check; agreement does not establish convergence or performance for new facets."
end

function _wright_caption(data)
    percentage = round(100 * data.interval; digits = 4)
    histogram_note = if data.histogram === nothing
        ""
    else
        h = data.histogram
        "Person histogram: one posterior median per person; all $(h.n_persons) persons in the selected facet.\n" *
        "This distribution of shrunken estimates is not a population density or pooled posterior draws; it does not show individual uncertainty. Use person_display=:intervals for individual intervals.\n" *
        "Bin edges (logits): $(join(h.edges, ", ")). Counts in increasing logit order: $(join(h.counts, ", ")).\n" *
        "Bins include the lower edge and exclude the upper edge, except the last includes both.\n"
    end
    return histogram_note * "Circles: medians and $(percentage)% central credible intervals; all $(data.n_draws) retained draws.\n" *
        "Diamonds: fixed references/anchors; external anchor uncertainty excluded.\n" *
        "+ Ability raises adjacent-category log odds; - severity and - difficulty lower them. No recentering.\n" *
        (:threshold in data.groups ?
            "Item + step: adjacent-category equal-probability boundaries at rater severity 0; not expected-score half-points.\n" : "") *
        data.diagnostic * " (whole fit). The map does not establish convergence or model fit."
end

include("prior_sensitivity.jl")
include("prior_predictive_sensitivity.jl")

end
