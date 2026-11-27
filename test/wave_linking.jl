using BayesianMGMFRM, Test, Statistics
@testset "Observed links and estimable wave changes" begin
    ids=Any["a",:a,3,4]
    tbl=(person=repeat(1:9,inner=4),recording=repeat(ids,9),rating=[mod(i+j,3) for i in 1:9 for j in 1:4])
    opts=(person=:person,score=:rating,facets=(recording=:recording,),category_levels=0:2)
    refs=Dict("a"=>.2,:a=>.6,3=>1.0,4=>.5)
    groups=[(block=:recording,levels=Any["a",:a],mean=.4)]
    fixed=(groups=groups,facets=(recording=Dict(3=>1.),),steps=(owner=:global,values=Dict(:global=>Dict(2=>.2))))
    spec=mfrm_spec(tbl;opts...,fixed_calibration=fixed,prior=:none)
    first=(p=[1,1,2,3,4],id=Any[:a,"a",3,5,5])
    for method in (:mmle,:jmle)
        f=fit(spec;method,estimate_mean=method===:mmle)
        a=anchor_linking_summary(first,f;block=:recording,reference=refs,person=:p,level=:id)
        @test a.qualified && a.interval_kind===:observed_information_wald
        @test a.connectivity.preliminary_components==3 && a.connectivity.receiving_components==1
        @test a.connectivity.combined_components==2 && a.connectivity.shared_levels==3
        @test a.connectivity.preliminary_people==4 && a.connectivity.receiving_people==9
        @test length(a.connectivity.rows)==5 && length(a.common_parameters)==3
        @test only(a.groups).member_free_df==1 && only(a.groups).imposed_change≈0
        @test only(d for d in a.dimensions if d.block===:recording).conditional_free_df==2
        step=only(d for d in a.dimensions if d.block===:steps)
        @test (step.locations,step.conditional_free_df,step.additional_step_constraints)==(2,0,1)
        @test (a.panel.status===:estimated)==(method===:mmle)
        byid=Dict(r.level=>r for r in a.common_parameters)
        @test byid["a"].label.kind===:string && byid[:a].label.kind===:symbol
        @test byid[3].role===:hard_anchor && ismissing(byid[3].displacement)
        @test byid["a"].displacement.se==byid["a"].receiving.se
        @test isapprox(byid[:a].displacement.estimate,-byid["a"].displacement.estimate;atol=1e-10)
        @test byid[:a].displacement.lower≈byid[:a].receiving.estimate-refs[:a]-1.959963984540054*byid[:a].receiving.se
        none=anchor_linking_summary((person=[1],recording=["q"]),f;block=:recording,reference=Dict())
        @test none.connectivity.combined_components==2 && isempty(none.common_parameters)
        absent=anchor_linking_summary(first,f;block=:recording,reference=Dict("a"=>.2),person=:p,level=:id)
        @test ismissing(only(r for r in absent.common_parameters if r.level===:a).displacement)
        @test ismissing(only(absent.groups).preliminary_statistic)
        @test_throws ArgumentError anchor_linking_summary(first,f;block=:recording,reference=Dict(),person=:p,level=:absent)
        @test_throws ArgumentError anchor_linking_summary(tbl,f;block=:recording,reference=Dict(true=>0.))
        @test_throws ArgumentError anchor_linking_summary(tbl,f;block=:recording,reference=refs,interval=1.)
        mktempdir() do dir
            path=joinpath(dir,"sub","links.json")
            receipt=save_report(path,a;return_receipt=true)
            restored=load_report(path;expected_sha256=receipt.sha256)
            @test Set(r.label.kind for r in restored.common_parameters)==Set(["integer","string","symbol"])
            @test_throws ArgumentError save_report(path,a)
            @test_throws ArgumentError load_report(path;expected_sha256=repeat("0",64))
        end
    end
    # Each receiving step owner keeps its own centered block.
    owner=mfrm_spec(tbl;opts...,steps=:recording,fixed_calibration=(groups=groups,
        steps=(owner=:recording,values=Dict(:a=>Dict(2=>.1))),),prior=:none)
    f=fit(owner;method=:mmle,estimate_mean=true)
    owned_report=anchor_linking_summary(tbl,f;block=:recording,reference=refs)
    @test owned_report.step_owner===:recording
    d=owned_report.dimensions
    @test sort([x.conditional_free_df for x in d if x.block===:steps])==[0,1,1,1]
    # An uncertain common coordinate is updated by both sources under one shared location.
    cal=(coordinates=[(block=:recording,level=3,estimate=1.)],covariance=fill(.2,1,1))
    bayes=mfrm_spec(tbl;opts...,calibration=cal,prior_sd=(person=1.,facets=(recording=.7,),step=.4),
        intercept=BayesianMGMFRM.Distributions.Normal())
    short=fit(bayes;method=:nuts,chains=2,warmup=25,ndraws=20,seed=923)
    b=anchor_linking_summary(tbl,short;block=:recording,reference=refs,interval=.8)
    @test !b.qualified && b.interval_kind===:equal_tailed_posterior
    carried=only(r for r in b.common_parameters if r.level==3)
    @test carried.role===:shared_calibration && carried.transferred==1. && ismissing(carried.displacement)
    free=only(r for r in b.common_parameters if r.level==4)
    @test free.displacement.posterior_sd==free.receiving.posterior_sd && ismissing(free.displacement.se)
    @test free.displacement.upper≈free.receiving.upper-.5
    # The two panels can reuse the same person label without gaining a bridge.
    g=BayesianMGMFRM._wave_link_graph([1,2],["a","b"],[1,2],["b","c"])
    @test g.combined_components==3 && g.shared_levels==1
end
