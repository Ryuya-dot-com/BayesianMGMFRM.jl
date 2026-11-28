# CR6: Modernized v0.2 Joint-Prior SBC Harness for Isometric MRCMLTarget and
# ScaleIdentifiedMGMFRM.Target (Modrak et al. 2023 data-dependent test quantities
# + unconditional full-denominator failure & exclusion retention).

const V02_SBC_PLAN = "bayesianmgmfrm.v02_sbc_plan.v1"
const V02_SBC_DATASET = "bayesianmgmfrm.v02_sbc_dataset.v1"
const V02_SBC_REVIEW = "bayesianmgmfrm.v02_sbc_rank_review.v1"
const V02_SBC_SUMMARY = "bayesianmgmfrm.v02_sbc_summary.v1"

const _V02Target = Union{B.AdditiveFacets.MRCMLTarget, B.ScaleIdentifiedMGMFRM.Target}

_v02_target_kind(::B.AdditiveFacets.MRCMLTarget) = :mrcml_target
_v02_target_kind(::B.ScaleIdentifiedMGMFRM.Target) = :scale_identified_mgmfrm

_v02_target_record(t::B.AdditiveFacets.MRCMLTarget) = B.AdditiveFacets.record(t)
_v02_target_record(t::B.ScaleIdentifiedMGMFRM.Target) = B.ScaleIdentifiedMGMFRM.target_record(t)

_v02_target_identity(t::B.AdditiveFacets.MRCMLTarget) = B._cache_hash(B.AdditiveFacets.record(t))
_v02_target_identity(t::B.ScaleIdentifiedMGMFRM.Target) = B.ScaleIdentifiedMGMFRM.target_identity(t)

function _v02_restore_target(kind::Symbol, rec::NamedTuple)
    kind === :mrcml_target && return B.AdditiveFacets.restore_mrcml(rec)
    kind === :scale_identified_mgmfrm && return B.ScaleIdentifiedMGMFRM.restore_target(rec)
    throw(ArgumentError("unsupported v0.2 SBC target kind: $(repr(kind))"))
end

function _v02_model_names(t::B.AdditiveFacets.MRCMLTarget)
    return B.AdditiveFacets.names(t, :model), copy(t.operator.fixed_model_names)
end
function _v02_model_names(t::B.ScaleIdentifiedMGMFRM.Target)
    return copy(t.model_names), copy(t.fixed_model_names)
end

function _v02_model_draws(t::B.AdditiveFacets.MRCMLTarget, draws::AbstractMatrix{<:Real})
    return B.AdditiveFacets.model_draws(t, draws)
end
function _v02_model_draws(t::B.ScaleIdentifiedMGMFRM.Target, draws::AbstractMatrix{<:Real})
    return B.ScaleIdentifiedMGMFRM.model_draws(t, draws)
end

function _v02_loglikelihood(t::B.AdditiveFacets.MRCMLTarget, q::AbstractVector{<:Real})
    return sum(B.AdditiveFacets.pointwise(t, q))
end
function _v02_loglikelihood(t::B.ScaleIdentifiedMGMFRM.Target, q::AbstractVector{<:Real})
    return B.ScaleIdentifiedMGMFRM.loglikelihood(t, q)
end

function _v02_logposterior(t::B.AdditiveFacets.MRCMLTarget, q::AbstractVector{<:Real})
    return B.LogDensityProblems.logdensity(t, q)
end
function _v02_logposterior(t::B.ScaleIdentifiedMGMFRM.Target, q::AbstractVector{<:Real})
    return B.LogDensityProblems.logdensity(t, q)
end

function _v02_resolve_sampling_chart(target::B.AdditiveFacets.MRCMLTarget, sampler::NamedTuple)
    mo = get(sampler, :mean_orthogonalization, :auto)
    require(mo in (:auto, :none), "sampler.mean_orthogonalization must be :auto or :none; got $(repr(mo))")
    eff = (mo === :auto && B.AdditiveFacets._maybe_mrcml_givens_target(target) !== nothing) ?
        :givens_mean_orthogonal : :raw
    return (;
        kind = :mrcml_target,
        mean_orthogonalization = mo,
        sampling_chart = eff,
    )
