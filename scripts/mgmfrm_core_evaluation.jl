module MGMFRMCoreEvaluation

# Sampler-free preparation for the one dense core candidate, not a study runner.
include(joinpath(@__DIR__, "run_mgmfrm_core_pilot.jl"))
const P = MGMFRMCorePilot
const B = P.B
const V = P.V
using Statistics, Random, SHA, JSON3, Serialization

function candidate_cells(data)
    data.person_levels == P.PERSONS &&
        data.item_levels == ["I$i" for i in 1:5] &&
        data.rater_levels == ["R$i" for i in 1:5] && data.n == 1250 &&
        collect(data.category_levels) == collect(1:4) ||
        throw(ArgumentError("Expected the declared dense 50/5/5/4 candidate"))
    ids = [(data.person_levels[data.person[n]], data.item_levels[data.item[n]],
        data.rater_levels[data.rater[n]]) for n in 1:data.n]
    length(unique(ids)) == 1250 || throw(ArgumentError("Repeated or missing design cells"))
    return ids
end

seal(body) = V._seal_sbc_attempt(body)
function check_seal(record)
    record.content_hash == B._cache_hash(Base.structdiff(record, (;content_hash=nothing))) ||
        throw(ArgumentError("Prepared content changed after binding"))
    return record
end

"""One condition/backend's preparation roster; never authorizes a study run.
The fixed mode exists only to replay the historical engineering pilot.
"""
function evaluation_plan(ids; mode::Symbol, condition=nothing, backend::Symbol, generator_sha256)
    !isempty(ids) && all(id -> id isa AbstractString && !isempty(strip(id)), ids) &&
        length(unique(ids)) == length(ids) || throw(ArgumentError("Unique nonempty planned IDs required"))
    mode in (:fixed, :recovery, :prior) && backend in (:advancedhmc, :cmdstan) ||
        throw(ArgumentError("Unsupported generation mode or backend"))
    (mode === :recovery ? condition in ("R0", "R1") : condition === nothing) ||
        throw(ArgumentError("Only recovery has an R0/R1 condition"))
    occursin(r"\A[0-9a-f]{64}\z", generator_sha256) || throw(ArgumentError("Generator SHA256 required"))
    return seal((; ids=String.(ids), mode, condition, backend, generator_sha256=String(generator_sha256),
        prior=B._source_fixture_prior_values(B._source_fixture_prior(P.prior())),
        controls=P.CONTROLS, criteria=P.CRITERIA, execution_allowed=false))
end

function checked_bytes(path, expected)
    expected isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", expected) ||
        throw(ArgumentError("Explicit SHA256 reference required"))
    bytes = read(path)
    bytes2hex(sha256(bytes)) == expected || throw(ArgumentError("File hash mismatch: $path"))
    return bytes
end

"""Bind all four generator files to externally retained hashes before fitting.
This verifies content and declared provenance, not an independent RNG replay.
Single-category observations remain bindable even if model validation rejects them.
"""
function bind_panel(plan, id; directory, hashes)
    check_seal(plan)
    id in plan.ids || throw(ArgumentError("Unplanned dataset ID"))
    keys(hashes) == (:generation, :raw_truth, :truth, :observed) ||
        throw(ArgumentError("All four generation file hashes are required in declared order"))
    records = map(keys(hashes)) do name
        file = name === :raw_truth ? "raw-truth.json" : "$name.json"
        JSON3.read(checked_bytes(joinpath(directory, file), getproperty(hashes, name)))
    end
    generation, raw_truth, truth, observed = records
    generation.candidate_id == observed.candidate_id == truth.candidate_id == "independent_2d_raw_primary_01" &&
        Symbol(generation.mode) === plan.mode && generation.generator_sha256 == plan.generator_sha256 &&
        generation.status == "generated" && generation.response_datasets == 1 && generation.redraws == 0 ||
        throw(ArgumentError("Generation recipe/status does not match this cell"))
    seed_ok(x) = x isa Integer && !(x isa Bool) && x >= 0
    seed_ok(generation.score_seed) || throw(ArgumentError("Invalid response seed"))
    if plan.mode === :prior
        seed_ok(generation.truth_seed) && generation.truth_seed != generation.score_seed ||
            throw(ArgumentError("Prior truth and response seeds must be distinct"))
    elseif plan.mode === :recovery
        generation.condition == plan.condition && seed_ok(generation.person_seed) &&
            generation.person_seed != generation.score_seed || throw(ArgumentError("Recovery recipe mismatch"))
    end
    data = P.observation_data(observed)
    generation.observed_categories == sort(unique(data.score)) ||
        throw(ArgumentError("Generation receipt/category observations disagree"))
    ids = candidate_cells(data)
    ids == [(p,i,r) for p in P.PERSONS for i in ["I$j" for j in 1:5] for r in ["R$j" for j in 1:5]] &&
        truth.ordered_ids.person == data.person_levels && truth.ordered_ids.item == data.item_levels &&
        truth.ordered_ids.rater == data.rater_levels || throw(ArgumentError("Generator coordinate/cell order mismatch"))
    raw_truth.raw == truth.raw && raw_truth.raw_names == truth.raw_names && length(truth.raw) == length(truth.raw_names) == 128 &&
        length(unique(truth.raw_names)) == 128 && all(V._finite_number, truth.raw) ||
        throw(ArgumentError("Generating raw truth or coordinate names mismatch"))
    logs = reduce(vcat, permutedims.(Vector{Float64}.(truth.log_probabilities)))
    size(logs) == (1250,4) || throw(ArgumentError("Wrong truth probability dimensions"))
    B._mgmfrm_check_probability_rows(logs, "truth", 1e-8; log_probabilities=true)
    isapprox(sum(logs[n,data.category[n]] for n in 1:1250), truth.log_likelihood; atol=1e-8, rtol=1e-12) ||
        throw(ArgumentError("Truth likelihood and response rows disagree"))
    return seal((; id=String(id), plan_identity=plan.content_hash, hashes,
        generation, truth, observed, role=:preparation_only))
