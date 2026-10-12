# Common reporting is opt-in: study identities, reliability cohorts and response
# matching are analytical choices, not defaults that a report can infer.
function _saved_reporting_request(fit, request; prediction_request=nothing)
    request === nothing && return nothing
    request isa NamedTuple || throw(ArgumentError("reporting must be a named tuple"))
    Set(keys(request)) ⊆ Set((:dataset_id,:observation_ids,:category,:agreement,:reliability,:classification,:ranking,:alpha,:icc)) ||
        throw(ArgumentError("unknown reporting option"))
    ranking=get(request,:ranking,nothing)
    ranking===nothing || (ranking isa NamedTuple &&
        Set(keys(ranking)) ⊆ Set((:parameters,:direction,:top_k,:interval,:max_rank_cells))) ||
        throw(ArgumentError("ranking must be a named tuple with parameters, direction and optional top_k, interval, max_rank_cells"))
    classification=get(request,:classification,nothing)
    classification===nothing || (classification isa NamedTuple &&
        Set(keys(classification)) ⊆ Set((:parameters,:cutoff,:pass_probability,:interval))) ||
        throw(ArgumentError("classification must be a named tuple with parameters, cutoff, pass_probability and optional interval"))
    category=get(request,:category,nothing);agreement=get(request,:agreement,nothing)
    alpha=get(request,:alpha,nothing);icc=get(request,:icc,nothing)
    all(x->x===nothing || x isa NamedTuple,(category,agreement,alpha,icc)) ||
        throw(ArgumentError("reporting.category, reporting.agreement, reporting.alpha and reporting.icc must be named tuples or nothing"))
    for options in (category,agreement,alpha,icc)
        options===nothing && continue
        isempty(intersect(Set(keys(options)),Set((:dataset_id,:observation_ids)))) ||
            throw(ArgumentError("supply shared dataset_id and observation_ids in reporting, not individual sections"))
    end
    cohorts=get(request,:reliability,())
    cohorts isa Union{Tuple,AbstractVector} || throw(ArgumentError("reporting.reliability must be a tuple or vector of named cohorts"))
    names=String[]
    for cohort in cohorts
        cohort isa NamedTuple && haskey(cohort,:id) && cohort.id isa AbstractString &&
            !isempty(strip(cohort.id)) && !(cohort.id in names) ||
            throw(ArgumentError("each reliability cohort needs a unique nonempty string id"))
        Set(keys(cohort)) ⊆ Set((:id,:parameters,:target,:weights)) ||
            throw(ArgumentError("unknown reliability cohort option"))
        push!(names,String(cohort.id))
    end
    dataset_id=get(request,:dataset_id,nothing);ids=get(request,:observation_ids,nothing)
    if category!==nothing || agreement!==nothing || alpha!==nothing || icc!==nothing
        dataset_id isa AbstractString && !isempty(strip(dataset_id)) ||
            throw(ArgumentError("category/agreement/alpha/icc reporting requires a nonempty shared dataset_id"))
        ids=PredictionObservationAdapter._ids(ids,PredictionObservationAdapter._fit_data(fit).n,"observation_ids")
        dataset_id=String(dataset_id)
        if prediction_request!==nothing
            dataset_id==prediction_request.dataset_id && ids==prediction_request.observation_ids ||
                throw(ArgumentError("reporting and prediction criteria must use the same dataset and observation IDs"))
        end
    else
        dataset_id===nothing && ids===nothing ||
            throw(ArgumentError("reporting identities require a category, agreement, alpha or icc request"))
    end
    prepared=(;dataset_id,observation_ids=ids,category,agreement,reliability=Tuple(cohorts))
    classification===nothing || (prepared=merge(prepared,(;classification)))
    ranking===nothing || (prepared=merge(prepared,(;ranking)))
    alpha===nothing || (prepared=merge(prepared,(;alpha)))
    icc===nothing || (prepared=merge(prepared,(;icc)))
    return deepcopy(prepared)
end

# Request dictionaries are dimension maps, not report field names. Preserve
# their key type in records so integer dimensions survive JSON/public projection.
_saved_reporting_request_record(value) = value
_saved_reporting_request_record(value::NamedTuple) =
    (;(k=>_saved_reporting_request_record(v) for (k,v) in pairs(value))...)
