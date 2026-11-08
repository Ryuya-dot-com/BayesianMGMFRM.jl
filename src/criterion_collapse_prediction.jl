# A rater's class is integrated once for all of that rater's repeated ratings.
function _class_logweights(t,q,c=components(t,q))
    odds=q[end] .+ c.ell[:,2] .- c.ell[:,1]
    (;ordinary=-softplus.(odds),collapse=-softplus.(-odds))
end
_logcomplement(x)=x < -log(2.) ? log1p(-exp(x)) : log(-expm1(x))
_logmean(x)=B._logsumexp(x)-log(length(x))

function _functional(v,run;fixed=false)
    names=["functional"]; constants=fixed ? Set(names) : Set{String}()
    values=reshape(v,:,1)
    p=only(B._posterior_mcse_rows(values,names,run.controls.chains;probabilities=(),
        parameter_space=:posterior_functional,structurally_fixed_parameters=constants))
    d=only(B._candidate_mcmc_diagnostic_rows(values,names,run.controls.chains;
        parameter_space=:posterior_functional,structurally_fixed_parameters=constants,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,
        ess_threshold=run.checked.ess_threshold))
    status=fixed ? :structurally_fixed : ismissing(p.mean_mcse) ? p.mcse_status : :available
    (;mean=mean(v),mean_mcse=p.mean_mcse,mcse_status=status,diagnostics=d)
end

function _operation_context(result,t)
    run=result.run; d=RI._diagnostics(t,run,_draws(t,run.draws))
    q=B._qualify_experimental_diagnostics(d,run,run.checked,.3)
    (;scope=SCOPE,target_identity=result.target_identity,source_sample_content_hash=result.content_hash,
        prior=_prior(t.prior),diagnostics=d,qualification=q,sampling_warning=q.sampling_warning || !q.qualified,
        total_draws=size(run.draws,1),chains=run.controls.chains,
        chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),
        precision_threshold_applied=false,automatic_classification=false)
end

function _comparison_values(t,draws,run)
    loga=[sum(_class_logweights(t,q).ordinary) for q in eachrow(draws)]
    logb=_logcomplement.(loga); lp=_logmean(loga); lq=_logmean(logb)
    # Integrating the shared Beta mixing proportion is not a product of marginal priors.
    a,b=t.prior.class_alpha,t.prior.class_beta
    prior_logp=-sum(softplus(log(a)-log(b+j)) for j in 0:t.R-1)
    prior_logq=_logcomplement(prior_logp)
    probability=_functional(exp.(loga),run)
    influence=isfinite(lp) && isfinite(lq) ? exp.(loga.-lp).-exp.(logb.-lq) : fill(NaN,length(loga))
    precision=_functional(influence,run)
    logbf=lp-lq-prior_logp+prior_logq
    boundary=!(0<probability.mean<1) || !isfinite(logbf)
    (;posterior_all_ordinary=(;probability...,log_probability=lp,log_complement=lq),
        prior_all_ordinary=(;probability=exp(prior_logp),log_probability=prior_logp,log_complement=prior_logq),
        log_bf_ordinary_vs_any_collapse=(;estimate=logbf,
            mcse=boundary ? missing : precision.mean_mcse,
            mcse_status=boundary ? :probability_boundary : precision.mcse_status,
            method=:chain_aware_delta_influence,diagnostics=precision.diagnostics),
        log_bf_ordinary_vs_mixture=lp-prior_logp,
        probability_boundary=boundary,
        mcse_warning=boundary || probability.mcse_status!==:available || precision.mcse_status!==:available)
end