end

function checked_panel(plan, input)
    check_seal(plan); check_seal(input)
    input.plan_identity == plan.content_hash && input.id in plan.ids ||
        throw(ArgumentError("Input belongs to another plan"))
    return input
end

function read_fit(reference)
    bytes = checked_bytes(reference.path, reference.sha256)
    record = B._check_fit_cache_record(deserialize(IOBuffer(bytes)), reference.path)
    B._verify_fit_cache_record(record, reference.path)
    record.fit isa B.MGMFRMFit || throw(ArgumentError("Expected a raw-prior MGMFRMFit"))
    B._fit_warmup_diagnostics(record.fit)
    return record.fit
end

function check_fit(plan, input, fit::B.MGMFRMFit; seed, training_rows=collect(1:1250))
    checked_panel(plan, input)
    seed isa Integer && !(seed isa Bool) && seed >= 0 || throw(ArgumentError("Explicit fit seed required"))
    rows = collect(training_rows)
    !isempty(rows) && all(n -> n isa Integer && !(n isa Bool) && 1 <= n <= 1250, rows) &&
        issorted(rows) && length(unique(rows)) == length(rows) || throw(ArgumentError("Invalid training rows"))
    full = P.specification(input.observed; require_all_categories=false)
    spec = length(rows) == 1250 ? full : B._refit_training_spec(full, B._loo_refit_training_data(full.data, rows))
    expected = P.target(spec)
    B.design_identity(fit.design).value == B.design_identity(expected.design).value &&
        B._source_fixture_prior_values(fit.prior) == plan.prior ||
        throw(ArgumentError("Fit data/model/prior differs from the bound training target"))
    fit.backend === plan.backend && fit.sampler === :nuts &&
        fit.warmup == plan.controls.warmup && B._fit_draws_per_chain(fit) == plan.controls.ndraws &&
        length(fit.chain_acceptance_rate) == plan.controls.chains || throw(ArgumentError("Fit backend/layout mismatch"))
    all(k -> getproperty(fit.sampler_controls,k) == getproperty(plan.controls,k),
        (:chains,:ndraws,:warmup,:step_size,:target_accept,:max_depth,:init_jitter)) &&
        fit.sampler_controls.rng.replayable === true && fit.sampler_controls.rng.seed == seed ||
        throw(ArgumentError("Fit controls/seed differ from the reference"))
    warmup = B._fit_warmup_diagnostics(fit)
    length(warmup) == 4 && all(r -> r.coverage === :recorded && r.observed_iterations == 1000 &&
        r.expected_iterations == 1000,warmup) || throw(ArgumentError("Incomplete warmup record"))
    fit.diagnostic_surface.raw_parameter_names == expected.blueprint.parameter_names == input.truth.raw_names &&
        fit.diagnostic_surface.direct_parameter_names == expected.blueprint.constrained_parameter_names ||
        throw(ArgumentError("Fit coordinate names/order mismatch"))
    size(fit.draws) == (4000,128) && all(isfinite,fit.draws) && all(isfinite,fit.log_posterior) ||
        throw(ArgumentError("Incomplete or nonfinite retained draws"))
    direct = reduce(vcat, [permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(expected.design,collect(r)))
        for r in eachrow(fit.draws)])
    size(fit.direct_draws) == size(direct) && all(isapprox(a,b;atol=1e-12,rtol=1e-12)
        for (a,b) in zip(fit.direct_draws,direct)) ||
        throw(ArgumentError("Saved direct draws disagree with raw reconstruction"))
    full_target = length(rows) == 1250 ? expected : P.target(full)
    raw_truth = Float64.(input.truth.raw)
    truth_direct = B._mgmfrm_source_constrained_params_from_unconstrained(full_target.design,raw_truth)
    truth_logs = reduce(vcat,permutedims.(Vector{Float64}.(input.truth.log_probabilities)))
    isapprox(B._source_fixture_logprior(full_target,raw_truth),input.truth.log_prior;atol=1e-9,rtol=1e-12) &&
        all(isapprox(a,b;atol=1e-10,rtol=1e-12) for (a,b) in zip(
            mean_log_probabilities(full_target.design,permutedims(truth_direct)),truth_logs)) ||
        throw(ArgumentError("Raw truth and generator prior/probabilities disagree with the fitted target"))
    return (;target=expected, direct)
