using Test, BayesianMGMFRM, Statistics, LinearAlgebra
using BayesianMGMFRM.GlassBox
import Distributions
import ForwardDiff

@testset "Shared and generalized common-plan kernels" begin
    A=BayesianMGMFRM.AdditiveFacets; S=BayesianMGMFRM.ScaleIdentifiedMGMFRM
    ids=[(p,i,r) for p in 1:4 for i in 1:4 for r in 1:3]
    data=(person=first.(ids),item=getindex.(ids,2),rater=last.(ids),
        event=["$p-$r" for (p,i,r) in ids],score=[1+mod(p+i+r,4) for (p,i,r) in ids])
    plan=(item=repeat(1:4;inner=3),rater=repeat(1:3;outer=4))
    for steps in (:global,:item,:rater), slope in (:item,:rater,:both)
        t=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps,
            category_levels=1:4,prior=:default,slope)
        raw=[.3sin(s+j) for s in 1:6,j in 1:t.dimension]
        b=A.fair_reference_basis(t); pl=A._fair_reference_plan(b,plan); m=S.model_draws(t,raw)
        v=A._fair_reference_values(b,pl,m.values,m.names)
        for s in 1:6
            probs=S._category_probs_point(t,S.coordinates(t,raw[s,:]))
            for p in 1:4
                ix=findall(x->x[1]==p,ids)
                @test v[s,p]≈mean(sum(probs[n,:].*t.category_levels) for n in ix) atol=2e-14
            end
        end
    end
    t=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,
        category_levels=1:4,prior=:default,q_matrix=Bool[1 0;1 0;0 1;0 1],latent_correlation=:lkj)
    raw=[.3sin(s+j) for s in 1:6,j in 1:t.dimension];m=S.model_draws(t,raw)
    b=A.fair_reference_basis(t);pl=A._fair_reference_plan(b,plan);v=A._fair_reference_values(b,pl,m.values,m.names)
    for s in 1:6,p in 1:4
        probs=S._category_probs_point(t,S.coordinates(t,raw[s,:]))
        @test v[s,p]≈mean(sum(probs[n,:].*t.category_levels) for n in findall(x->x[1]==p,ids)) atol=2e-14
    end
    t=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater,event=:event),
        steps=:item,assessment=:event,category_levels=1:4,prior=:default,
        random_effects=(event=Distributions.truncated(Distributions.Normal(0,.5),0,Inf),))
    raw=reshape(.3sin.(1:t.dimension),1,:);m=A.model_draws(t,raw)
    b=A.fair_reference_basis(t);pl=A._fair_reference_plan(b,plan)
    @test_throws ArgumentError A._fair_reference_values(b,pl,m.values,m.names)
    zero=A._fair_reference_evaluate(b,pl,m.values,m.names;shared_effects=:zero)
    integrated=A._fair_reference_evaluate(b,pl,m.values,m.names;shared_effects=:marginal_new)
    @test maximum(abs.(zero.values-integrated.values))>1e-4
    @test integrated.integration.max_score_difference<1e-7
    changed=copy(m.values)
    changed[:,findall(n->startswith(n,"event["),m.names)].+=10
    @test A._fair_reference_evaluate(b,pl,changed,m.names;shared_effects=:marginal_new).values==integrated.values
    changed[:,findall(==("residual_sd[event]"),m.names)].=1e-7
    @test A._fair_reference_evaluate(b,pl,changed,m.names;shared_effects=:marginal_new).values≈zero.values atol=1e-13
    @test_throws ArgumentError A._fair_reference_evaluate(b,pl,m.values,m.names;shared_effects=:marginal_new,quadrature_orders=(3,5),quadrature_tolerance=1e-15)
    fixed=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater,event=:event),
        steps=:item,assessment=:event,category_levels=1:4,prior=:default,random_effects=(event=.5,))
    fb=A.fair_reference_basis(fixed)
    @test only(fb.shared).sd_parameter===nothing && only(fb.shared).sd==.5
    fm=A.model_draws(fixed,reshape(.3sin.(1:fixed.dimension),1,:))
    fv=A._fair_reference_evaluate(fb,A._fair_reference_plan(fb,plan),fm.values,fm.names;shared_effects=:marginal_new)
    @test all(isfinite,fv.values)
    @test_throws ArgumentError A._fair_reference_plan(merge(b,(facets=NamedTuple[],)),(Weight=[1.],))
end

@testset "Quadrature probabilities at thresholds and strict margins" begin
    scores = [1.0, 2.0, 3.0]
    for offset in (eps(), -eps())
        weights = [0.25, 0.25, 0.5 + offset]
        event(threshold; strict=false) = BayesianMGMFRM._fair_weighted_summary(
            scores, weights; level=0.95, threshold, strict).event.probability
        @test event(1) == 1.0
        @test event(3; strict=true) == 0.0
        @test event(2) ≈ 0.75 atol=eps() rtol=0
        @test event(2; strict=true) ≈ 0.5 atol=eps() rtol=0
    end
