using BayesianMGMFRM

"""
    observed_icc_example()

Compare absolute agreement with consistency, without fitting. Every response
has ratings from both raters. The second rater always gives one point more.
Equal category gaps are explicitly assumed; this toy example does not validate
that assumption for a real ordinal rubric.
"""
function observed_icc_example()
    table=(;person=repeat(1:3;inner=2),rater=repeat(1:2;outer=3),
        item=fill("fluency",6),response=repeat(["A","B","C"];inner=2),score=[1,2,2,3,3,4])
    data=FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
        response_id=:response,category_levels=1:4)
    options=(;item="fluency",model=:two_way_mixed,score_scale=:interval,
        dataset_id="icc-example",observation_ids=["rating-$n" for n in 1:data.n])
    results=[BayesianMGMFRM.intraclass_correlation(data;options...,definition,unit)
        for definition in (:agreement,:consistency) for unit in (:single,:average)]
    (;data,results)
end
