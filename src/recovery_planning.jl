"""
    BayesianMGMFRM.Experimental.RecoveryPlanning

Prepare score-free scalar MFRM/PCM studies and review their saved
outcomes. Start with `prepare`, then `generator_input`, `bind_observations`,
`bind_data` and `review_fit`. Use `ledger`, `record_stage` and `review` to retain
the full roster, including failures and unfinished work. These operations never
generate responses, fit models, retry work or overwrite saved results.
Use `summarize_recovery` to aggregate saved fixed-truth reviews with that roster.
Read `contract()` for the supported model and persistence boundaries.
For joint-prior SBC input preparation, use `prepare_sbc`, `prior_input` and
`bind_prior_draw`, then `review_sbc_fit` and `summarize_sbc` for saved outcomes. These do not run SBC
experiments or establish posterior calibration.
"""
module RecoveryPlanning

using BayesianMGMFRM, LinearAlgebra, SHA
using Serialization: deserialize
const B = BayesianMGMFRM
const PLAN = "example.mfrm_recovery_plan.v2"
const SBC_PLAN = "bayesianmgmfrm.mfrm_sbc_plan.v1"
const LEDGER = "example.mfrm_recovery_ledger.v1"
const STAGES = (:generation, :fit, :recovery)
require(ok, message) = ok || throw(ArgumentError(message))
checkplan(plan) = B._prediction_check_seal(plan, PLAN)
function checksbc(plan)
    B._prediction_check_seal(plan, SBC_PLAN)
    checkplan(plan.template)
end
checkstudy(plan) = get(plan, :schema, nothing) == SBC_PLAN ? checksbc(plan) : checkplan(plan)
filehash(path) = open(sha256, path) |> bytes2hex


"""
    contract()

Return the supported model, fixed-truth saved-study aggregation, SBC input/rank
review and saved-record boundary, including a conditional full-roster SBC screen.
Legacy `example.*` schema names are retained so existing v2 plans and v1
observation/review/ledger records remain readable without relabelling them.
A matching seal proves content integrity, not generating provenance or
statistical validity. Native caches require their original compatible environment.
"""
contract() = (; stability=:experimental, model=:scalar_unit_logit_reference_pcm,
    dimensions=1, item_slopes=:fixed_one, rater_consistency=:fixed_one,
    threshold_owner=:item, analysis_prior=:MFRMPrior, categories=:consecutive_integers,
    reference_levels=:first_canonical_rater_and_item, response_ids=:metadata_only,
    mode=:fixed_truth, intervals=:central_equal_tailed, sbc=false, assurance=false,
    sbc_input_preparation=true, sbc_plan_schema=SBC_PLAN,
    sbc_saved_rank_review=true, sbc_study_summary=true, automatic_tie_randomization=false,
    automatic_generation=false, automatic_fitting=false, automatic_retry=false,
    persistence=:julia_serialization_same_environment_single_writer,
    interrupted_chain_resume=false, artifact_paths=:absolute,
    verified_ledger_relocation=true, fixed_truth_study_summary=true,
    plan_schema=PLAN, ledger_schema=LEDGER)

