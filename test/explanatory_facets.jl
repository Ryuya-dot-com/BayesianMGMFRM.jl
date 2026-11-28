using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Random, Statistics
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal, Gamma, logpdf, truncated, LocationScale, TDist, cdf
import LogDensityProblems as L
const EF=BayesianMGMFRM.AdditiveFacets

function explanatory_fixture(;P=12,R=6,K=4)
    pairs=[(p,r) for p in 1:P for r in 1:R if mod(p+r,3)!=0]
    x=collect(range(-1,1;length=P));e=collect(range(-1,1;length=R))
    d=Dict{Symbol,Vector}(:speaker=>first.(pairs),:judge=>last.(pairs),
        :prompt=>fill("one",length(pairs)),:rating=>[mod(p+2r,K) for (p,r) in pairs],
        :rate=>[x[p] for (p,r) in pairs],:experience=>[e[r] for (p,r) in pairs],
        :moderation=>[x[p]*e[r] for (p,r) in pairs])
    opts=(person=:speaker,score=:rating,facets=(assessor=:judge,prompt=:prompt),steps=:global,
        category_levels=0:K-1,prior_sd=(person=.7,facets=(prompt=0.,),step=K==2 ? 0. : .45),
        population=(assessor=LogNormal(log(.5),.5),),
        predictors=(person=(rate=Normal(.1,.6),),assessor=(experience=Normal(-.1,.6),),
            response=(moderation=Normal(0,.6),)),intercept=Normal(0,.8))
    d,opts
end

# Independent direct construction in model coordinates. It does not call
# production coordinates, step transforms, likelihood or Stan export.
function explanatory_reference(t,q;centered_prior=false)
    H(m)=[i<=j ? 1/sqrt(j*(j+1)) : i==j+1 ? -j/sqrt(j*(j+1)) : 0. for i in 1:m,j in 1:m-1]
    effects=Dict{Symbol,Any}();lp=zero(eltype(q));lv=zero(eltype(q))
    for b in t.residuals
        sigma=b.hyper==0 ? b.sd : b.scale_kind===:lognormal ? exp(b.logmean+b.logsd*q[b.hyper]) : exp(q[b.hyper])
        z=q[b.raw];m=length(z)
        v=b.kind===:iid_population ? sigma*z : sigma*H(m+1)*z
        effects[b.name]=v
        if centered_prior
            m>0 && (lp+=sum(logpdf.(Normal(0,sigma),sigma*z));lv+=m*log(sigma))
            if b.hyper>0
                prior=b.scale_kind===:lognormal ? LogNormal(b.logmean,b.logsd) :
                    b.scale_kind===:half_normal ? truncated(Normal(0,b.logsd),0,Inf) :
                    truncated(LocationScale(0,b.logsd,TDist(b.logmean)),0,Inf)
                lp+=logpdf(prior,sigma);lv+=log(sigma)+(b.scale_kind===:lognormal ? log(b.logsd) : 0)
            end
        end
    end
    shift=zeros(eltype(q),length(t.person))
    for term in t.terms
        b=term.mean+term.sd*q[term.raw]
        if term.owner===:response;shift.+=b.*term.values
        else;effects[term.owner].+=b.*term.values;end
        centered_prior && (lp+=logpdf(Normal(term.mean,term.sd),b);lv+=log(term.sd))
    end
    K=length(t.categories);tau=[t.step_scale*H(K-1)*q[r] for r in t.steps]
    if centered_prior
        for r in t.steps
            if !isempty(r)
                lp+=sum(logpdf.(Normal(0,t.step_scale),t.step_scale*q[r]));lv+=length(r)*log(t.step_scale)
            end
        end
    else
        lp=sum(logpdf.(Normal(),q))
    end
    prior=lp
    for n in eachindex(t.person)
        eta=effects[:person][t.person[n]]+shift[n]
        for b in t.facets;eta-=effects[b.name][b.index[n]];end
        w=[k*eta-sum(tau[t.group[n]][1:k]) for k in 0:K-1]
        mx=maximum(w);lp+=w[t.category[n]]-mx-log(sum(exp.(w.-mx)))
    end
    (;density=lp+lv,prior=prior+lv,volume=lv)
end

