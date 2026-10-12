function _report_prediction_request(fit; include_waic, include_loo,
        dataset_id, observation_ids, loo_threshold, loo_tail_fraction, loo_min_tail_draws)
    if !include_waic && !include_loo
        dataset_id === nothing && observation_ids === nothing ||
            throw(ArgumentError("report observation IDs require include_waic or include_loo"))
        return nothing
    end
    dataset_id isa AbstractString && !isempty(strip(dataset_id)) ||
        throw(ArgumentError("predictive criteria require a nonempty dataset_id"))
    data = PredictionObservationAdapter._fit_data(fit)
    ids = PredictionObservationAdapter._ids(observation_ids, data.n, "observation_ids")
    controls = _check_loo_controls(; pareto_k_threshold=loo_threshold,
        tail_fraction=loo_tail_fraction, min_tail_draws=loo_min_tail_draws)
    return (; dataset_id=String(dataset_id), observation_ids=ids, controls)
end

function _prediction_report_sections(fit, request, policy; include_waic, include_loo)
    request === nothing && return (; waic=_fit_report_not_requested(), loo=_fit_report_not_requested())
    extracted = _fit_report_section(policy) do
        (; prediction=prediction_observations(fit; request.dataset_id,
            request.observation_ids, include_probabilities=false))
    end
    function section(criterion, requested)
        requested || return _fit_report_not_requested()
        extracted.status === :error && return extracted
        return _fit_report_section(policy) do
            p = extracted.prediction
            evaluation = prediction_criteria(p; criteria=(criterion,), request.controls...)
            stat = getproperty(evaluation.scores,criterion)
            native_rows = criterion === :waic ?
                _waic_diagnostics_rows(stat; threshold=.4, only_flagged=false) :
                _loo_diagnostics_rows(stat; threshold=Float64(request.controls.pareto_k_threshold), only_flagged=false)
            diagnostic_rows = [merge(row,(; criterion, observation_id=p.observation_ids[row.observation])) for row in native_rows]
            problem_rows = filter(row -> row.flag !== :ok, diagnostic_rows)
            problem_ids = copy(getproperty(evaluation.problem_observation_ids,criterion))
            warning_rows = NamedTuple[]
            evaluation.sampling_warning && push!(warning_rows,(; code=:sampling_warning, severity=:warning,
                message="Whole-fit MCMC warnings remain; this predictive score is descriptive.",
                action=:inspect_parameter_and_sampler_diagnostics))
            stat.warning !== :ok && push!(warning_rows,(; code=:criterion_warning, severity=:warning,
                n_affected_rows=length(problem_ids),
                message=criterion === :waic ? "WAIC has high log-likelihood variance for some ratings." :
                    "Raw importance-sampling LOO has unstable weights for some ratings; inspect the reported rating IDs.",
                action=:inspect_observation_diagnostics_and_refit))
            interpretation = "All original retained draws and chains; one omitted rating with specification and level maps fixed. " *
                "Native pointwise SE assumes exchangeable ratings; it is not crossed-cluster adjusted or MCMC MCSE. " *
                (criterion === :waic ? "WAIC uses the saved training log likelihood. " :
                    "Raw importance-sampling LOO uses a Hill tail diagnostic, not reference-validated PSIS. Importance ESS is not MCMC adjusted. ") *
                "Computed status and report completeness do not establish convergence, score precision, new-level prediction or scientific acceptance."
            rows = [(; criterion, elpd=criterion === :waic ? stat.elpd_waic : stat.elpd_loo,
                se_elpd=criterion === :waic ? stat.se_elpd_waic : stat.se_elpd_loo,
                n_draws=p.n_retained_draws, n_observations=length(p.observation_ids),
                sampling_warning=evaluation.sampling_warning, criterion_warning=stat.warning)]
            (; criterion, stat, rows, n_rows=1, diagnostic_rows, n_diagnostic_rows=length(diagnostic_rows),
                problem_rows, n_problem_rows=length(problem_rows),
                warning_rows, n_warning_rows=length(warning_rows),
                dataset_id=p.dataset_id, observation_ids=copy(p.observation_ids),
                problem_observation_ids=problem_ids, category_levels=copy(p.category_levels),
                p.observation_binding, p.training_binding, p.source_sample_hash, p.source_hash_status,
                p.prediction_target, p.conditioning, p.weighting, p.n_retained_draws,
                evaluation.sampling_warning, criterion_warning=stat.warning,
                evaluation.loo_target, evaluation.uncertainty, evaluation.reference_psis_validation,
                evaluation.scientific_acceptance, interpretation)
        end
    end
    return (; waic=section(:waic,include_waic), loo=section(:raw_loo,include_loo))
end
