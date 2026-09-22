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

# M1 preparation, equal-event score only. Rows must retain contiguous chain
# blocks. This is a first-order delta-method candidate, not a precision gate.
# ponytail: reuse the scalar MCSE path; curvature/near-degeneracy needs separate
# review before promotion, not a second covariance-estimation framework here.
function _mfrm_anchor_log_score_delta_mcse(
        logdraws::AbstractArray{<:Real,3}, logtruth::AbstractMatrix{<:Real};
        chains::Integer)
    chains isa Bool && throw(ArgumentError("chains must be an integer count"))
    chains >= 1 && size(logdraws, 1) % chains == 0 || throw(ArgumentError(
        "draws must form equally sized contiguous chain blocks"))
    scored = mgmfrm_predictive_recovery_score(logdraws, logtruth;
        log_probabilities = true)
    base = (; estimate = scored.summary.mean_log_score_regret,
        n_chains = Int(chains), draws_per_chain = size(logdraws, 1) ÷ chains,
        convergence_review_required = true, curvature_review_required = true,
        precision_threshold_applied = false, validation_claim_allowed = false)
    scored.status === :scored || return merge(base, (;
        status = :nonfinite_log_score, influence = nothing, mcse = missing))
    logmean, ndraws = _mgmfrm_mean_predicted_probabilities(logdraws, 1e-8;
        log_probabilities = true)
    influence = zeros(ndraws)
    scale = 0.0
    for s in 1:ndraws
        magnitude = 0.0
        for n in axes(logtruth, 1), k in axes(logtruth, 2)
            q = Float64(logtruth[n, k])
            q == -Inf && continue
            # -q * (p_s / mean(p) - 1), retaining finite log support and
            # small differences without forming q / mean(p) or exp(log p).
            difference = expm1(Float64(logdraws[s, n, k]) - logmean[n, k])
            iszero(difference) && continue
            term = -copysign(exp(q + log(abs(difference))), difference)
            influence[s] += term
            magnitude += abs(term)
        end
        influence[s] /= size(logtruth, 1)
        scale = max(scale, magnitude / size(logtruth, 1))
    end
    all(isfinite, influence) && isfinite(scale) || return merge(base, (;
        status = :nonfinite_linearization, influence, mcse = missing))
    # Numerical cancellation, including q == mean(p), is NOT zero MC error.
    # Conversely, a nonzero sample gradient cannot rule out population degeneracy.
    maximum(abs, influence) <= 64eps(Float64) * scale && return merge(base, (;
        status = :first_order_degenerate, influence, mcse = missing))
    row = only(posterior_mcse(reshape(influence, :, 1);
        chains, parameter_names = ["log_score_linearization"], probabilities = ()))
    # Only the mean is the delta-method target. The aggregate row status can
    # be unavailable solely because the unrelated SD-MCSE is unavailable.
    usable = !ismissing(row.mean_mcse) && isfinite(row.mean_mcse) && row.mean_mcse > 0
    status = usable ? :first_order_candidate :
        row.mcse_status === :available ? :mcse_unavailable : row.mcse_status
    return merge(base, (; status,
        influence, mcse = usable ? row.mean_mcse : missing))
end

# M1 preparation: validate identities before joining the complete planned
# denominator. This does not validate payloads or authorize retry/fit settings.
function _mfrm_anchor_primary_attempts(plan::AbstractVector, attempts::AbstractVector)
    function identity_key(row)
        labels = Tuple(_report_lookup(row, field, nothing)
            for field in (:dataset_id, :heldout_id, :method))
        all(label -> label isa AbstractString && !isempty(label), labels) ||
            throw(ArgumentError("dataset_id, heldout_id, and method must be nonempty strings"))
        return labels
    end
    keys = identity_key.(plan)
    length(unique(keys)) == length(keys) || throw(ArgumentError(
        "duplicate planned dataset/heldout/method identity"))
    index = Dict(key => n for (n, key) in pairs(keys))
    primary = Any[nothing for _ in keys]
    seen = Set{Tuple}()
    for row in attempts
        key = identity_key(row)
        n = get(index, key, 0)
        n > 0 || throw(ArgumentError("attempt identity is outside the declared plan"))
        attempt = _report_lookup(row, :attempt, nothing)
        attempt isa Integer && !(attempt isa Bool) && attempt > 0 ||
            throw(ArgumentError("attempt must be a positive integer"))
        id = (key, attempt)
        id in seen && throw(ArgumentError("duplicate dataset/heldout/method/attempt identity"))
        push!(seen, id)
        attempt == 1 && (primary[n] = row)
    end
    all(id -> (id[1], 1) in seen, seen) || throw(ArgumentError(
        "a retry requires its retained primary attempt"))
    return primary
end

function _mfrm_anchor_event_key(row)
    labels = Tuple(_report_lookup(row, field, nothing)
        for field in (:person, :rater, :item))
    all(label -> label isa AbstractString && !isempty(label), labels) ||
        throw(ArgumentError("event labels must be nonempty strings"))
    return labels
end

# M1 preparation only: the caller supplies bytes and a separately trusted
# reference. Hash exactly the bytes parsed, never a second read of a path.
# This binds content, not authority, and is not an untrusted JSON importer.
function _mfrm_anchor_response_data(bytes::AbstractVector{UInt8}, reference)
    id = _report_lookup(reference, :dataset_id, nothing)
    role = _report_lookup(reference, :role, nothing)
    digest = _report_lookup(reference, :sha256, nothing)
    id isa AbstractString && !isempty(id) || throw(ArgumentError(
        "response reference dataset_id must be a nonempty string"))
    role isa AbstractString && role in ("train", "heldout") || throw(ArgumentError(
        "response reference role must be train or heldout"))
    digest isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", digest) ||
        throw(ArgumentError("response reference sha256 must be lowercase 64-hex"))
    bytes2hex(sha256(bytes)) == digest || throw(ArgumentError(
        "response bytes do not match the trusted reference"))
    record = JSON3.read(bytes)
    record isa AbstractDict && Set(keys(record)) ==
        Set((:dataset_id, :role, :category_levels, :rows)) || throw(ArgumentError(
            "response record must contain dataset_id, role, category_levels, and rows only"))
    record.dataset_id == id && record.role == role || throw(ArgumentError(
        "response dataset_id/role does not match the trusted reference"))
    levels, rows = record.category_levels, record.rows
    levels isa AbstractVector && rows isa AbstractVector && !isempty(rows) ||
        throw(ArgumentError("response categories/rows must be arrays with nonempty rows"))
    all(row -> row isa AbstractDict && Set(keys(row)) ==
        Set((:person, :rater, :item, :score)), rows) || throw(ArgumentError(
            "response rows must contain person, rater, item, and score only"))
    events = _mfrm_anchor_event_key.(rows)
    length(unique(events)) == length(events) || throw(ArgumentError(
        "response person/rater/item tuples must be unique"))
    # Untyped JSON3 can round decimal tokens to integers. After checking all
    # required fields, parse numerical fields directly as Int, not via Float64.
    row_type = NamedTuple{(:person, :rater, :item, :score), Tuple{String, String, String, Int}}
    record_type = NamedTuple{(:dataset_id, :role, :category_levels, :rows),
        Tuple{String, String, Vector{Int}, Vector{row_type}}}
    typed = JSON3.read(bytes, record_type)
    levels = typed.category_levels
    scores = [row.score for row in typed.rows]
    length(levels) >= 2 && all(i -> levels[i] > levels[i - 1] &&
        levels[i] - levels[i - 1] == 1, 2:length(levels)) || throw(ArgumentError(
            "response categories must be consecutive increasing integers"))
    return FacetData((; person = first.(events), rater = getindex.(events, 2),
        item = last.(events), score = scores); person = :person, rater = :rater,
        item = :item, score = :score, category_levels = levels)
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
    keys = _mfrm_anchor_event_key.(events)
    length(unique(keys)) == length(keys) || throw(ArgumentError(
        "event person/rater/item tuples must be unique"))
    divrem(length(records), length(levels)) == (length(events), 0) ||
        throw(ArgumentError("records must cover every event/category exactly once"))
    event_index = Dict(key => index for (index, key) in pairs(keys))
    category_index = Dict(level => index for (index, level) in pairs(levels))
    logs = fill(NaN, length(events), length(levels))
    for record in records
        row = get(event_index, _mfrm_anchor_event_key(record), 0)
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

