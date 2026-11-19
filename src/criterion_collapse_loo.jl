# Conditional leave-profile densities: their product is NOT the fitted likelihood.
function _heldout_design(t,unit)
    unit===:performance_rater || throw(ArgumentError("choose unit=:performance_rater explicitly; this predicts an observed profile in the original finite panel"))
    groups=Vector{Int}[];keys=Tuple{Int,Int}[];lookup=Dict{Tuple{Int,Int},Int}()
    for n in eachindex(t.score)
        key=(t.person[n],t.rater[n])
        if !haskey(lookup,key)
            push!(keys,key);push!(groups,Int[]);lookup[key]=length(groups)
        end
        push!(groups[lookup[key]],n)
    end
    profiles=NamedTuple[]
    for (j,ns) in enumerate(groups)
        p,r=keys[j]
        count(==(p),t.person)>length(ns) && count(==(r),t.rater)>length(ns) ||
            throw(ArgumentError("profile $j leaves a person or rater without other ratings; this is not the supported known-level prediction task"))
        push!(profiles,(;profile=j,person=t.data.person_levels[p],rater=t.data.rater_levels[r],
            rows=ns,criteria=t.data.item_levels[t.criterion[ns]],n_ratings=length(ns)))
    end
    observations=[(;row=n,person=t.data.person_levels[t.person[n]],rater=t.data.rater_levels[t.rater[n]],
        criterion=t.data.item_levels[t.criterion[n]],score=t.data.category_levels[t.data.category[n]]) for n in eachindex(t.score)]
    (;unit,profiles,groups,keys,observations,categories=copy(t.data.category_levels),
        observation_binding=B._cache_hash((;observations,categories=t.data.category_levels)))
end

function _heldout_values(t,draws,d)
    S=size(draws,1);M=length(d.groups)
    mixture=zeros(S,M);ordinary=similar(mixture);loga=zeros(S)
    for (j,q) in enumerate(eachrow(draws))
        c=components(t,q);s=coordinates(t,q)
        loga[j]=sum(_class_logweights(t,q,c).ordinary)
        for (h,ns) in enumerate(d.groups)
            r=d.keys[h][2]
            a=sum(c.probs.ordinary[n,t.score[n]+1] for n in ns)
            b=sum(c.probs.halo[n,t.score[n]+1] for n in ns)
            u=s.log1mpi+c.ell[r,1]-a;v=s.logpi+c.ell[r,2]-b
            normalizer=logadd(u,v)
            mixture[j,h]=logadd(u-normalizer+a,v-normalizer+b)
            ordinary[j,h]=a
        end
    end
    (;mixture,ordinary,loga)
end

function _heldout_model_arrays(x,model)
    model===:mixture && return (;log_density=x.mixture,log_ratios=-x.mixture)
    model===:all_ordinary && return (;log_density=x.ordinary,log_ratios=x.loga.-x.ordinary)
    throw(ArgumentError("model must be :mixture or :all_ordinary (its induced prior)"))
end

function _heldout_metadata(d)
    (;unit=d.unit,likelihood_kind=:conditional_holdout_ratio,factorizes_joint=false,
        conditioning=:known_people_raters_original_finite_panel,profiles=d.profiles,
        observations=d.observations,categories=d.categories,observation_binding=d.observation_binding,
        n_profiles=length(d.profiles),n_observations=length(d.observations),
        sampling_standard_error=missing,sampling_uncertainty=:not_assessed_crossed_overlapping_folds,
        waic=:unsupported_for_conditional_ratio_columns,
        mcse_method=:chain_aware_smoothed_ratio_delta,
        smoothing_fit_uncertainty=:not_separately_estimated)
end

"""
    pointwise_loglikelihood(result; unit=:performance_rater, model=:mixture)

Inspect all stored-draw conditional held-out log densities and the actual
full-mixture-posterior proposal ratios. Choose the profile unit explicitly.
Columns are joint observed performance/rater profiles, not independent rows;
their product does not recover the fitted likelihood. Do not use them for WAIC.
The induced all-ordinary model also needs its returned `log_ratios`; treating
these draws as ordinary-model posterior draws is incorrect. No fitting or RNG.
"""
function pointwise_loglikelihood(result;unit=nothing,model=:mixture)
    model in (:mixture,:all_ordinary) || throw(ArgumentError("model must be :mixture or :all_ordinary"))
    t=_restore(result);d=_heldout_design(t,unit);x=_heldout_values(t,result.run.draws,d)
    (;_heldout_metadata(d)...,model,target_identity=result.target_identity,
        source_sample_content_hash=result.content_hash,prior=_prior(t.prior),
        chain_ids=copy(result.run.chain_ids),iterations=copy(result.run.iterations),
        _heldout_model_arrays(x,model)...)
