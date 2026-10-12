function _rating_response_units(data, response_ids, observation_ids)
    ids = PredictionObservationAdapter._ids(observation_ids, data.n, "observation_ids")
    recorded = haskey(data.optional, :response_id) ?
        [data.optional_levels[:response_id][i] for i in data.optional[:response_id]] : nothing
    responses = response_ids === nothing ? recorded : response_ids
    responses isa AbstractVector && length(responses) == data.n ||
        throw(ArgumentError("provide response_ids in fitted-row order or response_id metadata; person-item matching is not inferred"))
    all(x -> (x isa AbstractString && !isempty(strip(x))) || (x isa Integer && !(x isa Bool)), responses) ||
        throw(ArgumentError("response IDs must be nonempty strings or integers"))
    recorded === nothing || isequal(responses, recorded) ||
        throw(ArgumentError("supplied response_ids conflict with the fitted response_id metadata"))
    roles = sort!([r for r in keys(data.optional) if r !== :response_id]; by=string)
    contexts = Dict{Any,Any}()
    groups = Dict{Any,Vector{Int}}()
    seen = Set{Any}()
    for n in 1:data.n
        response = responses[n]
        context = (data.person[n], Tuple(data.optional[r][n] for r in roles))
        haskey(contexts, response) && !isequal(contexts[response], context) &&
            throw(ArgumentError("a response ID spans different persons or optional context metadata; separate responses/occasions explicitly"))
        contexts[response] = context
        key = (response, data.item[n], data.rater[n])
        key in seen && throw(ArgumentError("duplicate response-item-rater rating; do not average or cross-pair repeated ratings implicitly"))
        push!(seen, key)
        push!(get!(groups, (response, data.item[n]), Int[]), n)
    end
    return (; observation_ids=ids, response_ids=collect(responses), groups,
        matching_roles=roles,
        response_binding=_cache_hash(collect(zip(ids[sortperm(ids)], responses[sortperm(ids)]))))
end

function _rater_agreement_units(data, response_ids, observation_ids, max_rater_pairs)
    R = length(data.rater_levels)
    big(R)*(R-1)÷2 <= max_rater_pairs || throw(ArgumentError("rater-pair roster exceeds max_rater_pairs"))
    units = _rating_response_units(data, response_ids, observation_ids)
    groups, ids = units.groups, units.observation_ids
    by_pair = Dict((a,b) => Tuple{Int,Int}[] for a in 1:R for b in a+1:R)
    paired = Set{Int}()
    for key in sort!(collect(keys(groups)); by=repr)
        ns = sort(groups[key]; by=n -> data.rater[n])
        for i in eachindex(ns), j in i+1:length(ns)
            a,b = ns[i],ns[j]
            push!(by_pair[(data.rater[a],data.rater[b])], (a,b))
            push!(paired,a); push!(paired,b)
        end
    end
    return (; observation_ids=ids, response_ids=units.response_ids, by_pair,
        matching_roles=units.matching_roles, n_response_items=length(groups),
        unmatched_observation_ids=ids[[n for n in 1:data.n if n ∉ paired]],
        response_binding=units.response_binding)
end

function _agreement_observed_se(indicators, persons, se_unit)
    groups = unique(persons)
    G, M = length(groups), length(indicators)
    status = M == 0 ? :no_common_units : se_unit === :none ? :not_requested :
        G < 2 ? :insufficient_persons : :approximate
    value = missing
    if status === :approximate
        rate = sum(indicators)/M
        totals = [sum(indicators[i]-rate for i in eachindex(indicators) if persons[i] == g) for g in groups]
        value = sqrt(G/(G-1)*sum(abs2,totals))/M
        value == 0 && (status = :empirical_zero_cluster_variance)
    end
    return (; value, status, unit=se_unit, n_persons=G,
        method=se_unit === :person ? :cluster_ratio_linearization : :not_computed)
end

function _agreement_metric(indicators, persons, expected, chains, interval, se_unit; structural_one=false)
    M = length(indicators)
    observed = M == 0 ? missing : sum(indicators)/M
    se = _agreement_observed_se(indicators, persons, se_unit)
    if M == 0
        return (; observed_count=0, observed_rate=missing, observed_se=se,
            expected_mean=missing, expected_median=missing, expected_lower=missing, expected_upper=missing,
            observed_minus_expected_mean=missing, mcse=nothing, status=:no_common_units)
    end
    values = structural_one ? ones(length(expected)) : expected ./ M
    lower, upper = _interval_probabilities(interval)
    mcse = only(_posterior_mcse_rows(reshape(values,:,1), ["expected_agreement"], chains;
        probabilities=(lower,.5,upper), parameter_space=:probability,
        structurally_fixed_parameters=structural_one ? Set(["expected_agreement"]) : Set{String}()))
    return (; observed_count=sum(indicators), observed_rate=observed, observed_se=se,
        expected_mean=mean(values), expected_median=mcse.quantiles[2].estimate,
        expected_lower=first(mcse.quantiles).estimate, expected_upper=last(mcse.quantiles).estimate,
        observed_minus_expected_mean=observed-mean(values), mcse,
        status=structural_one ? :all_categories_within_tolerance :
            mcse.mcse_status === :available ? :descriptive : :mcse_unavailable)
