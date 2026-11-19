# CairoMakie visualizations for `StanAdapter` and `PortableHandoff`

function plot_stan_adapter(x; kind::Symbol = :posterior, parameters = nothing,
        interval::Real = 0.95, max_parameters::Int = 30, size = nothing,
        annotation_io = stdout, reference::Real = 0.0)
    SA = B.StanAdapter
    offset = _annotation_offset(annotation_io)

    if hasproperty(x, :schema) && String(x.schema) == SA.COMPARISON_SCHEMA
        kind === :comparison || throw(ArgumentError("use kind = :comparison for StanAdapter compare_models reports"))
        rows = collect(x.rows)
        n_m = length(rows)
        labels = [String(r.model_label) for r in rows]
        elpds = [Float64(r.elpd) for r in rows]
        diffs = [Float64(r.elpd_difference) for r in rows]
        ses = [Float64(r.se_difference) for r in rows]

        fig = Figure(; size = something(size, (1040, 220 + 70 * n_m + 140 * offset)), fontsize = 14)
        ax1 = Axis(fig[1 + offset, 1];
            title = "Total ELPD ($(uppercase(String(x.criterion))), unit = $(x.unit))",
            xlabel = "Expected log predictive density (higher is better)",
            yticks = (1:n_m, labels), yreversed = true, ygridvisible = false)
        ax2 = Axis(fig[1 + offset, 2];
            title = "Difference from top-ranked model (±2 SE)",
            xlabel = "ΔELPD ± 2 SE",
            yticks = (1:n_m, fill("", n_m)), yreversed = true, ygridvisible = false)
        vlines!(ax2, [0.0]; color = :gray60, linestyle = :dash)

        for i in 1:n_m
            col = Bool(rows[i].qualified) ? :steelblue4 : :darkorange3
            scatter!(ax1, [elpds[i]], [i]; color = col, markersize = 12,
                marker = i == 1 ? :diamond : :circle)
            lo_d = diffs[i] - 2.0 * ses[i]
            hi_d = diffs[i] + 2.0 * ses[i]
            if ses[i] > 0.0
                rangebars!(ax2, [i], [lo_d], [hi_d]; direction = :x, color = col, linewidth = 2.2, whiskerwidth = 10)
            end
            scatter!(ax2, [diffs[i]], [i]; color = col, markersize = 11,
                marker = i == 1 ? :diamond : :circle)
        end
        e_span = max(maximum(elpds) - minimum(elpds), 1.0)
        xlims!(ax1, minimum(elpds) - 0.18 * e_span, maximum(elpds) + 0.18 * e_span)
        d_lo = minimum(diffs .- 2.0 .* ses)
        d_hi = maximum(diffs .+ 2.0 .* ses)
        d_span = max(d_hi - d_lo, 1.0)
        xlims!(ax2, d_lo - 0.15 * d_span, max(0.0, d_hi) + 0.15 * d_span)
        ylims!(ax1, n_m + 0.6, 0.4)
        ylims!(ax2, n_m + 0.6, 0.4)

        title = "StanAdapter Predictive Model Comparison ($(uppercase(String(x.criterion))))"
        caption = "Compared across N = $(x.n_units) bound `$(x.unit)` units (binding $(String(x.observation_binding)[1:12])...). " *
            "Blue: whole-fit MCMC qualified; orange: unqualified. " * String(x.warning)
        return _figure_text!(fig, title, caption; annotation_io, bottom_row = 2 + offset, columns = 2)
    end

    if hasproperty(x, :schema) && String(x.schema) == SA.PRIOR_SENSITIVITY_SCHEMA
        kind === :prior_sensitivity || throw(ArgumentError("use kind = :prior_sensitivity for StanAdapter prior_sensitivity reports"))
        all_rows = collect(x.rows)
        rows = parameters === nothing ? all_rows[1:min(length(all_rows), max_parameters)] :
            [r for r in all_rows if String(r.parameter) in String.(parameters)]
        isempty(rows) && throw(ArgumentError("no matching parameters in prior_sensitivity report"))
        n_p = length(rows)
        labels = [String(r.parameter) for r in rows]

        fig = Figure(; size = something(size, (960, 220 + 36 * n_p + 140 * offset)), fontsize = 13)
        ax = Axis(fig[1 + offset, 1];
            title = "Baseline vs. Alternative Prior (`$(x.alternative)`): Pareto k = $(round(Float64(x.pareto_k); digits=3)), Neff = $(round(Float64(x.effective_sample_size); digits=1))",
            xlabel = "Parameter estimate ($(round(100 * Float64(x.interval); digits=1))% CrI)",
            yticks = (1:n_p, labels), yreversed = true, ygridvisible = false)
        vlines!(ax, [Float64(reference)]; color = :gray65, linestyle = :dash)

        for (i, r) in enumerate(rows)
            y_base = i - 0.14
            y_alt = i + 0.14
            rangebars!(ax, [y_base], [Float64(r.baseline_lower)], [Float64(r.baseline_upper)];
                direction = :x, color = :steelblue4, linewidth = 2.0, whiskerwidth = 7)
            scatter!(ax, [Float64(r.baseline_mean)], [y_base]; color = :steelblue4, markersize = 8, marker = :circle,
                label = i == 1 ? "Baseline prior" : nothing)

            alt_col = String(x.status) == "reliable" ? :darkorange3 : :firebrick
            rangebars!(ax, [y_alt], [Float64(r.shifted_lower)], [Float64(r.shifted_upper)];
                direction = :x, color = alt_col, linewidth = 2.0, whiskerwidth = 7)
            scatter!(ax, [Float64(r.shifted_mean)], [y_alt]; color = alt_col, markersize = 8, marker = :rect,
                label = i == 1 ? "Reweighted (`$(x.alternative)`)" : nothing)
        end
        ylims!(ax, n_p + 0.6, 0.4)
        Legend(fig[2 + offset, 1], ax; orientation = :horizontal, framevisible = false, tellwidth = false)

        title = "PSIS Prior-Sensitivity Reweighting (`$(x.alternative)`)"
        caption = "Blue circles: baseline Stan posterior means and $(round(100 * Float64(x.interval); digits=1))% CrIs; " *
            "orange/red squares: PSIS importance-reweighted estimates under `$(x.alternative)` (status = $(x.status), " *
            "Pareto k = $(round(Float64(x.pareto_k); digits=3))). High Pareto k (> $(x.pareto_k_threshold)) requires direct refitting."
        return _figure_text!(fig, title, caption; annotation_io, bottom_row = 3 + offset)
    end

    # Fit or saved REPORT_SCHEMA
    is_saved_rep = !(x isa SA.Fit) && hasproperty(x, :schema) && String(x.schema) == SA.REPORT_SCHEMA
    if !(x isa SA.Fit || is_saved_rep)
        throw(ArgumentError("unsupported input for plot_stan_adapter"))
    end

    if kind === :posterior
        rep = is_saved_rep ? x : SA.report(x; parameters, interval)
        all_rows = collect(rep.posterior)
        rows = (is_saved_rep && parameters !== nothing) ?
            [r for r in all_rows if String(r.parameter) in String.(parameters)] :
            all_rows[1:min(length(all_rows), max_parameters)]
        isempty(rows) && throw(ArgumentError("no parameters selected for posterior plot"))
        n_p = length(rows)
        labels = ["$(r.parameter) [$(r.block)]" for r in rows]

        fig = Figure(; size = something(size, (940, 170 + 30 * n_p + 140 * offset)), fontsize = 13)
        ax = Axis(fig[1 + offset, 1];
            xlabel = "Posterior mean and credible interval (logit / model scale)",
            yticks = (1:n_p, labels), yreversed = true, ygridvisible = false)
        vlines!(ax, [Float64(reference)]; color = :gray65, linestyle = :dash)

        lo_min = minimum(Float64(r.lower) for r in rows)
        hi_max = maximum(Float64(r.upper) for r in rows)
        span = max(hi_max - lo_min, 0.5)
        for (i, r) in enumerate(rows)
            fixed = Bool(r.structurally_fixed)
            lo_v = Float64(r.lower)
            hi_v = Float64(r.upper)
            m_v = Float64(r.mean)
            excludes_ref = lo_v > Float64(reference) || hi_v < Float64(reference)
            col = fixed ? :gray45 : (excludes_ref ? :steelblue4 : :slategray)
            if !fixed
                rangebars!(ax, [i], [lo_v], [hi_v]; direction = :x, color = col, linewidth = 2.1, whiskerwidth = 8)
            end
            scatter!(ax, [m_v], [i]; color = col, markersize = 9,
                marker = fixed ? :diamond : (excludes_ref ? :rect : :circle))
        end
        xlims!(ax, lo_min - 0.10 * span, hi_max + 0.10 * span)
        ylims!(ax, n_p + 0.6, 0.4)

        qual_ok = Bool(rep.qualification.qualified)
        title = "Posterior Parameter Estimates (StanAdapter / PortableHandoff)"
        caption = "Points show posterior means; bars show central credible intervals; diamonds mark fixed anchors. " *
            "Squares exclude reference $(reference); circles include $(reference). " *
            "Whole-fit MCMC qualification: $(qual_ok ? "passed" : "not passed"). Source hash: $(String(rep.source_content_hash)[1:12])..."
        return _figure_text!(fig, title, caption; annotation_io, bottom_row = 2 + offset)

    elseif kind === :diagnostics
        if is_saved_rep
            hasproperty(x, :traces) && x.traces !== nothing ||
                throw(ArgumentError("saved StanAdapter report requires `fit_report(fit; include_draws = true)` for trace plotting"))
            tr = x.traces
            pnames_all = String.(tr.parameter_names)
            chosen = parameters === nothing ? pnames_all[1:min(length(pnames_all), 6)] : String.(parameters)
            c_ids = Int.(tr.chain_ids)
            iters = Int.(tr.iterations)
            n_ch = length(unique(c_ids))
            S = length(c_ids)
            mat = Matrix{Float64}(undef, S, length(chosen))
            for (j, nm) in enumerate(chosen)
                col_i = findfirst(==(nm), pnames_all)
                col_i === nothing && throw(ArgumentError("parameter $(repr(nm)) not stored in report traces"))
                for s in 1:S
                    mat[s, j] = Float64(tr.values[s][col_i])
                end
            end
            qual_ok = Bool(x.qualification.qualified)
        else
            r = SA.checked(x)
            free_names = [nm for nm in r.parameter_names if !(nm in r.fixed_name_set)]
            chosen = parameters === nothing ? free_names[1:min(length(free_names), 6)] : [String(p) for p in parameters]
            sel = SA._select_columns(r; parameters = chosen)
            mat = sel.values
            c_ids = r.run.chain_ids
            iters = r.run.iterations
            n_ch = r.run.controls.chains
            qual_ok = SA.qualify(x).qualified
        end
        nsel = length(chosen)
        colors = Makie.wong_colors()
        fig = Figure(; size = something(size, (980, 175 * nsel + 100 + 140 * offset)), fontsize = 13)
        for j in 1:nsel
            ax = Axis(fig[j + offset, 1]; title = chosen[j],
                xlabel = j == nsel ? "Retained post-warmup iteration" : "",
                ylabel = "Value")
            for c in 1:n_ch
                mask = findall(==(c), c_ids)
                lines!(ax, iters[mask], mat[mask, j];
                    color = colors[mod1(c, length(colors))], linewidth = 1.25,
                    label = j == 1 ? "Chain $c" : nothing)
            end
            j == 1 && axislegend(ax; position = :rt, orientation = :horizontal, framevisible = true, backgroundcolor = (:white, 0.85))
        end
        title = "MCMC Chain Trace Diagnostics ($n_ch Chains)"
        caption = "Post-warmup retained draws in original chain/iteration order across $n_ch chains. " *
            "Whole-fit MCMC qualification: $(qual_ok ? "passed" : "not passed"). Visual mixing alone does not establish convergence."
        return _figure_text!(fig, title, caption; annotation_io, bottom_row = nsel + 1 + offset)

    elseif kind === :wright
        rep = is_saved_rep ? x : SA.report(x; interval)
        rows = collect(rep.posterior)
        blocks = unique(Symbol(r.block) for r in rows)
        fig = Figure(; size = something(size, (max(880, 260 * length(blocks)), 560 + 140 * offset)), fontsize = 13)
        all_means = [Float64(r.mean) for r in rows]
        y_lo = minimum(all_means) - 0.5
        y_hi = maximum(all_means) + 0.5
        for (bi, blk) in enumerate(blocks)
            b_rows = [r for r in rows if Symbol(r.block) === blk]
            ax = Axis(fig[1 + offset, bi];
                title = String(blk),
                ylabel = bi == 1 ? "Logit location (posterior mean)" : "",
                xticksvisible = false, xticklabelsvisible = false, xgridvisible = false)
            ylims!(ax, y_lo, y_hi)
            hlines!(ax, [0.0]; color = :gray70, linestyle = :dash)
            if blk === :person && length(b_rows) > 12
                hist!(ax, [Float64(r.mean) for r in b_rows]; direction = :x, bins = min(15, max(5, div(length(b_rows), 2))),
                    color = (:steelblue4, 0.65), strokewidth = 1, strokecolor = :steelblue4)
            else
                n_b = length(b_rows)
                for (k, r) in enumerate(b_rows)
                    xv = n_b == 1 ? 0.0 : -0.30 + 0.60 * ((k - 1) / (n_b - 1))
                    mv = Float64(r.mean)
                    scatter!(ax, [xv], [mv]; color = Bool(r.structurally_fixed) ? :gray45 : :steelblue4,
                        marker = Bool(r.structurally_fixed) ? :diamond : :circle, markersize = 9)
                    align_h = xv > 0.08 ? :right : :left
                    dx = xv > 0.08 ? -0.04 : 0.04
                    text!(ax, xv + dx, mv; text = String(r.parameter), align = (align_h, :center), fontsize = 11)
                end
                xlims!(ax, -0.65, 0.65)
            end
        end
        title = "Shared-Scale Facet Map (StanAdapter)"
        caption = "Posterior mean locations grouped by declared parameter block in `roles.parameters`. Diamonds mark fixed anchors."
        return _figure_text!(fig, title, caption; annotation_io, bottom_row = 2 + offset, columns = length(blocks))
    end

    throw(ArgumentError("StanAdapter plot supports kind in (:posterior, :diagnostics, :wright, :comparison, :prior_sensitivity); got $(repr(kind))"))
end
