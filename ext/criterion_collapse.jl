const CC=B.Experimental.CriterionCollapse
function plot_criterion_classes(report;size=nothing,annotation_io=stdout)
    d=CC._class_plot_data(report);offset=_annotation_offset(annotation_io);n=length(d.levels)
    fig=Figure(;size=something(size,(1050,max(340,85+55n)+200offset)),fontsize=15)
    ax=Axis(fig[1+offset,1];xlabel="Posterior class probability",ylabel="Rater",yticks=(1:n,d.labels),yreversed=true)
    precision=Axis(fig[1+offset,2];xlabel="MCSE of probability estimate",yticks=(1:n,d.labels),yreversed=true)
    hideydecorations!(precision;grid=false);linkyaxes!(ax,precision)
    for (i,row) in enumerate(d.values)
        scatter!(ax,[row.probability],[i];color=:steelblue4,markersize=12)
        right=row.probability<.85
        text!(ax,row.probability,i;text=CC._plot_number(row.probability),
            offset=(right ? 9 : -9,0),align=(right ? :left : :right,:center),fontsize=12)
        if ismissing(row.mcse)
            text!(precision,0.,i;text="unavailable",offset=(5,0),align=(:left,:center),color=:darkorange3,fontsize=12)
        else
            scatter!(precision,[row.mcse],[i];color=:gray30,marker=:diamond,markersize=11)
            text!(precision,row.mcse,i;text=CC._plot_number(row.mcse),offset=(9,0),align=(:left,:center),fontsize=12)
        end
    end
    xlims!(ax,0,1);ylims!(ax,.5,n+.5)
    # Explicit limits reset axis direction; set both directions after linking.
    ax.yreversed[]=true;precision.yreversed[]=true
    colgap!(fig.layout,50)
    finite=[x.mcse for x in d.values if !ismissing(x.mcse)]
    upper=isempty(finite) || maximum(finite)==0 ? .01 : maximum(finite)*1.7
    xlims!(precision,0,upper)
    note="Dots: posterior probability of one constant criterion-collapse class per rater. " *
        "Diamonds: numerical MCSE on a separate scale, not credible intervals. No classification cutoff. " *
        "Unavailable class MCSE: $(d.mcse_unavailable). Precision thresholds are not applied.\n" * d.note
    _figure_text!(fig,"Criterion collapse: rater class probabilities",note;annotation_io,bottom_row=2+offset,columns=2)
end

function plot_criterion_categories(report;rater,size=nothing,annotation_io=stdout)
    d=CC._category_plot_data(report;rater);offset=_annotation_offset(annotation_io)
    n=length(d.panels);columns=min(n,3);blocks=cld(n,columns);K=length(d.categories)
    fig=Figure(;size=something(size,(380columns,500blocks+90+220offset)),fontsize=14)
    observed_color=:gray20;expected_color=:steelblue4
    mcse_upper=d.mcse_max===nothing || d.mcse_max==0 ? .01 : 1.4d.mcse_max
    for (j,panel) in enumerate(d.panels)
        block=cld(j,columns);column=mod1(j,columns);top=2block-1+offset
        ax=Axis(fig[top,column];title="Criterion $(d.labels[j]) (n=$(panel.n))",
            xlabel="Category",ylabel="Proportion",xticks=(1:K,string.(d.categories)))
        precision=Axis(fig[top+1,column];xlabel="Category",ylabel="Expected-proportion MCSE",
            xticks=(1:K,string.(d.categories)))
        x=collect(1:K)
        scatter!(ax,x.-.08,panel.observed;color=observed_color,marker=:circle,markersize=11)
        scatter!(ax,x.+.08,[v.probability for v in panel.expected];color=expected_color,marker=:diamond,markersize=12)
        for (k,row) in enumerate(panel.expected)
            if ismissing(row.mcse)
                text!(precision,k,mcse_upper/2;text="NA",align=(:center,:center),color=:darkorange3,fontsize=13)
            else
                scatter!(precision,[k],[row.mcse];color=expected_color,marker=:diamond,markersize=11)
            end
        end
        xlims!(ax,.5,K+.5);ylims!(ax,0,1)
        xlims!(precision,.5,K+.5);ylims!(precision,0,mcse_upper)
    end
    Legend(fig[2blocks+1+offset,1:columns],
        [MarkerElement(color=observed_color,marker=:circle,markersize=11),MarkerElement(color=expected_color,marker=:diamond,markersize=12)],
        ["Observed proportion","Posterior expected proportion"],orientation=:horizontal,tellwidth=false)
    note="Observed proportions versus posterior expected proportions, conditional on the fitted people, criteria and rater. " *
        "All criteria and categories are shown for rater $(rater). Probabilities use common 0–1 axes; MCSE axes share the full report's range. " *
        "MCSE is numerical uncertainty, not a credible or replicated-count interval; NA means unavailable, not zero. " *
        "Unavailable category MCSE across ALL raters: $(d.mcse_unavailable). No precision threshold or predictive fit test is applied. " *
        "The latent class is shared across a rater's ratings; marginal row probabilities cannot be multiplied as a joint density.\n" * d.note
    _figure_text!(fig,"Criterion collapse: category profiles for rater $(rater)",note;
        annotation_io,bottom_row=2blocks+2+offset,columns)
