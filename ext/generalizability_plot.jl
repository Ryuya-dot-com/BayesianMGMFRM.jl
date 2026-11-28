function plot_generalizability(obj;kind=:components,size=nothing,annotation_io=stdout,kwargs...)
    data=B.Generalizability.plot_data(obj;kind,kwargs...)
    offset=_annotation_offset(annotation_io)
    fig=Figure(;size=something(size,kind===:dstudy ? (900,520) : (1000,max(430,36length(data.rows)+140))),fontsize=14)
    colors=[:steelblue4,:darkorange3,:seagreen4,:purple4,:goldenrod3,:brown3]
    if kind===:dstudy
        facet=first(data.facets);others=data.facets[2:end]
        ylabel=data.metric===:Phi ? "Absolute dependability (Phi)" : data.metric===:G ? "Relative generalizability (G)" : data.metric===:relative_sem ? "Relative SEM" : "Absolute SEM"
        ax=Axis(fig[1+offset,1];xlabel="Number of $(facet) levels",ylabel,
            xticks=sort(unique([r.counts[facet] for r in data.rows])))
        group(r)=join(["$f=$(r.counts[f])" for f in others],", ")
        groups=unique(group.(data.rows))
        for (i,key) in enumerate(groups)
            rows=sort(filter(r->group(r)==key,data.rows);by=r->r.counts[facet])
            x=[r.counts[facet] for r in rows];y=[r.estimate for r in rows];color=colors[mod1(i,length(colors))]
            lines!(ax,x,y;color,label=isempty(key) ? data.score : key)
            scatter!(ax,x,y;color,markersize=9)
            for (j,r) in enumerate(rows)
                if !ismissing(r.lower)&&!isnothing(r.lower)&&!ismissing(r.upper)&&!isnothing(r.upper)
                    rangebars!(ax,[x[j]],[r.lower],[r.upper];color,whiskerwidth=8)
                end
            end
        end
        !isempty(others) && axislegend(ax;position=:rb)
        title="D study: $(data.score)"
    else
        labels=["$(r.component): $(r.score1)"*(r.score1==r.score2 ? "" : " × $(r.score2)") for r in data.rows]
        ax=Axis(fig[1+offset,1];xlabel="Variance / covariance (products of score units)",yticks=(1:length(labels),labels),yreversed=true)
        vlines!(ax,[0.];color=:gray65,linestyle=:dash)
        for (i,r) in enumerate(data.rows)
            color=r.score1==r.score2 ? colors[1] : colors[2]
            if !ismissing(r.lower)&&!isnothing(r.lower)&&!ismissing(r.upper)&&!isnothing(r.upper)
                rangebars!(ax,[i],[r.lower],[r.upper];direction=:x,color,whiskerwidth=8)
            end
            scatter!(ax,[r.estimate],[i];color,markersize=10)
        end
        title="G-study covariance components"
    end
    note=data.interval_kind===:confidence ? "$(100data.interval)% pointwise asymptotic confidence intervals; not clipped. Intervals unavailable at covariance boundaries are omitted." :
        "$(100data.interval)% pointwise equal-tailed credible intervals; points show posterior means."
    if hasproperty(data,:interval_method) && data.interval_method===:exact
        note="$(100data.interval)% pointwise exact $(data.metric===:G ? "F" : "chi-square") confidence intervals under the complete balanced Gaussian model with prespecified weights. Points retain ML/REML estimates."
        statuses=unique([string(r.status) for r in data.rows if r.status ∉ (:exact_f,:exact_chisq)])
        isempty(statuses) || (note*=" Omitted confidence sets: "*join(replace.(statuses,'_'=>' '),", ")*".")
    elseif hasproperty(data,:interval_method) && data.interval_method===:mean_square_region
        note="$(100data.interval)% Gaussian mean-square region projections: simultaneous across future plans and metrics for this prespecified score/composite. Requires a complete balanced design and independent normal effects; intervals can be wide. Points retain ML/REML estimates."
        statuses=unique([string(r.status) for r in data.rows if r.status!==:mean_square_region])
        isempty(statuses) || (note*=" Omitted confidence sets: "*join(replace.(statuses,'_'=>' '),", ")*".")
    end
    qualified=hasproperty(data.qualification,:qualified) ? data.qualification.qualified : false
    note*=" Numerical qualification: $qualified."
    if hasproperty(data.qualification,:warnings)
        note*=" "*join(data.qualification.warnings," ")
    end
    _figure_text!(fig,title,note;annotation_io,bottom_row=2+offset)
end
