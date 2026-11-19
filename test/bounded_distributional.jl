function distribution_fixture(;P=8,R=6)
    d,o=slope_fixture(;P,R)
    d[:condition]=[isodd(p+r) ? -.5 : .5 for (p,r) in zip(d[:speaker],d[:judge])]
    d[:score][1:3]=[0.,100.,50.]
    op=(precision=(intercept=LogNormal(log(12),.35),predictors=(response=(condition=Normal(0,.7),),),population=(assessor=LogNormal(log(.2),.35),)),
        endpoint_logit=(intercept=Normal(-1.,.6),predictors=(response=(condition=Normal(0,.7),),),population=(assessor=.15,)),
        upper_logit=(intercept=Normal(0,.6),predictors=(response=(condition=Normal(0,.7),),),population=(assessor=.15,)))
    d,merge(o,(;observation_prior=op))
end

# Independent scientific densities and direct link predictors; base pair uses its
# previously independently verified full-covariance reference, not the new kernels.
function distribution_reference(t,base,q)
    v=q[1:base.dimension];old=slope_reference(base,v);prior=old.prior;lv=old.jacobian
    eff=Dict{Symbol,Any}();shift=zeros(eltype(q),length(t.y))
    for r in base.residuals
        s=r.hyper==0 ? r.sd : exp(r.logmean+r.logsd*q[r.hyper]);eff[r.name]=s.*q[r.raw]
    end
    for p in base.terms
        beta=p.mean+p.sd*q[p.raw]
        p.owner===:response ? (shift.+=beta.*p.values) : (eff[p.owner].+=beta.*p.values)
    end
    eta=eff[:person][t.person]+shift
    for r in base.facets;eta.-=eff[r.name][r.index];end
    for r in RS.slope_blocks(base)
        s=r.hyper==0 ? r.scale.sd : exp(r.scale.logmean+r.scale.logsd*q[r.hyper]);rho=r.corr_raw==0 ? 0. : tanh(q[r.corr_raw])
        z=s.*(rho.*q[r.intercept_raw].+sqrt(1-rho^2).*q[r.raw])
        eta.+=(r.owner===:person ? 1 : -1).*z[RS._owner_index(t,r.owner)].*t.table[r.column]
    end
    p=t.observation_prior;off=t.location.dimension
    pars=repeat(reshape([p.precision.logmean+p.precision.logsd*q[off+1],p.endpoint_logit.mean+p.endpoint_logit.sd*q[off+2],p.upper_logit.mean+p.upper_logit.sd*q[off+3]],1,3),length(t.y),1)
    for b in RS.distribution_blocks(t)
        for p in b.terms
            beta=p.mean+p.sd*q[p.raw];x=t.table[p.column]
            if p.by!==nothing;x=x.*([RS._owner_levels(t,p.by)[i] for i in RS._owner_index(t,p.by)].==p.level);end
            pars[:,b.index].+=beta.*x
            prior+=logpdf(Normal(p.mean,p.sd),beta)+log(p.sd);lv+=log(p.sd)
        end
        for r in b.residuals
            s=r.hyper==0 ? r.sd : exp(r.logmean+r.logsd*q[r.hyper]);e=s.*q[r.raw]
            pars[:,b.index].+=e[RS._owner_index(t,r.name)]
            prior+=sum(logpdf.(Normal(0,s),e))+length(e)*log(s);lv+=length(e)*log(s)
            if r.hyper>0
                jac=log(r.logsd*s);prior+=logpdf(LogNormal(r.logmean,r.logsd),s)+jac;lv+=jac
            end
        end
    end
    ll=zero(first(q))
    for n in eachindex(t.y)
        y=t.y[n];mu=1/(1+exp(-eta[n]));phi=exp(pars[n,1]);z=pars[n,2];h=pars[n,3]
        ll+=y==0 || y==1 ? logpdf(BernoulliLogit(z),1)+logpdf(BernoulliLogit(h),Int(y)) :
            logpdf(BernoulliLogit(z),0)+logpdf(Beta(phi*mu,phi*(1-mu)),y)-log(100)
    end
    (;density=prior+ll,prior,jacobian=lv,pars,eta)
end

