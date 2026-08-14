# Shared resource-bounded, denominator-preserving fit wiring for generated
# MGMFRM stress cases and primary-grid candidates.

const _MGMFRM_STRESS_BACKENDS = (:advancedhmc, :cmdstan)
const _MGMFRM_STRESS_PRIOR_REGIMES = (
    :implementation_reference,
    :source_aligned,
    :strong_regularizing,
)

function _mgmfrm_stress_fit_controls(profile::Symbol)
    profile === :wiring_smoke && return (;
        profile,
        ndraws = 4,
        warmup = 4,
        chains = 1,
        step_size = 0.03,
        target_accept = 0.80,
        max_depth = 10,
        metric = :unit,
        convergence_assessed = false,
        diagnostic_decision = :not_applied_short_chain,
        claim_scope = :fit_and_diagnostic_wiring_only,
    )
    profile === :short_nuts_resource_probe && return (;
        profile,
        ndraws = 25,
        warmup = 25,
        chains = 1,
        step_size = 0.03,
        target_accept = 0.90,
        max_depth = 10,
        metric = :diagonal,
        convergence_assessed = false,
        diagnostic_decision = :not_applied_resource_probe_short_chain,
        claim_scope = :runtime_and_operability_only,
    )
    profile === :analysis && throw(ArgumentError(
        "profile = :analysis is blocked until its attempt-complete analysis " *
        "contract and independently reviewed scientific thresholds are frozen",
    ))
    throw(ArgumentError(
        "profile must be :wiring_smoke, :short_nuts_resource_probe, or :analysis",
    ))
end

function _mgmfrm_stress_prior(regime::Symbol)
    regime === :implementation_reference && return GeneralizedPrior(
        person_sd = 1.0,
        rater_sd = 1.0,
        item_sd = 1.0,
        log_discrimination_sd = 0.5,
        log_consistency_sd = 0.5,
        step_sd = 1.0,
    )
    regime === :source_aligned && return GeneralizedPrior(
        person_sd = 1.0,
        rater_sd = 1.0,
        item_sd = 1.0,
        log_discrimination_sd = 1.0,
        log_consistency_sd = 1.0,
        step_sd = 1.0,
    )
    regime === :strong_regularizing && return GeneralizedPrior(
        person_sd = 1.0,
        rater_sd = 0.5,
        item_sd = 0.5,
        log_discrimination_sd = 0.25,
        log_consistency_sd = 0.25,
        step_sd = 0.5,
    )
    throw(ArgumentError("unsupported MGMFRM stress prior regime :$regime"))
end

function _mgmfrm_stress_default_fit(case, backend::Symbol,
        prior::GeneralizedPrior, controls, fit_seed::Int;
        cmdstan_path,
        cmdstan_cache_dir)
    common = (;
        prior,
        backend,
        ndraws = controls.ndraws,
        warmup = controls.warmup,
        chains = controls.chains,
        step_size = controls.step_size,
        seed = fit_seed,
        target_accept = controls.target_accept,
        max_depth = controls.max_depth,
        metric = controls.metric,
        progress = false,
    )
    backend_options = backend === :cmdstan ? (;
        cmdstan_path,
        cmdstan_cache_dir,
    ) : NamedTuple()
    return Experimental.fit(case.spec; common..., backend_options...)
end

function _mgmfrm_stress_diagnostic_total(rows, field::Symbol)
    values = Int[]
    for row in rows
        value = getproperty(row, field)
        ismissing(value) || push!(values, Int(value))
    end
    return isempty(values) ? missing : sum(values)
end

function _mgmfrm_stress_default_diagnostics(fit::MGMFRMFit, controls)
    direct_draws = fit.direct_draws
    pointwise = pointwise_loglikelihood_matrix(fit)
    probabilities = predictive_probabilities(fit)
    probability_sums = dropdims(sum(probabilities; dims = 3); dims = 3)
    maximum_probability_sum_error =
        maximum(abs.(probability_sums .- 1.0))
    expected = expected_scores(fit)
    sampler_rows = sampler_diagnostics(fit)
    sampler_flags = Tuple(sort(unique(
        row.flag for row in sampler_rows if row.flag !== :ok
    ); by = string))
    n_failed_direct_constraints =
        Int(fit.diagnostic_surface.summary.n_failed_direct_constraints)
    integrity_passed = all(isfinite, direct_draws) &&
        all(isfinite, fit.log_posterior) &&
        all(isfinite, pointwise) &&
        all(isfinite, probabilities) &&
        all(isfinite, expected) &&
        maximum_probability_sum_error <= 1e-10 &&
        n_failed_direct_constraints == 0
    integrity_passed || throw(ArgumentError(
        "bounded MGMFRM output failed finite, probability-simplex, " *
        "or direct-constraint integrity checks",
    ))
    return (;
        diagnostic_status = :integrity_passed_not_convergence_assessed,
        output_integrity_passed = true,
        n_draws = size(direct_draws, 1),
        n_direct_parameters = size(direct_draws, 2),
        maximum_probability_sum_error,
        n_failed_direct_constraints,
        n_divergences = _mgmfrm_stress_diagnostic_total(
            sampler_rows, :n_divergences),
        n_max_treedepth = _mgmfrm_stress_diagnostic_total(
            sampler_rows, :n_max_treedepth),
        sampler_flags,
        convergence_assessed = controls.convergence_assessed,
        diagnostic_decision = controls.diagnostic_decision,
    )
