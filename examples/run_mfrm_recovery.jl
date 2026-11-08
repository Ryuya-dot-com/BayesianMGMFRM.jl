module MFRMRecoveryRun

using BayesianMGMFRM, Random, Serialization
const B = BayesianMGMFRM
const P = B.Experimental.RecoveryPlanning
const STAGES = (:generation, :fit, :recovery)

function save_new(path, value)
    (ispath(path) || islink(path)) && throw(ArgumentError("refusing to overwrite $path"))
    serialize(path, value)
    isequal(deserialize(path), value) || error("saved value differs: $path")
    path
end

fit_keywords(plan, job) = (;(k=>v for (k,v) in pairs(plan.sampler)
    if !(k in (:algorithm, :gradient_backend)))...,
    seed=job.fit_seed, init=zeros(length(plan.free_names)), progress=false)

study_prior(study) = MFRMPrior(; (k=>getproperty(study.generating_prior,k)
    for k in (:person_sd,:rater_sd,:item_sd,:step_sd))...)

function saved_dataset_plan(study, dataset_id, generation_path)
    path = joinpath(dirname(generation_path),"dataset-plan.jls")
    isfile(path) || throw(ArgumentError("keep dataset-plan.jls beside the SBC generation artifact"))
    plan = deserialize(path)
    truth = Dict(plan.truth)
    job = only(filter(j->j.dataset_id==dataset_id,study.jobs))
    expected = P.bind_prior_draw(study,dataset_id,
        Dict(n=>truth[n] for n in study.template.free_names);
        generating_prior=study_prior(study),parameter_seed=job.parameter_seed)
    isequal(plan,expected) || throw(ArgumentError("saved dataset plan differs from its SBC study"))
    plan
end

