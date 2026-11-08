isdefined(@__MODULE__, :MGMFRMCorrelated2DFixtures) || include("mgmfrm_correlated_2d_fixtures.jl")
module MGMFRMArtifactReuseChecks
using Test, BayesianMGMFRM, Serialization
using ..MGMFRMCorrelated2DFixtures: target, synthetic_record
const B=BayesianMGMFRM
const E=B.Experimental

# The parent's four-public-call composition is an independent regression oracle.
function legacy_payload(fit::B._RecordedMGMFRMFit;
        include_draws::Bool, include_log_posterior::Bool, include_sampler_stats::Bool,
        include_environment::Bool, include_packages::Bool, kwargs...)
    metadata = fit_metadata(fit)
    diagnostic = diagnostics(fit; kwargs...)
    record, run = fit.record, fit.record.run
    policy = (; draws = B._artifact_inclusion_flag(include_draws),
        log_posterior = B._artifact_inclusion_flag(include_log_posterior),
        sampler_stats = B._artifact_inclusion_flag(include_sampler_stats),
        environment = B._artifact_inclusion_flag(include_environment),
        package_status = B._artifact_inclusion_flag(include_environment && include_packages))
    return (; schema = B._recorded_mgmfrm_schemas(fit).artifact,
        object = :fit_artifact, family = :mgmfrm, model = metadata.model, status = :experimental,
        manifest = (; object = :fit, family = :mgmfrm, model = metadata.target_contract,
            fit = metadata, diagnostics = diagnostic.summary),
        diagnostics = diagnostic, posterior_summary = posterior_summary(fit),
        direct_posterior_summary = B.direct_posterior_summary(fit),
        reproducibility = (; data_signature = metadata.data_signature,
            target_identity = record.target_identity, source_sample_schema = record.schema,
            source_sample_content_hash = record.content_hash, prior = metadata.prior,
            sampler_controls = deepcopy(run.controls), diagnostic_policy = metadata.diagnostic_settings,
            artifact_policy = policy),
        draws = include_draws ? copy(run.draws) : nothing,
        log_posterior = include_log_posterior ? copy(run.logdensities) : nothing,
        sampler_stats = include_sampler_stats ? deepcopy(run.sampler_stats) : nothing,
        warmup_stats = include_sampler_stats ? deepcopy(get(run, :warmup_stats, nothing)) : nothing)
end


# Fixed artificial sample records; no sampler or data generator is called.
function normalized_fixture(t)
    initial=initial_params(t);nparams=length(initial)
    controls=(;ndraws=4,chains=2,warmup=0,step_size=.1,target_accept=.8,
        max_depth=4,max_energy_error=1000.,init_jitter=0.,ad_backend=:ForwardDiff,
        gradient_backend=:ad,metric=:diagonal)
    draws=[initial[j]+.01sin(i+j) for i in 1:8,j in 1:nparams]
    logdensities=[B.LogDensityProblems.logdensity(t,x) for x in eachrow(draws)]
    chain_ids=repeat(1:2;inner=4);iterations=repeat(1:4,2)
    stats=NamedTuple[B._advancedhmc_stat_row((;log_density=logdensities[i],step_size=.1,
        acceptance_rate=.75,hamiltonian_energy=Float64(i)),chain_ids[i],iterations[i]) for i in 1:8]
    acceptance=fill(.75,2)
    run=(;checked=B._check_diagnostic_thresholds(1.01,400),nparams,initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),total_draws=8,draws,
        logdensities,chain_ids,iterations,chain_acceptance=acceptance,sampler_stats=stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(logdensities,iterations,acceptance,
            stats,controls,:advancedhmc),backend=:advancedhmc,sampler=:nuts,
        split_chains_requested=true,actual_split=true,warmup_stats=NamedTuple[])
    record=(;schema="bayesianmgmfrm.normalized_fixed_q_samples.v2",
        spec=deepcopy(t.base.design.spec),prior=B._mgmfrm_normalized_prior_record(t),
        target_identity=B._mgmfrm_normalized_prior_identity(t),run)
    record=merge(record,(;content_hash=B._mgmfrm_normalized_sample_hash(record)))
    return E.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
end

