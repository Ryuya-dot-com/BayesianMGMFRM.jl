"""Internal normalized joint-category likelihood and analytic scores."""
module AssociationKernel
using BayesianMGMFRM, LinearAlgebra
import LogDensityProblems as L
const B=BayesianMGMFRM
const S=B.Experimental.JointRatings.S

struct Target{T}
    base::T
    events::Vector{NTuple{3,Int}} # representative row, encoded A, encoded C; -1 missing
    lambda_sd::Float64
end

function Target(base,lambda_sd)
    base.sizes[7]==0 || throw(ArgumentError("this finite prototype excludes predictors"))
    S.target_record(base) # Validate canonical input and derived layout before pairing.
    lookup=Dict{String,Int}();events=NTuple{3,Int}[]
    for (n,row) in enumerate(base.data.rows)
        e=get!(lookup,row.rating_event_id,length(events)+1)
        e>length(events) && push!(events,(n,-1,-1))
        c=base.indices.criterion[n]
        old=events[e]
        events[e]=c==1 ? (old[1],base.data.score[n],old[3]) : (old[1],old[2],base.data.score[n])
    end
    return Target(base,events,lambda_sd)
end
L.dimension(t::Target)=L.dimension(t.base)+1
L.capabilities(::Type{<:Target})=L.LogDensityOrder{1}()
initial(t)=vcat(S.initial(t.base),zeros(1))
extra_sd(t)=t.lambda_sd

function coordinates(t,q)
    N=L.dimension(t.base);_,T,R=t.base.sizes
    v=S.coordinates(t.base,view(q,1:N))
    return (;v...,a=ones(eltype(q),2,T),gamma=ones(eltype(q),R,2),lambda=q[end])
end

function category_logits!(a,t,v,n,c)
    ix=t.base.indices
    location=v.a[c,ix.task[n]]*v.theta[c,ix.person[n]]-v.task[c,ix.task[n]]-
        v.rater[ix.rater[n],c]+v.response[c,ix.response_id[n]]
    gamma=v.gamma[ix.rater[n],c];g=ix.threshold_group[c]
    a[1]=0
    for k in 2:length(a);a[k]=a[k-1]+gamma*(location-v.steps[k-1,g]);end
    return a
end

"""Exact joint log likelihood and logit scores, including either singleton margin.
P is overwritten by the normalized joint table; da/db are derivatives wrt a/b.
"""
function pair_terms!(P,da,db,a,b,lambda,ya,yb)
    K=length(a);center=(K-1)/2
    (-1<=ya<K && -1<=yb<K && (ya>=0 || yb>=0)) || throw(ArgumentError("invalid observed pair"))
    for j in 1:K,i in 1:K;P[i,j]=a[i]+b[j]+lambda*(i-1-center)*(j-1-center);end
    all(isfinite,P) || return (-oftype(lambda,Inf),oftype(lambda,NaN))
    m=maximum(P)
    fill!(da,0);fill!(db,0);dlambda=zero(m)
    if ya>=0 && yb>=0
        mobs=P[ya+1,yb+1];zobs=one(m)
        da[ya+1]=one(m);db[yb+1]=one(m)
        dlambda=(ya-center)*(yb-center)
    elseif ya<0
        # A separate margin shift preserves rare observations even when joint masses underflow.
        j=yb+1;mobs=maximum(view(P,:,j));zobs=zero(m)
        for i in 1:K;da[i]=exp(P[i,j]-mobs);zobs+=da[i];end
        for i in 1:K
            da[i]/=zobs;dlambda+=da[i]*(i-1-center)*(yb-center)
        end
        db[j]=one(m)
    else
        i=ya+1;mobs=maximum(view(P,i,:));zobs=zero(m)
        for j in 1:K;db[j]=exp(P[i,j]-mobs);zobs+=db[j];end
        for j in 1:K
            db[j]/=zobs;dlambda+=db[j]*(ya-center)*(j-1-center)
        end
        da[i]=one(m)
    end
    z=zero(m)
    for j in 1:K,i in 1:K
        p=exp(P[i,j]-m);P[i,j]=p;z+=p
    end
    for j in 1:K,i in 1:K
        p=P[i,j]/z;P[i,j]=p
        da[i]-=p;db[j]-=p
        dlambda-=p*(i-1-center)*(j-1-center)
    end
    return (mobs-m+log(zobs)-log(z),dlambda)
end