end

function _mgmfrm_stress_expanded_attempt_id(source_id, backend::Symbol,
        prior_regime::Symbol)
    return Symbol(source_id, "__", backend, "__", prior_regime)
end

function _mgmfrm_fit_source_id(plan_row)
    plan_row.object === :mgmfrm_response_stress_plan_row &&
        return Symbol(plan_row.attempt_id)
    plan_row.object === :mgmfrm_validation_primary_grid_candidate &&
        return Symbol(plan_row.cell_id)
    throw(ArgumentError("unsupported bounded MGMFRM fit source"))
end

function _mgmfrm_fit_simulation_seed(plan_row)
    plan_row.object === :mgmfrm_response_stress_plan_row &&
        return Int(plan_row.seed)
    plan_row.object === :mgmfrm_validation_primary_grid_candidate &&
        return Int(hasproperty(plan_row, :resource_seed) ?
            plan_row.resource_seed : plan_row.preflight_seed)
    throw(ArgumentError("unsupported bounded MGMFRM fit source"))
end

function _mgmfrm_fit_replication(plan_row)
    plan_row.object === :mgmfrm_response_stress_plan_row &&
        return plan_row.replication
    plan_row.object === :mgmfrm_validation_primary_grid_candidate &&
        return missing
    throw(ArgumentError("unsupported bounded MGMFRM fit source"))
end

function _mgmfrm_fit_generate(plan_row, truth_scale::Real)
    plan_row.object === :mgmfrm_response_stress_plan_row &&
        return simulate_mgmfrm_response_stress(plan_row; truth_scale)
    plan_row.object === :mgmfrm_validation_primary_grid_candidate &&
        return simulate_mgmfrm_validation_primary_candidate(
            plan_row;
            truth_scale,
            seed = _mgmfrm_fit_simulation_seed(plan_row),
        )
    throw(ArgumentError("unsupported bounded MGMFRM fit source"))
end

function _mgmfrm_fit_response_pattern_passed(case)
    case.object === :mgmfrm_response_stress_case &&
        return case.pattern_check.passed
    case.object === :mgmfrm_validation_primary_candidate_case &&
        return case.category_support_passed
    throw(ArgumentError("unsupported bounded MGMFRM generated case"))
end

function _mgmfrm_fit_result_identity(plan_rows)
    source_objects = unique(row.object for row in plan_rows)
    length(source_objects) == 1 || throw(ArgumentError(
        "bounded MGMFRM fit plan cannot mix source row types"))
    source_object = only(source_objects)
    source_object === :mgmfrm_response_stress_plan_row && return (;
        schema =
            "bayesianmgmfrm.mgmfrm_response_stress_fit_attempts.v1",
        object = :mgmfrm_response_stress_fit_attempts,
        row_schema =
            "bayesianmgmfrm.mgmfrm_response_stress_fit_attempt_row.v1",
        row_object = :mgmfrm_response_stress_fit_attempt_row,
    )
    source_object === :mgmfrm_validation_primary_grid_candidate && return (;
        schema =
            "bayesianmgmfrm.mgmfrm_validation_primary_fit_attempts.v1",
        object = :mgmfrm_validation_primary_fit_attempts,
        row_schema =
            "bayesianmgmfrm.mgmfrm_validation_primary_fit_attempt_row.v1",
        row_object = :mgmfrm_validation_primary_fit_attempt_row,
    )
    throw(ArgumentError("unsupported bounded MGMFRM fit source"))
end

