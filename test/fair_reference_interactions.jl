module FairReferenceInteractionsTests
using Test, BayesianMGMFRM, Statistics, LinearAlgebra, ForwardDiff
using Distributions: Normal, LogNormal, truncated, Categorical
const B=BayesianMGMFRM;const A=B.AdditiveFacets
const ids=[(p,i,r) for p in 1:8 for i in 1:3 for r in 1:3]
const data=(person=first.(ids),item=getindex.(ids,2),rater=last.(ids),score=[mod(p+2i+r+(p*i)%3,4) for (p,i,r) in ids])
const plan=(item=repeat(1:3;inner=3),rater=repeat(1:3;outer=3),Weight=collect(1.:9.))
const pop=(roster=(person=1:8,group=repeat(["A","B"];inner=4)),person=:person,group=:group,reference="A")
function direct(b,pl,op,x,p,n;zero=false)
    xi=x[[only(findall(==(name),getproperty.(b.people,:parameter) ∪ op.model_names)) for name in op.model_names]]
    if zero
        xi=copy(xi)
        for block in op.block_meta
            block.kind in (:facet_facet_interaction,:focal_dff_interaction,:facet_step_interaction) && (xi[block.model_range].=0)
        end
    end
    ix=op.pattern_ranges[op.pattern_of_row[n]]
    z=op.B_pat[ix].*x[p].+op.c0_pat[ix].+op.A_model[ix,:]*xi
    w=exp.(z.-maximum(z));dot(pl.categories,w)/sum(w)
end
@testset "Interaction reference kernels and contexts" begin
    bp=merge(pop,(coefficient_prior=Normal(0,1),sd_prior=LogNormal(0,.5)))
    for ints in (((:item,:rater)=>.5,),((:rater,:step)=>.5,),((:rater,:group)=>.5,),
            ((;pair=(:rater,:group),focal=[1],prior=.5),))
        grouped=any(i->i isa Pair ? :group in i.first : true,ints)
        extra=grouped ? (;population=bp,prior_sd=(facets=(item=1.,rater=1.),step=1.)) : (;prior=:default)
        t=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,interactions=ints,extra...)
        b=A.fair_reference_basis(t);pl=A._fair_reference_plan(b,plan)
        q=[.5sin(.3s+.7j) for s in 1:40,j in 1:t.dimension];m=A.model_draws(t,q)
        @test b.schema==A.FAIR_REFERENCE_INTERACTION_BASIS_SCHEMA
        @test_throws ArgumentError A._fair_reference_values(b,pl,m.values,m.names)
        @test_throws ArgumentError A._fair_reference_values(b,pl,m.values,m.names;interaction_effects=:unknown)
        for mode in (:fitted,:zero)
            v=A._fair_reference_values(b,pl,m.values,m.names;interaction_effects=mode)
            xnames=vcat(getproperty.(b.people,:parameter),t.operator.model_names)
            col=[only(findall(==(n),m.names)) for n in xnames]
            oracle=[sum(pl.weights[j]*direct(b,pl,t.operator,m.values[s,col],p,n;zero=mode===:zero) for (j,n) in enumerate(findall(==(p),t.person))) for s in axes(q,1),p in 1:8]
            @test v≈oracle atol=2e-14
            if mode===:fitted
                native=[sum(pl.weights[j]*dot(t.categories,exp.(A.logprobs(t,view(q,s,:))[n,:])) for (j,n) in enumerate(findall(==(p),t.person))) for s in axes(q,1),p in 1:8]
                @test v≈native atol=2e-14
            end
        end
        if grouped
            @test only(b.contexts).values==pop.roster.group
            @test_throws ArgumentError A._fair_reference_plan(b,merge(plan,(group=fill("A",9),)))
        end
        # Shared effects on a separate role and hard anchors preserve interaction conditioning.
        sddata=merge(data,(event=[(p-1)*3+r for (p,i,r) in ids],))
        tt=mfrm_spec(sddata;person=:person,score=:score,facets=(item=:item,rater=:rater,event=:event),steps=:item,
            category_levels=0:3,assessment=:event,random_effects=(event=.4,),interactions=ints,
            fixed_calibration=(facets=(item=Dict(1=>.2),),),extra...)
        bb=A.fair_reference_basis(tt);pp=A._fair_reference_plan(bb,plan)
        mm=A.model_draws(tt,reshape(.2sin.(1:tt.dimension),1,:))
        for mode in (:fitted,:zero)
            result=A._fair_reference_evaluate(bb,pp,mm.values,mm.names;interaction_effects=mode,shared_effects=:marginal_new)
            @test result.integration.max_score_difference<1e-7
            @test all(x->0<x<3,result.values)
        end
    end
end
@testset "Interaction JMLE covariance and grouped MMLE" begin
    for ints in (((:item,:rater),),((:rater,:step),))
        t=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,prior=:none,interactions=ints)
        f=fit(t;method=:jmle);r=f.record;op=r.mrcml_operator;P=8
        b=A.fair_reference_basis(f);pl=A._fair_reference_plan(b,plan)
        probs(u,n)=begin
            ix=op.pattern_ranges[op.pattern_of_row[n]]
            z=op.B_pat[ix].*u[t.person[n]].+op.c_pat[ix].+op.A_free[ix,:]*u[P+1:end]
            w=exp.(z.-maximum(z));w./sum(w)
        end
        nll(u)=-sum(log(probs(u,n)[t.category[n]]) for n in eachindex(t.person))
        H=ForwardDiff.hessian(nll,r.u_free)
        for mode in (:fitted,:zero)
            report=diagnostics(f;kind=:fair_average,reference_plan=plan,interaction_effects=mode,comparisons=[(left=1,right=2,margin=.1)])
            reference(u)=begin
                x=vcat(u[1:P],op.xi0_model+op.J_model*u[P+1:end])
                [sum(pl.weights[j]*direct(b,pl,op,x,p,n;zero=mode===:zero) for (j,n) in enumerate(findall(==(p),t.person))) for p in 1:P]
            end
            J=ForwardDiff.jacobian(reference,r.u_free);V=J*(H\J')
            @test getproperty.(report.rows,:mean)≈reference(r.u_free) atol=1e-12
            @test getproperty.(report.rows,:sd).^2≈diag(V) atol=1e-9
            @test only(report.contrasts).sd^2≈V[1,1]+V[2,2]-2V[1,2] atol=1e-9
        end
    end
    for ints in (((:rater,:group),),((;pair=(:rater,:group),focal=[1]),))
        t=mfrm_spec(data;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,category_levels=0:3,prior=:none,population=pop,interactions=ints)
        f=fit(t;method=:mmle,quad_points=41);b=A.fair_reference_basis(f);pl=A._fair_reference_plan(b,plan);d=b.frequentist
        @test only(b.contexts).values==pop.roster.group
        for mode in (:fitted,:zero)
            rep=diagnostics(f;kind=:fair_average,reference_plan=plan,interaction_effects=mode,threshold=1.5)
            for p in 1:8
                post=d.posterior[p]
                @test dot(post.nodes,post.weights)≈f.record.person_scores[p].eap atol=1e-12
                v=map(post.nodes) do theta
                    x=copy(d.values);x[p]=theta
                    sum(pl.weights[j]*direct(b,pl,f.record.mrcml_operator,x,p,n;zero=mode===:zero) for (j,n) in enumerate(findall(==(p),t.person)))
                end
                @test rep.rows[p].mean≈dot(v,post.weights) atol=1e-12
                @test rep.rows[p].event.probability≈sum(post.weights[v.>=1.5]) atol=1e-12
            end
        end
    end
end
end
