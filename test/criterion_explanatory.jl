using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Random, Statistics
using Distributions: Normal, LogNormal, logpdf
const CF=BayesianMGMFRM.AdditiveFacets

function criterion_fixture(;P=12,R=6,supports=Dict("content"=>0:1,"organization"=>1:4,"delivery"=>0:4))
    cs=["content","organization","delivery"]
    rng=MersenneTwister(61111);x=randn(rng,P,3)
    rows=[(p,j,r,c) for p in 1:P for j in 1:3 for r in 1:R if mod(r+p+j,R)<3 for c in cs]
    d=Dict{Symbol,Vector}(:speaker=>[p for (p,j,r,c) in rows],:talk=>[(p-1)*3+j for (p,j,r,c) in rows],
        :judge=>[r for (p,j,r,c) in rows],:aspect=>[c for (p,j,r,c) in rows],
        :rating=>[first(supports[c])+mod(p+j+r,length(supports[c])) for (p,j,r,c) in rows],
        :rate=>[x[p,j] for (p,j,r,c) in rows],:experience=>[(r-1)/(R-1)*2-1 for (p,j,r,c) in rows])
    o=(person=:speaker,performance=:talk,score=:rating,facets=(presentation=:talk,assessor=:judge,rubric=:aspect),
       steps=:rubric,category_levels=supports,
       prior_sd=(facets=(rubric=.4,),step=maximum(length,values(supports))==2 ? 0. : .45),
       population=(person=LogNormal(log(.6),.45),presentation=LogNormal(log(.4),.45),assessor=LogNormal(log(.35),.45)),
       decompose=(rate=(between=:mean_rate,within=:rate_change),),
       predictors=(person=(mean_rate=Normal(0,.6),),assessor=(experience=Normal(0,.6),),
           response=(rate_change=(by=:rubric,prior=Normal(0,.6)),)),intercept=Normal(0,.8))
    d,o
end

# Dense independent maps, local score coding and model-coordinate prior/Jacobian.
# No production transforms, logits, gradients or Stan export are used here.
function criterion_reference(t,q;centered=false)
    helmert(m)=[i<=j ? 1/sqrt(j*(j+1)) : i==j+1 ? -j/sqrt(j*(j+1)) : 0. for i in 1:m,j in 1:m-1]
    effects=Dict{Symbol,Any}();lp=zero(eltype(q));lv=zero(eltype(q))
    for b in t.residuals
        s=b.hyper==0 ? b.sd : exp(b.logmean+b.logsd*q[b.hyper])
        z=q[b.raw];effects[b.name]=s.*(b.kind===:iid_population ? z : helmert(length(z)+1)*z)
        if centered
            !isempty(z) && (lp+=sum(logpdf.(Normal(0,s),s.*z));lv+=length(z)*log(s))
            b.hyper==0 || (lp+=logpdf(LogNormal(b.logmean,b.logsd),s);lv+=log(b.logsd*s))
        end
    end
    shifts=zeros(eltype(q),length(t.person))
    for p in t.terms
        b=p.mean+p.sd*q[p.raw]
        if p.owner===:response;shifts.+=b.*p.values
        else;effects[p.owner].+=b.*p.values;end
        centered && (lp+=logpdf(Normal(p.mean,p.sd),b);lv+=log(p.sd))
    end
    sets=CF.record(t).category_levels
    localsets=sets isa AbstractDict ? [collect(sets[g]) for g in t.group_levels] : fill(collect(sets),length(t.steps))
    tau=[]
    for (g,r) in enumerate(t.steps)
        H=length(localsets[g])-1;s=H>1 ? t.step_sd*sqrt(H/(H-1)) : 0.
        push!(tau,s.*(helmert(H)*q[r]))
        centered && !isempty(r) && (lp+=sum(logpdf.(Normal(0,s),s.*q[r]));lv+=length(r)*log(s))
    end
    centered || (lp=sum(logpdf.(Normal(),q)))
    prior=lp+lv;pointwise=eltype(q)[]
    for n in eachindex(t.person)
        g=t.group[n];K=length(localsets[g]);eta=effects[:person][t.person[n]]+shifts[n]
        for b in t.facets;eta-=effects[b.name][b.index[n]];end
        w=[k*eta-sum(tau[g][1:k]) for k in 0:K-1];mx=maximum(w)
        y=only(findall(==(t.table[t.columns.score][n]),localsets[g]))
        push!(pointwise,w[y]-mx-log(sum(exp.(w.-mx))))
    end
    (;density=prior+sum(pointwise),prior,volume=lv,pointwise)
end

