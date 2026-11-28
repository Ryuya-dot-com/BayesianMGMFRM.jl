# Included at package scope after AdditiveFacets. Sampler coordinates are never powered.
function _explanatory_power_definitions(t::AdditiveFacets.ExplanatoryTarget)
    A=AdditiveFacets;out=NamedTuple[]
    common=(;normalization=:included,jacobian_powered=false)
    for b in t.residuals
        hierarchical=b.hyper>0
        sel=!hierarchical && !isempty(b.raw)
        rl=hierarchical ? :conditional_residual : (isempty(b.raw) ? :fixed_zero_residual : :fixed_scale_prior)
        push!(out,merge(common,(;id="residual[$(b.name)]",family=:normal,owner=b.name,
            owner_ids=deepcopy(A._owner_levels(t,b.name)),raw=collect(b.raw),
            free_dimension=length(b.raw),sd=b.sd,hyper=b.hyper,
            logmean=b.logmean,logsd=b.logsd,scale_kind=b.scale_kind,
            measure=b.kind===:iid_population ? :residual_lebesgue : :finite_orthonormal_volume,
            selectable=sel,role=rl)))
        hierarchical || continue
        push!(out,merge(common,(;id="residual_sd[$(b.name)]",family=b.scale_kind,owner=b.name,
            raw=[b.hyper],free_dimension=1,logmean=b.logmean,logsd=b.logsd,
            measure=:positive_sd_lebesgue,selectable=true,role=:hyperprior)))
    end
    for p in t.terms
        push!(out,merge(common,(;id=A._term_name(p),family=:normal,owner=p.owner,
            column=p.column,by=p.by,level=deepcopy(p.level),raw=[p.raw],
            free_dimension=1,mean=p.mean,sd=p.sd,hyper=0,
            measure=:coefficient_lebesgue,selectable=true,role=:coefficient_prior)))
    end
    for (g,r) in enumerate(t.steps)
        push!(out,merge(common,(;id="steps[$(repr(t.group_levels[g]))]",family=:normal,
            owner=t.owner,level=deepcopy(t.group_levels[g]),raw=collect(r),free_dimension=length(r),
            sd=A._step_scale(t,g),hyper=0,measure=:finite_orthonormal_volume,
            selectable=true,role=:step_prior)))
    end
    allunique(f.id for f in out) || throw(ArgumentError("ambiguous scientific factor IDs"))
    out
end

function _explanatory_factor_value(f,q)
    f.free_dimension==0 && return 0.0
    if f.family===:lkj2
        return (f.eta-1)*AdditiveFacets._logsech2(q[only(f.raw)])-AdditiveFacets.SF.logbeta(.5,f.eta)
    end
    if f.family===:lkj_corr
        ldet=sum(AdditiveFacets._logsech2(q[idx]) for idx in f.raw)
        lnorm=sum((f.D_dim-j)*AdditiveFacets.SF.logbeta(.5,f.eta+(f.D_dim-1-j)/2) for j in 1:(f.D_dim-1))
        return (f.eta-1)*ldet-lnorm
    end
    z=view(q,f.raw);normal=-sum(abs2,z)/2-length(z)*log(2pi)/2
    if f.family===:conditional_slope_normal
        ls=f.hyper==0 ? log(f.sd) : f.logmean+f.logsd*q[f.hyper]
        lc=isempty(f.corr_row_raw) ? 0. : sum(AdditiveFacets._logsech2(q[idx]) for idx in f.corr_row_raw)/2
        return normal-length(z)*(ls+lc)
    end
    if f.family===:lognormal
        return normal-log(f.logsd)-(f.logmean+f.logsd*only(z))
    end
    if f.family in (:half_normal,:half_student_t)
        D=AdditiveFacets.D
        prior=f.family===:half_normal ? D.Normal(0,f.logsd) : D.LocationScale(0,f.logsd,D.TDist(f.logmean))
        return log(2)+D.logpdf(prior,exp(only(z)))
    end
    logscale=f.hyper==0 ? log(f.sd) : get(f,:scale_kind,:lognormal)===:lognormal ? f.logmean+f.logsd*q[f.hyper] : q[f.hyper]
    normal-length(z)*logscale
