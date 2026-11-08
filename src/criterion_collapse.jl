"""Experimental scalar criterion collapse with one persistent latent class per rater."""
module CriterionCollapse
import BayesianMGMFRM as B
import LogDensityProblems as L
using LinearAlgebra, Statistics, Serialization, JSON3
const RI=B.Experimental.RaterItemInteractions
const SF=B.SpecialFunctions

"""
    Prior(; person_precision_shape, person_precision_rate,
        rater_precision_shape, rater_precision_rate, step_sd,
        class_alpha, class_beta)

Explicit Gamma(shape, rate) priors for person/rater precision, independent
Normal(0, step_sd) criterion steps and Beta(class_alpha, class_beta) class
proportion. Locations are exchangeable, finite-panel sum-zero normals with
conditional marginal SD equal to inverse square-root precision. Gamma uses
RATE, not scale. This is not the author-code last-level prior or a scientific
default. Positive shapes are proper but can imply infinite marginal moments.
"""
struct Prior
    person_precision_shape::Float64
    person_precision_rate::Float64
    rater_precision_shape::Float64
    rater_precision_rate::Float64
    step_sd::Float64
    class_alpha::Float64
    class_beta::Float64
    function Prior(;person_precision_shape,person_precision_rate,rater_precision_shape,
            rater_precision_rate,step_sd,class_alpha,class_beta)
        xs=(person_precision_shape,person_precision_rate,rater_precision_shape,
            rater_precision_rate,step_sd,class_alpha,class_beta)
        all(x->x isa Real && !(x isa Bool) && isfinite(x) && x>0,xs) ||
            throw(ArgumentError("Prior parameters must be finite positive real numbers."))
        ys=Float64.(xs)
        all(x->isfinite(x) && x>0,ys) && all(isfinite,(SF.loggamma(ys[1]),
            SF.loggamma(ys[3]),SF.logbeta(ys[6],ys[7]),log(ys[5]))) ||
            throw(ArgumentError("Prior parameters or normalization are not representable."))
        new(ys...)
    end
end
_prior(p::Prior)=(; (n=>getfield(p,n) for n in fieldnames(Prior))...)

struct Target
    data::B.FacetData
    prior::Prior
    P::Int
    R::Int
    I::Int
    K::Int
    person::Vector{Int}
    criterion::Vector{Int}
    rater::Vector{Int}
    score::Vector{Int}
    H::NTuple{7,Float64}
    halo::Bool
    Qp::Matrix{Float64}
    Qr::Matrix{Float64}
    allocation::NamedTuple
end

"""
    model(data::FacetData; prior::Prior)

Prepare the scalar fixed-coefficient criterion-collapse mixture. `item` means
criterion; each person ID must denote the same performance across criteria and
raters. Requires at least two persons, raters and criteria, at least three
common categories, no duplicate person/criterion/rater row, every rater/criterion
cell and connected person-cell allocation. Missing individual ratings are
allowed. Optional facets and other model combinations are rejected. This screen
does not establish distinct criterion profiles or reliable class identification.
"""
function model(data::B.FacetData;prior::Prior)
    isempty(data.optional) || throw(ArgumentError("CriterionCollapse fits only person, item (criterion) and rater; optional facets are not supported."))
    d=B.FacetData(RI._table(data);person=:person,item=:item,rater=:rater,score=:score,
        category_levels=copy(data.category_levels))
    P,R,I,K=length(d.person_levels),length(d.rater_levels),length(d.item_levels),length(d.category_levels)
    min(P,R,I)>=2 && K>=3 || throw(ArgumentError("Requires two persons, raters and criteria, and three common categories."))
    length(Set(zip(d.person,d.item,d.rater)))==d.n || throw(ArgumentError("Duplicate performance/criterion/rater rating; distinguish performances explicitly."))
    a=RI._allocation(d)
    a.complete_cells && a.connected || throw(ArgumentError("Requires observed rater/criterion cells and connected person-cell allocation; do not fill missing ratings with zero."))
    Target(d,prior,P,R,I,K,copy(d.person),copy(d.item),copy(d.rater),d.category.-1,
        Tuple(values(_prior(prior))),true,RI._helmert(P),RI._helmert(R),a)
end