# Explicit fields, not MFRMFit's abbreviated display or a stale cached signature.
function _mfrm_anchor_fit_hash(fit)
    # This file loads before the fit types; check at the call boundary.
    fit isa MFRMFit || throw(ArgumentError("anchor scoring requires an MFRMFit"))
    size(fit.draws, 1) > 0 && size(fit.draws, 2) == length(fit.design.parameter_names) ||
        throw(ArgumentError("anchor scoring requires nonempty draws in design parameter order"))
    return _cache_hash((; metadata = fit_metadata(fit), draws = fit.draws,
        log_posterior = fit.log_posterior, chain_ids = fit.chain_ids,
        iterations = fit.iterations, sampler_stats = fit.sampler_stats))
end

# A retained cell declaration is an input, not proof of model specification or
# likelihood identification. Only within-facet additive gauge shifts are checked.
function _mfrm_anchor_cell_targets(design, requests, cell, truth_sha256)
    cell === nothing && return nothing
    fields = (:cell_id, :design_id, :log_truth_sha256, :model_status,
        :identification_status, :anchor_atol, :truth, :targets)
    cell isa NamedTuple && Set(keys(cell)) == Set(fields) || throw(ArgumentError(
        "cell must supply its identity, truth, applicability declarations, and target roster"))
    cell.cell_id isa AbstractString && !isempty(cell.cell_id) ||
        throw(ArgumentError("cell_id must be a nonempty string"))
    cell.design_id isa AbstractString && cell.log_truth_sha256 isa AbstractString &&
        cell.design_id == design_identity(design).value && cell.log_truth_sha256 == truth_sha256 ||
        throw(ArgumentError("cell design/log-truth references do not match the scored inputs"))
    cell.model_status isa Symbol && cell.model_status in (:declared_correct, :misspecified, :unresolved) &&
        cell.identification_status isa Symbol &&
        cell.identification_status in (:declared_identified, :unidentified, :unresolved) ||
        throw(ArgumentError("unsupported cell model/identification declaration"))
    tolerance = cell.anchor_atol
    tolerance isa Real && !(tolerance isa Bool) && isfinite(Float64(tolerance)) && tolerance >= 0 ||
        throw(ArgumentError("anchor_atol must be explicitly finite and nonnegative"))
    cell.truth isa NamedTuple && Set(keys(cell.truth)) == Set((:person, :rater, :item)) ||
        throw(ArgumentError("cell truth must contain person, rater, and item labelled records"))
    truth = Dict{Symbol,Dict{String,Float64}}()
    for block in (:person, :rater, :item)
        supplied = getproperty(cell.truth, block)
        levels = getproperty(design.spec.data, Symbol(block, :_levels))
        supplied isa AbstractVector && all(row -> row isa NamedTuple &&
            Set(keys(row)) == Set((:level, :value)) && row.level isa AbstractString, supplied) &&
            length(supplied) == length(levels) && Set(row.level for row in supplied) == Set(levels) ||
            throw(ArgumentError("cell truth labels must exactly match the design's $block levels"))
        all(row -> row.value isa Real && !(row.value isa Bool) && isfinite(Float64(row.value)), supplied) ||
            throw(ArgumentError("cell truth values must be finite real numbers"))
        truth[block] = Dict(String(row.level) => Float64(row.value) for row in supplied)
    end
    shifts = NamedTuple[]
    for block in (:rater, :item)
        levels = getproperty(design.spec.data, Symbol(block, :_levels))
        offsets = [_stable_facet_fixed_value(design, block, n) - truth[block][label]
            for (n, label) in pairs(levels) if ismissing(_stable_facet_parameter_index(design, block, n))]
        !isempty(offsets) && all(isfinite, offsets) || throw(ArgumentError(
            "cell anchor offsets must be finite and include the identifying reference"))
        push!(shifts, (; block, reference_shift = first(offsets),
            compatible = all(offset -> abs(offset - first(offsets)) <= tolerance, offsets)))
    end
    cell.targets isa AbstractVector && requests isa AbstractVector ||
        throw(ArgumentError("cell targets and contrast requests must be explicit vectors"))
    targets = Dict{String,NamedTuple}()
    for row in cell.targets
        row isa NamedTuple && Set(keys(row)) == Set((:name, :block, :positive, :negative, :role)) ||
            throw(ArgumentError("cell targets must supply named contrast labels and primary/secondary role"))
        all(value -> value isa AbstractString && !isempty(value), (row.name, row.positive, row.negative)) &&
            row.block isa Symbol && row.block in (:person, :rater, :item) && row.positive != row.negative &&
            row.role isa Symbol && row.role in (:primary, :secondary) || throw(ArgumentError("invalid cell target labels or role"))
        !haskey(targets, row.name) && all(label -> haskey(truth[row.block], label),
            (row.positive, row.negative)) || throw(ArgumentError("duplicate target name or unknown truth level"))
        true_value = truth[row.block][row.positive] - truth[row.block][row.negative]
        isfinite(true_value) || throw(ArgumentError("cell true contrast is not representable"))
        levels = getproperty(design.spec.data, Symbol(row.block, :_levels))
        contrast_is_fixed = row.block !== :person && all(label ->
            ismissing(_stable_facet_parameter_index(design, row.block, findfirst(==(label), levels))),
            (row.positive, row.negative))
        targets[row.name] = merge(row, (; true_value, contrast_is_fixed))
    end
    length(requests) == length(targets) && all(request -> request isa NamedTuple &&
        all(key -> haskey(request, key), (:name, :block, :positive, :negative)) &&
        haskey(targets, request.name) && all(key -> getproperty(request, key) ==
            getproperty(targets[request.name], key), (:block, :positive, :negative)), requests) &&
        length(unique(request.name for request in requests)) == length(requests) ||
        throw(ArgumentError("requested contrasts must match the complete declared cell roster"))
    anchor_compatible = all(row -> row.compatible, shifts)
    recovery_status = cell.model_status === :misspecified ||
        cell.identification_status === :unidentified ? :distortion_only :
        !anchor_compatible ? :distortion_only :
        cell.model_status === :unresolved || cell.identification_status === :unresolved ? :unresolved_cell :
        :candidate_available
    return (; cell.cell_id, anchor_shifts = Tuple(shifts), anchor_compatible,
        recovery_status, targets = Tuple(targets[name] for name in sort(collect(keys(targets)))),
        declaration_review_required = true, validation_claim_allowed = false)
