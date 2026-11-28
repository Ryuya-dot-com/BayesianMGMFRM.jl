"""Prepare component or D-study figures from saved G-theory results, without fitting."""
function plot_data(obj;kind=:components,counts=nothing,score="composite",metric=:Phi,weights=nothing,interval=.95,interval_method=nothing)
    likelihood=obj isa Union{LikelihoodFit,LikelihoodReport}
    interval_method===nothing || (likelihood && kind===:dstudy && interval_method in (:delta,:exact,:mean_square_region)) ||
        throw(ArgumentError("interval_method applies to ML/REML D-study plots: :delta, :exact or :mean_square_region"))
    interval_method===:exact && metric ∉ (:G,:relative_sem) && throw(ArgumentError("exact plots support G or relative_sem"))
    kind in (:components,:variance,:covariance,:dstudy) || throw(ArgumentError("G-theory plots use :components, :variance, :covariance or :dstudy"))
    if kind!==:dstudy
        data=component_summary(obj;interval)
        rows=filter(r->kind===:components || (kind===:variance ? r.score1==r.score2 : r.score1!=r.score2),data.rows)
        isempty(rows) && throw(ArgumentError("no components for the requested plot"))
        return merge(data,(;kind,rows))
    end
    counts isa NamedTuple || throw(ArgumentError("D-study plots require counts=(rater=1:6, task=[1,2]), naming every facet"))
    metric in (:G,:Phi,:relative_sem,:absolute_sem) || throw(ArgumentError("unknown D-study metric"))
    grids=map(values(counts)) do v
        vals=v isa Integer ? [v] : collect(v)
        !isempty(vals) && all(n->n isa Integer && !(n isa Bool) && n>0,vals) && allunique(vals) || throw(ArgumentError("each facet grid needs distinct positive integers"))
        sort(vals)
    end
    options=interval_method===nothing ? (;) : (;interval_method)
    region=record=nothing
    if interval_method===:mean_square_region
        record=obj isa LikelihoodFit ? report(obj).record : check_likelihood_report(obj.record).record
        C=length(record.scores)
        w=if string(score)=="composite"
            weights===nothing ? fill(1/C,C) : Float64.(collect(weights))
        else
            j=findfirst(==(string(score)),string.(record.scores))
            j===nothing && throw(ArgumentError("unknown score"))
            Float64.(1:C .== j)
        end
        region=mean_square_region(record,w,interval)
        options=(;interval_method=:delta)
    end
    rows=map(vec(collect(Iterators.product(grids...)))) do vals
        plan=NamedTuple{keys(counts)}(vals);d=B.reliability(obj;counts=plan,weights,interval,options...)
        i=findfirst(r->r.score==string(score),d.rows)
        i===nothing && throw(ArgumentError("unknown score; use composite or a declared score column"))
        st=getproperty(d.rows[i],metric)
        if region!==nothing
            metrics=(:G,:Phi,:relative_sem,:absolute_sem,:universe_variance,:absolute_error_variance)
            estimates=[getproperty(d.rows[i],m).estimate for m in metrics]
            st=region_design_intervals(region,record.components,plan,estimates)[findfirst(==(metric),metrics)]
        end
        (;counts=plan,estimate=likelihood ? st.estimate : st.mean,lower=st.lower,upper=st.upper,
            status=likelihood ? st.status : :posterior)
    end
    qual=obj isa Union{Fit,LikelihoodFit,LikelihoodReport} ? B.qualify(obj) : obj.record.qualification
    (;kind,rows,score=string(score),metric,weights,facets=collect(keys(counts)),interval,interval_method,
        interval_kind=likelihood ? :confidence : :credible,qualification=qual)
end
