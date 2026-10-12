const _PRIOR_SENSITIVITY_SCHEMA = "bayesianmgmfrm.prior_sensitivity.v1"

function _sensitivity_estimands(estimands, context)
    specs = collect(estimands)
    all(p -> p isa Pair, specs) || throw(ArgumentError("estimands must contain label => definition pairs"))
    _recovery_replication_names(first.(specs), "estimand labels")
    lookup = Dict(r.parameter => r for r in context.coordinates)
    return map(specs) do entry
        entry isa Pair || throw(ArgumentError("estimands must contain label => coordinate or label => (left, right)"))
        label, source = entry
        terms = source isa AbstractString ? [String(source)] :
            source isa Tuple && length(source) == 2 && all(x -> x isa AbstractString, source) ? String.(collect(source)) :
            throw(ArgumentError("use an exact coordinate name or a pair of names for a within-fit difference"))
        length(unique(terms)) == length(terms) && all(k -> haskey(lookup, k), terms) ||
            throw(ArgumentError("unknown or repeated coordinate in $label"))
        rows = [lookup[k] for k in terms]
        descriptions = [_recovery_quantity(r, context.spec) for r in rows]
        all(d -> (d.block, d.dimension, d.parameter_space) ==
            (first(descriptions).block, first(descriptions).dimension, first(descriptions).parameter_space), descriptions) ||
            throw(ArgumentError("contrasts require the same block, dimension and coordinate scale"))
        d = first(descriptions)
        positive = length(terms) == 1 && d.block in
            (:item_dimension_discrimination, :item_discrimination, :rater_consistency, :rater_discrimination)
        values = Float64.(first(rows).values)
        length(rows) == 2 && (values .-= last(rows).values)
        all(isfinite, values) || throw(ArgumentError("nonfinite estimand: $label"))
        return (; label=String(label), terms, operation=length(terms) == 1 ? :coordinate : :paired_difference,
            d.block, d.dimension, d.dimension_label, d.parameter_space,
            support=positive ? :positive : :real, fixed=all(r -> r.fixed, rows), values)
    end
end

function _sensitivity_row(e, context, interval, cutoff, max_mcse, mcse_multiplier)
    lower, upper = _interval_probabilities(interval)
    m = only(_posterior_mcse_rows(reshape(e.values, :, 1), [e.label], length(unique(context.chain_ids));
        probabilities=(lower, 0.5, upper), parameter_space=e.parameter_space,
        structurally_fixed_parameters=e.fixed ? Set([e.label]) : Set{String}()))
    qs = getproperty.(m.quantiles, :estimate)
    available = m.mcse_status in (:available, :structurally_fixed)
    qualified = max_mcse === nothing ? nothing : available &&
        m.mean_mcse <= max_mcse && all(q -> q.mcse <= max_mcse, m.quantiles)
    decision = cutoff === nothing ? :not_requested : qs[1] > cutoff ? :above : qs[3] < cutoff ? :below : :includes_cutoff
    numerical_decision = cutoff === nothing ? :not_requested : !available ? :mcse_unavailable : e.fixed ? :structurally_fixed :
        any(q -> abs(q.estimate-cutoff) <= mcse_multiplier*q.mcse, (first(m.quantiles), last(m.quantiles))) ?
        :unresolved_mcse_screen : :stable_under_mcse_screen
    return merge(e, (; mean=mean(e.values), sd=length(e.values)>1 ? std(e.values) : missing, median=qs[2], lower=qs[1], upper=qs[3],
        mcse=m, cutoff, decision, numerical_decision, precision_qualified=qualified))
end

