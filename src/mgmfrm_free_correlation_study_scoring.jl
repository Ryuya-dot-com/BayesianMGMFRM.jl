const _FREE_CORRELATION_STUDY_EVALUATION_AGGREGATE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_evaluation_aggregate.v2"
const _FREE_CORRELATION_STUDY_SCORE_SCHEMA =
    "bayesianmgmfrm.mgmfrm_free_latent_correlation_2d_study_score.v2"

function _free_correlation_study_arithmetic_mean(values::AbstractVector{Float64})
    isempty(values) && return missing
    return sum(values; init = 0.0) / length(values)
end

function _free_correlation_study_sample_sd(
        values::AbstractVector{Float64},
        center)
    length(values) >= 2 || return missing
    variance = sum((value - center)^2 for value in values; init = 0.0) /
        (length(values) - 1)
    return sqrt(max(0.0, variance))
end

function _free_correlation_study_wilson(
        successes::Integer,
        trials::Integer,
        z::Real;
        interval_kind::Symbol)
    0 <= successes <= trials || throw(ArgumentError(
        "Wilson counts must satisfy 0 <= successes <= trials",
    ))
    z_value = _free_correlation_study_finite_float(z, "Wilson z")
    z_value > 0 || throw(ArgumentError("Wilson z must be positive"))
    if iszero(trials)
        return (;
            method = :wilson_score,
            interval_kind,
            z = z_value,
            successes = Int(successes),
            trials = Int(trials),
            estimate = missing,
            lower = missing,
            upper = missing,
        )
    end

    n = Float64(trials)
    estimate = Float64(successes) / n
    z2 = z_value^2
    denominator = 1 + z2 / n
    center = (estimate + z2 / (2n)) / denominator
    half_width = z_value / denominator * sqrt(
        estimate * (1 - estimate) / n + z2 / (4n^2),
    )
    return (;
        method = :wilson_score,
        interval_kind,
        z = z_value,
        successes = Int(successes),
        trials = Int(trials),
        estimate,
        lower = max(0.0, center - half_width),
        upper = min(1.0, center + half_width),
    )
end

function _free_correlation_study_binary_summary(
        successes::Int,
        n_valid::Int,
        n_planned::Int,
        two_sided_z::Float64)
    n_planned >= 1 || throw(ArgumentError(
        "binary study summary requires n_planned >= 1",
    ))
    0 <= successes <= n_valid <= n_planned || throw(ArgumentError(
        "binary study counts must satisfy successes <= valid <= planned",
    ))
    n_unresolved = n_planned - n_valid
    conditional = _free_correlation_study_wilson(
        successes,
        n_valid,
        two_sided_z;
        interval_kind = :two_sided_95,
    )
    joint = _free_correlation_study_wilson(
        successes,
        n_planned,
        two_sided_z;
        interval_kind = :two_sided_95,
    )
    return (;
        n_planned,
        n_valid,
        n_unresolved,
        n_successes = successes,
        conditional_rate_among_valid = conditional.estimate,
        conditional_wilson = conditional,
        joint_fixed_denominator_rate = joint.estimate,
        joint_fixed_denominator_wilson = joint,
        unresolved_bounds = (;
            assumption = :all_unresolved_fail_or_all_unresolved_succeed,
            lower = successes / n_planned,
            upper = (successes + n_unresolved) / n_planned,
        ),
    )
end

function _free_correlation_study_scoring_thresholds(plan)
    frozen = plan.recovery_analysis.fixed_evaluation_thresholds
    frozen.scorer_schema == _FREE_CORRELATION_STUDY_SCORE_SCHEMA ||
        throw(ArgumentError("frozen scorer schema does not match implementation"))
    frozen.aggregate_schema ==
        _FREE_CORRELATION_STUDY_EVALUATION_AGGREGATE_SCHEMA ||
        throw(ArgumentError(
            "frozen aggregate schema does not match implementation",
        ))
    frozen.algorithm ===
        :wilson_unresolved_envelope_endpoint_enumerated_full_denominator_mcse_unpaired_symmetry_v2 ||
        throw(ArgumentError("unsupported frozen study scoring algorithm"))
    frozen.implementation_change_policy ===
        :schema_or_algorithm_version_bump_required || throw(ArgumentError(
        "study scoring implementation-change policy was modified",
    ))
    required_terminal = Int(frozen.required_terminal_units_per_rho)
    minimum_valid = Int(frozen.minimum_diagnostically_valid_units_per_rho)
    minimum_scientifically_scored =
        Int(frozen.minimum_scientifically_scored_units_per_rho)
    required_terminal == plan.phases.evaluation.replications_per_rho ||
        throw(ArgumentError(
            "scoring terminal denominator differs from the frozen evaluation roster",
        ))
    0 <= minimum_valid <= required_terminal || throw(ArgumentError(
        "minimum diagnostically valid units must be inside the fixed denominator",
    ))
    0 <= minimum_scientifically_scored <= minimum_valid || throw(ArgumentError(
        "minimum scientifically scored units must not exceed the diagnostic minimum",
    ))

    two_sided_z = _free_correlation_study_finite_float(
        frozen.two_sided_normal_quantile,
        "two-sided normal quantile",
    )
    one_sided_z = _free_correlation_study_finite_float(
        frozen.one_sided_normal_quantile,
        "one-sided normal quantile",
    )
    maximum_abs_bias_upper = _free_correlation_study_finite_float(
        frozen.maximum_abs_bias_upper,
        "maximum absolute bias upper bound",
    )
    maximum_rmse_upper = _free_correlation_study_finite_float(
        frozen.maximum_rmse_upper,
        "maximum RMSE upper bound",
    )
    maximum_abs_unpaired_symmetry_upper =
        _free_correlation_study_finite_float(
            frozen.maximum_abs_unpaired_symmetry_upper,
            "maximum absolute unpaired symmetry upper bound",
        )
    minimum_joint_coverage = _free_correlation_study_finite_float(
        frozen.minimum_joint_valid_and_covered_per_rho,
        "minimum joint coverage per rho",
    )
    minimum_aggregate_coverage = _free_correlation_study_finite_float(
        frozen.minimum_equal_weight_aggregate_coverage_wilson_lower,
        "minimum aggregate coverage",
    )
    minimum_joint_direction = _free_correlation_study_finite_float(
        frozen.minimum_joint_valid_and_direction_matching_per_nonzero_rho,
        "minimum joint direction recovery per nonzero rho",
    )
    minimum_aggregate_direction = _free_correlation_study_finite_float(
        frozen.minimum_aggregate_direction_wilson_lower,
        "minimum aggregate direction recovery",
    )
    maximum_zero_false_exclusion = _free_correlation_study_finite_float(
        frozen.maximum_rho_zero_unresolved_false_exclusion_upper,
        "maximum unresolved rho-zero false-exclusion upper bound",
    )
    coverage_target = frozen.descriptive_interval_coverage_target
    coverage_target isa Tuple && length(coverage_target) == 2 ||
        throw(ArgumentError(
            "descriptive interval-coverage target must be a two-element Tuple",
        ))
    coverage_target_lower = _free_correlation_study_finite_float(
        coverage_target[1],
        "descriptive coverage lower target",
    )
    coverage_target_upper = _free_correlation_study_finite_float(
        coverage_target[2],
        "descriptive coverage upper target",
    )
    0 <= coverage_target_lower <= coverage_target_upper <= 1 ||
        throw(ArgumentError("coverage targets must lie in [0, 1]"))
    all(value -> 0 <= value <= 1, (
        minimum_joint_coverage,
        minimum_aggregate_coverage,
        minimum_joint_direction,
        minimum_aggregate_direction,
        maximum_zero_false_exclusion,
    )) || throw(ArgumentError("probability thresholds must lie in [0, 1]"))
    all(value -> value >= 0, (
        maximum_abs_bias_upper,
        maximum_rmse_upper,
        maximum_abs_unpaired_symmetry_upper,
    )) || throw(ArgumentError("error thresholds must be nonnegative"))
    two_sided_z > 0 && one_sided_z > 0 || throw(ArgumentError(
        "normal quantiles must be positive",
    ))

    return (;
        scorer_status = frozen.scorer_status,
        scorer_schema = frozen.scorer_schema,
        aggregate_schema = frozen.aggregate_schema,
        algorithm = frozen.algorithm,
        implementation_change_policy = frozen.implementation_change_policy,
        required_terminal_units_per_rho = required_terminal,
        minimum_diagnostically_valid_units_per_rho = minimum_valid,
        minimum_scientifically_scored_units_per_rho =
            minimum_scientifically_scored,
        two_sided_normal_quantile = two_sided_z,
        one_sided_normal_quantile = one_sided_z,
        maximum_abs_bias_upper,
        maximum_rmse_upper,
        maximum_abs_unpaired_symmetry_upper,
        descriptive_interval_coverage_target = (
            coverage_target_lower,
            coverage_target_upper,
        ),
        overcoverage_is_hard_failure = frozen.overcoverage_is_hard_failure,
        minimum_joint_valid_and_covered_per_rho = minimum_joint_coverage,
        minimum_equal_weight_aggregate_coverage_wilson_lower =
            minimum_aggregate_coverage,
        minimum_joint_valid_and_direction_matching_per_nonzero_rho =
            minimum_joint_direction,
        minimum_aggregate_direction_wilson_lower =
            minimum_aggregate_direction,
        maximum_rho_zero_unresolved_false_exclusion_upper =
            maximum_zero_false_exclusion,
        bias_guard = frozen.bias_guard,
        rmse_guard = frozen.rmse_guard,
        unpaired_symmetry_guard = frozen.unpaired_symmetry_guard,
        interval_crossing_decision_boundary =
            frozen.interval_crossing_decision_boundary,
    )
