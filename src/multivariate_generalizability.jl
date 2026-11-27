"""
Bayesian multivariate generalizability analysis of numeric score vectors.
`model` specifies one- or two-facet crossed designs, or a child facet nested in
one parent facet. Components have independent multivariate Gaussian effects,
HalfNormal marginal SD priors and LKJ correlation priors. These are score-scale
covariances; an event covariance alone does not identify psychological halo.
"""
module Generalizability
using LinearAlgebra, Statistics, Random, SHA, Serialization
import Distributions as D
import ForwardDiff as FD
import SpecialFunctions as SF
import LogDensityProblems as L
import BayesianMGMFRM as B
const A=B.AdditiveFacets
const TARGET_SCHEMA="bayesianmgmfrm.multivariate_generalizability_target.v1"
const REPORT_SCHEMA="bayesianmgmfrm.multivariate_generalizability_report.v1"
struct Component
    name::String
    factors::Vector{Symbol}
    index::Vector{Int}
    levels::Vector{Any}
    covariance::UnitRange{Int}
    latent::UnitRange{Int}
end
struct Target
    record::NamedTuple
    scores::Matrix{Float64}
    components::Vector{Component}
    dimension::Int
    allocation::NamedTuple
end
struct Fit
    target::Target
    record::NamedTuple
end
struct Report
    record::NamedTuple
end

