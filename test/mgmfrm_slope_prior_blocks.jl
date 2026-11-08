module MGMFRMSlopePriorBlockChecks
using Test, BayesianMGMFRM, LinearAlgebra
const B=BayesianMGMFRM
const E=B.Experimental
const FD=B.ForwardDiff

function target(R,K,policy; profiled=false, sd=1.0)
    cells=[(p,i,r) for p in 1:4 for i in 1:3 for r in 1:R]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+i+r,K) for (p,i,r) in cells]);person=:person,item=:item,
        rater=:rater,score=:score,category_levels=0:K-1)
    spec=mfrm_spec(data;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,q_matrix=trues(3,1))
    model=E.slope_restriction(spec;item_slopes=policy,rater_consistency=:fixed_one)
    base=E.NormalizedMGMFRMPrior(;prior_model=:exchangeable,person_sd=.6sd,
        rater_sd=.4sd,item_sd=.7sd,step_sd=.3sd,
        log_discrimination_sd=.35sd,log_consistency_sd=.45sd)
    prior=profiled ? E.MeanProfilePrior(model,base;
        item_means=Dict(i=>.1i for i in data.item_levels),
        step_means=Dict(i=>.02i.*((1:K-1).-K/2) for i in data.item_levels),
        category_levels=data.category_levels,units=:raw) : base
    return B._normalized_mgmfrm_target(model,prior)
end

# The unchanged full target supplies an independent retained Gaussian covariance.
function reference(t,x)
    R=length(t.base.design.spec.data.rater_levels);p=t.base.prior
    constant=(R-1)*(-log(p.log_consistency_sd)-log(2pi)/2)+log(R)/2
    if t.item_slopes===:fixed_one
        constant+=length(t.base.blueprint.blocks[:log_item_dimension_discrimination]) *
            (-log(p.log_discrimination_sd)-log(2pi)/2)
    end
    residual=t.profile===nothing ? x : x-t.mean_shift
    B.logprior(t.full,B._slope_full_raw(t,residual))-constant
end

@testset "Active prior blocks retain the normalized joint law" begin
    for R in (1,3), K in (2,3,25), policy in (:fixed_one,:estimated_positive)
        for profiled in (policy===:fixed_one ? (false,true) : (false,))
            t=target(R,K,policy;profiled);mu=initial_params(t);n=length(mu)
            precision=-FD.hessian(q->reference(t,q),mu)
            covariance=inv(Symmetric(precision))
            normalizer=(logdet(Symmetric(precision))-n*log(2pi))/2
            for x in (mu,mu.+.3sin.(1:n),mu.+2cos.(1:n))
                before=copy(x);v=B.logprior(t,x);r=x-mu
                @test x==before
                @test v≈reference(t,x) atol=1e-10 rtol=1e-12
                @test v≈normalizer-dot(r,precision*r)/2 atol=1e-10 rtol=1e-12
                @test FD.gradient(q->B.logprior(t,q),x)≈-(covariance\r) atol=1e-9 rtol=1e-10
                @test FD.hessian(q->B.logprior(t,q),x)≈-precision atol=1e-9 rtol=1e-10
                @test B.logprior(t,view(x,:))==v
            end
            @test_throws ArgumentError B.logprior(t,mu[1:end-1])
            @test_throws ArgumentError B.logprior(t,[mu;0.])
            @test_throws ArgumentError B.logprior(t,fill(NaN,n))
            @test_throws ArgumentError B.logprior(t,fill(Inf,n))
            rec=B._mgmfrm_normalized_prior_record(t)
            id=B._mgmfrm_normalized_prior_identity(t)
            restored=B._MGMFRMNormalizedPriorLogDensity(t.base.design.spec,rec;expected_identity=id)
            @test isequal(B._mgmfrm_normalized_prior_record(restored),rec)
            @test B.logprior(restored,mu)==B.logprior(t,mu)
        end
    end
end

@testset "Scale and residual boundaries retain stable arithmetic" begin
    for sd in (1e-150,1e150)
        t=target(3,3,:fixed_one;sd);x=sd.*sin.(1:length(initial_params(t)))
        @test isfinite(B.logprior(t,x))
        @test B.logprior(t,x)≈reference(t,x) atol=1e-10 rtol=1e-12
    end
    t=target(3,3,:fixed_one;profiled=true)
    x=initial_params(t);j=first(t.blueprint.blocks[:item])
    # A finite input can still overflow when the profile is subtracted.
    t.mean_shift[j]=-floatmax(Float64);x[j]=floatmax(Float64)
    @test_throws ArgumentError reference(t,x)
    @test_throws ArgumentError B.logprior(t,x)
end
end
