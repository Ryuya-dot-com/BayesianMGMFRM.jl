isdefined(@__MODULE__, :MGMFRMCorrelated2DSampleChecks) || include("mgmfrm_correlated_2d_samples.jl")
module MGMFRMCorrelated2DResultChecks
using Test, BayesianMGMFRM, Serialization, Statistics
using ..MGMFRMCorrelated2DSampleChecks: target, synthetic_record, controls
const B = BayesianMGMFRM
const E = B.Experimental
include("test_groups.jl")

Base.@nospecializeinfer function check_fit(@nospecialize(fit), directory)
    record=fit.record
    metadata=fit_metadata(fit); diag=diagnostics(fit)
    @test fit isa E.CorrelatedMGMFRMFit && !(fit isa B.MGMFRMFit)
    @test metadata.model===:mgmfrm_correlated_2d_raw_prior && metadata.latent_correlation===:free_2d
    @test metadata.prior.lkj_eta==record.prior.lkj_eta && metadata.prior.scales==record.prior.scales
    @test metadata.prior.ability===:conditional_bivariate_normal
    @test metadata.likelihood_scale==1.7 && metadata.loading_policy===:estimated_positive_fixed_q
    @test metadata.scientific_acceptance===:not_established && metadata.public_fit
    @test fit_metadata(fit;view=:public).latent_correlation===:free_2d
    @test !diag.summary.passed && !hasproperty(diag,:direct_values)
    @test diagnostics(fit;view=:public).summary.flag===diag.summary.flag
    @test isequal(sampler_diagnostics(fit),diag.sampler_rows)
    @test isequal(sampler_diagnostics(fit;phase=:warmup),diag.warmup_rows)
    @test last(posterior_summary(fit)).parameter_space===:fisher_z
    rho=last(B.direct_posterior_summary(fit;lower=0.1,upper=0.9))
    @test rho.parameter_space===:correlation
    @test rho.mean≈mean(tanh.(record.run.draws[:,end]))
    @test rho.lower≈quantile(tanh.(record.run.draws[:,end]),0.1)
    @test isequal(posterior_mcse(fit),B._mgmfrm_correlated_2d_posterior_mcse((;record)))
    @test last(posterior_mcse(fit;parameter_space=:raw_unconstrained)).parameter_space===:fisher_z
    @test occursin("estimated rho; experimental",sprint(show,fit))
    @test_throws ArgumentError diagnostics(fit;rhat_threshold=1.5)
    @test_throws ArgumentError diagnostics(fit;split_chains=!record.run.split_chains_requested)
    @test_throws ArgumentError sampler_diagnostics(fit;phase=:all)
    @test_throws ArgumentError fit_metadata(fit;view=:invalid)
    artifact=fit_artifact(fit;include_environment=false)
    @test artifact.schema=="bayesianmgmfrm.correlated_mgmfrm_fit_artifact.v1"
    @test isequal(artifact.manifest.fit,metadata)
    @test isequal(artifact.direct_posterior_summary,B.direct_posterior_summary(fit))
    @test artifact.reproducibility.target_identity==record.target_identity
    @test artifact.content_hash.value==artifact_content_hash(artifact)
    @test fit_archive_manifest(fit;artifact).content_hash.value==artifact.content_hash.value
    @test artifact.draws===artifact.log_posterior===artifact.sampler_stats===artifact.environment===nothing
    included=fit_artifact(fit;include_environment=false,include_draws=true,include_sampler_stats=true)
    @test included.draws==record.run.draws && included.draws!==record.run.draws
    @test included.log_posterior==record.run.logdensities
    @test isequal(included.sampler_stats,record.run.sampler_stats)
    path=joinpath(directory,"fit.jls")
    saved=save_fit_cache(path,fit;artifact,cache_key="manual-correlated")
    @test saved.schema=="bayesianmgmfrm.correlated_mgmfrm_fit_cache.v1"
    @test saved.fit.record.run.draws!==fit.record.run.draws
    bytes=read(path)
    for verify_hash in (false,true)
        loaded=load_fit_cache(path;verify_hash,expected_cache_key="manual-correlated")
        @test loaded isa E.CorrelatedMGMFRMFit
        @test isequal(fit_metadata(loaded),metadata)
        @test isequal(diagnostics(loaded),diag)
        @test isequal(posterior_mcse(loaded),posterior_mcse(fit))
    end
    @test isequal(load_fit_cache(path;return_record=true).artifact,artifact)
    @test_throws ArgumentError load_fit_cache(path;expected_cache_key="wrong")
    @test_throws ArgumentError save_fit_cache(path,fit)
    wrong=merge(artifact,(;model=:mgmfrm_independent))
    @test_throws ArgumentError save_fit_cache(path,fit;artifact=wrong,overwrite=true)
    @test read(path)==bytes
    # Semantic corruption is rejected even after recomputing the artifact hashes.
    rearchive(a)=B._with_archive_metadata(B._artifact_hash_payload(a);label=:correlated_mgmfrm_fit_artifact)
    bad_artifact=rearchive(merge(artifact,(;direct_posterior_summary=NamedTuple[])))
    wrong_archive=B.fit_archive_manifest(bad_artifact;label=:fit_cache_artifact,source_path=path)
    altered_fit=deepcopy(fit);altered_fit.record.run.draws[1,end]+=0.5
    bads=[merge(saved,(;target_identity="wrong")),merge(saved,(;source_sample_content_hash="wrong")),
        merge(saved,(;fit=altered_fit)),merge(saved,(;schema="bayesianmgmfrm.fit_cache.v1")),
        merge(saved,(;schema="bayesianmgmfrm.fit_cache.v2")),
        merge(saved,(;artifact=bad_artifact,artifact_content_hash=wrong_archive.content_hash,archive_manifest=wrong_archive)),
        merge(saved,(;archive_manifest=merge(saved.archive_manifest,(;label=:wrong))))]
    malformed=joinpath(directory,"malformed.jls")
    for bad in bads
        open(io->serialize(io,bad),malformed,"w")
        for verify_hash in (false,true)
            @test_throws ArgumentError load_fit_cache(malformed;verify_hash)
        end
    end
    @test_throws ArgumentError E.CorrelatedMGMFRMFit(record;expected_identity="wrong")
    @test_throws ArgumentError B._restore_mgmfrm_correlated_2d_samples(saved;expected_identity=record.target_identity)
    # User-supplied artifacts are optional; default policy must also round-trip.
    default_path=joinpath(directory,"default.jls")
    save_fit_cache(default_path,fit)
    @test isequal(fit_metadata(load_fit_cache(default_path)),metadata)
    full_path=joinpath(directory,"included.jls")
    save_fit_cache(full_path,fit;artifact=included)
    @test load_fit_cache(full_path;return_record=true).artifact.draws==record.run.draws
    return nothing
