using Test, BayesianMGMFRM, Random, Statistics, ForwardDiff
using BayesianMGMFRM.GlassBox
using BayesianMGMFRM.Legacy
using Distributions: Normal, LogNormal

function repeated_fixture(;P=8,R=6,J=3)
    rng=Xoshiro(9101);means=randn(rng,P);dev=randn(rng,P,J)
    dev.-=sum(dev;dims=2)./J
    rates=[means[p]+dev[p,j] for p in 1:P for j in 1:J]
    rows=[(p,j,r) for p in 1:P for j in 1:J for r in 1:R if mod(r+p+j,R)<3+mod(j,3)]
    e=collect(range(-1,1;length=R))
    d=Dict{Symbol,Vector}(:speaker=>[p for (p,j,r) in rows],
        :talk=>[(p-1)*J+j for (p,j,r) in rows],:judge=>[r for (p,j,r) in rows],
        :prompt=>fill("one",length(rows)),:rating=>[mod(p+j+r,4) for (p,j,r) in rows],
        :rate=>[rates[(p-1)*J+j] for (p,j,r) in rows],:experience=>[e[r] for (p,j,r) in rows])
    o=(person=:speaker,performance=:talk,score=:rating,
        facets=(presentation=:talk,assessor=:judge,prompt=:prompt),steps=:global,category_levels=0:3,
        prior_sd=(facets=(prompt=0.,),step=.45),
        population=(person=LogNormal(log(.6),.45),presentation=LogNormal(log(.4),.45),assessor=LogNormal(log(.35),.45)),
        decompose=(rate=(between=:mean_rate,within=:rate_change),),
        predictors=(person=(mean_rate=Normal(0,.6),),response=(rate_change=Normal(0,.6),),
            assessor=(experience=Normal(0,.6),)),intercept=Normal(0,.8))
    d,o
end

