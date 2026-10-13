using BayesianMGMFRM

"""
    mean_profile_example()

Return an artificial three-category fixed-slope model and explicit mean-profile
prior. This function performs no sampling. Means and scales illustrate the API;
they are not recommended application priors. Duplicate observations let a caller
prepare an existing-level K-fold split without dropping any facet levels.
"""
function mean_profile_example()
    E=BayesianMGMFRM.Experimental
    cells=[(p,i,r) for p in 1:3 for i in ("Clarity","Accuracy") for r in ("A","B") for repeat in 1:2]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=last.(cells),
        score=[mod(p+(i=="Clarity")+(r=="A"),3) for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
    spec=mfrm_spec(data;family=:mgmfrm,dimensions=1,thresholds=:partial_credit,q_matrix=trues(2,1))
    model=E.slope_restriction(spec;item_slopes=:fixed_one,rater_consistency=:fixed_one)
    # Base SDs are raw-scale inputs, even when the means below use unit-logit units.
    base=E.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
        person_sd=.8/1.7,rater_sd=.6/1.7,item_sd=.5/1.7,step_sd=.3/1.7,
        log_discrimination_sd=.3,log_consistency_sd=.4)
    prior=E.MeanProfilePrior(model,base;
        item_means=Dict("Clarity"=>-.2,"Accuracy"=>.3),
        step_means=Dict("Clarity"=>[-.5,.5],"Accuracy"=>[-.8,.8]),
        category_levels=0:2,units=:unit_logit)
    (;spec,model,prior)
end