end

# Reuse paired-draw diagnostics; a fixed coordinate is not a sampled constant.
function _mfrm_anchor_contrast_scores(fit, requests, policy; cell = nothing)
    requests isa AbstractVector || throw(ArgumentError("contrasts must be an explicit vector"))
    required = (:name, :block, :positive, :negative, :probabilities,
        :mean_mcse_max, :endpoint_mcse_max)
    names = String[]
    rows = NamedTuple[]
    for request in requests
        request isa NamedTuple && Set(keys(request)) == Set(required) || throw(ArgumentError(
            "contrast requests must supply labels, two endpoint probabilities, and MCSE limits"))
        all(value -> value isa AbstractString && !isempty(value),
            (request.name, request.positive, request.negative)) || throw(ArgumentError(
                "contrast names and level labels must be nonempty strings"))
        request.name in names && throw(ArgumentError("contrast names must be unique"))
        push!(names, request.name)
        request.block isa Symbol && request.block in (:person, :rater, :item) && request.positive != request.negative ||
            throw(ArgumentError("contrasts need two distinct levels in person, rater, or item"))
        request.probabilities isa Union{Tuple,AbstractVector} &&
            all(value -> value isa Real && !(value isa Bool), request.probabilities) ||
            throw(ArgumentError("contrast probabilities must be an explicit numeric pair"))
        probabilities = _posterior_interval_probabilities(request.probabilities)
        length(probabilities) == 2 && probabilities[1] < probabilities[2] ||
            throw(ArgumentError("contrasts require two increasing interval probabilities"))
        for limit in (request.mean_mcse_max, request.endpoint_mcse_max)
            limit === nothing || (limit isa Real && !(limit isa Bool) &&
                isfinite(limit) && limit > 0) || throw(ArgumentError(
                    "contrast MCSE limits must be positive finite numbers or nothing"))
        end
        levels = getproperty(fit.design.spec.data, Symbol(request.block, :_levels))
        function coordinate(label)
            level = findfirst(==(label), levels)
            level === nothing && throw(ArgumentError("unknown contrast level: $label"))
            index = request.block === :person ? fit.design.blocks[:person][level] :
                _stable_facet_parameter_index(fit.design, request.block, level)
            return (; is_fixed = ismissing(index), values = ismissing(index) ?
                fill(_stable_facet_fixed_value(fit.design, request.block, level), size(fit.draws, 1)) :
                @view(fit.draws[:, index]))
        end
        positive, negative = coordinate(request.positive), coordinate(request.negative)
        estimation = _rater_contrast_estimation_metadata(positive, negative)
        values = reshape(positive.values .- negative.values, :, 1)
        target = cell === nothing ? nothing : only(row for row in cell.targets if row.name == request.name)
        recovery_status = estimation.contrast_is_fixed ? :not_applicable_fixed :
            cell === nothing ? :undeclared_cell : cell.recovery_status
        # The existing recovery scorer supplies central intervals only. Do not
        # silently replace explicitly requested asymmetric quantiles.
        if recovery_status === :candidate_available &&
                !isapprox(sum(probabilities), 1.0; atol = 8eps(Float64), rtol = 0)
            recovery_status = :unsupported_recovery_interval
        end
        recovery = recovery_status === :candidate_available ? only(_parameter_recovery_rows(
            [String(request.name)], Dict(Symbol(request.block, :_contrast) => 1:1), values, [target.true_value];
            interval = probabilities[2] - probabilities[1],
            metadata = (; cell_id = cell.cell_id, target_role = target.role,
                diagnostic_selection_applied = false, validation_claim_allowed = false))) : nothing
        base = (; request, estimation...,
            contrast_interval_type = estimation.contrast_is_fixed ?
                estimation.contrast_interval_type : :quantile_interval,
            estimate = mean(values), target, recovery_status, recovery,
            target_error = target === nothing ? missing : mean(values) - target.true_value,
            validation_claim_allowed = false)
        if estimation.contrast_is_fixed
            push!(rows, merge(base, (; status = :not_applicable_fixed, diagnostics = nothing, mcse = nothing)))
            continue
        end
        chains = length(fit.chain_acceptance_rate)
        diagnostic = only(_candidate_mcmc_diagnostic_rows(values, [String(request.name)], chains;
            parameter_space = :derived_contrast, split_chains = policy.split_chains,
            rhat_threshold = Float64(policy.rhat_threshold), ess_threshold = Float64(policy.ess_threshold)))
        mcse = only(posterior_mcse(values; chains, parameter_names = [request.name],
            probabilities, parameter_space = :derived_contrast))
        # SD-MCSE is not a requested target; mean and both interval endpoints are.
        usable = all(value -> !ismissing(value) && isfinite(value) && value >= 0,
            (mcse.mean_mcse, (row.mcse for row in mcse.quantiles)...))
        status = diagnostic.flag !== :ok ? :diagnostic_warning :
            !usable ? :mcse_unavailable :
            request.mean_mcse_max === nothing || request.endpoint_mcse_max === nothing ? :precision_unresolved :
            mcse.mean_mcse > request.mean_mcse_max ||
                any(row -> row.mcse > request.endpoint_mcse_max, mcse.quantiles) ? :precision_exceeded :
            :screen_passed
        push!(rows, merge(base, (; status, diagnostics = diagnostic, mcse)))
    end
    return Tuple(rows)
end

