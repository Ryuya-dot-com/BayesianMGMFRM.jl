"""Opt-in workflow around the immutable static joint-rating density.

Trusted same-environment sample files; not a public package API or acceptance.
Include joint_rating_static.jl first.
"""
module JointRatingWorkflow
using Random, Statistics, Serialization, SHA, JSON3
import LogDensityProblems as L
import BayesianMGMFRM as B
import ..JointRatingStatic as S

const SCHEMA="bayesianmgmfrm.joint_rating_samples.v1"
const SCOPE=(;samplers=(:advancedhmc,:cmdstan),prediction=:training_rows_existing_effects,
    public_api=false,statistical_acceptance=false)

# Preserve diagnostic NaN/Inf explicitly without producing non-standard JSON.
jsonsafe(x::NamedTuple)=NamedTuple{keys(x)}(map(jsonsafe,values(x)))
jsonsafe(x::Union{Tuple,AbstractArray})=map(jsonsafe,x)
jsonsafe(x::AbstractFloat)=isfinite(x) ? x : (;nonfinite=string(x))
jsonsafe(x)=x
function save_report(path,report)
    ispath(path) && throw(ArgumentError("Preserve existing report: $path"))
    envelope=(;schema="bayesianmgmfrm.joint_rating_report_json.v1",
        encoding="NaN/Inf/-Inf use explicit nonfinite objects; missing is null. Use JLS for lossless replay.",
        data=jsonsafe(report))
    open(path,"w") do io; JSON3.write(io,envelope); end
    return path
end
B._check_source_fixture_raw_vector(t::S.Target,q::AbstractVector)=S.check_vector(t,q)

snapshot(t)=S.restore_target(S.target_record(t);expected_identity=B._cache_hash(S.target_record(t)))

function checked_result(t,run)
    B._check_generalized_sample_run(t,run)
    contract=S.target_record(t)
    body=(;schema=SCHEMA,target=contract,target_identity=B._cache_hash(contract),scope=SCOPE,run)
    result=merge(body,(;content_hash=B._cache_hash(body)))
    restore(result)
    return result
end

"""Run Julia NUTS with explicit sample counts/seed; retains numerical warnings."""
function fit_julia(target::S.Target;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept::Real=.9,max_depth::Int=10,step_size::Real=.03,init_jitter::Real=.1,
        ad_backend::Symbol=:auto,progress::Union{Bool,B.SamplingProgress}=false)
    t=snapshot(target)
    selected=ad_backend===:auto ? :analytic : ad_backend
    run=B._run_generalized_candidate_advancedhmc(t,S.initial(t);
        ndraws,warmup,chains,seed,target_accept,max_depth,step_size,init_jitter,
        ad_backend=selected,progress,record_warmup=true)
    return checked_result(t,run)
end

"""Reuse a successful native finite-check directory after verifying its binary/source hashes."""
function verified_stan(directory::AbstractString)
    info=JSON3.read(read(joinpath(directory,"verification.json"),String))
    info.status=="passed" || throw(ArgumentError("native check did not pass"))
    source=joinpath(@__DIR__,"stan","joint_rating_static.stan")
    source_hash=bytes2hex(sha256(read(source)))
    source_hash==info.stan_source_sha256 || throw(ArgumentError("Stan source changed after native check"))
    path=abspath(joinpath(directory,"joint_rating_static"))
    digest=B._cmdstan_executable_sha256(path,:sampling)
    digest==info.executable_sha256 || throw(ArgumentError("Stan executable changed after native check"))
    return (;path,sha256=digest,source_sha256=source_hash,version=String(info.cmdstan_version))
end