_saved_reporting_request_record(value::Tuple) = map(_saved_reporting_request_record,value)
_saved_reporting_request_record(value::AbstractVector) = map(_saved_reporting_request_record,value)
_saved_reporting_request_record(value::AbstractDict) =
    [(;dimension=key,value=_saved_reporting_request_record(item)) for (key,item) in sort(collect(pairs(value));by=p->(string(typeof(first(p))),string(first(p))))]

_saved_result_payload(result) = (; source_result_hash=result.content_hash,
    source_result_schema=result.schema, result_status=result.status,
    result=Base.structdiff(result,(;schema=nothing,content_hash=nothing)))

function _saved_reporting_warnings(result; cohort_id=nothing)
    rows=NamedTuple[]
    function warning(code,message,action)
        push!(rows,(;code,severity=:warning,cohort_id,message=message,action))
    end
    result.sampling_warning && warning(:sampling_warning,
        "Stored MCMC diagnostics contain warnings; computed results do not establish convergence.",:inspect_sampler_and_parameter_diagnostics)
    mcse_warning=get(result,:mcse_warning,false) ||
        (haskey(result,:mcse) && result.mcse.status!==:available)
    mcse_warning && warning(:mcse_unavailable,
        "Some Monte Carlo error estimates are unavailable; constant sampled indicators do not establish certainty.",:inspect_quantity_mcse)
    get(result,:numerical_warning,false) && warning(:numerical_warning,
        "Some numerical summaries are unavailable; the report retains their status.",:inspect_numerical_availability)
    get(result,:review_recommended,false) && warning(:category_review,
        "Category-use or step-order flags require substantive review; no category collapse is implied.",:review_category_support_and_ordering)
    result.status===:no_common_units && warning(:no_common_units,
        "No matched rating opportunities are available; agreement is unavailable, not zero.",:review_response_matching)
    !isempty(get(result,:empirical_zero_variance_parameters,())) && warning(:empirical_zero_variance,
        "Some selected coordinates have constant saved draws; this is not structural certainty.",:inspect_coordinate_draws)
    return rows
end

function _saved_summary_columns(summary; prefix="")
    values = summary===nothing ? (;fixed=missing,mean=missing,sd=missing,lower=missing,upper=missing,
        interval_probability=missing,interval_method=:not_applicable,mean_mcse=missing,
        mcse_status=:not_applicable,summary_status=:not_applicable) :
        (;summary.fixed,summary.mean,summary.sd,summary.lower,summary.upper,summary.interval_probability,
            summary.interval_method,mean_mcse=summary.mcse===nothing ? missing : summary.mcse.mean_mcse,
            mcse_status=summary.mcse===nothing ? :unavailable : summary.mcse.mcse_status,
            summary_status=summary.status)
    return (;(Symbol(prefix,String(key))=>value for (key,value) in pairs(values))...)
end

function _saved_category_tables(r)
    usage_rows=[merge(Base.structdiff(row,(;expected=nothing)),_saved_summary_columns(row.expected;prefix="expected_")) for row in r.usage_rows]
    threshold_rows=[merge(Base.structdiff(row,(;summary=nothing,gap=nothing,order_probability=nothing)),
        _saved_summary_columns(row.summary),_saved_summary_columns(row.gap;prefix="gap_"),
        (;order_probability=row.order_probability===nothing ? missing : row.order_probability.mean,
            order_mean_mcse=row.order_probability===nothing ? missing : row.order_probability.mcse.mean_mcse,
            order_mcse_status=row.order_probability===nothing ? :not_applicable : row.order_probability.mcse.mcse_status)) for row in r.threshold_rows]
    curve_rows=[merge(Base.structdiff(row,(;probability=nothing)),_saved_summary_columns(row.probability)) for row in r.curve_rows]
    crossing_rows=[merge(Base.structdiff(row,(;crossing=nothing)),_saved_summary_columns(row.crossing)) for row in r.crossing_rows]
    return (;usage_rows,threshold_rows,curve_rows,crossing_rows,profile_rows=r.profiles)
end

function _saved_category_section(fit,request,policy)
    options=request.category
    options===nothing && return merge(_fit_report_not_requested(),(;reason="No category report requested."))
    interpretation="Conditional expected category use on the observed rating allocation; posterior SD and pointwise equal-tailed intervals omit new-rating realization noise. Native step ownership and fixed-ability profile conditions are retained. Steps and adjacent equal-probability ability crossings differ. No HDI, simultaneous band, automatic category collapse or new-level guarantee. Every original retained draw contributes, independently of report prediction draw selection. Detailed quantile MCSE, source identity and controls remain in result."
    section=_fit_report_section(policy) do
        r=category_report(fit;request.dataset_id,request.observation_ids,options...)
        (;_saved_result_payload(r)...,_saved_category_tables(r)...,warning_rows=_saved_reporting_warnings(r))
    end
    return merge((;request=_saved_reporting_request_record(options),interpretation),section)
