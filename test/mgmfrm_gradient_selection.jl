module MGMFRMGradientSelectionChecks
using Test, BayesianMGMFRM
const B=BayesianMGMFRM
const E=B.Experimental

@testset "D1 gradient selection follows the admitted model contract" begin
    for R in (1,3), K in (2,3,25), policy in (:fixed_one,:estimated_positive)
        # Fixed artificial inputs include declared but unobserved categories.
        cells=[(p,i,r) for p in 1:4 for i in 1:3 for r in 1:R]
        d=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
            score=[mod(p+i+r,K) for (p,i,r) in cells]);
            person=:person,item=:item,rater=:rater,score=:score,category_levels=0:K-1)
        s=mfrm_spec(d;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,q_matrix=trues(3,1))
        m=E.slope_restriction(s;item_slopes=policy,rater_consistency=:fixed_one)
        base=E.NormalizedMGMFRMPrior(prior_model=:exchangeable,
            person_sd=.6,rater_sd=.4,item_sd=.7,step_sd=.3,
            log_discrimination_sd=.35,log_consistency_sd=.45)
        for profiled in (policy===:fixed_one ? (false,true) : (false,))
            prior=profiled ? E.MeanProfilePrior(m,base;
                item_means=Dict(i=>.1i for i in d.item_levels),
                step_means=Dict(i=>.02i.*((1:K-1).-K/2) for i in d.item_levels),
                category_levels=d.category_levels,units=:raw) : base
            contract=E.surface_contract(m;prior)
            @test contract.gradient_selection == (;requested=:auto,selected=:analytic,
                reason=:validated_d1_analytic_score)
            @test isequal(E.surface_contract(m;prior,ad_backend=:auto),contract)
            for ad_backend in (:analytic,:ForwardDiff,:ReverseDiff)
                explicit=E.surface_contract(m;prior,ad_backend)
                @test explicit.gradient_selection == (;requested=ad_backend,selected=ad_backend,
                    reason=:explicit_request)
                @test explicit.prior.target_identity==contract.prior.target_identity
            end
            @test_throws ArgumentError E.surface_contract(m;prior,ad_backend=:invalid)
            @test_throws ArgumentError E.fit(m;prior,ad_backend=:invalid)
            @test_throws ArgumentError E.fit(m;prior,init=fill(NaN,length(contract.raw_parameter_names)))
            @test m.base_spec.data.category_levels==collect(0:K-1)
            @test occursin("default gradient analytic",sprint(show,m))
        end
        # The unwrapped normalized target still has no analytic score contract.
        t=B._normalized_mgmfrm_target(s,base)
        @test B.LogDensityProblems.capabilities(typeof(t))==B.LogDensityProblems.LogDensityOrder{0}()
        s2=mfrm_spec(d;family=:mgmfrm,dimensions=2,thresholds=:partial_credit,q_matrix=[1 0; 0 1; 1 0])
        @test_throws ArgumentError E.slope_restriction(s2;item_slopes=policy,rater_consistency=:fixed_one)
    end
end
end
