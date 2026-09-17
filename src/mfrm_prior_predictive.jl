# Prior simulation uses the same free-coordinate measure and response kernel as fitting.
function _fixed_q_prior_target(spec::FacetSpec, prior::MFRMPrior)
    _is_mfrm_fixed_q(spec) || throw(ArgumentError("expected a multidimensional MFRM specification"))
    return _MFRMFixedQReferenceLogDensity(spec; prior)
end

_fixed_q_prior_target(spec::CorrelatedMFRMSpec, prior::MFRMPrior) =
    _MFRMFixedQCorrelated2DLogDensity(spec.base_spec; prior, lkj_eta = spec.lkj_eta)

function _fixed_q_prior_draws(target, ndraws::Int, rng::AbstractRNG)
    ndraws > 0 || throw(ArgumentError("ndraws must be positive"))
    correlated = target isa _MFRMFixedQCorrelated2DLogDensity
    base = correlated ? target.base : target
    draws = Matrix{Float64}(undef, ndraws, LogDensityProblems.dimension(target))
    correlation_prior = correlated ? Turing.Beta(target.lkj_eta, target.lkj_eta) : nothing
    for row in eachrow(draws)
        for i in 1:LogDensityProblems.dimension(base)
            row[i] = _source_fixture_prior_sd(base, i) * randn(rng)
        end
        if correlated
            # In two dimensions LKJ(eta) is rho = 2 Beta(eta, eta) - 1.
            # Generate in d_rho, then transform; do not weight by a Jacobian again.
            rho = 2rand(rng, correlation_prior) - 1
            -1 < rho < 1 || throw(ArgumentError("prior simulation generated a boundary correlation; use another RNG seed"))
            row[end] = atanh(rho)
            person = base.blueprint.blocks[:person]
            for i in first(person):2:last(person)
                row[i+1] = rho * row[i] + sqrt((1-rho) * (1+rho)) * row[i+1]
            end
        end
    end
    all(isfinite, draws) || throw(ArgumentError("prior simulation generated nonfinite coordinates; check prior scales"))
    return draws
end

function _fixed_q_prior_bundle(spec; prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng())
    target = _fixed_q_prior_target(spec, prior)
    draws = _fixed_q_prior_draws(target, ndraws, rng)
    base = target isa _MFRMFixedQCorrelated2DLogDensity ? target.base : target
    direct = _mfrm_fixed_q_predictive_draws(base, view(draws, :, 1:LogDensityProblems.dimension(base)))
    return (; target, base, draws, direct)
end

function _fixed_q_prior_predict(spec; prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng())
    bundle = _fixed_q_prior_bundle(spec; prior, ndraws, rng)
    return _replicate_scores_mgmfrm_direct(bundle.base.base.design, bundle.direct, rng)
end