"""
    prepare(assignments; levels, category_levels, truth, jobs, prior,
            parameters, interval, sampler, provenance, precision, response_ids=nothing)

Prepare one fixed-truth scalar, unit-slope, item-step PCM scenario without scores,
random generation or fitting. `assignments` contains exactly person/rater/item
string labels; `levels` explicitly declares those three sets. Canonical package
ordering determines the zero-reference rater/item. All declared levels must occur.
`truth` supplies every person/rater/item and all K-1 steps per item, including the
two zero references and final centered steps. Focal `parameters` must be free.
Optional ordered `response_ids` preserve shared-response grouping metadata;
they add no fitted facet or dependence effect. Each ID must identify one person/item.

Each job has dataset_id, response_seed and fit_seed. Distinct nonnegative seeds
are required across this independent-stream plan; they do not prove
independence. `sampler` records explicit settings; preparation performs no estimation.
`provenance` binds source/Project/Manifest SHA-256 and Julia/RNG versions supplied
by the caller; it does not attest that a generator used them. The separate
analysis `prior` must be MFRMPrior. `precision` maps every focal name to positive
absolute mean_mcse_max/endpoint_mcse_max limits on that coordinate's scale.
These declared limits are applied by review_fit, not calibrated accuracy guarantees.

Use through `BayesianMGMFRM.Experimental.RecoveryPlanning`. This is a
fixed-truth workflow, not joint-prior SBC, assurance or an execution scheduler.
"""
function prepare(assignments; levels, category_levels, truth, jobs,
        prior::MFRMPrior, parameters, interval, sampler::NamedTuple, provenance::NamedTuple, precision,
        response_ids=nothing)
    require(Set(keys(levels)) == Set((:person,:rater,:item)), "declare person/rater/item levels")
    canonical = map((:person,:rater,:item)) do role
        v = collect(getproperty(levels,role))
        require(!isempty(v) && all(x -> x isa AbstractString && !isempty(strip(x)),v) &&
            length(unique(v)) == length(v), "levels must be unique nonempty strings")
        Tuple(String.(B._stable_levels(v,role)))
    end
    lev = NamedTuple{(:person,:rater,:item)}(canonical)
    rows = Tuple(map(collect(assignments)) do r
        require(Set(keys(r)) == Set((:person,:rater,:item)), "allocation rows have no score or extra roles")
        require(all(k -> getproperty(r,k) in getproperty(lev,k),keys(lev)), "unknown allocation level")
        (;person=String(r.person),rater=String(r.rater),item=String(r.item))
    end)
    require(!isempty(rows) && length(unique(rows)) == length(rows), "allocation must be nonempty without repeated cells")
    responses = response_ids === nothing ? nothing : Tuple(response_ids)
    if responses !== nothing
        require(length(responses) == length(rows) && all(x ->
            (x isa AbstractString && !isempty(strip(x))) || (x isa Integer && !(x isa Bool)),responses),
            "response IDs must be ordered nonempty strings or integers, one per row")
        for id in unique(responses)
            require(length(unique((rows[i].person,rows[i].item) for i in eachindex(rows) if responses[i] == id)) == 1,
                "a response ID spans different person/item pairs")
        end
    end
    for role in keys(lev)
        require(Set(getproperty.(rows,role)) == Set(getproperty(lev,role)), "unobserved declared level: $role")
    end
    categories = Tuple(B._normalize_category_levels(category_levels))
    persons,raters,items = lev.person,lev.rater,lev.item
    locations = (Tuple("person[$p]" for p in persons)...,
        Tuple("rater[$r]" for r in raters[2:end])...,Tuple("item[$i]" for i in items[2:end])...)
    index = Dict(n=>j for (j,n) in enumerate(locations))
    # This bounded score-free adapter duplicates only the stable location matrix;
    # it is checked against getdesign after actual scores become available.
    X = zeros(length(rows),length(locations))
    for (j,r) in enumerate(rows), (name,value) in
            (("person[$(r.person)]",1), ("rater[$(r.rater)]",-1), ("item[$(r.item)]",-1))
        haskey(index,name) && (X[j,index[name]]=value)
    end
    location_rank = rank(X)
    require(location_rank == length(locations), "rank-deficient planned location design: $location_rank/$(length(locations))")
    free_names = (locations...,Tuple("step[item=$i,$k]" for i in items for k in 1:length(categories)-2)...)
    all_names = (locations...,"rater[$(first(raters))]","item[$(first(items))]",
        Tuple("step[item=$i,$k]" for i in items for k in 1:length(categories)-1)...)
    require(Set(keys(truth)) == Set(all_names), "truth must contain exactly every model coordinate")
    require(all(x -> x isa Real && !(x isa Bool) && isfinite(Float64(x)),values(truth)), "truth must be finite real values")
    values_by_name = Dict(String(k)=>Float64(v) for (k,v) in truth)
    require(values_by_name["rater[$(first(raters))]"] == values_by_name["item[$(first(items))]"] == 0,
        "reference rater/item truths must be zero")
    require(all(i -> abs(sum(values_by_name["step[item=$i,$k]"] for k in 1:length(categories)-1)) <= 1e-12,items),
        "each item's full steps must sum to zero")
    focal = Tuple(parameters)
    require(!isempty(focal) && length(unique(focal)) == length(focal) && all(in(free_names),focal),
        "focal quantities must be unique free model-coordinate names")
    B._interval_probabilities(interval)
    roster = Tuple(jobs)
    require(!isempty(roster), "declare the full dataset roster")
    for j in roster
        require(keys(j) == (:dataset_id,:response_seed,:fit_seed), "job needs dataset_id/response_seed/fit_seed")
        require(j.dataset_id isa AbstractString && !isempty(strip(j.dataset_id)), "empty dataset ID")
        require(all(x -> x isa Integer && !(x isa Bool) && 0 <= x <= typemax(Int), (j.response_seed,j.fit_seed)), "invalid seed")
    end
    require(length(unique(j.dataset_id for j in roster)) == length(roster), "duplicate dataset ID")
    seeds = [s for j in roster for s in (j.response_seed,j.fit_seed)]
    require(length(unique(seeds)) == length(seeds), "reused seed in independent-stream plan")
    require(haskey(sampler,:backend) && sampler.backend in (:julia,:advancedhmc), "supported Julia backend required")
    control_names = sampler.backend === :julia ?
        (:ndraws,:warmup,:chains,:step_size,:init_jitter) :
        (:ndraws,:warmup,:chains,:step_size,:init_jitter,:target_accept,:max_depth,
         :max_energy_error,:metric,:ad_backend,:gradient_backend)
    require(Set(keys(sampler)) == Set((:backend,:algorithm,control_names...)), "declare all recorded sampler controls")
    require(sampler.algorithm === (sampler.backend === :julia ? :random_walk_metropolis : :nuts), "algorithm/backend mismatch")
    finitepositive(x) = x isa Real && !(x isa Bool) && isfinite(x) && x > 0
    require(finitepositive(sampler.step_size), "positive finite step size required")
    require(sampler.init_jitter isa Real && !(sampler.init_jitter isa Bool) && isfinite(sampler.init_jitter) && sampler.init_jitter >= 0,
        "finite nonnegative init jitter required")
    if sampler.backend === :julia
        require(sampler.init_jitter == 0, "random-walk implementation records zero init jitter")
    else
        require(finitepositive(sampler.target_accept) && sampler.target_accept < 1 && finitepositive(sampler.max_energy_error), "invalid NUTS controls")
        require(sampler.max_depth isa Integer && !(sampler.max_depth isa Bool) && sampler.max_depth > 0, "invalid maximum depth")
        require(sampler.metric in (:diagonal,:unit,:dense) && sampler.ad_backend === :ForwardDiff && sampler.gradient_backend === :ad,
            "this workflow uses the existing ForwardDiff NUTS contract")
    end
    require(Set(keys(precision)) == Set(focal), "declare precision for every focal quantity")
    for limits in values(precision)
        require(limits isa NamedTuple && keys(limits) == (:mean_mcse_max,:endpoint_mcse_max) &&
            all(finitepositive,values(limits)), "precision limits must be positive finite absolute bounds")
    end
    require(all(k -> getproperty(sampler,k) isa Integer && !(getproperty(sampler,k) isa Bool) &&
        getproperty(sampler,k) > 0,(:ndraws,:warmup,:chains)), "sampler counts must be positive integers")
    for key in (:source_sha256,:project_sha256,:manifest_sha256)
        require(haskey(provenance,key) && getproperty(provenance,key) isa String &&
            occursin(r"^[0-9a-f]{64}$",getproperty(provenance,key)), "record $key")
    end
    require(all(k -> haskey(provenance,k) && getproperty(provenance,k) isa String &&
        !isempty(strip(getproperty(provenance,k))),(:julia_version,:rng_algorithm)), "record Julia/RNG version")
    B._prediction_seal((;schema=PLAN,model=:scalar_unit_logit_reference_pcm,
        assignments=rows,response_ids=responses,levels=lev,category_levels=categories,free_names,
        truth=Tuple(k=>values_by_name[k] for k in sort(collect(keys(values_by_name)))),
        analysis_prior=B._prior_cache_record(prior),parameters=focal,interval=Float64(interval),
        jobs=deepcopy(roster),sampler=deepcopy(sampler),provenance=deepcopy(provenance),
        location_rank,precision=Tuple(n=>precision[n] for n in focal),
        precision_applied=false,generation_verified=false))
end

"""
    prepare_sbc(assignments; levels, category_levels, jobs, prior,
                generating_prior=prior, parameters, interval, sampler,
                provenance, precision, response_ids=nothing, rank_settings=nothing)

Prepare joint-prior SBC inputs for the same scalar unit-slope, item-step PCM as
`prepare`, without drawing parameters, responses or posterior samples. Each job
must contain dataset_id, parameter_seed, response_seed and fit_seed, in that
order. All seeds must be distinct nonnegative integers across the full roster.
The explicit generating and analysis MFRMPrior must match exactly.

The joint prior is independent zero-mean normals on the model's free coordinates.
Reference rater/item values are zero; the last step of each item is the negative
sum of its other steps, not an additional independent draw. Use `prior_input`
to obtain the named means/scales and declared parameter seed, then save the
realized values with `bind_prior_draw` before generating responses.

All other keywords have the meanings in `prepare`. The internal zero-valued
template validates the allocation only; its values are not generating truths.
`ledger` and its stage operations retain the whole SBC roster. Save the bound
dataset plan separately from the bound observations; register the observations
alone as the generation artifact consumed by `summarize_sbc`.
For saved-rank review, declare `rank_settings=(iterations=(...),
dependence_policy="...")` before generation. Iterations must be increasing,
unique retained IDs, selected identically from every chain; the policy describes
how their posterior dependence will be assessed. No automatic thinning or
independence guarantee follows. Without this setting, older input-only plans
remain valid but cannot be passed to review_sbc_fit.
No generator history, calibration or design adequacy is verified.
"""
function prepare_sbc(assignments; levels, category_levels, jobs,
        prior::MFRMPrior, generating_prior::MFRMPrior=prior, parameters, interval,
        sampler::NamedTuple, provenance::NamedTuple, precision, response_ids=nothing,
        rank_settings=nothing)
    require(B._prior_cache_record(prior) == B._prior_cache_record(generating_prior),
        "SBC generating and analysis priors must match")
    roster = Tuple(jobs)
    require(!isempty(roster), "declare the full SBC dataset roster")
    for job in roster
        require(keys(job) == (:dataset_id,:parameter_seed,:response_seed,:fit_seed),
            "SBC job needs dataset_id/parameter_seed/response_seed/fit_seed")
        require(all(s -> s isa Integer && !(s isa Bool) && 0 <= s <= typemax(Int),
            (job.parameter_seed,job.response_seed,job.fit_seed)), "invalid SBC seed")
    end
    seeds = [s for job in roster for s in (job.parameter_seed,job.response_seed,job.fit_seed)]
    require(length(unique(seeds)) == length(seeds), "reused seed in SBC independent-stream plan")
    require(Set(keys(levels)) == Set((:person,:rater,:item)), "declare person/rater/item levels")
    categories = Tuple(B._normalize_category_levels(category_levels))
    zero_truth = Dict("$role[$label]"=>0.0 for role in keys(levels) for label in getproperty(levels,role))
    for item in levels.item, k in 1:length(categories)-1
        zero_truth["step[item=$item,$k]"] = 0.0
    end
    template = prepare(assignments; levels, category_levels=categories, truth=zero_truth,
        jobs=[(;j.dataset_id,j.response_seed,j.fit_seed) for j in roster],
        prior, parameters, interval, sampler, provenance, precision, response_ids)
    body = (;schema=SBC_PLAN,mode=:joint_prior_sbc,template,
        jobs=deepcopy(roster),generating_prior=B._prior_cache_record(generating_prior),
        parameter_measure=:independent_normals_on_free_coordinates,
        generation_verified=false,sbc_performed=false)
    if rank_settings !== nothing
        require(rank_settings isa NamedTuple && keys(rank_settings)==(:iterations,:dependence_policy),
            "rank settings need iterations and dependence_policy")
        selected = Tuple(rank_settings.iterations)
        require(!isempty(selected) && all(i -> i isa Integer && !(i isa Bool) &&
            1 <= i <= sampler.ndraws,selected) && issorted(selected) &&
            length(unique(selected))==length(selected), "invalid retained rank iterations")
        require(rank_settings.dependence_policy isa AbstractString &&
            !isempty(strip(rank_settings.dependence_policy)), "declare a posterior-dependence policy")
        body = merge(body,(;rank_settings=(;iterations=Int.(selected),
            dependence_policy=String(rank_settings.dependence_policy))))
    end
    B._prediction_seal(body)