end

"""Recompute parameter and retained-sampler diagnostics, never trust saved flags."""
function qualification(fit, checked, values, names)
    diagnostic(x,n;fixed=Set{String}()) = B._candidate_mcmc_diagnostic_rows(x,n,4;
        split_chains=true,rhat_threshold=P.CRITERIA.rhat,ess_threshold=P.CRITERIA.ess,
        structurally_fixed_parameters=fixed)
    blueprint = checked.target.blueprint
    groups = (;raw=diagnostic(fit.draws,blueprint.parameter_names),
        model=diagnostic(checked.direct,blueprint.constrained_parameter_names;
            fixed=B._structurally_fixed_constrained_parameter_names(blueprint)),
        focal=diagnostic(values,names))
    complete = length(fit.sampler_stats) == 4000 && all(enumerate(fit.sampler_stats)) do (n,r)
        r.chain == fit.chain_ids[n] && r.iteration == fit.iterations[n] && r.is_adapt === false &&
            r.numerical_error isa Bool && r.n_steps isa Integer && !(r.n_steps isa Bool) && r.n_steps > 0 &&
            r.tree_depth isa Integer && !(r.tree_depth isa Bool) && r.tree_depth > 0 && V._finite_number(r.hamiltonian_energy)
    end
    sampler = complete ? B._generalized_candidate_sampler_rows(fit.log_posterior,fit.iterations,
        fit.chain_acceptance_rate,fit.sampler_stats,fit.sampler_controls,fit.backend) : NamedTuple[]
    q = V.qualify_diagnostics(groups,sampler;criteria=P.CRITERIA,telemetry_complete=complete)
    warmup = B._fit_warmup_diagnostics(fit)
    return (;q...,warmup,diagnostic_rows=groups)
end

function recovery_quantities(target, raw)
    focal = P.focal_draws(target.design,raw)
    keep = findall(i -> focal.roles[i] === :primary && focal.kinds[i] === :parameter,eachindex(focal.names))
    length(keep) == 59 || error("Primary parameter roster changed")
    return (;names=[focal.names[keep];target.blueprint.parameter_names[1:100]],
        roles=[fill(:primary,59);fill(:secondary,100)],kinds=fill(:parameter,159),
        draws=hcat(focal.draws[:,keep],raw[:,1:100]))
end

"""Prepare 59 primary parameters and all 100 person coordinates, with 90/95%
intervals. A historical fixed-truth replay remains an engineering result.
"""
function prepare_recovery(plan,input,reference)
    checked_panel(plan,input)
    plan.mode in (:fixed,:recovery) || throw(ArgumentError("Recovery must not replace joint-prior SBC"))
    fit = read_fit(reference)
    checked = check_fit(plan,input,fit;seed=reference.seed)
    quantities = recovery_quantities(checked.target,fit.draws)
    truth = recovery_quantities(checked.target,permutedims(Float64.(input.truth.raw)))
    precision = P.precision_rows(quantities)
    blocks = Dict(:primary=>1:59,:person=>60:159)
    score(level) = B._parameter_recovery_rows(quantities.names,blocks,quantities.draws,vec(truth.draws);
        interval=level,metadata=(;))
    main, secondary = score(.9), score(.95)
    rows = [begin
        a,b,p = main[j],secondary[j],precision[j]
        (;parameter=a.parameter,role=quantities.roles[j],truth=a.true_value,estimate=a.posterior_mean,
            error=a.bias,lower=a.posterior_lower,upper=a.posterior_upper,covered=a.covered,width=a.interval_width,
            posterior_sd=a.posterior_sd,mcse=p.mcse,local_precision_passed=p.local_precision_passed,
            interval95=(;lower=b.posterior_lower,upper=b.posterior_upper,covered=b.covered,width=b.interval_width))
    end for j in eachindex(main)]
    q = qualification(fit,checked,quantities.draws,quantities.names)
    precision_passed = all(p -> p.role === :secondary || p.local_precision_passed,precision)
    status = !q.qualified ? :diagnostic_warning : !precision_passed ? :mcse_unavailable : :prepared
    return seal((;id=input.id,plan_identity=plan.content_hash,kind=:recovery,status,input,
        reference,qualification=q,primary_precision_passed=precision_passed,rows,
        target_identity=plan.content_hash,diagnostic_flag=q.qualified ? :ok : :warning,
        scientific_acceptance=false))