# A caller-retained roster is distinct from the supplied digest map. Coverage
# of that declaration does not establish its scientific/execution completeness.
function _mfrm_anchor_required_sources(reference)
    paths = _nt_get(reference, :required_source_paths, nothing)
    paths === nothing && return nothing
    (paths isa Tuple || paths isa AbstractVector) && !isempty(paths) &&
        all(p -> p isa AbstractString && isabspath(p) && normpath(p) == p, paths) &&
        length(unique(paths)) == length(paths) || throw(ArgumentError(
            "required_source_paths must be a nonempty tuple/vector of unique normalized absolute paths"))
    reference.source_files isa AbstractDict &&
        all(p -> haskey(reference.source_files, p), paths) || throw(ArgumentError(
            "source_files omits a declared required source"))
    return Tuple(sort!(collect(paths)))
end

# M2 preparation: a completed-object consumer, not a fitter or attempt ledger.
# References are retained separately by the caller; no self-reported acceptance.
function _mfrm_anchor_score_attempt(fit,
        training_bytes::AbstractVector{UInt8}, heldout_bytes::AbstractVector{UInt8},
        truth_records::AbstractVector; reference::NamedTuple)
    fit isa MFRMFit || throw(ArgumentError("anchor scoring requires an MFRMFit"))
    fit, training_bytes, heldout_bytes, truth_records, reference = deepcopy(
        (fit, training_bytes, heldout_bytes, truth_records, reference))
    required = (:dataset_id, :heldout_id, :method, :attempt, :training, :heldout,
        :fit_sha256, :truth_sha256, :source_files, :diagnostic_policy, :contrasts, :cell)
    all(key -> haskey(reference, key), required) || throw(ArgumentError(
        "scoring reference is missing required attempt/input/policy fields"))
    _mfrm_anchor_primary_attempts([reference], NamedTuple[]) # Validate planned labels.
    reference.attempt isa Integer && !(reference.attempt isa Bool) &&
        reference.attempt > 0 || throw(ArgumentError("attempt must be a positive integer"))
    source_files = reference.source_files
    source_files isa AbstractDict && !isempty(source_files) || throw(ArgumentError(
        "source_files must contain independently retained file digests"))
    required_source_paths = _mfrm_anchor_required_sources(reference)
    for digest in (reference.fit_sha256, reference.truth_sha256, values(source_files)...)
        digest isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", digest) ||
            throw(ArgumentError("scoring digests must be lowercase 64-hex"))
    end
    for (path, digest) in source_files
        path isa AbstractString && isabspath(path) || throw(ArgumentError(
            "source reference paths must be absolute"))
        _evidence_file_sha256(path) == digest || throw(ArgumentError(
            "source file does not match the retained reference: $path"))
    end
    policy = reference.diagnostic_policy
    policy isa NamedTuple && Set(keys(policy)) ==
        Set((:split_chains, :rhat_threshold, :ess_threshold, :min_e_bfmi)) || throw(ArgumentError(
            "diagnostic policy must explicitly supply split_chains, rhat_threshold, ess_threshold, and min_e_bfmi"))
    policy.split_chains isa Bool || throw(ArgumentError("split_chains must be Boolean"))
    all(value -> value isa Real && !(value isa Bool),
        (policy.rhat_threshold, policy.ess_threshold, policy.min_e_bfmi)) || throw(ArgumentError(
            "diagnostic thresholds must be real numbers, not Boolean"))
    _check_diagnostic_thresholds(policy.rhat_threshold, policy.ess_threshold)
    isfinite(policy.min_e_bfmi) && policy.min_e_bfmi > 0 || throw(ArgumentError(
        "min_e_bfmi must be finite and positive"))
    _mfrm_anchor_fit_hash(fit) == reference.fit_sha256 || throw(ArgumentError(
        "fit contents do not match the retained attempt reference"))
    _cache_hash(truth_records) == reference.truth_sha256 || throw(ArgumentError(
        "truth records do not match the retained reference"))

    train = _mfrm_anchor_response_data(training_bytes, reference.training)
    heldout = _mfrm_anchor_response_data(heldout_bytes, reference.heldout)
    _report_lookup(reference.training, :dataset_id, nothing) == reference.dataset_id &&
        _report_lookup(reference.training, :role, nothing) == "train" &&
        _report_lookup(reference.heldout, :dataset_id, nothing) == reference.heldout_id &&
        _report_lookup(reference.heldout, :role, nothing) == "heldout" || throw(ArgumentError(
            "response references do not match the attempt identities/roles"))
    # Rebuild only the declared minimal panel; do not trust a cached data signature.
    expected_design = getdesign(mfrm_spec(train; thresholds = fit.design.spec.thresholds,
        anchors = fit.design.spec.anchors))
    design_identity(expected_design).value == design_identity(fit.design).value ||
        throw(ArgumentError("fit design does not match the restored training responses"))
    events(data) = [(; person = data.person_levels[data.person[n]],
        rater = data.rater_levels[data.rater[n]], item = data.item_levels[data.item[n]])
        for n in 1:data.n]
    training_events, heldout_events = events(train), events(heldout)
    levels = train.category_levels
    heldout.category_levels == levels || throw(ArgumentError("heldout category scale differs from training"))
    training_index = Dict(_mfrm_anchor_event_key(row) => n for (n, row) in pairs(training_events))
    heldout_keys = Set(_mfrm_anchor_event_key.(heldout_events))
    panel = _nt_get(reference, :evaluation_panel, nothing)
    if panel === nothing
        heldout_keys == Set(keys(training_index)) || throw(ArgumentError(
            "without an explicit evaluation panel, heldout events must equal training events"))
    else
        panel isa NamedTuple && Set(keys(panel)) == Set((:panel_id, :events, :weighting)) &&
            panel.panel_id isa AbstractString && !isempty(panel.panel_id) && panel.weighting === :equal_event &&
            panel.events isa AbstractVector && !isempty(panel.events) &&
            all(row -> row isa NamedTuple && Set(keys(row)) == Set((:person, :rater, :item)), panel.events) ||
            throw(ArgumentError("evaluation panel requires an ID, labelled event vector, and equal-event weighting"))
        declared_keys = _mfrm_anchor_event_key.(panel.events)
        length(unique(declared_keys)) == length(declared_keys) && Set(declared_keys) == heldout_keys &&
            all(key -> haskey(training_index, key), declared_keys) || throw(ArgumentError(
                "evaluation events must be unique, match heldout exactly, and occur in training"))
    end
    heldout_indices = [training_index[_mfrm_anchor_event_key(row)] for row in heldout_events]
    evaluation_scope = (; declared_panel = panel !== nothing,
        panel_id = panel === nothing ? nothing : panel.panel_id, weighting = :equal_event,
        n_training_events = train.n, n_evaluation_events = heldout.n)
    logtruth = _mfrm_anchor_log_probability_matrix(truth_records, heldout_events, levels)
    logs = Array{Float64}(undef, size(fit.draws, 1), heldout.n, length(levels))
    # ponytail: reuse labelled inspection per draw; optimize only after a bounded
    # workload demonstrates a need. No sampled/subset/reordered posterior draws.
    for s in axes(fit.draws, 1)
        # Validate the full original-design prediction before selecting events;
        # never rebuild a possibly disconnected heldout design or drop bad rows.
        full_logs = _mfrm_anchor_log_probability_matrix(
            linear_predictor_values(fit.design, @view(fit.draws[s, :])), training_events, levels)
        logs[s, :, :] = full_logs[heldout_indices, :]
    end
    logobserved = fill(-Inf, heldout.n, length(levels))
    for n in 1:heldout.n
        logobserved[n, heldout.category[n]] = 0.0
    end
    # Malformed fields are integrity errors; absent/partial valid rows remain
    # diagnostic-unresolved and must not erase the available point scores.
    stat_fields = (:chain, :iteration, :is_adapt, :numerical_error, :tree_depth,
        :n_steps, :step_size, :hamiltonian_energy)
    all(row -> all(key -> haskey(row, key), stat_fields) &&
        row.chain isa Integer && !(row.chain isa Bool) && row.chain > 0 &&
        row.iteration isa Integer && !(row.iteration isa Bool) && row.iteration > 0 &&
        row.is_adapt isa Bool && row.numerical_error isa Bool &&
        (ismissing(row.tree_depth) || (row.tree_depth isa Integer &&
            !(row.tree_depth isa Bool) && row.tree_depth >= 0)) &&
        all(value -> ismissing(value) || (value isa Real && !(value isa Bool)),
            (row.n_steps, row.step_size, row.hamiltonian_energy)), fit.sampler_stats) ||
        throw(ArgumentError("malformed sampler statistics for anchor diagnostics"))
    depth = _nt_get(fit.sampler_controls, :max_depth, missing)
    ismissing(depth) || (depth isa Integer && !(depth isa Bool) && depth > 0) ||
        throw(ArgumentError("max_depth must be a positive integer when supplied"))
    diagnostic = diagnostics(fit; split_chains = policy.split_chains,
        rhat_threshold = policy.rhat_threshold, ess_threshold = policy.ess_threshold)
    trajectory_complete = length(fit.sampler_stats) == size(fit.draws, 1) &&
        all(row.chain == fit.chain_ids[n] && row.iteration == fit.iterations[n] && !row.is_adapt
            for (n, row) in pairs(fit.sampler_stats))
    depth_available = depth isa Integer && !(depth isa Bool) && depth > 0 &&
        all(row -> !ismissing(row.tree_depth), fit.sampler_stats)
    minimum_e_bfmi = trajectory_complete && diagnostic.summary.e_bfmi_complete ?
        diagnostic.summary.e_bfmi : missing
    hmc_status = !(fit.backend in (:advancedhmc, :turing, :cmdstan) && fit.sampler === :nuts) ? :not_applicable_backend :
        !trajectory_complete ? :incomplete_trajectory :
        ismissing(minimum_e_bfmi) || !depth_available ? :diagnostics_unavailable :
        !diagnostic.summary.passed ? :diagnostic_warning :
        minimum_e_bfmi < policy.min_e_bfmi ? :low_e_bfmi : :screen_passed
    hmc_screen = (; status = hmc_status, trajectory_complete, depth_available,
        minimum_e_bfmi, threshold = policy.min_e_bfmi, passed = hmc_status === :screen_passed,
        validation_claim_allowed = false)
    cell = _mfrm_anchor_cell_targets(fit.design, reference.contrasts, reference.cell, reference.truth_sha256)
    contrast_scores = _mfrm_anchor_contrast_scores(fit, reference.contrasts, policy; cell)
    chains = length(fit.chain_acceptance_rate)
    truth_score = _mfrm_anchor_log_score_delta_mcse(logs, logtruth; chains)
    heldout_score = _mfrm_anchor_log_score_delta_mcse(logs, logobserved; chains)
    # Descriptive totals on the evaluation panel, including unused categories;
    # these are not category/threshold interval or MCSE acceptance tests.
    category_totals = Tuple((; category = level,
        observed_count = count(==(level), heldout.score),
        truth_expected_count = sum(exp, @view(logtruth[:, k])),
        predicted_expected_count = sum(exp(_logmeanexp(@view(logs[:, n, k]))) for n in 1:heldout.n))
        for (k, level) in pairs(levels))
    record = (; reference.dataset_id, reference.heldout_id, reference.method,
        reference.attempt, status = :scored, reference,
        score_scope = :equal_event_log_scores_and_labelled_contrasts, julia_version = string(VERSION),
        diagnostics = diagnostic, hmc_screen, cell, contrast_scores, evaluation_scope,
        source_coverage = (; status = required_source_paths === nothing ?
            :undeclared : :declared_roster_covered, required_source_paths),
        truth_score, heldout_score, category_totals, precision_status = :unresolved,
        diagnostic_acceptance_review_required = true,
        source_coverage_review_required = true, validation_claim_allowed = false)
    return merge(record, (; content_hash = artifact_content_hash(record)))
