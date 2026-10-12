using BayesianMGMFRM

"""
    saved_rater_agreement(cache_path; dataset_id, observation_ids, kwargs...)

Read a trusted local fit cache and summarize common-response score agreement.
Supply `response_ids` unless the fit already retains response metadata. These
identify the same performance, not merely the same person or person-item cell.
No new sampling is performed. See `BayesianMGMFRM.rater_agreement` for matching,
denominators, expected-rate intervals and optional person-cluster observed SEs.
"""
function saved_rater_agreement(cache_path::AbstractString; dataset_id, observation_ids, kwargs...)
    return BayesianMGMFRM.rater_agreement(load_fit_cache(cache_path);
        dataset_id,observation_ids,kwargs...)
end
