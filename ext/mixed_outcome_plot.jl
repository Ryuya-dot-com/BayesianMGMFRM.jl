function plot_mixed_report(rep; kind, size = nothing, annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    if rep.schema == B.AdditiveFacets.MIXED_PREDICTION_SCHEMA
        kind === :prediction || throw(ArgumentError("mixed prediction report requires kind=:prediction"))
        outcomes = unique(Symbol(r.outcome) for r in rep.cells)
        cols = min(2, length(outcomes))
        nr = cld(length(outcomes), cols)
        fig = Figure(; size = something(size, (1120, 340 * nr + 130 + 110 * offset)), fontsize = 14)
        is_new = hasproperty(rep, :mode) && Symbol(rep.mode) === :new_owners
        has_pred = hasproperty(rep, :predictive_cells) && !isempty(rep.predictive_cells)
        first_ax = nothing
        for (j, oname) in enumerate(outcomes)
            orows = filter(r -> Symbol(r.outcome) === oname, rep.cells)
            fam = Symbol(first(orows).family)
            primary_metric = fam in (:binomial, :beta_binomial) ? :expected_proportion : :expected_score
            prows = filter(r -> Symbol(r.metric) === primary_metric, orows)
            xs = collect(1:length(prows))
            ylab = fam === :ordinal ? "Expected category score" :
                   fam === :zero_one_inflated_beta ? "Expected score (original units)" :
                   "Expected proportion correct"
            ax = Axis(fig[cld(j, cols) + offset, mod1(j, cols)];
                title = "$(oname) ($(fam))",
                xlabel = "Selected event row",
                ylabel = ylab,
                xticks = (xs, string.([r.row for r in prows])))
            first_ax === nothing && (first_ax = ax)
            if has_pred
                pcells = filter(r -> Symbol(r.outcome) === oname, rep.predictive_cells)
                if length(pcells) == length(prows)
                    plo = fam in (:binomial, :beta_binomial) ? Float64[r.lower / r.trials for r in pcells] : Float64[r.lower for r in pcells]
                    phi = fam in (:binomial, :beta_binomial) ? Float64[r.upper / r.trials for r in pcells] : Float64[r.upper for r in pcells]
                    rangebars!(ax, xs, plo, phi;
                        color = (:darkorange3, 0.45), linewidth = 4, whiskerwidth = 9,
                        label = "Replicated outcome predictive interval")
                end
            end
            rangebars!(ax, xs, Float64[r.lower for r in prows], Float64[r.upper for r in prows];
                color = is_new ? :teal : :steelblue4, linewidth = 2, whiskerwidth = 7,
                label = is_new ? "New-owner population-integrated CrI" : "Known-owner conditional-mean CrI")
            scatter!(ax, xs, Float64[r.median for r in prows];
                color = is_new ? :teal : :steelblue4, markersize = 9,
                marker = is_new ? :rect : :circle,
                label = "Posterior median")
            fam in (:binomial, :beta_binomial) && ylims!(ax, 0.0, 1.0)
        end
        first_ax !== nothing && Legend(fig[nr + 1 + offset, 1:cols], first_ax; orientation = :horizontal, framevisible = false)
        mode_note = is_new ?
            "NEW-OWNER prediction (mode=:new_owners, new_owners=$(collect(rep.new_owners)), seed=$(rep.seed)): fresh latent owner effects were drawn from fitted population priors at each posterior draw; zero-effect substitution was NOT used. " :
            "KNOWN-OWNER prediction (mode=:known_owners): posterior medians and $(round(100 * rep.interval; digits = 1))% equal-tailed CrIs condition on stored owner identities and attributes. "
        pred_note = has_pred ? "Orange bars show future-event outcome predictive intervals; inner bars show conditional expectation CrIs. " :
            "Intervals describe conditional expectations, not single-event outcome predictive intervals. "
        note = mode_note * pred_note *
            "Whole-fit numerical qualification: $(rep.qualification.qualified). " * join(rep.warnings, " ")
        title = is_new ? "Mixed-outcome model · new-owner population-integrated predictions" :
                         "Mixed-outcome model · known-owner conditional predictions"
        return _figure_text!(fig, title, note; annotation_io, bottom_row = nr + 2 + offset, columns = cols)
    end

    kind === :predictive || throw(ArgumentError("mixed predictive report requires kind=:predictive"))
    prior = Symbol(rep.kind) === :prior_predictive
    outcomes = unique(Symbol(r.outcome) for r in rep.cells)
    has_paired = hasproperty(rep, :paired_cells) && !isempty(rep.paired_cells)
    n_panels = length(outcomes) + (has_paired ? 1 : 0)
    cols = min(2, n_panels)
    nr = cld(n_panels, cols)
    fig = Figure(; size = something(size, (1160, 340 * nr + 130 + 110 * offset)), fontsize = 14)
    first_ax = nothing

    for (j, oname) in enumerate(outcomes)
        orows = filter(r -> Symbol(r.outcome) === oname, rep.cells)
        fam = Symbol(first(orows).family)
        # Keep key summary statistics per outcome in native units / rates
        sel_rows = if fam === :ordinal
            filter(r -> startswith(string(r.metric), "prop_cat_"), orows)
        elseif fam === :zero_one_inflated_beta
            filter(r -> Symbol(r.metric) in (:lower_rate, :upper_rate, :mean_score, :sd_score), orows)
        else
            filter(r -> Symbol(r.metric) in (:zero_rate, :perfect_rate, :mean_proportion, :sd_proportion), orows)
        end
        isempty(sel_rows) && (sel_rows = orows)
        xs = collect(1:length(sel_rows))
        xlabels = [string(r.label) == "\"all\"" ? string(r.metric) : "$(r.label):$(r.metric)" for r in sel_rows]
        ax = Axis(fig[cld(j, cols) + offset, mod1(j, cols)];
            title = "Marginal · $(oname) ($(fam))",
            xlabel = "Summary statistic",
            ylabel = fam === :zero_one_inflated_beta ? "Rate / original-unit statistic" : "Proportion / statistic",
            xticks = (xs, xlabels),
            xticklabelrotation = pi / 6)
        first_ax === nothing && (first_ax = ax)
        keep = findall(r -> r.lower !== nothing, sel_rows)
        if !isempty(keep)
            rangebars!(ax, keep, Float64[sel_rows[i].lower for i in keep], Float64[sel_rows[i].upper for i in keep];
                color = :steelblue4, linewidth = 2, whiskerwidth = 7)
            scatter!(ax, keep, Float64[sel_rows[i].median for i in keep];
                color = :steelblue4, markersize = 8, label = "Replicated median / interval")
        end
        obs = findall(r -> r.observed !== nothing, sel_rows)
        isempty(obs) || scatter!(ax, obs, Float64[sel_rows[i].observed for i in obs];
            color = :black, marker = :diamond, markersize = 9, label = "Observed")
    end

    if has_paired
        pj = length(outcomes) + 1
        prows = filter(r -> Symbol(r.metric) in (:pearson_r, :spearman_rho), rep.paired_cells)
        isempty(prows) && (prows = rep.paired_cells)
        xs = collect(1:length(prows))
        xlabels = [(string(r.group) == "all" ? "$(r.outcome_left)–$(r.outcome_right)\n$(r.metric)" :
            "$(r.group): $(r.outcome_left)–$(r.outcome_right)\n$(r.metric)") for r in prows]
        ax = Axis(fig[cld(pj, cols) + offset, mod1(pj, cols)];
            title = "Joint within-event paired association",
            xlabel = "Co-observed outcome pair & concordance statistic",
            ylabel = "Correlation across co-observed events",
            xticks = (xs, xlabels),
            xticklabelrotation = length(prows) > 4 ? pi / 6 : 0.0)
        hlines!(ax, [0.0]; color = :gray60, linestyle = :dash)
        keep = findall(r -> r.lower !== nothing, prows)
        if !isempty(keep)
            rangebars!(ax, keep, Float64[prows[i].lower for i in keep], Float64[prows[i].upper for i in keep];
                color = :purple4, linewidth = 2, whiskerwidth = 7)
            scatter!(ax, keep, Float64[prows[i].median for i in keep];
                color = :purple4, markersize = 8, label = "Replicated median / interval")
        end
        obs = findall(r -> r.observed !== nothing, prows)
        isempty(obs) || scatter!(ax, obs, Float64[prows[i].observed for i in obs];
            color = :black, marker = :diamond, markersize = 9, label = "Observed")
        ylims!(ax, -1.05, 1.05)
    end

    first_ax !== nothing && Legend(fig[nr + 1 + offset, 1:cols], first_ax; orientation = :horizontal, framevisible = false)
    title = (prior ? "PRIOR" : "POSTERIOR") * " predictive check · mixed-outcome joint model"
    hasproperty(rep, :replications_complete) && !rep.replications_complete && (title *= " · incomplete numerical replicas")
    note = "$(rep.ndraws) replicated datasets; $(round(100 * rep.interval; digits = 1))% pointwise predictive intervals. " *
        (prior ? "Parameters drawn from the declared joint prior; observed values are not overlaid. " :
                 "Black diamonds are observed values; each replica shares one joint posterior draw across all outcomes and events. ") *
        (has_paired ? "Joint panel checks within-event co-observed outcome concordance (Pearson r and Spearman rho) alongside per-outcome marginals. " : "") *
        join(rep.warnings, " ")
    _figure_text!(fig, title, note; annotation_io, bottom_row = nr + 2 + offset, columns = cols)
end

function plot_mixed_event_comparison(rep; size = nothing, annotation_io = stdout)
    offset = _annotation_offset(annotation_io)
    paired = rep.schema == B._MIXED_EVENT_COMPARISON_SCHEMA
    mcse_text = rep.mcse === nothing ? "unavailable; importance weights or precision unresolved" : string(rep.mcse)
    fig = Figure(; size = something(size, (1050, 460 + 100 * offset)), fontsize = 14)
    if paired
        ax = Axis(fig[1 + offset, 1]; xlabel = "$(rep.names[2]) event log score", ylabel = "$(rep.names[1]) event log score")
        scatter!(ax, [r.baseline for r in rep.rows], [r.primary for r in rep.rows];
            color = [r.eligible ? :steelblue4 : :darkorange for r in rep.rows])
        lo, hi = extrema([r.primary for r in rep.rows] ∪ [r.baseline for r in rep.rows])
        lines!(ax, [lo, hi], [lo, hi]; color = :gray50, linestyle = :dash)
        bx = Axis(fig[1 + offset, 2]; xlabel = "Event row", ylabel = "Primary − baseline log score")
        scatter!(bx, [r.row for r in rep.rows], [r.difference for r in rep.rows];
            color = [r.eligible ? :steelblue4 : :darkorange for r in rep.rows])
        hlines!(bx, [0.0]; color = :gray50)
        note = "Paired event-wise ELPD difference: $(round(rep.difference; digits = 3)); computational MCSE: $mcse_text. "
    else
        ax = Axis(fig[1 + offset, 1]; xlabel = "Event row", ylabel = "PSIS Pareto k")
        scatter!(ax, [r.row for r in rep.rows], [r.diagnostics.pareto_k for r in rep.rows];
            color = [r.eligible ? :steelblue4 : :darkorange for r in rep.rows])
        bx = Axis(fig[1 + offset, 2]; xlabel = "Event row", ylabel = "Joint event log predictive score")
        scatter!(bx, [r.row for r in rep.rows], [r.log_score for r in rep.rows]; color = :steelblue4)
        note = "Event-wise joint ELPD: $(round(rep.elpd; digits = 3)); computational MCSE: $mcse_text. "
    end
    note *= "Status: $(rep.status). Known owners across observed event outcomes. Orange marks unresolved weights/precision. Population sampling SE and automatic ranking are not supplied. " * join(rep.warnings, " ")
    _figure_text!(fig, "Mixed-outcome model · event-wise predictive comparison", note; annotation_io, bottom_row = 2 + offset, columns = 2)
end