end

# Shared integrity boundary for recovery and descriptive predictive summaries.
# Callers snapshot inputs; hashes are separately retained, not self-reported trust.
function _mfrm_anchor_checked_primary(plan::AbstractVector, attempts::AbstractVector,
        attempt_hashes::AbstractDict)
    isempty(plan) && throw(ArgumentError("summary requires a nonempty planned denominator"))
    primary = _mfrm_anchor_primary_attempts(plan, attempts)
    length(unique(row.method for row in plan)) == 1 &&
        length(unique(row.dataset_id for row in plan)) == length(plan) || throw(ArgumentError(
            "summarize one method with one heldout identity per independent dataset"))
    digest_valid(value) = value isa AbstractString && occursin(r"\A[0-9a-f]{64}\z", value)
    all(row -> haskey(row, :reference_sha256) &&
        (row.reference_sha256 === nothing || digest_valid(row.reference_sha256)), plan) ||
        throw(ArgumentError("planned primary-reference digests must be 64-hex or explicit nothing"))
    key(row) = (row.dataset_id, row.heldout_id, row.method, row.attempt)
    Set(keys(attempt_hashes)) == Set(key(row) for row in attempts) &&
        all(digest_valid, values(attempt_hashes)) || throw(ArgumentError(
            "independently retained attempt digests must cover exactly the supplied attempts"))
    for row in attempts
        _cache_hash(row) == attempt_hashes[key(row)] ||
            throw(ArgumentError("attempt contents do not match the retained digest"))
        row.status in (:scored, :not_started, :running, :generation_failed,
            :structurally_rejected, :fit_failed, :scoring_failed) ||
            throw(ArgumentError("unsupported primary/extra attempt disposition"))
        if row.status === :scored
            row.content_hash == artifact_content_hash(row) &&
                all(field -> getproperty(row.reference, field) == getproperty(row, field),
                    (:dataset_id, :heldout_id, :method, :attempt)) ||
                throw(ArgumentError("scored report hash or attempt/reference identity mismatch"))
        else
            haskey(row, :reason) && row.reason isa AbstractString && !isempty(row.reason) ||
                throw(ArgumentError("unscored dispositions require a retained reason"))
        end
    end
    for (planned, report) in zip(plan, primary)
        if report !== nothing && report.status === :scored
            planned.reference_sha256 === nothing || _cache_hash(report.reference) == planned.reference_sha256 ||
                throw(ArgumentError("primary scoring reference differs from the separately retained reference"))
        end
    end
    return primary
