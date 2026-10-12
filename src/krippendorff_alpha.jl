"""
    BayesianMGMFRM.krippendorff_alpha(data::FacetData; item, level,
        dataset_id, observation_ids, response_ids=nothing,
        max_category_pairs=1_000_000)

Compute observed-score Krippendorff alpha for one explicitly selected item
(use its label, not its index). `level` is required: `:nominal` or `:ordinal`.
No model fit or posterior draws are used. Integer category codes and their order
come from `data.category_levels`; nominal codes are labels, not distances.
Ordinal distances use pairable category frequencies, not squared score gaps.

Unique rating IDs are in data-row order. Supply globally unique response IDs
explicitly or through `response_id` metadata, as in [`rater_agreement`](@ref).
A response must identify the same person and recorded context. Duplicate
response-item-rater rows are rejected; repeated occasions need separate response
IDs. Items are never pooled. This checks recorded identity, not construct validity.

Missing ratings are absent rows (FacetData rejects literal missing scores).
Units with one rating are listed but excluded from both disagreements and the
category margins. Entirely unobserved units cannot be counted from these data.
Each usable unit with `m` ratings contributes its ordered pairs weighted by
`1/(m-1)`, giving total coincidence mass `m`, rather than equal weight per pair.
Returns alpha, observed/expected disagreement, coincidence/distance matrices,
marginal counts and a unit ledger with included, singleton and other-item IDs.
Zero expected disagreement and no pairable units yield `missing` with distinct
statuses. Negative alpha is retained; no cutoff or clipping is applied.

The result is descriptive: no confidence/credible interval, SE, bootstrap,
missingness correction, severity adjustment, ICC or population guarantee.
Ordinal distance matrices are specific to these pairable marginal frequencies.
`max_category_pairs` bounds each dense K-by-K matrix before allocation; there is
no dense rater-pair roster. Use `fit_report(...; reporting=(dataset_id=...,
observation_ids=..., alpha=(item=..., level=:ordinal, response_ids=...)))`
to include this observed-data result in existing report bundles.

Reference: Krippendorff, *Computing Krippendorff's Alpha-Reliability* (2011,
literature updated 2013), sections C and D.
"""
function krippendorff_alpha(data::FacetData; item, level::Symbol,
        dataset_id::AbstractString, observation_ids, response_ids=nothing,
        max_category_pairs::Integer=1_000_000)
    level in (:nominal,:ordinal) || throw(ArgumentError("level must be :nominal or :ordinal"))
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    index=findfirst(isequal(item),data.item_levels)
    index===nothing && throw(ArgumentError("item must be an existing item label"))
    K=length(data.category_levels)
    !(max_category_pairs isa Bool) && max_category_pairs>0 && big(K)^2<=max_category_pairs ||
        throw(ArgumentError("category matrix exceeds max_category_pairs or the limit is invalid"))
    units=_rating_response_units(data,response_ids,observation_ids)
    observed=zeros(K,K); margins=zeros(Int,K)
    rows=NamedTuple[];included=Int[];singletons=Int[]
    for key in sort!(collect(keys(units.groups));by=repr)
        key[2]==index || continue
        ns=units.groups[key];m=length(ns)
        usable=m>=2
        counts=zeros(Int,K)
        for n in ns
            counts[data.category[n]]+=1
        end
        if usable
            active=findall(>(0),counts)
            for c in active, k in active
                observed[c,k]+=Float64(counts[c])*(counts[k]-(c==k))/(m-1)
            end
            margins .+= counts
            append!(included,ns)
        else
            append!(singletons,ns)
        end
        push!(rows,(;response_id=key[1],person=data.person_levels[data.person[first(ns)]],
            n_ratings=m,status=usable ? :pairable : :singleton,
            observation_ids=units.observation_ids[ns],category_counts=counts))
    end
    n=sum(margins)
    midpoints=cumsum(Float64.(margins)).-margins./2
    distance=[level===:nominal ? Float64(c!=k) : (midpoints[c]-midpoints[k])^2 for c in 1:K,k in 1:K]
    expected=n==0 ? zeros(K,K) :
        [Float64(margins[c])*(margins[k]-(c==k))/(n-1) for c in 1:K,k in 1:K]
    Do=n==0 ? missing : sum(observed.*distance)/n
    De=n==0 ? missing : sum(expected.*distance)/n
    status=n==0 ? :no_pairable_units : De==0 ? :zero_expected_disagreement : :descriptive
    alpha=status===:descriptive ? 1-Do/De : missing
    ids=units.observation_ids
    selected=findall(==(index),data.item)
    return _prediction_seal((;schema="bayesianmgmfrm.krippendorff_alpha.v1",
        dataset_id=String(dataset_id),item=data.item_levels[index],level,alpha,status,
        observed_disagreement=Do,expected_disagreement=De,
        n_units=length(rows),n_pairable_units=count(r->r.status===:pairable,rows),
        n_singleton_units=length(singletons),n_ratings=length(selected),n_pairable_ratings=n,
        category_levels=copy(data.category_levels),marginal_counts=margins,
        observed_coincidences=observed,expected_coincidences=expected,squared_distances=distance,
        unit_rows=rows,observation_ids=copy(ids),response_ids=units.response_ids,
        included_observation_ids=ids[sort!(included)],singleton_observation_ids=ids[sort!(singletons)],
        other_item_observation_ids=ids[findall(!=(index),data.item)],
        matching=(;unit=:response_item,context_roles=units.matching_roles,duplicate_policy=:error),
        response_binding=units.response_binding,
        data_binding=_cache_hash((;data,observation_ids=ids,response_ids=units.response_ids)),
        weighting=:ordered_coincidences_divided_by_unit_rating_count_minus_one,
        target=:observed_score_agreement,interval=:not_computed,se=:not_computed,
        missing_rating_policy=:absent_rows,unobserved_units=:not_identifiable,
        scientific_acceptance=:not_established))
end
