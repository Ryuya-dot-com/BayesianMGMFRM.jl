"""Scalar RW1 target and exact allocation checks; no sampling or generation."""
module RaterDriftCandidate
import LogDensityProblems as L

struct Target
    P::Int
    R::Int
    K::Int
    person::Vector{Int}
    rater::Vector{Int}
    time::Vector{Int}
    score::Vector{Int}
    event::Vector{String}
    person_labels::Vector{String}
    rater_labels::Vector{String}
    time_ticks::Vector{Int}
    time_labels::Vector{String}
    time_unit::String
    mu_sigma::Float64
    parameterization::Symbol
    static::Bool
end

integer(x)=x isa Integer && !(x isa Bool)
function labels(x,n)
    length(x)==n && all(a->a isa AbstractString && !isempty(strip(a)),x) &&
        length(unique(x))==n || throw(ArgumentError("labels must be distinct nonempty strings"))
    String.(x)
end

"""Explicit full grid; time contains bin indices, score contains 0-based categories.
Repeated scoring events require distinct event IDs. Confounding is reported by
design_review, not removed with hidden constraints or judged from proper priors.
"""
function Target(;P,R,K,person,rater,time,score,event,person_labels,rater_labels,
                time_ticks,time_labels,time_unit,mu_sigma,parameterization=:noncentered,static=false)
    all(integer,(P,R,K)) && P>=1 && R>=1 && K>=2 || throw(ArgumentError("invalid counts"))
    T=length(time_ticks)
    T>=2 && all(integer,time_ticks) && all(BigInt(time_ticks[i+1])-time_ticks[i]==1 for i in 1:T-1) ||
        throw(ArgumentError("declare the full regular grid, including empty bins"))
    all(typemin(Int)<=x<=typemax(Int) for x in time_ticks) || throw(ArgumentError("time ticks out of range"))
    time_unit isa AbstractString && !isempty(strip(time_unit)) || throw(ArgumentError("time unit is required"))
    mu_sigma isa Real && !(mu_sigma isa Bool) && isfinite(mu_sigma) && isfinite(Float64(mu_sigma)) ||
        throw(ArgumentError("explicit finite log-innovation prior mean is required"))
    parameterization in (:centered,:noncentered) && static isa Bool || throw(ArgumentError("invalid variant"))
    static && parameterization!=:centered && throw(ArgumentError("static target uses centered severity only"))
    n=length(score)
    n>0 && all(length(v)==n for v in (person,rater,time)) || throw(ArgumentError("empty or unequal row lengths"))
    for (v,lo,hi) in ((person,1,P),(rater,1,R),(time,1,T),(score,0,K-1))
        all(x->integer(x) && lo<=x<=hi,v) || throw(ArgumentError("invalid row index or category"))
    end
    length(unique(person))==P && length(unique(rater))==R || throw(ArgumentError("each performance and judge must be observed"))
    Target(P,R,K,Int.(person),Int.(rater),Int.(time),Int.(score),labels(event,n),
        labels(person_labels,P),labels(rater_labels,R),Int.(time_ticks),labels(time_labels,T),
        String(time_unit),Float64(mu_sigma),parameterization,static)
end

L.dimension(t::Target)=t.P+t.R*(t.static ? 1 : length(t.time_ticks))+t.R*(t.K-2)+(!t.static)*t.R
L.capabilities(::Type{Target})=L.LogDensityOrder{0}()
normal(x,mu=0,sd=1)=-log(2pi)/2-log(sd)-((x-mu)/sd)^2/2

function coordinates(t::Target,q::AbstractVector{<:Real})
    length(q)==L.dimension(t) && all(isfinite,q) || throw(ArgumentError("invalid raw parameter vector"))
    T=length(t.time_ticks); nt=t.static ? 1 : T
    b=t.P+t.R*nt; c=b+t.R*(t.K-2)
    theta=view(q,1:t.P)
    raw_state=reshape(view(q,t.P+1:b),t.R,nt)
    free=reshape(view(q,b+1:c),t.R,t.K-2)
    steps=hcat(free,-sum(free;dims=2))
    lambda=view(q,c+1:length(q)); sigma=exp.(lambda)
    all(x->isfinite(x) && x>0,sigma) || throw(DomainError(lambda,"innovation SD overflow/underflow"))
    severity=t.static ? repeat(raw_state,1,T) : copy(raw_state)
    if !t.static && t.parameterization==:noncentered
        for j in 2:T, r in 1:t.R
            severity[r,j]=severity[r,j-1]+sigma[r]*raw_state[r,j]
        end
    end
    all(isfinite,severity) && all(isfinite,steps) || throw(DomainError(q,"nonfinite derived coordinates"))
    (;theta,raw_state,free,steps,lambda,sigma,severity)
