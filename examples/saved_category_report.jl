using BayesianMGMFRM

"""
    saved_category_report(cache_path; dataset_id, observation_ids, kwargs...)

Read a trusted fit cache and summarize category use, correctly owned transitions,
and optional conditional probability slices. This consumes saved draws without
fitting or simulating ratings. `interval=0.99` selects a pointwise 99% equal-tailed
interval, not a predictive interval or HDI. See `BayesianMGMFRM.category_report`.
"""
function saved_category_report(cache_path::AbstractString; dataset_id, observation_ids, kwargs...)
    return BayesianMGMFRM.category_report(load_fit_cache(cache_path);
        dataset_id, observation_ids, kwargs...)
end
