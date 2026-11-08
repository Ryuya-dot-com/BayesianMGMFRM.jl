"""Experimental observed-group differences in rater severity, jointly fitted with ability."""
module RaterGroupEffects
import BayesianMGMFRM as B
import LogDensityProblems as L
using LinearAlgebra, Statistics, Serialization, JSON3
const RI=B.Experimental.RaterItemInteractions
const N=B.Experimental.JointRatings.Numerics
const S=B.Experimental.JointRatings.S

"""
    Prior(; person_sd, group_mean_sd, item_sd, rater_sd, step_sd,
            interaction_logmean, interaction_logsd)

Explicit normal priors on white coordinates. `person_sd` is each person's
conditional residual SD within a finite cohort; `group_mean_sd` is the SD of
independent cohort means. `log(tau)` is normal with the last two parameters;
tau is each double-centered rater-by-group cell's conditional marginal SD.
No scientific default prior is supplied. See the group-effects guide.
"""
struct Prior
    person_sd::Float64
    group_mean_sd::Float64
    item_sd::Float64
    rater_sd::Float64
    step_sd::Float64
    interaction_logmean::Float64
    interaction_logsd::Float64
    function Prior(;person_sd,group_mean_sd,item_sd,rater_sd,step_sd,interaction_logmean,interaction_logsd)
        xs=(person_sd,group_mean_sd,item_sd,rater_sd,step_sd,interaction_logmean,interaction_logsd)
        all(x->x isa Real && !(x isa Bool) && isfinite(x),xs) || throw(ArgumentError("Prior parameters must be finite real numbers."))
        all(>(0),(xs[1],xs[2],xs[3],xs[4],xs[5],xs[7])) || throw(ArgumentError("Prior SDs must be positive."))
        ys=Float64.(xs)
        all(isfinite,ys) && all(>(0),(ys[1],ys[2],ys[3],ys[4],ys[5],ys[7])) || throw(ArgumentError("Prior parameters must be representable as Float64."))
        new(ys...)
    end
end
_prior(p::Prior)=(; (n=>getfield(p,n) for n in fieldnames(Prior))...)
function _table(d)
    (;person=deepcopy(d.person_levels[d.person]),item=deepcopy(d.item_levels[d.item]),
        rater=deepcopy(d.rater_levels[d.rater]),score=copy(d.score),
        group=deepcopy(d.optional_levels[:group][d.optional[:group]]))
end

# Eliminate person intercepts from item + within-group rater dummy columns.
# This Schur complement has no dense observation-by-person matrix.
function _allocation(d,person_group)
    P,R,I,G=length(d.person_levels),length(d.rater_levels),length(d.item_levels),length(d.optional_levels[:group])
    D=I-1+G*(R-1);gram=zeros(D,D);nc=zeros(Int,P)
    sums=[Dict{Int,Int}() for _ in 1:P]
    counts=zeros(Int,R,G);people=[Set{Int}() for _ in 1:R,_ in 1:G]
    for n in 1:d.n
        p,r,i,g=d.person[n],d.rater[n],d.item[n],person_group[d.person[n]]
        nc[p]+=1;counts[r,g]+=1;push!(people[r,g],p)
        cols=Int[]
        i>1 && push!(cols,i-1)
        r>1 && push!(cols,I-1+(g-1)*(R-1)+r-1)
        for a in cols
            sums[p][a]=get(sums[p],a,0)+1
            for b in cols;gram[a,b]+=1;end
        end
    end
    for p in 1:P,(a,va) in sums[p],(b,vb) in sums[p]
        gram[a,b]-=va*vb/nc[p]
    end
    ev=eigvals(Symmetric(gram));tol=max(d.n,D)*eps(Float64)*max(maximum(abs,ev),1.)*10
    rank=count(>(tol),ev)
    (;counts,people=length.(people),group_sizes=[count(==(g),person_group) for g in 1:G],
        location_rank=P+rank,location_columns=P+D,rank_tolerance=tol,
        minimum_conditional_eigenvalue=minimum(ev),complete_cells=all(>(0),counts),identified=rank==D)
end

struct Target
    data::B.FacetData
    prior::Prior
    blocks::NamedTuple
    group_people::Vector{Vector{Int}}
    residual_blocks::Vector{UnitRange{Int}}
    item_basis::Matrix{Float64}
    rater_basis::Matrix{Float64}
    group_basis::Matrix{Float64}
    step_basis::Matrix{Float64}
    interaction_normalization::Float64
    allocation::NamedTuple
end