end

function prepare_sbc(plan,input,reference;dependence,rank_rng::AbstractRNG)
    checked_panel(plan,input)
    plan.mode === :prior || throw(ArgumentError("SBC requires joint-prior generation"))
    V._check_dependence(dependence)
    fit = read_fit(reference)
    checked = check_fit(plan,input,fit;seed=reference.seed)
    quantities = sbc_quantities(checked.target,fit.draws;parameter_names=input.truth.raw_names)
    truth = sbc_quantities(checked.target,permutedims(Float64.(input.truth.raw));parameter_names=input.truth.raw_names)
    q = qualification(fit,checked,quantities.values,quantities.names)
    selected = sbc_rank_draws(checked.target,fit.draws;parameter_names=input.truth.raw_names,
        fit.chain_ids,fit.iterations)
    status = V._sbc_status(q,dependence)
    ranks = status === :rank_prepared ? [merge((;parameter=name),
        V.randomized_rank(truth.values[1,j],selected.values[:,j],rank_rng))
        for (j,name) in pairs(quantities.names)] : nothing
    return seal((;id=input.id,plan_identity=plan.content_hash,kind=:sbc,status,input,reference,
        qualification=q,dependence,ranks,names=quantities.names,truth=vec(truth.values),
        selected_draws=selected.values,selected_rows=selected.selected_rows,
        independence_verified=false,scientific_acceptance=false))
end

"""Bind the existing five-fold planner to one complete panel. Never redraw a split
to repair missing training support; preserve that failure under the original ID.
"""
function bind_folds(plan,input;seed)
    checked_panel(plan,input)
    plan.mode in (:fixed,:recovery) || throw(ArgumentError("CV is outside the SBC roster"))
    seed isa Integer && !(seed isa Bool) && seed >= 0 || throw(ArgumentError("Explicit split seed required"))
    data = P.observation_data(input.observed)
    folds = B.kfold_plan(data;k=5,group_by=nothing,shuffle=true,rng=MersenneTwister(seed))
    B.kfold_plan_diagnostics(data,folds;facets=:all).passed || throw(ArgumentError("Missing training facet support"))
    for f in folds.fold_rows, person in 1:50, dimension in 1:2
        any(n -> data.person[n] == person && P.Q[data.item[n],dimension],f.training_observations) ||
            throw(ArgumentError("Missing training person/dimension support"))
    end
    return seal((;plan_identity=plan.content_hash,input_identity=input.content_hash,seed,folds))
end

function checked_folds(plan,input,split)
    checked_panel(plan,input);check_seal(split)
    split.plan_identity == plan.content_hash && split.input_identity == input.content_hash ||
        throw(ArgumentError("Fold plan belongs to another input"))
    return split
end

"""Mean predictive log probabilities from the model's logits, in bounded batches.
Do not take log of rounded/underflowed probabilities, or drop posterior draws.
"""
function foreach_log_batch(visit,design,direct;batch_size=256)
    batch_size isa Integer && !(batch_size isa Bool) && batch_size > 0 && size(direct,1) > 0 ||
        throw(ArgumentError("Positive batch size and nonempty draws required"))
    # Heldout rows need not themselves cover every fitted item/dimension. The
    # bound training design establishes those coordinates, as in _refit_score_loglikelihood.
    B._check_mgmfrm_source_fixture_design(design,"core predictive preparation";require_q_observation_coverage=false)
    size(direct,2) == length(design.parameter_names) && all(isfinite,direct) ||
        throw(ArgumentError("Invalid direct predictive draws"))
    foreach(r -> B._mgmfrm_source_fixture_constraints(design,r),eachrow(direct))
    n = design.spec.data.n
    loading = B._mgmfrm_source_loading_index_matrix(design)
    logits = zeros(4)
    for first in 1:batch_size:size(direct,1)
        selected = first:min(first+batch_size-1,size(direct,1))
        logs = Array{Float64}(undef,length(selected),n,4)
        for (s,j) in enumerate(selected), row in 1:n
            B._mgmfrm_source_linear_predictors!(logits,design,@view(direct[j,:]),row,loading)
            all(isfinite,logits) || throw(ArgumentError("Nonfinite predictive logits"))
            logs[s,row,:] = logits .- B._logsumexp(logits)
        end
        visit(selected,logs)
    end
    return nothing
end

function mean_log_probabilities(design,direct;batch_size=256)
    total = fill(-Inf,design.spec.data.n,4)
    foreach_log_batch(design,direct;batch_size) do selected,logs
        average,count = B._mgmfrm_mean_predicted_probabilities(logs,1e-8;log_probabilities=true)
        for j in eachindex(total)
            total[j] = B._logsumexp([total[j],average[j]+log(count)])
        end
    end
    return total .- log(size(direct,1))
end