end

function _free_correlation_study_scoring_blockers(ledger, thresholds)
    blockers = NamedTuple[]
    summary = ledger.summary
    gate = summary.feasibility_gate
    if thresholds.scorer_status !==
            :contract_frozen_scorer_implemented_and_validated
        push!(blockers, (;
            code = :scorer_contract_not_implemented_and_validated,
            phase = :scoring,
            rho_truth = missing,
            observed = thresholds.scorer_status,
            required = :contract_frozen_scorer_implemented_and_validated,
        ))
    end
    if !gate.decision_available
        push!(blockers, (;
            code = :feasibility_decision_not_available,
            phase = :feasibility,
            rho_truth = missing,
            observed = false,
            required = true,
        ))
    elseif !gate.passed
        push!(blockers, (;
            code = :feasibility_gate_not_passed,
            phase = :feasibility,
            rho_truth = missing,
            observed = false,
            required = true,
        ))
    end
    summary.protocol_integrity_passed || push!(blockers, (;
        code = :study_protocol_integrity_failed,
        phase = :evaluation,
        rho_truth = missing,
        observed = summary.n_protocol_violations,
        required = 0,
    ))

    for rho in ledger.plan.rho_grid
        rows = [row for row in ledger.unit_rows
            if row.unit.phase === :evaluation && row.unit.rho_truth == rho]
        n_terminal = count(row -> !ismissing(row.result), rows)
        n_authorized = count(row -> !ismissing(row.result) &&
            !ismissing(row.authorization_artifact) &&
            isempty(row.protocol_violations), rows)
        if length(rows) != thresholds.required_terminal_units_per_rho
            push!(blockers, (;
                code = :evaluation_roster_denominator_mismatch,
                phase = :evaluation,
                rho_truth = rho,
                observed = length(rows),
                required = thresholds.required_terminal_units_per_rho,
            ))
        end
        if n_terminal != thresholds.required_terminal_units_per_rho
            push!(blockers, (;
                code = :evaluation_units_not_all_terminal,
                phase = :evaluation,
                rho_truth = rho,
                observed = n_terminal,
                required = thresholds.required_terminal_units_per_rho,
            ))
        end
        if n_authorized != n_terminal
            push!(blockers, (;
                code = :evaluation_terminal_authorization_incomplete,
                phase = :evaluation,
                rho_truth = rho,
                observed = n_authorized,
                required = n_terminal,
            ))
        end
    end
    return Tuple(blockers)
end

function _free_correlation_study_source_ledger_sha256(ledger)
    ordered_rows = Tuple((;
        unit_id = row.unit.unit_id,
        application_index = row.application_index,
        unit_result_sha256 = ismissing(row.result) ? missing :
            artifact_content_hash(row.result),
        authorization_decision_fingerprint =
            ismissing(row.authorization_artifact) ? missing :
            row.authorization_artifact.decision_fingerprint,
        protocol_violations = row.protocol_violations,
    ) for row in ledger.unit_rows)
    return artifact_content_hash((;
        schema = ledger.schema,
        plan_id = ledger.plan_id,
        plan_fingerprint = ledger.plan_fingerprint,
        ordered_rows,
        projection = :validated_compact_scoring_source_v1,
    ))
end

function _free_correlation_study_exact_rational(value::Float64)
    isfinite(value) || throw(ArgumentError(
        "exact scoring arithmetic requires finite Float64 values",
    ))
    bits = reinterpret(UInt64, value)
    negative = !iszero(bits >> 63)
    exponent_bits = Int((bits >> 52) & UInt64(0x07ff))
    fraction_bits = bits & UInt64(0x000f_ffff_ffff_ffff)
    if iszero(exponent_bits) && iszero(fraction_bits)
        return zero(Rational{BigInt})
    end
    mantissa, exponent = if iszero(exponent_bits)
        BigInt(fraction_bits), -1074
    else
        BigInt((UInt64(1) << 52) | fraction_bits),
        exponent_bits - 1023 - 52
    end
    numerator_value = exponent >= 0 ? mantissa << exponent : mantissa
    denominator_value = exponent >= 0 ? BigInt(1) : BigInt(1) << -exponent
    negative && (numerator_value = -numerator_value)
    return numerator_value // denominator_value
end

function _free_correlation_study_rational_record(value::Rational{BigInt})
    return (;
        numerator = string(numerator(value)),
        denominator = string(denominator(value)),
    )
end

function _free_correlation_study_rational_from_record(record)
    record isa NamedTuple &&
        propertynames(record) == (:numerator, :denominator) ||
        throw(ArgumentError("exact rational record has invalid fields"))
    record.numerator isa AbstractString &&
        record.denominator isa AbstractString || throw(ArgumentError(
        "exact rational record components must be strings",
    ))
    numerator_value = try
        parse(BigInt, record.numerator)
    catch
        throw(ArgumentError("exact rational numerator is invalid"))
    end
    denominator_value = try
        parse(BigInt, record.denominator)
    catch
        throw(ArgumentError("exact rational denominator is invalid"))
    end
    denominator_value > 0 || throw(ArgumentError(
        "exact rational denominator must be positive",
    ))
    return numerator_value // denominator_value
end

function _free_correlation_study_directed_rational_float64(
        value::Rational{BigInt},
        direction::Symbol)
    direction in (:down, :up) || throw(ArgumentError(
        "directed Float64 conversion requires :down or :up",
    ))
    candidate = Float64(value)
    isfinite(candidate) || throw(ArgumentError(
        "exact rational is outside finite Float64 range",
    ))
    if direction === :up
        while _free_correlation_study_exact_rational(candidate) < value
            candidate = nextfloat(candidate)
            isfinite(candidate) || throw(ArgumentError(
                "directed upper Float64 bound overflowed",
            ))
        end
        while true
            previous = prevfloat(candidate)
            isfinite(previous) || break
            _free_correlation_study_exact_rational(previous) >= value || break
            candidate = previous
        end
    else
        while _free_correlation_study_exact_rational(candidate) > value
            candidate = prevfloat(candidate)
            isfinite(candidate) || throw(ArgumentError(
                "directed lower Float64 bound overflowed",
            ))
        end
        while true
            following = nextfloat(candidate)
            isfinite(following) || break
            _free_correlation_study_exact_rational(following) <= value || break
            candidate = following
        end
    end
    return candidate
end

function _free_correlation_study_directed_rational_sqrt_float64(
        value::Rational{BigInt},
        direction::Symbol)
    value >= 0 || throw(ArgumentError(
        "directed square root requires a nonnegative rational",
    ))
    direction in (:down, :up) || throw(ArgumentError(
        "directed square root requires :down or :up",
    ))
    iszero(value) && return 0.0
    candidate = setprecision(BigFloat, 256) do
        Float64(sqrt(
            BigFloat(numerator(value)) / BigFloat(denominator(value)),
        ))
    end
    isfinite(candidate) && candidate >= 0 || throw(ArgumentError(
        "directed square-root approximation is invalid",
    ))
    candidate_square() =
        _free_correlation_study_exact_rational(candidate)^2
    if direction === :up
        while candidate_square() < value
            candidate = nextfloat(candidate)
        end
        while true
            previous = prevfloat(candidate)
            previous >= 0 || break
            _free_correlation_study_exact_rational(previous)^2 >= value || break
            candidate = previous
        end
    else
        while candidate_square() > value
            candidate = prevfloat(candidate)
        end
        while true
            following = nextfloat(candidate)
            isfinite(following) || break
            _free_correlation_study_exact_rational(following)^2 <= value || break
            candidate = following
        end
    end
    return candidate
end

function _free_correlation_study_exact_sufficient_statistics(
        values::Vector{Float64},
        n_planned::Int,
        support_lower::Float64,
        support_upper::Float64)
    n_planned >= 1 || throw(ArgumentError(
        "endpoint-imputed MCSE requires n_planned >= 1",
    ))
    length(values) <= n_planned || throw(ArgumentError(
        "endpoint-imputed MCSE observed values exceed n_planned",
    ))
    isfinite(support_lower) && isfinite(support_upper) &&
        support_lower <= support_upper || throw(ArgumentError(
        "endpoint-imputed MCSE support must be finite and ordered",
    ))
    all(value -> isfinite(value) &&
        support_lower <= value <= support_upper, values) ||
        throw(ArgumentError(
            "endpoint-imputed MCSE observed values must be finite and inside support",
        ))
    exact_values = _free_correlation_study_exact_rational.(values)
    exact_zero = zero(Rational{BigInt})
    return (;
        n_planned,
        n_observed = length(values),
        n_unresolved = n_planned - length(values),
        observed_sum = sum(exact_values; init = exact_zero),
        observed_sum_of_squares =
            sum(abs2, exact_values; init = exact_zero),
        support = (;
            lower = _free_correlation_study_exact_rational(support_lower),
            upper = _free_correlation_study_exact_rational(support_upper),
        ),
    )
