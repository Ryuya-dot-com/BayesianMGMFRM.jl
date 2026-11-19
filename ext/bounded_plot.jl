function plot_bounded_report(rep;kind,size,annotation_io)
    offset=_annotation_offset(annotation_io)
    if rep.schema==B.AdditiveFacets.BOUNDED_PREDICTION_SCHEMA
        kind===:prediction || throw(ArgumentError("bounded prediction report requires kind=:prediction"))
        metrics=unique(Symbol(r.metric) for r in rep.cells)
        titles=Dict(:expected_score=>"Total expected score",:interior_mean=>"Interior mean only",
            :lower_probability=>"Lower endpoint probability",:upper_probability=>"Upper endpoint probability",
            :precision=>"Interior precision",:endpoint_probability=>"Either endpoint probability",
            :upper_given_endpoint_probability=>"Upper probability given endpoint",
            :interior_sd=>"Interior score SD",:score_sd=>"Total score SD")
        nr=cld(length(metrics),2)
        fig=Figure(;size=something(size,(1100,340nr+100offset)),fontsize=14)
        for (j,k) in enumerate(metrics)
            rows=filter(r->Symbol(r.metric)===k,rep.cells)
            unit=B.AdditiveFacets.bounded_metric_unit(k)
            ax=Axis(fig[cld(j,2)+offset,mod1(j,2)];title=titles[k],
                xlabel="Selected observation",ylabel=replace(string(unit),"_"=>" "),xticks=(1:length(rows),string.([r.row for r in rows])))
            rangebars!(ax,1:length(rows),[r.lower for r in rows],[r.upper for r in rows];color=:steelblue4,whiskerwidth=7)
            scatter!(ax,1:length(rows),[r.median for r in rows];color=:steelblue4)
            if k in (:expected_score,:interior_mean);ylims!(ax,rep.bounds)
            elseif unit===:probability;ylims!(ax,0.,1.)
            else;ylims!(ax,0.,nothing);end
        end
        is_new=hasproperty(rep,:mode) && Symbol(rep.mode)===:new_owners
        prefix=is_new ? "New-owner population-integrated posterior medians" : "Known-owner posterior medians"
        note="$prefix and $(100rep.interval)% credible intervals for conditional distribution parameters/moments; not future-score prediction intervals. Precision is beta concentration, not rating reliability. SD panels describe conditional score dispersion; their intervals are parameter uncertainty. Total expectation includes both endpoint atoms. Whole-fit qualification: $(rep.qualification.qualified). "*join(rep.warnings," ")
        return _figure_text!(fig,"Bounded ratings · predicted distribution",note;annotation_io,bottom_row=nr+1+offset,columns=2)
    end
    kind===:predictive || throw(ArgumentError("bounded predictive report requires kind=:predictive"))
    metrics=(:lower_rate,:upper_rate,:mean_score,:sd_score,:interior_mean,:interior_sd)
    titles=("Lower endpoint rate","Upper endpoint rate","Mean score","Score SD","Interior mean","Interior SD")
    fig=Figure(;size=something(size,(1150,850+100offset)),fontsize=14)
    for (j,k) in enumerate(metrics)
        rows=filter(r->Symbol(r.metric)===k,rep.cells)
        ax=Axis(fig[cld(j,2)+offset,mod1(j,2)];title=titles[j],xlabel="Declared group",
            ylabel=j<=2 ? "Proportion" : "Original-score units",xticks=(1:length(rows),[r.label for r in rows]))
        keep=findall(r->r.lower!==nothing,rows)
        if !isempty(keep)
            rangebars!(ax,keep,Float64[rows[i].lower for i in keep],Float64[rows[i].upper for i in keep];color=:steelblue4,whiskerwidth=8)
            scatter!(ax,keep,Float64[rows[i].median for i in keep];color=:steelblue4,label="Replicated median / interval")
        end
        obs=findall(r->r.observed!==nothing,rows)
        isempty(obs) || scatter!(ax,obs,Float64[rows[i].observed for i in obs];color=:black,marker=:diamond,label="Observed")
        j<=2 && ylims!(ax,0,1)
        j==1 && (!isempty(keep) || !isempty(obs)) && Legend(fig[4+offset,1:2],ax;orientation=:horizontal,framevisible=false)
    end
    prior=Symbol(rep.kind)===:prior_predictive
    title=prior ? "PRIOR predictive check · bounded ratings" : "POSTERIOR predictive check · bounded ratings"
    hasproperty(rep,:replications_complete) && !rep.replications_complete && (title*=" · incomplete numerical replicas")
    note="$(rep.ndraws) replicated datasets; $(100rep.interval)% pointwise predictive intervals for statistics. "*
        (prior ? "Parameters drawn from the prior; observed values are not overlaid. " : "Black diamonds are observed; one joint posterior draw is shared by each replicated dataset. ")*
        "Interior-only summaries are conditional on having interior observations; defined-replica counts are saved. "*join(rep.warnings," ")
    _figure_text!(fig,title,note;annotation_io,bottom_row=5+offset,columns=2)
