isdefined(@__MODULE__, :MGMFRMCorrelated2DFixtures) || include("mgmfrm_correlated_2d_fixtures.jl")
module MGMFRMCorrelated2DSampleChecks
using Test, BayesianMGMFRM, Serialization, Statistics, Random
const B = BayesianMGMFRM
include("test_groups.jl")

using ..MGMFRMCorrelated2DFixtures: target, synthetic_record, rehash, restore, controls

Base.@nospecializeinfer function check_result(@nospecialize(result),t,directory)
    record=result.record;run=record.run;diag=result.diagnostics
    @test !result.public_fit && result.model===:mgmfrm_correlated_2d_raw_prior
    @test result.target_contract==B._mgmfrm_correlated_2d_contract(t)
    @test record.prior.lkj_eta==t.prior.lkj_eta
    @test result.raw_parameter_names==t.blueprint.parameter_names
    @test result.direct_parameter_names==[t.base.blueprint.constrained_parameter_names;t.blueprint.derived_parameter_names]
    @test diag.direct_values.direct_draws[:,end]==tanh.(run.draws[:,end])
    @test last(diag.parameter_rows).parameter_space===:fisher_z
    @test last(diag.direct_parameter_rows).parameter_space===:correlation
    @test only(filter(r->r.block===:z_latent_correlation,diag.block_rows)).parameter_space===:fisher_z
    @test only(filter(r->r.block===:latent_correlation,diag.direct_block_rows)).parameter_space===:correlation
    @test diag.raw_metrics.n_quality_gate_parameters==run.nparams
    @test diag.direct_metrics.n_quality_gate_parameters==length(result.direct_parameter_names)-length(result.structurally_fixed_parameters)
    @test diag.n_failed_direct_constraints==0 && diag.n_nonfinite_direct_loglikelihood==0
    @test diag.flag!==:ok # Every real run below is deliberately too short to qualify.
    for (i,x) in enumerate(eachrow(run.draws))
        raw=x[1:end-1]
        direct=B._mgmfrm_source_constrained_params_from_unconstrained(t.base.design,raw)
        @test diag.direct_values.direct_draws[i,1:end-1]≈direct atol=1e-12
        pointwise=B._mgmfrm_source_pointwise_loglikelihood(t.base.design,direct)
        @test diag.direct_values.pointwise_loglikelihood[i,:]≈pointwise atol=1e-10
        @test run.logdensities[i]≈sum(pointwise)+B._mgmfrm_free_latent_correlation_2d_logprior(t,x) atol=1e-9
    end
    for selected in (:raw_unconstrained,:direct_constrained)
        raw=selected===:raw_unconstrained
        draws=raw ? run.draws : diag.direct_values.direct_draws
        summary=B._mgmfrm_correlated_2d_posterior_summary(result;parameter_space=selected)
        @test getproperty.(summary,:mean)≈vec(mean(draws;dims=1))
        mcse=B._mgmfrm_correlated_2d_posterior_mcse(result;parameter_space=selected,probabilities=(0.1,0.5,0.9))
        reference=B._posterior_mcse_rows(draws[:,end:end],[last(mcse).parameter],run.controls.chains;
            parameter_space=raw ? :fisher_z : :correlation,probabilities=(0.1,0.5,0.9))
        @test isequal(last(mcse),only(reference))
        @test last(mcse).convergence_review_required && !last(mcse).precision_threshold_applied
        for row in mcse
            if row.parameter in result.structurally_fixed_parameters && !raw
                @test row.mcse_status===:structurally_fixed && row.mean_mcse==0
            end
        end
    end
    @test isequal(B._mgmfrm_correlated_2d_posterior_mcse(result),
        B._mgmfrm_correlated_2d_posterior_mcse(result;parameter_space=:direct_constrained))
    path=joinpath(directory,"samples.jls")
    B._save_mgmfrm_correlated_2d_samples(path,result)
    bytes=read(path)
    loaded=B._load_mgmfrm_correlated_2d_samples(path;expected_identity=record.target_identity)
    @test isequal(loaded.record.run,run) && loaded.record.prior==record.prior
    @test isequal(loaded.diagnostics,diag)
    @test isequal(loaded.warmup_diagnostics,result.warmup_diagnostics)
    @test isequal(B._mgmfrm_correlated_2d_posterior_mcse(loaded),B._mgmfrm_correlated_2d_posterior_mcse(result))
    @test_throws ArgumentError B._save_mgmfrm_correlated_2d_samples(path,result)
    @test_throws ArgumentError B._load_mgmfrm_correlated_2d_samples(path;expected_identity="wrong")
    for loader in (B._load_mfrm_fixed_q_samples,B._load_mfrm_correlated_2d_samples,B._load_mgmfrm_normalized_prior_samples)
        @test_throws ArgumentError loader(path;expected_identity=record.target_identity)
    end
    @test_throws ArgumentError load_fit_cache(path)
    @test read(path)==bytes
    bad=merge(result,(;record=merge(record,(;content_hash="wrong"))))
    @test_throws ArgumentError B._save_mgmfrm_correlated_2d_samples(path,bad;overwrite=true)
    @test read(path)==bytes
    fake=merge(result,(;diagnostics=(;flag=:ok),direct_parameter_names=["wrong"],structurally_fixed_parameters=Set([last(result.direct_parameter_names)])))
    @test isequal(B._mgmfrm_correlated_2d_posterior_mcse(fake),B._mgmfrm_correlated_2d_posterior_mcse(result))
    B._save_mgmfrm_correlated_2d_samples(path,fake;overwrite=true)
    @test isequal(B._load_mgmfrm_correlated_2d_samples(path;expected_identity=record.target_identity).diagnostics,diag)
