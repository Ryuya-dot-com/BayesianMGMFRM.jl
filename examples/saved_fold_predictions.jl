using BayesianMGMFRM

"""
    saved_fold_predictions(cache_path, request; include_probabilities=false)

Score a saved training fit against a request from `prediction_refit_plan`.
Does not fit, filter diagnostic warnings, aggregate folds, or select a model.
The caller retains the prepared request with its source data and persistent IDs.
"""
function saved_fold_predictions(cache_path::AbstractString, request;
        include_probabilities::Bool=false)
    training_fit = load_fit_cache(cache_path)
    return BayesianMGMFRM.prediction_fold_observations(training_fit, request;
        include_probabilities)
end
