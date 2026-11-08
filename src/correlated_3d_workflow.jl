using Random, Statistics, Serialization, JSON3

"""Scope of the opt-in `Experimental.Correlated3D` workflow; no scientific default."""
contract()=(;status=:experimental,dimensions=3,q=:fixed_pure,person_mean=:population_zero,
    person_sd=:fixed_one,slopes=:item_and_rater,threshold_owner=:item,
    prior=:explicit_normalized_exchangeable,lkj_eta=:explicit_fixed_positive,
    coordinates=:centered_abilities_and_rowwise_partial_fisher_z,
    sampler=:advancedhmc_forwarddiff,prediction=:existing_rating_rows,
    native_cache=:trusted_same_source_and_environment,scientific_acceptance=false)

"""
    model(spec; scales, lkj_eta)

Construct the declared 3D pure-Q MGMFRM. Supply all six normalized-prior scales
with `person_sd=1` and a positive LKJ shape. At least two items per dimension,
two raters, three categories and every person in every dimension are required.
Item discrimination multiplies ability; product-one rater consistency multiplies
the entire adjacent logit (multiplier 1.7). Admission does not prove identification.
"""
model(spec;scales,lkj_eta)=Target(spec;scales,lkj_eta)

function canonical(t::Target)
    r=contract(t)
    rebuilt=Target(deepcopy(t.independent.base.design.spec);scales=r.prior.scales,lkj_eta=r.lkj_eta)
    isequal(r,contract(rebuilt)) && isequal(t.independent.base.blueprint,rebuilt.independent.base.blueprint) &&
        isequal(t.correlation_log_normalizer,rebuilt.correlation_log_normalizer) ||
        throw(ArgumentError("target layout changed; reconstruct the model"))
    rebuilt
end
function checked_seed(seed)
    seed isa Integer && !(seed isa Bool) && 0<=seed<=typemax(Int) ||
        throw(ArgumentError("seed must be a nonnegative representable integer"))
    Int(seed)
end
function prior_draw(t,rng)
    raw=vec(B._guarded_generalized_prior_draws(t.independent,1,rng))
    z=[2rand(rng,B.Distributions.Beta(a,a))-1 for a in (t.eta+.5,t.eta+.5,t.eta)]
    all(x->abs(x)<1,z) || throw(ArgumentError("unrepresentable LKJ draw; do not clip or retry"))
    q=vcat(raw,atanh.(z));_,state=coordinates(t,q)
    block=t.independent.base.blueprint.blocks[:person]
    q[block]=vec(state.L*reshape(raw[block],3,:))
    q
end

"""
    generate(target; seed, q=nothing)

Generate one dataset on exactly the declared rating mask, IDs, Q and category
support. With `q=nothing`, draw the complete normalized joint prior, including
LKJ(3) and correlated abilities; otherwise use explicit centered coordinates.
Return the new specification, truth, probabilities and provenance. Missing
categories are retained in the declared support, never regenerated to force use.
This is not a recovery/SBC study or a new-person prediction from a fitted result.
"""
function generate(target::Target;seed,q=nothing)
    t=canonical(target);seed=checked_seed(seed);rng=MersenneTwister(seed)
    truth=q===nothing ? prior_draw(t,rng) : Float64.(q)
    lp=category_logprobs(t,truth);all(isfinite,lp) || throw(ArgumentError("nonfinite category probabilities"))
    data=t.independent.base.design.spec.data
    scores=[data.category_levels[rand(rng,B.Distributions.Categorical(exp.(view(lp,n,:))))] for n in axes(lp,1)]
    spec=B._refit_training_spec(t.independent.base.design.spec,B._facet_data_with_scores(data,scores))
    generated=model(spec;scales=contract(t).prior.scales,lkj_eta=t.eta)
    (;spec=deepcopy(generated.independent.base.design.spec),truth=copy(truth),probabilities=exp.(lp),
        seed,parameter_generation=q===nothing ? :joint_prior : :supplied_centered_state,
        input_contract=contract(t),generated_contract=contract(generated))
end

# Strict point inspection still throws at a saturated transform. The sampling
# adapter rejects that numerical boundary rather than clipping the correlation.
struct SamplingTarget{T};target::T;end
L.dimension(t::SamplingTarget)=L.dimension(t.target)
L.capabilities(::Type{<:SamplingTarget})=L.LogDensityOrder{0}()
function L.logdensity(t::SamplingTarget,q::AbstractVector)
    length(q)==L.dimension(t) || throw(ArgumentError("invalid parameter length"))
    all(isfinite,q) || return oftype(first(q),-Inf)
    try
        coordinates(t.target,q)
    catch err
        err isa DomainError || rethrow()
        return oftype(first(q),-Inf)
    end
    v=L.logdensity(t.target,q)
    isfinite(v) ? v : oftype(first(q),-Inf)
