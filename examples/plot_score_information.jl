using BayesianMGMFRM

"""
    plot_score_information(curves; annotation_io=stdout)

Load `CairoMakie` before calling this function. Including this file needs only
the package. Display an existing `score_information_report` result. Keep the emitted design,
interval and diagnostic note alongside the saved image. No fitting or simulation.
"""
function plot_score_information(curves; annotation_io=stdout)
    @isdefined(CairoMakie) || throw(ArgumentError("Run using CairoMakie before plotting."))
    curves.schema=="bayesianmgmfrm.score_information_report.v1" ||
        throw(ArgumentError("Expected a score_information_report result."))
    fig=CairoMakie.Figure(size=(1100,500),fontsize=15)
    for (column,field,label) in ((1,:expected_score,"Expected total score"),
            (2,:information,"Conditional information (unit logit⁻²)"))
        ax=CairoMakie.Axis(fig[1,column];xlabel="Ability (unit logits)",ylabel=label)
        x=[r.ability for r in curves.test_rows]
        summaries=[getproperty(r,field) for r in curves.test_rows]
        all(s->all(x->x isa Real && isfinite(x),(s.median,s.lower,s.upper)),summaries) ||
            throw(ArgumentError("Cannot plot unavailable summaries; inspect the saved report."))
        CairoMakie.band!(ax,x,[s.lower for s in summaries],[s.upper for s in summaries];color=(:steelblue,.22))
        CairoMakie.lines!(ax,x,[s.median for s in summaries];color=:steelblue4,linewidth=2)
    end
    note="$(curves.n_ratings) conditionally independent ratings: " *
        join(["$(c.item) / $(c.rater) × $(c.repetitions)" for c in curves.rating_design],"; ") *
        ". Medians and $(100curves.interval_probability)% pointwise equal-tailed posterior intervals. " *
        "Not realized-score prediction intervals, posterior precision or reliability. " *
        "Whole-fit warning: $(curves.sampling_warning); numerical warning: $(curves.numerical_warning); " *
        "MCSE unavailable: $(curves.mcse_warning). Inspect detailed MCSE in the saved result."
    println(annotation_io,note)
    return fig
end