end

function _v02_resolve_sampling_chart(target::B.ScaleIdentifiedMGMFRM.Target, sampler::NamedTuple)
    sc = get(sampler, :sampling_coordinates, :orthogonal_decoupled)
    require(sc in (:orthogonal_decoupled, :raw),
        "sampler.sampling_coordinates must be :orthogonal_decoupled or :raw; got $(repr(sc))")
    pc = get(sampler, :person_coordinates, :noncentered)
    st = B.ScaleIdentifiedMGMFRM.SamplingTarget(target; person_coordinates = pc)
    use_decoupled = (sc === :orthogonal_decoupled) && (st.use_loc || st.use_anc || any(st.centered_dims))
    return (;
        kind = :scale_identified_mgmfrm,
        sampling_coordinates = use_decoupled ? :orthogonal_decoupled : :raw,
        centered_dims = use_decoupled ? Tuple(st.centered_dims) : Tuple(falses(target.D)),
    )
end

function _v02_check_fit_sampling_chart(study, fit_obj)
    require(hasproperty(study, :sampling_chart),
        "SBC study plan is missing a sealed effective sampling_chart")
    planned = study.sampling_chart
    prod = fit_obj.record.producer
    if study.target_kind === :mrcml_target
        require(hasproperty(prod, :sampling_chart),
            "fitted AdditiveFacets.Fit producer does not record sampling_chart")
        actual = prod.sampling_chart
        require(actual === planned.sampling_chart,
            "fitted sampling_chart ($(repr(actual))) does not match planned SBC sampling_chart ($(repr(planned.sampling_chart)))")
    else
        require(hasproperty(prod, :sampling_coordinates) && hasproperty(prod, :centered_dims),
            "fitted ScaleIdentifiedMGMFRM.Fit producer does not record sampling_coordinates and centered_dims")
        actual_sc = prod.sampling_coordinates
        actual_cd = Tuple(Bool.(prod.centered_dims))
        planned_cd = Tuple(Bool.(planned.centered_dims))
        require(actual_sc === planned.sampling_coordinates && actual_cd == planned_cd,
            "fitted MGMFRM sampling chart (sampling_coordinates=$(repr(actual_sc)), centered_dims=$(repr(actual_cd))) does not match planned SBC chart (sampling_coordinates=$(repr(planned.sampling_coordinates)), centered_dims=$(repr(planned_cd)))")
    end
    return nothing
end

function _check_v02_sbc_plan(study)
    B._prediction_check_seal(study, V02_SBC_PLAN)
    return study
end

