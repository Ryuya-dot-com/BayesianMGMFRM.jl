using BayesianMGMFRM, Test, LinearAlgebra
using BayesianMGMFRM: fit
@testset "External calibration in named group contrasts" begin
    groups=repeat([:left,:reference,:right],inner=24)
    ids=collect(eachindex(groups)); practice=repeat([-1.,1.],36)
    person=repeat(ids,inner=6); item=repeat(["a","b","a","b","a","b"],length(ids))
    totals=[0,1,2,2,2,3,3,4,4,4,5,6]
    score=map(eachindex(person)) do k
        i=person[k]
        shift=groups[i]==:left ? -1 : Int(groups[i]==:right)
        t=clamp(totals[mod1(cld(i,2),12)]+shift,0,6)
        Int(mod(k+cld(i,2),6)<t)
    end
    data=(;person,item,score,occasion=repeat(1:6,length(ids)))
    roster=(id=ids,group=groups,x=practice)
    pop=(;roster,person=:id,group=:group,reference=:reference,covariates=(:x,))
    opts=(person=:person,score=:score,facets=(item=:item,),category_levels=0:1,population=pop,assessment=:occasion)
    anchors=[(block=:item,level="a",estimate=-.65),(block=:item,level="b",estimate=.35)]
    V=[.04 -.018;-.018 .09]
    transfer=(coordinates=anchors,covariance=V)
    function estimates(v)
        spec=mfrm_spec(data;opts...,fixed_calibration=(facets=(item=Dict("a"=>v[1],"b"=>v[2]),),))
        design_summary(fit(spec;method=:mmle,quad_points=41)).population.coefficients
    end
    spec=mfrm_spec(data;opts...,calibration=transfer)
    f=fit(spec;method=:mmle,quad_points=41); s=design_summary(f)
    @test qualify(f).qualified && s.calibration.status==:available
    @test contract(f).calibration_uncertainty==(method=:two_stage_delta,applies_to=:group_reference_contrasts,status=:available)
    @test_throws ArgumentError fit(spec;method=:jmle)
    @test_throws ArgumentError fit(spec;method=:mmle,estimate_mean=true)
    @test ismissing(s.population_mean_se)
    cs=s.calibration.contrasts
    @test getproperty.(cs,:group)==[:left,:right] && all(c->c.reference==:reference,cs)
    v=getproperty.(anchors,:estimate);h=.001
    fixed=estimates(v)
    @test getproperty.(fixed,:estimate)≈getproperty.(s.population.coefficients,:estimate) atol=1e-8
    @test s.population.coefficients[3].se≈fixed[3].se
    for j in eachindex(v)
        d=zeros(2);d[j]=h
        hi=estimates(v+d);lo=estimates(v-d)
        for (i,r) in enumerate(cs)
            @test r.gradient[j] ≈ (hi[i].estimate-lo[i].estimate)/(2h) atol=2e-5
        end
    end
    for (i,r) in enumerate(cs)
        @test r.conditional_se≈fixed[i].se && r.propagated_se==s.population.coefficients[i].se
        @test r.propagated_se^2 ≈ fixed[i].se^2+dot(r.gradient,V*r.gradient)
    end
    alt=fit(mfrm_spec(map(reverse,data);opts...,calibration=(coordinates=reverse(anchors),
        covariance=V[end:-1:1,end:-1:1]));method=:mmle,quad_points=41)
    @test getproperty.(design_summary(alt).calibration.contrasts,:propagated_se)≈getproperty.(cs,:propagated_se)
    refs=Dict("a"=>-.65,"b"=>.35)
    a=anchor_linking_summary(data,f;block=:item,reference=refs,interval=.90)
    @test a.panel.status==:group_contrasts && ismissing(a.panel_conditional_se)
    @test a.panel.contrasts[2].summary.upper≈cs[2].estimate+1.6448536269514722*cs[2].propagated_se
    mktempdir() do dir
        save_fit(joinpath(dir,"f.jls"),f)
        @test design_summary(load_fit(joinpath(dir,"f.jls"))).calibration==s.calibration
        save_report(joinpath(dir,"f.json"),f)
        restored=load_report(joinpath(dir,"f.json")).summary
        @test [r.propagated_se for r in restored.calibration.contrasts]==[r.propagated_se for r in cs]
        @test all(g->g.kind=="symbol",restored.population.design.group_labels)
    end
    # One binary response per person at zero difficulty cannot identify each group SD at mean zero.
    weak=(person=1:16,item=fill("a",16),score=repeat([0,1],8))
    wpop=(roster=(id=1:16,group=repeat([:reference,:other],inner=8)),person=:id,group=:group,reference=:reference)
    wc=(coordinates=[(block=:item,level="a",estimate=0.)],covariance=ones(1,1))
    wf=fit(mfrm_spec(weak;person=:person,score=:score,facets=(item=:item,),category_levels=0:1,
                     population=wpop,calibration=wc);method=:mmle)
    fail=design_summary(wf)
    @test !qualify(wf).qualified && fail.calibration.status==:unqualified_receiving_information
    @test ismissing(only(fail.calibration.contrasts).gradient) && ismissing(only(fail.population.coefficients).se)
end
