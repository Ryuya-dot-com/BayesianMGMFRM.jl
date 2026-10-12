# Sort complete joint draws, never independently sorted person marginals.
function _posterior_rank_draws(values, direction, top_k)
    S, N = size(values)
    ranks = Matrix{Float64}(undef, S, N)
    tied = falses(S, N)
    certain = top_k === nothing ? nothing : falses(S, N)
    possible = top_k === nothing ? nothing : falses(S, N)
    for s in 1:S
        order = sortperm(view(values, s, :); rev=direction === :higher)
        first_position = 1
        while first_position <= N
            last_position = first_position
            while last_position < N && values[s, order[last_position+1]] == values[s, order[first_position]]
                last_position += 1
            end
            for position in first_position:last_position
                i = order[position]
                ranks[s, i] = (first_position+last_position)/2
                tied[s, i] = last_position > first_position
                if top_k !== nothing
                    certain[s, i] = last_position <= top_k
                    possible[s, i] = first_position <= top_k
                end
            end
            first_position = last_position+1
        end
    end
    return (; ranks, tied, certain, possible)
end

function _posterior_rank_summary(values, chains, interval)
    lower, upper = _interval_probabilities(interval)
    sorted = sort(values)
    quantile_at(p) = sorted[clamp(ceil(Int, p*length(sorted)), 1, length(sorted))]
    return (; _classification_mean(values, chains)..., sd=length(values)>1 ? std(values) : missing,
        median=quantile_at(.5), lower=quantile_at(lower), upper=quantile_at(upper),
        interval_probability=interval, interval_method=:equal_tailed_empirical_inverse_cdf,
        interval_mcse=:not_computed)
end

