# sensitivity_and_comparisons.jl -- Prior/K-fold/LOO sensitivity comparisons, evidence summaries, and benchmarks.

function _sensitivity_axis(axis::Symbol)
    axis === :threshold && return :thresholds
    axis === :family && return :model_family
    axis === :dimensionality && return :dimensions
    return axis
end

function _sensitivity_prior_value(fit::MFRMFit)
    return (;
        person_sd = fit.prior.person_sd,
        rater_sd = fit.prior.rater_sd,
        item_sd = fit.prior.item_sd,
        step_sd = fit.prior.step_sd,
    )
end

function _sensitivity_prior_value(fit::Union{GMFRMFit,MGMFRMFit})
    return (;
        person_sd = fit.prior.person_sd,
        rater_sd = fit.prior.rater_sd,
        item_sd = fit.prior.item_sd,
        log_discrimination_sd = fit.prior.log_discrimination_sd,
        log_consistency_sd = fit.prior.log_consistency_sd,
        step_sd = fit.prior.step_sd,
    )
end

function _default_sensitivity_value(fit::_ModelComparisonFit,
        label::AbstractString,
        axis::Symbol)
    spec = fit.design.spec
    axis === :model && return String(label)
    axis === :model_family && return spec.family
    axis === :thresholds && return spec.thresholds
    axis === :discrimination && return spec.discrimination
    axis === :dimensions && return spec.dimensions
    axis === :q_matrix && return _q_matrix_manifest(spec.q_matrix)
    axis === :estimation_status && return spec.estimation_status
    axis === :prior && return _sensitivity_prior_value(fit)
    axis === :backend && return fit.backend
    axis === :sampler && return fit.sampler
    throw(ArgumentError(
        "axis = :$axis requires explicit values; supported inferred axes are " *
        ":model, :model_family, :thresholds, :discrimination, :dimensions, " *
        ":q_matrix, :estimation_status, :prior, :backend, and :sampler"))
end

function _explicit_sensitivity_values(
        labels::AbstractVector{<:AbstractString},
        values::NamedTuple)
    out = Any[]
    names = propertynames(values)
    for label in labels
        key = Symbol(label)
        key in names ||
            throw(ArgumentError("values does not contain a value for model $label"))
        push!(out, getproperty(values, key))
    end
    return out
end

function _explicit_sensitivity_values(
        labels::AbstractVector{<:AbstractString},
        values::AbstractDict)
    out = Any[]
    for label in labels
        if haskey(values, label)
            push!(out, values[label])
        elseif haskey(values, Symbol(label))
            push!(out, values[Symbol(label)])
        else
            throw(ArgumentError("values does not contain a value for model $label"))
        end
    end
    return out
end

function _explicit_sensitivity_values(
        labels::AbstractVector{<:AbstractString},
        values)
    collected = collect(values)
    length(collected) == length(labels) ||
        throw(ArgumentError(
            "values has length $(length(collected)); expected $(length(labels))"))
    return Any[collected...]
end

function _sensitivity_value_map(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString},
        axis::Symbol,
        values)
    resolved_values = values === nothing ?
        [_default_sensitivity_value(fit, label, axis)
            for (fit, label) in zip(fits, labels)] :
        _explicit_sensitivity_values(labels, values)
    return Dict{String,Any}(labels[index] => resolved_values[index]
        for index in eachindex(labels))
end

function _sensitivity_baseline_label(
        labels::AbstractVector{<:AbstractString},
        baseline)
    isempty(labels) && throw(ArgumentError("at least two models are required"))
    baseline === nothing && return labels[1]
    label = string(baseline)
    label in labels ||
        throw(ArgumentError("baseline model $label is not present in the comparison"))
    return label
end

function _sensitivity_baseline_difference(row::NamedTuple, baseline_row::NamedTuple)
    row.criterion === :waic && return (;
        baseline_elpd = baseline_row.elpd_waic,
        baseline_information_criterion = baseline_row.waic,
        elpd_difference_from_baseline = row.elpd_waic - baseline_row.elpd_waic,
        information_criterion_difference_from_baseline = row.waic - baseline_row.waic,
    )
    row.criterion === :loo && return (;
        baseline_elpd = baseline_row.elpd_loo,
        baseline_information_criterion = baseline_row.looic,
        elpd_difference_from_baseline = row.elpd_loo - baseline_row.elpd_loo,
        information_criterion_difference_from_baseline = row.looic - baseline_row.looic,
    )
    row.criterion === :kfold && return (;
        baseline_elpd = baseline_row.elpd_kfold,
        baseline_information_criterion = baseline_row.kfoldic,
        elpd_difference_from_baseline = row.elpd_kfold - baseline_row.elpd_kfold,
        information_criterion_difference_from_baseline =
            row.kfoldic - baseline_row.kfoldic,
    )
    throw(ArgumentError("unsupported comparison criterion $(row.criterion)"))
end

function _sensitivity_comparison_rows(comparison_rows::AbstractVector,
        axis::Symbol,
        value_map::AbstractDict{String,Any},
        baseline_label::AbstractString)
    baseline_index = findfirst(row -> row.model == baseline_label, comparison_rows)
    baseline_index === nothing &&
        throw(ArgumentError("baseline model $baseline_label is not present in comparison rows"))
    baseline_row = comparison_rows[baseline_index]
    baseline_value = value_map[String(baseline_label)]
    rows = NamedTuple[]
    for row in comparison_rows
        value = value_map[row.model]
        is_baseline = row.model == baseline_label
        push!(rows, merge((;
                sensitivity_axis = axis,
                sensitivity_value = value,
                baseline_model = String(baseline_label),
                baseline_value,
                is_baseline,
                sensitivity_contrast = (candidate = value, baseline = baseline_value),
                contrast = is_baseline ? :baseline : :candidate_vs_baseline,
            ),
            row,
            _sensitivity_baseline_difference(row, baseline_row)))
    end
    return rows
end