"""
    prepare_sbc(target::Union{AdditiveFacets.MRCMLTarget, ScaleIdentifiedMGMFRM.Target};
                jobs, parameters, sampler, rank_settings, provenance=nothing)

Prepare a fixed joint-prior simulation-based calibration (SBC) plan for either
an isometric Helmert `MRCMLTarget` or a `ScaleIdentifiedMGMFRM.Target`.
Always appends the data-dependent test quantities `"joint_log_likelihood"` and
`"joint_log_posterior"` (Modrák et al. 2023) to `parameters`.
Performs no simulation or MCMC sampling.
"""
function prepare_sbc(target::_V02Target;
        jobs,
        parameters,
        sampler::NamedTuple,
        rank_settings::NamedTuple,
        gates::NamedTuple = (; max_rhat = 1.01, min_ess = 400.0, min_bfmi = 0.30),
        provenance::Union{Nothing, NamedTuple} = nothing)
    roster = Tuple(jobs)
    require(!isempty(roster), "declare the full SBC dataset roster")
    ids = String[]
    seeds = Int[]
    for job in roster
        require(Set(keys(job)) == Set((:dataset_id, :parameter_seed, :response_seed, :fit_seed)),
            "SBC job needs dataset_id/parameter_seed/response_seed/fit_seed")
        did = String(job.dataset_id)
        require(!isempty(strip(did)), "SBC dataset_id must be nonempty")
        push!(ids, did)
        for s in (job.parameter_seed, job.response_seed, job.fit_seed)
            require(s isa Integer && !(s isa Bool) && 0 <= s <= typemax(Int), "invalid SBC seed")
            push!(seeds, Int(s))
        end
    end
    require(length(unique(ids)) == length(ids), "duplicate dataset_id in SBC plan")
    require(length(unique(seeds)) == length(seeds), "reused seed in SBC independent-stream plan")

    require(haskey(sampler, :chains) && haskey(sampler, :warmup) && haskey(sampler, :ndraws),
        "sampler declaration must include chains, warmup, and ndraws")
    require(sampler.chains isa Integer && sampler.chains >= 2 &&
        sampler.warmup isa Integer && sampler.warmup >= 1 &&
        sampler.ndraws isa Integer && sampler.ndraws >= 1,
        "invalid sampler chains/warmup/ndraws")

    require(Set(keys(rank_settings)) == Set((:iterations, :dependence_policy)),
        "rank_settings must declare iterations and dependence_policy")
    selected = Tuple(Int.(rank_settings.iterations))
    require(!isempty(selected) && all(i -> 1 <= i <= sampler.ndraws, selected) &&
        issorted(selected) && length(unique(selected)) == length(selected),
        "invalid retained rank iterations")
    require(rank_settings.dependence_policy isa AbstractString &&
        !isempty(strip(rank_settings.dependence_policy)),
        "declare a nonblank posterior-dependence policy")

    all_mod_names, fixed_mod_names = _v02_model_names(target)
    mod_set = Set(all_mod_names)
    focal = Tuple(String.(parameters))
    require(!isempty(focal) && length(unique(focal)) == length(focal),
        "declare at least one unique focal parameter")
    for p in focal
        require(p in mod_set, "unknown model parameter in SBC plan: $(repr(p))")
        require(!(p in fixed_mod_names), "structurally fixed parameter cannot be an SBC rank quantity: $(repr(p))")
    end

    require(Set(keys(gates)) == Set((:max_rhat, :min_ess, :min_bfmi)),
        "gates must declare max_rhat, min_ess, and min_bfmi")
    require(gates.max_rhat isa Real && !(gates.max_rhat isa Bool) && isfinite(gates.max_rhat) && gates.max_rhat > 1.0 &&
        gates.min_ess isa Real && !(gates.min_ess isa Bool) && isfinite(gates.min_ess) && gates.min_ess > 0.0 &&
        gates.min_bfmi isa Real && !(gates.min_bfmi isa Bool) && isfinite(gates.min_bfmi) && 0.0 < gates.min_bfmi < 1.0,
        "invalid SBC qualification gate thresholds")
    sealed_gates = (; max_rhat = Float64(gates.max_rhat),
        min_ess = Float64(gates.min_ess), min_bfmi = Float64(gates.min_bfmi))
    sampling_chart = _v02_resolve_sampling_chart(target, sampler)

    test_quantities = (focal..., "joint_log_likelihood", "joint_log_posterior")
    body = (;
        schema = V02_SBC_PLAN,
        mode = :joint_prior_sbc,
        target_kind = _v02_target_kind(target),
        target_identity = _v02_target_identity(target),
        target_record = _v02_target_record(target),
        jobs = Tuple((; dataset_id = String(j.dataset_id),
            parameter_seed = Int(j.parameter_seed),
            response_seed = Int(j.response_seed),
            fit_seed = Int(j.fit_seed)) for j in roster),
        parameters = focal,
        test_quantities,
        sampler = deepcopy(sampler),
        sampling_chart,
        gates = sealed_gates,
        rank_settings = (; iterations = selected,
            dependence_policy = String(strip(String(rank_settings.dependence_policy)))),
        provenance = provenance === nothing ? (;) : deepcopy(provenance),
        denominator_policy = :retain_all_planned_jobs_unconditionally,
        sbc_performed = false,
    )
    return B._prediction_seal(body)
