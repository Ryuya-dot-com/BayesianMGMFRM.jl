"""Read an existing fit cache through the opt-in common prediction adapter."""
module CommonPredictionExample
const HELP = """
Usage: julia --project=. examples/common_prediction_observations.jl FIT.jls DATASET_ID IDS.txt

Repository prototype; the common adapter is not yet a package API.
FIT.jls: an existing save_fit_cache file, not a private raw sample record.
DATASET_ID: the stable identity/version of the original fitted rating data.
IDS.txt: one unique, nonblank observation ID per line, in the original fit row order.
Keep IDs from data ingestion; person/item/rater combinations need not be unique.

No fitting or file writes. A one-draw probability preview checks array axes;
WAIC and raw importance-sampling LOO use every retained draw and chain.
Predictions condition on existing fitted rows/levels with equal-row weighting.
This is not heldout K-fold evaluation or new-person/rater prediction.
Sampling and criterion warnings remain visible. Pointwise score SE is not MCMC
MCSE or a cluster-adjusted SE; reference PSIS equivalence is not established.
"""

# Help and argument errors must not initialize the inference library.
if abspath(PROGRAM_FILE) == @__FILE__
    if isempty(ARGS) || ARGS == ["--help"]
        print(HELP)
        exit(0)
    end
    length(ARGS) == 3 || throw(ArgumentError(HELP))
end

using BayesianMGMFRM, SHA
include("../scripts/prediction_observation_adapter.jl")
using .PredictionObservationAdapter

function main(args=ARGS; io=stdout)
    if isempty(args) || args == ["--help"]
        print(io, HELP)
        return nothing
    end
    length(args) == 3 || throw(ArgumentError(HELP))
    cache_path, dataset_id, ids_path = args
    digest = bytes2hex(open(sha256, cache_path))
    fit = load_fit_cache(cache_path)
    ids = readlines(ids_path)
    preview = prediction_observations(fit; dataset_id, observation_ids=ids, draw_indices=[1])
    evaluation = prediction_criteria(fit; dataset_id, observation_ids=ids,
        criteria=(:waic, :raw_loo))
    bytes2hex(open(sha256, cache_path)) == digest || error("Input cache changed during review")
    println(io, "Prototype: existing fitted rows only; no new fit or acceptance decision.")
    println(io, "Dataset: ", dataset_id, "; observations: ", length(ids))
    println(io, "Category order: ", preview.category_levels)
    println(io, "Probability preview axes (one draw, observations, categories): ", size(preview.probabilities))
    println(io, "This preview is one draw, not a posterior mean or a precision assessment.")
    println(io, "Full log-likelihood axes (draws, observations): ", size(evaluation.prediction.pointwise_loglikelihood))
    println(io, "Model: ", preview.model.family, "; likelihood scale: ", preview.model.likelihood_scale)
    println(io, "WAIC ELPD: ", evaluation.scores.waic.elpd_waic)
    println(io, "Raw IS-LOO ELPD: ", evaluation.scores.raw_loo.elpd_loo)
    println(io, "Sampling warning: ", evaluation.sampling_warning)
    println(io, "Criterion warnings: ", evaluation.criterion_warnings)
    println(io, "Problem observation IDs: ", evaluation.problem_observation_ids)
    println(io, "Uncertainty: ", evaluation.uncertainty)
    println(io, "No automatic model ranking, reference PSIS validation or scientific acceptance.")
    return (; preview, evaluation)
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    CommonPredictionExample.main()
end