function _mgmfrm_stress_fit_seed(plan_row, backend_index::Int,
        prior_index::Int)
    return _mgmfrm_fit_simulation_seed(plan_row) + 100_000 +
        1_000 * prior_index + backend_index
end

function _mgmfrm_stress_fit_base_row(plan_row, expanded_index::Int,
        backend::Symbol, prior_regime::Symbol, fit_seed::Int, controls,
        generation_seconds::Float64, identity)
    source_id = _mgmfrm_fit_source_id(plan_row)
    return (;
        schema = identity.row_schema,
        object = identity.row_object,
        attempt_id = _mgmfrm_stress_expanded_attempt_id(
            source_id, backend, prior_regime),
        source_attempt_id = source_id,
        source_object = plan_row.object,
        attempt_index = expanded_index,
        design = plan_row.design,
        response_pattern = plan_row.response_pattern,
        replication = _mgmfrm_fit_replication(plan_row),
        backend,
        prior_regime,
        profile = controls.profile,
        simulation_seed = _mgmfrm_fit_simulation_seed(plan_row),
        fit_seed,
        generation_seconds,
        convergence_assessed = controls.convergence_assessed,
        diagnostic_decision = controls.diagnostic_decision,
        scientific_decision = :not_applied,
        claim_scope = controls.claim_scope,
    )
end

function _mgmfrm_stress_fit_terminal_row(base;
        terminal_status::Symbol,
        error_phase = missing,
        error = missing,
        fit_seconds::Real = 0.0,
        diagnostic_seconds::Real = 0.0,
        validation_passed = missing,
        validation_issue_codes = (),
        q_validation_passed = missing,
        response_pattern_passed = missing,
        fit_eligible::Bool = false,
        diagnostics = missing)
    error_type = ismissing(error) ? missing : string(typeof(error))
    error_message = ismissing(error) ? missing : sprint(showerror, error)
    diagnostic_status = ismissing(diagnostics) ? missing :
        diagnostics.diagnostic_status
    output_integrity_passed = ismissing(diagnostics) ? missing :
        diagnostics.output_integrity_passed
    n_draws = ismissing(diagnostics) ? missing : diagnostics.n_draws
    n_direct_parameters = ismissing(diagnostics) ? missing :
        diagnostics.n_direct_parameters
    maximum_probability_sum_error = ismissing(diagnostics) ? missing :
        diagnostics.maximum_probability_sum_error
    n_failed_direct_constraints = ismissing(diagnostics) ? missing :
        diagnostics.n_failed_direct_constraints
    n_divergences = ismissing(diagnostics) ? missing :
        diagnostics.n_divergences
    n_max_treedepth = ismissing(diagnostics) ? missing :
        diagnostics.n_max_treedepth
    sampler_flags = ismissing(diagnostics) ? () : diagnostics.sampler_flags
    return merge(base, (;
        terminal_status,
        terminal = true,
        error_phase,
        error_type,
        error_message,
        error,
        fit_seconds = Float64(fit_seconds),
        diagnostic_seconds = Float64(diagnostic_seconds),
        total_seconds = base.generation_seconds + Float64(fit_seconds) +
            Float64(diagnostic_seconds),
        validation_passed,
        validation_issue_codes,
        q_validation_passed,
        response_pattern_passed,
        fit_eligible,
        diagnostic_status,
        output_integrity_passed,
        n_draws,
        n_direct_parameters,
        maximum_probability_sum_error,
        n_failed_direct_constraints,
        n_divergences,
        n_max_treedepth,
        sampler_flags,
    ))
end