"""
    model(data::FacetData; prior::Prior)

Prepare a unit-slope item-step PCM with observed-group rater severity. Supply
`group` to `FacetData`; each person must belong to one group. Requires at least
two persons per group, two groups, raters and items, all rater/group cells, and
full conditional location rank. Missing individual ratings and unequal counts
are allowed. Item/step invariance across groups is an assumption, not a test.
Other optional facets are rejected. Construction performs no estimation.
"""
function model(data::B.FacetData;prior::Prior)
    Set(keys(data.optional))==Set([:group]) || throw(ArgumentError("Supply only the group optional facet; other facets are not fitted by this model."))
    d=B.FacetData(_table(data);person=:person,item=:item,rater=:rater,score=:score,group=:group,category_levels=copy(data.category_levels))
    P,R,I,K,G=length(d.person_levels),length(d.rater_levels),length(d.item_levels),length(d.category_levels),length(d.optional_levels[:group])
    min(R,I,G)>=2 || throw(ArgumentError("Requires at least two raters, items and observed groups."))
    pg=zeros(Int,P)
    for n in 1:d.n
        p,g=d.person[n],d.optional[:group][n]
        pg[p] in (0,g) || throw(ArgumentError("Each person must belong to exactly one observed group."))
        pg[p]=g
    end
    people=[findall(==(g),pg) for g in 1:G]
    all(x->length(x)>=2,people) || throw(ArgumentError("Each group requires at least two distinct persons."))
    a=_allocation(d,pg)
    a.complete_cells || throw(ArgumentError("Every rater/group cell must be observed; do not impute zero scores."))
    a.identified || throw(ArgumentError("Allocation cannot identify the location effects: rank $(a.location_rank)/$(a.location_columns). Link raters and items within groups; priors do not supply data identification."))
    sizes=(;group_mean=G,person=P-G,item=I-1,rater=R-1,steps=I*(K-2),interaction=(R-1)*(G-1),log_tau=1)
    start=1
    blocks=map(sizes) do n
        ids=start:start+n-1;start+=n;ids
    end
    start=first(blocks.person);rb=UnitRange{Int}[]
    for ps in people
        push!(rb,start:start+length(ps)-2);start+=length(ps)-1
    end
    Target(d,prior,blocks,people,rb,RI._helmert(I),RI._helmert(R),RI._helmert(G),RI._helmert(K-1),sqrt((1-1/R)*(1-1/G)),a)
end

"""Allocation counts and conditional location rank; full rank does not ensure precision or item invariance."""
design(t::Target)=(;deepcopy(t.allocation)...,raters=deepcopy(t.data.rater_levels),
    groups=deepcopy(t.data.optional_levels[:group]),reference=:equal_weight_rater_group_grid,
    warning="Relative panel effects only. A common penalty from all raters is inseparable from group ability. Full location rank is not adequate precision or model fit.")
L.dimension(t::Target)=last(t.blocks.log_tau)
L.capabilities(::Type{Target})=L.LogDensityOrder{1}()
function B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("Invalid rater-group coordinate vector."))
    nothing
end
function initial(t::Target)
    q=zeros(L.dimension(t));q[end]=t.prior.interaction_logmean;q