end

function _heldout_precision(influence,run,eligible)
    f=_functional(influence,run)
    status=!eligible ? :unstable_importance_weights : f.diagnostics.flag!==:ok ? :focal_diagnostics_failed : f.mcse_status
    (;mcse=status===:available ? f.mean_mcse : missing,mcse_status=status,diagnostics=f.diagnostics)
end

function _profile_score(logf,lr,run)
    S=length(lr);chains=run.controls.chains;perchain=div(S,chains)
    S%chains==0 && perchain>=8 && all(isfinite,logf) && all(isfinite,lr) ||
        throw(ArgumentError("profile PSIS needs finite joint draws and at least eight draws per chain"))
    # Reference PSIS uses relative efficiency of the inverse proposal ratio.
    inverse=exp.(-lr .- maximum(-lr))
    reff=all(==(first(inverse)),inverse) ? missing :
        Float64(B.MCMCDiagnosticTools.ess(reshape(inverse,perchain,chains);kind=:basic,split_chains=2))/S
    valid_reff=!ismissing(reff) && isfinite(reff) && reff>0
    valid_reff || (reff=missing)
    ps=B._SA_MOD._psis_smooth_log_ratios(Float64.(lr);r_eff=valid_reff ? reff : 1.)
    score=B._logsumexp(logf.+ps.norm_log_weights)
    # Delta influence for log(E[w*f]/E[w]); joint order retains cross-fold covariance.
    influence=S.*(exp.(ps.norm_log_weights.+logf.-score).-exp.(ps.norm_log_weights))
    threshold=B._SA_MOD._ps_khat_threshold(S)
    eligible=valid_reff && isfinite(ps.pareto_k) && ps.pareto_k<threshold
    precision=_heldout_precision(influence,run,eligible)
    row=(;log_score=score,precision...,pareto_k=ps.pareto_k,pareto_k_threshold=threshold,
        r_eff=reff,importance_ess=valid_reff ? ps.n_eff : missing,smoothed_weight_ess=ps.n_eff_raw,
        tail_draws=ps.tail_len,importance_status=eligible ? :ok : :diagnostic_only,
        raw_is_log_score=B._logsumexp(logf.+lr)-B._logsumexp(lr))
    (;row,influence,normalized_log_weights=ps.norm_log_weights)
end

function _resolve_profile_index(d,profile_id)
    if profile_id isa Integer && !(profile_id isa Bool)
        idx=Int(profile_id)
        1<=idx<=length(d.profiles) || throw(ArgumentError("profile index $idx is outside 1:$(length(d.profiles))"))
        return idx
    elseif profile_id isa NamedTuple && Set(keys(profile_id))==Set((:person,:rater))
        idx=findfirst(p->isequal(p.person,profile_id.person) && isequal(p.rater,profile_id.rater),d.profiles)
        idx===nothing && throw(ArgumentError("unknown (person, rater) profile $(repr(profile_id))"))
        return idx
    elseif profile_id isa Tuple && length(profile_id)==2
        idx=findfirst(p->isequal(p.person,profile_id[1]) && isequal(p.rater,profile_id[2]),d.profiles)
        idx===nothing && throw(ArgumentError("unknown (person, rater) profile $(repr(profile_id))"))
        return idx
    end
    throw(ArgumentError("profile_id must be an integer profile index 1..M or (person=..., rater=...) / (person, rater)"))
end

"""
    loo_refit_plan(result, profile_id; unit=:performance_rater, model=:mixture)

Build an explicit held-profile training target for a CriterionCollapse fit,
retaining all original people, raters, criteria, categories, orthonormal finite
bases, and priors while masking the observed ratings of `profile_id` (`1..M` or
`(person=..., rater=...)`). For `model=:all_ordinary`, the nuisance mixing
proportion `pi` is analytically integrated out (`halo=false`). Fit `plan.target`
with an independent RNG seed via `fit(plan.target; ...)`, then pass
`profile_id => refit_result` to `criteria(...; refits=[...], independent_refit_rng=true)`
or `compare_models(...; criterion=:loo, unit=:performance_rater, ...)`.
"""
function loo_refit_plan(result,profile_id;unit=nothing,model=:mixture)
    model in (:mixture,:all_ordinary) || throw(ArgumentError("model must be :mixture or :all_ordinary"))
    t=_restore(result);d=_heldout_design(t,unit)
    idx=_resolve_profile_index(d,profile_id);p=d.profiles[idx]
    heldout=copy(d.groups[idx]);retained=setdiff(1:t.data.n,heldout)
    # Check that remaining ratings still keep every rater-criterion cell observed for step identification
    if any(count(n->t.rater[n]==r && t.criterion[n]==i,retained)==0 for r in 1:t.R, i in 1:t.I)
        # Note: steps are criterion-owned (delta[i,k]), not rater-criterion owned; ensure every criterion has ratings!
        any(count(n->t.criterion[n]==i,retained)==0 for i in 1:t.I) &&
            throw(ArgumentError("withholding profile $(p.profile) removes all observations of a criterion"))
    end
    base=model===:mixture ? t : Target((f===:halo ? false : getfield(t,f) for f in fieldnames(Target))...)
    mt=MaskedTarget(base,idx,heldout,retained,model,result.target_identity)
    (;target=mt,profile=p.profile,person=p.person,rater=p.rater,heldout_rows=heldout,
      unit=:performance_rater,model,source_sample_content_hash=result.content_hash,
      target_identity=result.target_identity,observation_binding=d.observation_binding,
      automatic_refit=false)
