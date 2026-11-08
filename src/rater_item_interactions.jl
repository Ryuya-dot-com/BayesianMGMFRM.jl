"""Experimental scalar PCM with jointly fitted, partially pooled rater-by-item effects."""
module RaterItemInteractions
import BayesianMGMFRM as B
import LogDensityProblems as L
using LinearAlgebra, Statistics, Serialization, JSON3

"""
    Prior(; person_sd, item_sd, rater_sd, step_sd,
            interaction_logmean, interaction_logsd)

Explicit prior on orthonormal coordinates. `log(tau)` is Normal with the last
two parameters; tau is the marginal prior SD of each interaction cell conditional
on tau. Positive cell effects mean additional severity. No default scientific
prior is supplied. See the fitted-interaction section of the interpretation guide.
"""
struct Prior
    person_sd::Float64
    item_sd::Float64
    rater_sd::Float64
    step_sd::Float64
    interaction_logmean::Float64
    interaction_logsd::Float64
    function Prior(;person_sd,item_sd,rater_sd,step_sd,interaction_logmean,interaction_logsd)
        xs=(person_sd,item_sd,rater_sd,step_sd,interaction_logmean,interaction_logsd)
        all(x->x isa Real && !(x isa Bool) && isfinite(x),xs) ||
            throw(ArgumentError("Prior parameters must be finite real numbers."))
        all(>(0),(person_sd,item_sd,rater_sd,step_sd,interaction_logsd)) || throw(ArgumentError("Prior SDs must be positive."))
        ys=Float64.(xs)
        all(isfinite,ys) || throw(ArgumentError("Prior parameters must be representable as Float64."))
        new(ys...)
    end
end
_prior(p::Prior)=(; (n=>getfield(p,n) for n in fieldnames(Prior))...)

function _helmert(n)
    h=zeros(n,n-1)
    for j in 1:n-1
        h[1:j,j].=1/sqrt(j*(j+1));h[j+1,j]=-j/sqrt(j*(j+1))
    end
    h
end

# Complete cell locations span rater + item + doubly centered interaction.
# Person--cell connectivity therefore tests the location rank without a dense X.
function _allocation(d)
    P,R,I=length(d.person_levels),length(d.rater_levels),length(d.item_levels)
    counts=zeros(Int,R,I);people=[Set{Int}() for r in 1:R,i in 1:I]
    roots=collect(1:P+R*I)
    function root(a)
        while roots[a]!=a
            roots[a]=roots[roots[a]];a=roots[a]
        end
        a
    end
    for n in 1:d.n
        p,r,i=d.person[n],d.rater[n],d.item[n]
        counts[r,i]+=1;push!(people[r,i],p)
        roots[root(p)]=root(P+r+R*(i-1))
    end
    components=length(unique(root.(eachindex(roots))))
    (;counts,people=length.(people),components,
        location_rank=P+R*I-components,location_columns=P+R*I-1,
        complete_cells=all(>(0),counts),connected=components==1)
end

struct Target
    data::B.FacetData
    prior::Prior
    blocks::NamedTuple
    item_basis::Matrix{Float64}
    rater_basis::Matrix{Float64}
    step_basis::Matrix{Float64}
    interaction_normalization::Float64
    allocation::NamedTuple
end

function _table(d)
    (;person=deepcopy(d.person_levels[d.person]),item=deepcopy(d.item_levels[d.item]),
        rater=deepcopy(d.rater_levels[d.rater]),score=copy(d.score))
end

"""
    model(data::FacetData; prior::Prior)

Prepare an experimental unit-slope scalar item-step PCM. This first route requires
every rater-by-item cell observed and a connected person--cell allocation. Missing
individual ratings and unequal cell counts are allowed; no missing score is filled.
Other facet columns, slopes, Q matrices and group DIF are outside this model.
Constructing a model performs no sampling. Inspect `design(model)` before fitting.
"""
function model(data::B.FacetData;prior::Prior)
    isempty(data.optional) || throw(ArgumentError("This model accepts person, item and rater only; optional facets would not be fitted."))
    d=B.FacetData(_table(data);person=:person,item=:item,rater=:rater,score=:score,
        category_levels=copy(data.category_levels))
    P,R,I,K=length(d.person_levels),length(d.rater_levels),length(d.item_levels),length(d.category_levels)
    R>=2 && I>=2 || throw(ArgumentError("An interaction requires at least two raters and two items."))
    a=_allocation(d)
    a.complete_cells || throw(ArgumentError("Unobserved rater-by-item cells are outside this first fitted-interaction route; do not fill them with zero scores."))
    a.connected || throw(ArgumentError("Persons do not link all rater-by-item cells: $(a.components) components, location rank $(a.location_rank)/$(a.location_columns). Priors cannot supply data identification."))
    sizes=(;person=P,item=I-1,rater=R-1,steps=I*(K-2),interaction=(R-1)*(I-1),log_tau=1)
    start=1
    blocks=map(sizes) do n
        ids=start:start+n-1;start+=n;ids
    end
    Target(d,prior,blocks,_helmert(I),_helmert(R),_helmert(K-1),
        sqrt((1-1/R)*(1-1/I)),a)