end

# Read-only, one cell/method/target at a time. This is not an execution ledger.
function _mfrm_anchor_recovery_summary(plan::AbstractVector, attempts::AbstractVector;
        cell::NamedTuple, request::NamedTuple, diagnostic_policy::NamedTuple,
        attempt_hashes::AbstractDict)
    plan, attempts, cell, request, diagnostic_policy, attempt_hashes = deepcopy(
        (plan, attempts, cell, request, diagnostic_policy, attempt_hashes))
    primary = _mfrm_anchor_checked_primary(plan, attempts, attempt_hashes)
    selected_targets = [target for target in cell.targets if target.name == request.name]
    length(selected_targets) == 1 || throw(ArgumentError("requested summary target is not unique in the cell roster"))
    target = only(selected_targets)
    all(field -> getproperty(target, field) == getproperty(request, field), (:block, :positive, :negative)) ||
        throw(ArgumentError("summary target orientation does not match the declared roster"))
    applicability = target.contrast_is_fixed ? :not_applicable_fixed : cell.recovery_status
    applicability in (:candidate_available, :not_applicable_fixed, :distortion_only, :unresolved_cell) ||
        throw(ArgumentError("unsupported cell recovery applicability"))
    dispositions = NamedTuple[]
    eligible = NamedTuple[]
    for (planned, report) in zip(plan, primary)
        candidate = nothing
        disposition = report === nothing ? :not_recorded : report.status
        if report !== nothing && report.status === :scored
            _cache_hash(report.cell) == _cache_hash(cell) &&
                _cache_hash(report.reference.diagnostic_policy) == _cache_hash(diagnostic_policy) ||
                throw(ArgumentError("primary cell/truth or diagnostic policy differs from the planned definition"))
            matches = [row for row in report.contrast_scores if row.request.name == request.name]
            length(matches) == 1 || throw(ArgumentError("primary report must contain the selected target exactly once"))
            candidate = only(matches)
            _cache_hash(candidate.request) == _cache_hash(request) &&
                _cache_hash(candidate.target) == _cache_hash(target) &&
                candidate.contrast_is_fixed == target.contrast_is_fixed ||
                throw(ArgumentError("primary target, truth, role, interval, or precision limits differ from the plan"))
            hmc = report.hmc_screen
            diagnostic_ok = report.diagnostics.summary.passed === true &&
                hmc.status === :screen_passed && hmc.passed === true &&
                hmc.trajectory_complete === true && hmc.depth_available === true &&
                hmc.threshold == diagnostic_policy.min_e_bfmi &&
                !ismissing(hmc.minimum_e_bfmi) && isfinite(hmc.minimum_e_bfmi) &&
                hmc.minimum_e_bfmi >= diagnostic_policy.min_e_bfmi
            recovery = candidate.recovery
            if recovery !== nothing
                recovery.parameter == request.name && recovery.cell_id == cell.cell_id &&
                    recovery.target_role === target.role && recovery.true_value == target.true_value &&
                    isapprox(recovery.interval_probability, request.probabilities[2] - request.probabilities[1];
                        atol = 8eps(Float64), rtol = 0) ||
                    throw(ArgumentError("recovery row does not describe the declared target/truth/interval"))
            end
            mcse = candidate.mcse
            mcse_available = mcse !== nothing && length(mcse.quantiles) == 2 &&
                all(value -> !ismissing(value) && isfinite(value) && value >= 0,
                    (mcse.mean_mcse, (q.mcse for q in mcse.quantiles)...))
            if mcse !== nothing
                Tuple(q.probability for q in mcse.quantiles) == Tuple(request.probabilities) ||
                    throw(ArgumentError("contrast MCSE endpoints do not match the planned interval"))
            end
            precision_status = request.mean_mcse_max === nothing || request.endpoint_mcse_max === nothing ? :precision_unresolved :
                !mcse_available ? :mcse_unavailable :
                mcse.mean_mcse > request.mean_mcse_max ||
                    any(q -> q.mcse > request.endpoint_mcse_max, mcse.quantiles) ? :precision_exceeded : :screen_passed
            finite_recovery = recovery !== nothing && recovery.covered isa Bool &&
                all(field -> isfinite(getproperty(recovery, field)),
                    (:true_value, :posterior_mean, :posterior_sd, :bias, :absolute_bias,
                        :squared_error, :interval_width, :posterior_lower, :posterior_upper))
            disposition = applicability !== :candidate_available ? applicability :
                planned.reference_sha256 === nothing ? :reference_unavailable :
                !diagnostic_ok ? :diagnostic_unresolved :
                candidate.diagnostics === nothing || candidate.diagnostics.flag !== :ok ? :contrast_diagnostic_unresolved :
                candidate.status !== :screen_passed ? candidate.status :
                precision_status !== :screen_passed ? precision_status :
                candidate.recovery_status !== :candidate_available || recovery === nothing ? :recovery_unavailable :
                !finite_recovery ? :nonfinite_recovery : :screen_eligible
            disposition === :screen_eligible && push!(eligible, recovery)
        end
        push!(dispositions, (; planned.dataset_id, planned.heldout_id, planned.method,
            attempt = 1, reported_status = report === nothing ? :not_recorded : report.status,
            disposition, reason = report === nothing ? nothing : _nt_get(report, :reason, nothing),
            point_error = candidate === nothing ? missing : candidate.target_error,
            recovery = candidate === nothing ? nothing : candidate.recovery))
    end
    n_planned, n_eligible = length(plan), length(eligible)
    recovery_summary = isempty(eligible) ? nothing : only(parameter_recovery_summary(eligible; by = :all))
    # Reuse the existing descriptive 95% Wilson/count envelope, not its study
    # acceptance rules or bounded correlation-error assumptions.
    coverage = applicability === :candidate_available ? _free_correlation_study_binary_summary(
        count(row -> row.covered, eligible), n_eligible, n_planned, 1.959963984540054) : nothing
    across_mcse(values) = length(values) < 2 ? missing : std(values) / sqrt(length(values))
    bias_mcse = across_mcse([row.bias for row in eligible])
    mse_mcse = across_mcse([row.squared_error for row in eligible])
    aggregate_finite = recovery_summary === nothing || all(field -> isfinite(getproperty(recovery_summary, field)),
        (:mean_bias, :mean_absolute_error, :rmse, :mean_interval_width))
    aggregate_finite &= all(value -> ismissing(value) || isfinite(value), (bias_mcse, mse_mcse))
    record = (; cell.cell_id, method = only(unique(row.method for row in plan)), target, request,
        diagnostic_policy, applicability, n_planned, n_screen_eligible = n_eligible,
        n_reported_primary = count(!isnothing, primary),
        n_scored_primary = count(row -> row !== nothing && row.status === :scored, primary),
        n_additional_attempts = count(row -> row.attempt > 1, attempts),
        dispositions = Tuple(dispositions), recovery_summary, coverage, bias_mcse, mse_mcse,
        aggregate_finite, plan, attempt_hashes,
        status = applicability !== :candidate_available ? applicability :
            !aggregate_finite ? :aggregate_nonfinite : n_eligible == 0 ? :no_eligible_primary : :conditional_summary,
        lifecycle_counts_available = false, declaration_and_provenance_review_required = true,
        validation_claim_allowed = false)
    return merge(record, (; content_hash = artifact_content_hash(record)))
