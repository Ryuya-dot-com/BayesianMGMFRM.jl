module PairedRatingPriorReview

using Statistics, LinearAlgebra, Random
include("paired_rating_reference.jl")
const A=PairedRatingReference

# Fixed mechanism contrasts, not a prior optimizer or a posterior fit roster.
const CASES=(
    (;id=:baseline,nuisance=1.0,steps=:exchangeable),
    (;id=:nuisance_half,nuisance=0.5,steps=:exchangeable),
    (;id=:step_sd_double,nuisance=1.0,steps=:double_sd),
    (;id=:nuisance_half_step_sd_double,nuisance=0.5,steps=:double_sd),
    (;id=:sorted_steps,nuisance=1.0,steps=:ascending),
    (;id=:nuisance_half_sorted_steps,nuisance=0.5,steps=:ascending),
    (;id=:zero_steps,nuisance=1.0,steps=:zero))

function case_spec(id::Symbol)
    index=findfirst(c->c.id===id,CASES)
    isnothing(index) && throw(ArgumentError("unknown prior review case"))
    return CASES[index]
end

function transform_draws(t,raw::AbstractMatrix,id::Symbol)
    case=case_spec(id)
    size(raw,1)>=2 && size(raw,2)==A.LDP.dimension(t) && all(isfinite,raw) ||
        throw(ArgumentError("review requires at least two finite compatible joint prior draws"))
    out=Float64.(raw); b=t.blocks
    out[:,b.word].*=case.nuisance
    out[:,b.rater_free].*=case.nuisance
    out[:,b.log_recording_sd].+=log(case.nuisance)
    if case.steps===:double_sd
        out[:,b.step_free].*=2
    elseif case.steps===:ascending
        for q in eachrow(out)
            ordered=sort(A.coordinates(t,q).steps[2:end,:];dims=1)
            q[b.step_free]=vec(ordered[1:end-1,:])
        end
    elseif case.steps===:zero
        out[:,b.step_free].=0
    end
    all(isfinite,out) || throw(ArgumentError("nonfinite transformed draw; no replacement performed"))
    return out
end

function scenario_metadata(t,id::Symbol)
    case=case_spec(id)
    scales=merge(t.prior,(;word_sd=t.prior.word_sd*case.nuisance,
        rater_sd=t.prior.rater_sd.*case.nuisance,
        recording_log_sd_mean=t.prior.recording_log_sd_mean.+log(case.nuisance),
        step_sd=case.steps===:double_sd ? t.prior.step_sd.*2 : t.prior.step_sd))
    supported=case.steps in (:exchangeable,:double_sd)
    return (;case...,person_sd=1.0,
        status=supported ? :unselected_prior_sensitivity : :response_mechanism_only,
        fit_prior=supported ? scales : nothing,
        step_law=case.steps===:ascending ? :sorted_exchangeable_prior_requires_a_distinct_normalized_target :
            case.steps===:zero ? :fixed_zero_steps_not_a_positive_scale_prior : :projected_normal,
        ordered_normalization=case.steps===:ascending ? sum(log,1:t.data.K-1) : nothing,
        ordered_normalization_measure="log((K-1)!) relative to the original free-step Lebesgue density on the ordered chamber; not a raw-coordinate HMC transform")
end

# Exact upper envelope of the PCM's lines k*eta - cumulative_step[k].
# A zero-width tie does not count as an interval with a unique modal category.
function modal_intervals(steps::AbstractVector)
    length(steps)>=2 && all(isfinite,steps) && iszero(first(steps)) ||
        throw(ArgumentError("finite PCM steps including a zero baseline are required"))
    prefix=cumsum(Float64.(steps));all(isfinite,prefix) || throw(ArgumentError("unrepresentable cumulative steps"))
    H=length(steps)-1
    return map(0:H) do k
        lower=maximum(((prefix[k+1]-prefix[j+1])/(k-j) for j in 0:k-1);init=-Inf)
        upper=minimum(((prefix[j+1]-prefix[k+1])/(j-k) for j in k+1:H);init=Inf)
        (;category=k,lower,upper,has_interval=lower<upper)
    end
end

function summarize(values::AbstractVector)
    length(values)>=2 || throw(ArgumentError("at least two independent draws required for review MCSE"))
    return (;mean=mean(values),q05=quantile(values,0.05),q95=quantile(values,0.95),
        iid_mean_mcse=std(values)/sqrt(length(values)))
end

function review(t,raw::AbstractMatrix;prediction_seed)
    rows=A.prediction_rows(t)
    baseline=nothing;results=NamedTuple[]
    for case in CASES
        transformed=transform_draws(t,raw,case.id)
        prediction=A.prediction_summary(t,transformed,rows;
            recording_effect=:existing,seed=prediction_seed,integrations=1)
        expected=prediction.category_expected_by_draw
        case.id===:baseline && (baseline=expected)
        xs=[A.coordinates(t,q) for q in eachrow(transformed)]
        summaries=map(1:2) do c
            cols=(c-1)*t.data.K .+ (1:t.data.K)
            freq=expected[:,cols]
            endpoints=freq[:,1]+freq[:,end]
            base_endpoints=baseline[:,first(cols)]+baseline[:,last(cols)]
            modes=[count(v->v.has_interval,modal_intervals(x.steps[:,c])) for x in xs]
            (;criterion=t.data.levels.criterion[c],endpoint_mass=summarize(endpoints),
                paired_endpoint_change=summarize(endpoints-base_endpoints),
                expected_score=summarize(freq*collect(0:t.data.K-1)),
                modal_category_count=summarize(modes),
                mean_category_frequency=vec(mean(freq;dims=1)),
                mean_cumulative_frequency=vec(mean(cumsum(freq;dims=2);dims=1)))
        end
        push!(results,(;metadata=scenario_metadata(t,case.id),summary=summaries,
            category_expected_by_draw=expected))
    end
    return (;schema="bayesianmgmfrm.paired_rating_prior_review.v1",base_target_identity=A.identity(t),
        base_prior=t.prior,parameter_draws=size(raw,1),prediction_seed,
        categories=collect(0:t.data.K-1),criteria=t.data.levels.criterion,
        design=(;persons=t.data.P,words=t.data.W,raters=t.data.R,recordings=t.data.O,ratings=t.data.N),
        weighting=:equal_recordings_then_equal_supplied_raters_within_criterion,
        statistic="Conditional category probabilities, averaged over the fixed design; scores are integrated out",
        uncertainty="Variation and paired MCSE across the same independent joint prior draws; no posterior MCMC or numerical recording integration",
        selection="No fitted prior or model is selected; sorted and zero steps are response-mechanism contrasts only",
        results)
end

end # module
