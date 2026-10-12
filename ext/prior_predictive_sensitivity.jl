function plot_prior_predictive_sensitivity(result; statistic=:category_proportion,
        levels=nothing, annotation_io=stdout, size=nothing)
    B._prediction_check_seal(result, B._PRIOR_PREDICTIVE_SENSITIVITY_SCHEMA)
    reference = first(e.evaluation for e in result.ledger if e.evaluation !== nothing)
    available = [r for r in reference.rows if r.statistic === statistic]
    isempty(available) && throw(ArgumentError("unknown predictive statistic"))
    selected = levels === nothing ? getproperty.(available,:level) : collect(levels)
    !isempty(selected) && length(unique(selected)) == length(selected) &&
        all(l -> any(r -> isequal(r.level,l), available),selected) ||
        throw(ArgumentError("unknown, repeated or empty level selection"))
    offset = _annotation_offset(annotation_io)
    n = length(result.ledger)
    fig = Figure(; size=something(size,(1000,length(selected)*(100+45n)+120offset)),fontsize=15)
    positions = collect(n:-1:1)
    labels = [e.prior_id*(e.status===:descriptive ? "" : " [$(e.status)]") for e in result.ledger]
    for (i,level) in enumerate(selected)
        observed = only(r.observed for r in available if isequal(r.level,level))
        heading = get(Dict(:category_proportion=>"Category", :person_mean=>"Person",
            :item_mean=>"Item", :rater_mean=>"Rater", :mean_score=>"Overall mean score"),
            statistic, replace(string(statistic), "_"=>" "))
        title = ismissing(level) ? heading : "$heading $level"
        xlabel = statistic===:category_proportion ? "Proportion of rating rows" : "Mean score"
        ax = Axis(fig[i+offset,1];title,xlabel,yticks=(positions,labels),
            xgridvisible=false,ygridvisible=false,topspinevisible=false,rightspinevisible=false)
        for (j,e) in enumerate(result.ledger)
            e.evaluation===nothing && continue
            row=only(r for r in e.evaluation.rows if r.statistic===statistic && isequal(r.level,level))
            rangebars!(ax,[positions[j]],[row.replicated_lower],[row.replicated_upper];
                direction=:x,color=:steelblue4,whiskerwidth=8,linewidth=2)
            scatter!(ax,[row.replicated_median],[positions[j]];color=:steelblue4,markersize=9)
        end
        vlines!(ax,[observed];color=:gray30,linestyle=:dash,linewidth=1.5)
        xmin,xmax=statistic===:category_proportion ? (0.,1.) : extrema(result.category_levels)
        margin=.025*(xmax-xmin)
        xlims!(ax,xmin-margin,xmax+margin)
        ylims!(ax,.5,n+.5)
    end
    draws=join(["$(e.prior_id): $(e.evaluation.ndraws)" for e in result.ledger if e.evaluation!==nothing],"; ")
    caption="Dots are prior predictive medians; bars are $(round(100result.interval_probability;digits=2))% equal-tailed predictive intervals. "*
        "Dashed lines are observed statistics. All panels share the statistic's possible scale. "*
        "These intervals describe replicated score statistics, not posterior parameter uncertainty. "*
        "IID prior/response draws per variant: $draws. Existing rating rows and facet levels are held fixed; observed scores do not update the priors. "*
        "The saved result contains actual priors, seeds, per-draw statistics and IID mean/tail MCSE. Endpoint MCSE is not computed; a zero empirical MCSE need not mean exactness. "*
        "Missing/failed variants remain in the roster. Posterior statuses are recorded separately. "*
        "Agreement of these summaries with the data does not establish model adequacy, calibration or a preferred prior. Dataset: $(result.dataset_id)."
    return _figure_text!(fig,"Prior predictive sensitivity",caption;annotation_io,bottom_row=length(selected)+2)
end
