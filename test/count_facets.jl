using Test, BayesianMGMFRM, Distributions, ForwardDiff, Statistics, JSON3
const CF=BayesianMGMFRM.AdditiveFacets
function count_fixture(;P=12,R=6,family=:beta_binomial)
    pairs=[(p,u,r) for p in 1:P for u in 1:2 for r in 1:R if mod(p+u+r,3)!=0]
    n=[(1,5,10,20,40)[mod1(2p+u,5)] for (p,u,r) in pairs]
    d=Dict{Symbol,Vector}(:speaker=>[p for (p,u,r) in pairs],:clip=>[2p+u-2 for (p,u,r) in pairs],
      :judge=>[r for (p,u,r) in pairs],:correct=>[mod(13p+7u+17r,m+1) for ((p,u,r),m) in zip(pairs,n)],:total=>n,
      :rate=>[p/P+(u==1 ? -.2 : .2) for (p,u,r) in pairs],:experience=>[(r-1)/(R-1) for (p,u,r) in pairs])
    op=family===:beta_binomial ? (;precision=LogNormal(log(8),.6)) : (;)
    o=(person=:speaker,score=:correct,facets=(recording=:clip,assessor=:judge),performance=:clip,
      observation=(;family,trials=:total),observation_prior=op,
      population=(person=LogNormal(log(.5),.35),recording=.3,assessor=LogNormal(log(.4),.35)),
      predictors=(person=(mean_rate=Normal(0,.6),),assessor=(experience=Normal(0,.5),),response=(rate_change=Normal(0,.6),)),
      decompose=(rate=(between=:mean_rate,within=:rate_change),),intercept=Normal(0,1.))
    d,o
end
function count_reference(t,q;prior_only=false)
    effects=Dict{Symbol,Any}();lp=zero(eltype(q));lv=zero(eltype(q))
    for b in t.residuals
        s=b.hyper==0 ? b.sd : exp(b.logmean+b.logsd*q[b.hyper]);effects[b.name]=s.*q[b.raw]
        lp+=sum(logpdf.(Normal(0,s),effects[b.name]));lv+=length(b.raw)*log(s)
        if b.hyper>0;lp+=logpdf(LogNormal(b.logmean,b.logsd),s);lv+=log(b.logsd*s);end
    end
    shift=zeros(eltype(q),length(t.y))
    for p in t.terms
        z=p.mean+p.sd*q[p.raw];lp+=logpdf(Normal(p.mean,p.sd),z);lv+=log(p.sd)
        p.owner===:response ? (shift.+=z.*p.values) : (effects[p.owner].+=z.*p.values)
    end
    bb=t.observation.family===:beta_binomial;phi=one(eltype(q))
    if bb
        pr=t.observation_prior.precision;phi=exp(pr.logmean+pr.logsd*q[end])
        lp+=logpdf(LogNormal(pr.logmean,pr.logsd),phi);lv+=log(pr.logsd*phi)
    end
    prior_only && return lp+lv
    for n in eachindex(t.y)
        e=effects[:person][t.person[n]]+shift[n]
        for b in t.facets;e-=effects[b.name][b.index[n]];end
        p=1/(1+exp(-e));m=t.trials[n];y=t.y[n]
        lp+=bb ? logpdf(BetaBinomial(m,p*phi,(1-p)*phi),y) : logpdf(Binomial(m,p),y)
    end
    lp+lv
end
@testset "Count target, measure and independent gradient" begin
 for family in (:binomial,:beta_binomial)
    d,o=count_fixture(;family);t=mfrm_spec(d;o...)
    @test validate_design(t).identified
    @test contract(t).multiplier==1
    @test !hasproperty(t,:categories) && !hasproperty(t,:steps)
    @test CF.record(CF.restore(CF.record(t)))==CF.record(t)
    for q in (zeros(t.dimension),.21sin.(1:t.dimension),collect(range(-1.5,1.5;length=t.dimension)))
        @test logposterior(t,q)≈count_reference(t,q) atol=1e-9
        @test logprior(t,q)≈count_reference(t,q;prior_only=true) atol=1e-9
        @test last(logdensity_and_gradient(t,q))≈ForwardDiff.gradient(x->count_reference(t,x),q) atol=1e-8 rtol=1e-8
        @test sum(pointwise_loglikelihood(t,q))+logprior(t,q)≈logposterior(t,q) atol=1e-9
        @test length(parameter_names(t))==length(q)
    end
    bad=deepcopy(d);bad[:total]=fill(0,length(t.y));@test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:correct]=fill(.5,length(t.y));@test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:correct][1]=bad[:total][1]+1;@test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:total]=Any[d[:total]...];bad[:total][1]=missing;@test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:total]=Float64.(d[:total]);bad[:total][1]+=.5;@test_throws ArgumentError mfrm_spec(bad;o...)
    @test_throws ArgumentError mfrm_spec(d;merge(o,(observation=(family=:binomial,trials=:correct),))...)
    d2=deepcopy(d);d2[:correct]=Float64.(d[:correct]);d2[:total]=Float64.(d[:total]);@test CF.record(mfrm_spec(d2;o...))==CF.record(t)
    p=predict(t,zeros(t.dimension));@test p.expected_count≈p.expected_proportion.*t.trials
    @test all(0 .<=p.zero_probability.<=1) && all(0 .<=p.perfect_probability.<=1)
    @test_throws ArgumentError predictive_probabilities(t,zeros(t.dimension))
 end
end
@testset "Count normalization, moments and limiting cases" begin
 for n in (1,2,7,40),eta in (-30.,-5.,0.,6.,30.),phi in (nothing,1e-8,.2,8.,1e4,1e12)
    l=[CF.count_cell(k,n,eta,phi,logpdf(Binomial(n,.5),k)+n*log(2))[1] for k in 0:n]
    mass=exp.(l);p=1/(1+exp(-eta));mu=sum((0:n).*mass)
    v=sum(((0:n).-mu).^2 .*mass);truth=n*p*(1-p)*(phi===nothing ? 1 : 1+(n-1)/(1+phi))
    @test sum(mass)≈1 atol=2e-10
    @test mu≈n*p atol=2e-9
    @test v≈truth atol=2e-8
 end
 for eta in (-100.,-4.,0.,10.,100.),y in (0,1)
    b=CF.count_cell(y,1,eta,nothing,0.)
    @test CF.count_cell(y,1,eta,1e-10,0.)==b==CF.count_cell(y,1,eta,1e14,0.)
    @test b[1]≈logpdf(BernoulliLogit(eta),y) atol=1e-12
 end
 for eta in (-3.,0.,4.),y in (0,1,20,50)
    lc=logpdf(Binomial(50,.5),y)+50log(2)
    @test CF.count_cell(y,50,eta,1e14,lc)[1]≈CF.count_cell(y,50,eta,nothing,lc)[1] atol=1e-8
 end
 d,o=count_fixture();d[:total].=1;d[:correct].=mod.(d[:correct],2);t=mfrm_spec(d;o...)
 @test any(contains("informed only by its prior"),validate_design(t).warnings)
 q=zeros(t.dimension);q[end]=2.;@test last(logdensity_and_gradient(t,q))[end]==-2.
 z=copy(q);z[end]=-3.;@test pointwise_loglikelihood(t,q)==pointwise_loglikelihood(t,z)
 @test CF.count_stats([0,9],[1,10]).mean_proportion==.45
 @test CF.count_stats([0,9],[1,10]).pooled_proportion==9/11
end