end

function _free_correlation_study_exact_statistics_record(statistics)
    return (;
        schema = :exact_float64_rational_sufficient_statistics_v1,
        n_planned = statistics.n_planned,
        n_observed = statistics.n_observed,
        n_unresolved = statistics.n_unresolved,
        observed_sum = _free_correlation_study_rational_record(
            statistics.observed_sum,
        ),
        observed_sum_of_squares = _free_correlation_study_rational_record(
            statistics.observed_sum_of_squares,
        ),
        support = (;
            lower = _free_correlation_study_rational_record(
                statistics.support.lower,
            ),
            upper = _free_correlation_study_rational_record(
                statistics.support.upper,
            ),
        ),
    )
end

function _free_correlation_study_exact_statistics_from_record(record)
    record isa NamedTuple && propertynames(record) == (
        :schema,
        :n_planned,
        :n_observed,
        :n_unresolved,
        :observed_sum,
        :observed_sum_of_squares,
        :support,
    ) || throw(ArgumentError(
        "exact sufficient-statistics record has invalid fields",
    ))
    record.schema === :exact_float64_rational_sufficient_statistics_v1 ||
        throw(ArgumentError("exact sufficient-statistics schema is invalid"))
    record.n_planned isa Int && record.n_planned >= 1 ||
        throw(ArgumentError("exact n_planned must be a positive Int"))
    record.n_observed isa Int && record.n_observed >= 0 ||
        throw(ArgumentError("exact n_observed must be a nonnegative Int"))
    record.n_unresolved isa Int && record.n_unresolved >= 0 ||
        throw(ArgumentError("exact n_unresolved must be a nonnegative Int"))
    record.n_observed + record.n_unresolved == record.n_planned ||
        throw(ArgumentError("exact sufficient-statistics counts are inconsistent"))
    record.support isa NamedTuple &&
        propertynames(record.support) == (:lower, :upper) ||
        throw(ArgumentError("exact sufficient-statistics support is invalid"))
    statistics = (;
        n_planned = record.n_planned,
        n_observed = record.n_observed,
        n_unresolved = record.n_unresolved,
        observed_sum = _free_correlation_study_rational_from_record(
            record.observed_sum,
        ),
        observed_sum_of_squares =
            _free_correlation_study_rational_from_record(
                record.observed_sum_of_squares,
            ),
        support = (;
            lower = _free_correlation_study_rational_from_record(
                record.support.lower,
            ),
            upper = _free_correlation_study_rational_from_record(
                record.support.upper,
            ),
        ),
    )
    statistics.support.lower <= statistics.support.upper ||
        throw(ArgumentError("exact sufficient-statistics support is unordered"))
    statistics.observed_sum_of_squares >= 0 || throw(ArgumentError(
        "exact observed sum of squares must be nonnegative",
    ))
    n_observed_exact = BigInt(statistics.n_observed)
    n_observed_exact * statistics.support.lower <=
        statistics.observed_sum <=
        n_observed_exact * statistics.support.upper || throw(ArgumentError(
        "exact observed sum is outside the declared support",
    ))
    n_observed_exact * statistics.observed_sum_of_squares >=
        statistics.observed_sum^2 || throw(ArgumentError(
        "exact observed moments imply a negative variance",
    ))
    return statistics
end

function _free_correlation_study_endpoint_candidates(statistics)
    n_planned = statistics.n_planned
    n_unresolved = statistics.n_unresolved
    rows = NamedTuple[]
    for n_upper in 0:n_unresolved
        n_lower = n_unresolved - n_upper
        total_sum = statistics.observed_sum +
            n_lower * statistics.support.lower +
            n_upper * statistics.support.upper
        total_sum_of_squares = statistics.observed_sum_of_squares +
            n_lower * statistics.support.lower^2 +
            n_upper * statistics.support.upper^2
        mean = total_sum / n_planned
        standard_error_squared = if n_planned == 1
            nothing
        else
            variance_numerator = n_planned * total_sum_of_squares -
                total_sum^2
            variance_numerator >= 0 || throw(ArgumentError(
                "exact endpoint-imputed variance became negative",
            ))
            variance_numerator /
                (BigInt(n_planned)^2 * BigInt(n_planned - 1))
        end
        push!(rows, (;
            n_lower,
            n_upper,
            mean,
            standard_error_squared,
        ))
    end
    return Tuple(rows)
end

function _free_correlation_study_exact_mean_bounds(statistics)
    n_planned_exact = BigInt(statistics.n_planned)
    n_unresolved_exact = BigInt(statistics.n_unresolved)
    return (;
        lower = (statistics.observed_sum +
            n_unresolved_exact * statistics.support.lower) /
            n_planned_exact,
        upper = (statistics.observed_sum +
            n_unresolved_exact * statistics.support.upper) /
            n_planned_exact,
    )
end

function _free_correlation_study_endpoint_imputed_mcse_upper(
        values::Vector{Float64},
        n_planned::Int,
        support_lower::Float64,
        support_upper::Float64,
        z::Float64;
        objective::Symbol)
    n_planned >= 1 || throw(ArgumentError(
        "endpoint-imputed MCSE requires n_planned >= 1",
    ))
    length(values) <= n_planned || throw(ArgumentError(
        "endpoint-imputed MCSE observed values exceed n_planned",
    ))
    isfinite(z) && z > 0 || throw(ArgumentError(
        "endpoint-imputed MCSE z must be finite and positive",
    ))
    isfinite(support_lower) && isfinite(support_upper) &&
        support_lower <= support_upper || throw(ArgumentError(
        "endpoint-imputed MCSE support must be finite and ordered",
    ))
    all(value -> isfinite(value) &&
        support_lower <= value <= support_upper, values) ||
        throw(ArgumentError(
            "endpoint-imputed MCSE observed values must be finite and inside support",
        ))
    objective in (:absolute_mean, :mean) || throw(ArgumentError(
        "endpoint-imputed MCSE objective is unsupported",
    ))
    statistics = _free_correlation_study_exact_sufficient_statistics(
        values,
        n_planned,
        support_lower,
        support_upper,
    )
    candidates = _free_correlation_study_endpoint_candidates(statistics)
    z_exact = _free_correlation_study_exact_rational(z)
    selected = nothing
    selected_standard_error = Inf
    selected_objective_exact = missing
    upper = -Inf
    for candidate in candidates
        if candidate.standard_error_squared === nothing
            standard_error = Inf
            objective_exact = missing
            candidate_upper = Inf
        else
            standard_error =
            _free_correlation_study_directed_rational_sqrt_float64(
                candidate.standard_error_squared,
                :up,
            )
            objective_exact =
                (objective === :absolute_mean ? abs(candidate.mean) :
                    candidate.mean) +
                z_exact *
                    _free_correlation_study_exact_rational(standard_error)
            candidate_upper =
                _free_correlation_study_directed_rational_float64(
                    objective_exact,
                    :up,
                )
        end
        if selected === nothing || candidate_upper > upper
            selected = candidate
            selected_standard_error = standard_error
            selected_objective_exact = objective_exact
            upper = candidate_upper
        end
    end
    n_unresolved = n_planned - length(values)
    return (;
        method =
            :exact_rational_support_endpoint_enumeration_full_planned_denominator_mcse,
        mathematical_basis = :convex_objective_maximized_over_hyperrectangle_vertices,
        arithmetic =
            :float64_exact_rational_moments_and_directed_float64_upper,
        objective,
        n_planned,
        n_observed = length(values),
        n_unresolved,
        support = (; lower = support_lower, upper = support_upper),
        z,
        endpoint_configurations_evaluated = length(candidates),
        maximizing_endpoint_counts = (;
            lower = selected.n_lower,
            upper = selected.n_upper,
        ),
        imputed_mean_at_maximum = Float64(selected.mean),
        imputed_mean_exact =
            _free_correlation_study_rational_record(selected.mean),
        standard_error_squared_exact = selected.standard_error_squared ===
            nothing ? missing : _free_correlation_study_rational_record(
                selected.standard_error_squared,
            ),
        standard_error_at_maximum = selected_standard_error,
        objective_rational_upper = ismissing(selected_objective_exact) ?
            missing : _free_correlation_study_rational_record(
                selected_objective_exact,
            ),
        upper,
        numerical_policy = isfinite(upper) ?
            :smallest_float64_not_below_exact_rational_upper_using_exact_comparison :
            :single_planned_unit_mcse_is_infinite,
    )
end

