# Unified Practitioner Lifecycle Surface (Layer 1)
# Connects single-facet/multidimensional MFRM, generalized MGMFRM, correlated 2D/3D,
# JointRatings, OrdinalAssociation, StarAssociation, and rater-effect workflows
# under consistent multiple-dispatch verbs while preserving every existing API.

const _SA_MOD = Experimental.StarAssociation
const _C3D_MOD = Experimental.Correlated3D
const _JR_MOD = Experimental.JointRatings
const _OA_MOD = Experimental.JointRatings.OrdinalAssociation
const _RGE_MOD = Experimental.RaterGroupEffects
const _RII_MOD = Experimental.RaterItemInteractions
const _CC_MOD = Experimental.CriterionCollapse
const _RD_MOD = Experimental.RaterDrift
const _TI_MOD = Experimental.ThreeIndicator
const _SupportedCommonFit = PredictionObservationAdapter.SupportedFit

function _sample_schema_symbol(x)
    x isa NamedTuple && hasproperty(x, :schema) && x.schema isa AbstractString || return nothing
    s = x.schema
    s == "bayesianmgmfrm.correlated_3d_samples.v1" && return :correlated_3d
    s == "bayesianmgmfrm.joint_rating_samples.v1" && return :joint_ratings
    s == "bayesianmgmfrm.ordinal_association_samples.v1" && return :ordinal_association
    s == "bayesianmgmfrm.rater_group_effect_samples.v1" && return :rater_group_effects
    s == "bayesianmgmfrm.rater_item_interaction_samples.v1" && return :rater_item_interactions
    s == "bayesianmgmfrm.criterion_collapse_samples.v1" && return :criterion_collapse
    return nothing
end

"""
    design_summary(x; kwargs...)

Return a structured design, connectivity, and category-usage summary before
running MCMC estimation.

Dispatches across `FacetData`, `FacetSpec`, `FacetDesign`,
`Experimental.StarAssociation.StarModel`, `Experimental.Correlated3D.Target`,
`Experimental.JointRatings` targets, `Experimental.RaterGroupEffects.Target`,
`Experimental.RaterItemInteractions.Target`, `Experimental.CriterionCollapse.Target`,
and `Experimental.RaterDrift` targets.
"""
function design_summary(data::FacetData)
    check = rating_design_check(data)
    cov = coverage_summary(data)
    ov = rater_overlap(data)
    return (;
        schema = "bayesianmgmfrm.design_summary.v1",
        n_observations = data.n,
        n_persons = length(data.person_levels),
        n_raters = length(data.rater_levels),
        n_items = length(data.item_levels),
        n_categories = length(data.category_levels),
        category_levels = copy(data.category_levels),
        design_check = check,
        coverage = cov,
        rater_overlap = ov,
    )
end

validate_design(spec::FacetSpec) = spec.validation
validate_design(design::FacetDesign) = design.spec.validation
validate_design(m::_SA_MOD.StarModel; kwargs...) = _SA_MOD.validate_design(m; kwargs...)

function design_summary(spec::FacetSpec)
    val = spec.validation
    base = design_summary(spec.data)
    return merge(base, (;
        family = spec.family,
        dimensions = spec.dimensions,
        thresholds = spec.thresholds,
        discrimination = spec.discrimination,
        validation = val,
    ))
end

function design_summary(design::FacetDesign)
    base = design_summary(design.spec)
    return merge(base, (;
        n_free_parameters = length(design.parameter_names),
        parameter_names = copy(design.parameter_names),
    ))
end

design_summary(m::_SA_MOD.StarModel) = _SA_MOD.design_summary(m)
design_summary(t::_RGE_MOD.Target) = _RGE_MOD.design(t)
design_summary(t::_RII_MOD.Target) = _RII_MOD.design(t)
design_summary(t::_CC_MOD.Target) = _CC_MOD.design(t)
design_summary(t::_RD_MOD.M.Target; kwargs...) = _RD_MOD.design_review(t; kwargs...)

function design_summary(t::_C3D_MOD.Target)
    base = design_summary(t.independent.base.design)
    return merge(base, (; lkj_eta = t.eta, target_contract = _C3D_MOD.contract(t)))
end

function design_summary(t::_JR_MOD.S.Target)
    P, T, R, O, K, G, F = t.sizes
    return (;
        schema = "bayesianmgmfrm.joint_ratings_design_summary.v1",
        n_rows = length(t.data.rows),
        n_persons = P,
        n_tasks = T,
        n_raters = R,
        n_responses = O,
        n_criteria = length(t.levels.criterion),
        n_categories = K,
        n_threshold_groups = G,
        n_predictors = F,
        n_parameters = LogDensityProblems.dimension(t),
        levels = deepcopy(t.levels),
    )
end

function design_summary(t::_OA_MOD.Target)
    base = design_summary(t.layout.original.base)
    return merge(base, (;
        schema = "bayesianmgmfrm.ordinal_association_design_summary.v1",
        n_events = length(t.layout.original.events),
        n_parameters = LogDensityProblems.dimension(t),
        lambda_sd = t.layout.original.lambda_sd,
    ))
end

"""
    with_options(model_or_spec; kwargs...)

Return a copy of a model specification updated with modified structural, prior,
parameterization, or sampler options without mutating the original input.
"""
with_options(m::_SA_MOD.StarModel; kwargs...) = _SA_MOD.with_options(m; kwargs...)

function with_options(spec::FacetSpec;
        family::Symbol = spec.family,
        dimensions::Int = spec.dimensions,
        thresholds::Symbol = spec.thresholds,
        discrimination::Symbol = spec.discrimination,
        q_matrix = spec.q_matrix,
        dimension_labels = spec.dimension_labels,
        anchors = spec.anchors)
    return mfrm_spec(
        spec.data;
        family,
        dimensions,
        thresholds,
        discrimination,
        q_matrix,
        dimension_labels,
        anchors,
    )
end

"""
    prior_draw(model_or_spec; seed = 1, prior = MFRMPrior(), kwargs...)

Draw one complete unconstrained parameter vector `q` from the declared joint
prior using a reproducible integer `seed`. No MCMC estimation is executed.
"""
prior_draw(m::_SA_MOD.StarModel; seed::Integer = 1, kwargs...) =
    _SA_MOD.prior_draw(m; seed, kwargs...)

function prior_draw(t::_C3D_MOD.Target; seed::Integer = 1)
    rng = Random.MersenneTwister(_C3D_MOD.checked_seed(seed))
    return _C3D_MOD.prior_draw(t, rng)
end

function prior_draw(design::FacetDesign; seed::Integer = 1, prior::MFRMPrior = MFRMPrior())
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    rng = Random.MersenneTwister(Int(seed))
    return vec(_prior_parameter_draws(design, prior, 1, rng))
end

prior_draw(spec::FacetSpec; seed::Integer = 1, prior::MFRMPrior = MFRMPrior()) =
    prior_draw(getdesign(spec); seed, prior)

"""
    simulate(model_or_spec; seed = 1, kwargs...)

Simulate a synthetic rating dataset on the declared observation design from
either a fresh joint prior draw or explicit true parameter values.
"""
simulate(m::_SA_MOD.StarModel; seed::Integer = 1, kwargs...) =
    _SA_MOD.simulate(m; seed, kwargs...)

simulate(t::_C3D_MOD.Target; seed::Integer = 1, q = nothing) =
    _C3D_MOD.generate(t; seed, q)

function simulate(design::FacetDesign; seed::Integer = 1, params = nothing, prior::MFRMPrior = MFRMPrior())
    seed isa Integer && !(seed isa Bool) || throw(ArgumentError("seed must be an integer"))
    rng = Random.MersenneTwister(Int(seed))
    truth = params === nothing ? vec(_prior_parameter_draws(design, prior, 1, rng)) : Float64.(params)
    sim = simulate_responses(design, truth; rng)
    return (;
        seed = Int(seed),
        truth,
        simulated = sim,
    )
end

simulate(spec::FacetSpec; seed::Integer = 1, params = nothing, prior::MFRMPrior = MFRMPrior()) =
    simulate(getdesign(spec); seed, params, prior)

