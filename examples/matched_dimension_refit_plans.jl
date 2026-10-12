using BayesianMGMFRM

"""
    matched_dimension_refit_plans(data, split; q_matrix, dimension_labels,
        prior, dataset_id, observation_ids)

Prepare one-dimensional and between-item MGMFRM training requests on the same
ratings and split. Supply a normalized MGMFRM prior and one active Q entry per
item. The same prior object, item-owned steps, coefficient placement and 1.7
likelihood constant are used in both models. Ability dimensionality and item
assignment differ; equal numeric prior settings do not make joint predictive
distributions equal. Neither model is the rater-step scalar GMFRM.

No fitting, model selection or precision guarantee is performed. Fit each
request with `Experimental.fit(request.model; prior=request.prior, ...)`, then
use `prediction_fold_observations`, `prediction_kfold` and
`compare_kfold_predictions(...; comparison_axis=:dimensions)`. Retain failed
folds and diagnostics. This example leaves numerical controls to the caller.
"""
function matched_dimension_refit_plans(data, split; q_matrix, dimension_labels,
        prior, dataset_id, observation_ids)
    prior isa BayesianMGMFRM.Experimental.NormalizedMGMFRMPrior ||
        throw(ArgumentError("supply an explicit normalized MGMFRM prior"))
    q_matrix isa AbstractMatrix && size(q_matrix,2)>=2 ||
        throw(ArgumentError("the comparison Q must have at least two columns"))
    multidimensional=mfrm_spec(data;family=:mgmfrm,dimensions=size(q_matrix,2),
        thresholds=:partial_credit,q_matrix,dimension_labels)
    all(==(1),sum(multidimensional.q_matrix;dims=2)) ||
        throw(ArgumentError("this matched-loading example requires one active dimension per item"))
    unidimensional=mfrm_spec(data;family=:mgmfrm,dimensions=1,
        thresholds=:partial_credit,q_matrix=trues(length(data.item_levels),1),
        dimension_labels=["General"])
    return [label=>BayesianMGMFRM.prediction_refit_plan(model,split;
        prior,dataset_id,observation_ids) for (label,model) in
        ("One dimension"=>unidimensional,"Multiple dimensions"=>multidimensional)]
end
