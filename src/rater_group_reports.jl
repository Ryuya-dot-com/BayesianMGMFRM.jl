function _draws(t,draws)
    d=t.data;P,R,I,K,G=length(d.person_levels),length(d.rater_levels),length(d.item_levels),length(d.category_levels),length(t.group_people)
    names=[["person[$p]" for p in 1:P];["group_mean[$g]" for g in 1:G];["item[$i]" for i in 1:I];["rater[$r]" for r in 1:R];
        ["step[$i,$k]" for k in 1:K-1 for i in 1:I];["interaction[$r,$g]" for g in 1:G for r in 1:R];"tau"]
    vals=Matrix{Float64}(undef,size(draws,1),length(names))
    for (n,q) in enumerate(eachrow(draws))
        v=coordinates(t,q);vals[n,:]=[v.person;v.group_mean;v.item;v.rater;vec(v.steps);vec(v.interaction);v.tau]
    end
    fixed=K==2 ? Set(["step[$i,1]" for i in 1:I]) : Set{String}()
    (;names,values=vals,fixed)
end
function _level(value,levels,kind)
    index=findfirst(isequal(value),levels)
    index===nothing && throw(ArgumentError("Unknown $kind label: $value"))
    index
end

"""
    report(result; reference_group, practical_threshold, interval=.95)

Fitted rater/group cells and each rater's severity change from `reference_group`,
with joint-draw intervals and mean/endpoint/event MCSE. Includes cohort means,
all parameter summaries and whole-fit raw/model/sampler/warmup diagnostics.
Positive changes mean greater relative severity. The threshold is in unit logits;
choose it for the question. This does not establish bias, fairness or multiplicity
control, and cannot separate a shared panel penalty from group ability.
"""
function report(result;reference_group,practical_threshold,interval=.95)
    margin=RI._margin(practical_threshold);t=_restore(result);run=result.run;m=_draws(t,run.draws)
    d=t.data;R,G=length(d.rater_levels),length(t.group_people)
    ref=_level(reference_group,d.optional_levels[:group],"group")
    column(r,g)=view(m.values,:,only(findall(==("interaction[$r,$g]"),m.names)))
    cells=[(;rater=d.rater_levels[r],group=d.optional_levels[:group][g],n=t.allocation.counts[r,g],
        people=t.allocation.people[r,g],summary=RI._summary(column(r,g),run,interval,margin)) for g in 1:G for r in 1:R]
    changes=[(;rater=d.rater_levels[r],group=d.optional_levels[:group][g],reference_group,
        summary=RI._summary(column(r,g).-column(r,ref),run,interval,margin)) for g in 1:G if g!=ref for r in 1:R]
    parameter_rows=B._posterior_summary_rows(m.values,m.names;lower=(1-interval)/2,
        upper=(1+interval)/2,intervals=(interval,),reference=0.,rope=nothing,rope_probability_threshold=.95)
    (;target_identity=result.target_identity,source_sample_content_hash=result.content_hash,scope=SCOPE,
        prior=_prior(t.prior),controls=run.controls,design=design(t),unit=:unit_logit,
        positive_effect=:additional_relative_severity,reference_group,practical_threshold=margin,interval,cells,changes,
        diagnostics=RI._diagnostics(t,run,m),
        labels=(;person=copy(d.person_levels),item=copy(d.item_levels),rater=copy(d.rater_levels),group=copy(d.optional_levels[:group])),
        parameter_summary=[(;r.parameter,r.mean,r.sd,r.median,r.intervals,r.n_draws) for r in parameter_rows],
        warning="Experimental relative panel effects. Check whole-fit diagnostics AND focal MCSE; item/step invariance and prior sensitivity remain assumptions to assess. No automatic bias, fairness or multiplicity decision.")
end

"""
    contrast(result; left, right, group, reference_group, practical_threshold, interval=.95)

Compare two existing raters at two distinct observed groups. Return overall
(left-right) severity, severity differences at each group, and the difference
of those differences (`difference_in_differences`). Positive values mean the
left rater is relatively more severe for `group` than for `reference_group`.
All contrasts use paired joint draws and preserve global diagnostic warnings.
"""
function contrast(result;left,right,group,reference_group,practical_threshold,interval=.95)
    margin=RI._margin(practical_threshold);t=_restore(result);d=t.data;run=result.run
    a,b=_level(left,d.rater_levels,"rater"),_level(right,d.rater_levels,"rater")
    g,h=_level(group,d.optional_levels[:group],"group"),_level(reference_group,d.optional_levels[:group],"group")
    a!=b && g!=h || throw(ArgumentError("Choose distinct raters and distinct groups."))
    values=Matrix{Float64}(undef,size(run.draws,1),4)
    for (n,q) in enumerate(eachrow(run.draws))
        v=coordinates(t,q);overall=v.rater[a]-v.rater[b]
        at_group=overall+v.interaction[a,g]-v.interaction[b,g]
        at_reference=overall+v.interaction[a,h]-v.interaction[b,h]
        values[n,:]=[overall,at_group,at_reference,at_group-at_reference]
    end
    summaries=map(j->RI._summary(values[:,j],run,interval,margin),1:4)
    (;target_identity=result.target_identity,source_sample_content_hash=result.content_hash,
        left,right,group,reference_group,unit=:unit_logit,positive_effect=:greater_relative_severity,practical_threshold=margin,
        overall=summaries[1],at_group=summaries[2],at_reference_group=summaries[3],difference_in_differences=summaries[4],
        diagnostics=RI._diagnostics(t,run,_draws(t,run.draws)),chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),
        evaluated_draws_hash=B._cache_hash(values),scope=SCOPE)
end