end

function plot_criterion_predictive(report;size=nothing,annotation_io=stdout)
    CC._operation_report_check(report)
    string(report.kind)=="criterion_collapse_predictive_check" ||
        throw(ArgumentError("plot_criterion_predictive expects a CriterionCollapse predictive_check report"))
    ctx=CC._plot_context(report);offset=_annotation_offset(annotation_io)
    sup=collect(Int,report.support);pmf=collect(Float64,report.pmf)
    fig=Figure(;size=something(size,(960,460+210offset)),fontsize=14)
    ax=Axis(fig[1+offset,1];
        title="Model: $(report.model) · category $(report.category) (n=$(report.n_observations))",
        xlabel="Signed category count",ylabel="Posterior predictive mass")
    barplot!(ax,sup,pmf;color=(:steelblue4,0.75),strokecolor=:steelblue4,strokewidth=1)
    vlines!(ax,[Float64(report.observed)];color=:firebrick,linestyle=:dash,linewidth=2.2)
    vlines!(ax,[Float64(report.expected_count.estimate)];color=:gray25,linestyle=:dot,linewidth=2.0)
    Legend(fig[2+offset,1],
        [PolyElement(color=(:steelblue4,0.75),strokecolor=:steelblue4,strokewidth=1),
         LineElement(color=:firebrick,linestyle=:dash,linewidth=2.2),
         LineElement(color=:gray25,linestyle=:dot,linewidth=2.0)],
        ["Exact posterior-averaged PMF","Observed count ($(report.observed))",
         "Posterior expected count ($(CC._plot_number(report.expected_count.estimate)))"];
        orientation=:horizontal,tellwidth=false)
    fmt_fn(s)=ismissing(s.mcse) || s.mcse===nothing ? "$(CC._plot_number(s.estimate)) (MCSE $(s.mcse_status))" :
        "$(CC._plot_number(s.estimate)) (MCSE $(CC._plot_number(s.mcse)))"
    note="Same-design exact Poisson-binomial / convolution PMF for signed category-$(report.category) count under model=$(report.model). " *
        "Expected count: $(fmt_fn(report.expected_count)); inclusive lower tail P(T <= T_obs): $(fmt_fn(report.lower_tail)); " *
        "inclusive upper tail P(T >= T_obs): $(fmt_fn(report.upper_tail)); observed mass: $(fmt_fn(report.observed_mass)). " *
        "Inclusive tails overlap at T_obs and are not calibrated p-values. PMF-cell and count-quantile precision are unassessed.\n" * ctx.note
    _figure_text!(fig,"Criterion collapse: joint signed-count posterior predictive check",note;
        annotation_io,bottom_row=3+offset,columns=1)
end

