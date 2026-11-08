module CriterionCollapsePredictionChecks
using BayesianMGMFRM, Test, Statistics, JSON3
const B=BayesianMGMFRM
const C=B.Experimental.CriterionCollapse
include("fixtures/experimental_diagnostic_record.jl")

# Independent enumeration over the persistent class AND every binary indicator.
function enumerated(t,q,category,signs;ordinary=false)
    s=C.coordinates(t,q); probs=zeros(t.data.n,2,t.K)
    for n in 1:t.data.n,z in 0:1
        steps=z==0 ? s.delta[t.criterion[n],:] : vec(mean(s.delta;dims=1))
        logits=[0.;cumsum(s.theta[t.person[n]]-s.severity[t.rater[n]].-steps)]
        p=exp.(logits.-maximum(logits));probs[n,z+1,:]=p/sum(p)
    end
    states=collect(Iterators.product(fill(0:1,t.R)...))
    weights=[prod((zs[r]==0 ? exp(s.log1mpi) : exp(s.logpi)) for r in 1:t.R)*
        prod(probs[n,zs[t.rater[n]]+1,t.score[n]+1] for n in 1:t.data.n) for zs in states]
    weights ./=sum(weights)
    support=collect(sum(min(signs[t.rater[n]],0) for n in 1:t.data.n):
        sum(max(signs[t.rater[n]],0) for n in 1:t.data.n))
    mass=zeros(length(support)); p0=weights[1]
    for (j,zs) in enumerate(states)
        ordinary && j!=1 && continue
        for ys in Iterators.product(fill(0:1,t.data.n)...)
            count=sum(signs[t.rater[n]]*ys[n] for n in 1:t.data.n)
            probability=prod(ys[n]==1 ? probs[n,zs[t.rater[n]]+1,category+1] :
                1-probs[n,zs[t.rater[n]]+1,category+1] for n in 1:t.data.n)
            mass[count-first(support)+1]+=weights[j]*probability/(ordinary ? p0 : 1.)
        end
    end
    (;support,mass,p0)
end

