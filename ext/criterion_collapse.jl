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
