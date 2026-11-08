module BayesianMGMFRMCairoMakieExt

using BayesianMGMFRM, CairoMakie
const B = BayesianMGMFRM

function plot_rater_drift(saved; rater, size=(1000,550), annotation_io=stdout)
    d=B.Experimental.RaterDrift.trajectory(saved;rater)
    offset=_annotation_offset(annotation_io)
    fig=Figure(;size,fontsize=14)
    ax=Axis(fig[1+offset,1];xlabel="Time ($(d.time_unit))",
        ylabel="Severity change from $(d.reference) (model units)",
        xticks=([r.tick for r in d.rows],[r.time for r in d.rows]))
    hlines!(ax,[0.];color=:gray60,linestyle=:dash)
    lines!(ax,[r.tick for r in d.rows],[r.median for r in d.rows];color=:gray60)
    for row in d.rows
        color=row.design_status in ("linked","reference","static_constraint") ? :steelblue4 : :darkorange3
        if !row.structurally_fixed
            rangebars!(ax,[row.tick],[row.lower],[row.upper];color,linewidth=2,whiskerwidth=12)
        end
        scatter!(ax,[row.tick],[row.median];color,markersize=12,
            marker=row.structurally_fixed ? :diamond : :circle)
    end
    title="Severity change: $(rater===:panel ? "fixed panel" : rater)"
    note="Medians and $(100d.interval_mass)% pointwise equal-tailed credible intervals; not a simultaneous band. " *
        "Positive change means harsher rating. Model units enter the adjacent-category logit with multiplier 1.7. " *
        (d.process===:static ? "All diamonds are changes fixed at zero by the static model; severity levels remain uncertain. " :
            "The reference diamond is zero by definition. Orange marks process-only or confounded changes. ") *
        "Lines connect stored bins and are not a continuous-time fit. " *
        "Original numerical qualification: $(d.original_numerical_qualified); integrated: $(d.numerical_qualified). " *
        (d.process===:static ? "No innovation SD is fitted. " : "Log innovation SD prior mean: $(d.innovation_log_sd_mean), SD: 1. ") *
        "Retrospective estimates; no forecasting, change-point or intervention-effect claim. " *
        "Whole-report warnings: " * (isempty(d.warnings) ? "none recorded." : join(d.warnings," "))
    _figure_text!(fig,title,note;annotation_io,bottom_row=2+offset)
end

function plot_design_precision(results; parameter, size=nothing, annotation_io=stdout)
    data = B.design_precision_plot_data(results; parameter)
    offset = _annotation_offset(annotation_io)
    rows = data.rows
    labels = map(rows) do row
        status = row.confidence_interval.status
        note = status === :available ? "" : "\nCI: " * replace(String(status),'_'=>' ')
        "$(row.scenario_id)\nwidth <= $(row.max_interval_width); qualified $(row.n_qualified)/$(row.n_planned)" * note
    end
    fig = Figure(;size=something(size,(1300,160+100length(rows)+180offset)),fontsize=14)
    level = data.confidence_level === nothing ? "requested" : "$(round(100data.confidence_level;digits=2))%"
    left = Axis(fig[1+offset,1];title="Numerically qualified datasets",
        xlabel="Target frequency and $level confidence interval",
        yticks=(1:length(rows),labels),yreversed=true,ygridvisible=false)
    right = Axis(fig[1+offset,2];title="All planned datasets",
        xlabel="Unresolved-outcome bounds (not a confidence interval)",
        yticks=(1:length(rows),fill("",length(rows))),yreversed=true,ygridvisible=false)
    for (i,row) in enumerate(rows)
        ci = row.confidence_interval
        if ci.status === :available
            rangebars!(left,[i],[ci.lower],[ci.upper];direction=:x,color=:steelblue4,
                linewidth=2,whiskerwidth=10)
        end
        if ismissing(row.conditional_frequency)
            text!(left,0.05,i;text="No qualified result",align=(:left,:center),fontsize=12)
        else
            scatter!(left,[row.conditional_frequency],[i];color=:black,markersize=10)
        end
        lower,upper = row.all_planned_frequency_bounds
        rangebars!(right,[i],[lower],[upper];direction=:x,color=:darkorange3,
            linewidth=2,whiskerwidth=10)
        lower == upper && scatter!(right,[lower],[i];marker=:diamond,color=:darkorange3,markersize=10)
    end
    for ax in (left,right)
        xlims!(ax,-0.03,1.03); ylims!(ax,length(rows)+0.6,0.4)
        ax.xticks = 0:0.25:1
    end
    target = data.interval_probability === nothing ? "Declared central interval" :
        "$(round(100data.interval_probability;digits=2))% central interval"
    title = "Design precision: $(data.parameter)"
    caption = "$target widths use each row's target in its native units. Black points are observed frequencies. " *
        "Left intervals are per-scenario Clopper-Pearson confidence intervals conditional on numerical qualification, " *
        "requiring independent identically distributed dataset replications; unavailable intervals are labelled. " *
        "Right bounds assign every unresolved outcome failure or success; they have no confidence level. " *
        "Failures and numerical exclusions remain in planned counts. MCMC width-classification error is not corrected. " *
        "No simultaneous inference, design ranking, calibration or assurance is established."
    return _figure_text!(fig,title,caption;annotation_io,bottom_row=2+offset,columns=2)
