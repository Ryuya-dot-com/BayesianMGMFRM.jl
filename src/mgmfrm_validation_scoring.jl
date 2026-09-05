function _mgmfrm_probability_tolerance(value::Real)
    checked = Float64(value)
    isfinite(checked) && checked >= 0 || throw(ArgumentError(
        "probability_tolerance must be finite and non-negative",
    ))
    return checked
end

function _mgmfrm_check_probability_rows(values, name::AbstractString,
        tolerance::Float64; log_probabilities::Bool = false)
    if log_probabilities
        all(value -> Float64(value) <= 0, values) || throw(ArgumentError(
            "$name must contain log probabilities in [-Inf, 0]"))
    else
        all(value -> isfinite(Float64(value)) && 0 <= value <= 1, values) ||
            throw(ArgumentError("$name must contain finite probabilities in [0, 1]"))
    end
    mass_error(row) = log_probabilities ?
        abs(expm1(_logsumexp(Float64.(row)))) : abs(sum(row) - 1)
    if ndims(values) == 2
        for observation in axes(values, 1)
            mass_error(@view values[observation, :]) <= tolerance ||
                throw(ArgumentError("each $name observation must have total probability mass one"))
        end
    elseif ndims(values) == 3
        for draw in axes(values, 1), observation in axes(values, 2)
            mass_error(@view values[draw, observation, :]) <= tolerance ||
                throw(ArgumentError(
                    "each $name draw-observation row must have total probability mass one",
                ))
        end
    else
        throw(ArgumentError("$name must be a 2D or 3D probability array"))
    end
    return nothing
end

function _mgmfrm_mean_predicted_probabilities(predicted,
        tolerance::Float64; log_probabilities::Bool = false)
    ndims(predicted) in (2, 3) || throw(ArgumentError(
        "predicted_probabilities must be a 2D or 3D probability array",
    ))
    _mgmfrm_check_probability_rows(
        predicted,
        "predicted_probabilities",
        tolerance; log_probabilities,
    )
    if ndims(predicted) == 2
        return Float64.(predicted), 1
    end
    size(predicted, 1) >= 1 || throw(ArgumentError(
        "predicted_probabilities must contain at least one draw",
    ))
    means = Matrix{Float64}(undef, size(predicted, 2), size(predicted, 3))
    for observation in axes(predicted, 2), category in axes(predicted, 3)
        if log_probabilities
            column = Float64.(@view predicted[:, observation, category])
            # Preserve a category with zero support in every draw. Other
            # columns may mix finite logs and -Inf; do not drop zero-mass draws.
            means[observation, category] = all(==(-Inf), column) ? -Inf :
                _logsumexp(column) - log(length(column))
            continue
        end
        total = 0.0
        for draw in axes(predicted, 1)
            total += Float64(predicted[draw, observation, category])
        end
        means[observation, category] = total / size(predicted, 1)
    end
    return means, size(predicted, 1)
end

function _mgmfrm_category_values(category_levels, n_categories::Int)
    levels = category_levels === nothing ? collect(0:(n_categories - 1)) :
        collect(category_levels)
    length(levels) == n_categories || throw(ArgumentError(
        "category_levels has $(length(levels)) values; expected $n_categories",
    ))
    all(level -> level isa Real && isfinite(Float64(level)), levels) ||
        throw(ArgumentError("category_levels must contain finite numbers"))
    return Float64.(levels)
end

function _mgmfrm_truth_log_score_regret(truth_row, predicted_row;
        log_probabilities::Bool = false)
    regret = 0.0
    for category in eachindex(truth_row)
        truth = Float64(truth_row[category])
        truth == (log_probabilities ? -Inf : 0.0) && continue
        predicted = Float64(predicted_row[category])
        predicted == (log_probabilities ? -Inf : 0.0) && return Inf
        if log_probabilities
            difference = truth - predicted
            # exp(truth) can underflow even when its product with the log
            # ratio is representable. Keep that product in the log domain.
            iszero(difference) ||
                (regret += copysign(exp(truth + log(abs(difference))), difference))
        else
            # Forming the ratio first can overflow for positive subnormal support.
            regret += truth * (log(truth) - log(predicted))
        end
    end
    return regret