end

function plot_bounded_comparison(rep;size=nothing,annotation_io=stdout)
    offset=_annotation_offset(annotation_io);paired=rep.schema in (B._BOUNDED_COMPARISON_SCHEMA,B._COUNT_COMPARISON_SCHEMA)
    counts=rep.schema in (B._COUNT_CRITERIA_SCHEMA,B._COUNT_COMPARISON_SCHEMA)
    mcse_text=rep.mcse===nothing ? "unavailable; importance weights or precision unresolved" : string(rep.mcse)
    fig=Figure(;size=something(size,(1050,460+100offset)),fontsize=14)
    if paired
        ax=Axis(fig[1+offset,1];xlabel="$(rep.names[2]) log predictive score",ylabel="$(rep.names[1]) log predictive score")
        scatter!(ax,[r.baseline for r in rep.rows],[r.primary for r in rep.rows];color=[r.eligible ? :steelblue4 : :darkorange for r in rep.rows])
        lo,hi=extrema([r.primary for r in rep.rows]∪[r.baseline for r in rep.rows]);lines!(ax,[lo,hi],[lo,hi];color=:gray50,linestyle=:dash)
        bx=Axis(fig[1+offset,2];xlabel="Rating row",ylabel="Primary − baseline log score")
        scatter!(bx,[r.row for r in rep.rows],[r.difference for r in rep.rows];color=[r.eligible ? :steelblue4 : :darkorange for r in rep.rows]);hlines!(bx,[0.];color=:gray50)
        note="Paired rating-wise ELPD difference: $(round(rep.difference;digits=3)); computational MCSE: $mcse_text. "
    else
        ax=Axis(fig[1+offset,1];xlabel="Rating row",ylabel="PSIS Pareto k")
        scatter!(ax,[r.row for r in rep.rows],[r.diagnostics.pareto_k for r in rep.rows];color=[r.eligible ? :steelblue4 : :darkorange for r in rep.rows])
        bx=Axis(fig[1+offset,2];xlabel="Rating row",ylabel="Log predictive score")
        scatter!(bx,[r.row for r in rep.rows],[r.log_score for r in rep.rows];color=:steelblue4)
        note="Rating-wise ELPD: $(round(rep.elpd;digits=3)); computational MCSE: $mcse_text. "
    end
    note*="Status: $(rep.status). Known owners. "*(counts ? "Success-count probabilities at declared trial counts. " : "Original-score density and endpoint atoms. ")*"Orange marks unresolved weights/precision. Population sampling SE and automatic ranking are not supplied. "*join(rep.warnings," ")
    _figure_text!(fig,counts ? "Count responses · known-owner predictive comparison" : "Bounded ratings · known-owner predictive comparison",note;annotation_io,bottom_row=2+offset,columns=2)
end
