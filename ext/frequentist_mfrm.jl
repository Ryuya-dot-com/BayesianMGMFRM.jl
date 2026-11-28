const FM = B.FrequentistMFRM

function plot_frequentist_mfrm(x; kind::Symbol = :posterior, size = nothing, annotation_io = stdout, facet = nothing)
    rep = x isa FM.Fit ? FM.report(x) : FM.check_loaded_report(x)
    if string(rep.schema) == FM.COMPARISON_SCHEMA
        kind === :comparison || throw(ArgumentError("use kind = :comparison for FrequentistMFRM model comparison reports"))
        return _plot_frequentist_comparison(rep; size, annotation_io)
    end
    kind in (:posterior, :wright, :pathway) ||
        throw(ArgumentError("FrequentistMFRM plot supports kind = :posterior, :wright, or :pathway; got $(repr(kind))"))
    kind === :posterior && return _plot_frequentist_estimates(rep; size, annotation_io, facet)
    kind === :wright && return _plot_frequentist_wright(rep; size, annotation_io)
    return _plot_frequentist_pathway(rep; size, annotation_io, facet)
end

_fm_num(v) = v isa Real && isfinite(v) ? Float64(v) : NaN

function _plot_frequentist_estimates(rep; size = nothing, annotation_io = stdout, facet = nothing)
    s = rep.summary
    offset = _annotation_offset(annotation_io)
    frows = facet === nothing ? collect(rep.facet_measures) :
            [r for r in rep.facet_measures if string(r.facet) == string(facet)]
    srows = facet === nothing ? collect(rep.step_measures) : []
    labels = String[]
    ests = Float64[]
    los = Float64[]
    his = Float64[]
    fixeds = Bool[]

    for r in frows
        lbl = (haskey(r, :parameter) && string(r.level) == string(r.parameter)) ? string(r.parameter) : "$(r.facet)[$(r.level)]"
        push!(labels, lbl)
        push!(ests, _fm_num(r.estimate))
        push!(los, _fm_num(get(r, :lower, NaN)))
        push!(his, _fm_num(get(r, :upper, NaN)))
        push!(fixeds, Bool(r.fixed))
    end
    for r in srows
        push!(labels, "$(r.group):$(r.label)")
        push!(ests, _fm_num(r.estimate))
        push!(los, _fm_num(get(r, :lower, NaN)))
        push!(his, _fm_num(get(r, :upper, NaN)))
        push!(fixeds, Bool(r.fixed))
    end
    nrows = length(labels)
    nrows > 0 || throw(ArgumentError("no matching facet/step rows to plot"))

    fig = Figure(; size = something(size, (960, max(360, 120 + 30 * nrows) + 160 * offset)), fontsize = 14)
    ax = Axis(fig[1 + offset, 1];
        title = "Structural facet & step estimates ($(uppercase(string(s.method))) · $(uppercase(string(s.model))))",
        xlabel = "Logit estimate and 95% asymptotic Wald interval",
        yticks = (1:nrows, labels),
        yreversed = true,
        ygridvisible = false)
    vlines!(ax, [0.0]; color = :gray60, linestyle = :dash)
    for i in 1:nrows
        isfinite(ests[i]) || continue
        col = fixeds[i] ? :gray35 : :steelblue4
        mk = fixeds[i] ? :diamond : :circle
        if !fixeds[i] && isfinite(los[i]) && isfinite(his[i])
            rangebars!(ax, [i], [los[i]], [his[i]]; direction = :x, color = col, linewidth = 2, whiskerwidth = 8)
        end
        scatter!(ax, [ests[i]], [i]; color = col, marker = mk, markersize = 9)
    end
    ylims!(ax, nrows + 0.6, 0.4)
    note = "Frequentist $(uppercase(string(s.method))) ($(uppercase(string(s.model)))) point estimates and 95% asymptotic Wald intervals " *
        "from exact constrained observed-information SEs (NOT Bayesian credible intervals). Diamonds mark fixed identification/anchor constraints. " *
        "Converged=$(s.converged), stationarity_qualified=$(s.stationarity_qualified), logLik=$(round(Float64(s.loglikelihood); digits=3))."
    return _figure_text!(fig, "Frequentist 1D MFRM parameter summary", note; annotation_io, bottom_row = 2 + offset)
end