end

"""
    mgmfrm_predictive_recovery_score(
        predicted_probabilities,
        truth_probabilities;
        category_levels = nothing,
        probability_tolerance = 1e-8,
        log_probabilities = false,
    )

Score known-truth predictive recovery without applying a scientific pass/fail
threshold. `truth_probabilities` is an observations-by-categories matrix.
`predicted_probabilities` may have the same shape or may add a leading posterior
draw dimension; posterior draws are averaged before scoring.

With `log_probabilities = true`, **both** arrays contain normalized natural-log
probabilities, not unnormalized logits. `-Inf` denotes exact zero support;
NaN, positive entries, and rows with no mass are rejected. Draws are averaged
in probability space using log-sum-exp, and KL is evaluated without first
exponentiating its inputs. The tolerance still measures deviation of row mass
from one. Category-probability and expected-score errors use Float64
probabilities and may round vanishing contributions to zero.

The result reports category-probability MAE/RMSE, expected-score MAE/RMSE, and
mean proper log-score regret (the mean KL divergence from truth to prediction),
plus observation-level rows. Exact predicted zeros where truth is positive are
retained as infinite log-score regret rather than silently clamped. This is a
descriptive Stage-A scorer, not validation evidence by itself.
"""
function mgmfrm_predictive_recovery_score(
        predicted_probabilities,
        truth_probabilities;
        category_levels = nothing,
        probability_tolerance::Real = 1e-8,
        log_probabilities::Bool = false)
    tolerance = _mgmfrm_probability_tolerance(probability_tolerance)
    ndims(truth_probabilities) == 2 || throw(ArgumentError(
        "truth_probabilities must be an observations-by-categories matrix",
    ))
    _mgmfrm_check_probability_rows(
        truth_probabilities,
        "truth_probabilities",
        tolerance; log_probabilities,
    )
    mean_predictions, n_prediction_draws = _mgmfrm_mean_predicted_probabilities(
        predicted_probabilities, tolerance; log_probabilities)
    predicted = log_probabilities ? exp.(mean_predictions) : mean_predictions
    truth = log_probabilities ? exp.(Float64.(truth_probabilities)) : truth_probabilities
    size(predicted) == size(truth_probabilities) || throw(ArgumentError(
        "predicted and truth probability dimensions must match after draw averaging",
    ))
    n_observations, n_categories = size(predicted)
    n_observations >= 1 || throw(ArgumentError(
        "probability arrays must contain at least one observation",
    ))
    n_categories >= 2 || throw(ArgumentError(
        "probability arrays must contain at least two categories",
    ))
    levels = _mgmfrm_category_values(category_levels, n_categories)

    rows = NamedTuple[]
    total_abs_probability_error = 0.0
    total_squared_probability_error = 0.0
    maximum_abs_probability_error = 0.0
    total_abs_expected_score_error = 0.0
    total_squared_expected_score_error = 0.0
    maximum_abs_expected_score_error = 0.0
    total_log_score_regret = 0.0
    finite_log_score_regret = true

    for observation in 1:n_observations
        truth_row = @view truth[observation, :]
        predicted_row = @view predicted[observation, :]
        probability_abs_sum = 0.0
        probability_squared_sum = 0.0
        observation_max_abs = 0.0
        truth_expected_score = 0.0
        predicted_expected_score = 0.0
        for category in 1:n_categories
            difference = Float64(predicted_row[category]) -
                Float64(truth_row[category])
            absolute_difference = abs(difference)
            probability_abs_sum += absolute_difference
            probability_squared_sum += difference * difference
            observation_max_abs = max(observation_max_abs, absolute_difference)
            truth_expected_score += levels[category] * Float64(truth_row[category])
            predicted_expected_score +=
                levels[category] * Float64(predicted_row[category])
        end
        expected_score_error = predicted_expected_score - truth_expected_score
        log_score_regret =
            _mgmfrm_truth_log_score_regret(@view(truth_probabilities[observation, :]),
                @view(mean_predictions[observation, :]); log_probabilities)
        finite_log_score_regret &= isfinite(log_score_regret)
        total_abs_probability_error += probability_abs_sum
        total_squared_probability_error += probability_squared_sum
        maximum_abs_probability_error =
            max(maximum_abs_probability_error, observation_max_abs)
        total_abs_expected_score_error += abs(expected_score_error)
        total_squared_expected_score_error += expected_score_error^2
        maximum_abs_expected_score_error =
            max(maximum_abs_expected_score_error, abs(expected_score_error))
        if log_probabilities
            # Online mean avoids overflowing a sum or underflowing each
            # contribution by dividing it before summation. Retain true Inf.
            total_log_score_regret = isinf(total_log_score_regret) || isinf(log_score_regret) ?
                Inf : total_log_score_regret + (log_score_regret - total_log_score_regret) / observation
        else
            total_log_score_regret += log_score_regret
        end
        push!(rows, (;
            observation,
            mean_absolute_category_probability_error =
                probability_abs_sum / n_categories,
            root_mean_squared_category_probability_error =
                sqrt(probability_squared_sum / n_categories),
            maximum_absolute_category_probability_error =
                observation_max_abs,
            truth_expected_score,
            predicted_expected_score,
            expected_score_error,
            absolute_expected_score_error = abs(expected_score_error),
            log_score_regret,
        ))
    end

    probability_denominator = n_observations * n_categories
    summary = (;
        n_observations,
        n_categories,
        n_prediction_draws,
        mean_absolute_category_probability_error =
            total_abs_probability_error / probability_denominator,
        root_mean_squared_category_probability_error =
            sqrt(total_squared_probability_error / probability_denominator),
        maximum_absolute_category_probability_error =
            maximum_abs_probability_error,
        mean_absolute_expected_score_error =
            total_abs_expected_score_error / n_observations,
        root_mean_squared_expected_score_error =
            sqrt(total_squared_expected_score_error / n_observations),
        maximum_absolute_expected_score_error =
            maximum_abs_expected_score_error,
        mean_log_score_regret = log_probabilities ? total_log_score_regret :
            total_log_score_regret / n_observations,
        finite_log_score_regret,
    )
    return (;
        schema = "bayesianmgmfrm.mgmfrm_predictive_recovery_score.v1",
        object = :mgmfrm_predictive_recovery_score,
        status = finite_log_score_regret ? :scored : :nonfinite_log_score_regret,
        thresholds_applied = false,
        validation_claim_allowed = false,
        category_levels = levels,
        summary,
        rows = Tuple(rows),
    )