end

"""
    prior_input(study, dataset_id)

Return the named zero-mean normal coordinates, scales, declared parameter seed
and RNG for one prepared SBC job. Draw every free coordinate jointly; do not draw
only the focal quantities or center an independently generated full step vector.
The reference rater/item and final item steps are reconstructed by bind_prior_draw.
This sealed recipe is deterministic. It neither calls an RNG nor proves that
any later parameter values were sampled from the declared prior.
"""
function prior_input(study, dataset_id)
    checksbc(study)
    index = findfirst(j -> j.dataset_id == dataset_id,study.jobs)
    require(index !== nothing, "unplanned SBC dataset")
    job = study.jobs[index]
    design = generator_input(study.template,dataset_id).design
    prior = MFRMPrior(; (k=>getproperty(study.generating_prior,k)
        for k in (:person_sd,:rater_sd,:item_sd,:step_sd))...)
    coordinates = Tuple((;parameter=name,mean=0.0,sd=B._prior_sd(design,prior,i))
        for (i,name) in enumerate(design.parameter_names))
    B._prediction_seal((;schema="bayesianmgmfrm.mfrm_sbc_prior_input.v1",
        study_hash=study.content_hash,dataset_id=String(dataset_id),
        parameter_seed=job.parameter_seed,rng_declaration=study.template.provenance.rng_algorithm,
        prior=study.generating_prior,coordinates,parameter_measure=study.parameter_measure,
        reconstructed_steps=:negative_sum_of_free_steps,generation_verified=false))
end

"""
    bind_prior_draw(study, dataset_id, values; generating_prior, parameter_seed)

Bind one supplied full free-coordinate parameter vector, keyed by parameter name,
to its SBC job. Check all names, finite values, declared seed and generating prior;
reconstruct zero references and final item steps using the existing model map.
Return a sealed, one-dataset plan accepted by generator_input, bind_observations,
bind_data and review_fit. Save this plan before response generation. Save the
observations separately and register them as the study ledger's generation
artifact. The execution example keeps dataset-plan.jls beside generation.jls.

The returned sbc_binding retains the parent study, parameter seed and declaration
that sampling history is unverified. Supplying values does not prove prior
sampling; deterministic fixtures must not be counted as SBC simulations. Keep
the parent study ledger for all planned IDs. The fixed-truth recovery_replications
aggregator does not assess SBC across varying truths. Use review_sbc_fit for
saved rank bounds; study-wide rank analysis and calibration remain separate.
"""
function bind_prior_draw(study, dataset_id, values::AbstractDict;
        generating_prior::MFRMPrior, parameter_seed)
    recipe = prior_input(study,dataset_id)
    require(parameter_seed isa Integer && !(parameter_seed isa Bool) &&
        parameter_seed == recipe.parameter_seed, "parameter seed differs from SBC plan")
    require(B._prior_cache_record(generating_prior) == study.generating_prior,
        "generating prior differs from SBC plan")
    template = study.template
    require(Set(keys(values)) == Set(template.free_names), "supply every named free coordinate exactly")
    require(all(v -> v isa Real && !(v isa Bool) && isfinite(Float64(v)),Base.values(values)),
        "prior coordinates must be finite real values")
    direct = [Float64(values[n]) for n in template.free_names]
    truth = Dict(template.truth)
    for (name,value) in zip(template.free_names,direct)
        truth[name] = value
    end
    design = generator_input(template,dataset_id).design
    last_step = length(template.category_levels)-1
    for (i,item) in enumerate(template.levels.item)
        truth["step[item=$item,$last_step]"] = B._threshold_step(design,direct,i,last_step)
    end
    job = only(filter(j -> j.dataset_id == dataset_id,study.jobs))
    bound = prepare(template.assignments;levels=template.levels,
        category_levels=template.category_levels,truth,
        jobs=[(;job.dataset_id,job.response_seed,job.fit_seed)],prior=generating_prior,
        parameters=template.parameters,interval=template.interval,sampler=template.sampler,
        provenance=template.provenance,precision=Dict(template.precision),response_ids=template.response_ids)
    # Exclude the old seal before attaching parent identity and resealing.
    payload = Base.structdiff(bound,(;content_hash=nothing))
    B._prediction_seal(merge(payload,(;sbc_binding=(;study_hash=study.content_hash,
        parameter_seed=job.parameter_seed,prior_input_hash=recipe.content_hash,
        generating_prior=study.generating_prior,sampling_history_verified=false))))
end

"""
    bind_observations(plan, dataset_id, table)

Bind observed rows before model validation, including valid single-category data.
Save this sealed record before calling bind_data/review_fit. It preserves the
planned ID, full-truth reference, declared response seed and all observed scores;
it does not attest how those scores were generated. No model or RNG is run.
"""
function bind_observations(plan, dataset_id, table)
    checkplan(plan)
    job_index = findfirst(x -> x.dataset_id == dataset_id,plan.jobs)
    require(job_index !== nothing, "unplanned dataset")
    columns = map(k -> B._column(table,k),(:person,:rater,:item,:score))
    require(all(v -> length(v)==length(plan.assignments),columns), "realized row count differs")
    for (j,k) in enumerate((:person,:rater,:item))
        require(Tuple(columns[j]) == getproperty.(plan.assignments,k), "realized assignment/order differs: $k")
    end
    if plan.response_ids !== nothing
        require(Tuple(B._column(table,:response_id)) == plan.response_ids, "realized response IDs/order differ")
    end
    data = planned_data(plan,table)
    B._prediction_seal((;schema="example.mfrm_planned_observations.v1",plan_hash=plan.content_hash,
        dataset_id=String(dataset_id),response_seed=plan.jobs[job_index].response_seed,
        scores=Tuple(data.score),generating_truth_verification=:not_established))
