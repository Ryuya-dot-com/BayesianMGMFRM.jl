module BayesianMGMFRMCairoMakieExt

using BayesianMGMFRM, CairoMakie
const B = BayesianMGMFRM

function plot_posterior(fit; size = nothing, kwargs...)
    return _render_posterior(fit, B._posterior_plot_data(fit; kwargs...); size)
end

function _render_posterior(fit, data; size = nothing)
    family = uppercase(String(fit.design.spec.family))
    title = (fit isa B.MFRMFit ? "" : "Experimental ") * family * " posterior intervals"
    xlabel = data.scale === :model ? "Model coordinate" :
        fit isa B.MFRMFit ? "Free identified coordinate" : "Raw computational coordinate"
    return _render_posterior(data; title, xlabel,
        dimension_labels = fit.design.spec.dimension_labels, size)
end

function _render_posterior(data; title, dimension_labels, xlabel, size = nothing)
    groups = [[row for row in data.rows if (row.block, row.dimension) == key] for key in data.groups]
    figure_size = size === nothing ? (850, 30 * length(data.rows) + 95 * length(groups) + 160) : size
    fig = Figure(; size = figure_size, fontsize = 15)
    Label(fig[1, 1], title; fontsize = 21, font = :bold, tellwidth = false)
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
        ax = Axis(fig[index + 1, 1]; title = heading, yticks = (1:length(rows), labels),
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
        rowsize!(fig.layout, index + 1, Auto(length(rows)))
    end
    caption = _posterior_caption(data)
    Label(fig[length(groups) + 2, 1], caption; fontsize = 12, tellwidth = false,
        justification = :left, halign = :left, word_wrap = true)
    return fig
end

function plot_diagnostics(fit; size = nothing, kwargs...)
    return _render_diagnostics(fit, B._diagnostic_plot_data(fit; kwargs...); size)
end

function _render_diagnostics(fit, data; size = nothing)
    family = (fit isa B.MFRMFit ? "" : "Experimental ") * uppercase(String(fit.design.spec.family))
    scale = data.scale === :model ? "model coordinates" : fit isa B.MFRMFit ?
        "free identified coordinates" : "raw computational coordinates"
    return _render_diagnostics(data; title = "$family chain diagnostics\n$scale", size)
end

function _render_diagnostics(data; title, ylabel = "Value", size = nothing)
    fig = Figure(; size = size === nothing ? (1100, 285 * length(data.rows) + 310 + 22 * data.nchains) : size,
        fontsize = 14)
    Label(fig[1, 1:2], title; fontsize = 20,
        font = :bold, tellwidth = false)
    colors = Makie.wong_colors()
    styles = (:solid, :dash, :dot, :dashdot, :dashdotdot)
    for (index, row) in enumerate(data.rows)
        position = 2 * index
        Label(fig[position, 1:2], row.parameter * "\n" * row.status;
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
    footer_row = 2 * length(data.rows) + 2
    Legend(fig[footer_row, 1:2], elements, labels; orientation = :horizontal, nbanks = cld(length(labels), 6), tellwidth = false)
    caption = _diagnostics_caption(data)
    Label(fig[footer_row + 1, 1:2], caption; fontsize = 12, tellwidth = false,
        justification = :left, halign = :left, word_wrap = true)
    return fig
end

function plot_predictive(fit; size = nothing, kwargs...)
    return _render_predictive(fit, B._predictive_plot_data(fit; kwargs...); size)
end

function _render_predictive(fit, data; size = nothing)
    family = (fit isa B.MFRMFit ? "" : "Experimental ") * uppercase(String(fit.design.spec.family))
    return _render_predictive(data; title = "$family posterior predictive check\nCategory proportions", size)
end

function _render_predictive(data; title, size = nothing)
    n = length(data.rows)
    fig = Figure(; size = size === nothing ? (900, max(480, 50 * n + 300)) : size, fontsize = 15)
    Label(fig[1, 1], title;
        fontsize = 21, font = :bold, tellwidth = false)
    ax = Axis(fig[2, 1]; xlabel = "Proportion of ratings", ylabel = "Score category",
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
    Legend(fig[3, 1], [observed, predicted, bars],
        ["Observed", "Replicated mean", "$(level)% predictive interval"];
        orientation = :horizontal, tellwidth = false)
    caption = _predictive_caption(data)
    Label(fig[4, 1], caption; fontsize = 12, tellwidth = false,
        justification = :left, halign = :left, word_wrap = true)
    return fig
end

function plot_wright(fit; size = nothing, kwargs...)
    return _render_wright(fit, B._wright_plot_data(fit; kwargs...); size)
end

function _render_wright(fit, data; size = nothing)
    groups = [[row for row in data.rows if row.facet === facet] for facet in data.groups]
    fig = Figure(; size = size === nothing ? (max(1000, 65 * length(data.rows) + 200), 760) : size, fontsize = 14)
    Label(fig[1, 1:length(groups)], "MFRM Wright map\nShared logit scale";
        fontsize = 21, font = :bold, tellwidth = false)
    headings = Dict(:person => "+ Person ability", :rater => "- Rater severity",
        :item => "- Item difficulty", :threshold => "Item + step\n(rater severity = 0)")
    axes = Axis[]
    for (column, rows) in enumerate(groups)
        labels = [row.component === :threshold ? "$(row.item)\n$(row.from_category) -> $(row.to_category)" :
            string(row.level) for row in rows]
        ax = Axis(fig[2, column]; title = headings[data.groups[column]],
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
    lo = min(0.0, minimum(row.position_lower for row in data.rows))
    hi = max(0.0, maximum(row.position_upper for row in data.rows))
    pad = hi > lo ? 0.08 * (hi - lo) : 0.1
    ylims!(first(axes), lo - pad, hi + pad)
    caption = _wright_caption(data)
    Label(fig[3, 1:length(groups)], caption; fontsize = 12, tellwidth = false,
        justification = :left, halign = :left, word_wrap = true)
    return fig
end

function _posterior_caption(data)
    percentage = round(100 * data.interval; digits = 4)
    return "Medians and $(percentage)% central credible intervals; $(length(data.rows)) of $(data.total) coordinates shown.\n" *
        get(data, :fixed_note, "Diamonds: fixed identification values; anchor uncertainty excluded.") * "\n" *
        data.diagnostic * " (whole fit). Intervals do not establish convergence."
end

function _diagnostics_caption(data)
    s = data.summary
    return "$(length(data.rows)) of $(data.total) coordinates; all $(data.nchains) chains and $(data.per_chain) retained draws per chain. " *
        "$(data.bins) rank bins; ties use average ranks.\n" *
        data.diagnostic * " (whole fit). R-hat max $(B._plot_metric(s.max_rank_normalized_rhat)); " *
        "bulk/tail ESS min $(B._plot_metric(s.min_bulk_ess)) / $(B._plot_metric(s.min_tail_ess)).\n" *
        join(data.sampler_notes, "\n") * "\nSimilar ranks do not establish convergence. Warmup parameter draws are not stored."
end

function _predictive_caption(data)
    return "$(data.n_replicates) replicated datasets of $(data.n_observations) ratings each; seed $(data.rng.seed).\n" *
        "$(data.n_unique_draws) distinct posterior draws from $(data.n_retained) retained; " * data.selection * ".\n" *
        "Same rating rows and fitted persons, items and raters.\n" *
        "Bars: pointwise central predictive intervals for category proportions.\n" *
        data.diagnostic * " (whole fit).\n" *
        "Same-data check; agreement does not establish convergence or performance for new facets."
end

function _wright_caption(data)
    percentage = round(100 * data.interval; digits = 4)
    return "Circles: medians and $(percentage)% central credible intervals; all $(data.n_draws) retained draws.\n" *
        "Diamonds: fixed references/anchors; external anchor uncertainty excluded.\n" *
        "+ Ability raises adjacent-category log odds; - severity and - difficulty lower them. No recentering.\n" *
        (:threshold in data.groups ?
            "Item + step: adjacent-category equal-probability boundaries at rater severity 0; not expected-score half-points.\n" : "") *
        data.diagnostic * " (whole fit). The map does not establish convergence or model fit."
end

end
