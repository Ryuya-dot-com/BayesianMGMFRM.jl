"""Opt-in Julia sampling/replication for the shared-task density prototype.

Include four_facet_shared_target.jl first. Records are trusted, same-environment
Julia files, separate from public fit types and the common comparison adapter.
"""
module FourFacetSharedWorkflow
using Random, Statistics, Serialization
import LogDensityProblems as L
import BayesianMGMFRM as B
import ..FourFacetSharedTarget as F
export prior_draws, replicate, fit_julia, restore, save_result, load_result,
       report, conditional_prediction
const SCHEMA = "bayesianmgmfrm.four_facet_shared_task_samples.prototype.v1"

function prior_draws(rng::AbstractRNG, target::F.SharedTaskTarget, count::Integer)
    count isa Bool && throw(ArgumentError("draw count must be a positive integer"))
    count > 0 || throw(ArgumentError("draw count must be positive"))
    F.target_record(target)
    b,p = target.blocks,target.prior
    draws = zeros(count,L.dimension(target))
    for (block,sd) in ((b.theta,p.person_sd),(b.task,p.task_kernel_sd),
            (b.rater,p.rater_kernel_sd),(b.criterion,p.criterion_kernel_sd),
            (b.steps,p.step_kernel_sd),(b.z,1.))
        draws[:,block] .= sd .* randn(rng,count,length(block))
    end
    for row in 1:count
        z = abs(randn(rng))
        z > 0 || throw(ArgumentError("RNG returned exactly zero for a positive scale"))
        draws[row,end] = log(p.shared_sd_scale)+log(z)
    end
    all(isfinite,draws) || throw(ArgumentError("prior draws exceed the numeric range"))
    return draws
end

"""One replicate of the original rows, conditional on ONE joint parameter draw."""
function replicate(rng::AbstractRNG, target::F.SharedTaskTarget, x::AbstractVector)
    probabilities = exp.(F.category_logprobs(target,x))
    indices = Vector{Int}(undef,target.input_spec.data.n)
    for n in eachindex(indices)
        u = rand(rng)
        cumulative = 0.
        indices[n] = size(probabilities,2) # Roundoff at the upper CDF endpoint.
        for k in axes(probabilities,2)
            cumulative += probabilities[n,k]
            if u < cumulative
                indices[n] = k
                break
            end
        end
    end
    return (;category_index=indices,score=target.input_spec.data.category_levels[indices])
end

# Reuse the maintained sampler/run validator without inventing a legacy blueprint.
B._check_source_fixture_raw_vector(t::F.SharedTaskTarget,x::AbstractVector) = F._check(t,x)

function fit_julia(target::F.SharedTaskTarget; ndraws::Int,warmup::Int,chains::Int,seed,
        target_accept::Real=.9,max_depth::Int=10,step_size::Real=.03,init_jitter::Real=.1)
    contract = F.target_record(target)
    identity = B._cache_hash(contract)
    t = F.restore_target(contract;expected_identity=identity)
    initial = zeros(L.dimension(t))
    initial[end] = log(t.prior.shared_sd_scale)
    run = B._run_generalized_candidate_advancedhmc(t,initial;
        ndraws,warmup,chains,seed,target_accept,max_depth,step_size,init_jitter,
        ad_backend=:ForwardDiff,record_warmup=true)
    B._check_generalized_sample_run(t,run)
    record = (;schema=SCHEMA,target=contract,target_identity=identity,run)
    return merge(record,(;content_hash=B._cache_hash(record)))
end

function restore(record::NamedTuple)
    keys(record) == (:schema,:target,:target_identity,:run,:content_hash) && record.schema == SCHEMA ||
        throw(ArgumentError("unsupported shared-task sample record"))
    B._cache_hash(Base.structdiff(record,(;content_hash=nothing))) == record.content_hash ||
        throw(ArgumentError("shared-task sample checksum mismatch"))
    t = F.restore_target(record.target;expected_identity=record.target_identity)
    record.run.backend === :advancedhmc || throw(ArgumentError("only the Julia sampler is connected"))
    B._check_generalized_sample_run(t,record.run)
    return t
end

function save_result(path,record)
    restore(record)
    return B._save_serialized_record(path,record;overwrite=false)
end
function load_result(path)
    record = open(deserialize,path) # Trusted local files only.
    record isa NamedTuple || throw(ArgumentError("invalid shared-task sample record"))
    restore(record)
    return record
end

function report(record)
    t = restore(record)
    run = record.run
    P,T,R,C,K = t.sizes
    names = [["theta[$d,$p]" for p in 1:P for d in 1:2];
        ["task[$i]" for i in 1:T];["rater[$i]" for i in 1:R];
        ["criterion[$i]" for i in 1:C];["step[$k,$c]" for c in 1:C for k in 1:K-1];
        ["shared[$p,$a]" for p in 1:P for a in 1:T];"shared_sd"]
    draws = reduce(vcat,[begin
        v = F._components(t,x)
        permutedims([vec(v.theta);v.task;v.rater;v.criterion;vec(v.steps);v.shared;v.sigma])
    end for x in eachrow(run.draws)])
    fixed = K == 2 ? Set(["step[1,$c]" for c in 1:C]) : Set{String}()
    raw_names = ["$(name)[$j]" for (name,block) in pairs(t.blocks) for j in eachindex(block)]
    diagnose(values,labels;fixed=Set{String}(),space=:model) = B._candidate_mcmc_diagnostic_rows(
        values,labels,run.controls.chains;parameter_space=space,structurally_fixed_parameters=fixed,
        split_chains=run.split_chains_requested,rhat_threshold=run.checked.rhat_threshold,
        ess_threshold=run.checked.ess_threshold)
    posterior = B._posterior_summary_rows(draws,names;lower=.025,upper=.975,
        intervals=(.66,.9,.95),reference=0.,rope=nothing,rope_probability_threshold=.95)
    # A positive-support scale cannot supply evidence merely by exceeding zero.
    posterior = [row.parameter == "shared_sd" ? merge(row,(;reference=missing,
        probability_positive=missing,probability_negative=missing,probability_equal=missing,
        probability_of_direction=missing,direction=:not_applicable_positive_scale)) : row for row in posterior]
    return (;target_identity=record.target_identity,backend=run.backend,controls=run.controls,
        status=:engineering_only,statistical_acceptance=false,
        scale_evidence=:requires_practical_width_or_fixed_null_comparison,posterior,
        raw_diagnostics=diagnose(run.draws,raw_names;space=:orthonormal_noncentered_log_sd),
        model_diagnostics=diagnose(draws,names;fixed),
        mcse=B._posterior_mcse_rows(draws,names,run.controls.chains;
            parameter_space=:model,structurally_fixed_parameters=fixed),
        sampler=run.sampler_rows,
        warmup=B._warmup_diagnostic_rows(run.warmup_stats,run.controls,run.backend))
end

"""Posterior mean category probabilities for original rows and existing effects only."""
function conditional_prediction(record)
    t = restore(record)
    mean_probs = zeros(t.input_spec.data.n,t.sizes[5])
    for x in eachrow(record.run.draws)
        mean_probs .+= exp.(F.category_logprobs(t,x))
    end
    mean_probs ./= size(record.run.draws,1)
    return (;target_identity=record.target_identity,input_identity=record.target.input_identity,
        observation_id=collect(1:t.input_spec.data.n),category_levels=copy(t.input_spec.data.category_levels),
        conditioning=:existing_person_task_rater_criterion,integrated_over=:posterior_existing_effects,
        new_levels=false,probabilities=mean_probs,mcse_status=:not_computed)
end
end