"""
    compare_models(result::NamedTuple)

For a CriterionCollapse fit, compare the all-ordinary submodel (A) with its
complement (at least one persistent collapse class), under the encompassing
model's induced priors. Returns posterior/prior event probabilities and log
Bayes factors, with chain-aware probability and delta-method log-odds MCSE.
P(A)=B(alpha,beta+R)/B(alpha,beta); posterior products are formed within each
joint draw. This is not the default MFRM prior, WAIC/LOO, held-out prediction,
classification accuracy or a model-adequacy check. No equal model odds, verbal
cutoff, new fit, subsampling or RNG is imposed. Inspect whole-fit qualification,
focal diagnostics/MCSE and prior sensitivity separately. Boundary or constant
sampled probabilities do not establish certainty. Save/reopen via the shared
`save_report` / `load_report` with the returned SHA-256 receipt.

Alternatively, `criterion=:loo, unit=:performance_rater` compares held-out
profile log scores for the mixture and induced all-ordinary model. This returns
a separate criterion report with PSIS diagnostics and paired numerical MCSE,
not Bayes factors; see `criteria` for its conditioning and precision limits.
"""
function compare_models(result;criterion=:bayes_factor,unit=nothing)
    criterion===:loo && return _heldout_comparison(result;unit)
    criterion===:bayes_factor && unit===nothing || throw(ArgumentError("choose criterion=:loo with unit=:performance_rater, or the no-keyword Bayes-factor operation"))
    t=_restore(result)
    (;kind=:criterion_collapse_model_comparison,_operation_context(result,t)...,
        models=(ordinary=:all_raters_ordinary,alternative=:at_least_one_collapse,encompassing=:mixture),
        conditioning=:induced_submodels_of_same_joint_prior,
        _comparison_values(t,result.run.draws,result.run)...,
        warning="Relative model evidence under the specified induced priors, not adequacy, calibrated detection, prevalence or fairness. Inspect probability/log-BF MCSE and whole-fit warnings; boundary probabilities do not establish certainty.")
end

function _count_design(t,category,rater_weights,S,model,max_count_updates)
    model in (:mixture,:all_ordinary) || throw(ArgumentError("model must be :mixture or :all_ordinary"))
    category isa Integer && !(category isa Bool) && category in t.data.category_levels ||
        throw(ArgumentError("category must be a declared integer score"))
    max_count_updates isa Integer && !(max_count_updates isa Bool) && max_count_updates>0 ||
        throw(ArgumentError("max_count_updates must be a positive integer"))
    levels=t.data.rater_levels
    rater_weights===nothing || (rater_weights isa AbstractDict &&
        all(k->any(isequal(k),levels),keys(rater_weights)) &&
        all(v->v isa Integer && !(v isa Bool) && v in (-1,0,1),values(rater_weights))) ||
        throw(ArgumentError("rater_weights must map known rater labels to -1, 0 or 1; omitted raters have weight zero"))
    weights=rater_weights===nothing ? ones(Int,t.R) : [Int(get(rater_weights,r,0)) for r in levels]
    any(!=(0),weights) || throw(ArgumentError("Select at least one nonzero rater weight"))
    ids=[findall(==(r),t.rater) for r in 1:t.R]; ns=length.(ids)
    lo=sum(min(weights[r],0)*ns[r] for r in 1:t.R)
    hi=sum(max(weights[r],0)*ns[r] for r in 1:t.R)
    updates=big(0);width=big(1)
    for r in 1:t.R
        weights[r]==0 && continue
        n=ns[r]
        updates+=(model===:mixture ? 2 : 1)*big(n)*(n+3)÷2+width*(n+1)
        width+=n
    end
    updates*=S
    updates<=max_count_updates || throw(ArgumentError("Exact joint count recurrence exceeds max_count_updates; raise the budget explicitly rather than discard draws or ratings"))
    (;weights,ids,lo,hi,category_index=findfirst(==(category),t.data.category_levels),
        observed=sum(weights[t.rater[n]]*(t.data.category[n]==findfirst(==(category),t.data.category_levels)) for n in eachindex(t.score)),
        count_updates=Int(updates))
end

function _convolve(a,b)
    out=zeros(length(a)+length(b)-1)
    for i in eachindex(a),j in eachindex(b);out[i+j-1]+=a[i]*b[j];end
    out
