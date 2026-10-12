module CategoryReportChecks
using BayesianMGMFRM,Test,Statistics,Serialization,Random
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks
const K=CommonPredictionKfoldChecks
include("../examples/saved_category_report.jl")
ids(fit)=["rating-$i" for i in 1:B.PredictionObservationAdapter._fit_data(fit).n]
report(fit;kwargs...)=B.category_report(fit;dataset_id="category-fixture",observation_ids=ids(fit),kwargs...)

function profile(spec;dimension=1,id="slice",grid=[-1.,0.,1.])
    (;id,item=first(spec.data.item_levels),rater=first(spec.data.rater_levels),dimension,
        ability_grid=grid,fixed_abilities=Dict(d=>.2d for d in 1:spec.dimensions if d!=dimension))
end

function finite_checks()
@testset "Category profile mathematics and uncertainty definitions" begin
    steps=[(;values=[-1.,-.7],fixed=false),(;values=[1.,.7],fixed=false)]
    terms=(;offset=[.4,-.2],axis=ones(2),scale=[1.,2.],steps)
    probs=B._category_profile_probabilities(terms,0.)
    oracle=exp.([0.,.6,-.8]);oracle./=sum(oracle)
    @test probs[1,:] ≈ oracle
    @test vec(sum(probs;dims=2)) ≈ ones(2)
    @test log(probs[1,2]/probs[1,1]) ≈ .6
    @test log(probs[1,3]/probs[1,2]) ≈ -1.4
    # Scalar two-slope products change steepness, not the held-fixed crossing.
    for scale in (.2,1.,3.), step in 1:2
        one=(;offset=[.4],axis=[1.],scale=[scale],steps=[(;values=[-1.]),(;values=[1.])])
        boundary=.4+one.steps[step].values[1]
        p=B._category_profile_probabilities(one,boundary)
        @test p[1,step] ≈ p[1,step+1]
        @test p[1,step]<.5
    end
    # MGMFRM uses loading in the ability term and the literal 1.7 rater scale.
    for a in (.4,2.3),gamma in (.3,1.8)
        one=(;offset=[.4],axis=[a],scale=[1.7gamma],steps=[(;values=[-1.]),(;values=[1.])])
        for step in 1:2
            p=B._category_profile_probabilities(one,(.4+one.steps[step].values[1])/a)
            @test p[1,step] ≈ p[1,step+1]
        end
    end
    # Joint-draw ratios, not ratios of marginal posterior means.
    values=[1.,3.]./[1.,2.]
    @test mean(values)==1.25 && mean([1.,3.])/mean([1.,2.])≈4/3
    summary=B._category_report_summary(values,1,.99)
    @test summary.mean==1.25 && summary.sd≈std(values)
    @test summary.lower≈quantile(values,.005) && summary.upper≈quantile(values,.995)
    @test summary.mcse.mcse_status===:insufficient_chains
    @test B._category_report_summary(zeros(40),2,.95).mcse.mcse_status===:degenerate_draws
    @test B._category_report_summary(zeros(40),2,.95;fixed=true).mcse.mean_mcse==0
    unavailable=B._category_report_summary([1.,Inf],1,.95)
    @test unavailable.n_finite_draws==1 && ismissing(unavailable.mean) && unavailable.status===:nonfinite_draws
end
end

