using BayesianMGMFRM, Test
using BayesianMGMFRM.GlassBox
@testset "Group location estimability on the linked response design" begin
    ratings=(id=[1,1,2,2,3,3,4,4],item=repeat(["A","B"],4),score=[1,0,0,1,1,1,0,0])
    spec=mfrm_spec(ratings;person=:id,score=:score,facets=(item=:item,),steps=:global,
        category_levels=0:1,fixed_calibration=(facets=(item=Dict("A"=>0.0),),),prior=:none)
    roster=(id=[1,2,3,4],study=["first","first","second","second"],practice=[0.,1.,0.,1.])
    check(r;kwargs...)=BayesianMGMFRM.MRCML.population_design(spec,r;person=:id,
        group=:study,reference="first",covariates=(:practice,),kwargs...)
    a=check(roster)
    @test a.full_rank && a.rank==a.columns==4 && all(t->t.identifiable,a.mean_terms)
    @test a.X==[1 0 0;1 0 1;1 1 0;1 1 1]
    @test check(map(reverse,roster))==a
    @test check(roster;reference="second").X[:,2]==1 .- a.X[:,2]
    dup=check(merge(roster,(practice=[0.,0.,1.,1.],)))
    @test !dup.full_rank && dup.rank==3 && first(dup.mean_terms).identifiable && all(t->!t.identifiable,dup.mean_terms[2:end])
    constant=check(merge(roster,(practice=zeros(4),)))
    @test !constant.full_rank && first(constant.mean_terms).identifiable && !last(constant.mean_terms).identifiable
    @test_throws ArgumentError check(merge(roster,(id=[1,1,3,4],)))
    @test_throws ArgumentError check(merge(roster,(id=[1,2,3,5],)))
    @test_throws ArgumentError check(merge(roster,(practice=[NaN,0,0,0],)))
    @test_throws ArgumentError check(roster;reference="absent")
    @test_throws ArgumentError check(roster;covariates=(:practice,:practice))
    @test_throws ArgumentError check(roster;covariates=(:study,))
end

using Distributions: Normal, LogNormal
using ForwardDiff
using LinearAlgebra

@testset "Group person coordinates with estimated item and step calibration" begin
    ids = Any[:a,"a",3,4,5,6,7,8]
    ratings = (id=repeat(ids,inner=4), item=repeat(["A","B","A","B"],8),
               assessment=repeat(1:4,8), score=repeat([0,1,2,1,0,0,1,2],4))
    roster = (id=ids,g=repeat(["ref","other"],inner=4), x=repeat([-1.,1.],4))
    opts = (;person=:id,score=:score,assessment=:assessment,facets=(item=:item,),category_levels=0:2,
        fixed_calibration=(facets=(item=Dict("A"=>-0.7),),),prior_sd=(facets=(item=.9,),step=.7))
    pop = (;roster, person=:id,group=:g,reference="ref",covariates=(:x,),
           coefficient_prior=Normal(.2,.8),sd_prior=LogNormal(-.1,.6))
    target(choice; r=roster, data=ratings) = mfrm_spec(data;opts...,
        population=merge(pop,(;roster=r,person_coordinates=choice)))
    base = mfrm_spec(ratings;opts...,population=pop)
    @test getdesign(base).spec_record == getdesign(target(:noncentered)).spec_record
    choices = Dict(id => isodd(i) ? :centered : :noncentered for (i,id) in enumerate(ids))
    info = target((information_cutoff=3.,))
    pc = design_summary(info).population.person_chart
    # beta has a nonzero prior mean. For routing the ability itself is fixed at zero.
    q0 = zeros(base.dimension)
    d = base.spec_record.population
    q0[1:8] .= -(d.X*fill(.2,length(d.beta))) ./ exp(-.1)
    reference = exp.(BayesianMGMFRM.AdditiveFacets.logprobs(base,q0))
    scores = collect(0:2)
    perrow = reference*(scores.^2) .- (reference*scores).^2
    @test pc.information ≈ exp(-.2) .* [sum(perrow[base.person.==i]) for i=1:8]
    @test pc.centered == (pc.information .>= 3)
    @test target((information_cutoff=3.,);data=merge(ratings,(score=2 .- ratings.score,))).spec_record.population.person_chart == pc
    for choice in (:centered, choices, (information_cutoff=3.,))
        t = target(choice)
        record = BayesianMGMFRM.AdditiveFacets.record(t)
        @test record.schema == "bayesianmgmfrm.mrcml_design.v2"
        @test_throws ArgumentError BayesianMGMFRM.AdditiveFacets.restore(merge(record,(schema="bayesianmgmfrm.mrcml_design.v1",)))
        reordered = target(choice;r=map(reverse,roster),data=map(reverse,ratings))
        centered = t.spec_record.population.person_chart.centered
        choice isa AbstractDict && @test centered == [choices[p] === :centered for p in t.people]
        @test contract(t).supported_methods == (:nuts,)
        @test_throws ArgumentError BayesianMGMFRM.fit(t;method=:mmle)
        @test t.people == reordered.people && centered == reordered.spec_record.population.person_chart.centered
        @test BitVector(stan_data(t)["centered"]) == centered
        @test all(startswith(parameter_names(t;scale=:raw)[p],"person.centered") == centered[p] for p=1:8)
        for seed in (2,13,47)
            z, q = prior_draw(base;seed), prior_draw(t;seed)
            popvals = coordinates(base,z).population
            scales = popvals.group_sd[d.group_index]
            function to_white(x)
                beta = .2 .+ .8 .* x[d.beta]
                sd = exp.(-.1 .+ .6 .* x[d.logsd])[d.group_index]
                vcat(ifelse.(centered,(x[1:8] .- d.X*beta)./sd,x[1:8]),x[9:end])
            end
            jac = -sum(log,scales[centered];init=0.)
            @test to_white(q) ≈ z
            @test logabsdet(ForwardDiff.jacobian(to_white,q))[1] ≈ jac atol=1e-12
            @test coordinates(t,q).person ≈ coordinates(base,z).person
            @test coordinates(t,q).log_volume ≈ coordinates(base,z).log_volume + jac
            @test logprior(t,q) ≈ logprior(base,z) + jac
            @test pointwise_loglikelihood(t,q) ≈ pointwise_loglikelihood(base,z)
            lp,g = logdensity_and_gradient(t,q)
            @test lp ≈ logposterior(base,z) + jac
            matched(x) = logposterior(base,to_white(x)) -
                sum((-.1 .+ .6 .* x[d.logsd])[d.group_index[centered]];init=zero(eltype(x)))
            @test g ≈ ForwardDiff.gradient(matched,q)
            @test logdensity_and_gradient(reordered,q)[2] ≈ g
            @test simulate(t;seed).category == simulate(base;seed).category
        end
    end
    for bad in (:automatic,Dict(:a=>:centered),merge(choices,Dict(9=>:centered)),
                Dict(k=>:wrong for k in ids),(information_cutoff=NaN,),(information_cutoff=true,))
        @test_throws ArgumentError target(bad)
    end