end

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
        elevation = pi/7, annotation_io = stdout, layout = :overlay, kwargs...)
    layout isa Symbol && layout in (:overlay, :panels, :heatmaps) ||
        throw(ArgumentError("layout must be :overlay, :panels or :heatmaps"))
    data = B.item_response_surface(fit; kwargs...)
    return _render_response_surface(data; size, azimuth, elevation, annotation_io, layout)
end

function _render_response_surface(data; size = nothing, azimuth = 1.275pi,
        elevation = pi/7, annotation_io = stdout, layout = :overlay)
    layout === :overlay || return _render_response_panels(data;
        size, azimuth, elevation, annotation_io, layout)
    offset = _annotation_offset(annotation_io)
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
    _figure_text!(fig, title, _response_caption(data); annotation_io, bottom_row = plot_row + 1,
        columns = 2, title_bold = false)
end

function _response_caption(data)
    fixed = isempty(data.fixed_abilities) ? "No additional ability dimensions." :
        "Fixed abilities: " * join(["$(_ability_axis(r.dimension))=$(r.value)" for r in data.fixed_abilities], ", ") * "."
    inactive = [_ability_axis(data.dimensions[i]) for i in 1:2 if !data.active_dimensions[i]]
    qnote = isempty(inactive) ? "" : " Q excludes " * join(inactive, ", ") * "; the surface is flat along that axis."
    return "$(data.quantity_label); $(data.n_draws) of $(data.total_draws) retained joint draws. $fixed$qnote\n" *
        "Pointwise intervals describe uncertainty in the conditional mean/probability, not future individual ratings.\n" *
        "Interval widths are posterior uncertainty, not MCSE or simultaneous bands.\n" *
        "Ability ranges are display choices; they do not establish data support.\n" * data.diagnostic * " (whole fit)."
end

function _render_response_panels(data; size, azimuth, elevation, annotation_io, layout)
    offset = _annotation_offset(annotation_io)
    all_categories = data.category === :all
    levels = all_categories ? data.category_levels : [data.category]
    columns = min(3,length(levels))
    rows = cld(length(levels),columns)
    fig = Figure(; size=something(size,(460columns,510rows+90+180offset)),fontsize=14)
    xlabel,ylabel = _ability_axis.(data.dimensions)
    inactive = [_ability_axis(data.dimensions[i]) for i in 1:2 if !data.active_dimensions[i]]
    qnote = isempty(inactive) ? "" : "\nQ excludes " * join(inactive,", ")
    bounds = data.category === nothing ? extrema(data.category_levels) : (0.,1.)
    widths = (0., max(maximum(data.interval_width),eps(Float64)))
    for (k,level) in enumerate(levels)
        row,col = 2cld(k,columns)-1+offset,mod1(k,columns)
        heading = (level === nothing ? "Expected rating" : "Rating $level") * " · mean" * qnote
        means = all_categories ? data.mean[:,:,k] : data.mean
        uncertainty = all_categories ? data.interval_width[:,:,k] : data.interval_width
        if layout === :panels
            ax = Axis3(fig[row,col];xlabel,ylabel,zlabel=data.quantity_label,title=heading,
                azimuth,elevation,protrusions=(65,25,40,25))
            surface!(ax,data.x,data.y,means;colormap=:viridis,colorrange=bounds)
            zlims!(ax,bounds...)
        else
            ax = Axis(fig[row,col];xlabel,ylabel,title=heading)
            heatmap!(ax,data.x,data.y,means;colormap=:viridis,colorrange=bounds)
        end
        width = Axis(fig[row+1,col];xlabel,ylabel,title="Rating $(something(level,"mean")) · interval width")
        heatmap!(width,data.x,data.y,uncertainty;colormap=:magma,colorrange=widths)
    end
    scales = GridLayout(fig[2rows+1+offset,1:columns])
    Colorbar(scales[1,1];colormap=:viridis,limits=bounds,vertical=false,label="Mean: $(data.quantity_label)")
    Colorbar(scales[columns==1 ? 2 : 1,columns==1 ? 1 : 2];colormap=:magma,limits=widths,vertical=false,
        label="$(round(100data.interval;digits=2))% pointwise interval width")
    colgap!(fig.layout,40)
    colgap!(scales,60)
    return _figure_text!(fig,"Experimental MGMFRM · Item $(data.item) · Rater $(data.rater)",
        _response_caption(data) * "\nCommon mean and width scales across all category panels.";
        annotation_io,bottom_row=2rows+2+offset,columns,title_bold=false)
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
    hasproperty(data,:ridge) && return _render_wright_ridges(data;size,annotation_io)
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