end

"""
    observation_table(plan, observations)

Restore the planned columns and saved scores from a sealed observation record.
Checks the plan identity and declared response seed; does not generate data.
"""
function observation_table(plan, observed)
    checkplan(plan)
    B._prediction_check_seal(observed,"example.mfrm_planned_observations.v1")
    require(observed.plan_hash == plan.content_hash, "observations belong to another plan")
    job = only(filter(j -> j.dataset_id == observed.dataset_id,plan.jobs))
    require(observed.response_seed == job.response_seed, "response seed declaration differs")
    table = (;person=collect(getproperty.(plan.assignments,:person)),rater=collect(getproperty.(plan.assignments,:rater)),
      item=collect(getproperty.(plan.assignments,:item)),score=collect(observed.scores))
    plan.response_ids === nothing ? table : merge(table,(;response_id=collect(plan.response_ids)))
end
planned_data(plan, table) = FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
    response_id=plan.response_ids === nothing ? nothing : :response_id,category_levels=plan.category_levels)
observed_data(plan, observed) = planned_data(plan,observation_table(plan,observed))

"""
    bind_data(plan, dataset_id, table)

Check realized person/rater/item/score columns against the ordered allocation,
then use ordinary FacetData/mfrm_spec/getdesign validation. Declared categories
are retained, including categories absent from the supplied scores. Rejected
data are outcomes to record, not instructions to redraw. Returns an existing
design, the direct truth vector and analysis prior, without fitting/generating.
The binding proves alignment, not that the scores were sampled from the truth.
"""
function bind_data(plan, dataset_id, table)
    observed = bind_observations(plan,dataset_id,table)
    data = observed_data(plan,observed)
    design = getdesign(mfrm_spec(data;thresholds=:partial_credit))
    require(Tuple(design.parameter_names) == plan.free_names, "model coordinates differ from plan")
    prior = MFRMPrior(; (k=>getproperty(plan.analysis_prior,k) for k in (:person_sd,:rater_sd,:item_sd,:step_sd))...)
    truth = Dict(plan.truth)
    (;data,design,prior,direct_truth=[truth[k] for k in plan.free_names],binding=observed)
end

"""
    generator_input(plan, dataset_id)

Build an input for existing simulate_responses without invoking it. The returned
design contains deterministic cyclic structural placeholders, NOT observed or
generated outcomes. Never fit this design. Use only design/direct_truth as the
generator arguments; save its eventual actual scores with bind_observations.
The declared response seed/RNG are recorded, not executed or verified.
"""
function generator_input(plan, dataset_id)
    checkplan(plan)
    index = findfirst(j -> j.dataset_id == dataset_id,plan.jobs)
    require(index !== nothing, "unplanned dataset")
    require(length(plan.assignments) >= 2, "generator adapter needs at least two allocation rows")
    rows = plan.assignments
    table = (;person=collect(getproperty.(rows,:person)),rater=collect(getproperty.(rows,:rater)),
        item=collect(getproperty.(rows,:item)),
        score=[plan.category_levels[mod1(i,length(plan.category_levels))] for i in eachindex(rows)])
    plan.response_ids === nothing || (table = merge(table,(;response_id=collect(plan.response_ids))))
    data = planned_data(plan,table)
    design = getdesign(mfrm_spec(data;thresholds=:partial_credit))
    require(Tuple(design.parameter_names) == plan.free_names, "generator coordinates differ from plan")
    truth = Dict(plan.truth)
    recipe = B._prediction_seal((;schema="example.mfrm_generator_input.v1",plan_hash=plan.content_hash,
        dataset_id=String(dataset_id),response_seed=plan.jobs[index].response_seed,
        response_rng_declaration=plan.provenance.rng_algorithm,
        scores=:structural_placeholders_only,generation_verified=false))
    (;design,direct_truth=[truth[n] for n in plan.free_names],recipe)
end

# Apply absolute MCSE limits to the mean and both central-interval endpoints.
# This arithmetic helper consumes native recovery rows, not synthetic fit objects.
function focal_precision(plan, rows)
    lower,upper = B._interval_probabilities(plan.interval)
    limits = Dict(plan.precision)
    Tuple(map(plan.parameters) do name
        r = only(filter(r -> r.parameter == name,rows))
        endpoint_mcse = Tuple(only(filter(q -> q.probability == p,r.mcse.quantiles)).mcse for p in (lower,upper))
        values = (r.mcse.mean_mcse,endpoint_mcse...)
        available = r.mcse.mcse_status === :available && all(x -> x isa Real && isfinite(x) && x >= 0,values)
        bound = limits[name]
        passed = available && values[1] <= bound.mean_mcse_max && all(x -> x <= bound.endpoint_mcse_max,endpoint_mcse)
        (;parameter=name,mean_mcse=r.mcse.mean_mcse,endpoint_mcse,limits=bound,
          status=!available ? :unavailable : passed ? :passed : :exceeded,passed)
    end)
end

"""
    review_fit(plan, observations, cache_path; cache_sha256)

Load an existing native MFRM cache, verify its bytes and its data/model/prior,
parameter order, backend/algorithm, recorded controls, fit seed and retained draw
counts against the plan. Reuse recovery_evaluation without generating or fitting.
Apply declared absolute mean/central-endpoint MCSE limits; global sampling
warnings still exclude numerical qualification. An unavailable MCSE never passes.

Matching metadata does not attest execution provenance, the response-generating
truth/RNG, unrecorded initialization, source/environment declarations, calibration
or adequate replication precision. Return a sealed review for separate storage;
the stage ledger remains a declaration and byte-integrity record.
"""
function review_fit(plan, observed, cache_path; cache_sha256)
    checked_review(plan,observed,cache_path;cache_sha256).review
end

# Share the existing cache checks so SBC review loads and verifies a fit once.
function checked_review(plan, observed, cache_path; cache_sha256)
    bound = bind_data(plan,observed.dataset_id,observation_table(plan,observed))
    require(isfile(cache_path) && filehash(cache_path) == cache_sha256, "saved cache missing or hash differs")
    fit = load_fit_cache(cache_path)
    require(filehash(cache_path) == cache_sha256, "saved cache changed during review")
    require(fit isa MFRMFit, "this adapter requires a native scalar MFRM fit")
    require(B._prediction_fitted_target(fit) == B._prediction_refit_target(bound.design.spec,bound.prior),
        "saved data/model/prior differs from plan and observations")
    require(Tuple(fit.design.parameter_names) == plan.free_names, "saved parameter order differs")
    controls = plan.sampler
    require(fit.backend === controls.backend && fit.sampler === controls.algorithm, "saved backend/algorithm differs")
    expected = Dict(k=>v for (k,v) in pairs(controls) if !(k in (:backend,:algorithm)))
    actual = Dict(k=>v for (k,v) in pairs(fit.sampler_controls) if !(k in (:rng,:warmup_diagnostics)))
    require(isequal(actual,expected), "saved sampler controls differ")
    job = only(filter(j -> j.dataset_id == observed.dataset_id,plan.jobs))
    rng = fit.sampler_controls.rng
    require(rng.algorithm === :MersenneTwister && rng.replayable === true && rng.seed == job.fit_seed,
        "saved fit RNG/seed differs or is not replayable")
    require(fit.warmup == controls.warmup && size(fit.draws) == (controls.ndraws*controls.chains,length(plan.free_names)) &&
        length(unique(fit.chain_ids)) == controls.chains, "saved draw/warmup counts differ")
    require(all(isfinite,fit.draws) && all(isfinite,fit.log_posterior), "nonfinite saved posterior")
    truth = Dict(plan.truth)
    recovery = B.recovery_evaluation(fit,Dict(n=>truth[n] for n in plan.parameters);
        dataset_id=observed.dataset_id,observation_ids=["$(observed.dataset_id)/row-$i" for i in eachindex(plan.assignments)],
        interval=plan.interval)
    precision = focal_precision(plan,recovery.rows)
    qualified = !recovery.sampling_warning && !recovery.fixed_truth_mismatch && all(r -> r.passed,precision)
    review = B._prediction_seal((;schema="example.mfrm_saved_fit_review.v1",plan_hash=plan.content_hash,
        observations_hash=observed.content_hash,cache=(;path=abspath(cache_path),sha256=String(cache_sha256)),
        recovery,precision,precision_applied=true,numerically_qualified=qualified,
        generating_truth_verification=:not_established,execution_provenance_verified=false,
        scientific_acceptance=:not_established,new_posterior_fits=0,new_generated_datasets=0))
    (;fit,review)
