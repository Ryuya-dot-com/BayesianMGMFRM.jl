isdefined(@__MODULE__, :MGMFRMNormalizedPriorPredictiveChecks) || include("mgmfrm_normalized_prior_predictive.jl")
module MGMFRMNormalizedFitChecks
using Test, BayesianMGMFRM, Random, Statistics, Serialization
using ..MGMFRMNormalizedPriorPredictiveChecks: specification, target, SCALES, saved_record_fixture
const B = BayesianMGMFRM
const E = B.Experimental
prior(model=:exchangeable; kwargs...) = E.NormalizedMGMFRMPrior(; prior_model=model, SCALES..., kwargs...)

@testset "Explicit normalized MGMFRM public boundary" begin
    spec = specification()
    for model in (:exchangeable, :source)
        p = prior(model; source_rater=model === :source ? :judge_3 : nothing)
        t = B._normalized_mgmfrm_target(spec, p)
        actual = E.prior_predictive_check(spec; prior=p, ndraws=9, rng=MersenneTwister(7))
        expected = B._mgmfrm_normalized_prior_predictive_check(t; ndraws=9, rng=MersenneTwister(7))
        @test actual.prior == expected.prior
        @test actual.raw_parameter_draws == expected.raw_parameter_draws
        @test actual.public_fit && actual.prior_metadata.public_fit
        @test actual.replicated_scores == E.prior_predict(spec; prior=p, ndraws=9, rng=MersenneTwister(7))
        @test_throws ArgumentError E.cached_fit(spec; prior=p, cache_path="unused.jls")
        @test_throws ArgumentError E.fit_cache_key(spec; prior=p)
        @test_throws ArgumentError E.fit(E.correlated(spec); prior=p)
        @test_throws ArgumentError E.fit(spec; prior=p, sampling_coordinates=:unknown)
        @test_throws ArgumentError E.fit(spec; prior=p, backend=:cmdstan,
            sampling_coordinates=:orthogonal_person_mean_item_offset)
        @test_throws ArgumentError E.fit(spec; prior=p, backend=:unsupported)
        @test_throws ArgumentError E.fit(specification(3, 2); prior=p, backend=:cmdstan)
        @test_throws ArgumentError E.prior_predictive_check(E.correlated(spec); prior=p)
        @test_throws ArgumentError E.fit(spec; prior=p, init=[0.0])
        @test_throws ArgumentError E.fit(spec; prior=p, experimental=true)
    end
    @test_throws UndefKeywordError E.NormalizedMGMFRMPrior(; prior_model=:exchangeable)
    @test_throws ArgumentError prior(:raw)
    @test_throws ArgumentError prior(:source)
    @test_throws ArgumentError prior(; source_rater=:judge_1)
    for value in (true, 0., -1., Inf, NaN)
        @test_throws ArgumentError prior(; rater_sd=value)
    end
    @test_throws ArgumentError E.fit(spec; prior=prior(:source; source_rater=:absent))
    @test_throws ArgumentError E.fit(spec; prior=E.ExchangeablePrior(rater_kernel_sd=.5))
end