"""
    Generalizability.model(table; scores, person, facets, nesting=(;), prior)

Declare numeric score columns and one or two random measurement facets, e.g.
`facets=(rater=:Rater,task=:Task)`. A nested design uses `nesting=(rater=:task,)`;
child IDs are local to their parent. Use `prior=:none` with `fit(...; method=:ml)`
or `:reml`, or supply explicit `prior=(mean=Normal(...),
 sd=truncated(Normal(0,s),0,Inf), correlation=LKJ(length(scores),eta))` for NUTS.
A single score uses `correlation=nothing`.
All criteria must be observed in each row. Duplicate cells must be resolved
explicitly. The highest interaction and measurement residual form one component.
"""
function model(table;scores,person::Symbol,facets::NamedTuple,nesting::NamedTuple=(;),prior)
    cols=Tuple(scores); C=length(cols); roles=collect(keys(facets))
    C>=1 && all(x->x isa Symbol,cols) && allunique(cols) || throw(ArgumentError("scores needs at least one distinct numeric column"))
    1<=length(roles)<=2 && all(x->x isa Symbol,values(facets)) && :person ∉ roles || throw(ArgumentError("declare one or two distinct measurement facets; person is reserved"))
    ids=(person,values(facets)...)
    allunique((ids...,cols...)) || throw(ArgumentError("person, facets and scores must use distinct columns"))
    valid_nesting=isempty(nesting) || (length(roles)==2 && length(nesting)==1 &&
        first(keys(nesting)) in roles && first(values(nesting)) in roles && first(keys(nesting))!==first(values(nesting)))
    valid_nesting || throw(ArgumentError("nesting must map a child facet to its parent"))
    prior_record = if prior === :none
        :none
    else
        prior isa NamedTuple && Set(keys(prior))==Set((:mean,:sd,:correlation)) || throw(ArgumentError("declare mean, sd and correlation priors, or prior=:none for ML/REML"))
        mp=A._normal_parameters(prior.mean,:mean)
        sp=A._parse_scale_or_lognormal(prior.sd,true,:sd)
        sp.kind===:half_normal || throw(ArgumentError("sd requires a zero-centered HalfNormal prior in score units"))
        eta = if C==1
            prior.correlation===nothing || throw(ArgumentError("one score has no correlation parameter; use correlation=nothing"))
            1.0
        else
            prior.correlation isa D.LKJ || throw(ArgumentError("correlation requires LKJ(number_of_scores, eta)"))
            dim,shape=D.params(prior.correlation)
            dim==C && isfinite(shape) && shape>0 || throw(ArgumentError("LKJ dimension must match the score columns"))
            Float64(shape)
        end
        (;mean=mp,sd_scale=sp.logsd,lkj_eta=eta)
    end
    raw=Dict(c=>collect(B._column(table,c)) for c in (ids...,cols...))
    N=length(raw[person]); N>0 || throw(ArgumentError("empty score table"))
    all(v->length(v)==N,values(raw)) || throw(ArgumentError("columns have unequal lengths"))
    all(c->all(A._valid_facet_label,raw[c]),ids) || throw(ArgumentError("IDs must be finite, nonmissing labels"))
    all(c->all(x->x isa Real && !(x isa Bool) && isfinite(x),raw[c]),cols) || throw(ArgumentError("scores must be finite numbers, with all criteria observed"))
    allunique([Tuple(raw[c][i] for c in ids) for i in 1:N]) || throw(ArgumentError("duplicate person/facet cells; do not silently average replications"))
    Y=hcat((Float64.(raw[c]) for c in cols)...)
    all(isfinite,Y) || throw(ArgumentError("scores exceed Float64 numeric range"))
    mapping=merge((;person),facets)
    factors=Vector{Symbol}[]
    if isempty(nesting)
        allroles=[:person;roles]
        for mask in 1:(2^length(allroles)-2)
            push!(factors,[allroles[j] for j in eachindex(allroles) if (mask >> (j-1)) & 1 == 1])
        end
        push!(factors,allroles)
    else
        child=first(keys(nesting));parent=first(values(nesting))
        append!(factors,[[:person],[parent],[parent,child],[:person,parent],[:person,parent,child]])
    end
    cursor=C;components=Component[]
    for (k,ff) in enumerate(factors)
        labels=Any[Tuple(raw[mapping[f]][i] for f in ff) for i in 1:N]
        levels=sort!(unique(labels);by=repr);lookup=Dict(x=>i for (i,x) in enumerate(levels))
        index=[lookup[x] for x in labels]
        residual=k==length(factors)
        !residual && length(levels)<2 && throw(ArgumentError("component $(join(ff, ':')) needs at least two observed levels"))
        nc=C+C*(C-1)÷2;cr=cursor+1:cursor+nc;cursor+=nc
        nz=residual ? 0 : C*length(levels);zr=cursor+1:cursor+nz;cursor+=nz
        push!(components,Component(residual ? "residual" : join(ff,":"),ff,index,levels,cr,zr))
    end
    K=length(components);gram=zeros(K,K)
    for a in 1:K,b in 1:K
        counts=Dict{Tuple{Int,Int},Int}()
        for cell in zip(components[a].index,components[b].index);counts[cell]=get(counts,cell,0)+1;end
        gram[a,b]=sum(x->Float64(x)^2,values(counts))
    end
    norm=sqrt.(diag(gram));gram./=norm*norm'
    rk=rank(gram);reasons=rk==K ? String[] : ["Covariance components are aliased ($rk/$K); add crossing or replication."]
    allocation=(;passed=isempty(reasons),identified=isempty(reasons),covariance_rank=rk,
        covariance_components=getproperty.(components,:name),normalized_covariance_gram=gram,reasons,
        interpretation="Structural covariance screen; posterior precision and Gaussian model adequacy require assessment.")
    record=(;schema=TARGET_SCHEMA,table=raw,scores=cols,person,facets,nesting,
        prior=prior_record)
    Target(record,Y,components,cursor,allocation)
end
function restore_target(r)
    model(r.table;scores=Symbol.(r.scores),person=Symbol(r.person),facets=r.facets,nesting=r.nesting,
        prior=r.prior===:none ? :none : (;mean=D.Normal(r.prior.mean.mean,r.prior.mean.sd),
            sd=D.truncated(D.Normal(0,r.prior.sd_scale),0,Inf),
            correlation=length(r.scores)==1 ? nothing : D.LKJ(length(r.scores),r.prior.lkj_eta)))
end
function factor(t,x)
    C=size(t.scores,2)
    Lc,_,_=A._cholesky_cpc(x,C+1:length(x),C)
    Diagonal(exp.(x[1:C]))*Lc