end

"""Observed counts, distinct people, exact location rank and the equal-cell reference."""
design(t::Target)=(;deepcopy(t.allocation)...,
    raters=deepcopy(t.data.rater_levels),items=deepcopy(t.data.item_levels),
    reference=:equal_weight_full_rater_item_grid,
    scope=:complete_cells_connected_person_cell_allocation,
    warning="Connectivity is not adequate precision; inspect counts, priors and posterior diagnostics.")

L.dimension(t::Target)=last(t.blocks.log_tau)
L.capabilities(::Type{Target})=L.LogDensityOrder{0}()
function B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("Invalid interaction coordinate vector."))
    nothing
end
function initial(t::Target)
    q=zeros(L.dimension(t));q[t.blocks.log_tau].=t.prior.interaction_logmean;q
end
function coordinates(t::Target,q)
    b,p=t.blocks,t.prior;I=length(t.data.item_levels);R=length(t.data.rater_levels)
    K=length(t.data.category_levels);tau=exp(q[only(b.log_tau)])
    (;person=p.person_sd.*q[b.person],item=p.item_sd.*(t.item_basis*q[b.item]),
        rater=p.rater_sd.*(t.rater_basis*q[b.rater]),
        steps=p.step_sd.*permutedims(t.step_basis*reshape(q[b.steps],K-2,I)),
        interaction=(tau/t.interaction_normalization).*
            (t.rater_basis*reshape(q[b.interaction],R-1,I-1)*t.item_basis'),tau)
end

function category_logprobs(t::Target,q)
    v=coordinates(t,q);d=t.data;K=length(d.category_levels)
    out=Matrix{eltype(q)}(undef,d.n,K)
    for n in 1:d.n
        i,r=d.item[n],d.rater[n]
        eta=v.person[d.person[n]]-v.item[i]-v.rater[r]-v.interaction[r,i]
        out[n,1]=zero(eta)
        for k in 2:K;out[n,k]=out[n,k-1]+eta-v.steps[i,k-1];end
        m=maximum(view(out,n,:));normalizer=m+log(sum(exp.(view(out,n,:).-m)))
        out[n,:].-=normalizer
    end
    out
end
function L.logdensity(t::Target,q)
    length(q)==L.dimension(t) || throw(DimensionMismatch("interaction coordinates"))
    all(isfinite,q) && isfinite(exp(q[end])) || return oftype(q[1],-Inf)
    z=(q[end]-t.prior.interaction_logmean)/t.prior.interaction_logsd
    lp=-(sum(abs2,view(q,1:length(q)-1))+z^2)/2-
        length(q)*log(2pi)/2-log(t.prior.interaction_logsd)
    probs=category_logprobs(t,q)
    lp+sum(probs[n,t.data.category[n]] for n in 1:t.data.n)
end

const SCHEMA="bayesianmgmfrm.rater_item_interaction_samples.v1"
const SCOPE=(;family=:scalar_unit_slope_item_step_pcm,interaction=:rater_item,
    reference=:equal_weight_full_grid,acceptance=:experimental_engineering_only)
"""Machine-readable scope of the experimental fitted-interaction workflow."""
contract()=(;SCOPE...,backend=:advancedhmc,
    allocation=:complete_cells_connected_person_cell_graph,prior=:explicit,
    operations=(:model,:design,:target_identity,:fit,:report,:contrast,:save_result,:load_result,:save_report),
    scientific_acceptance=false)
_target_record(t)=(;table=_table(t.data),categories=copy(t.data.category_levels),prior=_prior(t.prior))
"""Fingerprint the model's data, categories and prior to check a saved result's target."""
target_identity(t::Target)=B._cache_hash(_target_record(t))
function _restore_target(record)
    keys(record)==(:table,:categories,:prior) || throw(ArgumentError("Unknown interaction target record."))
    d=B.FacetData(record.table;person=:person,item=:item,rater=:rater,score=:score,category_levels=record.categories)
    model(d;prior=Prior(;record.prior...))
end

"""Fit with Julia NUTS; explicit counts and seed, full sampler and warmup telemetry."""
function fit(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept=.9,max_depth::Int=10,step_size=.03,init_jitter=.1)
    t=_restore_target(_target_record(target))
    run=B._run_generalized_candidate_advancedhmc(t,initial(t);ndraws,warmup,chains,seed,
        target_accept,max_depth,step_size,init_jitter,ad_backend=:ForwardDiff,record_warmup=true)
    record=_target_record(t)
    body=(;schema=SCHEMA,target=record,target_identity=B._cache_hash(record),scope=SCOPE,run)
    result=merge(body,(;content_hash=B._cache_hash(body)))
    _restore(result);result
end
function _restore(result)
    result isa NamedTuple && keys(result)==(:schema,:target,:target_identity,:scope,:run,:content_hash) &&
        result.schema==SCHEMA && result.scope==SCOPE || throw(ArgumentError("Unknown interaction sample record."))
    B._cache_hash(Base.structdiff(result,(;content_hash=nothing)))==result.content_hash ||
        throw(ArgumentError("Interaction sample checksum mismatch."))
    B._cache_hash(result.target)==result.target_identity || throw(ArgumentError("Interaction target checksum mismatch."))
    t=_restore_target(result.target);B._check_generalized_sample_run(t,result.run)
    run=result.run
    length(run.warmup_stats)==run.controls.chains*run.controls.warmup ||
        throw(ArgumentError("Incomplete warmup record."))
    B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend)
    t
end
"""Save without overwrite. Native samples require their original source and environment."""
function save_result(path,result)
    _restore(result);B._save_serialized_record(path,result;overwrite=false)
end
"""Read a trusted native file and validate its target, hashes and every retained density."""
function load_result(path)
    result=open(deserialize,path);_restore(result);result
end
_jsonsafe(x::NamedTuple)=NamedTuple{keys(x)}(map(_jsonsafe,values(x)))
_jsonsafe(x::Union{Tuple,AbstractArray})=map(_jsonsafe,x)
_jsonsafe(x::AbstractFloat)=isfinite(x) ? x : (;nonfinite=string(x))
_jsonsafe(x)=x
"""Save a computed JSON report, preserving nonfinite warnings; this is not a draw interchange."""
function save_report(path,report)
    ispath(path) && throw(ArgumentError("Preserve existing report: $path"))
    open(path,"w") do io
        JSON3.write(io,(;schema="bayesianmgmfrm.rater_item_interaction_report.v1",data=_jsonsafe(report)))
    end
    path
end

function _draws(t,draws)
    d=t.data;P,R,I,K=length(d.person_levels),length(d.rater_levels),length(d.item_levels),length(d.category_levels)
    names=[["person[$p]" for p in 1:P];["item[$i]" for i in 1:I];["rater[$r]" for r in 1:R];
        ["step[$i,$k]" for k in 1:K-1 for i in 1:I];
        ["interaction[$r,$i]" for i in 1:I for r in 1:R];"tau"]
    vals=Matrix{Float64}(undef,size(draws,1),length(names))
    for (n,q) in enumerate(eachrow(draws))
        v=coordinates(t,q);vals[n,:]=[v.person;v.item;v.rater;vec(v.steps);vec(v.interaction);v.tau]
    end
    fixed=K==2 ? Set(["step[$i,1]" for i in 1:I]) : Set{String}()
    (;names,values=vals,fixed)
end
function _diagnostics(t,run,m=_draws(t,run.draws))
    diagnose(values,names;fixed=Set{String}(),space=:model)=B._candidate_mcmc_diagnostic_rows(
        values,names,run.controls.chains;parameter_space=space,structurally_fixed_parameters=fixed,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,ess_threshold=run.checked.ess_threshold)
    raw=diagnose(run.draws,["raw[$j]" for j in 1:size(run.draws,2)];space=:white_log_sd)
    transformed=diagnose(m.values,m.names;fixed=m.fixed)
    ok(row)=!row.quality_gate_applicable ? row.flag===:structurally_fixed :
        all(isfinite,(row.rank_normalized_rhat,row.bulk_ess,row.tail_ess)) &&
        row.rank_normalized_rhat<=run.checked.rhat_threshold &&
        min(row.bulk_ess,row.tail_ess)>=run.checked.ess_threshold
    qualified=run.controls.chains>=4 && all(ok,[raw;transformed]) &&
        all(s->s.n_divergences==0 && s.n_nonfinite_logdensity==0 && s.n_max_treedepth==0 &&
            isfinite(s.e_bfmi) && s.e_bfmi>=.3,run.sampler_rows)
    (;raw,model=transformed,sampler=run.sampler_rows,qualified,sampling_warning=!qualified,
        warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend),
        thresholds=(;run.checked...,minimum_chains=4,minimum_ebfmi=.3))
