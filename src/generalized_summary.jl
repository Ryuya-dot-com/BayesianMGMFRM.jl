# Read-only views of existing joint draws; no target, prior or sample conversion.
function _generalized_summary_selection(scale, estimand; parameter_space=nothing)
    estimand in (:parameters, :adjacent_logit_slope) || throw(ArgumentError(
        "estimand must be :parameters or :adjacent_logit_slope"))
    scale in (nothing, :raw, :model) || throw(ArgumentError("scale must be :raw or :model"))
    scale !== nothing && parameter_space !== nothing && throw(ArgumentError(
        "choose scale or parameter_space, not both"))
    if estimand === :adjacent_logit_slope
        scale === :raw && throw(ArgumentError("adjacent-logit slopes are derived model quantities, not raw coordinates"))
        parameter_space in (nothing, :auto, :adjacent_logit_slope) || throw(ArgumentError(
            "adjacent-logit slopes require parameter_space=:auto or :adjacent_logit_slope"))
        return :adjacent_logit_slope
    end
    parameter_space === nothing || return parameter_space
    return scale === :model ? :direct_constrained : :raw_unconstrained
end

function _generalized_slope_context(fit::Union{GMFRMFit,MGMFRMFit})
    input = _posterior_mcse_generalized_input(fit, :direct_constrained)
    return (; design=fit.design, direct=input.draws, fixed=input.structurally_fixed_parameters,
        chains=length(fit.chain_acceptance_rate), chain_ids=fit.chain_ids, iterations=fit.iterations)
end

function _generalized_slope_context(fit::_RecordedMGMFRMFit)
    c = _mgmfrm_correlated_2d_report_context(fit)
    run = c.checked.record.run
    return (; design=c.target.base.design, c.direct, fixed=c.checked.structurally_fixed_parameters,
        chains=run.controls.chains, chain_ids=run.chain_ids, iterations=run.iterations)
end

function _generalized_slope_rows(fit; operation::Symbol=:summary,
        probabilities=(0.025, 0.5, 0.975), lower::Real=0.025, upper::Real=0.975,
        intervals=(0.66, 0.9, 0.95), reference::Real=0.0, rope=nothing,
        rope_probability_threshold::Real=0.95)
    c = _generalized_slope_context(fit)
    design, draws = c.design, c.direct
    spec, data = design.spec, design.spec.data
    n = size(draws, 1)
    c.chains > 0 && n > 0 && n % c.chains == 0 || throw(ArgumentError("invalid joint draw chain layout"))
    per_chain = div(n, c.chains)
    c.chain_ids == repeat(1:c.chains; inner=per_chain) &&
        length(c.iterations) == n && all(chain ->
            issorted(c.iterations[(chain-1)*per_chain+1:chain*per_chain]; lt=<=), 1:c.chains) ||
        throw(ArgumentError("joint draws must retain contiguous chains and strictly increasing iterations"))
    size(draws, 2) >= length(design.parameter_names) && all(isfinite, draws) ||
        throw(ArgumentError("model draws have invalid dimensions or nonfinite values"))
    gm = spec.family === :gmfrm
    multiplier = gm ? 1.0 : 1.7
    loadings = gm ? reshape(collect(design.blocks[:item_discrimination]), :, 1) :
        _mgmfrm_source_loading_index_matrix(design)
    observed = Set(zip(data.item, data.rater))
    rows = NamedTuple[]
    for i in eachindex(data.item_levels), r in eachindex(data.rater_levels), d in 1:spec.dimensions
        a, consistency = loadings[i,d], design.blocks[:rater_consistency][r]
        fixed = iszero(a) || (design.parameter_names[a] in c.fixed &&
            design.parameter_names[consistency] in c.fixed)
        # One joint column at a time avoids a draws × items × raters × dimensions allocation.
        values = iszero(a) ? zeros(n) : multiplier .* view(draws,:,a) .* view(draws,:,consistency)
        all(isfinite, values) || throw(ArgumentError("adjacent-logit slope overflowed"))
        name = "adjacent_logit_slope[item=$(repr(data.item_levels[i])),rater=$(repr(data.rater_levels[r])),dimension=$(repr(spec.dimension_labels[d]))]"
        metadata = (; parameter_space=:adjacent_logit_slope, estimand=:adjacent_logit_slope,
            item=data.item_levels[i], rater=data.rater_levels[r], dimension=spec.dimension_labels[d],
            likelihood_scale=multiplier, fixed, derived=true, structural_zero=iszero(a),
            observed_pair=(i,r) in observed, unit=:log_odds_per_ability_unit,
            conditioning=:other_ability_components_fixed, joint_draws_used=true)
        summary = operation in (:summary, :report) ? only(_posterior_summary_rows(reshape(values,:,1), [name];
            lower, upper, intervals, reference, rope, rope_probability_threshold)) : (;)
        precision = operation in (:mcse, :report) ? only(_posterior_mcse_rows(reshape(values,:,1), [name], c.chains;
            probabilities, parameter_space=:adjacent_logit_slope,
            structurally_fixed_parameters=fixed ? Set([name]) : Set{String}())) : (;)
        push!(rows, merge(summary, precision, metadata))
    end
    return rows
end

function _generalized_slope_report(fit; lower, upper, on_section_error)
    return _fit_report_section(on_section_error) do
        rows = _generalized_slope_rows(fit; operation=:report, lower, upper,
            intervals=(upper-lower,), probabilities=(lower, 0.5, upper))
        (; rows, n_rows=length(rows), estimand=:adjacent_logit_slope,
            interpretation="Conditional adjacent-category log-odds slopes per one unit of the fitted ability dimension, with other components held fixed. Each stored joint draw supplies multiplier × item loading × rater consistency; separate posterior means are never multiplied. These are not cumulative-event log odds, reliability coefficients or standardized effects. Matching logit units alone does not align constructs, ability scales or priors across models. Fixed/zero rows are model constraints, not estimated certainty. MCSE requires adequate sampling; retain the report's whole-fit warnings. Unobserved item-rater pairs use the fitted model, not direct observations.")
    end
end
