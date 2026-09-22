# Consumers of validated records; neither the fit layout nor v1 artifacts change.
function _mgmfrm_correlated_2d_coordinates(target, raw, direct; scale::Symbol = :model)
    scale in (:model, :raw) || throw(ArgumentError("scale must be :model or :raw"))
    base, design = target.base.blueprint, target.base.design
    spec, data = design.spec, design.spec.data
    model = scale === :model
    blocks = model ? design.blocks : base.blocks
    names = model ? design.parameter_names : base.parameter_names
    draws = model ? direct : raw
    mapping = Dict(:rater_free => :rater,
        :log_item_dimension_discrimination => :item_dimension_discrimination,
        :log_rater_consistency_free => :rater_consistency)
    block_for = Dict(i => get(mapping, block, block) for (block, range) in blocks for i in range)
    fixed = Set(_structurally_fixed_constrained_parameter_names(base))
    rows = NamedTuple[]
    for (i, name) in enumerate(names)
        block = block_for[i]
        dimension = block === :person ? mod1(i - first(blocks[:person]) + 1, 2) :
            block === :item_dimension_discrimination ? only(findall(spec.q_matrix[
                i - first(blocks[model ? :item_dimension_discrimination : :log_item_dimension_discrimination]) + 1, :])) : nothing
        derived = model && ((block === :rater && i == last(blocks[:rater])) ||
            (block === :rater_consistency && i == last(blocks[:rater_consistency])))
        space = model ? (block in (:item_dimension_discrimination, :rater_consistency) ? :dimensionless : :model_coordinate) : :raw_unconstrained
        push!(rows, (; parameter = name, values = view(draws, :, i), block, dimension,
            fixed = model && name in fixed, derived, parameter_space = space))
    end
    if model
        # Include baseline and reconstructed last steps, which are absent from direct columns.
        K = length(data.category_levels)
        for (i, item) in enumerate(data.item_levels), k in (1, K)
            values = [Float64(_source_step_value(design, row, :item_steps, i, k)) for row in eachrow(direct)]
            push!(rows, (; parameter = "item_step[item=$item,m=$k]", values, block = :item_steps,
                dimension = nothing, fixed = k == 1 || K == 2, derived = k == K,
                parameter_space = :model_coordinate))
        end
        steps = Dict(row.parameter => row for row in rows if row.block === :item_steps)
        rows = vcat(filter(row -> row.block !== :item_steps, rows),
            [steps["item_step[item=$item,m=$k]"] for item in data.item_levels for k in 1:K])
    end
    push!(rows, (; parameter = model ? only(target.blueprint.derived_parameter_names) : last(target.blueprint.parameter_names),
        values = model ? tanh.(raw[:, end]) : view(raw, :, size(raw, 2)),
        block = :latent_correlation, dimension = nothing, fixed = false, derived = model,
        parameter_space = model ? :correlation : :fisher_z))
    return rows
end

function _mgmfrm_correlated_2d_report_context(fit::_CorrelatedMGMFRMFit)
    checked = _mgmfrm_correlated_2d_samples(fit)
    record = checked.record
    target = _mgmfrm_free_latent_correlation_2d_logdensity(record.spec;
        prior = _SourceFixturePrior(; record.prior.scales...), lkj_eta = record.prior.lkj_eta)
    direct = view(checked.diagnostics.direct_values.direct_draws, :, 1:length(target.base.design.parameter_names))
    return (; fit, checked, target, direct, diagnostics = diagnostics(fit))
end

function _mgmfrm_correlated_2d_report_coordinates(context; scale = :model)
    return _mgmfrm_correlated_2d_coordinates(context.target, context.checked.record.run.draws,
        context.direct; scale)
end

function _mgmfrm_correlated_2d_coordinate_summary(coordinates, labels; interval)
    # Shared finite-draw summaries; every coordinate supplies its own scale.
    return _fixed_q_prior_parameter_rows(coordinates, labels; interval)
end