end

function _validate_cc_refits(t,d,result,model,refits)
    items=collect(refits)
    isempty(items) && return Dict{Int,NamedTuple}()
    out=Dict{Int,NamedTuple}()
    for item in items
        item isa Pair || throw(ArgumentError("refits must be profile_id => masked_fit pairs"))
        pid,rf=first(item),last(item)
        idx=_resolve_profile_index(d,pid)
        haskey(out,idx) && throw(ArgumentError("duplicate refit for profile $idx"))
        mt=_restore_masked(rf)
        mt.parent_target_identity==result.target_identity && mt.profile==idx && mt.model===model &&
            mt.heldout==d.groups[idx] && mt.retained==setdiff(1:t.data.n,d.groups[idx]) ||
            throw(ArgumentError("masked refit for profile $idx does not match loo_refit_plan target"))
        md=_masked_draws(mt,rf.run.draws)
        diag=RI._diagnostics(mt,rf.run,md)
        qual=B._qualify_experimental_diagnostics(diag,rf.run,rf.run.checked,.3)
        fine=_masked_heldout_logprobs(mt,rf.run.draws)
        score=_logmean(fine)
        prec=_heldout_precision(exp.(fine.-score).-1.,rf.run,qual.qualified)
        out[idx]=(;fit=rf,mt,qual,fine,score,prec)
    end
    out
end

function _heldout_evaluation(x,run,model;t=nothing,d=nothing,result=nothing,refits=(),independent_refit_rng::Bool=false)
    a=_heldout_model_arrays(x,model);S,M=size(a.log_density)
    supplied=isempty(refits) ? Dict{Int,NamedTuple}() : _validate_cc_refits(t,d,result,model,refits)
    if !isempty(supplied) && independent_refit_rng
        hashes=[result.content_hash;[v.fit.content_hash for v in values(supplied)]]
        allunique(hashes) || throw(ArgumentError("baseline and masked refit sample records must have distinct hashes"))
    end
    rows=NamedTuple[];influences=zeros(S,M);ref_records=NamedTuple[];direct_var=0.0
    for h in 1:M
        z=_profile_score(view(a.log_density,:,h),view(a.log_ratios,:,h),run)
        if !haskey(supplied,h)
            if isempty(supplied)
                push!(rows,(;profile=h,z.row...))
            else
                push!(rows,(;profile=h,z.row...,method=:psis,original_log_score=z.row.log_score))
            end
            influences[:,h]=z.influence
        else
            sr=supplied[h]
            ok=independent_refit_rng && sr.qual.qualified && sr.prec.mcse_status===:available
            mcse_val=ok ? sr.prec.mcse : missing
            mcse_st=!independent_refit_rng ? :unassessed_refit_covariance : (!sr.qual.qualified ? :focal_diagnostics_failed : sr.prec.mcse_status)
            row_ref=(;profile=h,log_score=sr.score,mcse=mcse_val,mcse_status=mcse_st,diagnostics=sr.prec.diagnostics,
                pareto_k=z.row.pareto_k,pareto_k_threshold=z.row.pareto_k_threshold,
                r_eff=z.row.r_eff,importance_ess=z.row.importance_ess,smoothed_weight_ess=z.row.smoothed_weight_ess,
                tail_draws=z.row.tail_draws,importance_status=ok ? :ok : :diagnostic_only,
                raw_is_log_score=z.row.raw_is_log_score,method=:direct_refit,original_log_score=z.row.log_score)
            push!(rows,row_ref)
            push!(ref_records,(;profile=h,source_sample_content_hash=sr.fit.content_hash,
                target_identity=sr.fit.target_identity,qualified=sr.qual.qualified,
                log_score=sr.score,original_psis_log_score=z.row.log_score,
                original_pareto_k=z.row.pareto_k,mcse=mcse_val,mcse_status=mcse_st))
            ok && (direct_var+=Float64(mcse_val)^2)
        end
    end
    psis_idxs=[h for h in 1:M if !haskey(supplied,h)]
    good=all(r->r.importance_status===:ok,rows) && (isempty(supplied) || independent_refit_rng)
    psis_total=isempty(psis_idxs) ? (;mcse=0.0,mcse_status=:available,diagnostics=rows[1].diagnostics) :
        _heldout_precision(vec(sum(view(influences,:,psis_idxs);dims=2)),run,good)
    tot_ok=good && psis_total.mcse_status===:available
    tot_mcse=tot_ok ? sqrt(Float64(psis_total.mcse)^2+direct_var) : missing
    tot_status=(!isempty(supplied) && !independent_refit_rng) ? :unassessed_refit_covariance :
        (!good ? :unstable_importance_weights : psis_total.mcse_status)
    base_rep=(;model,pointwise=rows,elpd=sum(r.log_score for r in rows),
        mcse=tot_mcse,mcse_status=tot_status,diagnostics=psis_total.diagnostics,
        mean_log_score=mean(r.log_score for r in rows),mean_mcse=ismissing(tot_mcse) ? missing : tot_mcse/M,
        problem_profiles=[r.profile for r in rows if r.importance_status!==:ok],
        status=good ? :estimated : :diagnostic_only,
        mcse_warning=tot_status!==:available || any(r->r.mcse_status!==:available,rows))
    report=isempty(supplied) ? base_rep : merge(base_rep,(;reference_records=ref_records,independent_refit_rng))
    (;report,influences,psis_idxs,direct_var)