end

@testset "correlated MGMFRM maintained records and precision" begin
    for (K,raters,eta,chains,ndraws) in ((2,1,5,2,20),(4,3,2,2,20),(3,2,1,1,10),(4,3,2,2,4)),backend in (:advancedhmc,:cmdstan)
        t=target(;K,raters,eta);record=synthetic_record(t;backend,chains,ndraws)
        result=restore(record)
        mktempdir() do dir;check_result(result,t,dir);end
        run=record.run
        changed=copy(run.draws);changed[1,end]+=0.5
        stat=copy(run.sampler_stats);stat[1]=merge(stat[1],(;iteration=99))
        spec=deepcopy(record.spec);spec.dimension_labels[1]="changed"
        for bad in (
                merge(record,(;content_hash="wrong")),merge(record,(;extra=true)),merge(record,(;spec)),
                rehash(merge(record,(;schema="bayesianmgmfrm.fixed_q_mfrm_samples.v2"))),
                rehash(merge(record,(;prior=merge(record.prior,(;lkj_eta=eta+1))))),
                rehash(merge(record,(;prior=merge(record.prior,(;lkj_eta=Float64(eta)))))),
                rehash(merge(record,(;prior=merge(record.prior,(;scale_measure=:normalized))))),
                rehash(merge(record,(;prior=merge(record.prior,(;scales=merge(record.prior.scales,(;person_sd=0.8))))))),
                rehash(merge(record,(;run=merge(run,(;draws=changed))))),
                rehash(merge(record,(;run=merge(run,(;sampler_stats=stat))))),
                rehash(merge(record,(;run=merge(run,(;backend=:turing))))),
                rehash(merge(record,(;run=merge(run,(;warmup_stats=[(;chain=1,iteration=1)]))))),
                rehash(merge(record,(;run=Base.structdiff(run,(;warmup_stats=nothing))))))
            @test_throws Union{ArgumentError,B._SamplerError} restore(bad)
        end
        for space in (:unit_logit,:fisher_z,:correlation)
            @test_throws ArgumentError B._mgmfrm_correlated_2d_posterior_mcse(result;parameter_space=space)
        end
        @test_throws ArgumentError B._mgmfrm_correlated_2d_posterior_mcse(result;probabilities=(1.1,))
        @test_throws ArgumentError B.Experimental.fit(t)
    end
    t=target()
    degenerate=restore(synthetic_record(t;z=x->0.7))
    @test last(degenerate.diagnostics.parameter_rows).flag===:degenerate_draws
    @test last(degenerate.diagnostics.direct_parameter_rows).flag===:degenerate_draws
    @test degenerate.diagnostics.raw_metrics.n_degenerate_parameters==1
    @test degenerate.diagnostics.direct_metrics.n_degenerate_parameters==1
    @test last(B._mgmfrm_correlated_2d_posterior_mcse(degenerate)).mcse_status===:degenerate_draws
    @test_throws ArgumentError B._mgmfrm_correlated_2d_sample(t;backend=:julia)
    for backend in (:advancedhmc,:cmdstan)
        @test_throws ArgumentError B._mgmfrm_correlated_2d_sample(t;backend,ndraws=0)
        @test_throws ArgumentError B._mgmfrm_correlated_2d_sample(t,[NaN];backend)
        @test_throws ArgumentError B._mgmfrm_correlated_2d_sample(t,"wrong";backend)
    end