function _render_wright_ridges(data; size, annotation_io)
    offset = _annotation_offset(annotation_io)
    r = data.ridge
    maximum_rows = maximum(count(row->row.facet===facet,data.rows) for facet in data.groups)
    fig = Figure(;size=something(size,(380length(data.groups),150+48maximum_rows+220offset)),fontsize=14)
    headings = Dict(:person=>"+ Person ability",:rater=>"− Rater severity",
        :item=>"− Item difficulty",:threshold=>"Item + step (rater = 0)")
    peak = maximum((maximum(d) for d in r.densities if d !== nothing);init=1e-12)
    axes = Axis[]
    for (col,facet) in enumerate(data.groups)
        indices = findall(row->row.facet===facet,data.rows)
        labels = [row.component === :threshold ? "$(row.item): $(row.from_category) → $(row.to_category)" :
            string(row.level) for row in data.rows[indices]]
        ax = Axis(fig[1+offset,col];title=headings[facet],xlabel="Logit position",
            yticks=(maximum_rows-length(indices)+1:maximum_rows,reverse(labels)),ygridvisible=false)
        push!(axes,ax)
        vlines!(ax,[0.];color=:gray60,linestyle=:dash)
        for (level,i) in enumerate(indices)
            y = maximum_rows-level+1
            row,d,status = data.rows[i],r.densities[i],r.statuses[i]
            if d !== nothing
                top = y .+ .72 .* d ./ peak
                band!(ax,r.grid,fill(Float64(y),length(r.grid)),top;color=(:steelblue,.35))
                lines!(ax,r.grid,top;color=:steelblue4,linewidth=1.1)
            end
            row.is_fixed || rangebars!(ax,[y],[row.position_lower],[row.position_upper];
                direction=:x,color=:black,linewidth=2,whiskerwidth=6)
            scatter!(ax,[row.position_median],[y];color=status===:constant ? :darkorange3 : :black,
                marker=status===:fixed ? :diamond : status===:constant ? :xcross : :circle,markersize=8)
        end
        xlims!(ax,first(r.grid),last(r.grid)); ylims!(ax,.6,maximum_rows+.9)
    end
    linkxaxes!(axes...)
    note = "Each ridge is one level's marginal posterior density, not a population distribution or pooled draws. " *
        "Gaussian bandwidth: $(r.bandwidth) logits; common grid and height multiplier; no recentering. " *
        "Smoothing is descriptive, not an MCSE estimate. Intervals use unsmoothed draws.\n" *
        (isempty(r.constant_labels) ? "" : "Crosses: constant estimated draws, not fixed anchors: $(join(r.constant_labels,", ")).\n") *
        _wright_caption(data)
    return _figure_text!(fig,"MFRM ridge Wright map · shared logit scale",note;
        annotation_io,bottom_row=2+offset,columns=length(data.groups))
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

include("criterion_collapse.jl")
include("prior_sensitivity.jl")
include("prior_predictive_sensitivity.jl")

