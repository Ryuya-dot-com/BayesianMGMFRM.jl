# simulation_and_recovery.jl -- Prior/posterior predictive checks, response simulation, recovery evaluation, and validation grids.

function _sample_category_index(rng::AbstractRNG, probs::AbstractVector{Float64})
    !isempty(probs) && all(p -> isfinite(p) && 0 <= p <= 1, probs) &&
        isapprox(sum(probs), 1.0) ||
        throw(ArgumentError("predictive category probabilities must be finite, nonnegative and sum to one"))
    u = rand(rng)
    cumulative = 0.0
    for category in eachindex(probs)
        cumulative += probs[category]
        u <= cumulative && return category
    end
    return lastindex(probs)
end

function _replicate_scores(design::FacetDesign, draws::AbstractMatrix, rng::AbstractRNG)
    size(draws, 2) == length(design.parameter_names) ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $(length(design.parameter_names))"))
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(draws, 1), data.n)
    probs = zeros(Float64, K)

    for replication in axes(draws, 1)
        params = @view draws[replication, :]
        for row in 1:data.n
            _category_probabilities!(probs, design, params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _replicate_scores_gmfrm_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        rng::AbstractRNG,
        caller::AbstractString = "posterior_predict")
    checked = _gmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        caller,
    )
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(checked, 1), data.n)
    probs = zeros(Float64, K)

    for replication in axes(checked, 1)
        direct_params = @view checked[replication, :]
        for row in 1:data.n
            _gmfrm_category_probabilities!(probs, design, direct_params, row)
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _replicate_scores_mgmfrm_direct(
        design::FacetDesign,
        direct_draws::AbstractMatrix,
        rng::AbstractRNG,
        caller::AbstractString = "posterior_predict")
    checked = _mgmfrm_direct_draws_for_prediction(
        design,
        direct_draws,
        caller,
    )
    data = design.spec.data
    K = length(data.category_levels)
    replicated = Matrix{Int}(undef, size(checked, 1), data.n)
    probs = zeros(Float64, K)
    loading_indices = _mgmfrm_source_loading_index_matrix(design)

    for replication in axes(checked, 1)
        direct_params = @view checked[replication, :]
        for row in 1:data.n
            _mgmfrm_category_probabilities!(
                probs,
                design,
                loading_indices,
                direct_params,
                row,
            )
            category = _sample_category_index(rng, probs)
            replicated[replication, row] = data.category_levels[category]
        end
    end
    return replicated
end

function _prior_parameter_draws(design::FacetDesign,
        prior::MFRMPrior,
        ndraws::Int,
        rng::AbstractRNG)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    nparams = length(design.parameter_names)
    draws = Matrix{Float64}(undef, ndraws, nparams)
    for draw in 1:ndraws, param in 1:nparams
        draws[draw, param] = _prior_sd(design, prior, param) * randn(rng)
    end
    return draws
end

function _guarded_generalized_prior_target(design::FacetDesign, prior)
    if design.spec.family === :gmfrm
        checked_prior = _experimental_gmfrm_prior(prior)
        return _gmfrm_promotion_candidate_logdensity(design;
            prior = checked_prior)
    elseif design.spec.family === :mgmfrm
        checked_prior = _guarded_mgmfrm_prior(prior)
        return _mgmfrm_guarded_local_fit_logdensity(design;
            prior = checked_prior)
    end
    throw(ArgumentError(
        "generalized prior prediction requires family = :gmfrm " *
        "or :mgmfrm",
    ))
end

function _guarded_generalized_direct_params(
        target::_GMFRMPromotionCandidateLogDensity,
        raw_params::AbstractVector)
    return _gmfrm_source_constrained_params_from_unconstrained(
        target.design,
        raw_params,
    )
end

function _guarded_generalized_direct_params(
        target::_MGMFRMGuardedLocalFitLogDensity,
        raw_params::AbstractVector)
    return _mgmfrm_source_constrained_params_from_unconstrained(
        target.design,
        raw_params,
    )
end

function _guarded_generalized_prior_draw_bundle(
        spec::FacetSpec,
        caller::AbstractString;
        prior = nothing,
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng())
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    _check_guarded_generalized_spec(
        spec,
        caller,
    )
    design = getdesign(spec; preview = true)
    target = _guarded_generalized_prior_target(design, prior)
    raw_draws = _guarded_generalized_prior_draws(target, ndraws, rng)
    return _generalized_prior_bundle_from_draws(target, raw_draws)
end

# Retain the legacy draw order and RNG consumption for successful generation.
# Alternative targets transform these normals before direct reconstruction.
function _guarded_generalized_prior_draws(target::_GeneralizedCandidateLogDensity,
        ndraws::Int, rng::AbstractRNG)
    ndraws >= 1 || throw(ArgumentError("ndraws must be positive"))
    nraw = target.blueprint.n_parameters
    raw_draws = Matrix{Float64}(undef, ndraws, nraw)
    for draw in 1:ndraws
        for parameter in 1:nraw
            raw_draws[draw, parameter] =
                _source_fixture_prior_sd(target, parameter) * randn(rng)
        end
    end
    return raw_draws
end

function _generalized_prior_bundle_from_draws(target::_GeneralizedCandidateLogDensity,
        raw_draws::Matrix{Float64}; prior_record = target.prior)
    ndirect = length(target.design.parameter_names)
    direct_draws = Matrix{Float64}(undef, size(raw_draws, 1), ndirect)
    for draw in axes(raw_draws, 1)
        direct = _guarded_generalized_direct_params(
            target,
            @view(raw_draws[draw, :]),
        )
        length(direct) == ndirect || throw(ArgumentError(
            "generalized raw-to-direct transform returned $(length(direct)) " *
            "parameters; expected $ndirect",
        ))
        direct_draws[draw, :] .= direct
    end
    return (;
        design = target.design,
        prior = prior_record,
        raw_draws,
        direct_draws,
        raw_parameter_names = copy(target.blueprint.parameter_names),
        direct_parameter_names = copy(target.design.parameter_names),
    )
end

function _guarded_generalized_replicate_scores(bundle, rng::AbstractRNG,
        caller::AbstractString)
    bundle.design.spec.family === :gmfrm &&
        return _replicate_scores_gmfrm_direct(
            bundle.design,
            bundle.direct_draws,
            rng,
            caller,
        )
    bundle.design.spec.family === :mgmfrm &&
        return _replicate_scores_mgmfrm_direct(
            bundle.design,
            bundle.direct_draws,
            rng,
            caller,
        )
    throw(ArgumentError("$caller requires family = :gmfrm or :mgmfrm"))
end

function _experimental_generalized_prior_predict(
        spec::FacetSpec;
        prior = nothing,
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng())
    bundle = _guarded_generalized_prior_draw_bundle(
        spec,
        "Experimental.prior_predict";
        prior,
        ndraws,
        rng,
    )
    return _guarded_generalized_replicate_scores(
        bundle,
        rng,
        "Experimental.prior_predict",
    )
end

"""
    prior_predict(spec_or_design; prior = MFRMPrior(), ndraws = 1000,
        rng = Random.default_rng())

Generate replicated score matrices from prior draws for the minimal MFRM
design. The returned matrix has one replicated dataset per row and one rating
observation per column, with entries on the original integer score scale.
"""
function prior_predict(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng())
    draws = _prior_parameter_draws(design, prior, ndraws, rng)
    return _replicate_scores(design, draws, rng)
end

prior_predict(spec::FacetSpec; kwargs...) = prior_predict(getdesign(spec); kwargs...)

