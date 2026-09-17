isdefined(@__MODULE__, :MFRMExchangeableSampleChecks) || include("mfrm_exchangeable_samples.jl")
module MFRMExchangeableAPIChecks
using Test, BayesianMGMFRM, Random, Serialization
using ..MFRMExchangeableRaterChecks: specification, target, SCALES
using ..MFRMExchangeableSampleChecks: synthetic_record, rehash
const B = BayesianMGMFRM
const E = B.Experimental
untimed(r) = Base.structdiff(r, (; created_at=nothing))

function check_fit(fit; directory=nothing)
    directory === nothing && return mktempdir(d -> check_fit(fit; directory=d))
    record = fit.record
    metadata = fit_metadata(fit)
    @test fit isa E.ExchangeableMFRMFit
    @test metadata.public_fit && metadata.fitting_available && metadata.cache_available
    @test metadata.prior == record.prior
    @test metadata.rater_prior === :normalized_zero_sum_normal
    @test metadata.target_identity == record.target_identity
    @test metadata.model === B._fixed_q_fit_model(fit)
    @test occursin("exchangeable rater prior", repr(fit))
    @test !occursin("_Exchangeable", repr(fit))
    @test diagnostics(fit).summary.flag !== :ok
    @test_throws ArgumentError diagnostics(fit; rhat_threshold=1.2)
    if record.spec isa E.CorrelatedMFRMSpec
        @test last(posterior_summary(fit)).parameter_space === :fisher_z
        rho = only(filter(r -> r.block === :latent_correlation, B.direct_posterior_summary(fit)))
        @test rho.parameter_space === :correlation
        @test rho.mean ≈ sum(tanh.(record.run.draws[:,end])) / size(record.run.draws,1)
    end
    artifact = fit_artifact(fit; include_environment=false)
    @test artifact.schema == "bayesianmgmfrm.mfrm_exchangeable_raters_fit_artifact.v1"
    @test artifact.manifest.spec.prior == record.prior
    @test isequal(artifact.manifest.fit, metadata)
    @test artifact.reproducibility.prior == record.prior
    @test_throws ArgumentError fit_artifact(fit; legacy=true)
    path = joinpath(directory,"fit.jls")
    saved = save_fit_cache(path,fit; artifact)
    bytes = read(path)
    restored = load_fit_cache(path)
    @test restored isa E.ExchangeableMFRMFit
    for f in (fit_metadata, posterior_summary, B.direct_posterior_summary, diagnostics)
        @test isequal(f(restored), f(fit))
    end
    options = (; seed=37, ndraws=7, include_prior_predictive=true, prior_predictive_ndraws=19,
        prior_interval=0.8, predictive_interval=0.7, require_complete=true, include_artifact=false)
    full = fit_report(fit; view=:full, options...)
    public = fit_report(fit; options...)
    projected = fit_report_public(full)
    @test projected.schema == public.schema == "bayesianmgmfrm.fit_report_public.v1"
    for section in (:metadata, :prior_policy, :prior_predictive, :posterior,
            :direct_posterior, :diagnostics, :posterior_predictive, :warmup)
        @test isequal(getproperty(projected,section),getproperty(public,section))
    end
    @test B._assert_public_fit_report_language(public) === public
    @test public.metadata.prior == B._public_fit_report_project_value(record.prior)
    @test full.metadata.public_fit && full.prior_predictive.prior == record.prior
    @test full.diagnostics.summary.flag === diagnostics(fit).summary.flag
    @test isequal(untimed(full),untimed(fit_report(restored;view=:full,options...)))
    for report in (public,full)
        md = fit_report_markdown(report;max_rows=0)
        @test occursin("rater_kernel_sd",md)
        @test !occursin("renaming rater IDs can change",md)
    end
    save_fit_report_bundle(joinpath(directory,"report"),restored;options...)
    @test load_fit_report_bundle(joinpath(directory,"report");require_complete=true)["report_status"] == "complete"
    @test read(path) == bytes
    # The cache digest does not authorize a different prior, schema or derived summary.
    wrong = B._with_archive_metadata(merge(artifact,(;posterior_summary=reverse(artifact.posterior_summary)));
        label=B._fixed_q_artifact_label(fit))
    @test_throws ArgumentError save_fit_cache(path,fit;overwrite=true,artifact=wrong)
    @test read(path) == bytes
    badpath = joinpath(directory,"invalid.jls")
    for bad in (merge(saved,(;model=:mfrm_fixed_q)),
            merge(saved,(;artifact=merge(artifact,(;schema="bayesianmgmfrm.mfrm_fixed_q_fit_artifact.v2")))),
            merge(saved,(;artifact=wrong)),merge(saved,(;target_identity=record.prior.base_identity)))
        B._save_serialized_record(badpath,bad;overwrite=true)
        for verify_hash in (true,false)
            @test_throws ArgumentError load_fit_cache(badpath;verify_hash)
        end
    end
    corrupt = E.ExchangeableMFRMFit(record;expected_identity=record.target_identity)
    corrupt.record.run.draws[1,1] += 0.1
    @test_throws ArgumentError save_fit_cache(path,corrupt;overwrite=true)
    @test read(path) == bytes
    @test record.content_hash == B._mgmfrm_normalized_sample_hash(record)
    return restored