function _fixed_q_prior_predictive_check(spec; prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000, rng::AbstractRNG = Random.default_rng(),
        min_category_probability::Real = 0.01, prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    _check_prior_implication_controls(; min_category_probability,
        prior_warning_probability, wide_facet_range_fraction)
    bundle = _fixed_q_prior_bundle(spec; prior, ndraws, rng)
    target, base, draws = bundle.target, bundle.base, bundle.draws
    correlated = target isa _MFRMFixedQCorrelated2DLogDensity
    data = base.design.spec.data
    replicated = _replicate_scores_mgmfrm_direct(base.base.design, bundle.direct, rng)
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    implication_diagnostics = _prior_predictive_implication_diagnostics(data, observed, replicated_summary;
        min_category_probability, prior_warning_probability, wide_facet_range_fraction)
    coordinates = _mfrm_fixed_q_model_coordinates(target, draws)
    parameter_summary = [merge(_finite_draw_summary(row.values, 0.025, 0.975),
        (; row.parameter, row.block, row.dimension, row.fixed, row.derived,
            parameter_space = get(row, :parameter_space, row.fixed && row.block in
                (:item_dimension_discrimination, :rater_consistency) ? :dimensionless : :unit_logit),
            interval_probability = 0.95)) for row in coordinates]
    prior_record = correlated ? (;
        base = _mfrm_fixed_q_prior_record(base),
        correlation = Base.structdiff(_mfrm_correlated_2d_contract(target),
            (; fitting_available = nothing, cache_available = nothing))) : _mfrm_fixed_q_prior_record(base)
    return (;
        schema = "bayesianmgmfrm.fixed_q_prior_predictive_check.v1",
        model = correlated ? :mfrm_fixed_q_correlated_2d : :mfrm_fixed_q,
        stability = :experimental, prior = prior_record,
        dimension_labels = copy(base.design.spec.dimension_labels), q_matrix = copy(base.design.spec.q_matrix),
        observed, replicated = replicated_summary, replicated_scores = replicated,
        grouped = _predictive_grouped_summary(base.design.spec, replicated),
        parameter_draws = draws, parameter_names = copy(target.blueprint.parameter_names),
        parameter_space = correlated ? :unit_logit_and_fisher_z : :unit_logit_free,
        model_coordinates = coordinates, parameter_summary, implication_diagnostics,
        category_levels = copy(data.category_levels), person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels), item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

function _fixed_q_prior_plot_data(check; interval::Real = 0.95, kwargs...)
    get(check, :schema, nothing) == "bayesianmgmfrm.fixed_q_prior_predictive_check.v1" ||
        throw(ArgumentError("plot_prior requires a fixed-coefficient MFRM prior_predictive_check result"))
    selected = _select_posterior_coordinates(copy(check.model_coordinates), check.dimension_labels; kwargs...)
    selected.scale === :model || throw(ArgumentError("prior plots use scale = :model"))
    constraints = Dict(:person => "zero-centered prior; fixed marginal scale",
        :item => "zero-centered prior", :rater => "sum to zero",
        :item_steps => "first step zero sum to zero", :latent_correlation => "LKJ prior on population correlation")
    return _posterior_interval_data(selected; interval, constraints, diagnostic = "Prior simulation")
end

"""
    BayesianMGMFRM.plot_prior(check; interval = 0.95, block = nothing,
        dimension = nothing, parameters = nothing, max_parameters = 60, size = nothing)

Plot parameter medians and central prior intervals from a fixed-coefficient
MFRM `Experimental.prior_predictive_check` result. Load `CairoMakie` first;
returns an editable Figure for display or PDF/SVG saving. No posterior fitting
or additional random simulation occurs. Select named dimensions or parameter
blocks as in `plot_posterior`. Correlated models support `block = :latent_correlation`.
Locations and reconstructed steps use unit logits; rho uses its correlation
scale. Diamonds are fixed coefficients/baseline steps, not estimated precision.
`check.parameter_summary` contains 95% numerical intervals for all coordinates.
"""
function plot_prior(check::NamedTuple; size = nothing, kwargs...)
    data = _fixed_q_prior_plot_data(check; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("plot_prior requires `using CairoMakie`"))
    model = check.model === :mfrm_fixed_q_correlated_2d ? "Correlated MFRM" : "Multidimensional MFRM"
    caption = "Medians and $(round(100data.interval; digits=4))% central prior intervals; " *
        "$(length(data.rows)) of $(data.total) coordinates shown.\n" *
        "$(Base.size(check.parameter_draws, 1)) independent joint prior draws; no posterior fitting.\n" *
        "Diamonds: fixed coefficients or baseline steps. Derived intervals use reconstructed draws.\n" *
        "Model support: experimental. Prior plausibility does not establish identification or recovery."
    units = Dict(:item_dimension_discrimination => "Loading (dimensionless)",
        :rater_consistency => "Consistency (dimensionless)", :latent_correlation => "Population correlation (rho)")
    return extension._render_posterior(data; title = "$model prior intervals",
        dimension_labels = check.dimension_labels, xlabel = units, caption, size)
end