end

"""
    summarize_recovery(plan, ledger; scenario_id, dataset_independence,
                       max_interval_widths=nothing, width_confidence_level=nothing)

Aggregate one fixed-truth scalar PCM plan from its full saved stage ledger.
Save bound observations with Serialization as the generation artifact, the native
fit as the fit artifact, and `review_fit`'s result with Serialization as the
recovery artifact. Read only trusted records in a compatible Julia environment.
No native fit is deserialized, rescored or refitted by this operation.

Check artifact bytes and the saved observation/plan/cache/recovery bindings.
Completed reviews must match the plan's actual-data target, focal truths,
interval, draw layout and MCSE limits. Missing or changed artifacts, unfinished
stages and unattempted jobs remain unresolved in the full planned denominator;
recorded failures retain their stage, kind and reason. Invalid completed review
contents raise an error instead of silently excluding a dataset.

Return `roster` with stage details and whole-job numerical qualification, and
`replications`, the existing `BayesianMGMFRM.recovery_replications` result. Its
precision-qualified summaries apply the plan's MCSE limits per focal quantity;
one failed focal quantity does not exclude another qualifying quantity. Pass
`replications` to `design_precision_plot_data` or `plot_design_precision` when
width targets were requested. These targets do not change the saved plan.

Dataset independence must be declared explicitly; it is not verified. The
existing conditional confidence intervals and unresolved-outcome bounds retain
their distinct meanings. One plan is one scenario, not a design comparison.
Seals and metadata do not attest generation, execution provenance, calibration
or adequacy of the analysis prior. Use `summarize_sbc` for joint-prior SBC.
Nothing is generated, fitted, retried or written.
"""
function summarize_recovery(plan, record; scenario_id::AbstractString,
        dataset_independence, max_interval_widths=nothing, width_confidence_level=nothing)
    checkplan(plan)
    require(!hasproperty(plan,:sbc_binding), "use summarize_sbc for joint-prior SBC")
    inventory = review(plan,record)
    evaluations, roster = NamedTuple[], NamedTuple[]
    failures = Pair{String,String}[]
    seen_caches = Set{String}()
    for entry in inventory.rows
        r = nothing
        if entry.outcome === :recorded_completed
            observed = deserialize(entry.stages.generation.artifact.path)
            r = deserialize(entry.stages.recovery.artifact.path)
            for stage in STAGES
                artifact = getproperty(entry.stages,stage).artifact
                require(isfile(artifact.path) && filehash(artifact.path)==artifact.sha256,
                    "recovery artifact changed during summary")
            end
            B._prediction_check_seal(r,"example.mfrm_saved_fit_review.v1")
            recovery = r.recovery
            B._prediction_check_seal(recovery,"bayesianmgmfrm.recovery_evaluation.v1")
            bound = bind_data(plan,entry.dataset_id,observation_table(plan,observed))
            require(r.plan_hash==plan.content_hash &&
                observed.dataset_id==recovery.dataset_id==entry.dataset_id &&
                r.observations_hash==observed.content_hash &&
                r.cache.sha256==entry.stages.fit.artifact.sha256,
                "recovery review, observations and recorded fit identities differ")
            require(recovery.model_contract.fitted_target==B._prediction_refit_target(bound.design.spec,bound.prior),
                "recovery data/model/prior target differs from plan")
            require(recovery.interval_probability==plan.interval &&
                Tuple(getproperty.(recovery.rows,:parameter))==plan.parameters &&
                all(row -> !row.fixed && row.true_value==Dict(plan.truth)[row.parameter],recovery.rows),
                "recovery quantities, truths or interval differ from plan")
            require(recovery.n_retained_draws==plan.sampler.chains*plan.sampler.ndraws &&
                recovery.chain_ids==repeat(1:plan.sampler.chains;inner=plan.sampler.ndraws) &&
                recovery.iterations==repeat(1:plan.sampler.ndraws;outer=plan.sampler.chains) &&
                recovery.observation_ids==["$(entry.dataset_id)/row-$i" for i in eachindex(plan.assignments)],
                "recovery draw layout or observation IDs differ from plan")
            precision = focal_precision(plan,recovery.rows)
            qualified = !recovery.sampling_warning && !recovery.fixed_truth_mismatch && all(p->p.passed,precision)
            require(r.precision_applied===true && isequal(r.precision,precision) &&
                r.numerically_qualified===qualified,"saved recovery precision differs from plan")
            require(!(r.cache.sha256 in seen_caches),"saved fit cache reused across datasets")
            push!(seen_caches,r.cache.sha256)
            push!(evaluations,recovery)
        elseif entry.outcome === :failed
            stage = only(filter(k -> getproperty(entry.stages,k).status===:failed,STAGES))
            failure = getproperty(entry.stages,stage)
            push!(failures,entry.dataset_id=>"$stage/$(failure.failure_kind): $(failure.reason)")
        end
        status = r===nothing ? entry.outcome : r.numerically_qualified ? :numerically_qualified : :numerically_excluded
        push!(roster,merge(entry,(;status,review_hash=r===nothing ? nothing : r.content_hash)))
    end
    replications = B.recovery_replications(evaluations;
        planned_dataset_ids=collect(getproperty.(plan.jobs,:dataset_id)),parameters=collect(plan.parameters),
        scenario_id,dataset_independence,failures,mcse_limits=Dict(plan.precision),
        max_interval_widths,width_confidence_level)
    B._prediction_seal((;schema="bayesianmgmfrm.mfrm_recovery_summary.v1",
        plan_hash=plan.content_hash,ledger_hash=record.content_hash,n_planned=length(plan.jobs),
        roster,counts=Dict(s=>count(r->r.status==s,roster) for s in unique(getproperty.(roster,:status))),
        replications,execution_provenance_verified=false,generation_verified=false,
        scientific_acceptance=:not_established,new_posterior_fits=0,new_generated_datasets=0))
end

# Same strict comparison as the existing SBC worker; keep ties unresolved here.
function rank_interval(truth::Real, draws::AbstractVector{<:Real})
    require(!(truth isa Bool) && isfinite(truth) && !isempty(draws) &&
        all(x -> !(x isa Bool) && isfinite(x),draws), "rank values must be finite real numbers")
    lower = count(<(truth),draws)
    ties = count(==(truth),draws)
    (;truth,n_draws=length(draws),lower,upper=lower+ties,ties,
        rank=ties==0 ? lower : missing)