function fixtures()
    fits=[]
    for (K,R) in ((2,1),(4,3))
        t=target(;K,raters=R);r=synthetic_record(t;ndraws=4)
        push!(fits,B._CorrelatedMGMFRMFit(r;expected_identity=r.target_identity))
    end
    c=target();s=c.base.design.spec
    scales=B._source_fixture_prior_values(c.prior.source_prior)
    for kind in (:source,:exchangeable)
        t=B._MGMFRMNormalizedPriorLogDensity(s;scales,prior_model=kind,
            source_rater=kind===:source ? first(s.data.rater_levels) : nothing)
        push!(fits,normalized_fixture(t))
    end
    s1=mfrm_spec(s.data;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,q_matrix=trues(4,1))
    base=E.NormalizedMGMFRMPrior(;prior_model=:exchangeable,scales...)
    for policy in (:fixed_one,:estimated_positive)
        m=E.slope_restriction(s1;item_slopes=policy,rater_consistency=:fixed_one)
        push!(fits,normalized_fixture(B._normalized_mgmfrm_target(m,base)))
        if policy===:fixed_one
            p=E.MeanProfilePrior(m,base;item_means=Dict(i=>.2 for i in s.data.item_levels),
                step_means=Dict(i=>[-.1,0.,.1] for i in s.data.item_levels),
                category_levels=s.data.category_levels,units=:raw)
            push!(fits,normalized_fixture(B._normalized_mgmfrm_target(m,p)))
        end
    end
    return fits
end

function check_fixture(fit)
    original=deepcopy(fit.record.run)
    for include_draws in (false,true)
        options=(;include_draws,include_log_posterior=include_draws,
            include_sampler_stats=include_draws,include_environment=include_draws,
            include_packages=include_draws)
        old=legacy_payload(fit;options...)
        new=B._mgmfrm_correlated_2d_artifact_payload(fit;options...)
        @test isequal(new,old)
        @test !new.diagnostics.summary.passed
        @test isequal(fit.record.run,original)
        @test_throws ArgumentError B._mgmfrm_correlated_2d_artifact_payload(fit;options...,split_chains=false)
    end
    @test_throws ArgumentError fit_metadata(fit;view=:invalid)
    @test_throws ArgumentError diagnostics(fit;view=:invalid)
    @test_throws ArgumentError fit_artifact(fit;view=:invalid)
    @test_throws ArgumentError posterior_summary(fit;lower=.9,upper=.1)
    @test isequal(posterior_summary(fit;intervals=(.8,),reference=.2,rope=(-.1,.1)),
        B._recorded_mgmfrm_posterior_summary(B._recorded_mgmfrm_summary_input(
            B._recorded_mgmfrm_samples(fit),:raw_unconstrained);intervals=(.8,),reference=.2,rope=(-.1,.1)))
    mktempdir() do dir
        path=joinpath(dir,"fit.jls")
        saved=save_fit_cache(path,fit;artifact_include_draws=true,artifact_include_sampler_stats=true)
        loaded=load_fit_cache(path)
        @test isequal(loaded.record.run,fit.record.run)
        @test loaded.record.content_hash==fit.record.content_hash
        @test isequal(fit_metadata(loaded),fit_metadata(fit))
        @test isequal(diagnostics(loaded),diagnostics(fit))
        @test_throws ArgumentError load_fit_cache(path;expected_cache_key="wrong")
        bad=deepcopy(saved);bad.fit.record.run.draws[1,1]+=.1
        broken=joinpath(dir,"corrupt-source.jls");serialize(broken,bad)
        @test_throws ArgumentError load_fit_cache(broken;verify_hash=false)
        altered=copy(saved.artifact.posterior_summary)
        altered[1]=merge(altered[1],(;mean=altered[1].mean+.1))
        artifact=B._with_archive_metadata(merge(saved.artifact,(;posterior_summary=altered));
            label=B._recorded_mgmfrm_schemas(fit).label)
        archive=fit_archive_manifest(artifact;label=:fit_cache_artifact,source_path=path)
        forged=merge(saved,(;artifact,archive_manifest=archive,artifact_content_hash=archive.content_hash))
        forged_path=joinpath(dir,"forged-artifact.jls");serialize(forged_path,forged)
        @test_throws ArgumentError load_fit_cache(forged_path;verify_hash=false)
    end
    for field in (:draws,:chain_ids,:warmup_stats)
        r=deepcopy(fit.record)
        field===:draws && (r.run.draws[1,1]+=.1)
        field===:chain_ids && (r.run.chain_ids[1]=99)
        field===:warmup_stats && push!(r.run.warmup_stats,(;chain=1,iteration=1))
        r=merge(r,(;content_hash=B._mgmfrm_normalized_sample_hash(r)))
        @test_throws Union{ArgumentError,B._SamplerError} typeof(fit)(r;expected_identity=r.target_identity)
    end
    # A successful call must not leave a stale cross-call validation cache.
    fit.record.run.draws[1,1]+=.1
    @test_throws ArgumentError fit_metadata(fit)
    @test_throws ArgumentError fit_artifact(fit)
    fit.record.run.draws[1,1]=original.draws[1,1]
    @test isequal(fit.record.run,original)
    @test isequal(fit_artifact(fit;include_environment=false).posterior_summary,posterior_summary(fit))
end

@testset "Reuse within an operation preserves artifacts and integrity" begin
    for fit in fixtures()
        check_fixture(fit)
    end
end
end