function fit_checks(fit,i,output; check_contract=true)
@testset "Category report saved-fit variant $i" begin
    native=B._recovery_context(fit);spec=native.spec;data=spec.data
    profiles=[profile(spec)]
    before=R.bytes(fit)
    result=report(fit;profiles,interval=.99)
    owner=spec.family===:gmfrm ? :rater : :item
    if check_contract
    @test R.bytes(fit)==before
    @test result.category_levels==data.category_levels && result.n_retained_draws==40
    @test length(result.usage_rows)==(1+length(data.item_levels)+length(data.rater_levels))*length(data.category_levels)
    owner=spec.family===:gmfrm ? :rater : :item
    @test result.step_contract.owner===owner
    nowners=owner===:rater ? length(data.rater_levels) : length(data.item_levels)
    @test length(result.threshold_rows)==nowners*(length(data.category_levels)-1)
    @test all(row->row.owner===owner && row.step>=1,result.threshold_rows)
    @test result.model_contract.category_contract.implementation_scale_constant == (spec.family===:mgmfrm ? 1.7 : 1.)
    @test result.source_sample_hash==native.source_sample_hash
    @test result.chain_ids==native.chain_ids && result.iterations==native.iterations
    @test result.sampling_warning==B._prediction_sampling_warning(native.quality)
    @test result.usage_target===:conditional_expected_category_proportion_existing_rows
    @test result.predictive_interval===:not_computed && result.multiplicity_adjustment===:none
    @test !result.refit_performed && !result.automatic_category_collapse
    @test result.scientific_acceptance===:not_established
    @test B._prediction_check_seal(result,"bayesianmgmfrm.category_report.v1")===nothing
    end
    p=B.prediction_observations(fit;dataset_id="category-fixture",observation_ids=ids(fit))
    for row in result.usage_rows
        idx=row.facet===:overall ? collect(1:data.n) :
            findall(==(row.level_index),getproperty(data,row.facet))
        k=findfirst(==(row.category),data.category_levels)
        v=vec(sum(p.probabilities[:,idx,k];dims=2))./length(idx)
        @test row.observed_count==count(==(row.category),data.score[idx])
        @test row.n_observations==length(idx)
        @test row.expected.mean≈mean(v)
        @test row.expected.sd≈std(v)
        @test row.expected.lower≈quantile(v,.005) && row.expected.upper≈quantile(v,.995)
        expectedowners=Tuple(sort(unique((owner===:rater ? data.rater_levels[data.rater[idx]] : data.item_levels[data.item[idx]]))))
        @test Set(row.threshold_levels)==Set(expectedowners)
    end
    @test sum(r.expected.mean for r in result.usage_rows if r.facet===:overall)≈1
    lookup=Dict(row.parameter=>row for row in native.coordinates)
    for row in result.threshold_rows
        original=lookup[row.parameter]
        @test row.summary.mean≈mean(original.values) && row.summary.sd≈std(original.values)
        @test row.summary.lower≈quantile(original.values,.005) && row.summary.upper≈quantile(original.values,.995)
        @test row.fixed==original.fixed
        if row.step==1
            @test row.order_probability===nothing && row.gap===nothing
        else
            previous=only(filter(r->r.owner_index==row.owner_index && r.step==row.step-1,result.threshold_rows))
            gap=original.values-lookup[previous.parameter].values
            @test row.order_probability.mean==mean(gap.>0)
            @test row.gap.mean≈mean(gap)
        end
    end
    # Conditional curve kernel against native prediction at an actual person's
    # coordinates, separately for each model, including fixed-MFRM unit scales.
    _,steps=B._category_report_steps(native)
    for s in (1,40), n in (1,data.n)
        person=data.person_levels[data.person[n]]
        abilities=[lookup[spec.dimensions==1 ? "person[$person]" :
            "person[$person,$(spec.dimension_labels[d])]"].values[s] for d in 1:spec.dimensions]
        pr=(;id="native",item=data.item_levels[data.item[n]],rater=data.rater_levels[data.rater[n]],
            dimension=1,ability_grid=[-1.,1.],fixed_abilities=Dict(d=>abilities[d] for d in 2:spec.dimensions))
        pr=only(B._category_profiles([pr],spec,1,1000))
        one=merge(native,(;total_draws=1,coordinates=[merge(r,(;values=r.values[s:s])) for r in native.coordinates]))
        _,onesteps=B._category_report_steps(one)
        terms=B._category_profile_terms(one,onesteps,pr)
        predicted=B._category_profile_probabilities(terms,abilities[1])
        @test vec(predicted)≈p.probabilities[s,n,:] atol=1e-12
    end
    for ability in profiles[1].ability_grid
        @test sum(r.probability.mean for r in result.curve_rows if r.ability==ability)≈1
    end
    for row in result.crossing_rows
        if row.crossing!==nothing
            @test row.crossing.lower<=row.crossing.median<=row.crossing.upper
        else
            @test row.status===:no_unique_crossing_inactive_dimension
        end
    end
    path=joinpath(output,"fit-$i.jls");save_fit_cache(path,fit)
    serialize(joinpath(output,"case-$i.jls"),(;path,profiles,observation_ids=ids(fit),expected=result))
    @test isequal(saved_category_report(path;dataset_id="category-fixture",observation_ids=ids(fit),profiles,interval=.99),result)
    return result