end

"""
    logprior(fit::AdditiveFacets.Fit; components=:factors)

Inspect explanatory-model priors in coefficient, positive-SD and orthonormal
finite-block measures. Conditional residuals with estimated SD are inspectable
but not selectable for powers; select their hyperprior instead. The factor sum
plus the unpowered Jacobian equals the white-coordinate prior. No new sampling.
"""
function logprior(f::AdditiveFacets.Fit;components=:factors)
    components===:factors || throw(ArgumentError("use components=:factors"))
    t=AdditiveFacets.checked(f;full=true)
    t isa Union{AdditiveFacets.ExplanatoryTarget,AdditiveFacets.BoundedTarget,AdditiveFacets.CountTarget,AdditiveFacets.MixedOutcomeTarget} || throw(ArgumentError("scientific factors require an explanatory fit"))
    defs=_explanatory_power_definitions(t);run=f.record.run
    factors=[merge(d,(;log_density=[_explanatory_factor_value(d,q) for q in eachrow(run.draws)])) for d in defs]
    all(d->all(isfinite,d.log_density),factors) || throw(ArgumentError("nonfinite scientific prior factor"))
    (;schema="bayesianmgmfrm.explanatory_prior_factors.v1",factors,
      target_identity=f.record.target_identity,source_sample_hash=f.record.content_hash,
      chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),
      joint_measure=t isa AdditiveFacets.MixedOutcomeTarget ? :mixed_outcome_owner_factors_loadings_coefficients_and_family_parameters : t isa AdditiveFacets.CountTarget ? (isempty(AdditiveFacets.slope_blocks(t)) ? (AdditiveFacets.is_beta_binomial(t) ? :residuals_coefficients_sd_precision : :residuals_coefficients_sd) : (AdditiveFacets.is_beta_binomial(t) ? :residuals_coefficients_sd_precision_and_correlation : :residuals_coefficients_sd_and_correlation)) : t isa AdditiveFacets.BoundedTarget ? (isempty(AdditiveFacets.slope_blocks(t)) ? :residuals_coefficients_sd_precision_and_endpoint_logits : :residuals_coefficients_sd_precision_endpoint_logits_and_correlation) : :residuals_coefficients_positive_sd_and_finite_orthonormal_volume,
      hierarchical_conditionals_powered=false,jacobian_powered=false)
end

