using BayesianMGMFRM

"""
    saved_posterior_reliability(cache_path; parameters, target, weights=nothing)

Read a trusted local fit cache and summarize the explicitly selected cohort.
Use `BayesianMGMFRM.recovery_quantities(load_fit_cache(cache_path))` to select
estimated locations in one facet/dimension. No new sampling is performed.
"""
function saved_posterior_reliability(cache_path::AbstractString; parameters, target, weights=nothing)
    return BayesianMGMFRM.posterior_reliability(load_fit_cache(cache_path);parameters,target,weights)
end
