module LargePanelSpeedParity
using BayesianMGMFRM, BayesianMGMFRM.GlassBox, Test, ForwardDiff, LinearAlgebra, LogDensityProblems
using Distributions: Normal

const FM = BayesianMGMFRM.FrequentistMFRM
const AF = BayesianMGMFRM.AdditiveFacets
const L = LogDensityProblems

@testset "Sparse and dense Louis score covariance" begin
    d, Q, P = 7, 9, 11
    post = [abs(sin(p+q)) for p in 1:P, q in 1:Q]
    post ./= sum(post;dims=2)
    dense = zeros(d,Q,P)
    sparse_scores = FM._SparsePersonScores([Dict{Int,Vector{Float64}}() for _ in 1:P],Q)
    for p in 1:P, q in 1:Q, i in 1:d
        isodd(i+p) || continue
        v = cos(i*p+q)
        FM._add_node_score!(dense,i,q,p,v)
        FM._add_node_score!(sparse_scores,i,q,p,v)
    end
    @test FM._subtract_missing_information!(zeros(d,d),dense,post) ≈
          FM._subtract_missing_information!(zeros(d,d),sparse_scores,post) atol=1e-13
end

@testset "Ordinal and matrix kernels against automatic differentiation" begin
    n = 36
    tbl = (person=repeat(1:6, inner=6), item=mod1.(1:n,7),
           rater=mod1.(div.((1:n).-1,7),4), score=mod.((1:n) .+ 2 .* div.((1:n).-1,7),4))
    weights = [0.5 + mod(i,3)/2 for i in 1:n]
    opts = (;person=:person, score=:score, facets=(item=:item,rater=:rater),category_levels=0:3)
    quad = FM.build_quadrature(:gauss_hermite,11;sd=1.0)
    for owner in (:global,:item)
        spec = mfrm_spec(tbl;opts...,steps=owner,prior=:none)
        prob = FM.compile_problem(spec;method=:mmle,weights)
        for (mean_free,sd_free) in ((false,false),(false,true),(true,true))
            lay = FM.build_layout(prob;estimate_mean=mean_free,estimate_sd=sd_free)
            sc = FM._build_freq_mmle_scratch(prob,lay,quad)
            @test 2sc.n_patterns > n
            x = 0.04sin.(1:lay.n_free)
            g = similar(x)
            fg(z) = FM.mmle_nll_and_grad!(nothing,z,prob,lay,quad;scratch=sc)
            value = FM.mmle_nll_and_grad!(g,x,prob,lay,quad;scratch=sc)
            @test abs(value-fg(x)) < 1e-13
            @test maximum(abs,g - ForwardDiff.gradient(fg,x)) < 1e-13
            h = FM._ordinal_louis(x,prob,lay,quad,1.0,sc)
            h_ad = ForwardDiff.hessian(fg,x)
            @test maximum(abs,h-h_ad) <= 1e-11
            if isposdef(h_ad)
                @test maximum(abs,sqrt.(diag(inv(h))) - sqrt.(diag(inv(h_ad)))) <= 1e-10
            end
        end
        t=mfrm_spec(tbl;opts...,steps=owner,prior=:default)
        ds=AF._get_mrcml_grad_scratch(t)
        specialized=ds.scalar
        @test !isnothing(specialized)
        givens=AF._maybe_mrcml_givens_target(t)
        @test !isnothing(givens)
        x=0.08cos.(1:t.dimension)
        for target in (t,givens)
            ds.scalar=nothing
            old=L.logdensity_and_gradient(target,x)
            ds.scalar=specialized
            new=L.logdensity_and_gradient(target,x)
            @test abs(new[1]-old[1]) <= 1e-13
            @test maximum(abs,new[2]-old[2]) <= 1e-13
        end

        op=t.operator
        d=size(op.A_free,2)
        sc=FM._build_mrcml_mmle_scratch(op,length(t.people),t.group,t.supports,t.category,quad)
        patterns=FM._pattern_derivatives(op)
        for (mi,si) in ((0,0),(0,d+1),(d+1,d+2))
            x=0.07cos.(1:max(d,mi,si))
            fgmat(g,z) = FM._mrcml_mmle_nll_and_grad!(g,z,op,length(t.people),t.person,t.group,
                t.supports,t.category,weights,quad,0.0,1.0,mi,si,op.c_pat,sc)
            g=similar(x)
            fgmat(g,x)
            @test maximum(abs,g-ForwardDiff.gradient(z->fgmat(nothing,z),x)) <= 1e-13
            H=FM._mrcml_louis(x,op,t.person,t.group,t.supports,t.category,weights,quad,0.0,1.0,mi,si,sc,patterns)
            H_ad=ForwardDiff.hessian(z->fgmat(nothing,z),x)
            @test maximum(abs,H-H_ad) <= 1e-11
            if isposdef(H_ad)
                @test maximum(abs,sqrt.(diag(inv(H))) - sqrt.(diag(inv(H_ad)))) <= 1e-10
            end
        end
        pop=(group_index=[1,1,1,2,2,2],X=hcat(ones(6),collect(1:6) .> 3))
        parts=[merge(a,(;scratch=FM._build_mrcml_mmle_scratch(a.op,length(a.persons),a.owner,a.support,a.category,quad))) for a in FM._population_parts(t,pop,weights)]
        br,sr=d+1:d+2,d+3:d+4
        x=0.04cos.(1:last(sr))
        H=FM._grouped_louis(x,parts,quad,br,sr,patterns)
        H_ad=ForwardDiff.hessian(z->FM._grouped_mmle!(nothing,z,parts,quad,br,sr,op.c_pat),x)
        @test maximum(abs,H-H_ad) <= 1e-11
    end