function _mgmfrm_bounded_fit_attempts(plan;
        profile::Symbol,
        backends,
        prior_regimes,
        maximum_attempts::Integer,
        truth_scale::Real,
        cmdstan_path,
        cmdstan_cache_dir,
        fit_executor = _mgmfrm_stress_default_fit,
        diagnostic_executor = _mgmfrm_stress_default_diagnostics)
    controls = _mgmfrm_stress_fit_controls(profile)
    selected_backends = _mgmfrm_stress_selection(
        backends, _MGMFRM_STRESS_BACKENDS, "backends")
    selected_priors = _mgmfrm_stress_selection(
        prior_regimes, _MGMFRM_STRESS_PRIOR_REGIMES, "prior_regimes")
    cmdstan_options_supplied =
        cmdstan_path !== nothing || cmdstan_cache_dir !== nothing
    if cmdstan_options_supplied && :cmdstan ∉ selected_backends
        throw(ArgumentError(
            "CmdStan paths can be supplied only when :cmdstan is selected",
        ))
    end
    maximum_attempts_value = Int(maximum_attempts)
    maximum_attempts_value >= 1 ||
        throw(ArgumentError("maximum_attempts must be positive"))
    isfinite(truth_scale) && truth_scale > 0 ||
        throw(ArgumentError("truth_scale must be finite and positive"))
    plan_rows = collect(plan)
    isempty(plan_rows) && throw(ArgumentError("plan must not be empty"))
    all(row -> hasproperty(row, :object), plan_rows) ||
        throw(ArgumentError("bounded MGMFRM fit rows must declare object"))
    identity = _mgmfrm_fit_result_identity(plan_rows)
    source_ids = [_mgmfrm_fit_source_id(row) for row in plan_rows]
    length(unique(source_ids)) == length(source_ids) ||
        throw(ArgumentError("plan source identifiers must be unique"))
    expanded_attempts = length(plan_rows) * length(selected_backends) *
        length(selected_priors)
    expanded_attempts <= maximum_attempts_value || throw(ArgumentError(
        "expanded plan has $expanded_attempts attempt(s), exceeding " *
        "maximum_attempts = $maximum_attempts_value; select a smaller explicit " *
        "plan or raise the resource bound",
    ))

    rows = NamedTuple[]
    cases = Any[]
    fits = Any[]
    expanded_index = 0
    for plan_row in plan_rows
        generation_started = time_ns()
        generated = try
            _mgmfrm_fit_generate(plan_row, truth_scale)
        catch err
            _mgmfrm_stress_fatal_exception(err) && rethrow()
            err
        end
        generation_seconds = (time_ns() - generation_started) / 1.0e9

        for (prior_index, prior_regime) in pairs(selected_priors),
                (backend_index, backend) in pairs(selected_backends)
            expanded_index += 1
            fit_seed = _mgmfrm_stress_fit_seed(
                plan_row, backend_index, prior_index)
            base = _mgmfrm_stress_fit_base_row(
                plan_row,
                expanded_index,
                backend,
                prior_regime,
                fit_seed,
                controls,
                generation_seconds,
                identity,
            )
            if generated isa Exception
                push!(rows, _mgmfrm_stress_fit_terminal_row(
                    base;
                    terminal_status = :generation_failed,
                    error_phase = :generation_and_preflight,
                    error = generated,
                ))
                push!(cases, missing)
                push!(fits, missing)
                continue
            end

            validation_issue_codes =
                _mgmfrm_stress_issue_codes(generated.validation)
            if !generated.preflight_passed || !generated.fit_eligible
                push!(rows, _mgmfrm_stress_fit_terminal_row(
                    base;
                    terminal_status = :pre_fit_rejected,
                    validation_passed = generated.validation.passed,
                    validation_issue_codes,
                    q_validation_passed = generated.q_validation.passed,
                    response_pattern_passed =
                        _mgmfrm_fit_response_pattern_passed(generated),
                    fit_eligible = generated.fit_eligible,
                ))
                push!(cases, generated)
                push!(fits, missing)
                continue
            end

            prior = _mgmfrm_stress_prior(prior_regime)
            fit_started = time_ns()
            fit_result = try
                fit_executor(
                    generated,
                    backend,
                    prior,
                    controls,
                    fit_seed;
                    cmdstan_path,
                    cmdstan_cache_dir,
                )
            catch err
                _mgmfrm_stress_fatal_exception(err) && rethrow()
                err
            end
            fit_seconds = (time_ns() - fit_started) / 1.0e9
            if fit_result isa Exception
                push!(rows, _mgmfrm_stress_fit_terminal_row(
                    base;
                    terminal_status = :fit_failed,
                    error_phase = :fit,
                    error = fit_result,
                    fit_seconds,
                    validation_passed = true,
                    validation_issue_codes,
                    q_validation_passed = true,
                    response_pattern_passed = true,
                    fit_eligible = true,
                ))
                push!(cases, generated)
                push!(fits, missing)
                continue
            end

            diagnostic_started = time_ns()
            diagnostics = try
                diagnostic_executor(fit_result, controls)
            catch err
                _mgmfrm_stress_fatal_exception(err) && rethrow()
                err
            end
            diagnostic_seconds =
                (time_ns() - diagnostic_started) / 1.0e9
            if diagnostics isa Exception
                push!(rows, _mgmfrm_stress_fit_terminal_row(
                    base;
                    terminal_status = :diagnostic_failed,
                    error_phase = :diagnostic,
                    error = diagnostics,
                    fit_seconds,
                    diagnostic_seconds,
                    validation_passed = true,
                    validation_issue_codes,
                    q_validation_passed = true,
                    response_pattern_passed = true,
                    fit_eligible = true,
                ))
                push!(cases, generated)
                push!(fits, fit_result)
                continue
            end

            push!(rows, _mgmfrm_stress_fit_terminal_row(
                base;
                terminal_status = :completed,
                fit_seconds,
                diagnostic_seconds,
                validation_passed = true,
                validation_issue_codes,
                q_validation_passed = true,
                response_pattern_passed = true,
                fit_eligible = true,
                diagnostics,
            ))
            push!(cases, generated)
            push!(fits, fit_result)
        end
    end

    statuses = Tuple(row.terminal_status for row in rows)
    n_completed = count(==(:completed), statuses)
    n_generation_failed = count(==(:generation_failed), statuses)
    n_pre_fit_rejected = count(==(:pre_fit_rejected), statuses)
    n_fit_failed = count(==(:fit_failed), statuses)
    n_diagnostic_failed = count(==(:diagnostic_failed), statuses)
    all_completed = n_completed == expanded_attempts
    completed_status = profile === :wiring_smoke ?
        :wiring_smoke_complete : :short_nuts_resource_probe_complete
    failure_status = profile === :wiring_smoke ?
        :wiring_smoke_complete_with_recorded_failures :
        :short_nuts_resource_probe_complete_with_recorded_failures
    return (;
        schema = identity.schema,
        object = identity.object,
        status = all_completed ? completed_status : failure_status,
        profile,
        controls,
        maximum_attempts = maximum_attempts_value,
        truth_scale = Float64(truth_scale),
        backends = selected_backends,
        prior_regimes = selected_priors,
        rows = Tuple(rows),
        cases = Tuple(cases),
        fits = Tuple(fits),
        summary = (;
            n_planned_source_cases = length(plan_rows),
            n_attempts = expanded_attempts,
            n_terminal_attempts = count(row -> row.terminal, rows),
            n_completed,
            n_generation_failed,
            n_pre_fit_rejected,
            n_fit_failed,
            n_diagnostic_failed,
            denominator_preserved = length(rows) == expanded_attempts,
        ),
        operability_completed = all_completed,
        convergence_assessed = false,
        computational_decision = :not_applied_short_chain,
        scientific_decision = :not_applied,
        recovery_evidence = :not_established,
        claim_scope = controls.claim_scope,
        next_gate = profile === :wiring_smoke ?
            :freeze_attempt_complete_analysis_profile_and_thresholds :
            :review_short_nuts_runtime_and_memory_without_scientific_scoring,
    )
