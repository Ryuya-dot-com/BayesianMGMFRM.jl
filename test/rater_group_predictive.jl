module RaterGroupPredictiveChecks
using Test, Statistics
import BayesianMGMFRM as B
const RG=B.Experimental.RaterGroupEffects
function fixture(K=3,start=0)
    rows=[(;person="p$p",rater="r$r",item="i$i",group=p<=2 ? "A" : "B",
        score=start+mod(p+r+i,K-1)) for p in 1:4 for r in 1:2 for i in 1:2]
    table=(;(k=>getproperty.(rows,k) for k in keys(first(rows)))...)
    d=B.FacetData(table;person=:person,rater=:rater,item=:item,score=:score,group=:group,category_levels=start:start+K-1)
    prior=RG.Prior(person_sd=.9,group_mean_sd=1.4,item_sd=.7,rater_sd=.6,step_sd=.8,interaction_logmean=log(.5),interaction_logsd=.6)
    RG.model(d;prior)
end
function enumeration(ps)
    out=zeros(length(ps)+1)
    for state in Iterators.product(fill(0:1,length(ps))...)
        out[sum(state)+1]+=prod(z==1 ? p : 1-p for (z,p) in zip(state,ps))
    end
    out
end
function mass(ps)
    v=zeros(length(ps)+1);v[1]=1.
    for (j,p) in enumerate(ps);RG._count_update!(v,p,j);end
    v
end
@testset "Predictive count recurrence and dependence" begin
    for ps in ([.1,.3,.6,.9],[0.,1.,0.,1.],fill(.5,4),[1e-12,1-1e-12,.2])
        @test mass(ps)≈enumeration(ps) atol=2e-15
        @test sum(mass(ps))≈1.
        @test sum((0:length(ps)).*mass(ps))≈sum(ps)
    end
    @test mass(fill(.2,8))≈[binomial(8,k)*.2^k*.8^(8-k) for k in 0:8]
    @test (mass([.1,.1])+mass([.9,.9]))/2≈[.41,.18,.41]
    @test mass([.5,.5])≈[.25,.5,.25]
    @test_throws ArgumentError mass([NaN])
    @test_throws ArgumentError mass([1.1])
end
@testset "Selected category: exact oracle, labels, support, bounds and precision" begin
    for K in (2,3),start in (0,6)
        t=fixture(K,start);d=t.data
        q=[.4sin(.7s+.5j) for s in 1:40,j in 1:B.LogDensityProblems.dimension(t)]
        q[:,end].=log(.6).+.1sin.(1:40)
        for category in d.category_levels
            x=RG._category_count_values(t,q;rater="r1",group="A",category,max_count_updates=560)
            @test x.n_observations==4 && x.count_updates==560
            @test x.workspace_cells==160+5+K
            @test :category_predictive_check in RG.contract().operations
            @test x.max_mass_error<1e-14
            for (s,raw) in enumerate(eachrow(q))
                v=RG.coordinates(t,raw);probs=Float64[]
                for n in x.observations
                    i,r,g=d.item[n],d.rater[n],d.optional[:group][n]
                    eta=v.person[d.person[n]]-v.item[i]-v.rater[r]-v.interaction[r,g]
                    logits=eta.*collect(0:K-1).-vcat(0.,cumsum(v.steps[i,:]))
                    p=exp.(logits.-maximum(logits));p./=sum(p)
                    push!(probs,p[category-start+1])
                end
                oracle=enumeration(probs);obs=x.observed_count
                @test x.values[s,:]≈[sum(probs),sum(oracle[1:obs+1]),sum(oracle[obs+1:end]),oracle[obs+1]] atol=2e-14
                @test x.values[s,2]+x.values[s,3]≈1+x.values[s,4]
            end
        end
        zeroq=repeat(permutedims(RG.initial(t)),40,1)
        x=RG._category_count_values(t,zeroq;rater="r1",group="A",category=last(d.category_levels),max_count_updates=560)
        summary=RG._count_summaries(x,2)
        @test x.observed_count==0 && x.fixed==Set(["upper_tail"])
        @test summary[3].mean==1. && summary[3].mean_mcse==0. && summary[3].mcse_status===:structurally_fixed
        @test ismissing(summary[1].mean_mcse) && summary[1].mcse_status===:degenerate_draws
        for kwargs in ((rater="missing",group="A",category=start,max_count_updates=560),
                       (rater="r1",group="missing",category=start,max_count_updates=560),
                       (rater="r1",group="A",category=-1,max_count_updates=560),
                       (rater="r1",group="A",category=true,max_count_updates=560),
                       (rater="r1",group="A",category=start,max_count_updates=559),
                       (rater="r1",group="A",category=start,max_count_updates=true))
            @test_throws ArgumentError RG._category_count_values(t,q;kwargs...)
        end
        for bad in (q[1:1,:],q[:,1:end-1],fill(NaN,size(q)))
            @test_throws ArgumentError RG._category_count_values(t,bad;rater="r1",group="A",category=start,max_count_updates=560)
        end
    end
end
end
