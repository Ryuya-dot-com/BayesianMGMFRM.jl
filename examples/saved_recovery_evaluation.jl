using BayesianMGMFRM

"""
    saved_recovery_evaluation(cache_path, truth; dataset_id, observation_ids, interval=0.95)

Evaluate one saved fit against named model-coordinate truths. Does not generate
data, fit a model, pool datasets, or interpret synthetic checks as calibration.
Use `BayesianMGMFRM.recovery_quantities(load_fit_cache(cache_path))` to inspect
the available names, scales and fixed quantities before supplying truth.
"""
function saved_recovery_evaluation(cache_path::AbstractString, truth::AbstractDict;
        dataset_id::AbstractString, observation_ids, interval::Real=0.95)
    return BayesianMGMFRM.recovery_evaluation(load_fit_cache(cache_path), truth;
        dataset_id, observation_ids, interval)
end
