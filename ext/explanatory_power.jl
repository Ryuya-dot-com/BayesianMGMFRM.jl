function plot_explanatory_power(rep;size=nothing,annotation_io=stdout)
    names=[r.label for r in first(rep.cases).rows]
    groups=unique([collect(c.factors) for c in rep.cases])
    colors=_response_category_colors(length(groups));offset=_annotation_offset(annotation_io)
    cols=min(2,length(names));nr=cld(length(names),cols)
    fig=Figure(;size=something(size,(1150,250nr+110+120offset)),fontsize=13)
    firstaxis=nothing
    for (i,name) in enumerate(names)
        ax=Axis(fig[cld(i,cols)+offset,mod1(i,cols)];title=name,
            xlabel="Prior power α",ylabel="Change in posterior mean")
        firstaxis===nothing && (firstaxis=ax)
        hlines!(ax,[0.];color=:gray55,linestyle=:dash)
        for (j,g) in enumerate(groups)
            cases=sort(filter(c->collect(c.factors)==g,rep.cases);by=c->c.alpha)
            # NaN gaps prevent connecting across failed importance-weight screens.
            xs=Float64[c.alpha for c in cases]
            ys=Float64[c.reweighting.reliable ? c.rows[i].mean_shift : NaN for c in cases]
            lines!(ax,xs,ys;color=colors[j],linewidth=1.5,label="Factor group $j")
            for (x,y,c) in zip(xs,ys,cases)
                isfinite(y) || continue
                row=c.rows[i];warn=c.sampling_warning || row.precision_qualified===false
                scatter!(ax,[x],[y];color=colors[j],marker=warn ? :utriangle : :circle,markersize=9)
                err=row.paired_shift_mcse
                err===nothing || rangebars!(ax,[x],[y-2err],[y+2err];color=colors[j],whiskerwidth=7)
            end
        end
    end
    Legend(fig[nr+1+offset,1:cols],firstaxis;orientation=:horizontal,framevisible=false)
    failed=count(c->!c.reweighting.reliable,rep.cases)
    note="Scientific prior power sensitivity: points are changes in posterior means relative to α=1. "*
        "Bars show ±2 paired-shift plug-in MCSE, not credible intervals or total Monte Carlo uncertainty; PSIS tail-fit uncertainty is omitted. "*
        "$failed unreliable cases are retained in the report and omitted as gaps, not zero changes. "*
        "Triangles retain baseline sampling or declared mean-MCSE warnings. Baseline sampling warning: $(rep.baseline.sampling_warning). "*
        "Conditional residuals and Jacobians are not powered; no new sampling. Near-one stability is not general robustness or causal evidence."
    for (j,g) in enumerate(groups);note*="\nFactor group $j: "*join(g,", ")*".";end
    for name in names
        r=only(filter(r->r.label==name,first(rep.cases).rows));note*="\n$name: $(r.unit)."
    end
    for c in rep.cases
        note*="\n$(c.id): α=$(c.alpha), Pareto-k=$(c.reweighting.pareto_k), weight ESS=$(c.reweighting.weight_ess), "*
            "r_eff=$(c.reweighting.r_eff), status=$(c.reweighting.status)."
    end
    note*="\nModel warnings: "*join(rep.warnings," ")
    _figure_text!(fig,"Explanatory model · scientific prior powers",note;annotation_io,bottom_row=nr+2+offset,columns=cols)
end