end
function covariance_prior(t,x)
    C=size(t.scores,2);scale=t.record.prior.sd_scale
    lp=sum(log(2)-log(scale)-log(2pi)/2+u-exp(2u)/(2scale^2) for u in x[1:C])
    k=C
    for i in 2:C,j in 1:i-1
        k+=1;alpha=t.record.prior.lkj_eta+(C-1-j)/2
        lp+=alpha*A._logsech2(x[k])-SF.logbeta(.5,alpha)
    end
    lp
end
function unpack(t,q)
    C=size(t.scores,2);p=t.record.prior.mean
    mu=p.mean .+ p.sd.*q[1:C]
    factors=[factor(t,view(q,b.covariance)) for b in t.components]
    mean=repeat(transpose(mu),size(t.scores,1))
    for (b,F) in zip(t.components[1:end-1],factors[1:end-1])
        z=reshape(view(q,b.latent),length(b.levels),C)
        mean .+= (z*F')[b.index,:]
    end
    (;mu,factors,mean)
end
function logprior(t,q)
    C=size(t.scores,2);lp=-C*log(2pi)/2-sum(abs2,view(q,1:C))/2
    for b in t.components
        lp+=covariance_prior(t,view(q,b.covariance))-length(b.latent)*log(2pi)/2-sum(abs2,view(q,b.latent))/2
    end
    lp
end
function pointwise(t,q)
    u=unpack(t,q);C=size(t.scores,2);F=LowerTriangular(last(u.factors))
    z=F\transpose(t.scores-u.mean)
    vec(-C*log(2pi)/2 .-sum(log,diag(F)).-sum(abs2,z;dims=1)./2)
end
L.dimension(t::Target)=t.dimension
L.capabilities(::Type{Target})=L.LogDensityOrder{1}()
function L.logdensity(t::Target,q)
    length(q)==t.dimension || throw(DimensionMismatch("wrong parameter dimension"))
    all(isfinite,q) || return -Inf
    value=try
        all(F->all(isfinite,F) && all(>(0),diag(F)),unpack(t,q).factors) || return -Inf
        logprior(t,q)+sum(pointwise(t,q))
    catch e
        e isa ArgumentError || e isa SingularException || rethrow()
        return -Inf
    end
    isfinite(value) ? value : -Inf
end
function L.logdensity_and_gradient(t::Target,q::AbstractVector)
    length(q)==t.dimension || throw(DimensionMismatch("wrong parameter dimension"))
    reject()=(-Inf,fill(NaN,length(q)))
    all(isfinite,q) || return reject()
    u=try unpack(t,q) catch e; e isa ArgumentError || rethrow();return reject();end
    all(F->all(isfinite,F) && all(>(0),diag(F)),u.factors) || return reject()
    N,C=size(t.scores);F=LowerTriangular(last(u.factors));z=F\transpose(t.scores-u.mean)
    all(isfinite,z) || return reject()
    gmean=transpose(F'\z);grad=zeros(eltype(gmean),length(q))
    grad[1:C].=t.record.prior.mean.sd.*vec(sum(gmean;dims=1)).-q[1:C]
    for (k,b) in enumerate(t.components)
        if k==length(t.components)
            gf=transpose(gmean)*transpose(z)-N*inv(F')
        else
            latent=reshape(view(q,b.latent),length(b.levels),C)
            ge=zeros(length(b.levels),C)
            for n in 1:N;ge[b.index[n],:].+=gmean[n,:];end
            gf=ge'*latent
            grad[b.latent].=vec(ge*u.factors[k]-latent)
        end
        grad[b.covariance].=FD.gradient(x->sum(factor(t,x).*gf)+covariance_prior(t,x),q[b.covariance])
    end
    lp=logprior(t,q)-N*C*log(2pi)/2-N*sum(log,diag(F))-sum(abs2,z)/2
    isfinite(lp) && all(isfinite,grad) ? (lp,grad) : reject()
end
function initial(t)
    q=zeros(t.dimension);C=size(t.scores,2)
    for b in t.components;q[b.covariance[1:C]].=log(t.record.prior.sd_scale);end
    q
end
function B._check_source_fixture_raw_vector(t::Target,q::AbstractVector)
    length(q)==t.dimension && all(isfinite,q) || throw(ArgumentError("invalid generalizability coordinates"))
    nothing
end
const FIT_SCHEMA="bayesianmgmfrm.multivariate_generalizability_fit.v1"
function source_signature()
    root=pkgdir(B);files=sort!([joinpath(d,n) for (d,_,ns) in walkdir(joinpath(root,"src")) for n in ns if endswith(n,".jl") || endswith(n,".stan")])
    proj=Base.active_project()
    manifest=proj===nothing ? nothing : Base.project_file_manifest_path(proj)
    (;julia=string(VERSION),package=string(Base.pkgversion(B)),
        source=B._cache_hash([(replace(relpath(p,root),'\\'=>'/'),bytes2hex(sha256(read(p)))) for p in files]),
        manifest=(manifest!==nothing && isfile(manifest)) ? bytes2hex(sha256(read(manifest))) : nothing)
end
function checked(f::Fit;full=false,environment=false)
    r=f.record
    r.schema==FIT_SCHEMA && B._cache_hash(Base.structdiff(r,(;content_hash=nothing)))==r.content_hash || throw(ArgumentError("generalizability fit checksum mismatch"))
    B._cache_hash(f.target.record)==r.target_identity && r.target==f.target.record || throw(ArgumentError("generalizability target changed"))
    environment && r.producer!=source_signature() && throw(ArgumentError("native cache requires the producing source and environment; use a portable report across environments"))
    t=restore_target(r.target)
    t.allocation.passed || throw(ArgumentError("saved covariance design is unidentified"))
    if full
        B._check_generalized_sample_run(t,r.run)
        length(r.run.warmup_stats)==r.run.controls.chains*r.run.controls.warmup || throw(ArgumentError("incomplete warmup telemetry"))
    end
    t
end
function _fit_nuts(target::Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept=.9,max_depth::Int=10,step_size=.03,init_jitter=.1,
        metric=:diagonal,progress=false,chain_execution=:serial,max_parallel_chains=chains)
    t=restore_target(target.record)
    t.allocation.passed || throw(ArgumentError(join(t.allocation.reasons," ")))
    run=B._run_generalized_candidate_advancedhmc(t,initial(t);ndraws,warmup,chains,seed,
        target_accept,max_depth,step_size,init_jitter,metric,progress,chain_execution,max_parallel_chains,
        ad_backend=:analytic,record_warmup=true)
    body=(;schema=FIT_SCHEMA,target=t.record,target_identity=B._cache_hash(t.record),run,producer=source_signature())
    f=Fit(t,merge(body,(;content_hash=B._cache_hash(body))))
    checked(f;full=true);f
end
B.validate_design(t::Target)=t.allocation
B.design_summary(t::Target)=(;family=:multivariate_gaussian_generalizability,
    scores=t.record.scores,facets=t.record.facets,nesting=t.record.nesting,
    components=[(;b.name,b.factors,n_levels=length(b.levels)) for b in t.components],
    prior=t.record.prior,allocation=t.allocation,n_observations=size(t.scores,1))
function raw_names(t)
    names=fill("",t.dimension);C=size(t.scores,2)
    names[1:C]=["mean_white[$s]" for s in t.record.scores]
    for b in t.components
        # Correlation coordinates are unconstrained canonical partial correlations.
        names[b.covariance]=vcat(["log_sd[$(b.name),$s]" for s in t.record.scores],
            ["correlation_raw[$(b.name),$i,$j]" for i in 2:C for j in 1:i-1])
        isempty(b.latent) || (names[b.latent]=["white[$(b.name),$(repr(level)),$s]" for s in t.record.scores for level in b.levels])
    end
    names
end
function model_draws(f)
    t=checked(f);C=size(t.scores,2)
    names=vcat(["mean[$s]" for s in t.record.scores],
        ["sd[$(b.name),$s]" for b in t.components for s in t.record.scores],
        ["correlation[$(b.name),$(t.record.scores[i]),$(t.record.scores[j])]" for b in t.components for i in 2:C for j in 1:i-1])
    values=zeros(size(f.record.run.draws,1),length(names))
    for (s,q) in enumerate(eachrow(f.record.run.draws))
        u=unpack(t,q);covs=[F*F' for F in u.factors];sds=[sqrt.(diag(V)) for V in covs]
        values[s,:]=[u.mu;reduce(vcat,sds);[covs[k][i,j]/(sds[k][i]*sds[k][j]) for k in eachindex(covs) for i in 2:C for j in 1:i-1]]
    end
    (;names,values)
end
function B.diagnostics(f::Fit;kind=:mcmc)
    kind===:mcmc || throw(ArgumentError("use predictive_check for Gaussian score diagnostics"))
    t=checked(f);run=f.record.run;m=model_draws(f)
    diagnose(x,n,space)=B._candidate_mcmc_diagnostic_rows(x,n,run.controls.chains;
        parameter_space=space,split_chains=run.split_chains_requested,
        rhat_threshold=run.checked.rhat_threshold,ess_threshold=run.checked.ess_threshold)
    (;raw=diagnose(run.draws,raw_names(t),:white_logsd_cpc),model=diagnose(m.values,m.names,:score_scale),
        sampler=run.sampler_rows,warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend),
        thresholds=(;run.checked...,minimum_chains=4),scientific_acceptance=false)
end
function B.qualify(f::Fit;max_rhat=1.01,min_ess=400.,min_bfmi=.3)
    isfinite(min_bfmi) && min_bfmi>0 || throw(ArgumentError("min_bfmi must be positive"))
    B._qualify_experimental_diagnostics(B.diagnostics(f),f.record.run,
        B._check_diagnostic_thresholds(max_rhat,min_ess),Float64(min_bfmi))
end
function B.posterior_summary(f::Fit;interval=.95)
    m=model_draws(f);lo,hi=A.interval_bounds(interval)
    B._posterior_summary_rows(m.values,m.names;lower=lo,upper=hi,intervals=(interval,),reference=0.,rope=nothing,rope_probability_threshold=.95)
end
B.posterior_mcse(f::Fit;probabilities=(.025,.5,.975))=begin
    m=model_draws(f)
    B._posterior_mcse_rows(m.values,m.names,f.record.run.controls.chains;probabilities,parameter_space=:score_scale)
end
"""Return portable joint covariance draws, labels, sampler diagnostics and provenance."""
function report(f::Fit)
    t=checked(f);r=f.record;C=size(t.scores,2)
    draws=[reduce(vcat,[vec(F*F') for F in unpack(t,q).factors]) for q in eachrow(r.run.draws)]
    Report((;schema=REPORT_SCHEMA,scores=t.record.scores,facets=collect(keys(t.record.facets)),nesting=t.record.nesting,
        components=[(;b.name,b.factors,levels=b.levels) for b in t.components],covariance_draws=draws,
        chain_ids=r.run.chain_ids,iterations=r.run.iterations,chains=r.run.controls.chains,
        diagnostics=B.diagnostics(f),qualification=B.qualify(f),prior=t.record.prior,
        target_identity=r.target_identity,source_sample_hash=r.content_hash,producer=r.producer,
        interpretation="Covariance components describe score dependence under the declared design; they do not by themselves identify a causal halo mechanism."))
end
function check_report(r)
    r.schema==REPORT_SCHEMA || throw(ArgumentError("unknown generalizability report"))
    C=length(r.scores);K=length(r.components);S=length(r.covariance_draws)
    C>=1 && K>=3 && S>0 && length(r.chain_ids)==length(r.iterations)==S || throw(ArgumentError("invalid covariance draw dimensions"))
    B._check_psis_iterations(Int.(r.chain_ids),Int.(r.iterations))
    r.chains isa Integer && r.chains>=1 && S%r.chains==0 &&
        r.chain_ids==repeat(1:r.chains;inner=S÷r.chains) || throw(ArgumentError("joint chain ordering changed"))
    for row in r.covariance_draws
        length(row)==K*C*C && all(isfinite,row) || throw(ArgumentError("invalid covariance draw"))
        for k in 1:K
            V=reshape(collect(row[(k-1)*C*C+1:k*C*C]),C,C)
            isapprox(V,V';atol=1e-12,rtol=1e-12) && isposdef(Symmetric(V)) || throw(ArgumentError("covariance matrix must be symmetric positive definite"))
        end
    end
    Report((;pairs(r)...))
end
function B.reliability(f::Fit;kwargs...)
    B.reliability(report(f);kwargs...)
end
"""
    reliability(report_or_fit; counts, weights=nothing, threshold=.8, interval=.95)

D study for random measurement facets. Counts name every measurement facet;
nested child counts are per parent. Each posterior covariance draw yields G,
Phi, relative/absolute SEM, and P(coefficient >= threshold). Weights retain
supplied units (default equal-score mean); they are never silently normalized.
"""
function B.reliability(rep::Report;counts::NamedTuple,weights=nothing,threshold=.8,interval=.95)
    r=check_report(rep.record).record;C=length(r.scores);K=length(r.components);S=length(r.covariance_draws)
    Set(keys(counts))==Set(Symbol.(r.facets)) && all(n->n isa Integer && !(n isa Bool) && n>0,values(counts)) || throw(ArgumentError("counts must give a positive integer for every random facet; nested child counts are per parent"))
    w=weights===nothing ? fill(1/C,C) : collect(weights)
    length(w)==C && all(x->x isa Real && !(x isa Bool) && isfinite(x),w) && any(!iszero,w) || throw(ArgumentError("weights must be a finite nonzero vector matching the score order"))
    threshold isa Real && !(threshold isa Bool) && 0<threshold<1 || throw(ArgumentError("threshold must lie in (0,1)"))
    lo,hi=A.interval_bounds(interval)
    targets=[("composite",Float64.(w));[(string(r.scores[j]),Float64.(1:C .==j)) for j in 1:C]]
    summarize(x)=begin
        mcse=B._posterior_mcse_rows(reshape(x,:,1),["quantity"],r.chains;probabilities=(lo,hi),parameter_space=:derived)
        (;mean=mean(x),lower=quantile(x,lo),upper=quantile(x,hi),mcse=only(mcse))
    end
    rows=map(targets) do (label,weight)
        weight_scale=maximum(abs,weight)
        isfinite(weight_scale^2) && weight_scale^2>0 || throw(ArgumentError("rescale weights to represent their squared units"))
        unit_weight=weight./weight_scale
        vals=zeros(S,6)
        for (s,draw) in enumerate(r.covariance_draws)
            universe=0.;relative=0.;absolute=0.
            for (k,b) in enumerate(r.components)
                factors=Symbol.(b.factors);V=reshape(collect(draw[(k-1)*C*C+1:k*C*C]),C,C)
                v=dot(unit_weight,V*unit_weight)
                if factors==[:person];universe=v;continue;end
                denominator=prod(Float64(counts[f]) for f in factors if f!==:person)
                isfinite(denominator) || throw(ArgumentError("planned counts exceed numeric range"))
                v/=denominator
                absolute+=v
                :person in factors && (relative+=v)
            end
            vals[s,:]=[universe/(universe+relative),universe/(universe+absolute),
                sqrt(relative)*weight_scale,sqrt(absolute)*weight_scale,
                universe*weight_scale^2,absolute*weight_scale^2]
        end
        all(isfinite,vals) || throw(ArgumentError("D-study projection exceeded numeric range; rescale scores or weights"))
        G=vals[:,1];Phi=vals[:,2]
        probability(x)=begin
            indicators=Float64.(x.>=threshold)
            precision=only(B._posterior_mcse_rows(reshape(indicators,:,1),["threshold_probability"],r.chains;
                probabilities=(),parameter_space=:derived))
            (;estimate=mean(indicators),precision,
                status=allequal(indicators) ? :constant_indicator_precision_unresolved : :estimated)
        end
        (;score=label,weights=weight,G=summarize(G),Phi=summarize(Phi),
            relative_sem=summarize(vals[:,3]),absolute_sem=summarize(vals[:,4]),
            universe_variance=summarize(vals[:,5]),absolute_error_variance=summarize(vals[:,6]),
            probability_G_at_least=probability(G),probability_Phi_at_least=probability(Phi))
    end
    (;counts,threshold,interval,rows,qualification=r.qualification,source_sample_hash=r.source_sample_hash,
        population=:new_random_facet_levels,measurement=:weighted_average,
        interpretation="Posterior probabilities are conditional on the Gaussian component model and declared priors; MCSE describes computation, not data uncertainty.")
end
function B.save_fit(path::AbstractString,f::Fit)
    checked(f;full=true)
    B._save_serialized_record(path,f;overwrite=false)
end
function B.save_report(path::AbstractString,rep::Report;return_receipt::Bool=false)
    check_report(rep.record);B._SA_MOD._save_atomic_json(path,rep.record)
    return_receipt ? (;path=abspath(path),sha256=bytes2hex(sha256(read(path)))) : path
end
B.save_report(path::AbstractString,f::Fit;kwargs...)=B.save_report(path,report(f);kwargs...)

function B.prior_draw(t::Target;seed)
    rng=MersenneTwister(seed);q=randn(rng,t.dimension);C=size(t.scores,2)
    for b in t.components
        x=view(q,b.covariance)
        x[1:C].=log.(rand(rng,D.truncated(D.Normal(0,t.record.prior.sd_scale),0,Inf),C))
        ch=C==1 ? ones(1,1) : cholesky(rand(rng,D.LKJ(C,t.record.prior.lkj_eta))).L;k=C
        for i in 2:C
            remainder=1.
            for j in 1:i-1
                rho=ch[i,j]/sqrt(remainder);k+=1;x[k]=atanh(rho)
                remainder*=1-rho^2
            end
        end
    end
    all(isfinite,q) || throw(ArgumentError("prior draw reached an unrepresentable boundary"))
    q
end
function B.simulate(t::Target,q::AbstractVector;seed)
    u=unpack(t,q);y=u.mean+randn(MersenneTwister(seed),size(t.scores))*last(u.factors)'
    table=deepcopy(t.record.table)
    for (j,col) in enumerate(t.record.scores);table[col]=y[:,j];end
    (;table,parameters=copy(q),seed)
end
function B.predictive_check(f::Fit;seed,max_draws::Int=200,interval=.95)
    t=checked(f);lo,hi=A.interval_bounds(interval)
    max_draws>0 || throw(ArgumentError("max_draws must be positive"))
    run=f.record.run;idx=unique(round.(Int,range(1,size(run.draws,1);length=min(max_draws,size(run.draws,1)))))
    rng=MersenneTwister(seed);C=size(t.scores,2)
    labels=vcat(["mean[$s]" for s in t.record.scores],["variance[$s]" for s in t.record.scores],
        ["covariance[$(t.record.scores[i]),$(t.record.scores[j])]" for i in 2:C for j in 1:i-1])
    stats(y)=vcat(vec(mean(y;dims=1)),vec(var(y;dims=1)),[cov(view(y,:,i),view(y,:,j)) for i in 2:C for j in 1:i-1])
    obs=stats(t.scores);rep=zeros(length(idx),length(labels))
    for (j,s) in enumerate(idx)
        u=unpack(t,view(run.draws,s,:))
        rep[j,:]=stats(u.mean+randn(rng,size(t.scores))*last(u.factors)')
    end
    (;rows=[(;statistic=labels[j],observed=obs[j],replicated_mean=mean(rep[:,j]),
        replicated_lower=quantile(rep[:,j],lo),replicated_upper=quantile(rep[:,j],hi),
        posterior_predictive_tail_probability=mean(rep[:,j].>=obs[j])) for j in eachindex(labels)],
        conditioning=:observed_person_and_facet_levels,seed,draw_indices=idx,interval,
        qualification=B.qualify(f),source_sample_hash=f.record.content_hash)
end
include("generalizability_likelihood.jl")
include("generalizability_plot.jl")
end