end
function _margin(x)
    x isa Real && !(x isa Bool) && isfinite(x) && x>0 ||
        throw(ArgumentError("practical_threshold must be a positive finite logit difference, chosen for the question."))
    Float64(x)
end
_summary(draws,run,interval,margin)=B.posterior_contrast(draws,zeros(length(draws));
    chains=run.controls.chains,interval,rope=(-margin,margin))

"""
    report(result; practical_threshold, interval=.95)

Return every fitted interaction cell, counts, paired-draw uncertainty, mean/endpoint
and event-probability MCSE, plus all raw/model/sampler/warmup diagnostics. The
practical threshold is in unit logits and is chosen by the analyst. Positive gamma
means additional severity relative to the equal-cell additive surface. Marginal
probabilities do not control multiplicity or establish causal unfairness.
"""
function report(result;practical_threshold,interval=.95)
    margin=_margin(practical_threshold);t=_restore(result);run=result.run;m=_draws(t,run.draws)
    d=t.data;R,I=length(d.rater_levels),length(d.item_levels)
    cells=[(;rater=d.rater_levels[r],item=d.item_levels[i],n=t.allocation.counts[r,i],
        people=t.allocation.people[r,i],summary=_summary(
            m.values[:,only(findall(==("interaction[$r,$i]"),m.names))],run,interval,margin)) for i in 1:I for r in 1:R]
    parameter_rows=B._posterior_summary_rows(m.values,m.names;lower=(1-interval)/2,
        upper=(1+interval)/2,intervals=(interval,),reference=0.,rope=nothing,rope_probability_threshold=.95)
    (;target_identity=result.target_identity,source_sample_content_hash=result.content_hash,scope=SCOPE,
        prior=_prior(t.prior),controls=run.controls,design=design(t),unit=:unit_logit,
        positive_effect=:additional_severity,practical_threshold=margin,interval,cells,
        diagnostics=_diagnostics(t,run,m),
        labels=(;person=copy(d.person_levels),item=copy(d.item_levels),rater=copy(d.rater_levels)),
        parameter_summary=[(;r.parameter,r.mean,r.sd,r.median,r.intervals,r.n_draws) for r in parameter_rows],
        warning="Experimental model. Check whole-fit diagnostics AND focal MCSE. No automatic bias, fairness, equivalence or multiplicity decision.")
