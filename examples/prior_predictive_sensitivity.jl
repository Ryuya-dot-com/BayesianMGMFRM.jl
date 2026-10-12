# Prior-predictive illustration linked to a previously saved posterior comparison.
module PriorPredictiveSensitivityExample
using BayesianMGMFRM, JSON3
const B=BayesianMGMFRM

function compare_saved_priors(spec, posterior_path, output; seeds, ndraws=500)
    posterior=B.load_prior_sensitivity(posterior_path)
    priors=[e.prior_id => B.Experimental.NormalizedMGMFRMPrior(;
        prior_model=e.evaluation.prior.prior_model,
        source_rater=e.evaluation.prior.source_rater,
        e.evaluation.prior.scales...) for e in posterior.ledger if e.evaluation!==nothing]
    result=B.prior_predictive_sensitivity(spec,priors;
        planned_prior_ids=posterior.planned_prior_ids,
        dataset_id=posterior.dataset_id,observation_ids=posterior.observation_ids,
        seeds,ndraws,interval=.90,posterior)
    mkpath(output)
    B.save_prior_predictive_sensitivity(joinpath(output,"result.jls"),result)
    # Compact numerical export; the saved result also retains every statistic draw.
    tables=[(;e.prior_id,e.status,e.posterior_status,
        rows=e.evaluation===nothing ? nothing : [Base.structdiff(r,(;values=nothing)) for r in e.evaluation.rows])
        for e in result.ledger]
    open(joinpath(output,"summary.json"),"w") do io
        JSON3.pretty(io,(;result_hash=result.content_hash,result.posterior_result_hash,
            result.interval_probability,result.interval_method,
            prior_roster=[(;e.prior_id,prior=e.evaluation.prior,seed=e.evaluation.seed,
                ndraws=e.evaluation.ndraws,target_identity=e.evaluation.target_identity)
                for e in result.ledger if e.evaluation!==nothing],tables))
    end
    return result
end
end