end

function _mfrm_anchor_check_comparison(comparison)
    length(comparison) in (2, 4) && all(row -> row isa NamedTuple &&
        Set(keys(row)) == Set((:method, :weight)) && row.method isa AbstractString &&
        !isempty(row.method) && row.weight isa Real && !(row.weight isa Bool) &&
        row.weight in (-1, 1), comparison) &&
        sum(row.weight for row in comparison) == 0 &&
        length(unique(row.method for row in comparison)) == length(comparison) || throw(ArgumentError(
            "predeclare two or four distinct methods with balanced +1/-1 weights"))
    return nothing
end

# Design/fit hashes and cell IDs may differ across anchor methods. Data/truth
# and evaluation declarations must agree even on subsequently excluded rows.
function _mfrm_anchor_check_shared_data(scored)
    data_reference(r) = (; r.training, r.heldout, r.truth_sha256,
        r.source_files, required_source_paths = _mfrm_anchor_required_sources(r),
        coordinate_truth = r.cell === nothing ? nothing : r.cell.truth,
        evaluation_panel = _nt_get(r, :evaluation_panel, nothing))
    isempty(scored) || all(r -> _cache_hash(data_reference(r.reference)) ==
        _cache_hash(data_reference(scored[1].reference)), scored) || throw(ArgumentError(
            "paired primary response bytes, truth, sources, or evaluation declarations differ"))
    return nothing
end

# Same-data contrast-error differences only; predictive-loss eligibility still
# needs its own precision/curvature review. Never subtract marginal summaries.
function _mfrm_anchor_paired_recovery(groups::AbstractVector; comparison)
    groups, comparison = deepcopy((groups, comparison))
    _mfrm_anchor_check_comparison(comparison)
    summaries = [_mfrm_anchor_recovery_summary(g.plan, g.attempts;
        g.cell, g.request, g.diagnostic_policy, g.attempt_hashes) for g in groups]
    length(summaries) == length(comparison) &&
        Set(s.method for s in summaries) == Set(c.method for c in comparison) || throw(ArgumentError(
            "supply exactly one recovery group per predeclared method"))
    order = [only(findall(s -> s.method == c.method, summaries)) for c in comparison]
    groups, summaries = groups[order], summaries[order]
    key(row) = (row.dataset_id, row.heldout_id)
    roster = Set(key(row) for row in summaries[1].plan)
    target_definition(t) = (; t.name, t.block, t.positive, t.negative, t.role, t.true_value)
    for summary in summaries
        Set(key(row) for row in summary.plan) == roster || throw(ArgumentError(
            "paired methods must retain the same planned dataset AND heldout roster"))
        _cache_hash(target_definition(summary.target)) == _cache_hash(target_definition(summaries[1].target)) &&
            _cache_hash(summary.request) == _cache_hash(summaries[1].request) &&
            _cache_hash(summary.diagnostic_policy) == _cache_hash(summaries[1].diagnostic_policy) ||
            throw(ArgumentError("paired methods must share the oriented target/truth/role and screening policy"))
    end
    primary = [Dict(key(p) => r for (p, r) in zip(g.plan,
        _mfrm_anchor_primary_attempts(g.plan, g.attempts))) for g in groups]
    dispositions = [Dict(key(row) => row for row in s.dispositions) for s in summaries]
    rows = NamedTuple[]
    for identity in sort!(collect(roster))
        scored = [p[identity] for p in primary if p[identity] !== nothing && p[identity].status === :scored]
        _mfrm_anchor_check_shared_data(scored)
        methods = Tuple(d[identity] for d in dispositions)
        common = all(row -> row.disposition === :screen_eligible, methods)
        bias_difference = common ? sum(c.weight * row.recovery.bias for (c, row) in zip(comparison, methods)) : missing
        squared_error_difference = common ? sum(c.weight * row.recovery.squared_error for (c, row) in zip(comparison, methods)) : missing
        finite = common && isfinite(bias_difference) && isfinite(squared_error_difference)
        push!(rows, (; dataset_id = identity[1], heldout_id = identity[2], methods,
            status = !common ? :outside_common_subset : !finite ? :nonfinite_difference : :screen_eligible,
            bias_difference, squared_error_difference))
    end
    eligible = [row for row in rows if row.status === :screen_eligible]
    n = length(eligible)
    bias = [row.bias_difference for row in eligible]
    squared_error = [row.squared_error_difference for row in eligible]
    bias_difference = n == 0 ? missing : mean(bias)
    mse_difference = n == 0 ? missing : mean(squared_error)
    bias_difference_mcse = n < 2 ? missing : std(bias) / sqrt(n)
    mse_difference_mcse = n < 2 ? missing : std(squared_error) / sqrt(n)
    aggregate_finite = all(value -> ismissing(value) || isfinite(value),
        (bias_difference, mse_difference, bias_difference_mcse, mse_difference_mcse))
    applicable = all(s -> s.applicability === :candidate_available, summaries)
    methods = Tuple(merge(s, (; c.weight,
        n_unavailable = s.n_planned - s.n_screen_eligible,
        n_eligible_outside_common = s.n_screen_eligible - n,
        unavailable_counts = Tuple((; disposition = status, n = count(r -> r.disposition === status, s.dispositions))
            for status in sort!(unique([r.disposition for r in s.dispositions if r.disposition !== :screen_eligible]); by = string))))
        for (s, c) in zip(summaries, comparison))
    record = (; comparison = Tuple(comparison), target = target_definition(summaries[1].target),
        n_planned = length(roster), n_common_eligible = n,
        n_joint_screen_eligible = count(row -> row.status !== :outside_common_subset, rows),
        methods, rows = Tuple(rows), bias_difference, mse_difference,
        bias_difference_mcse, mse_difference_mcse, aggregate_finite,
        status = !applicable ? :inapplicable_comparison :
            !aggregate_finite || any(row -> row.status === :nonfinite_difference, rows) ? :nonfinite_comparison :
            n == 0 ? :no_common_eligible_primary : :conditional_summary,
        lifecycle_counts_available = false, declaration_and_provenance_review_required = true,
        validation_claim_allowed = false)
    return merge(record, (; content_hash = artifact_content_hash(record)))
