using BayesianMGMFRM

# Reopen a normalized/correlated MGMFRM or fixed-coefficient multidimensional
# MFRM cache (independent, correlated or exchangeable-rater); keep original IDs.
# This example writes a new report bundle and does not run a sampler.
function saved_mgmfrm_report(cache_path, directory; dataset_id, observation_ids,
        draw_indices=nothing)
    fit = load_fit_cache(cache_path)
    save_fit_report_bundle(directory, fit; dataset_id, observation_ids,
        include_waic=true, include_loo=true, draw_indices, view=:public, require_complete=true)
    return load_fit_report_bundle(directory; require_complete=true)
end