end

const _HELDOUT_WARNING="Conditional leave-profile prediction for the original finite panel, not new-level accuracy or halo detection. PSIS and its chain-aware smoothed-ratio delta MCSE are approximations; smoothing-fit uncertainty is not estimated separately. Failed weight diagnostics invalidate precision. Inspect whole-fit and focal diagnostics and choose useful MCSE limits. Sampling/design uncertainty is unassessed; no iid comparison SE, WAIC, ranking or automatic refit is supplied."

"""
    criteria(result; unit=:performance_rater, model=:mixture)

Conditional leave-profile PSIS log scores from all stored draws, preserving the
original finite-panel prior and persistent rater classes. `unit` is required;
`model=:all_ordinary` conditions on the encompassing model's all-ordinary event.
Returns profile bindings, Pareto-k, relative efficiency, importance ESS, approximate
chain-aware delta MCSE and unchanged whole-fit diagnostics. A failed tail/relative
efficiency check retains the estimate as diagnostic-only and makes MCSE unavailable.
MCSE includes shared-draw covariance in totals, but does not separately estimate
tail-fit uncertainty. No precision cutoff or iid sampling SE is supplied. No WAIC,
new-level prediction, subsampling, automatic refit or RNG. Save via `save_report`.
"""
function criteria(result;unit=nothing,model=:mixture,refits=(),independent_refit_rng::Bool=false)
    model in (:mixture,:all_ordinary) || throw(ArgumentError("model must be :mixture or :all_ordinary"))
    t=_restore(result);d=_heldout_design(t,unit);x=_heldout_values(t,result.run.draws,d)
    z=_heldout_evaluation(x,result.run,model;t,d,result,refits,independent_refit_rng)
    (;kind=:criterion_collapse_heldout_criteria,_operation_context(result,t)...,
        _heldout_metadata(d)...,criterion=:loo,estimator=:zhang_stephens_psis,
        result=z.report,mcse_warning=z.report.mcse_warning,warning=_HELDOUT_WARNING)
end