end
function B._check_source_fixture_raw_vector(t::Union{Target,SamplingTarget},q::AbstractVector)
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("invalid parameter vector"))
    nothing
end
source_signature()=B.Experimental.JointRatings.OrdinalAssociation.source_signature()
const SAMPLE_SCHEMA="bayesianmgmfrm.correlated_3d_samples.v1"

function model_draws(t,draws)
    base=t.independent.base;labels=base.design.spec.dimension_labels
    pairs=((2,1),(3,1),(3,2))
    marginal=["rho[$(repr(labels[j])),$(repr(labels[i]))]" for (i,j) in pairs]
    partial=["partial[$(repr(labels[i])),$(repr(labels[j]))|$(repr(labels[1:j-1]))]" for (i,j) in pairs]
    direct=zeros(size(draws,1),length(base.design.parameter_names))
    rho=zeros(size(draws,1),6)
    for k in axes(draws,1)
        q=view(draws,k,:);raw,s=coordinates(t,q)
        direct[k,:]=B._guarded_generalized_direct_params(base,raw)
        rho[k,:]=vcat([s.R[i,j] for (i,j) in pairs],tanh.(q[end-2:end]))
    end
    # The shared normalized-target consumer also restores fixed baseline and
    # last sum-zero steps, which are absent from the free direct columns.
    core=B._mgmfrm_correlated_2d_coordinates(t.independent,view(draws,:,1:L.dimension(t.independent)),direct;scale=:model)
    names=vcat([c.parameter for c in core],marginal,partial)
    values=hcat([c.values for c in core]...,rho)
    fixed=Set(c.parameter for c in core if c.fixed)
    (;names,values,fixed,marginal,partial,labels)
end
function record(t,run)
    m=model_draws(t,run.draws)
    body=(;schema=SAMPLE_SCHEMA,spec=deepcopy(t.independent.base.design.spec),target=contract(t),
        source=source_signature(),run,model_effects_hash=B._cache_hash((;m.names,m.values)),
        warnings=["Experimental 3D model; numerical diagnostics do not establish scientific adequacy or calibration."])
    merge(body,(;content_hash=B._cache_hash(body)))
end
function restore(r)
    r isa NamedTuple && keys(r)==(:schema,:spec,:target,:source,:run,:model_effects_hash,:warnings,:content_hash) &&
        r.schema==SAMPLE_SCHEMA || throw(ArgumentError("invalid 3D sample record"))
    B._cache_hash(Base.structdiff(r,(;content_hash=nothing)))==r.content_hash || throw(ArgumentError("sample checksum mismatch"))
    isequal(r.source,source_signature()) || throw(ArgumentError("source or environment changed"))
    t=model(deepcopy(r.spec);scales=r.target.prior.scales,lkj_eta=r.target.lkj_eta)
    isequal(contract(t),r.target) || throw(ArgumentError("target or data changed"))
    B._check_generalized_sample_run(t,r.run)
    length(r.run.warmup_stats)==r.run.controls.warmup*r.run.controls.chains ||
        throw(ArgumentError("complete warmup telemetry required"))
    B._warmup_diagnostic_rows(r.run.warmup_stats,r.run.controls,r.run.backend)
    m=model_draws(t,r.run.draws)
    all(isfinite,m.values) && B._cache_hash((;m.names,m.values))==r.model_effects_hash ||
        throw(ArgumentError("restored model values changed"))
    t
end

"""
    fit(target; ndraws, warmup, chains, seed, kwargs...)

Run centered AdvancedHMC NUTS with ForwardDiff and complete warmup telemetry.
Controls: `target_accept=.9`, `max_depth=10`, `step_size=.03`, `init_jitter=.1`,
`metric=:diagonal`, `progress=false`. Returns owned joint chains, model/source
identity and warnings. No automatic retry, extension, cache lookup or acceptance.
"""
function fit(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept=.9,max_depth=10,step_size=.03,init_jitter=.1,metric=:diagonal,progress=false)
    t=canonical(target);seed=checked_seed(seed)
    run=B._run_generalized_candidate_advancedhmc(SamplingTarget(t),initial(t);ndraws,warmup,chains,seed,
        target_accept,max_depth,step_size,init_jitter,metric,progress,ad_backend=:ForwardDiff,record_warmup=true)
    result=record(t,run);restore(result);result
end
"""`save_result(path, result)` validates and atomically saves trusted native samples without overwrite."""
function save_result(path::AbstractString,result)
    restore(result);B._save_serialized_record(path,result;overwrite=false)
end
"""`load_result(path)` requires the producing source/environment and validates all retained densities; no RNG."""
function load_result(path::AbstractString)
    result=open(deserialize,path);restore(result);result