"""
    prior_predictive_check(target::ThreeIndicator.ConcurrentTarget; ndraws, seed,
                           interval=0.95, conditioning=:declared_design)

Generate independent joint-prior parameter vectors and responses on the declared
concurrent 9/9/2 design, before posterior fitting. `predictive_check(target; ...)`
is the same operation; passing a concurrent fitted result instead performs a
posterior predictive check. The report explicitly identifies the parameter source.

Every table shares one full prior state across events and channels. Existing-roster
effects are redrawn from the prior, while allocation and presentation histories
stay fixed. Supplied responses are comparison values only; the current target
constructor still requires a complete response table. This is not a new-design
or new-population interface, and data-informed prior choices remain data-informed.

Report marginal/A-C cell counts, independent-draw mean/CDF MCSE and discrete
endpoint precision screens. Constant empirical indicators have unavailable MCSE;
only analytic support events have exactly known precision. Pointwise intervals
and CDF screens are neither quantile MCSE nor calibrated adequacy tests. Use
`save_report` / checksum-verified `load_report` to preserve provenance and limits.
No posterior is fitted. Generation cost grows with `ndraws × number of events`;
count arrays are retained during computation, not full replicated response cubes.
"""
prior_predictive_check(t::_TI_MOD.Concurrent.Target; kwargs...) =
    _TI_MOD.ConcurrentPriorPredictive.check(t; kwargs...)
predictive_check(t::_TI_MOD.Concurrent.Target; kwargs...) =
    prior_predictive_check(t; kwargs...)

prior_predictive_check(m::_SA_MOD.StarModel; kwargs...) =
    _SA_MOD.prior_predictive_check(m; kwargs...)

function prior_predictive_check(t::_C3D_MOD.Target; ndraws::Int = 50, seed::Integer = 1)
    ndraws >= 1 || throw(ArgumentError("ndraws must be >= 1"))
    base_seed = _C3D_MOD.checked_seed(seed)
    data = t.independent.base.design.spec.data
    cats = data.category_levels
    K = length(cats)
    obs_props = [count(==(k), data.category) / data.n for k in 1:K]
    rep_props = Matrix{Float64}(undef, ndraws, K)
    for s in 1:ndraws
        gen = _C3D_MOD.generate(t; seed = base_seed + s - 1)
        gdata = gen.spec.data
        for k in 1:K
            rep_props[s, k] = count(==(k), gdata.category) / gdata.n
        end
    end
    rows = [
        (;
            category = cats[k],
            observed_proportion = obs_props[k],
            prior_mean = Statistics.mean(view(rep_props, :, k)),
            prior_q05 = Statistics.quantile(view(rep_props, :, k), 0.05),
            prior_q50 = Statistics.quantile(view(rep_props, :, k), 0.50),
            prior_q95 = Statistics.quantile(view(rep_props, :, k), 0.95),
        ) for k in 1:K
    ]
    return (;
        schema = "bayesianmgmfrm.correlated_3d_prior_predictive.v1",
        ndraws,
        seed = base_seed,
        rows,
    )
end

# Extend root fit ONLY for explicitly typed Experimental target objects so
# FacetSpec stability boundaries remain unchanged while typed targets use a single fit verb.
fit(m::_SA_MOD.StarModel; kwargs...) = _SA_MOD.fit(m; kwargs...)
fit(t::_C3D_MOD.Target; kwargs...) = _C3D_MOD.fit(t; kwargs...)
fit(t::_JR_MOD.S.Target; kwargs...) = _JR_MOD.fit(t; kwargs...)
fit(t::_OA_MOD.Target; kwargs...) = _OA_MOD.fit(t; kwargs...)
fit(t::_RGE_MOD.Target; kwargs...) = _RGE_MOD.fit(t; kwargs...)
fit(t::_RII_MOD.Target; kwargs...) = _RII_MOD.fit(t; kwargs...)
fit(t::_CC_MOD.Target; kwargs...) = _CC_MOD.fit(t; kwargs...)

"""
    prepare_fit(workspace_dir, model; kwargs...)
    prepare_fit(model, workspace_dir; kwargs...)

Create a deterministic, self-contained multi-worker or pre-validated fitting
plan before launching MCMC chains.
"""
prepare_fit(workspace_dir::AbstractString, m::_SA_MOD.StarModel; kwargs...) =
    _SA_MOD.prepare_fit(workspace_dir, m; kwargs...)
prepare_fit(m::_SA_MOD.StarModel, workspace_dir::AbstractString; kwargs...) =
    _SA_MOD.prepare_fit(workspace_dir, m; kwargs...)
prepare_fit(t::_RD_MOD.M.Target; kwargs...) = _RD_MOD.prepare(t; kwargs...)

"""
    run_chain_worker(workspace_dir, chain_id; resume = true)

Execute or resume a single MCMC chain worker inside a prepared workspace,
persisting periodic atomic checkpoints.
"""
run_chain_worker(workspace_dir::AbstractString, chain_id::Int; kwargs...) =
    _SA_MOD.run_chain_worker(workspace_dir, chain_id; kwargs...)

"""
    worker_status(workspace_dir)

Inspect per-chain completion and checkpoint status inside a prepared multi-worker
workspace without loading posterior draw matrices.
"""
worker_status(workspace_dir::AbstractString) = _SA_MOD.worker_status(workspace_dir)

"""
    collect_fit(workspace_dir)

Assemble completed per-chain worker artifacts into a verified joint posterior
result record.
"""
collect_fit(workspace_dir::AbstractString) = _SA_MOD.collect_fit(workspace_dir)