end

# M1 preparation: align one labelled draw (or truth) before array scoring.
# Repeated occasions need explicit event IDs; this panel permits one event
# per person/rater/item tuple and rejects duplicates instead of pooling them.
function _mfrm_anchor_log_probability_matrix(records::AbstractVector,
        events::AbstractVector, category_levels; probability_tolerance::Real = 1e-8)
    tolerance = _mgmfrm_probability_tolerance(probability_tolerance)
    levels = collect(category_levels)
    !isempty(events) && length(levels) >= 2 || throw(ArgumentError(
        "labelled log probabilities need events and at least two categories"))
    all(level -> level isa Integer && !(level isa Bool), levels) &&
        length(unique(levels)) == length(levels) || throw(ArgumentError(
            "category labels must be distinct integers"))
    function event_key(row)
        labels = Tuple(_report_lookup(row, field, nothing)
            for field in (:person, :rater, :item))
        all(label -> label isa AbstractString && !isempty(label), labels) ||
            throw(ArgumentError("event labels must be nonempty strings"))
        return labels
    end
    keys = event_key.(events)
    length(unique(keys)) == length(keys) || throw(ArgumentError(
        "event person/rater/item tuples must be unique"))
    divrem(length(records), length(levels)) == (length(events), 0) ||
        throw(ArgumentError("records must cover every event/category exactly once"))
    event_index = Dict(key => index for (index, key) in pairs(keys))
    category_index = Dict(level => index for (index, level) in pairs(levels))
    logs = fill(NaN, length(events), length(levels))
    for record in records
        row = get(event_index, event_key(record), 0)
        category = _report_lookup(record, :category, nothing)
        category isa Integer && !(category isa Bool) || throw(ArgumentError(
            "record category labels must be integers"))
        column = get(category_index, category, 0)
        row > 0 && column > 0 || throw(ArgumentError(
            "record event/category is outside the declared panel"))
        isnan(logs[row, column]) || throw(ArgumentError(
            "duplicate event/category record"))
        value = _report_lookup(record, :log_probability, nothing)
        # Decode only the numeric field's explicit JSON zero-support token;
        # strings such as "null" or "-Inf" in facet labels stay literal labels.
        value isa AbstractString && value == "-Inf" && (value = -Inf)
        value isa Real && !(value isa Bool) || throw(ArgumentError(
            "log_probability must be numeric or the string -Inf"))
        converted = Float64(value)
        converted <= 0 && (isfinite(converted) || value == -Inf) ||
            throw(ArgumentError("log_probability must be representable in [-Inf, 0]"))
        logs[row, column] = converted
    end
    _mgmfrm_check_probability_rows(logs, "labelled log probabilities", tolerance;
        log_probabilities = true)
    return logs