end

"""
    contrast(result; left, right, item, practical_threshold, interval=.95)

Three paired contrasts for left minus right: overall severity, additional
item-specific severity, and their sum at this item. All retain the source's
complete joint draws and diagnostics. Positive differences mean greater severity.
"""
function contrast(result;left,right,item,practical_threshold,interval=.95)
    margin=_margin(practical_threshold);t=_restore(result);d=t.data;run=result.run
    a,b=findfirst(isequal(left),d.rater_levels),findfirst(isequal(right),d.rater_levels)
    i=findfirst(isequal(item),d.item_levels)
    a!==nothing && b!==nothing && i!==nothing && a!=b || throw(ArgumentError("Choose two distinct existing raters and an existing item."))
    values=Matrix{Float64}(undef,size(run.draws,1),3)
    for (n,q) in enumerate(eachrow(run.draws))
        v=coordinates(t,q);overall=v.rater[a]-v.rater[b];extra=v.interaction[a,i]-v.interaction[b,i]
        values[n,:]=[overall,extra,overall+extra]
    end
    summaries=map(j->_summary(values[:,j],run,interval,margin),1:3)
    (;target_identity=result.target_identity,source_sample_content_hash=result.content_hash,
        left,right,item,unit=:unit_logit,positive_effect=:greater_severity,practical_threshold=margin,
        overall=summaries[1],additional=summaries[2],total_at_item=summaries[3],
        diagnostics=_diagnostics(t,run),chain_ids=copy(run.chain_ids),iterations=copy(run.iterations),
        evaluated_draws_hash=B._cache_hash(values),scope=SCOPE)
end
end
