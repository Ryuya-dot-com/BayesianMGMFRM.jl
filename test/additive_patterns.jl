using Test, BayesianMGMFRM, Distributions
const AP=BayesianMGMFRM.AdditiveFacets
function pattern_fixture(;mixed=false,rename=:rubric)
    rows=[(p,r,c) for p in 1:4 for r in 1:3 for c in ("A","B")]
    d=(p=[x[1] for x in rows],r=[x[2] for x in rows],c=[x[3] for x in rows],
        y=[x[3]=="A" && mixed ? mod(x[1]+x[2],2) : mod(x[1]+x[2],5)+1 for x in rows])
    o=(person=:p,score=:y,facets=NamedTuple{(:judge,rename)}((:r,:c)),steps=rename,
       category_levels=Dict("A"=>(mixed ? (0:1) : (1:5)),"B"=>1:5),
       prior_sd=(person=.6,facets=NamedTuple{(:judge,rename)}((.5,.4)),step=.5))
    d,o
end
@testset "Named, support-aware descriptive rating warnings" begin
    for explanatory in (false,true),case in (:middle,:upper,:judge,:criterion)
        d,o=pattern_fixture()
        if case===:middle;d.y[d.y.==3].=2
        elseif case===:upper;d.y[d.y.==5].=4
        elseif case===:judge;d.y[d.r.==1].=5
        else;d.y[d.c.=="B"].=3;end
        # A map selects the explanatory route; use the base builder explicitly
        # to verify the unchanged ordinary additive target's reporting too.
        t=explanatory ? mfrm_spec(d;o...,intercept=Normal()) : AP.model(d;o...)
        record=AP.record(t);q=fill(.2,t.dimension);before=logposterior(t,q)
        ds=design_summary(t);v=validate_design(t);audit=ds.response_patterns
        @test v.identified==t.allocation.identified
        @test isequal(v.response_patterns,audit)
        @test all(x->x in ds.warnings,audit.warnings)
        @test all(r->r.severity===:warning,audit.issues)
        @test isequal(AP.record(t),record) && logposterior(t,q)==before
        @test sum(r.n_observations for r in audit.category_usage)==length(d.y)
        code=case===:middle ? :unused_interior_category : case===:upper ? :unobserved_declared_endpoint : :constant_score_pattern
        selected=filter(r->r.code===code,audit.issues)
        @test !isempty(selected)
        case===:middle && @test any(r->3 in r.categories,selected)
        case===:upper && @test any(r->5 in r.categories,selected)
        case===:judge && @test any(r->r.facet===:judge && r.level==1 && r.categories==[5],selected)
        case===:criterion && @test count(r->r.step_level=="B" && r.code===:constant_score_pattern,audit.issues)==1
        @test_logs (:warn,r"Observed rating patterns need review") AP.warn_patterns(t)
    end
    d,o=pattern_fixture(mixed=true,rename=:assessment_scale)
    d.y[d.r.==1 .&& d.c.=="A"].=1;d.y[d.r.==1 .&& d.c.=="B"].=5
    t=mfrm_spec(d;o...);a=design_summary(t).response_patterns
    @test all(r->all(k->k in (r.level=="A" ? (0:1) : (1:5)),r.categories),a.category_usage)
    @test all(r->r.step_owner===:assessment_scale,a.issues)
    @test any(r->r.facet===:judge && r.level==1 && r.step_level=="A" && r.position===:maximum,a.constant_patterns)
    @test any(r->r.facet===:judge && r.level==1 && r.step_level=="B" && r.position===:maximum,a.constant_patterns)
    @test all(r->r.step_level!="A" || all(k->k in 0:1,r.categories),a.issues)
    @test all(r->r.n_observations>=2,a.constant_patterns)
    # One observation is not a repeated constant pattern; absent owner remains absent.
    small=(p=[1,2],r=[1,2],y=[1,5])
    t=mfrm_spec(small;person=:p,score=:y,facets=(panel=:r,),steps=:global,
        category_levels=1:5,prior_sd=(person=.6,facets=(panel=.5,),step=.5))
    @test isempty(design_summary(t).response_patterns.constant_patterns)
    same=(p=[1,2],r=[1,2],y=[3,3])
    z=mfrm_spec(same;person=:p,score=:y,facets=(panel=:r,),steps=:global,
        category_levels=1:5,prior_sd=(person=.6,facets=(panel=.5,),step=.5))
    @test any(r->r.facet===:global && r.score==3,design_summary(z).response_patterns.constant_patterns)
end
@testset "CrI reference display boundaries" begin
    row(lo,hi;fixed=false)=(lower=lo,upper=hi,structurally_fixed=fixed)
    rows=[row(-1.,1.),row(0.,1.),row(-1.,0.),row(.1,2.),row(-2.,-.1),row(0.,0.;fixed=true)]
    s=AP.interval_style(rows;reference=0.)
    @test s.states==[:contains,:contains,:contains,:excludes,:excludes,:fixed]
    @test s.markers==[:circle,:circle,:circle,:rect,:rect,:diamond]
    @test AP.interval_style(rows)===nothing
    @test AP.interval_style(rows;reference=1.).states[2]===:contains
    @test AP.interval_style(rows;reference=2.,interval_colors=(contains=:orange,excludes=:purple)).colors[4]===:orange
    @test_throws ArgumentError AP.interval_style(rows;reference=NaN)
    @test_throws ArgumentError AP.interval_style(rows;reference=true)
    @test_throws ArgumentError AP.interval_style(rows;reference=Inf)
    @test_throws ArgumentError AP.interval_style(rows;reference=big"1e1000")
    @test_throws ArgumentError AP.interval_style(rows;interval_colors=(contains=:red,excludes=:blue))
    @test_throws ArgumentError AP.interval_style(rows;reference=0.,interval_colors=(inside=:red,))
    @test_throws ArgumentError AP.interval_style([row(1.,0.)];reference=0.)
    @test_throws ArgumentError AP.interval_style([row(missing,1.)];reference=0.)
end
