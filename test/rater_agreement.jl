module RaterAgreementChecks
using BayesianMGMFRM, Test, Statistics, Serialization
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks
const K=CommonPredictionKfoldChecks
include("../examples/saved_rater_agreement.jl")

function finite_checks()
    @testset "Agreement probability algebra and uncertainty targets" begin
        p=zeros(1,2,3);p[1,1,:]=[.1,.4,.5];p[1,2,:]=[.2,.6,.2]
        sums=B._agreement_expected_sums(p,[(1,2)],1)
        @test sums[1,1] ≈ .36
        @test sums[1,2] ≈ .88
        @test B._agreement_expected_sums(p,[(1,2)],0)[1,:] ≈ [.36,.36]
        @test B._agreement_expected_sums(p,[(1,2)],2)[1,2] ≈ 1
        # Product of posterior means is not the posterior mean of the joint product.
        joint=zeros(2,2,2);joint[:,:,1]=[.9 .9;.1 .1];joint[:,:,2]=1 .- joint[:,:,1]
        @test mean(B._agreement_expected_sums(joint,[(1,2)],0)[:,1]) ≈ .82
        @test sum(mean(joint;dims=1)[1,1,:].*mean(joint;dims=1)[1,2,:]) ≈ .5
        joint[:,2,:]=joint[end:-1:1,2,:]
        @test mean(B._agreement_expected_sums(joint,[(1,2)],0)[:,1]) ≈ .18
        # Unequal cluster sizes: totals (1, 0, 2), sizes (1, 2, 3), p=1/2.
        y=[1,0,0,1,1,0];persons=[1,2,2,3,3,3]
        se=B._agreement_observed_se(y,persons,:person)
        @test se.value ≈ .25
        @test se.status === :approximate
        @test B._agreement_observed_se([1,0,1,1],[1,1,2,2],:person).value ≈ std([.5,1.])/sqrt(2)
        @test B._agreement_observed_se(y,ones(Int,6),:person).status === :insufficient_persons
        @test ismissing(B._agreement_observed_se(y,persons,:none).value)
        @test B._agreement_observed_se(ones(6),persons,:person).status === :empirical_zero_cluster_variance
        @test B._agreement_observed_se(Int[],Int[],:person).status === :no_common_units
        values=[.4+.1sin(s)+.05cos(s/3) for s in 1:80]
        metric=B._agreement_metric(y,persons,6values,2,.99,:person)
        @test metric.expected_mean ≈ mean(values)
        @test metric.expected_lower ≈ quantile(values,.005)
        @test metric.expected_upper ≈ quantile(values,.995)
        @test metric.observed_minus_expected_mean ≈ .5-mean(values)
        native=only(posterior_mcse(reshape(values,:,1);chains=2,parameter_names=["expected_agreement"],probabilities=(.005,.5,.995)))
        @test metric.mcse.mean_mcse ≈ native.mean_mcse
        @test metric.mcse.mcse_status === :available
        degenerate=B._agreement_metric(y,persons,fill(3.,80),2,.95,:none)
        @test degenerate.status === :mcse_unavailable
        structural=B._agreement_metric(ones(6),persons,fill(6.,80),2,.95,:none;structural_one=true)
        @test structural.expected_mean==structural.expected_lower==structural.expected_upper==1
        @test structural.mcse.mean_mcse==0 && structural.status===:all_categories_within_tolerance
    end
end