"""
    posterior_predict(fit::MFRMFit; ndraws = nothing, draw_indices = nothing,
        rng = Random.default_rng())

Generate replicated score matrices from posterior draws. The returned matrix
has one replicated dataset per row and one rating observation per column, with
entries on the original integer score scale.
"""
function posterior_predict(fit::MFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _replicate_scores(fit.design, fit.draws[indices, :], rng)
end

function posterior_predict(fit::GMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _replicate_scores_gmfrm_direct(
        fit.design,
        fit.direct_draws[indices, :],
        rng,
    )
end

function posterior_predict(fit::MGMFRMFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    return _replicate_scores_mgmfrm_direct(
        fit.design,
        fit.direct_draws[indices, :],
        rng,
    )
end

function _mean_score(scores::AbstractVector{<:Integer})
    isempty(scores) && return NaN
    return sum(Float64, scores) / length(scores)
end

function _category_proportions(scores::AbstractVector{<:Integer}, levels::AbstractVector{Int})
    counts = zeros(Float64, length(levels))
    level_index = Dict(level => index for (index, level) in pairs(levels))
    for score in scores
        counts[level_index[score]] += 1
    end
    if !isempty(scores)
        counts ./= length(scores)
    end
    return counts
end

function _facet_mean_scores(scores::AbstractVector{<:Integer},
        index::AbstractVector{Int},
        levels::AbstractVector)
    sums = zeros(Float64, length(levels))
    counts = zeros(Int, length(levels))
    for row in eachindex(scores)
        facet_index = index[row]
        sums[facet_index] += scores[row]
        counts[facet_index] += 1
    end
    return [counts[i] == 0 ? NaN : sums[i] / counts[i] for i in eachindex(levels)]
end

function _predictive_summary(data::FacetData, scores::AbstractVector{<:Integer})
    length(scores) == data.n ||
        throw(ArgumentError("scores has length $(length(scores)); expected $(data.n)"))
    optional_mean = Dict{Symbol,Vector{Float64}}()
    for facet in sort(collect(keys(data.optional)); by = string)
        optional_mean[facet] = _facet_mean_scores(scores,
            data.optional[facet],
            data.optional_levels[facet])
    end
    return (;
        mean_score = _mean_score(scores),
        category_proportions = _category_proportions(scores, data.category_levels),
        person_mean = _facet_mean_scores(scores, data.person, data.person_levels),
        rater_mean = _facet_mean_scores(scores, data.rater, data.rater_levels),
        item_mean = _facet_mean_scores(scores, data.item, data.item_levels),
        optional_mean,
    )
end

function _replicated_summaries(data::FacetData, replicated::AbstractMatrix{<:Integer})
    nrep = size(replicated, 1)
    ncategory = length(data.category_levels)
    nperson = length(data.person_levels)
    nrater = length(data.rater_levels)
    nitem = length(data.item_levels)
    mean_score = Vector{Float64}(undef, nrep)
    category_proportions = Matrix{Float64}(undef, nrep, ncategory)
    person_mean = Matrix{Float64}(undef, nrep, nperson)
    rater_mean = Matrix{Float64}(undef, nrep, nrater)
    item_mean = Matrix{Float64}(undef, nrep, nitem)
    optional_mean = Dict{Symbol,Matrix{Float64}}(
        facet => Matrix{Float64}(undef, nrep, length(data.optional_levels[facet]))
        for facet in sort(collect(keys(data.optional)); by = string)
    )

    for replication in 1:nrep
        summary = _predictive_summary(data, vec(replicated[replication, :]))
        mean_score[replication] = summary.mean_score
        category_proportions[replication, :] .= summary.category_proportions
        person_mean[replication, :] .= summary.person_mean
        rater_mean[replication, :] .= summary.rater_mean
        item_mean[replication, :] .= summary.item_mean
        for facet in keys(optional_mean)
            optional_mean[facet][replication, :] .= summary.optional_mean[facet]
        end
    end
    return (;
        mean_score,
        category_proportions,
        person_mean,
        rater_mean,
        item_mean,
        optional_mean,
    )
end

function _cell_mean_score(scores::AbstractVector{<:Integer},
        observations::AbstractVector{Int})
    isempty(observations) && return NaN
    total = 0.0
    @inbounds for observation in observations
        total += scores[observation]
    end
    return total / length(observations)
end

function _replicated_cell_mean_scores(replicated::AbstractMatrix{<:Integer},
        observations::AbstractVector{Int})
    means = Vector{Float64}(undef, size(replicated, 1))
    if isempty(observations)
        fill!(means, NaN)
        return means
    end
    @inbounds for replication in axes(replicated, 1)
        total = 0.0
        for observation in observations
            total += replicated[replication, observation]
        end
        means[replication] = total / length(observations)
    end
    return means
end

function _dff_cell_observations(data::FacetData,
        index_a::AbstractVector{Int},
        level_a::Int,
        index_b::AbstractVector{Int},
        level_b::Int)
    observations = Int[]
    for observation in 1:data.n
        if index_a[observation] == level_a && index_b[observation] == level_b
            push!(observations, observation)
        end
    end
    return observations
end

function _push_dff_predictive_group_rows!(rows::Vector{NamedTuple},
        data::FacetData,
        replicated::AbstractMatrix{<:Integer},
        term::Tuple{Symbol,Symbol})
    facet_a = _facet(data, term[1])
    facet_b = _facet(data, term[2])
    facet_a === nothing &&
        throw(ArgumentError("DFF term $(term) references unknown facet :$(term[1])"))
    facet_b === nothing &&
        throw(ArgumentError("DFF term $(term) references unknown facet :$(term[2])"))
    index_a, levels_a = facet_a
    index_b, levels_b = facet_b
    for level_a_index in eachindex(levels_a), level_b_index in eachindex(levels_b)
        observations = _dff_cell_observations(
            data,
            index_a,
            level_a_index,
            index_b,
            level_b_index,
        )
        level_a = levels_a[level_a_index]
        level_b = levels_b[level_b_index]
        push!(rows, (;
            statistic = :dff_cell_mean,
            level = (term = term, cell = (level_a, level_b)),
            facet_a = term[1],
            facet_b = term[2],
            level_a,
            level_b,
            n_observations = length(observations),
            observed = _cell_mean_score(data.score, observations),
            replicated = _replicated_cell_mean_scores(replicated, observations),
        ))
    end
    return rows
end

function _push_sparse_design_block_predictive_rows!(rows::Vector{NamedTuple},
        data::FacetData,
        replicated::AbstractMatrix{<:Integer})
    cells = Dict{Tuple{Int,Int,Int},Vector{Int}}()
    for observation in 1:data.n
        key = (data.person[observation], data.rater[observation], data.item[observation])
        push!(get!(cells, key, Int[]), observation)
    end
    ordered_keys = sort(collect(keys(cells)); by = key -> string((
        data.person_levels[key[1]],
        data.rater_levels[key[2]],
        data.item_levels[key[3]],
    )))
    for key in ordered_keys
        observations = cells[key]
        person = data.person_levels[key[1]]
        rater = data.rater_levels[key[2]]
        item = data.item_levels[key[3]]
        push!(rows, (;
            statistic = :sparse_design_block_mean,
            level = (person = person, rater = rater, item = item),
            block = :person_rater_item,
            person,
            rater,
            item,
            n_observations = length(observations),
            observed = _cell_mean_score(data.score, observations),
            replicated = _replicated_cell_mean_scores(replicated, observations),
        ))
    end
    return rows
end

function _predictive_grouped_summary(spec::FacetSpec,
        replicated::AbstractMatrix{<:Integer})
    data = spec.data
    rows = NamedTuple[]
    for term in sort(copy(spec.validation_bias_terms); by = string)
        _push_dff_predictive_group_rows!(rows, data, replicated, term)
    end
    n_dff_cells = length(rows)
    _push_sparse_design_block_predictive_rows!(rows, data, replicated)
    return (;
        schema = "bayesianmgmfrm.predictive_grouped_summary.v1",
        rows,
        n_dff_terms = length(spec.validation_bias_terms),
        n_dff_cells,
        n_sparse_design_blocks = length(rows) - n_dff_cells,
    )
end

function _check_prior_implication_controls(;
        min_category_probability::Real,
        prior_warning_probability::Real,
        wide_facet_range_fraction::Real)
    isfinite(min_category_probability) && 0 <= min_category_probability <= 1 ||
        throw(ArgumentError("min_category_probability must be finite and in [0, 1]"))
    isfinite(prior_warning_probability) && 0 < prior_warning_probability <= 1 ||
        throw(ArgumentError("prior_warning_probability must be finite and in (0, 1]"))
    isfinite(wide_facet_range_fraction) && wide_facet_range_fraction >= 0 ||
        throw(ArgumentError("wide_facet_range_fraction must be finite and non-negative"))
    return (;
        min_category_probability = Float64(min_category_probability),
        prior_warning_probability = Float64(prior_warning_probability),
        wide_facet_range_fraction = Float64(wide_facet_range_fraction),
    )
end

function _finite_range(values::AbstractVector{<:Real})
    finite = [Float64(value) for value in values if isfinite(value)]
    isempty(finite) && return NaN
    length(finite) == 1 && return 0.0
    return maximum(finite) - minimum(finite)
end

function _row_ranges(values::AbstractMatrix{<:Real})
    ranges = Vector{Float64}(undef, size(values, 1))
    for row in axes(values, 1)
        ranges[row] = _finite_range(@view values[row, :])
    end
    return ranges
end

function _prior_category_implication_rows(data::FacetData,
        replicated_summary,
        controls)
    rows = NamedTuple[]
    lower_probability, upper_probability = _interval_probabilities(0.9)
    for (index, category) in pairs(data.category_levels)
        replicated = @view replicated_summary.category_proportions[:, index]
        summary = _finite_draw_summary(replicated, lower_probability, upper_probability)
        probability_empty = count(==(0.0), replicated) / length(replicated)
        probability_below_min =
            count(<(controls.min_category_probability), replicated) / length(replicated)
        flag =
            probability_empty >= controls.prior_warning_probability ? :prior_category_nonuse :
            probability_below_min >= controls.prior_warning_probability ? :prior_category_sparse :
            :ok
        push!(rows, (;
            category,
            observed_proportion =
                _category_proportions(data.score, data.category_levels)[index],
            observed_empty =
                _category_proportions(data.score, data.category_levels)[index] == 0.0,
            replicated_mean_proportion = summary.mean,
            replicated_median_proportion = summary.median,
            replicated_lower_proportion = summary.lower,
            replicated_upper_proportion = summary.upper,
            interval_probability = 0.9,
            lower_probability,
            upper_probability,
            min_category_probability = controls.min_category_probability,
            probability_empty,
            probability_below_min_category_probability = probability_below_min,
            prior_warning_probability = controls.prior_warning_probability,
            n_replicates = length(replicated),
            flag,
        ))
    end
    return rows
end

function _prior_facet_range_row(facet::Symbol,
        levels,
        observed_means::AbstractVector{<:Real},
        replicated_means::AbstractMatrix{<:Real},
        score_range::Float64,
        controls)
    lower_probability, upper_probability = _interval_probabilities(0.9)
    ranges = _row_ranges(replicated_means)
    summary = _finite_draw_summary(ranges, lower_probability, upper_probability)
    wide_range_threshold = score_range * controls.wide_facet_range_fraction
    probability_wide_range = count(>=(wide_range_threshold), ranges) / length(ranges)
    return (;
        facet,
        n_levels = length(levels),
        observed_range = _finite_range(observed_means),
        replicated_mean_range = summary.mean,
        replicated_median_range = summary.median,
        replicated_lower_range = summary.lower,
        replicated_upper_range = summary.upper,
        interval_probability = 0.9,
        lower_probability,
        upper_probability,
        score_range,
        wide_facet_range_fraction = controls.wide_facet_range_fraction,
        wide_range_threshold,
        probability_wide_range,
        prior_warning_probability = controls.prior_warning_probability,
        n_replicates = length(ranges),
        flag = probability_wide_range >= controls.prior_warning_probability ?
            :prior_wide_facet_range : :ok,
    )
end

function _prior_facet_range_rows(data::FacetData,
        observed_summary,
        replicated_summary,
        controls)
    score_range = Float64(maximum(data.category_levels) - minimum(data.category_levels))
    rows = NamedTuple[]
    push!(rows, _prior_facet_range_row(:person,
        data.person_levels,
        observed_summary.person_mean,
        replicated_summary.person_mean,
        score_range,
        controls))
    push!(rows, _prior_facet_range_row(:rater,
        data.rater_levels,
        observed_summary.rater_mean,
        replicated_summary.rater_mean,
        score_range,
        controls))
    push!(rows, _prior_facet_range_row(:item,
        data.item_levels,
        observed_summary.item_mean,
        replicated_summary.item_mean,
        score_range,
        controls))
    for facet in sort(collect(keys(data.optional)); by = string)
        push!(rows, _prior_facet_range_row(facet,
            data.optional_levels[facet],
            observed_summary.optional_mean[facet],
            replicated_summary.optional_mean[facet],
            score_range,
            controls))
    end
    return rows
end

function _prior_category_use_summary(data::FacetData,
        replicated_summary,
        controls)
    used_by_replication = [
        count(>(0.0), @view replicated_summary.category_proportions[replication, :])
        for replication in axes(replicated_summary.category_proportions, 1)
    ]
    lower_probability, upper_probability = _interval_probabilities(0.9)
    summary = _finite_draw_summary(used_by_replication, lower_probability, upper_probability)
    n_categories = length(data.category_levels)
    probability_all_categories_used = count(==(n_categories), used_by_replication) /
        length(used_by_replication)
    probability_missing_any_category = 1 - probability_all_categories_used
    return (;
        observed_n_categories_used =
            count(>(0.0), _category_proportions(data.score, data.category_levels)),
        replicated_mean_n_categories_used = summary.mean,
        replicated_median_n_categories_used = summary.median,
        replicated_lower_n_categories_used = summary.lower,
        replicated_upper_n_categories_used = summary.upper,
        interval_probability = 0.9,
        lower_probability,
        upper_probability,
        n_categories,
        probability_all_categories_used,
        probability_missing_any_category,
        prior_warning_probability = controls.prior_warning_probability,
        n_replicates = length(used_by_replication),
        flag = probability_missing_any_category >= controls.prior_warning_probability ?
            :prior_category_collapse : :ok,
    )
end

function _prior_predictive_implication_diagnostics(data::FacetData,
        observed_summary,
        replicated_summary;
        min_category_probability::Real,
        prior_warning_probability::Real,
        wide_facet_range_fraction::Real)
    controls = _check_prior_implication_controls(;
        min_category_probability,
        prior_warning_probability,
        wide_facet_range_fraction)
    category_rows = _prior_category_implication_rows(
        data,
        replicated_summary,
        controls,
    )
    facet_range_rows = _prior_facet_range_rows(
        data,
        observed_summary,
        replicated_summary,
        controls,
    )
    category_use = _prior_category_use_summary(data, replicated_summary, controls)
    flag = any(row -> row.flag !== :ok, category_rows) ||
        any(row -> row.flag !== :ok, facet_range_rows) ||
        category_use.flag !== :ok ? :prior_implication_warning : :ok
    return (;
        schema = "bayesianmgmfrm.prior_predictive_implication_diagnostics.v1",
        flag,
        controls,
        category_use,
        category_rows,
        facet_range_rows,
    )
end

function _tail_probabilities(values::AbstractVector{<:Real}, observed::Real)
    obs = Float64(observed)
    vals = [Float64(value) for value in values if isfinite(value)]
    isempty(vals) && return (lower = NaN, upper = NaN, two_sided = NaN)
    if !isfinite(obs)
        return (lower = NaN, upper = NaN, two_sided = NaN)
    end
    lower = count(<=(obs), vals) / length(vals)
    upper = count(>=(obs), vals) / length(vals)
    return (;
        lower,
        upper,
        two_sided = min(1.0, 2 * min(lower, upper)),
    )
end

function _predictive_check_row(statistic::Symbol,
        level,
        observed::Real,
        replicated::AbstractVector{<:Real},
        interval::Real,
        lower_probability::Float64,
        upper_probability::Float64;
        metadata = NamedTuple())
    summary = _finite_draw_summary(replicated, lower_probability, upper_probability)
    tails = _tail_probabilities(replicated, observed)
    obs = Float64(observed)
    outside = isfinite(obs) &&
        (obs < summary.lower || obs > summary.upper)
    return merge((;
        statistic,
        level,
        observed = obs,
        replicated_mean = summary.mean,
        replicated_median = summary.median,
        replicated_lower = summary.lower,
        replicated_upper = summary.upper,
        interval_probability = Float64(interval),
        lower_probability,
        upper_probability,
        lower_tail_probability = tails.lower,
        upper_tail_probability = tails.upper,
        two_sided_tail_probability = tails.two_sided,
        n_replicates = count(value -> isfinite(Float64(value)), replicated),
        flag = outside ? :outside_interval : :ok,
    ), metadata)
end

function _require_predictive_check_fields(check)
    for field in (:observed, :replicated, :category_levels, :person_levels, :rater_levels, :item_levels, :optional_levels)
        hasproperty(check, field) ||
            throw(ArgumentError("predictive check object is missing .$field"))
    end
    return nothing
end

function _require_predictive_grouped_fields(check)
    hasproperty(check, :grouped) ||
        throw(ArgumentError("predictive check object is missing .grouped"))
    hasproperty(check.grouped, :rows) ||
        throw(ArgumentError("predictive check grouped object is missing .rows"))
    return nothing
end

function _predictive_grouped_row_metadata(row)
    if row.statistic === :dff_cell_mean
        return (;
            n_observations = row.n_observations,
            facet_a = row.facet_a,
            facet_b = row.facet_b,
            level_a = row.level_a,
            level_b = row.level_b,
        )
    elseif row.statistic === :sparse_design_block_mean
        return (;
            n_observations = row.n_observations,
            block = row.block,
            person = row.person,
            rater = row.rater,
            item = row.item,
        )
    end
    return (; n_observations = row.n_observations)
end

"""
    predictive_check_summary(check; interval = 0.9, include_grouped = false)

Summarize a `prior_predictive_check` or `posterior_predictive_check` result as
rows with observed values, replicated means, replicated intervals, and tail
probabilities. The current summary covers overall mean score, category
proportions, person-level mean scores, rater-level mean scores, item-level mean
scores, and optional facet mean scores. Set `include_grouped = true` to append
DFF-cell and observed sparse-design-block mean-score rows from checks generated
by current `prior_predictive_check` or `posterior_predictive_check` objects.
"""
function predictive_check_summary(check; interval::Real = 0.9,
        include_grouped::Bool = false)
    _require_predictive_check_fields(check)
    include_grouped && _require_predictive_grouped_fields(check)
    lower_probability, upper_probability = _interval_probabilities(interval)
    observed = check.observed
    replicated = check.replicated
    rows = NamedTuple[]

    push!(rows, _predictive_check_row(:mean_score, missing,
        observed.mean_score,
        replicated.mean_score,
        interval,
        lower_probability,
        upper_probability))

    for (index, level) in pairs(check.category_levels)
        push!(rows, _predictive_check_row(:category_proportion, level,
            observed.category_proportions[index],
            @view(replicated.category_proportions[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.person_levels)
        push!(rows, _predictive_check_row(:person_mean, level,
            observed.person_mean[index],
            @view(replicated.person_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.rater_levels)
        push!(rows, _predictive_check_row(:rater_mean, level,
            observed.rater_mean[index],
            @view(replicated.rater_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for (index, level) in pairs(check.item_levels)
        push!(rows, _predictive_check_row(:item_mean, level,
            observed.item_mean[index],
            @view(replicated.item_mean[:, index]),
            interval,
            lower_probability,
            upper_probability))
    end

    for facet in sort(collect(keys(check.optional_levels)); by = string)
        levels = check.optional_levels[facet]
        for (index, level) in pairs(levels)
            push!(rows, _predictive_check_row(Symbol(facet, :_mean), level,
                observed.optional_mean[facet][index],
                @view(replicated.optional_mean[facet][:, index]),
                interval,
                lower_probability,
                upper_probability))
        end
    end

    if include_grouped
        for row in check.grouped.rows
            push!(rows, _predictive_check_row(row.statistic,
                row.level,
                row.observed,
                row.replicated,
                interval,
                lower_probability,
                upper_probability;
                metadata = _predictive_grouped_row_metadata(row)))
        end
    end

    return rows
end

"""
    prior_predictive_check(spec_or_design; prior = MFRMPrior(), ndraws = 1000,
        rng = Random.default_rng(), min_category_probability = 0.01,
        prior_warning_probability = 0.95, wide_facet_range_fraction = 0.8)

Generate prior predictive replicated scores and compact observed-vs-replicated
summaries for the minimal MFRM design. The returned object includes the prior
parameter draws used to generate `replicated_scores` and prior-implication
diagnostics for category use and facet-score ranges. It also includes grouped
DFF-cell and observed sparse-design-block mean-score summaries for
`predictive_check_summary(...; include_grouped = true)`.
"""
function prior_predictive_check(design::FacetDesign;
        prior::MFRMPrior = MFRMPrior(),
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng(),
        min_category_probability::Real = 0.01,
        prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    draws = _prior_parameter_draws(design, prior, ndraws, rng)
    replicated = _replicate_scores(design, draws, rng)
    data = design.spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(design.spec, replicated)
    implication_diagnostics = _prior_predictive_implication_diagnostics(
        data,
        observed,
        replicated_summary;
        min_category_probability,
        prior_warning_probability,
        wide_facet_range_fraction,
    )
    return (;
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        parameter_draws = draws,
        implication_diagnostics,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

prior_predictive_check(spec::FacetSpec; kwargs...) =
    prior_predictive_check(getdesign(spec); kwargs...)

function _experimental_generalized_prior_predictive_check(
        spec::FacetSpec;
        prior = nothing,
        ndraws::Int = 1000,
        rng::AbstractRNG = Random.default_rng(),
        min_category_probability::Real = 0.01,
        prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    bundle = _guarded_generalized_prior_draw_bundle(
        spec,
        "Experimental.prior_predictive_check";
        prior,
        ndraws,
        rng,
    )
    prior_record = (;
        parameter_space = :raw_unconstrained_coordinates,
        family = :independent_zero_centered_normal,
        scales = _source_fixture_prior_values(bundle.prior),
        jacobian_policy = :none_raw_coordinate_density,
    )
    return _generalized_prior_check_from_bundle(bundle; prior_record, rng,
        min_category_probability, prior_warning_probability, wide_facet_range_fraction)
end

# The caller must supply the actual distribution record. Free coordinates alone
# do not imply independent raw priors (normalized priors use the same chart).
function _generalized_prior_check_from_bundle(bundle; prior_record, rng::AbstractRNG,
        min_category_probability::Real = 0.01,
        prior_warning_probability::Real = 0.95,
        wide_facet_range_fraction::Real = 0.8)
    replicated = _guarded_generalized_replicate_scores(
        bundle,
        rng,
        "Experimental.prior_predictive_check",
    )
    data = bundle.design.spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(bundle.design.spec, replicated)
    implication_diagnostics = _prior_predictive_implication_diagnostics(
        data,
        observed,
        replicated_summary;
        min_category_probability,
        prior_warning_probability,
        wide_facet_range_fraction,
    )
    return (;
        schema =
            "bayesianmgmfrm.experimental_generalized_prior_predictive_check.v1",
        model_family = bundle.design.spec.family,
        stability = :experimental,
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        parameter_draws = bundle.raw_draws,
        parameter_space = :raw_unconstrained_coordinates,
        raw_parameter_draws = bundle.raw_draws,
        direct_parameter_draws = bundle.direct_draws,
        raw_parameter_names = bundle.raw_parameter_names,
        direct_parameter_names = bundle.direct_parameter_names,
        prior = prior_record,
        implication_diagnostics,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(
            facet => copy(levels)
            for (facet, levels) in data.optional_levels
        ),
    )
end

"""
    posterior_predictive_check(fit::MFRMFit; ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Generate posterior predictive replicated scores and compact observed-vs-
replicated summaries for the minimal MFRM design. The summary currently covers
overall mean score, category proportions, person-level mean scores, rater-level
mean scores, item-level mean scores, optional facet mean scores, and grouped
DFF-cell and observed sparse-design-block mean-score rows for
`predictive_check_summary(...; include_grouped = true)`.
"""
function posterior_predictive_check(fit::_ModelComparisonFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    replicated = posterior_predict(fit; draw_indices = indices, rng)
    return _posterior_predictive_check(fit.design.spec, replicated, indices)
end

function _posterior_predictive_check(spec::FacetSpec, replicated::AbstractMatrix, indices)
    data = spec.data
    observed = _predictive_summary(data, data.score)
    replicated_summary = _replicated_summaries(data, replicated)
    grouped = _predictive_grouped_summary(spec, replicated)
    return (;
        observed,
        replicated = replicated_summary,
        grouped,
        replicated_scores = replicated,
        draw_indices = indices,
        category_levels = copy(data.category_levels),
        person_levels = copy(data.person_levels),
        rater_levels = copy(data.rater_levels),
        item_levels = copy(data.item_levels),
        optional_levels = Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
    )
end

function _check_simulation_output(output::Symbol)
    output in (:data, :table, :scores) ||
        throw(ArgumentError("output must be :data, :table, or :scores"))
    return output
end

function _simulated_response_table(data::FacetData, scores::AbstractVector{<:Integer})
    names = Symbol[:person, :rater, :item, :score]
    values = Any[
        [data.person_levels[index] for index in data.person],
        [data.rater_levels[index] for index in data.rater],
        [data.item_levels[index] for index in data.item],
        collect(Int, scores),
    ]
    for facet in sort(collect(keys(data.optional)); by = string)
        push!(names, facet)
        push!(values, [data.optional_levels[facet][index] for index in data.optional[facet]])
    end
    return NamedTuple{Tuple(names)}(Tuple(values))
end

function _facet_data_with_scores(data::FacetData, scores::AbstractVector{<:Integer})
    length(scores) == data.n ||
        throw(ArgumentError("scores has length $(length(scores)); expected $(data.n)"))
    category_index = Dict(level => index for (index, level) in pairs(data.category_levels))
    all(score -> haskey(category_index, score), scores) ||
        throw(ArgumentError("scores contain values outside the design category levels"))
    return FacetData(
        data.n,
        copy(data.person),
        copy(data.rater),
        copy(data.item),
        collect(Int, scores),
        [category_index[score] for score in scores],
        copy(data.person_levels),
        copy(data.rater_levels),
        copy(data.item_levels),
        copy(data.category_levels),
        Dict(facet => copy(index) for (facet, index) in data.optional),
        Dict(facet => copy(levels) for (facet, levels) in data.optional_levels),
        data.columns,
    )
end

function _check_simulation_parameter_space(parameter_space::Symbol)
    parameter_space in (:direct, :raw) ||
        throw(ArgumentError("parameter_space must be :direct or :raw"))
    return parameter_space
end

function _check_finite_parameter_values(params::AbstractVector, caller::AbstractString)
    all(value -> isfinite(Float64(value)), params) ||
        throw(ArgumentError("$caller parameter vector contains non-finite values"))
    return params
end

function _generalized_simulation_direct_params(design::FacetDesign,
        params::AbstractVector,
        parameter_space::Symbol,
        caller::AbstractString)
    _check_finite_parameter_values(params, caller)
    if design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        direct = parameter_space === :raw ?
            _gmfrm_source_constrained_params_from_unconstrained(design, params) :
            collect(Float64, params)
        _gmfrm_direct_draws_for_prediction(design, reshape(direct, 1, :), caller)
        return direct
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        direct = parameter_space === :raw ?
            _mgmfrm_source_constrained_params_from_unconstrained(design, params) :
            collect(Float64, params)
        _mgmfrm_direct_draws_for_prediction(design, reshape(direct, 1, :), caller)
        return direct
    end
    throw(ArgumentError(
        "$caller currently supports fit-supported MFRM/RSM/PCM designs and " *
        "specified-only GMFRM/MGMFRM preview designs",
    ))
end

"""
    simulate_responses(spec_or_design, params; rng = Random.default_rng(),
        output = :data, parameter_space = :direct, preview = false)

Simulate one response dataset from the current fit-supported MFRM/RSM/PCM
likelihood, or from a specified-only GMFRM/MGMFRM preview design for
simulation and recovery evaluation. MFRM/RSM/PCM designs use direct identified
parameters. GMFRM/MGMFRM previews accept constrained direct parameters by
default, or raw fit-ready candidate parameters with `parameter_space = :raw`.
`output = :data` returns a `FacetData` object with the same
person/rater/item/optional facet structure and category levels as the original
design. Use `output = :table` for a column-oriented named tuple, or
`output = :scores` for just the simulated score vector.
"""
function simulate_responses(design::FacetDesign,
        params::AbstractVector;
        rng::AbstractRNG = Random.default_rng(),
        output::Symbol = :data,
        parameter_space::Symbol = :direct)
    checked_output = _check_simulation_output(output)
    checked_space = _check_simulation_parameter_space(parameter_space)
    if design.spec.family === :mfrm && design.spec.estimation_status === :fit_supported
        checked_space === :direct ||
            throw(ArgumentError("fit-supported MFRM/RSM/PCM simulation only accepts parameter_space = :direct"))
        _check_parameter_vector(design, params)
        draws = reshape(collect(Float64, params), 1, :)
        scores = vec(_replicate_scores(design, draws, rng))
    elseif design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        direct = _generalized_simulation_direct_params(
            design,
            params,
            checked_space,
            "simulate_responses",
        )
        scores = vec(_replicate_scores_gmfrm_direct(
            design,
            reshape(direct, 1, :),
            rng,
            "simulate_responses",
        ))
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        direct = _generalized_simulation_direct_params(
            design,
            params,
            checked_space,
            "simulate_responses",
        )
        scores = vec(_replicate_scores_mgmfrm_direct(
            design,
            reshape(direct, 1, :),
            rng,
            "simulate_responses",
        ))
    else
        throw(ArgumentError(
            "simulate_responses currently supports fit-supported MFRM/RSM/PCM " *
            "designs and specified-only GMFRM/MGMFRM preview designs",
        ))
    end
    checked_output === :scores && return scores
    checked_output === :table && return _simulated_response_table(design.spec.data, scores)
    return _facet_data_with_scores(design.spec.data, scores)
end

simulate_responses(spec::FacetSpec,
        params::AbstractVector;
        preview::Bool = false,
        kwargs...) =
    simulate_responses(getdesign(spec; preview), params; kwargs...)

function _check_recovery_inputs(parameter_names::AbstractVector{String},
        draws::AbstractMatrix,
        truth::AbstractVector,
        caller::AbstractString)
    nparams = length(parameter_names)
    size(draws, 1) >= 1 ||
        throw(ArgumentError("$caller requires at least one draw"))
    size(draws, 2) == nparams ||
        throw(ArgumentError("draws has $(size(draws, 2)) column(s); expected $nparams"))
    length(truth) == nparams ||
        throw(ArgumentError("truth has length $(length(truth)); expected $nparams"))
    all(value -> isfinite(Float64(value)), draws) ||
        throw(ArgumentError("draws contain non-finite values"))
    all(value -> isfinite(Float64(value)), truth) ||
        throw(ArgumentError("truth contains non-finite values"))
    return nothing
end

function _check_recovery_inputs(design::FacetDesign,
        draws::AbstractMatrix,
        truth::AbstractVector,
        caller::AbstractString = "parameter recovery")
    return _check_recovery_inputs(design.parameter_names, draws, truth, caller)
end

function _parameter_block_name(blocks, index::Int)
    for block in sort(collect(keys(blocks)); by = string)
        _in_range(blocks[block], index) && return block
    end
    return :unknown
end

_parameter_block_name(design::FacetDesign, index::Int) =
    _parameter_block_name(design.blocks, index)

function _block_ranges_from_value_rows(rows)
    blocks = Dict{Symbol,UnitRange{Int}}()
    for row in rows
        Int(row.n_parameters) == 0 && continue
        blocks[row.block] = Int(row.first_parameter):Int(row.last_parameter)
    end
    return blocks
end

function _check_recovery_parameter_space(parameter_space::Symbol)
    parameter_space in (:direct, :raw) ||
        throw(ArgumentError("parameter_space must be :direct or :raw"))
    return parameter_space
end

function _recovery_metadata(;
        model_family::Symbol,
        parameter_space::Symbol,
        density_space::Symbol,
        scope,
        fit_ready::Bool,
        public_fit::Bool,
        experimental_public::Bool,
        guarded_local_fit::Bool)
    return (;
        model_family,
        parameter_space,
        density_space,
        scope,
        fit_ready,
        public_fit,
        experimental_public,
        guarded_local_fit,
    )
end

function _parameter_recovery_rows(parameter_names::AbstractVector{String},
        blocks,
        draws::AbstractMatrix,
        truth::AbstractVector;
        interval::Real,
        metadata)
    lower_probability, upper_probability = _interval_probabilities(interval)
    _check_recovery_inputs(parameter_names, draws, truth, "parameter_recovery")
    rows = NamedTuple[]
    for index in 1:length(parameter_names)
        vals = Float64.(draws[:, index])
        sorted = sort(vals)
        posterior_mean = _column_mean(vals)
        posterior_sd = _column_sd(vals, posterior_mean)
        posterior_median = _quantile_sorted(sorted, 0.5)
        posterior_lower = _quantile_sorted(sorted, lower_probability)
        posterior_upper = _quantile_sorted(sorted, upper_probability)
        true_value = Float64(truth[index])
        bias = posterior_mean - true_value
        relative_bias = iszero(true_value) ? NaN : bias / abs(true_value)
        covered = posterior_lower <= true_value <= posterior_upper
        push!(rows, merge((;
            parameter = parameter_names[index],
            parameter_index = index,
            block = _parameter_block_name(blocks, index),
            true_value,
            posterior_mean,
            posterior_sd,
            posterior_median,
            posterior_lower,
            posterior_upper,
            interval_probability = Float64(interval),
            lower_probability,
            upper_probability,
            bias,
            absolute_bias = abs(bias),
            squared_error = bias * bias,
            relative_bias,
            interval_width = posterior_upper - posterior_lower,
            covered,
            flag = covered ? :covered : :missed_interval,
        ), metadata))
    end
    return rows
end

function _design_recovery_metadata(design::FacetDesign, parameter_space::Symbol)
    if design.spec.family === :mfrm && design.spec.estimation_status === :fit_supported
        parameter_space === :direct ||
            throw(ArgumentError("fit-supported MFRM/RSM/PCM recovery only accepts parameter_space = :direct"))
        return _recovery_metadata(;
            model_family = :mfrm,
            parameter_space = :direct,
            density_space = :constrained_direct,
            scope = _spec_scope(design.spec.family, design.spec.estimation_status),
            fit_ready = true,
            public_fit = true,
            experimental_public = false,
            guarded_local_fit = false,
        )
    elseif design.spec.family === :gmfrm && design.spec.estimation_status === :specified_only
        return _recovery_metadata(;
            model_family = :gmfrm,
            parameter_space,
            density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
            scope = :scalar_gmfrm_fit_ready_candidate,
            fit_ready = false,
            public_fit = false,
            experimental_public = true,
            guarded_local_fit = false,
        )
    elseif design.spec.family === :mgmfrm && design.spec.estimation_status === :specified_only
        return _recovery_metadata(;
            model_family = :mgmfrm,
            parameter_space,
            density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
            scope = :minimal_confirmatory_mgmfrm_candidate,
            fit_ready = true,
            public_fit = true,
            experimental_public = true,
            guarded_local_fit = true,
        )
    end
    throw(ArgumentError(
        "parameter_recovery currently supports fit-supported MFRM/RSM/PCM " *
        "designs and specified-only GMFRM/MGMFRM preview designs",
    ))
end

function _design_recovery_layout(design::FacetDesign, parameter_space::Symbol)
    metadata = _design_recovery_metadata(design, parameter_space)
    if design.spec.family === :mfrm
        return (; parameter_names = design.parameter_names, blocks = design.blocks, metadata)
    elseif parameter_space === :direct
        return (; parameter_names = design.parameter_names, blocks = design.blocks, metadata)
    elseif design.spec.family === :gmfrm
        blueprint = _gmfrm_fit_ready_candidate_blueprint(design)
        return (; parameter_names = blueprint.parameter_names, blocks = blueprint.blocks, metadata)
    elseif design.spec.family === :mgmfrm
        blueprint = _mgmfrm_fit_ready_candidate_blueprint(design)
        return (; parameter_names = blueprint.parameter_names, blocks = blueprint.blocks, metadata)
    end
    throw(ArgumentError("unsupported recovery layout"))
end

function _fit_recovery_layout(fit::GMFRMFit, parameter_space::Symbol)
    metadata = _recovery_metadata(;
        model_family = :gmfrm,
        parameter_space,
        density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
        scope = :scalar_gmfrm_fit_ready_candidate,
        fit_ready = true,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = false,
    )
    if parameter_space === :direct
        return (;
            parameter_names = fit.diagnostic_surface.direct_parameter_names,
            blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.direct_blocks),
            draws = fit.direct_draws,
            metadata,
        )
    end
    return (;
        parameter_names = fit.diagnostic_surface.raw_parameter_names,
        blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.raw_blocks),
        draws = fit.draws,
        metadata,
    )
end

function _fit_recovery_layout(fit::MGMFRMFit, parameter_space::Symbol)
    metadata = _recovery_metadata(;
        model_family = :mgmfrm,
        parameter_space,
        density_space = parameter_space === :direct ? :constrained_direct : :raw_unconstrained,
        scope = :minimal_confirmatory_mgmfrm_candidate,
        fit_ready = true,
        public_fit = true,
        experimental_public = true,
        guarded_local_fit = true,
    )
    if parameter_space === :direct
        return (;
            parameter_names = fit.diagnostic_surface.direct_parameter_names,
            blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.direct_blocks),
            draws = fit.direct_draws,
            metadata,
        )
    end
    return (;
        parameter_names = fit.diagnostic_surface.raw_parameter_names,
        blocks = _block_ranges_from_value_rows(fit.diagnostic_surface.raw_blocks),
        draws = fit.draws,
        metadata,
    )
end

"""
    parameter_recovery(fit::MFRMFit, truth; interval = 0.95)
    parameter_recovery(fit::GMFRMFit, truth; interval = 0.95,
        parameter_space = :direct)
    parameter_recovery(design::FacetDesign, draws, truth; interval = 0.95,
        parameter_space = :direct)

Compare posterior draws with known simulation truth. Rows include the true
value, posterior mean/median/interval, bias, absolute bias, squared error,
relative bias, interval width, and whether the posterior interval covers the
true value. MFRM/RSM/PCM rows use the fit-supported direct parameterization.
GMFRM/MGMFRM fit objects and preview designs use direct constrained parameters
by default; pass `parameter_space = :raw` to evaluate raw fit-ready candidate
coordinates.
"""
function parameter_recovery(design::FacetDesign,
        draws::AbstractMatrix,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct)
    checked_space = _check_recovery_parameter_space(parameter_space)
    layout = _design_recovery_layout(design, checked_space)
    if design.spec.family === :gmfrm && checked_space === :direct
        _gmfrm_direct_draws_for_prediction(design, draws, "parameter_recovery")
    elseif design.spec.family === :mgmfrm && checked_space === :direct
        _mgmfrm_direct_draws_for_prediction(design, draws, "parameter_recovery")
    end
    return _parameter_recovery_rows(
        layout.parameter_names,
        layout.blocks,
        draws,
        truth;
        interval,
        metadata = layout.metadata,
    )
end

parameter_recovery(fit::MFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery(fit.design, fit.draws, truth; interval, parameter_space)

function parameter_recovery(fit::GMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct)
    checked_space = _check_recovery_parameter_space(parameter_space)
    layout = _fit_recovery_layout(fit, checked_space)
    return _parameter_recovery_rows(
        layout.parameter_names,
        layout.blocks,
        layout.draws,
        truth;
        interval,
        metadata = layout.metadata,
    )
end

function parameter_recovery(fit::MGMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct)
    checked_space = _check_recovery_parameter_space(parameter_space)
    layout = _fit_recovery_layout(fit, checked_space)
    return _parameter_recovery_rows(
        layout.parameter_names,
        layout.blocks,
        layout.draws,
        truth;
        interval,
        metadata = layout.metadata,
    )
end

function _recovery_group_key(row, by::Symbol)
    by === :all && return :all
    hasproperty(row, by) ||
        throw(ArgumentError("recovery rows do not contain grouping field :$by"))
    return getproperty(row, by)
end

"""
    parameter_recovery_summary(recovery_rows; by = :block)
    parameter_recovery_summary(fit::MFRMFit, truth; interval = 0.95,
        by = :block)

Aggregate parameter-recovery rows by block, or use `by = :all` for a single
overall row. Summaries include mean bias, mean absolute error, RMSE, median
absolute error, max absolute error, interval coverage, and mean interval width.
"""
function parameter_recovery_summary(recovery_rows; by::Symbol = :block)
    isempty(recovery_rows) &&
        throw(ArgumentError("recovery_rows must not be empty"))
    groups = Dict{Any,Vector{Any}}()
    order = Any[]
    for row in recovery_rows
        key = _recovery_group_key(row, by)
        if !haskey(groups, key)
            groups[key] = Any[]
            push!(order, key)
        end
        push!(groups[key], row)
    end

    rows = NamedTuple[]
    for key in order
        group_rows = groups[key]
        n = length(group_rows)
        biases = [Float64(row.bias) for row in group_rows]
        absolute_biases = [Float64(row.absolute_bias) for row in group_rows]
        squared_errors = [Float64(row.squared_error) for row in group_rows]
        widths = [Float64(row.interval_width) for row in group_rows]
        n_covered = count(row -> row.covered, group_rows)
        nominal = Float64(group_rows[1].interval_probability)
        sorted_abs = sort(absolute_biases)
        push!(rows, (;
            by,
            group = key,
            n_parameters = n,
            mean_bias = sum(biases) / n,
            mean_absolute_error = sum(absolute_biases) / n,
            rmse = sqrt(sum(squared_errors) / n),
            median_absolute_error = _quantile_sorted(sorted_abs, 0.5),
            max_absolute_error = maximum(absolute_biases),
            coverage_rate = n_covered / n,
            nominal_coverage = nominal,
            coverage_gap = n_covered / n - nominal,
            mean_interval_width = sum(widths) / n,
            n_covered,
            flag = n_covered / n >= nominal ? :ok : :coverage_below_nominal,
        ))
    end
    return rows
end

parameter_recovery_summary(fit::MFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        by::Symbol = :block,
        parameter_space::Symbol = :direct) =
    parameter_recovery_summary(
        parameter_recovery(fit, truth; interval, parameter_space);
        by)

parameter_recovery_summary(fit::GMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        by::Symbol = :block,
        parameter_space::Symbol = :direct) =
    parameter_recovery_summary(
        parameter_recovery(fit, truth; interval, parameter_space);
        by)

parameter_recovery_summary(fit::MGMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        by::Symbol = :block,
        parameter_space::Symbol = :direct) =
    parameter_recovery_summary(
        parameter_recovery(fit, truth; interval, parameter_space);
        by)

"""
    parameter_recovery_plot_data(recovery_rows)
    parameter_recovery_plot_data(fit::MFRMFit, truth; interval = 0.95)

Return plotting-ready rows for a parameter-recovery scatter/interval plot
without depending on a plotting package. Suggested mappings are
`x = true_value`, `y = estimate`, and `ymin/ymax = interval_lower/interval_upper`;
the diagonal reference line is `y = x`.
"""
function parameter_recovery_plot_data(recovery_rows)
    return [(;
        parameter = row.parameter,
        parameter_index = row.parameter_index,
        block = row.block,
        true_value = row.true_value,
        estimate = row.posterior_mean,
        interval_lower = row.posterior_lower,
        interval_upper = row.posterior_upper,
        error = row.bias,
        absolute_error = row.absolute_bias,
        covered = row.covered,
        flag = row.flag,
        reference = row.true_value,
    ) for row in recovery_rows]
end

parameter_recovery_plot_data(fit::MFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery_plot_data(
        parameter_recovery(fit, truth; interval, parameter_space))

parameter_recovery_plot_data(fit::GMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery_plot_data(
        parameter_recovery(fit, truth; interval, parameter_space))

parameter_recovery_plot_data(fit::MGMFRMFit,
        truth::AbstractVector;
        interval::Real = 0.95,
        parameter_space::Symbol = :direct) =
    parameter_recovery_plot_data(
        parameter_recovery(fit, truth; interval, parameter_space))

const _DEFAULT_SIMULATION_GRID_REQUIRED_AXES = (
    :density,
    :anchor_size,
    :ratings_per_target,
    :category_pathology,
    :rater_noise,
    :dff,
    :dimensionality,
    :misspecification,
)

function _simulation_axis_tuple(values, name::Symbol)
    out = if values isa Symbol || values isa AbstractString ||
            values isa Number || values isa Bool
        (values,)
    else
        Tuple(values)
    end
    isempty(out) &&
        throw(ArgumentError("simulation grid axis :$name must contain at least one value"))
    return out
end

function _simulation_integer_axis(values, name::Symbol; minimum::Int = 1)
    axis = _simulation_axis_tuple(values, name)
    out = Int[]
    for value in axis
        value isa Integer ||
            throw(ArgumentError("simulation grid axis :$name must contain integers"))
        Int(value) >= minimum ||
            throw(ArgumentError("simulation grid axis :$name values must be >= $minimum"))
        push!(out, Int(value))
    end
    return Tuple(out)
end

function _simulation_symbol_axis(values, name::Symbol)
    axis = _simulation_axis_tuple(values, name)
    out = Symbol[]
    for value in axis
        value isa Symbol ||
            throw(ArgumentError("simulation grid axis :$name must contain Symbols"))
        push!(out, value)
    end
    return Tuple(out)
end

function _simulation_positive_integer(value::Integer, name::Symbol; minimum::Int = 1)
    Int(value) >= minimum ||
        throw(ArgumentError("$name must be >= $minimum"))
    return Int(value)
end

function _simulation_density_target(density)
    density === :sparse && return 0.15
    density === :moderate && return 0.50
    density === :near_complete && return 0.90
    if density isa Real
        value = Float64(density)
        isfinite(value) && 0 < value <= 1 ||
            throw(ArgumentError("numeric density values must be finite and in (0, 1]"))
        return value
    end
    throw(ArgumentError("density values must be :sparse, :moderate, :near_complete, or numeric proportions"))
end

function _simulation_rater_noise_sd(noise)
    noise === :low && return 0.25
    noise === :moderate && return 0.75
    noise === :high && return 1.50
    if noise isa Real
        value = Float64(noise)
        isfinite(value) && value >= 0 ||
            throw(ArgumentError("numeric rater_noise values must be finite and nonnegative"))
        return value
    end
    throw(ArgumentError("rater_noise values must be :low, :moderate, :high, or numeric standard deviations"))
end

_simulation_axis_active(value, inactive::Tuple) =
    !(value in inactive)

function _simulation_validation_focus(density, anchor_size::Int,
        category_pathology, rater_noise, dff, dimensionality::Int,
        misspecification)
    focus = Symbol[]
    density_target = _simulation_density_target(density)
    density_target <= 0.25 && push!(focus, :connectedness_and_sparse_cells)
    anchor_size > 0 && push!(focus, :anchor_linking)
    _simulation_axis_active(category_pathology, (:none, :balanced)) &&
        push!(focus, :category_pathology)
    _simulation_rater_noise_sd(rater_noise) >= 1.0 && push!(focus, :rater_noise)
    _simulation_axis_active(dff, (:none, :absent, false)) &&
        push!(focus, :dff_decision_stability)
    dimensionality > 1 && push!(focus, :multidimensional_gauge)
    _simulation_axis_active(misspecification, (:none, :well_specified, false)) &&
        push!(focus, :misspecification)
    isempty(focus) && push!(focus, :baseline_recovery)
    return Tuple(focus)
end

function _simulation_fit_surface(dimensionality::Int, misspecification)
    if dimensionality > 1
        return :guarded_mgmfrm_preview
    elseif _simulation_axis_active(misspecification, (:none, :well_specified, false))
        return :public_mfrm_baseline_or_guarded_gmfrm_comparison
    end
    return :public_mfrm_baseline
end

"""
    simulation_grid(; densities = (:sparse, :moderate, :near_complete),
        anchor_sizes = (0, 2, 5), ratings_per_target = (1, 2, 4),
        category_pathologies = (:none, :skipped_middle, :top_set),
        rater_noise = (:low, :moderate, :high), dff = (:none, :rater_by_group),
        dimensionalities = (1, 2),
        misspecifications = (:none, :wrong_thresholds, :omitted_dff),
        repetitions = 1, base_seed = 20260620, grid_id = "default",
        n_persons = 48, n_items = 12, n_raters = 6, n_categories = 4,
        view = :full)

Return predeclared simulation-study rows that cross sparse-to-near-complete
design density, anchor size, ratings per target, category pathologies, rater
noise, DFF patterns, dimensionality, and misspecification. Rows are planning
metadata for reproducible simulation/recovery studies; this helper does not
simulate responses, fit models, or evaluate claims. Use the rows with
[`simulate_responses`](@ref), [`parameter_recovery`](@ref), calibration,
predictive-check, and model-comparison helpers when executing a study.
Use `view = :public` for compact reader-facing rows; `view = :full` preserves
the complete planning record.
"""
function simulation_grid(; densities = (:sparse, :moderate, :near_complete),
        anchor_sizes = (0, 2, 5),
        ratings_per_target = (1, 2, 4),
        category_pathologies = (:none, :skipped_middle, :top_set),
        rater_noise = (:low, :moderate, :high),
        dff = (:none, :rater_by_group),
        dimensionalities = (1, 2),
        misspecifications = (:none, :wrong_thresholds, :omitted_dff),
        repetitions::Integer = 1,
        base_seed::Integer = 20260620,
        grid_id::AbstractString = "default",
        n_persons::Integer = 48,
        n_items::Integer = 12,
        n_raters::Integer = 6,
        n_categories::Integer = 4,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    density_axis = _simulation_axis_tuple(densities, :density)
    anchor_axis = _simulation_integer_axis(anchor_sizes, :anchor_size; minimum = 0)
    ratings_axis = _simulation_integer_axis(ratings_per_target, :ratings_per_target)
    category_axis = _simulation_symbol_axis(category_pathologies, :category_pathology)
    noise_axis = _simulation_axis_tuple(rater_noise, :rater_noise)
    dff_axis = _simulation_axis_tuple(dff, :dff)
    dimensionality_axis =
        _simulation_integer_axis(dimensionalities, :dimensionality)
    misspecification_axis =
        _simulation_axis_tuple(misspecifications, :misspecification)
    checked_repetitions =
        _simulation_positive_integer(repetitions, :repetitions)
    checked_persons = _simulation_positive_integer(n_persons, :n_persons)
    checked_items = _simulation_positive_integer(n_items, :n_items)
    checked_raters = _simulation_positive_integer(n_raters, :n_raters)
    checked_categories = _simulation_positive_integer(n_categories, :n_categories; minimum = 2)
    all(rating -> rating <= checked_raters, ratings_axis) ||
        throw(ArgumentError("ratings_per_target values cannot exceed n_raters"))

    target_units = checked_persons * checked_items
    max_ratings = target_units * checked_raters
    rows = NamedTuple[]
    scenario_index = 0
    for density in density_axis, anchor_size in anchor_axis,
            ratings in ratings_axis, category_pathology in category_axis,
            noise in noise_axis, dff_pattern in dff_axis,
            dimensionality in dimensionality_axis,
            misspecification in misspecification_axis
        scenario_index += 1
        density_target = _simulation_density_target(density)
        planned_density = ratings / checked_raters
        planned_n_ratings = target_units * ratings
        validation_focus = _simulation_validation_focus(
            density,
            anchor_size,
            category_pathology,
            noise,
            dff_pattern,
            dimensionality,
            misspecification,
        )
        for replication in 1:checked_repetitions
            row_index = length(rows) + 1
            push!(rows, (;
                schema = "bayesianmgmfrm.simulation_grid.v1",
                object = :simulation_grid_row,
                grid_id = String(grid_id),
                row_index,
                scenario_index,
                replication,
                seed = Int(base_seed) + row_index - 1,
                n_persons = checked_persons,
                n_items = checked_items,
                n_raters = checked_raters,
                n_categories = checked_categories,
                target_units,
                max_ratings,
                planned_n_ratings,
                density,
                density_target,
                planned_density,
                density_gap = planned_density - density_target,
                anchor_size,
                ratings_per_target = ratings,
                category_pathology,
                rater_noise = noise,
                rater_noise_sd = _simulation_rater_noise_sd(noise),
                dff = dff_pattern,
                dff_active = _simulation_axis_active(dff_pattern, (:none, :absent, false)),
                dimensionality,
                misspecification,
                misspecified =
                    _simulation_axis_active(misspecification, (:none, :well_specified, false)),
                validation_focus,
                fit_surface = _simulation_fit_surface(dimensionality, misspecification),
                simulation_status = :predeclared_not_run,
                caveat = :simulation_grid_not_runner_or_evidence,
                next_gate = :run_predeclared_grid_and_apply_falsification_rules,
            ))
        end
    end
    return view === :full ? rows : [
        _public_reader_payload(
            row;
            schema = "bayesianmgmfrm.simulation_grid_public.v1",
        ) for row in rows
    ]
end

function _simulation_grid_axis(axis::Symbol)
    axis in (:density, :design_density) && return :density
    axis in (:anchor, :anchors, :anchor_size) && return :anchor_size
    axis in (:ratings, :ratings_per_target, :ratings_per_target_unit) &&
        return :ratings_per_target
    axis in (:category, :category_pathology, :category_pathologies) &&
        return :category_pathology
    axis in (:noise, :rater_noise) && return :rater_noise
    axis in (:dff, :dff_pattern, :dff_effects) && return :dff
    axis in (:dimensions, :dimensionality) && return :dimensionality
    axis in (:misspecification, :misspecifications, :model_misspecification) &&
        return :misspecification
    return axis
end

function _simulation_grid_axis_tuple(axes)
    out = Symbol[]
    for axis in axes
        axis isa Symbol ||
            throw(ArgumentError("simulation grid axes must be Symbols"))
        canonical = _simulation_grid_axis(axis)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_simulation_grid_axis_tuple(axis::Symbol) = (_simulation_grid_axis(axis),)

function _simulation_grid_axis_summary(axis::Symbol, rows::AbstractVector)
    values = Any[]
    for row in rows
        hasproperty(row, axis) || continue
        push!(values, getproperty(row, axis))
    end
    unique_values = _sensitivity_unique_tuple(values)
    present = !isempty(values)
    status = !present ? :missing : length(unique_values) >= 2 ? :varied : :single_value
    return (;
        axis,
        present,
        status,
        n_values = length(unique_values),
        values = unique_values,
    )
end

"""
    simulation_grid_summary(rows; required_axes =
        (:density, :anchor_size, :ratings_per_target, :category_pathology,
         :rater_noise, :dff, :dimensionality, :misspecification),
         view = :full)

Summarize whether predeclared simulation-grid rows cover the default critical axes
for sparse Bayesian MFRM/GMFRM/MGMFRM validation. The summary reports missing
required axes, single-value axes, varied axes, row/scenario counts, and the
repetition/seed envelope. It is a coverage check for a planned grid, not
evidence that the grid has been run.
`view = :public` returns a compact reader-facing summary; the default `:full`
payload remains unchanged.
"""
function simulation_grid_summary(rows::AbstractVector;
        required_axes = _DEFAULT_SIMULATION_GRID_REQUIRED_AXES,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    isempty(rows) &&
        throw(ArgumentError("at least one simulation grid row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("simulation grid summary expects NamedTuple rows"))
    end
    checked_required = _simulation_grid_axis_tuple(required_axes)
    axis_rows = [_simulation_grid_axis_summary(axis, rows)
        for axis in checked_required]
    missing_required_axes = Tuple(row.axis for row in axis_rows
        if row.status === :missing)
    single_value_required_axes = Tuple(row.axis for row in axis_rows
        if row.status === :single_value)
    varied_required_axes = Tuple(row.axis for row in axis_rows
        if row.status === :varied)
    scenario_values = _sensitivity_unique_tuple(
        hasproperty(row, :scenario_index) ? row.scenario_index : missing
        for row in rows)
    repetition_values = _sensitivity_unique_tuple(
        hasproperty(row, :replication) ? row.replication : missing
        for row in rows)
    seed_values = [Int(row.seed) for row in rows if hasproperty(row, :seed)]

    summary = (;
        schema = "bayesianmgmfrm.simulation_grid_summary.v1",
        object = :simulation_grid_summary,
        required_axes = checked_required,
        n_rows = length(rows),
        n_scenarios = length(scenario_values),
        n_repetitions = length(repetition_values),
        first_seed = isempty(seed_values) ? missing : minimum(seed_values),
        last_seed = isempty(seed_values) ? missing : maximum(seed_values),
        missing_required_axes,
        single_value_required_axes,
        varied_required_axes,
        axis_rows = Tuple(axis_rows),
        passed = isempty(missing_required_axes) &&
            isempty(single_value_required_axes),
        caveat = :simulation_grid_summary_not_run_evidence,
        next_gate = :run_predeclared_grid_and_apply_falsification_rules,
    )
    return view === :full ? summary :
        _public_reader_payload(
            summary;
            schema = "bayesianmgmfrm.simulation_grid_summary_public.v1",
        )
end

simulation_grid_summary(row, rows...; kwargs...) =
    simulation_grid_summary([row; rows...]; kwargs...)

const _DEFAULT_FALSIFICATION_RULE_DOMAINS = (
    :simulation_grid,
    :design_validation,
    :computation,
    :recovery,
    :calibration,
    :predictive_check,
    :decision_stability,
    :sensitivity,
    :baseline_comparison,
    :reproducibility,
)

function _finite_rule_threshold(value::Real, name::Symbol;
        minimum = nothing,
        maximum = nothing)
    checked = Float64(value)
    isfinite(checked) ||
        throw(ArgumentError("$name must be finite"))
    if minimum !== nothing
        checked >= Float64(minimum) ||
            throw(ArgumentError("$name must be >= $minimum"))
    end
    if maximum !== nothing
        checked <= Float64(maximum) ||
            throw(ArgumentError("$name must be <= $maximum"))
    end
    return checked
end

function _falsification_rule(; claim::Symbol, rule_index::Int, rule_id::Symbol,
        domain::Symbol, metric::Symbol, fail_if::Symbol, threshold,
        required_evidence::Symbol, action_if_triggered::Symbol)
    return (;
        schema = "bayesianmgmfrm.falsification_rule.v1",
        object = :falsification_rule,
        claim,
        rule_index,
        rule_id,
        domain,
        metric,
        fail_if,
        threshold,
        required_evidence,
        status = :predeclared_not_evaluated,
        action_if_triggered,
        manuscript_claim_allowed_if_triggered = false,
        caveat = :rule_predeclared_not_evidence,
    )
end

"""
    falsification_rules(; claim = :sparse_hierarchical_priors_stabilize_mgmfrm,
        max_rhat = 1.01, min_bulk_ess = 400, max_divergences = 0,
        max_max_treedepth_hits = 0, min_interval_coverage = 0.90,
        max_block_mean_absolute_error = 0.35,
        max_parameter_absolute_error = 0.75,
        max_expected_score_calibration_error = 0.25,
        max_category_probability_error = 0.10,
        min_predictive_tail_probability = 0.05,
        max_decision_flip_rate = 0.10,
        max_prior_sensitivity_shift = 0.25,
        min_heldout_elpd_gain = 0.0,
        required_grid_axes = ...)

Return predeclared falsification-rule rows for the claim that hierarchical
priors stabilize sparse MGMFRM designs. Rules cover simulation-grid coverage,
design validation, computation, recovery, calibration, predictive checks,
decision stability, sensitivity, baseline comparison, and reproducibility.

The rows are a claim contract, not run evidence. A triggered rule should narrow
or block the corresponding sparse-stability claim until the study is revised
or new evidence is generated.
"""
function falsification_rules(;
        claim::Symbol = :sparse_hierarchical_priors_stabilize_mgmfrm,
        max_rhat::Real = 1.01,
        min_bulk_ess::Real = 400,
        max_divergences::Integer = 0,
        max_max_treedepth_hits::Integer = 0,
        min_interval_coverage::Real = 0.90,
        max_block_mean_absolute_error::Real = 0.35,
        max_parameter_absolute_error::Real = 0.75,
        max_expected_score_calibration_error::Real = 0.25,
        max_category_probability_error::Real = 0.10,
        min_predictive_tail_probability::Real = 0.05,
        max_decision_flip_rate::Real = 0.10,
        max_prior_sensitivity_shift::Real = 0.25,
        min_heldout_elpd_gain::Real = 0.0,
        required_grid_axes = _DEFAULT_SIMULATION_GRID_REQUIRED_AXES)
    checked_max_rhat = _finite_rule_threshold(max_rhat, :max_rhat; minimum = 1)
    checked_min_bulk_ess =
        _finite_rule_threshold(min_bulk_ess, :min_bulk_ess; minimum = 1)
    checked_min_interval_coverage =
        _finite_rule_threshold(min_interval_coverage, :min_interval_coverage;
            minimum = 0, maximum = 1)
    checked_max_block_mae =
        _finite_rule_threshold(max_block_mean_absolute_error,
            :max_block_mean_absolute_error; minimum = 0)
    checked_max_parameter_abs =
        _finite_rule_threshold(max_parameter_absolute_error,
            :max_parameter_absolute_error; minimum = 0)
    checked_expected_score_error =
        _finite_rule_threshold(max_expected_score_calibration_error,
            :max_expected_score_calibration_error; minimum = 0)
    checked_category_error =
        _finite_rule_threshold(max_category_probability_error,
            :max_category_probability_error; minimum = 0)
    checked_tail_probability =
        _finite_rule_threshold(min_predictive_tail_probability,
            :min_predictive_tail_probability; minimum = 0, maximum = 1)
    checked_decision_flip =
        _finite_rule_threshold(max_decision_flip_rate, :max_decision_flip_rate;
            minimum = 0, maximum = 1)
    checked_prior_shift =
        _finite_rule_threshold(max_prior_sensitivity_shift,
            :max_prior_sensitivity_shift; minimum = 0)
    checked_elpd_gain =
        _finite_rule_threshold(min_heldout_elpd_gain, :min_heldout_elpd_gain)
    checked_grid_axes = _simulation_grid_axis_tuple(required_grid_axes)
    checked_divergences =
        _simulation_positive_integer(max_divergences, :max_divergences; minimum = 0)
    checked_treedepth =
        _simulation_positive_integer(max_max_treedepth_hits,
            :max_max_treedepth_hits; minimum = 0)

    specs = (
        (rule_id = :grid_axes_incomplete,
            domain = :simulation_grid,
            metric = :required_grid_axes_present,
            fail_if = :missing_any,
            threshold = checked_grid_axes,
            required_evidence = :simulation_grid_summary,
            action_if_triggered = :expand_predeclared_grid_before_claim),
        (rule_id = :design_disconnected,
            domain = :design_validation,
            metric = :n_rater_components,
            fail_if = :greater_than,
            threshold = 1,
            required_evidence = :validate_design_and_anchor_linking_summary,
            action_if_triggered = :narrow_to_connected_designs_or_collect_links),
        (rule_id = :rhat_too_high,
            domain = :computation,
            metric = :max_rhat,
            fail_if = :greater_than,
            threshold = checked_max_rhat,
            required_evidence = :diagnostics,
            action_if_triggered = :do_not_report_sparse_stability_claim),
        (rule_id = :bulk_ess_too_low,
            domain = :computation,
            metric = :min_bulk_ess,
            fail_if = :less_than,
            threshold = checked_min_bulk_ess,
            required_evidence = :diagnostics,
            action_if_triggered = :increase_sampling_or_simplify_model),
        (rule_id = :divergences_or_treedepth,
            domain = :computation,
            metric = :n_divergences_or_max_treedepth_hits,
            fail_if = :greater_than,
            threshold = (divergences = checked_divergences,
                max_treedepth_hits = checked_treedepth),
            required_evidence = :sampler_diagnostics,
            action_if_triggered = :treat_posterior_geometry_as_unresolved),
        (rule_id = :interval_coverage_low,
            domain = :recovery,
            metric = :interval_coverage_rate,
            fail_if = :less_than,
            threshold = checked_min_interval_coverage,
            required_evidence = :parameter_recovery_summary,
            action_if_triggered = :narrow_recovery_claim_or_revise_priors),
        (rule_id = :recovery_error_large,
            domain = :recovery,
            metric = :recovery_error,
            fail_if = :greater_than,
            threshold = (block_mean_absolute_error = checked_max_block_mae,
                parameter_absolute_error = checked_max_parameter_abs),
            required_evidence = :parameter_recovery_summary,
            action_if_triggered = :report_sparse_recovery_failure),
        (rule_id = :calibration_error_large,
            domain = :calibration,
            metric = :calibration_error,
            fail_if = :greater_than,
            threshold = (expected_score = checked_expected_score_error,
                category_probability = checked_category_error),
            required_evidence = :calibration_table,
            action_if_triggered = :block_predictive_stability_claim),
        (rule_id = :predictive_tail_mismatch,
            domain = :predictive_check,
            metric = :minimum_two_sided_tail_probability,
            fail_if = :less_than,
            threshold = checked_tail_probability,
            required_evidence = :predictive_check_summary,
            action_if_triggered = :report_predictive_misfit_before_claim),
        (rule_id = :decision_instability,
            domain = :decision_stability,
            metric = :max_decision_flip_rate,
            fail_if = :greater_than,
            threshold = checked_decision_flip,
            required_evidence = :dff_and_sparse_decision_grid,
            action_if_triggered = :frame_outputs_as_screening_only),
        (rule_id = :prior_sensitivity_large,
            domain = :sensitivity,
            metric = :max_focal_shift_across_prior_regimes,
            fail_if = :greater_than,
            threshold = checked_prior_shift,
            required_evidence = :sensitivity_comparison_summary,
            action_if_triggered = :treat_sparse_claim_as_prior_dependent),
        (rule_id = :heldout_baseline_not_improved,
            domain = :baseline_comparison,
            metric = :hierarchical_minus_baseline_heldout_elpd,
            fail_if = :less_than,
            threshold = checked_elpd_gain,
            required_evidence = :compare_kfold,
            action_if_triggered = :avoid_superiority_language),
        (rule_id = :reproduction_bundle_incomplete,
            domain = :reproducibility,
            metric = :all_required_artifacts_present,
            fail_if = :not_equal,
            threshold = true,
            required_evidence = :fit_archive_manifest,
            action_if_triggered = :do_not_publish_claim_until_rerunnable),
    )

    return [_falsification_rule(;
        claim,
        rule_index = index,
        spec...)
        for (index, spec) in pairs(specs)]
end

function _falsification_rule_domain(axis::Symbol)
    axis in (:grid, :simulation_grid) && return :simulation_grid
    axis in (:validation, :design_validation) && return :design_validation
    axis in (:sampler, :sampling, :computation) && return :computation
    axis in (:recovery, :parameter_recovery) && return :recovery
    axis in (:calibration, :predictive_calibration) && return :calibration
    axis in (:ppc, :predictive_check) && return :predictive_check
    axis in (:decision, :decision_stability) && return :decision_stability
    axis in (:sensitivity, :prior_sensitivity) && return :sensitivity
    axis in (:baseline, :baseline_comparison) && return :baseline_comparison
    axis in (:reproduction, :reproducibility) && return :reproducibility
    return axis
end

function _falsification_domain_tuple(domains)
    out = Symbol[]
    for domain in domains
        domain isa Symbol ||
            throw(ArgumentError("falsification rule domains must be Symbols"))
        canonical = _falsification_rule_domain(domain)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_falsification_domain_tuple(domain::Symbol) = (_falsification_rule_domain(domain),)

function _falsification_domain_summary(domain::Symbol, rows::AbstractVector)
    domain_rows = [row for row in rows if hasproperty(row, :domain) &&
        _falsification_rule_domain(row.domain) === domain]
    rule_ids = _sensitivity_unique_tuple(row.rule_id for row in domain_rows)
    return (;
        domain,
        present = !isempty(domain_rows),
        n_rules = length(domain_rows),
        rule_ids,
        status = isempty(domain_rows) ? :missing : :present,
    )
end

"""
    falsification_rule_summary(rows; required_domains =
        (:simulation_grid, :design_validation, :computation, :recovery,
         :calibration, :predictive_check, :decision_stability, :sensitivity,
         :baseline_comparison, :reproducibility), view = :full)

Summarize predeclared falsification-rule rows and check whether every required
claim domain is represented. This is a rule-coverage summary; it does not
evaluate study results or decide whether a claim has passed.
`view = :public` returns a compact reader-facing summary; `view = :full`
preserves the complete rule-coverage record.
"""
function falsification_rule_summary(rows::AbstractVector;
        required_domains = _DEFAULT_FALSIFICATION_RULE_DOMAINS,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    isempty(rows) &&
        throw(ArgumentError("at least one falsification rule row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("falsification rule summary expects NamedTuple rows"))
    end
    checked_required = _falsification_domain_tuple(required_domains)
    domain_rows = [_falsification_domain_summary(domain, rows)
        for domain in checked_required]
    missing_required_domains = Tuple(row.domain for row in domain_rows
        if row.status === :missing)
    present_required_domains = Tuple(row.domain for row in domain_rows
        if row.status === :present)
    summary = (;
        schema = "bayesianmgmfrm.falsification_rule_summary.v1",
        object = :falsification_rule_summary,
        required_domains = checked_required,
        n_rules = length(rows),
        n_domains = length(_sensitivity_unique_tuple(
            _falsification_rule_domain(row.domain) for row in rows
            if hasproperty(row, :domain))),
        missing_required_domains,
        present_required_domains,
        domain_rows = Tuple(domain_rows),
        passed = isempty(missing_required_domains),
        status = isempty(missing_required_domains) ? :complete : :incomplete,
        caveat = :rule_summary_not_study_result,
        next_gate = :evaluate_rules_on_predeclared_simulation_grid,
    )
    return view === :full ? summary :
        _public_reader_payload(
            summary;
            schema = "bayesianmgmfrm.falsification_rule_summary_public.v1",
        )
end

falsification_rule_summary(row, rows...; kwargs...) =
    falsification_rule_summary([row; rows...]; kwargs...)

"""
    calibration_plot_data(calibration_rows)

Return plotting-ready rows from [`calibration_table`](@ref). Suggested mappings
are `x = predicted_mean`, `y = observed_mean`, with `reference = predicted_mean`
for the ideal calibration diagonal. The predicted interval fields can be used
as horizontal uncertainty bars for the **mean expected value**, not prediction
intervals for observed ratings. Retain `target`, `category`, the bin's prediction
range, and the conditioning described in [`calibration_table`](@ref) when labelling
a figure. `flag` remains a descriptive comparison, not a fit-test decision.

Rows also retain `n_observations`, `n_draws`, `predicted_median`,
`interval_probability`, `lower_probability` and `upper_probability` when present.
Older reduced rows remain accepted; absent metadata is returned as `missing`.
Do not infer rating counts, effective sample size or interval levels from the
plot coordinates. This conversion neither recomputes predictions nor generates
replicated outcomes.
"""
function calibration_plot_data(calibration_rows)
    return [(;
        target = row.target,
        category = row.category,
        bin = row.bin,
        n_observations = hasproperty(row, :n_observations) ? row.n_observations : missing,
        n_draws = hasproperty(row, :n_draws) ? row.n_draws : missing,
        predicted_mean = row.predicted_mean,
        predicted_median = hasproperty(row, :predicted_median) ? row.predicted_median : missing,
        observed_mean = row.observed_mean,
        predicted_lower = row.predicted_lower,
        predicted_upper = row.predicted_upper,
        predicted_bin_lower = row.predicted_bin_lower,
        predicted_bin_upper = row.predicted_bin_upper,
        interval_probability = hasproperty(row, :interval_probability) ? row.interval_probability : missing,
        lower_probability = hasproperty(row, :lower_probability) ? row.lower_probability : missing,
        upper_probability = hasproperty(row, :upper_probability) ? row.upper_probability : missing,
        calibration_error = row.calibration_error,
        absolute_calibration_error = row.absolute_calibration_error,
        flag = row.flag,
        reference = row.predicted_mean,
    ) for row in calibration_rows]
end

"""
    predictive_check_plot_data(summary_rows)

Return plotting-ready rows from [`predictive_check_summary`](@ref). Suggested
mappings are `y = observed`, `ymin/ymax = replicated_lower/replicated_upper`,
and `replicated_mean` as the model-implied center for each statistic/level.
"""
function predictive_check_plot_data(summary_rows)
    return [(;
        statistic = row.statistic,
        level = row.level,
        observed = row.observed,
        replicated_mean = row.replicated_mean,
        replicated_lower = row.replicated_lower,
        replicated_upper = row.replicated_upper,
        lower_tail_probability = row.lower_tail_probability,
        upper_tail_probability = row.upper_tail_probability,
        two_sided_tail_probability = row.two_sided_tail_probability,
        n_replicates = row.n_replicates,
        flag = row.flag,
    ) for row in summary_rows]
end
