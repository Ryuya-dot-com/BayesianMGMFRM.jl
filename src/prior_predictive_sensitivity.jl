const _PRIOR_PREDICTIVE_SENSITIVITY_SCHEMA = "bayesianmgmfrm.prior_predictive_sensitivity.v1"

function _prior_sensitivity_common_prior(prior)
    return merge(Base.structdiff(prior, (; scales=nothing)),
        (; scales=Base.structdiff(prior.scales, (; log_discrimination_sd=nothing))))
end

function _prior_predictive_sensitivity_rows(check, interval)
    summaries = predictive_check_summary(check; interval, include_grouped=true)
    replicated = check.replicated
    series = Vector{Float64}[copy(replicated.mean_score)]
    for block in (:category_proportions, :person_mean, :rater_mean, :item_mean)
        append!(series, [collect(x) for x in eachcol(getproperty(replicated, block))])
    end
    for facet in sort(collect(keys(check.optional_levels)); by=string)
        append!(series, [collect(x) for x in eachcol(replicated.optional_mean[facet])])
    end
    append!(series, [Float64.(r.replicated) for r in check.grouped.rows])
    length(series) == length(summaries) || error("predictive summary layout mismatch")
    return map(summaries, series) do row, values
        all(isfinite, values) || throw(ArgumentError("nonfinite predictive statistic"))
        n = length(values)
        n >= 2 || throw(ArgumentError("at least two prior predictive draws are required"))
        lower = Float64.(values .<= row.observed)
        upper = Float64.(values .>= row.observed)
        merge(row, (; values, replicated_sd=std(values),
            mean_mcse=std(values)/sqrt(n),
            lower_tail_mcse=std(lower)/sqrt(n), upper_tail_mcse=std(upper)/sqrt(n),
            mean_mcse_degenerate=allequal(values),
            lower_tail_mcse_degenerate=allequal(lower), upper_tail_mcse_degenerate=allequal(upper),
            mcse_method=:iid_sample_sd_over_sqrt_draws,
            interval_endpoint_mcse=:not_computed))
    end
end