function _free_correlation_study_continuous_bounds(
        errors::Vector{Float64},
        rho::Float64,
        n_planned::Int)
    n_planned >= 1 || throw(ArgumentError(
        "continuous unresolved bounds require n_planned >= 1",
    ))
    length(errors) <= n_planned || throw(ArgumentError(
        "continuous unresolved bounds require n_valid <= n_planned",
    ))
    isfinite(rho) && -1 < rho < 1 || throw(ArgumentError(
        "continuous unresolved bounds require finite rho in (-1, 1)",
    ))
    minimum_error = -1.0 - rho
    maximum_error = 1.0 - rho
    all(error -> isfinite(error) &&
        minimum_error <= error <= maximum_error, errors) ||
        throw(ArgumentError(
            "continuous unresolved errors must be finite and inside posterior-median support",
        ))
    n_valid = length(errors)
    n_unresolved = n_planned - n_valid
    error_sum = sum(errors; init = 0.0)
    absolute_error_sum = sum(abs, errors; init = 0.0)
    squared_error_sum = sum(abs2, errors; init = 0.0)
    maximum_absolute_error = 1.0 + abs(rho)
    raw_bias_lower =
        (error_sum + n_unresolved * minimum_error) / n_planned
    raw_bias_upper =
        (error_sum + n_unresolved * maximum_error) / n_planned
    raw_mae_lower = absolute_error_sum / n_planned
    raw_mae_upper = (absolute_error_sum +
        n_unresolved * maximum_absolute_error) / n_planned
    raw_mse_lower = squared_error_sum / n_planned
    raw_mse_upper = (squared_error_sum +
        n_unresolved * maximum_absolute_error^2) / n_planned
    if n_unresolved > 0
        exact_statistics =
            _free_correlation_study_exact_sufficient_statistics(
                errors,
                n_planned,
                minimum_error,
                maximum_error,
            )
        n_exact = BigInt(n_planned)
        unresolved_exact = BigInt(n_unresolved)
        absolute_error_sum_exact = sum(
            abs(_free_correlation_study_exact_rational(error))
            for error in errors;
            init = zero(Rational{BigInt}),
        )
        maximum_absolute_error_exact = max(
            abs(exact_statistics.support.lower),
            abs(exact_statistics.support.upper),
        )
        bias_lower_exact = (exact_statistics.observed_sum +
            unresolved_exact * exact_statistics.support.lower) / n_exact
        bias_upper_exact = (exact_statistics.observed_sum +
            unresolved_exact * exact_statistics.support.upper) / n_exact
        mae_lower_exact = absolute_error_sum_exact / n_exact
        mae_upper_exact = (absolute_error_sum_exact +
            unresolved_exact * maximum_absolute_error_exact) / n_exact
        mse_lower_exact =
            exact_statistics.observed_sum_of_squares / n_exact
        mse_upper_exact = (exact_statistics.observed_sum_of_squares +
            unresolved_exact * maximum_absolute_error_exact^2) / n_exact
        bias_lower = _free_correlation_study_directed_rational_float64(
            bias_lower_exact,
            :down,
        )
        bias_upper = _free_correlation_study_directed_rational_float64(
            bias_upper_exact,
            :up,
        )
        mae_lower = _free_correlation_study_directed_rational_float64(
            mae_lower_exact,
            :down,
        )
        mae_upper = _free_correlation_study_directed_rational_float64(
            mae_upper_exact,
            :up,
        )
        mse_lower = _free_correlation_study_directed_rational_float64(
            mse_lower_exact,
            :down,
        )
        mse_upper = _free_correlation_study_directed_rational_float64(
            mse_upper_exact,
            :up,
        )
        rmse_lower =
            _free_correlation_study_directed_rational_sqrt_float64(
                mse_lower_exact,
                :down,
            )
        rmse_upper =
            _free_correlation_study_directed_rational_sqrt_float64(
                mse_upper_exact,
                :up,
            )
    else
        bias_lower = raw_bias_lower
        bias_upper = raw_bias_upper
        mae_lower = raw_mae_lower
        mae_upper = raw_mae_upper
        mse_lower = raw_mse_lower
        mse_upper = raw_mse_upper
        rmse_lower = sqrt(max(0.0, mse_lower))
        rmse_upper = sqrt(max(0.0, mse_upper))
    end
    return (;
        support_assumption =
            :posterior_median_closed_envelope_minus_one_to_one,
        numerical_policy = n_unresolved > 0 ?
            :exact_rational_bounds_then_directed_float64_conversion :
            :exact_observed_formula,
        n_unresolved,
        bias = (; lower = bias_lower, upper = bias_upper),
        mean_absolute_error = (; lower = mae_lower, upper = mae_upper),
        mean_squared_error = (; lower = mse_lower, upper = mse_upper),
        root_mean_squared_error = (;
            lower = rmse_lower,
            upper = rmse_upper,
        ),
    )
end

function _free_correlation_study_absolute_interval_upper(bounds)
    lower = _free_correlation_study_finite_float(
        bounds.lower,
        "continuous unresolved lower bound",
    )
    upper = _free_correlation_study_finite_float(
        bounds.upper,
        "continuous unresolved upper bound",
    )
    lower <= upper || throw(ArgumentError(
        "continuous unresolved bounds must be ordered",
    ))
    return max(abs(lower), abs(upper))
end

function _free_correlation_study_absolute_interval_minimum(bounds)
    lower = _free_correlation_study_finite_float(
        bounds.lower,
        "continuous unresolved lower bound",
    )
    upper = _free_correlation_study_finite_float(
        bounds.upper,
        "continuous unresolved upper bound",
    )
    lower <= upper || throw(ArgumentError(
        "continuous unresolved bounds must be ordered",
    ))
    return lower <= 0 <= upper ? 0.0 : min(abs(lower), abs(upper))
end

