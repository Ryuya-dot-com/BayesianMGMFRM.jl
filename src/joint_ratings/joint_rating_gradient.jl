# Exact PCM score followed by the noncentered correlation/Helmert chain rule.
# Keep the canonical density and target record unchanged.
function _helmert_pullback!(out, block, g, scale)
    prefix=zero(eltype(g))
    for j in eachindex(block)
        prefix+=g[j]
        out[block[j]]+=scale*(prefix-j*g[j+1])/sqrt(j*(j+1))
    end
end

function L.logdensity_and_gradient(t::Target,q::AbstractVector{<:Real})
    length(q)==L.dimension(t) || throw(ArgumentError("invalid parameter dimension"))
    Z=promote_type(Float64,eltype(q))
    all(isfinite,q) || return (-Z(Inf),fill(Z(NaN),length(q)))
    # Specialize the row loop on the realized coordinate matrices, including
    # variable-sized hcat outputs, without changing the canonical transforms.
    return _coordinate_gradient(t,q,coordinates(t,q))
end

function _coordinate_gradient(t,q,v)
    Z=promote_type(Float64,eltype(q))
    rejected()=(-Z(Inf),fill(Z(NaN),length(q)))
    prior=logprior(t,q,v)
    isfinite(prior) || return rejected()
    P,T,R,O,K,G,F=t.sizes;b=t.blocks;ix=t.indices
    grad=zeros(Z,length(q))
    for i in eachindex(t.mean);grad[i]=-(q[i]-t.mean[i])/t.sd[i]^2;end
    person=zeros(Z,2,P);task=zeros(Z,2,T);rater=zeros(Z,R,2)
    response=zeros(Z,2,O);steps=zeros(Z,K-1,G)
    a=zeros(Z,K);prob=similar(a);total=zero(Z)
    for n in eachindex(t.data.score)
        c=ix.criterion[n];g=ix.threshold_group[c];y=t.data.score[n]
        location=row_location(t,v,n)
        a[1]=0
        for k in 2:K;a[k]=a[k-1]+location-v.steps[k-1,g];end
        all(isfinite,a) || return rejected()
        a.-=maximum(a);a.-=B._logsumexp(a)
        total+=a[y+1];prob.=exp.(a)
        score=Z(y)
        for k in 2:K;score-=(k-1)*prob[k];end
        person[c,ix.person[n]]+=score;task[c,ix.task[n]]-=score
        rater[ix.rater[n],c]-=score;response[c,ix.response_id[n]]+=score
        for f in 1:F;grad[b.beta[f]]+=t.X[n,f]*score;end
        tail=zero(Z)
        for k in K:-1:2
            tail+=prob[k]
            steps[k-1,g]+=tail-(y>=k-1)
        end
    end
    value=prior+total;isfinite(value) || return rejected()
    grad[b.task].+=vec(task)
    for c in 1:2
        block=(first(b.rater_white)+(c-1)*(R-1)):(first(b.rater_white)+c*(R-1)-1)
        _helmert_pullback!(grad,block,view(rater,:,c),t.prior.rater_sd[c])
    end
    for g in 1:G
        block=(first(b.step_white)+(g-1)*(K-2)):(first(b.step_white)+g*(K-2)-1)
        _helmert_pullback!(grad,block,view(steps,:,g),t.prior.step_sd[g])
    end
    # Compute derivatives from z, not 1-rho^2, which rounds to zero in the tails.
    for (h,block,scores,N) in ((1,b.person_white,person,P),(2,b.response_white,response,O))
        z=q[b.correlation[h]];rho=C.stable_tanh(z)
        logdelta=B._log_one_minus_tanh_squared(z);s=exp(logdelta/2);delta=exp(logdelta)
        eta=h==1 ? t.prior.person_lkj_eta : t.prior.response_lkj_eta
        dz=-2eta*rho
        for j in 1:N
            i1=block[2j-1];i2=block[2j]
            g1=scores[1,j];g2=scores[2,j]
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
    return value,grad
end
