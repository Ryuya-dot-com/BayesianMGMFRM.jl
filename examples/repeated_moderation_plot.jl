# Saved-report plotting recipe; no inference, prediction or native fit is needed.
if abspath(PROGRAM_FILE)==abspath(@__FILE__) && Base.find_package("CairoMakie")===nothing
    println("Include examples/repeated_moderation_plot.jl in an analysis environment with CairoMakie installed.")
    exit(0)
end
module RepeatedModerationPlot
using CairoMakie
function figure(report)
    m=report.moderation
    fig=Figure(size=(1150,480),fontsize=15)
    left=Axis(fig[1,1];xlabel="Rater experience (centered example units)",
        ylabel="Association (adjacent logits / rate unit)")
    right=Axis(fig[1,2];xlabel="Rater experience (centered example units)",
        ylabel="Within minus between (same units)")
    for ax in (left,right);hlines!(ax,[0.];color=:gray50,linestyle=:dash);end
    for (kind,color,style,label) in (("between",:darkorange3,:dash,"Between persons"),
            ("within",:steelblue4,:solid,"Within persons"))
        rows=filter(r->string(r.kind)==kind,m.curve)
        x=[r.experience for r in rows]
        band!(left,x,[r.lower for r in rows],[r.upper for r in rows];color=(color,.18))
        lines!(left,x,[r.median for r in rows];color,linestyle=style,label,linewidth=2)
    end
    rows=filter(r->string(r.kind)=="within_minus_between",m.curve)
    x=[r.experience for r in rows]
    band!(right,x,[r.lower for r in rows],[r.upper for r in rows];color=(:steelblue4,.18))
    lines!(right,x,[r.median for r in rows];color=:steelblue4,linewidth=2)
    axislegend(left;position=:lt,framevisible=false)
    fig
end
function caption(report)
    "One artificial repeated-performance fit: 36 people, 108 performances, 10 raters, 432 ratings. "*
    "Lines are posterior medians; shading is pointwise 95% credible intervals for conditional adjacent-logit slopes, not score changes or new-rater predictive intervals. "*
    "The right panel uses paired joint draws for within-minus-between, including coefficient covariance. "*
    "Experience is a centered, artificial scale; only the observed [-1,1] range is shown. "*
    "Only experience -1, 0 and 1 receive focal MCSE checks; these are not simultaneous bands. "*
    "Whole-fit numerical qualification: $(report.qualification.qualified). "*
    join(report.moderation.warnings," ")
end
end