@testset "Persistent classes and conditional joint prediction" begin
    d=B.FacetData((;person=repeat([1,2];inner=4),item=repeat([1,2];outer=4),
        rater=repeat([1,1,2,2];outer=2),score=[0,1,2,0,2,1,0,2]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    _,base=diagnostic_target(:CriterionCollapse);t=C.model(d;prior=base.prior)
    qs=reduce(vcat,[permutedims(.6sin.(collect(1:B.LogDensityProblems.dimension(t)).+j)) for j in 1:3])
    for signs in ([1,1],[-1,1],[0,-1]), model in (:mixture,:all_ordinary)
        design=C._count_design(t,1,Dict(1=>signs[1],2=>signs[2]),3,model,100000)
        x=C._count_values(t,qs,design,model)
        oracles=[enumerated(t,q,1,signs;ordinary=model===:all_ordinary) for q in eachrow(qs)]
        weights=model===:all_ordinary ? getproperty.(oracles,:p0) : ones(3)
        expected=sum(weights[j]*oracles[j].mass for j in 1:3)/sum(weights)
        @test x.support==first(oracles).support
        @test x.pmf≈expected atol=2e-13
        @test x.values[:,1]≈[sum(o.support.*o.mass) for o in oracles] atol=1e-13
        @test x.values[:,3]≈[sum(o.mass[o.support.>=design.observed]) for o in oracles] atol=1e-13
        @test exp.(x.logweights)≈weights atol=1e-14
        @test x.max_mass_error<1e-13
        if model===:all_ordinary && signs==[-1,1]
            unweighted=mean(getproperty.(oracles,:mass))
            @test maximum(abs.(unweighted-expected))>1e-5
        end
    end
    # Correlated class weights must be multiplied within a draw, not afterwards.
    @test mean([(.9*.9),(.1*.1)])≈.41
    @test prod([mean([.9,.1]),mean([.9,.1])])≈.25
    for a in ([.25,.75],[1.,1.])
        v=[0.,2.];run=diagnostic_record(:CriterionCollapse).run
        @test C._ratio_summary(repeat(v;outer=40),repeat(a;outer=40),run).estimate≈sum(a.*v)/sum(a)
    end
    for bad in (Dict(3=>1),Dict(1=>.5),Dict(1=>true),Dict(1=>0),Dict(1=>2))
        @test_throws ArgumentError C._count_design(t,1,bad,3,:mixture,10000)
    end
    @test_throws ArgumentError C._count_design(t,3,nothing,3,:mixture,10000)
    @test_throws ArgumentError C._count_design(t,true,nothing,3,:mixture,10000)
    @test_throws ArgumentError C._count_design(t,1,nothing,3,:new_rater,10000)
    for budget in (true,0,-1,Inf,1.5,1)
        @test_throws ArgumentError C._count_design(t,1,nothing,3,:mixture,budget)
    end
    # A large class logit may round probabilities to a boundary, never to certainty.
    run=diagnostic_record(:CriterionCollapse).run
    for z in (-1000.,1000.)
        raw=repeat(permutedims(C.initial(t)),40,1);raw[:,end].=z
        x=C._comparison_values(t,raw,run)
        @test x.probability_boundary && x.mcse_warning
        @test ismissing(x.log_bf_ordinary_vs_any_collapse.mcse)
    end
end

@testset "Shared public routes, provenance, controls and persistence" begin
    r=diagnostic_record(:CriterionCollapse);t=C._restore(r)
    c=compare_models(r)
    @test c.prior_all_ordinary.probability≈1/(t.R+1)
    @test c.prior_all_ordinary.probability!=.5^t.R
    p=[prod(1 .- C.components(t,q).weights) for q in eachrow(r.run.draws)]
    @test c.posterior_all_ordinary.mean≈mean(p) atol=1e-13
    @test c.log_bf_ordinary_vs_any_collapse.estimate≈log(mean(p)/(1-mean(p))*t.R) atol=1e-12
    @test c.source_sample_content_hash==r.content_hash
    @test c.qualification.focal_precision_qualification===:not_assessed
    @test !c.precision_threshold_applied && !c.automatic_classification
    @test_throws MethodError compare_models(r;unknown=true)
    @test_throws ArgumentError criteria(r)
    @test_throws ArgumentError compare_models(diagnostic_record(:RaterGroupEffects))
    f=predictive_check(r;category=1,rater_weights=Dict("r1"=>-1,"r2"=>1),model=:all_ordinary)
    @test f.lower_tail.estimate+f.upper_tail.estimate≈1+f.observed_mass.estimate
    @test sum(f.pmf)≈1.
    @test f.expected_count.estimate≈sum(f.support.*f.pmf)
    @test f.pmf_precision===:not_assessed && f.count_quantile_precision===:not_assessed
    @test !f.weight_concentration.is_mcmc_ess
    @test f.chain_ids==r.run.chain_ids && f.iterations==r.run.iterations
    @test_throws MethodError predictive_check(r;category=1,seed=42)
    @test_throws ArgumentError predictive_check(r;category=1,max_count_updates=1)
    @test_throws ArgumentError predictive_check(r;category=1,rater_weights=Dict("missing"=>1))
    mktempdir() do dir
        save_fit(joinpath(dir,"fit.jls"),r)
        loaded=load_fit(joinpath(dir,"fit.jls"))
        @test compare_models(loaded).posterior_all_ordinary.mean==c.posterior_all_ordinary.mean
        for (i,report) in enumerate((c,f,predictive_check(r;category=0)))
            path=joinpath(dir,"$i.json");receipt=save_report(path,report;return_receipt=true)
            restored=load_report(path;expected_sha256=receipt.sha256)
            @test String(restored.kind)==String(report.kind)
            @test restored.source_sample_content_hash==report.source_sample_content_hash
            @test restored.sampling_warning==report.sampling_warning
            @test_throws ArgumentError load_report(path;expected_sha256="0"^64)
            @test_throws ArgumentError save_report(path,report)
            @test_throws MethodError load_report(path;expected_sha256=receipt.sha256,unknown=true)
        end
        @test_throws ArgumentError save_report(joinpath(dir,"bad.json"),merge(f,(;pmf=zeros(length(f.pmf)))))
        @test !isfile(joinpath(dir,"bad.json"))
        for key in (:conditioning,:statistic,:n_observations,:weight_denominator,:qualification,:mcse_warning)
            broken=Base.structdiff(f,NamedTuple{(key,)}((nothing,)))
            @test_throws ArgumentError save_report(joinpath(dir,"missing.json"),broken)
        end
        @test_throws ArgumentError save_report(joinpath(dir,"bad-weight.json"),merge(f,(;rater_weights=[(;rater="r1",weight=2)])))
        @test_throws ArgumentError save_report(joinpath(dir,"bad-condition.json"),merge(c,(;conditioning=:different_prior)))
    end
    # Missing telemetry cannot be hidden by a derived report.
    run=merge(r.run,(;sampler_stats=r.run.sampler_stats[1:end-1]))
    body=merge(Base.structdiff(r,(;content_hash=nothing)),(;run));bad=merge(body,(;content_hash=B._cache_hash(body)))
    @test_throws ArgumentError compare_models(bad)
end
end
