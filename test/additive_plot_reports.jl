using Test, BayesianMGMFRM, Statistics
const APR=BayesianMGMFRM.AdditiveFacets
@testset "Computed additive prior report boundaries and four fixture replicas" begin
    data=(p=[1,1,2,2],r=[1,2,1,2],y=[0,1,2,1])
    t=mfrm_spec(data;person=:p,score=:y,facets=(judge=:r,),steps=:global,category_levels=0:2,
        prior_sd=(person=1.,facets=(judge=.4,),step=.5))
    counts=[0 1 3;1 2 1;2 2 0;4 0 0]
    rep=APR.prior_report(t,counts;seed=1,source=:deterministic_fixture)
    generated=prior_predictive_check(t;ndraws=2,seed=101)
    @test generated.kind==:prior_predictive && generated.ndraws==2
    @test all(sum(generated.replicated_counts;dims=2).==4)
    @test rep.kind==:prior_predictive && !hasproperty(rep,:qualification)
    @test rep.replicated_counts==counts
    @test rep.rows[1].median==1.5
    @test rep.rows[1].lower≈.075 atol=1e-14
    @test APR.check_plot_report(rep)===rep
    @test_throws ArgumentError APR.prior_report(t,counts[:,1:2];seed=1)
    bad=copy(counts);bad[1,1]=-1
    @test_throws ArgumentError APR.prior_report(t,bad;seed=1)
    @test_throws ArgumentError APR.prior_report(t,counts.+1;seed=1)
    @test_throws ArgumentError APR.prior_report(t,Float64.(counts);seed=1)
    @test_throws ArgumentError APR.prior_report(t,counts;seed=1,interval=1.)
    # Binary and ordinal supports stay separate even when categories overlap.
    m=mfrm_spec((p=[1,1,2,2],r=[1,2,1,2],c=["A","B","A","B"],y=[0,1,1,2]);
        person=:p,score=:y,facets=(judge=:r,rubric=:c),steps=:rubric,
        category_levels=Dict("A"=>0:1,"B"=>1:3),population=(person=1.,),
        prior_sd=(facets=(judge=.4,rubric=.3),step=.5))
    aggregate=[1 1 1 1;0 3 1 0]
    owner=[1 1 0 1 1;0 2 1 1 0]
    mixed=APR.prior_report(m,aggregate;seed=1,owner_counts=owner)
    generated_mixed=prior_predictive_check(m;ndraws=2,seed=103)
    @test length(generated_mixed.rows)==5 && generated_mixed.grouping_by_support
    @test all(sum(generated_mixed.replicated_counts;dims=2).==4)
    @test mixed.grouping_by_support
    @test [r.category for r in mixed.rows]==[0,1,1,2,3]
    @test [r.level for r in mixed.rows]==["A","A","B","B","B"]
    @test all(r.n==2 for r in mixed.rows)
    @test_throws ArgumentError APR.prior_report(m,aggregate;seed=1)
    @test_throws ArgumentError APR.prior_report(m,aggregate;seed=1,owner_counts=owner.+1)
    wrong=copy(owner);wrong[1,:]=[0,2,1,0,1]
    @test_throws ArgumentError APR.prior_report(m,aggregate;seed=1,owner_counts=wrong)
end
@testset "Trace and probability report structural checks" begin
    tr=(;phase=:retained,parameters=["a"],chains=2,draws_per_chain=3,scale=:model,
        series=[(;parameter="a",chain=c,iterations=[1,2,3],values=[.1,.2,.3]) for c in 1:2])
    rep=(;schema=APR.REPORT_SCHEMA,traces=tr)
    @test APR.check_plot_report(rep)===rep
    @test_throws ArgumentError APR.check_plot_report(merge(rep,(traces=merge(tr,(phase=:warmup,)),)))
    @test_throws ArgumentError APR.check_plot_report(merge(rep,(traces=merge(tr,(series=tr.series[1:1],)),)))
    for (field,value) in ((:iterations,[1,3,2]),(:iterations,[1,1,2]),(:values,[NaN,.2,.3]))
        firstrow=merge(tr.series[1],NamedTuple{(field,)}((value,)))
        bad=merge(rep,(traces=merge(tr,(series=[firstrow,tr.series[2]],)),))
        @test_throws ArgumentError APR.check_plot_report(bad)
    end
    cells=[(;position=1,row=7,category=k,mean=k==0 ? 0. : .5,lower=k==0 ? 0. : .2,
        upper=k==0 ? 0. : .8,structural_zero=k==0) for k in 0:2]
    pred=(;schema=APR.PREDICTION_SCHEMA,kind=:prediction,interval_target=:posterior_category_probability,
        interval=.95,rows=[7],category_levels=[0,1,2],cells)
    @test APR.check_plot_report(pred)===pred
    @test_throws ArgumentError APR.check_plot_report(merge(pred,(interval_target=:future_rating,)))
    @test_throws ArgumentError APR.check_plot_report(merge(pred,(cells=cells[1:2],)))
    @test_throws ArgumentError APR.check_plot_report(merge(pred,(cells=reverse(cells),)))
    bad=[merge(cells[1],(;mean=.1)),cells[2:3]...]
    @test_throws ArgumentError APR.check_plot_report(merge(pred,(;cells=bad)))
end