@testset "Normalized saved results retain target, summaries and reports" begin
    for model in (:exchangeable, :source), (R, K, mixed) in ((1, 2, false), (3, 4, true)), version in (1, 2)
        spec = specification(R, K; mixed)
        t = target(spec, model, R)
        record = saved_record_fixture(t, version) # synthetic, not posterior evidence
        fit = E.NormalizedMGMFRMFit(record; expected_identity=record.target_identity)
        before = fit_metadata(fit)
        @test before.prior == record.prior
        @test isequal(before.prior_metadata.blocks, B._mgmfrm_normalized_prior_metadata(t).blocks)
        @test before.latent_correlation === :identity_fixed
        @test before.dimensions == spec.dimensions
        @test length(posterior_summary(fit)) == size(record.run.draws, 2)
        @test length(posterior_mcse(fit)) == before.n_direct_parameters
        @test length(B.direct_posterior_summary(fit)) == before.n_direct_parameters
        @test diagnostics(fit; view=:public).stability === :experimental
        @test !diagnostics(fit).summary.passed
        context = B._mgmfrm_correlated_2d_report_context(fit)
        options = (; include_prior_predictive=true, prior_predictive_ndraws=7,
            draw_indices=[8, 1, 1], seed=19, require_complete=true)
        report = fit_report(fit; view=:full, options...)
        @test report.report_status === :complete
        @test report.metadata.prior == record.prior
        @test report.prior_policy.prior == record.prior
        @test report.prior_predictive.prior == record.prior
        @test isempty(report.direct_posterior.correlation_rows)
        @test isempty(report.diagnostics.correlation_rows)
        @test report.dimensions == spec.dimensions
        @test report.prior_predictive.prior_label == before.prior_label
        p = prior(model; source_rater=record.prior.source_rater)
        check = E.prior_predictive_check(spec; prior=p, ndraws=7, rng=MersenneTwister(19))
        @test isequal(report.prior_predictive.rows, predictive_check_summary(check; interval=.9, include_grouped=true))
        checkpost = posterior_predictive_check(fit; draw_indices=[8, 1, 1], rng=MersenneTwister(19))
        @test isequal(report.posterior_predictive.rows, predictive_check_summary(checkpost; interval=.9, include_grouped=true))
        @test checkpost.prior_metadata.prior == record.prior
        prob = predictive_probabilities(fit; draw_indices=[8, 1, 1])
        @test prob ≈ B._mgmfrm_predictive_probabilities_direct(t.base.design, context.direct[[8, 1, 1], :])
        coords = B._mgmfrm_correlated_2d_report_coordinates(context)
        for (row, c) in zip(report.direct_posterior.rows, coords)
            @test row.mean ≈ mean(c.values)
            @test row.lower ≈ quantile(c.values, .025)
            @test row.upper ≈ quantile(c.values, .975)
        end
        for dimension in 1:spec.dimensions
            data = B._mgmfrm_correlated_2d_plot_data(context; block=:person, dimension)
            @test data.prior_label == before.prior_label
            @test !occursin("correlated", data.model_label)
        end
        public = fit_report_public(report)
        @test public.metadata.prior == Base.structdiff(record.prior, (; schema=nothing))
        mktempdir() do dir
            path = joinpath(dir, "fit.jls")
            saved = save_fit_cache(path, fit; artifact_include_draws=true, artifact_include_sampler_stats=true)
            restored = load_fit_cache(path; verify_hash=false)
            @test restored isa E.NormalizedMGMFRMFit
            @test isequal(fit_metadata(restored), before)
            @test isequal(posterior_summary(restored), posterior_summary(fit))
            @test posterior_predict(restored; rng=MersenneTwister(3)) == posterior_predict(fit; rng=MersenneTwister(3))
            @test_throws ArgumentError save_fit_cache(path, fit)
            @test_throws ArgumentError load_fit_cache(path; expected_cache_key="wrong")
            bad = merge(saved, (; target_identity="wrong"))
            serialize(joinpath(dir, "bad.jls"), bad)
            @test_throws ArgumentError load_fit_cache(joinpath(dir, "bad.jls"); verify_hash=false)
            badartifact = merge(saved.artifact, (; manifest=merge(saved.artifact.manifest,
                (; fit=merge(saved.artifact.manifest.fit, (; prior=merge(record.prior, (; prior_model=:raw))))))))
            serialize(joinpath(dir, "bad-artifact.jls"), merge(saved, (; artifact=badartifact)))
            @test_throws ArgumentError load_fit_cache(joinpath(dir, "bad-artifact.jls"); verify_hash=false)
            bundle = joinpath(dir, "report")
            save_fit_report_bundle(bundle, restored; options...)
            @test isdir(bundle)
            @test !isempty(readdir(bundle))
        end
    end
end
# Optional bounded operability check, separate from sampler-free CI evidence.
if get(ENV, "BAYESIANMGMFRM_NORMALIZED_FIT_SMOKE", "false") == "true"
    @testset "Normalized public sampler and saved-report smoke" begin
        backends = get(ENV, "BAYESIANMGMFRM_CMDSTAN_TESTS", "false") == "true" ?
            (:advancedhmc, :cmdstan) : (:advancedhmc,)
        spec = specification()
        for backend in backends, model in (:exchangeable, :source)
            p = prior(model; source_rater=model === :source ? :judge_3 : nothing)
            mktempdir() do dir
                options = backend === :cmdstan ? (; cmdstan_cache_dir=joinpath(dir, "stan")) : (;)
                fit = E.fit(spec; prior=p, backend, ndraws=8, warmup=10, chains=2,
                    max_depth=3, seed=260926, options...)
                t = B._normalized_mgmfrm_target(spec, p)
                @test fit isa E.NormalizedMGMFRMFit
                @test fit.record.run.backend === backend
                @test fit.record.run.total_draws == 16
                @test fit.record.run.logdensities ≈ [B.LogDensityProblems.logdensity(t, row) for row in eachrow(fit.record.run.draws)]
                path = joinpath(dir, "fit.jls")
                save_fit_cache(path, fit)
                restored = load_fit_cache(path)
                @test isequal(posterior_summary(restored), posterior_summary(fit))
                @test fit_metadata(restored).prior == B._mgmfrm_normalized_prior_record(t)
                report = fit_report(restored; include_prior_predictive=true,
                    prior_predictive_ndraws=8, seed=260926, require_complete=true, view=:full)
                @test report.prior_predictive.prior == report.metadata.prior
                println("Operability only: ", backend, " / ", model, "; diagnostics = ", diagnostics(fit).summary.flag)
                flush(stdout)
            end
        end
    end
end

end
