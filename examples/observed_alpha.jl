using BayesianMGMFRM

"""
    observed_alpha_example()

Compute nominal and ordinal alpha for the same toy criterion, without fitting.
Response C has only one rating: it remains visible but contributes to neither
disagreement. Integer labels encode the declared order, not interval distances.
"""
function observed_alpha_example()
    table=(;person=[1,1,1,2,2,3],rater=[1,2,3,1,2,1],
        item=fill("fluency",6),response=["A","A","A","B","B","C"],
        score=[1,1,2,3,3,2])
    data=FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:response,category_levels=1:3)
    options=(;item="fluency",dataset_id="alpha-example",
        observation_ids=["rating-$n" for n in 1:data.n])
    (;data,nominal=BayesianMGMFRM.krippendorff_alpha(data;options...,level=:nominal),
        ordinal=BayesianMGMFRM.krippendorff_alpha(data;options...,level=:ordinal))
end