end

function _agreement_row(data, links, sums, chains, interval, se_unit, adjacent)
    persons = [data.person[a] for (a,b) in links]
    exact = [data.category[a] == data.category[b] for (a,b) in links]
    nearby = [abs(data.category[a]-data.category[b]) <= adjacent for (a,b) in links]
    return (; n_opportunities=length(links), n_persons=length(unique(persons)),
        exact=_agreement_metric(exact, persons, sums[:,1], chains, interval, se_unit),
        adjacent=_agreement_metric(nearby, persons, sums[:,2], chains, interval, se_unit;
            structural_one=adjacent == length(data.category_levels)-1))
end

function _agreement_expected_sums(probabilities, links, adjacent)
    S, _, K = size(probabilities)
    sums = zeros(S,2)
    for (a,b) in links, s in 1:S
        for k in 1:K
            sums[s,1] += probabilities[s,a,k]*probabilities[s,b,k]
            for l in max(1,k-adjacent):min(K,k+adjacent)
                sums[s,2] += probabilities[s,a,k]*probabilities[s,b,l]
            end
        end
    end
    return sums
end

_agreement_draw_count(fit::_ModelComparisonFit) = size(fit.draws,1)
_agreement_draw_count(fit::Union{_RecordedMGMFRMFit,_FixedQMFRMFit}) = fit.record.run.total_draws