function _explanatory_power_estimands(t,run,estimands)
    specs=collect(estimands)
    all(p->p isa Pair,specs) || throw(ArgumentError("estimands must contain label => definition pairs"))
    _recovery_replication_names(first.(specs),"estimand labels")
    m=AdditiveFacets.model_draws(t,run.draws);lookup=Dict(n=>j for (j,n) in enumerate(m.names))
    map(specs) do entry
        label,source=entry
        if t isa AdditiveFacets.MixedOutcomeTarget && source isa NamedTuple && hasproperty(source,:outcome)
            res=_mixed_power_estimand(t,run,label,source)
            res!==nothing && return res
            throw(ArgumentError("invalid mixed-outcome prediction estimand; use (row,outcome,metric) or (row,outcome,category)"))
        end
        if t isa AdditiveFacets.CountTarget && source isa NamedTuple && Set(keys(source))==Set((:row,:metric))
            n=source.row;k=source.metric
            n isa Integer && !(n isa Bool) && 1<=n<=length(t.y) && k in AdditiveFacets.COUNT_METRICS || throw(ArgumentError("invalid count prediction estimand"))
            sub=AdditiveFacets.count_prediction_target(t,Dict(c=>v[[n]] for (c,v) in t.table if c!=t.columns.score))
            values=[only(getproperty(predict(sub,q),k)) for q in eachrow(run.draws)]
            return (;label=String(label),definition=source,unit=k===:expected_count ? "success count" : "probability",parameter_space=:count_prediction,operation=:known_row_moment,fixed=false,values)
        end
        if t isa AdditiveFacets.BoundedTarget && source isa NamedTuple && Set(keys(source))==Set((:row,:metric))
            n=source.row;k=source.metric
            n isa Integer && !(n isa Bool) && 1<=n<=length(t.y) && k in AdditiveFacets.BOUNDED_METRICS || throw(ArgumentError("invalid bounded prediction estimand"))
            sub=AdditiveFacets.bounded_prediction_target(t,Dict(c=>v[[n]] for (c,v) in t.table if c!=t.columns.score))
            values=[only(getproperty(predict(sub,q;metrics=(k,)),k)) for q in eachrow(run.draws)]
            return (;label=String(label),definition=source,unit=replace(string(AdditiveFacets.bounded_metric_unit(k)),"_"=>" "),parameter_space=:bounded_prediction,operation=:known_row_moment,fixed=false,values)
        end
        if source isa NamedTuple && Set(keys(source))==Set((:row,:category))
            t isa AdditiveFacets.ExplanatoryTarget || throw(ArgumentError("bounded/count prediction estimands require (row,metric), not (row,category)"))
            n=source.row;k=findfirst(==(source.category),t.categories)
            n isa Integer && !(n isa Bool) && 1<=n<=length(t.person) && k!==nothing ||
                throw(ArgumentError("prediction estimand requires a known row and declared category"))
            sub=AdditiveFacets.prediction_target(t,Dict(c=>v[[n]] for (c,v) in t.table if c!=t.columns.score))
            values=[predictive_probabilities(sub,q)[1,k] for q in eachrow(run.draws)]
            return (;label=String(label),definition=source,unit="category probability",
                parameter_space=:probability,operation=:known_row_probability,
                fixed=!(k in t.supports[t.group[n]]),values)
        end
        if source isa AbstractString
            terms=[String(source)];weights=[1.];unit="model coordinate; coefficients per supplied predictor unit"
        elseif source isa NamedTuple && Set(keys(source))==Set((:terms,:weights,:unit))
            source.terms isa AbstractVector && source.weights isa AbstractVector ||
                throw(ArgumentError("linear estimands require terms and weights vectors"))
            terms=collect(source.terms);weights=collect(source.weights);unit=source.unit
            unit isa AbstractString && !isempty(strip(unit)) || throw(ArgumentError("declare the linear estimand unit"))
        else
            throw(ArgumentError("use a parameter name, (terms,weights,unit), or (row,category)"))
        end
        !isempty(terms) && allunique(terms) && length(terms)==length(weights) &&
            all(n->n isa AbstractString && haskey(lookup,n),terms) &&
            all(x->x isa Real && !(x isa Bool) && isfinite(x),weights) && any(!iszero,weights) ||
            throw(ArgumentError("invalid linear estimand terms or weights"))
        values=m.values[:,[lookup[n] for n in terms]]*Float64.(weights)
        all(isfinite,values) || throw(ArgumentError("nonfinite focal values"))
        (;label=String(label),definition=(;terms,weights=Float64.(weights),unit=String(unit)),unit=String(unit),
          parameter_space=:declared_model_units,operation=:linear_combination,
          fixed=all(i->iszero(weights[i]) || terms[i] in m.fixed,eachindex(terms)),values)
    end
end

# Match loo's inverse-ratio efficiency definition; never substitute iid draws.
function _explanatory_power_weights(lp,alpha,chains,max_k,constant)
    lr=(alpha-1).*lp;reff=nothing
    all(isfinite,lr) || throw(ArgumentError("nonfinite power ratios"))
    if alpha!=1 && !constant && !allequal(lr) && length(lp)÷chains>=8
        inverse=exp.(-lr.-maximum(-lr))
        reff=MCMCDiagnosticTools.ess(reshape(inverse,:,chains);kind=:basic,split_chains=2)/length(lp)
    end
    w=_power_weights(lp,alpha,chains,max_k;r_eff=reff===nothing ? NaN : reff,analytic_constant=constant)
    merge(w,(;r_eff_method=w.identity ? :not_needed : :basic_ess_of_inverse_ratios,
        weight_ess_autocorrelation_adjusted=w.r_eff===nothing ? nothing : w.weight_ess*w.r_eff))
end

