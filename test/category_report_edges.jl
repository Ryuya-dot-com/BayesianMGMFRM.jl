function additional_checks(output; crossloading=true)
@testset "Category report cross-loading and anchored binary cases" begin
    if crossloading
    # The second ability contributes to the crossing of a cross-loaded item.
    fit=R.reporting_fit(:mgmfrm;chains=2,ndraws=20,warmup=0,q_matrix=Bool[1 1;0 1])
    fit_checks(fit,12,output)
    context=B._recovery_context(fit);spec=context.spec
    base=profile(spec); shifted=merge(base,(;id="shifted",fixed_abilities=Dict(2=>1.4)))
    a=report(fit;profiles=[base]);b=report(fit;profiles=[shifted])
    _,steps=B._category_report_steps(context)
    checked=only(B._category_profiles([base],spec,context.total_draws,10000))
    for name in ("rater_consistency[rater=$(base.rater)]",
            "item_dimension_discrimination[item=$(base.item),$(spec.dimension_labels[1])]")
        for value in (0.,-1.,Inf)
            broken=deepcopy(context)
            only(filter(r->r.parameter==name,broken.coordinates)).values[1]=value
            @test_throws ArgumentError B._category_profile_terms(broken,steps,checked)
        end
    end
    coords=Dict(r.parameter=>r for r in context.coordinates)
    slope1=coords["item_dimension_discrimination[item=$(base.item),$(spec.dimension_labels[1])]"]
    slope2=coords["item_dimension_discrimination[item=$(base.item),$(spec.dimension_labels[2])]"]
    for (x,y) in zip(a.crossing_rows,b.crossing_rows)
        @test y.crossing.mean-x.crossing.mean≈-mean(slope2.values./slope1.values) atol=1e-12
    end
    end
    data=FacetData((;person=[1,1,2,2,3,3],rater=[1,2,1,2,1,2],item=[1,2,2,1,1,2],score=[0,1,1,0,1,0]);
        person=:person,rater=:rater,item=:item,score=:score,category_levels=0:1)
    anchored=R.reporting_fit(:mfrm;data,chains=2,ndraws=20,warmup=0,
        anchors=[(;block=:rater,level=2,value=.25,type=:hard),(;block=:item,level=1,value=-.4,type=:hard)])
    pr=(;id="anchored",item=1,rater=2,dimension=1,ability_grid=[-1.,0.,1.])
    result=report(anchored;profiles=[pr])
    @test all(r->r.fixed && r.summary.mean==0 && r.summary.mcse.mean_mcse==0,result.threshold_rows)
    @test only(result.crossing_rows).crossing.mean≈-.15
    @test only(result.crossing_rows).crossing.fixed
    @test only(result.crossing_rows).crossing.mcse.mean_mcse==0
    @test all(r->r.probability.fixed && r.probability.mcse.mean_mcse==0,result.curve_rows)
    for row in result.curve_rows
        p=1/(1+exp(-(row.ability+.15)))
        @test row.probability.mean≈(row.category==1 ? p : 1-p)
    end
end
end