end

@testset "Scalar group regressions share a measurement scale" begin
    ratings = (id=repeat(1:9,inner=2), item=repeat(["A","B"],9), score=repeat([0,1,1,0,1,1],3))
    roster = (id=collect(1:9), panel=repeat([:z,:a,:k],inner=3), x=repeat([-1.,0.,1.],3))
    measurement = (;person=:id,score=:score,facets=(item=:item,),steps=:global,
        category_levels=0:1,fixed_calibration=(facets=(item=Dict("A"=>0.),),))
    population = (;roster=map(reverse,roster),person=:id,group=:panel,reference=:k,covariates=(:x,))
    prior = (;coefficient_prior=Normal(-.15,.8),sd_prior=LogNormal(.1,.4))
    s = mfrm_spec(ratings;measurement...,population,prior=:none)
    t = mfrm_spec(ratings;measurement...,population=merge(population,prior),prior_sd=(facets=(item=.9,),step=0.))
    d = design_summary(s).population
    @test d.groups==[:a,:k,:z] && d.people==roster.id
    @test d.X==hcat(ones(9),roster.panel.==:a,roster.panel.==:z,roster.x)
    @test contract(s).supported_methods==(:mmle,)
    @test :jmle ∉ contract(t).supported_methods
    @test_throws ArgumentError fit(s;method=:jmle)
    @test_throws ArgumentError fit(s;method=:mmle,estimate_sd=true)
    @test_throws ArgumentError mfrm_spec(s;population)
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population)
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,prior))
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,prior),prior=:none)
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population,prior_sd=(facets=(item=1.,),step=0.))
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,prior),
        prior_sd=(person=1.5,facets=(item=1.,),step=0.))
    duplicate = merge(roster,(;x=Float64.(roster.panel.==:a)))
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,(;roster=duplicate)),prior=:none)
    q = collect(range(-.7,.5;length=t.dimension))
    pv = t.spec_record.population
    co = coordinates(t,q)
    @test co.population.coefficients≈-.15 .+ .8 .* q[pv.beta]
    @test co.population.group_sd≈exp.(.1 .+ .4 .* q[pv.logsd])
    @test co.person≈d.X*co.population.coefficients .+ co.population.group_sd[d.group_index].*q[1:9]
    lp,g = logdensity_and_gradient(t,q)
    @test lp≈logposterior(t,q)
    @test g≈ForwardDiff.gradient(a->logposterior(t,a),q)
    @test stan_data(t)["member"]==d.group_index
    @test length(parameter_names(t;scale=:raw))==t.dimension
    @test parameter_names(s;scale=:model)[end-5:end]==parameter_names(t;scale=:model)[end-5:end]
    # A previously valid facet may happen to be named roster.
    old = mfrm_spec(ratings;person=:id,score=:score,facets=(roster=:item,),steps=:global,
        category_levels=0:1,prior_sd=(person=1.,facets=(;),step=0.),
        population=(roster=LogNormal(0.,.4),))
    @test !hasproperty(old,:operator)
end