"""
    run_job(plan, ledger, dataset_id; output_dir, through, posterior_dependence=nothing)

Explicitly execute one fixed-truth or joint-prior SBC scalar PCM job through
`:generation`, `:fit` or `:recovery`. This can draw prior parameters, generate
random responses and run MCMC. Including the example does nothing. Inspect
`RecoveryPlanning.review(plan, ledger)` first. For SBC supply the parent study
and its full ledger, with rank_settings declared before generation. Supply
`posterior_dependence=(status=:unresolved, evidence="...")` or an explicit
supported assessment when requesting pending SBC recovery. No independence
assessment is inferred from convergence or thinning.

Use a new output directory, a trusted ledger and the original compatible Julia
environment. Completed stages are checked and reused; started, failed or damaged
stages stop before execution. No retries, redraws, chain continuation or parallel
writers are provided. Supply the latest saved ledger and another new directory
to continue from a completed stage boundary. Keep every directory it references.

Save the full plan and ledger before work, each stage's started/terminal ledger,
actual responses before validation, artifacts, stage wall time/bytes and a final
`outcome.jls`. Stage costs include stage work and artifact saving, not setup,
ledger persistence, CPU time or peak memory. Failures are recorded and rethrown;
if storage itself fails, retain the last readable ledger and any partial files.
An unresolved started stage requires inspection and is never silently rerun.

Return the final ledger, costs and saved outcome path. If the requested stages
are already complete, return `:already_completed` without writing any files.
This runner does not rank designs, aggregate datasets or attest provenance.
Preserve the plan's Project/Manifest and Julia version with the output.

Generation uses Random.MersenneTwister and requires that RNG declaration in the
plan. SBC saves prior-input.jls, prior-draw.jls and dataset-plan.jls before drawing
responses. generation.jls contains bound observations, as required by the saved
summary API. Keep dataset-plan.jls beside it for continuation; the full bound
plan is checked against the parent study and observations before fitting.
The SBC recovery artifact is review_sbc_fit's rank record, including exclusions.
summarize_sbc accepts the resulting parent ledger. One executed job, or an
artificial fixed-value check, cannot establish SBC calibration.
"""
function run_job(plan, record, dataset_id; output_dir::AbstractString, through::Symbol,
        posterior_dependence=nothing)
    inventory = P.review(plan, record)
    sbc = get(plan, :schema, nothing) == P.SBC_PLAN
    if sbc
        hasproperty(plan,:rank_settings) || throw(ArgumentError("declare SBC rank_settings before generation"))
    else
        !hasproperty(plan,:sbc_binding) || throw(ArgumentError("supply the parent SBC study and ledger"))
        posterior_dependence === nothing || throw(ArgumentError("posterior_dependence applies only to SBC"))
    end
    last_stage = findfirst(==(through), STAGES)
    last_stage === nothing && throw(ArgumentError("through must be generation, fit or recovery"))
    index = findfirst(r -> r.dataset_id == dataset_id, inventory.rows)
    index === nothing && throw(ArgumentError("unplanned dataset ID"))
    entry = inventory.rows[index]
    entry.outcome in (:no_attempt_recorded, :partial_completed, :recorded_completed) ||
        throw(ArgumentError("inspect the existing job before execution: $(entry.outcome)"))
    selected = STAGES[1:last_stage]
    pending = filter(k -> getproperty(entry.stages,k).status !== :completed, selected)
    isempty(pending) && return (;status=:already_completed, ledger=record, costs=(), outcome_path=nothing)
    all(k -> getproperty(entry.stages,k).status === :not_started, pending) ||
        throw(ArgumentError("only unstarted stages can execute"))
    if sbc && :recovery in pending
        P.checkdependence(posterior_dependence)
    end
    template = sbc ? plan.template : plan
    if :generation in pending
        template.provenance.rng_algorithm == "Random.MersenneTwister" ||
            throw(ArgumentError("generation requires the Random.MersenneTwister declaration"))
    end
    out = abspath(output_dir)
    isdir(dirname(out)) || throw(ArgumentError("create the output parent directory first"))
    # Atomic directory creation prevents accidental reuse, including interrupted work.
    mkdir(out)
    save_new(joinpath(out,"plan.jls"),plan)
    save_new(joinpath(out,"ledger-00.jls"),record)
    save_new(joinpath(out,"runtime.jls"),(;julia_version=string(VERSION),
        julia_threads=Threads.nthreads(),package_version=string(pkgversion(B)),
        source_path=pkgdir(B),project=Base.active_project(),
        execution_provenance_verified=false))
    sequence = 0
    function checkpoint(stage, status; kwargs...)
        next = P.record_stage(plan,record,dataset_id;stage,status,kwargs...)
        sequence += 1
        save_new(joinpath(out,"ledger-$(lpad(sequence,2,'0')).jls"),next)
        record = next
    end
    job = plan.jobs[index]
    costs = NamedTuple[]
    stage = first(pending)
    kind = :persistence
    started = time_ns()
    outcome_path = joinpath(out,"outcome.jls")
    try
        for current in pending
            stage = current
            kind = :persistence
            checkpoint(stage,:started)
            started = time_ns()
            artifact = joinpath(out,"$(stage).jls")
            kind = :validation
            if stage === :generation
                dataset_plan = plan
                if sbc
                    recipe = P.prior_input(plan,dataset_id)
                    kind = :persistence
                    save_new(joinpath(out,"prior-input.jls"),recipe)
                    kind = :computation
                    rng = MersenneTwister(job.parameter_seed)
                    values = Dict(c.parameter=>c.mean+c.sd*randn(rng) for c in recipe.coordinates)
                    kind = :persistence
                    save_new(joinpath(out,"prior-draw.jls"),values)
                    kind = :validation
                    dataset_plan = P.bind_prior_draw(plan,dataset_id,values;
                        generating_prior=study_prior(plan),parameter_seed=job.parameter_seed)
                    kind = :persistence
                    save_new(joinpath(out,"dataset-plan.jls"),dataset_plan)
                end
                kind = :validation
                input = P.generator_input(dataset_plan,dataset_id)
                kind = :computation
                table = simulate_responses(input.design,input.direct_truth;
                    rng=MersenneTwister(job.response_seed),output=:table)
                kind = :persistence
                save_new(joinpath(out,"generated-table.jls"),table)
                kind = :validation
                observed = P.bind_observations(dataset_plan,dataset_id,table)
                kind = :persistence
                save_new(artifact,observed)
            else
                stages = record.entries[index].stages
                observed = deserialize(stages.generation.artifact.path)
                observed.dataset_id == dataset_id || throw(ArgumentError("observations belong to another dataset"))
                dataset_plan = sbc ? saved_dataset_plan(plan,dataset_id,stages.generation.artifact.path) : plan
                table = P.observation_table(dataset_plan,observed)
                if stage === :fit
                    bound = P.bind_data(dataset_plan,dataset_id,table)
                    kind = :computation
                    fitted = fit(bound.design;prior=bound.prior,fit_keywords(dataset_plan,job)...)
                    kind = :persistence
                    save_fit_cache(artifact,fitted)
                else
                    cache = stages.fit.artifact
                    kind = :computation
                    checked = sbc ? P.review_sbc_fit(plan,dataset_plan,observed,cache.path;
                        cache_sha256=cache.sha256,posterior_dependence) :
                        P.review_fit(plan,observed,cache.path;cache_sha256=cache.sha256)
                    kind = :persistence
                    save_new(artifact,checked)
                end
            end
            cost = (;stage,status=:completed,seconds=(time_ns()-started)/1e9,
                artifact_bytes=filesize(artifact))
            kind = :persistence
            checkpoint(stage,:completed;artifact)
            push!(costs,cost)
            save_new(joinpath(out,"$(stage)-cost.jls"),cost)
        end
        result = (;status=:completed,through,dataset_id,plan_hash=plan.content_hash,
            ledger=record,costs=Tuple(costs),outcome_path)
        save_new(outcome_path,result)
        result
    catch err
        reason = sprint(showerror,err)
        # A usable completed artifact remains completed even if later bookkeeping fails.
        if getproperty(record.entries[index].stages,stage).status === :started
            try
                checkpoint(stage,:failed;failure_kind=kind,reason)
            catch persistence_error
                @warn "Could not save failure ledger; inspect the last readable checkpoint" exception=persistence_error
            end
        end
        try
            save_new(outcome_path,(;status=:failed,through,dataset_id,
                plan_hash=plan.content_hash,stage,failure_kind=kind,reason,
                seconds_since_stage_start=(time_ns()-started)/1e9,
                ledger=record,completed_costs=Tuple(costs)))
        catch persistence_error
            @warn "Could not save failure outcome; retain partial files" exception=persistence_error
        end
        rethrow()
    end
end

end
