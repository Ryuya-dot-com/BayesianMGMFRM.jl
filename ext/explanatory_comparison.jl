function plot_explanatory_comparison(rep;size=nothing,annotation_io=stdout)
    rep.schema in (B._MIXED_EVENT_CRITERIA_SCHEMA,B._MIXED_EVENT_COMPARISON_SCHEMA) && return plot_mixed_event_comparison(rep;size,annotation_io)
    rep.schema in (B._BOUNDED_CRITERIA_SCHEMA,B._BOUNDED_COMPARISON_SCHEMA,B._COUNT_CRITERIA_SCHEMA,B._COUNT_COMPARISON_SCHEMA) && return plot_bounded_comparison(rep;size,annotation_io)
    is_mixed=rep.schema in (B._MIXED_PROFILE_CRITERIA_SCHEMA,B._MIXED_PROFILE_COMPARISON_SCHEMA)
    offset=_annotation_offset(annotation_io);paired=rep.schema in (B._EXPLANATORY_COMPARISON_SCHEMA,B._MIXED_PROFILE_COMPARISON_SCHEMA)
    fig=Figure(;size=something(size,(1120,500+120offset)),fontsize=13)
    if paired
        ax=Axis(fig[1+offset,1];xlabel="$(rep.names[2]): joint log predictive score",
            ylabel="$(rep.names[1]): joint log predictive score",title="Paired withheld-performance scores")
        diff=Axis(fig[1+offset,2];xlabel="Performance index (input order)",
            ylabel="Log-score difference: primary − baseline",title="Where predictions differ")
        scores=vcat([r.primary for r in rep.rows],[r.baseline for r in rep.rows])
        lo,hi=extrema(scores);lines!(ax,[lo-.1,hi+.1],[lo-.1,hi+.1];color=:gray55,linestyle=:dash)
        hlines!(diff,[0.];color=:gray55,linestyle=:dash)
        for r in rep.rows
            color=r.eligible ? :steelblue : :darkorange
            marker=r.eligible ? :circle : :utriangle
            scatter!(ax,[r.baseline],[r.primary];color,marker,markersize=7)
            scatter!(diff,[r.profile],[r.difference];color,marker,markersize=7)
            B._explanatory_absent(r.mcse) || rangebars!(diff,[r.profile],
                [r.difference-2r.mcse],[r.difference+2r.mcse];color,whiskerwidth=3)
            r.reference_used && scatter!(diff,[r.profile],[r.difference];
                color=:transparent,strokecolor=:black,strokewidth=1,markersize=12)
        end
        models=rep.models
        note="Primary $(rep.names[1]) minus baseline $(rep.names[2]): total difference $(round(rep.difference;digits=6)); "*
            "delta MCSE $(rep.mcse). Status: $(rep.status). Independent model RNG assumption: $(rep.independent_model_rng). "*
            "Points retain input order, not an estimated ranking. Rings mark direct-refit contributions. "
    else
        ax=Axis(fig[1+offset,1];xlabel="Performance index (input order)",
            ylabel="Original PSIS Pareto k",title="Importance-weight diagnostic")
        score=Axis(fig[1+offset,2];xlabel="Performance index (input order)",
            ylabel="Joint log predictive score",title="Held-performance prediction")
        for r in rep.rows
            k=r.original.pareto_k;color=r.eligible ? :steelblue : :darkorange
            k isa Real && isfinite(k) && scatter!(ax,[r.profile],[k];color,markersize=7)
            scatter!(score,[r.profile],[r.log_score];color,marker=r.eligible ? :circle : :utriangle,markersize=7)
            B._explanatory_absent(r.mcse) || rangebars!(score,[r.profile],
                [r.log_score-2r.mcse],[r.log_score+2r.mcse];color,whiskerwidth=3)
        end
        hlines!(ax,[first(rep.rows).original.pareto_k_threshold];color=:darkorange,linestyle=:dash)
        models=[rep];note="Total joint log predictive score $(round(rep.elpd;digits=6)); delta MCSE $(rep.mcse). Status: $(rep.status). "
    end
    bad=sum(length(m.problem_performances) for m in models)
    note*="Whole-performance exclusion, integrating one shared iid residual; other owners and observed predictors remain known. "*
        "Bars are ±2 computational MCSE, not credible intervals or population confidence intervals. PSIS tail-fit uncertainty is omitted from delta MCSE. "*
        "Crossed-design population uncertainty is unassessed; no superiority/equivalence or empirical claim follows. "*
        "$bad unresolved model/profile contributions remain orange triangles with unavailable qualified MCSE. "*
        "Joint profile scores depend on the number of ratings; profile sizes and identities remain in the report."
    for (i,m) in enumerate(models)
        warm=sum(r.n_divergences for r in m.quality.warmup)
        note*="\nModel $i: whole-fit qualified=$(m.quality.qualified), warmup divergences=$warm, "*
            "direct refits=$(length(m.reference_records)); independent refit RNG assumption=$(m.independent_refit_rng). "
        if length(m.reference_records)<=6
            for ref in m.reference_records
                note*="Refit $(ref.performance): qualified=$(ref.quality.qualified), warmup divergences=$(sum(r.n_divergences for r in ref.quality.warmup)). "
            end
        else
            n_q=count(ref->ref.quality.qualified,m.reference_records)
            w_tot=sum(sum(r.n_divergences for r in ref.quality.warmup) for ref in m.reference_records)
            note*="Refit summary: qualified=$n_q/$(length(m.reference_records)), total warmup divergences=$w_tot (per-performance records retained in report). "
        end
    end
    # Keep arbitrary warnings verbatim once; aggregate only recognized pattern messages.
    codes=("unused_interior_category","unobserved_declared_endpoint","constant_score_pattern")
    recognized(w)=any(code->startswith(w,"[$code]"),codes)
    remaining=unique([String(w) for m in models for w in m.model_warnings if !recognized(w)])
    isempty(remaining) || (note*="\nModel warnings (shared messages listed once): "*join(remaining," "))
    for (i,m) in enumerate(models)
        counts=["$code=$(count(w->startswith(w,"[$code]"),m.model_warnings))" for code in codes
            if any(w->startswith(w,"[$code]"),m.model_warnings)]
        isempty(counts) || (note*="\nModel $i observed pattern warnings: "*join(counts,", ")*".")
    end
    any(m->any(recognized,m.model_warnings),models) &&
        (note*=" Individual IDs, categories and counts remain in each model's model_warnings; counts above refer to warning records, not independent people. No observation or category was removed.")
    paired && !isempty(rep.mcse_blocks) && (note*="\nBlock-jackknife MCSE checks: "*join(["$(r.block)-draw blocks: $(r.mcse)" for r in rep.mcse_blocks],"; ")*". Original relative efficiencies held fixed.")
    _figure_text!(fig,is_mixed ? "Mixed-outcome model · held-performance prediction" : "Explanatory model · held-performance prediction",note;
        annotation_io,bottom_row=2+offset,columns=2)
end
