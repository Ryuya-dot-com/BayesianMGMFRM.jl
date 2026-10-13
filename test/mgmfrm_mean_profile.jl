isdefined(@__MODULE__, :MGMFRMSlopeRestrictionChecks) || include("mgmfrm_slope_restriction.jl")
module MGMFRMMeanProfileChecks
using Test, BayesianMGMFRM, Random, ForwardDiff, LinearAlgebra
using ..MGMFRMSlopeRestrictionChecks: specification, model, prior, saved_record_fixture
const B=BayesianMGMFRM; const E=B.Experimental
function profile(m; units=:raw, item_means=nothing, step_means=nothing, category_levels=m.base_spec.data.category_levels)
    data=m.base_spec.data;H=length(data.category_levels)-1
    item_means===nothing && (item_means=Dict(i=>-.12i for i in data.item_levels))
    step_means===nothing && (step_means=Dict(i=>.08i.*((1:H).-((H+1)/2)) for i in data.item_levels))
    E.MeanProfilePrior(m,prior();item_means,step_means,category_levels,units)
end
@testset "Fixed profiles bind IDs, scale and supported models" begin
    m=model(specification(),:fixed_one);d=m.base_spec.data;p=profile(m)
    @test :MeanProfilePrior in E.surface_contract().reader_facing_bindings
    @test occursin("not integrated",string(@doc E.MeanProfilePrior))
    @test_throws ArgumentError profile(m;units=:ambiguous)
    @test_throws ArgumentError profile(m;category_levels=reverse(d.category_levels))
    @test_throws ArgumentError profile(m;item_means=Dict(1=>0.))
    @test_throws ArgumentError profile(m;item_means=Dict(i=>true for i in d.item_levels))
    @test_throws ArgumentError profile(m;item_means=Dict(i=>Inf for i in d.item_levels))
    @test_throws ArgumentError profile(m;step_means=Dict(i=>[0.,1.,0.] for i in d.item_levels))
    @test_throws ArgumentError profile(m;step_means=Dict(i=>[0.,0.] for i in d.item_levels))
    @test_throws ArgumentError profile(model(specification(),:estimated_positive))
    @test_throws ArgumentError E.fit(m.base_spec;prior=p)
    @test_throws ArgumentError E.prior_predict(m.base_spec;prior=p,ndraws=1)
    @test_throws ArgumentError E.fit_cache_key(m;prior=p)
    @test_throws ArgumentError E.cached_fit(m;prior=p)
    @test_throws ArgumentError E.fit(m;prior=p,backend=:cmdstan)
    @test_throws ArgumentError E.fit(m;prior=p,sampling_coordinates=:orthogonal_person_mean_item_offset)
    @test_throws ArgumentError B._normalized_mgmfrm_target(model(specification(3,3),:fixed_one),p)
    malformed=deepcopy(p);malformed.profile.item_levels[1]=99
    @test_throws ArgumentError B._normalized_mgmfrm_target(m,malformed)
    @test_throws ArgumentError profile(model(specification(1,2),:fixed_one);step_means=Dict(i=>[.1] for i in 1:4))
