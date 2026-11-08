module RaterItemInteractionChecks
using Test, LinearAlgebra, BayesianMGMFRM
using BayesianMGMFRM: ForwardDiff, LogDensityProblems, JSON3
const RI=BayesianMGMFRM.Experimental.RaterItemInteractions
const L=LogDensityProblems
include(joinpath(@__DIR__,"..","examples","rater_item_interactions.jl"))

@testset "Fitted rater-item interaction: finite artificial fixtures, no sampling" begin
    t=RaterItemInteractionExample.inputs();q=RI.initial(t)
    @test RI.contract().scientific_acceptance===false
    @test RI.target_identity(t)==BayesianMGMFRM._cache_hash(RI._target_record(t))
    @test BayesianMGMFRM.Experimental.surface_contract().candidate_surfaces.rater_item_interactions==RI.contract()
    @test L.dimension(t)==32
    @test RI.design(t).location_rank==RI.design(t).location_columns==23
    @test sum(RI.design(t).counts)==72
    @test minimum(RI.design(t).counts)==6
    @test RI.design(t).reference==:equal_weight_full_rater_item_grid
    for h in (t.rater_basis,t.item_basis,t.step_basis)
        @test h'h≈I
        @test maximum(abs,sum(h;dims=1))<1e-14
    end
    for scale in (0.,.3,2.)
        x=[scale*sin(j) for j in 1:L.dimension(t)];x[end]=log(.3)
        v=RI.coordinates(t,x)
        @test abs(sum(v.rater))<1e-14
        @test abs(sum(v.item))<1e-14
        @test maximum(abs,sum(v.interaction;dims=1))<1e-14
        @test maximum(abs,sum(v.interaction;dims=2))<1e-14
        @test maximum(abs,sum(v.steps;dims=2))<1e-14
        lp=RI.category_logprobs(t,x)
        @test all(isfinite,lp)
        @test maximum(abs,sum(exp.(lp);dims=2).-1)<1e-14
        @test isfinite(L.logdensity(t,x))
        @test all(isfinite,ForwardDiff.gradient(y->L.logdensity(t,y),x))
    end
    # Cell marginal prior variance equals tau^2 under independent standard normal z.
    C=kron(t.item_basis,t.rater_basis)/t.interaction_normalization
    @test diag(C*C')≈ones(12)
    @test rank(C)==6
    @test norm(C'*C-I/t.interaction_normalization^2)<1e-13
    bad=copy(q);bad[end]=1000
    @test L.logdensity(t,bad)==-Inf
    @test_throws DimensionMismatch L.logdensity(t,q[1:end-1])
    @test_throws ArgumentError RI._margin(0)
    @test_throws ArgumentError RI._margin(true)
    @test_throws ArgumentError RI.Prior(;merge(RI._prior(t.prior),(;interaction_logsd=0.))...)
    @test_throws ArgumentError RI.Prior(;merge(RI._prior(t.prior),(;person_sd=NaN))...)
    d=t.data;rows=RI._table(d)
    shifted=FacetData(merge(rows,(;score=rows.score.+2));person=:person,item=:item,rater=:rater,score=:score,category_levels=2:5)
    @test L.logdensity(RI.model(shifted;prior=t.prior),q)==L.logdensity(t,q)
    reversed=map(reverse,rows)
    reordered=RI.model(FacetData(reversed;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:3);prior=t.prior)
    @test L.logdensity(reordered,q)≈L.logdensity(t,q)
    @test RI._target_record(RI._restore_target(RI._target_record(t)))==RI._target_record(t)
    # Deterministic fixtures: these are not generated research datasets.
    make(rows;cats=0:1)=FacetData(rows;person=:person,item=:item,rater=:rater,score=:score,category_levels=cats)
    balanced=(person=fill("P",4),rater=["A","A","B","B"],item=["a","b","a","b"],score=[0,1,1,0])
    binary=RI.model(make(balanced);prior=t.prior)
    v=RI.coordinates(binary,RI.initial(binary));@test all(iszero,v.steps)
    @test exp.(RI.category_logprobs(binary,RI.initial(binary)))≈fill(.5,4,2)
    # A positive gamma reduces adjacent-category odds at that rater/item.
    bq=RI.initial(binary);bq[only(binary.blocks.interaction)]=1.
    bv=RI.coordinates(binary,bq);bl=RI.category_logprobs(binary,bq)
    @test bl[1,2]-bl[1,1]≈-bv.interaction[1,1]
    @test bl[1,2]<bl[1,1]
    unbalanced=map(x->x[[fill(1,9);2;3;fill(4,9)]],balanced)
    @test RI.design(RI.model(make(unbalanced);prior=t.prior)).counts==[9 1;1 9]
    @test_throws ArgumentError RI.model(make(map(x->x[1:3],balanced));prior=t.prior)
    disconnected=merge(balanced,(;person=["P1","P1","P2","P2"]))
    @test_throws ArgumentError RI.model(make(disconnected);prior=t.prior)
    @test_throws ArgumentError RI.model(make(merge(balanced,(;rater=fill("A",4))));prior=t.prior)
    snap=RI._restore_target(RI._target_record(t));snap.data.score[1]=3
    @test t.data.score[1]==0
end

if haskey(ENV,"RI_FINITE_OUTPUT")
    t=RaterItemInteractionExample.inputs()
    points=[begin
        q=[scale*sin(j) for j in 1:L.dimension(t)];q[end]=log(tau)
        (;q,logdensity=L.logdensity(t,q),gradient=ForwardDiff.gradient(x->L.logdensity(t,x),q),
            coordinates=RI.coordinates(t,q),logprobs=RI.category_logprobs(t,q))
    end for (scale,tau) in ((0.,.3),(.3,.01),(1.,.3),(2.,2.))]
    path=ENV["RI_FINITE_OUTPUT"];ispath(path) && error("Preserve finite evidence")
    open(path,"w") do io
        JSON3.write(io,(;origin="deterministic finite coordinate fixtures, not posterior draws",
            prior=RI._prior(t.prior),person=t.data.person,item=t.data.item,rater=t.data.rater,
            category=t.data.category,P=length(t.data.person_levels),R=length(t.data.rater_levels),
            I=length(t.data.item_levels),K=length(t.data.category_levels),points))
    end
end
end # module