end
end

function boundary_checks(cases)
@testset "Category ownership and rejected ambiguity" begin
    fit=cases[1].fit
    shared=R.reporting_fit(:mfrm;thresholds=:rating_scale,ndraws=20,chains=2,warmup=0)
    shared_result=report(shared)
    @test shared_result.step_contract.owner===:global
    @test all(r->r.owner_level===nothing,shared_result.threshold_rows)
    @test all(r->r.threshold_levels==(nothing,),shared_result.usage_rows)
    @test isempty(shared_result.profiles) && isempty(shared_result.curve_rows)
    # Existing predictive-replication summary stays deterministic under its RNG.
    old=category_functioning_summary(shared;rng=MersenneTwister(771))
    report(shared)
    @test isequal(category_functioning_summary(shared;rng=MersenneTwister(771)),old)
    data=FacetData((;person=[1,1,2,2,3,3],rater=[1,2,1,2,1,2],item=[1,2,2,1,1,2],score=[0,1,1,0,1,0]);
        person=:person,rater=:rater,item=:item,score=:score,category_levels=0:2)
    unused=report(R.reporting_fit(:mfrm;data,ndraws=20,chains=2,warmup=0))
    @test all(r->r.observed_count==0 && r.observed_flag===:skipped,filter(r->r.category==2,unused.usage_rows))
    @test all(r->r.expected.mean>0,filter(r->r.category==2,unused.usage_rows))
    spec=B._recovery_context(cases[3].fit).spec
    inactive=report(cases[3].fit;profiles=[profile(spec;dimension=2)])
    @test all(r->r.status===:no_unique_crossing_inactive_dimension && r.crossing===nothing,inactive.crossing_rows)
    for category in inactive.category_levels
        @test allequal([r.probability.mean for r in inactive.curve_rows if r.category==category])
    end
    @test_throws ArgumentError report(fit;interval=1)
    @test_throws ArgumentError report(fit;min_count=0)
    @test_throws ArgumentError report(fit;max_prediction_cells=1)
    @test_throws ArgumentError report(fit;max_curve_cells=true)
    @test_throws ArgumentError B.category_report(fit;dataset_id=" ",observation_ids=ids(fit))
    @test_throws ArgumentError B.category_report(fit;dataset_id="a",observation_ids=fill("same",length(ids(fit))))
    pr=profile(spec)
    for bad in (merge(pr,(;item="missing")),merge(pr,(;rater="missing")),merge(pr,(;dimension=true)),
        merge(pr,(;ability_grid=[0.,0.])),merge(pr,(;ability_grid=[0.,Inf])),merge(pr,(;fixed_abilities=Dict())),
        merge(pr,(;id=" ")),merge(pr,(;extra=true)),merge(pr,(;fixed_abilities=Dict(1=>0.,2=>0.))))
        @test_throws ArgumentError report(cases[3].fit;profiles=[bad])
    end
    @test_throws ArgumentError report(cases[3].fit;profiles=[pr,pr])
    @test_throws ArgumentError report(cases[3].fit;profiles=[merge(pr,(;ability_grid=1:10^12))])
    @test_throws ArgumentError report(cases[3].fit;profiles=[pr],max_curve_cells=1)
    broken=deepcopy(fit);reverse!(broken.chain_ids)
    @test_throws ArgumentError report(broken)
    broken=deepcopy(cases[6].fit);broken.record.run.draws[1,1]+=.1
    @test_throws ArgumentError report(broken)
    @test_throws ArgumentError report(R.prediction_fixed_fixture(:legacy).fit)
    tampered=deepcopy(shared_result);tampered.usage_rows[1]=merge(tampered.usage_rows[1],(;observed_count=999))
    @test_throws ArgumentError B._prediction_check_seal(tampered,"bayesianmgmfrm.category_report.v1")
end
end

include("category_report_edges.jl")

function checks(output)
    finite_checks()
    cases=K.fixture_cases()
    @test length(unique(typeof(c.fit) for c in cases))==8
    results=[fit_checks(c.fit,i,output) for (i,c) in enumerate(cases)]
    boundary_checks(cases)
    additional_checks(output)
    return results
end
end