function prepare_fold(plan,input,split,fold,reference)
    checked_folds(plan,input,split)
    f = only(filter(r -> r.fold == fold,split.folds.fold_rows))
    fit = read_fit(reference)
    checked = check_fit(plan,input,fit;seed=reference.seed,training_rows=f.training_observations)
    quantities = recovery_quantities(checked.target,fit.draws)
    q = qualification(fit,checked,quantities.draws,quantities.names)
    score_design = B._loo_refit_score_design(P.observation_data(input.observed),fit.design,f.heldout_observations)
    logs = q.qualified ? mean_log_probabilities(score_design,checked.direct) : nothing
    error = if q.qualified
        data = P.observation_data(input.observed)
        truth = reduce(vcat,permutedims.(Vector{Float64}.(input.truth.log_probabilities)))
        weights = predictive_weights(data)[f.heldout_observations]
        state = loss_delta_setup(logs,truth[f.heldout_observations,:],
            data.category[f.heldout_observations],weights,size(checked.direct,1))
        foreach_log_batch(score_design,checked.direct) do selected,draws
            loss_delta_add!(state,draws,selected)
        end
        result = loss_delta_finish(state;fit.chain_ids,fit.iterations)
        blocks = predictive_blocks(score_design,checked.direct;fit.chain_ids,fit.iterations)
        resolution = predictive_resolution(blocks,truth[f.heldout_observations,:];
            categories=data.category[f.heldout_observations],weights)
        curvature = last(resolution.prefixes).curvature
        result = merge(result,(;curvature,resolution))
        # Keep compact aggregate evidence; the saved fit regenerates all influences.
        Base.structdiff(result,(;influence=nothing))
    else
        nothing
    end
    return seal((;id=input.id,fold,split_identity=split.content_hash,reference,qualification=q,
        heldout_observations=f.heldout_observations,status=q.qualified ? :prepared : :diagnostic_warning,
        log_probabilities=logs,heldout_provenance_verified=true,n_prediction_draws=size(fit.draws,1),
        monte_carlo_error=error,monte_carlo_precision_assessed=false,scientific_acceptance=false))
end

function fold_failure(plan,input,split,fold,status;detail)
    checked_folds(plan,input,split)
    fold in split.folds.folds && status in (:pre_fit_rejected,:fit_error,:scoring_error,:timeout,:interrupted) &&
        detail isa AbstractString && !isempty(strip(detail)) || throw(ArgumentError("Invalid fold failure"))
    return seal((;id=input.id,fold,split_identity=split.content_hash,status,detail=String(detail),
        log_probabilities=nothing,scientific_acceptance=false))
end

"""A complete score needs every planned heldout row from its bound training fit.
Missing/unqualified folds keep the dataset unresolved; no partial renormalization.
"""
function assemble_cv(plan,input,split,attempts;
        fold_independence=(;status=:unresolved,evidence="Independent fold streams not yet reviewed"))
    V._check_dependence(fold_independence)
    checked_folds(plan,input,split)
    length(unique(r.fold for r in attempts)) == length(attempts) || throw(ArgumentError("Duplicate primary fold"))
    all(r -> r.fold in split.folds.folds,attempts) || throw(ArgumentError("Unplanned fold"))
    lookup = Dict(r.fold=>r for r in attempts)
    logs = fill(NaN,1250,4)
    ledger = NamedTuple[]
    caches = Set{String}()
    for f in split.folds.fold_rows
        r = get(lookup,f.fold,nothing)
        status = r === nothing ? :missing_attempt : r.status
        if r !== nothing
            check_seal(r)
            r.id == input.id && r.split_identity == split.content_hash || throw(ArgumentError("Fold/input mismatch"))
            if status in (:prepared,:diagnostic_warning)
                r.heldout_observations == f.heldout_observations && r.heldout_provenance_verified === true &&
                    r.n_prediction_draws == 4000 && r.qualification.qualified === (status === :prepared) ||
                    throw(ArgumentError("Fold rows/diagnostics/provenance mismatch"))
                r.reference.sha256 in caches && throw(ArgumentError("Fit reused across folds"))
                push!(caches,r.reference.sha256)
                if status === :prepared
                    size(r.log_probabilities) == (length(f.heldout_observations),4) || throw(ArgumentError("Missing fold predictions"))
                    logs[f.heldout_observations,:] = r.log_probabilities
                else
                    r.log_probabilities === nothing || throw(ArgumentError("Unqualified fold supplied scores"))
                end
            else
                r == fold_failure(plan,input,split,f.fold,status;detail=r.detail) || throw(ArgumentError("Malformed fold failure"))
            end
        end
        push!(ledger,(;fold=f.fold,status))
    end
    complete = all(r -> r.status === :prepared,ledger)
    truth = reduce(vcat,permutedims.(Vector{Float64}.(input.truth.log_probabilities)))
    ids = candidate_cells(P.observation_data(input.observed))
    score = complete ? predictive_score(input.observed,logs,truth;prediction_ids=ids,truth_ids=ids) : nothing
    error = combine_fold_mcse(attempts,complete,fold_independence)
    return (;id=input.id,status=complete ? :assembled : :incomplete,planned_folds=5,
        usable_folds=count(r -> r.status === :prepared,ledger),ledger,score,monte_carlo_error=error,
        heldout_provenance_verified=complete,monte_carlo_precision_assessed=false,scientific_acceptance=false)