"""Run the matched Stan target; verify every retained density and observation likelihood in Julia."""
function fit_cmdstan(target::S.Target,compiled;ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept::Real=.9,max_depth::Int=10,step_size::Real=.03,init_jitter::Real=.1)
    t=snapshot(target)
    step_size=B._check_fit_controls(ndraws,warmup,chains,step_size)
    target_accept,_,init_jitter=B._check_nuts_controls(target_accept,max_depth,1000.,init_jitter)
    compiled.source_sha256==bytes2hex(sha256(read(joinpath(@__DIR__,"stan","joint_rating_static.stan")))) ||
        throw(ArgumentError("Stan source changed"))
    rng,rng_control=B._fit_rng(MersenneTwister(0),seed)
    initial=S.initial(t)
    parse_chain=(path,chain,count)->begin
        parsed=B._cmdstan_raw_chain_result(path,L.dimension(t),length(t.data.rows),chain,count,
            q->(;pointwise=S.pointwise_loglikelihood(t,q),logposterior=L.logdensity(t,q));
            warmup,parameter_names=["q.$j" for j in 1:L.dimension(t)])
        all(isapprox(stat.stan_lp,lp;atol=1e-8,rtol=1e-8)
            for (stat,lp) in zip(parsed.stats,parsed.logps)) ||
            throw(ArgumentError("retained Stan/Julia normalized density mismatch"))
        parsed
    end
    sampled=B._cmdstan_sample_chains(compiled.path,S.stan_data(t),initial,rng,
        q->L.logdensity(t,q),parse_chain;expected_sha256=compiled.sha256,
        ndraws,warmup,chains,step_size=Float64(step_size),target_accept=Float64(target_accept),
        max_depth,metric="diag_e",init_jitter=Float64(init_jitter),progress=false,
        record_warmup=true,initial_payload=q->(;q))
    controls=(;ndraws,warmup,chains,step_size=Float64(step_size),target_accept=Float64(target_accept),
        max_depth,max_energy_error=1000.,metric=:diagonal,ad_backend=:stan_reverse_mode,
        gradient_backend=:stan_autodiff,rng=merge(rng_control,(;chain_seeds=Tuple(sampled.chain_seeds))),
        init_jitter=Float64(init_jitter),thinning=1,cmdstan_version=compiled.version,
        cmdstan_executable_sha256=compiled.sha256,execution=:cmdstan_cli)
    run=(;checked=B._check_diagnostic_thresholds(1.01,400),nparams=L.dimension(t),initial,
        initial_logdensity=L.logdensity(t,initial),total_draws=ndraws*chains,draws=sampled.draws,
        logdensities=sampled.logdensities,chain_ids=sampled.chain_ids,iterations=sampled.iterations,
        chain_acceptance=sampled.chain_acceptance,sampler_stats=sampled.sampler_stats,controls,
        sampler_rows=B._generalized_candidate_sampler_rows(sampled.logdensities,sampled.iterations,
            sampled.chain_acceptance,sampled.sampler_stats,controls,:cmdstan),
        backend=:cmdstan,sampler=:nuts,split_chains_requested=true,
        actual_split=chains>=2 && ndraws>=4,warmup_stats=sampled.warmup_stats)
    return checked_result(t,run)
end

"""Validate a saved record, including target reconstruction and every retained log density."""
function restore(record)
    record isa NamedTuple && keys(record)==(:schema,:target,:target_identity,:scope,:run,:content_hash) &&
        record.schema==SCHEMA && record.scope==SCOPE || throw(ArgumentError("unsupported joint sample record"))
    B._cache_hash(Base.structdiff(record,(;content_hash=nothing)))==record.content_hash ||
        throw(ArgumentError("joint sample checksum mismatch"))
    t=S.restore_target(record.target;expected_identity=record.target_identity)
    B._check_generalized_sample_run(t,record.run)
    run=record.run;stats=get(run,:warmup_stats,nothing)
    stats isa AbstractVector && length(stats)==run.controls.chains*run.controls.warmup ||
        throw(ArgumentError("complete recorded warmup is required"))
    B._warmup_diagnostic_rows(stats,run.controls,run.backend)
    return t
end

function save_result(path,record)
    restore(record)
    return B._save_serialized_record(path,record;overwrite=false)
end
function load_result(path)
    record=open(deserialize,path) # Trusted same-environment Julia files only.
    restore(record)
    return record
end

function model_draws(t,draws)
    P,T,R,O,K,G,F=t.sizes;lv=t.levels
    names=[["theta[$(repr(p)),$(repr(c))]" for p in lv.person for c in lv.criterion];
        ["task[$(repr(task)),$(repr(c))]" for task in lv.task for c in lv.criterion];
        ["rater[$(repr(r)),$(repr(c))]" for c in lv.criterion for r in lv.rater];
        ["step[$k,$(repr(g))]" for g in lv.threshold_group for k in 1:K-1];
        ["response[$(repr(o)),$(repr(c))]" for o in lv.response_id for c in lv.criterion];
        ["beta[$(repr(string(n)))]" for n in t.predictor_names];
        ["response_sd[$(repr(c))]" for c in lv.criterion];"rho_person";"rho_response"]
    values=reduce(vcat,[begin
        v=S.coordinates(t,q)
        permutedims([vec(v.theta);vec(v.task);vec(v.rater);vec(v.steps);vec(v.response);
            v.beta;v.response_sd;v.person_correlation;v.response_correlation])
    end for q in eachrow(draws)])
    fixed=K==2 ? Set(["step[1,$(repr(g))]" for g in lv.threshold_group]) : Set{String}()
    positive=Set(["response_sd[$(repr(c))]" for c in lv.criterion])
    return (;names,values,fixed,positive)
