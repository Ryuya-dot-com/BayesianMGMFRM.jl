module FourFacetSharedTargetChecks
using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Serialization
import LogDensityProblems as L
const B = BayesianMGMFRM
include("../scripts/four_facet_shared_target.jl")
const F = FourFacetSharedTarget
const PRIOR = (; person_sd=.8, task_kernel_sd=.4, rater_kernel_sd=.3,
    criterion_kernel_sd=.5, step_kernel_sd=.6, shared_sd_scale=.7)

function fixture(; K=4, P=3, T=2, R=2, perm=nothing)
    cells = [(p,t,r,c) for p in 1:P for t in 1:T for r in 1:R for c in 1:4]
    perm === nothing || (cells=cells[perm])
    table = (; person=first.(cells), task=getindex.(cells,2), rater=getindex.(cells,3),
        criterion=last.(cells), score=[mod(p+t+r+c,K) for (p,t,r,c) in cells],
        response=["p$p-t$t" for (p,t,r,c) in cells])
    return table
end

function spec(table; K=4, task=true, response=true, q=nothing)
    data = FacetData(table; person=:person, task=task ? :task : nothing,
        rater=:rater, item=:criterion, score=:score,
        response_id=response ? :response : nothing, category_levels=0:(K-1))
    q === nothing && (q=Bool[cld(c,2)==d for c in data.item_levels, d in 1:2])
    return mfrm_spec(data; dimensions=2, q_matrix=q, thresholds=:partial_credit)
end
target(s; prior=PRIOR) = F.SharedTaskTarget(s; prior,category_direction=:higher_is_more)
params(t) = [.15sin(i) for i in 1:L.dimension(t)]

# Explicit dense Helmert formula, independent of the production linear-time map.
helmert(n) = [i <= j ? 1/sqrt(j*(j+1)) : i == j+1 ? -j/sqrt(j*(j+1)) : 0.
              for i in 1:n, j in 1:(n-1)]
function physical(t,x)
    P,T,R,C,K=t.sizes
    b=t.blocks
    criterion=zeros(eltype(x),C)
    offset=first(b.criterion)
    for group in t.criterion_groups
        q=length(group)-1
        criterion[group]=helmert(length(group))*x[offset:offset+q-1]
        offset+=q
    end
    return (; theta=reshape(x[b.theta],2,P), task=helmert(T)*x[b.task],
        rater=helmert(R)*x[b.rater],criterion,
        steps=helmert(K-1)*reshape(x[b.steps],K-2,C),
        shared=exp(x[first(b.log_sigma)])*x[b.z])
end

function oracle(t,x)
    v=physical(t,x)
    data=t.input_spec.data
    out=zeros(eltype(x),data.n,t.sizes[5])
    for n in 1:data.n
        c=data.item[n]
        eta=v.theta[t.dimension[c],data.person[n]]-v.task[t.task[n]]-
            v.rater[data.rater[n]]-v.criterion[c]+v.shared[t.group[n]]
        logits=[zero(eta); cumsum(eta .- v.steps[:,c])]
        out[n,:]=logits .- log(sum(exp,logits))
    end
    return out
end

function native_baseline(t,x)
    v=physical(t,x)
    data=t.input_spec.data
    T,C=t.sizes[2],t.sizes[4]
    combined=FacetData((; person=data.person, rater=data.rater,
        item=[(a-1)*C+c for (a,c) in zip(t.task,data.item)],score=data.score);
        person=:person,rater=:rater,item=:item,score=:score,category_levels=data.category_levels)
    q=Bool[t.dimension[mod1(i,C)]==d for i in combined.item_levels,d in 1:2]
    reference=B._MFRMFixedQReferenceLogDensity(mfrm_spec(combined;dimensions=2,q_matrix=q);
        prior=MFRMPrior())
    raw=zeros(L.dimension(reference))
    b=reference.blueprint.blocks
    raw[b[:person]]=vec(v.theta)
    raw[b[:rater_free]]=v.rater[1:end-1]
    for (i,code) in enumerate(combined.item_levels)
        task,criterion=cld(code,C),mod1(code,C)
        raw[b[:item][i]]=v.task[task]+v.criterion[criterion]
        for j in 1:(t.sizes[5]-2)
            raw[b[:item_steps][(i-1)*(t.sizes[5]-2)+j]]=v.steps[j,criterion]
        end
    end
    return B._mfrm_fixed_q_pointwise(reference,raw)