end

@testset "explicit exchangeable prior and public result API" begin
    prior = E.ExchangeablePrior(;SCALES...)
    @test E.ExchangeablePrior(rater_kernel_sd=0.4).person_sd == MFRMPrior().person_sd
    @test occursin("Experimental.ExchangeablePrior",repr(prior))
    @test_throws UndefKeywordError E.ExchangeablePrior()
    for name in keys(SCALES), invalid in (0,-1,Inf,NaN,true,"0.4")
        @test_throws ArgumentError E.ExchangeablePrior(;merge(SCALES,NamedTuple{(name,)}((invalid,)))...)
    end
    @test_throws MethodError E.ExchangeablePrior(rater_kernel_sd=0.4,rater_sd=0.4)
    for (D,K,mixed,correlated) in ((2,2,false,false),(3,4,false,false),(2,4,true,false),(2,4,false,true))
        spec = specification(3,K;D,mixed)
        model = correlated ? E.correlated(spec;lkj_eta=3) : spec
        t = target(spec,correlated)
        identity = B._mfrm_exchangeable_rater_identity(t)
        check = E.prior_predictive_check(model;prior,ndraws=17,rng=MersenneTwister(4))
        @test check.target_identity == identity
        @test isequal(check,B._mfrm_exchangeable_prior_check(t;ndraws=17,rng=MersenneTwister(4)))
        @test check.replicated_scores == E.prior_predict(model;prior,ndraws=17,rng=MersenneTwister(4))
        @test_throws ArgumentError E.prior_predictive_check(model;prior,ndraws=0)
        @test_throws ArgumentError E.prior_predictive_check(model;prior,min_category_probability=2)
        custom = E.prior_predictive_check(model;prior,ndraws=17,rng=MersenneTwister(4),
            min_category_probability=0.05,prior_warning_probability=0.8,wide_facet_range_fraction=0.6)
        @test custom.replicated_scores == check.replicated_scores
        @test custom.implication_diagnostics != check.implication_diagnostics
        for backend in (:advancedhmc,:cmdstan)
            record = synthetic_record(t,model,backend)
            fit = E.ExchangeableMFRMFit(record;expected_identity=identity)
            @test fit.record.run.draws !== record.run.draws
            check_fit(fit)
            @test_throws ArgumentError E.fit(model;prior,backend,ndraws=0)
            @test_throws ArgumentError E.fit(model;prior,backend,init=[NaN])
            @test_throws ArgumentError E.fit(model;prior,backend,init=0)
        end
        @test_throws ArgumentError E.fit(model;prior,backend=:absent)
        @test_throws (correlated ? MethodError : ArgumentError) B.fit(model;prior)
    end
    spec = specification()
    for family in (:gmfrm,:mgmfrm)
        other = mfrm_spec(spec.data;family,dimensions=family===:gmfrm ? 1 : 2,
            q_matrix=family===:gmfrm ? nothing : spec.q_matrix,
            discrimination=family===:gmfrm ? :rater : :none)
        @test_throws ArgumentError E.fit(other;prior,ndraws=1,warmup=0,chains=1)
        @test_throws ArgumentError E.prior_predictive_check(other;prior,ndraws=1)
    end
end
end