end
function coordinates(t::Target,q)
    b,p=t.blocks,t.prior;d=t.data
    I,R,K,G=length(d.item_levels),length(d.rater_levels),length(d.category_levels),length(t.group_people)
    mu=p.group_mean_sd.*q[b.group_mean];theta=similar(mu,length(d.person_levels))
    for g in 1:G
        ps=t.group_people[g]
        theta[ps].=mu[g].+(p.person_sd/sqrt(1-1/length(ps))).*N._zero_sum(q[t.residual_blocks[g]])
    end
    tau=exp(q[end])
    (;person=theta,group_mean=mu,item=p.item_sd.*(t.item_basis*q[b.item]),
        rater=p.rater_sd.*(t.rater_basis*q[b.rater]),
        steps=p.step_sd.*permutedims(t.step_basis*reshape(q[b.steps],K-2,I)),
        interaction=(tau/t.interaction_normalization).*(t.rater_basis*reshape(q[b.interaction],R-1,G-1)*t.group_basis'),tau)
end
function _weights!(a,v,d,n)
    i,r,g=d.item[n],d.rater[n],d.optional[:group][n]
    eta=v.person[d.person[n]]-v.item[i]-v.rater[r]-v.interaction[r,g]
    a[1]=zero(eta)
    for k in 2:length(a);a[k]=a[k-1]+eta-v.steps[i,k-1];end
    m=maximum(a);m+log(sum(x->exp(x-m),a))
end
function _logprior(t,q)
    z=(q[end]-t.prior.interaction_logmean)/t.prior.interaction_logsd
    -(sum(abs2,view(q,1:length(q)-1))+z^2)/2-length(q)*log(2pi)/2-log(t.prior.interaction_logsd)
end
function category_logprobs(t::Target,q)
    v=coordinates(t,q);d=t.data;out=Matrix{eltype(v.person)}(undef,d.n,length(d.category_levels))
    for n in 1:d.n
        a=view(out,n,:);c=_weights!(a,v,d,n);a.-=c
    end
    out
end
function L.logdensity(t::Target,q)
    length(q)==L.dimension(t) || throw(DimensionMismatch("rater-group coordinates"))
    all(isfinite,q) && isfinite(exp(q[end])) || return oftype(float(q[1]),-Inf)
    v=coordinates(t,q);d=t.data;a=similar(v.person,length(d.category_levels));lp=_logprior(t,q)
    for n in 1:d.n
        c=_weights!(a,v,d,n);lp+=a[d.category[n]]-c
    end
    isfinite(lp) ? lp : oftype(lp,-Inf)
end
function L.logdensity_and_gradient(t::Target,q)
    length(q)==L.dimension(t) || throw(DimensionMismatch("rater-group coordinates"))
    Z=promote_type(Float64,eltype(q));rejected()=(-Z(Inf),fill(Z(NaN),length(q)))
    all(isfinite,q) && isfinite(exp(q[end])) || return rejected()
    v=coordinates(t,q);d=t.data;b=t.blocks;p=t.prior;K=length(d.category_levels)
    gp=zeros(Z,length(v.person));gi=zeros(Z,length(v.item));gr=zeros(Z,length(v.rater))
    gs=zeros(Z,size(v.steps));gx=zeros(Z,size(v.interaction));a=zeros(Z,K);lp=_logprior(t,q)
    for n in 1:d.n
        c=_weights!(a,v,d,n);y=d.category[n];lp+=a[y]-c
        a.=exp.(a.-c);de=(y-1)-sum((k-1)*a[k] for k in 1:K)
        i,r,g=d.item[n],d.rater[n],d.optional[:group][n]
        gp[d.person[n]]+=de;gi[i]-=de;gr[r]-=de;gx[r,g]-=de
        tail=zero(Z)
        for h in K-1:-1:1
            tail+=a[h+1];gs[i,h]+=tail-(y>h)
        end
    end
    isfinite(lp) || return rejected()
    grad=-Z.(q);grad[end]=-(q[end]-p.interaction_logmean)/p.interaction_logsd^2
    for (g,ps) in enumerate(t.group_people)
        grad[b.group_mean[g]]+=p.group_mean_sd*sum(gp[ps])
        S._helmert_pullback!(grad,t.residual_blocks[g],gp[ps],p.person_sd/sqrt(1-1/length(ps)))
    end
    S._helmert_pullback!(grad,b.item,gi,p.item_sd)
    S._helmert_pullback!(grad,b.rater,gr,p.rater_sd)
    grad[b.steps].+=p.step_sd.*vec(t.step_basis'*permutedims(gs))
    grad[b.interaction].+=(v.tau/t.interaction_normalization).*vec(t.rater_basis'*gx*t.group_basis)
    grad[end]+=sum(gx.*v.interaction)
    all(isfinite,grad) ? (lp,grad) : rejected()
end

const SCHEMA="bayesianmgmfrm.rater_group_effect_samples.v1"
const SCOPE=(;family=:scalar_unit_slope_item_step_pcm,interaction=:rater_group,
    reference=:equal_weight_full_grid,acceptance=:experimental_engineering_only)
"""Machine-readable scope of the experimental fitted-interaction workflow."""
contract()=(;SCOPE...,backend=:advancedhmc,
    allocation=:complete_rater_group_cells_full_location_rank,prior=:explicit,
    operations=(:model,:design,:target_identity,:fit,:report,:contrast,:category_report,:category_predictive_check,:save_result,:load_result,:save_report),
    scientific_acceptance=false)
_target_record(t)=(;table=_table(t.data),categories=copy(t.data.category_levels),prior=_prior(t.prior))
"""Fingerprint the model's data, categories and prior to check a saved result's target."""
target_identity(t::Target)=B._cache_hash(_target_record(t))
function _restore_target(record)
    keys(record)==(:table,:categories,:prior) || throw(ArgumentError("Unknown interaction target record."))
    d=B.FacetData(record.table;person=:person,item=:item,rater=:rater,score=:score,group=:group,category_levels=record.categories)
    model(d;prior=Prior(;record.prior...))
end

"""Fit with Julia NUTS; explicit counts and seed, full sampler and warmup telemetry."""
function fit(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept=.9,max_depth::Int=10,step_size=.03,init_jitter=.1,
        progress::Union{Bool,B.SamplingProgress}=false,chain_execution::Symbol=:serial,max_parallel_chains::Int=chains)
    t=_restore_target(_target_record(target))
    run=B._run_generalized_candidate_advancedhmc(t,initial(t);ndraws,warmup,chains,seed,
        target_accept,max_depth,step_size,init_jitter,ad_backend=:analytic,record_warmup=true,
        progress,chain_execution,max_parallel_chains)
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
"""Save a computed JSON report, preserving nonfinite warnings; this is not a draw interchange."""
function save_report(path,report)
    ispath(path) && throw(ArgumentError("Preserve existing report: $path"))
    open(path,"w") do io
        JSON3.write(io,(;schema="bayesianmgmfrm.rater_group_effect_report.v1",data=RI._jsonsafe(report)))
    end
    path
end

include("rater_group_reports.jl")
include("rater_group_categories.jl")
include("rater_group_predictive.jl")
end