"""
    prior_sensitivity(fit::AdditiveFacets.Fit; powers, estimands,
        max_pareto_k=.7, max_mean_mcse=nothing)

Reweight saved explanatory draws with declared scientific prior factors from
`logprior(fit)`. Each case is `id => (factors=[factor_id], alpha=.9)`.
An estimand is `label => parameter_name`, `label => (terms=[names...],
weights=[...], unit="...")`, or `label => (row=1, category=3)` for a known ordinal row. Bounded/count
predictions use `label => (row=1, metric=:expected_score)` or
`metric=:expected_proportion`, respectively.
Linear-combination units are the caller's declaration; no causal or new-owner
interpretation is implied. All calculations use original joint draw order.

Only top-level and fixed-scale factors are selectable. Powering a positive-SD
LogNormal(mu,s) is proportional to LogNormal(mu+(1-alpha)*s^2/alpha,s/sqrt(alpha));
it is not just a change to log-SD spread. Conditional residuals and Jacobians
stay unchanged. This method perturbs priors only, with no automatic refitting.

Reports retain Pareto-k, inverse-ratio chain ESS, weight ESS, baseline warnings,
means and plug-in mean/paired-shift MCSE. Quantile/decision precision and PSIS
tail-fit uncertainty are not assessed. Failed weights cannot establish robustness.
Use `plot(report; kind=:prior_sensitivity)` and the common save/load verbs.
"""
function prior_sensitivity(f::AdditiveFacets.Fit;powers=nothing,estimands=nothing,max_pareto_k=.7,max_mean_mcse=nothing)
    powers !== nothing && estimands !== nothing ||
        throw(ArgumentError("prior_sensitivity on AdditiveFacets.Fit requires explicit `powers` and `estimands` keyword arguments"))
    max_pareto_k isa Real && !(max_pareto_k isa Bool) && isfinite(max_pareto_k) &&
        0<max_pareto_k<=.7 || throw(ArgumentError("max_pareto_k must be in (0,.7]"))
    max_mean_mcse===nothing || (max_mean_mcse isa Real && !(max_mean_mcse isa Bool) &&
        isfinite(max_mean_mcse) && max_mean_mcse>0) || throw(ArgumentError("invalid max_mean_mcse"))
    t=AdditiveFacets.checked(f;full=true)
    t isa Union{AdditiveFacets.ExplanatoryTarget,AdditiveFacets.BoundedTarget,AdditiveFacets.CountTarget,AdditiveFacets.MixedOutcomeTarget} || throw(ArgumentError("prior powers require an explanatory fit"))
    run=f.record.run;S=size(run.draws,1);S>=5 || throw(ArgumentError("at least five draws required"))
    factors=logprior(f);lookup=Dict(d.id=>d for d in factors.factors)
    es=_explanatory_power_estimands(t,run,estimands);specs=collect(powers)
    all(p->p isa Pair,specs) || throw(ArgumentError("powers must contain named pairs"))
    _recovery_replication_names(first.(specs),"power IDs")
    quality=qualify(f);warning=!quality.qualified
    cases=map(specs) do entry
        id,choice=entry
        choice isa NamedTuple && Set(keys(choice))==Set((:factors,:alpha)) && choice.factors isa AbstractVector ||
            throw(ArgumentError("each power needs factors and alpha"))
        selected=_recovery_replication_names(choice.factors,"factor IDs")
        all(k->haskey(lookup,k),selected) || throw(ArgumentError("unknown scientific factor"))
        all(k->lookup[k].selectable,selected) || throw(ArgumentError("power the residual-SD hyperprior, not its conditional residuals"))
        alpha=choice.alpha
        alpha isa Real && !(alpha isa Bool) && isfinite(alpha) && alpha>0 || throw(ArgumentError("alpha must be positive and finite"))
        alpha=Float64(alpha);isfinite(alpha) && alpha>0 || throw(ArgumentError("alpha is not representable"))
        lp=sum(lookup[k].log_density for k in selected)
        weights=_explanatory_power_weights(lp,alpha,run.controls.chains,max_pareto_k,
            all(k->lookup[k].free_dimension==0,selected))
        rows=[_power_focal(e,weights,run.controls.chains,max_mean_mcse,warning) for e in es]
        (;id=String(id),factors=selected,alpha,reweighting=weights,rows,sampling_warning=warning,
          selected_source=weights.reliable ? :reweighting : :unavailable,refit_performed=false)
    end
    _prediction_seal((;schema=_PRIOR_POWER_SCHEMA,scope=t isa AdditiveFacets.MixedOutcomeTarget ? :mixed_outcome_joint_explanatory : t isa AdditiveFacets.CountTarget ? :scalar_explanatory_count : t isa AdditiveFacets.BoundedTarget ? :scalar_explanatory_zoib : :scalar_explanatory,
        baseline=(;target_identity=f.record.target_identity,source_sample_hash=f.record.content_hash,
            sampling_quality=quality,sampling_warning=warning,prior=deepcopy(t.specification)),
        factor_record=factors,cases,max_mean_mcse,max_pareto_k,
        warnings=AdditiveFacets.design(t).warnings,
        conditioning=AdditiveFacets.prediction_conditioning(t),multiplier=1,
        precision_method=:chain_aware_plugin_delta_ignores_tail_fit_uncertainty,
        quantile_precision=:not_computed,decision_precision=:not_computed,
        scientific_acceptance=:not_established,new_fits=0,new_random_draws=0))
