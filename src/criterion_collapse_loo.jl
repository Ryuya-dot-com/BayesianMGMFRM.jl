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

function _heldout_evaluation(x,run,model)
    a=_heldout_model_arrays(x,model);S,M=size(a.log_density)
    rows=NamedTuple[];influences=zeros(S,M)
    for h in 1:M
        z=_profile_score(view(a.log_density,:,h),view(a.log_ratios,:,h),run)
        push!(rows,(;profile=h,z.row...));influences[:,h]=z.influence
    end
    good=all(r->r.importance_status===:ok,rows)
    total=_heldout_precision(vec(sum(influences;dims=2)),run,good)
    report=(;model,pointwise=rows,elpd=sum(r.log_score for r in rows),total...,
        mean_log_score=mean(r.log_score for r in rows),mean_mcse=ismissing(total.mcse) ? missing : total.mcse/M,
        problem_profiles=[r.profile for r in rows if r.importance_status!==:ok],
        status=good ? :estimated : :diagnostic_only,
        mcse_warning=total.mcse_status!==:available || any(r->r.mcse_status!==:available,rows))
    (;report,influences)
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
function criteria(result;unit=nothing,model=:mixture)
    model in (:mixture,:all_ordinary) || throw(ArgumentError("model must be :mixture or :all_ordinary"))
    t=_restore(result);d=_heldout_design(t,unit);x=_heldout_values(t,result.run.draws,d)
    z=_heldout_evaluation(x,result.run,model)
    (;kind=:criterion_collapse_heldout_criteria,_operation_context(result,t)...,
        _heldout_metadata(d)...,criterion=:loo,estimator=:zhang_stephens_psis,
        result=z.report,mcse_warning=z.report.mcse_warning,warning=_HELDOUT_WARNING)
end

function _heldout_comparison(result;unit=nothing)
    t=_restore(result);d=_heldout_design(t,unit);x=_heldout_values(t,result.run.draws,d)
    m=_heldout_evaluation(x,result.run,:mixture);a=_heldout_evaluation(x,result.run,:all_ordinary)
    good=isempty(m.report.problem_profiles) && isempty(a.report.problem_profiles)
    delta=m.influences.-a.influences
    pointwise=[(;profile=j,difference=m.report.pointwise[j].log_score-a.report.pointwise[j].log_score,
        _heldout_precision(view(delta,:,j),result.run,
            m.report.pointwise[j].importance_status===:ok && a.report.pointwise[j].importance_status===:ok)...)
        for j in eachindex(d.profiles)]
    precision=_heldout_precision(vec(sum(delta;dims=2)),result.run,good)
    difference=(;direction=:mixture_minus_all_ordinary,estimate=m.report.elpd-a.report.elpd,
        mean_difference=(m.report.elpd-a.report.elpd)/length(d.profiles),precision...,pointwise)
    (;kind=:criterion_collapse_heldout_comparison,_operation_context(result,t)...,
        _heldout_metadata(d)...,criterion=:loo,estimator=:zhang_stephens_psis,
        mixture=m.report,all_ordinary=a.report,difference,
        mcse_warning=m.report.mcse_warning || a.report.mcse_warning || precision.mcse_status!==:available ||
            any(p->p.mcse_status!==:available,pointwise),
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
        !eligible && (status!="unstable_importance_weights" || !absent(p.mcse)) && fail()
    end
    function modelcheck(m,name)
        all(k->hasproperty(m,k),(:model,:pointwise,:elpd,:mcse,:mcse_status,:diagnostics,:problem_profiles,:status,:mcse_warning,:mean_log_score,:mean_mcse)) || fail()
        string(m.model)==name && length(m.pointwise)==r.n_profiles && validmcse(m.mcse) && validmcse(m.mean_mcse) || fail()
        for (j,p) in enumerate(m.pointwise)
            all(k->hasproperty(p,k),(:profile,:log_score,:mcse,:mcse_status,:diagnostics,:pareto_k,:pareto_k_threshold,:r_eff,:importance_ess,:smoothed_weight_ess,:tail_draws,:importance_status,:raw_is_log_score)) || fail()
            p.profile==j && _plot_finite(p.log_score) && p.log_score<=1e-10 && validmcse(p.mcse) || fail()
            if string(p.importance_status)=="ok"
                _plot_finite(p.pareto_k) && p.pareto_k<p.pareto_k_threshold && _plot_finite(p.r_eff) && p.r_eff>0 || fail()
            elseif string(p.importance_status)=="diagnostic_only"
                (p.mcse===nothing || ismissing(p.mcse)) && string(p.mcse_status)=="unstable_importance_weights" || fail()
            else;fail();end
            precisioncheck(p,string(p.importance_status)=="ok")
        end
        collect(m.problem_profiles)==[p.profile for p in m.pointwise if string(p.importance_status)!="ok"] || fail()
        isapprox(m.elpd,sum(p.log_score for p in m.pointwise);atol=1e-8,rtol=1e-10) &&
            isapprox(m.mean_log_score,m.elpd/r.n_profiles;atol=1e-10,rtol=1e-10) || fail()
        !isempty(m.problem_profiles) && (!(m.mcse===nothing || ismissing(m.mcse)) || !m.mcse_warning || string(m.status)!="diagnostic_only") && fail()
        precisioncheck(m,isempty(m.problem_profiles))
        absent(m.mcse) == absent(m.mean_mcse) || fail()
        !absent(m.mcse) && !isapprox(m.mean_mcse,m.mcse/r.n_profiles;atol=1e-12,rtol=1e-10) && fail()
        m.mcse_warning == (string(m.mcse_status)!="available" || any(p->string(p.mcse_status)!="available",m.pointwise)) || fail()
    end
    if string(r.kind)=="criterion_collapse_heldout_criteria"
        hasproperty(r,:result) || fail();modelcheck(r.result,string(r.result.model))
        string(r.result.model) in ("mixture","all_ordinary") || fail()
        r.mcse_warning==r.result.mcse_warning || fail()
    else
        all(k->hasproperty(r,k),(:mixture,:all_ordinary,:difference)) || fail()
        modelcheck(r.mixture,"mixture");modelcheck(r.all_ordinary,"all_ordinary")
        d=r.difference
        all(k->hasproperty(d,k),(:direction,:estimate,:mean_difference,:mcse,:mcse_status,:diagnostics,:pointwise)) || fail()
        string(d.direction)=="mixture_minus_all_ordinary" && validmcse(d.mcse) &&
            length(d.pointwise)==r.n_profiles && isapprox(d.estimate,r.mixture.elpd-r.all_ordinary.elpd;atol=1e-8) &&
            isapprox(d.mean_difference,d.estimate/r.n_profiles;atol=1e-10) || fail()
        precisioncheck(d,isempty(r.mixture.problem_profiles) && isempty(r.all_ordinary.problem_profiles))
        for (j,p) in enumerate(d.pointwise)
            p.profile==j && validmcse(p.mcse) && isapprox(p.difference,
                r.mixture.pointwise[j].log_score-r.all_ordinary.pointwise[j].log_score;atol=1e-10) || fail()
            precisioncheck(p,string(r.mixture.pointwise[j].importance_status)=="ok" && string(r.all_ordinary.pointwise[j].importance_status)=="ok")
        end
        r.mcse_warning == (r.mixture.mcse_warning || r.all_ordinary.mcse_warning ||
            string(d.mcse_status)!="available" || any(p->string(p.mcse_status)!="available",d.pointwise)) || fail()
    end
    r
end
