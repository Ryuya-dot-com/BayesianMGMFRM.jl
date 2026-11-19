function plot_count_report(rep;kind,size,annotation_io)
    offset=_annotation_offset(annotation_io)
    if rep.schema==B.AdditiveFacets.COUNT_PREDICTION_SCHEMA
        kind===:prediction || throw(ArgumentError("use kind=:prediction for count predictions"))
        fig=Figure(;size=something(size,(1100,680+100offset)),fontsize=15)
        metrics=("expected_proportion","expected_count","zero_probability","perfect_probability")
        titles=("Expected proportion correct","Expected correct count","Zero-correct probability","Perfect-response probability")
        for (j,k) in enumerate(metrics)
            rows=filter(r->string(r.metric)==k,rep.cells);ids=collect(1:length(rows))
            labels=["$(r.row)\nn=$(r.trials)" for r in rows]
            ax=Axis(fig[offset+cld(j,2),mod1(j,2)];title=titles[j],xticks=(ids,labels),xlabel="Observation and trial count",ylabel=j==2 ? "Correct count" : "Probability")
            rangebars!(ax,ids,[r.lower for r in rows],[r.upper for r in rows];color=:steelblue4,whiskerwidth=7)
            scatter!(ax,ids,[r.mean for r in rows];color=:steelblue4)
            j==2 ? ylims!(ax,0,maximum(r.trials for r in rows)) : ylims!(ax,0,1)
        end
        is_new=hasproperty(rep,:mode) && Symbol(rep.mode)===:new_owners
        owner_tag=is_new ? "New-owner population-integrated predictions" : "Known owners and stored attributes"
        note="Posterior means and $(round(100rep.interval;digits=1))% equal-tailed CrIs for conditional expectations/probabilities at the declared trial counts. These are not future-response predictive intervals. $owner_tag; numerical qualification: $(rep.qualification.qualified). "*join(rep.warnings," ")
        return _figure_text!(fig,"Count response predictions",note;annotation_io,bottom_row=3+offset,columns=2)
    end
    kind===:predictive || throw(ArgumentError("use kind=:predictive for count prior/PPC reports"))
    prior=string(rep.kind)=="prior_predictive"
    fig=Figure(;size=something(size,(1150,850+100offset)),fontsize=14)
    metrics=("zero_rate","perfect_rate","mean_proportion","pooled_proportion","sd_proportion","mean_count")
    titles=("Zero-correct responses","Perfect responses","Mean proportion · equal responses","Pooled proportion · equal words","SD of response proportions","Mean correct count")
    for (j,k) in enumerate(metrics)
        rows=filter(r->string(r.metric)==k,rep.cells);ids=collect(1:length(rows))
        ax=Axis(fig[offset+cld(j,2),mod1(j,2)];title=titles[j],xticks=(ids,[r.label for r in rows]),xlabel=string(rep.groupby)=="trials" ? "Trial count" : "Declared owner group",ylabel=j==6 ? "Correct count" : j==5 ? "SD" : "Proportion")
        rangebars!(ax,ids,Float64[r.lower for r in rows],Float64[r.upper for r in rows];color=:steelblue4,whiskerwidth=7)
        scatter!(ax,ids,Float64[r.median for r in rows];color=:steelblue4,label="Replicated median / interval")
        prior || scatter!(ax,ids,Float64[r.observed for r in rows];color=:black,marker=:diamond,label="Observed")
        j<=4 && ylims!(ax,0,1)
        j==1 && Legend(fig[4+offset,1:2],ax;orientation=:horizontal,framevisible=false)
    end
    title=(prior ? "PRIOR" : "POSTERIOR")*" predictive check · counts"
    note="$(rep.ndraws) replicated datasets; $(round(100rep.interval;digits=1))% pointwise predictive intervals for statistics at the retained trial counts. "*
        (prior ? "Parameters drawn from the declared prior, without conditioning on correct counts. " : "Black diamonds are observed; each replica shares one joint posterior draw. ")*
        "Equal-response and pooled word proportions differ when denominators vary within a group. "*join(rep.warnings," ")
    _figure_text!(fig,title,note;annotation_io,bottom_row=5+offset,columns=2)
end
