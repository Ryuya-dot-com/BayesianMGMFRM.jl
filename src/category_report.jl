function _category_report_summary(values, chains, interval; fixed=false, space=:model_coordinate)
    S = length(values)
    finite = count(isfinite, values)
    unavailable = (; mean=missing, sd=missing, median=missing, lower=missing, upper=missing,
        n_draws=S, n_finite_draws=finite, fixed, interval_probability=Float64(interval),
        interval_method=:equal_tailed, mcse=nothing, status=:nonfinite_draws,
        draws_hash=_cache_hash(values))
    finite == S || return unavailable
    lower, upper = _interval_probabilities(interval)
    m = mean(values)
    sd = S > 1 ? std(values) : missing
    isfinite(m) && (ismissing(sd) || isfinite(sd)) || return merge(unavailable,(;status=:nonfinite_summary))
    mcse = only(_posterior_mcse_rows(reshape(values,:,1), ["category_quantity"], chains;
        probabilities=(lower,.5,upper), parameter_space=space,
        structurally_fixed_parameters=fixed ? Set(["category_quantity"]) : Set{String}()))
    return (; mean=m, sd, median=mcse.quantiles[2].estimate,
        lower=first(mcse.quantiles).estimate, upper=last(mcse.quantiles).estimate,
        n_draws=S, n_finite_draws=finite, fixed, interval_probability=Float64(interval),
        interval_method=:equal_tailed, mcse,
        status=mcse.mcse_status in (:available,:structurally_fixed) ? :descriptive : :mcse_unavailable,
        draws_hash=_cache_hash(values))
end

function _category_report_steps(context)
    spec=context.spec; data=spec.data; contract=_model_family_step_contract(spec)
    lookup=Dict(row.parameter=>row for row in context.coordinates)
    levels=contract.owner===:global ? [nothing] :
        contract.owner===:rater ? data.rater_levels : data.item_levels
    native_stable=spec.family===:mfrm && spec.dimensions==1
    rows=NamedTuple[]
    for (owner_index,level) in pairs(levels), k in 1:length(data.category_levels)-1
        name = native_stable ? (contract.owner===:global ? "step[$k]" : "step[item=$level,$k]") :
            "$(contract.owner)_step[$(contract.owner)=$level,m=$(k+1)]"
        haskey(lookup,name) || throw(ArgumentError("missing native category step: $name"))
        coordinate=lookup[name]
        push!(rows,(;owner=contract.owner,owner_index,owner_level=level,step=k,
            from_category=data.category_levels[k],to_category=data.category_levels[k+1],
            parameter=name,coordinate.values,coordinate.fixed))
    end
    return contract,rows
end

function _category_profile_dimension(value, spec)
    d=value isa Integer && !(value isa Bool) ? Int(value) :
        value isa Union{AbstractString,Symbol} ? findfirst(==(string(value)),string.(spec.dimension_labels)) : nothing
    d!==nothing && 1<=d<=spec.dimensions || throw(ArgumentError("unknown ability dimension: $value"))
    return d
end

function _category_profiles(profiles,spec,S,max_curve_cells)
    profiles isa Union{Tuple,AbstractVector} || throw(ArgumentError("profiles must be a tuple or vector of named tuples"))
    required=Set((:id,:item,:rater,:dimension,:ability_grid))
    allowed=union(required,Set((:fixed_abilities,)))
    checked=NamedTuple[];total=big(0)
    for profile in profiles
        profile isa NamedTuple && required ⊆ Set(keys(profile)) && Set(keys(profile)) ⊆ allowed ||
            throw(ArgumentError("each profile needs id, item, rater, dimension, ability_grid and optional fixed_abilities"))
        profile.id isa AbstractString && !isempty(strip(profile.id)) &&
            all(p->p.id!=profile.id,checked) || throw(ArgumentError("profile IDs must be unique nonempty strings"))
        item=findfirst(isequal(profile.item),spec.data.item_levels)
        rater=findfirst(isequal(profile.rater),spec.data.rater_levels)
        item!==nothing && rater!==nothing || throw(ArgumentError("profiles require exact stored item and rater labels"))
        dimension=_category_profile_dimension(profile.dimension,spec)
        profile.ability_grid isa Union{AbstractVector,Tuple} || throw(ArgumentError("ability_grid must be a vector, range or tuple"))
        total+=big(S)*length(profile.ability_grid)*length(spec.data.category_levels)
        total<=max_curve_cells || throw(ArgumentError("category profiles exceed max_curve_cells; narrow the grid or raise the explicit budget"))
        grid=collect(profile.ability_grid)
        length(grid)>=2 && all(x->x isa Real && !(x isa Bool) && isfinite(x),grid) ||
            throw(ArgumentError("ability_grid needs at least two finite real values"))
        grid=Float64.(grid)
        all(isfinite,grid) && all(>(0),diff(grid)) || throw(ArgumentError("ability_grid must be finite and strictly increasing"))
        raw=get(profile,:fixed_abilities,Dict())
        raw isa AbstractDict || throw(ArgumentError("fixed_abilities must map dimensions to finite values"))
        fixed=Dict{Int,Float64}()
        for (key,value) in pairs(raw)
            d=_category_profile_dimension(key,spec)
            d!=dimension && !haskey(fixed,d) || throw(ArgumentError("duplicate or plotted fixed ability dimension"))
            value isa Real && !(value isa Bool) && isfinite(value) && isfinite(Float64(value)) ||
                throw(ArgumentError("fixed abilities must be finite real numbers"))
            fixed[d]=Float64(value)
        end
        Set(keys(fixed))==setdiff(Set(1:spec.dimensions),Set([dimension])) ||
            throw(ArgumentError("specify every other dimension in fixed_abilities"))
        push!(checked,(;id=String(profile.id),item=spec.data.item_levels[item],item_index=item,
            rater=spec.data.rater_levels[rater],rater_index=rater,dimension,
            dimension_label=spec.dimension_labels[dimension],ability_grid=grid,
            fixed_abilities=Tuple((;dimension=d,dimension_label=spec.dimension_labels[d],value=fixed[d]) for d in sort(collect(keys(fixed))))))
    end
    return checked