end

@testset "correlated MGMFRM preserves sampling failure context" begin
    t=target();initial=initial_params(t);transitions=Ref(0)
    observer=function(event)
        if event.phase===:transition
            transitions[]+=1
            transitions[]==2 && error("correlated-sampling-test-failure")
        end
    end
    err=try
        B._mgmfrm_correlated_2d_sample(t,initial;ndraws=3,warmup=0,chains=1,
            max_depth=1,seed=92142,_sampling_observer=observer)
        nothing
    catch caught
        caught
    end
    @test err isa B._SamplerError
    @test err.backend===:advancedhmc && err.chain==1 && err.phase===:sampling
    @test err.cause.ex isa ErrorException && err.cause.ex.msg=="correlated-sampling-test-failure"
    @test transitions[]==2 && initial==initial_params(t)
end

function sampling_checks(backend,directory)
    t=target();events=NamedTuple[]
    options=backend===:cmdstan ? (;cmdstan_cache_dir=joinpath(directory,"compile")) :
        (;_sampling_observer=e->push!(events,(;phase=e.phase,chain=e.chain)))
    result=B._mgmfrm_correlated_2d_sample(t;backend,controls...,options...)
    check_result(result,t,directory)
    @test all(r->r.coverage===:recorded && r.observed_iterations==controls.warmup,result.warmup_diagnostics)
    @test result.record.run.controls.rng.seed==controls.seed
    @test size(result.record.run.draws)==(24,B.LogDensityProblems.dimension(t))
    if backend===:advancedhmc
        @test count(e->e.phase===:transition,events)==44
        @test count(e->e.phase===:sampling_start,events)==2
        @test count(e->e.phase===:sampling_end,events)==2
        reference=B._run_generalized_candidate_advancedhmc(t,initial_params(t);controls...,record_warmup=true)
        @test isequal(result.record.run,reference)
        # Rebuild stale numerical views; disable recording without changing draws.
        stale=deepcopy(t);stale.scalar_kernel.observed_category.=0
        unrecorded=B._mgmfrm_correlated_2d_sample(stale;controls...,record_warmup=false)
        @test isequal(unrecorded.record.run.draws,result.record.run.draws)
        @test isequal(unrecorded.record.run.sampler_stats,result.record.run.sampler_stats)
        @test unrecorded.record.run.warmup_stats===nothing
        @test all(r->r.coverage===:not_recorded,unrecorded.warmup_diagnostics)
        @test isequal(restore(unrecorded.record).warmup_diagnostics,unrecorded.warmup_diagnostics)
    else
        @test all(isapprox(s.stan_lp,lp;atol=1e-8,rtol=1e-8) for (s,lp) in
            zip(result.record.run.sampler_stats,result.record.run.logdensities))
        stats=copy(result.record.run.sampler_stats)
        stats[1]=merge(stats[1],(;stan_lp=stats[1].stan_lp+0.1))
        @test_throws ArgumentError restore(rehash(merge(result.record,(;run=merge(result.record.run,(;sampler_stats=stats))))))
    end
    return result
end

@testset "correlated MGMFRM bounded maintained Julia sampling" begin
    directory=get(ENV,"BAYESIANMGMFRM_CORRELATED_SAMPLES_OUTPUT","")
    if isempty(directory)
        mktempdir(dir->sampling_checks(:advancedhmc,dir))
    else
        path=joinpath(directory,"julia");mkpath(path);sampling_checks(:advancedhmc,path)
    end
end

if test_flag("BAYESIANMGMFRM_CMDSTAN_TESTS")
    @testset "correlated MGMFRM bounded maintained CmdStan sampling" begin
        directory=get(ENV,"BAYESIANMGMFRM_CORRELATED_SAMPLES_OUTPUT","")
        if isempty(directory)
            mktempdir(dir->sampling_checks(:cmdstan,dir))
        else
            path=joinpath(directory,"cmdstan");mkpath(path);sampling_checks(:cmdstan,path)
        end
    end
end
end
