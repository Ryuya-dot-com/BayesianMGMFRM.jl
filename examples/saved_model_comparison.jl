using BayesianMGMFRM

# Supply persistent rating IDs in each fit's original row order. A dictionary
# keyed by these model names supports fits whose input rows were permuted.
function saved_model_comparison(caches::Pair...; dataset_id, observation_ids,
        comparison_axis, criterion=:waic, baseline=nothing, se_unit=:none)
    fits = [name => load_fit_cache(path) for (name,path) in caches]
    return BayesianMGMFRM.compare_predictions(fits...; dataset_id, observation_ids,
        comparison_axis, criterion, baseline, se_unit)
end
