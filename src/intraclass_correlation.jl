"""
    BayesianMGMFRM.intraclass_correlation(data::FacetData; item, model,
        definition, unit, score_scale, dataset_id, observation_ids,
        response_ids=nothing)

Compute a two-way ANOVA, observed-score ICC for one explicit item label and a
complete response-by-rater rectangle. Every response must have exactly one
rating from the same set of at least two raters; at least two responses are
required. Incomplete designs are rejected, without deletion or imputation.
Response/rating identities follow [`rater_agreement`](@ref). Items are not pooled.

All choices are required. `model=:two_way_random` treats raters as a sample from
a rater population; `:two_way_mixed` targets this fixed panel. `definition` is
`:agreement` (systematic rater differences count) or `:consistency` (additive
rater differences are removed). `unit=:single` concerns one rating;
`:average` concerns the arithmetic mean of all K recorded raters. The model
choice changes generalization, not the formula for a given definition/unit.

`score_scale=:interval` explicitly declares that equal gaps between the integer
score codes have substantive meaning. This is a user assumption, not a property
established by FacetData or the ICC. Nominal/ordinal scale choices are rejected;
consider [`krippendorff_alpha`](@ref) for nominal/ordinal agreement instead.

Return the coefficient, numerator/denominator, ANOVA sums of squares, degrees of
freedom and mean squares, response/rater ledger and identities. Negative values
with a positive denominator are retained, not clipped. A nonpositive denominator
yields `missing` with an explicit status; any finite raw ratio is retained for
inspection, not interpreted as reliability. Repeated responses from one person
are counted and disclosed; there is no independence or population guarantee.

This is an unadjusted observed-score method-of-moments point estimate, independent
of model draws. No SE, confidence/credible interval, significance test, one-way
ICC, missing-data mixed model or latent-trait reliability is provided. Fit-report
integration uses `reporting=(dataset_id=..., observation_ids=..., icc=(item=...,
model=:two_way_random, definition=:agreement, unit=:single, score_scale=:interval,
response_ids=...))`. No MCMC is run.

References: Shrout & Fleiss (1979), doi:10.1037/0033-2909.86.2.420;
Liljequist et al. (2019), doi:10.1371/journal.pone.0219854; the psych package
ICC documentation for the McGraw-Wong random/mixed interpretation.
"""
function intraclass_correlation(data::FacetData; item, model::Symbol,
        definition::Symbol, unit::Symbol, score_scale::Symbol,
        dataset_id::AbstractString, observation_ids, response_ids=nothing)
    model in (:two_way_random,:two_way_mixed) || throw(ArgumentError("model must be :two_way_random or :two_way_mixed"))
    definition in (:agreement,:consistency) || throw(ArgumentError("definition must be :agreement or :consistency"))
    unit in (:single,:average) || throw(ArgumentError("unit must be :single or :average"))
    score_scale===:interval || throw(ArgumentError("score_scale=:interval is required; equal score gaps must be substantively justified"))
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    index=findfirst(isequal(item),data.item_levels)
    index===nothing && throw(ArgumentError("item must be an existing item label"))
    units=_rating_response_units(data,response_ids,observation_ids)
    selected=findall(==(index),data.item)
    keys_selected=sort!([key for key in keys(units.groups) if key[2]==index];by=repr)
    raters=sort!(unique(data.rater[selected]))
    n=length(keys_selected); k=length(raters)
    n>=2 && k>=2 || throw(ArgumentError("ICC requires at least two response units and two raters on the selected item"))
    for key in keys_selected
        sort(data.rater[units.groups[key]])==raters ||
            throw(ArgumentError("ICC requires the same complete rater roster on every selected response; incomplete designs are not deleted or imputed"))
    end
    # Allocation is bounded by the validated input rectangle, not an unobserved grid.
    ratings=Matrix{Float64}(undef,n,k); rows=NamedTuple[]
    for (i,key) in enumerate(keys_selected)
        ns=sort(units.groups[key];by=j->data.rater[j])
        ratings[i,:]=data.score[ns]
        push!(rows,(;response_id=key[1],person=data.person_levels[data.person[first(ns)]],
            observation_ids=units.observation_ids[ns],scores=copy(data.score[ns])))
    end
    centered=ratings .- ratings[1,1]
    grand=mean(centered); rowmeans=mean(centered;dims=2); colmeans=mean(centered;dims=1)
    ss_rows=k*sum(abs2,rowmeans .- grand)
    ss_raters=n*sum(abs2,colmeans .- grand)
    ss_error=sum(abs2,centered .- rowmeans .- colmeans .+ grand)
    ms_rows=ss_rows/(n-1); ms_raters=ss_raters/(k-1); ms_error=ss_error/((n-1)*(k-1))
    numerator=ms_rows-ms_error
    denominator=unit===:single ? ms_rows+(k-1)*ms_error : ms_rows
    definition===:agreement && (denominator+=(unit===:single ? k : 1)*(ms_raters-ms_error)/n)
    status=denominator==0 ? :zero_denominator : denominator<0 ? :negative_denominator : :descriptive
    raw_ratio=denominator==0 ? missing : numerator/denominator
    icc=status===:descriptive ? raw_ratio : missing
    anova_rows=[(;source=:response,ss=ss_rows,df=n-1,ms=ms_rows),
        (;source=:rater,ss=ss_raters,df=k-1,ms=ms_raters),
        (;source=:residual,ss=ss_error,df=(n-1)*(k-1),ms=ms_error)]
    n_people=length(unique(data.person[selected]))
    ids=units.observation_ids
    return _prediction_seal((;schema="bayesianmgmfrm.intraclass_correlation.v1",
        dataset_id=String(dataset_id),item=data.item_levels[index],model,definition,unit,score_scale,
        icc,status,numerator,denominator,raw_ratio,anova_rows,
        n_units=n,n_raters=k,n_ratings=length(selected),n_people,
        repeated_person_units=n>n_people,raters=copy(data.rater_levels[raters]),unit_rows=rows,
        observation_ids=copy(ids),response_ids=units.response_ids,
        included_observation_ids=ids[selected],other_item_observation_ids=ids[findall(!=(index),data.item)],
        matching=(;unit=:response_item,context_roles=units.matching_roles,duplicate_policy=:error),
        response_binding=units.response_binding,
        data_binding=_cache_hash((;data,observation_ids=ids,response_ids=units.response_ids)),
        estimator=:two_way_anova_method_of_moments,target=:observed_score_reliability,
        rater_generalization=model===:two_way_random ? :rater_population_assumed : :fixed_panel,
        average_rating_count=unit===:average ? k : 1,interval=:not_computed,se=:not_computed,
        missing_rating_policy=:reject_incomplete,scientific_acceptance=:not_established))
end