function _free_correlation_study_evaluation_rho_row(
        ledger,
        rho::Float64,
        thresholds)
    selected = [row for row in ledger.unit_rows
        if row.unit.phase === :evaluation && row.unit.rho_truth == rho]
    completed = [row for row in selected
        if row.result.primary_status === :completed]
    n_planned = length(selected)
    n_terminal = count(row -> !ismissing(row.result), selected)
    n_valid = length(completed)
    n_generation_failed = count(row ->
        row.result.primary_status === :generation_failed, selected)
    n_fit_failed = count(row ->
        row.result.primary_status === :fit_failed, selected)
    n_diagnostic_failed = count(row ->
        row.result.primary_status === :diagnostic_failed, selected)
    n_recovery_scoring_failed = count(row ->
        row.result.primary_status === :recovery_scoring_failed, selected)
    n_failures = n_generation_failed + n_fit_failed + n_diagnostic_failed +
        n_recovery_scoring_failed
    n_diagnostically_valid = n_valid + n_recovery_scoring_failed

    medians = Float64[
        Float64(row.result.scientific_outcome.posterior_median)
        for row in completed
    ]
    errors = Float64[median - rho for median in medians]
    absolute_errors = abs.(errors)
    squared_errors = abs2.(errors)
    mean_bias = _free_correlation_study_arithmetic_mean(errors)
    bias_sample_sd = _free_correlation_study_sample_sd(errors, mean_bias)
    bias_mcse = ismissing(bias_sample_sd) ? missing :
        bias_sample_sd / sqrt(n_valid)
    mean_absolute_error =
        _free_correlation_study_arithmetic_mean(absolute_errors)
    mean_squared_error =
        _free_correlation_study_arithmetic_mean(squared_errors)
    squared_error_sample_sd = _free_correlation_study_sample_sd(
        squared_errors,
        mean_squared_error,
    )
    mean_squared_error_mcse = ismissing(squared_error_sample_sd) ? missing :
        squared_error_sample_sd / sqrt(n_valid)
    root_mean_squared_error = ismissing(mean_squared_error) ? missing :
        sqrt(max(0.0, mean_squared_error))
    bias_uncertainty_upper = ismissing(bias_mcse) ? missing :
        abs(mean_bias) + thresholds.two_sided_normal_quantile * bias_mcse
    mean_squared_error_one_sided_upper =
        ismissing(mean_squared_error_mcse) ? missing :
        mean_squared_error + thresholds.one_sided_normal_quantile *
            mean_squared_error_mcse
    rmse_one_sided_upper = ismissing(mean_squared_error_one_sided_upper) ?
        missing : sqrt(max(0.0, mean_squared_error_one_sided_upper))

    n_covered = count(row ->
        row.result.scientific_outcome.interval_covered, completed)
    coverage = _free_correlation_study_binary_summary(
        n_covered,
        n_valid,
        n_planned,
        thresholds.two_sided_normal_quantile,
    )
    target_lower, target_upper =
        thresholds.descriptive_interval_coverage_target
    coverage_descriptive_status = if ismissing(
            coverage.conditional_rate_among_valid)
        :not_estimable
    elseif coverage.conditional_rate_among_valid < target_lower
        :below_descriptive_target
    elseif coverage.conditional_rate_among_valid > target_upper
        :above_descriptive_target_not_a_hard_failure
    else
        :inside_descriptive_target
    end

    direction_applicable = !iszero(rho)
    direction = if direction_applicable
        n_direction_matches = count(row ->
            row.result.scientific_outcome.direction_matches_truth,
            completed,
        )
        _free_correlation_study_binary_summary(
            n_direction_matches,
            n_valid,
            n_planned,
            thresholds.two_sided_normal_quantile,
        )
    else
        missing
    end
    rho_zero_false_exclusion = if iszero(rho)
        n_false_exclusions = n_valid - n_covered
        false_exclusion = _free_correlation_study_binary_summary(
            n_false_exclusions,
            n_valid,
            n_planned,
            thresholds.two_sided_normal_quantile,
        )
        merge(false_exclusion, (;
            unresolved_false_exclusion_upper =
                false_exclusion.unresolved_bounds.upper,
        ))
    else
        missing
    end
    continuous_unresolved_bounds =
        _free_correlation_study_continuous_bounds(
            errors,
            rho,
            n_planned,
        )
    completed_fraction = n_valid / n_planned
    conditional_pattern_bias_mcse = ismissing(bias_mcse) ? missing :
        completed_fraction * bias_mcse
    conditional_pattern_mean_squared_error_mcse =
        ismissing(mean_squared_error_mcse) ? missing :
        completed_fraction * mean_squared_error_mcse
    minimum_error = -1.0 - rho
    maximum_error = 1.0 - rho
    maximum_absolute_error = 1.0 + abs(rho)
    bias_endpoint_enumeration =
        _free_correlation_study_endpoint_imputed_mcse_upper(
            errors,
            n_planned,
            minimum_error,
            maximum_error,
            thresholds.two_sided_normal_quantile;
            objective = :absolute_mean,
        )
    mean_squared_error_endpoint_enumeration =
        _free_correlation_study_endpoint_imputed_mcse_upper(
            squared_errors,
            n_planned,
            0.0,
            maximum_absolute_error^2,
            thresholds.one_sided_normal_quantile;
            objective = :mean,
        )
    absolute_mean_bias_envelope_upper =
        _free_correlation_study_absolute_interval_upper(
            continuous_unresolved_bounds.bias,
        )
    minimum_absolute_mean_bias =
        _free_correlation_study_absolute_interval_minimum(
            continuous_unresolved_bounds.bias,
        )
    root_mean_squared_error_envelope_plus_mcse_upper =
        ismissing(mean_squared_error_endpoint_enumeration.
            objective_rational_upper) ? Inf :
        _free_correlation_study_directed_rational_sqrt_float64(
            _free_correlation_study_rational_from_record(
                mean_squared_error_endpoint_enumeration.
                    objective_rational_upper,
            ),
            :up,
        )
    continuous_unresolved_worst_case = (;
        method =
            :endpoint_enumerated_full_planned_denominator_mcse_with_exact_rational_arithmetic,
        guard_uses_conditional_completion_pattern_mcse = false,
        completed_fraction,
        conditional_on_realized_completion_pattern = (;
            method = :observed_completion_pattern_scaled_conditional_mcse,
            used_for_guard = false,
            bias_mcse = conditional_pattern_bias_mcse,
            mean_squared_error_mcse =
                conditional_pattern_mean_squared_error_mcse,
        ),
        bias_endpoint_enumeration,
        mean_squared_error_endpoint_enumeration,
        fixed_denominator_bias_mcse =
            bias_endpoint_enumeration.standard_error_at_maximum,
        fixed_denominator_mean_squared_error_mcse =
            mean_squared_error_endpoint_enumeration.
                standard_error_at_maximum,
        minimum_absolute_mean_bias,
        absolute_mean_bias_upper = absolute_mean_bias_envelope_upper,
        absolute_mean_bias_envelope_plus_mcse_upper =
            bias_endpoint_enumeration.upper,
        root_mean_squared_error_upper =
            continuous_unresolved_bounds.root_mean_squared_error.upper,
        root_mean_squared_error_envelope_plus_mcse_upper =
            root_mean_squared_error_envelope_plus_mcse_upper,
    )
    endpoint_mcse_sufficient_statistics =
        _free_correlation_study_exact_statistics_record(
            _free_correlation_study_exact_sufficient_statistics(
                errors,
                n_planned,
                minimum_error,
                maximum_error,
            ),
        )

    return (;
        rho_truth = rho,
        n_planned,
        n_terminal,
        n_valid = n_valid,
        n_diagnostically_valid,
        n_scientifically_scored = n_valid,
        n_scientifically_unresolved = n_failures,
        n_generation_failed,
        n_fit_failed,
        n_diagnostic_failed,
        n_recovery_scoring_failed,
        n_categorized_failures = n_failures,
        diagnostically_valid_rate = n_diagnostically_valid / n_planned,
        scientifically_scored_rate = n_valid / n_planned,
        posterior_median_mean =
            _free_correlation_study_arithmetic_mean(medians),
        mean_bias,
        absolute_mean_bias = ismissing(mean_bias) ? missing : abs(mean_bias),
        bias_sample_sd,
        bias_mcse,
        absolute_mean_bias_uncertainty_upper = bias_uncertainty_upper,
        mean_absolute_error,
        mean_squared_error,
        squared_error_sample_sd,
        mean_squared_error_mcse,
        mean_squared_error_one_sided_upper,
        root_mean_squared_error,
        rmse_one_sided_upper,
        continuous_unresolved_bounds,
        continuous_unresolved_worst_case,
        endpoint_mcse_sufficient_statistics,
        coverage,
        coverage_descriptive_status,
        coverage_over_target_is_hard_failure = false,
        direction_applicable,
        direction,
        rho_zero_false_exclusion,
    )
end

function _free_correlation_study_symmetry_endpoint_imputed_mcse_upper(
        negative_statistics_record,
        positive_statistics_record,
        z::Float64)
    isfinite(z) && z > 0 || throw(ArgumentError(
        "symmetry endpoint-imputed MCSE z must be finite and positive",
    ))
    negative_statistics =
        _free_correlation_study_exact_statistics_from_record(
            negative_statistics_record,
        )
    positive_statistics =
        _free_correlation_study_exact_statistics_from_record(
            positive_statistics_record,
        )
    negative_candidates = _free_correlation_study_endpoint_candidates(
        negative_statistics,
    )
    positive_candidates = _free_correlation_study_endpoint_candidates(
        positive_statistics,
    )
    z_exact = _free_correlation_study_exact_rational(z)
    selected_negative = nothing
    selected_positive = nothing
    selected_contrast = zero(Rational{BigInt})
    selected_standard_error_squared = nothing
    selected_standard_error = Inf
    selected_objective_exact = missing
    upper = -Inf
    for negative in negative_candidates
        for positive in positive_candidates
            contrast = negative.mean + positive.mean
            if negative.standard_error_squared === nothing ||
                    positive.standard_error_squared === nothing
                standard_error_squared = nothing
                standard_error = Inf
                objective_exact = missing
                candidate_upper = Inf
            else
                standard_error_squared =
                    negative.standard_error_squared +
                    positive.standard_error_squared
                standard_error =
                    _free_correlation_study_directed_rational_sqrt_float64(
                        standard_error_squared,
                        :up,
                    )
                objective_exact = abs(contrast) +
                    z_exact *
                        _free_correlation_study_exact_rational(standard_error)
                candidate_upper =
                    _free_correlation_study_directed_rational_float64(
                        objective_exact,
                        :up,
                    )
            end
            if selected_negative === nothing || candidate_upper > upper
                selected_negative = negative
                selected_positive = positive
                selected_contrast = contrast
                selected_standard_error_squared = standard_error_squared
                selected_standard_error = standard_error
                selected_objective_exact = objective_exact
                upper = candidate_upper
            end
        end
    end
    n_unresolved = negative_statistics.n_unresolved +
        positive_statistics.n_unresolved
    return (;
        method =
            :exact_rational_support_endpoint_enumeration_full_planned_denominator_independent_mcse,
        mathematical_basis =
            :convex_objective_maximized_over_two_independent_hyperrectangle_vertex_sets,
        arithmetic =
            :float64_exact_rational_moments_and_directed_float64_upper,
        n_scientifically_unresolved = n_unresolved,
        z,
        endpoint_configurations_evaluated =
            length(negative_candidates) * length(positive_candidates),
        maximizing_endpoint_counts = (;
            negative = (;
                lower = selected_negative.n_lower,
                upper = selected_negative.n_upper,
            ),
            positive = (;
                lower = selected_positive.n_lower,
                upper = selected_positive.n_upper,
            ),
        ),
        imputed_signed_bias_contrast_at_maximum = Float64(selected_contrast),
        imputed_signed_bias_contrast_exact =
            _free_correlation_study_rational_record(selected_contrast),
        independent_standard_error_squared_exact =
            selected_standard_error_squared === nothing ? missing :
            _free_correlation_study_rational_record(
                selected_standard_error_squared,
            ),
        independent_standard_error_at_maximum = selected_standard_error,
        objective_rational_upper = ismissing(selected_objective_exact) ?
            missing : _free_correlation_study_rational_record(
                selected_objective_exact,
            ),
        upper,
        numerical_policy = isfinite(upper) ?
            :smallest_float64_not_below_exact_rational_upper_using_exact_comparison :
            :single_planned_unit_mcse_is_infinite,
    )
end