function _mgmfrm_correlated_2d_report_prior_policy(record)
    rows = [(; block, parameter = scale, value = getproperty(record.prior.scales, scale),
        meaning = block === :person ? "Fixed marginal SD of conditional bivariate abilities" :
            "Fixed SD of zero-centered normal free raw coordinates", estimated = false)
        for (block, scale) in ((:person, :person_sd), (:rater, :rater_sd), (:item, :item_sd),
            (:item_dimension_discrimination, :log_discrimination_sd),
            (:rater_consistency, :log_consistency_sd), (:item_steps, :step_sd))]
    push!(rows, (; block = :latent_correlation, parameter = :lkj_eta, value = record.prior.lkj_eta,
        meaning = "Fixed normalized LKJ shape on population rho; not an SD", estimated = false))
    R, K = length(record.spec.data.rater_levels), length(record.spec.data.category_levels)
    return (; status = :computed, rows, n_rows = length(rows),
        interpretation = "Ability pairs have covariance person_sd^2 * [1 rho; rho 1]; rho is estimated. Other free raw coordinates have independent normal priors. Positive loadings and product-one consistencies use log coordinates. These transforms add no Jacobian to the declared raw-coordinate density. LKJ is declared on rho; Fisher z contributes log(1-rho^2) exactly once. Locations and loading/ability scales are prior-anchored: ratings alone admit shifts and rescaling. For this $R-rater, $K-category design, the last rater severity has variance (R-1)*rater_sd^2, the last free-step reconstruction has variance (K-2)*step_sd^2, and the last log-consistency has variance (R-1)*log_consistency_sd^2. Thus with more than two raters the prior depends on the chosen last rater; exchangeability is not implied. All SDs and eta are fixed inputs, not learned hyperparameters.")
end

function _mgmfrm_correlated_2d_predictive_section(fit; interval, ndraws, draw_indices, seed)
    rng, control = _fit_rng(Random.default_rng(), seed)
    check = posterior_predictive_check(fit; ndraws, draw_indices, rng)
    run = fit.record.run
    rows = predictive_check_summary(check; interval, include_grouped = true)
    selection = draw_indices !== nothing ? "Explicit ordered draw indices" :
        ndraws === nothing ? "All retained draws in stored order" : "Draw indices sampled with replacement"
    return (; rows, n_rows = length(rows), check.draw_indices, check.prediction_target,
        check.prior, check.target_identity, check.source_sample_content_hash, check.sampling_quality,
        chain_ids = run.chain_ids[check.draw_indices], iterations = run.iterations[check.draw_indices],
        rng = control, selection, n_replicates = length(check.draw_indices),
        n_unique_draws = length(unique(check.draw_indices)), n_retained = size(run.draws, 1),
        n_observations = fit.record.spec.data.n,
        interpretation = "Conditional on joint posterior draws for the existing persons, items, raters and rating rows. Population rho is already reflected in sampled abilities and is not applied again. Central $(100interval)% pointwise intervals summarize replicated statistics, not parameter uncertainty or Monte Carlo error. Same-data agreement does not establish convergence, recovery or accuracy for new facet levels.")
end