end

"""
    generate_sbc_dataset(study, dataset_id)

Deterministically draw a full joint prior vector `q_truth` using `job.parameter_seed`
and simulate synthetic responses using `job.response_seed` for one planned v0.2 SBC job,
retaining the exact declared model structure, levels, category supports, and prior.
Returns a sealed dataset record with `target_sim` and exact truth test quantities
(including `joint_log_likelihood` and `joint_log_posterior`).
"""
function generate_sbc_dataset(study, dataset_id)
    _check_v02_sbc_plan(study)
    did = String(dataset_id)
    idx = findfirst(j -> j.dataset_id == did, study.jobs)
    require(idx !== nothing, "unplanned SBC dataset: $(repr(did))")
    job = study.jobs[idx]
    t_base = _v02_restore_target(study.target_kind, study.target_record)

    q_truth, t_sim = if study.target_kind === :mrcml_target
        qt = B.AdditiveFacets.prior_draw(t_base; seed = job.parameter_seed)
        sim = B.AdditiveFacets.simulate(t_base; seed = job.response_seed, q = qt)
        rec_sim = deepcopy(study.target_record)
        rec_sim.table[rec_sim.columns.score] = copy(sim.simulated[rec_sim.columns.score])
        rec_sim = merge(rec_sim, (; category = copy(sim.category)))
        (qt, B.AdditiveFacets.restore_mrcml(rec_sim))
    else
        qt = B.ScaleIdentifiedMGMFRM.prior_draw(t_base; seed = job.parameter_seed)
        sim = B.ScaleIdentifiedMGMFRM.simulate(t_base; seed = job.response_seed, q = qt)
        (qt, sim.target)
    end

    md = _v02_model_draws(t_sim, reshape(q_truth, 1, :))
    col_map = Dict(nm => j for (j, nm) in enumerate(md.names))
    truth_vals = Float64[md.values[1, col_map[nm]] for nm in study.parameters]
    ll_truth = Float64(_v02_loglikelihood(t_sim, q_truth))
    lp_truth = Float64(_v02_logposterior(t_sim, q_truth))
    push!(truth_vals, ll_truth, lp_truth)
    require(all(isfinite, truth_vals), "nonfinite truth SBC test quantity for dataset $did")

    truth_map = NamedTuple{Tuple(Symbol.(study.test_quantities))}(Tuple(truth_vals))
    body = (;
        schema = V02_SBC_DATASET,
        study_hash = study.content_hash,
        dataset_id = did,
        target_kind = study.target_kind,
        parameter_seed = job.parameter_seed,
        response_seed = job.response_seed,
        fit_seed = job.fit_seed,
        q_truth = copy(q_truth),
        truth_quantities = Tuple((; quantity = nm, value = val) for (nm, val) in zip(study.test_quantities, truth_vals)),
        truth_by_quantity = truth_map,
        target_sim_identity = _v02_target_identity(t_sim),
        target_sim_record = _v02_target_record(t_sim),
    )
    return merge(B._prediction_seal(body), (; target_sim = t_sim))
end