function _heldout_comparison(result;unit=nothing,mixture_refits=(),ordinary_refits=(),independent_refit_rng::Bool=false)
    t=_restore(result);d=_heldout_design(t,unit);x=_heldout_values(t,result.run.draws,d)
    m=_heldout_evaluation(x,result.run,:mixture;t,d,result,refits=mixture_refits,independent_refit_rng)
    a=_heldout_evaluation(x,result.run,:all_ordinary;t,d,result,refits=ordinary_refits,independent_refit_rng)
    if (!isempty(mixture_refits) || !isempty(ordinary_refits)) && independent_refit_rng
        m_hashes=hasproperty(m.report,:reference_records) ? [r.source_sample_content_hash for r in m.report.reference_records] : String[]
        a_hashes=hasproperty(a.report,:reference_records) ? [r.source_sample_content_hash for r in a.report.reference_records] : String[]
        allunique([result.content_hash;m_hashes;a_hashes]) ||
            throw(ArgumentError("mixture and ordinary refits must use distinct sample streams"))
    end
    good=isempty(m.report.problem_profiles) && isempty(a.report.problem_profiles) &&
        ((isempty(mixture_refits) && isempty(ordinary_refits)) || independent_refit_rng)
    pointwise=NamedTuple[]
    for j in eachindex(d.profiles)
        mp=m.report.pointwise[j];ap=a.report.pointwise[j]
        diff_j=mp.log_score-ap.log_score
        m_ref=hasproperty(mp,:method) && mp.method===:direct_refit
        a_ref=hasproperty(ap,:method) && ap.method===:direct_refit
        ok_j=mp.importance_status===:ok && ap.importance_status===:ok
        if !m_ref && !a_ref
            pr_j=_heldout_precision(view(m.influences,:,j).-view(a.influences,:,j),result.run,ok_j)
            push!(pointwise,(;profile=j,difference=diff_j,pr_j...))
        else
            var_j=0.0;diag_j=mp.diagnostics;st_j=:available
            ok_j &= independent_refit_rng
            if !m_ref
                pm=_heldout_precision(view(m.influences,:,j),result.run,ok_j)
                ok_j &= pm.mcse_status===:available
                ok_j && (var_j+=Float64(pm.mcse)^2)
                diag_j=pm.diagnostics;st_j=pm.mcse_status
            elseif ok_j
                var_j+=Float64(mp.mcse)^2
            end
            if !a_ref
                pa=_heldout_precision(view(a.influences,:,j),result.run,ok_j)
                ok_j &= pa.mcse_status===:available
                ok_j && (var_j+=Float64(pa.mcse)^2)
                diag_j=pa.diagnostics;st_j=ok_j ? :available : pa.mcse_status
            elseif ok_j
                var_j+=Float64(ap.mcse)^2
            end
            !ok_j && (st_j=!independent_refit_rng ? :unassessed_refit_covariance :
                (mp.importance_status!==:ok || ap.importance_status!==:ok ? :unstable_importance_weights : :focal_diagnostics_failed))
            push!(pointwise,(;profile=j,difference=diff_j,mcse=ok_j ? sqrt(var_j) : missing,mcse_status=st_j,diagnostics=diag_j))
        end
    end
    # Covariance-preserving shared-draw influence trace for non-refit profiles + independent direct refit variances
    no_refits=isempty(mixture_refits) && isempty(ordinary_refits)
    if no_refits
        shared_prec=_heldout_precision(vec(sum(m.influences-a.influences;dims=2)),result.run,good)
    else
        u_shared=zeros(Float64,size(result.run.draws,1))
        for h in m.psis_idxs; u_shared .+= view(m.influences,:,h); end
        for h in a.psis_idxs; u_shared .-= view(a.influences,:,h); end
        shared_prec=isempty(m.psis_idxs) && isempty(a.psis_idxs) ? (;mcse=0.0,mcse_status=:available,diagnostics=pointwise[1].diagnostics) :
            _heldout_precision(u_shared,result.run,good)
    end
    tot_ok=good && shared_prec.mcse_status===:available
    tot_mcse=tot_ok ? (no_refits ? shared_prec.mcse : sqrt(Float64(shared_prec.mcse)^2+m.direct_var+a.direct_var)) : missing
    tot_status=(!no_refits && !independent_refit_rng) ? :unassessed_refit_covariance :
        (!good ? :unstable_importance_weights : shared_prec.mcse_status)
    difference=(;direction=:mixture_minus_all_ordinary,estimate=m.report.elpd-a.report.elpd,
        mean_difference=(m.report.elpd-a.report.elpd)/length(d.profiles),
        mcse=tot_mcse,mcse_status=tot_status,diagnostics=shared_prec.diagnostics,pointwise)
    (;kind=:criterion_collapse_heldout_comparison,_operation_context(result,t)...,
        _heldout_metadata(d)...,criterion=:loo,estimator=:zhang_stephens_psis,
        mixture=m.report,all_ordinary=a.report,difference,
        mcse_warning=m.report.mcse_warning || a.report.mcse_warning || tot_status!==:available ||
            any(p->p.mcse_status!==:available,pointwise),
        warning=_HELDOUT_WARNING)
end

