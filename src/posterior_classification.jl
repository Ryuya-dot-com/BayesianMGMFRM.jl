function _classification_mean(values, chains; fixed=false)
    n = div(length(values), chains)
    status = fixed ? :structurally_fixed : chains < 2 ? :insufficient_chains :
        n < 10 ? :insufficient_draws : allequal(values) ? :degenerate_draws : :available
    value = fixed ? 0.0 : status === :available ?
        _posterior_mcse_value(reshape(Float64.(values), n, chains), Statistics.mean) : missing
    if status === :available && (ismissing(value) || value <= 0)
        status = :mcse_unavailable
        value = missing
    end
    return (; mean=mean(values), mcse=(; value, status,
        method=:mcmc_mean, n_chains=chains, draws_per_chain=n,
        convergence_review_required=!fixed, precision_threshold_applied=false))
end

function _classification_events(values, cutoff, pass_probability)
    qualifies = values .>= cutoff
    probabilities = vec(mean(qualifies; dims=1))
    pass = probabilities .>= pass_probability
    false_pass = vec(sum((.!qualifies) .& pass'; dims=2))
    false_fail = vec(sum(qualifies .& (.!pass)'; dims=2))
    return (; qualifies, probabilities, pass, false_pass, false_fail,
        errors=false_pass+false_fail)
end

"""
    BayesianMGMFRM.posterior_classification(fit; parameters, cutoff,
        pass_probability, interval=0.90)

Report conditional ability precision and binary classification risk from saved
joint draws. `parameters` selects one or more distinct estimated person locations
by exact names from `recovery_quantities(fit)`, in one dimension and scale.
Fixed anchors, other facets and mixed dimensions are rejected. The finite cohort
is exactly these people, each counted once, independent of their rating counts.

Both rules are required: qualification means `ability >= cutoff` in the fitted
coordinate system; classify a person as `:pass` when the saved estimate of that
probability is `>= pass_probability` (strictly between zero and one). Equality
belongs to the qualifying/passing side. The package does not choose a substantive
standard or infer loss costs. No centering, scale linking or multidimensional
composite is performed. For dimensions with different interpretations, call
separately with justified cutoffs; these calls do not define a conjunctive rule.

Each row retains posterior mean/SD, pointwise equal-tailed CrI (`interval=0.99`
requests 99%), probability of qualification, the specified decision and its
posterior error probability. SD describes uncertainty conditional on this model,
prior, data and calibration; it is not repeated-sampling SE or MCMC error.
`cohort` reports expected false-pass/false-fail/total counts and the probability
of any error, calculated within each joint draw to retain posterior dependence.
Decisions are held fixed at the reported choices for these calculations.

Mean MCSE accounts for chain autocorrelation. Short/single chains and constant
sampled events have unavailable MCSE, not proof of certainty. A count is known
zero only when the decision rule leaves no people eligible for that error type.
Inspect event MCSE and convergence before interpreting decisions near the chosen
probability boundary; no precision threshold or automatic refit is applied.
The reported MCSE conditions on the displayed decisions and does not quantify
their possible changes across finite MCMC runs.

These are posterior risks for the selected people, not known-truth error rates,
population sensitivity/specificity, future-score predictions or design guarantees.
Shared calibration uncertainty is included only where represented in the joint
draws. Source identity and sampling warnings are preserved for all eight common
fit types. This qualified candidate is not statistical acceptance of a model.
"""
function posterior_classification(fit::PredictionObservationAdapter.SupportedFit;
        parameters, cutoff, pass_probability, interval=0.90)
    parameters isa Union{AbstractVector,Tuple} || throw(ArgumentError("parameters must be exact coordinate names in a vector or tuple"))
    names = collect(parameters)
    !isempty(names) && all(p -> p isa AbstractString && !isempty(strip(p)), names) &&
        length(unique(names)) == length(names) || throw(ArgumentError("select distinct nonempty person coordinate names"))
    all(x -> x isa Real && !(x isa Bool) && isfinite(x) && isfinite(Float64(x)),
        (cutoff, pass_probability, interval)) || throw(ArgumentError("cutoff, pass_probability and interval must be finite real numbers"))
    cutoff, pass_probability, interval = Float64(cutoff), Float64(pass_probability), Float64(interval)
    0 < pass_probability < 1 || throw(ArgumentError("pass_probability must be strictly between zero and one"))
    _interval_probabilities(interval)
    context = _recovery_context(fit)
    lookup = Dict(r.parameter => r for r in context.coordinates)
    all(p -> haskey(lookup, p), names) || throw(ArgumentError("unknown classification coordinate"))
    coordinates = [lookup[p] for p in names]
    descriptions = [_recovery_quantity(r, context.spec) for r in coordinates]
    d = first(descriptions)
    all(r -> r.block === :person && !r.fixed &&
        (r.dimension, r.parameter_space) == (d.dimension, d.parameter_space), descriptions) ||
        throw(ArgumentError("classification requires estimated person locations in one dimension and scale"))
    selected = hcat([r.values for r in coordinates]...)
    events = _classification_events(selected, Float64(cutoff), Float64(pass_probability))
    chains = length(unique(context.chain_ids))
    rows = map(eachindex(names)) do i
        qualifies = view(events.qualifies, :, i)
        (; descriptions[i]..., ability=_category_report_summary(view(selected, :, i), chains, interval),
            qualification_probability=_classification_mean(qualifies, chains),
            decision=events.pass[i] ? :pass : :fail,
            error_probability=_classification_mean(events.pass[i] ? .!qualifies : qualifies, chains))
    end
    cohort = (;
        expected_false_pass_count=_classification_mean(events.false_pass, chains; fixed=!any(events.pass)),
        expected_false_fail_count=_classification_mean(events.false_fail, chains; fixed=all(events.pass)),
        expected_error_count=_classification_mean(events.errors, chains),
        probability_any_error=_classification_mean(events.errors .> 0, chains))
    mcse_warning = any(r -> r.ability.mcse === nothing || r.ability.mcse.mcse_status !== :available ||
        r.qualification_probability.mcse.status !== :available, rows) ||
        any(r -> !(r.mcse.status in (:available, :structurally_fixed)), values(cohort))
    sampling_warning = _prediction_sampling_warning(context.quality)
    return _prediction_seal((; schema="bayesianmgmfrm.posterior_classification.v1",
        cutoff=Float64(cutoff), pass_probability=Float64(pass_probability),
        interval_probability=Float64(interval), interval_method=:equal_tailed,
        qualification_rule=:ability_greater_than_or_equal_to_cutoff,
        decision_rule=:probability_greater_than_or_equal_to_pass_probability,
        rows, cohort, n_people=length(names), n_pass=count(events.pass),
        n_fail=count(!, events.pass), cohort_basis=:explicit_selected_people_equal_weight,
        model_contract=_recovery_model_contract(fit, context),
        n_retained_draws=context.total_draws, chain_ids=copy(context.chain_ids), iterations=copy(context.iterations),
        evaluated_draws_hash=_cache_hash((; parameters=names, values=selected)),
        context.source_sample_hash, context.source_hash_status,
        sampling_quality=deepcopy(context.quality), sampling_warning, mcse_warning,
        status=sampling_warning || mcse_warning ? :warning : :descriptive,
        scientific_acceptance=:not_established,
        scope=:conditional_posterior_risk_not_known_truth_error_rate))
end