"""
    fit_report(fit::Experimental.CorrelatedMGMFRMFit; view = :public,
        posterior_lower = 0.025, posterior_upper = 0.975,
        predictive_interval = 0.9, include_prior_predictive = false,
        prior_predictive_ndraws = 100, prior_interval = 0.95, seed = 1, ...)

Explain the saved correlated MGMFRM, its prior, MCMC warnings, model-coordinate
summaries and MCSE, and conditional existing-row predictions. Optional prior
checks reconstruct the saved prior; they never substitute default scales.
Posterior bounds must be central. Summaries/diagnostics use all retained draws;
only posterior prediction uses `ndraws` or ordered `draw_indices`.

Reports default to reader-facing output. `view = :full` retains reproduction
details. `on_section_error = :capture` exposes failed optional sections;
`require_complete = true` rejects them. Report completeness does not certify
MCMC quality, identification or scientific acceptance. Save portable Markdown,
JSON and tables with `save_fit_report_bundle`; this report is not a fit cache.
"""
function fit_report(fit::_CorrelatedMGMFRMFit; view::Symbol = :public,
        posterior_lower::Real = 0.025, posterior_upper::Real = 0.975,
        predictive_interval::Real = 0.9, include_posterior_predictive::Bool = true,
        include_prior_predictive::Bool = false, prior_predictive_ndraws::Int = 100,
        prior_interval::Real = 0.95, ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing,
        seed::Integer = 1, include_artifact::Bool = true, include_full_artifact::Bool = false,
        split_chains::Bool = fit.record.run.split_chains_requested,
        rhat_threshold::Real = fit.record.run.checked.rhat_threshold,
        ess_threshold::Real = fit.record.run.checked.ess_threshold,
        on_section_error::Symbol = :capture, require_complete::Bool = false)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    lower, upper = _check_posterior_summary_bounds(posterior_lower, posterior_upper)
    interval = upper - lower
    0 < interval < 1 && isapprox(lower + upper, 1; atol = 8eps(Float64), rtol = 0) ||
        throw(ArgumentError("correlated MGMFRM reports require central posterior bounds strictly inside (0, 1)"))
    _interval_probabilities(prior_interval); _interval_probabilities(predictive_interval)
    seed isa Bool && throw(ArgumentError("seed must be an integer, not Bool"))
    _, rng_control = _fit_rng(Random.default_rng(), seed)
    !include_posterior_predictive && (ndraws !== nothing || draw_indices !== nothing) &&
        throw(ArgumentError("draw selection requires include_posterior_predictive = true"))
    !include_artifact && include_full_artifact && throw(ArgumentError("include_full_artifact requires include_artifact"))
    policy = _fit_report_on_section_error(on_section_error)
    context = _mgmfrm_correlated_2d_report_context(fit)
    diagnostics(fit; split_chains, rhat_threshold, ess_threshold)
    record, run = context.checked.record, context.checked.record.run
    spec = record.spec; labels = spec.dimension_labels
    coordinates = _mgmfrm_correlated_2d_report_coordinates(context)
    metadata = merge(fit_metadata(fit), (; backend_label = run.backend === :advancedhmc ? "Julia (AdvancedHMC)" : "CmdStan",
        scale_convention = "Prior-anchored model coordinates; response multiplier 1.7; rho on correlation scale",
        source_sample_schema = record.schema, source_sample_content_hash = record.content_hash,
        interpretation = "Experimental correlated MGMFRM: positive loadings, product-one rater consistency and population rho are estimated. Q fixes the zero pattern, not active loading values. Supported operations do not establish scientific acceptance."))
    posterior = _fit_report_section(policy) do
        rows = posterior_summary(fit; lower, upper)
        (; rows, n_rows = length(rows), interpretation = "Raw computational coordinates; the last coordinate is Fisher z. All retained draws; central $(100interval)% credible intervals. Use the model-coordinate section for positive loadings, consistencies and rho.")
    end
    direct_posterior = _fit_report_section(policy) do
        rows = _mgmfrm_correlated_2d_coordinate_summary(coordinates, labels; interval)
        mcse = _posterior_mcse_rows(hcat(getproperty.(coordinates, :values)...), getproperty.(coordinates, :parameter),
            run.controls.chains; probabilities = (lower, 0.5, upper), parameter_space = :direct_constrained,
            structurally_fixed_parameters = Set(row.parameter for row in coordinates if row.fixed))
        mcse_rows = [merge(row, (; c.block, c.dimension, c.fixed, c.derived, c.parameter_space,
            dimension_label = c.dimension === nothing ? missing : labels[c.dimension])) for (row, c) in zip(mcse, coordinates)]
        (; rows, n_rows = length(rows), mcse_rows,
            correlation_rows = filter(row -> row.block === :latent_correlation, rows),
            correlation_mcse_rows = filter(row -> row.block === :latent_correlation, mcse_rows),
            interpretation = "Named model coordinates, including reconstructed last-rater/step constraints and population rho. All retained draws; central $(100interval)% credible intervals. Rho intervals and MCSE use tanh-transformed draws. MCSE measures simulation precision, not posterior uncertainty; no precision acceptance margin is applied. Fixed point intervals are constants, not estimated certainty. Inactive Q loadings are structural zeros listed in the Q table.")
    end
    posterior_predictive = include_posterior_predictive ? _fit_report_section(policy) do
        _mgmfrm_correlated_2d_predictive_section(fit; interval = predictive_interval, ndraws, draw_indices, seed)
    end : _fit_report_not_requested()
    prior_predictive = include_prior_predictive ? _fit_report_section(policy) do
        model = _CorrelatedMGMFRMSpec(spec; lkj_eta = record.prior.lkj_eta)
        prior = GeneralizedPrior(; record.prior.scales...)
        check = _mgmfrm_correlated_2d_prior_predictive_check(model; prior, ndraws = prior_predictive_ndraws,
            rng = first(_fit_rng(Random.default_rng(), seed)))
        prior_coordinates = _mgmfrm_correlated_2d_coordinates(context.target,
            check.raw_parameter_draws, Base.view(check.direct_parameter_draws, :, 1:size(context.direct, 2)))
        parameter_rows = _mgmfrm_correlated_2d_coordinate_summary(prior_coordinates, labels; interval = prior_interval)
        rows = predictive_check_summary(check; interval = predictive_interval, include_grouped = true)
        (; model = check.model, stability = :experimental, dimension_labels = copy(labels), check.prior,
            check.target_identity, check.prediction_target, rows, n_rows = length(rows), parameter_rows,
            correlation_rows = filter(row -> row.block === :latent_correlation, parameter_rows),
            ndraws = prior_predictive_ndraws, n_observations = spec.data.n, rng = rng_control,
            parameter_interval = Float64(prior_interval), predictive_interval = Float64(predictive_interval),
            implication_diagnostics = check.implication_diagnostics,
            interpretation = "Joint prior draws from the saved scales and LKJ shape. Observed scores are only a comparison and do not update the prior. Parameter intervals describe prior uncertainty; predictive intervals describe replicated statistics on the existing rating design. Prior plausibility does not establish identification, convergence, recovery or new-level accuracy.")
    end : _fit_report_not_requested()
    rating_design = _fit_report_section(policy) do
        audit = rating_design_audit(spec)
        rows = collect(audit.rows)
        (; rows, n_rows = length(rows), summary = audit.summary)
    end
    artifact = include_artifact ? _fit_report_section(policy) do
        value = fit_artifact(fit; include_environment = false)
        (; schema = value.schema, content_hash = value.content_hash, archive_manifest = value.archive_manifest,
            artifact = include_full_artifact ? value : nothing)
    end : _fit_report_not_requested()
    warning_rows = context.diagnostics.summary.flag === :ok ? NamedTuple[] :
        [(; code = :mcmc_warning, severity = :warning, message = _plot_diagnostic_note(context.diagnostics.summary),
            action = :inspect_parameter_and_sampler_diagnostics)]
    fixed_rows = [(; row.parameter, row.block, value = first(row.values), fixed = true) for row in coordinates if row.fixed]
    q_rows = [(; item = spec.data.item_levels[i], dimension = d, dimension_label = labels[d],
        active = spec.q_matrix[i, d], loading = spec.q_matrix[i, d] ? :estimated_positive : :fixed_zero)
        for i in axes(spec.q_matrix, 1) for d in 1:2]
    unsupported = (; (name => _fit_report_unsupported("$label is not connected for this correlated MGMFRM result.")
        for (name, label) in ((:category_functioning, "Category-functioning analysis"),
            (:rater_homogeneity, "Rater-homogeneity analysis"), (:mcmc_budget_guidance, "MCMC-budget guidance"),
            (:calibration, "Calibration analysis"), (:waic, "WAIC"), (:loo, "LOO"), (:dff, "DFF analysis")))...)
    report = merge((; schema = "bayesianmgmfrm.fit_report.v1", object = :fit_report, created_at = string(now()),
        family = :mgmfrm, model = metadata.model, estimation_status = :experimental,
        thresholds = spec.thresholds, dimensions = 2, dimension_labels = copy(labels), metadata,
        report_policy = (; posterior_lower = lower, posterior_upper = upper, posterior_interval = interval,
            predictive_interval = Float64(predictive_interval), include_posterior_predictive,
            include_prior_predictive, prior_predictive_ndraws, prior_interval = Float64(prior_interval),
            ndraws, draw_indices = draw_indices === nothing ? nothing : collect(draw_indices),
            resolved_draw_indices = get(posterior_predictive, :draw_indices, nothing), rng = rng_control,
            include_artifact, include_full_artifact, on_section_error = policy, require_complete),
        diagnostics = merge(context.diagnostics, (; status = :computed, warning_rows,
            correlation_rows = filter(row -> row.parameter == last(coordinates).parameter, context.diagnostics.direct_parameter_rows),
            interpretation = "Whole-fit diagnostics use all retained draws and the saved thresholds, even when prediction selects a subset. Inspect raw and direct coordinates, divergences, tree depth and energy coverage before inference. Report completeness does not establish MCMC quality.")),
        warmup = (; status = :computed, rows = context.checked.warmup_diagnostics,
            n_rows = length(context.checked.warmup_diagnostics), interpretation = _FIT_REPORT_WARMUP_INTERPRETATION),
        fixed_coordinates = (; status = :computed, rows = fixed_rows, n_rows = length(fixed_rows),
            interpretation = "Baseline steps and any single-rater constraints are fixed. Active loadings are estimated; inactive Q entries are zero."),
        q_matrix = (; status = :computed, rows = q_rows, n_rows = length(q_rows), q_matrix = copy(spec.q_matrix),
            dimension_labels = copy(labels), interpretation = "Between-item Q fixes the loading pattern. Each active loading is positive and estimated; rho is the estimated population correlation between dimensions."),
        prior_policy = _mgmfrm_correlated_2d_report_prior_policy(record),
        pooling_policy = (; status = :computed, rows = [(; parameter = :rho, estimated = true,
            meaning = "Population correlation; marginal SDs and LKJ shape are fixed inputs")], n_rows = 1,
            interpretation = "Conditionally correlated ability pairs; other free coordinates have independent priors and reconstructed constraints induce dependence. No arbitrary grouping effects or learned variance components are fitted."),
        rating_design, artifact, posterior, direct_posterior, posterior_predictive, prior_predictive), unsupported)
    health = _derive_fit_report_health(report)
    report = merge(report, (; report_status = health.status, report_health = health))
    require_complete && _require_complete_fit_report(report, :fit_report)
    return view === :public ? fit_report_public(report) : report