end

# Descriptive point-loss pairs only: no diagnostic/precision selection, inferred
# cross-fit draw coupling, combined within-fit MCSE, or recovery applicability.
function _mfrm_anchor_paired_predictive(groups::AbstractVector; comparison, score::Symbol)
    score in (:truth_score, :heldout_score) || throw(ArgumentError(
        "select truth_score or heldout_score explicitly; never mix score kinds"))
    groups, comparison = deepcopy((groups, comparison))
    _mfrm_anchor_check_comparison(comparison)
    checked = [_mfrm_anchor_checked_primary(g.plan, g.attempts, g.attempt_hashes) for g in groups]
    methods = [only(unique(p.method for p in g.plan)) for g in groups]
    length(groups) == length(comparison) && Set(methods) == Set(c.method for c in comparison) ||
        throw(ArgumentError("supply exactly one predictive group per predeclared method"))
    order = [only(findall(==(c.method), methods)) for c in comparison]
    groups, checked = groups[order], checked[order]
    key(row) = (row.dataset_id, row.heldout_id)
    roster = Set(key(row) for row in groups[1].plan)
    all(g -> Set(key(row) for row in g.plan) == roster, groups) || throw(ArgumentError(
        "paired methods must retain the same planned dataset AND heldout roster"))
    primary = [Dict(key(p) => r for (p, r) in zip(g.plan, reports)) for (g, reports) in zip(groups, checked)]
    plans = [Dict(key(p) => p for p in g.plan) for g in groups]
    rows = NamedTuple[]
    for identity in sort!(collect(roster))
        scored = [p[identity] for p in primary if p[identity] !== nothing && p[identity].status === :scored]
        _mfrm_anchor_check_shared_data(scored)
        isempty(scored) || all(r -> r.score_scope === :equal_event_log_scores_and_labelled_contrasts &&
            r.evaluation_scope.weighting === :equal_event &&
            _cache_hash(r.evaluation_scope) == _cache_hash(scored[1].evaluation_scope), scored) ||
            throw(ArgumentError("paired predictive reports must share their equal-event scoring scope"))
        dispositions = NamedTuple[]
        for (c, p, planned) in zip(comparison, primary, plans)
            report = p[identity]
            value = mcse = missing
            score_status = diagnostic_status = nothing
            diagnostic_passed = missing
            status = report === nothing ? :not_recorded : report.status
            if report !== nothing && report.status === :scored
                haskey(report, score) || throw(ArgumentError("report is missing the selected predictive score"))
                prediction = getproperty(report, score)
                prediction isa NamedTuple && all(f -> haskey(prediction, f), (:estimate, :status, :mcse)) &&
                    prediction.estimate isa Real && !(prediction.estimate isa Bool) && prediction.status isa Symbol &&
                    (ismissing(prediction.mcse) || (prediction.mcse isa Real && !(prediction.mcse isa Bool) &&
                        isfinite(prediction.mcse) && prediction.mcse >= 0)) ||
                    throw(ArgumentError("malformed predictive point loss or reported MCSE"))
                value, mcse, score_status = Float64(prediction.estimate), prediction.mcse, prediction.status
                diagnostic_status, diagnostic_passed = report.hmc_screen.status, report.diagnostics.summary.passed
                status = planned[identity].reference_sha256 === nothing ? :reference_unavailable :
                    !isfinite(value) ? :nonfinite_loss : :point_available
            end
            push!(dispositions, (; method = c.method, attempt = 1, disposition = status,
                reported_status = report === nothing ? :not_recorded : report.status,
                reason = report === nothing ? nothing : _nt_get(report, :reason, nothing),
                point_loss = value, score_status, reported_within_fit_mcse = mcse,
                diagnostic_status, diagnostic_passed))
        end
        common = all(r -> r.disposition === :point_available, dispositions)
        difference = common ? sum(c.weight * r.point_loss for (c, r) in zip(comparison, dispositions)) : missing
        status = !common ? :outside_common_subset : !isfinite(difference) ? :nonfinite_difference : :point_available
        push!(rows, (; dataset_id = identity[1], heldout_id = identity[2], methods = Tuple(dispositions),
            status, loss_difference = difference))
    end
    finite_rows = [r for r in rows if r.status === :point_available]
    n = length(finite_rows)
    differences = [r.loss_difference for r in finite_rows]
    mean_difference = n == 0 ? missing : mean(differences)
    across_replication_se = n < 2 ? missing : std(differences) / sqrt(n)
    aggregate_finite = all(v -> ismissing(v) || isfinite(v), (mean_difference, across_replication_se))
    counts = Tuple((; c.method, c.weight, n_planned = length(roster),
        n_reported_primary = count(!isnothing, checked[j]),
        n_scored_primary = count(r -> r !== nothing && r.status === :scored, checked[j]),
        n_additional_attempts = count(r -> r.attempt > 1, groups[j].attempts),
        n_point_available = count(r -> r.methods[j].disposition === :point_available, rows),
        unavailable_counts = Tuple((; disposition = s, n = count(r -> r.methods[j].disposition === s, rows))
            for s in sort!(unique([r.methods[j].disposition for r in rows
                if r.methods[j].disposition !== :point_available]); by = string))) for (j, c) in pairs(comparison))
    record = (; score, comparison = Tuple(comparison), n_planned = length(roster), n_common_finite = n,
        n_joint_point_available = count(r -> r.status !== :outside_common_subset, rows),
        methods = counts, rows = Tuple(rows), mean_difference, across_replication_se, aggregate_finite,
        status = !aggregate_finite || any(r -> r.status === :nonfinite_difference, rows) ? :nonfinite_comparison :
            n == 0 ? :no_common_finite_primary : :descriptive_common_subset,
        selection = :bound_finite_primary, diagnostic_selection_applied = false,
        precision_status = :unresolved, combined_within_fit_mcse = missing,
        curvature_review_required = true, convergence_review_required = true,
        lifecycle_counts_available = false, declaration_and_provenance_review_required = true,
        plans = Tuple(g.plan for g in groups), attempt_hashes = Tuple(g.attempt_hashes for g in groups),
        validation_claim_allowed = false)
    return merge(record, (; content_hash = artifact_content_hash(record)))
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