function _sensitivity_comparison(fits::AbstractVector{<:_ModelComparisonFit},
        labels::AbstractVector{<:AbstractString};
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    checked_axis = _sensitivity_axis(axis)
    checked_criterion = _compare_criterion(criterion)
    _compare_model_names(labels, length(labels))
    value_map = _sensitivity_value_map(fits, labels, checked_axis, values)
    baseline_label = _sensitivity_baseline_label(labels, baseline)
    comparison_rows = checked_criterion === :waic ?
        _sensitivity_compare_models_waic(fits, labels, checked_axis;
            ndraws, draw_indices, rng) :
        _sensitivity_compare_models_loo(fits, labels, checked_axis;
            ndraws,
            draw_indices,
            rng,
            psis_smoothing = checked_criterion === :psis_loo)
    return _sensitivity_comparison_rows(
        comparison_rows,
        checked_axis,
        value_map,
        baseline_label,
    )
end

"""
    sensitivity_comparison(fits...; names = nothing, axis = :model,
        values = nothing, baseline = nothing, criterion = :waic,
        ndraws = nothing, draw_indices = nothing, rng = Random.default_rng())
    sensitivity_comparison(models::Pair...; axis = :model, values = nothing,
        baseline = nothing, criterion = :waic, ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng())

Return report-ready sensitivity comparison rows for already fitted candidate
models. The function uses the same WAIC, raw-importance LOO, or PSIS-smoothed
LOO scoring rows as [`compare_models`](@ref), while applying
sensitivity-specific compatibility checks. Additional columns identify the requested
`sensitivity_axis`, the per-model `sensitivity_value`, the baseline model and
value, and expected-log-predictive-density and information-criterion
differences relative to that baseline.

When `values` is omitted, values are inferred for common axes: `:model`,
`:model_family`, `:thresholds`, `:discrimination`, `:dimensions`, `:q_matrix`,
`:estimation_status`, `:prior`, `:backend`, and `:sampler`. Pass a vector,
tuple, dictionary, or named tuple to `values` for custom axes such as
`:anchor`, `:dff`, or externally defined prior regimes. `baseline` names the
baseline model label and defaults to the first supplied model. Direct
`compare_models` output still requires matching dimensions and Q-matrices;
declared `sensitivity_comparison` rows allow dimensionality differences for
`axis = :dimensions`, and fixed-Q differences for `axis = :q_matrix` or
`:dimensions`, while retaining same-data and same-category checks.
"""
function sensitivity_comparison(fits::_ModelComparisonFit...;
        names = nothing,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    labels = _compare_model_names(names, length(fits))
    collected_fits = _ModelComparisonFit[fits...]
    return _sensitivity_comparison(collected_fits, labels;
        axis,
        values,
        baseline,
        criterion,
        ndraws,
        draw_indices,
        rng)
end

function sensitivity_comparison(models::Pair...;
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        criterion::Symbol = :waic,
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng())
    fits = _ModelComparisonFit[]
    labels = String[]
    for model in models
        model.second isa _ModelComparisonFit ||
            throw(ArgumentError("model pair :$(model.first) does not contain a comparable fitted model"))
        push!(labels, string(model.first))
        push!(fits, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _sensitivity_comparison(fits, labels;
        axis,
        values,
        baseline,
        criterion,
        ndraws,
        draw_indices,
        rng)
end

function _kfold_sensitivity_value_map(labels::AbstractVector{<:AbstractString},
        axis::Symbol,
        values)
    resolved_values = if values === nothing
        axis === :model ||
            throw(ArgumentError(
                "axis = :$axis requires explicit values for K-fold sensitivity rows"))
        Any[String(label) for label in labels]
    else
        _explicit_sensitivity_values(labels, values)
    end
    return Dict{String,Any}(labels[index] => resolved_values[index]
        for index in eachindex(labels))
end

function _kfold_sensitivity_comparison(stats::AbstractVector,
        labels::AbstractVector{<:AbstractString};
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    checked_axis = _sensitivity_axis(axis)
    _compare_model_names(labels, length(labels))
    value_map = _kfold_sensitivity_value_map(labels, checked_axis, values)
    baseline_label = _sensitivity_baseline_label(labels, baseline)
    comparison_rows = _kfold_comparison_rows(labels, stats)
    return _sensitivity_comparison_rows(
        comparison_rows,
        checked_axis,
        value_map,
        baseline_label,
    )
end

"""
    kfold_sensitivity_comparison(stats...; names = nothing, axis = :model,
        values = nothing, baseline = nothing)
    kfold_sensitivity_comparison(models::Pair...; axis = :model,
        values = nothing, baseline = nothing)

Return report-ready sensitivity rows for supplied heldout K-fold summaries.
This helper uses [`compare_kfold`](@ref) compatibility checks, then adds the
declared sensitivity axis, per-model values, baseline label, baseline value,
and baseline-relative heldout ELPD and K-fold information-criterion
differences. It does not construct folds or refit models. For axes other than
`:model`, pass explicit `values`.
"""
function kfold_sensitivity_comparison(stats::NamedTuple...;
        names = nothing,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    labels = _compare_model_names(names, length(stats))
    return _kfold_sensitivity_comparison(Any[stats...], labels;
        axis,
        values,
        baseline)
end

function kfold_sensitivity_comparison(;
        names = nothing,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    labels = _compare_model_names(names, 0)
    return _kfold_sensitivity_comparison(Any[], labels;
        axis,
        values,
        baseline)
end

function kfold_sensitivity_comparison(models::Pair...;
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing)
    stats = Any[]
    labels = String[]
    for model in models
        push!(labels, string(model.first))
        push!(stats, model.second)
    end
    _compare_model_names(labels, length(labels))
    return _kfold_sensitivity_comparison(stats, labels;
        axis,
        values,
        baseline)
end

const _RefitComparisonModel = Union{FacetData,FacetSpec,FacetDesign,_ModelComparisonFit}

_refit_comparison_data(data::FacetData) = data
_refit_comparison_data(spec::FacetSpec) = spec.data
_refit_comparison_data(design::FacetDesign) = design.spec.data
_refit_comparison_data(fit::_ModelComparisonFit) = fit.design.spec.data

_refit_comparison_data_signature(data::FacetData) = _data_signature(data)
_refit_comparison_data_signature(spec::FacetSpec) = spec.validation.data_signature
_refit_comparison_data_signature(design::FacetDesign) =
    design.spec.validation.data_signature
_refit_comparison_data_signature(fit::_ModelComparisonFit) =
    fit.design.spec.validation.data_signature

function _refit_comparison_contract(model::_RefitComparisonModel)
    data = _refit_comparison_data(model)
    return (;
        data_signature = _refit_comparison_data_signature(model),
        n_observations = data.n,
        category_levels = copy(data.category_levels),
        optional_facets = sort(collect(keys(data.optional)); by = string),
    )
end

function _require_refit_comparison_compatibility(models::AbstractVector)
    contracts = [_refit_comparison_contract(model) for model in models]
    _require_same_contract_field(contracts, :data_signature,
        "all refit comparison models must use the same observation data and row order")
    _require_same_contract_field(contracts, :n_observations,
        "all refit comparison models must have the same number of observations")
    _require_same_contract_field(contracts, :category_levels,
        "all refit comparison models must use the same ordinal category levels")
    _require_same_contract_field(contracts, :optional_facets,
        "all refit comparison models must use the same optional facet roles")
    return nothing
end

function _refit_comparison_pairs(models::Tuple, caller::AbstractString)
    length(models) >= 2 || throw(ArgumentError("at least two models are required"))
    labels = String[]
    refit_models = _RefitComparisonModel[]
    for model in models
        model.second isa _RefitComparisonModel ||
            throw(ArgumentError(
                "$caller model pair :$(model.first) does not contain a supported " *
                "refit comparison model"))
        push!(labels, string(model.first))
        push!(refit_models, model.second)
    end
    _compare_model_names(labels, length(labels))
    return labels, refit_models
end

function _refit_comparison_named_models(models::Tuple, names, caller::AbstractString)
    length(models) >= 2 || throw(ArgumentError("at least two models are required"))
    labels = _compare_model_names(names, length(models))
    refit_models = _RefitComparisonModel[models...]
    length(refit_models) == length(models) ||
        throw(ArgumentError("$caller received an unsupported refit comparison model"))
    return labels, refit_models
end

function _refit_plan_observation_indices(plan)
    hasproperty(plan, :heldout_observation_indices) || return Any[]
    isempty(plan.heldout_observation_indices) && return Any[]
    return vcat(plan.heldout_observation_indices...)
end

function _kfold_refit_comparison_plan(models::AbstractVector, plan;
        k,
        group_by::Union{Nothing,Symbol},
        shuffle::Bool,
        rng::AbstractRNG,
        fold_ids)
    if plan === nothing
        k === nothing &&
            throw(ArgumentError("kfold_refit_comparison requires either plan or k"))
        return kfold_plan(_refit_comparison_data(first(models));
            k,
            group_by,
            shuffle,
            rng,
            fold_ids)
    end
    k === nothing ||
        throw(ArgumentError("kfold_refit_comparison accepts either plan or k, not both"))
    return plan
end

function _loo_refit_comparison_plan(models::AbstractVector, plan;
        stat,
        observations,
        threshold,
        only_flagged::Bool,
        fold_ids)
    if plan !== nothing
        stat === nothing ||
            throw(ArgumentError("loo_refit_comparison accepts either plan or stat, not both"))
        observations === nothing ||
            throw(ArgumentError("loo_refit_comparison accepts either plan or observations, not both"))
        fold_ids === nothing ||
            throw(ArgumentError("loo_refit_comparison accepts either plan or fold_ids, not both"))
        return plan
    end

    data = _refit_comparison_data(first(models))
    if stat === nothing
        return loo_refit_plan(data; observations, fold_ids)
    end
    observations === nothing ||
        throw(ArgumentError("loo_refit_comparison accepts either stat or observations, not both"))
    return loo_refit_plan(data, stat; threshold, only_flagged, fold_ids)
end

function _kfold_refit_comparison_model(model, plan;
        prior,
        return_fits::Bool,
        kwargs...)
    prior === nothing &&
        return kfold_refit(model, plan; return_fits, kwargs...)
    return kfold_refit(model, plan; prior, return_fits, kwargs...)
end

function _loo_refit_comparison_model(model, plan;
        prior,
        return_fits::Bool,
        kwargs...)
    prior === nothing &&
        return loo_refit(model, plan; return_fits, kwargs...)
    return loo_refit(model, plan; prior, return_fits, kwargs...)
end

function _refit_comparison_rows(labels::AbstractVector{<:AbstractString},
        refits::AbstractVector;
        axis::Symbol,
        values,
        baseline)
    stats = Any[]
    for refit in refits
        hasproperty(refit, :kfold_summary) ||
            throw(ArgumentError("refit result is missing kfold_summary"))
        refit.kfold_summary === nothing && push!(stats, nothing)
        refit.kfold_summary === nothing || push!(stats, refit.kfold_summary)
    end
    if any(isnothing, stats)
        all(isnothing, stats) ||
            throw(ArgumentError("either all or no refit results must include kfold_summary"))
        return NamedTuple[], NamedTuple[]
    end
    pairs = [labels[index] => stats[index] for index in eachindex(labels)]
    return compare_kfold(pairs...),
        kfold_sensitivity_comparison(pairs...; axis, values, baseline)
end

function _refit_comparison_refit_rows(labels::AbstractVector{<:AbstractString},
        refits::AbstractVector)
    rows = NamedTuple[]
    for (label, refit) in zip(labels, refits)
        push!(rows, (;
            model = String(label),
            object = refit.object,
            schema = refit.schema,
            criterion = refit.criterion,
            method = refit.method,
            refit_method = hasproperty(refit, :refit_method) ?
                refit.refit_method : missing,
            n_refits = refit.n_refits,
            n_folds = refit.n_folds,
            n_observations = refit.n_observations,
            n_total_observations = refit.n_total_observations,
            n_draws_by_fold = copy(refit.n_draws_by_fold),
            n_heldout_by_fold = copy(refit.n_heldout_by_fold),
            folds = copy(refit.folds),
            warning = refit.warning,
            plan_diagnostics_passed = hasproperty(refit, :plan_diagnostics) ?
                refit.plan_diagnostics.passed : missing,
        ))
    end
    return rows
end

function _refit_comparison_warning(refits::AbstractVector,
        comparison_rows::AbstractVector)
    warnings = [refit.warning for refit in refits if hasproperty(refit, :warning)]
    isempty(comparison_rows) && return :no_refits_required
    all(warning -> warning === :ok, warnings) && return :ok
    all(warning -> warning === :no_refits_required, warnings) &&
        return :no_refits_required
    return :refit_warning
end

function _refit_comparison_result(schema::AbstractString,
        object::Symbol,
        refit_method::Symbol,
        data::FacetData,
        plan,
        labels::AbstractVector{<:AbstractString},
        refits::AbstractVector,
        comparison_rows::AbstractVector,
        sensitivity_rows::AbstractVector;
        include_refits::Bool)
    refit_rows = _refit_comparison_refit_rows(labels, refits)
    n_refits_per_model = [row.n_refits for row in refit_rows]
    return (;
        schema,
        object,
        criterion = isempty(comparison_rows) ? :loo_refit : :kfold,
        method = :shared_plan_refit_comparison,
        refit_method,
        comparison_contract = _KFOLD_COMPARISON_CONTRACT,
        plan_schema = hasproperty(plan, :schema) ? plan.schema : missing,
        group_by = hasproperty(plan, :group_by) ? plan.group_by : missing,
        n_models = length(labels),
        models = Tuple(labels),
        n_refits_per_model,
        n_total_refits = sum(n_refits_per_model),
        n_folds = hasproperty(plan, :n_folds) ? plan.n_folds : missing,
        n_observations = isempty(refit_rows) ? 0 : refit_rows[1].n_observations,
        n_total_observations = data.n,
        folds = hasproperty(plan, :folds) ? copy(plan.folds) : Any[],
        observation_indices = _refit_plan_observation_indices(plan),
        refit_rows,
        comparison_rows,
        sensitivity_rows,
        refits = include_refits ? Tuple(refits) : nothing,
        warning = _refit_comparison_warning(refits, comparison_rows),
    )
end

function _kfold_refit_comparison(models::AbstractVector,
        labels::AbstractVector{<:AbstractString};
        plan = nothing,
        k = nothing,
        group_by::Union{Nothing,Symbol} = nothing,
        shuffle::Bool = false,
        rng::AbstractRNG = Random.default_rng(),
        fold_ids = nothing,
        prior = nothing,
        return_refits::Bool = false,
        return_fits::Bool = false,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        kwargs...)
    _require_refit_comparison_compatibility(models)
    checked_plan = _kfold_refit_comparison_plan(models, plan;
        k,
        group_by,
        shuffle,
        rng,
        fold_ids)
    refits = Any[
        _kfold_refit_comparison_model(model, checked_plan;
            prior,
            return_fits,
            kwargs...)
        for model in models
    ]
    comparison_rows, sensitivity_rows =
        _refit_comparison_rows(labels, refits; axis, values, baseline)
    return _refit_comparison_result(
        "bayesianmgmfrm.kfold_refit_comparison.v1",
        :kfold_refit_comparison,
        :automatic_kfold_refit,
        _refit_comparison_data(first(models)),
        checked_plan,
        labels,
        refits,
        comparison_rows,
        sensitivity_rows;
        include_refits = return_refits || return_fits,
    )
end

"""
    kfold_refit_comparison(models::Pair...; plan = nothing, k = nothing,
        group_by = nothing, shuffle = false, rng = Random.default_rng(),
        fold_ids = nothing, prior = nothing, return_refits = false,
        return_fits = false, axis = :model, values = nothing, baseline = nothing,
        kwargs...)
    kfold_refit_comparison(model1, model2, ...; names = nothing, kwargs...)

Execute automatic heldout K-fold refits for multiple fit-supported
MFRM/RSM/PCM candidates under a shared [`kfold_plan`](@ref), then return both
[`compare_kfold`](@ref) rows and baseline-relative
[`kfold_sensitivity_comparison`](@ref) rows. Labels are supplied by pair keys
or by `names`; unlabeled positional models use `model_1`, `model_2`, ....
All models must use the same observation data and row order. Pass an explicit
`plan`, or pass `k` plus the usual fold-planning keywords to build a shared
plan from the first model.
"""
function kfold_refit_comparison(models::Pair...; kwargs...)
    labels, refit_models =
        _refit_comparison_pairs(models, "kfold_refit_comparison")
    return _kfold_refit_comparison(refit_models, labels; kwargs...)
end

function kfold_refit_comparison(
        first::_RefitComparisonModel,
        second::_RefitComparisonModel,
        rest::_RefitComparisonModel...;
        names = nothing,
        kwargs...)
    models = (first, second, rest...)
    labels, refit_models =
        _refit_comparison_named_models(models, names, "kfold_refit_comparison")
    return _kfold_refit_comparison(refit_models, labels; kwargs...)
end

function _loo_refit_comparison(models::AbstractVector,
        labels::AbstractVector{<:AbstractString};
        plan = nothing,
        stat = nothing,
        observations = nothing,
        threshold = nothing,
        only_flagged::Bool = true,
        fold_ids = nothing,
        prior = nothing,
        return_refits::Bool = false,
        return_fits::Bool = false,
        axis::Symbol = :model,
        values = nothing,
        baseline = nothing,
        kwargs...)
    _require_refit_comparison_compatibility(models)
    checked_plan = _loo_refit_comparison_plan(models, plan;
        stat,
        observations,
        threshold,
        only_flagged,
        fold_ids)
    refits = Any[
        _loo_refit_comparison_model(model, checked_plan;
            prior,
            return_fits,
            kwargs...)
        for model in models
    ]
    comparison_rows, sensitivity_rows =
        _refit_comparison_rows(labels, refits; axis, values, baseline)
    return _refit_comparison_result(
        "bayesianmgmfrm.loo_refit_comparison.v1",
        :loo_refit_comparison,
        :exact_leave_one_observation_out_refit,
        _refit_comparison_data(first(models)),
        checked_plan,
        labels,
        refits,
        comparison_rows,
        sensitivity_rows;
        include_refits = return_refits || return_fits,
    )
end

"""
    loo_refit_comparison(models::Pair...; plan = nothing, stat = nothing,
        observations = nothing, threshold = nothing, only_flagged = true,
        fold_ids = nothing, prior = nothing, return_refits = false,
        return_fits = false, axis = :model, values = nothing, baseline = nothing,
        kwargs...)
    loo_refit_comparison(model1, model2, ...; names = nothing, kwargs...)

Execute exact leave-one-observation-out refits for multiple fit-supported
MFRM/RSM/PCM candidates under a shared [`loo_refit_plan`](@ref), then return
K-fold-compatible comparison and sensitivity rows for the heldout exact-refit
log scores. Pass an explicit `plan`, select `observations`, or pass a raw LOO
`stat` to construct the shared follow-up plan from the first model. If a
flagged-row plan contains no refits, comparison rows are empty and the returned
warning is `:no_refits_required`.
"""
function loo_refit_comparison(models::Pair...; kwargs...)
    labels, refit_models =
        _refit_comparison_pairs(models, "loo_refit_comparison")
    return _loo_refit_comparison(refit_models, labels; kwargs...)
end

function loo_refit_comparison(
        first::_RefitComparisonModel,
        second::_RefitComparisonModel,
        rest::_RefitComparisonModel...;
        names = nothing,
        kwargs...)
    models = (first, second, rest...)
    labels, refit_models =
        _refit_comparison_named_models(models, names, "loo_refit_comparison")
    return _loo_refit_comparison(refit_models, labels; kwargs...)
end

const _DEFAULT_SENSITIVITY_REQUIRED_AXES = (
    :thresholds,
    :discrimination,
    :rater_pooling,
    :dff,
    :anchor,
    :dimensions,
    :prior_regime,
)

function _sensitivity_summary_axis(axis::Symbol)
    checked = _sensitivity_axis(axis)
    checked === :prior && return :prior_regime
    checked in (:anchors, :anchoring) && return :anchor
    checked in (:pooling, :rater_effects, :rater_pooling) && return :rater_pooling
    checked in (:dff_on_off, :dff_effects) && return :dff
    return checked
end

function _sensitivity_summary_axis(axis)
    axis isa Symbol ||
        throw(ArgumentError("sensitivity axes must be Symbols"))
    return _sensitivity_summary_axis(axis)
end

function _sensitivity_axis_tuple(axes)
    out = Symbol[]
    for axis in axes
        canonical = _sensitivity_summary_axis(axis)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

function _sensitivity_axis_tuple(axis::Symbol)
    return (_sensitivity_summary_axis(axis),)
end

function _sensitivity_unique_tuple(values)
    collected = collect(Set(values))
    sort!(collected; by = string)
    return Tuple(collected)
end

function _sensitivity_summary_row_check(row::NamedTuple)
    required = (
        :sensitivity_axis,
        :sensitivity_value,
        :baseline_value,
        :model,
        :baseline_model,
        :is_baseline,
        :contrast,
        :criterion,
        :elpd_difference_from_baseline,
        :information_criterion_difference_from_baseline,
    )
    fields = propertynames(row)
    missing_fields = [field for field in required if !(field in fields)]
    isempty(missing_fields) ||
        throw(ArgumentError("sensitivity comparison row is missing fields: $(join(missing_fields, ", "))"))
    row.sensitivity_axis isa Symbol ||
        throw(ArgumentError("sensitivity_axis must be a Symbol"))
    row.is_baseline isa Bool ||
        throw(ArgumentError("is_baseline must be a Bool"))
    row.criterion isa Symbol ||
        throw(ArgumentError("criterion must be a Symbol"))
    return nothing
end

function _sensitivity_axis_summary_row(axis::Symbol, rows::AbstractVector)
    if isempty(rows)
        return (;
            axis,
            present = false,
            status = :missing,
            n_rows = 0,
            n_models = 0,
            models = (),
            n_values = 0,
            sensitivity_values = (),
            has_baseline = false,
            n_baseline_rows = 0,
            n_candidate_rows = 0,
            baseline_models = (),
            criteria = (),
            warnings = (),
        )
    end

    models = _sensitivity_unique_tuple(String(string(row.model)) for row in rows)
    values = _sensitivity_unique_tuple(row.sensitivity_value for row in rows)
    baseline_models =
        _sensitivity_unique_tuple(String(string(row.baseline_model)) for row in rows)
    criteria = _sensitivity_unique_tuple(row.criterion for row in rows)
    n_baseline_rows = count(row -> row.is_baseline, rows)
    n_candidate_rows = length(rows) - n_baseline_rows
    has_baseline = n_baseline_rows > 0
    has_candidate = n_candidate_rows > 0
    warnings = Symbol[]
    length(criteria) > 1 && push!(warnings, :mixed_criteria)
    length(baseline_models) > 1 && push!(warnings, :multiple_baselines)
    status = has_baseline && has_candidate ? :complete : :incomplete

    return (;
        axis,
        present = true,
        status,
        n_rows = length(rows),
        n_models = length(models),
        models,
        n_values = length(values),
        sensitivity_values = values,
        has_baseline,
        n_baseline_rows,
        n_candidate_rows,
        baseline_models,
        criteria,
        warnings = Tuple(warnings),
    )
end

"""
    sensitivity_comparison_summary(rows; required_axes =
        (:thresholds, :discrimination, :rater_pooling, :dff, :anchor,
         :dimensions, :prior_regime), view = :full)
    sensitivity_comparison_summary(row, rows...; required_axes = ...)

Summarize report-ready sensitivity comparison rows and check whether the
declared sensitivity table covers the package's default critical-review axes:
threshold family, discrimination on/off, pooled versus unpooled rater effects,
DFF on/off, anchor choice, dimensionality, and prior regime. Rows are expected
to come from [`sensitivity_comparison`](@ref) or an equivalent same-schema
external comparison table.

The summary records observed axes, missing required axes, per-axis model and
baseline coverage, criteria used, and whether every required axis has both a
baseline and at least one candidate row. It checks declared comparison rows; it
does not create refits, fit unsupported generalized/DFF/anchor models, or
replace predeclared simulation and case-study protocols.
`view = :public` returns the compact reader-facing projection; `:full`
preserves the existing contract.
"""
function sensitivity_comparison_summary(rows::AbstractVector;
        required_axes = _DEFAULT_SENSITIVITY_REQUIRED_AXES,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    isempty(rows) &&
        throw(ArgumentError("at least one sensitivity comparison row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("sensitivity comparison summary expects NamedTuple rows"))
        _sensitivity_summary_row_check(row)
    end

    checked_required = _sensitivity_axis_tuple(required_axes)
    observed_axes = _sensitivity_unique_tuple(
        _sensitivity_summary_axis(row.sensitivity_axis) for row in rows)
    observed_set = Set(observed_axes)
    missing_required_axes =
        Tuple(axis for axis in checked_required if !(axis in observed_set))
    extra_axes = sort(
        [axis for axis in observed_axes if !(axis in checked_required)];
        by = string)
    reported_axes = (checked_required..., extra_axes...)
    axis_rows = NamedTuple[]
    for axis in reported_axes
        axis_specific_rows = NamedTuple[
            row for row in rows
            if _sensitivity_summary_axis(row.sensitivity_axis) === axis
        ]
        push!(axis_rows, _sensitivity_axis_summary_row(axis, axis_specific_rows))
    end

    required_axis_rows = filter(row -> row.axis in checked_required, axis_rows)
    incomplete_required_axes = Tuple(row.axis for row in required_axis_rows
        if row.status !== :complete)
    complete_required_axes = Tuple(row.axis for row in required_axis_rows
        if row.status === :complete)
    criteria = _sensitivity_unique_tuple(row.criterion for row in rows)
    baseline_models =
        _sensitivity_unique_tuple(String(string(row.baseline_model)) for row in rows)
    n_baseline_rows = count(row -> row.is_baseline, rows)

    summary = (;
        schema = "bayesianmgmfrm.sensitivity_comparison_summary.v1",
        object = :sensitivity_comparison_summary,
        comparison_scope = :declared_same_data_sensitivity_rows,
        coverage_contract = :required_axes_need_baseline_and_candidate_rows,
        required_axes = checked_required,
        observed_axes,
        missing_required_axes,
        complete_required_axes,
        incomplete_required_axes,
        passed = isempty(missing_required_axes) && isempty(incomplete_required_axes),
        n_rows = length(rows),
        n_axes = length(observed_axes),
        n_required_axes = length(checked_required),
        n_complete_required_axes = length(complete_required_axes),
        n_baseline_rows,
        n_candidate_rows = length(rows) - n_baseline_rows,
        criteria,
        baseline_models,
        axis_rows = Tuple(axis_rows),
        caveat = :summary_of_declared_rows_not_refit_orchestration,
        next_gate = :predeclared_case_study_sensitivity_grid,
    )
    return view === :full ? summary :
        _public_reader_payload(
            summary;
            schema = "bayesianmgmfrm.sensitivity_comparison_summary_public.v1",
        )
end

function sensitivity_comparison_summary(row::NamedTuple, rows::NamedTuple...;
        required_axes = _DEFAULT_SENSITIVITY_REQUIRED_AXES,
        view::Symbol = :full)
    return sensitivity_comparison_summary(
        [row; collect(rows)];
        required_axes,
        view,
    )
end

function _sensitivity_power_values(values, name::Symbol)
    collected = Float64.(collect(values))
    isempty(collected) &&
        throw(ArgumentError("$name must contain at least one power value"))
    all(value -> isfinite(value) && value >= 0, collected) ||
        throw(ArgumentError("$name values must be finite and non-negative"))
    return collected
end

function _sensitivity_power_values(value::Real, name::Symbol)
    checked = Float64(value)
    isfinite(checked) && checked >= 0 ||
        throw(ArgumentError("$name values must be finite and non-negative"))
    return [checked]
end

function _sensitivity_min_ess(min_effective_sample_size, n_draws::Int)
    min_effective_sample_size === nothing &&
        return max(1.0, 0.1 * n_draws)
    value = Float64(min_effective_sample_size)
    isfinite(value) && value > 0 ||
        throw(ArgumentError("min_effective_sample_size must be finite and positive"))
    return value
end

function _check_sensitivity_log_terms(logprior_draws::AbstractVector,
        loglikelihood_draws::AbstractVector)
    n_draws = length(logprior_draws)
    n_draws == length(loglikelihood_draws) ||
        throw(ArgumentError("logprior_draws and loglikelihood_draws must have the same length"))
    n_draws >= 2 ||
        throw(ArgumentError("prior/likelihood sensitivity requires at least two draws"))
    prior_values = Float64.(logprior_draws)
    likelihood_values = Float64.(loglikelihood_draws)
    all(isfinite, prior_values) ||
        throw(ArgumentError("logprior_draws contain non-finite values"))
    all(isfinite, likelihood_values) ||
        throw(ArgumentError("loglikelihood_draws contain non-finite values"))
    return prior_values, likelihood_values
end

function _weighted_mean(values::AbstractVector{Float64},
        normalized_log_weights::AbstractVector{Float64})
    total = 0.0
    for index in eachindex(values)
        total += exp(normalized_log_weights[index]) * values[index]
    end
    return total
end

function _normalized_weight_ess(normalized_log_weights::AbstractVector{Float64})
    sum_squared = 0.0
    for value in normalized_log_weights
        weight = exp(value)
        sum_squared += weight * weight
    end
    return 1 / sum_squared
end

function _prior_likelihood_sensitivity_metadata()
    return (; input = :draw_level_log_terms)
end

function _prior_likelihood_sensitivity_metadata(fit::_ModelComparisonFit)
    spec = fit.design.spec
    data = spec.data
    return (;
        input = :fit_object,
        model_family = spec.family,
        thresholds = spec.thresholds,
        dimensions = spec.dimensions,
        discrimination = spec.discrimination,
        q_matrix = _q_matrix_manifest(spec.q_matrix),
        estimation_status = spec.estimation_status,
        data_signature = spec.validation.data_signature,
        n_observations = data.n,
        n_total_draws = size(fit.draws, 1),
        n_parameters = size(fit.draws, 2),
        backend = fit.backend,
        sampler = fit.sampler,
    )
end

function _prior_likelihood_sensitivity(logprior_draws::AbstractVector,
        loglikelihood_draws::AbstractVector;
        prior_powers = (0.8, 1.0, 1.2),
        likelihood_powers = (0.8, 1.0, 1.2),
        min_effective_sample_size = nothing,
        metadata = _prior_likelihood_sensitivity_metadata())
    prior_values, likelihood_values =
        _check_sensitivity_log_terms(logprior_draws, loglikelihood_draws)
    checked_prior_powers = _sensitivity_power_values(prior_powers, :prior_powers)
    checked_likelihood_powers =
        _sensitivity_power_values(likelihood_powers, :likelihood_powers)
    n_draws = length(prior_values)
    ess_threshold = _sensitivity_min_ess(min_effective_sample_size, n_draws)
    baseline_mean_logprior = _column_mean(prior_values)
    baseline_mean_loglikelihood = _column_mean(likelihood_values)

    rows = NamedTuple[]
    log_weights = Vector{Float64}(undef, n_draws)
    normalized_log_weights = Vector{Float64}(undef, n_draws)
    for prior_power in checked_prior_powers
        for likelihood_power in checked_likelihood_powers
            prior_delta = prior_power - 1.0
            likelihood_delta = likelihood_power - 1.0
            for draw in 1:n_draws
                log_weights[draw] =
                    prior_delta * prior_values[draw] +
                    likelihood_delta * likelihood_values[draw]
            end
            log_weight_total = _logsumexp(log_weights)
            for draw in 1:n_draws
                normalized_log_weights[draw] = log_weights[draw] - log_weight_total
            end
            effective_sample_size =
                _normalized_weight_ess(normalized_log_weights)
            weighted_mean_logprior =
                _weighted_mean(prior_values, normalized_log_weights)
            weighted_mean_loglikelihood =
                _weighted_mean(likelihood_values, normalized_log_weights)
            logprior_shift = weighted_mean_logprior - baseline_mean_logprior
            loglikelihood_shift =
                weighted_mean_loglikelihood - baseline_mean_loglikelihood
            warning = effective_sample_size < ess_threshold ?
                :low_effective_sample_size : :ok
            push!(rows, (;
                prior_power,
                likelihood_power,
                prior_power_delta = prior_delta,
                likelihood_power_delta = likelihood_delta,
                log_normalizing_ratio = log_weight_total - log(n_draws),
                effective_sample_size,
                effective_sample_size_ratio = effective_sample_size / n_draws,
                max_normalized_weight = maximum(exp, normalized_log_weights),
                baseline_mean_logprior,
                weighted_mean_logprior,
                logprior_mean_shift = logprior_shift,
                abs_logprior_mean_shift = abs(logprior_shift),
                baseline_mean_loglikelihood,
                weighted_mean_loglikelihood,
                loglikelihood_mean_shift = loglikelihood_shift,
                abs_loglikelihood_mean_shift = abs(loglikelihood_shift),
                warning,
            ))
        end
    end

    low_ess_count = count(row -> row.warning === :low_effective_sample_size, rows)
    return merge((;
            schema = "bayesianmgmfrm.prior_likelihood_sensitivity.v1",
            object = :prior_likelihood_sensitivity,
            method = :self_normalized_importance_reweighting,
            comparison_scope = :local_power_scaling_grid,
            baseline_prior_power = 1.0,
            baseline_likelihood_power = 1.0,
        ),
        metadata,
        (;
            prior_powers = Tuple(checked_prior_powers),
            likelihood_powers = Tuple(checked_likelihood_powers),
            n_prior_powers = length(checked_prior_powers),
            n_likelihood_powers = length(checked_likelihood_powers),
            n_cells = length(rows),
            n_draws,
            min_effective_sample_size = ess_threshold,
            baseline_mean_logprior,
            baseline_mean_loglikelihood,
            min_effective_sample_size_observed =
                minimum(row.effective_sample_size for row in rows),
            low_effective_sample_size_count = low_ess_count,
            max_abs_logprior_mean_shift =
                maximum(row.abs_logprior_mean_shift for row in rows),
            max_abs_loglikelihood_mean_shift =
                maximum(row.abs_loglikelihood_mean_shift for row in rows),
            rows = Tuple(rows),
            warning = low_ess_count == 0 ? :ok : :low_effective_sample_size,
            caveat = :local_reweighting_not_refit,
        ))
end

function _prior_likelihood_draw_terms(fit::MFRMFit, indices::AbstractVector{Int})
    selected_draws = fit.draws[indices, :]
    pointwise = pointwise_loglikelihood_matrix(fit.design, selected_draws)
    n_draws = size(selected_draws, 1)
    logprior_draws = Vector{Float64}(undef, n_draws)
    loglikelihood_draws = Vector{Float64}(undef, n_draws)
    for draw in 1:n_draws
        logprior_draws[draw] =
            logprior(fit.design, view(selected_draws, draw, :), fit.prior)
        loglikelihood_draws[draw] = sum(view(pointwise, draw, :))
    end
    return logprior_draws, loglikelihood_draws
end

function _prior_likelihood_draw_terms(fit::GMFRMFit, indices::AbstractVector{Int})
    target = _gmfrm_promotion_candidate_logdensity(fit.design; prior = fit.prior)
    logprior_draws = Vector{Float64}(undef, length(indices))
    loglikelihood_draws = Vector{Float64}(undef, length(indices))
    for (position, index) in pairs(indices)
        logprior_draws[position] =
            _source_fixture_logprior(target, view(fit.draws, index, :))
        loglikelihood_draws[position] = Float64(fit.direct_loglikelihood[index])
    end
    return logprior_draws, loglikelihood_draws
end

function _prior_likelihood_draw_terms(fit::MGMFRMFit, indices::AbstractVector{Int})
    target = _mgmfrm_guarded_local_fit_logdensity(fit.design; prior = fit.prior)
    logprior_draws = Vector{Float64}(undef, length(indices))
    loglikelihood_draws = Vector{Float64}(undef, length(indices))
    for (position, index) in pairs(indices)
        logprior_draws[position] =
            _source_fixture_logprior(target, view(fit.draws, index, :))
        loglikelihood_draws[position] = Float64(fit.direct_loglikelihood[index])
    end
    return logprior_draws, loglikelihood_draws
end

"""
    prior_likelihood_sensitivity(fit; prior_powers = (0.8, 1.0, 1.2),
        likelihood_powers = (0.8, 1.0, 1.2), ndraws = nothing,
        draw_indices = nothing, rng = Random.default_rng(),
        min_effective_sample_size = nothing)
    prior_likelihood_sensitivity(logprior_draws, loglikelihood_draws; kwargs...)

Compute a local prior/likelihood power-scaling sensitivity grid by
self-normalized importance reweighting of posterior draws. For each
`prior_power` and `likelihood_power` cell, the helper estimates the shift in
mean log prior and mean log likelihood relative to the baseline posterior
(`prior_power = likelihood_power = 1`) and reports effective sample size
diagnostics for the reweighted draws.

This helper does not refit models and does not replace predeclared
simulation, exact LOO, or K-fold sensitivity work. Treat cells with
`:low_effective_sample_size` as local-reweighting failures that need refits or
a narrower sensitivity claim.
"""
function prior_likelihood_sensitivity(logprior_draws::AbstractVector,
        loglikelihood_draws::AbstractVector;
        kwargs...)
    return _prior_likelihood_sensitivity(logprior_draws, loglikelihood_draws;
        metadata = _prior_likelihood_sensitivity_metadata(),
        kwargs...)
end

function prior_likelihood_sensitivity(fit::_ModelComparisonFit;
        ndraws::Union{Nothing,Int} = nothing,
        draw_indices = nothing,
        rng::AbstractRNG = Random.default_rng(),
        kwargs...)
    indices = _posterior_draw_indices(fit, ndraws, draw_indices, rng)
    logprior_draws, loglikelihood_draws =
        _prior_likelihood_draw_terms(fit, indices)
    return _prior_likelihood_sensitivity(logprior_draws, loglikelihood_draws;
        metadata = _prior_likelihood_sensitivity_metadata(fit),
        kwargs...)
end

const _DEFAULT_COMPARISON_EVIDENCE_CLASSES = (
    :stan_faithful,
    :r_frequentist,
    :nested_model,
)

function _comparison_evidence_class(class::Symbol)
    class in (:stan, :bridge_stan, :bridgestan, :stan_faithful, :faithful_stan) &&
        return :stan_faithful
    class in (:r, :frequentist, :r_frequentist, :overlapping_r,
        :overlapping_frequentist, :facets, :tam, :sirt, :immer, :mirt) &&
        return :r_frequentist
    class in (:nested, :nested_model, :simpler_nested, :baseline,
        :baseline_model, :mfrm_baseline, :pcm_baseline, :rsm_baseline) &&
        return :nested_model
    return class
end

function _comparison_class_tuple(classes)
    out = Symbol[]
    for class in classes
        class isa Symbol ||
            throw(ArgumentError("comparison evidence classes must be Symbols"))
        canonical = _comparison_evidence_class(class)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_comparison_class_tuple(class::Symbol) = (_comparison_evidence_class(class),)

function _comparison_finite_float(value::Real, name::Symbol; minimum = nothing)
    checked = Float64(value)
    isfinite(checked) ||
        throw(ArgumentError("$name must be finite"))
    if minimum !== nothing
        checked >= Float64(minimum) ||
            throw(ArgumentError("$name must be >= $minimum"))
    end
    return checked
end

function _comparison_pass_if(pass_if::Symbol)
    pass_if in (:within_tolerance, :greater_equal, :less_equal) ||
        throw(ArgumentError(
            "pass_if must be :within_tolerance, :greater_equal, or :less_equal",
        ))
    return pass_if
end

function _comparison_evidence_passed(difference::Float64,
        tolerance::Float64,
        pass_if::Symbol)
    pass_if === :within_tolerance && return abs(difference) <= tolerance
    pass_if === :greater_equal && return difference >= -tolerance
    return difference <= tolerance
end

"""
    comparison_evidence_row(; comparison_class, target_model, comparator,
        metric, estimate, reference, tolerance = 0.0,
        pass_if = :within_tolerance, evidence = :declared_comparison,
        label = nothing, artifact = nothing, source = nothing)

Return one machine-readable comparison-evidence row for a precomputed result
against a faithful Stan/BridgeStan model, an overlapping R/frequentist tool, or a
simpler nested model. `estimate` is the focal Julia/Bayesian value and
`reference` is the comparator value. `pass_if = :within_tolerance` checks
absolute agreement, while `:greater_equal` and `:less_equal` check directional
comparisons such as heldout ELPD gains.

This helper records already computed evidence; it does not run Stan, call R,
fit nested models, or refit heldout folds.
"""
function comparison_evidence_row(;
        comparison_class::Symbol,
        target_model::Symbol,
        comparator::Symbol,
        metric::Symbol,
        estimate::Real,
        reference::Real,
        tolerance::Real = 0.0,
        pass_if::Symbol = :within_tolerance,
        evidence::Symbol = :declared_comparison,
        label = nothing,
        artifact = nothing,
        source = nothing)
    checked_class = _comparison_evidence_class(comparison_class)
    checked_estimate = _comparison_finite_float(estimate, :estimate)
    checked_reference = _comparison_finite_float(reference, :reference)
    checked_tolerance =
        _comparison_finite_float(tolerance, :tolerance; minimum = 0)
    checked_pass_if = _comparison_pass_if(pass_if)
    difference = checked_estimate - checked_reference
    passed = _comparison_evidence_passed(difference, checked_tolerance, checked_pass_if)
    return (;
        schema = "bayesianmgmfrm.comparison_evidence_row.v1",
        object = :comparison_evidence_row,
        label = label === nothing ? comparator : label,
        comparison_class = checked_class,
        target_model,
        comparator,
        metric,
        estimate = checked_estimate,
        reference = checked_reference,
        difference,
        absolute_difference = abs(difference),
        tolerance = checked_tolerance,
        pass_if = checked_pass_if,
        passed,
        status = passed ? :passed : :failed,
        evidence,
        artifact,
        source,
        caveat = :declared_comparison_evidence_not_runner,
    )
end

function _comparison_evidence_summary_row_check(row::NamedTuple)
    required = (
        :comparison_class,
        :target_model,
        :comparator,
        :metric,
        :passed,
        :status,
        :evidence,
    )
    fields = propertynames(row)
    missing_fields = [field for field in required if !(field in fields)]
    isempty(missing_fields) ||
        throw(ArgumentError("comparison evidence row is missing fields: $(join(missing_fields, ", "))"))
    return nothing
end

function _comparison_evidence_class_summary(class::Symbol, rows::AbstractVector)
    class_rows = [row for row in rows
        if _comparison_evidence_class(row.comparison_class) === class]
    if isempty(class_rows)
        return (;
            comparison_class = class,
            present = false,
            status = :missing,
            n_rows = 0,
            n_passed_rows = 0,
            n_failed_rows = 0,
            target_models = (),
            comparators = (),
            metrics = (),
            evidence = (),
            artifacts = (),
        )
    end
    n_passed = count(row -> row.passed === true, class_rows)
    n_failed = length(class_rows) - n_passed
    artifacts = _sensitivity_unique_tuple(
        row.artifact for row in class_rows
        if hasproperty(row, :artifact) && row.artifact !== nothing)
    return (;
        comparison_class = class,
        present = true,
        status = n_failed == 0 ? :passed : :failed,
        n_rows = length(class_rows),
        n_passed_rows = n_passed,
        n_failed_rows = n_failed,
        target_models = _sensitivity_unique_tuple(row.target_model for row in class_rows),
        comparators = _sensitivity_unique_tuple(row.comparator for row in class_rows),
        metrics = _sensitivity_unique_tuple(row.metric for row in class_rows),
        evidence = _sensitivity_unique_tuple(row.evidence for row in class_rows),
        artifacts,
    )
end

"""
    comparison_evidence_summary(rows; required_classes =
        (:stan_faithful, :r_frequentist, :nested_model), view = :full)
    comparison_evidence_summary(row, rows...; required_classes = ...)

Summarize declared comparison-evidence rows and check whether the default
critical-review comparison classes are present and passing: faithful
Stan/BridgeStan models, overlapping R/frequentist tools, and simpler nested
models. The summary is a coverage check over recorded comparison rows; it does
not execute external tools or refit models.
Use `view = :public` for a compact reader-facing summary of the recorded
comparison results. The default `:full` contract is unchanged.
"""
function comparison_evidence_summary(rows::AbstractVector;
        required_classes = _DEFAULT_COMPARISON_EVIDENCE_CLASSES,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    isempty(rows) &&
        throw(ArgumentError("at least one comparison evidence row is required"))
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("comparison evidence summary expects NamedTuple rows"))
        _comparison_evidence_summary_row_check(row)
    end

    checked_required = _comparison_class_tuple(required_classes)
    observed_classes = _sensitivity_unique_tuple(
        _comparison_evidence_class(row.comparison_class) for row in rows)
    observed_set = Set(observed_classes)
    missing_required_classes = Tuple(class for class in checked_required
        if !(class in observed_set))
    class_rows = [_comparison_evidence_class_summary(class, rows)
        for class in checked_required]
    failed_required_classes = Tuple(row.comparison_class for row in class_rows
        if row.status === :failed)
    passed_required_classes = Tuple(row.comparison_class for row in class_rows
        if row.status === :passed)
    n_passed_rows = count(row -> row.passed === true, rows)

    summary = (;
        schema = "bayesianmgmfrm.comparison_evidence_summary.v1",
        object = :comparison_evidence_summary,
        comparison_scope = :stan_r_frequentist_nested_evidence,
        coverage_contract = :required_classes_present_and_passing,
        required_classes = checked_required,
        observed_classes,
        missing_required_classes,
        passed_required_classes,
        failed_required_classes,
        n_rows = length(rows),
        n_passed_rows,
        n_failed_rows = length(rows) - n_passed_rows,
        n_classes = length(observed_classes),
        class_rows = Tuple(class_rows),
        passed = isempty(missing_required_classes) && isempty(failed_required_classes),
        status = isempty(missing_required_classes) && isempty(failed_required_classes) ?
            :complete : :incomplete,
        caveat = :summary_of_declared_comparison_rows_not_external_runner,
        next_gate = :idle_machine_repeated_benchmarks,
    )
    return view === :full ? summary :
        _public_reader_payload(
            summary;
            schema = "bayesianmgmfrm.comparison_evidence_summary_public.v1",
        )
end

function comparison_evidence_summary(row::NamedTuple, rows::NamedTuple...;
        required_classes = _DEFAULT_COMPARISON_EVIDENCE_CLASSES,
        view::Symbol = :full)
    return comparison_evidence_summary(
        [row; collect(rows)];
        required_classes,
        view,
    )
end

const _DEFAULT_BENCHMARK_REQUIRED_ENGINES = (
    :julia,
    :stan,
)

function _benchmark_engine(engine::Symbol)
    engine in (:julia, :advancedhmc, :turing, :native_julia) && return :julia
    engine in (:stan, :cmdstan, :bridge_stan, :bridgestan) && return :stan
    return engine
end

function _benchmark_engine_tuple(engines)
    out = Symbol[]
    for engine in engines
        engine isa Symbol ||
            throw(ArgumentError("benchmark engines must be Symbols"))
        canonical = _benchmark_engine(engine)
        canonical in out || push!(out, canonical)
    end
    return Tuple(out)
end

_benchmark_engine_tuple(engine::Symbol) = (_benchmark_engine(engine),)

function _benchmark_numeric_tuple(values, name::Symbol; minimum::Real = 0)
    out = if values isa Number
        (values,)
    else
        Tuple(values)
    end
    isempty(out) &&
        throw(ArgumentError("$name must contain at least one value"))
    checked = Float64[]
    for value in out
        numeric = Float64(value)
        isfinite(numeric) ||
            throw(ArgumentError("$name values must be finite"))
        numeric >= Float64(minimum) ||
            throw(ArgumentError("$name values must be >= $minimum"))
        push!(checked, numeric)
    end
    return Tuple(checked)
end

function _benchmark_iqr(values::Tuple)
    sorted = sort(collect(Float64, values))
    return _quantile_sorted(sorted, 0.75) - _quantile_sorted(sorted, 0.25)
end

function _benchmark_median(values::Tuple)
    return _quantile_sorted(sort(collect(Float64, values)), 0.5)
end

function _benchmark_optional_threshold(value)
    value === nothing && return missing
    return _benchmark_numeric_tuple(value, :time_to_quality_threshold_seconds)[1]
end

"""
    benchmark_result_row(; benchmark, engine, model, elapsed_seconds,
        effective_sample_sizes = nothing, time_to_quality_seconds = elapsed_seconds,
        time_to_quality_threshold_seconds = nothing, idle_machine = true,
        target_quality = :predeclared_quality_gate, hardware = nothing,
        software = nothing, artifact = nothing)

Summarize one repeated benchmark result row. `elapsed_seconds` must contain one
or more repeated timings and is summarized with median and IQR. When
`effective_sample_sizes` is supplied, the row also reports median/IQR ESS/sec.
`time_to_quality_seconds` records repeated time-to-quality measurements, checked
against `time_to_quality_threshold_seconds` when provided.

This helper records benchmark evidence from an idle-machine run; it does not run
the benchmark itself or enforce hardware isolation.
"""
function benchmark_result_row(;
        benchmark::Symbol,
        engine::Symbol,
        model::Symbol,
        elapsed_seconds,
        effective_sample_sizes = nothing,
        time_to_quality_seconds = elapsed_seconds,
        time_to_quality_threshold_seconds = nothing,
        idle_machine::Bool = true,
        target_quality::Symbol = :predeclared_quality_gate,
        hardware = nothing,
        software = nothing,
        artifact = nothing)
    elapsed = _benchmark_numeric_tuple(elapsed_seconds, :elapsed_seconds; minimum = eps())
    n_repetitions = length(elapsed)
    time_to_quality = _benchmark_numeric_tuple(
        time_to_quality_seconds,
        :time_to_quality_seconds;
        minimum = eps(),
    )
    length(time_to_quality) == n_repetitions ||
        throw(ArgumentError("time_to_quality_seconds must have the same length as elapsed_seconds"))
    threshold = _benchmark_optional_threshold(time_to_quality_threshold_seconds)

    ess_values = effective_sample_sizes === nothing ?
        nothing :
        _benchmark_numeric_tuple(effective_sample_sizes, :effective_sample_sizes)
    if ess_values !== nothing && length(ess_values) != n_repetitions
        throw(ArgumentError("effective_sample_sizes must have the same length as elapsed_seconds"))
    end
    ess_per_second = ess_values === nothing ?
        nothing :
        Tuple(ess_values[index] / elapsed[index] for index in eachindex(elapsed))
    time_to_quality_median = _benchmark_median(time_to_quality)
    threshold_passed = threshold === missing ?
        missing :
        time_to_quality_median <= threshold
    status = !idle_machine ? :not_idle :
        threshold_passed === false ? :failed :
        threshold_passed === true ? :passed :
        :recorded

    return (;
        schema = "bayesianmgmfrm.benchmark_result_row.v1",
        object = :benchmark_result_row,
        benchmark,
        engine = _benchmark_engine(engine),
        reported_engine = engine,
        model,
        n_repetitions,
        idle_machine,
        target_quality,
        elapsed_seconds = elapsed,
        elapsed_median_seconds = _benchmark_median(elapsed),
        elapsed_iqr_seconds = _benchmark_iqr(elapsed),
        effective_sample_sizes = ess_values === nothing ? missing : ess_values,
        ess_per_second = ess_per_second === nothing ? missing : ess_per_second,
        ess_per_second_median =
            ess_per_second === nothing ? missing : _benchmark_median(ess_per_second),
        ess_per_second_iqr =
            ess_per_second === nothing ? missing : _benchmark_iqr(ess_per_second),
        time_to_quality_seconds = time_to_quality,
        time_to_quality_median_seconds = time_to_quality_median,
        time_to_quality_iqr_seconds = _benchmark_iqr(time_to_quality),
        time_to_quality_threshold_seconds = threshold,
        time_to_quality_passed = threshold_passed,
        status,
        hardware,
        software,
        artifact,
        caveat = :local_idle_machine_benchmark_not_portable,
    )
end

function _benchmark_summary_row_check(row::NamedTuple)
    required = (
        :benchmark,
        :engine,
        :model,
        :n_repetitions,
        :idle_machine,
        :elapsed_median_seconds,
        :elapsed_iqr_seconds,
        :ess_per_second_median,
        :time_to_quality_median_seconds,
        :time_to_quality_passed,
        :status,
    )
    fields = propertynames(row)
    missing_fields = [field for field in required if !(field in fields)]
    isempty(missing_fields) ||
        throw(ArgumentError("benchmark row is missing fields: $(join(missing_fields, ", "))"))
    return nothing
end

function _benchmark_median_field(rows::AbstractVector, field::Symbol)
    values = Float64[]
    for row in rows
        value = getproperty(row, field)
        value === missing && continue
        push!(values, Float64(value))
    end
    isempty(values) && return missing
    return _benchmark_median(Tuple(values))
end

function _benchmark_engine_rows(rows::AbstractVector, engine::Symbol)
    return [row for row in rows if _benchmark_engine(row.engine) === engine]
end

function _benchmark_ratio_row(benchmark, rows::AbstractVector, required_engines::Tuple,
        min_repetitions::Int)
    observed_engines = _sensitivity_unique_tuple(_benchmark_engine(row.engine) for row in rows)
    missing_required_engines = Tuple(engine for engine in required_engines
        if !(engine in observed_engines))
    julia_rows = _benchmark_engine_rows(rows, :julia)
    stan_rows = _benchmark_engine_rows(rows, :stan)
    julia_elapsed = isempty(julia_rows) ?
        missing :
        _benchmark_median_field(julia_rows, :elapsed_median_seconds)
    stan_elapsed = isempty(stan_rows) ?
        missing :
        _benchmark_median_field(stan_rows, :elapsed_median_seconds)
    julia_ess = isempty(julia_rows) ?
        missing :
        _benchmark_median_field(julia_rows, :ess_per_second_median)
    stan_ess = isempty(stan_rows) ?
        missing :
        _benchmark_median_field(stan_rows, :ess_per_second_median)
    stan_to_julia_elapsed_ratio =
        julia_elapsed === missing || stan_elapsed === missing ?
        missing :
        stan_elapsed / julia_elapsed
    julia_to_stan_ess_per_second_ratio =
        julia_ess === missing || stan_ess === missing || iszero(stan_ess) ?
        missing :
        julia_ess / stan_ess
    rows_with_few_repetitions =
        count(row -> Int(row.n_repetitions) < min_repetitions, rows)
    failed_time_to_quality =
        count(row -> row.time_to_quality_passed === false, rows)
    all_idle = all(row -> row.idle_machine === true, rows)
    status = isempty(missing_required_engines) &&
        rows_with_few_repetitions == 0 &&
        failed_time_to_quality == 0 &&
        all_idle ? :complete : :incomplete

    return (;
        benchmark,
        status,
        n_rows = length(rows),
        observed_engines,
        missing_required_engines,
        rows_with_few_repetitions,
        min_repetitions,
        all_idle,
        failed_time_to_quality,
        julia_elapsed_median_seconds = julia_elapsed,
        stan_elapsed_median_seconds = stan_elapsed,
        stan_to_julia_elapsed_ratio,
        julia_ess_per_second_median = julia_ess,
        stan_ess_per_second_median = stan_ess,
        julia_to_stan_ess_per_second_ratio,
    )
end

"""
    benchmark_summary(rows; required_engines = (:julia, :stan),
        min_repetitions = 3, view = :full)
    benchmark_summary(row, rows...; required_engines = ..., min_repetitions = 3)

Summarize repeated idle-machine benchmark rows. The summary checks required
engine coverage, minimum repetitions, idle-machine flags, time-to-quality
threshold failures, and per-benchmark Stan/Julia elapsed-time and ESS/sec ratios.
It aggregates recorded benchmark rows; it does not run benchmarks.
`view = :public` produces a compact reader-facing projection;
`view = :full` preserves the complete existing payload.
"""
function benchmark_summary(rows::AbstractVector;
        required_engines = _DEFAULT_BENCHMARK_REQUIRED_ENGINES,
        min_repetitions::Integer = 3,
        view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    isempty(rows) &&
        throw(ArgumentError("at least one benchmark row is required"))
    checked_min_repetitions =
        _simulation_positive_integer(min_repetitions, :min_repetitions)
    for row in rows
        row isa NamedTuple ||
            throw(ArgumentError("benchmark summary expects NamedTuple rows"))
        _benchmark_summary_row_check(row)
    end
    checked_required = _benchmark_engine_tuple(required_engines)
    observed_engines = _sensitivity_unique_tuple(_benchmark_engine(row.engine) for row in rows)
    missing_required_engines = Tuple(engine for engine in checked_required
        if !(engine in observed_engines))
    benchmarks = _sensitivity_unique_tuple(row.benchmark for row in rows)
    benchmark_rows = NamedTuple[]
    for benchmark in benchmarks
        benchmark_specific = [row for row in rows if row.benchmark === benchmark]
        push!(benchmark_rows, _benchmark_ratio_row(
            benchmark,
            benchmark_specific,
            checked_required,
            checked_min_repetitions,
        ))
    end
    incomplete_benchmarks = Tuple(row.benchmark for row in benchmark_rows
        if row.status !== :complete)
    rows_with_few_repetitions =
        count(row -> Int(row.n_repetitions) < checked_min_repetitions, rows)
    failed_time_to_quality =
        count(row -> row.time_to_quality_passed === false, rows)
    all_idle = all(row -> row.idle_machine === true, rows)
    passed = isempty(missing_required_engines) &&
        isempty(incomplete_benchmarks) &&
        rows_with_few_repetitions == 0 &&
        failed_time_to_quality == 0 &&
        all_idle

    summary = (;
        schema = "bayesianmgmfrm.benchmark_summary.v1",
        object = :benchmark_summary,
        benchmark_scope = :idle_machine_repeated_benchmarks,
        coverage_contract = :required_engines_repeated_idle_and_quality_checked,
        required_engines = checked_required,
        observed_engines,
        missing_required_engines,
        n_rows = length(rows),
        n_benchmarks = length(benchmarks),
        min_repetitions = checked_min_repetitions,
        rows_with_few_repetitions,
        all_idle,
        failed_time_to_quality,
        incomplete_benchmarks,
        benchmark_rows = Tuple(benchmark_rows),
        passed,
        status = passed ? :complete : :incomplete,
        caveat = :local_benchmark_summary_not_portable_performance_claim,
        next_gate = :external_release_decision,
    )
    return view === :full ? summary :
        _public_reader_payload(
            summary;
            schema = "bayesianmgmfrm.benchmark_summary_public.v1",
        )
end

function benchmark_summary(row::NamedTuple, rows::NamedTuple...;
        required_engines = _DEFAULT_BENCHMARK_REQUIRED_ENGINES,
        min_repetitions::Integer = 3,
        view::Symbol = :full)
    return benchmark_summary(
        [row; collect(rows)];
        required_engines,
        min_repetitions,
        view,
    )
end