@testset "Scalar explanatory target, ownership and population meaning" begin
    for K in (2,4)
        d,o=explanatory_fixture(;K);t=mfrm_spec(d;o...)
        @test validate_design(t).identified
        @test length(parameter_names(t))==t.dimension
        @test t isa EF.ExplanatoryTarget
        @test contract(t).multiplier==1
        for q in (zeros(t.dimension),[.21sin(j) for j in 1:t.dimension],collect(range(-2,2;length=t.dimension)))
            ref=explanatory_reference(t,q)
            @test logposterior(t,q)≈ref.density atol=1e-10 rtol=0
            lp,g=logdensity_and_gradient(t,q)
            @test lp≈ref.density atol=1e-10 rtol=0
            @test g≈ForwardDiff.gradient(x->explanatory_reference(t,x).density,q) atol=1e-9 rtol=0
            @test g≈ForwardDiff.gradient(x->logposterior(t,x),q) atol=1e-9 rtol=0
            centered=explanatory_reference(t,q;centered_prior=true)
            @test centered.density≈ref.density atol=1e-10
            @test centered.prior≈logprior(t,q) atol=1e-10
            @test centered.volume≈coordinates(t,q).log_volume atol=1e-12
            @test lp≈logprior(t,q)+sum(pointwise_loglikelihood(t,q)) atol=1e-10
            @test all(abs.(sum(predictive_probabilities(t,q);dims=2).-1).<1e-12)
            @test sum(coordinates(t,q).facets[:assessor]) != 0 || all(iszero,q)
        end
        @test all(isfinite,coordinates(t,zeros(Int,t.dimension)).person)
        @test logposterior(t,fill(1e9,t.dimension)) == -Inf
        @test all(isnan,last(logdensity_and_gradient(t,fill(1e9,t.dimension))))
        @test_throws ArgumentError predictive_probabilities(t,fill(1e9,t.dimension))
        r=EF.restore(EF.record(t));@test isequal(EF.record(t),EF.record(r))
        @test logposterior(r,zeros(r.dimension))==logposterior(t,zeros(t.dimension))
        s=simulate(t;seed=35);@test s.simulated==simulate(t;seed=35,q=s.truth).simulated
        @test sum(prior_predictive_check(t;ndraws=3,seed=51).replicated_counts)==3length(t.person)
        q=prior_draw(t;seed=31);pred=Dict(k=>v[[3,1,5]] for (k,v) in d if k!=:rating)
        p=EF.prediction_target(t,pred)
        @test predictive_probabilities(p,q)≈predictive_probabilities(t,q)[[3,1,5],:] atol=1e-14
        pred[:experience][1]+=.1
        @test_throws ArgumentError EF.prediction_target(t,pred)
        bad=deepcopy(d);bad[:experience][1]+=.1
        @test_throws ArgumentError mfrm_spec(bad;o...)
        bad=deepcopy(d);bad[:rate][1]=NaN
        @test_throws ArgumentError mfrm_spec(bad;o...)
        @test_throws ArgumentError mfrm_spec(d;merge(o,(population=(assessor=Gamma(2,1),),))...)
        @test_throws ArgumentError mfrm_spec(d;merge(o,(prior_sd=(person=.7,facets=(assessor=.5,prompt=0.),step=o.prior_sd.step),))...)
        # Duplicate direct/latent effects are not separated by their names or priors.
        duplicate=merge(o.predictors,(response=(moderation=Normal(0,.6),rate=Normal(0,.6)),))
        aliased=mfrm_spec(d;merge(o,(predictors=duplicate,))...)
        @test !validate_design(aliased).identified
        @test_throws ArgumentError fit(aliased;ndraws=10,warmup=10,chains=2,seed=11)
        # A unit conversion transports the coefficient prior, including its mean.
        scaled=deepcopy(d);scaled[:rate].*=10
        po=merge(o.predictors,(person=(rate=Normal(.01,.06),),))
        st=mfrm_spec(scaled;merge(o,(predictors=po,))...)
        @test logposterior(st,q)≈logposterior(t,q) atol=1e-12
        # Known SDs and population mean regression are explicit alternatives.
        fixed=mfrm_spec(d;merge(o,(population=(assessor=.5,),))...)
        @test count(b->b.hyper>0,fixed.residuals)==0
        @test validate_design(fixed).identified
    end
    d,o=explanatory_fixture()
    d[:performance]=copy(d[:speaker])
    alias=mfrm_spec(d;person=:speaker,score=:rating,facets=(assessor=:judge,performance_owner=:performance),
        steps=:global,category_levels=0:3,prior_sd=(facets=(;),step=.45),
        population=(person=LogNormal(0,.5),assessor=LogNormal(0,.5),performance_owner=LogNormal(0,.5)))
    @test !validate_design(alias).identified
    @test validate_design(alias).covariance_rank==2
    @test_throws ArgumentError fit(alias;ndraws=10,warmup=10,chains=2,seed=1)
    # Names and facet count have no behavior: five extra singleton facets are valid.
    for j in 1:5;d[Symbol("c",j)]=fill("constant",length(d[:rating]));end
    fs=merge(o.facets,(alpha=:c1,banana=:c2,cobalt=:c3,delta=:c4,ember=:c5))
    ps=merge(o.prior_sd,(facets=(prompt=0.,alpha=0.,banana=0.,cobalt=0.,delta=0.,ember=0.),))
    t=mfrm_spec(d;merge(o,(facets=fs,prior_sd=ps))...)
    @test design_summary(t).n_facets==8
    @test validate_design(t).identified
    q=prior_draw(t;seed=47)
    @test logposterior(t,q)≈explanatory_reference(t,q).density atol=1e-10
    # Fixed SD iid populations do not impose exact sample centering.
    v=coordinates(t,q)
    @test sum(v.facets[:assessor]) != 0
    @test all(iszero,v.facets[:banana])
end