end
function _rater_count(logprobs,ids,k)
    mass=zeros(length(ids)+1);mass[1]=1.
    for (j,n) in enumerate(ids)
        B.Experimental.RaterGroupEffects._count_update!(mass,exp(logprobs[n,k]),j)
    end
    mass
end

function _count_values(t,draws,design,model)
    S=size(draws,1); support=collect(design.lo:design.hi); oi=design.observed-design.lo+1
    values=zeros(S,4);logweights=zeros(S);aggregate=zeros(length(support));scale=-Inf;denominator=0.;mass_error=0.
    for (j,q) in enumerate(eachrow(draws))
        c=components(t,q);w=_class_logweights(t,q,c)
        logweights[j]=model===:all_ordinary ? sum(w.ordinary) : 0.
        mass=[1.]
        for r in 1:t.R
            sign=design.weights[r];sign==0 && continue
            p=_rater_count(c.probs.ordinary,design.ids[r],design.category_index)
            if model===:mixture
                p=exp(w.ordinary[r]).*p .+ exp(w.collapse[r]).*_rater_count(c.probs.halo,design.ids[r],design.category_index)
            end
            mass=_convolve(mass,sign<0 ? reverse(p) : p)
        end
        error=abs(sum(mass)-1);mass_error=max(mass_error,error)
        all(isfinite,mass) && minimum(mass)>=0 && error<=max(1e-12,32t.data.n*eps(Float64)) ||
            throw(ArgumentError("Joint predictive mass failed normalization"))
        values[j,:]=[sum(support.*mass),oi==length(mass) ? 1. : sum(view(mass,1:oi)),
            oi==1 ? 1. : sum(view(mass,oi:length(mass))),mass[oi]]
        nextscale=max(scale,logweights[j]);oldweight=exp(scale-nextscale);newweight=exp(logweights[j]-nextscale)
        aggregate .*=oldweight;aggregate .+=newweight.*mass
        denominator=denominator*oldweight+newweight;scale=nextscale
    end
    isfinite(denominator) && denominator>0 || throw(ArgumentError("Conditional model has no representable posterior weight"))
    (;values,logweights,support,pmf=aggregate./denominator,max_mass_error=mass_error)
end

function _ratio_summary(v,weights,run;fixed=false)
    denominator=mean(weights);mu=sum(weights.*v)/sum(weights)
    influence=weights.*(v.-mu)./denominator
    precision=_functional(influence,run;fixed)
    (;estimate=mu,mcse=precision.mean_mcse,mcse_status=precision.mcse_status,
        method=:chain_aware_ratio_influence,diagnostics=precision.diagnostics,
        numerator_diagnostics=_functional(weights.*v,run;fixed=fixed && allequal(weights)).diagnostics)
end