end
@testset "Translated Gaussian law, generator and labels" begin
    for R in (1,3), K in (2,3,25)
        m=model(specification(R,K),:fixed_one);p=profile(m);t=B._normalized_mgmfrm_target(m,p)
        zero=B._normalized_mgmfrm_target(m,prior());mu=initial_params(t);n=length(mu)
        @test mu[t.blueprint.blocks[:item]]==p.profile.item_means
        @test mu[t.blueprint.blocks[:item_steps]]==reduce(vcat,[s[1:end-1] for s in p.profile.step_means])
        # Independent multivariate-normal oracle, including the chart normalizer.
        V=inv(-ForwardDiff.hessian(x->B.logprior(zero,x),zeros(n)));L=cholesky(Symmetric(V)).L
        for x in (mu, .2sin.(1:n), mu.+.4cos.(1:n))
            r=x-mu
            @test B.logprior(t,x)≈-sum(abs2,L\r)/2-sum(log,diag(L))-n*log(2pi)/2 atol=1e-10
            @test ForwardDiff.gradient(q->B.logprior(t,q),x)≈-(V\r) atol=1e-10
            @test B.LogDensityProblems.logdensity(t,x)≈B._source_fixture_loglikelihood(t.base,B._slope_full_raw(t,x))+B.logprior(zero,r) atol=1e-10
        end
        c=E.prior_predictive_check(m;prior=p,ndraws=3,rng=MersenneTwister(17))
        c0=E.prior_predictive_check(m;prior=prior(),ndraws=3,rng=MersenneTwister(17))
        @test c.raw_parameter_draws≈c0.raw_parameter_draws.+transpose(mu) atol=1e-14
        @test c.prior_metadata.blocks.item_steps.mean==p.profile.step_means
        @test c.prior_metadata.blocks.item.mean==p.profile.item_means
        @test !c.prior_metadata.blocks.item_steps.hard_ordered
        @test c.prior_metadata.blocks.item_steps.full_prior_exchangeable==(K==2)
        @test c.replicated_scores==E.prior_predict(m;prior=p,ndraws=3,rng=MersenneTwister(17))
        logits=profile(m;units=:unit_logit,item_means=Dict(i=>1.7v for (i,v) in zip(p.profile.item_levels,p.profile.item_means)),
            step_means=Dict(i=>1.7.*v for (i,v) in zip(p.profile.item_levels,p.profile.step_means)))
        @test initial_params(B._normalized_mgmfrm_target(m,logits))≈mu atol=1e-14
        zeros_profile=profile(m;item_means=Dict(i=>0. for i in 1:4),step_means=Dict(i=>zeros(K-1) for i in 1:4))
        tz=B._normalized_mgmfrm_target(m,zeros_profile)
        @test B.logprior(tz,.1sin.(1:n))==B.logprior(zero,.1sin.(1:n))
        @test B._mgmfrm_normalized_prior_identity(tz)!=B._mgmfrm_normalized_prior_identity(zero)
        rec=B._mgmfrm_normalized_prior_record(t)
        restored=B._MGMFRMNormalizedPriorLogDensity(m.base_spec,rec;expected_identity=B._mgmfrm_normalized_prior_identity(t))
        @test isequal(B._mgmfrm_normalized_prior_record(restored),rec)
        @test initial_params(restored)==mu
    end
end
@testset "Saved fit, report and heldout target preserve means" begin
    spec=specification(2,3)
    data=FacetData(map(v->repeat(v;inner=2),facet_response_table(spec.data));person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    source=B._refit_training_spec(spec,data);m=model(source,:fixed_one);p=profile(m)
    split=kfold_plan(data;k=2);ids=["profile-$i" for i in 1:data.n]
    plan=B.prediction_refit_plan(m,split;prior=p,dataset_id="profile-test",observation_ids=ids)
    req=plan.folds[1];t=B._normalized_mgmfrm_target(req.model,req.prior)
    record=saved_record_fixture(t,2);fit=E.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
    report=fit_report(fit;view=:full,include_prior_predictive=true,prior_predictive_ndraws=3,seed=11,require_complete=true)
    @test report.report_status===:complete
    @test all(r->r.loading===:fixed_one,report.q_matrix.rows)
    @test occursin("fixed at one",report.q_matrix.interpretation)
    @test only(filter(r->r.block===:item_steps,report.prior_policy.rows)).mean==p.profile.step_means
    @test !diagnostics(fit).summary.passed
    obs=B.prediction_fold_observations(fit,req)
    @test all(isfinite,obs.pointwise_loglikelihood)
    @test obs.native_metadata.prior.mean_profile==p.profile
    different=B.prediction_refit_plan(m,split;prior=prior(),dataset_id="profile-test",observation_ids=ids)
    @test_throws ArgumentError B.prediction_fold_observations(fit,different.folds[1])
    mktempdir() do dir
        path=joinpath(dir,"profile.jls");save_fit_cache(path,fit;artifact_include_draws=true)
        loaded=load_fit_cache(path)
        @test isequal(fit_metadata(loaded),fit_metadata(fit))
        @test predictive_probabilities(loaded)==predictive_probabilities(fit)
        @test isequal(B.prediction_fold_observations(loaded,req),obs)
        bad=deepcopy(record);bad.prior.mean_profile.item_means[1]+=.2
        bad=merge(bad,(;content_hash=B._mgmfrm_normalized_sample_hash(bad)))
        @test_throws ArgumentError E.NormalizedMGMFRMFit(bad;expected_identity=record.target_identity)
    end
end
end