end

function _category_profile_terms(context, steps, profile)
    spec=context.spec;S=context.total_draws
    lookup=Dict(row.parameter=>row for row in context.coordinates)
    item=lookup["item[$(profile.item)]"];rater=lookup["rater[$(profile.rater)]"]
    offset=item.values+rater.values; fixed=item.fixed && rater.fixed; scale_fixed=true
    if spec.dimensions==1
        axis=ones(S)
        if spec.family===:gmfrm
            a=lookup["item_discrimination[item=$(profile.item)]"]
            gamma=lookup["rater_consistency[rater=$(profile.rater)]"]
            scale=a.values.*gamma.values; scale_fixed=a.fixed && gamma.fixed
        else
            scale=ones(S)
        end
    else
        function loading(d)
            spec.q_matrix[profile.item_index,d] || return (;values=zeros(S),fixed=true)
            lookup["item_dimension_discrimination[item=$(profile.item),$(spec.dimension_labels[d])]"]
        end
        a=loading(profile.dimension);axis=a.values;fixed &= a.fixed
        for other in profile.fixed_abilities
            a=loading(other.dimension);offset.-=a.values.*other.value
            fixed &= a.fixed || iszero(other.value)
        end
        gamma=lookup["rater_consistency[rater=$(profile.rater)]"]
        scale=_model_family_category_contract(spec).implementation_scale_constant.*gamma.values
        scale_fixed=gamma.fixed
    end
    owner=spec.family===:gmfrm ? :rater :
        spec.dimensions==1 && spec.thresholds===:rating_scale ? :global : :item
    index=owner===:rater ? profile.rater_index : owner===:item ? profile.item_index : 1
    selected=filter(row->row.owner_index==index,steps)
    active=spec.dimensions==1 || spec.q_matrix[profile.item_index,profile.dimension]
    all(x->isfinite(x) && x>0,scale) && (!active || all(x->isfinite(x) && x>0,axis)) ||
        throw(ArgumentError("category profiles require finite positive native scales and active loadings; inspect underflow or overflow in fitted draws"))
    return (;offset,axis,scale,steps=selected,fixed,owner,owner_index=index,
        probability_fixed=fixed && scale_fixed && all(row->row.fixed,selected),
        active)
end

function _category_profile_probabilities(terms, ability)
    S=length(terms.offset);K=length(terms.steps)+1
    probabilities=zeros(S,K)
    for s in 1:S
        for k in 2:K
            probabilities[s,k]=probabilities[s,k-1]+terms.scale[s]*
                (terms.axis[s]*ability-terms.offset[s]-terms.steps[k-1].values[s])
        end
        all(isfinite,@view(probabilities[s,:])) || throw(ArgumentError("nonfinite category profile logits; reduce the ability range or inspect fitted scales"))
        _softmax_eta!(@view(probabilities[s,:]))
    end
    return probabilities
end