@testset "Criterion-owned supports and same-source effects" begin
    for sets in (Dict("content"=>0:1,"organization"=>1:4,"delivery"=>0:4),
                 Dict("content"=>4:5,"organization"=>-3:0,"delivery"=>7:11),
                 Dict(c=>0:1 for c in ("content","organization","delivery")))
        d,o=criterion_fixture(;supports=sets);t=mfrm_spec(d;o...)
        @test validate_design(t).identified
        @test contract(t).multiplier==1
        @test length(parameter_names(t;scale=:raw))==t.dimension
        @test CF.record(t).schema=="bayesianmgmfrm.explanatory_facet_design.v3"
        @test isequal(CF.record(CF.restore(CF.record(t))),CF.record(t))
        for term in t.terms
            if term.by!==nothing
                @test term.values==t.table[term.column].*(d[:aspect].==term.level)
            end
        end
        for q in (zeros(t.dimension),[.35sin(j) for j in 1:t.dimension],collect(range(-1.5,1.5;length=t.dimension)))
            ref=criterion_reference(t,q);cp=criterion_reference(t,q;centered=true)
            @test logposterior(t,q)≈ref.density atol=1e-10 rtol=0
            @test pointwise_loglikelihood(t,q)≈ref.pointwise atol=1e-12 rtol=0
            lp,g=logdensity_and_gradient(t,q)
            @test lp≈ref.density atol=1e-10 rtol=0
            @test g≈ForwardDiff.gradient(x->criterion_reference(t,x).density,q) atol=1e-9 rtol=0
            @test g≈ForwardDiff.gradient(x->logposterior(t,x),q) atol=1e-9 rtol=0
            @test cp.density≈ref.density atol=1e-10 rtol=0
            @test cp.prior≈logprior(t,q) atol=1e-10 rtol=0
            @test cp.volume≈coordinates(t,q).log_volume atol=1e-10 rtol=0
            probs=predictive_probabilities(t,q)
            @test all(abs.(sum(probs;dims=2).-1).<1e-12)
            @test all(n->all(k->probs[n,k]==0,setdiff(eachindex(t.categories),t.supports[t.group[n]])),eachindex(t.person))
        end
        sim=simulate(t;seed=11,q=zeros(t.dimension))
        @test all(n->sim.simulated[:rating][n] in sets[d[:aspect][n]],eachindex(t.person))
        @test all(isfinite,coordinates(t,zeros(Int,t.dimension)).steps)
        ns=filter(n->occursin(";rubric=",n),parameter_names(t;scale=:model))
        @test length(ns)==3
        @test CF.contrast_unit(t,ns[1],ns[2])==:unit_logit_per_shared_predictor_unit
        @test_throws ArgumentError CF.contrast_unit(t,ns[1],"coefficient[person,mean_rate]")
        m=CF.model_draws(t,zeros(8,t.dimension))
        @test size(m.values,2)==length(m.names)
        @test count(n->startswith(n,"steps["),m.fixed)==count(x->length(x)==2,values(sets))
        sd=stan_data(t)
        @test sd["D"]==sd["R"]+sd["Qstep"]+sd["T"]+sd["V"]
    end
    d,o=criterion_fixture()
    @test_throws ArgumentError mfrm_spec(d;merge(o,(steps=:global,))...)
    @test_throws ArgumentError mfrm_spec(d;merge(o,(category_levels=Dict("content"=>0:1),))...)
    bad=deepcopy(d);bad[:rating][1]=99
    @test_throws ArgumentError mfrm_spec(bad;o...)
    for p in ((by=:missing,prior=Normal()),(by=:rubric,prior=Normal(),extra=1))
        @test_throws ArgumentError mfrm_spec(d;merge(o,(predictors=(response=(rate=p,),),))...)
    end
    @test_throws ArgumentError mfrm_spec(d;merge(o,(predictors=(person=(rate=(by=:rubric,prior=Normal()),),),))...)
    d[:duplicate]=copy(d[:rate])
    alias=mfrm_spec(d;merge(o,(predictors=(response=(rate=Normal(),duplicate=(by=:rubric,prior=Normal())),),))...)
    @test !validate_design(alias).identified
    # A supplied shared-support map and the original vector are the same target.
    sets=Dict(c=>0:3 for c in ("content","organization","delivery"));d,o=criterion_fixture(;supports=sets)
    a=mfrm_spec(d;o...);b=mfrm_spec(d;merge(o,(category_levels=0:3,))...);q=[.17cos(j) for j in 1:a.dimension]
    @test a.dimension==b.dimension
    @test logposterior(a,q)==logposterior(b,q)
    @test logdensity_and_gradient(a,q)==logdensity_and_gradient(b,q)
    @test predictive_probabilities(a,q)==predictive_probabilities(b,q)
    # Renaming a facet does not introduce a special criterion role.
    renamed=mfrm_spec(d;merge(o,(facets=(presentation=:talk,assessor=:judge,aspect_owner=:aspect),steps=:aspect_owner,
        prior_sd=(facets=(aspect_owner=.4,),step=.45),
        predictors=(person=o.predictors.person,assessor=o.predictors.assessor,response=(rate_change=(by=:aspect_owner,prior=Normal(0,.6)),)),))...)
    @test logposterior(renamed,q)==logposterior(a,q)
end
