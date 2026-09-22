module PairedRatingReferenceChecks

using Test, LinearAlgebra, ForwardDiff, Random, Serialization
import LogDensityProblems as LDP
include(joinpath(@__DIR__,"..","scripts","paired_rating_reference.jl"))
const A=PairedRatingReference
const B=A.B
const PRIOR=(;word_sd=1.0,rater_sd=(0.5,0.6),step_sd=(0.7,0.8),
    recording_log_sd_mean=(log(0.5),log(0.6)),recording_log_sd_sd=(0.5,0.6),
    person_lkj_eta=2,recording_lkj_eta=5)

function rows(K=4)
    [(;person="P$p",word="W$w",recording="S$p-$w",rater="R$r",criterion="C$c",score=mod(p+w+r+c,K))
        for (p,w) in ((1,1),(1,2),(2,2),(2,3),(3,1),(3,3)) for r in 1:3 for c in 1:2
        if !(p==1 && w==1 && r==1 && c==1)]
end
target(K=4;prior=PRIOR)=A.Target(rows(K);categories=K,criteria=["C1","C2"],prior)

# Independent centered-coordinate density and Cholesky map, including the
# determinants of the noncentered transforms and the log-SD/tanh Jacobians.
function oracle(t,q)
    d,b,p=t.data,t.blocks,t.prior
    rho=tanh.(q[b.z_correlation]); sd=exp.(q[b.log_recording_sd])
    corr=[one(rho[1]) rho[1];rho[1] one(rho[1])]
    covariance=[sd[1]^2 rho[2]*prod(sd);rho[2]*prod(sd) sd[2]^2]
    theta=cholesky(Symmetric(corr)).L*reshape(q[b.person_white],2,d.P)
    u=cholesky(Symmetric(covariance)).L*reshape(q[b.recording_white],2,d.O)
    word=reshape(q[b.word],2,d.W)
    rf=reshape(q[b.rater_free],d.R-1,2); r=vcat(rf,-sum(rf;dims=1))
    sf=reshape(q[b.step_free],d.K-2,2); s=vcat(zeros(eltype(q),1,2),sf,-sum(sf;dims=1))
    pointwise=map(1:d.N) do n
        c=d.criterion[n]
        eta=theta[c,d.person[n]]-word[c,d.word[n]]-r[d.rater[n],c]+u[c,d.recording[n]]
        weights=[h*eta-sum(s[2:h+1,c];init=zero(eta)) for h in 0:d.K-1]
        m=maximum(weights)
        weights[d.score[n]+1]-m-log(sum(exp.(weights.-m)))
    end
    normal(x,mu,sd)=-log(sd)-log(2pi)/2-((x-mu)/sd)^2/2
    mvnormal(x,cov)=-(length(x)*log(2pi)+logdet(cov)+dot(x,cov\x))/2
    lp=sum(mvnormal(theta[:,i],corr) for i in 1:d.P)+d.P*logdet(corr)/2
    lp+=sum(mvnormal(u[:,i],covariance) for i in 1:d.O)+d.O*logdet(covariance)/2
    lp+=sum(normal(x,0,p.word_sd) for x in word)
    for c in 1:2
        for (free,kernel_sd,n) in ((rf[:,c],p.rater_sd[c],d.R),(sf[:,c],p.step_sd[c],d.K-1))
            if n>1
                cov=kernel_sd^2*(Matrix{Float64}(I,n-1,n-1).-1/n)
                lp+=mvnormal(free,cov)
            end
        end
        # Lognormal on sigma, then d sigma / d log(sigma).
        lp+=normal(log(sd[c]),p.recording_log_sd_mean[c],p.recording_log_sd_sd[c])-log(sd[c])+q[b.log_recording_sd[c]]
        eta=c==1 ? p.person_lkj_eta : p.recording_lkj_eta
        beta=Dict(1=>2.,2=>4/3,5=>256/315)[eta]
        lp+=(eta-1)*log1p(-rho[c]^2)-log(beta)+log1p(-rho[c]^2)
    end
    return (;logprior=lp,pointwise,logposterior=lp+sum(pointwise))
end

