module RaterGroupEffectChecks
using Test, LinearAlgebra, Statistics
import BayesianMGMFRM as B
const L=B.LogDensityProblems
const ForwardDiff=B.ForwardDiff
const RG=B.Experimental.RaterGroupEffects
function group_fixture(;K=3)
    rows=[(;person="p$p",rater="r$r",item="i$i",group=p<=3 ? "A" : "B",score=mod(p+r+i,K))
        for p in 1:8 for r in 1:3 for i in 1:3 if mod(p+2r+3i,7)!=0]
    table=(; (k=>[getproperty(row,k) for row in rows] for k in keys(first(rows)))...)
    B.FacetData(table;person=:person,rater=:rater,item=:item,group=:group,score=:score,category_levels=0:K-1)
end
function group_prior()
    RG.Prior(person_sd=.9,group_mean_sd=1.4,item_sd=.7,rater_sd=.6,step_sd=.8,interaction_logmean=log(.5),interaction_logsd=.6)
end
function encode_group(t,v)
    p=t.prior;b=t.blocks;q=RG.initial(t)
    q[b.group_mean]=v.group_mean/p.group_mean_sd
    for (g,ps) in enumerate(t.group_people)
        q[t.residual_blocks[g]]=RG.RI._helmert(length(ps))'*(v.person[ps].-v.group_mean[g])*sqrt(1-1/length(ps))/p.person_sd
    end
    q[b.item]=t.item_basis'*v.item/p.item_sd;q[b.rater]=t.rater_basis'*v.rater/p.rater_sd
    q[b.steps]=vec(t.step_basis'*permutedims(v.steps))/p.step_sd
    q[b.interaction]=vec(t.rater_basis'*v.interaction*t.group_basis)*t.interaction_normalization/v.tau
    q[end]=log(v.tau);q
end
@testset "Observed-group rater severity: finite mathematics and input boundaries" begin
    for K in (2,3,4)
        d=group_fixture(;K);t=RG.model(d;prior=group_prior());q=sin.(collect(1:L.dimension(t))).*.4;q[end]=log(.6)
        v=RG.coordinates(t,q);pr=RG.category_logprobs(t,q)
        @test maximum(abs.(sum(exp.(pr);dims=2).-1))<1e-13
        @test all(g->mean(v.person[t.group_people[g]])≈v.group_mean[g],1:2)
        @test maximum(abs.(sum(v.interaction;dims=1)))<1e-14
        @test maximum(abs.(sum(v.interaction;dims=2)))<1e-14
        @test encode_group(t,v)≈q
        for scale in (0.,1.,30.)
            qq=q.*scale;qq[end]=log(.6)
            val,grad=L.logdensity_and_gradient(t,qq)
            @test val≈L.logdensity(t,qq) atol=1e-10 rtol=1e-13
            @test grad≈ForwardDiff.gradient(x->L.logdensity(t,x),qq) atol=1e-8 rtol=1e-10
        end
        bad=copy(q);bad[end]=1000
        @test L.logdensity(t,bad)==-Inf
        @test all(isnan,last(L.logdensity_and_gradient(t,bad)))
        @test_throws DimensionMismatch L.logdensity(t,q[2:end])
        # Independent dense location design checks the Schur-complement rank.
        P,R,I,G=8,3,3,2
        X=zeros(d.n,P+I-1+G*(R-1))
        for n in 1:d.n
            p,r,i,g=d.person[n],d.rater[n],d.item[n],d.optional[:group][n]
            X[n,p]=1
            i>1 && (X[n,P+i-1]=-1)
            r>1 && (X[n,P+I-1+(g-1)*(R-1)+r-1]=-1)
        end
        @test rank(X)==RG.design(t).location_rank==size(X,2)
        # Each gamma's conditional marginal prior variance is tau^2.
        A=kron(t.group_basis,t.rater_basis)/t.interaction_normalization
        @test diag(A*A')≈ones(R*G)
        for ps in t.group_people
            H=RG.RI._helmert(length(ps))/sqrt(1-1/length(ps))
            @test diag(H*H')≈ones(length(ps))
        end
        # A shared group penalty plus the same ability shift is invisible to likelihood.
        shifts=[-.7,.4]
        for n in 1:d.n
            p,r,i,g=d.person[n],d.rater[n],d.item[n],d.optional[:group][n]
            eta=v.person[p]-v.item[i]-v.rater[r]-v.interaction[r,g]
            @test (v.person[p]+shifts[g])-v.item[i]-v.rater[r]-(v.interaction[r,g]+shifts[g])≈eta
        end
        table=RG._table(d)
        shifted=merge(table,(;score=table.score.+5))
        ts=RG.model(B.FacetData(shifted;person=:person,rater=:rater,item=:item,group=:group,score=:score,category_levels=5:K+4);prior=t.prior)
        @test L.logdensity(ts,q)≈L.logdensity(t,q)
        # Reordered observations induce new level indices; transport all coordinates.
        rev=map(reverse,table);tr=RG.model(B.FacetData(rev;person=:person,rater=:rater,item=:item,group=:group,score=:score,category_levels=0:K-1);prior=t.prior)
        idx(a,b)=[findfirst(isequal(x),b) for x in a]
        pp=idx(tr.data.person_levels,d.person_levels);rr=idx(tr.data.rater_levels,d.rater_levels)
        ii=idx(tr.data.item_levels,d.item_levels);gg=idx(tr.data.optional_levels[:group],d.optional_levels[:group])
        vr=(;person=v.person[pp],group_mean=v.group_mean[gg],item=v.item[ii],rater=v.rater[rr],steps=v.steps[ii,:],interaction=v.interaction[rr,gg],tau=v.tau)
        qr=encode_group(tr,vr)
        @test RG.category_logprobs(tr,qr)≈reverse(pr;dims=1)
        @test L.logdensity(tr,qr)≈L.logdensity(t,q)
        @test RG.target_identity(RG._restore_target(RG._target_record(t)))==RG.target_identity(t)
    end
    d=group_fixture();table=RG._table(d);prior=group_prior()
    make(x)=B.FacetData(x;person=:person,rater=:rater,item=:item,group=:group,score=:score,category_levels=0:2)
    wrong=deepcopy(table);wrong.group[1]="B"
    @test_throws ArgumentError RG.model(make(wrong);prior)
    keep=[r=="r$(mod(parse(Int,p[2:end])-1,3)+1)" for (p,r) in zip(table.person,table.rater)]
    disconnected=map(x->x[keep],table)
    @test_throws ArgumentError RG.model(make(disconnected);prior)
    keep=.!((table.rater.=="r1").&(table.group.=="B"))
    @test_throws ArgumentError RG.model(make(map(x->x[keep],table));prior)
    @test_throws ArgumentError RG.model(B.FacetData(table;person=:person,rater=:rater,item=:item,score=:score,category_levels=0:2);prior)
    @test_throws ArgumentError RG.Prior(;merge(RG._prior(prior),(;group_mean_sd=0.))...)
    @test :RaterGroupEffects in B.Experimental.surface_contract().reader_facing_bindings
end

end