end

@testset "explicit correlated MGMFRM specification and result" begin
    t=target();base=t.base.design.spec;model=E.correlated(base;lkj_eta=5)
    @test model isa E.CorrelatedMGMFRMSpec && model.base_spec!==base
    @test model.base_spec.q_matrix!==base.q_matrix
    @test E.surface_contract(:mgmfrm).latent_correlation===:identity_fixed
    contract=E.surface_contract(model)
    @test contract.latent_correlation===:free_2d && contract.prior.lkj_eta==5
    @test contract.prior.explicit_prior_required && contract.fit_enabled && contract.manual_cache_enabled
    @test !contract.automatic_cache_enabled && contract.prior.prior_predictive_check_available
    @test contract.reports_available && contract.plots_available
    @test occursin("LKJ eta = 5",sprint(show,model))
    prior=E.GeneralizedPrior(;B._source_fixture_prior_values(t.prior.source_prior)...)
    for invalid in (nothing,MFRMPrior(),t.prior.source_prior,E.ExchangeablePrior(;rater_kernel_sd=0.4))
        @test_throws ArgumentError E.fit(model;prior=invalid)
    end
    for backend in (:advancedhmc,:cmdstan)
        @test_throws ArgumentError E.fit(model;prior,backend,ndraws=0)
        @test_throws ArgumentError E.fit(model;prior,backend,init=[NaN])
        @test_throws ArgumentError E.fit(model;prior,backend,init="wrong")
    end
    @test_throws ArgumentError E.fit(model;prior,experimental=true)
    @test_throws ArgumentError E.fit(model;prior,backend=:turing)
    for op in (E.cached_fit,E.fit_cache_key,E.preview,E.prior_predict,E.prior_predictive_check)
        @test_throws ArgumentError op(model)
    end
    for eta in (0,1.5,10001)
        @test_throws ArgumentError E.correlated(base;lkj_eta=eta)
    end
    bad=deepcopy(model);bad.base_spec.q_matrix[1,2]=true
    @test_throws ArgumentError E.fit(bad;prior)
    @test_throws ArgumentError E.surface_contract(bad)
    @test_throws ArgumentError E.correlated(bad.base_spec)
    @test !E.free_latent_correlation_2d_contract().fit_enabled
    @test_throws ArgumentError E.fit(t;prior) # Legacy density-only entry remains separate.
    for name in (:CorrelatedMGMFRMSpec,:CorrelatedMGMFRMFit)
        @test name ∉ names(B) && name ∉ names(E)
        @test name in E.surface_contract().reader_facing_bindings
    end
    for K in (2,4),backend in (:advancedhmc,:cmdstan)
        t=target(;K,raters=K==2 ? 1 : 3,eta=K==2 ? 5 : 2)
        record=synthetic_record(t;backend)
        fit=E.CorrelatedMGMFRMFit(record;expected_identity=record.target_identity)
        @test fit.record.run.draws!==record.run.draws
        mktempdir(dir->check_fit(fit,dir))
    end
end

function fit_check(backend,directory)
    t=target();model=E.correlated(t.base.design.spec;lkj_eta=t.prior.lkj_eta)
    prior=E.GeneralizedPrior(;B._source_fixture_prior_values(t.prior.source_prior)...)
    options=backend===:cmdstan ? (;cmdstan_cache_dir=joinpath(directory,"compile")) : (;)
    fit=E.fit(model;prior,backend,controls...,options...)
    @test fit.record.target_identity==B._mgmfrm_correlated_2d_identity(t)
    @test fit.record.run.controls.rng.seed==controls.seed
    check_fit(fit,directory)
    @test all(r->r.coverage===:recorded,sampler_diagnostics(fit;phase=:warmup))
    return fit
end

@testset "explicit correlated MGMFRM Julia fit and manual cache" begin
    root=get(ENV,"BAYESIANMGMFRM_CORRELATED_FIT_OUTPUT",nothing)
    root===nothing ? mktempdir(dir->fit_check(:advancedhmc,dir)) : fit_check(:advancedhmc,mkpath(joinpath(root,"julia")))
end
if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "explicit correlated MGMFRM CmdStan fit and manual cache" begin
        root=get(ENV,"BAYESIANMGMFRM_CORRELATED_FIT_OUTPUT",nothing)
        root===nothing ? mktempdir(dir->fit_check(:cmdstan,dir)) : fit_check(:cmdstan,mkpath(joinpath(root,"cmdstan")))
    end
end
end