function _free_correlation_study_unpaired_symmetry_rows(
        per_rho_rows,
        plan,
        thresholds)
    rows = NamedTuple[]
    for pair in plan.recovery_analysis.symmetry_pairs
        negative_rho, positive_rho = pair
        negative = only(row for row in per_rho_rows
            if row.rho_truth == negative_rho)
        positive = only(row for row in per_rho_rows
            if row.rho_truth == positive_rho)
        bias_contrast = if ismissing(negative.mean_bias) ||
                ismissing(positive.mean_bias)
            missing
        else
            negative.mean_bias + positive.mean_bias
        end
        independent_bias_se = if ismissing(negative.bias_mcse) ||
                ismissing(positive.bias_mcse)
            missing
        else
            sqrt(negative.bias_mcse^2 + positive.bias_mcse^2)
        end
        bias_contrast_uncertainty_upper =
            ismissing(independent_bias_se) ? missing :
            abs(bias_contrast) + thresholds.two_sided_normal_quantile *
                independent_bias_se

        negative_joint = negative.coverage.joint_fixed_denominator_rate
        positive_joint = positive.coverage.joint_fixed_denominator_rate
        joint_difference = negative_joint - positive_joint
        joint_difference_se = sqrt(
            negative_joint * (1 - negative_joint) / negative.n_planned +
            positive_joint * (1 - positive_joint) / positive.n_planned,
        )
        negative_conditional =
            negative.coverage.conditional_rate_among_valid
        positive_conditional =
            positive.coverage.conditional_rate_among_valid
        conditional_difference = if ismissing(negative_conditional) ||
                ismissing(positive_conditional)
            missing
        else
            negative_conditional - positive_conditional
        end
        conditional_difference_se = if ismissing(conditional_difference)
            missing
        else
            sqrt(
                negative_conditional * (1 - negative_conditional) /
                    negative.n_scientifically_scored +
                positive_conditional * (1 - positive_conditional) /
                    positive.n_scientifically_scored,
            )
        end
        negative_bounds = negative.coverage.unresolved_bounds
        positive_bounds = positive.coverage.unresolved_bounds
        negative_exact_statistics =
            _free_correlation_study_exact_statistics_from_record(
                negative.endpoint_mcse_sufficient_statistics,
            )
        positive_exact_statistics =
            _free_correlation_study_exact_statistics_from_record(
                positive.endpoint_mcse_sufficient_statistics,
            )
        negative_exact_bias_bounds =
            _free_correlation_study_exact_mean_bounds(
                negative_exact_statistics,
            )
        positive_exact_bias_bounds =
            _free_correlation_study_exact_mean_bounds(
                positive_exact_statistics,
            )
        unresolved_bias_contrast_lower_exact =
            negative_exact_bias_bounds.lower +
            positive_exact_bias_bounds.lower
        unresolved_bias_contrast_upper_exact =
            negative_exact_bias_bounds.upper +
            positive_exact_bias_bounds.upper
        n_scientifically_unresolved =
            negative.n_scientifically_unresolved +
            positive.n_scientifically_unresolved
        unresolved_bias_contrast_bounds = (;
            lower = _free_correlation_study_directed_rational_float64(
                unresolved_bias_contrast_lower_exact,
                :down,
            ),
            upper = _free_correlation_study_directed_rational_float64(
                unresolved_bias_contrast_upper_exact,
                :up,
            ),
        )
        unresolved_absolute_bias_contrast_upper =
            _free_correlation_study_absolute_interval_upper(
                unresolved_bias_contrast_bounds,
            )
        minimum_absolute_bias_contrast =
            _free_correlation_study_absolute_interval_minimum(
                unresolved_bias_contrast_bounds,
            )
        endpoint_enumeration =
            _free_correlation_study_symmetry_endpoint_imputed_mcse_upper(
                negative.endpoint_mcse_sufficient_statistics,
                positive.endpoint_mcse_sufficient_statistics,
                thresholds.two_sided_normal_quantile,
            )
        fixed_denominator_independent_bias_se =
            endpoint_enumeration.independent_standard_error_at_maximum
        unresolved_absolute_bias_contrast_plus_mcse_upper =
            endpoint_enumeration.upper

        push!(rows, (;
            rho_pair = pair,
            method = :unpaired_independent_seed_namespaces,
            replication_numbers_are_not_pairs = true,
            signed_bias_contrast = bias_contrast,
            absolute_signed_bias_contrast = ismissing(bias_contrast) ?
                missing : abs(bias_contrast),
            independent_bias_standard_error = independent_bias_se,
            absolute_signed_bias_contrast_uncertainty_upper =
                bias_contrast_uncertainty_upper,
            n_scientifically_unresolved,
            signed_bias_contrast_unresolved_bounds =
                unresolved_bias_contrast_bounds,
            signed_bias_contrast_unresolved_bounds_exact = (;
                lower = _free_correlation_study_rational_record(
                    unresolved_bias_contrast_lower_exact,
                ),
                upper = _free_correlation_study_rational_record(
                    unresolved_bias_contrast_upper_exact,
                ),
            ),
            signed_bias_contrast_bounds_numerical_policy =
                :exact_rational_bounds_then_directed_float64_conversion,
            minimum_absolute_signed_bias_contrast =
                minimum_absolute_bias_contrast,
            absolute_signed_bias_contrast_unresolved_upper =
                unresolved_absolute_bias_contrast_upper,
            endpoint_imputed_full_denominator_mcse = endpoint_enumeration,
            fixed_denominator_independent_bias_standard_error =
                fixed_denominator_independent_bias_se,
            absolute_signed_bias_contrast_unresolved_plus_mcse_upper =
                unresolved_absolute_bias_contrast_plus_mcse_upper,
            joint_fixed_denominator_coverage_difference = joint_difference,
            joint_coverage_difference_independent_standard_error =
                joint_difference_se,
            joint_coverage_difference_two_sided_normal_interval = (;
                lower = max(-1.0, joint_difference -
                    thresholds.two_sided_normal_quantile *
                    joint_difference_se),
                upper = min(1.0, joint_difference +
                    thresholds.two_sided_normal_quantile *
                    joint_difference_se),
            ),
            joint_coverage_difference_unresolved_bounds = (;
                lower = negative_bounds.lower - positive_bounds.upper,
                upper = negative_bounds.upper - positive_bounds.lower,
            ),
            conditional_coverage_difference_among_valid =
                conditional_difference,
            conditional_coverage_difference_independent_standard_error =
                conditional_difference_se,
        ))
    end
    return Tuple(rows)
end

function _free_correlation_study_overall_metrics(
        per_rho_rows,
        thresholds)
    n_coverage_planned = sum(row.n_planned for row in per_rho_rows; init = 0)
    n_coverage_valid = sum(row.n_scientifically_scored for row in per_rho_rows;
        init = 0)
    n_covered = sum(row.coverage.n_successes for row in per_rho_rows;
        init = 0)
    coverage = _free_correlation_study_binary_summary(
        n_covered,
        n_coverage_valid,
        n_coverage_planned,
        thresholds.two_sided_normal_quantile,
    )
    coverage_one_sided = _free_correlation_study_wilson(
        n_covered,
        n_coverage_planned,
        thresholds.one_sided_normal_quantile;
        interval_kind = :one_sided_95_lower,
    )
    equal_weight_coverage = sum(
        row.coverage.joint_fixed_denominator_rate for row in per_rho_rows;
        init = 0.0,
    ) / length(per_rho_rows)

    nonzero_rows = [row for row in per_rho_rows if row.direction_applicable]
    n_direction_planned = sum(row.n_planned for row in nonzero_rows; init = 0)
    n_direction_valid = sum(row.n_scientifically_scored for row in nonzero_rows;
        init = 0)
    n_direction_matches = sum(row.direction.n_successes for row in nonzero_rows;
        init = 0)
    direction = _free_correlation_study_binary_summary(
        n_direction_matches,
        n_direction_valid,
        n_direction_planned,
        thresholds.two_sided_normal_quantile,
    )
    direction_one_sided = _free_correlation_study_wilson(
        n_direction_matches,
        n_direction_planned,
        thresholds.one_sided_normal_quantile;
        interval_kind = :one_sided_95_lower,
    )
    equal_weight_direction = sum(
        row.direction.joint_fixed_denominator_rate for row in nonzero_rows;
        init = 0.0,
    ) / length(nonzero_rows)
    zero_row = only(row for row in per_rho_rows if iszero(row.rho_truth))

    return (;
        weighting = :equal_rho_weight_fixed_planned_denominators,
        coverage = merge(coverage, (;
            equal_weight_joint_fixed_denominator_rate = equal_weight_coverage,
            joint_fixed_denominator_one_sided_wilson = coverage_one_sided,
            one_sided_wilson_lower = coverage_one_sided.lower,
        )),
        direction_nonzero_rho = merge(direction, (;
            equal_weight_joint_fixed_denominator_rate = equal_weight_direction,
            joint_fixed_denominator_one_sided_wilson = direction_one_sided,
            one_sided_wilson_lower = direction_one_sided.lower,
        )),
        rho_zero_false_exclusion = zero_row.rho_zero_false_exclusion,
    )
end