end

function _mgmfrm_decision_cutpoints(cutpoints)
    values = Float64.(collect(cutpoints))
    all(isfinite, values) ||
        throw(ArgumentError("cutpoints must be finite"))
    (length(values) <= 1 ||
        all(index -> values[index] < values[index + 1],
            1:(length(values) - 1))) ||
        throw(ArgumentError("cutpoints must be strictly increasing"))
    return values
end

_mgmfrm_decision_class(value::Real, cutpoints::AbstractVector{Float64}) =
    searchsortedlast(cutpoints, Float64(value)) + 1

function _mgmfrm_pairwise_order_disagreement(reference, candidate)
    n_comparable = 0
    n_disagreements = 0
    for first in 1:(length(reference) - 1), second in (first + 1):length(reference)
        reference_difference = reference[first] - reference[second]
        reference_difference == 0 && continue
        n_comparable += 1
        candidate_difference = candidate[first] - candidate[second]
        if candidate_difference == 0 ||
                signbit(candidate_difference) != signbit(reference_difference)
            n_disagreements += 1
        end
    end
    rate = n_comparable == 0 ? missing : n_disagreements / n_comparable
    return (; n_comparable, n_disagreements, rate)
end

function _mgmfrm_decision_labels(labels, n::Int, prefix::AbstractString)
    labels === nothing &&
        return Tuple(Symbol(prefix * string(index)) for index in 1:n)
    values = Tuple(labels)
    length(values) == n || throw(ArgumentError(
        "$(prefix)labels has $(length(values)) values; expected $n",
    ))
    return values
end

function _mgmfrm_maximum_present(values)
    present = Float64[value for value in values if !ismissing(value)]
    return isempty(present) ? missing : maximum(present)
end