"""
    BayesianMGMFRM.prior_sensitivity(fits; planned_prior_ids, estimands,
        dataset_id, observation_ids, baseline=first(planned_prior_ids),
        interval=0.90, failures=Pair[], cutoffs=Dict(), max_mcse=nothing,
        mcse_multiplier=2.0)

Compare saved prior variants without fitting. `fits` contains `id => fit` pairs;
declare every planned ID, including failures and missing fits. The first supported
scope is `Experimental.NormalizedMGMFRMFit` with identical data/specification and
prior, except `log_discrimination_sd`. Different dimensions, identifying priors,
models and unsupported fit types are rejected. Use exact coordinate names from
`recovery_quantities(fit)`. An estimand maps a label to a name, or to `(left,right)`
for a within-fit draw-paired difference in the same block/dimension/scale.

Intervals are equal-tailed (e.g. `interval=0.99`), never HDI. All retained chains
and draws, native mean/SD/quantile MCSE, sampling warnings, actual prior records,
and sample/target identities are preserved. `max_mcse` optionally screens the
mean and all three reported quantiles in estimand units; no default precision
acceptance is inferred. `cutoffs` maps labels to declared scientific thresholds.
Interval-relative decisions carry an endpoint MCSE screen, not a simultaneous
error bound or proof of practical equivalence. This does not compute P(X>cutoff).

Across-prior differences are differences of summaries, not paired draws or
credible intervals for an across-model random variable. Their MCSE upper bounds
sum the two marginal MCSEs, allowing unknown covariance; these are estimated
standard-error bounds, not confidence bounds. Scientific acceptance, calibration,
prior predictive adequacy and recommendations are not established by this report.
"""
function prior_sensitivity(fits; planned_prior_ids, estimands, dataset_id::AbstractString,
        observation_ids, baseline=first(planned_prior_ids), interval::Real=0.90,
        failures=Pair[], cutoffs=Dict(), max_mcse=nothing, mcse_multiplier::Real=2.0)
    ids = _recovery_replication_names(planned_prior_ids, "planned_prior_ids")
    baseline in ids || throw(ArgumentError("baseline must be a planned ID"))
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    interval isa Bool && throw(ArgumentError("interval must be a probability"))
    _interval_probabilities(interval)
    max_mcse === nothing || (max_mcse isa Real && !(max_mcse isa Bool) && isfinite(max_mcse) && max_mcse > 0) ||
        throw(ArgumentError("max_mcse must be nothing or a finite positive number"))
    !(mcse_multiplier isa Bool) && isfinite(mcse_multiplier) && mcse_multiplier > 0 ||
        throw(ArgumentError("mcse_multiplier must be finite and positive"))
    all(v -> v isa Real && !(v isa Bool) && isfinite(v), values(cutoffs)) ||
        throw(ArgumentError("cutoffs must be finite real numbers"))
    entries = collect(fits)
    !isempty(entries) && all(p -> p isa Pair && first(p) in ids, entries) ||
        throw(ArgumentError("provide at least one planned id => fit"))
    length(unique(first.(entries))) == length(entries) || throw(ArgumentError("duplicate prior ID"))
    all(p -> last(p) isa _NormalizedMGMFRMFit, entries) ||
        throw(ArgumentError("this candidate supports saved NormalizedMGMFRMFit variants only"))
    failed = Dict{String,String}()
    for p in failures
        p isa Pair && first(p) in ids && last(p) isa AbstractString && !isempty(strip(last(p))) &&
            !haskey(failed, first(p)) && !(first(p) in first.(entries)) ||
            throw(ArgumentError("unplanned, duplicate or completed failure ID"))
        failed[String(first(p))] = String(last(p))
    end
    reference_fit = last(first(entries))
    prior_contract(p) = merge(Base.structdiff(p, (; scales=nothing)),
        (; scales=Base.structdiff(p.scales, (; log_discrimination_sd=nothing))))
    spec_hash = design_identity(getdesign(reference_fit.record.spec; preview=true)).value
    reference_prior = prior_contract(reference_fit.record.prior)
    observations = PredictionObservationAdapter._ids(observation_ids, reference_fit.record.spec.data.n, "observation_ids")
    evaluations = Dict{String,Any}()
    descriptor_hash = nothing
    for (id, fit) in entries
        design_identity(getdesign(fit.record.spec; preview=true)).value == spec_hash && isequal(prior_contract(fit.record.prior), reference_prior) ||
            throw(ArgumentError("only log_discrimination_sd may vary; data, model, labels and identifying priors must match"))
        context = _recovery_context(fit)
        es = _sensitivity_estimands(estimands, context)
        all(k -> k in getproperty.(es, :label), keys(cutoffs)) || throw(ArgumentError("unknown cutoff label"))
        current = _cache_hash([Base.structdiff(e, (; values=nothing)) for e in es])
        descriptor_hash === nothing || descriptor_hash == current || throw(ArgumentError("estimand coordinates differ"))
        descriptor_hash = current
        rows = [_sensitivity_row(e, context, interval, get(cutoffs, e.label, nothing), max_mcse, mcse_multiplier) for e in es]
        sampling_warning = _prediction_sampling_warning(context.quality)
        mcse_warning = any(r -> !(r.mcse.mcse_status in (:available, :structurally_fixed)), rows)
        precision_warning = any(r -> r.precision_qualified === false, rows)
        evaluations[id] = (; prior_id=String(id), status=sampling_warning || mcse_warning || precision_warning ? :warning : :descriptive,
            rows, prior=deepcopy(context.prior), target_identity=fit.record.target_identity,
            sampling_quality=deepcopy(context.quality), sampling_warning, mcse_warning, precision_warning,
            context.source_sample_hash, context.source_hash_status, n_retained_draws=context.total_draws,
            chain_ids=copy(context.chain_ids), iterations=copy(context.iterations))
    end
    ledger = [(; prior_id=id, status=haskey(evaluations,id) ? evaluations[id].status : haskey(failed,id) ? :failed : :missing,
        reason=get(failed,id,nothing), evaluation=get(evaluations,id,nothing)) for id in ids]
    changes = NamedTuple[]
    if haskey(evaluations, baseline)
        ref = evaluations[baseline]
        for id in ids
            (id == baseline || !haskey(evaluations,id)) && continue
            alt = evaluations[id]
            for (a,b) in zip(alt.rows, ref.rows)
                bound(x,y) = ismissing(x) || ismissing(y) ? missing : x+y
                push!(changes, (; prior_id=id, baseline=String(baseline), label=a.label,
                    mean_shift=a.mean-b.mean, median_shift=a.median-b.median,
                    lower_shift=a.lower-b.lower, upper_shift=a.upper-b.upper,
                    mean_shift_mcse_upper_bound=bound(a.mcse.mean_mcse,b.mcse.mean_mcse),
                    quantile_shift_mcse_upper_bounds=[bound(x.mcse,y.mcse) for (x,y) in zip(a.mcse.quantiles,b.mcse.quantiles)],
                    decision_changed=a.cutoff === nothing ? nothing : a.decision != b.decision,
                    same_saved_samples=alt.source_sample_hash == ref.source_sample_hash,
                    cross_fit_covariance=:unknown, paired_draws=false))
            end
        end
    end
    return _prediction_seal((; schema=_PRIOR_SENSITIVITY_SCHEMA, dataset_id=String(dataset_id),
        observation_ids=observations, source_binding=_prediction_source_binding(reference_fit.record.spec.data, observations, String(dataset_id)),
        spec_hash, scope=:normalized_mgmfrm_loading_prior_sd_only, scale=:model,
        model_contract=(; family=reference_fit.record.spec.family, dimensions=reference_fit.record.spec.dimensions,
            dimension_labels=copy(reference_fit.record.spec.dimension_labels), q_matrix=copy(reference_fit.record.spec.q_matrix),
            origin=:prior_anchored, common_prior=reference_prior),
        planned_prior_ids=ids, baseline=String(baseline), baseline_available=haskey(evaluations,baseline),
        ledger, changes, interval_probability=Float64(interval), interval_method=:equal_tailed,
        max_mcse, mcse_multiplier=Float64(mcse_multiplier), numerical_screen=:pointwise_asymptotic_mcse,
        comparison_uncertainty=:sum_of_mcse_upper_bound_unknown_covariance,
        scientific_acceptance=:not_established, new_fits=0))