end

"""Record an observed primary failure without catching, retrying or replacing it."""
function failure(plan,id,status;detail,input=nothing)
    check_seal(plan)
    id in plan.ids && detail isa AbstractString && !isempty(strip(detail)) &&
        status in (:generation_error,:pre_fit_rejected,:fit_error,:scoring_error,:timeout,:interrupted,:missing_draws,:nonfinite_draws) ||
        throw(ArgumentError("Planned ID, supported failure status and detail required"))
    input === nothing && !(status in (:generation_error,:timeout,:interrupted)) &&
        throw(ArgumentError("Post-generation failures must retain the input"))
    input === nothing || (checked_panel(plan,input).id == id || throw(ArgumentError("Failure/input ID mismatch")))
    return seal((;id=String(id),plan_identity=plan.content_hash,kind=:failure,status,detail=String(detail),input,
        scientific_acceptance=false))
end

"""Run the existing input validator before sampling, preserving the bound panel
and its declared scale. A rejection is a planned failure, never a redraw request.
Passing preflight neither runs nor qualifies a fit.
"""
function input_preflight(plan,input;split=nothing,fold=nothing)
    checked_panel(plan,input)
    (split===nothing)===(fold===nothing) || throw(ArgumentError("Supply both split and fold, or neither"))
    data=P.observation_data(input.observed)
    rows=collect(1:data.n)
    if split!==nothing
        checked_folds(plan,input,split)
        fold isa Integer && !(fold isa Bool) && fold in split.folds.folds || throw(ArgumentError("Unplanned fold"))
        rows=only(filter(r -> r.fold==fold,split.folds.fold_rows)).training_observations
        data=B._loo_refit_training_data(data,rows)
    end
    report=B.validate_design(data)
    issues=[(;i.code,i.severity,i.message,i.context) for i in report.issues]
    detail="validate_design rejected before sampling: "*join((String(i.code) for i in report.issues if i.severity===:error),", ")
    rejected=report.passed ? nothing : split===nothing ?
        failure(plan,input.id,:pre_fit_rejected;detail,input) :
        fold_failure(plan,input,split,fold,:pre_fit_rejected;detail)
    return seal((;id=input.id,plan_identity=plan.content_hash,input_identity=input.content_hash,
        split_identity=split===nothing ? nothing : split.content_hash,fold,training_rows=rows,
        passed=report.passed,issues,declared_categories=copy(data.category_levels),
        observed_categories=sort(unique(data.score)),failure=rejected,
        posterior_propriety_assessed=false,new_sampler_runs=0,scientific_acceptance=false))
end

function attempt_ledger(plan,attempts)
    check_seal(plan)
    results = V._attempt_results([(;id,target_identity=plan.content_hash) for id in plan.ids],
        [(;r.id,target_identity=r.plan_identity,result=r) for r in attempts])
    generations,caches = Set{String}(),Set{String}()
    ledger = map(plan.ids) do id
        r = get(results,id,nothing)
        if r !== nothing
            check_seal(r)
            if r.input !== nothing
                checked_panel(plan,r.input).id == id || throw(ArgumentError("Attempt/input ID mismatch"))
                hash = r.input.hashes.generation
                hash in generations && throw(ArgumentError("Generating attempt reused under another primary ID"))
                push!(generations,hash)
            end
            if r.kind === :failure
                r == failure(plan,id,r.status;detail=r.detail,input=r.input) || throw(ArgumentError("Malformed failure"))
            else
                r.kind === (plan.mode === :prior ? :sbc : :recovery) || throw(ArgumentError("Wrong attempt kind"))
                r.qualification.criteria == plan.criteria &&
                    r.qualification.qualified === isempty(r.qualification.failures) ||
                    throw(ArgumentError("Attempt diagnostic qualification is inconsistent"))
                if r.kind === :recovery
                    status = !r.qualification.qualified ? :diagnostic_warning :
                        !r.primary_precision_passed ? :mcse_unavailable : :prepared
                    r.status === status || throw(ArgumentError("Recovery status disagrees with diagnostics/precision"))
                end
                r.reference.sha256 in caches && throw(ArgumentError("Saved fit reused under another primary ID"))
                push!(caches,r.reference.sha256)
            end
        end
        (;id,status=r === nothing ? :missing_attempt : r.status,result=r)
    end
    return ledger
end

