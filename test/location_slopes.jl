using Test, BayesianMGMFRM, Distributions, ForwardDiff, LinearAlgebra, Statistics, JSON3
using BayesianMGMFRM.GlassBox
const RS=BayesianMGMFRM.AdditiveFacets
function slope_fixture(;P=8,R=6,random=true,correlation=LKJ(2,2.))
    ix=[(p,u,r) for p in 1:P for u in 1:2 for r in 1:R if mod(p+u+r,3)!=0]
    d=Dict{Symbol,Vector}(:speaker=>[p for (p,u,r) in ix],:clip=>[2p+u-2 for (p,u,r) in ix],
        :judge=>[r for (p,u,r) in ix],:score=>[Float64(mod(p+3u+5r,101)) for (p,u,r) in ix],
        :rate=>[p/P+(u==1 ? -.6 : .6) for (p,u,r) in ix],:experience=>[(r-1)/(R-1) for (p,u,r) in ix])
    ass=random ? (intercept=LogNormal(log(.4),.35),slopes=(rate_change=LogNormal(log(.6),.4),),correlation=correlation) : LogNormal(log(.4),.35)
    o=(person=:speaker,score=:score,facets=(recording=:clip,assessor=:judge),performance=:clip,
        observation=(family=:zero_one_inflated_beta,bounds=(0.,100.)),
        observation_prior=(precision=LogNormal(log(12),.4),endpoint_logit=Normal(-2.,.6),upper_logit=Normal(0.,.7)),
        population=(person=LogNormal(log(.5),.35),recording=.3,assessor=ass),
        predictors=(person=(mean_rate=Normal(0,.6),),assessor=(experience=Normal(0,.5),),response=(rate_change=Normal(0,.6),)),
        decompose=(rate=(between=:mean_rate,within=:rate_change),),intercept=Normal(0,1.))
    d,o
end

@testset "Matching slope contrast units" begin
 d,o=slope_fixture();t=mfrm_spec(d;o...)
 a="coefficient[response,rate_change]";b="slope[assessor,rate_change,1]"
 @test RS.contrast_unit(t,a,b)===:interior_mean_logit_per_declared_predictor_unit
 @test RS.contrast_unit(t,b,a)===:interior_mean_logit_per_declared_predictor_unit
 @test_throws ArgumentError RS.contrast_unit(t,"coefficient[person,mean_rate]",b)
 @test_throws ArgumentError RS.contrast_unit(t,a,"correlation[assessor,rate_change]")
end
function slope_reference(t,q)
    eff=Dict{Symbol,Any}();lp=zero(eltype(q));lv=zero(eltype(q));sv=Dict{Symbol,Any}()
    for b in t.residuals
        s=b.hyper==0 ? b.sd : exp(b.logmean+b.logsd*q[b.hyper]);e=s.*q[b.raw];eff[b.name]=e
        matching=filter(x->x.owner===b.name,RS.slope_blocks(t))
        if isempty(matching)
            lp+=sum(logpdf.(Normal(0,s),e));lv+=length(e)*log(s)
        else
            a=only(matching);s1=a.hyper==0 ? a.scale.sd : exp(a.scale.logmean+a.scale.logsd*q[a.hyper])
            rho=a.corr_raw==0 ? zero(eltype(q)) : tanh(q[a.corr_raw]);c=sqrt(1-rho^2)
            e1=s1.*(rho.*q[b.raw].+c.*q[a.raw]);sv[b.name]=e1
            cov=[s^2 s*s1*rho;s*s1*rho s1^2]
            for j in eachindex(e)
                pair=[e[j],e1[j]];lp+=-log(2pi)-logdet(cov)/2-dot(pair,cov\pair)/2
            end
            lv+=length(e)*logdet(cov)/2
            if a.hyper>0;lp+=logpdf(LogNormal(a.scale.logmean,a.scale.logsd),s1);lv+=log(a.scale.logsd*s1);end
            if a.corr_raw>0
                lp+=logpdf(Beta(a.correlation.eta,a.correlation.eta),(rho+1)/2)-log(2)
                lv+=log(1-rho^2)
            end
        end
        if b.hyper>0;lp+=logpdf(LogNormal(b.logmean,b.logsd),s);lv+=log(b.logsd*s);end
    end
    shift=zeros(eltype(q),length(t.y))
    for p in t.terms
        z=p.mean+p.sd*q[p.raw];lp+=logpdf(Normal(p.mean,p.sd),z);lv+=log(p.sd)
        p.owner===:response ? (shift.+=z.*p.values) : (eff[p.owner].+=z.*p.values)
    end
    p=t.observation_prior;off=t.location.dimension
    phi=exp(p.precision.logmean+p.precision.logsd*q[off+1]);z=p.endpoint_logit.mean+p.endpoint_logit.sd*q[off+2];h=p.upper_logit.mean+p.upper_logit.sd*q[off+3]
    lp+=logpdf(LogNormal(p.precision.logmean,p.precision.logsd),phi)+logpdf(Normal(p.endpoint_logit.mean,p.endpoint_logit.sd),z)+logpdf(Normal(p.upper_logit.mean,p.upper_logit.sd),h)
    lv+=log(p.precision.logsd*phi*p.endpoint_logit.sd*p.upper_logit.sd)
    prior=lp+lv
    for n in eachindex(t.y)
        eta=eff[:person][t.person[n]]+shift[n]
        for b in t.facets;eta-=eff[b.name][b.index[n]];end
        for b in RS.slope_blocks(t);eta+=(b.owner===:person ? 1 : -1)*sv[b.owner][RS._owner_index(t,b.owner)[n]]*t.table[b.column][n];end
        y=t.y[n];mu=1/(1+exp(-eta))
        lp+=y==0 ? logpdf(BernoulliLogit(z),1)+logpdf(BernoulliLogit(h),0) : y==1 ? logpdf(BernoulliLogit(z),1)+logpdf(BernoulliLogit(h),1) : logpdf(BernoulliLogit(z),0)+logpdf(Beta(mu*phi,(1-mu)*phi),y)-log(100)
    end
    (;density=lp+lv,prior,jacobian=lv)
