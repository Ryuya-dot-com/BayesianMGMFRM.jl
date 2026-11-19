using Test, BayesianMGMFRM, Distributions, ForwardDiff, Random, Statistics, JSON3
import LogDensityProblems as L
const BF=BayesianMGMFRM.AdditiveFacets
function bounded_fixture(;P=12,R=6)
    pairs=[(p,u,r) for p in 1:P for u in 1:2 for r in 1:R if mod(p+u+r,3)!=0]
    d=Dict{Symbol,Vector}(:speaker=>[p for (p,u,r) in pairs],:clip=>[2p+u-2 for (p,u,r) in pairs],
      :judge=>[r for (p,u,r) in pairs],:score=>[mod(13p+7u+17r,101)*1. for (p,u,r) in pairs],
      :rate=>[p/P+(u==1 ? -.2 : .2) for (p,u,r) in pairs],:experience=>[(r-1)/(R-1) for (p,u,r) in pairs])
    d[:score][1:5]=[0.,100.,1e-8,100-1e-8,50.]
    o=(person=:speaker,score=:score,facets=(recording=:clip,assessor=:judge),performance=:clip,
      observation=(family=:zero_one_inflated_beta,bounds=(0.,100.)),
      observation_prior=(precision=LogNormal(log(12),.4),endpoint_logit=Normal(-2,.7),upper_logit=Normal(.3,.8)),
      population=(person=LogNormal(log(.5),.35),recording=.3,assessor=LogNormal(log(.4),.35)),
      predictors=(person=(mean_rate=Normal(0,.6),),assessor=(experience=Normal(0,.5),),response=(rate_change=Normal(0,.6),)),
      decompose=(rate=(between=:mean_rate,within=:rate_change),),intercept=Normal(0,1.))
    d,o
end
# Independent response construction and centered scientific prior + Jacobian.
function bounded_reference(t,q;centered=false)
    effects=Dict{Symbol,Any}();lp=zero(eltype(q));lv=zero(eltype(q))
    for b in t.residuals
        s=b.hyper==0 ? b.sd : exp(b.logmean+b.logsd*q[b.hyper]);effects[b.name]=s.*q[b.raw]
        lp+=sum(logpdf.(Normal(0,s),effects[b.name]));lv+=length(b.raw)*log(s)
        if b.hyper>0;lp+=logpdf(LogNormal(b.logmean,b.logsd),s);lv+=log(b.logsd*s);end
    end
    shift=zeros(eltype(q),length(t.y))
    for p in t.terms
        c=p.mean+p.sd*q[p.raw];lp+=logpdf(Normal(p.mean,p.sd),c);lv+=log(p.sd)
        p.owner===:response ? (shift.+=c.*p.values) : (effects[p.owner].+=c.*p.values)
    end
    pr=t.observation_prior;ph=exp(pr.precision.logmean+pr.precision.logsd*q[end-2])
    z=pr.endpoint_logit.mean+pr.endpoint_logit.sd*q[end-1];h=pr.upper_logit.mean+pr.upper_logit.sd*q[end]
    lp+=logpdf(LogNormal(pr.precision.logmean,pr.precision.logsd),ph)+logpdf(Normal(pr.endpoint_logit.mean,pr.endpoint_logit.sd),z)+logpdf(Normal(pr.upper_logit.mean,pr.upper_logit.sd),h)
    lv+=log(pr.precision.logsd*ph)+log(pr.endpoint_logit.sd)+log(pr.upper_logit.sd)
    prior=lp+lv
    centered || (lp=sum(logpdf.(Normal(),q));lv=zero(lp))
    sig(x)=1/(1+exp(-x))
    for n in eachindex(t.y)
        e=effects[:person][t.person[n]]+shift[n]
        for b in t.facets;e-=effects[b.name][b.index[n]];end
        y=t.y[n]
        if y in (0,1)
            lp+=log(sig(z))+log(y==1 ? sig(h) : 1-sig(h))
        else
            u=sig(e);lp+=log1p(-sig(z))+logpdf(Beta(u*ph,(1-u)*ph),y)-log(t.observation.bounds[2]-t.observation.bounds[1])
        end
    end
    (;value=lp+lv,prior,volume=lv)
end
@testset "Bounded explanatory target" begin
    d,o=bounded_fixture();t=mfrm_spec(d;o...)
    @test validate_design(t).identified
    @test !hasproperty(t,:categories) && !hasproperty(t,:steps)
    @test length(parameter_names(t))==t.dimension
    for q in (zeros(t.dimension),.21sin.(1:t.dimension),collect(range(-1.5,1.5;length=t.dimension)))
        lp,g=logdensity_and_gradient(t,q);r=bounded_reference(t,q)
        @test lp≈r.value atol=1e-9 rtol=0
        @test g≈ForwardDiff.gradient(x->bounded_reference(t,x).value,q) atol=1e-7 rtol=1e-10
        @test lp≈bounded_reference(t,q;centered=true).value atol=1e-9
        @test logprior(t,q)≈r.prior atol=1e-10
        @test coordinates(t,q).log_volume≈bounded_reference(t,q;centered=true).volume atol=1e-10
        @test lp≈logprior(t,q)+sum(pointwise_loglikelihood(t,q)) atol=1e-9
        @test logposterior(BF.restore(BF.record(t)),q)==lp
        m=predict(t,q);@test all(0 .<=m.expected_score.<=100)
        @test all(m.lower_probability.+m.upper_probability.<1)
    end
    @test logposterior(t,fill(1e9,t.dimension))==-Inf
    @test_throws ArgumentError predictive_probabilities(t,zeros(t.dimension))
    bad=deepcopy(d);bad[:score][1]=101;@test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:experience][1]+=.1;@test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:score].=100.;u=mfrm_spec(bad;o...)
    @test design_summary(u).response_patterns.interior==0
    @test !isempty(design_summary(u).warnings)
    @test all(isfinite,last(logdensity_and_gradient(u,zeros(u.dimension))))
    # Same exact observations in another unit: only interior density measure changes.
    unit=deepcopy(d);unit[:score]./=100
    u=mfrm_spec(unit;merge(o,(observation=(family=:zero_one_inflated_beta,bounds=(0.,1.)),))...)
    q=.1sin.(1:t.dimension);nint=count(x->0<x<1,t.y)
    @test logposterior(u,q)-logposterior(t,q)≈nint*log(100) atol=1e-9
    @test last(logdensity_and_gradient(u,q))≈last(logdensity_and_gradient(t,q)) atol=1e-10
    # Labels and row order cannot change the prior interpretation or predictions.
    ix=reverse(eachindex(d[:score]));dr=Dict(k=>v[ix] for (k,v) in d)
    levels=(person=t.people,facets=(recording=t.facets[1].levels,assessor=t.facets[2].levels))
    tr=mfrm_spec(dr;merge(o,(;levels))...)
    @test logposterior(t,q)≈logposterior(tr,q) atol=1e-9
    @test predict(t,q).expected_score[ix]≈predict(tr,q).expected_score atol=1e-12
    # Duplicate person/performance variance kernels cannot identify two estimated SDs.
    one=Dict(k=>v[1:2:end] for (k,v) in d);one[:clip]=copy(one[:speaker])
    oo=merge(o,(decompose=nothing,predictors=(;),population=(person=LogNormal(0,.5),recording=LogNormal(0,.5),assessor=.4)))
    # Preserve unique rating identity while deliberately coinciding population groupings.
    one[:event]=collect(eachindex(one[:score]));oo=merge(oo,(assessment=:event,))
    @test !validate_design(mfrm_spec(one;oo...)).identified
end
