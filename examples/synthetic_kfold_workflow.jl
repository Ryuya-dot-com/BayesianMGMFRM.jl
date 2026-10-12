using BayesianMGMFRM, Serialization

"""
    synthetic_kfold_workflow(directory; sampler, seed=261011)

Fit eight explicitly specified model/prior combinations on the same synthetic
two-fold split, save every training fit, and compare heldout rating predictions.
`sampler` must supply `chains`, `warmup`, `ndraws`, and `max_depth`. All fits use
AdvancedHMC. The fixed ratings and prior scales demonstrate API use; they are
neither a generative study nor recommended scientific settings. Short runs are
operability checks only. Inspect the retained diagnostics and MCSE before making
any substantive interpretation. The comparison never chooses a winner.

All three ratings of a person-item response stay in the same fold. Predictions
concern existing people, items and raters; the score is additive over ratings,
not a joint response probability. An existing output directory is rejected.
On an error, completed caches remain available, but this example does not retry
or resume sampling. `replay_synthetic_kfold_workflow(directory)` reuses a completed
run without fitting. Julia Serialization requires a compatible Julia environment.
"""
function synthetic_kfold_workflow(directory; sampler, seed::Int=261011)
    ispath(directory) && throw(ArgumentError("output directory already exists"))
    Set(keys(sampler)) == Set((:chains, :warmup, :ndraws, :max_depth)) ||
        throw(ArgumentError("supply exactly chains, warmup, ndraws and max_depth"))
    B, E = BayesianMGMFRM, BayesianMGMFRM.Experimental
    response_orders = ((1,2,3,4), (1,2,4,3), (2,1,3,4), (2,1,4,3))
    rows = [(; person="P$p", item="I$i", rater="R$r",
        score=mod(p + 2r + i + div(p*i, 2), 3),
        # Both folds stay connected and retain one item per dimension for each person.
        response_id=4(p-1) + response_orders[mod1(p,4)][i]) for p in 1:8 for i in 1:4 for r in 1:3]
    table = (; person=[row.person for row in rows], item=[row.item for row in rows],
        rater=[row.rater for row in rows], score=[row.score for row in rows],
        response_id=[row.response_id for row in rows])
    data = FacetData(table; person=:person, item=:item, rater=:rater, score=:score,
        response_id=:response_id, category_levels=0:2)
    scalar = mfrm_spec(data)
    generalized = mfrm_spec(data; family=:gmfrm, discrimination=:rater)
    fixed = mfrm_spec(data; dimensions=2, dimension_labels=["A", "B"],
        q_matrix=Bool[1 0; 1 0; 0 1; 0 1])
    multidimensional = mfrm_spec(data; family=:mgmfrm, dimensions=2,
        dimension_labels=["A", "B"], q_matrix=Bool[1 0; 1 0; 0 1; 0 1])
    scales = (; person_sd=1.0, rater_sd=0.5, item_sd=1.0,
        log_discrimination_sd=0.25, log_consistency_sd=0.25, step_sd=0.5)
    fixed_prior = MFRMPrior(person_sd=1.0, rater_sd=0.5, item_sd=1.0, step_sd=0.5)
    raw_prior = E.GeneralizedPrior(; scales...)
    roster = [
        (; label="MFRM 1D", model=scalar, prior=fixed_prior, fitter=fit),
        (; label="GMFRM 1D", model=generalized, prior=raw_prior, fitter=E.fit),
        (; label="MGMFRM 2D raw", model=multidimensional, prior=raw_prior, fitter=E.fit),
        (; label="MGMFRM 2D normalized", model=multidimensional,
            prior=E.NormalizedMGMFRMPrior(; prior_model=:exchangeable, scales...), fitter=E.fit),
        (; label="MGMFRM 2D correlated", model=E.correlated(multidimensional; lkj_eta=2),
            prior=raw_prior, fitter=E.fit),
        (; label="MFRM 2D", model=fixed, prior=fixed_prior, fitter=E.fit),
        (; label="MFRM 2D correlated", model=E.correlated(fixed; lkj_eta=2),
            prior=fixed_prior, fitter=E.fit),
        (; label="MFRM 2D exchangeable", model=fixed,
            prior=E.ExchangeablePrior(person_sd=1.0, rater_kernel_sd=0.5,
                item_sd=1.0, step_sd=0.5), fitter=E.fit),
    ]
    split = kfold_plan(data; k=2, group_by=:response_id)
    ids = ["rating-$i" for i in 1:data.n]
    plans = [B.prediction_refit_plan(entry.model, split; prior=entry.prior,
        dataset_id="synthetic-kfold-operability-v1", observation_ids=ids) for entry in roster]
    mkdir(directory)
    serialize(joinpath(directory, "inputs.jls"), (; plans, labels=[r.label for r in roster], sampler, seed))
    summaries = Pair[]
    for (i, (entry, prepared)) in enumerate(zip(roster, plans))
        scores = []
        for (j, request) in enumerate(prepared.folds)
            println("Fitting ", entry.label, "; fold ", request.fold); flush(stdout)
            fitted = entry.fitter(request.model; prior=request.prior, backend=:advancedhmc,
                sampler..., seed=seed + 2(i-1) + j)
            cache = joinpath(directory, "model-$i-fold-$j.jls")
            save_fit_cache(cache, fitted)
            score = B.prediction_fold_observations(fitted, request; include_probabilities=false)
            serialize(joinpath(directory, "model-$i-fold-$j-output.jls"),
                (; score, metadata=fit_metadata(fitted), diagnostics=diagnostics(fitted),
                    parameter_mcse=posterior_mcse(fitted)))
            push!(scores, score)
        end
        push!(summaries, entry.label => B.prediction_kfold(prepared, scores))
    end
    comparison = B.compare_kfold_predictions(summaries...; comparison_axis=:dimensions)
    serialize(joinpath(directory, "comparison.jls"), comparison)
    return comparison
end

"""Reproduce the example's saved comparison, using no sampler or private API."""
function replay_synthetic_kfold_workflow(directory)
    B = BayesianMGMFRM
    input = deserialize(joinpath(directory, "inputs.jls"))
    summaries = map(enumerate(zip(input.labels, input.plans))) do (i, (label, prepared))
        scores = [B.prediction_fold_observations(
            load_fit_cache(joinpath(directory, "model-$i-fold-$j.jls")), request;
            include_probabilities=false) for (j, request) in enumerate(prepared.folds)]
        label => B.prediction_kfold(prepared, scores)
    end
    return B.compare_kfold_predictions(summaries...; comparison_axis=:dimensions)
end
