using BayesianMGMFRM, CairoMakie

"""
    pathway_map(fit_result::MFRMFit; interval = 0.95)

Plot item, rater and person locations against infit, using all retained draws.
Points are marginal medians; horizontal and vertical lines show separate central
credible intervals, not a joint credible region. This is a diagnostic display,
not a model-selection rule. Include this example after loading CairoMakie.
"""
function pathway_map(fit_result::MFRMFit; interval = 0.95)
    rows = diagnostic_map_data(fit_result; metrics = :infit,
        include_thresholds = false, interval)
    figure = Figure(size = (1250, 740), fontsize = 18)
    Label(figure[1, 1:3], "MFRM Pathway Map", fontsize = 26)
    panels = ((:person, "+ Person ability"), (:rater, "− Rater severity"),
        (:item, "− Item difficulty"))
    axes = Axis[]
    for (column, (facet, title)) in enumerate(panels)
        ax = Axis(figure[2, column]; title, xlabel = "Infit mean square",
            ylabel = column == 1 ? "Location (logits)" : "")
        push!(axes, ax)
        vlines!(ax, [1.0]; color = :gray50, linestyle = :dash)
        selected = filter(row -> row.facet == facet, rows)
        for row in selected
            x, y = row.fit_median, row.logit_median
            any(ismissing, (x, y, row.fit_lower, row.fit_upper,
                row.logit_lower, row.logit_upper)) && error(
                "Missing summaries for $facet $(row.level); inspect diagnostic_map_data first.")
            lines!(ax, [row.fit_lower, row.fit_upper], [y, y]; color = :steelblue)
            lines!(ax, [x, x], [row.logit_lower, row.logit_upper]; color = :steelblue)
            scatter!(ax, [x], [y]; color = :steelblue, markersize = 11)
            text!(ax, x, y; text = string(row.level), offset = (8, 8), fontsize = 15)
        end
        xlims!(ax, 0, max(1.2, maximum(row.fit_upper for row in selected) * 1.15))
    end
    linkyaxes!(axes...)
    Label(figure[3, 1:3],
        "Points: medians; bars: $(100interval)% marginal intervals on each axis.\n" *
        "Infit = 1 is a reference, not an automatic acceptance threshold.\n" *
        "Review sampler diagnostics and predictive checks before interpreting this map.",
        fontsize = 16, tellwidth = false)
    return figure
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia pathway_map.jl FIT_CACHE OUTPUT.svg")
    save(ARGS[2], pathway_map(load_fit_cache(ARGS[1])))
end
