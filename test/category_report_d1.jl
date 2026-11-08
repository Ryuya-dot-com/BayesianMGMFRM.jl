module CategoryReportD1Checks
using BayesianMGMFRM, Test, Statistics
const B=BayesianMGMFRM
const E=B.Experimental
include("common_prediction_fixtures.jl")

# Deterministic contract records, never posterior or calibration evidence.
function fixture(mode; K=4)
    old=F.synthetic_record(F.target(;K))
    spec=mfrm_spec(old.spec.data;family=:mgmfrm,dimensions=1,
        q_matrix=trues(4,1),dimension_labels=["Ability"])
    restricted=mode in (:fixed,:free,:profile)
    model=restricted ? E.slope_restriction(spec;
        item_slopes=mode===:free ? :estimated_positive : :fixed_one,
        rater_consistency=:fixed_one) : spec
    base=E.NormalizedMGMFRMPrior(;prior_model=mode===:source ? :source : :exchangeable,
        old.prior.scales...,source_rater=mode===:source ? last(spec.data.rater_levels) : nothing)
    prior=mode===:profile ? E.MeanProfilePrior(model,base;
        item_means=Dict(i=>.1i for i in 1:4),
        step_means=Dict(i=>.1i.*((1:K-1).-K/2) for i in 1:4),
        category_levels=0:K-1,units=:raw) : base
    return normalized_fixture(old;target=B._normalized_mgmfrm_target(model,prior))
end

function check_fit(fit;high_categories=false)
    context=B._recovery_context(fit);spec=context.spec;data=spec.data
    coords=Dict(row.parameter=>row.values for row in context.coordinates)
    item=first(data.item_levels);rater=last(data.rater_levels)
    profile=(;id="D1",item,rater,dimension=1,ability_grid=[-1.,.25,1.5])
    ids=["row-$i" for i in 1:data.n]
    r=B.category_report(fit;dataset_id="fixed-value-test-only",observation_ids=ids,
        profiles=[profile],interval=.95)
    prediction=B.prediction_observations(fit;dataset_id="fixed-value-test-only",observation_ids=ids)
    offset=coords["item[$item]"]+coords["rater[$rater]"]
    slope=coords["item_dimension_discrimination[item=$item,$(spec.dimension_labels[1])]"]
    scale=1.7coords["rater_consistency[rater=$rater]"]
    steps=[coords["item_step[item=$item,m=$k]"] for k in 2:length(data.category_levels)]
    for ability in profile.ability_grid
        oracle=zeros(context.total_draws,length(data.category_levels))
        for s in 1:context.total_draws
            logits=[0.;cumsum([scale[s]*(slope[s]*ability-offset[s]-step[s]) for step in steps])]
            weights=exp.(logits.-maximum(logits));oracle[s,:]=weights/sum(weights)
        end
        for row in filter(x->x.ability==ability,r.curve_rows)
            k=findfirst(==(row.category),data.category_levels);values=oracle[:,k]
            @test row.probability.mean≈mean(values) atol=2e-13
            @test row.probability.lower≈quantile(values,.025) atol=2e-13
            @test row.probability.upper≈quantile(values,.975) atol=2e-13
        end
    end
    for row in r.crossing_rows
        values=(offset+steps[row.step])./slope
        @test row.crossing.mean≈mean(values) atol=2e-13
        @test row.crossing.lower≈quantile(values,.025) atol=2e-13
        @test row.crossing.upper≈quantile(values,.975) atol=2e-13
    end
    # Evaluate the profile kernel at original person coordinates: independent
    # likelihood prediction must agree, including reconstructed final-rater values.
    for s in (1,context.total_draws), n in (1,data.n)
        person=data.person_levels[data.person[n]]
        ability=coords["person[$person]"][s]
        pr=merge(profile,(;item=data.item_levels[data.item[n]],rater=data.rater_levels[data.rater[n]]))
        pr=only(B._category_profiles([pr],spec,1,10000))
        one=merge(context,(;total_draws=1,coordinates=[merge(x,(;values=x.values[s:s])) for x in context.coordinates]))
        _,steps1=B._category_report_steps(one)
        probabilities=B._category_profile_probabilities(B._category_profile_terms(one,steps1,pr),ability)
        @test vec(probabilities)≈prediction.probabilities[s,n,:] atol=2e-13
    end
    @test r.chain_ids==context.chain_ids && r.iterations==context.iterations
    @test r.source_sample_hash==context.source_sample_hash
    @test r.sampling_warning==B._prediction_sampling_warning(context.quality)
    @test r.scientific_acceptance===:not_established
    @test r.category_levels==data.category_levels
    if high_categories
        unused=filter(x->x.observed_count==0,r.usage_rows)
        @test !isempty(unused)
        @test all(x->x.expected.mean>0,unused)
        @test length(r.threshold_rows)==4*24
    end
end

function checks()
    @testset "D1 MGMFRM profile equations across coefficient and prior policies" begin
        for mode in (:fixed,:free,:profile,:unrestricted,:source)
            check_fit(fixture(mode))
        end
        check_fit(fixture(:profile;K=25);high_categories=true)
        check_fit(reporting_fit(:mgmfrm;dimensions=1,q_matrix=trues(2,1),chains=2,ndraws=20,warmup=0))
    end
end
end
