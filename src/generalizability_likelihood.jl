# Gaussian random effects are integrated exactly. ML profiles the score means;
# REML adds log|X'V^-1 X|, with the same score-specific intercept design.
const LIKELIHOOD_SCHEMA = "bayesianmgmfrm.generalizability_likelihood_report.v1"
include("generalizability_exact.jl")
include("generalizability_region.jl")
struct LikelihoodFit
    target::Target
    record::NamedTuple
end
struct LikelihoodReport
    record::NamedTuple
end

function B.fit(t::Target; method::Symbol=:nuts, kwargs...)
    if method===:nuts
        t.record.prior===:none && throw(ArgumentError("NUTS requires explicit priors"))
        return _fit_nuts(t;kwargs...)
    end
    method in (:ml,:reml) || throw(ArgumentError("G-theory uses :ml, :reml or :nuts; ordinal :jmle/:mmle are different estimators"))
    t.record.prior===:none || throw(ArgumentError("ML/REML requires explicit prior=:none; priors are never silently ignored"))
    fit_likelihood(t;method,kwargs...)
end

function likelihood_data(t)
    N,C=size(t.scores)
    center=vec(mean(t.scores;dims=1)); scales=vec(std(t.scores;dims=1))
    all(s->isfinite(s)&&s>0,scales) || throw(ArgumentError("each score needs positive observed variance"))
    y=vec((t.scores .- center')./scales')
    kernels=[Float64.(b.index .== b.index') for b in t.components]
    X=kron(Matrix{Float64}(I,C,C),ones(N,1))
    (;N,C,K=length(kernels),center,scales,y,kernels,X)
end
function likelihood_factors(x,C,K)
    length(x)==K*C*(C+1)÷2 || throw(DimensionMismatch("wrong covariance coordinate count"))
    cursor=0
    [begin
        F=zeros(eltype(x),C,C)
        for j in 1:C,i in j:C
            cursor+=1
            F[i,j]=(k==K && i==j) ? exp(x[cursor]) : x[cursor]
        end
        F
    end for k in 1:K]
end
function likelihood_coordinates(factors)
    K=length(factors);C=size(first(factors),1)
    [k==K && i==j ? log(F[i,j]) : F[i,j] for (k,F) in enumerate(factors) for j in 1:C for i in j:C]
end
function likelihood_evaluate(d,x,method; gradient=true)
    factors=likelihood_factors(x,d.C,d.K)
    all(F->all(isfinite,F),factors) && all(>(0),diag(last(factors))) || throw(ArgumentError("unrepresentable covariance factor"))
    covariances=[F*F' for F in factors]
    V=sum(kron(S,A) for (S,A) in zip(covariances,d.kernels))
    ch=cholesky(Symmetric(V))
    vx=ch\d.X; vy=ch\d.y
    info=cholesky(Symmetric(d.X'*vx));mu=info\(d.X'*vy)
    residual=d.y-d.X*mu;alpha=ch\residual
    reml=method===:reml;n=d.N*d.C
    value=(logdet(ch)+dot(residual,alpha)+(n-reml*d.C)*log(2pi)+(reml ? logdet(info) : 0))/2+
        (d.N-reml)*sum(log,d.scales)
    gradient || return (;value,mu,covariances,mean_covariance=inv(info))
    P=inv(ch)
    reml && (P-=vx*(info\vx'))
    Q=(P-alpha*alpha')/2
    scores=[begin
        S=zeros(d.C,d.C)
        for a in 1:d.C,b in 1:d.C
            S[a,b]=sum(view(Q,(a-1)*d.N+1:a*d.N,(b-1)*d.N+1:b*d.N).*A)
        end
        (S+S')/2
    end for A in d.kernels]
    g=similar(x);cursor=0
    for (k,(S,F)) in enumerate(zip(scores,factors))
        H=2S*F
        for j in 1:d.C,i in j:d.C
            cursor+=1;g[cursor]=H[i,j]*(k==d.K && i==j ? F[i,j] : 1)
        end
    end
    (;value,gradient=g,mu,covariances,scores,mean_covariance=inv(info))
end
function likelihood_fg!(g,x,d,method)
    try
        e=likelihood_evaluate(d,x,method)
        g.=e.gradient
        isfinite(e.value)&&all(isfinite,g) ? e.value : Inf
    catch err
        err isa Union{PosDefException,SingularException,ArgumentError,OverflowError} || rethrow()
        fill!(g,0.);Inf
    end
end
function likelihood_hessian(x,fg!)
    n=length(x);H=zeros(n,n);a=zeros(n);b=zeros(n)
    for j in 1:n
        h=cbrt(eps(Float64))*max(1.,abs(x[j]));u=copy(x);v=copy(x)
        u[j]+=h;v[j]-=h
        fg!(a,u);fg!(b,v);H[:,j]=(a-b)/(2h)
    end
    (H+H')/2
end
function likelihood_polish(opt,fg!,gtol)
    x=copy(opt.x);g=copy(opt.g);f=opt.f
    for _ in 1:8
        norm(g,Inf)<=gtol && break
        H=likelihood_hessian(x,fg!);ch=cholesky(Symmetric(H);check=false)
        issuccess(ch) || break
        step=-(ch\g);accepted=false;trial=similar(g)
        for j in 0:25
            z=x+step/2.0^j;value=fg!(trial,z)
            if isfinite(value) && (value<f || (value<=f+1e-12 && norm(trial,Inf)<norm(g,Inf)))
                x=z;f=value;g=copy(trial);accepted=true;break
            end
        end
        accepted || break
    end
    (;x,f,g,nit=opt.nit,nfev=opt.nfev)
end
function fit_likelihood(t;method,maxiter::Int=600,gtol::Real=1e-6)
    t=restore_target(t.record)
    t.allocation.passed || throw(ArgumentError(join(t.allocation.reasons," ")))
    maxiter>0 && isfinite(gtol) && 0<gtol<=1e-3 || throw(ArgumentError("maxiter must be positive and 0 < gtol <= .001"))
    d=likelihood_data(t);fg! = (g,x)->likelihood_fg!(g,x,d,method)
    if method===:reml
        centered=[A.-mean(A;dims=1).-mean(A;dims=2).+mean(A) for A in d.kernels]
        gram=[dot(A,B) for A in centered,B in centered];s=sqrt.(diag(gram))
        all(>(0),s) && rank(gram./(s*s'))==d.K || throw(ArgumentError("covariance components are aliased after removing score means (REML)"))
    end
    attempts=NamedTuple[]
    # Positive and zero-effect starts expose stationary factor boundaries.
    for fraction in (.15,.65,0.)
        Fs=[Matrix{Float64}(I,d.C,d.C)*sqrt(k==d.K ? 1-fraction : fraction/(d.K-1)) for k in 1:d.K]
        start=likelihood_coordinates(Fs)
        opt=B.FrequentistMFRM._optimize_lbfgs(fg!,start;maxit=maxiter,gtol=Float64(gtol))
        push!(attempts,likelihood_polish(opt,fg!,Float64(gtol)))
    end
    best=attempts[argmin(getproperty.(attempts,:f))]
    isfinite(best.f) || throw(ArgumentError("no finite likelihood optimum"))
    e=likelihood_evaluate(d,best.x,method)
    # Factor gradients alone vanish at zero variance; also check covariance KKT.
    kkt=maximum(max(0.,-eigmin(Symmetric(S)),norm(S*V,Inf)) for (S,V) in zip(e.scores,e.covariances))
    qualified=norm(e.gradient,Inf)<=max(10gtol,1e-5) && kkt<=max(10gtol,1e-5)
    boundary=[eigmin(Symmetric(V))<=1e-7*max(1.,opnorm(V)) for V in e.covariances]
    H=likelihood_hessian(best.x,fg!);eig=eigvals(Symmetric(H))
    interior=qualified && !any(boundary) && all(isfinite,eig) && minimum(eig)>1e-8*max(1.,maximum(eig))
    ci_cov=interior ? inv(Symmetric(H)) : nothing
    warnings=String[]
    !qualified && push!(warnings,"Likelihood stationarity checks failed; estimates require further optimization.")
    any(boundary) && push!(warnings,"One or more covariance components are on a boundary; Wald intervals are unavailable.")
    !interior && !any(boundary) && push!(warnings,"Observed information is unsuitable for Wald intervals.")
    push!(warnings,"Delta intervals use an asymptotic approximation; finite-sample coverage is not established for those intervals.")
    covariance=[Diagonal(d.scales)*V*Diagonal(d.scales) for V in e.covariances]
    body=(;schema=LIKELIHOOD_SCHEMA,method=String(method),scores=collect(t.record.scores),facets=collect(keys(t.record.facets)),
        nesting=t.record.nesting,components=[(;b.name,b.factors,levels=b.levels) for b in t.components],
        covariance=[vec(V) for V in covariance],means=d.center+d.scales.*e.mu,
        mean_covariance=vec(Diagonal(d.scales)*e.mean_covariance*Diagonal(d.scales)),
        coordinates=best.x,scales=d.scales,coordinate_covariance=ci_cov===nothing ? nothing : vec(Matrix(ci_cov)),
        n_observations=d.N,objective=e.value,balanced_moments=balanced_moments(t,d),anova_moments=anova_moments(t,d),interval_basis=interior ? "observed_information_delta" : "unavailable",
        diagnostics=(;qualified,gradient_max=norm(e.gradient,Inf),covariance_kkt=kkt,boundary,warnings,
            attempts=[(;objective=a.f,gradient_max=norm(a.g,Inf),iterations=a.nit,evaluations=a.nfev) for a in attempts]),
        design=B.design_summary(t),target_identity=B._cache_hash(t.record),producer=source_signature())
    f=LikelihoodFit(t,merge(body,(;content_hash=B._cache_hash(body))))
    checked(f);f
end
function checked(f::LikelihoodFit;full=false,environment=false)
    r=f.record
    r.content_hash==B._cache_hash(Base.structdiff(r,(;content_hash=nothing))) || throw(ArgumentError("likelihood fit checksum mismatch"))
    r.target_identity==B._cache_hash(f.target.record) || throw(ArgumentError("likelihood target changed"))
    environment && r.producer!=source_signature() && throw(ArgumentError("native cache requires producing source and environment; use the portable report"))
    check_likelihood_report(r);f.target
end
function check_likelihood_report(r)
    r.schema==LIKELIHOOD_SCHEMA && r.method in ("ml","reml") || throw(ArgumentError("unknown G-theory likelihood report"))
    C=length(r.scores);K=length(r.components);q=K*C*(C+1)÷2
    C>0 && K==length(r.covariance) && length(r.scales)==C && length(r.coordinates)==q || throw(ArgumentError("invalid likelihood report dimensions"))
    all(x->isfinite(x)&&x>0,r.scales) && all(isfinite,r.coordinates) && isfinite(r.objective) || throw(ArgumentError("invalid likelihood values"))
    for (k,row) in enumerate(r.covariance)
        length(row)==C*C && all(isfinite,row) || throw(ArgumentError("invalid covariance component"))
        V=reshape(collect(row),C,C)
        isapprox(V,V';rtol=1e-10,atol=1e-12) && eigmin(Symmetric(V))>=-1e-10*max(1.,opnorm(V)) || throw(ArgumentError("component must be positive semidefinite"))
        k==K && !isposdef(Symmetric(V)) && throw(ArgumentError("residual covariance must be positive definite"))
    end
    reconstructed=[Diagonal(collect(r.scales))*(F*F')*Diagonal(collect(r.scales)) for F in likelihood_factors(collect(r.coordinates),C,K)]
    all(isapprox(vec(V),collect(row);rtol=1e-9,atol=1e-12) for (V,row) in zip(reconstructed,r.covariance)) || throw(ArgumentError("covariance coordinates disagree with stored estimates"))
    if r.coordinate_covariance!==nothing
        length(r.coordinate_covariance)==q*q && all(isfinite,r.coordinate_covariance) || throw(ArgumentError("invalid information covariance"))
        isposdef(Symmetric(reshape(collect(r.coordinate_covariance),q,q))) || throw(ArgumentError("information covariance is not positive definite"))
    end
    check_balanced_moments(r)
    check_anova_moments(r)
    LikelihoodReport((;pairs(r)...))
end
report(f::LikelihoodFit)=(checked(f);check_likelihood_report(f.record))
B.fit_report(f::LikelihoodFit)=report(f).record
B.fit_report(r::LikelihoodReport)=check_likelihood_report(r.record).record
B.diagnostics(f::LikelihoodFit)=(checked(f);f.record.diagnostics)
B.diagnostics(r::LikelihoodReport)=check_likelihood_report(r.record).record.diagnostics
B.qualify(f::Union{LikelihoodFit,LikelihoodReport})=(;qualified=B.diagnostics(f).qualified,
    warnings=B.diagnostics(f).warnings,scope=:numerical_stationarity)
B.save_fit(path::AbstractString,f::LikelihoodFit)=(checked(f);B._save_serialized_record(path,f;overwrite=false))
function B.save_report(path::AbstractString,r::LikelihoodReport;return_receipt=false)
    check_likelihood_report(r.record);B._SA_MOD._save_atomic_json(path,r.record)
    return_receipt ? (;path=abspath(path),sha256=bytes2hex(sha256(read(path)))) : path
end
B.save_report(path::AbstractString,f::LikelihoodFit;kwargs...)=B.save_report(path,report(f);kwargs...)

function design_moments(covariances,components,counts,w)
    universe=zero(eltype(first(covariances)));relative=zero(universe);absolute=zero(universe)
    for (V,b) in zip(covariances,components)
        factors=Symbol.(b.factors);v=dot(w,V*w)
        if factors==[:person];universe=v;continue;end
        divisor=prod(Float64(counts[f]) for f in factors if f!==:person)
        absolute+=v/divisor
        :person in factors && (relative+=v/divisor)
    end
    [universe/(universe+relative),universe/(universe+absolute),sqrt(relative),sqrt(absolute),universe,absolute]
end
function likelihood_interval(value,gradient,r,interval)
    if r.coordinate_covariance===nothing || !isfinite(value) || !all(isfinite,gradient)
        return (;estimate=value,se=missing,lower=missing,upper=missing,status=:unavailable)
    end
    q=length(gradient);V=reshape(collect(r.coordinate_covariance),q,q)
    variance=dot(gradient,V*gradient)
    variance>=0 || return (;estimate=value,se=missing,lower=missing,upper=missing,status=:unavailable)
    se=sqrt(variance);z=D.quantile(D.Normal(),(1+interval)/2)
    (;estimate=value,se,lower=value-z*se,upper=value+z*se,status=:asymptotic_delta)
end
function B.reliability(f::LikelihoodFit;kwargs...)
    B.reliability(report(f);kwargs...)
end
function B.reliability(rep::LikelihoodReport;counts::NamedTuple,weights=nothing,interval=.95,interval_method=:delta)
    r=check_likelihood_report(rep.record).record;C=length(r.scores);K=length(r.components)
    A.interval_bounds(interval)
    interval_method in (:delta,:exact,:mean_square_region) || throw(ArgumentError("interval_method must be :delta, :exact or :mean_square_region"))
    interval_method===:exact && check_balanced_moments(r)===nothing && throw(ArgumentError("exact intervals require stored mean squares from a complete balanced one-facet design"))
    Set(keys(counts))==Set(Symbol.(r.facets)) && all(n->n isa Integer && !(n isa Bool) && n>0,values(counts)) || throw(ArgumentError("counts must name every random facet with a positive integer"))
    w=weights===nothing ? fill(1/C,C) : Float64.(collect(weights))
    length(w)==C && all(isfinite,w) && any(!iszero,w) || throw(ArgumentError("weights must be finite, nonzero and match scores"))
    Dscale=Diagonal(collect(r.scales));x=collect(r.coordinates)
    targets=[("composite",w);[(string(r.scores[j]),Float64.(1:C .==j)) for j in 1:C]]
    rows=map(targets) do (label,weight)
        transform(z)=design_moments([Dscale*(F*F')*Dscale for F in likelihood_factors(z,C,K)],r.components,counts,weight)
        values=transform(x)
        all(isfinite,values) || throw(ArgumentError("D-study coefficients are undefined or exceeded numeric range"))
        stats=if interval_method===:exact
            exact_design_intervals(r,weight,only(counts),values,interval)
        elseif interval_method===:mean_square_region
            region_design_intervals(mean_square_region(r,weight,interval),r.components,counts,values)
        else
            J=r.coordinate_covariance===nothing ? zeros(6,length(x)) : FD.jacobian(transform,x)
            [likelihood_interval(values[j],view(J,j,:),r,interval) for j in 1:6]
        end
        (;score=label,weights=weight,G=stats[1],Phi=stats[2],relative_sem=stats[3],absolute_sem=stats[4],universe_variance=stats[5],absolute_error_variance=stats[6])
    end
    (;counts,interval,method=r.method,rows,qualification=B.qualify(rep),population=:new_random_facet_levels,
        measurement=:weighted_average,interval_method,interval_basis=interval_method===:mean_square_region ? "simultaneous_mean_square_region" : interval_method===:exact ? "balanced_gaussian_pivots" : r.interval_basis,
        interpretation=interval_method===:mean_square_region ? "Gaussian mean-square region projections protect future plans and metrics jointly for one fixed score/composite, not jointly across different scores or data-selected weights. Coverage is at least the stated level under the complete balanced independent-normal model; intervals can be wide. ML/REML points and original diagnostics are retained; empty regions remain empty." : interval_method===:exact ? "Pointwise exact F intervals for G and chi-square intervals for relative SEM under the balanced Gaussian model and prespecified weights. ML/REML point estimates are unchanged. Empty confidence sets remain empty; no exact Phi or absolute SEM intervals are supplied." :
            "Pointwise asymptotic confidence intervals, not posterior probabilities; unavailable at covariance boundaries. Bounds are not clipped.")
end

"""Score-scale covariance estimates with pointwise intervals (confidence or credible)."""
function component_summary(obj::Union{LikelihoodFit,LikelihoodReport};interval=.95)
    r=obj isa LikelihoodFit ? report(obj).record : check_likelihood_report(obj.record).record
    A.interval_bounds(interval);C=length(r.scores);K=length(r.components);Dscale=Diagonal(collect(r.scales));x=collect(r.coordinates)
    transform(z)=reduce(vcat,[vec(Dscale*(F*F')*Dscale) for F in likelihood_factors(z,C,K)])
    vals=transform(x);J=r.coordinate_covariance===nothing ? zeros(length(vals),length(x)) : FD.jacobian(transform,x)
    rows=[begin
        k=(c-1)*C*C+(b-1)*C+a
        merge((;component=r.components[c].name,score1=string(r.scores[a]),score2=string(r.scores[b])),
            likelihood_interval(vals[k],view(J,k,:),r,interval))
    end for c in 1:K for b in 1:C for a in b:C]
    indices=[(c-1)*C*C+(b-1)*C+a for c in 1:K for b in 1:C for a in b:C]
    q=length(x)
    sampling_covariance=r.coordinate_covariance===nothing ? nothing :
        J[indices,:]*reshape(collect(r.coordinate_covariance),q,q)*J[indices,:]'
    (;rows,interval,interval_kind=:confidence,method=r.method,qualification=B.qualify(obj),sampling_covariance)
end
function component_summary(obj::Union{Fit,Report};interval=.95)
    r=obj isa Fit ? report(obj).record : check_report(obj.record).record
    lo,hi=A.interval_bounds(interval);C=length(r.scores);K=length(r.components)
    rows=[begin
        k=(c-1)*C*C+(b-1)*C+a;vals=[v[k] for v in r.covariance_draws]
        (;component=r.components[c].name,score1=string(r.scores[a]),score2=string(r.scores[b]),
            estimate=mean(vals),se=missing,lower=quantile(vals,lo),upper=quantile(vals,hi),status=:posterior)
    end for c in 1:K for b in 1:C for a in b:C]
    (;rows,interval,interval_kind=:credible,method="nuts",qualification=r.qualification)
end