function plot_star_result(res; kind::Symbol = :posterior, interval::Real = 0.95,
        max_parameters::Int = 30, size = nothing, annotation_io = stdout, seed::Int = 20261030)
    kind in (:posterior, :diagnostics, :predictive) || throw(ArgumentError(
        "StarResult supports plot kind = :posterior, :diagnostics, or :predictive"))
    max_parameters >= 1 || throw(ArgumentError("max_parameters must be positive"))
    SA = B.Experimental.StarAssociation
    qual = SA.qualify(res)
    diag_note = qual.result.numerically_qualified ? "All MCMC qualification thresholds met" :
        "MCMC diagnostic warnings present; inspect qualify(fit)"
    if kind === :posterior
        rep = SA.posterior_summary(res; interval = Float64(interval)).result
        rows = rep.posterior[1:min(length(rep.posterior), max_parameters)]
        offset = _annotation_offset(annotation_io)
        fig = Figure(; size = something(size, (950, 120 + 36 * length(rows) + 140 * offset)), fontsize = 14)
        ax = Axis(fig[1 + offset, 1];
            title = "Model parameter summaries",
            yticks = (1:length(rows), [r.parameter for r in rows]),
            yreversed = true,
            xlabel = "Posterior estimate",
            ygridvisible = false)
        vlines!(ax, [0.0]; color = :gray65, linestyle = :dash)
        for (i, r) in enumerate(rows)
            rangebars!(ax, [i], [r.lower], [r.upper]; direction = :x, color = :steelblue4, linewidth = 2, whiskerwidth = 8)
            scatter!(ax, [r.median], [i]; color = :steelblue4, markersize = 8)
        end
        ylims!(ax, length(rows) + 0.6, 0.4)
        return _figure_text!(fig, "Experimental StarAssociation posterior summary",
            "Medians and $(round(100 * interval; digits = 2))% equal-tailed intervals. $diag_note.";
            annotation_io, bottom_row = 2 + offset)
    elseif kind === :diagnostics
        pnames = SA.parameter_names(res.model; space = :raw)
        nsel = min(length(pnames), min(max_parameters, 8))
        nch = res.config.chains
        per_ch = res.config.ndraws
        offset = _annotation_offset(annotation_io)
        fig = Figure(; size = something(size, (1050, 240 * nsel + 120 + 140 * offset)), fontsize = 14)
        colors = Makie.wong_colors()
        for idx in 1:nsel
            ax = Axis(fig[idx + offset, 1]; title = pnames[idx], xlabel = "Retained iteration", ylabel = "Value")
            for c in 1:nch
                rng_idx = ((c - 1) * per_ch + 1):(c * per_ch)
                lines!(ax, 1:per_ch, view(res.draws, rng_idx, idx);
                    color = colors[mod1(c, length(colors))], linewidth = 1.3)
            end
        end
        return _figure_text!(fig, "Experimental StarAssociation chain traces",
            "$nch chains, $per_ch retained draws per chain. $diag_note.";
            annotation_io, bottom_row = nsel + 1 + offset)
    elseif kind === :predictive
        ppc_rep = SA.predictive_check(res; checks = (:marginal,), seed).result
        rows = ppc_rep.marginal_categories
        offset = _annotation_offset(annotation_io)
        ids = unique(r.criterion for r in rows)
        fig = Figure(; size = something(size, (900, 250 * length(ids) + 100 + 140 * offset)), fontsize = 14)
        for (i, id) in enumerate(ids)
            selected = filter(r -> r.criterion == id, rows)
            ax = Axis(fig[i + offset, 1]; title = id,
                xticks = (1:length(selected), string.([r.display_score for r in selected])),
                xlabel = "Score category", ylabel = "Proportion of rating events")
            for (j, r) in enumerate(selected)
                rangebars!(ax, [j + 0.10], [r.pred_rate_q025], [r.pred_rate_q975];
                    color = :steelblue4, linewidth = 2, whiskerwidth = 8)
                scatter!(ax, [j + 0.10], [r.expected_rate_mean]; color = :steelblue4, markersize = 8)
                scatter!(ax, [j - 0.10], [r.observed_rate]; color = :black, marker = :diamond, markersize = 10)
            end
            xlims!(ax, 0.5, length(selected) + 0.5)
            ylims!(ax, 0, 1)
        end
        return _figure_text!(fig, "Experimental StarAssociation posterior predictive check",
            "Black diamonds: observed category proportions; blue points: posterior mean expected proportions; blue bars: 95% replicated intervals. Conditional on fitted entities and raters; all retained draws. $diag_note.";
            annotation_io, bottom_row = length(ids) + 1 + offset)
    end
    throw(ArgumentError("StarResult supports plot kind = :posterior, :diagnostics, or :predictive"))
end

end