end

fit_report_public(fit::_CorrelatedMGMFRMFit; kwargs...) = fit_report_public(fit_report(fit; kwargs...))

function _mgmfrm_correlated_2d_plot_identity(context)
    record = context.checked.record
    return (; model = context.checked.model, dimension_labels = copy(record.spec.dimension_labels),
        backend = record.run.backend, target_identity = record.target_identity,
        prior_label = "Correlated MGMFRM | LKJ eta = $(record.prior.lkj_eta) | fixed raw-prior scales")
end

function _mgmfrm_correlated_2d_plot_constraints()
    return Dict(:person => "prior-anchored scale/location", :item => "prior-anchored location",
        :rater => "sum to zero", :item_dimension_discrimination => "positive estimated loadings",
        :rater_consistency => "positive; product one", :item_steps => "first step zero sum to zero",
        :latent_correlation => "estimated population correlation")
end

function _mgmfrm_correlated_2d_plot_data(context; scale::Symbol = :model, interval::Real = 0.95, kwargs...)
    _interval_probabilities(interval)
    selected = _select_posterior_coordinates(_mgmfrm_correlated_2d_report_coordinates(context; scale),
        context.checked.record.spec.dimension_labels; scale, kwargs...)
    data = _posterior_interval_data(selected; interval, diagnostic = _plot_diagnostic_note(context.diagnostics.summary),
        constraints = _mgmfrm_correlated_2d_plot_constraints())
    return merge(data, _mgmfrm_correlated_2d_plot_identity(context), (;
        fixed_note = "Diamonds: fixed baselines or single-rater constraints. Derived intervals use reconstructed draws; inactive Q loadings are zero and omitted."))
