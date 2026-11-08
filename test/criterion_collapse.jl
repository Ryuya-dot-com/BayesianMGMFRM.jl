module CriterionCollapseChecks
using Test, Statistics, LinearAlgebra
import BayesianMGMFRM as B
const C=B.Experimental.CriterionCollapse
const L=B.LogDensityProblems
function prior()
    C.Prior(person_precision_shape=3.,person_precision_rate=2.,rater_precision_shape=3.,
        rater_precision_rate=.5,step_sd=1.5,class_alpha=1.,class_beta=1.)
end
function fixture(;K=3)
    rows=[(;person="p$p",item="c$i",rater="r$r",score=mod(p+i+r,K)) for p in 1:4 for r in 1:3 for i in 1:2]
    (; (k=>getproperty.(rows,k) for k in keys(first(rows)))...)
end
fd(d;K=3)=B.FacetData(d;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:K-1)
# Independent enumeration: every rater's class is assigned once, with row
# categorical probabilities constructed without the implementation helpers.
function oracle(t,q)
    s=C.coordinates(t,q);ell=zeros(t.R,2)
    for n in eachindex(t.score),z in 0:1
        step=z==0 ? s.delta[t.criterion[n],:] : vec(mean(s.delta;dims=1))
        a=[0.;cumsum(s.theta[t.person[n]]-s.severity[t.rater[n]].-step)]
        prob=exp.(a.-maximum(a));prob./=sum(prob)
        ell[t.rater[n],z+1]+=log(prob[t.score[n]+1])
    end
    classes=collect(Iterators.product(fill(0:1,t.R)...));terms=Float64[]
    for zs in classes
        push!(terms,sum(ell[r,zs[r]+1]+(zs[r]==0 ? s.log1mpi : s.logpi) for r in 1:t.R))
    end
    m=maximum(terms);a=exp.(terms.-m);a./=sum(a)
    weights=[sum(a[j]*classes[j][r] for j in eachindex(a)) for r in 1:t.R]
    (;loglikelihood=m+log(sum(exp.(terms.-m))),weights,ell)