end

function _saved_agreement_metric(metric)
    (;metric.observed_rate,metric.expected_mean,metric.expected_lower,metric.expected_upper,
        observed_se=metric.observed_se.value,observed_se_status=metric.observed_se.status,
        mean_mcse=metric.mcse===nothing ? missing : metric.mcse.mean_mcse,
        mcse_status=metric.mcse===nothing ? :no_common_units : metric.mcse.mcse_status,
        metric_status=metric.status)
end

function _saved_agreement_rows(r)
    rows=NamedTuple[]
    groups=vcat([(;group=:overall,level=missing,row=r.overall)],
        [(;group=:rater,level=row.rater,row) for row in r.raters],
        [(;group=:rater_pair,level=(row.rater_a,row.rater_b),row) for row in r.rater_pairs])
    for group in groups, kind in (:exact,:adjacent)
        row=group.row;metric=getproperty(row,kind)
        push!(rows,(;group=group.group,level=group.level,agreement=kind,
            category_distance=kind===:exact ? 0 : r.adjacent,
            row.n_opportunities,row.n_persons,metric.observed_count,
            interval_probability=r.interval_probability,interval_method=r.interval_method,
            se_unit=r.se_unit,_saved_agreement_metric(metric)...))
    end
    return rows
end

function _saved_agreement_section(fit,request,policy)
    options=request.agreement
    options===nothing && return merge(_fit_report_not_requested(),(;reason="No score-agreement report requested."))
    interpretation="Exact/adjacent score agreement on explicitly matched responses and items, weighted by unordered rating-pair opportunities. Observed rates, optional person-cluster observed SE, conditional expected-rate posterior intervals and Monte Carlo error answer different questions. There is no predictive interval, kappa or diagnosis of halo/dependence. Zero-overlap pairs remain unavailable. Every original retained draw contributes. Matching identities, denominators, assumptions and detailed MCSE remain in result."
    section=_fit_report_section(policy) do
        r=rater_agreement(fit;request.dataset_id,request.observation_ids,options...)
        (;_saved_result_payload(r)...,rows=_saved_agreement_rows(r),warning_rows=_saved_reporting_warnings(r))
    end
    return merge((;request=_saved_reporting_request_record(options),interpretation),section)
end

function _saved_reliability_section(fit,request,policy)
    isempty(request.reliability) && return merge(_fit_report_not_requested(),(;reason="No explicit reliability cohort and target requested."))
    interpretation="Finite-cohort posterior reliability for each explicitly selected location block and dimension. Absolute and jointly centered targets differ. Weights and components are retained; MCSE measures numerical precision. No reliability CrI, population/design coefficient, conventional separation or Strata is computed. Fixed anchors and mixed dimensions are rejected. Every original retained draw contributes. A failed cohort remains listed and does not discard successful cohorts."
    rows=NamedTuple[];coordinate_rows=NamedTuple[];results=NamedTuple[];warnings=NamedTuple[];failures=String[]
    for cohort in request.reliability
        evaluated=_fit_report_section(policy) do
            haskey(cohort,:parameters) && haskey(cohort,:target) ||
                throw(ArgumentError("Reliability cohort requires parameters and target."))
            r=posterior_reliability(fit;Base.structdiff(cohort,(;id=nothing))...)
            _saved_result_payload(r)
        end
        push!(results,(;cohort_id=cohort.id,request=cohort,evaluated...))
        if evaluated.status===:error
            push!(failures,cohort.id)
            push!(rows,(;cohort_id=cohort.id,status=:error,reliability=missing,
                exception=evaluated.exception,message=evaluated.message))
            push!(warnings,(;code=:cohort_error,severity=:warning,cohort_id=cohort.id,
                message="A reliability cohort could not be evaluated; see its error row.",action=:correct_cohort_request))
            continue
        end
        r=evaluated.result;d=first(r.rows)
        push!(rows,(;cohort_id=cohort.id,status=:computed,result_status=r.status,target=r.target,
            d.block,d.dimension,d.parameter_space,r.reliability,r.between_variance,r.within_variance,
            r.total_variance,r.n_levels,r.n_retained_draws,r.interval,r.strata,r.separation,
            mean_mcse=r.mcse.value,mcse_status=r.mcse.status,r.sampling_warning))
        append!(coordinate_rows,[(;cohort_id=cohort.id,row...) for row in r.rows])
        append!(warnings,_saved_reporting_warnings(r;cohort_id=cohort.id))
    end
    status=isempty(failures) ? (;status=:computed) : (;status=:error,exception=:CohortEvaluationError,
        message="One or more reliability cohorts failed; see their error rows.")
    return (;status...,request=request.reliability,interpretation,rows,coordinate_rows,results,
        warning_rows=warnings,n_requested_cohorts=length(request.reliability),n_failed_cohorts=length(failures))