end
@testset "Declared population intercept/slope target" begin
 for corr in (0.,LKJ(2,1.),LKJ(2,2.5))
    d,o=slope_fixture(;correlation=corr);t=mfrm_spec(d;o...)
    @test validate_design(t).identified
    @test RS.record(RS.restore(RS.record(t)))==RS.record(t)
    for q in (zeros(t.dimension),.25sin.(1:t.dimension),collect(range(-.8,.8;length=t.dimension)))
        ref=slope_reference(t,q)
        @test logposterior(t,q)≈ref.density atol=1e-8
        @test logprior(t,q)≈ref.prior atol=1e-9
        @test coordinates(t,q).log_volume≈ref.jacobian atol=1e-9
        @test last(logdensity_and_gradient(t,q))≈ForwardDiff.gradient(x->slope_reference(t,x).density,q) atol=1e-7 rtol=1e-8
        @test sum(pointwise_loglikelihood(t,q))+logprior(t,q)≈logposterior(t,q) atol=1e-9
        fs=BayesianMGMFRM._explanatory_power_definitions(t)
        @test sum(BayesianMGMFRM._explanatory_factor_value(f,q) for f in fs)+coordinates(t,q).log_volume≈logprior(t,q) atol=1e-9
        @test length(parameter_names(t;scale=:raw))==t.dimension
        @test length(RS.model_draws(t,reshape(q,1,:)).names)==length(parameter_names(t;scale=:model))
    end
 end
 d,o=slope_fixture();t=mfrm_spec(d;o...);b=only(RS.slope_blocks(t));q=zeros(t.dimension)
 for a in (-6.,6.)
    q[b.corr_raw]=a
    @test last(logdensity_and_gradient(t,q))≈ForwardDiff.gradient(x->logposterior(t,x),q) atol=1e-7 rtol=1e-7
 end
 # LKJ(2,2) is uniform neither in Fisher coordinates nor over the correlation.
 rr=[tanh(prior_draw(t;seed=j)[b.corr_raw]) for j in 1:2000]
 @test abs(mean(rr))<.04
 @test abs(var(rr)-1/5)<.025
 @test logprior(t,zeros(t.dimension))≈slope_reference(t,zeros(t.dimension)).prior
 # Same finite covariance transformed for reversed predictor units.
 dr=deepcopy(d);dr[:rate].=-dr[:rate];tr=mfrm_spec(dr;o...);q=.3sin.(1:t.dimension);qr=copy(q)
 for p in t.terms;p.column in (:mean_rate,:rate_change) && (qr[p.raw]=-q[p.raw]);end
 qr[b.raw].=-q[b.raw];qr[b.corr_raw]=-q[b.corr_raw]
 @test logposterior(t,q)≈logposterior(tr,qr) atol=1e-9
 @test predict(t,q).expected_score≈predict(tr,qr).expected_score atol=1e-10
 # Constant slope is structurally confounded with the intercept (keep design inspectable).
 dc=deepcopy(d);dc[:rate].=1.;tc=mfrm_spec(dc;o...)
 @test !validate_design(tc).identified
 @test any(contains("slope"),validate_design(tc).reasons)
 # Dimension mismatch on LKJ for 2 slopes (requires LKJ(3, eta) or 0) throws ArgumentError; valid LKJ(3, 2.0) succeeds!
 @test_throws ArgumentError mfrm_spec(d;merge(o,(population=merge(o.population,(assessor=(intercept=.4,slopes=(rate_change=.3,mean_rate=.2),correlation=LKJ(2,2.)),)),predictors=merge(o.predictors,(response=(rate_change=Normal(0,.6),mean_rate=Normal(0,.6)),))))...)
 @test_throws ArgumentError mfrm_spec(d;merge(o,(population=merge(o.population,(assessor=(intercept=.4,slopes=(rate_change=.3,),correlation=.3),)),))...)
 @test_throws ArgumentError mfrm_spec(d;merge(o,(predictors=(person=o.predictors.person,assessor=o.predictors.assessor),))...)
 # New rows preserve order, known-owner means and the slope column.
 sub=RS.bounded_prediction_target(t,Dict(k=>v[[4,1]] for (k,v) in t.table if k!=:score))
 @test predict(sub,q).expected_score≈predict(t,q).expected_score[[4,1]]

 # Multi-slope (K=2, D=3) ZOIB and CountTarget verification (analytic gradient, LKJ(3, eta) normalization, scientific factors, contrasts)
 for corr in (0., LKJ(3, 1.0), LKJ(3, 2.5))
    ass2=(intercept=LogNormal(log(.4),.35),slopes=(mean_rate=LogNormal(log(.35),.35),rate_change=LogNormal(log(.6),.4)),correlation=corr)
    o2=merge(o,(population=merge(o.population,(assessor=ass2,)),predictors=(person=NamedTuple(),assessor=o.predictors.assessor,response=(mean_rate=Normal(0,.6),rate_change=Normal(0,.6)))))
    t2=mfrm_spec(d;o2...)
    @test validate_design(t2).identified
    @test RS.record(RS.restore(RS.record(t2)))==RS.record(t2)
    q2=.22 .* sin.(1:t2.dimension)
    lp2,g2=logdensity_and_gradient(t2,q2)
    @test g2 ≈ ForwardDiff.gradient(x->first(logdensity_and_gradient(t2,x)),q2) atol=1e-9 rtol=1e-9
    @test sum(pointwise_loglikelihood(t2,q2))+logprior(t2,q2) ≈ lp2 atol=1e-9
    fs2=BayesianMGMFRM._explanatory_power_definitions(t2)
    @test sum(BayesianMGMFRM._explanatory_factor_value(f,q2) for f in fs2)+coordinates(t2,q2).log_volume ≈ logprior(t2,q2) atol=1e-9
    @test RS.contrast_unit(t2,"coefficient[response,mean_rate]","slope[assessor,mean_rate,1]")===:interior_mean_logit_per_declared_predictor_unit
    @test RS.contrast_unit(t2,"coefficient[response,rate_change]","slope[assessor,rate_change,1]")===:interior_mean_logit_per_declared_predictor_unit

    # Shared LocationDesign on CountTarget (:beta_binomial) with K=2 slopes
    dcnt=merge(d,Dict(:trials=>fill(10,length(d[:score])),:succ=>Int[mod(Int(s),11) for s in d[:score]]))
    tc2=mfrm_spec(dcnt;person=:speaker,score=:succ,facets=(recording=:clip,assessor=:judge),performance=:clip,
        observation=(family=:beta_binomial,trials=:trials),observation_prior=(precision=LogNormal(log(8.),.4),),
        population=o2.population,predictors=o2.predictors,decompose=o2.decompose,intercept=o2.intercept)
    @test validate_design(tc2).identified
    @test RS.record(RS.restore(RS.record(tc2)))==RS.record(tc2)
    qc2=.18 .* cos.(1:tc2.dimension)
    lpc2,gc2=logdensity_and_gradient(tc2,qc2)
    @test gc2 ≈ ForwardDiff.gradient(x->first(logdensity_and_gradient(tc2,x)),qc2) atol=1e-9 rtol=1e-9
    fsc2=BayesianMGMFRM._explanatory_power_definitions(tc2)
    @test sum(BayesianMGMFRM._explanatory_factor_value(f,qc2) for f in fsc2)+coordinates(tc2,qc2).log_volume ≈ logprior(tc2,qc2) atol=1e-9
 end
end
