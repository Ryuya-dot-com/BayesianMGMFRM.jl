isdefined(@__MODULE__, :MGMFRMNormalizedPriorPredictiveChecks) || include("mgmfrm_normalized_prior_predictive.jl")
module MGMFRMSlopeRestrictionChecks
using Test, BayesianMGMFRM, Random, LinearAlgebra, ForwardDiff, Serialization
using ..MGMFRMNormalizedPriorPredictiveChecks: SCALES, saved_record_fixture
const B=BayesianMGMFRM;const E=B.Experimental
prior(;kwargs...)=E.NormalizedMGMFRMPrior(;prior_model=:exchangeable,merge(SCALES,(;kwargs...))...)
function specification(R=3,K=4)
    cells=[(p,i,r) for p in 1:4 for i in 1:4 for r in 1:R]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+i+r,K) for (p,i,r) in cells]);person=:person,item=:item,rater=:rater,
        score=:score,category_levels=0:K-1)
    mfrm_spec(data;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,q_matrix=trues(4,1))
end
model(spec,policy)=E.slope_restriction(spec;item_slopes=policy,rater_consistency=:fixed_one)

@testset "Slope restriction boundary and normalized reduced density" begin
    spec=specification();p=prior()
    @test_throws UndefKeywordError E.slope_restriction(spec;item_slopes=:fixed_one)
    @test_throws ArgumentError model(spec,:wrong)
    @test_throws ArgumentError E.slope_restriction(spec;item_slopes=:fixed_one,rater_consistency=:estimated)
    multidim=mfrm_spec(spec.data;family=:mgmfrm,dimensions=2,thresholds=:partial_credit,
        q_matrix=Bool[1 0;1 0;0 1;0 1])
    @test_throws ArgumentError model(multidim,:fixed_one)
    for R in (1,3), K in (2,4), policy in (:fixed_one,:estimated_positive)
        spec=specification(R,K);m=model(spec,policy);t=B._normalized_mgmfrm_target(m,p)
        contract=E.surface_contract(m;prior=p)
        @test contract.rater_consistency===:fixed_one
        @test contract.loading_policy===policy
        @test contract.supported_backends==(:advancedhmc,)
        @test model_family_contract(m).dimensionality.current_loading_policy===policy
        @test length(contract.raw_parameter_names)==4+R-1+4+4*(K-2)+(policy===:fixed_one ? 0 : 4)
        @test isempty(t.blueprint.blocks[:log_rater_consistency_free])
        for x in (zeros(length(t.active)),.4sin.(1:length(t.active)))
            full=B._slope_full_raw(t,x)
            @test full[t.active]==x
            @test all(iszero,full[t.full.base.blueprint.blocks[:log_rater_consistency_free]])
            # The normalized reduced prior has covariance given by the retained
            # block of the original normalized Gaussian law (independent fixed blocks).
            H=-ForwardDiff.hessian(q->B.logprior(t.full,q),zeros(length(full)))
            V=Matrix(inv(Symmetric(H)))[t.active,t.active];L=cholesky(Symmetric(V)).L
            expected=-sum(abs2,L\x)/2-sum(log,diag(L))-length(x)*log(2pi)/2
            @test B.logprior(t,x)≈expected atol=1e-10
            @test ForwardDiff.gradient(q->B.logprior(t,q),x)≈-(V\x) atol=1e-10
        end
        check=E.prior_predictive_check(m;prior=p,ndraws=5,rng=MersenneTwister(3))
        @test size(check.raw_parameter_draws,2)==length(t.active)
        @test all(==(1),check.direct_parameter_draws[:,t.base.design.blocks[:rater_consistency]])
        if policy===:fixed_one
            @test all(==(1),check.direct_parameter_draws[:,t.base.design.blocks[:item_dimension_discrimination]])
        end
        @test check.prior.item_slopes===policy
        @test check.replicated_scores==E.prior_predict(m;prior=p,ndraws=5,rng=MersenneTwister(3))
        other=prior(log_consistency_sd=.9,log_discrimination_sd=policy===:fixed_one ? 1.1 : .3)
        @test B.LogDensityProblems.logdensity(t,initial_params(t))≈
            B.LogDensityProblems.logdensity(B._normalized_mgmfrm_target(m,other),initial_params(t)) atol=1e-10
        @test_throws ArgumentError E.fit(m;prior=p,backend=:cmdstan)
        @test_throws ArgumentError E.fit(m;prior=p,sampling_coordinates=:orthogonal_person_mean_item_offset)
        @test_throws ArgumentError E.fit(m;prior=p,init=[0.])
        @test_throws ArgumentError E.fit(m)
        @test_throws ArgumentError E.fit(m;prior=E.NormalizedMGMFRMPrior(;prior_model=:source,source_rater=1,SCALES...))
    end