"""
    _free_correlation_study_evaluation_aggregate(ledger)

Compute the quarantined free-correlation study's deterministic evaluation
summary. The input ledger is validated in full. A valid but incomplete,
unauthorized, or feasibility-blocked ledger returns a blocked aggregate instead
of throwing; malformed or modified artifacts still raise `ArgumentError`.
Scientific metrics are computed only when every planned evaluation unit is in a
terminal state and bound to valid feasibility authorization.
"""
function _free_correlation_study_evaluation_aggregate(ledger)
    checked = _validate_free_correlation_study_ledger(ledger)
    thresholds = _free_correlation_study_scoring_thresholds(checked.plan)
    blockers = _free_correlation_study_scoring_blockers(checked, thresholds)
    source_ledger_sha256 =
        _free_correlation_study_source_ledger_sha256(checked)
    if !isempty(blockers)
        payload = (;
            schema = _FREE_CORRELATION_STUDY_EVALUATION_AGGREGATE_SCHEMA,
            object = :mgmfrm_free_latent_correlation_2d_study_evaluation_aggregate,
            status = :evaluation_aggregate_blocked,
            ready = false,
            plan_id = checked.plan_id,
            plan_fingerprint = checked.plan_fingerprint,
            source_ledger_sha256,
            thresholds,
            blockers,
            per_rho_rows = (),
            overall = missing,
            unpaired_symmetry_rows = (),
            public_fit = false,
            cache_enabled = false,
            promotion_effect = :none,
            recovery_claimed = false,
            replicated_recovery_verified = false,
        )
        return merge(payload, (;
            aggregate_fingerprint = artifact_content_hash(payload),
        ))
    end

    per_rho_rows = Tuple(
        _free_correlation_study_evaluation_rho_row(
            checked,
            Float64(rho),
            thresholds,
        ) for rho in checked.plan.rho_grid
    )
    overall = _free_correlation_study_overall_metrics(
        per_rho_rows,
        thresholds,
    )
    symmetry_rows = _free_correlation_study_unpaired_symmetry_rows(
        per_rho_rows,
        checked.plan,
        thresholds,
    )
    payload = (;
        schema = _FREE_CORRELATION_STUDY_EVALUATION_AGGREGATE_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_evaluation_aggregate,
        status = :evaluation_aggregate_ready,
        ready = true,
        plan_id = checked.plan_id,
        plan_fingerprint = checked.plan_fingerprint,
        source_ledger_sha256,
        thresholds,
        blockers = (),
        per_rho_rows,
        overall,
        unpaired_symmetry_rows = symmetry_rows,
        public_fit = false,
        cache_enabled = false,
        promotion_effect = :none,
        recovery_claimed = false,
        replicated_recovery_verified = false,
    )
    return merge(payload, (;
        aggregate_fingerprint = artifact_content_hash(payload),
    ))
end


function _free_correlation_study_decision_rows(aggregate)
    thresholds = aggregate.thresholds
    hard_failures = NamedTuple[]
    uncertainty_blockers = NamedTuple[]

    for row in aggregate.per_rho_rows
        coordinate = row.rho_truth
        if row.n_diagnostically_valid <
                thresholds.minimum_diagnostically_valid_units_per_rho
            push!(hard_failures, (;
                code = :insufficient_diagnostically_valid_units,
                scope = :rho,
                coordinate,
                estimate = row.n_diagnostically_valid,
                threshold =
                    thresholds.minimum_diagnostically_valid_units_per_rho,
                criterion = :at_least,
            ))
        end
        if row.n_scientifically_scored <
                thresholds.minimum_scientifically_scored_units_per_rho
            push!(hard_failures, (;
                code = :insufficient_scientifically_scored_units,
                scope = :rho,
                coordinate,
                estimate = row.n_scientifically_scored,
                threshold =
                    thresholds.minimum_scientifically_scored_units_per_rho,
                criterion = :at_least,
            ))
        end
        if row.n_scientifically_unresolved > 0
            if row.continuous_unresolved_worst_case.
                    minimum_absolute_mean_bias >
                    thresholds.maximum_abs_bias_upper
                push!(hard_failures, (;
                    code =
                        :absolute_mean_bias_unresolved_envelope_lower_exceeds_limit,
                    scope = :rho,
                    coordinate,
                    estimate = row.continuous_unresolved_worst_case.
                        minimum_absolute_mean_bias,
                    threshold = thresholds.maximum_abs_bias_upper,
                    criterion = :lower_at_most,
                ))
            elseif (ismissing(row.continuous_unresolved_worst_case.
                    absolute_mean_bias_envelope_plus_mcse_upper) ||
                row.continuous_unresolved_worst_case.
                    absolute_mean_bias_envelope_plus_mcse_upper >
                    thresholds.maximum_abs_bias_upper)
            push!(uncertainty_blockers, (;
                code = :absolute_mean_bias_unresolved_envelope_crosses_limit,
                scope = :rho,
                coordinate,
                point_estimate = row.absolute_mean_bias,
                uncertainty_bound = row.continuous_unresolved_worst_case.
                    absolute_mean_bias_envelope_plus_mcse_upper,
                n_unresolved = row.n_scientifically_unresolved,
                threshold = thresholds.maximum_abs_bias_upper,
                criterion = :upper_at_most,
            ))
            end
        elseif !ismissing(row.absolute_mean_bias) &&
                row.absolute_mean_bias > thresholds.maximum_abs_bias_upper
            push!(hard_failures, (;
                code = :absolute_mean_bias_exceeds_limit,
                scope = :rho,
                coordinate,
                estimate = row.absolute_mean_bias,
                threshold = thresholds.maximum_abs_bias_upper,
                criterion = :at_most,
            ))
        elseif ismissing(row.absolute_mean_bias_uncertainty_upper) ||
                row.absolute_mean_bias_uncertainty_upper >
                    thresholds.maximum_abs_bias_upper
            push!(uncertainty_blockers, (;
                code = :absolute_mean_bias_uncertainty_crosses_limit,
                scope = :rho,
                coordinate,
                point_estimate = row.absolute_mean_bias,
                uncertainty_bound =
                    row.absolute_mean_bias_uncertainty_upper,
                threshold = thresholds.maximum_abs_bias_upper,
                criterion = :upper_at_most,
            ))
        end
        if row.n_scientifically_unresolved > 0
            if row.continuous_unresolved_bounds.root_mean_squared_error.lower >
                    thresholds.maximum_rmse_upper
                push!(hard_failures, (;
                    code = :rmse_unresolved_envelope_lower_exceeds_limit,
                    scope = :rho,
                    coordinate,
                    estimate = row.continuous_unresolved_bounds.
                        root_mean_squared_error.lower,
                    threshold = thresholds.maximum_rmse_upper,
                    criterion = :lower_at_most,
                ))
            elseif (ismissing(row.continuous_unresolved_worst_case.
                    root_mean_squared_error_envelope_plus_mcse_upper) ||
                row.continuous_unresolved_worst_case.
                    root_mean_squared_error_envelope_plus_mcse_upper >
                    thresholds.maximum_rmse_upper)
            push!(uncertainty_blockers, (;
                code = :rmse_unresolved_envelope_crosses_limit,
                scope = :rho,
                coordinate,
                point_estimate = row.root_mean_squared_error,
                uncertainty_bound = row.continuous_unresolved_worst_case.
                    root_mean_squared_error_envelope_plus_mcse_upper,
                n_unresolved = row.n_scientifically_unresolved,
                threshold = thresholds.maximum_rmse_upper,
                criterion = :upper_at_most,
            ))
            end
        elseif !ismissing(row.root_mean_squared_error) &&
                row.root_mean_squared_error > thresholds.maximum_rmse_upper
            push!(hard_failures, (;
                code = :rmse_exceeds_limit,
                scope = :rho,
                coordinate,
                estimate = row.root_mean_squared_error,
                threshold = thresholds.maximum_rmse_upper,
                criterion = :at_most,
            ))
        elseif ismissing(row.rmse_one_sided_upper) ||
                row.rmse_one_sided_upper > thresholds.maximum_rmse_upper
            push!(uncertainty_blockers, (;
                code = :rmse_uncertainty_crosses_limit,
                scope = :rho,
                coordinate,
                point_estimate = row.root_mean_squared_error,
                uncertainty_bound = row.rmse_one_sided_upper,
                threshold = thresholds.maximum_rmse_upper,
                criterion = :upper_at_most,
            ))
        end
        if row.coverage.joint_fixed_denominator_rate <
                thresholds.minimum_joint_valid_and_covered_per_rho
            push!(hard_failures, (;
                code = :joint_coverage_below_per_rho_minimum,
                scope = :rho,
                coordinate,
                estimate = row.coverage.joint_fixed_denominator_rate,
                threshold =
                    thresholds.minimum_joint_valid_and_covered_per_rho,
                criterion = :at_least,
            ))
        end
        if row.direction_applicable &&
                row.direction.joint_fixed_denominator_rate <
                    thresholds.minimum_joint_valid_and_direction_matching_per_nonzero_rho
            push!(hard_failures, (;
                code = :joint_direction_recovery_below_per_rho_minimum,
                scope = :rho,
                coordinate,
                estimate = row.direction.joint_fixed_denominator_rate,
                threshold =
                    thresholds.minimum_joint_valid_and_direction_matching_per_nonzero_rho,
                criterion = :at_least,
            ))
        end
        if iszero(row.rho_truth)
            false_exclusion_lower = row.rho_zero_false_exclusion.
                unresolved_bounds.lower
            false_exclusion_upper = row.rho_zero_false_exclusion.
                unresolved_false_exclusion_upper
            false_exclusion_threshold = thresholds.
                maximum_rho_zero_unresolved_false_exclusion_upper
            if false_exclusion_lower > false_exclusion_threshold
                push!(hard_failures, (;
                    code =
                        :rho_zero_false_exclusion_observed_lower_exceeds_limit,
                    scope = :rho,
                    coordinate,
                    estimate = false_exclusion_lower,
                    threshold = false_exclusion_threshold,
                    criterion = :lower_at_most,
                ))
            elseif false_exclusion_upper > false_exclusion_threshold
                push!(uncertainty_blockers, (;
                    code =
                        :rho_zero_false_exclusion_unresolved_upper_crosses_limit,
                    scope = :rho,
                    coordinate,
                    point_estimate = false_exclusion_lower,
                    uncertainty_bound = false_exclusion_upper,
                    n_unresolved = row.rho_zero_false_exclusion.n_unresolved,
                    threshold = false_exclusion_threshold,
                    criterion = :upper_at_most,
                ))
            end
        end
    end

    aggregate_coverage = aggregate.overall.coverage
    if aggregate_coverage.equal_weight_joint_fixed_denominator_rate <
            thresholds.minimum_equal_weight_aggregate_coverage_wilson_lower
        push!(hard_failures, (;
            code = :aggregate_coverage_point_below_minimum,
            scope = :aggregate,
            coordinate = :all_rho,
            estimate =
                aggregate_coverage.equal_weight_joint_fixed_denominator_rate,
            threshold = thresholds.
                minimum_equal_weight_aggregate_coverage_wilson_lower,
            criterion = :at_least,
        ))
    elseif aggregate_coverage.one_sided_wilson_lower <
            thresholds.minimum_equal_weight_aggregate_coverage_wilson_lower
        push!(uncertainty_blockers, (;
            code = :aggregate_coverage_wilson_lower_crosses_minimum,
            scope = :aggregate,
            coordinate = :all_rho,
            point_estimate =
                aggregate_coverage.equal_weight_joint_fixed_denominator_rate,
            uncertainty_bound = aggregate_coverage.one_sided_wilson_lower,
            threshold = thresholds.
                minimum_equal_weight_aggregate_coverage_wilson_lower,
            criterion = :lower_at_least,
        ))
    end

    aggregate_direction = aggregate.overall.direction_nonzero_rho
    if aggregate_direction.equal_weight_joint_fixed_denominator_rate <
            thresholds.minimum_aggregate_direction_wilson_lower
        push!(hard_failures, (;
            code = :aggregate_direction_point_below_minimum,
            scope = :aggregate,
            coordinate = :nonzero_rho,
            estimate =
                aggregate_direction.equal_weight_joint_fixed_denominator_rate,
            threshold = thresholds.minimum_aggregate_direction_wilson_lower,
            criterion = :at_least,
        ))
    elseif aggregate_direction.one_sided_wilson_lower <
            thresholds.minimum_aggregate_direction_wilson_lower
        push!(uncertainty_blockers, (;
            code = :aggregate_direction_wilson_lower_crosses_minimum,
            scope = :aggregate,
            coordinate = :nonzero_rho,
            point_estimate =
                aggregate_direction.equal_weight_joint_fixed_denominator_rate,
            uncertainty_bound = aggregate_direction.one_sided_wilson_lower,
            threshold = thresholds.minimum_aggregate_direction_wilson_lower,
            criterion = :lower_at_least,
        ))
    end

    for row in aggregate.unpaired_symmetry_rows
        coordinate = row.rho_pair
        if row.n_scientifically_unresolved > 0
            if row.minimum_absolute_signed_bias_contrast >
                    thresholds.maximum_abs_unpaired_symmetry_upper
                push!(hard_failures, (;
                    code =
                        :unpaired_bias_symmetry_unresolved_envelope_lower_exceeds_limit,
                    scope = :symmetry_pair,
                    coordinate,
                    estimate = row.minimum_absolute_signed_bias_contrast,
                    threshold =
                        thresholds.maximum_abs_unpaired_symmetry_upper,
                    criterion = :lower_at_most,
                ))
            elseif (ismissing(row.
                    absolute_signed_bias_contrast_unresolved_plus_mcse_upper) ||
                row.absolute_signed_bias_contrast_unresolved_plus_mcse_upper >
                    thresholds.maximum_abs_unpaired_symmetry_upper)
            push!(uncertainty_blockers, (;
                code =
                    :unpaired_bias_symmetry_unresolved_envelope_crosses_limit,
                scope = :symmetry_pair,
                coordinate,
                point_estimate = row.absolute_signed_bias_contrast,
                uncertainty_bound =
                    row.
                        absolute_signed_bias_contrast_unresolved_plus_mcse_upper,
                n_unresolved = row.n_scientifically_unresolved,
                threshold =
                    thresholds.maximum_abs_unpaired_symmetry_upper,
                criterion = :upper_at_most,
            ))
            end
        elseif !ismissing(row.absolute_signed_bias_contrast) &&
                row.absolute_signed_bias_contrast >
                thresholds.maximum_abs_unpaired_symmetry_upper
            push!(hard_failures, (;
                code = :unpaired_bias_symmetry_contrast_exceeds_limit,
                scope = :symmetry_pair,
                coordinate,
                estimate = row.absolute_signed_bias_contrast,
                threshold =
                    thresholds.maximum_abs_unpaired_symmetry_upper,
                criterion = :at_most,
            ))
        elseif ismissing(row.absolute_signed_bias_contrast) || ismissing(
                row.absolute_signed_bias_contrast_uncertainty_upper) ||
                row.absolute_signed_bias_contrast_uncertainty_upper >
                    thresholds.maximum_abs_unpaired_symmetry_upper
            push!(uncertainty_blockers, (;
                code = :unpaired_bias_symmetry_uncertainty_crosses_limit,
                scope = :symmetry_pair,
                coordinate,
                point_estimate = row.absolute_signed_bias_contrast,
                uncertainty_bound = row.
                    absolute_signed_bias_contrast_uncertainty_upper,
                threshold =
                    thresholds.maximum_abs_unpaired_symmetry_upper,
                criterion = :upper_at_most,
            ))
        end
    end
    return (;
        hard_failure_rows = Tuple(hard_failures),
        uncertainty_blocker_rows = Tuple(uncertainty_blockers),
    )
