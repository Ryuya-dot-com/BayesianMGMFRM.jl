# Model-specific blueprints keep the common reporting target independent of fitting.
function AdditiveFacets.fair_reference_basis(t::ScaleIdentifiedMGMFRM.Target)
    fmt=ScaleIdentifiedMGMFRM._fmt_label
    people=map(1:t.P) do p
        ix=findall(==(p),t.person)
        (;level=deepcopy(t.person_levels[p]),parameters=t.model_names[(p-1)*t.D+1:p*t.D],
            n_observations=length(ix),observed_average=mean(t.category_levels[t.category[ix]]),
            observed_categories=copy(t.category_levels))
    end
    item_role=t.prior.item_role
    facets=[(;name=role,levels=deepcopy(levels),parameters=["$pname[$(fmt(x))]" for x in levels])
        for (role,pname,levels) in ((item_role,:item,t.item_levels),(:rater,:rater,t.rater_levels))]
    steps=[(;level=deepcopy(t.step_group_levels[g]),categories=copy(t.category_levels),
        parameters=["step[$(t.step_owner===:global ? "global" : fmt(t.step_group_levels[g])), $h]" for h in 1:t.H]) for g in 1:t.n_step_groups]
    (;schema=AdditiveFacets.FAIR_REFERENCE_BASIS_SCHEMA,kernel=:mgmfrm,people,facets,steps,
        owner=t.step_owner===:item ? item_role : t.step_owner,intercept=nothing,shared=NamedTuple[],active_dims=deepcopy(t.active_dims_of_item),
        loadings=[["loading[$(fmt(t.item_levels[i])), dim=$d]" for d in t.active_dims_of_item[i]] for i in 1:t.I],
        consistency=["consistency[$(fmt(x))]" for x in t.rater_levels],
        logit_scale=t.prior.logit_scale,item_slope_scope=t.prior.item_slope_scope,
        rater_slope_scope=t.prior.rater_slope_scope,aggregation=t.prior.aggregation,
        cross_loading_average=t.prior.cross_loading_average,
        softmin_kappa=t.prior.aggregation===:softmin ? "softmin_kappa" : nothing)
end
AdditiveFacets.fair_reference_draws(t::ScaleIdentifiedMGMFRM.Target,raw)=ScaleIdentifiedMGMFRM.model_draws(t,raw)
AdditiveFacets.fair_reference_warnings(t::ScaleIdentifiedMGMFRM.Target)=validate_design(t).warnings

function plot(f::ScaleIdentifiedMGMFRM.Fit;kind::Symbol=:posterior,kwargs...)
    kind===:fair_average && return _plot_additive_report(f;kind,kwargs...)
    extension=Base.get_extension(@__MODULE__,:BayesianMGMFRMCairoMakieExt)
    extension===nothing && throw(ArgumentError("plot requires `using CairoMakie`"))
    extension.plot_scale_identified_mgmfrm(f;kind,kwargs...)
end