function evaluate(t,q,with_gradient)
    length(q)==L.dimension(t) || throw(ArgumentError("invalid parameter dimension"))
    Z=promote_type(Float64,eltype(q));reject()=(-Z(Inf),fill(Z(NaN),length(q)))
    all(isfinite,q) || return reject()
    base=t.base;N=L.dimension(base);v=coordinates(t,q)
    all(isfinite,v.a) && all(isfinite,v.gamma) || return reject()
    prior=S.logprior(base,view(q,1:N),v)+sum(B._normal_logpdf(q[i],extra_sd(t)) for i in N+1:length(q))
    isfinite(prior) || return reject()
    return score_coordinates(t,q,v,prior,with_gradient)
end

# Keep the realization of all coordinate arrays visible to Julia's row-loop compiler.
function score_coordinates(t,q,v,prior,with_gradient)
    base=t.base;P,T,R,O,K,G,F=base.sizes;ix=base.indices;b=base.blocks
    N=L.dimension(base);Z=eltype(v.theta)
    grad=zeros(Z,length(q));person=zeros(Z,2,P);task=zeros(Z,2,T)
    rater=zeros(Z,R,2);response=zeros(Z,2,O);steps=zeros(Z,K-1,G)
    a=zeros(Z,K);bb=similar(a);da=similar(a);db=similar(a);joint=zeros(Z,K,K)
    total=zero(Z)
    function accumulate!(n,c,du,logits)
        p=ix.person[n];w=ix.task[n];r=ix.rater[n];o=ix.response_id[n];g=ix.threshold_group[c]
        rawscore=sum((k-1)*du[k] for k in 2:K)
        score=v.gamma[r,c]*rawscore
        person[c,p]+=v.a[c,w]*score;task[c,w]-=score;rater[r,c]-=score;response[c,o]+=score
        tail=zero(Z)
        for k in K:-1:2;tail+=du[k];steps[k-1,g]-=v.gamma[r,c]*tail;end
    end
        for (n,ya,yb) in t.events
            category_logits!(a,t,v,n,1);category_logits!(bb,t,v,n,2)
            lp,dlambda=pair_terms!(joint,da,db,a,bb,v.lambda,ya,yb)
            total+=lp
            if with_gradient
                grad[end]+=dlambda
                accumulate!(n,1,da,a);accumulate!(n,2,db,bb)
            end
        end
    value=prior+total
    isfinite(value) || return (-Z(Inf),fill(Z(NaN),length(q)))
    with_gradient || return (value,grad)
    for i in eachindex(base.mean);grad[i]=-(q[i]-base.mean[i])/base.sd[i]^2;end
    for i in N+1:length(q);grad[i]-=q[i]/extra_sd(t)^2;end
    grad[b.task].+=vec(task)
    for c in 1:2
        block=(first(b.rater_white)+(c-1)*(R-1)):(first(b.rater_white)+c*(R-1)-1)
        S._helmert_pullback!(grad,block,view(rater,:,c),base.prior.rater_sd[c])
    end
    for g in 1:G
        block=(first(b.step_white)+(g-1)*(K-2)):(first(b.step_white)+g*(K-2)-1)
        S._helmert_pullback!(grad,block,view(steps,:,g),base.prior.step_sd[g])
    end
    for (h,block,scores,M) in ((1,b.person_white,person,P),(2,b.response_white,response,O))
        z=q[b.correlation[h]];rho=S.C.stable_tanh(z)
        logdelta=B._log_one_minus_tanh_squared(z);s=exp(logdelta/2);delta=exp(logdelta)
        eta=h==1 ? base.prior.person_lkj_eta : base.prior.response_lkj_eta
        dz=-2eta*rho
        for j in 1:M
            i1=block[2j-1];i2=block[2j];g1=scores[1,j];g2=scores[2,j]
            if h==2
                grad[b.log_response_sd[1]]+=g1*v.response[1,j]
                grad[b.log_response_sd[2]]+=g2*v.response[2,j]
                g1*=v.response_sd[1];g2*=v.response_sd[2]
            end
            grad[i1]+=g1+rho*g2;grad[i2]+=s*g2
            dz+=g2*(delta*q[i1]-rho*s*q[i2])
        end
        grad[b.correlation[h]]=dz
    end
    all(isfinite,grad) || return (-Z(Inf),fill(Z(NaN),length(q)))
    return value,grad
end
L.logdensity(t::Target,q::AbstractVector{<:Real})=first(evaluate(t,q,false))
L.logdensity_and_gradient(t::Target,q::AbstractVector{<:Real})=evaluate(t,q,true)

end