"""
    review_sbc_fit(study, dataset, fit_obj; posterior_dependence,
                   max_rhat=1.01, min_ess=400.0, min_bfmi=0.30)

Score one fitted v0.2 SBC dataset (`AdditiveFacets.Fit` for `MRCMLTarget` or
`ScaleIdentifiedMGMFRM.Fit`) against its sealed truth, computing whole-fit
qualification, test-quantity diagnostics (including `joint_log_likelihood` and
`joint_log_posterior`), and exact tie-aware rank intervals without random tie breaking.
"""
function review_sbc_fit(study, dataset, fit_obj::Union{B.AdditiveFacets.Fit, B.ScaleIdentifiedMGMFRM.Fit};
        posterior_dependence::NamedTuple,
        max_rhat::Union{Nothing, Real} = nothing,
        min_ess::Union{Nothing, Real} = nothing,
        min_bfmi::Union{Nothing, Real} = nothing)
    _check_v02_sbc_plan(study)
    ds_body = Base.structdiff(dataset, (; target_sim = nothing))
    B._prediction_check_seal(ds_body, V02_SBC_DATASET)
    require(dataset.study_hash == study.content_hash, "SBC dataset belongs to a different study")
    checkdependence(posterior_dependence)

    plan_gates = hasproperty(study, :gates) ? study.gates : (; max_rhat = 1.01, min_ess = 400.0, min_bfmi = 0.30)
    eff_rhat = max_rhat === nothing ? plan_gates.max_rhat : Float64(max_rhat)
    eff_ess  = min_ess === nothing  ? plan_gates.min_ess  : Float64(min_ess)
    eff_bfmi = min_bfmi === nothing ? plan_gates.min_bfmi : Float64(min_bfmi)
    require(eff_rhat == plan_gates.max_rhat && eff_ess == plan_gates.min_ess && eff_bfmi == plan_gates.min_bfmi,
        "SBC review diagnostic thresholds ($(eff_rhat), $(eff_ess), $(eff_bfmi)) must match sealed study.gates ($(plan_gates.max_rhat), $(plan_gates.min_ess), $(plan_gates.min_bfmi))")

    t_fit, q_rep, raw_draws, chain_ids, iterations, fit_hash = if study.target_kind === :mrcml_target
        require(fit_obj isa B.AdditiveFacets.Fit, "expected AdditiveFacets.Fit for MRCMLTarget SBC study")
        tf = B.AdditiveFacets.checked(fit_obj; full = true)
        require(tf isa B.AdditiveFacets.MRCMLTarget, "expected fitted MRCMLTarget")
        qr = B.qualify(fit_obj; max_rhat = eff_rhat, min_ess = eff_ess, min_bfmi = eff_bfmi)
        run = fit_obj.record.run
        (tf, qr, run.draws, run.chain_ids, run.iterations, String(fit_obj.record.content_hash))
    else
        require(fit_obj isa B.ScaleIdentifiedMGMFRM.Fit, "expected ScaleIdentifiedMGMFRM.Fit for MGMFRM SBC study")
        tf = B.ScaleIdentifiedMGMFRM.checked(fit_obj; full = true)
        qr = B.qualify(fit_obj; max_rhat = eff_rhat, min_ess = eff_ess, min_bfmi = eff_bfmi)
        run = fit_obj.record.run
        (tf, qr, run.draws, run.chain_ids, run.iterations, String(fit_obj.record.content_hash))
    end

    require(_v02_target_identity(t_fit) == dataset.target_sim_identity,
        "fitted target does not match the simulated SBC dataset target")
    ctrl = fit_obj.record.run.controls
    n_chains = Int(ctrl.chains)
    n_warmup = Int(ctrl.warmup)
    n_draws_pc = Int(ctrl.ndraws)
    require(n_chains == study.sampler.chains &&
        n_warmup == study.sampler.warmup &&
        n_draws_pc == study.sampler.ndraws,
        "fitted chains/warmup/ndraws ($(n_chains)/$(n_warmup)/$(n_draws_pc)) differs from declared SBC sampler plan ($(study.sampler.chains)/$(study.sampler.warmup)/$(study.sampler.ndraws))")
    fit_seed_used = hasproperty(ctrl, :rng) && hasproperty(ctrl.rng, :seed) ? ctrl.rng.seed : nothing
    require(fit_seed_used == dataset.fit_seed,
        "fitted RNG seed ($(repr(fit_seed_used))) does not match planned dataset.fit_seed ($(dataset.fit_seed))")
    _v02_check_fit_sampling_chart(study, fit_obj)

    selected = findall(in(study.rank_settings.iterations), iterations)
    L_sel = Base.checked_mul(n_chains, length(study.rank_settings.iterations))
    require(length(selected) == L_sel, "selected SBC rank draws do not match rank_settings")

    md = _v02_model_draws(t_fit, raw_draws)
    col_map = Dict(nm => j for (j, nm) in enumerate(md.names))
    S = size(raw_draws, 1)
    T_q = length(study.test_quantities)
    vals = Matrix{Float64}(undef, S, T_q)
    for (j, nm) in enumerate(study.parameters)
        vals[:, j] .= view(md.values, :, col_map[nm])
    end
    idx_ll = length(study.parameters) + 1
    idx_lp = length(study.parameters) + 2
    for s in 1:S
        qv = view(raw_draws, s, :)
        vals[s, idx_ll] = Float64(_v02_loglikelihood(t_fit, qv))
        vals[s, idx_lp] = Float64(_v02_logposterior(t_fit, qv))
    end
    require(all(isfinite, vals), "nonfinite posterior SBC test quantity")

    q_diags = B._candidate_mcmc_diagnostic_rows(
        vals, collect(study.test_quantities), n_chains;
        parameter_space = :sbc_test_quantity,
        split_chains = true,
        rhat_threshold = eff_rhat,
        ess_threshold = eff_ess,
    )

    ranks = Tuple(begin
        tq = dataset.truth_quantities[j]
        merge((; quantity = tq.quantity), rank_interval(tq.value, view(vals, selected, j)))
    end for j in 1:T_q)

    exclusions = Symbol[]
    q_rep.qualified || push!(exclusions, :fit_not_qualified)
    all(d -> d.flag === :ok, q_diags) || push!(exclusions, :test_quantity_diagnostics)
    posterior_dependence.status === :declared_independent || push!(exclusions, :posterior_dependence)
    any(r -> r.ties > 0, ranks) && push!(exclusions, :ties)

    body = (;
        schema = V02_SBC_REVIEW,
        study_hash = study.content_hash,
        dataset_hash = dataset.content_hash,
        dataset_id = dataset.dataset_id,
        fit_content_hash = fit_hash,
        qualified = Bool(q_rep.qualified),
        max_rhat = Float64(q_rep.max_rhat),
        min_bulk_ess = Float64(q_rep.min_bulk_ess),
        min_tail_ess = Float64(q_rep.min_tail_ess),
        n_divergences = Int(q_rep.n_divergences),
        n_max_treedepth = Int(q_rep.n_max_treedepth),
        rank_settings = study.rank_settings,
        selected_rows = Tuple(selected),
        chain_ids = Tuple(Int.(chain_ids[selected])),
        iterations = Tuple(Int.(iterations[selected])),
        quantity_diagnostics = Tuple(q_diags),
        ranks,
        posterior_dependence = deepcopy(posterior_dependence),
        exclusions = Tuple(exclusions),
        rank_eligible = isempty(exclusions),
    )
    return B._prediction_seal(body)
