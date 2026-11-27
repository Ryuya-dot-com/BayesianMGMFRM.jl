using Test, BayesianMGMFRM, Statistics

@testset "Common reference expected scores" begin
    AF=BayesianMGMFRM.AdditiveFacets
    ids=[(p,i,r) for p in 1:4 for i in 1:2 for r in 1:3]
    table=(person=first.(ids),item=getindex.(ids,2),rater=last.(ids),score=[1+mod(p+i+r,4) for (p,i,r) in ids])
    plan=(item=[1,1,1,2,2,2],rater=[1,2,3,1,2,3],Weight=[1.,2,3,4,5,6])
    for steps in (:global,:item)
        t=mfrm_spec(table;person=:person,score=:score,facets=(item=:item,rater=:rater),steps,category_levels=1:4,prior=:default)
        q=[.7sin(.31s+.8j) for s in 1:80,j in 1:t.dimension]
        m=AF.model_draws(t,q); b=AF.fair_reference_basis(t); pl=AF._fair_reference_plan(b,plan)
        v=AF._fair_reference_values(b,pl,m.values,m.names)
        direct=zeros(size(v))
        for s in axes(q,1)
            probs=exp.(AF.logprobs(t,view(q,s,:)))
            for (n,(p,i,r)) in enumerate(ids)
                direct[s,p]+=pl.weights[(i-1)*3+r]*sum(probs[n,:].*t.categories)
            end
        end
        @test v ≈ direct atol=2e-14
        perm=reverse(eachindex(plan.item))
        rev=map(x->x[perm],plan)
        @test AF._fair_reference_values(b,AF._fair_reference_plan(b,rev),m.values,m.names) ≈ v atol=2e-14
        huge=merge(plan,(Weight=plan.Weight.*1e200,))
        @test AF._fair_reference_values(b,AF._fair_reference_plan(b,huge),m.values,m.names) ≈ v atol=2e-14
        @test AF._fair_reference_values(b,pl,m.values[:,end:-1:1],reverse(m.names)) ≈ v
        @test maximum(abs.(vec(mean(v;dims=1))-vec(AF._fair_reference_values(b,pl,mean(m.values;dims=1),m.names)))) > 1e-4
        @test_throws ArgumentError AF._fair_reference_values(b,pl,m.values[:,2:end],m.names[2:end])
        for bad in ((item=[99],rater=[1]),(item=[1,1],rater=[1,1]),(item=Int[],rater=Int[]),
                (item=[1],rater=[1],Weight=[0]),(item=[1],rater=[1],Weight=[Inf]),
                (item=[1],rater=[1],Weight=[true]),(item=[1],rater=[1],extra=[2]),
                (item=[1],),(item=[1,2],rater=[1]),(item=[missing],rater=[1]))
            @test_throws ArgumentError AF._fair_reference_plan(b,bad)
        end
    end
    # Partial calibration constants remain in the same model coordinates.
    t=mfrm_spec(table;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:global,category_levels=1:4,
        prior=:default,fixed_calibration=(facets=(rater=Dict(1=>.7),),))
    b=AF.fair_reference_basis(t);q=[.3sin(.7s+j) for s in 1:80,j in 1:t.dimension]; m=AF.model_draws(t,q)
    one=AF._fair_reference_plan(b,(item=[2],rater=[1]))
    v=AF._fair_reference_values(b,one,m.values,m.names)
    for p in 1:4
        n=only(findall(==((p,2,1)),ids))
        @test v[:,p] ≈ [sum(exp.(AF.logprobs(t,view(q,s,:))[n,:]).*t.categories) for s in 1:80] atol=2e-14
    end
    mixed=merge(table,(score=[i==1 ? mod(p+r,4) : mod(p+r,3) for (p,i,r) in ids],))
    tm=mfrm_spec(mixed;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,
        category_levels=Dict(1=>0:3,2=>0:2),prior=:default)
    bm=AF.fair_reference_basis(tm)
    @test_throws ArgumentError AF._fair_reference_plan(bm,plan)
    @test AF._fair_reference_plan(bm,(item=[2],rater=[3])).categories == collect(0:2)
    @test all(p->p.observed_categories===nothing && ismissing(p.observed_average),bm.people)
    roster=(person=1:4,cohort=["A","A","B","B"])
    pop=(;roster,person=:person,group=:cohort,reference="A",
        coefficient_prior=BayesianMGMFRM.Distributions.Normal(0,1),sd_prior=BayesianMGMFRM.Distributions.LogNormal(0,.5))
    tg=mfrm_spec(table;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:item,
        category_levels=1:4,population=pop,prior_sd=(facets=(item=1.,rater=1.),step=1.))
    bg=AF.fair_reference_basis(tg); mg=AF.model_draws(tg,[.3sin(.7s+j) for s in 1:80,j in 1:tg.dimension])
    pg=AF._fair_reference_plan(bg,plan); vg=AF._fair_reference_values(bg,pg,mg.values,mg.names)
    qg=[.3sin(.7s+j) for s in 1:80,j in 1:tg.dimension]
    for p in 1:4
        ns=findall(x->x[1]==p,ids)
        @test vg[:,p] ≈ [sum(pg.weights[j]*sum(exp.(AF.logprobs(tg,view(qg,s,:))[n,:]).*tg.categories) for (j,n) in enumerate(ns)) for s in 1:80] atol=2e-14
    end
    ti=mfrm_spec(table;person=:person,score=:score,facets=(item=:item,rater=:rater),steps=:global,
        category_levels=1:4,prior=:default,interactions=((:item,:rater)=>.5,))
    @test AF.fair_reference_basis(ti).schema == AF.FAIR_REFERENCE_INTERACTION_BASIS_SCHEMA
    c=AF._fair_reference_summary(collect(range(1.,4.,length=80));chains=4,interval=.9,threshold=2.5)
    @test c.event.probability == .5
    @test c.event.count == 40
    @test c.lower<=c.median<=c.upper
    @test AF._fair_reference_summary(ones(80);chains=4,interval=.95,threshold=1).event.probability == 1
    @test ismissing(AF._fair_reference_summary(ones(80);chains=4,interval=.95,threshold=1).event.mcse)
    @test AF._fair_reference_summary(ones(80);chains=4,interval=.95,threshold=1,strict=true).event.probability == 0
    @test_throws ArgumentError AF._fair_reference_summary(ones(80);chains=4,interval=.95,threshold=NaN)
    # Balanced indicators may have unavailable SD MCSE despite an estimable mean.
    z=[sin(.13i)+cos(.31i) for i in 1:8000]
    balanced=AF._fair_reference_summary(2 .+ vcat(z,-z);chains=4,interval=.95,threshold=2)
    @test balanced.event.probability == .5
    @test !ismissing(balanced.event.mcse) && isfinite(balanced.event.mcse)
    @test balanced.event.status === :available
    @test AF._fair_reference_summary(ones(80);chains=4,interval=.95,threshold=1).event.status === :degenerate_draws
end