@testset "ZOIB declared distributional blocks" begin
 d,o=distribution_fixture();t=mfrm_spec(d;o...)
 bp=(;(k=>getproperty(o.observation_prior,k).intercept for k in RS.BOUNDED_PARAMETERS)...)
 base=mfrm_spec(d;merge(o,(observation_prior=bp,))...)
 @test keys(predict(t,zeros(t.dimension)))==(:interior_mean,:expected_score,:lower_probability,:upper_probability)
 @test RS.contrast_unit(t,"precision[assessor,1]","precision[assessor,2]")===:log_precision
 @test_throws ArgumentError RS.contrast_unit(t,"residual_sd[precision,assessor]","residual_sd[assessor]")
 @test_throws ArgumentError RS.contrast_unit(t,"residual_sd[precision,assessor]","residual_sd[upper_logit,assessor]")
 @test validate_design(t).identified
 @test RS.record(RS.restore(RS.record(t)))==RS.record(t)
 for q in (zeros(t.dimension),.2sin.(1:t.dimension),collect(range(-.6,.6;length=t.dimension)))
    r=distribution_reference(t,base,q)
    @test logposterior(t,q)≈r.density atol=1e-9
    @test logprior(t,q)≈r.prior atol=1e-9
    @test coordinates(t,q).log_volume≈r.jacobian atol=1e-9
    @test last(logdensity_and_gradient(t,q))≈ForwardDiff.gradient(x->distribution_reference(t,base,x).density,q) atol=1e-7 rtol=1e-8
    @test sum(pointwise_loglikelihood(t,q))+logprior(t,q)≈logposterior(t,q) atol=1e-9
    @test [BayesianMGMFRM._rating_log_cell(t,coordinates(t,q),n) for n in eachindex(t.y)]≈pointwise_loglikelihood(t,q) atol=1e-12
    factors=BayesianMGMFRM._explanatory_power_definitions(t)
    @test sum(BayesianMGMFRM._explanatory_factor_value(f,q) for f in factors)+coordinates(t,q).log_volume≈logprior(t,q) atol=1e-9
    m=predict(t,q;metrics=RS.BOUNDED_METRICS)
    @test m.precision≈exp.(r.pars[:,1])
    @test m.endpoint_probability≈1 ./ (1 .+exp.(-r.pars[:,2]))
    @test m.upper_given_endpoint_probability≈1 ./ (1 .+exp.(-r.pars[:,3]))
    @test m.lower_probability+m.upper_probability≈m.endpoint_probability
    @test all(>(0),m.score_sd)
    @test length(parameter_names(t;scale=:raw))==t.dimension
    @test length(RS.model_draws(t,reshape(q,1,:)).names)==size(RS.model_draws(t,reshape(q,1,:)).values,2)
 end
 emptyop=(;(k=>(intercept=getproperty(bp,k),predictors=(;),population=(;)) for k in RS.BOUNDED_PARAMETERS)...)
 @test RS.record(mfrm_spec(d;merge(o,(observation_prior=emptyop,))...))==RS.record(base)
 q=.2sin.(1:t.dimension)
 sub=RS.bounded_prediction_target(t,Dict(k=>v[[3,1]] for (k,v) in t.table if k!=:score))
 @test predict(sub,q;metrics=(:precision,)).precision==predict(t,q;metrics=(:precision,)).precision[[3,1]]
 # Regressions owned by a named facet are positive on their distributional link.
 op=merge(o.observation_prior,(precision=(intercept=bp.precision,predictors=(assessor=(experience=Normal(0,.5),),),population=(assessor=.2,recording=LogNormal(log(.1),.3))),))
 u=mfrm_spec(d;merge(o,(observation_prior=op,))...)
 @test RS.record(RS.restore(RS.record(u)))==RS.record(u)
 q=zeros(u.dimension);b=first(RS.distribution_blocks(u));q[only(b.terms).raw]=1.
 @test predict(u,q;metrics=(:precision,)).precision≈12exp.(.5d[:experience])
 qu=.13cos.(1:u.dimension)
 @test logposterior(u,qu)≈distribution_reference(u,base,qu).density atol=1e-9
 @test last(logdensity_and_gradient(u,qu))≈ForwardDiff.gradient(x->distribution_reference(u,base,x).density,qu) atol=1e-7
 ob=merge(o.observation_prior,(precision=(intercept=bp.precision,predictors=(response=(condition=(prior=Normal(.2,.6),by=:assessor),),),population=(assessor=.2,)),))
 tb=mfrm_spec(d;merge(o,(observation_prior=ob,))...);qb=.15sin.(1:tb.dimension)
 @test RS.record(RS.restore(RS.record(tb)))==RS.record(tb)
 @test logposterior(tb,qb)≈distribution_reference(tb,base,qb).density atol=1e-9
 @test last(logdensity_and_gradient(tb,qb))≈ForwardDiff.gradient(x->distribution_reference(tb,base,x).density,qb) atol=1e-7
 bad=Dict(k=>v[[3,1]] for (k,v) in u.table if k!=:score);bad[:experience][1]+=.1
 @test_throws ArgumentError predict(RS.bounded_prediction_target(u,bad),q)
 # Conditional information is distinct from full design rank.
 dc=deepcopy(d);dc[:score]=[x<0 ? 0. : 50. for x in dc[:condition]];tc=mfrm_spec(dc;o...)
 @test validate_design(tc).identified
 @test any(contains("rank 1/2"),design_summary(tc).warnings)
 dc[:score].=0.;tc=mfrm_spec(dc;o...);g=last(logdensity_and_gradient(tc,zeros(tc.dimension)))
 b=first(RS.distribution_blocks(tc))
 @test g[only(b.terms).raw]==0.
 @test any(contains("No interior"),design_summary(tc).warnings)
 dc=deepcopy(d);dc[:condition].=1.;@test !validate_design(mfrm_spec(dc;o...)).identified
 @test_throws ArgumentError mfrm_spec(d;merge(o,(observation_prior=merge(o.observation_prior,(precision=(predictors=(;),),)),))...)
 @test_throws ArgumentError mfrm_spec(d;merge(o,(observation_prior=merge(o.observation_prior,(precision=(intercept=bp.precision,predictors=(unknown=(condition=Normal(),),)),)),))...)
 @test_throws ArgumentError predict(t,zeros(t.dimension);metrics=(:unknown,))
end