end

function _mgmfrm_correlated_2d_diagnostic_plot_data(context; scale::Symbol = :model,
        max_parameters::Int = 12, bins = 20, view::Symbol = :parameters, kwargs...)
    view === :parameters || throw(ArgumentError("correlated MGMFRM diagnostics support view = :parameters only"))
    bins isa Integer && !(bins isa Bool) && bins > 0 || throw(ArgumentError("bins must be a positive integer"))
    selected = _select_posterior_coordinates(_mgmfrm_correlated_2d_report_coordinates(context; scale),
        context.checked.record.spec.dimension_labels; scale, max_parameters, kwargs...)
    run = context.checked.record.run
    metrics = scale === :model ? context.diagnostics.direct_parameter_rows : context.diagnostics.parameter_rows
    data = _trace_rank_plot_data(selected, metrics, context.diagnostics, run;
        bins, nchains = run.controls.chains, per_chain = run.controls.ndraws)
    return merge(data, _mgmfrm_correlated_2d_plot_identity(context))
end

function _mgmfrm_correlated_2d_predictive_plot_data(context, section; interval)
    section.status === :computed || throw(ArgumentError("predictive figure requires a computed posterior_predictive section"))
    rows = predictive_check_plot_data(filter(row -> row.statistic === :category_proportion, section.rows))
    return merge((; rows, interval = Float64(interval), section.draw_indices, section.chain_ids,
        section.iterations, section.rng, section.selection, section.n_replicates, section.n_unique_draws,
        section.n_retained, section.n_observations, diagnostic = _plot_diagnostic_note(context.diagnostics.summary)),
        _mgmfrm_correlated_2d_plot_identity(context))