end

function logprior(t::Target,q::AbstractVector{<:Real})
    s=coordinates(t,q)
    lp=sum(normal,s.theta)
    # Normalized density in the K-2 source free-step coordinates, including K=2.
    lp+=t.R*(-(t.K-2)*log(2pi)/2+log(t.K-1)/2)-sum(abs2,s.steps)/2
    if t.static || t.parameterization==:noncentered
        lp+=sum(normal,s.raw_state)
    else
        lp+=sum(normal,s.severity[:,1])
        for j in 2:length(t.time_ticks), r in 1:t.R
            lp+=normal(s.severity[r,j],s.severity[r,j-1],s.sigma[r])
        end
    end
    lp+=sum((normal(x,t.mu_sigma) for x in s.lambda);init=zero(q[1]))
    isfinite(lp) || throw(DomainError(q,"nonfinite full prior"))
    lp
end

function category_logprobs(t::Target,q::AbstractVector{<:Real})
    s=coordinates(t,q); out=zeros(eltype(q),length(t.score),t.K)
    for n in eachindex(t.score)
        eta=s.theta[t.person[n]]-s.severity[t.rater[n],t.time[n]]
        for k in 2:t.K
            out[n,k]=out[n,k-1]+1.7*(eta-s.steps[t.rater[n],k-1])
        end
        row=view(out,n,:); m=maximum(row)
        row .-= m+log(sum(exp(x-m) for x in row))
    end
    all(isfinite,out) || throw(DomainError(q,"nonfinite category probabilities"))
    out
end

function loglikelihood(t::Target,q::AbstractVector{<:Real})
    probs=category_logprobs(t,q)
    sum(probs[n,t.score[n]+1] for n in eachindex(t.score))
end
L.logdensity(t::Target,q::AbstractVector{<:Real})=logprior(t,q)+loglikelihood(t,q)

# Exact elimination is for bounded preflight allocations, never inside a density call.
function exact_rank(A)
    a=Rational{BigInt}.(A); pivot=0
    for col in axes(a,2)
        found=findfirst(i->a[i,col]!=0,pivot+1:size(a,1))
        isnothing(found) && continue
        j=pivot+found; pivot+=1
        a[pivot,:],a[j,:]=copy(a[j,:]),copy(a[pivot,:])
        a[pivot,:]./=a[pivot,col]
        for i in pivot+1:size(a,1)
            a[i,:].-=a[i,col].*a[pivot,:]
        end
        pivot==size(a,1) && break
    end
    pivot
end

"""Likelihood rank and each judge's baseline contrast, separately from priors.
An unrated state is process-only even if the proper posterior is computable.
This exact small-design check is not a sample-size or precision assessment.
"""
function design_review(t::Target;reference=1)
    T=length(t.time_ticks)
    integer(reference) && 1<=reference<=T || throw(ArgumentError("invalid reference bin"))
    nt=t.static ? 1 : T; b=t.P+t.R*nt; ncols=b+t.R*(t.K-2)
    A=zeros(Int,length(t.score)*(t.K-1),ncols)
    rated=falses(t.R,T)
    for n in eachindex(t.score)
        r=t.rater[n]; j=t.static ? 1 : t.time[n]; rated[r,t.time[n]]=true
        for k in 1:t.K-1
            row=(n-1)*(t.K-1)+k
            A[row,t.person[n]]=1; A[row,t.P+(j-1)*t.R+r]=-1
            if k<t.K-1
                A[row,b+(k-1)*t.R+r]=-1
            else
                for h in 1:t.K-2; A[row,b+(h-1)*t.R+r]=1; end
            end
        end
    end
    rank=exact_rank(A); status=fill("reference",t.R,T)
    for j in 1:T, r in 1:t.R
        if t.static
            status[r,j]="static_constraint"
        elseif !rated[r,j] || !rated[r,reference]
            status[r,j]="process_only_endpoint"
        elseif j!=reference
            c=zeros(Int,1,ncols)
            c[1,t.P+(j-1)*t.R+r]+=1; c[1,t.P+(reference-1)*t.R+r]-=1
            status[r,j]=exact_rank(vcat(A,c))==rank ? "linked" : "data_confounded"
        end
    end
    (;rank,coordinates=ncols,rank_deficiency=ncols-rank,reference=t.time_labels[reference],
      time_labels=copy(t.time_labels),rater_labels=copy(t.rater_labels),rated,status)
end

stan_data(t::Target)=(;P=t.P,R=t.R,T=length(t.time_ticks),K=t.K,N=length(t.score),
    person=t.person,rater=t.rater,time=t.time,score=t.score,mu_sigma=t.mu_sigma,
    noncentered=Int(t.parameterization==:noncentered),is_static=Int(t.static))
end