end

@testset "Fixed coefficients, reports and cache model identity" begin
    for R in (1,3), K in (2,4), policy in (:fixed_one,:estimated_positive)
        spec=specification(R,K);m=model(spec,policy);t=B._normalized_mgmfrm_target(m,prior())
        record=saved_record_fixture(t,2)
        fit=E.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
        metadata=fit_metadata(fit)
        @test metadata.loading_policy===policy && metadata.rater_consistency===:fixed_one
        @test metadata.n_parameters==length(t.active)
        @test length(posterior_summary(fit))==length(t.active)
        @test !diagnostics(fit).summary.passed
        direct=B.direct_posterior_summary(fit);mcse=posterior_mcse(fit)
        fixed=B._recorded_mgmfrm_samples(fit).structurally_fixed_parameters
        for i in t.base.design.blocks[:rater_consistency]
            @test direct[i].mean==1 && direct[i].sd==0
            @test direct[i].parameter in fixed
            @test mcse[i].mcse_status===:structurally_fixed
        end
        report=fit_report(fit;view=:full,include_prior_predictive=true,
            prior_predictive_ndraws=5,seed=32,require_complete=true)
        @test report.report_status===:complete
        @test occursin("fixed at one",report.metadata.interpretation)
        @test all(r->r.fixed && r.mean==1,filter(r->r.block===:rater_consistency,report.direct_posterior.rows))
        @test only(filter(r->r.parameter===:log_consistency_sd,report.prior_policy.rows)).active===false
        if policy===:fixed_one
            @test only(filter(r->r.parameter===:log_discrimination_sd,report.prior_policy.rows)).active===false
        end
        context=B._mgmfrm_correlated_2d_report_context(fit)
        plot=B._mgmfrm_correlated_2d_plot_data(context;block=:rater_consistency)
        @test occursin("fixed at one",plot.model_label)
        @test length(B._mgmfrm_correlated_2d_report_coordinates(context;scale=:raw))==length(t.active)
        ids=["rating-$i" for i in 1:spec.data.n]
        obs=B.prediction_observations(fit;dataset_id="slope-test",observation_ids=ids)
        @test obs.model.native_metadata.prior.item_slopes===policy
        @test all(isfinite,predictive_probabilities(fit))
        mktempdir() do dir
            path=joinpath(dir,"fit.jls");save_fit_cache(path,fit;artifact_include_draws=true)
            loaded=load_fit_cache(path)
            @test isequal(fit_metadata(loaded),metadata)
            @test isequal(posterior_summary(loaded),posterior_summary(fit))
            @test predictive_probabilities(loaded)==predictive_probabilities(fit)
            bad=merge(record,(;prior=merge(record.prior,(;item_slopes=policy===:fixed_one ? :estimated_positive : :fixed_one))))
            bad=merge(bad,(;content_hash=B._mgmfrm_normalized_sample_hash(bad)))
            @test_throws ArgumentError E.NormalizedMGMFRMFit(bad;expected_identity=record.target_identity)
            @test_throws ArgumentError load_fit_cache(path;expected_cache_key="different-policy")
        end
    end
end
@testset "K-fold requests retain the slope policy and reject another model" begin
    spec=specification();data=FacetData(map(v->repeat(v;inner=2),facet_response_table(spec.data));
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:3)
    source=B._refit_training_spec(spec,data)
    split=kfold_plan(data;k=2);ids=["shared-$i" for i in 1:data.n]
    fits=Dict();requests=Dict()
    for policy in (:fixed_one,:estimated_positive)
        m=model(source,policy)
        plan=B.prediction_refit_plan(m,split;prior=prior(),dataset_id="shared-ratings",observation_ids=ids)
        request=plan.folds[1];requests[policy]=request
        @test request.model.item_slopes===policy
        @test request.model.base_spec.data.n==spec.data.n
        t=B._normalized_mgmfrm_target(request.model,request.prior)
        r=saved_record_fixture(t,2)
        fit=E.NormalizedMGMFRMFit(r;expected_identity=r.target_identity);fits[policy]=fit
        heldout=B.prediction_fold_observations(fit,request)
        @test heldout.native_metadata.prior.item_slopes===policy
        @test heldout.observation_ids==ids[request.heldout_observations]
        @test all(isfinite,heldout.pointwise_loglikelihood)
    end
    @test fits[:fixed_one].record.target_identity!=fits[:estimated_positive].record.target_identity
    @test_throws ArgumentError B.prediction_fold_observations(fits[:fixed_one],requests[:estimated_positive])
    @test_throws ArgumentError B.prediction_fold_observations(fits[:estimated_positive],requests[:fixed_one])
end
end