end
@testset "Criterion collapse: target, shared class and boundaries" begin
    for K in (3,4)
        t=C.model(fd(fixture(;K);K);prior=prior());q=.3sin.(collect(1:L.dimension(t)))
        for scale in (0.,1.,3.)
            qq=q.*scale;c=C.components(t,qq);o=oracle(t,qq)
            @test c.loglikelihood≈o.loglikelihood atol=1e-12
            @test c.weights≈o.weights atol=1e-13
            @test vec(sum(exp.(c.probs.ordinary);dims=2))≈ones(t.data.n)
            @test vec(sum(exp.(c.probs.halo);dims=2))≈ones(t.data.n)
            v=C.coordinates(t,qq);h=t.H;D=B.Distributions
            lp=sum(D.logpdf.(D.Normal(),[v.u;v.v]))+sum(D.logpdf.(D.Normal(0,h[5]),v.delta))+
                D.logpdf(D.Gamma(h[1],1/h[2]),v.precision[1])+v.logt[1]+
                D.logpdf(D.Gamma(h[3],1/h[4]),v.precision[2])+v.logt[2]+
                D.logpdf(D.Beta(h[6],h[7]),exp(v.logpi))+v.logpi+v.log1mpi
            @test C.logprior(t,qq)≈lp atol=1e-12
            @test L.logdensity(t,qq)≈lp+o.loglikelihood atol=1e-12
            grad=B.ForwardDiff.gradient(x->L.logdensity(t,x),qq)
            ref=[(L.logdensity(t,qq.+[k==j ? 1e-5 : 0. for k in eachindex(qq)])-
                L.logdensity(t,qq.-[k==j ? 1e-5 : 0. for k in eachindex(qq)]))/2e-5 for j in eachindex(qq)]
            @test grad≈ref atol=2e-8 rtol=2e-8
            @test abs(sum(v.theta))<1e-13 && abs(sum(v.severity))<1e-13
        end
        @test diag(t.Qp*t.Qp')*(t.P/(t.P-1))≈ones(t.P)
        @test diag(t.Qr*t.Qr')*(t.R/(t.R-1))≈ones(t.R)
        # Equal profiles provide no likelihood information about the class.
        flat=zeros(L.dimension(t));flat[end]=.7
        @test C.components(t,flat).weights≈fill(1/(1+exp(-.7)),t.R)
        c=C.components(t,q);s=C.coordinates(t,q)
        rowwise=sum(C.logadd(s.log1mpi+c.probs.ordinary[n,t.score[n]+1],
            s.logpi+c.probs.halo[n,t.score[n]+1]) for n in eachindex(t.score))
        @test abs(rowwise-c.loglikelihood)>1e-4
        for z in (-1000.,1000.)
            extreme=copy(q);extreme[end]=z
            @test isfinite(L.logdensity(t,extreme))
            @test all(isfinite,C._quantities(t,extreme).prediction)
        end
        bad=copy(q);bad[end-2]=1000
        @test L.logdensity(t,bad)==-Inf
        @test_throws DimensionMismatch L.logdensity(t,q[2:end])
        shifted=merge(fixture(;K),(;score=fixture(;K).score.+5))
        st=C.model(B.FacetData(shifted;person=:person,item=:item,rater=:rater,score=:score,category_levels=5:K+4);prior=prior())
        @test L.logdensity(t,q)==L.logdensity(st,q)
        # Fixed artificial points check aggregation, not posterior precision.
        raw=reduce(vcat,[permutedims(q.*(.8+.01j)) for j in 1:20])
        out=C._category_rows(t,raw,2,10000)
        for row in out.rows
            r=findfirst(==(row.rater),t.data.rater_levels);i=findfirst(==(row.criterion),t.data.item_levels)
            ids=findall(n->t.rater[n]==r && t.criterion[n]==i,eachindex(t.score));k=row.category+1
            expected=mean([mean(C._quantities(t,z).prediction[ids,k]) for z in eachrow(raw)])
            @test row.expected.mean≈expected atol=1e-13
            @test row.expected.interval===nothing
            @test row.observed_count==count(n->t.score[n]==k-1,ids)
        end
        @test_throws ArgumentError C._category_rows(t,raw,2,1)
        @test C._probability_mean(ones(20),2).mcse_status===:degenerate_draws
        @test ismissing(C._probability_mean(ones(20),2).mean_mcse)
    end
    data=fixture();t=C.model(fd(data);prior=prior());original=C.target_identity(t)
    data.score[1]=mod(data.score[1]+1,3)
    @test C.target_identity(t)==original
    @test C.target_identity(C._restore_target(C._target_record(t)))==original
    @test_throws ArgumentError C.model(fd(map(v->[v;v[1]],fixture()));prior=prior())
    ids=findall(n->!(fixture().rater[n]=="r1" && fixture().item[n]=="c1"),1:24)
    @test_throws ArgumentError C.model(fd(map(v->v[ids],fixture()));prior=prior())
    @test_throws ArgumentError C.model(fd(fixture(;K=2);K=2);prior=prior())
    extra=merge(fixture(),(;group=fill("A",24)))
    @test_throws ArgumentError C.model(B.FacetData(extra;person=:person,item=:item,rater=:rater,score=:score,group=:group,category_levels=0:2);prior=prior())
    for field in fieldnames(C.Prior),value in (0.,-1.,Inf,NaN,true)
        record=merge(C._prior(prior()),NamedTuple{(field,)}((value,)))
        @test_throws ArgumentError C.Prior(;record...)
    end
    # Missing individual ratings are allowed when the declared design remains linked.
    @test C.design(C.model(fd(map(v->v[2:end],fixture()));prior=prior())).connected
end
end