end
function diagnostics(t,run,m)
    raw=vcat(t.independent.base.blueprint.parameter_names,["q21","q31","q32"])
    diagnose(x,names;fixed=Set{String}(),space)=B._candidate_mcmc_diagnostic_rows(x,names,run.controls.chains;
        parameter_space=space,structurally_fixed_parameters=fixed,split_chains=run.split_chains_requested,
        rhat_threshold=run.checked.rhat_threshold,ess_threshold=run.checked.ess_threshold)
    (;raw=diagnose(run.draws,raw;space=:centered_raw),model=diagnose(m.values,m.names;fixed=m.fixed,space=:model),
        sampler=run.sampler_rows,warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend))
end
function summaries(values,names,chains,interval;fixed=Set{String}())
    interval isa Real && !(interval isa Bool) && isfinite(interval) && 0<interval<1 || throw(ArgumentError("interval must be in (0,1)"))
    lo=(1-Float64(interval))/2;hi=1-lo
    rows=B._posterior_summary_rows(values,names;lower=lo,upper=hi,intervals=(interval,),reference=0.,rope=nothing,rope_probability_threshold=.95)
    (;posterior=[(;r.parameter,r.mean,r.sd,r.median,r.lower,r.upper) for r in rows],
        mcse=B._posterior_mcse_rows(values,names,chains;probabilities=(lo,.5,hi),parameter_space=:model,
            structurally_fixed_parameters=fixed),interval_method=:equal_tailed)
end
envelope(r,operation,result)=(;schema="bayesianmgmfrm.correlated_3d_report.v1",operation,api=contract(),
    target=deepcopy(r.target),source_sample_content_hash=r.content_hash,warnings=copy(r.warnings),result)

"""
    report(result; parameters=nothing, interval=.95)

Named model effects, three marginal correlations and three rowwise partial
correlations with intervals and MCSE. Defaults to all model coordinates; a
selection never removes all-coordinate raw/model/sampler diagnostics. Population
covariance equals correlation because marginal SDs are fixed at one. Partial
rho32 conditions on the first named dimension. Neither is a sample-score correlation.
"""
function report(r;parameters=nothing,interval=.95)
    t=restore(r);m=model_draws(t,r.run.draws)
    names=parameters===nothing ? m.names : collect(parameters)
    !isempty(names) && allunique(names) && all(n->n in m.names,names) || throw(ArgumentError("select distinct stored names"))
    ix=[only(findall(==(n),m.names)) for n in names]
    covariance=[(;dimension_1=m.labels[i],dimension_2=m.labels[j],fixed=i==j,
        fixed_value=i==j ? 1. : nothing,parameter=i==j ? nothing : m.marginal[findfirst(==((max(i,j),min(i,j))),((2,1),(3,1),(3,2)))]) for i in 1:3 for j in 1:3]
    envelope(r,:parameters,merge(summaries(m.values[:,ix],names,r.run.controls.chains,interval;fixed=m.fixed),
        (;parameter_names=m.names,population_covariance=covariance,population_mean=zeros(3),population_sd=ones(3),
          diagnostics=diagnostics(t,r.run,m),controls=r.run.controls,focal_precision_qualification=:not_assessed,scientific_acceptance=false)))
end

"""
    probabilities(result; observation, interval=.95)

Posterior category probabilities for one original rating row, with IDs, the
full declared category support, intervals and MCSE. Conditional on fitted
effects, not prediction for new people/raters or a replicated-rating interval.
All raw/model diagnostics remain attached; no simulation occurs.
"""
function probabilities(r;observation::Integer,interval=.95)
    t=restore(r);base=t.independent.base;data=base.design.spec.data
    !(observation isa Bool) && 1<=observation<=data.n || throw(ArgumentError("invalid observation"))
    n=Int(observation);K=length(data.category_levels);values=zeros(r.run.total_draws,K)
    loading=B._mgmfrm_source_loading_index_matrix(base.design)
    for k in axes(values,1)
        raw,_=coordinates(t,view(r.run.draws,k,:));direct=B._guarded_generalized_direct_params(base,raw)
        row=view(values,k,:);B._mgmfrm_source_linear_predictors!(row,base.design,direct,n,loading)
        row .= exp.(row.-B._logsumexp(row))
    end
    names=["probability[$(repr(c))]" for c in data.category_levels];m=model_draws(t,r.run.draws)
    envelope(r,:probabilities,merge(summaries(values,names,r.run.controls.chains,interval),
        (;observation=n,person=data.person_levels[data.person[n]],item=data.item_levels[data.item[n]],rater=data.rater_levels[data.rater[n]],
          categories=copy(data.category_levels),conditioning=:existing_fitted_effects,
          diagnostics=diagnostics(t,r.run,m),scientific_acceptance=false)))
end
"""Write a portable JSON report without overwrite. Reports are not replayable sample records."""
function save_report(path::AbstractString,r)
    (ispath(path)||islink(path)) && throw(ArgumentError("preserve existing report"))
    open(path,"w") do io;JSON3.write(io,B.Experimental.JointRatings.W.jsonsafe(r));end
    path
end