end

"""
    BayesianMGMFRM.save_prior_sensitivity(path, result)
    BayesianMGMFRM.load_prior_sensitivity(path)

Save/reload the complete sealed result, including selected draws and chain metadata.
Existing paths are refused. Load trusted Julia serialization files only; integrity
hashes detect accidental changes and do not authenticate an untrusted file.
"""
function save_prior_sensitivity(path::AbstractString, result)
    _prediction_check_seal(result, _PRIOR_SENSITIVITY_SCHEMA)
    ispath(path) && throw(ArgumentError("destination already exists"))
    return _save_serialized_record(path, result)
end
function load_prior_sensitivity(path::AbstractString)
    result = open(deserialize, path)
    _prediction_check_seal(result, _PRIOR_SENSITIVITY_SCHEMA)
    return result
end
@doc (@doc save_prior_sensitivity) load_prior_sensitivity

"""
    BayesianMGMFRM.prior_sensitivity_plot_data(result; bandwidth=nothing, points=256)

Compute reproducible Gaussian kernel densities from all selected draws. Each
estimand shares a grid and bandwidth across priors. The default bandwidth is
0.9 * min(SD, IQR/1.34) * n^(-1/5) of pooled display draws; `bandwidth` overrides
it in real or log units. Positive coordinates use log-KDE with the inverse
Jacobian, avoiding negative density support. Fixed or accidentally constant
draws receive markers, not fabricated densities. Density height is descriptive;
no KDE precision or posterior calibration is inferred from draw count.
"""
function prior_sensitivity_plot_data(result; bandwidth=nothing, points::Integer=256)
    _prediction_check_seal(result, _PRIOR_SENSITIVITY_SCHEMA)
    !(points isa Bool) && 32 <= points <= 2048 || throw(ArgumentError("points must be 32:2048"))
    bandwidth === nothing || (bandwidth isa Real && !(bandwidth isa Bool) && isfinite(bandwidth) && bandwidth > 0) ||
        throw(ArgumentError("bandwidth must be finite and positive"))
    available = [e.evaluation for e in result.ledger if e.evaluation !== nothing]
    panels = map(eachindex(first(available).rows)) do i
        rows = [e.rows[i] for e in available]
        positive = first(rows).support === :positive
        transform(x) = positive ? log(x) : x
        all(r -> !positive || all(>(0),r.values), rows) || throw(ArgumentError("nonpositive draws on positive support"))
        pooled = reduce(vcat, [transform.(r.values) for r in rows if !allequal(r.values)]; init=Float64[])
        h = bandwidth === nothing && isempty(pooled) ? nothing : bandwidth === nothing ?
            0.9 * min(std(pooled), (quantile(pooled,.75)-quantile(pooled,.25))/1.34) * length(pooled)^(-.2) : Float64(bandwidth)
        h === nothing || isfinite(h) && h > 0 || throw(ArgumentError("automatic bandwidth is degenerate; supply bandwidth"))
        grid = isempty(pooled) ? Float64[] : collect(range(minimum(pooled)-4h, maximum(pooled)+4h; length=points))
        x = positive ? exp.(grid) : grid
        all(isfinite,x) && all(>(0),diff(x)) || throw(ArgumentError("density grid is not representable"))
        curves = map(result.ledger) do entry
            row = entry.evaluation === nothing ? nothing : entry.evaluation.rows[i]
            marker = row === nothing ? :unavailable : row.fixed ? :fixed : allequal(row.values) ? :degenerate : :density
            y = if marker === :density
                zs = transform.(row.values)
                [sum(z -> exp(-.5*((g-z)/h)^2), zs)/(length(zs)*h*sqrt(2pi)) for g in grid]
            else
                Float64[]
            end
            positive && !isempty(y) && (y ./= x)
            all(isfinite,y) || throw(ArgumentError("density overflows on the displayed scale"))
            (; entry.prior_id, entry.status, marker, density=y,
                median=row === nothing ? nothing : row.median,
                lower=row === nothing ? nothing : row.lower, upper=row === nothing ? nothing : row.upper)
        end
        descriptor = Base.structdiff(first(rows), (; values=nothing, mean=nothing, sd=nothing, median=nothing,
            lower=nothing, upper=nothing, mcse=nothing, cutoff=nothing, decision=nothing,
            numerical_decision=nothing, precision_qualified=nothing))
        (; descriptor, x, bandwidth=h, density_coordinate=positive ? :log : :identity, curves)
    end
    return (; schema="bayesianmgmfrm.prior_sensitivity_plot.v1", result_hash=result.content_hash,
        panels, points, bandwidth_rule=bandwidth === nothing ? :pooled_silverman : :user_supplied,
        kernel=:gaussian, tail_display_bandwidths=4, interval_probability=result.interval_probability)
