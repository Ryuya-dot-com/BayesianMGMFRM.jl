# Compare trusted saved fit caches without fitting or generating random draws.
module PriorSensitivityExample
using BayesianMGMFRM, SHA
using BayesianMGMFRM: JSON3
const B = BayesianMGMFRM

"""
    run_saved_example(cache_paths, output; planned_prior_ids, estimands,
        dataset_id, observation_ids, kwargs...)

Compare `prior_id => cache_path` pairs using `BayesianMGMFRM.prior_sensitivity`.
Use trusted caches in their original Julia/dependency environment. Declare the
full planned roster, exact quantity names and original fitted row IDs; optional
arguments such as `vary`, `failures`, `interval`, `cutoffs` and `max_mcse` pass through
to the comparison. Missing or unreadable files stop the operation; list known
failed fits in `failures` instead of supplying a nonexistent cache path.
Use `vary=:mean_profile` for the admitted fixed-one D1 profile alternatives;
the default remains the loading-SD comparison.

Write `result.jls` and `sources.json` to a new directory and verify result reload.
The JSON records cache paths/hashes, the planned roster and result hash; it is
provenance, not a portable posterior report. Existing destinations are refused.
Including this file only defines functions; it does not run an analysis.
"""
function run_saved_example(cache_paths, output; planned_prior_ids, estimands,
        dataset_id, observation_ids, kwargs...)
    (ispath(output) || islink(output)) && throw(ArgumentError("Choose a new output directory."))
    entries = collect(cache_paths)
    !isempty(entries) && all(p -> p isa Pair && first(p) isa AbstractString &&
        last(p) isa AbstractString, entries) ||
        throw(ArgumentError("cache_paths must contain prior_id => cache_path pairs."))
    fits = [id => load_fit_cache(path) for (id, path) in entries]
    result = B.prior_sensitivity(fits; planned_prior_ids, estimands,
        dataset_id, observation_ids, kwargs...)
    sources = [(; prior_id=id, path=abspath(path), sha256=bytes2hex(open(sha256, path)))
        for (id, path) in entries]
    mkpath(dirname(abspath(output)))
    mkdir(output)
    result_path = joinpath(output, "result.jls")
    B.save_prior_sensitivity(result_path, result)
    restored = B.load_prior_sensitivity(result_path)
    isequal(restored, result) || error("Saved and reloaded prior comparisons differ.")
    open(joinpath(output, "sources.json"), "w") do io
        JSON3.pretty(io, (; sources, planned_prior_ids=result.planned_prior_ids,
            result_hash=result.content_hash, new_fits=result.new_fits,
            scientific_acceptance=result.scientific_acceptance))
    end
    return restored
end
end