end

function _population_power_definitions(t)
    A=AdditiveFacets;out=NamedTuple[];common=(;normalization=:included,jacobian_powered=false)
    for b in t.residuals
        push!(out,merge(common,(;id="residual[$(b.name)]",family=:normal,owner=b.name,owner_ids=A._owner_levels(t,b.name),raw=collect(b.raw),free_dimension=length(b.raw),sd=b.sd,hyper=b.hyper,logmean=b.logmean,logsd=b.logsd,measure=:residual_lebesgue,selectable=b.hyper==0,role=b.hyper==0 ? :fixed_scale_prior : :conditional_residual)))
        b.hyper==0 || push!(out,merge(common,(;id="residual_sd[$(b.name)]",family=:lognormal,owner=b.name,raw=[b.hyper],free_dimension=1,logmean=b.logmean,logsd=b.logsd,measure=:positive_sd_lebesgue,selectable=true,role=:hyperprior)))
    end
    for p in t.terms
        push!(out,merge(common,(;id=A._term_name(p),family=:normal,owner=p.owner,raw=[p.raw],free_dimension=1,mean=p.mean,sd=p.sd,hyper=0,measure=:coefficient_lebesgue,selectable=true,role=:coefficient_prior)))
    end
    out
end
function _explanatory_power_definitions(t::AdditiveFacets.BoundedTarget)
    out=_population_power_definitions(t);append!(out,_slope_power_definitions(t));common=(;normalization=:included,jacobian_powered=false)
    p=t.observation_prior
    off=t.location.dimension
    push!(out,merge(common,(;id="precision",family=:lognormal,owner=:observation,raw=[off+1],free_dimension=1,logmean=p.precision.logmean,logsd=p.precision.logsd,measure=:positive_precision_lebesgue,selectable=true,role=:observation_prior)))
    for (name,idx,pr) in (("endpoint_logit",off+2,p.endpoint_logit),("upper_logit",off+3,p.upper_logit))
        push!(out,merge(common,(;id=name,family=:normal,owner=:observation,raw=[idx],free_dimension=1,mean=pr.mean,sd=pr.sd,hyper=0,measure=:logit_lebesgue,selectable=true,role=:observation_prior)))
    end
    for b in AdditiveFacets.distribution_blocks(t)
        for c in b.terms
            push!(out,merge(common,(;id=AdditiveFacets.distribution_term_name(b,c),family=:normal,owner=c.owner,parameter=b.parameter,column=c.column,by=c.by,level=c.level,raw=[c.raw],free_dimension=1,mean=c.mean,sd=c.sd,hyper=0,measure=:link_coefficient_lebesgue,selectable=true,role=:coefficient_prior)))
        end
        for r in b.residuals
            push!(out,merge(common,(;id="residual[$(b.parameter),$(r.name)]",family=:normal,owner=r.name,raw=collect(r.raw),free_dimension=length(r.raw),sd=r.sd,hyper=r.hyper,logmean=r.logmean,logsd=r.logsd,measure=:link_residual_lebesgue,selectable=r.hyper==0,role=r.hyper==0 ? :fixed_scale_prior : :conditional_residual)))
            r.hyper==0 || push!(out,merge(common,(;id=AdditiveFacets.distribution_sd_name(b,r),family=:lognormal,owner=r.name,raw=[r.hyper],free_dimension=1,logmean=r.logmean,logsd=r.logsd,measure=:positive_sd_lebesgue,selectable=true,role=:hyperprior)))
        end
    end
    out