end

"""
    _mgmfrm_free_latent_correlation_2d_study_score(ledger)

Score a fully terminal, authorized evaluation ledger using only its frozen plan.
The decision is one of `:passed`, `:failed`, or
`:inconclusive_not_passed`. A structurally valid ledger that is not yet eligible
for scoring returns `status = :evaluation_scoring_blocked`,
`decision = :inconclusive_not_passed`, and `evaluated = false`. Passing this
experimental score never publishes a fit and never sets recovery verification.
"""
function _mgmfrm_free_latent_correlation_2d_study_score(ledger)
    aggregate = _free_correlation_study_evaluation_aggregate(ledger)
    if !aggregate.ready
        payload = (;
            schema = _FREE_CORRELATION_STUDY_SCORE_SCHEMA,
            object = :mgmfrm_free_latent_correlation_2d_study_score,
            status = :evaluation_scoring_blocked,
            plan_id = aggregate.plan_id,
            plan_fingerprint = aggregate.plan_fingerprint,
            source_ledger_sha256 = aggregate.source_ledger_sha256,
            aggregate_fingerprint = aggregate.aggregate_fingerprint,
            evaluated = false,
            decision = :inconclusive_not_passed,
            passed = false,
            thresholds = aggregate.thresholds,
            blockers = aggregate.blockers,
            hard_failure_rows = (),
            uncertainty_blocker_rows = (),
            aggregate,
            claim_scope = :none_quarantined_experimental_evidence_only,
            public_fit = false,
            fit_ready = false,
            cache_enabled = false,
            promotion_effect = :none,
            recovery_claimed = false,
            replicated_recovery_verified = false,
            next_gate = :complete_authorized_fixed_evaluation_denominator,
        )
        return merge(payload, (;
            score_fingerprint = artifact_content_hash(payload),
        ))
    end

    decision_rows = _free_correlation_study_decision_rows(aggregate)
    hard_failures = decision_rows.hard_failure_rows
    uncertainty_blockers = decision_rows.uncertainty_blocker_rows
    decision = if !isempty(hard_failures)
        :failed
    elseif !isempty(uncertainty_blockers)
        :inconclusive_not_passed
    else
        :passed
    end
    status = decision === :passed ? :evaluation_scoring_passed :
        decision === :failed ? :evaluation_scoring_failed :
        :evaluation_scoring_inconclusive_not_passed
    next_gate = decision === :passed ?
        :independent_reproduction_and_boundary_review :
        decision === :failed ? :new_versioned_protocol_required :
        :additional_independent_evidence_under_new_versioned_protocol
    payload = (;
        schema = _FREE_CORRELATION_STUDY_SCORE_SCHEMA,
        object = :mgmfrm_free_latent_correlation_2d_study_score,
        status,
        plan_id = aggregate.plan_id,
        plan_fingerprint = aggregate.plan_fingerprint,
        source_ledger_sha256 = aggregate.source_ledger_sha256,
        aggregate_fingerprint = aggregate.aggregate_fingerprint,
        evaluated = true,
        decision,
        passed = decision === :passed,
        thresholds = aggregate.thresholds,
        blockers = (),
        hard_failure_rows = hard_failures,
        uncertainty_blocker_rows = uncertainty_blockers,
        aggregate,
        claim_scope = :none_quarantined_experimental_evidence_only,
        public_fit = false,
        fit_ready = false,
        cache_enabled = false,
        promotion_effect = :none,
        recovery_claimed = false,
        replicated_recovery_verified = false,
        next_gate,
    )
    return merge(payload, (;
        score_fingerprint = artifact_content_hash(payload),
    ))
end