"""
    BayesianMGMFRM.posterior_ranking(fit; parameters, direction,
        top_k=nothing, interval=0.90, max_rank_cells=20_000_000)

Summarize posterior ranks of an explicit finite cohort from saved joint draws.
Select at least two distinct estimated person coordinates by exact names from
`recovery_quantities(fit)`, in one ability dimension and scale. Fixed anchors,
other facets and mixed dimensions are rejected. `direction=:higher` puts the
largest value first; `:lower` puts the smallest first. Rank 1 is always first.
No direction, composite ability, population or selected winner is inferred.

Rank people within each original retained draw, preserving posterior dependence.
Exact numeric ties receive the average of their occupied positions (midrank).
Each row reports mean rank and its chain-aware MCSE, rank SD, median and a
pointwise equal-tailed interval (`interval=0.99` requests 99%). Interval endpoints
use the empirical inverse CDF without interpolation, so belong to the observed
rank support. They need not enclose exactly the requested mass, especially with
ties or few draws. These are marginal rank intervals, not a simultaneous ordering
or a credible interval for the mean rank. Interval/quantile MCSE is not computed.

Optional `top_k` is an integer from 1 to the cohort size. `top_k_probability`
contains `lower`, `upper` and `boundary_tie_probability` summaries, each with a
posterior mean and numerical MCSE. A person's best position is one plus the
number strictly ahead; their worst position includes all equals. The lower
probability counts draws with worst position <= k; the upper counts draws with
best position <= k. The difference is the probability of a tie crossing the
selection boundary. These are bounds over unspecified tie-breaking rules, not a
credible interval. With no boundary ties they coincide. No random tie-breaking
or arbitrary input-order preference is introduced. `top_k == n_people` is the
structural event that everyone is included, with probability one and MCSE zero.

Mean MCSE reuses the classification report's autocorrelation-aware estimator.
Constant sampled ranks/events and short/single chains retain unavailable MCSE,
not certainty. Diagnostics and source identity remain attached. Ranks depend on
the selected cohort; they discard the magnitude of ability differences and are
not ranks of posterior means, future-score ranks, practical-equivalence tests,
known-truth rank recovery or calibrated selection guarantees. No all-pairs
matrix, whole-order probability or multidimensional aggregate is computed.

The algorithm uses O(draws * people * log(people)) sorting and O(draws * people)
working storage. `max_rank_cells` bounds the selected draw-by-person matrix
before allocation; it is not a bound on the already loaded fit's memory.
This qualified candidate supports the eight common saved-fit types without
refitting and does not establish their scientific acceptance.
"""
function posterior_ranking(fit::PredictionObservationAdapter.SupportedFit;
        parameters, direction::Symbol, top_k=nothing, interval=0.90,
        max_rank_cells=20_000_000)
    parameters isa Union{AbstractVector,Tuple} || throw(ArgumentError("parameters must be a vector or tuple of exact coordinate names"))
    names = collect(parameters)
    length(names)>=2 && all(p -> p isa AbstractString && !isempty(strip(p)), names) &&
        length(unique(names))==length(names) || throw(ArgumentError("select at least two distinct person coordinate names"))
    direction in (:higher,:lower) || throw(ArgumentError("direction must be :higher or :lower"))
    top_k === nothing || (top_k isa Integer && !(top_k isa Bool) && 1<=top_k<=length(names)) ||
        throw(ArgumentError("top_k must be an integer from one to the cohort size"))
    interval isa Real && !(interval isa Bool) && isfinite(interval) && 0<Float64(interval)<1 ||
        throw(ArgumentError("interval must be representable strictly between zero and one"))
    max_rank_cells isa Integer && !(max_rank_cells isa Bool) && max_rank_cells>0 ||
        throw(ArgumentError("max_rank_cells must be a positive integer"))
    context = _recovery_context(fit)
    big(context.total_draws)*length(names)<=max_rank_cells || throw(ArgumentError("ranking exceeds max_rank_cells; narrow the cohort or raise the explicit budget"))
    lookup = Dict(r.parameter => r for r in context.coordinates)
    all(p -> haskey(lookup,p), names) || throw(ArgumentError("unknown ranking coordinate"))
    coordinates = [lookup[p] for p in names]
    descriptions = [_recovery_quantity(r,context.spec) for r in coordinates]
    d = first(descriptions)
    all(r -> r.block===:person && !r.fixed &&
        (r.dimension,r.parameter_space)==(d.dimension,d.parameter_space),descriptions) ||
        throw(ArgumentError("ranking requires estimated person locations in one dimension and scale"))
    selected = hcat([r.values for r in coordinates]...)
    draws = _posterior_rank_draws(selected,direction,top_k)
    chains = length(unique(context.chain_ids))
    rows = map(eachindex(names)) do i
        top = if top_k === nothing
            nothing
        else
            fixed = top_k==length(names)
            (; lower=_classification_mean(view(draws.certain,:,i),chains;fixed),
                upper=_classification_mean(view(draws.possible,:,i),chains;fixed),
                boundary_tie_probability=_classification_mean(draws.possible[:,i] .& .!draws.certain[:,i],chains;fixed))
        end
        (; descriptions[i]..., rank=_posterior_rank_summary(draws.ranks[:,i],chains,Float64(interval)),
            tie_probability=_classification_mean(view(draws.tied,:,i),chains), top_k_probability=top)
    end
    mcse_warning = any(rows) do r
        r.rank.mcse.status!==:available || r.tie_probability.mcse.status!==:available ||
            (r.top_k_probability!==nothing && any(v -> !(v.mcse.status in (:available,:structurally_fixed)),values(r.top_k_probability)))
    end
    boundary_ties_observed = top_k!==nothing && any(draws.possible .!= draws.certain)
    sampling_warning = _prediction_sampling_warning(context.quality)
    return _prediction_seal((; schema="bayesianmgmfrm.posterior_ranking.v1",
        direction, top_k=top_k===nothing ? nothing : Int(top_k), n_people=length(names),
        interval_probability=Float64(interval), interval_method=:equal_tailed_empirical_inverse_cdf,
        tie_policy=:exact_numeric_midrank_with_top_k_bounds, boundary_ties_observed,
        cohort_basis=:explicit_selected_people, rows,
        model_contract=_recovery_model_contract(fit,context),
        n_retained_draws=context.total_draws, chain_ids=copy(context.chain_ids), iterations=copy(context.iterations),
        evaluated_draws_hash=_cache_hash((;parameters=names,values=selected)),
        context.source_sample_hash, context.source_hash_status,
        sampling_quality=deepcopy(context.quality), sampling_warning, mcse_warning,
        status=sampling_warning || mcse_warning || boundary_ties_observed ? :warning : :descriptive,
        scientific_acceptance=:not_established, scope=:conditional_finite_cohort_rank_uncertainty))
end