end

function _explanatory_power_definitions(t::AdditiveFacets.CountTarget)
    out=_population_power_definitions(t);append!(out,_slope_power_definitions(t))
    if AdditiveFacets.is_beta_binomial(t)
        p=t.observation_prior.precision
        push!(out,(;normalization=:included,jacobian_powered=false,id="precision",family=:lognormal,owner=:observation,raw=[t.dimension],free_dimension=1,logmean=p.logmean,logsd=p.logsd,measure=:positive_precision_lebesgue,selectable=true,role=:observation_prior))
    end
    out
end

function _slope_power_definitions(t)
    A=AdditiveFacets;out=NamedTuple[];common=(;normalization=:included,jacobian_powered=false)
    for b in A.slope_blocks(t)
        if !A._sb_is_multi(b)
            p=b.scale;cr=b.corr_raw==0 ? (1:0) : (b.corr_raw:b.corr_raw)
            push!(out,merge(common,(;id="residual_slope[$(b.owner),$(b.column)]",family=:conditional_slope_normal,
                owner=b.owner,raw=collect(b.raw),free_dimension=length(b.raw),hyper=b.hyper,corr_raw=b.corr_raw,corr_row_raw=cr,
                sd=b.hyper==0 ? p.sd : 1.,logmean=b.hyper==0 ? 0. : p.logmean,logsd=b.hyper==0 ? 1. : p.logsd,
                measure=:slope_residual_lebesgue,selectable=false,role=:conditional_residual)))
            b.hyper==0 || push!(out,merge(common,(;id="slope_sd[$(b.owner),$(b.column)]",family=:lognormal,
                owner=b.owner,raw=[b.hyper],free_dimension=1,logmean=p.logmean,logsd=p.logsd,
                measure=:positive_sd_lebesgue,selectable=true,role=:hyperprior)))
            b.corr_raw==0 || push!(out,merge(common,(;id="correlation[$(b.owner),$(b.column)]",family=:lkj2,
                owner=b.owner,raw=[b.corr_raw],free_dimension=1,eta=b.correlation.eta,
                measure=:correlation_lebesgue,selectable=true,role=:hyperprior)))
        else
            cols=b.columns;raws=b.raws;hyps=b.hyps;scales=b.scales;cr=b.corr_raw;D_dim=length(cols)+1
            for (k,col) in enumerate(cols)
                p=scales[k];i=k+1
                row_cr=isempty(cr) ? (1:0) : cr[(((i-2)*(i-1))÷2+1):(((i-1)*i)÷2)]
                push!(out,merge(common,(;id="residual_slope[$(b.owner),$col]",family=:conditional_slope_normal,
                    owner=b.owner,raw=collect(raws[k]),free_dimension=length(raws[k]),hyper=hyps[k],corr_row_raw=row_cr,
                    sd=hyps[k]==0 ? p.sd : 1.,logmean=hyps[k]==0 ? 0. : p.logmean,logsd=hyps[k]==0 ? 1. : p.logsd,
                    measure=:slope_residual_lebesgue,selectable=false,role=:conditional_residual)))
                hyps[k]==0 || push!(out,merge(common,(;id="slope_sd[$(b.owner),$col]",family=:lognormal,
                    owner=b.owner,raw=[hyps[k]],free_dimension=1,logmean=p.logmean,logsd=p.logsd,
                    measure=:positive_sd_lebesgue,selectable=true,role=:hyperprior)))
            end
            isempty(cr) || push!(out,merge(common,(;id="correlation[$(b.owner)]",family=:lkj_corr,
                owner=b.owner,raw=collect(cr),free_dimension=length(cr),D_dim,eta=b.correlation.eta,
                measure=:correlation_matrix_lebesgue,selectable=true,role=:hyperprior)))
        end
    end
    out
end
