module PriorPredictiveSensitivityTests
using Test, BayesianMGMFRM, Random, Statistics, Serialization
const B=BayesianMGMFRM
const SCALES=(;person_sd=.8,rater_sd=.6,item_sd=.9,log_discrimination_sd=.3,log_consistency_sd=.4,step_sd=.7)
function specification(; offset=0, categories=0:3)
    cells=[(p,i,r) for p in 1:2 for i in 1:4 for r in 1:3]
    data=FacetData((;person=first.(cells),item=getindex.(cells,2),rater=getindex.(cells,3),
        score=[categories[mod(p+2i+r+offset,length(categories))+1] for (p,i,r) in cells]);
        person=:person,item=:item,rater=:rater,score=:score,category_levels=categories)
    mfrm_spec(data;family=:mgmfrm,dimensions=2,thresholds=:partial_credit,q_matrix=Bool[1 0;1 0;0 1;0 1])
end
prior(sd=.3;person_sd=.8)=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,
    merge(SCALES,(;log_discrimination_sd=sd,person_sd))...)
const SPEC=specification()
const ARGS=(;planned_prior_ids=["narrow","wide","failed","missing"],dataset_id="test-rating-design",
    observation_ids=["rating-$i" for i in 1:SPEC.data.n], seeds=Dict("narrow"=>71,"wide"=>72),
    ndraws=40,failures=["failed"=>"Declared failure; no generated result"])

@testset "Prior comparison: actual generator and independent statistic calculations" begin
    global result=B.prior_predictive_sensitivity(SPEC,["narrow"=>prior(),"wide"=>prior(.8)];ARGS...,interval=.99)
    @test [e.status for e in result.ledger]==[:descriptive,:descriptive,:failed,:missing]
    @test all(e->e.posterior_status===:not_linked,result.ledger)
    @test result.new_fits==result.new_scientific_replications==0
    @test result.interval_method===:equal_tailed_predictive
    @test result.scientific_acceptance===:not_established
    @test isequal(result,B.prior_predictive_sensitivity(SPEC,["narrow"=>prior(),"wide"=>prior(.8)];ARGS...,interval=.99))
    @test isequal(result,B.prior_predictive_sensitivity(SPEC,["wide"=>prior(.8),"narrow"=>prior()];ARGS...,interval=.99))
    check=B.Experimental.prior_predictive_check(SPEC;prior=prior(),ndraws=40,rng=MersenneTwister(71))
    rows=result.ledger[1].evaluation.rows
    @test length(rows)==length(B.predictive_check_summary(check;include_grouped=true))
    for row in rows
        indices=if row.statistic===:mean_score || row.statistic===:category_proportion
            1:SPEC.data.n
        elseif row.statistic in (:person_mean,:item_mean,:rater_mean)
            field=Symbol(first(split(string(row.statistic),'_')))
            levels=getproperty(SPEC.data,Symbol(field,:_levels))
            findall(==(findfirst(isequal(row.level),levels)),getproperty(SPEC.data,field))
        else
            continue
        end
        direct=row.statistic===:category_proportion ?
            vec(mean(check.replicated_scores[:,indices].==row.level;dims=2)) :
            vec(mean(check.replicated_scores[:,indices];dims=2))
        @test row.values ≈ direct
        @test row.replicated_mean ≈ mean(direct)
        @test row.replicated_lower ≈ quantile(direct,.005)
        @test row.replicated_upper ≈ quantile(direct,.995)
        @test row.mean_mcse ≈ std(direct)/sqrt(40)
        @test row.upper_tail_probability==mean(direct .>= row.observed)
        @test row.upper_tail_mcse ≈ std(Float64.(direct .>= row.observed))/sqrt(40)
        @test row.interval_endpoint_mcse===:not_computed
    end
    changed=B.prior_predictive_sensitivity(specification(;offset=1),["narrow"=>prior(),"wide"=>prior(.8)];ARGS...)
    @test changed.spec_hash!=result.spec_hash
    @test changed.source_binding!=result.source_binding
    @test all(a.values==b.values for (a,b) in zip(rows,changed.ledger[1].evaluation.rows))
    @test any(a.observed!=b.observed for (a,b) in zip(rows,changed.ledger[1].evaluation.rows))
    binary=B.prior_predictive_sensitivity(specification(;categories=1:2),["narrow"=>prior()];
        merge(ARGS,(;seeds=Dict("narrow"=>17),ndraws=2))...)
    @test all(r->all(isfinite,r.values),binary.ledger[1].evaluation.rows)
    @test binary.category_levels==[1,2]
    @test any(r->r.mean_mcse_degenerate,binary.ledger[1].evaluation.rows)
end

@testset "Input rejection and persistence" begin
    entries=["narrow"=>prior(),"wide"=>prior(.8)]
    for args in ((;ndraws=1),(;ndraws=true),(;interval=1.),(;interval=true),(;dataset_id=" "),
            (;seeds=Dict("narrow"=>1,"wide"=>1)),(;seeds=Dict("narrow"=>-1,"wide"=>2)),
            (;seeds=Dict("narrow"=>true,"wide"=>2)),(;seeds=Dict("narrow"=>1)),
            (;observation_ids=reverse(ARGS.observation_ids)[1:end-1]),
            (;observation_ids=fill("duplicate",SPEC.data.n)),(;failures=["narrow"=>"no"]),
            (;failures=["failed"=>"no","failed"=>"again"]),
            (;planned_prior_ids=["narrow","wide","narrow"]))
        @test_throws ArgumentError B.prior_predictive_sensitivity(SPEC,entries;merge(ARGS,args)...)
    end
    @test_throws ArgumentError B.prior_predictive_sensitivity(SPEC,["narrow"=>prior(),"wide"=>prior(.8;person_sd=1.)];ARGS...)
    @test_throws ArgumentError B.prior_predictive_sensitivity(SPEC,["narrow"=>prior(),"narrow"=>prior()];ARGS...)
    @test_throws ArgumentError B.prior_predictive_sensitivity(SPEC,["unplanned"=>prior()];ARGS...)
    @test_throws ArgumentError B.prior_predictive_sensitivity(SPEC,["narrow"=>B.MFRMPrior()];ARGS...)
    mktempdir() do dir
        path=joinpath(dir,"prior-check.jls")
        B.save_prior_predictive_sensitivity(path,result)
        @test isequal(B.load_prior_predictive_sensitivity(path),result)
        @test_throws ArgumentError B.save_prior_predictive_sensitivity(path,result)
        bad=deepcopy(result);bad.ledger[1].evaluation.rows[1].values[1]+=.1
        @test_throws ArgumentError B.save_prior_predictive_sensitivity(joinpath(dir,"bad.jls"),bad)
        serialize(joinpath(dir,"bad.jls"),bad)
        @test_throws ArgumentError B.load_prior_predictive_sensitivity(joinpath(dir,"bad.jls"))
    end
end
end