@testset "Explanatory ownership, coordinate transport and varied facets" begin
    d,o=explanatory_fixture()
    for extra in ((;steps=:assessor),
            (;population=(person=LogNormal(log(.7),.4),assessor=LogNormal(log(.5),.5)),
              prior_sd=(facets=(prompt=0.,),step=.45)))
        t=mfrm_spec(d;merge(o,extra)...);q=.11sin.(1:t.dimension)
        @test validate_design(t).identified
        @test logposterior(t,q)≈explanatory_reference(t,q).density atol=1e-10
        @test last(logdensity_and_gradient(t,q))≈ForwardDiff.gradient(x->explanatory_reference(t,x).density,q) atol=1e-9
    end
    t=mfrm_spec(d;o...);rev=Dict(k=>reverse(v) for (k,v) in d);r=mfrm_spec(rev;o...)
    q=.17sin.(1:t.dimension);qr=copy(q)
    for (a,b) in zip(t.residuals,r.residuals)
        a.kind===:iid_population || continue
        old=EF._owner_levels(t,a.name);new=EF._owner_levels(r,b.name)
        qr[b.raw]=q[a.raw][[only(findall(==(x),old)) for x in new]]
    end
    @test logposterior(t,q)≈logposterior(r,qr) atol=1e-10
    @test predictive_probabilities(t,q)≈reverse(predictive_probabilities(r,qr);dims=1) atol=1e-13
    combos=collect(Iterators.product(1:5,1:2,1:2,1:2,1:2,1:2,1:2))[:]
    many=Dict{Symbol,Vector}(:p=>[x[1] for x in combos],:y=>[mod(i,4) for i in eachindex(combos)],
        :x=>Float64[x[1]-3 for x in combos],:e=>Float64[2x[2]-3 for x in combos])
    fs=(alpha=:a,banana=:b,cobalt=:c,delta=:d,ember=:e_id,fern=:f)
    for (j,c) in enumerate(values(fs));many[c]=[x[j+1] for x in combos];end
    m=mfrm_spec(many;person=:p,score=:y,facets=fs,steps=:cobalt,category_levels=0:3,
        prior_sd=(person=.7,facets=(banana=.4,cobalt=.4,delta=.4,ember=.4,fern=.4),step=.45),
        population=(alpha=LogNormal(log(.5),.5),),
        predictors=(person=(x=Normal(0,.5),),alpha=(e=Normal(0,.5),)),intercept=Normal(0,.8))
    @test design_summary(m).n_facets==7
    @test validate_design(m).identified
    q=.12sin.(1:m.dimension)
    @test logposterior(m,q)≈explanatory_reference(m,q).density atol=1e-9
    @test last(logdensity_and_gradient(m,q))≈ForwardDiff.gradient(x->explanatory_reference(m,x).density,q) atol=1e-8
end

@testset "Explanatory HalfNormal/Half-t scales: normalized measure and persistence" begin
    d,o=explanatory_fixture()
    for prior in (truncated(Normal(0,.8),0,Inf), truncated(LocationScale(0,.7,TDist(4)),0,Inf))
        t=mfrm_spec(d;merge(o,(;population=(assessor=prior,)))...)
        b=only(b for b in t.residuals if b.name===:assessor)
        @test EF.record(t).schema=="bayesianmgmfrm.explanatory_facet_design.v4"
        restored=EF.restore(EF.record(t))
        for u in (-20.,-1.2,0.,1.1)
            q=.12sin.(1:t.dimension);q[b.hyper]=u
            ref=explanatory_reference(t,q;centered_prior=true)
            lp,g=logdensity_and_gradient(t,q)
            @test lp≈ref.density atol=1e-10
            @test logprior(t,q)≈ref.prior atol=1e-10
            @test coordinates(t,q).log_volume≈ref.volume atol=1e-10
            @test g≈ForwardDiff.gradient(x->explanatory_reference(t,x;centered_prior=true).density,q) atol=1e-9
            @test logposterior(restored,q)==logposterior(t,q)
            @test logposterior(t,BigFloat.(q))≈lp atol=1e-10
            defs=BayesianMGMFRM._explanatory_power_definitions(t)
            @test sum(BayesianMGMFRM._explanatory_factor_value(f,q) for f in defs)+ref.volume≈logprior(t,q) atol=1e-10
        end
        rng=MersenneTwister(726)
        draws=[cdf(prior,exp(EF._prior_draw!(rng,t)[b.hyper])) for _ in 1:10000]
        @test abs(mean(draws)-.5)<.015
        @test abs(mean(draws .< .1)-.1)<.012
        bad=merge(EF.record(t),(;coordinates=:white_standard_normal))
        @test_throws ArgumentError EF.restore(bad)
        @test_throws ArgumentError EF._population_parameters(prior,:assessor) # other families retain their contract
    end
    for p in (truncated(Normal(1,1),0,Inf),truncated(Normal(),.1,Inf),truncated(Normal(),0,1))
        @test_throws ArgumentError mfrm_spec(d;merge(o,(;population=(assessor=p,)))...)
    end
end
