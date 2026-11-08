function _category_cells(d)
    cells=NamedTuple[(;facet=:overall,level=nothing,group=nothing,observations=collect(1:d.n))]
    for facet in (:rater,:item),g in eachindex(d.optional_levels[:group]),j in eachindex(getproperty(d,Symbol(facet,:_levels)))
        ids=findall(n->getproperty(d,facet)[n]==j && d.optional[:group][n]==g,1:d.n)
        push!(cells,(;facet=Symbol(facet,:_group),level=getproperty(d,Symbol(facet,:_levels))[j],group=d.optional_levels[:group][g],observations=ids))
    end
    cells
end

function _category_sums(t,draws,max_prediction_cells)
    max_prediction_cells isa Integer && !(max_prediction_cells isa Bool) && max_prediction_cells>0 ||
        throw(ArgumentError("max_prediction_cells must be a positive integer"))
    d=t.data;S=size(draws,1);K=length(d.category_levels);G=length(t.group_people)
    R,I=length(d.rater_levels),length(d.item_levels);C=1+(R+I)*G
    workspace=big(S)*K*C+K
    workspace<=max_prediction_cells || throw(ArgumentError("category aggregation workspace exceeds max_prediction_cells; raise the explicit budget rather than silently dropping draws or observations"))
    size(draws,2)==L.dimension(t) && S>=2 && all(isfinite,draws) || throw(ArgumentError("Expected at least two finite, complete coordinate draws"))
    sums=zeros(S,K,C);a=zeros(K)
    # Each observed rating is evaluated once per draw, then assigned to three cells.
    for (s,q) in enumerate(eachrow(draws))
        v=coordinates(t,q)
        for n in 1:d.n
            z=_weights!(a,v,d,n);g=d.optional[:group][n]
            rc=1+(g-1)*R+d.rater[n];ic=1+R*G+(g-1)*I+d.item[n]
            for k in 1:K
                p=exp(a[k]-z);isfinite(p) || throw(ArgumentError("Nonfinite category probability"))
                sums[s,k,1]+=p;sums[s,k,rc]+=p;sums[s,k,ic]+=p
            end
        end
    end
    (;sums,workspace_cells=Int(workspace))
end

function _category_rows(t,draws,chains,interval,max_prediction_cells)
    B._interval_probabilities(interval)
    accumulated=_category_sums(t,draws,max_prediction_cells);d=t.data
    usage=NamedTuple[];scores=NamedTuple[]
    for (c,cell) in enumerate(_category_cells(d))
        n=length(cell.observations);base=(;cell.facet,cell.level,cell.group,n_observations=n,
            status=n==0 ? :unobserved_cell : :observed_cell)
        score_draws=zeros(size(draws,1))
        for (k,category) in enumerate(d.category_levels)
            observed=count(j->d.category[j]==k,cell.observations)
            values=n==0 ? nothing : accumulated.sums[:,k,c]./n
            expected=n==0 ? nothing : B._category_report_summary(values,chains,interval;space=:probability)
            n>0 && (score_draws .+= category.*values)
            proportion=n==0 ? missing : observed/n
            discrepancy=n==0 || ismissing(expected.mean) ? missing : proportion-expected.mean
            push!(usage,(;base...,category,observed_count=observed,observed_proportion=proportion,expected,observed_minus_expected=discrepancy))
        end
        observed=n==0 ? missing : mean(d.score[cell.observations])
        expected=n==0 ? nothing : B._category_report_summary(score_draws,chains,interval;space=:expected_score)
        push!(scores,(;base...,observed_mean=observed,expected,
            observed_minus_expected=n==0 || ismissing(expected.mean) ? missing : observed-expected.mean))
    end
    (;category_rows=usage,score_rows=scores,workspace_cells=accumulated.workspace_cells)
end

"""
    category_report(result; interval=.95, max_prediction_cells=20_000_000)

Compare observed category proportions and scores with posterior expected values
overall, by rater/group and by item/group. Uses all original observations and
joint retained draws, with mean/interval MCSE and whole-fit warnings. Empty
item/group cells remain explicit with unavailable expectations; unobserved
categories in observed cells retain their declared support.

Intervals describe uncertainty in expected proportions/mean scores conditional
on fitted people, raters, items and group assignments. They are NOT replicated
outcome intervals, new-level predictions, p-values or a model-adequacy test.
Different cells can contain different people/items: descriptive residuals are
not adjusted rater contrasts or evidence of bias. Use `contrast` for rater gaps.

No random generation or draw subsampling occurs. The explicit limit bounds the
Float64 category accumulation/logit workspace, `S*K*(1+(R+I)*G)+K`, not total
memory, restored samples, summaries or diagnostics. Save with `save_report`.
"""
function category_report(result;interval::Real=.95,max_prediction_cells::Integer=20_000_000)
    B._interval_probabilities(interval)
    t=_restore(result);run=result.run
    rows=_category_rows(t,run.draws,run.controls.chains,interval,max_prediction_cells)
    diagnostics=RI._diagnostics(t,run,_draws(t,run.draws))
    summaries=[r.expected for r in [rows.category_rows;rows.score_rows] if r.expected!==nothing]
    body=(;kind=:rater_group_category_report,target_identity=result.target_identity,
        source_sample_content_hash=result.content_hash,scope=SCOPE,prior=_prior(t.prior),
        conditioning=:observed_people_items_raters_and_groups,observation_scope=:all_original_rows,
        n_observations=t.data.n,total_draws=size(run.draws,1),chains=run.controls.chains,
        max_prediction_cells,
        chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),interval=Float64(interval),
        categories=copy(t.data.category_levels),rows...,diagnostics,
        sampling_warning=!diagnostics.qualified,
        numerical_warning=any(s->s.status in (:nonfinite_draws,:nonfinite_summary),summaries),
        mcse_warning=any(s->s.status===:mcse_unavailable,summaries),
        precision_threshold_applied=false,
        warning="Descriptive in-sample discrepancies only. Expected-value intervals are not replicated-outcome intervals or fit tests. Inspect focal MCSE and whole-fit warnings; no automatic DIF, bias or fairness decision.")
    merge(body,(;content_hash=B._cache_hash(body)))
end