function compare_heldout_criteria(models;criterion=:loo,independent_model_rng::Bool=false)
    criterion in (:loo,:psis_loo) || throw(ArgumentError("CriterionCollapse profile comparison requires criterion=:loo (or :psis_loo)"))
    length(models)==2 || throw(ArgumentError("supply exactly two labeled CriterionCollapse held-out criteria reports"))
    labels=[strip(string(first(p))) for p in models]
    all(!isempty,labels) && allunique(labels) || throw(ArgumentError("distinct nonempty model labels are required"))
    a,b=last(models[1]),last(models[2])
    string(get(a,:kind,""))=="criterion_collapse_heldout_criteria" &&
        string(get(b,:kind,""))=="criterion_collapse_heldout_criteria" ||
        throw(ArgumentError("both inputs must be CriterionCollapse held-out criteria reports"))
    _operation_report_check(a);_operation_report_check(b)
    a.observation_binding==b.observation_binding && a.n_profiles==b.n_profiles ||
        throw(ArgumentError("CriterionCollapse criteria reports do not bind the same observations/profiles"))
    hashes_a=[String(a.source_sample_content_hash);(hasproperty(a.result,:reference_records) ? [String(r.source_sample_content_hash) for r in a.result.reference_records] : String[])]
    hashes_b=[String(b.source_sample_content_hash);(hasproperty(b.result,:reference_records) ? [String(r.source_sample_content_hash) for r in b.result.reference_records] : String[])]
    independent_model_rng && !isempty(intersect(hashes_a,hashes_b)) &&
        throw(ArgumentError("shared sample records cannot be declared independent_model_rng=true"))
    ma=a.result;mb=b.result
    good=independent_model_rng && isempty(ma.problem_profiles) && isempty(mb.problem_profiles) &&
        string(ma.mcse_status)=="available" && string(mb.mcse_status)=="available" &&
        !a.sampling_warning && !b.sampling_warning
    pointwise=NamedTuple[]
    for j in 1:a.n_profiles
        pa=ma.pointwise[j];pb=mb.pointwise[j]
        ok_j=independent_model_rng && string(pa.importance_status)=="ok" && string(pb.importance_status)=="ok" &&
            string(pa.mcse_status)=="available" && string(pb.mcse_status)=="available"
        st_j=ok_j ? :available : (!independent_model_rng ? :unassessed_model_covariance : :unstable_importance_weights)
        push!(pointwise,(;profile=j,primary=pa.log_score,baseline=pb.log_score,difference=pa.log_score-pb.log_score,
            mcse=ok_j ? hypot(Float64(pa.mcse),Float64(pb.mcse)) : missing,
            mcse_status=st_j,diagnostics=pa.diagnostics))
    end
    tot_mcse=good ? hypot(Float64(ma.mcse),Float64(mb.mcse)) : missing
    tot_status=good ? :available : (!independent_model_rng ? :unassessed_model_covariance : :unstable_importance_weights)
    difference=(;direction=:primary_minus_baseline,primary_name=labels[1],baseline_name=labels[2],
        estimate=ma.elpd-mb.elpd,mean_difference=(ma.elpd-mb.elpd)/a.n_profiles,
        mcse=tot_mcse,mcse_status=tot_status,diagnostics=ma.diagnostics,pointwise)
    (;kind=:criterion_collapse_heldout_pair_comparison,
        scope=a.scope,target_identity=a.target_identity,baseline_target_identity=b.target_identity,
        source_sample_content_hash=a.source_sample_content_hash,baseline_source_sample_content_hash=b.source_sample_content_hash,
        prior=a.prior,baseline_prior=b.prior,diagnostics=a.diagnostics,qualification=a.qualification,
        baseline_qualification=b.qualification,sampling_warning=a.sampling_warning || b.sampling_warning,
        total_draws=a.total_draws,chains=a.chains,chain_ids=a.chain_ids,iterations=a.iterations,
        precision_threshold_applied=false,automatic_classification=false,
        unit=a.unit,likelihood_kind=a.likelihood_kind,factorizes_joint=false,conditioning=a.conditioning,
        profiles=a.profiles,observations=a.observations,categories=a.categories,
        observation_binding=a.observation_binding,n_profiles=a.n_profiles,n_observations=a.n_observations,
        sampling_standard_error=missing,sampling_uncertainty=a.sampling_uncertainty,
        waic=a.waic,mcse_method=a.mcse_method,smoothing_fit_uncertainty=a.smoothing_fit_uncertainty,
        criterion=:loo,estimator=a.estimator,names=labels,primary=ma,baseline=mb,difference,
        independent_model_rng,
        mcse_warning=ma.mcse_warning || mb.mcse_warning || tot_status!==:available || any(p->p.mcse_status!==:available,pointwise),
        warning=_HELDOUT_WARNING)
end