# Unified diagnostics & qualification
diagnostics(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.diagnostics(res; kwargs...)

function diagnostics(r::NamedTuple)
    tag = _sample_schema_symbol(r)
    if tag === :correlated_3d
        t = _C3D_MOD.restore(r)
        m = _C3D_MOD.model_draws(t, r.run.draws)
        return _C3D_MOD.diagnostics(t, r.run, m)
    elseif tag === :joint_ratings
        t = _JR_MOD.W.restore(r)
        return _JR_MOD.W._source_diagnostics(t, r.run)
    elseif tag === :ordinal_association
        rep = _OA_MOD.report(r)
        return rep.result.diagnostics
    elseif tag === :rater_group_effects
        t = _RGE_MOD._restore(r)
        return _RII_MOD._diagnostics(t, r.run, _RGE_MOD._draws(t, r.run.draws))
    elseif tag === :rater_item_interactions
        t = _RII_MOD._restore(r)
        return _RII_MOD._diagnostics(t, r.run)
    elseif tag === :criterion_collapse
        rep = _CC_MOD.report(r)
        return rep.diagnostics
    end
    throw(ArgumentError("unsupported NamedTuple record for diagnostics"))
end

"""
    qualify(fit; max_rhat = 1.01, min_ess = 400.0, min_bfmi = 0.30, kwargs...)

Evaluate MCMC convergence and sampler-telemetry qualification gates on a fitted
result. Common fits return a boolean `qualified` flag; StarResult preserves its
report envelope with `result.numerically_qualified` and named focal MCSE gates.
The common names `max_rhat`, `min_ess`, `min_bfmi` work for all these routes.
Star retains `rhat_max`, `ess_min`, `ebfmi_min` as aliases (do not supply both).
All applicable raw, reconstructed and finite-panel location coordinates must
pass. Missing NUTS telemetry is unqualified, not evidence of zero divergences.
The requested thresholds apply to this gate; stored diagnostics retain their
original thresholds and warnings.

Experimental NamedTuple records check raw, model and available conditional-location
coordinates. Existing four-chain requirements for rater-effect/criterion-collapse
records are retained; the other routes require at least two chains for diagnostics.
Common fits and Experimental NamedTuple records expose
`focal_precision_qualification=:not_assessed`: their `qualified` flag covers
whole-fit diagnostics only. Star also checks mean/95% interval-endpoint MCSE,
but only for the reported `focal_parameters` (finite-entity root/branch
correlations). Other estimands need their own MCSE assessment. A partial Star
check with `check_transformed=false` cannot pass whole-fit qualification. Use `qualify`
to request different thresholds; `diagnostics(record)` reports original settings
and rejects unsupported keywords.
"""
qualify(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.qualify(res; kwargs...)

function qualify(fit::_SupportedCommonFit;
        max_rhat::Real = 1.01,
        min_ess::Real = 400.0,
        min_bfmi::Real = 0.30)
    min_ess isa Bool && throw(ArgumentError("min_ess must be a finite positive real number"))
    checked = _check_diagnostic_thresholds(max_rhat, min_ess)
    min_bfmi isa Bool && throw(ArgumentError("min_bfmi must be a finite positive real number"))
    isfinite(min_bfmi) && isfinite(Float64(min_bfmi)) && min_bfmi > 0 || throw(ArgumentError("min_bfmi must be finite and positive"))
    diag = if fit isa Union{GMFRMFit, MGMFRMFit}
        stored = fit.diagnostic_surface.summary
        diagnostics(fit; split_chains = stored.split_chains_requested,
            rhat_threshold = stored.rhat_threshold, ess_threshold = stored.ess_threshold)
    else
        diagnostics(fit)
    end
    samp = diag.sampler_rows
    rows = vcat((get(diag, key, NamedTuple[]) for key in
        (:parameter_rows, :direct_parameter_rows, :model_parameter_rows, :location_rows))...)
    applicable = filter(_quality_gate_applicable, rows)
    finite(x) = x isa Real && isfinite(x)
    param_ok = !isempty(applicable) && all(applicable) do row
        finite(row.rank_normalized_rhat) && row.rank_normalized_rhat <= checked.rhat_threshold &&
            finite(row.bulk_ess) && row.bulk_ess >= checked.ess_threshold &&
            finite(row.tail_ess) && row.tail_ess >= checked.ess_threshold
    end
    param_ok &= all(row -> row.n_failed == 0, get(diag, :direct_constraint_rows, NamedTuple[]))
    metrics = _mcmc_metric_summary(rows, checked.rhat_threshold, checked.ess_threshold)
    run = fit isa _ModelComparisonFit ? fit : fit.record.run
    stats = run.sampler_stats
    # Match every retained iteration, not just the count of available energy rows.
    telemetry_complete = length(stats) == length(run.chain_ids) && all(eachindex(stats)) do i
        get(stats[i], :chain, nothing) == run.chain_ids[i] &&
            get(stats[i], :iteration, nothing) == run.iterations[i]
    end
    random_walk = run.sampler === :random_walk_metropolis
    if !random_walk
        telemetry_complete &= all(stats) do row
            get(row, :numerical_error, missing) isa Bool &&
                get(row, :tree_depth, missing) isa Integer &&
                finite(get(row, :hamiltonian_energy, missing))
        end
    end
    coverage = _ebfmi_coverage(samp)
    n_div = !isempty(samp) && all(row -> !ismissing(row.n_divergences), samp) ?
        sum(row.n_divergences for row in samp) : missing
    n_td = !isempty(samp) && all(row -> !ismissing(row.n_max_treedepth), samp) ?
        sum(row.n_max_treedepth for row in samp) : missing
    sampler_ok = telemetry_complete && !isempty(samp) && all(row -> row.flag === :ok, samp)
    sampler_ok &= if random_walk
        all(row -> isequal(get(row, :n_nonfinite_proposals, missing), 0), samp)
    else
        coverage.e_bfmi_complete && all(samp) do row
            isequal(row.n_divergences, 0) && isequal(row.n_max_treedepth, 0) &&
                finite(row.e_bfmi) && row.e_bfmi >= min_bfmi
        end
    end
    return (;
        qualified = param_ok && sampler_ok,
        qualification_scope = :whole_fit_diagnostics,
        focal_precision_qualification = :not_assessed,
        parameter_gate_passed = param_ok,
        sampler_gate_passed = sampler_ok,
        max_rhat = metrics.max_rank_normalized_rhat,
        min_bulk_ess = metrics.min_bulk_ess,
        min_tail_ess = metrics.min_tail_ess,
        n_divergences = n_div,
        n_max_treedepth = n_td,
        telemetry_complete,
        coverage...,
        thresholds = (; max_rhat = Float64(max_rhat), min_ess = Float64(min_ess), min_bfmi = Float64(min_bfmi)),
        diagnostics = diag,
        sampler = samp,
    )
end

function qualify(r::NamedTuple; max_rhat::Real = 1.01, min_ess::Real = 400.0, min_bfmi::Real = 0.30)
    min_ess isa Bool && throw(ArgumentError("min_ess must be a finite positive real number"))
    checked = _check_diagnostic_thresholds(max_rhat, min_ess)
    min_bfmi isa Bool && throw(ArgumentError("min_bfmi must be a finite positive real number"))
    isfinite(min_bfmi) && isfinite(Float64(min_bfmi)) && min_bfmi > 0 || throw(ArgumentError("min_bfmi must be finite and positive"))
    d = diagnostics(r)
    return _qualify_experimental_diagnostics(d, r.run, checked, Float64(min_bfmi))
end

function _qualify_experimental_diagnostics(d, run, checked, min_bfmi)
    rows = vcat((get(d, key, NamedTuple[]) for key in
        (:raw, :model, :conditional, :raw_diagnostics, :model_diagnostics))...)
    finite(x) = x isa Real && isfinite(x)
    p_ok = !isempty(rows) && any(_quality_gate_applicable, rows) && all(rows) do row
        if !_quality_gate_applicable(row)
            return get(row, :flag, nothing) === :structurally_fixed
        end
        finite(row.rank_normalized_rhat) && row.rank_normalized_rhat <= checked.rhat_threshold &&
            finite(row.bulk_ess) && row.bulk_ess >= checked.ess_threshold &&
            finite(row.tail_ess) && row.tail_ess >= checked.ess_threshold
    end
    minimum_chains = get(get(d, :thresholds, (;)), :minimum_chains, 2)
    p_ok &= run.controls.chains >= minimum_chains
    stats = run.sampler_stats
    telemetry_complete = length(stats) == length(run.chain_ids) &&
        length(stats) == run.controls.chains * run.controls.ndraws && all(eachindex(stats)) do i
            s = stats[i]
            get(s, :chain, nothing) == run.chain_ids[i] &&
                get(s, :iteration, nothing) == run.iterations[i] &&
                get(s, :numerical_error, missing) isa Bool &&
                get(s, :tree_depth, missing) isa Integer &&
                finite(get(s, :hamiltonian_energy, missing))
        end
    srows = get(d, :sampler, NamedTuple[])
    s_ok = telemetry_complete && length(srows) == run.controls.chains && all(srows) do s
        isequal(s.n_divergences, 0) && isequal(s.n_nonfinite_logdensity, 0) &&
            isequal(s.n_max_treedepth, 0) && finite(s.e_bfmi) && s.e_bfmi >= min_bfmi
    end
    # Keep the original diagnostic fields for callers of the former direct return.
    return merge(d, (;
        qualified = p_ok && s_ok,
        qualification_scope = :whole_fit_diagnostics,
        parameter_gate_passed = p_ok,
        sampler_gate_passed = s_ok,
        telemetry_complete,
        sampling_warning = !(p_ok && s_ok) || get(d, :sampling_warning, false),
        focal_precision_qualification = :not_assessed,
        thresholds = (; max_rhat = checked.rhat_threshold, min_ess = checked.ess_threshold,
            min_bfmi, minimum_chains),
        diagnostics = d,
    ))
end

# Unified posterior_summary extensions
posterior_summary(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.posterior_summary(res; kwargs...)
posterior_summary(saved::Union{_RD_MOD.SavedReport, _RD_MOD.SavedComparison}) = _RD_MOD.report(saved)
posterior_summary(saved::_TI_MOD.SavedReport) = _TI_MOD.report(saved)

function posterior_summary(r::NamedTuple; kwargs...)
    tag = _sample_schema_symbol(r)
    tag === :correlated_3d && return _C3D_MOD.report(r; kwargs...)
    tag === :joint_ratings && return _JR_MOD.report(r; kwargs...)
    tag === :ordinal_association && return _OA_MOD.report(r; kwargs...)
    tag === :rater_group_effects && return _RGE_MOD.report(r; kwargs...)
    tag === :rater_item_interactions && return _RII_MOD.report(r; kwargs...)
    tag === :criterion_collapse && return _CC_MOD.report(r; kwargs...)
    throw(ArgumentError("unsupported NamedTuple record for posterior_summary"))
end

"""
    facet_summary(fit; facet = :person, interval = 0.95, kwargs...)

Summarize posterior locations, credible intervals, and Monte Carlo standard
errors for all levels of a selected facet (`:person` / `:entity`, `:rater`, or `:item`).
"""
facet_summary(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.facet_summary(res; kwargs...)

function facet_summary(fit::_SupportedCommonFit; facet::Symbol = :person, interval::Real = 0.95)
    target_block = facet === :entity ? :person : facet
    target_block in (:person, :rater, :item) ||
        throw(ArgumentError("facet must be :person (:entity), :rater, or :item"))
    ctx = _recovery_context(fit)
    lo, hi = _interval_probabilities(Float64(interval))
    chains = length(unique(ctx.chain_ids))
    selected = filter(c -> _recovery_quantity(c, ctx.spec).block === target_block, ctx.coordinates)
    rows = map(selected) do coord
        desc = _recovery_quantity(coord, ctx.spec)
        vals = Float64.(coord.values)
        mcse = only(_posterior_mcse_rows(
            reshape(vals, :, 1),
            [coord.parameter],
            chains;
            probabilities = (lo, 0.5, hi),
            parameter_space = desc.parameter_space,
            structurally_fixed_parameters = coord.fixed ? Set([coord.parameter]) : Set{String}(),
        ))
        qs = getproperty.(mcse.quantiles, :estimate)
        (;
            parameter = coord.parameter,
            block = target_block,
            dimension = desc.dimension,
            dimension_label = desc.dimension_label,
            fixed = coord.fixed,
            mean = Statistics.mean(vals),
            sd = length(vals) > 1 ? Statistics.std(vals) : missing,
            median = qs[2],
            lower = qs[1],
            upper = qs[3],
            mean_mcse = mcse.mean_mcse,
            mcse_status = mcse.mcse_status,
        )
    end
    return (;
        schema = "bayesianmgmfrm.facet_summary.v1",
        facet = target_block,
        interval = Float64(interval),
        n_levels = length(rows),
        rows,
    )
end

"""
    category_summary(fit; kwargs...)

Summarize category usage, adjacent step thresholds, and expected category
proportions across a fitted ordinal rating model.
"""
category_summary(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.category_summary(res; kwargs...)
function category_summary(fit::_SupportedCommonFit;
        dataset_id::AbstractString = "default",
        observation_ids = nothing,
        kwargs...)
    n_obs = PredictionObservationAdapter._fit_data(fit).n
    ids = observation_ids === nothing ? ["obs_$n" for n in 1:n_obs] : observation_ids
    return category_report(fit; dataset_id, observation_ids = ids, kwargs...)
end

function category_summary(r::NamedTuple; kwargs...)
    tag = _sample_schema_symbol(r)
    tag === :rater_group_effects && return _RGE_MOD.category_report(r; kwargs...)
    tag === :criterion_collapse && return _CC_MOD.category_report(r; kwargs...)
    throw(ArgumentError("category_summary is not defined for this record schema"))
end

"""
    contrast(fit; left, right, kwargs...)
    contrast(left_draws, right_draws; chains, kwargs...)

Compute draw-paired posterior contrasts (differences or log-ratios) with
equal-tailed credible intervals, event probabilities, ROPE summaries, and
autocorrelation-aware Monte Carlo standard errors.
"""
contrast(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.contrast(res; kwargs...)
contrast(fit::_SupportedCommonFit; kwargs...) = posterior_contrast(fit; kwargs...)
contrast(left::AbstractVector, right::AbstractVector; kwargs...) =
    posterior_contrast(left, right; kwargs...)

function contrast(r::NamedTuple; kwargs...)
    tag = _sample_schema_symbol(r)
    tag === :joint_ratings && return _JR_MOD.contrast(r; kwargs...)
    tag === :ordinal_association && return _OA_MOD.contrast(r; kwargs...)
    tag === :rater_group_effects && return _RGE_MOD.contrast(r; kwargs...)
    tag === :rater_item_interactions && return _RII_MOD.contrast(r; kwargs...)
    if tag === :correlated_3d
        left = String(kwargs[:left])
        right = String(kwargs[:right])
        left == right && throw(ArgumentError("left and right must be distinct coordinates"))
        interval = get(kwargs, :interval, 0.90)
        rope = get(kwargs, :rope, nothing)
        t = _C3D_MOD.restore(r)
        m = _C3D_MOD.model_draws(t, r.run.draws)
        il = findfirst(==(left), m.names)
        ir = findfirst(==(right), m.names)
        il !== nothing && ir !== nothing ||
            throw(ArgumentError("unknown Correlated3D coordinate name"))
        return posterior_contrast(
            view(m.values, :, il),
            view(m.values, :, ir);
            chains = r.run.controls.chains,
            interval,
            rope,
        )
    end
    throw(ArgumentError("contrast is not defined for this record schema"))
end

"""
    event_probabilities(fit; kwargs...)

Compute conditional category or cell probabilities through the model's existing
prediction contract. No replicated scores are generated. Returns differ:

- Common fits: a draws-by-rating-rows-by-categories array, using all draws by
  default; no intervals, MCSE or diagnostic envelope are computed. `ndraws`
  resamples draws with replacement, while `draw_indices` preserves the requested
  order/duplicates. Neither selection should be treated as original MCMC chains
  for precision estimation.
- Star / OrdinalAssociation: `rating_event_id` selects an existing joint event;
  reports contain probability intervals, MCSE and source warnings/diagnostics.
- Correlated3D: `observation` or `rows` selects original rating rows, with
  probability intervals, MCSE and diagnostics.
- JointRatings: `rows` and `response_effect=:existing` or `:new` describe future
  events for known person/task/rater levels. New shared response effects are
  integrated; output rows are marginals, not a joint event distribution.

Intervals quantify posterior uncertainty in probabilities, not future scores.
No route here establishes heldout accuracy or new-person/task/rater prediction.
Whole-fit qualification does not qualify every probability's MCSE.
"""
event_probabilities(res::_SA_MOD.StarResult; kwargs...) =
    _SA_MOD.event_probabilities(res; kwargs...)
event_probabilities(fit::_SupportedCommonFit; kwargs...) =
    predictive_probabilities(fit; kwargs...)

"""
    predictive_probabilities(fit::MultidimensionalMFRMFit; ndraws=nothing,
        draw_indices=nothing, rng=Random.default_rng())

Existing-rating conditional category probabilities for fixed-Q MFRM, including
its correlated-ability and exchangeable-rater fit variants. Returns a draws ×
rows × categories array in saved category order; no scores are generated.
Reuses the verified unit-logit reconstruction without applying correlation a
second time. Default selection retains all original draws; `ndraws` resamples
with replacement and `draw_indices` preserves order/duplicates. Use original
chain ordering, not resampled arrays, for MCMC precision calculations.
"""
function predictive_probabilities(fit::_FixedQMFRMFit;
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    context = PredictionObservationAdapter._context(fit, ndraws, draw_indices, rng)
    return _mgmfrm_predictive_probabilities_direct(context.design, context.direct)
end

"""
    posterior_predictive_check(fit::MultidimensionalMFRMFit; ndraws=nothing,
        draw_indices=nothing, rng=Random.default_rng())

Conditional replicated ratings and summaries for fixed-Q MFRM (including its
correlated/exchangeable variants), retaining selected draw/chain/iteration IDs
and source diagnostics. Reuses the existing report-generation kernel. This is
an existing-row model check, not heldout or new-facet predictive validation.
`predictive_check(fit; seed, ...)` supplies the unified seeded entry point.
"""
function posterior_predictive_check(fit::_FixedQMFRMFit;
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    return _mfrm_fixed_q_predictive_check((; fit.record); ndraws, draw_indices, seed=nothing, rng)
end

function event_probabilities(r::NamedTuple; kwargs...)
    tag = _sample_schema_symbol(r)
    tag === :ordinal_association && return _OA_MOD.event_probabilities(r; kwargs...)
    if tag === :correlated_3d
        if haskey(kwargs, :rows)
            rest = Base.structdiff((; kwargs...), (; rows = nothing))
            return (;
                schema = "bayesianmgmfrm.correlated_3d_probabilities_batch.v1",
                rows = [_C3D_MOD.probabilities(r; observation = obs, rest...) for obs in kwargs[:rows]],
            )
        end
        return _C3D_MOD.probabilities(r; kwargs...)
    end
    if tag === :joint_ratings
        haskey(kwargs, :rows) || throw(ArgumentError("supply rows = ... for JointRatings event_probabilities"))
        rest = Base.structdiff((; kwargs...), (; rows = nothing))
        return _JR_MOD.predict(r, kwargs[:rows]; rest...)
    end
    throw(ArgumentError("event_probabilities is not defined for this record schema"))
end

function _default_person_parameters(fit::_SupportedCommonFit)
    ctx = _recovery_context(fit)
    return [c.parameter for c in ctx.coordinates if _recovery_quantity(c, ctx.spec).block === :person]
end

"""
    reliability(fit; kwargs...)

Summarize finite-cohort posterior variance decomposition (`B / (B + W)`) and
its delta-method Monte Carlo standard error across joint posterior draws.
"""
reliability(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.reliability(res; kwargs...)
function reliability(fit::_SupportedCommonFit;
        parameters = nothing,
        target::Symbol = :centered,
        weights = nothing)
    ps = parameters === nothing ? _default_person_parameters(fit) : parameters
    return posterior_reliability(fit; parameters = ps, target, weights)
end

"""
    ranking(fit; kwargs...)

Summarize joint-draw posterior ranks, tie-aware intervals, and top-k inclusion
probability bounds for an explicit cohort of rated entities.
"""
ranking(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.ranking(res; kwargs...)
function ranking(fit::_SupportedCommonFit;
        parameters = nothing,
        direction::Symbol = :higher,
        top_k = nothing,
        interval = 0.90,
        max_rank_cells = 20_000_000)
    ps = parameters === nothing ? _default_person_parameters(fit) : parameters
    return posterior_ranking(fit; parameters = ps, direction, top_k, interval, max_rank_cells)
end

"""
    classification(fit; cutoff, pass_probability = 0.5, kwargs...)

Evaluate binary mastery/cut-score decisions and cohort-level expected
false-pass / false-fail risks across joint posterior draws.
"""
classification(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.classification(res; kwargs...)
function classification(fit::_SupportedCommonFit;
        parameters = nothing,
        cutoff,
        pass_probability = 0.5,
        interval = 0.90)
    ps = parameters === nothing ? _default_person_parameters(fit) : parameters
    return posterior_classification(fit; parameters = ps, cutoff, pass_probability, interval)
end

# Fit criteria, predictive checks, comparison, and sensitivity
waic(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.waic(res; kwargs...)
psis_loo(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.psis_loo(res; kwargs...)

function _correlated_3d_ll_matrix(r::NamedTuple)
    t = _C3D_MOD.restore(r)
    data = t.independent.base.design.spec.data
    S_n = r.run.total_draws
    N_n = data.n
    ll = Matrix{Float64}(undef, S_n, N_n)
    for s in 1:S_n
        lp = _C3D_MOD.category_logprobs(t, view(r.run.draws, s, :))
        for n in 1:N_n
            ll[s, n] = lp[n, data.category[n]]
        end
    end
    return ll, r.run.controls.chains
end

function _correlated_3d_psis_loo(ll::Matrix{Float64}, n_ch::Int)
    S_n, N_n = size(ll)
    lppd_vec = Vector{Float64}(undef, N_n)
    elpd_vec = Vector{Float64}(undef, N_n)
    p_vec = Vector{Float64}(undef, N_n)
    k_vec = Vector{Float64}(undef, N_n)
    neff_vec = Vector{Float64}(undef, N_n)
    reff_vec = Vector{Float64}(undef, N_n)
    lr = Vector{Float64}(undef, S_n)
    for n in 1:N_n
        col = view(ll, :, n)
        lppd_n = _SA_MOD._logmeanexp_f64(col)
        lppd_vec[n] = lppd_n
        for s in 1:S_n
            lr[s] = -col[s]
        end
        reff_n = _SA_MOD._relative_eff_exp_ll(col, n_ch)
        reff_vec[n] = reff_n
        ps = _SA_MOD._psis_smooth_log_ratios(lr; r_eff = reff_n)
        elpd_n = _SA_MOD._logsumexp_f64(col .+ ps.norm_log_weights)
        elpd_vec[n] = elpd_n
        p_vec[n] = lppd_n - elpd_n
        k_vec[n] = ps.pareto_k
        neff_vec[n] = ps.n_eff
    end
    elpd_loo = sum(elpd_vec)
    p_loo = sum(p_vec)
    lppd = sum(lppd_vec)
    se_elpd_loo = N_n > 1 ? sqrt(N_n * Statistics.var(elpd_vec; corrected = true)) : 0.0
    k_th = _SA_MOD._ps_khat_threshold(S_n)
    bad_pareto_k_count = count(>(k_th), k_vec)
    return (;
        criterion = :loo,
        method = :pareto_smoothed_importance_sampling,
        pareto_k_estimator = :zhang_stephens_gpd,
        elpd_loo,
        p_loo,
        lppd,
        looic = -2.0 * elpd_loo,
        se_elpd_loo,
        se_looic = 2.0 * se_elpd_loo,
        pointwise = (;
            elpd_loo = elpd_vec,
            p_loo = p_vec,
            lppd = lppd_vec,
            pareto_k = k_vec,
            effective_sample_size = neff_vec,
            r_eff = reff_vec,
        ),
        n_draws = S_n,
        n_observations = N_n,
        pareto_k_threshold = k_th,
        bad_pareto_k_count,
        max_pareto_k = maximum(k_vec),
        warning = bad_pareto_k_count == 0 ? :ok : :high_pareto_k,
    )
end

function waic(r::NamedTuple)
    _sample_schema_symbol(r) === :correlated_3d ||
        throw(ArgumentError("waic is not defined for this record schema"))
    ll, _ = _correlated_3d_ll_matrix(r)
    return waic(ll)
end

function psis_loo(r::NamedTuple)
    _sample_schema_symbol(r) === :correlated_3d ||
        throw(ArgumentError("psis_loo is not defined for this record schema"))
    ll, n_ch = _correlated_3d_ll_matrix(r)
    return _correlated_3d_psis_loo(ll, n_ch)
end

"""
    criteria(fit; kwargs...)

Compute WAIC and LOO from all retained draws. For common fits, select unique
`criteria = (:waic, :psis_loo)` from `:waic`, `:psis_loo`,
`:hill_smoothed_loo` and `:raw_loo`. Common-fit `:psis_loo` uses standard
PSIS with chain-based relative efficiency. The historical Hill approximation
remains an explicit alternative. Nondefault tail controls apply only to raw/Hill
LOO; standard PSIS chooses its tail from draw count and relative efficiency.
Subsetting/resampling is rejected, consistently with `prediction_criteria`.

Supply both `dataset_id` and `observation_ids` to retain the observation-bound
`prediction_criteria` report, including sampling warnings and affected IDs;
its `scores` use the same selected names and estimators as the unlabelled result.
IDs never change the estimator. StarResult and correlated 3D retain their own
documented criterion contracts. CriterionCollapse requires
`unit=:performance_rater`, accepts `model=:mixture` or `:all_ordinary`, and
returns conditional profile PSIS scores, not WAIC. See
`Experimental.CriterionCollapse.criteria` for prior, precision and scope.
"""
criteria(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.criteria(res; kwargs...)

function criteria(fit::_SupportedCommonFit;
        criteria::Tuple = (:waic, :psis_loo), dataset_id = nothing, observation_ids = nothing,
        pareto_k_threshold::Real = 0.7, tail_fraction::Real = 0.2, min_tail_draws::Int = 5,
        ndraws = nothing, draw_indices = nothing)
    ndraws === nothing && draw_indices === nothing || throw(ArgumentError(
        "criteria requires all retained draws; ndraws and draw_indices are not supported"))
    mapped = criteria
    !isempty(mapped) && allunique(mapped) && all(in((:waic, :hill_smoothed_loo, :raw_loo, :psis_loo)), mapped) ||
        throw(ArgumentError("choose distinct criteria from :waic, :psis_loo, :hill_smoothed_loo, :raw_loo"))
    (dataset_id === nothing) == (observation_ids === nothing) ||
        throw(ArgumentError("supply dataset_id and observation_ids together"))
    controls = _check_loo_controls(; pareto_k_threshold, tail_fraction, min_tail_draws)
    if dataset_id !== nothing
        rep = prediction_criteria(fit; dataset_id, observation_ids, criteria = mapped, controls...)
        rename(nt) = NamedTuple{criteria}(values(nt))
        return merge(rep, (; scores = rename(rep.scores),
            problem_observation_ids = rename(rep.problem_observation_ids),
            criterion_warnings = rename(rep.criterion_warnings)))
    end
    context = PredictionObservationAdapter._context(fit, nothing, nothing, Random.default_rng())
    :psis_loo in mapped && _check_psis_iterations(context.chain_ids,context.iterations)
    _, loglik = PredictionObservationAdapter._prediction_arrays(context.design, context.direct, false)
    scores = map(mapped) do c
        c === :waic ? waic(loglik) : c === :raw_loo ? loo(loglik; controls...) :
            c === :hill_smoothed_loo ? _hill_smoothed_loo(loglik; controls...) :
            psis_loo(loglik; chain_ids=context.chain_ids, controls...)
    end
    return NamedTuple{criteria}(scores)
end

function criteria(r::NamedTuple; kwargs...)
    tag = _sample_schema_symbol(r)
    tag === :criterion_collapse && return _CC_MOD.criteria(r; kwargs...)
    isempty(kwargs) || throw(ArgumentError("unsupported criteria controls for this record schema"))
    if tag === :correlated_3d
        ll, n_ch = _correlated_3d_ll_matrix(r)
        return (;
            waic = waic(ll),
            psis_loo = _correlated_3d_psis_loo(ll, n_ch),
        )
    end
    throw(ArgumentError("criteria is not defined for this record schema"))
end

"""
    predictive_check(fit; kwargs...)

Run posterior predictive checks comparing observed score summaries against
replicated datasets drawn from the fitted posterior. CriterionCollapse instead
integrates a same-design category-count distribution exactly; see
`Experimental.CriterionCollapse.predictive_check` for its required category,
optional rater contrast and posterior-conditioning controls.
"""
predictive_check(res::_SA_MOD.StarResult; kwargs...) = _SA_MOD.predictive_check(res; kwargs...)

"""
    predictive_check(fit::Experimental.ThreeIndicator.ConcurrentWorkflow.Fit;
        seed, interval=.95, conditioning=:existing_levels, qualification_report=nothing)

Perform a **posterior predictive check**, using parameters from the fitted
posterior and generating new categorical responses. This is not a prior
predictive check: it does not draw parameters from the prior. The report records
`check_type="posterior_predictive"` and `parameter_source="fitted_posterior"`.
`posterior_predictive_check(fit; ...)` is an equivalent existing entry point.

Every complete retained joint state generates one 9/9/2 response table on the
observed design, conditional on existing effects and histories. Study panels,
score direction, chain/iteration IDs and baseline numerical warnings remain.
Outputs are marginal and A/C joint counts plus maximum joint-cell discrepancies.
No new-level, held-out or prior predictive generator is supplied for this target.

Count intervals use the inverse empirical CDF. Mean/tail MCSE and discrete
endpoint CDF screens are reported separately. These screens are not quantile
MCSE, calibrated significance tests or scientific acceptance. A tail constant
within any chain has unavailable MCSE unless fixed by the known count support.
No whole-fit qualification is inferred from favorable predictive results.

Optionally pass an intact same-fit concurrent probability/contrast report as
`qualification_report` to reuse its validated whole-fit diagnostics. A different
fit or corrupted report is rejected. Otherwise diagnostics are computed once.
Save computed results with `save_report`, and reopen with `load_report` and a
separately retained checksum receipt. The report does not retain response tables
or promise native-cache migration. All retained states are used: cost scales with
retained draws × observed events. No automatic thinning or refitting occurs.
"""
predictive_check(fit::_TI_MOD.ConcurrentWorkflow.Fit; kwargs...) =
    _TI_MOD.ConcurrentPredictive.check(fit; kwargs...)
posterior_predictive_check(fit::_TI_MOD.ConcurrentWorkflow.Fit; kwargs...) =
    predictive_check(fit; kwargs...)
function predictive_check(fit::_SupportedCommonFit;
        seed::Union{Nothing,Integer} = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    actual_rng = seed === nothing ? rng : Random.Xoshiro(seed)
    return posterior_predictive_check(fit; rng = actual_rng, kwargs...)
end

function predictive_check(r::NamedTuple; kwargs...)
    tag = _sample_schema_symbol(r)
    tag === :rater_group_effects && return _RGE_MOD.category_predictive_check(r; kwargs...)
    tag === :criterion_collapse && return _CC_MOD.predictive_check(r; kwargs...)
    throw(ArgumentError("predictive_check is not defined for this record schema"))
end

"""
    compare_models(result::NamedTuple)

For a CriterionCollapse fit, compare the all-ordinary and at-least-one-collapse
submodels under the original induced priors. Returns log Bayes factors, event
probabilities, MCSE and retained diagnostic warnings. This one-fit comparison is
not WAIC/LOO or an arbitrary two-fit comparison; see
`Experimental.CriterionCollapse.compare_models` for conditioning and precision.
With `criterion=:loo, unit=:performance_rater`, compare the mixture and induced
all-ordinary models using conditional held-out profile scores instead; no iid
sampling SE or automatic ranking is supplied.
"""
function compare_models(r::NamedTuple; kwargs...)
    _sample_schema_symbol(r) === :criterion_collapse ||
        throw(ArgumentError("one-record compare_models requires a CriterionCollapse fit"))
    return _CC_MOD.compare_models(r; kwargs...)
end

function compare_models(fits::AbstractVector{<:Pair{<:Any, _SA_MOD.StarResult}}; kwargs...)
    length(fits) == 2 || throw(ArgumentError("StarResult pair comparison expects exactly 2 models"))
    return compare_models(fits[1], fits[2]; kwargs...)
end
function compare_models(primary::Pair{<:Any,_SA_MOD.StarResult}, baseline::Pair{<:Any,_SA_MOD.StarResult}; kwargs...)
    haskey(kwargs,:names) && throw(ArgumentError("model names are supplied by the pair labels"))
    return _SA_MOD.compare_models(last(primary),last(baseline);names=(first(primary),first(baseline)),kwargs...)
end
compare_models(primary::NamedTuple,baseline::NamedTuple;kwargs...) =
    _SA_MOD.compare_models(primary,baseline;kwargs...)
compare_models(primary::_SA_MOD.StarResult, baseline::_SA_MOD.StarResult; kwargs...) =
    _SA_MOD.compare_models(primary, baseline; kwargs...)

prior_sensitivity(res::_SA_MOD.StarResult, alt_prior::Union{_SA_MOD.PriorConfig, NamedTuple}; kwargs...) =
    _SA_MOD.prior_sensitivity(res, [:alternative => alt_prior]; kwargs...)
prior_sensitivity(res::_SA_MOD.StarResult, variants::AbstractVector; kwargs...) =
    _SA_MOD.prior_sensitivity(res, variants; kwargs...)

"""
    save_fit(path, fit; kwargs...)

Atomically save a fitted Bayesian rating model to disk with cryptographic
integrity hashes and target-identity metadata, refusing to overwrite existing files
by default.
"""
save_fit(path::AbstractString, res::_SA_MOD.StarResult) = _SA_MOD.save_fit(path, res)
save_fit(path::AbstractString, fit::_SupportedCommonFit; kwargs...) =
    save_fit_cache(path, fit; kwargs...)

function save_fit(path::AbstractString, r::NamedTuple)
    tag = _sample_schema_symbol(r)
    tag === :correlated_3d && return _C3D_MOD.save_result(path, r)
    tag === :joint_ratings && return _JR_MOD.save_result(path, r)
    tag === :ordinal_association && return _OA_MOD.save_result(path, r)
    tag === :rater_group_effects && return _RGE_MOD.save_result(path, r)
    tag === :rater_item_interactions && return _RII_MOD.save_result(path, r)
    tag === :criterion_collapse && return _CC_MOD.save_result(path, r)
    throw(ArgumentError("unsupported NamedTuple record for save_fit"))
end

"""
    load_fit(path; kwargs...)

Restore a native fitted model saved by `save_fit` (or `save_fit_cache` /
`save_result`), or a RaterDrift/ThreeIndicator fit directory. The stored schema
selects the reader; its checksum, target and environment checks remain in force.
Only use trusted native files in their original compatible environment.

Reader-specific controls are forwarded, never ignored. For example,
`require_complete=false` inspects a partial fit directory without resuming it;
common fit caches accept `expected_cache_key`, `verify_hash`, and `return_record`.
Unsupported controls raise an error.
"""
function load_fit(path::AbstractString; kwargs...)
    if isdir(path)
        plan_path = joinpath(path, "plan.jls")
        isfile(plan_path) || throw(ArgumentError("fit directory has no plan.jls: $path"))
        plan = open(Serialization.deserialize, plan_path)
        schema = plan isa NamedTuple ? get(plan, :schema, nothing) : nothing
        schema == _RD_MOD.RaterDriftWorkflow.PLAN_SCHEMA && return _RD_MOD.load_fit(path; kwargs...)
        schema == _TI_MOD.W.SCHEMA && return _TI_MOD.load_fit(path; kwargs...)
        schema == _TI_MOD.ConcurrentWorkflow.PLAN_SCHEMA && return _TI_MOD.ConcurrentWorkflow.load(path; kwargs...)
        throw(ArgumentError("unsupported fit directory schema: $schema"))
    end
    isfile(path) || throw(ArgumentError("saved fit file does not exist: $path"))
    raw = open(Serialization.deserialize, path)
    if raw isa _SA_MOD.StarResult
        return _SA_MOD.load_fit(path; kwargs...)
    end
    if raw isa _TI_MOD.ConcurrentWorkflow.Fit
        all(k->k==:require_complete,keys(kwargs)) || throw(ArgumentError("unsupported concurrent fit reader controls"))
        complete=get(kwargs,:require_complete,true);complete isa Bool || throw(ArgumentError("require_complete must be Boolean"))
        _TI_MOD.ConcurrentWorkflow.checked(raw;complete,full=true);return raw
    end
    if raw isa AdditiveFacets.Fit
        isempty(kwargs) || throw(ArgumentError("unsupported additive fit reader controls: $(keys(kwargs))"))
        return AdditiveFacets.load_result(raw)
    end
    tag = _sample_schema_symbol(raw)
    tag === :correlated_3d && return _C3D_MOD.load_result(path; kwargs...)
    tag === :joint_ratings && return _JR_MOD.load_result(path; kwargs...)
    tag === :ordinal_association && return _OA_MOD.load_result(path; kwargs...)
    tag === :rater_group_effects && return _RGE_MOD.load_result(path; kwargs...)
    tag === :rater_item_interactions && return _RII_MOD.load_result(path; kwargs...)
    tag === :criterion_collapse && return _CC_MOD.load_result(path; kwargs...)
    return load_fit_cache(path; kwargs...)
end

"""
    save_report(path, report_or_fit; return_receipt=false, kwargs...)

Write a portable computed report without overwriting existing files. Pass a
computed report or a fitted result. Common fits use `save_fit_report`; Star and
experimental sample records use `posterior_summary` with the supplied keywords.
For rater-by-item records, `practical_threshold` is required; rater-group records
also require `reference_group`. No inference or
predictive generation occurs. Keep model-specific warnings and report structure.

With `return_receipt=true`, return `(path, sha256)` for every supported writer;
keep this receipt separately and pass its digest to `load_report`. Otherwise
the return value remains the existing writer's path or receipt. Reports contain
computed values, not draws for new analyses. Use `save_fit` for native draws.
Unsupported writer or summary controls raise an error.
"""
function save_report(path::AbstractString, rep; return_receipt::Bool=false, kwargs...)
    saved = _save_report(path, rep; kwargs...)
    return return_receipt ? (;path=abspath(path), sha256=bytes2hex(SHA.sha256(read(path)))) : saved
end

function _save_report(path::AbstractString, rep; kwargs...)
    if hasproperty(rep,:schema) && rep.schema in _TI_MOD.ConcurrentPriorPredictive.SCHEMAS
        isempty(kwargs) || throw(ArgumentError("prior predictive reports accept no extra writer controls"))
        return _TI_MOD.ConcurrentPriorPredictive.save(path,rep)
    end
    if hasproperty(rep,:schema) && rep.schema in _TI_MOD.ConcurrentPredictive.SCHEMAS
        isempty(kwargs) || throw(ArgumentError("unsupported posterior predictive writer controls"))
        return _TI_MOD.ConcurrentPredictive.save(path,rep)
    end
    if hasproperty(rep,:schema) && rep.schema == _PRIOR_POWER_SCHEMA
        isempty(kwargs) || throw(ArgumentError("unsupported prior-power writer controls"))
        _prediction_check_seal(rep, _PRIOR_POWER_SCHEMA)
        return _SA_MOD._save_atomic_json(path,rep)
    end
    if hasproperty(rep,:schema) && rep.schema in _TI_MOD.ConcurrentWorkflow.REPORT_SCHEMAS
        isempty(kwargs) || throw(ArgumentError("unsupported concurrent writer controls"))
        return _TI_MOD.ConcurrentWorkflow.save_report(path,rep)
    end
    if hasproperty(rep,:schema) && rep.schema==_TI_MOD.ConcurrentReports.SCHEMA
        isempty(kwargs) || throw(ArgumentError("unsupported concurrent report writer controls: $(keys(kwargs))"))
        return _TI_MOD.ConcurrentReports.save(path,rep)
    end
    if rep isa _SupportedCommonFit
        return save_fit_report(path, rep; kwargs...)
    elseif rep isa _SA_MOD.StarResult || _sample_schema_symbol(rep) !== nothing
        return save_report(path, posterior_summary(rep; kwargs...))
    elseif rep isa Union{_RD_MOD.SavedReport, _RD_MOD.SavedComparison}
        return _RD_MOD.save_report(path, rep; kwargs...)
    elseif rep isa _TI_MOD.SavedReport
        return _TI_MOD.save_report(path, rep; kwargs...)
    elseif rep isa NamedTuple && hasproperty(rep, :schema) && rep.schema isa AbstractString
        s = rep.schema
        if s == AdditiveFacets.REPORT_SCHEMA
            isempty(kwargs) || throw(ArgumentError("unsupported additive report controls: $(keys(kwargs))"))
            return AdditiveFacets.save_computed(path,rep)
        end
        s == _SA_MOD.REPORT_SCHEMA && return _SA_MOD.save_report(path, rep; kwargs...)
        s == "bayesianmgmfrm.joint_rating_api_report.v1" && return _JR_MOD.save_report(path, rep; kwargs...)
        s == "bayesianmgmfrm.ordinal_association_report.v1" && return _OA_MOD.save_report(path, rep; kwargs...)
        s == "bayesianmgmfrm.correlated_3d_report.v1" && return _C3D_MOD.save_report(path, rep; kwargs...)
        if startswith(s, "bayesianmgmfrm.fit_report")
            return save_fit_report(path, rep; kwargs...)
        end
    elseif rep isa AbstractDict && haskey(rep, "schema") && startswith(String(rep["schema"]), "bayesianmgmfrm.fit_report")
        return save_fit_report(path, rep; kwargs...)
    elseif rep isa NamedTuple && hasproperty(rep, :scope)
        sc = rep.scope
        if sc isa NamedTuple && get(sc, :interaction, nothing) === :rater_group
            return _RGE_MOD.save_report(path, rep; kwargs...)
        elseif sc isa NamedTuple && get(sc, :mechanism, nothing) === :criterion_collapse
            return _CC_MOD.save_report(path, rep; kwargs...)
        elseif hasproperty(rep, :cells) && hasproperty(rep, :practical_threshold)
            return _RII_MOD.save_report(path, rep; kwargs...)
        end
    end
    return _SA_MOD.save_report(path, rep; kwargs...)
end

"""
    load_report(path; expected_sha256=nothing, kwargs...)

Read a supported portable computed report or concurrent model specification.
The stored schema selects the reader;
no fitting or diagnostic recomputation occurs. The original report structure,
warnings and source metadata are retained.

`expected_sha256` checks the file against a separately retained lowercase SHA-256
receipt. It remains required for criterion-collapse, RaterDrift and ThreeIndicator
reports and is optional for other supported reports. Internal hash validation,
where present, is independent of this file check. A digest does not authenticate
a producer or establish statistical validity. Normalized PCM prior-power
reports also require this receipt and return computed JSON without recomputation.

Common report controls (`require_complete`, `verify_hash`, `return_record`) and
ThreeIndicator comparison controls go to their existing readers. Unsupported
controls or schemas raise an error. RaterDrift/ThreeIndicator return their saved
report objects; use `posterior_summary(saved)` to inspect computed values.
Concurrent model specifications return a `ConcurrentTarget`. Concurrent fixed-point
probability reports return their saved JSON object: inspect `.rows`, `.comparisons`
or `.recordings`/`.speakers` according to `.operation`. These require a checksum
receipt, accept no reader controls and contain no posterior uncertainty.
"""
function load_report(path::AbstractString; expected_sha256=nothing, kwargs...)
    isfile(path) || throw(ArgumentError("report file does not exist: $path"))
    bytes = read(path)
    if expected_sha256 !== nothing
        expected_sha256 isa AbstractString && occursin(r"^[0-9a-f]{64}$", expected_sha256) ||
            throw(ArgumentError("expected_sha256 must be a lowercase 64-digit SHA-256 receipt"))
        bytes2hex(SHA.sha256(bytes)) == expected_sha256 ||
            throw(ArgumentError("computed-report checksum mismatch: $path"))
    end
    parsed = JSON3.read(bytes)
    if hasproperty(parsed, :object) && parsed.object == "fit_report_export"
        return load_fit_report(path; kwargs...)
    end
    s = get(parsed, :schema, nothing)
    s isa AbstractString || throw(ArgumentError("computed report has no supported schema"))
    if s in _TI_MOD.ConcurrentPriorPredictive.SCHEMAS
        expected_sha256 === nothing && throw(ArgumentError("expected_sha256 is required for prior predictive reports"))
        isempty(kwargs) || throw(ArgumentError("prior predictive reports accept no extra reader controls"))
        return _TI_MOD.ConcurrentPriorPredictive.check_report(parsed)
    end
    if s in _TI_MOD.ConcurrentPredictive.SCHEMAS
        expected_sha256!==nothing || throw(ArgumentError("a separately retained expected_sha256 is required"))
        isempty(kwargs) || throw(ArgumentError("unsupported posterior predictive reader controls"))
        return _TI_MOD.ConcurrentPredictive.check_report(parsed)
    end
    if s == _PRIOR_POWER_SCHEMA
        expected_sha256 !== nothing || throw(ArgumentError("a separately retained expected_sha256 is required"))
        isempty(kwargs) || throw(ArgumentError("unsupported prior-power reader controls"))
        return parsed
    end
    if s in _TI_MOD.ConcurrentWorkflow.REPORT_SCHEMAS
        expected_sha256!==nothing || throw(ArgumentError("a separately retained expected_sha256 is required"))
        isempty(kwargs) || throw(ArgumentError("unsupported concurrent posterior reader controls"))
        return _TI_MOD.ConcurrentWorkflow.check_report(parsed)
    elseif s==_TI_MOD.Concurrent.ASSOCIATION_SCHEMA
        expected_sha256!==nothing || throw(ArgumentError("a separately retained expected_sha256 is required"))
        isempty(kwargs) || throw(ArgumentError("unsupported association model reader controls"))
        return _TI_MOD.Concurrent.load_association(path;expected_sha256)
    elseif s==_TI_MOD.ConcurrentReports.SCHEMA || s in _TI_MOD.ConcurrentReports.MODEL_SCHEMAS
        expected_sha256!==nothing || throw(ArgumentError("a separately retained expected_sha256 is required"))
        isempty(kwargs) || throw(ArgumentError("unsupported concurrent reader controls: $(keys(kwargs))"))
        return s==_TI_MOD.ConcurrentReports.SCHEMA ? _TI_MOD.ConcurrentReports.check(parsed) :
            _TI_MOD.ConcurrentTarget(path;expected_sha256)
    elseif s == AdditiveFacets.REPORT_SCHEMA
        isempty(kwargs) || throw(ArgumentError("unsupported additive report reader controls: $(keys(kwargs))"))
        return parsed
    elseif s == _SA_MOD.JSON_ENVELOPE_SCHEMA
        return _SA_MOD.load_report(path; kwargs...)
    elseif startswith(s, "bayesianmgmfrm.fit_report")
        return load_fit_report(path; kwargs...)
    elseif s == "bayesianmgmfrm.criterion_collapse_report.v1"
        return _CC_MOD.load_report(path; expected_sha256, kwargs...)
    elseif s in (_RD_MOD.SAVED_SCHEMA, _RD_MOD.SOURCE_SCHEMA, _RD_MOD.COMPARISON_SCHEMA,
                  "bayesianmgmfrm.rw1_package_report.v1", "bayesianmgmfrm.rw1_package_report.v2")
        return _RD_MOD.load_report(path; expected_sha256, kwargs...)
    elseif s in (_TI_MOD.SAVED_SCHEMA, _TI_MOD.W.SCHEMA, "bayesianmgmfrm.private_stan_report.v1")
        return _TI_MOD.load_report(path; expected_sha256, kwargs...)
    elseif s in ("bayesianmgmfrm.joint_rating_report_json.v1",
                  "bayesianmgmfrm.ordinal_association_json.v1",
                  "bayesianmgmfrm.rater_group_effect_report.v1",
                  "bayesianmgmfrm.rater_item_interaction_report.v1")
        isempty(kwargs) || throw(ArgumentError("unsupported report controls: $(keys(kwargs))"))
        hasproperty(parsed, :data) || throw(ArgumentError("computed report envelope has no data"))
        return parsed.data
    elseif s == "bayesianmgmfrm.correlated_3d_report.v1"
        isempty(kwargs) || throw(ArgumentError("unsupported report controls: $(keys(kwargs))"))
        return parsed
    end
    throw(ArgumentError("unsupported computed report schema: $s"))
end

"""
    BayesianMGMFRM.plot(x; kind = :posterior, kwargs...)

Unified visualization dispatcher across all package figure types (requires
loading `CairoMakie`).

Supported `kind` values:
- `:posterior` — posterior medians and credible intervals (`plot_posterior`)
- `:diagnostics` — chain trace and rank-histogram plots (`plot_diagnostics`)
- `:predictive` — posterior predictive category checks (`plot_predictive`)
- `:wright` — shared-logit Wright / ridge map (`plot_wright`)
- `:pathway` — location-by-infit/outfit Pathway map (`plot_pathway`)
- `:response_surface` — multidimensional category probability surfaces (`plot_response_surface`)
- `:design_precision` — study-design interval-width frequency plot (`plot_design_precision`)
- `:prior_sensitivity` — named estimand prior-sensitivity curves (`plot_prior_sensitivity`)
- `:prior_predictive_sensitivity` — prior-predictive sensitivity summaries (`plot_prior_predictive_sensitivity`)
- `:rater_drift` — dynamic rater-severity trajectories (`Experimental.RaterDrift.plot_trajectory`)
- `:criterion_collapse_classes` — rater latent-class probabilities (`Experimental.CriterionCollapse.plot_classes`)
- `:criterion_collapse_categories` — class-specific category curves (`Experimental.CriterionCollapse.plot_categories`)
"""
function plot(x; kind::Symbol = :posterior, kwargs...)
    if x isa _SA_MOD.StarResult
        extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
        extension === nothing && throw(ArgumentError(
            "BayesianMGMFRM.plot requires CairoMakie; install it with Pkg.add(\"CairoMakie\") and run `using CairoMakie`",
        ))
        return extension.plot_star_result(x; kind, kwargs...)
    end
    kind === :posterior && return plot_posterior(x; kwargs...)
    kind === :diagnostics && return plot_diagnostics(x; kwargs...)
    kind === :predictive && return plot_predictive(x; kwargs...)
    kind === :wright && return plot_wright(x; kwargs...)
    kind === :pathway && return plot_pathway(x; kwargs...)
    kind === :response_surface && return plot_response_surface(x; kwargs...)
    kind === :design_precision && return plot_design_precision(x; kwargs...)
    kind === :prior_sensitivity && return plot_prior_sensitivity(x; kwargs...)
    kind === :prior_predictive_sensitivity && return plot_prior_predictive_sensitivity(x; kwargs...)
    kind === :rater_drift && return _RD_MOD.plot_trajectory(x; kwargs...)
    kind === :criterion_collapse_classes && return _CC_MOD.plot_classes(x; kwargs...)
    kind === :criterion_collapse_categories && return _CC_MOD.plot_categories(x; kwargs...)
    throw(ArgumentError(
        "unknown plot kind $(repr(kind)); choose :posterior, :diagnostics, :predictive, :wright, :pathway, :response_surface, :design_precision, :prior_sensitivity, :prior_predictive_sensitivity, :rater_drift, :criterion_collapse_classes, or :criterion_collapse_categories",
    ))
end