@testset "A0 paired-rating reference target" begin
    for K in (2,4,9), eta in (1,2,5)
        t=target(K;prior=merge(PRIOR,(;person_lkj_eta=eta)))
        d,b=t.data,t.blocks; q=A.initial(t)
        @test d.N==35 && d.O==6 && d.P==3 && d.R==3
        @test LDP.dimension(t)==2*(d.P+d.O+d.W+d.R-1+d.K-2)+4
        @test length(unique(t.names))==length(q)
        @test isequal(t.data,A.Target(reverse(rows(K));categories=K,criteria=["C1","C2"],prior=t.prior).data)
        @test A.identity(t)==A.identity(A.snapshot(t))
        @test A.identity(t)!=A.identity(target(K;prior=merge(t.prior,(;word_sd=2.))))
        for scale in (0.0,0.2,0.9)
            q=A.initial(t)+scale.*sin.(1:length(q))
            q[b.z_correlation]=[scale,-scale]
            ref=oracle(t,q); x=A.coordinates(t,q)
            @test A.logprior(t,q)≈ref.logprior atol=1e-10
            @test A.pointwise(t,q)≈ref.pointwise atol=1e-11
            @test LDP.logdensity(t,q)≈ref.logposterior atol=1e-10
            lp,g=LDP.logdensity_and_gradient(t,q)
            @test lp≈ref.logposterior atol=1e-10
            @test g≈ForwardDiff.gradient(v->LDP.logdensity(t,v),q) atol=1e-9 rtol=1e-9
            @test g≈ForwardDiff.gradient(v->oracle(t,v).logposterior,q) atol=1e-8 rtol=1e-8
            direction=cos.(1:length(q)); h=1e-5
            @test dot(g,direction)≈(LDP.logdensity(t,q+h*direction)-LDP.logdensity(t,q-h*direction))/(2h) atol=2e-7 rtol=2e-7
            @test all(abs.(sum(x.rater;dims=1)).<1e-12)
            @test all(abs.(sum(x.steps;dims=1)).<1e-12)
            @test all(iszero,x.steps[1,:])
            @test all(isapprox(sum(exp.(v)),1;atol=1e-13) for v in A.logprobabilities(t,q))
        end
        # Missing category levels are retained rather than forcing regeneration.
        zero_rows=[merge(row,(;score=0)) for row in rows(K)]
        @test A.Target(zero_rows;categories=K,criteria=["C1","C2"],prior=t.prior).data.K==K
        for z in (-20.,0.,20.)
            q=A.initial(t);q[b.z_correlation].=[z,-z]
            q[b.person_white].=0.2;q[b.recording_white].=-0.3
            lp,g=LDP.logdensity_and_gradient(t,q)
            @test isfinite(lp) && all(isfinite,g)
            @test g≈ForwardDiff.gradient(v->LDP.logdensity(t,v),q) atol=1e-9 rtol=1e-9
        end
    end
    t=target(); q=A.initial(t)+0.2sin.(1:LDP.dimension(t))
    # Relabeling the exchangeable raters preserves the prior and likelihood.
    permutation=[3,1,2]; relabeled=[merge(row,(;rater="R$(permutation[parse(Int,string(last(row.rater)))])")) for row in rows()]
    other=A.Target(relabeled;categories=4,criteria=["C1","C2"],prior=t.prior)
    old=A.coordinates(t,q).rater; new=similar(old);new[permutation,:]=old
    q2=copy(q);q2[t.blocks.rater_free]=vec(new[1:2,:])
    @test LDP.logdensity(t,q)≈LDP.logdensity(other,q2) atol=1e-10
    for bad in (zeros(length(q)-1),fill(NaN,length(q)),fill(Inf,length(q)))
        @test_throws ArgumentError LDP.logdensity(t,bad)
    end
    @test_throws ArgumentError target(;prior=merge(PRIOR,(;word_sd=0.)))
    @test_throws ArgumentError target(;prior=merge(PRIOR,(;recording_log_sd_sd=(0.5,0.))))
    @test_throws ArgumentError target(;prior=Base.structdiff(PRIOR,(;word_sd=nothing)))
    @test_throws ArgumentError A.Target([rows();first(rows())];categories=4,criteria=["C1","C2"],prior=PRIOR)
    @test_throws ArgumentError A.Target([merge(first(rows()),(;score=missing))];categories=4,criteria=["C1","C2"],prior=PRIOR)
    @test_throws ArgumentError A.Target([merge(first(rows()),(;score=4))];categories=4,criteria=["C1","C2"],prior=PRIOR)
    @test_throws ArgumentError A.Target([merge(first(rows()),(;person="wrong"));rows()[2:end]];categories=4,criteria=["C1","C2"],prior=PRIOR)
end

function sampling_checks(t,result,directory)
    @test A.restore(result).data==t.data
    path=joinpath(directory,"samples.jls")
    A.save_result(path,result);loaded=A.load_result(path)
    report=A.report(result)
    @test length(report.raw_diagnostics)==LDP.dimension(t)
    @test all(r->r.parameter_space==:raw_noncentered,report.raw_diagnostics)
    @test all(r->r.parameter_space==:model,report.model_diagnostics)
    @test Set(getproperty.(last(report.posterior,2),:parameter))==Set(["rho_person","rho_recording"])
    @test any(row->row.flag!=:ok,report.model_diagnostics)
    @test length(result.run.warmup_stats)==result.run.controls.warmup*result.run.controls.chains
    @test isequal(A.report(loaded),report)
    @test_throws ArgumentError A.save_result(path,result)
    corrupt=deepcopy(result);corrupt.run.draws[1,1]+=0.01
    @test_throws ArgumentError A.restore(corrupt)
    q=result.run.draws[1,:]
    @test A.pointwise(A.restore(loaded),q)==A.pointwise(t,q)
    B._write_json_record(joinpath(directory,"report.json"),report)
    return report
end

end # module
