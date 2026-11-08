function _quantities(t,q)
    s=coordinates(t,q);c=components(t,q)
    p0,p1=exp.(c.probs.ordinary),exp.(c.probs.halo)
    # The class is shared across a rater's rows. Keep both log weights, even if
    # subtracting a rounded weight from one would erase a small branch.
    prediction=[exp(logadd(s.log1mpi+c.ell[t.rater[n],1]-c.group[t.rater[n]]+c.probs.ordinary[n,k],
        s.logpi+c.ell[t.rater[n],2]-c.group[t.rater[n]]+c.probs.halo[n,k]))
        for n in eachindex(t.score),k in 1:t.K]
    shift=abs.((p1-p0)*collect(0.:t.K-1))
    (;theta=collect(s.theta),severity=collect(s.severity),delta=Matrix(s.delta),
        sigma=inv.(sqrt.(s.precision)),pi=exp(s.logpi),class_weights=c.weights,
        branch_shift=[mean(shift[findall(==(r),t.rater)]) for r in 1:t.R],prediction)
end

function _draws(t,draws)
    names=[["theta[$p]" for p in 1:t.P];["severity[$r]" for r in 1:t.R];
        ["delta[$i,$k]" for k in 1:t.K-1 for i in 1:t.I];"sigma_person";"sigma_rater";"pi";
        ["class_probability[$r]" for r in 1:t.R];["branch_shift[$r]" for r in 1:t.R]]
    values=Matrix{Float64}(undef,size(draws,1),length(names))
    for (j,q) in enumerate(eachrow(draws))
        x=_quantities(t,q)
        values[j,:]=[x.theta;x.severity;vec(x.delta);x.sigma;x.pi;x.class_weights;x.branch_shift]
    end
    (;names,values,fixed=Set{String}())
end

function _probability_mean(v,chains)
    n=length(v);n%chains==0 || throw(ArgumentError("Incomplete chains"))
    status=!all(isfinite,v) ? :nonfinite_draws : chains<2 ? :insufficient_chains :
        n÷chains<10 ? :insufficient_draws : allequal(v) ? :degenerate_draws : :available
    mcse=status===:available ? B._posterior_mcse_value(reshape(v,n÷chains,chains),mean) : missing
    (;mean=mean(v),mean_mcse=mcse,mcse_status=status===:available && ismissing(mcse) ? :mcse_unavailable : status,
        interval=nothing,total_draws=n,precision_threshold_applied=false)
end

"""
    report(result; interval=.9)

Return posterior probabilities of a constant criterion-collapse class per rater,
with chain-aware MCSE (not credible intervals of conditional class weights).
Continuous location/step/scale/prevalence and descriptive branch-shift summaries
include equal-tailed intervals and endpoint MCSE. Raw, transformed, class and
branch diagnostics, sampler warnings and warmup telemetry are retained.

No class cutoff or precision threshold is chosen. Whole-fit diagnostics do not
qualify focal precision, model adequacy, classification accuracy or fairness.
The branch shift is an absolute expected-score difference at the same parameter
values, not a causal correction, signed halo/horns or proof of a mechanism.
"""
function report(result;interval::Real=.9)
    B._interval_probabilities(interval)
    t=_restore(result);run=result.run;m=_draws(t,run.draws)
    continuous=[j for j in eachindex(m.names) if !startswith(m.names[j],"class_probability[")]
    mcse=B._posterior_mcse_rows(m.values[:,continuous],m.names[continuous],run.controls.chains;
        probabilities=((1-interval)/2,(1+interval)/2),parameter_space=:model_and_branch)
    summaries=[(;parameter=m.names[j],mean=mean(view(m.values,:,j)),
        mean_mcse=v.mean_mcse,mcse_status=v.mcse_status,
        interval=(;method=:equal_tailed,mass=Float64(interval),
            lower=v.quantiles[1].estimate,upper=v.quantiles[2].estimate,
            lower_mcse=v.quantiles[1].mcse,upper_mcse=v.quantiles[2].mcse)) for (j,v) in zip(continuous,mcse)]
    classes=[(;rater=t.data.rater_levels[r],_probability_mean(
        view(m.values,:,only(findall(==("class_probability[$r]"),m.names))),run.controls.chains)...)
        for r in 1:t.R]
    diagnostics=RI._diagnostics(t,run,m)
    (;target_identity=result.target_identity,source_sample_content_hash=result.content_hash,scope=SCOPE,
        prior=_prior(t.prior),controls=run.controls,design=design(t),unit=:unit_logit,
        labels=(;person=copy(t.data.person_levels),criterion=copy(t.data.item_levels),rater=copy(t.data.rater_levels)),
        classes,parameter_summary=summaries,diagnostics,
        precision_threshold_applied=false,automatic_classification=false,
        warning="Experimental criterion-collapse model. Inspect whole-fit diagnostics, focal MCSE, prior sensitivity and category adequacy separately. Low class support does not prove good fit; no automatic rater exclusion, signed halo/horns or fairness conclusion.")
