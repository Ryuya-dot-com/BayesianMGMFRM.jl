using BayesianMGMFRM, Test, LinearAlgebra, ForwardDiff, Statistics
using Distributions: Normal, LogNormal
@testset "Named subset means on substantive scalar facet locations" begin
    ids = ["a","b","c","d","e"]
    table = (person=repeat(1:10,inner=5),item=repeat(ids,10),
             score=[Int(mod(i+2j,5) < (2+isodd(j))) for i in 1:10 for j in eachindex(ids)])
    opts=(person=:person,score=:score,facets=(item=:item,),category_levels=0:1)
    group=(block=:item,levels=["c","a","b"],mean=.4)
    make(gs;kw...)=mfrm_spec(table;opts...,fixed_calibration=(groups=gs,),kw...)
    par=(person=1.,facets=(item=.7,),step=0.)
    b=make((group,);prior_sd=par,intercept=Normal(.2,.9))
    op=b.operator
    bm=first(op.block_meta)
    C=Matrix(op.J_model[bm.model_range,bm.eta_range])
    origin=op.xi0_model[bm.model_range]
    P=C*C'
    w=[1.,1.,1.,0.,0.]/3
    @test size(C)==(5,4) && C'*C≈I
    @test origin≈[.4,.4,.4,0.,0.] && norm(w'*C)<2e-15
    @test P≈I-w*w'/dot(w,w)
    @test isempty(intersect(op.fixed_model_names,op.model_names[bm.model_range]))
    for v in ([1.,-1.,0.,0.,0.],[1.,0.,-1.,0.,0.],[0.,1.,-1.,0.,0.])
        @test .7^2*dot(v,P*v)≈2*.7^2
    end
    @test design_summary(b).facets[1].unit_contrast_sd==.7
    hyper=make([group];prior_sd=merge(par,(facets=(item=LogNormal(log(.8),.5),),)))
    @test design_summary(hyper).facets[1].unit_contrast_sd_prior_median≈.8
    @test ismissing(design_summary(hyper).facets[1].unit_contrast_sd)
    q=collect(range(-.6,.7,length=length(initial_params(b))))
    @test dot(w,coordinates(b,q).structural_model[bm.model_range])≈.4
    @test last(logdensity_and_gradient(b,q))≈ForwardDiff.gradient(z->logposterior(b,z),q) atol=1e-11
    fixed=(groups=[group,(block=:item,levels=("b","c","d"),sum=1.5),
                         (block=:item,levels=reverse(group.levels),sum=1.2)],facets=(item=Dict("e"=>.7),))
    spec=mfrm_spec(table;opts...,fixed_calibration=fixed)
    L=[1 1 1 0 0;0 1 1 1 0;0 0 0 0 1]
    for t in (table,map(reverse,table))
        s=mfrm_spec(t;opts...,fixed_calibration=fixed)
        m=first(s.operator.block_meta)
        pos=[only(findall(==(id),m.levels)) for id in ids]
        J=Matrix(s.operator.J_model[m.model_range[pos],m.eta_range])
        @test norm(L*J)<2e-14 && J'*J≈I
        @test L*s.operator.xi0_model[m.model_range[pos]]≈[1.2,1.5,.7]
        @test J*J'≈I-L'*((L*L')\L)
        @test "item[\"e\"]" in s.operator.fixed_model_names
        @test only(design_summary(s).fixed_calibration.dimensions)==(block=:item,n_levels=5,constraint_rank=3,free_locations=2)
    end
    disjoint=make([group,(block=:item,levels=("d","e"),sum=-1.)])
    @test only(disjoint.spec_record.fixed_calibration.dimensions).free_locations==3
    fixed_all=make([(block=:item,levels=[k],mean=.1i) for (i,k) in enumerate(ids)])
    @test size(fixed_all.operator.J_model,2)==0 && all(in(fixed_all.operator.fixed_model_names),fixed_all.operator.model_names)
    for bad in ([],[merge(group,(levels=["a","a"],))],[merge(group,(levels=["u"],))],
                [merge(group,(levels=["a",true],))],[merge(group,(levels=[],))],[merge(group,(mean=Inf,))],
                [merge(group,(sum=1.,))],[merge(group,(block=:rater,))],[group,merge(group,(mean=.5,))])
        @test_throws ArgumentError make(bad)
    end
    @test_throws ArgumentError mfrm_spec(table;opts...,fixed_calibration=(facets=(item=Dict("a"=>1.),),
        groups=[(block=:item,levels=["a"],mean=0.)]))
    # Independent elimination coordinates for the joint Hessian; no extremes in this design.
    f=fit(make([group]);method=:jmle)
    @test qualify(f).qualified
    items=f.record.facet_measures
    bhat=[r.estimate for r in items]
    th=[r.estimate for r in f.record.person_scores]
    θ=length(th)
    expand(v)=[v[1],v[2],3*.4-v[1]-v[2],v[3],v[4]]
    function nll(z)
        loc=expand(z[θ+1:end])
        sum(enumerate(table.score)) do (i,y)
            x=z[table.person[i]]-loc[mod1(i,5)]
            log1p(exp(x))-y*x
        end
    end
    z=vcat(th,bhat[[1,2,4,5]])
    @test norm(ForwardDiff.gradient(nll,z),Inf)<1e-5
    H=ForwardDiff.hessian(nll,z)
    D=ForwardDiff.jacobian(expand,z[θ+1:end])
    cov=D*inv(Symmetric(H))[θ+1:end,θ+1:end]*D'
    @test norm(cov-f.record.covariance.matrix[1:5,1:5],Inf)<1e-8
    @test sqrt.(diag(cov))≈[r.se for r in items] && norm(cov*w)<1e-14
    mixed = (person=table.person,item=Any[x=="b" ? :a : x for x in table.item],score=table.score)
    mixed_cal = (groups=[(block=:item,levels=Any[:a,"a"],sum=.8)],)
    fm = fit(mfrm_spec(mixed;opts...,fixed_calibration=mixed_cal);method=:jmle)
    mktempdir() do dir
        path=joinpath(dir,"mixed.json")
        save_report(path,fit_report(fm))
        labels=only(load_report(path).summary.fixed_calibration.groups).level_labels
        @test Set(l.kind for l in labels)==Set(["string","symbol"]) && all(l->l.value=="a",labels)
    end
    # FacetSpec keeps pre-existing hard anchors alongside the new group restriction.
    fd=FacetData(table;person=:person,item=:item,rater=nothing,score=:score,category_levels=0:1)
    fs=mfrm_spec(fd;thresholds=:rating_scale,anchors=[(block=:item,level="e",value=.7)])
    both=mfrm_spec(fs;fixed_calibration=(groups=[group],))
    @test only(both.spec_record.fixed_calibration.dimensions).free_locations==3
    @test both.spec_record.fixed_calibration.anchors[1].level=="e"
end
