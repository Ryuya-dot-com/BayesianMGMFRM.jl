using BayesianMGMFRM

"""
    saved_kfold_comparison(models::Pair...; comparison_axis, baseline=nothing,
        mcse=:none, independent_fold_rng=false, independent_model_rng=false)

Each named model supplies `(prepared=plan, caches=Dict(fold_id=>path), failures=...)`.
`failures` is optional; missing caches remain missing folds. Invalid/corrupted
caches raise errors rather than silently becoming missing observations. This
example invokes no sampler and uses only public/qualified prediction APIs.
Optional `mcse=:delta` reports first-order numerical error from saved draws.
Declare independent fold/model random streams explicitly to combine MCSEs;
this does not supply uncertainty from resampling data or overlapping folds.
"""
function saved_kfold_comparison(models::Pair...; comparison_axis::Symbol, baseline=nothing,
        mcse::Symbol=:none, independent_fold_rng::Bool=false, independent_model_rng::Bool=false)
    summaries = map(models) do (label, entry)
        entry.caches isa AbstractDict || throw(ArgumentError("caches must be a fold-ID dictionary"))
        expected = [r.fold for r in entry.prepared.folds]
        all(id -> id in expected, keys(entry.caches)) || throw(ArgumentError("unknown cache fold ID"))
        scores = [BayesianMGMFRM.prediction_fold_observations(
            load_fit_cache(entry.caches[r.fold]), r; include_probabilities=false)
            for r in entry.prepared.folds if haskey(entry.caches, r.fold)]
        label => BayesianMGMFRM.prediction_kfold(entry.prepared, scores;
            failures=get(entry, :failures, Pair[]), mcse, independent_fold_rng)
    end
    return BayesianMGMFRM.compare_kfold_predictions(summaries...; comparison_axis, baseline, independent_model_rng)
end