function _plot_frequentist_wright(rep; size = nothing, annotation_io = stdout)
    s = rep.summary
    offset = _annotation_offset(annotation_io)
    p_vals = Float64[_fm_num(r.estimate) for r in rep.person_scores if isfinite(_fm_num(r.estimate))]
    fnames = [string(fn) for fn in s.facet_names]
    ncols = 2 + length(fnames)
    fig = Figure(; size = something(size, (260 * ncols, 560 + 160 * offset)), fontsize = 13)

    ax_p = Axis(fig[1 + offset, 1];
        title = s.method == "mmle" || s.method === :mmle ? "Persons (EAP)" : "Persons (JMLE)",
        xlabel = "Count", ylabel = "Logit measure")
    if !isempty(p_vals)
        hist!(ax_p, p_vals; direction = :x, bins = max(6, min(18, round(Int, sqrt(length(p_vals)) * 2))),
            color = (:steelblue4, 0.65), strokecolor = :steelblue4, strokewidth = 1)
    end
    hlines!(ax_p, [0.0]; color = :gray60, linestyle = :dash)

    other_axes = Axis[ax_p]
    for (j, fn) in enumerate(fnames)
        ax_f = Axis(fig[1 + offset, 1 + j]; title = fn, xlabel = "Difficulty / Severity",
            xticksvisible = false, xticklabelsvisible = false)
        hideydecorations!(ax_f; grid = false)
        hlines!(ax_f, [0.0]; color = :gray60, linestyle = :dash)
        frows = sort([r for r in rep.facet_measures if string(r.facet) == fn]; by = r -> _fm_num(r.estimate))
        n_cols_f = min(max(length(frows), 1), 3)
        x_slots = n_cols_f == 1 ? [0.0] : n_cols_f == 2 ? [-0.24, 0.16] : [-0.36, -0.02, 0.32]
        for (idx, r) in enumerate(frows)
            v = _fm_num(r.estimate)
            isfinite(v) || continue
            x_jit = x_slots[mod1(idx, n_cols_f)]
            scatter!(ax_f, [x_jit], [v]; color = Bool(r.fixed) ? :gray35 : :firebrick,
                marker = Bool(r.fixed) ? :diamond : :circle, markersize = 9)
            text!(ax_f, x_jit, v; text = string(r.level), offset = (7, 0), align = (:left, :center), fontsize = 11)
        end
        xlims!(ax_f, -0.58, 1.05)
        push!(other_axes, ax_f)
    end

    ax_s = Axis(fig[1 + offset, ncols]; title = "Steps", xlabel = "Thresholds",
        xticksvisible = false, xticklabelsvisible = false)
    hideydecorations!(ax_s; grid = false)
    hlines!(ax_s, [0.0]; color = :gray60, linestyle = :dash)
    for (idx, r) in enumerate(rep.step_measures)
        v = _fm_num(r.estimate)
        isfinite(v) || continue
        x_jit = -0.25 + 0.5 * ((idx - 1) % 2)
        scatter!(ax_s, [x_jit], [v]; color = :darkgreen, marker = :rect, markersize = 8)
        lbl = string(r.group) == "Common" ? string(r.label) : "$(r.group):$(r.step)"
        text!(ax_s, x_jit, v; text = lbl, offset = (6, 0), align = (:left, :center), fontsize = 10)
    end
    xlims!(ax_s, -0.6, 0.9)
    push!(other_axes, ax_s)
    linkyaxes!(other_axes...)

    all_y = vcat(p_vals,
        Float64[_fm_num(r.estimate) for r in rep.facet_measures if isfinite(_fm_num(r.estimate))],
        Float64[_fm_num(r.estimate) for r in rep.step_measures if isfinite(_fm_num(r.estimate))])
    if !isempty(all_y)
        lo, hi = extrema(all_y)
        pad = max(0.3, 0.12 * (hi - lo))
        ylims!(ax_p, lo - pad, hi + pad)
    end
    note = "Shared-logit Wright map ($(uppercase(string(s.method))) · $(uppercase(string(s.model)))). " *
        "Left histogram shows finite person point estimates (not a population density); facet columns show difficulty/severity point estimates."
    return _figure_text!(fig, "Frequentist 1D MFRM Wright map", note; annotation_io, bottom_row = 2 + offset, columns = ncols)
end