"""
    BayesianMGMFRM.rater_agreement(fit; dataset_id, observation_ids,
        response_ids=nothing, interval=0.95, adjacent=1, se_unit=:none,
        max_prediction_cells=20_000_000, max_rater_pairs=10_000)

Compare observed and model-expected agreement for the same response and item.
Uses the eight common saved-fit types, all original retained draws and category
probabilities. Supply unique rating `observation_ids` in fitted-row order and
globally unique response identities through fitted `response_id` metadata or an
explicit `response_ids` vector (nonempty strings or integers). Repeated response
IDs across raters/items are expected; one ID must belong to one person and one
combination of all recorded optional metadata. Supplied and fitted IDs must agree.
Duplicate response-item-rater rows are rejected. Matching by person-item alone
is never inferred, and omitted context cannot be verified from the scores.

Return overall, per-rater and every unordered fitted-rater-pair row, retaining
zero-overlap rows and unpaired observation IDs. Each common response-item and
unordered rater pair contributes one opportunity. Overall weights are equal per
opportunity, not per person, response or rater pair. Per-rater totals count its
incident opportunities, so their denominators sum to twice the overall denominator.
The opportunity ledger preserves both rating IDs and the response/item/person.

`exact` uses the original category labels. `adjacent` includes exact agreement
and categories at most the declared number of ordinal positions apart. It does
not realign a rater's lowest observed PCM category as some FACETS reports do.
For each joint posterior draw, expected exact agreement is `sum_k p_A(k)*p_B(k)`;
adjacent agreement sums the corresponding category pairs. Conditional independence
is assumed given that draw. Averaging separately by rater before multiplying
would lose shared-parameter dependence and is not used.

Intervals are central posterior intervals for the *conditional expected rate*
on these fitted responses and raters, not posterior predictive intervals for
realized agreement, population CIs or evidence for a dependence mechanism.
The mean observed-minus-expected discrepancy is descriptive, not a p-value.
MCMC MCSE for expected means/quantiles is reported separately; short/degenerate
draws retain unavailable status. If the tolerance spans the whole category scale,
the adjacent probability is structurally one and labeled accordingly.

`se_unit=:person` optionally adds a ratio-linearization SE for observed rates
with independent, exchangeable person clusters, preserving all within-person
opportunities together. It conditions on these raters/items and does not handle
arbitrary crossed dependence or sampling-design weights. Default `:none` reports
no observed-rate SE. Fewer than two persons is unavailable; zero empirical cluster
variance is flagged. No observed CI, kappa, automatic cutoff or reliability
correction is computed. Resource limits reject oversized extraction/rosters
before allocating the predictions; they do not subsample or omit pairs.
"""
function rater_agreement(fit::PredictionObservationAdapter.SupportedFit;
        dataset_id::AbstractString, observation_ids, response_ids=nothing,
        interval::Real=.95, adjacent::Integer=1, se_unit::Symbol=:none,
        max_prediction_cells::Integer=20_000_000, max_rater_pairs::Integer=10_000)
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    _interval_probabilities(interval)
    se_unit in (:none,:person) || throw(ArgumentError("se_unit must be :none or :person"))
    all(x -> !(x isa Bool) && x > 0,(max_prediction_cells,max_rater_pairs)) ||
        throw(ArgumentError("resource limits must be positive integers"))
    data = PredictionObservationAdapter._fit_data(fit)
    K = length(data.category_levels)
    !(adjacent isa Bool) && 0 <= adjacent < K || throw(ArgumentError("adjacent must be an integer from zero to the category count minus one"))
    fit isa _FixedQMFRMFit && _fixed_q_result_spec((;fit.record)).family !== :mfrm &&
        throw(ArgumentError("agreement requires canonical fixed-MFRM records; legacy v1 is unsupported"))
    units = _rater_agreement_units(data, response_ids, observation_ids, max_rater_pairs)
    S = _agreement_draw_count(fit)
    big(S)*data.n*K <= max_prediction_cells || throw(ArgumentError("agreement probabilities exceed max_prediction_cells; raise the explicit budget or use a separately justified analysis"))
    p = prediction_observations(fit;dataset_id,observation_ids,include_probabilities=true)
    PredictionObservationAdapter._criterion_draws(p)
    _comparison_prediction_binding(p)
    probabilities = p.probabilities
    chains = length(unique(p.chain_ids))
    R = length(data.rater_levels)
    all_links = Tuple{Int,Int}[]
    rater_links = [Tuple{Int,Int}[] for _ in 1:R]
    rater_sums = [zeros(S,2) for _ in 1:R]
    overall_sums = zeros(S,2)
    pair_rows = NamedTuple[]
    expected_draw_hashes = String[]
    ledger = NamedTuple[]
    for (a,b) in sort!(collect(keys(units.by_pair)))
        links = units.by_pair[(a,b)]
        sums = _agreement_expected_sums(probabilities,links,adjacent)
        push!(expected_draw_hashes,_cache_hash((;pair=(a,b),sums)))
        push!(pair_rows,merge((;rater_a=data.rater_levels[a],rater_b=data.rater_levels[b]),
            _agreement_row(data,links,sums,chains,interval,se_unit,adjacent)))
        append!(all_links,links)
        append!(rater_links[a],links); append!(rater_links[b],links)
        overall_sums .+= sums
        rater_sums[a] .+= sums; rater_sums[b] .+= sums
        for (i,j) in links
            push!(ledger,(;response_id=units.response_ids[i], person=data.person_levels[data.person[i]],
                item=data.item_levels[data.item[i]],rater_a=data.rater_levels[a],rater_b=data.rater_levels[b],
                observation_a=units.observation_ids[i],observation_b=units.observation_ids[j],
                category_a=data.score[i],category_b=data.score[j]))
        end
    end
    overall = _agreement_row(data,all_links,overall_sums,chains,interval,se_unit,adjacent)
    raters = [merge((;rater=data.rater_levels[r]),
        _agreement_row(data,rater_links[r],rater_sums[r],chains,interval,se_unit,adjacent)) for r in 1:R]
    sampling_warning = _prediction_sampling_warning(p.sampling_quality)
    mcse_warning = any(row -> row.n_opportunities > 0 &&
        any(m -> m.mcse.mcse_status ∉ (:available,:structurally_fixed),(row.exact,row.adjacent)),
        Iterators.flatten(((overall,),raters,pair_rows)))
    result = (; schema="bayesianmgmfrm.rater_agreement.v1",dataset_id=String(dataset_id),
        overall,raters,rater_pairs=pair_rows,opportunities=ledger,
        observation_ids=units.observation_ids,response_ids=units.response_ids,
        unmatched_observation_ids=units.unmatched_observation_ids,
        response_binding=units.response_binding,p.observation_binding,p.training_binding,
        matching=(;unit=:response_item,context_roles=units.matching_roles,
            duplicate_policy=:error,response_source=response_ids === nothing ? :fitted_metadata : :explicit_vector),
        weighting=:equal_unordered_pair_opportunity,category_levels=copy(p.category_levels),
        adjacent,interval_probability=Float64(interval),interval_method=:equal_tailed,
        expected_target=:conditional_expected_agreement_existing_responses,
        conditional_independence_assumed=true,se_unit,
        observed_interval=:not_computed,predictive_interval=:not_computed,kappa=:not_computed,
        mechanism_classification=:not_performed,model_contract=deepcopy(p.model),
        n_retained_draws=S,chain_ids=copy(p.chain_ids),iterations=copy(p.iterations),
        expected_draws_hash=_cache_hash(expected_draw_hashes),
        p.source_sample_hash,p.source_hash_status,sampling_quality=deepcopy(p.sampling_quality),sampling_warning,
        mcse_warning,status=isempty(all_links) ? :no_common_units :
            (sampling_warning || mcse_warning) ? :warning : :descriptive,
        scientific_acceptance=:not_established)
    return _prediction_seal(result)
end