end

"""
    review_sbc_fit(study, dataset_plan, observations, cache_path;
                   cache_sha256, posterior_dependence)

Review one native scalar MFRM cache against a prepared SBC study and its bound
truth. `study` must declare rank_settings before generation. Reconstruct the
dataset plan to check its full binding, then apply all review_fit checks without
reloading the cache. Select the declared retained iterations from each chain.
Compute zero-based ranks for the focal free coordinates and the joint observed
data log likelihood, using the same actual responses at truth and at each draw.
Diagnostics for these test quantities use all retained draws (rank-normalized
split R-hat <= 1.01 and bulk/tail ESS >= 400), in addition to the global fit and
focal MCSE checks. All diagnostic rows and exclusions are retained.

`posterior_dependence=(status=:unresolved, evidence="...")` or
`status=:declared_independent` records the caller's assessment of the selected
draws against the study policy. Passing diagnostics or thinning alone does not
establish independence. The declaration is not independently verified.

An exact tie yields [lower, upper], the inclusive possible rank range, and a
missing point rank. No midpoint, approximate tie or randomized tie is substituted.
Even an unqualified fit retains its descriptive rank bounds; rank_eligible is
false when fit/quantity diagnostics, dependence or ties are unresolved. Keep
such outcomes in the parent study ledger, along with failed and missing fits.
The result preserves cache/plan/observation identities and selected row IDs.
It neither verifies prior generation nor supplies a uniformity test, calibration
certificate, posterior simulation or automatic retry. Save it separately.
"""
function review_sbc_fit(study, plan, observed, cache_path;
        cache_sha256, posterior_dependence::NamedTuple)
    checksbc(study)
    checkplan(plan)
    require(hasproperty(study,:rank_settings), "declare rank_settings before SBC generation")
    checkdependence(posterior_dependence)
    id = observed.dataset_id
    prior = MFRMPrior(; (k=>getproperty(study.generating_prior,k)
        for k in (:person_sd,:rater_sd,:item_sd,:step_sd))...)
    truth = Dict(plan.truth)
    recipe = prior_input(study,id)
    expected = bind_prior_draw(study,id,Dict(n=>truth[n] for n in study.template.free_names);
        generating_prior=prior,parameter_seed=recipe.parameter_seed)
    require(plan.content_hash==expected.content_hash, "dataset plan differs from its parent SBC study")
    checked = checked_review(plan,observed,cache_path;cache_sha256)
    fit,review = checked.fit,checked.review
    require(B._fit_draws_per_chain(fit)==plan.sampler.ndraws, "retained chain layout differs")
    selected = findall(in(study.rank_settings.iterations),fit.iterations)
    columns = [only(findall(==(n),fit.design.parameter_names)) for n in plan.parameters]
    names = [collect(plan.parameters); "joint_log_likelihood"]
    joint = [loglikelihood(fit.design,row) for row in eachrow(fit.draws)]
    values = hcat(fit.draws[:,columns],joint)
    truth_values = [Float64[truth[n] for n in plan.parameters];
        loglikelihood(fit.design,[truth[n] for n in plan.free_names])]
    require(all(isfinite,values) && all(isfinite,truth_values), "nonfinite SBC test quantity")
    diagnostics = B._candidate_mcmc_diagnostic_rows(values,names,plan.sampler.chains;
        parameter_space=:sbc_test_quantity,split_chains=true,rhat_threshold=1.01,ess_threshold=400.0)
    ranks = Tuple(merge((;quantity=name),rank_interval(truth_values[j],values[selected,j]))
        for (j,name) in enumerate(names))
    exclusions = sbc_exclusions(review,diagnostics,posterior_dependence,ranks)
    B._prediction_seal((;schema="bayesianmgmfrm.mfrm_sbc_rank_review.v1",
        study_hash=study.content_hash,plan_hash=plan.content_hash,observations_hash=observed.content_hash,
        dataset_id=id,fit_review=review,rank_settings=study.rank_settings,
        selected_rows=Tuple(selected),chain_ids=Tuple(fit.chain_ids[selected]),
        iterations=Tuple(fit.iterations[selected]),quantity_diagnostics=Tuple(diagnostics),ranks,
        posterior_dependence=deepcopy(posterior_dependence),exclusions=Tuple(exclusions),
        rank_eligible=isempty(exclusions),independence_verified=false,generation_verified=false,
        calibration_verified=false,scientific_acceptance=:not_established,
        new_posterior_fits=0,new_generated_datasets=0))
end

# Conditional full-roster DKW arithmetic, shared with the existing study protocol.
function sbc_rank_cdf(ranks; n_draws, n_quantities, alpha, independent)
    n = length(ranks)
    valid = collect(skipmissing(ranks))
    unresolved = n-length(valid)
    epsilon = independent ? sqrt((log(2.0)+log(n_quantities)-log(alpha))/(2n)) : missing
    rows = [begin
        c = count(<=(k),valid)
        lower = k==n_draws ? 1.0 : c/n
        upper = k==n_draws ? 1.0 : (c+unresolved)/n
        band_lower = !independent ? missing : k==n_draws ? 1.0 : max(0.0,lower-epsilon)
        band_upper = !independent ? missing : k==n_draws ? 1.0 : min(1.0,upper+epsilon)
        reference = (k+1)/(n_draws+1)
        resolved_departure = independent ? reference<band_lower || reference>band_upper : missing
        (;rank=k,reference,lower,upper,band_lower,band_upper,resolved_departure)
    end for k in 0:n_draws]
    conditional_screen = !independent ? :assumptions_unresolved : isempty(valid) ? :unresolved :
        any(r->r.resolved_departure,rows) ? :departure : :no_resolved_departure
    (;planned=n,usable=length(valid),unresolved,n_draws,n_quantities,alpha,epsilon,rows,conditional_screen)
end

function checkdependence(declaration)
    require(declaration isa NamedTuple && keys(declaration)==(:status,:evidence) &&
        declaration.status in (:unresolved,:declared_independent) &&
        declaration.evidence isa AbstractString && !isempty(strip(declaration.evidence)),
        "record dependence status and supporting evidence")
end

function sbc_exclusions(review,diagnostics,dependence,ranks)
    exclusions = Symbol[]
    review.numerically_qualified || push!(exclusions,:fit_or_focal_precision)
    all(r->r.flag===:ok,diagnostics) || push!(exclusions,:test_quantity_diagnostics)
    dependence.status===:declared_independent || push!(exclusions,:posterior_dependence)
    any(r->r.ties>0,ranks) && push!(exclusions,:ties)
    Tuple(exclusions)
end