function _plot_frequentist_pathway(rep; size = nothing, annotation_io = stdout, facet = nothing)
    s = rep.summary
    offset = _annotation_offset(annotation_io)
    fnames = facet === nothing ? [string(fn) for fn in s.facet_names] : [string(facet)]
    ncols = length(fnames)
    fig = Figure(; size = something(size, (420 * ncols, 500 + 160 * offset)), fontsize = 13)
    axes = Axis[]
    for (j, fn) in enumerate(fnames)
        ax = Axis(fig[1 + offset, j]; title = fn, xlabel = "Infit MNSQ",
            ylabel = j == 1 ? "Logit measure" : "")
        j > 1 && hideydecorations!(ax; grid = false)
        vlines!(ax, [1.0]; color = :gray55, linestyle = :dash)
        hlines!(ax, [0.0]; color = :gray75, linestyle = :dot)
        frows = [r for r in rep.facet_measures if string(r.facet) == fn]
        inf_vals = Float64[_fm_num(get(r, :infit, NaN)) for r in frows if isfinite(_fm_num(get(r, :infit, NaN)))]
        xmin, xmax = isempty(inf_vals) ? (0.8, 1.2) : extrema(vcat(inf_vals, [1.0]))
        xspan = max(xmax - xmin, 0.06)
        xmid = 0.5 * (xmin + xmax)
        xlims!(ax, xmin - 0.18 * xspan, xmax + 0.18 * xspan)
        for (idx, r) in enumerate(frows)
            inf_v = _fm_num(get(r, :infit, NaN))
            est_v = _fm_num(r.estimate)
            (isfinite(inf_v) && isfinite(est_v)) || continue
            lo_v = _fm_num(get(r, :lower, NaN))
            hi_v = _fm_num(get(r, :upper, NaN))
            col = Bool(r.fixed) ? :gray35 : :steelblue4
            if !Bool(r.fixed) && isfinite(lo_v) && isfinite(hi_v)
                rangebars!(ax, [inf_v], [lo_v], [hi_v]; color = col, linewidth = 1.8, whiskerwidth = 7)
            end
            scatter!(ax, [inf_v], [est_v]; color = col, marker = Bool(r.fixed) ? :diamond : :circle, markersize = 10)
            on_right = inf_v > xmid
            text!(ax, inf_v, est_v; text = "$(r.level) (n=$(r.n_ratings))",
                offset = on_right ? (-8, 0) : (8, 0),
                align = on_right ? (:right, :center) : (:left, :center), fontsize = 11)
        end
        push!(axes, ax)
    end
    length(axes) > 1 && linkyaxes!(axes...)
    note = "Pathway map ($(uppercase(string(s.method))) · $(uppercase(string(s.model)))): horizontal axis shows descriptive Infit MNSQ " *
        "(1.0 reference dashed line, not a hard rejection cutoff); vertical bars show 95% asymptotic Wald intervals."
    return _figure_text!(fig, "Frequentist 1D MFRM Pathway map", note; annotation_io, bottom_row = 2 + offset, columns = ncols)
end

function _plot_frequentist_comparison(rep; size = nothing, annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    rows = collect(rep.rows)
    n = length(rows)
    labels = [string(r.model_label) for r in rows]
    deltas = [Float64(r.delta_criterion) for r in rows]
    lls = [Float64(r.loglikelihood) for r in rows]
    fig = Figure(; size = something(size, (960, max(320, 120 + 55 * n) + 150 * offset)), fontsize = 14)
    ax1 = Axis(fig[1 + offset, 1]; title = "Δ$(uppercase(string(rep.criterion))) from top-ranked model",
        xlabel = "Δ$(uppercase(string(rep.criterion))) (lower is better)", yticks = (1:n, labels), yreversed = true)
    ax2 = Axis(fig[1 + offset, 2]; title = "Marginal log-likelihood",
        xlabel = "Log-likelihood", yticks = (1:n, labels), yreversed = true)
    hideydecorations!(ax2; grid = false)
    linkyaxes!(ax1, ax2)
    barplot!(ax1, 1:n, deltas; direction = :x, color = (:steelblue4, 0.8))
    scatter!(ax2, lls, 1:n; color = :firebrick, markersize = 11)
    ax1.yreversed[] = true; ax2.yreversed[] = true
    note = "Frequentist MMLE marginal information-criterion comparison ($(rep.quad_points)-point $(rep.quadrature) quadrature). " * string(rep.warning)
    return _figure_text!(fig, "Frequentist MMLE model comparison", note; annotation_io, bottom_row = 2 + offset, columns = 2)
end
