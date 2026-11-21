using BayesianMGMFRM, Test
@testset "Group location estimability on the linked response design" begin
    ratings=(id=[1,1,2,2,3,3,4,4],item=repeat(["A","B"],4),score=[1,0,0,1,1,1,0,0])
    spec=mfrm_spec(ratings;person=:id,score=:score,facets=(item=:item,),steps=:global,
        category_levels=0:1,fixed_calibration=(facets=(item=Dict("A"=>0.0),),))
    roster=(id=[1,2,3,4],study=["first","first","second","second"],practice=[0.,1.,0.,1.])
    check(r;kwargs...)=BayesianMGMFRM.MRCML.population_design(spec,r;person=:id,
        group=:study,reference="first",covariates=(:practice,),kwargs...)
    a=check(roster)
    @test a.full_rank && a.rank==a.columns==3 && all(t->t.identifiable,a.mean_terms)
    @test a.X==[0 0;0 1;1 0;1 1]
    @test check(map(reverse,roster))==a
    @test check(roster;reference="second").X[:,1]==1 .- a.X[:,1]
    dup=check(merge(roster,(practice=[0.,0.,1.,1.],)))
    @test !dup.full_rank && dup.rank==2 && all(t->!t.identifiable,dup.mean_terms)
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

@testset "Scalar group regressions share a measurement scale" begin
    ratings = (id=repeat(1:9,inner=2), item=repeat(["A","B"],9), score=repeat([0,1,1,0,1,1],3))
    roster = (id=collect(1:9), panel=repeat([:z,:a,:k],inner=3), x=repeat([-1.,0.,1.],3))
    measurement = (;person=:id,score=:score,facets=(item=:item,),steps=:global,
        category_levels=0:1,fixed_calibration=(facets=(item=Dict("A"=>0.),),))
    population = (;roster=map(reverse,roster),person=:id,group=:panel,reference=:k,covariates=(:x,))
    prior = (;coefficient_prior=Normal(-.15,.8),sd_prior=LogNormal(.1,.4))
    s = mfrm_spec(ratings;measurement...,population)
    t = mfrm_spec(ratings;measurement...,population=merge(population,prior),prior_sd=(facets=(item=.9,),step=0.))
    d = design_summary(s).population
    @test d.groups==[:a,:k,:z] && d.people==roster.id
    @test d.X==hcat(roster.panel.==:a,roster.panel.==:z,roster.x)
    @test contract(s).supported_methods==(:mmle,)
    @test :jmle ∉ contract(t).supported_methods
    @test_throws ArgumentError fit(s;method=:jmle)
    @test_throws ArgumentError fit(s;method=:mmle,estimate_sd=true)
    @test_throws ArgumentError mfrm_spec(s;population)
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,prior))
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population,prior_sd=(facets=(item=1.,),step=0.))
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,prior),
        prior_sd=(person=1.5,facets=(item=1.,),step=0.))
    duplicate = merge(roster,(;x=Float64.(roster.panel.==:a)))
    @test_throws ArgumentError mfrm_spec(ratings;measurement...,population=merge(population,(;roster=duplicate)))
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
