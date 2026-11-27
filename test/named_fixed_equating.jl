using BayesianMGMFRM, ForwardDiff, LinearAlgebra, Test
using BayesianMGMFRM.GlassBox
using Distributions: Normal
@testset "Named fixed equating on the response scale" begin
    t = (person=repeat(1:12,inner=4), item=repeat(["z","a","z","a"],12),
         rater=repeat([1,1,2,2],12), score=repeat([5,6,7,6,6,7,6,5],6))
    opts = (person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:global,category_levels=5:7)
    locations = (item=Dict("z"=>1.4,"a"=>0.4),rater=Dict(1=>0.,2=>0.))
    fixed = (facets=locations,steps=(owner=:global,values=Dict(:global=>Dict(6=>-.3,7=>.3))))
    s = mfrm_spec(t;opts...,fixed_calibration=fixed,prior=:none)
    op = s.operator
    @test size(op.A_free,2)==0 && length(op.fixed_model_names)==6
    for (i,name) in enumerate(t.item)
        base=locations.item[name]
        @test op.c_pat[op.pattern_ranges[op.pattern_of_row[i]]] ≈ [0.,-base+.3,-2base]
    end
    f=fit(s;method=:mmle,estimate_mean=true,quad_points=61)
    @test qualify(f).qualified && design_summary(f).population_mean_se>0
    @test qualify(fit(s;method=:jmle)).qualified
    shifted=merge(fixed,(facets=merge(locations,(item=Dict(k=>v+.7 for (k,v) in locations.item),)),))
    fs=fit(mfrm_spec(t;opts...,fixed_calibration=shifted,prior=:none);method=:mmle,estimate_mean=true,quad_points=61)
    @test design_summary(fs).population_mean ≈ design_summary(f).population_mean+.7 atol=1e-7
    @test loglikelihood(fs) ≈ loglikelihood(f) atol=1e-8
    @test design_summary(fs).population_mean_se ≈ design_summary(f).population_mean_se atol=1e-7
    # A partial facet anchor frees the remaining absolute location. One remaining step follows from sum zero.
    owned=(facets=(item=Dict("z"=>.9),),steps=(owner=:item,values=Dict("a"=>Dict(7=>.25))))
    psd=(person=1.,facets=(item=.8,rater=.5),step=.6)
    b=mfrm_spec(t;opts...,steps=:item,fixed_calibration=owned,prior_sd=psd,intercept=Normal(.2,.7))
    for q in (zeros(length(initial_params(b))), collect(range(-.35,.6,length=length(initial_params(b)))))
        v=coordinates(b,q)
        pars=Dict(zip(b.operator.model_names,v.structural_model))
        @test pars["item[\"z\"]"]==.9
        @test pars["steps[\"a\",6]"]==-.25 && pars["steps[\"a\",7]"]==.25
        @test pars["steps[\"z\",6]"]≈-pars["steps[\"z\",7]"]
        @test pars["population_mean"] ≈ .2+.7*q[end]
        _,g=logdensity_and_gradient(b,q)
        @test g ≈ ForwardDiff.gradient(x->logposterior(b,x),q) atol=5e-11
    end
    @test "item[\"a\"]" in b.operator.free_names && "steps[\"a\",6]" in b.operator.fixed_model_names
    # With four centered steps and one fixed value, three unanchored steps share the remainder.
    wide=mfrm_spec(t;opts...,category_levels=4:8,fixed_calibration=(steps=(owner=:global,
        values=Dict(:global=>Dict(8=>.9))),),prior_sd=(person=1.,facets=(item=.8,rater=.5),step=.6))
    active=last(wide.operator.block_meta)
    E=Matrix(wide.operator.J_model[active.model_range,active.eta_range])
    @test E'*E≈I && norm(sum(E;dims=1))<1e-14
    @test wide.operator.xi0_model[active.model_range]≈[-.3,-.3,-.3,.9]
    @test Matrix(E*E')[1:3,1:3]≈Matrix(I,3,3).-ones(3,3)/3
    @test fixed.steps.values[:global]==Dict(6=>-.3,7=>.3)
    data=FacetData(t;person=:person,rater=:rater,item=:item,score=:score,category_levels=5:7)
    legacy=mfrm_spec(data;thresholds=:rating_scale)
    @test_throws ArgumentError mfrm_spec(legacy;fixed_calibration=fixed)
    from_spec=mfrm_spec(legacy;fixed_calibration=fixed,prior=:none)
    @test from_spec.operator.c_pat==s.operator.c_pat
    prior_anchor=mfrm_spec(data;thresholds=:rating_scale,anchors=[(block=:item,level="z",value=1.4)])
    @test mfrm_spec(prior_anchor;fixed_calibration=fixed,prior=:none).operator.c_pat==op.c_pat
    steps_only = mfrm_spec(prior_anchor;fixed_calibration=(steps=fixed.steps,),prior=:none)
    @test any(r->r.kind==:hard && r.block==:item && r.level=="z", steps_only.spec_record.fixed_calibration.anchors)
    repeat_table = merge(t,(id=collect(eachindex(t.score)),))
    no_rater = mfrm_spec(FacetData(repeat_table;person=:person,rater=nothing,item=:item,score=:score,
        category_levels=5:7,response_id=:id);thresholds=:rating_scale)
    single = mfrm_spec(no_rater;fixed_calibration=(facets=(item=locations.item,),steps=fixed.steps),prior=:none)
    row_offsets(o,i) = o.c_pat[o.pattern_ranges[o.pattern_of_row[i]]]
    @test all(i->row_offsets(single.operator,i)==row_offsets(op,i), eachindex(t.score))
    @test all(r->r.block != :rater,single.spec_record.fixed_calibration.anchors)
    @test single.table[:response_id] == repeat_table.id
    @test qualify(fit(single;method=:mmle)).qualified
    @test_throws ArgumentError mfrm_spec(no_rater;fixed_calibration=fixed,prior=:none)
    @test_throws ArgumentError mfrm_spec(t;opts...,steps=:rater,fixed_calibration=(steps=(owner=:rater,values=Dict(true=>Dict(6=>0.))),),prior=:none)
    @test_throws ArgumentError mfrm_spec(prior_anchor;fixed_calibration=shifted,prior=:none)
    for bad in ((facets=(item=Dict("unknown"=>0.),),),(facets=(missing_role=Dict(1=>.3),),),
                (steps=(owner=:item,values=Dict(:global=>Dict(6=>.3))),),
                (steps=(owner=:global,values=Dict(:global=>Dict(1=>.3))),),
                (steps=(owner=:global,values=Dict(:global=>Dict(6=>.3,7=>.4))),),
                (facets=(item=Dict("a"=>Inf),),),(facets=(rater=Dict(true=>1.),),))
        @test_throws ArgumentError mfrm_spec(t;opts...,fixed_calibration=bad,prior=:none)
    end
    @test_throws ArgumentError mfrm_spec(t;opts...,fixed_calibration=fixed,intercept=Normal(),prior=:none)
    @test_throws ArgumentError mfrm_spec(t;opts...,design_matrix=s,fixed_calibration=fixed)
end