function summarize_recovery(plan,attempts;parameter,interval=.9)
    plan.mode in (:fixed,:recovery) && interval in (.9,.95) || throw(ArgumentError("Wrong recovery cell or interval"))
    ledger = attempt_ledger(plan,attempts)
    prepared = NamedTuple[]
    for l in ledger
        r = l.result
        r === nothing && continue
        if r.kind === :recovery
            row = only(filter(x -> x.parameter == parameter,r.rows))
            interval == .95 && (row=merge(row,row.interval95))
            status = r.status === :prepared && (row.mcse.mcse_status !== :available || !row.local_precision_passed) ?
                :mcse_unavailable : r.status
            result = (;status,target_identity=plan.content_hash,r.diagnostic_flag,rows=[row])
        else
            result = (;r.status)
        end
        push!(prepared,(;id=l.id,target_identity=plan.content_hash,result))
    end
    summary = V.summarize_attempts([(;id,target_identity=plan.content_hash) for id in plan.ids],prepared;parameter)
    return (;summary...,interval,mode=plan.mode,condition=plan.condition,
        status=summary.unresolved > 0 ? :incomplete : :prepared,
        selection_caveat=:continuous_summaries_condition_on_qualified_attempts)
end

function summarize_sbc(plan,attempts;dataset_independence,alpha=.05)
    plan.mode === :prior || throw(ArgumentError("SBC roster required"))
    V._check_dependence(dataset_independence)
    ledger = attempt_ledger(plan,attempts)
    prepared = [l.result for l in ledger if l.result !== nothing && l.result.kind === :sbc]
    isempty(prepared) && return (;planned=length(plan.ids),usable=0,ledger,cdfs=nothing,
        status=:no_prepared_quantities,interpretation=:exploratory_error_detection,
        calibration_verified=false,scientific_acceptance=false)
    names = first(prepared).names
    length(names) == length(unique(names)) == 138 || throw(ArgumentError("Wrong SBC quantity family"))
    ranks = [Union{Missing,Int}[missing for _ in plan.ids] for _ in names]
    for (i,l) in pairs(ledger)
        r = l.result
        r === nothing || r.kind === :failure || begin
            r.names == names && r.status === V._sbc_status(r.qualification,r.dependence) ||
                throw(ArgumentError("Inconsistent SBC status or quantity family"))
            if r.status === :rank_prepared
                for j in eachindex(names)
                    rank = r.ranks[j]
                    lower = count(<(r.truth[j]),r.selected_draws[:,j])
                    ties = count(==(r.truth[j]),r.selected_draws[:,j])
                    rank.parameter == names[j] && rank.n_draws == 4 && rank.lower == lower && rank.ties == ties &&
                        rank.upper == lower+ties && rank.rank isa Integer && !(rank.rank isa Bool) &&
                        lower <= rank.rank <= lower+ties || throw(ArgumentError("Rank/truth/draw mismatch"))
                    ranks[j][i] = rank.rank
                end
            else
                r.ranks === nothing || throw(ArgumentError("Unqualified ranks must be absent"))
            end
        end
    end
    cdfs = [begin
        cdf = V.rank_cdf(ranks[j];n_draws=4,n_quantities=138,alpha)
        if dataset_independence.status === :unresolved
            cdf=merge(cdf,(;epsilon=missing,conditional_screen=:assumptions_unresolved,
                rows=[merge(r,(;band_lower=missing,band_upper=missing,resolved_departure=missing)) for r in cdf.rows]))
        end
        (;parameter=names[j],cdf)
    end for j in eachindex(names)]
    return (;planned=length(plan.ids),usable=count(l -> l.status === :rank_prepared,ledger),ledger,cdfs,
        dataset_independence,interpretation=:exploratory_error_detection,
        independence_verified=false,calibration_verified=false,scientific_acceptance=false)
end

function candidate_design(design)
    design.spec.q_matrix == P.Q || throw(ArgumentError("Wrong candidate Q matrix"))
    return candidate_cells(design.spec.data)
end

function aligned_rows(ids, expected)
    keys = [Tuple(id) for id in ids]
    length(keys) == length(expected) && length(unique(keys)) == length(keys) &&
        Set(keys) == Set(expected) ||
        throw(ArgumentError("IDs must cover every declared cell exactly once"))
    lookup = Dict(id => n for (n, id) in enumerate(keys))
    return [lookup[id] for id in expected]
end