end

function _saved_classification_section(fit,options,policy)
    interpretation="Posterior qualification and classification risk for explicitly selected people in one fitted ability dimension. Cutoff and probability rule are supplied by the user; equality qualifies/passes. Ability SD and pointwise equal-tailed intervals describe conditional uncertainty; MCSE describes numerical error. Cohort counts and any-error probability retain joint-draw dependence and condition on the displayed decisions. These are not known-truth repeated-sampling error rates or a multidimensional composite rule."
    section=_fit_report_section(policy) do
        r=posterior_classification(fit;options...)
        rows=[merge(Base.structdiff(row,(;ability=nothing,qualification_probability=nothing,error_probability=nothing)),
            _saved_summary_columns(row.ability;prefix="ability_"),
            (;qualification_probability=row.qualification_probability.mean,
                qualification_mcse=row.qualification_probability.mcse.value,
                qualification_mcse_status=row.qualification_probability.mcse.status,
                error_probability=row.error_probability.mean,
                error_mcse=row.error_probability.mcse.value,
                error_mcse_status=row.error_probability.mcse.status)) for row in r.rows]
        cohort_rows=[(;quantity=name,mean=value.mean,mean_mcse=value.mcse.value,
            mcse_status=value.mcse.status,n_people=r.n_people,n_pass=r.n_pass,n_fail=r.n_fail)
            for (name,value) in pairs(r.cohort)]
        (;_saved_result_payload(r)...,rows,cohort_rows,warning_rows=_saved_reporting_warnings(r))
    end
    return merge((;request=options,interpretation),section)
end

function _saved_ranking_section(fit,options,policy)
    interpretation="Conditional posterior ranks among explicitly selected people in one fitted ability dimension, ranked within complete joint draws. Rank 1 follows the requested direction; exact ties receive midranks. Intervals are marginal empirical inverse-CDF intervals, not a simultaneous ordering or intervals for mean ranks. Top-k lower/upper probabilities bound unspecified tie-breaking, not credible intervals. Mean MCSE is numerical error; interval MCSE is not computed. No automatic selection, practical-equivalence test, population rank or multidimensional composite is supplied."
    section=_fit_report_section(policy) do
        r=posterior_ranking(fit;options...)
        rows=map(r.rows) do row
            top=row.top_k_probability
            (; Base.structdiff(row,(;rank=nothing,tie_probability=nothing,top_k_probability=nothing))...,
                r.direction,r.n_people,r.top_k,r.tie_policy,r.interval_probability,r.interval_method,
                mean_rank=row.rank.mean,rank_sd=row.rank.sd,median_rank=row.rank.median,
                rank_lower=row.rank.lower,rank_upper=row.rank.upper,
                mean_rank_mcse=row.rank.mcse.value,mean_rank_mcse_status=row.rank.mcse.status,
                interval_mcse=row.rank.interval_mcse,tie_probability=row.tie_probability.mean,
                tie_mcse=row.tie_probability.mcse.value,tie_mcse_status=row.tie_probability.mcse.status,
                top_k_lower=top===nothing ? missing : top.lower.mean,
                top_k_upper=top===nothing ? missing : top.upper.mean,
                top_k_lower_mcse=top===nothing ? missing : top.lower.mcse.value,
                top_k_upper_mcse=top===nothing ? missing : top.upper.mcse.value,
                top_k_lower_mcse_status=top===nothing ? :not_requested : top.lower.mcse.status,
                top_k_upper_mcse_status=top===nothing ? :not_requested : top.upper.mcse.status,
                boundary_tie_probability=top===nothing ? missing : top.boundary_tie_probability.mean)
        end
        warnings=_saved_reporting_warnings(r)
        r.boundary_ties_observed && push!(warnings,(;code=:rank_boundary_ties,severity=:warning,
            cohort_id=nothing,message="Ties cross the top-k boundary; reported probabilities are bounds over unspecified tie-breaking.",action=:review_selection_rule))
        (;_saved_result_payload(r)...,rows,warning_rows=warnings)
    end
    return merge((;request=options,interpretation),section)