end
@testset "Custom scoring and offsets keep their matrix semantics" begin
    n = 12
    A = [0.2r + (j==1 ? sin(r+k) : k*cos(r)) for r in 1:n, k in 1:3, j in 1:2]
    B = [k==1 ? -0.3 : k*(1+0.01r) for r in 1:n, k in 1:3]
    tbl = (p=mod1.(1:n,4), y=mod.(1:n,3))
    t = BayesianMGMFRM.MRCML.custom_spec(tbl;person=:p,score=:y,category_levels=0:2,
        A,B,offset=[0.15cos(r+k) for r in 1:n,k in 1:3],item_index=1:n,
        prior=Normal(0,1),person_prior_sd=1.0)
    @test isnothing(AF._scalar_rating_design(t;force=true))
    x = 0.13sin.(1:t.dimension)
    @test maximum(abs,L.logdensity_and_gradient(t,x)[2] - ForwardDiff.gradient(z->L.logdensity(t,z),x)) <= 1e-13
    quad = FM.build_quadrature(:gauss_hermite,13;sd=1.0)
    op = t.operator
    sc=FM._build_mrcml_mmle_scratch(op,length(t.people),t.group,t.supports,t.category,quad)
    @test !sc.ordinal_rows
    pars=[0.17,-0.05,0.12,0.08]
    weights=[1+0.05i for i in 1:n]
    obj(z)=FM._mrcml_mmle_nll_and_grad!(nothing,z,op,4,t.person,t.group,t.supports,t.category,weights,quad,0.,1.,3,4,op.c_pat,sc)
    full=FM._mrcml_louis(pars,op,t.person,t.group,t.supports,t.category,weights,quad,0.,1.,3,4,sc,FM._pattern_derivatives(op);calibration=true)
    @test maximum(abs,full.observed-ForwardDiff.hessian(obj,pars)) <= 1e-11
    # Sum of outer products of the four integrated person scores, before HC1 correction.
    g=hcat([ForwardDiff.gradient(pars) do z
        FM._mrcml_mmle_nll_and_grad!(nothing,z,op,4,t.person,t.group,t.supports,t.category,
            weights .* (t.person .== p),quad,0.,1.,3,4,op.c_pat,sc)
    end for p in 1:4]...)
    @test maximum(abs,full.meat-g*g') <= 1e-11
end

@testset "Deterministic large-panel row reductions" begin
    n=8100
    fd=FacetData((person=mod1.(1:n,9),item=mod1.(div.((1:n).-1,9),5),rater=mod1.(div.((1:n).-1,45),3),score=mod.(div.((1:n).-1,17),4));
                 person=:person,item=:item,rater=:rater,score=:score,category_levels=0:3)
    spec=mfrm_spec(fd;family=:mgmfrm,dimensions=2,thresholds=:partial_credit,q_matrix=Bool[1 0;1 0;0 1;0 1;1 1])
    target=BayesianMGMFRM.Experimental.scale_identified_target(spec)
    q=0.04cos.(1:target.dimension)
    serial=task_local_storage(:bayesianmgmfrm_active_chains,Threads.nthreads(:default)) do
        L.logdensity_and_gradient(target,q)
    end
    @test L.logdensity_and_gradient(target,q) == serial
    @test abs(L.logdensity(target,q)-serial[1]) <= 1e-10
end

end