function _heldout_report_check(r)
    fail()=throw(ArgumentError("Incomplete or inconsistent criterion-collapse held-out report"))
    required=(:unit,:likelihood_kind,:factorizes_joint,:conditioning,:profiles,:observations,:categories,
        :observation_binding,:n_profiles,:n_observations,:sampling_standard_error,:sampling_uncertainty,
        :waic,:mcse_method,:smoothing_fit_uncertainty,:criterion,:estimator)
    all(k->hasproperty(r,k),required) || fail()
    string(r.unit)=="performance_rater" && string(r.likelihood_kind)=="conditional_holdout_ratio" &&
        r.factorizes_joint===false && string(r.conditioning)=="known_people_raters_original_finite_panel" &&
        string(r.criterion)=="loo" && string(r.estimator)=="zhang_stephens_psis" &&
        string(r.waic)=="unsupported_for_conditional_ratio_columns" &&
        string(r.mcse_method)=="chain_aware_smoothed_ratio_delta" &&
        string(r.sampling_uncertainty)=="not_assessed_crossed_overlapping_folds" &&
        string(r.smoothing_fit_uncertainty)=="not_separately_estimated" &&
        (r.sampling_standard_error===nothing || ismissing(r.sampling_standard_error)) &&
        _plot_hash(r.observation_binding) || fail()
    length(r.profiles)==r.n_profiles>0 && length(r.observations)==r.n_observations>0 || fail()
    sort(vcat([collect(p.rows) for p in r.profiles]...))==collect(1:r.n_observations) || fail()
    for (j,p) in enumerate(r.profiles)
        p.profile==j && p.n_ratings==length(p.rows)==length(p.criteria) && !isempty(p.rows) || fail()
        for (n,i) in zip(p.rows,p.criteria)
            o=r.observations[n]
            o.row==n && o.person==p.person && o.rater==p.rater && o.criterion==i && o.score in r.categories || fail()
        end
    end
    validmcse(x)=x===nothing || ismissing(x) || (_plot_finite(x) && x>=0)
    absent(x)=x===nothing || ismissing(x)
    function precisioncheck(p,eligible)
        all(k->hasproperty(p,k),(:mcse,:mcse_status,:diagnostics)) || fail()
        validmcse(p.mcse) || fail()
        status=string(p.mcse_status)
        (status=="available") == !absent(p.mcse) || fail()
        !eligible && (!(status in ("unstable_importance_weights","focal_diagnostics_failed","unassessed_refit_covariance","unassessed_model_covariance")) || !absent(p.mcse)) && fail()
    end
    function modelcheck(m,name)
        all(k->hasproperty(m,k),(:model,:pointwise,:elpd,:mcse,:mcse_status,:diagnostics,:problem_profiles,:status,:mcse_warning,:mean_log_score,:mean_mcse)) || fail()
        string(m.model)==name && length(m.pointwise)==r.n_profiles && validmcse(m.mcse) && validmcse(m.mean_mcse) || fail()
        for (j,p) in enumerate(m.pointwise)
            all(k->hasproperty(p,k),(:profile,:log_score,:mcse,:mcse_status,:diagnostics,:pareto_k,:pareto_k_threshold,:r_eff,:importance_ess,:smoothed_weight_ess,:tail_draws,:importance_status,:raw_is_log_score)) || fail()
            p.profile==j && _plot_finite(p.log_score) && p.log_score<=1e-10 && validmcse(p.mcse) || fail()
            is_direct=hasproperty(p,:method) && string(p.method)=="direct_refit"
            if string(p.importance_status)=="ok"
                is_direct || (_plot_finite(p.pareto_k) && p.pareto_k<p.pareto_k_threshold && _plot_finite(p.r_eff) && p.r_eff>0) || fail()
            elseif string(p.importance_status)=="diagnostic_only"
                (p.mcse===nothing || ismissing(p.mcse)) && string(p.mcse_status) in ("unstable_importance_weights","focal_diagnostics_failed","unassessed_refit_covariance") || fail()
            else;fail();end
            precisioncheck(p,string(p.importance_status)=="ok")
        end
        collect(m.problem_profiles)==[p.profile for p in m.pointwise if string(p.importance_status)!="ok"] || fail()
        isapprox(m.elpd,sum(p.log_score for p in m.pointwise);atol=1e-8,rtol=1e-10) &&
            isapprox(m.mean_log_score,m.elpd/r.n_profiles;atol=1e-10,rtol=1e-10) || fail()
        ref_ok=!hasproperty(m,:independent_refit_rng) || m.independent_refit_rng===true
        (!isempty(m.problem_profiles) || !ref_ok) && (!(m.mcse===nothing || ismissing(m.mcse)) || !m.mcse_warning || string(m.status)!="diagnostic_only") && fail()
        precisioncheck(m,isempty(m.problem_profiles) && ref_ok)
        absent(m.mcse) == absent(m.mean_mcse) || fail()
        !absent(m.mcse) && !isapprox(m.mean_mcse,m.mcse/r.n_profiles;atol=1e-12,rtol=1e-10) && fail()
        m.mcse_warning == (string(m.mcse_status)!="available" || any(p->string(p.mcse_status)!="available",m.pointwise)) || fail()
    end
    if string(r.kind)=="criterion_collapse_heldout_criteria"
        hasproperty(r,:result) || fail();modelcheck(r.result,string(r.result.model))
        string(r.result.model) in ("mixture","all_ordinary") || fail()
        r.mcse_warning==r.result.mcse_warning || fail()
    elseif string(r.kind)=="criterion_collapse_heldout_pair_comparison"
        all(k->hasproperty(r,k),(:names,:primary,:baseline,:difference,:independent_model_rng,:baseline_qualification)) || fail()
        length(r.names)==2 && r.independent_model_rng isa Bool || fail()
        (!r.baseline_qualification.qualified) && !r.sampling_warning && fail()
        modelcheck(r.primary,string(r.primary.model));modelcheck(r.baseline,string(r.baseline.model))
        d=r.difference
        all(k->hasproperty(d,k),(:direction,:estimate,:mean_difference,:mcse,:mcse_status,:diagnostics,:pointwise)) || fail()
        string(d.direction)=="primary_minus_baseline" && validmcse(d.mcse) &&
            length(d.pointwise)==r.n_profiles && isapprox(d.estimate,r.primary.elpd-r.baseline.elpd;atol=1e-8) &&
            isapprox(d.mean_difference,d.estimate/r.n_profiles;atol=1e-10) || fail()
        precisioncheck(d,r.independent_model_rng && isempty(r.primary.problem_profiles) && isempty(r.baseline.problem_profiles) &&
            string(r.primary.mcse_status)=="available" && string(r.baseline.mcse_status)=="available" && !r.sampling_warning)
        for (j,p) in enumerate(d.pointwise)
            p.profile==j && validmcse(p.mcse) && isapprox(p.difference,
                r.primary.pointwise[j].log_score-r.baseline.pointwise[j].log_score;atol=1e-10) || fail()
            precisioncheck(p,r.independent_model_rng && string(r.primary.pointwise[j].importance_status)=="ok" &&
                string(r.baseline.pointwise[j].importance_status)=="ok" &&
                string(r.primary.pointwise[j].mcse_status)=="available" && string(r.baseline.pointwise[j].mcse_status)=="available")
        end
        r.mcse_warning == (r.primary.mcse_warning || r.baseline.mcse_warning ||
            string(d.mcse_status)!="available" || any(p->string(p.mcse_status)!="available",d.pointwise)) || fail()
    else
        all(k->hasproperty(r,k),(:mixture,:all_ordinary,:difference)) || fail()
        modelcheck(r.mixture,"mixture");modelcheck(r.all_ordinary,"all_ordinary")
        d=r.difference
        all(k->hasproperty(d,k),(:direction,:estimate,:mean_difference,:mcse,:mcse_status,:diagnostics,:pointwise)) || fail()
        string(d.direction)=="mixture_minus_all_ordinary" && validmcse(d.mcse) &&
            length(d.pointwise)==r.n_profiles && isapprox(d.estimate,r.mixture.elpd-r.all_ordinary.elpd;atol=1e-8) &&
            isapprox(d.mean_difference,d.estimate/r.n_profiles;atol=1e-10) || fail()
        ref_ok=(!hasproperty(r.mixture,:independent_refit_rng) || r.mixture.independent_refit_rng===true) &&
            (!hasproperty(r.all_ordinary,:independent_refit_rng) || r.all_ordinary.independent_refit_rng===true)
        precisioncheck(d,isempty(r.mixture.problem_profiles) && isempty(r.all_ordinary.problem_profiles) && ref_ok)
        for (j,p) in enumerate(d.pointwise)
            p.profile==j && validmcse(p.mcse) && isapprox(p.difference,
                r.mixture.pointwise[j].log_score-r.all_ordinary.pointwise[j].log_score;atol=1e-10) || fail()
            precisioncheck(p,string(r.mixture.pointwise[j].importance_status)=="ok" && string(r.all_ordinary.pointwise[j].importance_status)=="ok" && ref_ok)
        end
        r.mcse_warning == (r.mixture.mcse_warning || r.all_ordinary.mcse_warning ||
            string(d.mcse_status)!="available" || any(p->string(p.mcse_status)!="available",d.pointwise)) || fail()
    end
    r
end
