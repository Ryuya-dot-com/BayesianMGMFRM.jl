module GeneralizabilityLikelihoodTests
using Test, BayesianMGMFRM, LinearAlgebra, Random, Statistics, ForwardDiff
const G=BayesianMGMFRM.Generalizability
BLAS.set_num_threads(1)
rng=MersenneTwister(55);P=12;R=6
pp=randn(rng,P,2)*[1.0 .4;0. .8];rr=randn(rng,R,2)*[.6 .2;0. .5]
ids=[(p,r) for r in 1:R for p in 1:P]
y=reduce(vcat,[(pp[p,:]+rr[r,:]+.3randn(rng,2))' for (p,r) in ids])
tab=(person=first.(ids),rater=last.(ids),a=y[:,1],b=y[:,2])
model(table=tab,cols=(:a,:b))=G.model(table;scores=cols,person=:person,facets=(rater=:rater,),prior=:none)
@testset "Gaussian marginal likelihood and gradient" begin
    tiny=(; (k=>v[1:24] for (k,v) in pairs(tab))...)
    for cols in ((:a,),(:a,:b)),method in (:ml,:reml)
        t=model(tiny,cols);d=G.likelihood_data(t);x=G.likelihood_coordinates([Matrix{Float64}(I,d.C,d.C)*s for s in (.7,.4,.6)])
        e=G.likelihood_evaluate(d,x,method)
        fd=ForwardDiff.gradient(z->G.likelihood_evaluate(d,z,method;gradient=false).value,x)
        @test e.gradient≈fd atol=1e-8
        @test_throws ArgumentError fit(t;method=:jmle)
        @test_throws ArgumentError fit(t;method=:mmle)
        @test_throws ArgumentError fit(t;method=:nuts)
    end
end
@testset "REML balanced solution, scale invariance and persisted D studies" begin
    cube=reshape(y,P,R,2);grand=mean(cube;dims=(1,2))
    pm=dropdims(mean(cube;dims=2);dims=2);rm=dropdims(mean(cube;dims=1);dims=1)
    eps=cube.-reshape(pm,P,1,2).-reshape(rm,1,R,2).+grand
    E=reshape(eps,P*R,2);Se=E'E/((P-1)*(R-1));Sp=cov(pm)-Se/R;Sr=cov(rm)-Se/P
    for cols in ((:a,),(:a,:b))
        C=length(cols);f=fit(model(tab,cols);method=:reml)
        @test qualify(f).qualified
        for (j,S) in enumerate((Sp,Sr,Se))
            @test reshape(f.record.covariance[j],C,C)≈S[1:C,1:C] atol=1e-6
        end
        ds=reliability(f;counts=(rater=3,))
        exact=reliability(f;counts=(rater=3,),interval_method=:exact)
        @test exact.rows[1].G.estimate==ds.rows[1].G.estimate
        @test exact.rows[1].G.status===:exact_f
        @test 0<=exact.rows[1].G.lower<exact.rows[1].G.upper<=1
        @test exact.rows[1].relative_sem.status===:exact_chisq
        @test exact.rows[1].Phi.status===:not_supported_by_exact
        @test ismissing(exact.rows[1].Phi.lower)
        @test_throws ArgumentError G.plot_data(f;kind=:dstudy,counts=(rater=1:3,),interval_method=:exact)
        @test G.plot_data(f;kind=:dstudy,counts=(rater=3,),metric=:G,interval_method=:exact).rows[1].lower==exact.rows[1].G.lower
        @test ds.rows[1].G.estimate≈ds.rows[1].universe_variance.estimate/(ds.rows[1].universe_variance.estimate+ds.rows[1].relative_sem.estimate^2)
        @test_throws MethodError reliability(f;counts=(rater=3,),threshold=.8)
        @test_throws ArgumentError reliability(f;counts=(rater=0,))
        @test length(G.plot_data(f;kind=:dstudy,counts=(rater=1:3,)).rows)==3
        weights=collect(1.:C)
        plotted=G.plot_data(f;kind=:dstudy,counts=(rater=1:3,),weights,metric=:absolute_sem)
        weighted=reliability(f;counts=(rater=3,),weights).rows[1].absolute_sem
        @test plotted.rows[3].estimate≈weighted.estimate
        @test plotted.rows[3].lower≈weighted.lower
        mktempdir() do dir
            receipt=save_report(joinpath(dir,"fit.json"),f;return_receipt=true)
            saved=load_report(receipt.path;expected_sha256=receipt.sha256)
            @test isequal(reliability(saved;counts=(rater=3,)).rows,ds.rows)
            @test isequal(reliability(saved;counts=(rater=3,),interval_method=:exact).rows,exact.rows)
            @test_throws ArgumentError load_report(receipt.path)
            save_fit(joinpath(dir,"fit.jls"),f)
            @test load_fit(joinpath(dir,"fit.jls")).record==f.record
        end
    end
    f=fit(model();method=:ml)
    changed=(person=reverse(tab.person),rater=reverse(tab.rater),a=reverse(5 .+ 2tab.b),b=reverse(-3 .+ 2tab.a))
    h=fit(model(changed);method=:ml)
    @test qualify(h).qualified
    for k in 1:3
        @test reshape(h.record.covariance[k],2,2)≈4reshape(f.record.covariance[k],2,2)[[2,1],[2,1]] atol=2e-5
    end
    @test h.record.objective-f.record.objective≈length(y)*log(2) atol=1e-6
end
@testset "Zero variance, nested and incomplete designs" begin
    z=[sin(p*r) for p in 1:8,r in 1:5];z=z.-mean(z;dims=1).-mean(z;dims=2).+mean(z)
    zz=(person=repeat(1:8;outer=5),rater=repeat(1:5;inner=8),a=vec(z))
    f=fit(model(zz,(:a,));method=:reml)
    @test qualify(f).qualified
    @test f.record.covariance[1][1]<1e-7 && f.record.covariance[2][1]<1e-7
    @test f.record.coordinate_covariance===nothing
    @test ismissing(reliability(f;counts=(rater=2,)).rows[1].G.lower)
    exact=reliability(f;counts=(rater=2,),interval_method=:exact)
    @test exact.rows[1].G.status===:empty_confidence_set
    @test ismissing(exact.rows[1].G.lower)
    @test exact.rows[1].relative_sem.status===:exact_chisq
    ids=[(p,t,r) for p in 1:5 for t in 1:3 for r in 1:2]
    nested=(person=first.(ids),task=getindex.(ids,2),rater=last.(ids),a=randn(rng,length(ids)),b=randn(rng,length(ids)))
    for nesting in ((;),(rater=:task,))
        t=G.model(nested;scores=(:a,:b),person=:person,facets=(rater=:rater,task=:task),nesting,prior=:none)
        d=G.likelihood_data(t);x=G.likelihood_coordinates([Matrix{Float64}(I,2,2)*.5 for _ in 1:d.K])
        @test G.likelihood_evaluate(d,x,:reml).gradient≈ForwardDiff.gradient(z->G.likelihood_evaluate(d,z,:reml;gradient=false).value,x) atol=1e-8
    end
    incomplete=(; (k=>v[setdiff(1:length(v),[3,16,22])] for (k,v) in pairs(tab))...)
    incomplete_fit=fit(model(incomplete);method=:reml)
    @test qualify(incomplete_fit).qualified
    @test_throws ArgumentError reliability(incomplete_fit;counts=(rater=3,),interval_method=:exact)
    bad=(person=1:4,rater=1:4,a=[1.,2.,4.,3.])
    @test_throws ArgumentError fit(model(bad,(:a,));method=:reml)
end
end