function matching_checks()
    @testset "Response identity, repeated performances and complete denominators" begin
        table=(;person=[1,1,1,1,1,2,2,3,3,3],item=[1,1,1,2,2,1,1,1,1,1],
            rater=[1,2,3,1,2,1,2,1,2,4],score=[0,0,2,1,1,0,0,1,2,2],
            response=["a","a","a","a","a","b","b","c","d","e"],
            occasion=ones(Int,10))
        data=FacetData(table;person=:person,item=:item,rater=:rater,score=:score,
            response_id=:response,occasion=:occasion,category_levels=0:2)
        ids=["row-$i" for i in 1:data.n]
        units=B._rater_agreement_units(data,nothing,ids,10)
        @test length(units.by_pair)==6
        @test sum(length,values(units.by_pair))==5
        @test length(units.by_pair[(1,2)])==3
        @test units.unmatched_observation_ids==ids[8:10]
        @test :occasion in units.matching_roles && :response_id ∉ units.matching_roles
        fit=R.reporting_fit(:mfrm;data,ndraws=20,chains=2,warmup=0)
        result=B.rater_agreement(fit;dataset_id="known-responses",observation_ids=ids,se_unit=:person)
        @test result.overall.n_opportunities==5
        @test result.overall.exact.observed_count==3 && result.overall.exact.observed_rate==.6
        @test result.overall.adjacent.observed_count==3
        @test length(result.rater_pairs)==6 && length(result.raters)==4
        @test sum(r.n_opportunities for r in result.raters)==10
        @test result.raters[4].n_opportunities==0 && ismissing(result.raters[4].exact.observed_rate)
        @test result.rater_pairs[1].exact.observed_rate==1
        @test mean(r.exact.observed_rate for r in result.rater_pairs if r.n_opportunities>0) ≈ 1/3
        @test result.overall.exact.observed_rate != 1/3 # Opportunity-weighted, not pair-weighted.
        @test length(result.opportunities)==5
        @test result.matching.response_source===:fitted_metadata
        @test result.observed_interval===:not_computed && result.predictive_interval===:not_computed
        @test result.kappa===:not_computed && result.mechanism_classification===:not_performed
        @test result.conditional_independence_assumed
        same=B._rater_agreement_units(data,table.response,ids,10)
        @test same.response_binding==units.response_binding
        bad=copy(table.response);bad[1]="different"
        @test_throws ArgumentError B._rater_agreement_units(data,bad,ids,10)
        @test_throws ArgumentError B._rater_agreement_units(data,nothing,ids,5)
        bad=deepcopy(data);bad.optional[:occasion][2]=2
        @test_throws ArgumentError B._rater_agreement_units(bad,nothing,ids,10)
        bad=deepcopy(data);bad.person[2]=2
        @test_throws ArgumentError B._rater_agreement_units(bad,nothing,ids,10)
        bad=deepcopy(data);bad.rater[2]=1
        @test_throws ArgumentError B._rater_agreement_units(bad,nothing,ids,10)
        plain=FacetData(table;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:2)
        for bad in (nothing,table.response[1:9],fill(" ",10),fill(missing,10),fill(true,10),fill(1.,10),"a")
            @test_throws ArgumentError B._rater_agreement_units(plain,bad,ids,10)
        end
        plainfit=R.reporting_fit(:mfrm;data=plain,ndraws=20,chains=2,warmup=0)
        no_overlap=B.rater_agreement(plainfit;dataset_id="separate-performances",observation_ids=ids,response_ids=ids)
        @test no_overlap.status===:no_common_units
        @test no_overlap.unmatched_observation_ids==ids
        @test all(r -> r.n_opportunities==0 && ismissing(r.exact.expected_mean),no_overlap.rater_pairs)
        @test no_overlap.overall.exact.mcse===nothing
    end
end

# Independent category-pair enumeration, including aggregation before posterior quantiles.
function probability_oracle(fit, result)
    p=B.prediction_observations(fit;dataset_id=result.dataset_id,
        observation_ids=result.observation_ids,include_probabilities=true)
    index=Dict(id=>i for (i,id) in enumerate(result.observation_ids))
    S,_,K=size(p.probabilities)
    expected=[sum(p.probabilities[s,index[o.observation_a],a]*p.probabilities[s,index[o.observation_b],b]
        for o in result.opportunities for a in 1:K for b in 1:K if abs(a-b)<=t) /
        length(result.opportunities) for s in 1:S,t in (0,result.adjacent)]
    for (j,metric) in enumerate((result.overall.exact,result.overall.adjacent))
        @test metric.expected_mean ≈ mean(expected[:,j]) atol=2e-14
        @test metric.expected_lower ≈ quantile(expected[:,j],.025) atol=2e-14
        @test metric.expected_upper ≈ quantile(expected[:,j],.975) atol=2e-14
        @test 0 <= metric.observed_rate <= 1
    end
end