"""
    predictive_check(result; category, rater_weights=nothing,
                     model=:mixture, max_count_updates=50_000_000)

For CriterionCollapse, integrate the same-design category-count distribution,
retaining one persistent class per rater. Default: total count of `category`.
A dictionary of rater labels to -1/0/+1 defines a signed count contrast; omitted
raters have weight zero. `model=:all_ordinary` conditions the joint posterior
on every rater being ordinary, using within-draw event weights. Merely replacing
the response rule without reweighting gives a different posterior prediction.

Returns the predictive PMF, expected count/contrast, inclusive lower/upper tails
and observed mass. Four functionals have chain-aware ratio-influence MCSE and
numerator diagnostics; the PMF cells and count quantiles have no precision claim.
The weight denominator has separate diagnostics. Weight concentration is not
MCMC ESS. No automatic precision, classification or rejection threshold is set.
Constant sampled functionals have unavailable MCSE, except support-fixed tails.

Per-rater Poisson-binomial recurrence is mixed once per class, convolved within
each joint draw and then posterior-averaged. Work is bounded by the explicit
recurrence/convolution update budget; no draw/rating is discarded. Storage is
linear in draws and count support, excluding sample/probability/diagnostic
storage. No fitting or prediction RNG. This repeats known persons/raters and
allocation; it is not new-level or held-out validation. Inclusive tails overlap
at the observed mass and are not calibrated p-values. Inspect original and
focal warnings; save/reopen with `save_report` / `load_report` and its receipt.
"""
function predictive_check(result;category,rater_weights=nothing,model=:mixture,max_count_updates=50_000_000)
    t=_restore(result);run=result.run
    d=_count_design(t,category,rater_weights,size(run.draws,1),model,max_count_updates)
    x=_count_values(t,run.draws,d,model)
    shift=maximum(x.logweights);weights=exp.(x.logweights.-shift)
    summaries=[_ratio_summary(view(x.values,:,j),weights,run;
        fixed=(j==2 && d.observed==d.hi) || (j==3 && d.observed==d.lo)) for j in 1:4]
    denominator=_functional(weights,run;fixed=model===:mixture)
    context=_operation_context(result,t)
    (;kind=:criterion_collapse_predictive_check,context...,model,category,
        conditioning=:same_people_criteria_raters_and_allocation,
        statistic=:signed_category_count,rater_weights=[(;rater=t.data.rater_levels[r],weight=d.weights[r]) for r in 1:t.R],
        n_observations=t.data.n,observed=d.observed,support=x.support,pmf=x.pmf,
        expected_count=summaries[1],lower_tail=summaries[2],upper_tail=summaries[3],observed_mass=summaries[4],
        weight_denominator=(;denominator...,log_scale=shift,log_probability=_logmean(x.logweights)),
        weight_concentration=(;descriptive_n=sum(weights)^2/sum(abs2,weights),
            max_normalized_weight=maximum(weights)/sum(weights),is_mcmc_ess=false),
        pmf_precision=:not_assessed,count_quantile_precision=:not_assessed,
        max_count_updates,count_updates=d.count_updates,max_mass_error=x.max_mass_error,
        mcse_warning=any(s->!(s.mcse_status in (:available,:structurally_fixed)),summaries) ||
            !(denominator.mcse_status in (:available,:structurally_fixed)),
        warning="Same-design joint prediction, not held-out validation, calibrated p-values or a mechanism diagnosis. Inspect whole-fit, numerator/denominator and focal precision separately; relative model support does not establish adequacy. PMF-cell and count-quantile precision are not assessed.")
end