end

# Callers validate the complete source with restore before using this helper.
function _source_diagnostics(t,run,m=model_draws(t,run.draws))
    raw_names=["$name[$j]" for (name,block) in pairs(t.blocks) for j in eachindex(block)]
    diagnose(values,names;fixed=Set{String}(),space=:model)=B._candidate_mcmc_diagnostic_rows(
        values,names,run.controls.chains;parameter_space=space,structurally_fixed_parameters=fixed,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,
        ess_threshold=run.checked.ess_threshold)
    return (;status=:engineering_only,controls=run.controls,
        raw_diagnostics=diagnose(run.draws,raw_names;space=:white_log_sd_fisher_z),
        model_diagnostics=diagnose(m.values,m.names;fixed=m.fixed),
        sampler=run.sampler_rows,warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend))
end

"""
    report(record; lower=.05, upper=.95, intervals=(.9,))

Equal-tailed parameter intervals, raw/model diagnostics, MCSE and sampler/warmup
warnings. For 99% use lower=.005, upper=.995, intervals=(.99,). These intervals
are not HDIs, and short-chain endpoint precision is not guaranteed.
"""
function report(record;lower=.05,upper=.95,intervals=(.9,))
    t=restore(record);run=record.run;m=model_draws(t,run.draws)
    diagnostics=_source_diagnostics(t,run,m)
    posterior=B._posterior_summary_rows(m.values,m.names;lower,upper,intervals,
        reference=0.,rope=nothing,rope_probability_threshold=.95)
    posterior=[row.parameter in m.positive ? merge(row,(;reference=missing,
        probability_positive=missing,probability_negative=missing,probability_equal=missing,
        probability_of_direction=missing,direction=:not_applicable_positive_scale)) : row for row in posterior]
    probabilities=Tuple(sort(unique([Float64(lower),.5,Float64(upper),
        [p for mass in B._posterior_interval_probabilities(intervals)
            for p in ((1-mass)/2,(1+mass)/2)]...])))
    return (;target_identity=record.target_identity,source_sample_content_hash=record.content_hash,
        status=diagnostics.status,scope=SCOPE,backend=run.backend,controls=diagnostics.controls,
        prior=t.prior,criteria=copy(t.data.criteria),interval_method=:equal_tailed,
        interval_controls=(;lower,upper,intervals),posterior,
        raw_diagnostics=diagnostics.raw_diagnostics,
        model_diagnostics=diagnostics.model_diagnostics,
        mcse=B._posterior_mcse_rows(m.values,m.names,run.controls.chains;
            probabilities,parameter_space=:model,structurally_fixed_parameters=m.fixed),
        sampler=diagnostics.sampler,warmup=diagnostics.warmup,
        scale_evidence=:positive_support_is_not_evidence_against_zero)
end

"""
    conditional_prediction(record)

Posterior mean probabilities for original training rows, conditional on existing
effects and observed data. No new-level integration or heldout-performance claim.
Uses O(N*K) output storage, not a full draw-by-row-by-category array.
"""
function conditional_prediction(record)
    t=restore(record);quality=report(record)
    probs=zeros(length(t.data.rows),t.sizes[5])
    for q in eachrow(record.run.draws);probs.+=exp.(S.category_logprobs(t,q));end
    probs./=size(record.run.draws,1)
    labels=[(;criterion=c.criterion,raw_categories=c.direction==:higher_is_more ?
        copy(c.levels) : reverse(c.levels)) for c in t.data.criteria]
    return (;target_identity=record.target_identity,source_sample_content_hash=record.content_hash,
        conditioning=:observed_training_data_and_existing_effects,scope=SCOPE,new_levels=false,
        observation_ids=copy(t.data.observation_ids),response_ids=copy(t.data.response_ids),
        rating_event_ids=copy(t.data.rating_event_ids),criteria=getproperty.(t.data.rows,:criterion),
        canonical_categories=collect(0:t.sizes[5]-1),category_labels=labels,probabilities=probs,
        parameter_chain_ids=copy(record.run.chain_ids),parameter_iterations=copy(record.run.iterations),
        mcse_status=:prediction_mcse_not_computed,
        sampling_quality=(;quality.status,quality.backend,quality.controls,quality.raw_diagnostics,
            quality.model_diagnostics,quality.sampler,quality.warmup),
        marginal_warning="Products of marginal row probabilities are not joint predictive probabilities.")
end
end
