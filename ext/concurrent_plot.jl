function plot_concurrent_report(data;view,size=nothing,annotation_io=stdout)
    offset=_annotation_offset(annotation_io)
    m=data.metadata
    panels=("Preliminary listeners", "Additional ENG listeners")
    outcomes=("Accentedness", "Comprehension difficulty", "Transcription correctness")
    note=B._concurrent_plot_note(data,view)
    if view===:joint
        fig=Figure(;size=something(size,(1150,570+160offset)),fontsize=14)
        rows=filter(x->x.kind=="ac_joint",data.rows)
        residual(r)=100*(r.observed-r.mean)/r.denominator
        limit=maximum(abs(residual(r)) for r in rows)
        limit=limit==0 ? 1. : limit
        for g in 1:2
            selected=filter(r->r.panel==g,rows)
            grid=zeros(9,9)
            for r in selected;grid[r.c,r.a]=residual(r);end
            ax=Axis(fig[1+offset,g];title="$(panels[g]) ($(m.denominators[g]) events)",
                xlabel="Comprehension difficulty category",ylabel="Accentedness category",
                xticks=1:9,yticks=1:9,aspect=DataAspect())
            hm=heatmap!(ax,1:9,1:9,grid;colormap=:RdBu,colorrange=(-limit,limit))
            for r in selected
                r.outside_pointwise_interval || continue
                stable=all(e->e.status=="stable_under_pointwise_cdf_mcse_screen",(r.lower_endpoint,r.upper_endpoint))
                scatter!(ax,[r.c],[r.a];marker=stable ? :rect : :circle,markersize=10,
                    color=:transparent,strokecolor=:black,strokewidth=1.5)
            end
            g==2 && Colorbar(fig[1+offset,3],hm;label="Observed − replicated mean (percentage points)")
        end
        return _figure_text!(fig,"Posterior predictive check · A–C joint counts",note;
            annotation_io,bottom_row=2+offset)
    elseif view===:marginal
        fig=Figure(;size=something(size,(1350,800+160offset)),fontsize=14)
        for g in 1:2,a in 1:3
            name=B._TI_MOD.ConcurrentWorkflow.OUTCOMES[a]
            rows=sort(filter(r->r.panel==g && r.kind=="marginal" && r.outcome==name,data.rows);by=r->r.category)
            x=Int[r.category for r in rows]
            ax=Axis(fig[g+offset,a];title="$(panels[g])\n$(a==3 ? "Transcription response" : outcomes[a])",
                xlabel="Category",ylabel="Event count",xticks=a==3 ? (x,["Correct","Error"]) : x)
            rangebars!(ax,x,Float64[r.lower for r in rows],Float64[r.upper for r in rows];
                color=:steelblue4,linewidth=2,whiskerwidth=9)
            scatter!(ax,x,Float64[r.median for r in rows];color=:steelblue4,markersize=9,label="Replicated median / interval")
            scatter!(ax,x,Float64[r.observed for r in rows];color=:black,marker=:diamond,markersize=9,label="Observed")
            ylims!(ax,0,nothing)
            g==1 && a==1 && Legend(fig[3+offset,1:3],ax;orientation=:horizontal,framevisible=false)
        end
        return _figure_text!(fig,"Posterior predictive check · marginal counts",note;
            annotation_io,bottom_row=4+offset)
    end
    selection=B._concurrent_plot_names(m)
    n=length(selection.labels)
    fig=Figure(;size=something(size,(1550,170+45n+160offset)),fontsize=14)
    by_name=Dict(x.name=>x for x in data.rows)
    for a in 1:3
        rows=[by_name[name] for name in selection.names[(a-1)*n+1:a*n]]
        unit=a==3 ? "Probability" : "Expected rating"
        ax=Axis(fig[1+offset,a];title=outcomes[a],
            xlabel=view===:contrasts ? "Difference in $(lowercase(unit))" : unit,
            yticks=(1:n,a==1 ? selection.labels : fill("",n)),yreversed=true,ygridvisible=false)
        view===:contrasts && vlines!(ax,[0.];color=:gray60,linestyle=:dash)
        for (i,r) in enumerate(rows)
            rangebars!(ax,[i],[Float64(r.lower)],[Float64(r.upper)];direction=:x,
                color=:steelblue4,linewidth=2,whiskerwidth=8)
            passed=r.precision_passed && r.diagnostic_passed
            scatter!(ax,[Float64(r.mean)],[i];color=passed ? :steelblue4 : :white,
                strokecolor=:steelblue4,strokewidth=1.5,markersize=10)
        end
        ylims!(ax,.5,n+.5)
        ax.yreversed[]=true
    end
    _figure_text!(fig,view===:contrasts ? "Posterior contrasts" : "Posterior ENG speaker profiles",note;
        annotation_io,bottom_row=2+offset)
end