function _operation_report_check(r)
    fail()=throw(ArgumentError("Incomplete criterion-collapse comparison/prediction report"))
    _plot_context(r)
    all(k->hasproperty(r,k),(:kind,:qualification,:sampling_warning,:total_draws,:chains,:chain_ids,
        :iterations,:precision_threshold_applied,:automatic_classification,:mcse_warning)) || fail()
    r.chains isa Integer && r.chains>0 && r.total_draws isa Integer && r.total_draws>0 && r.total_draws%r.chains==0 || fail()
    n=r.total_draws÷r.chains
    collect(r.chain_ids)==repeat(1:r.chains;inner=n) && collect(r.iterations)==repeat(1:n;outer=r.chains) || fail()
    r.precision_threshold_applied===false && r.automatic_classification===false || fail()
    all(k->hasproperty(r.qualification,k),(:qualified,:telemetry_complete,:focal_precision_qualification,:thresholds)) || fail()
    r.qualification.qualified isa Bool && r.qualification.telemetry_complete isa Bool &&
        string(r.qualification.focal_precision_qualification)=="not_assessed" || fail()
    (!r.qualification.qualified || !r.diagnostics.qualified) && !r.sampling_warning && fail()
    for flag in (:sampling_warning,:mcse_warning)
        getproperty(r,flag) isa Bool || fail()
    end
    if string(r.kind) in ("criterion_collapse_heldout_criteria","criterion_collapse_heldout_comparison")
        return _heldout_report_check(r)
    elseif string(r.kind)=="criterion_collapse_model_comparison"
        all(k->hasproperty(r,k),(:models,:conditioning,:posterior_all_ordinary,:prior_all_ordinary,
            :log_bf_ordinary_vs_any_collapse,:log_bf_ordinary_vs_mixture,:probability_boundary)) || fail()
        string(r.conditioning)=="induced_submodels_of_same_joint_prior" && r.probability_boundary isa Bool || fail()
        all(k->hasproperty(r.models,k),(:ordinary,:alternative,:encompassing)) &&
            string(r.models.ordinary)=="all_raters_ordinary" && string(r.models.alternative)=="at_least_one_collapse" &&
            string(r.models.encompassing)=="mixture" || fail()
        all(k->hasproperty(r.posterior_all_ordinary,k),(:mean,:mean_mcse,:mcse_status,:diagnostics,:log_probability,:log_complement)) &&
            all(k->hasproperty(r.prior_all_ordinary,k),(:probability,:log_probability,:log_complement)) &&
            all(k->hasproperty(r.log_bf_ordinary_vs_any_collapse,k),(:estimate,:mcse,:mcse_status,:method,:diagnostics)) || fail()
        _plot_finite(r.prior_all_ordinary.probability) && 0<=r.prior_all_ordinary.probability<=1 || fail()
        _plot_mean(merge((;mean=r.posterior_all_ordinary.mean,mean_mcse=r.posterior_all_ordinary.mean_mcse,
            mcse_status=r.posterior_all_ordinary.mcse_status),(;interval=nothing)))
    elseif string(r.kind)=="criterion_collapse_predictive_check"
        all(k->hasproperty(r,k),(:model,:category,:rater_weights,:observed,:support,:pmf,:expected_count,:conditioning,:statistic,:n_observations,
            :lower_tail,:upper_tail,:observed_mass,:weight_denominator,:weight_concentration,
            :pmf_precision,:count_quantile_precision,:max_count_updates,:count_updates,:max_mass_error)) || fail()
        string(r.model) in ("mixture","all_ordinary") && !isempty(r.support) &&
            string(r.conditioning)=="same_people_criteria_raters_and_allocation" &&
            string(r.statistic)=="signed_category_count" && r.n_observations isa Integer && r.n_observations>0 || fail()
        r.category isa Integer && !(r.category isa Bool) && !isempty(r.rater_weights) || fail()
        all(row->hasproperty(row,:rater) && hasproperty(row,:weight) && row.weight isa Integer &&
            !(row.weight isa Bool) && row.weight in (-1,0,1),r.rater_weights) || fail()
        allunique([row.rater for row in r.rater_weights]) && any(row->row.weight!=0,r.rater_weights) || fail()
        all(k->hasproperty(r.weight_denominator,k),(:mean,:mean_mcse,:mcse_status,:diagnostics,:log_scale,:log_probability)) &&
            all(k->hasproperty(r.weight_concentration,k),(:descriptive_n,:max_normalized_weight,:is_mcmc_ess)) || fail()
        r.weight_concentration.is_mcmc_ess===false && string(r.pmf_precision)=="not_assessed" &&
            string(r.count_quantile_precision)=="not_assessed" || fail()
        support=collect(r.support);p=collect(r.pmf)
        all(x->x isa Integer,support) && all(diff(support).==1) && r.observed in support || fail()
        length(p)==length(support) && all(x->_plot_finite(x) && 0<=x<=1,p) && isapprox(sum(p),1.;atol=1e-8) || fail()
        oi=findfirst(==(r.observed),support)
        expected=(sum(support.*p),sum(p[1:oi]),sum(p[oi:end]),p[oi])
        for (key,value) in zip((:expected_count,:lower_tail,:upper_tail,:observed_mass),expected)
            s=getproperty(r,key)
            all(k->hasproperty(s,k),(:estimate,:mcse,:mcse_status,:diagnostics,:numerator_diagnostics)) || fail()
            _plot_finite(s.estimate) && isapprox(s.estimate,value;atol=1e-8,rtol=1e-8) || fail()
            (ismissing(s.mcse) || s.mcse===nothing || (_plot_finite(s.mcse) && s.mcse>=0)) || fail()
        end
    else
        fail()
    end
    r
end