function checks(output)
    finite_checks()
    matching_checks()
    structural_checks()
    @testset "Common agreement across eight saved-fit types and persistence" begin
        cases=K.fixture_cases()
        @test length(unique(typeof(c.fit) for c in cases))==8
        for (i,c) in enumerate(cases)
            fit=c.fit; data=B.PredictionObservationAdapter._fit_data(fit)
            # These fixtures deliberately have one performance per person and no repeated item ratings.
            responses=["fixture-person-$p" for p in data.person]
            ids=["rating-$n" for n in 1:data.n]
            before=R.bytes(fit)
            result=B.rater_agreement(fit;dataset_id="synthetic-$i",observation_ids=ids,response_ids=responses)
            @test result.n_retained_draws==40
            @test result.chain_ids==repeat(1:2;inner=20)
            @test result.iterations==repeat(1:20;outer=2)
            @test result.overall.n_opportunities>0
            @test length(result.rater_pairs)==binomial(length(data.rater_levels),2)
            @test sum(r.n_opportunities for r in result.rater_pairs)==result.overall.n_opportunities
            @test sum(r.n_opportunities for r in result.raters)==2result.overall.n_opportunities
            @test result.sampling_warning && result.status===:warning
            @test result.scientific_acceptance===:not_established
            @test B._prediction_check_seal(result,"bayesianmgmfrm.rater_agreement.v1")===nothing
            probability_oracle(fit,result)
            @test R.bytes(fit)==before
            path=joinpath(output,"fit-$i.jls");save_fit_cache(path,fit)
            replay=saved_rater_agreement(path;dataset_id=result.dataset_id,observation_ids=ids,response_ids=responses)
            @test isequal(replay,result)
            serialize(joinpath(output,"case-$i.jls"),(;path,result))
        end
        fit=cases[1].fit;data=B.PredictionObservationAdapter._fit_data(fit)
        ids=["r-$i" for i in 1:data.n];responses=copy(data.person)
        base=(;dataset_id="boundaries",observation_ids=ids,response_ids=responses)
        for changed in ((;dataset_id=" "),(;observation_ids=fill("same",data.n)),
                (;max_prediction_cells=1),(;max_rater_pairs=false),(;max_prediction_cells=0),
                (;adjacent=true),(;adjacent=-1),(;adjacent=3),(;interval=1.),(;interval=NaN),(;se_unit=:pair))
            @test_throws ArgumentError B.rater_agreement(fit;merge(base,changed)...)
        end
        @test_throws ArgumentError B.rater_agreement(fit;dataset_id="missing-response",observation_ids=ids)
        bad=deepcopy(fit);reverse!(bad.chain_ids)
        @test_throws ArgumentError B.rater_agreement(bad;base...)
        bad=deepcopy(cases[6].fit);bad.record.run.draws[1,1]+=1
        d=B.PredictionObservationAdapter._fit_data(bad)
        @test_throws ArgumentError B.rater_agreement(bad;dataset_id="corrupt",observation_ids=["r-$n" for n in 1:d.n],response_ids=d.person)
        legacy=R.prediction_fixed_fixture(:legacy).fit
        @test_throws ArgumentError B.rater_agreement(legacy;base...)
        for tolerance in (0,2)
            result=B.rater_agreement(fit;base...,adjacent=tolerance)
            tolerance==0 ? (@test isequal(result.overall.exact,result.overall.adjacent)) :
                (@test result.overall.adjacent.status===:all_categories_within_tolerance)
        end
        short=R.reporting_fit(:mfrm;chains=1,ndraws=4,warmup=0)
        result=B.rater_agreement(short;base...)
        @test result.mcse_warning && result.overall.exact.status===:mcse_unavailable
        @test ismissing(result.overall.exact.mcse.mean_mcse)
        @test Base.Docs.doc(B.rater_agreement)!==nothing
        @test :rater_agreement ∉ names(B)
        @test B._root_api_contract()!==nothing
    end
end

function structural_checks()
    @testset "Whole-scale adjacency is known, not missing MCSE" begin
        table=facet_response_table(R.reporting_fit(:mfrm).design.spec.data)
        for categories in (2,3)
            rows=merge(table,(;score=mod.(table.score,categories)))
            data=FacetData(rows;person=:person,item=:item,rater=:rater,score=:score,category_levels=0:categories-1)
            fit=R.reporting_fit(:mfrm;data,ndraws=40,chains=2,warmup=0)
            ids=["id-$n" for n in 1:data.n];responses=copy(data.person)
            result=B.rater_agreement(fit;dataset_id="whole-scale",observation_ids=ids,response_ids=responses,
                adjacent=categories-1,interval=.99)
            @test result.overall.adjacent.observed_rate==1
            @test result.overall.adjacent.expected_mean==result.overall.adjacent.expected_lower==result.overall.adjacent.expected_upper==1
            @test result.overall.adjacent.mcse.mcse_status===:structurally_fixed
            @test result.overall.adjacent.mcse.mean_mcse==0
            @test !result.mcse_warning
            @test result.interval_probability==.99
            @test first(result.overall.exact.mcse.quantiles).probability ≈ .005
            @test last(result.overall.exact.mcse.quantiles).probability ≈ .995
            bytes=R.bytes(result);ids[1]="changed";responses[1]=999
            @test R.bytes(result)==bytes
            tampered=deepcopy(result);tampered.response_ids[1]=999
            @test_throws ArgumentError B._prediction_check_seal(tampered,"bayesianmgmfrm.rater_agreement.v1")
        end
    end
end
end