end

"""
    mgmfrm_response_stress_fit_attempts(plan;
        profile = :wiring_smoke, backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,), maximum_attempts = 1,
        truth_scale = 0.15, cmdstan_path = nothing,
        cmdstan_cache_dir = nothing)

Run a resource-bounded fit-wiring smoke over an explicit response-stress plan.
The plan is expanded across the selected backends and prior regimes, and
`maximum_attempts` is checked before generation or fitting. Every admitted
attempt terminates as `:generation_failed`, `:pre_fit_rejected`, `:fit_failed`,
`:diagnostic_failed`, or `:completed`; caught errors retain their exception
object, concrete type, message, and phase.

Only `profile = :wiring_smoke` is currently executable. It uses four warmup and
four retained draws in one chain, does not assess convergence, and cannot be
used for recovery, backend, prior, or scientific decisions. `profile =
:analysis` fails before execution until the Stage-A protocol and independent
threshold review are frozen.
"""
function mgmfrm_response_stress_fit_attempts(plan;
        profile::Symbol = :wiring_smoke,
        backends = (:advancedhmc,),
        prior_regimes = (:implementation_reference,),
        maximum_attempts::Integer = 1,
        truth_scale::Real = 0.15,
        cmdstan_path::Union{Nothing,AbstractString} = nothing,
        cmdstan_cache_dir::Union{Nothing,AbstractString} = nothing)
    profile === :short_nuts_resource_probe && throw(ArgumentError(
        "profile = :short_nuts_resource_probe is available only through " *
        "mgmfrm_validation_short_nuts_resource_probe, which enforces the " *
        "memory and workload preflight",
    ))
    return _mgmfrm_bounded_fit_attempts(
        plan;
        profile,
        backends,
        prior_regimes,
        maximum_attempts,
        truth_scale,
        cmdstan_path,
        cmdstan_cache_dir,
    )
end