"""
    mgmfrm_decision_stability_score(
        reference,
        candidates;
        cutpoints = (),
        condition_labels = nothing,
        unit_labels = nothing,
        reference_role = :known_truth,
    )

Compare rows of candidate point estimates with a reference vector. Each row
reports absolute shift, pairwise ordering disagreement, and—when the caller
supplies substantively meaningful ordered `cutpoints`—classification flip
rates. Reference ties are excluded from pairwise ordering denominators;
candidate ties against a non-tied reference pair count as disagreements.

No default practical cutpoint or pass/fail threshold is assumed. The function
is intended to score prior, backend, Q-specification, or replication
conditions after those conditions and cutpoints have been frozen externally.
"""
function mgmfrm_decision_stability_score(
        reference::AbstractVector,
        candidates::AbstractMatrix;
        cutpoints = (),
        condition_labels = nothing,
        unit_labels = nothing,
        reference_role::Symbol = :known_truth)
    n_conditions, n_units = size(candidates)
    n_conditions >= 1 || throw(ArgumentError(
        "candidates must contain at least one condition row",
    ))
    n_units >= 1 || throw(ArgumentError(
        "reference and candidates must contain at least one unit",
    ))
    length(reference) == n_units || throw(ArgumentError(
        "reference has $(length(reference)) values; expected $n_units",
    ))
    all(value -> isfinite(Float64(value)), reference) ||
        throw(ArgumentError("reference must contain finite values"))
    all(value -> isfinite(Float64(value)), candidates) ||
        throw(ArgumentError("candidates must contain finite values"))
    checked_cutpoints = _mgmfrm_decision_cutpoints(cutpoints)
    checked_condition_labels =
        _mgmfrm_decision_labels(condition_labels, n_conditions, "condition_")
    checked_unit_labels =
        _mgmfrm_decision_labels(unit_labels, n_units, "unit_")
    classification_evaluated = !isempty(checked_cutpoints)
    reference_values = Float64.(reference)
    reference_classes = classification_evaluated ?
        [_mgmfrm_decision_class(value, checked_cutpoints)
            for value in reference_values] : Int[]

    rows = NamedTuple[]
    for condition in 1:n_conditions
        candidate = Float64.(@view candidates[condition, :])
        differences = candidate .- reference_values
        ordering =
            _mgmfrm_pairwise_order_disagreement(reference_values, candidate)
        candidate_classes = classification_evaluated ?
            [_mgmfrm_decision_class(value, checked_cutpoints)
                for value in candidate] : Int[]
        n_classification_flips = classification_evaluated ?
            count(index -> candidate_classes[index] != reference_classes[index],
                eachindex(reference_classes)) : missing
        classification_flip_rate = classification_evaluated ?
            n_classification_flips / n_units : missing
        push!(rows, (;
            condition_index = condition,
            condition = checked_condition_labels[condition],
            n_units,
            mean_absolute_shift = sum(abs, differences) / n_units,
            root_mean_squared_shift = sqrt(sum(abs2, differences) / n_units),
            maximum_absolute_shift = maximum(abs, differences),
            n_comparable_order_pairs = ordering.n_comparable,
            n_pairwise_order_disagreements = ordering.n_disagreements,
            pairwise_order_disagreement_rate = ordering.rate,
            classification_evaluated,
            n_classification_flips,
            classification_flip_rate,
        ))
    end

    summary = (;
        n_conditions,
        n_units,
        reference_role,
        classification_evaluated,
        n_cutpoints = length(checked_cutpoints),
        maximum_mean_absolute_shift =
            maximum(row.mean_absolute_shift for row in rows),
        maximum_root_mean_squared_shift =
            maximum(row.root_mean_squared_shift for row in rows),
        maximum_absolute_shift =
            maximum(row.maximum_absolute_shift for row in rows),
        maximum_pairwise_order_disagreement_rate = _mgmfrm_maximum_present(
            row.pairwise_order_disagreement_rate for row in rows),
        maximum_classification_flip_rate = _mgmfrm_maximum_present(
            row.classification_flip_rate for row in rows),
    )
    return (;
        schema = "bayesianmgmfrm.mgmfrm_decision_stability_score.v1",
        object = :mgmfrm_decision_stability_score,
        status = :scored_descriptive,
        thresholds_applied = false,
        validation_claim_allowed = false,
        reference_role,
        cutpoints = Tuple(checked_cutpoints),
        condition_labels = checked_condition_labels,
        unit_labels = checked_unit_labels,
        summary,
        rows = Tuple(rows),
    )
end