end

"""
    summarize_sbc(study, outcomes::AbstractVector; alpha=0.05, dataset_independence)

Aggregate a v0.2 SBC study across ALL planned jobs in `study.jobs`, unconditionally
retaining failed, excluded, and missing jobs in the full denominator `N = length(study.jobs)`.
Each element of `outcomes` may be either a sealed `review_sbc_fit` result or a failure record
`(; dataset_id, status = :fit_failed, reason = "...")`.
Computes exact missing-rank bounds `[c/N, (c+u)/N]` and Bonferroni-DKW envelopes across all
focal parameters plus `joint_log_likelihood` and `joint_log_posterior`.
"""
function summarize_sbc(study, outcomes::AbstractVector;
        alpha::Real = 0.05,
        dataset_independence::NamedTuple)
    _check_v02_sbc_plan(study)
    require(!(alpha isa Bool) && isfinite(alpha) && 0 < alpha < 1, "alpha must lie strictly between 0 and 1")
    checkdependence(dataset_independence)

    by_id = Dict{String, Any}()
    seen_fits = Set{String}()
    for item in outcomes
        require(item isa NamedTuple && haskey(item, :dataset_id), "each SBC outcome must be a NamedTuple with dataset_id")
        did = String(item.dataset_id)
        require(!haskey(by_id, did), "duplicate SBC outcome for dataset_id: $(repr(did))")
        if get(item, :schema, nothing) == V02_SBC_REVIEW
            B._prediction_check_seal(item, V02_SBC_REVIEW)
            require(item.study_hash == study.content_hash, "SBC review belongs to a different study")
            require(!(item.fit_content_hash in seen_fits), "reused fit_content_hash across SBC datasets")
            push!(seen_fits, item.fit_content_hash)
        else
            require(get(item, :status, nothing) === :fit_failed &&
                haskey(item, :reason) && item.reason isa AbstractString && !isempty(strip(item.reason)),
                "non-review SBC outcome must have status = :fit_failed and a nonblank reason")
        end
        by_id[did] = item
    end

    planned_ids = Set(j.dataset_id for j in study.jobs)
    for did in keys(by_id)
        require(did in planned_ids, "unexpected SBC outcome for unplanned dataset_id: $(repr(did))")
    end

    qnames = study.test_quantities
    N_plan = length(study.jobs)
    L_sel = Base.checked_mul(study.sampler.chains, length(study.rank_settings.iterations))
    columns = [Union{Missing, Int}[missing for _ in 1:N_plan] for _ in qnames]
    roster = NamedTuple[]
    n_qualified = 0

    for (i, job) in enumerate(study.jobs)
        did = job.dataset_id
        item = get(by_id, did, nothing)
        if item === nothing
            push!(roster, (; dataset_id = did, status = :missing, qualified = false,
                exclusions = (:missing_outcome,), reason = "missing outcome",
                review_hash = nothing, descriptive_ranks = nothing))
        elseif get(item, :schema, nothing) == V02_SBC_REVIEW
            item.qualified && (n_qualified += 1)
            if item.rank_eligible
                for j in eachindex(qnames)
                    columns[j][i] = item.ranks[j].rank
                end
            end
            push!(roster, (; dataset_id = did,
                status = item.rank_eligible ? :rank_eligible : :rank_excluded,
                qualified = item.qualified,
                exclusions = item.exclusions,
                reason = isempty(item.exclusions) ? nothing : join(String.(item.exclusions), ","),
                review_hash = item.content_hash,
                descriptive_ranks = item.ranks))
        else
            push!(roster, (; dataset_id = did, status = :fit_failed, qualified = false,
                exclusions = (:fit_failed,), reason = String(strip(item.reason)),
                review_hash = nothing, descriptive_ranks = nothing))
        end
    end

    quantities = Tuple((;
        quantity = nm,
        ranks = Tuple(columns[j]),
        sbc_rank_cdf(columns[j]; n_draws = L_sel, n_quantities = length(qnames),
            alpha = Float64(alpha),
            independent = dataset_independence.status === :declared_independent)...,
    ) for (j, nm) in enumerate(qnames))

    n_elig = count(r -> r.status === :rank_eligible, roster)
    any_dep = any(q -> q.conditional_screen === :departure, quantities)
    overall_screen = dataset_independence.status !== :declared_independent ? :assumptions_unresolved :
        n_elig == 0 ? :unresolved :
        any_dep ? :departure : :no_resolved_departure

    body = (;
        schema = V02_SBC_SUMMARY,
        study_hash = study.content_hash,
        target_kind = study.target_kind,
        n_planned = N_plan,
        n_qualified,
        n_eligible = n_elig,
        qualification_rate = n_qualified / N_plan,
        eligible_rate = n_elig / N_plan,
        denominator_policy = :all_planned_jobs_retained_unconditionally,
        roster = Tuple(roster),
        counts = Dict(s => count(r -> r.status === s, roster) for s in unique(getproperty.(roster, :status))),
        exclusion_counts = Dict(s => count(r -> s in r.exclusions, roster)
            for s in (:fit_not_qualified, :test_quantity_diagnostics, :posterior_dependence, :ties, :fit_failed, :missing_outcome)),
        quantities,
        alpha = Float64(alpha),
        overall_screen,
        dataset_independence = deepcopy(dataset_independence),
        calibration_verified = false,
        scientific_acceptance = :not_established,
    )
    return B._prediction_seal(body)
end
