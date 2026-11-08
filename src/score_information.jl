function _score_information_draws(terms, ability, levels)
    probabilities = _category_profile_probabilities(terms, ability)
    S, K = size(probabilities)
    expected = zeros(S); information = zeros(S)
    for s in 1:S
        mean_index = sum((k-1)*probabilities[s,k] for k in 1:K)
        expected[s] = sum(levels[k]*probabilities[s,k] for k in 1:K)
        # Centered variance avoids subtracting nearly equal second moments.
        information[s] = (terms.scale[s]*terms.axis[s])^2 *
            sum(probabilities[s,k]*(k-1-mean_index)^2 for k in 1:K)
    end
    return (;expected, information)
end

"""
    BayesianMGMFRM.score_information_report(fit::MFRMFit;
        dataset_id, observation_ids, ratings, ability_grid,
        interval=0.95, max_curve_cells=20_000_000)

Compute conditional expected-score and Fisher-information curves for an ordinary
scalar unit-logit MFRM, with item-owned PCM or shared rating-scale steps. Each
`ratings` entry is `(id="...", item=stored_label, rater=stored_label, repetitions=1)`.
Use unique IDs and item/rater pairs and positive integer repetitions. This is an
explicit assessment design, not the observed incomplete allocation, survey
weights, unknown raters or a standardization inferred from the data.

At each finite, strictly increasing `ability_grid` value, `rating_rows` summarize
ONE rating for each item/rater pair. `test_rows` summarize the total score and
information for the declared repetitions. Totals are formed within each original
joint draw before intervals and MCSE; interval endpoints are never added. All
retained draws and their original complete chains contribute. No fit, outcome
simulation or random draw selection occurs.

For category index k starting at zero, the model logit is k*theta plus a nuisance
offset. Expected score uses the stored score labels; information is Var(k), in
inverse squared unit logits. The test sum assumes ratings are independent given
ability and ALL fitted nuisance parameters. Posterior uncertainty in those
parameters is retained through draw-wise curves. This is not the information of
the marginal predictive mixture, a posterior variance, reliability or a precision
guarantee. Repeated ratings sharing an unmodelled response effect need a different
model. Fixed anchors omit external calibration uncertainty.

Intervals are pointwise equal-tailed posterior intervals for expected values and
conditional information, not realized-score prediction intervals or simultaneous
bands. All sampling warnings and detailed mean/quantile MCSE remain available;
`:descriptive` does not assert a user-specific MCSE tolerance. The ability grid is
not evidence of empirical support. Resource limits bound evaluated probability
cells, with only one draw-by-category matrix retained at a time.

This qualified candidate API accepts `MFRMFit`, not generalized/multidimensional
or application-specific wrappers. Use the opt-in `fit_report` request
`reporting=(;dataset_id, observation_ids, score_information=(;ratings, ability_grid))`
to retain conditions, warnings, numerical tables and full summaries in a report
bundle. Existing report requests are unchanged when this option is omitted.
"""
function score_information_report(fit::MFRMFit; dataset_id::AbstractString,
        observation_ids, ratings, ability_grid, interval::Real=.95,
        max_curve_cells::Integer=20_000_000)
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    _interval_probabilities(interval)
    !(max_curve_cells isa Bool) && max_curve_cells>0 ||
        throw(ArgumentError("max_curve_cells must be a positive integer"))
    ratings isa Union{Tuple,AbstractVector} && !isempty(ratings) ||
        throw(ArgumentError("ratings must contain at least one named rating design cell"))
    data=fit.design.spec.data
    ids=PredictionObservationAdapter._ids(observation_ids,data.n,"observation_ids")
    cells=NamedTuple[]
    for r in ratings
        r isa NamedTuple && Set(keys(r))==Set((:id,:item,:rater,:repetitions)) ||
            throw(ArgumentError("each rating cell requires exactly id, item, rater and repetitions"))
        r.repetitions isa Integer && !(r.repetitions isa Bool) && 0<r.repetitions<=typemax(Int) ||
            throw(ArgumentError("repetitions must be a positive representable integer, not a weight"))
        any(c->isequal((c.item,c.rater),(r.item,r.rater)),cells) &&
            throw(ArgumentError("duplicate item/rater pair; declare its repetitions in one cell"))
        push!(cells,(;r.id,r.item,r.rater,repetitions=Int(r.repetitions)))
    end
    total_repetitions=sum(big(c.repetitions) for c in cells)
    total_repetitions<=typemax(Int) || throw(ArgumentError("total repetitions overflow Int"))
    context=_recovery_context(fit);spec=context.spec;S=context.total_draws
    spec.family===:mfrm && spec.dimensions==1 ||
        throw(ArgumentError("score_information_report requires ordinary scalar MFRM"))
    profiles=_category_profiles([(;c.id,c.item,c.rater,dimension=1,ability_grid) for c in cells],
        spec,S,max_curve_cells)
    step_contract,steps=_category_report_steps(context)
    terms=[_category_profile_terms(context,steps,p) for p in profiles]
    chains=length(unique(context.chain_ids))
    rating_rows=NamedTuple[];test_rows=NamedTuple[]
    for ability in first(profiles).ability_grid
        total_score=zeros(S);total_information=zeros(S)
        for (cell,term) in zip(cells,terms)
            values=_score_information_draws(term,ability,data.category_levels)
            total_score .+= cell.repetitions .* values.expected
            total_information .+= cell.repetitions .* values.information
            push!(rating_rows,(;id=cell.id,ability,
                expected_score=_category_report_summary(values.expected,chains,interval;
                    fixed=term.probability_fixed,space=:score),
                information=_category_report_summary(values.information,chains,interval;
                    fixed=term.probability_fixed,space=:inverse_squared_unit_logit)))
        end
        fixed=all(t->t.probability_fixed,terms)
        push!(test_rows,(;ability,
            expected_score=_category_report_summary(total_score,chains,interval;fixed,space=:total_score),
            information=_category_report_summary(total_information,chains,interval;
                fixed,space=:inverse_squared_unit_logit)))
    end
    summaries=[s for row in Iterators.flatten((rating_rows,test_rows)) for s in (row.expected_score,row.information)]
    numerical_warning=any(s->s.status in (:nonfinite_draws,:nonfinite_summary),summaries)
    mcse_warning=any(s->s.status===:mcse_unavailable,summaries)
    sampling_warning=_prediction_sampling_warning(context.quality)
    observations=PredictionObservationAdapter._observations(data);order=sortperm(ids)
    binding=_cache_hash((;dataset_id=String(dataset_id),category_levels=data.category_levels,
        observations=collect(zip(ids[order],observations[order]))))
    return _prediction_seal((;schema="bayesianmgmfrm.score_information_report.v1",
        dataset_id=String(dataset_id),observation_ids=ids,observation_binding=binding,
        model_contract=_recovery_model_contract(fit,context),step_contract,
        category_levels=copy(data.category_levels),rating_design=cells,
        n_ratings=Int(total_repetitions),ability_grid=copy(first(profiles).ability_grid),
        rating_rows,test_rows,interval_probability=Float64(interval),
        n_retained_draws=S,chain_ids=copy(context.chain_ids),iterations=copy(context.iterations),
        context.source_sample_hash,context.source_hash_status,
        source_draws_hash=_cache_hash((;fit.draws,fit.chain_ids,fit.iterations)),
        sampling_quality=deepcopy(context.quality),sampling_warning,numerical_warning,mcse_warning,
        status=(sampling_warning || numerical_warning || mcse_warning) ? :warning : :descriptive,
        ability_units=:unit_logit,information_units=:inverse_squared_unit_logit,
        target=:fixed_ability_existing_item_rater,aggregation=:conditionally_independent_integer_repetitions,
        intervals=:pointwise_equal_tailed,predictive_interval=:not_computed,
        scientific_acceptance=:not_established,refit_performed=false))
end
