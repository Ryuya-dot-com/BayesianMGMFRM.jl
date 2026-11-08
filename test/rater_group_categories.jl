module RaterGroupCategoryChecks
using Test, Statistics
import BayesianMGMFRM as B
const RG=B.Experimental.RaterGroupEffects
function fixture(K=3,minimum_score=1)
    rows=[(;person="p$p",rater="r$r",item="i$i",group=p<=2 ? "A" : "B",
        score=minimum_score+mod(p+r+i,K-1)) for p in 1:4 for r in 1:2 for i in 1:2 if !(p>2 && i==2)]
    table=(;(k=>[getproperty(row,k) for row in rows] for k in keys(first(rows)))...)
    data=B.FacetData(table;person=:person,rater=:rater,item=:item,score=:score,group=:group,category_levels=minimum_score:minimum_score+K-1)
    prior=RG.Prior(person_sd=.9,group_mean_sd=1.4,item_sd=.7,rater_sd=.6,step_sd=.8,interaction_logmean=log(.5),interaction_logsd=.6)
    RG.model(data;prior)
end
# Deterministic coordinate fixtures: not fitted samples or MCMC-quality evidence.
function fixture_draws(t)
    q=[.6sin(s+.7j) for s in 1:40,j in 1:B.LogDensityProblems.dimension(t)]
    q[:,end].=log(.6).+.1sin.(1:40);q
end
function dense(t,q)
    d=t.data;K=length(d.category_levels);out=zeros(size(q,1),d.n,K)
    for (s,raw) in enumerate(eachrow(q))
        v=RG.coordinates(t,raw)
        for n in 1:d.n
            i,r,g=d.item[n],d.rater[n],d.optional[:group][n]
            eta=v.person[d.person[n]]-v.item[i]-v.rater[r]-v.interaction[r,g]
            logits=eta.*collect(0:K-1).-vcat(0.,cumsum(v.steps[i,:]))
            weights=exp.(logits.-maximum(logits));out[s,n,:]=weights/sum(weights)
        end
    end
    out
end
@testset "Group category report: joint aggregation, supports, empty cells and limits" begin
    for K in (2,3)
        t=fixture(K);q=fixture_draws(t);d=t.data;cube=dense(t,q)
        cells=RG._category_cells(d);budget=40*K*length(cells)+K
        sums=RG._category_sums(t,q,budget)
        @test sums.workspace_cells==budget
        @test length(cells)==9
        @test :category_report in RG.contract().operations
        rows=RG._category_rows(t,q,2,.9,budget)
        @test length(rows.category_rows)==9K && length(rows.score_rows)==9
        @test count(r->r.status===:unobserved_cell,rows.score_rows)==1
        for (c,cell) in enumerate(cells)
            n=length(cell.observations)
            expected=dropdims(sum(cube[:,cell.observations,:];dims=2);dims=2)
            @test sums.sums[:,:,c]≈expected atol=2e-14
            @test sum(sums.sums[:,:,c];dims=2)≈fill(float(n),40,1)
            score=rows.score_rows[c]
            cr=rows.category_rows[(c-1)*K+1:c*K]
            @test sum(r.observed_count for r in cr)==n
            if n==0
                @test all(r->r.expected===nothing && ismissing(r.observed_proportion) && ismissing(r.observed_minus_expected),cr)
                @test score.expected===nothing && ismissing(score.observed_mean)
                continue
            end
            score_draws=(expected/n)*d.category_levels
            @test score.expected.mean≈mean(score_draws)
            @test score.expected.lower≈quantile(score_draws,.05)
            @test score.expected.upper≈quantile(score_draws,.95)
            @test score.observed_mean≈mean(d.score[cell.observations])
            for k in 1:K
                p=expected[:,k]/n;r=cr[k]
                @test r.expected.mean≈mean(p)
                @test r.expected.lower≈quantile(p,.05)
                @test r.expected.upper≈quantile(p,.95)
                @test r.observed_minus_expected≈r.observed_proportion-mean(p)
                @test r.observed_count==count(==(k),d.category[cell.observations])
            end
            @test cr[end].observed_count==0 && cr[end].expected.mean>0
        end
        @test_throws ArgumentError RG._category_sums(t,q,budget-1)
        @test_throws ArgumentError RG._category_sums(t,q,true)
        @test_throws ArgumentError RG._category_sums(t,q,0)
        @test_throws ArgumentError RG._category_sums(t,q[1:1,:],budget)
        @test_throws ArgumentError RG._category_rows(t,q,2,1.,budget)
        @test_throws ArgumentError RG._category_rows(t,q,2,NaN,budget)
        shifted=fixture(K,6);sr=RG._category_rows(shifted,q,2,.9,budget)
        @test sr.category_rows[1].expected.mean≈rows.category_rows[1].expected.mean
        @test sr.score_rows[1].expected.mean≈rows.score_rows[1].expected.mean+5
        @test sr.score_rows[1].expected.lower≈rows.score_rows[1].expected.lower+5
        @test sr.score_rows[1].observed_minus_expected≈rows.score_rows[1].observed_minus_expected
        zerosq=repeat(permutedims(RG.initial(t)),40,1)
        uniform=RG._category_rows(t,zerosq,2,.95,budget)
        @test all(r->r.expected===nothing || r.expected.mean≈1/K,uniform.category_rows)
        @test uniform.score_rows[1].expected.mean≈mean(d.category_levels)
        @test uniform.category_rows[1].expected.status===:mcse_unavailable
        @test ismissing(uniform.category_rows[1].expected.mcse.mean_mcse)
        extreme=q.*1000;extreme[:,end].=log(.6)
        @test all(isfinite,RG._category_sums(t,extreme,budget).sums)
    end
end
end