end

"""
    BayesianMGMFRM.plot_prior_sensitivity(result; kind=:interval, annotation_io=stdout,
        size=nothing, bandwidth=nothing, points=256)

Draw same-scale prior rows in separate estimand panels; `kind=:ridge` adds KDEs.
Requires CairoMakie. Warning/missing/failed rows remain visible. Figure titles and
notes are external by default. Ridge heights share one density scale within each
panel; density overlap is neither a contrast test nor evidence of equivalence.
"""
function plot_prior_sensitivity(result; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("plot_prior_sensitivity requires CairoMakie"))
    return extension.plot_prior_sensitivity(result; kwargs...)
end

"""
    BayesianMGMFRM.save_prior_sensitivity_bundle(directory, result; bandwidth=nothing, points=256)
    BayesianMGMFRM.load_prior_sensitivity_bundle(directory)

Export PDF/SVG/PNG interval and ridge figures, external notes, numerical JSON,
and the reloadable result. CairoMakie is required only for writing. The directory
must not exist; all figures are staged before publication. The reader checks
every file hash, then reloads the sealed result. Only load trusted bundles.
"""
function save_prior_sensitivity_bundle(directory::AbstractString, result; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("figure export requires CairoMakie"))
    return extension.save_prior_sensitivity_bundle(directory, result; kwargs...)