end

function _render_mgmfrm_correlated_2d(extension, kind, data; size = nothing)
    model = "Experimental correlated MGMFRM (estimated loadings and consistency)"
    backend = data.backend === :advancedhmc ? "Julia (AdvancedHMC)" : "CmdStan"
    units = Dict(block => "Model coordinate (prior-anchored)" for block in (:person, :item, :rater, :item_steps))
    merge!(units, Dict(:item_dimension_discrimination => "Positive loading", :rater_consistency => "Positive consistency",
        :latent_correlation => "Population correlation (rho)"))
    if kind in (:posterior, :diagnostics, :prior)
        scale = get(data, :scale, :model)
        xlabel = scale === :raw ? "Raw coordinate (correlation: Fisher z)" : units
        kind === :diagnostics && return extension._render_diagnostics(data;
            title = "$model chain diagnostics\n$backend", ylabel = xlabel, size)
        title = "$model\n$backend | $(kind === :prior ? "prior" : "posterior") intervals"
        # Reserve space for the model identity and prior/diagnostic footnotes,
        # including a one-coordinate rho panel.
        size === nothing && (size = (1050, 40 * length(data.rows) + 110 * length(data.groups) + 300))
        return extension._render_posterior(data; title, dimension_labels = data.dimension_labels,
            xlabel, size, caption = kind === :prior ? _prior_caption(data) : extension._posterior_caption(data))
    end
    kind === :prior_predictive && return extension._render_predictive(data;
        title = "$model\nPrior predictive check | Category proportions", size, caption = _prior_predictive_caption(data))
    return extension._render_predictive(data;
        title = "$model\n$backend | Posterior predictive check\nCategory proportions", size)
end

"""
    BayesianMGMFRM.plot_posterior(fit::Experimental.CorrelatedMGMFRMFit; kwargs...)

Plot named dimensions, estimated positive loadings/consistencies or population
rho from a saved result. Use `block = :latent_correlation` for rho or
`block = :person, dimension = "label"` for abilities. Supports `scale = :model`
(default) or `:raw`; raw correlation is Fisher z. Intervals use all retained
draws and the footer retains whole-fit warnings. Requires `using CairoMakie`.
"""
function plot_posterior(fit::_CorrelatedMGMFRMFit; size = nothing, kwargs...)
    extension = _mgmfrm_correlated_2d_plot_extension()
    return _render_mgmfrm_correlated_2d(extension, :posterior,
        _mgmfrm_correlated_2d_plot_data(_mgmfrm_correlated_2d_report_context(fit); kwargs...); size)
end

"""
    BayesianMGMFRM.plot_diagnostics(fit::Experimental.CorrelatedMGMFRMFit; kwargs...)

Trace/rank plots in model coordinates (default) or `scale = :raw`. Select a
block, named dimension or exact parameters as in `plot_posterior`. Derived
steps without stored convergence diagnostics are labelled unavailable; whole-fit
warnings remain visible. Only `view = :parameters` is supported. Requires CairoMakie.
"""
function plot_diagnostics(fit::_CorrelatedMGMFRMFit; size = nothing, kwargs...)
    extension = _mgmfrm_correlated_2d_plot_extension()
    return _render_mgmfrm_correlated_2d(extension, :diagnostics,
        _mgmfrm_correlated_2d_diagnostic_plot_data(_mgmfrm_correlated_2d_report_context(fit); kwargs...); size)
end