end

function _saved_alpha_section(fit,request,policy)
    options=request.alpha
    interpretation="Observed-score Krippendorff alpha for one explicit item and measurement level. This section uses the recorded ratings, not posterior draws, and does not depend on MCMC convergence. Singleton units are excluded from both disagreements and margins but retained in the ledger. Negative values remain negative; zero expected disagreement is undefined. No interval, SE, missingness correction, severity adjustment or population reliability guarantee."
    section=_fit_report_section(policy) do
        data=PredictionObservationAdapter._fit_data(fit)
        r=krippendorff_alpha(data;request.dataset_id,request.observation_ids,options...)
        rows=[(;r.item,r.level,r.alpha,r.status,r.observed_disagreement,r.expected_disagreement,
            r.n_units,r.n_pairable_units,r.n_singleton_units,r.n_ratings,r.n_pairable_ratings,r.interval,r.se)]
        warnings=NamedTuple[]
        r.status!==:descriptive && push!(warnings,(;code=r.status,severity=:warning,
            message="Alpha is undefined; inspect pairable units and expected disagreement.",action=:review_rating_support))
        r.n_singleton_units>0 && push!(warnings,(;code=:singleton_units_excluded,severity=:warning,
            message="Units with one rating do not enter alpha or its category margins; IDs remain in the result.",action=:review_rating_allocation))
        (;_saved_result_payload(r)...,rows,unit_rows=r.unit_rows,warning_rows=warnings)
    end
    return merge((;request=options,interpretation),section)
end

function _saved_icc_section(fit,request,policy)
    options=request.icc
    interpretation="Observed-score two-way ANOVA ICC for one item and a complete response-by-rater rectangle. Agreement versus consistency, single rating versus the actual panel mean, random versus fixed raters and equal score gaps are explicit choices. The model choice affects generalization, not the point formula. Negative estimates are retained; nonpositive denominators are unavailable. This section uses observed ratings, not posterior draws. No SE, interval, severity adjustment or population guarantee."
    section=_fit_report_section(policy) do
        r=intraclass_correlation(PredictionObservationAdapter._fit_data(fit);
            request.dataset_id,request.observation_ids,options...)
        rows=[(;r.item,r.model,r.definition,r.unit,r.score_scale,r.icc,r.status,
            r.numerator,r.denominator,r.raw_ratio,r.n_units,r.n_raters,r.n_ratings,r.n_people,r.interval,r.se)]
        warnings=NamedTuple[]
        r.status!==:descriptive && push!(warnings,(;code=r.status,severity=:warning,
            message="ICC is unavailable because its denominator is nonpositive; inspect the ANOVA components and raw ratio.",action=:review_rating_support))
        !ismissing(r.icc) && r.icc<0 && push!(warnings,(;code=:negative_icc,severity=:warning,
            message="The negative method-of-moments estimate is retained, not clipped to zero.",action=:review_rating_support))
        r.repeated_person_units && push!(warnings,(;code=:repeated_person_units,severity=:warning,
            message="Multiple response units belong to a person; independent response sampling is not established.",action=:review_response_sampling))
        (;_saved_result_payload(r)...,rows,anova_rows=r.anova_rows,unit_rows=r.unit_rows,warning_rows=warnings)
    end
    return merge((;request=options,interpretation),section)
end

function _with_saved_reporting(report,fit,request,policy)
    request===nothing && return report
    sections=(;category_report=_saved_category_section(fit,request,policy),
        posterior_reliability=_saved_reliability_section(fit,request,policy),
        rater_agreement=_saved_agreement_section(fit,request,policy))
    if haskey(request,:classification)
        sections=merge(sections,(;posterior_classification=_saved_classification_section(fit,request.classification,policy)))
    end
    if haskey(request,:ranking)
        sections=merge(sections,(;posterior_ranking=_saved_ranking_section(fit,request.ranking,policy)))
    end
    if haskey(request,:alpha)
        sections=merge(sections,(;krippendorff_alpha=_saved_alpha_section(fit,request,policy)))
    end
    if haskey(request,:icc)
        sections=merge(sections,(;intraclass_correlation=_saved_icc_section(fit,request,policy)))
    end
    return merge(report,sections,(;report_policy=merge(report.report_policy,(;reporting=request))))
end