end

@testset "Four-facet shared-task density, constraints and native null likelihood" begin
    for K in (2,4)
        s=spec(fixture(;K);K)
        t=target(s)
        x=params(t)
        x[first(t.blocks.log_sigma)]=log(.4)
        v=physical(t,x)
        actual=F.category_logprobs(t,x)
        @test actual ≈ oracle(t,x) atol=3e-14
        @test vec(sum(exp.(actual);dims=2)) ≈ ones(s.data.n) atol=3e-14
        @test sum(v.task) ≈ 0 atol=1e-14
        @test sum(v.rater) ≈ 0 atol=1e-14
        @test all(g -> abs(sum(v.criterion[g])) < 1e-14,t.criterion_groups)
        @test vec(sum(v.steps;dims=1)) ≈ zeros(4) atol=1e-14
        @test F._components(t,x).shared ≈ v.shared
        @test F.pointwise_loglikelihood(t,x) ≈ [actual[n,s.data.category[n]] for n in 1:s.data.n]
        @test L.logdensity(t,x) ≈ sum(F.pointwise_loglikelihood(t,x))+F.logprior(t,x)
        null=copy(x); null[t.blocks.z].=0
        native=native_baseline(t,null)
        @test F.pointwise_loglikelihood(t,null) ≈ native atol=2e-12
        extreme=copy(null); extreme[t.blocks.theta].=1000
        logs=F.category_logprobs(t,extreme)
        @test all(isfinite,logs) && any(iszero,exp.(logs))
        @test all(isfinite,ForwardDiff.gradient(v -> L.logdensity(t,v),x))
        gradient=ForwardDiff.gradient(v -> L.logdensity(t,v),x)
        step=1e-5
        finite=map(eachindex(x)) do i
            plus,minus=copy(x),copy(x)
            plus[i]+=step; minus[i]-=step
            (L.logdensity(t,plus)-L.logdensity(t,minus))/(2step)
        end
        @test gradient ≈ finite atol=2e-7 rtol=2e-7
        @info "Density-only verification; no sampling" categories=K parameters=length(x) max_gradient_error=maximum(abs.(gradient-finite)) native_null_error=maximum(abs.(F.pointwise_loglikelihood(t,null)-native))
        prior_gradient=ForwardDiff.gradient(v -> F.logprior(t,v),x)
        @test prior_gradient[first(t.blocks.log_sigma)] ≈ 1-(.4/PRIOR.shared_sd_scale)^2
        @test prior_gradient[t.blocks.z] ≈ -x[t.blocks.z]
        zero_x=zeros(length(x))
        counts=length.(values(t.blocks)[1:6])
        scales=(PRIOR.person_sd,PRIOR.task_kernel_sd,PRIOR.rater_kernel_sd,
                PRIOR.criterion_kernel_sd,PRIOR.step_kernel_sd,1.)
        expected=-sum(n*(log(sd)+log(2pi)/2) for (n,sd) in zip(counts,scales))+
            log(2/pi)/2-log(PRIOR.shared_sd_scale)-1/(2PRIOR.shared_sd_scale^2)
        @test F.logprior(t,zero_x) ≈ expected
        wide=target(s;prior=merge(PRIOR,(;shared_sd_scale=2.)))
        @test F.pointwise_loglikelihood(wide,x) == F.pointwise_loglikelihood(t,x)
        @test F.logprior(wide,x) != F.logprior(t,x)
        low=copy(x); low[first(t.blocks.log_sigma)]=-1000
        @test isfinite(L.logdensity(t,low))
        high=copy(x); high[first(t.blocks.log_sigma)]=1000
        @test L.logdensity(t,high) == -Inf
        # Group effect changes only that person's task, shared by all raters/criteria.
        shifted=copy(null); shifted[first(t.blocks.z)]=1
        delta=F.category_logprobs(t,shifted)-F.category_logprobs(t,null)
        @test all(n -> (t.group[n]==1) == any(!iszero,delta[n,:]),1:s.data.n)
        old=F.pointwise_loglikelihood(t,x)
        s.data.score[1]=mod(s.data.score[1]+1,K)
        @test F.pointwise_loglikelihood(t,x) == old # owned snapshot
    end