"""
    BayesianMGMFRM.plot_predictive(fit::Experimental.CorrelatedMGMFRMFit;
        interval = 0.9, ndraws = nothing, draw_indices = nothing, seed = 1, size = nothing)

Plot conditional existing-row category proportions with pointwise predictive
intervals and whole-fit warnings. A local seed reproduces draw selection and
replications after reload; it leaves the global RNG unchanged. Requires CairoMakie.
"""
function plot_predictive(fit::_CorrelatedMGMFRMFit; interval::Real = 0.9,
        ndraws::Union{Nothing,Int} = nothing, draw_indices = nothing, seed::Integer = 1, size = nothing)
    _interval_probabilities(interval)
    seed isa Bool && throw(ArgumentError("seed must be an integer, not Bool"))
    extension = _mgmfrm_correlated_2d_plot_extension()
    context = _mgmfrm_correlated_2d_report_context(fit)
    section = merge(_mgmfrm_correlated_2d_predictive_section(fit; interval, ndraws, draw_indices, seed), (; status = :computed))
    return _render_mgmfrm_correlated_2d(extension, :predictive,
        _mgmfrm_correlated_2d_predictive_plot_data(context, section; interval); size)
end

function _mgmfrm_correlated_2d_plot_extension()
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("correlated MGMFRM figures require `using CairoMakie`"))
    return extension
end

"""
    save_fit_report_bundle(directory, fit::Experimental.CorrelatedMGMFRMFit;
        view = :public, figures = nothing, seed = 1, kwargs...)

Save Markdown, JSON and tables; optional `figures` adds editable PDF/SVG and
their numerical inputs. Available kinds are `posterior`, `diagnostics`,
`predictive`, `prior` and `prior_predictive`. Prior figures require
`include_prior_predictive = true`. Set intervals, draw selection and seed on
this call so report and figures agree; figure-specific overrides are rejected.
All figures are prepared before replacing a bundle. Requires CairoMakie only
when figures are requested. No posterior sampling occurs.
"""
function save_fit_report_bundle(directory::AbstractString, fit::_CorrelatedMGMFRMFit;
        figures = nothing, view::Symbol = :public, seed::Integer = 1, overwrite::Bool = false,
        label = nothing, title::AbstractString = "Correlated MGMFRM report", max_rows::Integer = 6,
        include_empty::Bool = false, require_complete::Bool = false, kwargs...)
    view in (:full, :public) || throw(ArgumentError("view must be :full or :public"))
    if figures === nothing
        report = fit_report(fit; view, seed, require_complete, kwargs...)
        return _save_fit_report_bundle(directory, report; overwrite, label, title, max_rows, include_empty, require_complete)
    end
    _fit_report_figure_options(figures)
    haskey(figures, :wright) && throw(ArgumentError("correlated MGMFRM bundles do not support Wright maps"))
    any(kind -> haskey(figures, kind), (:prior, :prior_predictive)) && !get(kwargs, :include_prior_predictive, false) &&
        throw(ArgumentError("prior figures require include_prior_predictive = true"))
    extension = _check_fit_report_figure_destination(directory, figures; overwrite, max_rows)
    report = fit_report(fit; view = :full, seed, require_complete, kwargs...)
    exported = view === :public ? fit_report_public(report) : report
    context = _mgmfrm_correlated_2d_report_context(fit)
    identity = (; report.family, report.dimension_labels, report.metadata.backend,
        report.metadata.scale_convention, report.metadata.target_identity,
        report.metadata.source_sample_schema, report.metadata.source_sample_content_hash)
    return _write_fit_report_figures(directory, exported, figures;
            identity, seed, overwrite, label, title, max_rows, include_empty, require_complete) do kind, numerical, size
        data = if kind === :posterior
            _mgmfrm_correlated_2d_plot_data(context; interval = report.report_policy.posterior_interval, numerical...)
        elseif kind === :diagnostics
            _mgmfrm_correlated_2d_diagnostic_plot_data(context; numerical...)
        elseif kind === :predictive
            _mgmfrm_correlated_2d_predictive_plot_data(context, report.posterior_predictive; interval = report.report_policy.predictive_interval)
        else
            prior_data = _report_prior_plot_data(report.prior_predictive, kind; numerical...)
            merge(prior_data, _mgmfrm_correlated_2d_plot_identity(context),
                kind === :prior ? (; constraints = _mgmfrm_correlated_2d_plot_constraints()) : (;))
        end
        (; data, figure = _render_mgmfrm_correlated_2d(extension, kind, data; size))
    end
end