"""
    BayesianMGMFRM.category_report(fit; dataset_id, observation_ids,
        interval=0.95, min_count=5, min_proportion=0.01,
        order_probability_threshold=0.8, profiles=(),
        max_prediction_cells=20_000_000, max_curve_cells=20_000_000)

Summarize category use and correctly owned steps across the eight common saved-fit
types, using every original retained draw. Supply persistent, unique rating IDs
in fitted-row order. Canonical fixed-MFRM records are required. No fitting,
response simulation, category sorting/collapse or random draw selection occurs.

`usage_rows` retain every declared category overall, per item and per rater,
observed counts/denominators, actual contributing threshold groups and the
posterior distribution of the conditional *expected* proportion. Counts give
equal weight to ratings, not persons, raters or likelihood/survey weights. This
is the observed allocation, not balanced standardization. Its intervals are not
predictive intervals for realized category use; a discrepancy is not a p-value.
The existing MFRM `category_functioning_summary` keeps its predictive-replication
semantics and unchanged numerical implementation.

`threshold_rows` identify shared, item- or rater-owned centered transitions,
excluding dummy reference-category zeros. They include posterior SD, equal-tailed
intervals, joint-draw ordering probabilities, gap summaries and chain-aware MCSE.
Posterior SD is not a repeated-sampling SE; empirical constant draws/indicators
are not automatically treated as structural constants or certain ordering.
Flags prompt review and never establish a reason to merge categories.

Optional `profiles` are named tuples with unique string `id`, exact stored `item`
and `rater` labels, `dimension` (index or label), strictly increasing finite
`ability_grid`, and `fixed_abilities=Dict(other_dimension=>value, ...)` specifying
ALL other dimensions. Profiles are slices, not integrations over other abilities
or raters. `curve_rows` give conditional category probabilities at the grid points;
`crossing_rows` give draw-wise ability values where adjacent categories are equally
probable. These probabilities need not each be 0.5. Steps, crossings and expected-
score half-points differ. Inactive dimensions retain flat curves and no unique
crossing. The scalar GMFRM's item coefficient multiplies the whole contrast,
whereas MGMFRM loadings multiply abilities; native scale conventions are retained.

All intervals are pointwise, conditional on this fitted model and its calibration
policy; they are not simultaneous bands, new-rater guarantees or calibration
evidence. Fixed anchors omit external calibration uncertainty. A profile grid is
a display choice, not evidence of empirical support. Structural constants and
unavailable numerical summaries stay explicit. Sampling warnings, source identity,
model/step contracts, complete chain layout and a content seal are retained.
Resources exceeding the explicit budgets fail instead of subsampling. This
qualified candidate API is also available through the optional
`fit_report(...; reporting=(; category=(...), ...))` request.
"""
function category_report(fit::PredictionObservationAdapter.SupportedFit;
        dataset_id::AbstractString, observation_ids, interval::Real=.95,
        min_count::Int=5, min_proportion::Real=.01, order_probability_threshold::Real=.8,
        profiles=(),max_prediction_cells::Integer=20_000_000,max_curve_cells::Integer=20_000_000)
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    all(x->!(x isa Bool) && x>0,(max_prediction_cells,max_curve_cells)) || throw(ArgumentError("resource limits must be positive integers"))
    controls=_category_functioning_controls(interval,min_count,min_proportion,order_probability_threshold)
    data=PredictionObservationAdapter._fit_data(fit)
    ids=PredictionObservationAdapter._ids(observation_ids,data.n,"observation_ids")
    S=_agreement_draw_count(fit);K=length(data.category_levels)
    big(S)*data.n*K<=max_prediction_cells || throw(ArgumentError("category probabilities exceed max_prediction_cells; raise the explicit budget or use a separately justified analysis"))
    context=_recovery_context(fit);spec=context.spec
    checked_profiles=_category_profiles(profiles,spec,S,max_curve_cells)
    step_contract,steps=_category_report_steps(context)
    prediction=prediction_observations(fit;dataset_id,observation_ids=ids)
    PredictionObservationAdapter._criterion_draws(prediction)
    prediction.chain_ids==context.chain_ids && prediction.iterations==context.iterations &&
        prediction.source_sample_hash==context.source_sample_hash || error("category native/predictive draw provenance mismatch")
    chains=length(unique(context.chain_ids))
    usage_rows=NamedTuple[]
    for group in _category_functioning_groups(data)
        rows=group.observations;n=length(rows)
        owner_indices=step_contract.owner===:global ? [1] :
            sort(unique((step_contract.owner===:rater ? data.rater : data.item)[rows]))
        owner_levels=step_contract.owner===:global ? (nothing,) :
            Tuple((step_contract.owner===:rater ? data.rater_levels : data.item_levels)[owner_indices])
        for (k,category) in pairs(data.category_levels)
            observed=count(j->data.category[j]==k,rows)
            values=vec(mean(prediction.probabilities[:,rows,k];dims=2))
            expected=_category_report_summary(values,chains,interval;space=:probability)
            push!(usage_rows,(;facet=group.facet,level=group.level,level_index=group.level_index,
                category,n_observations=n,observed_count=observed,observed_proportion=observed/n,
                observed_flag=_category_observed_flag(observed,observed/n,controls),
                threshold_owner=step_contract.owner,threshold_levels=owner_levels,
                expected,observed_minus_expected=ismissing(expected.mean) ? missing : observed/n-expected.mean))
        end
    end
    threshold_rows=NamedTuple[]
    for step in steps
        summary=_category_report_summary(step.values,chains,interval;fixed=step.fixed)
        previous=step.step==1 ? nothing : only(filter(x->x.owner_index==step.owner_index && x.step==step.step-1,steps))
        if previous===nothing
            gap=nothing;order=nothing;ordering_flag=:not_applicable
        else
            gap=_category_report_summary(step.values-previous.values,chains,interval;fixed=step.fixed && previous.fixed)
            order=_category_report_summary(Float64.(step.values.>previous.values),chains,interval;
                fixed=step.fixed && previous.fixed,space=:probability)
            ordering_flag=order.mean>=controls.order_probability_threshold ? :likely_ordered :
                1-order.mean>=controls.order_probability_threshold ? :likely_disordered : :order_uncertain
        end
        push!(threshold_rows,merge(Base.structdiff(step,(;values=nothing)),
            (;summary,gap,order_probability=order,ordering_flag)))
    end
    curve_rows=NamedTuple[];crossing_rows=NamedTuple[]
    for profile in checked_profiles
        terms=_category_profile_terms(context,steps,profile)
        for ability in profile.ability_grid
            probabilities=_category_profile_probabilities(terms,ability)
            for (k,category) in pairs(data.category_levels)
                push!(curve_rows,(;profile_id=profile.id,ability,category,active_dimension=terms.active,
                    probability=_category_report_summary(probabilities[:,k],chains,interval;fixed=terms.probability_fixed,space=:probability)))
            end
        end
        for step in terms.steps
            crossing=terms.active ? _category_report_summary((terms.offset+step.values)./terms.axis,
                chains,interval;fixed=terms.fixed && step.fixed,space=:ability) : nothing
            push!(crossing_rows,(;profile_id=profile.id,step=step.step,step.owner,step.owner_level,
                step.from_category,step.to_category,
                status=terms.active ? crossing.status : :no_unique_crossing_inactive_dimension,
                crossing))
        end
    end
    summaries=Any[r.expected for r in usage_rows]
    for r in threshold_rows
        push!(summaries,r.summary);r.gap===nothing || append!(summaries,(r.gap,r.order_probability))
    end
    append!(summaries,[r.probability for r in curve_rows])
    append!(summaries,[r.crossing for r in crossing_rows if r.crossing!==nothing])
    sampling_warning=_prediction_sampling_warning(context.quality)
    numerical_warning=any(s->s.status in (:nonfinite_draws,:nonfinite_summary),summaries)
    mcse_warning=any(s->s.status===:mcse_unavailable,summaries)
    review_recommended=any(r->r.observed_flag!==:ok,usage_rows) ||
        any(r->r.ordering_flag in (:likely_disordered,:order_uncertain),threshold_rows)
    return _prediction_seal((;schema="bayesianmgmfrm.category_report.v1",dataset_id=String(dataset_id),
        observation_ids=ids,prediction.observation_binding,prediction.training_binding,
        category_levels=copy(data.category_levels),model_contract=_recovery_model_contract(fit,context),
        step_contract,usage_rows,threshold_rows,profiles=checked_profiles,curve_rows,crossing_rows,controls,
        n_retained_draws=S,chain_ids=copy(context.chain_ids),iterations=copy(context.iterations),
        context.source_sample_hash,context.source_hash_status,sampling_quality=deepcopy(context.quality),
        sampling_warning,numerical_warning,mcse_warning,review_recommended,
        status=(sampling_warning || numerical_warning || mcse_warning) ? :warning : :descriptive,
        usage_target=:conditional_expected_category_proportion_existing_rows,
        usage_weighting=:equal_observed_rating,profile_target=:conditional_fixed_ability_slice,
        intervals=:pointwise_equal_tailed,predictive_interval=:not_computed,
        multiplicity_adjustment=:none,automatic_category_collapse=false,refit_performed=false,
        scientific_acceptance=:not_established))
end
