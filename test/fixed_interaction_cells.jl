using BayesianMGMFRM, Test, LinearAlgebra, ForwardDiff
using BayesianMGMFRM.GlassBox
using Distributions: LogNormal
@testset "Named fixed cells on doubly centered facet interactions" begin
    p = repeat(1:6,inner=9)
    r = repeat(repeat(["A","B","C"],inner=3),6)
    i = repeat([1,2,3],18)
    tbl = (p=p,r=r,i=i,y=[mod(a+b,3) for a in 1:6 for b in 1:9])
    opts=(person=:p,score=:y,facets=(rater=:r,item=:i),category_levels=0:2,interactions=((:item,:rater),))
    cell=(levels=(item=1,rater="A"),value=.6)
    fix(cs;data=tbl,kw...)=mfrm_spec(data;opts...,fixed_calibration=(cells=cs,),(haskey(kw,:prior_sd) || haskey(kw,:prior) ? (;) : (;prior=:none))...,kw...)
    prior=(person=1.,facets=(rater=.7,item=.8),step=.5,interactions=(rater_item=.9,))
    target=fix([cell];prior_sd=prior)
    op=target.operator
    bm=only(filter(x->x.kind===:facet_facet_interaction,op.block_meta))
    rows=bm.model_range
    C=Matrix(op.J_model[rows,bm.eta_range])
    base=op.xi0_model[rows]
    center=I-ones(3,3)/3
    P=kron(center,center)
    expected=P-P[:,1]*P[1,:]'/P[1,1]
    @test base ≈ [.6,-.3,-.3,-.3,.15,.15,-.3,.15,.15]
    @test size(C)==(9,3) && C'*C≈I && C*C'≈expected && all(iszero,C[1,:])
    @test op.model_names[first(rows)] in op.fixed_model_names
    info=target.spec_record.fixed_calibration
    @test only(info.interaction_dimensions)==(;facets=(:rater,:item),locations=9,centered_df=4,anchor_rank=1,free_df=3)
    @test only(info.anchors).level==("A",1) && only(info.anchors).value===.6
    repeated = fill(.6,4800,1)
    point = only(BayesianMGMFRM._posterior_summary_rows(repeated,["fixed cell"];
        lower=.025,upper=.975,intervals=(.95,),reference=0.,rope=nothing,rope_probability_threshold=.95))
    @test point.mean === .6 && point.sd === 0. && point.lower === point.upper === .6
    pb=only(filter(x->x.name===:rater_item,target.prior_blocks))
    @test pb.scale_vec≈fill(.9*1.5,3)
    @test C*Diagonal(pb.scale_vec.^2)*C'≈(.9*1.5)^2*expected
    @test !target.prior_symmetry.prior_asymmetry_detected
    q=collect(range(-.55,.4,length=length(initial_params(target))))
    v=coordinates(target,q)
    grid=permutedims(reshape(v.structural_model[rows],3,3))
    @test grid[1,1]===.6 && norm(sum(grid;dims=1))<1e-14 && norm(sum(grid;dims=2))<1e-14
    @test abs(v.log_volume-(2log(.7sqrt(3/2))+2log(.8sqrt(3/2))+log(.5sqrt(2))+3log(.9*1.5)))<1e-13
    @test logdensity_and_gradient(target,q)[2]≈ForwardDiff.gradient(x->logposterior(target,x),q) atol=1e-11
    # A fixed logit residual contributes -k times its value to category k.
    for (n,y) in enumerate(tbl.y)
        b=sum(v.blocks[k][j] for (k,j) in ((:rater,findfirst(==(r[n]),["A","B","C"])),(:item,i[n])))
        h=grid[findfirst(==(r[n]),["A","B","C"]),i[n]]
        steps=v.structural_model[7:8]
        pred=[0.,v.person[p[n]]-b-h-steps[1],2*(v.person[p[n]]-b-h)-sum(steps)]
        rng=op.pattern_ranges[op.pattern_of_row[n]]
        @test pred≈op.c_pat[rng]+op.A_free[rng,:]*v.structural_free+op.B_pat[rng]*v.person[p[n]]
    end
    # Reverse the facet and level order. Compare on the original cell labels.
    flipped=fix([cell];facets=(item=:i,rater=:r),levels=(person=collect(6:-1:1),
                facets=(item=[3,2,1],rater=["C","B","A"])))
    rev=only(filter(x->x.kind===:facet_facet_interaction,flipped.operator.block_meta))
    positions=[(findfirst(==(j),rev.levels1)-1)*3+findfirst(==(k),rev.levels2)
               for k in ["A","B","C"] for j in 1:3]
    V=Matrix(flipped.operator.J_model[rev.model_range[positions],rev.eta_range])
    @test flipped.operator.xi0_model[rev.model_range[positions]]≈base && V*V'≈expected
    entire=[(levels=(rater="A",item=j),value=x) for (j,x) in enumerate([.6,-.2,-.4])]
    redundant=fix(entire)
    @test only(redundant.spec_record.fixed_calibration.interaction_dimensions).anchor_rank==2
    implied=fix(entire[1:2])
    @test "interaction[rater,item][\"A\",3]" in implied.operator.fixed_model_names
    @test implied.operator.xi0_model[first(rows)+2]≈-.4
    four=[(levels=(rater=k,item=j),value=.1) for k in ["A","B"] for j in 1:2]
    full=fix(four;prior_sd=merge(prior,(interactions=(rater_item=0.,),)))
    @test only(full.spec_record.fixed_calibration.interaction_dimensions).free_df==0
    @test all(n->n in full.operator.fixed_model_names,op.model_names[rows])
    hyper=fix([cell];prior_sd=merge(prior,(interactions=(rater_item=LogNormal(log(.9),.3),),)))
    hp=only(filter(x->x.name===:rater_item,hyper.prior_blocks))
    @test hp.iso_factor==1.5 && hp.hyper_idx>0 && length(hp.eta_range)==3
    hq=collect(range(.35,-.4,length=length(initial_params(hyper))))
    @test logdensity_and_gradient(hyper,hq)[2]≈ForwardDiff.gradient(x->logposterior(hyper,x),hq) atol=1e-11
    for bad in ([],[cell,cell],[merge(cell,(value=NaN,))],[merge(cell,(value=true,))],
                [(levels=(rater="A",item=true),value=0.)],[(levels=(rater="X",item=1),value=0.)],
                [(levels=(rater="A",step=1),value=0.)],[(levels=(person=1,item=1),value=0.)],
                [(levels=("A",1),value=0.)],vcat(entire[1:2],[(levels=(rater="A",item=3),value=.1)]))
        @test_throws ArgumentError fix(bad)
    end
    @test_throws ArgumentError fix([cell];interactions=nothing)
    single=map(v->v[r.=="A"],tbl)
    @test_throws ArgumentError fix([cell];data=single)
    @test only(fix([merge(cell,(value=0.,))];data=single).spec_record.fixed_calibration.interaction_dimensions).free_df==0
    # With two raters the other cell in the same column is also fixed by the margin.
    rect=fix([cell];data=map(v->v[r.!="C"],tbl))
    opposite="interaction[rater,item][\"B\",1]"
    @test opposite in rect.operator.fixed_model_names
    @test rect.operator.xi0_model[only(findall(==(opposite),rect.operator.model_names))]≈-.6
    @test only(rect.spec_record.fixed_calibration.interaction_dimensions).free_df==1
    # A row with two remaining members has equal variances and opposite covariance.
    s=fix([cell])
    for method in (:mmle,:jmle)
        f=fit(s;method)
        @test qualify(f).qualified
        measures=Dict(x.parameter=>x for x in f.record.facet_measures)
        names=s.operator.model_names[rows]
        @test measures[names[1]].fixed && measures[names[1]].estimate===.6 && measures[names[1]].se==0
        @test measures[names[2]].se>0 && measures[names[2]].se≈measures[names[3]].se
        V=f.record.covariance.matrix[rows,rows]
        @test V[2,3]≈-V[2,2] && norm(V[:,1])==0
    end
    d=FacetData(tbl;person=:p,rater=:r,item=:i,score=:y,category_levels=0:2)
    orig=mfrm_spec(d;thresholds=:rating_scale,anchors=[(block=:item,level=2,value=.2)])
    fromspec=mfrm_spec(orig;interactions=((:rater,:item),),fixed_calibration=(cells=[cell],),prior=:none)
    direct=mfrm_spec(tbl;opts...,fixed_calibration=(cells=[cell],facets=(item=Dict(2=>.2),)),prior=:none)
    @test fromspec.operator.c_pat≈direct.operator.c_pat && fromspec.operator.A_free≈direct.operator.A_free
    @test fromspec.spec_record.fixed_calibration.anchors==direct.spec_record.fixed_calibration.anchors
end