"""Descriptive full-panel scoring of normalized log probabilities with explicit
cell IDs. This checks coverage and alignment, not whether predictions came from
held-out fits. No fold provenance, diagnostics, MCSE or study acceptance is inferred.
"""
function predictive_score(observed, predicted, truth; prediction_ids, truth_ids)
    data = P.observation_data(observed)
    expected = candidate_cells(data)
    pi = aligned_rows(prediction_ids, expected)
    ti = aligned_rows(truth_ids, expected)
    ndims(predicted) in (2, 3) && size(predicted, ndims(predicted)-1) == 1250 &&
        size(predicted, ndims(predicted)) == 4 && size(truth) == (1250, 4) ||
        throw(ArgumentError("Expected full-panel log probabilities with four categories"))
    ordered = ndims(predicted) == 2 ? predicted[pi, :] : predicted[:, pi, :]
    mean_logs, n_draws = B._mgmfrm_mean_predicted_probabilities(ordered, 1e-8; log_probabilities=true)
    score = B.mgmfrm_predictive_recovery_score(mean_logs, truth[ti, :];
        category_levels=1:4, log_probabilities=true)
    rows = map(1:1250) do n
        r = score.rows[n]
        (; person=expected[n][1], item=expected[n][2], rater=expected[n][3],
            dimension=findfirst(P.Q[data.item[n], :]),
            negative_log_predictive_probability=-mean_logs[n, data.category[n]],
            squared_category_probability_error=4r.root_mean_squared_category_probability_error^2,
            squared_expected_score_error=r.expected_score_error^2,
            log_score_regret=r.log_score_regret)
    end
    metrics = (:negative_log_predictive_probability, :squared_category_probability_error,
        :squared_expected_score_error, :log_score_regret)
    averages(selected) = NamedTuple{metrics}(Tuple(mean(getproperty(r, m) for r in selected) for m in metrics))
    groups = [begin
        selected = filter(r -> r.person == person && r.dimension == d, rows)
        (; person, dimension=d, n_observations=length(selected), averages(selected)...)
    end for person in P.PERSONS for d in 1:2]
    return (; rows, person_dimension_rows=groups, summary=averages(groups),
        n_observations=1250, n_prediction_draws=n_draws,
        weighting=:equal_person_equal_dimension_after_row_scoring,
        heldout_provenance_verified=false, diagnostic_qualification_applied=false,
        scientific_acceptance=false)
end

"""The 138 proposed SBC quantities, including the likelihood of the supplied
observed data. Matching these quantities does not bind a fit to joint-prior
generation or qualify posterior draws; the study-level connection remains pending.
"""
function sbc_quantities(target, raw::AbstractMatrix; parameter_names)
    candidate_design(target.design)
    parameter_names == target.blueprint.parameter_names ||
        throw(ArgumentError("Raw coordinate names/order mismatch"))
    size(raw, 1) > 0 && size(raw, 2) == 128 &&
        all(x -> x isa Real && !(x isa Bool) && isfinite(x), raw) ||
        throw(ArgumentError("Expected nonempty finite raw draws with 128 coordinates"))
    names = [String.(parameter_names); "severity[R5]"; "log_gamma[R5]";
        ["last_step[I$i]" for i in 1:5];
        ["theta_product[$p,D1,D2]" for p in ("P1", "P2")]; "observed_log_likelihood"]
    columns = [-vec(sum(raw[:, 101:104]; dims=2)), -vec(sum(raw[:, 115:118]; dims=2))]
    append!(columns, [-vec(sum(raw[:, (117+2i):(118+2i)]; dims=2)) for i in 1:5])
    for person in ("P1", "P2")
        p = findfirst(==(person), P.PERSONS)
        push!(columns, raw[:, 2p-1] .* raw[:, 2p])
    end
    push!(columns, [B._source_fixture_loglikelihood(target, collect(row)) for row in eachrow(raw)])
    values = hcat(raw, columns...)
    all(isfinite, values) || throw(ArgumentError("Nonfinite SBC quantity; preserve the failed slot"))
    return (; names, values)
end

"""Select exactly one predeclared retained iteration from each of four chains.
All raw rows and all chain/iteration IDs are checked. Selection uses no quantity
values, and does not assert independence or convergence. Keep the complete fit.
"""
function sbc_rank_draws(target, raw::AbstractMatrix; parameter_names, chain_ids, iterations,
        retained_iteration=1000)
    size(raw, 2) == 128 && all(x -> x isa Real && !(x isa Bool) && isfinite(x), raw) ||
        throw(ArgumentError("Every retained raw coordinate must be finite"))
    layout = V.chain_order(chain_ids, iterations, size(raw, 1))
    layout.chains == 4 || throw(ArgumentError("This proposal requires exactly four chains"))
    retained_iteration isa Integer && !(retained_iteration isa Bool) &&
        retained_iteration == size(raw, 1) ÷ 4 ||
        throw(ArgumentError("The predeclared iteration must equal the fixed retained chain length"))
    selected = [n for n in layout.order if iterations[n] == retained_iteration]
    q = sbc_quantities(target, raw[selected, :]; parameter_names)
    return (; q..., selected_rows=selected, chain_ids=chain_ids[selected],
        iterations=iterations[selected], retained_iteration, n_rank_draws=4,
        selection=:fixed_terminal_draw_per_chain, independence_verified=false,
        diagnostic_qualification_applied=false, joint_prior_binding_verified=false,
        scientific_acceptance=false)
end


include("mgmfrm_core_summaries.jl")
include("mgmfrm_core_cv_review.jl")

end