end

function _category_rows(t,draws,chains,max_prediction_cells)
    max_prediction_cells isa Integer && !(max_prediction_cells isa Bool) && max_prediction_cells>0 ||
        throw(ArgumentError("max_prediction_cells must be a positive integer"))
    S=size(draws,1);workspace=big(S)*t.K*t.R*t.I
    workspace<=max_prediction_cells || throw(ArgumentError("Category workspace exceeds max_prediction_cells; raise the budget explicitly rather than drop draws or observations."))
    sums=zeros(S,t.K,t.R,t.I)
    for (j,q) in enumerate(eachrow(draws))
        v=_quantities(t,q)
        for n in eachindex(t.score),k in 1:t.K
            sums[j,k,t.rater[n],t.criterion[n]]+=v.prediction[n,k]
        end
    end
    rows=NamedTuple[]
    for i in 1:t.I,r in 1:t.R,k in 1:t.K
        ids=findall(n->t.rater[n]==r && t.criterion[n]==i,eachindex(t.score))
        observed=count(n->t.score[n]==k-1,ids);n=length(ids)
        expected=_probability_mean(view(sums,:,k,r,i)./n,chains)
        push!(rows,(;rater=t.data.rater_levels[r],criterion=t.data.item_levels[i],
            category=t.data.category_levels[k],n_observations=n,observed_count=observed,
            observed_proportion=observed/n,expected,
            observed_minus_expected=observed/n-expected.mean))
    end
    (;rows,workspace_cells=Int(workspace))
end

"""
    category_report(result; max_prediction_cells=20_000_000)

Observed versus posterior expected category proportions for each rater/criterion
cell, using all original ratings/draws and posterior class weights informed by
all of that rater's rows. Reports integrated means and MCSE, not replicated-count
intervals or a fit test. Retains whole-fit warnings. No prediction RNG is used.

The budget bounds the Float64 draw-by-category-by-cell accumulation only;
additional parameter, observation-probability and diagnostic storage is required.
A marginal row probability must not be multiplied across rows to form a joint
predictive density: the persistent class induces dependence. New levels,
heldout comparison and joint predictive count checks are not supplied here.
"""
function category_report(result;max_prediction_cells::Integer=20_000_000)
    t=_restore(result);run=result.run
    rows=_category_rows(t,run.draws,run.controls.chains,max_prediction_cells)
    diagnostics=RI._diagnostics(t,run,_draws(t,run.draws))
    (;target_identity=result.target_identity,source_sample_content_hash=result.content_hash,scope=SCOPE,
        prior=_prior(t.prior),conditioning=:observed_data_existing_effects,
        n_observations=t.data.n,total_draws=size(run.draws,1),chains=run.controls.chains,
        categories=copy(t.data.category_levels),rows...,diagnostics,
        chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),
        mcse_warning=any(r->r.expected.mcse_status!==:available,rows.rows),
        precision_threshold_applied=false,
        warning="In-sample conditional expectations, not a predictive fit test or mechanism diagnosis. The rater class is shared. Low class probability does not establish category adequacy; check prior sensitivity, MCSE and whole-fit warnings.")
end