end

@testset "Facet relabeling with the corresponding orthogonal coordinates" begin
    table=fixture()
    t=target(spec(table)); x=params(t)
    reference=F.category_logprobs(t,x)
    for role in (:rater,:task,:criterion)
        transformed=copy(x)
        if role === :rater
            renamed=merge(table,(;rater=3 .- table.rater))
            transformed[t.blocks.rater] .*= -1
        elseif role === :task
            renamed=merge(table,(;task=3 .- table.task))
            transformed[t.blocks.task] .*= -1
            transformed[t.blocks.z] = vec(reverse(reshape(x[t.blocks.z],2,3);dims=1))
        else
            renamed=merge(table,(;criterion=[c==1 ? 2 : c==2 ? 1 : c for c in table.criterion]))
            transformed[first(t.blocks.criterion)] *= -1
            transformed[t.blocks.steps] = vec(reshape(x[t.blocks.steps],2,4)[:,[2,1,3,4]])
        end
        other=target(spec(renamed))
        @test F.category_logprobs(other,transformed) ≈ reference atol=1e-14
        @test L.logdensity(other,transformed) ≈ L.logdensity(t,x) atol=1e-12
    end
end

@testset "Target identity, reconstruction and unsupported inputs" begin
    table=fixture()
    s=spec(table)
    t=target(s); x=params(t)
    record=F.target_record(t)
    identity=B._cache_hash(record)
    mktempdir() do dir
        file=joinpath(dir,"target.jls")
        serialize(file,record)
        restored=F.restore_target(deserialize(file);expected_identity=identity)
        @test B._cache_hash(F.target_record(restored)) == identity
        @test L.logdensity(restored,x) == L.logdensity(t,x)
        @test F.category_logprobs(restored,x) == F.category_logprobs(t,x)
    end
    @test_throws ArgumentError F.restore_target(record;expected_identity="wrong")
    wrong=merge(record,(;likelihood_scale=1.7))
    @test_throws ArgumentError F.restore_target(wrong;expected_identity=B._cache_hash(wrong))
    # FacetSpec has a short display; the full native identity must bind its data.
    changed_scores=copy(table.score); changed_scores[1]=mod(changed_scores[1]+1,4)
    changed_spec=spec(merge(table,(;score=changed_scores)))
    changed=F.target_record(target(changed_spec))
    @test B._cache_hash(changed) != identity
    forged=merge(record,(;input_spec=changed_spec))
    @test_throws ArgumentError F.restore_target(forged;expected_identity=B._cache_hash(forged))
    perm=reverse(1:s.data.n)
    reordered=target(spec(fixture(;perm)))
    @test F.pointwise_loglikelihood(reordered,x) ≈ F.pointwise_loglikelihood(t,x)[perm]
    for bad in (() -> spec(table;task=false),() -> spec(table;response=false),
                () -> spec(fixture(;T=1)),() -> spec(fixture(;R=1)),() -> spec(fixture(;P=1)),
                () -> spec(map(v -> v[2:end],table)),
                () -> spec(merge(table,(;response=fill("same",s.data.n)))),
                () -> spec(merge(table,(;response=["row-$i" for i in 1:s.data.n]))),
                () -> spec(table;q=Bool[1 1;1 0;0 1;0 1]))
        @test_throws ArgumentError target(bad())
    end
    for scale in (0.,-1.,Inf,NaN,true)
        @test_throws ArgumentError target(s;prior=merge(PRIOR,(;shared_sd_scale=scale)))
    end
    @test_throws ArgumentError F.SharedTaskTarget(s;prior=PRIOR,category_direction=:unspecified)
    @test_throws ArgumentError target(s;prior=(;person_sd=1.))
    @test_throws ArgumentError L.logdensity(t,x[2:end])
    @test_throws ArgumentError L.logdensity(t,fill(NaN,length(x)))
    broken=target(s); broken.group[1]=2
    @test_throws ArgumentError F.target_record(broken)
end
end