function check_sbc_rank_review(study,r,observed,entry)
    B._prediction_check_seal(r,"bayesianmgmfrm.mfrm_sbc_rank_review.v1")
    B._prediction_check_seal(observed,"example.mfrm_planned_observations.v1")
    B._prediction_check_seal(r.fit_review,"example.mfrm_saved_fit_review.v1")
    B._prediction_check_seal(r.fit_review.recovery,"bayesianmgmfrm.recovery_evaluation.v1")
    require(r.study_hash==study.content_hash &&
        r.dataset_id==observed.dataset_id==entry.dataset_id==r.fit_review.recovery.dataset_id &&
        r.plan_hash==observed.plan_hash==r.fit_review.plan_hash &&
        r.observations_hash==observed.content_hash==r.fit_review.observations_hash &&
        r.fit_review.cache.sha256==entry.stages.fit.artifact.sha256,
        "SBC review, observations and recorded fit identities differ")
    job = only(filter(j->j.dataset_id==entry.dataset_id,study.jobs))
    require(observed.response_seed==job.response_seed && r.rank_settings==study.rank_settings,
        "SBC response seed or rank policy differs")
    chains,ndraws = study.template.sampler.chains,study.template.sampler.ndraws
    ids = study.rank_settings.iterations
    require(r.selected_rows==Tuple((c-1)*ndraws+i for c in 1:chains for i in ids) &&
        r.chain_ids==Tuple(c for c in 1:chains for _ in ids) &&
        r.iterations==Tuple(i for _ in 1:chains for i in ids),"SBC selected draw layout differs")
    names = (study.template.parameters...,"joint_log_likelihood")
    require(getproperty.(r.ranks,:quantity)==names &&
        getproperty.(r.quantity_diagnostics,:parameter)==names,"SBC quantity family differs")
    L = Base.checked_mul(chains,length(ids))
    for rank in r.ranks
        require(rank.truth isa Real && !(rank.truth isa Bool) && isfinite(rank.truth) &&
            all(x->x isa Integer && !(x isa Bool),(rank.n_draws,rank.lower,rank.upper,rank.ties)) &&
            rank.n_draws==L && 0<=rank.lower<=rank.upper<=L && rank.ties==rank.upper-rank.lower &&
            (rank.ties>0 ? ismissing(rank.rank) :
                rank.rank isa Integer && !(rank.rank isa Bool) && rank.rank==rank.lower),
            "invalid SBC rank support, tie range or point rank")
    end
    require(all(d->d.total_draws==chains*ndraws && d.draws_per_chain==ndraws,r.quantity_diagnostics),
        "SBC diagnostics do not cover the declared retained draws")
    checkdependence(r.posterior_dependence)
    recovery = r.fit_review.recovery
    require(r.fit_review.numerically_qualified===(!recovery.sampling_warning &&
        !recovery.fixed_truth_mismatch && all(p->p.passed,r.fit_review.precision)),
        "SBC fit qualification differs from its recorded warnings")
    exclusions = sbc_exclusions(r.fit_review,r.quantity_diagnostics,r.posterior_dependence,r.ranks)
    require(r.exclusions==exclusions && r.rank_eligible===isempty(exclusions),
        "SBC eligibility differs from its recorded exclusions")
end

"""
    summarize_sbc(study, ledger; alpha, dataset_independence)

Summarize every planned scalar PCM SBC dataset, including failures and unfinished
work. Use the parent study ledger: save bound observations with Serialization as
its generation artifact, the native fit as its fit artifact, and review_sbc_fit's
result with Serialization as its recovery artifact. Read only trusted local
records in a compatible Julia environment. Check all artifact bytes and the
saved review/observation/fit bindings. No native fit is deserialized or rescored.
Missing/changed artifacts and unfinished stages retain missing ranks; malformed
completed records raise an error. Reusing a saved cache/sample under two IDs is
rejected. For legacy scalar reviews without a source-sample hash, use the fitted
target plus evaluated focal-draw hash, as in recovery_replications. Paths embedded
in old reviews need not change after verified relocation.

All focal coordinates plus joint_log_likelihood form the fixed quantity family.
Only rank_eligible reviews enter primary rank CDFs; keep their other descriptive
ranks and all exclusion reasons in roster. At k<L, lower=c/N and upper=(c+u)/N,
where N is the planned count, c the eligible ranks <=k and u all unresolved slots.
Both endpoints are 1 at L. These are missing-rank bounds, not confidence bands.

Supply dataset_independence=(status=:unresolved, evidence="...") or an explicit
:declared_independent assessment. The former suppresses bands and the screen.
Under independent datasets and valid iid posterior ranks, widen the bounds by
sqrt(log(2*T/alpha)/(2*N)), a DKW bound with Bonferroni adjustment for the T
predeclared quantities. Compare with the discrete-uniform reference (k+1)/(L+1).
A departure is resolved only outside the widened envelope. Declare alpha before
inspecting results; this is a fixed-roster, single-assessment bound, not repeated
monitoring or a guarantee across multiple studies. No departure is not proof
of calibration. Eligibility and independence declarations are not verification
of actual prior generation, independence, posterior correctness or study power.
No random tie breaking, new fits, generation, retries or file writes occur.
"""
function summarize_sbc(study,record;alpha::Real,dataset_independence::NamedTuple)
    checksbc(study)
    require(hasproperty(study,:rank_settings),"declare rank_settings before SBC generation")
    require(!(alpha isa Bool) && isfinite(alpha) && 0<alpha<1,"alpha must lie strictly between 0 and 1")
    checkdependence(dataset_independence)
    inventory = review(study,record)
    names = (study.template.parameters...,"joint_log_likelihood")
    L = Base.checked_mul(study.template.sampler.chains,length(study.rank_settings.iterations))
    columns = [Union{Missing,Int}[missing for _ in study.jobs] for _ in names]
    roster = NamedTuple[]
    seen_caches,seen_samples = Set{String}(),Set{String}()
    for (i,entry) in enumerate(inventory.rows)
        r = nothing
        if entry.outcome===:recorded_completed
            observed = deserialize(entry.stages.generation.artifact.path)
            r = deserialize(entry.stages.recovery.artifact.path)
            for stage in STAGES
                a = getproperty(entry.stages,stage).artifact
                require(isfile(a.path) && filehash(a.path)==a.sha256,"SBC artifact changed during summary")
            end
            check_sbc_rank_review(study,r,observed,entry)
            cache = r.fit_review.cache.sha256
            recovery = r.fit_review.recovery
            # Match recovery_replications for scalar caches without a source-sample hash.
            sample = recovery.source_sample_hash===nothing ?
                B._cache_hash((recovery.model_contract.fitted_target,recovery.evaluated_draws_hash)) :
                recovery.source_sample_hash
            require(sample isa AbstractString && !isempty(sample) &&
                !(cache in seen_caches) && !(sample in seen_samples),"SBC cache/sample reused or unbound")
            push!(seen_caches,cache);push!(seen_samples,sample)
            if r.rank_eligible
                for j in eachindex(names)
                    columns[j][i] = r.ranks[j].rank
                end
            end
        end
        status = r===nothing ? entry.outcome : r.rank_eligible ? :rank_eligible : :rank_excluded
        push!(roster,merge(entry,(;status,review_hash=r===nothing ? nothing : r.content_hash,
            exclusions=r===nothing ? () : r.exclusions,descriptive_ranks=r===nothing ? nothing : r.ranks)))
    end
    quantities = Tuple((;quantity=name,ranks=Tuple(columns[j]),
        sbc_rank_cdf(columns[j];n_draws=L,n_quantities=length(names),alpha,
            independent=dataset_independence.status===:declared_independent)...)
        for (j,name) in enumerate(names))
    B._prediction_seal((;schema="bayesianmgmfrm.mfrm_sbc_summary.v1",
        study_hash=study.content_hash,ledger_hash=record.content_hash,n_planned=length(study.jobs),
        roster,counts=Dict(s=>count(r->r.status==s,roster) for s in unique(getproperty.(roster,:status))),
        exclusion_counts=Dict(s=>count(r->s in r.exclusions,roster)
            for s in (:fit_or_focal_precision,:test_quantity_diagnostics,:posterior_dependence,:ties)),
        quantities,alpha,dataset_independence=deepcopy(dataset_independence),
        independence_verified=false,generation_verified=false,calibration_verified=false,
        scientific_acceptance=:not_established,new_posterior_fits=0,new_generated_datasets=0))