"""
    BayesianMGMFRM.prior_predictive_sensitivity(spec, priors;
        planned_prior_ids, dataset_id, observation_ids, seeds, ndraws,
        interval=0.90, failures=Pair[], posterior=nothing)

Compare explicitly supplied normalized MGMFRM priors on the same observed rating
design. `priors` contains `id => Experimental.NormalizedMGMFRMPrior` pairs; only
`log_discrimination_sd` may differ. `seeds` maps each available ID to an explicit
nonnegative integer seed. `ndraws >= 2` is required, with no automatic extra draws.
Each variant uses the existing prior-predictive generator with its own seeded
MersenneTwister. Observed scores are reference values, not conditioning data.
This generates IID prior parameter/response draws, never posterior fits or SBC.

The sealed result retains all planned IDs, missing/failed variants, full actual
priors, target/data identity, seeds and per-draw statistics for overall/category,
person/item/rater, optional-facet and grouped checks. Replicated intervals are
equal-tailed predictive intervals, not parameter CrIs or HDIs. MCSE of means and
inclusive tail proportions uses sample SD / sqrt(ndraws), not MCMC ESS. Zero
empirical MCSE can reflect an unobserved event; endpoint MCSE is not computed.
Tail probabilities and `flag` are descriptive, not calibrated tests, automatic
prior rankings, or proof of adequacy. They are dependent across statistics.

Optionally bind a saved `prior_sensitivity` result through `posterior`. Its seal,
planned IDs, row IDs/order, canonical design/data, dataset ID and every available
variant's actual prior/target must agree before any simulation. Posterior failures
remain distinct from prior-generation failures. The linked result hash and source
sample hashes are retained; existing posterior draws are neither updated nor fit.
"""
function prior_predictive_sensitivity(spec::FacetSpec, priors;
        planned_prior_ids, dataset_id::AbstractString, observation_ids, seeds,
        ndraws::Integer, interval::Real=0.90, failures=Pair[], posterior=nothing)
    ids = _recovery_replication_names(planned_prior_ids, "planned_prior_ids")
    isempty(strip(dataset_id)) && throw(ArgumentError("dataset_id must be nonempty"))
    !(ndraws isa Bool) && 2 <= ndraws <= typemax(Int) || throw(ArgumentError("ndraws must be at least two"))
    interval isa Bool && throw(ArgumentError("interval must be a probability"))
    _interval_probabilities(interval)
    entries = collect(priors)
    !isempty(entries) && all(p -> p isa Pair && first(p) in ids && last(p) isa _NormalizedMGMFRMPrior, entries) ||
        throw(ArgumentError("provide planned id => NormalizedMGMFRMPrior pairs"))
    length(unique(first.(entries))) == length(entries) || throw(ArgumentError("duplicate prior ID"))
    seeds isa AbstractDict && Set(keys(seeds)) == Set(first.(entries)) ||
        throw(ArgumentError("seeds must map exactly the available prior IDs"))
    all(s -> s isa Integer && !(s isa Bool) && 0 <= s <= typemax(Int), values(seeds)) ||
        throw(ArgumentError("seeds must be nonnegative integers representable as Int"))
    length(unique(values(seeds))) == length(seeds) || throw(ArgumentError("use a different explicit seed for each variant"))
    failed = Dict{String,String}()
    for p in failures
        p isa Pair && first(p) in ids && last(p) isa AbstractString && !isempty(strip(last(p))) &&
            !haskey(failed, first(p)) && !(first(p) in first.(entries)) ||
            throw(ArgumentError("unplanned, duplicate or available failure ID"))
        failed[String(first(p))] = String(last(p))
    end
    observations = PredictionObservationAdapter._ids(observation_ids, spec.data.n, "observation_ids")
    spec_hash = design_identity(getdesign(spec; preview=true)).value
    binding = _prediction_source_binding(spec.data, observations, String(dataset_id))
    targets = Dict(id => _normalized_mgmfrm_target(spec, prior) for (id,prior) in entries)
    records = Dict(id => _mgmfrm_normalized_prior_record(t) for (id,t) in targets)
    common = _prior_sensitivity_common_prior(records[first(first(entries))])
    all(p -> isequal(_prior_sensitivity_common_prior(p), common), values(records)) ||
        throw(ArgumentError("only log_discrimination_sd may differ"))
    if posterior !== nothing
        _prediction_check_seal(posterior, _PRIOR_SENSITIVITY_SCHEMA)
        posterior.planned_prior_ids == ids && posterior.dataset_id == dataset_id &&
            posterior.observation_ids == observations && posterior.spec_hash == spec_hash &&
            posterior.source_binding == binding && isequal(posterior.model_contract.common_prior, common) ||
            throw(ArgumentError("posterior roster, data, design or common prior differs"))
        for entry in posterior.ledger
            e = entry.evaluation
            (e === nothing || !haskey(targets,entry.prior_id)) && continue
            isequal(e.prior, records[entry.prior_id]) &&
                e.target_identity == _mgmfrm_normalized_prior_identity(targets[entry.prior_id]) ||
                throw(ArgumentError("posterior prior/target differs for $(entry.prior_id)"))
        end
    end
    evaluations = Dict{String,Any}()
    for id in ids
        haskey(targets,id) || continue
        check = _normalized_mgmfrm_prior_check(targets[id]; ndraws=Int(ndraws), rng=MersenneTwister(Int(seeds[id])))
        evaluations[id] = (; prior=records[id], check.target_identity, check.prior_metadata,
            seed=Int(seeds[id]), ndraws=Int(ndraws),
            rows=_prior_predictive_sensitivity_rows(check, interval),
            check.implication_diagnostics, generator=:normalized_mgmfrm_prior_predictive,
            rng=:MersenneTwister, julia_version=string(VERSION))
    end
    ledger = map(ids) do id
        linked = posterior === nothing ? nothing : only(e for e in posterior.ledger if e.prior_id == id)
        (; prior_id=id, status=haskey(evaluations,id) ? :descriptive : haskey(failed,id) ? :failed : :missing,
            reason=get(failed,id,nothing), evaluation=get(evaluations,id,nothing),
            posterior_status=linked === nothing ? :not_linked : linked.status,
            posterior_source_sample_hash=linked === nothing || linked.evaluation === nothing ? nothing : linked.evaluation.source_sample_hash)
    end
    return _prediction_seal((; schema=_PRIOR_PREDICTIVE_SENSITIVITY_SCHEMA,
        dataset_id=String(dataset_id), observation_ids=observations, source_binding=binding,
        spec_hash, planned_prior_ids=ids, ledger,
        scope=:normalized_mgmfrm_loading_prior_sd_only,
        prediction_target=:existing_rating_rows, common_prior=common,
        category_levels=copy(spec.data.category_levels),
        interval_probability=Float64(interval), interval_method=:equal_tailed_predictive,
        posterior_result_hash=posterior === nothing ? nothing : posterior.content_hash,
        scientific_acceptance=:not_established, new_fits=0, new_scientific_replications=0))
end

"""
    BayesianMGMFRM.save_prior_predictive_sensitivity(path, result)
    BayesianMGMFRM.load_prior_predictive_sensitivity(path)

Save/reload the sealed comparison, including generated statistic draws, seeds,
actual priors and optional posterior link. Existing paths are refused. Load only
trusted Julia serialization files; integrity hashes do not authenticate a source.
"""
function save_prior_predictive_sensitivity(path::AbstractString, result)
    _prediction_check_seal(result, _PRIOR_PREDICTIVE_SENSITIVITY_SCHEMA)
    (ispath(path) || islink(path)) && throw(ArgumentError("destination already exists"))
    return _save_serialized_record(path, result)
end
function load_prior_predictive_sensitivity(path::AbstractString)
    result = open(deserialize, path)
    _prediction_check_seal(result, _PRIOR_PREDICTIVE_SENSITIVITY_SCHEMA)
    return result
end
@doc (@doc save_prior_predictive_sensitivity) load_prior_predictive_sensitivity

"""
    BayesianMGMFRM.plot_prior_predictive_sensitivity(result;
        statistic=:category_proportion, levels=nothing, annotation_io=stdout, size=nothing)

Compare a declared statistic across priors. `levels=nothing` displays all levels;
an explicit collection selects exact level IDs. Dots/bars are prior predictive
medians/intervals; dashed lines mark observed statistics. Requires CairoMakie.
Every level has a panel on a common scale; failed/missing rows remain visible.
Figure notes are external by default. This does not visualize parameter CrIs.
"""
function plot_prior_predictive_sensitivity(result; kwargs...)
    extension = Base.get_extension(@__MODULE__, :BayesianMGMFRMCairoMakieExt)
    extension === nothing && throw(ArgumentError("plot_prior_predictive_sensitivity requires CairoMakie"))
    return extension.plot_prior_predictive_sensitivity(result; kwargs...)
end