@testset "Unique-performance decomposition and preserved estimands" begin
    A=BayesianMGMFRM.AdditiveFacets;d,o=repeated_fixture();saved=deepcopy(d);t=mfrm_spec(d;o...)
    @test d==saved
    @test validate_design(t).identified
    @test validate_design(t).covariance_rank==3
    @test contract(t).multiplier==1
    manual=deepcopy(d);expected=Dict(p=>mean([only(unique(d[:rate][d[:talk].==j])) for j in unique(d[:talk][d[:speaker].==p])]) for p in unique(d[:speaker]))
    manual[:mean_rate]=[expected[p] for p in d[:speaker]];manual[:rate_change]=d[:rate].-manual[:mean_rate]
    @test all(abs.(t.table[:mean_rate].-manual[:mean_rate]).<=4eps(maximum(abs,d[:rate])))
    @test all(abs.(t.table[:rate_change].-manual[:rate_change]).<=4eps(maximum(abs,d[:rate])))
    plain=mfrm_spec(manual;merge(o,(decompose=nothing,))...)
    for q in (zeros(t.dimension),.21sin.(1:t.dimension))
        @test logposterior(t,q)≈logposterior(plain,q) atol=1e-12
        @test logposterior(t,q)≈explanatory_reference(t,q).density atol=1e-10
        @test last(logdensity_and_gradient(t,q))≈ForwardDiff.gradient(x->explanatory_reference(t,x).density,q) atol=1e-9
    end
    @test any(p->!isapprox(mean(d[:rate][d[:speaker].==p]),expected[p]),unique(d[:speaker]))
    # Alter rating multiplicity without changing the set of performances.
    ix=[findfirst(==(j),d[:talk]) for j in unique(d[:talk])]
    thin=mfrm_spec(Dict(k=>v[ix] for (k,v) in d);o...)
    @test thin.table[:mean_rate]==t.table[:mean_rate][ix]
    @test !validate_design(thin).identified # no performance replication for its estimated SD
    rev=mfrm_spec(Dict(k=>reverse(v) for (k,v) in d);o...)
    @test rev.table[:mean_rate]==reverse(t.table[:mean_rate])
    @test rev.table[:rate_change]==reverse(t.table[:rate_change])
    q=.17sin.(1:t.dimension);qr=copy(q)
    for (a,b) in zip(t.residuals,rev.residuals)
        a.kind===:iid_population || continue
        old=A._owner_levels(t,a.name);new=A._owner_levels(rev,b.name)
        qr[b.raw]=q[a.raw][[only(findall(==(x),old)) for x in new]]
    end
    @test logposterior(t,q)≈logposterior(rev,qr) atol=1e-10
    rec=A.record(t);@test endswith(rec.schema,".v2")
    @test isequal(A.record(A.restore(rec)),rec)
    @test endswith(A.record(plain).schema,".v1")
    bad=deepcopy(rec);bad.specification.decomposition.rules[1].means[1]+=.1
    @test_throws ArgumentError A.restore(bad)
    @test_throws ArgumentError A.restore(merge(rec,(schema="bayesianmgmfrm.explanatory_facet_design.v1",)))
    sub=[1,8,31];new=Dict(k=>v[sub] for (k,v) in d if k!=:rating)
    pred=A.prediction_target(t,new)
    @test pred.table[:mean_rate]==t.table[:mean_rate][sub]
    @test predictive_probabilities(pred,q)≈predictive_probabilities(t,q)[sub,:] atol=1e-14
    new[:rate][1]+=.1
    @test_throws ArgumentError A.prediction_target(t,new)
    new=Dict(k=>v[sub] for (k,v) in d if k!=:rating);new[:talk][1]=1000
    @test_throws ArgumentError A.prediction_target(t,new)
    # Unknown performance also refused when performance is only grouping metadata.
    noeff=merge(o,(facets=(assessor=:judge,prompt=:prompt),population=(person=.6,assessor=.35)))
    mt=mfrm_spec(d;noeff...)
    @test_throws ArgumentError A.prediction_target(mt,new)
    bad=deepcopy(d);bad[:rate][1]+=.1
    @test_throws ArgumentError mfrm_spec(bad;o...)
    bad=deepcopy(d);bad[:speaker][1]=99
    @test_throws ArgumentError mfrm_spec(bad;o...)
    for x in (NaN,Inf,missing,true)
        bad=Dict{Symbol,Vector}(k=>Any[v...] for (k,v) in d);bad[:rate][1]=x
        @test_throws ArgumentError mfrm_spec(bad;o...)
    end
    for rule in ((rate=(between=:speaker,within=:w),),(rate=(between=:rate,within=:w),),
                 (rate=(between=:x,within=:x),),(rate=(between=:x,within=:y,weights=:r),))
        @test_throws ArgumentError mfrm_spec(d;merge(o,(decompose=rule,))...)
    end
    @test_throws ArgumentError mfrm_spec(d;merge(o,(performance=nothing,))...)
    bad=deepcopy(d);bad[:mean_rate]=zeros(length(d[:rate]))
    @test_throws ArgumentError mfrm_spec(bad;o...)
    @test isequal(A.record(mfrm_spec(t.table;o...)),rec)
    flat=deepcopy(d);flat[:rate]=Float64.(flat[:speaker]);ft=mfrm_spec(flat;o...)
    @test !validate_design(ft).identified
    @test_throws ArgumentError BayesianMGMFRM.fit(ft;ndraws=10,warmup=10,chains=2,seed=1)
    one,oo=repeated_fixture(;J=1);ot=mfrm_spec(one;oo...)
    @test !validate_design(ot).identified
    @test validate_design(ot).covariance_rank==2
    # Only coefficients from the same declared source have assured common units.
    bn="coefficient[person,mean_rate]";wn="coefficient[response,rate_change]"
    @test A.contrast_unit(t,bn,wn)==:unit_logit_per_decomposed_predictor_unit
    @test_throws ArgumentError A.contrast_unit(t,bn,"coefficient[assessor,experience]")
    @test_throws ArgumentError A.contrast_unit(plain,bn,wn)
    scaled=deepcopy(d);scaled[:rate].*=10
    so=merge(o,(predictors=(person=(mean_rate=Normal(0,.06),),response=(rate_change=Normal(0,.06),),assessor=o.predictors.assessor),))
    @test logposterior(mfrm_spec(scaled;so...),q)≈logposterior(t,q) atol=1e-10
end