"""Return allocation counts and the fixed scope; connectivity does not ensure halo identification."""
design(t::Target)=(;deepcopy(t.allocation)...,persons=t.P,raters=copy(t.data.rater_levels),
    criteria=copy(t.data.item_levels),categories=copy(t.data.category_levels),
    warning="Connectivity is a location-design screen. Equal or weak criterion profiles can leave class probabilities prior-driven; no sample-size or classification guarantee.")
function B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)
    coordinates(t,q);nothing
end
function initial(t::Target)
    q=zeros(L.dimension(t));a,b,c,d,sd,e,f=t.H
    q[end-2]=log(a)-log(b);q[end-1]=log(c)-log(d);q[end]=log(e)-log(f);q
end

L.dimension(t::Target)=t.P+t.R-2+t.I*(t.K-1)+2+Int(t.halo)
L.capabilities(::Type{Target})=L.LogDensityOrder{0}()
softplus(x)=x>zero(x) ? x+log1p(exp(-x)) : log1p(exp(x))
function logadd(a,b)
    # Both exponential terms retain their derivative when the components tie.
    m=max(a,b)
    m+log(exp(a-m)+exp(b-m))
end

function coordinates(t::Target,q::AbstractVector{<:Real})
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("invalid parameter vector"))
    a=t.P-1; b=a+t.R-1; c=b+t.I*(t.K-1)
    u=view(q,1:a); v=view(q,a+1:b)
    logt=view(q,c+1:c+2); precision=exp.(logt)
    all(x->isfinite(x) && x>0,precision) || throw(DomainError(logt,"nonfinite/zero precision"))
    theta=sqrt(t.P/(t.P-1))*exp(-logt[1]/2)*(t.Qp*u)
    severity=sqrt(t.R/(t.R-1))*exp(-logt[2]/2)*(t.Qr*v)
    all(isfinite,theta) && all(isfinite,severity) || throw(DomainError(q,"nonfinite derived location"))
    delta=reshape(view(q,b+1:c),t.I,t.K-1)
    logpi=t.halo ? -softplus(-q[end]) : oftype(q[1],-Inf)
    log1mpi=t.halo ? -softplus(q[end]) : zero(q[1])
    (;u,v,theta,severity,delta,logt,precision,logpi,log1mpi)
end

function logprior(t::Target,q::AbstractVector{<:Real})
    s=coordinates(t,q); a,b,c,d,sd,e,f=t.H
    lp=zero(q[1])
    for (v,lt) in ((s.u,s.logt[1]),(s.v,s.logt[2]))
        lp += -length(v)*log(2pi)/2-sum(abs2,v)/2
    end
    lp += -length(s.delta)*(log(2pi)/2+log(sd))-sum(abs2,s.delta./sd)/2
    # Gamma precision densities plus log-precision Jacobians, exactly once.
    lp += a*log(b)-SF.loggamma(a)+a*s.logt[1]-b*s.precision[1]
    lp += c*log(d)-SF.loggamma(c)+c*s.logt[2]-d*s.precision[2]
    t.halo && (lp += e*s.logpi+f*s.log1mpi-SF.logbeta(e,f))
    lp
end

function category_logprobs(t::Target,q::AbstractVector{<:Real})
    s=coordinates(t,q); n=length(t.score)
    ordinary=zeros(eltype(q),n,t.K); halo=similar(ordinary)
    average=vec(sum(s.delta;dims=1))/t.I
    for row in 1:n
        location=s.theta[t.person[row]]-s.severity[t.rater[row]]
        for (out,steps) in ((ordinary,view(s.delta,t.criterion[row],:)),(halo,average))
            out[row,1]=zero(q[1])
            for k in 2:t.K; out[row,k]=out[row,k-1]+location-steps[k-1]; end
            view(out,row,:) .-= B._logsumexp(view(out,row,:))
        end
    end
    all(isfinite,ordinary) && all(isfinite,halo) || throw(DomainError(q,"nonfinite category log probabilities"))
    (;ordinary,halo)
end

function components(t::Target,q::AbstractVector{<:Real})
    probs=category_logprobs(t,q); s=coordinates(t,q)
    ell=zeros(eltype(q),t.R,2)
    for n in eachindex(t.score)
        ell[t.rater[n],1]+=probs.ordinary[n,t.score[n]+1]
        ell[t.rater[n],2]+=probs.halo[n,t.score[n]+1]
    end
    group=t.halo ? [logadd(s.log1mpi+ell[r,1],s.logpi+ell[r,2]) for r in 1:t.R] : ell[:,1]
    weights=t.halo ? [exp(s.logpi+ell[r,2]-group[r]) for r in 1:t.R] : zeros(eltype(q),t.R)
    (;probs,ell,group,weights,loglikelihood=sum(group))