function plot_criterion_comparison(report;size=nothing,annotation_io=stdout)
    CC._operation_report_check(report)
    k=string(report.kind)
    k in ("criterion_collapse_heldout_criteria","criterion_collapse_heldout_comparison","criterion_collapse_heldout_pair_comparison") ||
        throw(ArgumentError("plot_criterion_comparison expects a CriterionCollapse held-out criteria or comparison report"))
    ctx=CC._plot_context(report);offset=_annotation_offset(annotation_io)
    fig=Figure(;size=something(size,(1120,480+220offset)),fontsize=13)
    if k=="criterion_collapse_heldout_criteria"
        m=report.result;pts=m.pointwise
        ax_k=Axis(fig[1+offset,1];title="PSIS Pareto-k diagnostic ($(m.model))",
            xlabel="Performance-rater profile index",ylabel="Original PSIS Pareto k")
        ax_s=Axis(fig[1+offset,2];title="Held-profile conditional log score ($(m.model))",
            xlabel="Performance-rater profile index",ylabel="Conditional log predictive score")
        hlines!(ax_k,[Float64(first(pts).pareto_k_threshold)];color=:darkorange3,linestyle=:dash)
        for p in pts
            ok=string(p.importance_status)=="ok"
            is_ref=hasproperty(p,:method) && string(p.method)=="direct_refit"
            col=ok ? :steelblue4 : :darkorange3
            mk=ok ? :circle : :utriangle
            CC._plot_finite(p.pareto_k) && scatter!(ax_k,[p.profile],[Float64(p.pareto_k)];color=col,marker=mk,markersize=8)
            scatter!(ax_s,[p.profile],[Float64(p.log_score)];color=col,marker=mk,markersize=8)
            if !(p.mcse===nothing || ismissing(p.mcse))
                rangebars!(ax_s,[p.profile],[Float64(p.log_score)-2Float64(p.mcse)],
                    [Float64(p.log_score)+2Float64(p.mcse)];color=col,whiskerwidth=4)
            end
            is_ref && scatter!(ax_s,[p.profile],[Float64(p.log_score)];
                color=:transparent,strokecolor=:black,strokewidth=1.3,markersize=13)
        end
        tot_mcse=m.mcse===nothing || ismissing(m.mcse) ? "unavailable ($(m.mcse_status))" : CC._plot_number(m.mcse)
        n_ref=hasproperty(m,:reference_records) ? length(m.reference_records) : 0
        note="Held-profile conditional log predictive score ($(m.model)): total $(CC._plot_number(m.elpd)), computational delta MCSE $tot_mcse, status=$(m.status). " *
            "Unresolved profiles: $(length(m.problem_profiles)) (orange triangles); direct masked refits: $n_ref (black rings). " *
            "Bars show ±2 computational MCSE, not population SEs or credible intervals.\n" * ctx.note
        return _figure_text!(fig,"Criterion collapse: held-profile conditional criteria",note;
            annotation_io,bottom_row=2+offset,columns=2)
    end
    is_pair=k=="criterion_collapse_heldout_pair_comparison"
    pname=is_pair ? String(report.names[1]) : "mixture"
    bname=is_pair ? String(report.names[2]) : "all_ordinary"
    pm=is_pair ? report.primary : report.mixture
    bm=is_pair ? report.baseline : report.all_ordinary
    d=report.difference
    ax_sc=Axis(fig[1+offset,1];title="Paired held-profile conditional log scores",
        xlabel="$bname: profile log score",ylabel="$pname: profile log score")
    ax_df=Axis(fig[1+offset,2];title="Profile log-score difference ($pname - $bname)",
        xlabel="Performance-rater profile index",ylabel="Log-score difference")
    all_s=vcat([Float64(p.log_score) for p in pm.pointwise],[Float64(p.log_score) for p in bm.pointwise])
    lo,hi=extrema(all_s);pad=max(0.1,0.06*(hi-lo))
    lines!(ax_sc,[lo-pad,hi+pad],[lo-pad,hi+pad];color=:gray55,linestyle=:dash)
    hlines!(ax_df,[0.0];color=:gray55,linestyle=:dash)
    for j in 1:report.n_profiles
        pp=pm.pointwise[j];bp=bm.pointwise[j];dp=d.pointwise[j]
        ok=string(dp.mcse_status)=="available" && !(dp.mcse===nothing || ismissing(dp.mcse))
        is_ref=(hasproperty(pp,:method) && string(pp.method)=="direct_refit") ||
               (hasproperty(bp,:method) && string(bp.method)=="direct_refit")
        col=ok ? :steelblue4 : :darkorange3
        mk=ok ? :circle : :utriangle
        scatter!(ax_sc,[Float64(bp.log_score)],[Float64(pp.log_score)];color=col,marker=mk,markersize=8)
        scatter!(ax_df,[j],[Float64(dp.difference)];color=col,marker=mk,markersize=8)
        if ok
            rangebars!(ax_df,[j],[Float64(dp.difference)-2Float64(dp.mcse)],
                [Float64(dp.difference)+2Float64(dp.mcse)];color=col,whiskerwidth=4)
        end
        is_ref && scatter!(ax_df,[j],[Float64(dp.difference)];
            color=:transparent,strokecolor=:black,strokewidth=1.3,markersize=13)
    end
    tot_mcse=d.mcse===nothing || ismissing(d.mcse) ? "unavailable ($(d.mcse_status))" : CC._plot_number(d.mcse)
    n_prob=length(union(pm.problem_profiles,bm.problem_profiles))
    note="Paired profile log-score difference ($pname minus $bname): total $(CC._plot_number(d.estimate)) " *
        "(mean $(CC._plot_number(d.mean_difference))), computational MCSE $tot_mcse. " *
        "Unresolved profiles across both sides: $n_prob (orange triangles); black rings mark direct masked refits. " *
        "Bars show ±2 computational MCSE on the original finite panel, not crossed-design sampling SEs.\n" * ctx.note
    _figure_text!(fig,"Criterion collapse: held-profile conditional comparison",note;
        annotation_io,bottom_row=2+offset,columns=2)
end