end

@testset "Frequentist expected scores and joint covariance" begin
    B=BayesianMGMFRM;A=B.AdditiveFacets
    ids=[(p,i,r) for p in 1:8 for i in 1:3 for r in 1:3]
    data=(person=first.(ids),item=getindex.(ids,2),rater=last.(ids),score=[mod(p+2i+r+(p*i)%3,4) for (p,i,r) in ids])
    t=A.compile_structured_mrcml(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3)
    plan=(item=repeat(1:3;inner=3),rater=repeat(1:3;outer=3),Weight=collect(1.:9.))
    f=fit(t;method=:jmle);r=f.record;P=8;op=r.mrcml_operator
    probs(u,n)=begin
        ix=op.pattern_ranges[op.pattern_of_row[n]]
        z=op.B_pat[ix].*u[t.person[n]].+op.c_pat[ix].+op.A_free[ix,:]*u[P+1:end]
        w=exp.(z.-maximum(z));w./sum(w)
    end
    nll(u)=-sum(log(probs(u,n)[t.category[n]-first(t.supports[t.group[n]])+1]) for n in eachindex(t.person))
    H=ForwardDiff.hessian(nll,r.u_free)
    reference(u)=[sum(plan.Weight[j]*dot(0:3,probs(u,n))/sum(plan.Weight) for (j,n) in enumerate(findall(==(p),t.person))) for p in 1:P]
    J=ForwardDiff.jacobian(reference,r.u_free);V=J*(H\J')
    report=diagnostics(f;kind=:fair_average,reference_plan=plan,comparisons=[(left=1,right=2,margin=.1)])
    @test getproperty.(report.rows,:mean)≈reference(r.u_free) atol=1e-12
    @test getproperty.(report.rows,:sd).^2≈diag(V) atol=1e-10
    @test only(report.contrasts).sd^2≈V[1,1]+V[2,2]-2V[1,2] atol=1e-10
    @test report.interval_target===:wald_expected_score
    @test_throws ArgumentError diagnostics(f;kind=:fair_average,reference_plan=plan,threshold=2.)
    @test_throws ArgumentError diagnostics(f;kind=:fair_average,reference_plan=plan,comparisons=[(left=1,right=2,margin=true)])
    default=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,prior=:none)
    dr=diagnostics(fit(default;method=:jmle);kind=:fair_average,reference_plan=plan,comparisons=[(left=1,right=2,margin=.1)])
    @test getproperty.(dr.rows,:mean)≈getproperty.(report.rows,:mean) atol=1e-8
    @test getproperty.(dr.rows,:sd)≈getproperty.(report.rows,:sd) atol=1e-8
    @test only(dr.contrasts).sd≈only(report.contrasts).sd atol=1e-8
    centered=diagnostics(fit(default;method=:jmle,noncenter_facet=:item);kind=:fair_average,reference_plan=plan)
    @test getproperty.(centered.rows,:mean)≈getproperty.(report.rows,:mean) atol=1e-8
    @test getproperty.(centered.rows,:sd)≈getproperty.(report.rows,:sd) atol=1e-8
    labels=Any[1,"1",:third]
    typed=merge(data,(item=[labels[i] for i in data.item],))
    tf=mfrm_spec(typed;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,prior=:none)
    tr=diagnostics(fit(tf;method=:jmle);kind=:fair_average,reference_plan=merge(plan,(item=[labels[i] for i in plan.item],)))
    @test getproperty.(tr.rows,:mean)≈getproperty.(report.rows,:mean) atol=1e-8
    for grouped in (false,true)
        pop=(;roster=(person=1:8,group=repeat(["A","B"];inner=4)),person=:person,group=:group,reference="A")
        spec=grouped ? mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,prior=:none,population=pop) : t
        mf=fit(spec;method=:mmle,quad_points=41);basis=A.fair_reference_basis(mf)
        if !grouped
            alt=diagnostics(fit(default;method=:mmle,quad_points=41);kind=:fair_average,reference_plan=plan)
            main=diagnostics(mf;kind=:fair_average,reference_plan=plan)
            @test getproperty.(alt.rows,:mean)≈getproperty.(main.rows,:mean) atol=1e-7
            @test getproperty.(alt.rows,:sd)≈getproperty.(main.rows,:sd) atol=1e-7
        end
        for p in 1:P
            posterior=basis.frequentist.posterior[p]
            @test dot(posterior.nodes,posterior.weights)≈mf.record.person_scores[p].eap atol=1e-12
        end
        mr=diagnostics(mf;kind=:fair_average,reference_plan=plan,threshold=1.5,comparisons=[(left=1,right=2,margin=.1)])
        @test mr.interval_target===:conditional_posterior_expected_score
        @test all(x->0<=x.event.probability<=1,mr.rows)
        if !grouped
            @test maximum(abs.([x.mean-x.plugin_mean for x in mr.rows]))>1e-4
        end
        @test 0<=only(mr.contrasts).event.probability<=1
    end
    extreme=merge(data,(score=[p==1 ? 0 : p==2 ? 3 : data.score[n] for (n,(p,i,r)) in enumerate(ids)],))
    et=mfrm_spec(extreme;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,prior=:none)
    er=diagnostics(fit(et;method=:jmle);kind=:fair_average,reference_plan=plan)
    @test er.rows[1].mean==0 && ismissing(er.rows[1].lower)
    @test er.rows[2].mean==3 && ismissing(er.rows[2].lower)

    # Frequentist marginal Fair-M / Fair-Z (`by = ...`) and `pair_bias` (`dff_report`)
    for f_chk in (f, fit(default; method=:jmle), fit(t; method=:mmle, quad_points=41), fit(default; method=:mmle, quad_points=41))
        fs_r = facet_summary(f_chk; facet=:rater)
        fs_p = facet_summary(f_chk; facet=:person)
        @test all(x -> isfinite(x.fair_m) && isfinite(x.fair_z) && 0.0 <= x.fair_m <= 3.0, fs_r.rows)
        @test all(x -> isfinite(x.fair_m) && isfinite(x.fair_z) && 0.0 <= x.fair_m <= 3.0, fs_p.rows)

        fa_rm = diagnostics(f_chk; kind=:fair_average, by=:rater, baseline=:sample_mean)
        fa_rz = diagnostics(f_chk; kind=:fair_average, by=:rater, baseline=:zero_origin)
        @test [x.fair_average for x in fa_rm.rows] ≈ [x.fair_m for x in fs_r.rows] atol=1e-12
        @test [x.fair_average for x in fa_rz.rows] ≈ [x.fair_z for x in fs_r.rows] atol=1e-12
        @test all(x -> !(x.fair_average_se === missing) && x.fair_average_se > 0.0, fa_rm.rows)

        pb_chk = diagnostics(f_chk; kind=:pair_bias, pair=(:rater, :item))
        @test pb_chk.analysis_mode === :secondary_residual_screen
        @test pb_chk.n_cells == 9
        @test all(x -> isfinite(x.approx_severity_bias_logit) && x.approx_severity_bias_se > 0.0, pb_chk.rows)
        @test B.dff_report(f_chk; pair=(:rater, :item)).n_cells == 9
    end

    # Fixed non-zero facet anchor separates Fair-M from Fair-Z and verifies delta SE against ForwardDiff
    anc_spec = mfrm_spec(data; person=:person, score=:score, facets=(item=:item, rater=:rater),
        steps=:global, category_levels=0:3, fixed_calibration=(facets=(item=Dict(1=>0.9),),), prior=:none)
    f_anc = fit(anc_spec; method=:mmle, estimate_mean=true, quad_points=41)
    fa_anc_m = diagnostics(f_anc; kind=:fair_average, by=:rater, baseline=:sample_mean)
    fa_anc_z = diagnostics(f_anc; kind=:fair_average, by=:rater, baseline=:zero_origin)
    @test maximum(abs.([x.fair_average for x in fa_anc_m.rows] .- [x.fair_average for x in fa_anc_z.rows])) > 1e-3
    r1_row = fa_anc_z.rows[1]
    tau_g = Float64[x.estimate for x in f_anc.record.step_measures]
    fd_exp = ForwardDiff.derivative(b -> sum(k * exp(k * (-b) - sum(tau_g[1:k]; init=0.0)) for k in 0:3) /
        sum(exp(k * (-b) - sum(tau_g[1:k]; init=0.0)) for k in 0:3), r1_row.logit_estimate)
    @test r1_row.fair_average_se ≈ abs(fd_exp) * r1_row.logit_se atol=1e-12

    # Mixed category supports require step_group on non-owner facets
    mix_data = merge(data, (score=[i == 1 ? mod(s, 2) : s for (s, (_, i, _)) in zip(data.score, ids)],))
    mix_spec = mfrm_spec(mix_data; person=:person, score=:score, facets=(item=:item, rater=:rater),
        steps=:item, category_levels=Dict(1=>0:1, 2=>0:3, 3=>0:3), prior=:none)
    f_mix = fit(mix_spec; method=:mmle, quad_points=31)
    @test_throws ArgumentError diagnostics(f_mix; kind=:fair_average, by=:rater)
    fa_mix_it = diagnostics(f_mix; kind=:fair_average, by=:item)
    fa_mix_rt = diagnostics(f_mix; kind=:fair_average, by=:rater, step_group=2)
    @test [x.max_category for x in fa_mix_it.rows] == [1, 3, 3]
    @test all(x -> x.max_category == 3 && isfinite(x.fair_average), fa_mix_rt.rows)
end