end

"""Create a sealed, full-roster ledger. It records declarations, not independent execution attestation."""
function ledger(plan)
    checkstudy(plan)
    pending = (;status=:not_started,artifact=nothing,failure_kind=nothing,reason=nothing)
    entries = NamedTuple[(;dataset_id=j.dataset_id,stages=NamedTuple{STAGES}((pending,pending,pending))) for j in plan.jobs]
    B._prediction_seal((;schema=LEDGER,plan_hash=plan.content_hash,entries))
end

function checkledger(plan, record)
    checkstudy(plan)
    B._prediction_check_seal(record,LEDGER)
    require(record.plan_hash == plan.content_hash, "ledger belongs to a different plan")
    require(Tuple(getproperty.(record.entries,:dataset_id)) == getproperty.(plan.jobs,:dataset_id), "ledger roster differs")
end

"""
    record_stage(plan, ledger, dataset_id; stage, status, artifact=nothing,
                 failure_kind=nothing, reason=nothing)

Return a new ledger; never execute work or overwrite the input. Stages are
generation/fit/recovery, each not_started -> started -> completed or failed.
Completion requires an existing saved artifact whose bytes are hashed. Failure
requires kind computation/validation/persistence and a reason. Failed or completed
stages cannot silently restart. Use Serialization to save the returned record
before starting work, and again after a terminal update. No MCMC resume is supplied.
"""
function record_stage(plan, record, dataset_id; stage, status, artifact=nothing,
        failure_kind=nothing, reason=nothing)
    checkledger(plan,record)
    j = findfirst(e -> e.dataset_id == dataset_id,record.entries)
    require(j !== nothing, "unplanned dataset")
    s = findfirst(==(stage),STAGES)
    require(s !== nothing, "unknown stage")
    previous = getproperty(record.entries[j].stages,stage)
    require((previous.status == :not_started && status == :started) ||
        (previous.status == :started && status in (:completed,:failed)), "invalid stage transition; no automatic retry")
    require(all(k -> getproperty(record.entries[j].stages,k).status == :completed,STAGES[1:s-1]),
        "prior stages must be completed")
    # Recheck saved dependencies before declaring the next stage started.
    if status == :started
        for k in STAGES[1:s-1]
            a = getproperty(record.entries[j].stages,k).artifact
            require(isfile(a.path) && filehash(a.path) == a.sha256, "saved predecessor missing or changed")
        end
    end
    if status == :failed
        require(failure_kind in (:computation,:validation,:persistence) && reason isa AbstractString &&
            !isempty(strip(reason)), "failure requires kind and nonempty reason")
    else
        require(failure_kind === nothing && reason === nothing, "failure fields on nonfailure")
    end
    saved = if status == :completed
        require(artifact isa AbstractString && isfile(artifact), "completion requires a saved artifact")
        (;path=abspath(artifact),sha256=filehash(artifact))
    else
        require(artifact === nothing, "only completed stages bind an artifact")
        nothing
    end
    entries = deepcopy(record.entries)
    update = (;status,artifact=saved,failure_kind,reason)
    entries[j] = merge(entries[j],(;stages=merge(entries[j].stages,NamedTuple{(stage,)}((update,)))))
    B._prediction_seal(merge(Base.structdiff(record,(;content_hash=nothing)),(;entries)))
end

"""
    relocate_ledger(plan, ledger; source_root, destination_root)

Return a new ledger referring to an already moved or copied artifact tree.
Supply absolute directory paths on the current platform. Every recorded artifact
must be below `source_root`; its relative path is retained under the existing
`destination_root`. All destination bytes must match the original saved hashes.
Missing, changed or out-of-tree artifacts cause an error without changing either
ledger or any file. The original source tree need not still exist.

Preserve dataset IDs, stages, failures and unresolved work. Append a `relocations`
entry with the previous ledger hash and both roots; later `record_stage` calls
retain that history. Keep the original ledger and save the returned value at a
new path with Serialization. A ledger without artifacts is returned unchanged.

This operation reads file hashes only: it does not copy files, deserialize fits,
change paths embedded in saved reports, execute stages or resume MCMC. Native
fit compatibility still requires its original compatible environment. File
identity is checked at this call, not guaranteed against later changes.
"""
function relocate_ledger(plan, record; source_root::AbstractString,
        destination_root::AbstractString)
    checkledger(plan,record)
    require(isabspath(source_root) && isabspath(destination_root),
        "source_root and destination_root must be absolute directory paths")
    source = normpath(source_root)
    destination = normpath(destination_root)
    require(source != destination, "relocation requires different directory paths")
    require(isdir(destination), "destination_root must already exist")
    entries = deepcopy(record.entries)
    changed = false
    for j in eachindex(entries), stage in STAGES
        previous = getproperty(entries[j].stages,stage)
        artifact = previous.artifact
        artifact === nothing && continue
        relative = relpath(artifact.path,source)
        require(isabspath(artifact.path) && !isabspath(relative) &&
            relative != "." && first(splitpath(relative)) != "..",
            "saved artifact is outside source_root: $(artifact.path)")
        target = joinpath(destination,relative)
        require(isfile(target), "relocated artifact is missing: $target")
        require(filehash(target) == artifact.sha256, "relocated artifact bytes differ: $target")
        update = merge(previous,(;artifact=merge(artifact,(;path=target))))
        entries[j] = merge(entries[j],(;stages=merge(entries[j].stages,
            NamedTuple{(stage,)}((update,)))))
        changed = true
    end
    changed || return deepcopy(record)
    history = (;previous_ledger_hash=record.content_hash,
        source_root=source,destination_root=destination)
    relocations = (get(record,:relocations,())...,history)
    B._prediction_seal(merge(Base.structdiff(record,(;content_hash=nothing)),
        (;entries,relocations)))
end

"""
    review(plan, ledger)

Read-only continuation inventory retaining every planned ID. Completed artifact
bytes are checked; missing/changed files need review, started stages are unresolved
and failures are terminal. A no-record stage is not proof that no process/output
exists. Nothing is automatically rerun. Artifact integrity does not validate a
fit/cache format, numerical precision or true data-generation provenance.
"""
function review(plan, record)
    checkledger(plan,record)
    rows = map(record.entries) do entry
        integrity = Tuple((;stage=k,status=begin
            a = getproperty(entry.stages,k).artifact
            a === nothing ? :not_recorded : !isfile(a.path) ? :missing :
                filehash(a.path) != a.sha256 ? :changed : :matched
        end) for k in STAGES)
        states = getproperty.(values(entry.stages),:status)
        outcome = any(x -> x.status in (:missing,:changed),integrity) ? :artifact_review_required :
            :failed in states ? :failed : :started in states ? :unresolved_started :
            all(==(:completed),states) ? :recorded_completed :
            all(==(:not_started),states) ? :no_attempt_recorded : :partial_completed
        (;entry.dataset_id,outcome,stages=entry.stages,integrity)
    end
    (;plan_hash=plan.content_hash,n_planned=length(rows),rows,
        counts=Dict(s=>count(r->r.outcome==s,rows) for s in unique(getproperty.(rows,:outcome))),
        automatic_execution=false,precision_applied=false,execution_provenance_verified=false)
end

end