end

const _PRIOR_SENSITIVITY_FILES = ("result.jls", "result.json", "plot-data.json",
    "interval.pdf", "interval.svg", "interval.png", "interval-note.txt",
    "ridge.pdf", "ridge.svg", "ridge.png", "ridge-note.txt")
function load_prior_sensitivity_bundle(directory::AbstractString)
    manifest = JSON3.read(read(joinpath(directory,"manifest.json"),String))
    manifest.schema == "bayesianmgmfrm.prior_sensitivity_bundle.v1" &&
        Set(String.(keys(manifest.files))) == Set(_PRIOR_SENSITIVITY_FILES) ||
        throw(ArgumentError("unsupported sensitivity bundle"))
    for name in _PRIOR_SENSITIVITY_FILES
        path = joinpath(directory,name)
        isfile(path) && !islink(path) && _fit_report_figure_file_hash(read(path)).value == manifest.files[Symbol(name)] ||
            throw(ArgumentError("missing or altered bundle file: $name"))
    end
    result = load_prior_sensitivity(joinpath(directory,"result.jls"))
    result.content_hash == manifest.result_hash || throw(ArgumentError("bundle result hash mismatch"))
    return result
end
@doc (@doc save_prior_sensitivity_bundle) load_prior_sensitivity_bundle