end

function L.logdensity(t::Target,q::AbstractVector{<:Real})
    length(q)==L.dimension(t) || throw(DimensionMismatch("criterion-collapse coordinates"))
    all(isfinite,q) || return oftype(float(q[1]),-Inf)
    try
        lp=logprior(t,q)+components(t,q).loglikelihood
        isfinite(lp) ? lp : oftype(lp,-Inf)
    catch e
        e isa DomainError || rethrow()
        oftype(float(q[1]),-Inf)
    end
end


const SCHEMA="bayesianmgmfrm.criterion_collapse_samples.v1"
const SCOPE=(;family=:scalar_unit_slope_criterion_step_pcm,
    mechanism=:criterion_collapse,latent_class_unit=:rater_constant,
    prior=:exchangeable_sum_zero,acceptance=:experimental_engineering_only)
"""Machine-readable supported operations and scientific boundary."""
contract()=(;SCOPE...,backend=:advancedhmc,allocation=:complete_cells_connected_person_cell,
    operations=(:model,:design,:target_identity,:fit,:report,:category_report,:predictive_check,:criteria,:pointwise_loglikelihood,:compare_models,:save_result,:load_result,:save_report,:load_report,:plot_classes,:plot_categories),
    scientific_acceptance=false)
_target_record(t)=(;table=RI._table(t.data),categories=copy(t.data.category_levels),prior=_prior(t.prior))
"""Fingerprint the model's data, categories and prior to check a saved result's target."""
target_identity(t::Target)=B._cache_hash(_target_record(t))
function _restore_target(record)
    keys(record)==(:table,:categories,:prior) || throw(ArgumentError("Unknown criterion-collapse target record."))
    d=B.FacetData(record.table;person=:person,item=:item,rater=:rater,score=:score,category_levels=record.categories)
    model(d;prior=Prior(;record.prior...))
end

"""Fit with Julia NUTS; explicit counts and seed, full sampler and warmup telemetry."""
function fit(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept=.9,max_depth::Int=10,step_size=.03,init_jitter=.1,
        progress::Union{Bool,B.SamplingProgress}=false,chain_execution::Symbol=:serial,max_parallel_chains::Int=chains)
    t=_restore_target(_target_record(target))
    run=B._run_generalized_candidate_advancedhmc(t,initial(t);ndraws,warmup,chains,seed,
        target_accept,max_depth,step_size,init_jitter,ad_backend=:ForwardDiff,record_warmup=true,
        progress,chain_execution,max_parallel_chains)
    record=_target_record(t)
    body=(;schema=SCHEMA,target=record,target_identity=B._cache_hash(record),scope=SCOPE,run)
    result=merge(body,(;content_hash=B._cache_hash(body)))
    _restore(result);result
end
function _restore(result)
    result isa NamedTuple && keys(result)==(:schema,:target,:target_identity,:scope,:run,:content_hash) &&
        result.schema==SCHEMA && result.scope==SCOPE || throw(ArgumentError("Unknown criterion-collapse sample record."))
    B._cache_hash(Base.structdiff(result,(;content_hash=nothing)))==result.content_hash ||
        throw(ArgumentError("Criterion-collapse sample checksum mismatch."))
    B._cache_hash(result.target)==result.target_identity || throw(ArgumentError("Criterion-collapse target checksum mismatch."))
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
"""Save a computed JSON report, preserving nonfinite warnings; this is not a draw interchange."""
function save_report(path,report)
    hasproperty(report,:kind) && _operation_report_check(report)
    ispath(path) && throw(ArgumentError("Preserve existing report: $path"))
    open(path,"w") do io
        JSON3.write(io,(;schema="bayesianmgmfrm.criterion_collapse_report.v1",data=RI._jsonsafe(report)))
    end
    path
end


include("criterion_collapse_reports.jl")
include("criterion_collapse_prediction.jl")
include("criterion_collapse_loo.jl")
include("criterion_collapse_plots.jl")
end
