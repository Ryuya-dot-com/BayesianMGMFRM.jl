module ComparisonAPIContractChecks
using BayesianMGMFRM, Test, Random
const B=BayesianMGMFRM;const SA=B.Experimental.StarAssociation;const E=B.Experimental
include("common_prediction_fixtures.jl")
include("../examples/star_association.jl")
const INPUT=StarAssociationExample.inputs()

# Deterministic coordinates, not posterior draws or sampling-performance evidence.
function star_fixture(;rows=INPUT.rows,criteria=INPUT.criterion_specs,prior=INPUT.prior,
        root="overall",include_phi=true)
    m=E.joint_rating_spec(rows;criteria,prior,association=:star,root_criterion=root,include_phi)
    cfg=SA._build_sampler_config(ndraws=12,warmup=5,chains=2)
    SA._build_star_result(m,cfg,[.1sin(i+j) for i in 1:24,j in 1:m.dim],NamedTuple[],NamedTuple[];
        provenance=(;operation=:deterministic_test_fixture))
end

@testset "Star comparison binds actual outcomes and retains named inputs" begin
    a=star_fixture();b=star_fixture(;include_phi=false)
    ac=criteria(a);bc=criteria(b)
    actual=compare_models("association"=>a,"independent"=>b)
    direct=compare_models(a,b;names=("association","independent"))
    @test isequal(actual,direct)
    @test isequal(actual,compare_models([:association=>a,:independent=>b]))
    @test isequal(actual,compare_models(ac,bc;names=(:association,:independent)))
    @test actual.primary_name=="association" && actual.baseline_name=="independent"
    @test actual.direction===:primary_minus_baseline
    @test actual.model_selection===:not_performed
    @test actual.primary_source_sample_content_hash==a.content_hash
    @test actual.baseline_source_sample_content_hash==b.content_hash
    @test actual.primary_warnings==a.warnings
    @test actual.primary_sampling_warning==a.sampling_warning
    @test actual.any_sampling_warning
    @test actual.comparison_data.evaluation_unit===:rating_event
    @test actual.comparison_data.loo_target===:single_event_omission_fixed_specification
    @test actual.uncertainty.mcmc_mcse===:not_computed
    @test ac.result.uncertainty==actual.uncertainty
    @test actual.waic_diff.elpd_diff≈sum(ac.result.pointwise.elpd_waic.-bc.result.pointwise.elpd_waic)
    @test actual.psis_loo_diff.elpd_diff≈sum(ac.result.pointwise.elpd_psis_loo.-bc.result.pointwise.elpd_psis_loo)
    @test compare_models(b,a).waic_diff.elpd_diff≈-actual.waic_diff.elpd_diff
    @test isequal(actual.waic_diff.se,SA._crossed_sum_se(
        ac.result.pointwise.elpd_waic.-bc.result.pointwise.elpd_waic,a.model.entity,a.model.I,a.model.rater,a.model.R))
    for names in (("same","same"),(" ","b"),("a",))
        @test_throws ArgumentError compare_models(ac,bc;names)
        @test_throws ArgumentError compare_models(a,b;names)
    end
    @test_throws ArgumentError compare_models([:same=>a,:same=>b])
    @test_throws ArgumentError compare_models([:single=>a])
    @test_throws ArgumentError compare_models(:a=>a,:b=>b;names=("override","labels"))
    @test_throws MethodError compare_models(a,b;unknown_control=true)
    @test_throws ArgumentError compare_models((;schema="unknown"),bc)
    old=merge(ac,(;result=Base.structdiff(ac.result,(;comparison_data=nothing))))
    @test_throws ArgumentError compare_models(old,old)
    bad=merge(bc,(;result=merge(bc.result,(;pointwise=merge(bc.result.pointwise,
        (;elpd_waic=fill(NaN,bc.result.n_events)))))))
    @test_throws ArgumentError compare_models(ac,bad)
    bad=merge(bc,(;result=merge(bc.result,(;psis_loo=merge(bc.result.psis_loo,(;estimator=:hill))))))
    @test_throws ArgumentError compare_models(ac,bad)
    for change in ((;conditioning=:new_entity),(;weighting=:equal_rater),
            (;evaluation_unit=:single_rating),(;loo_target=:new_rater),
            (;event_ids=reverse(bc.result.comparison_data.event_ids)))
        bad=merge(bc,(;result=merge(bc.result,(;comparison_data=merge(bc.result.comparison_data,change)))))
        @test_throws ArgumentError compare_models(ac,bad)
    end
    changed=copy(INPUT.rows)
    changed[1]=merge(changed[1],(;score=1+mod(changed[1].score,5)))
    variants=[star_fixture(;rows=changed),
        star_fixture(;rows=[merge(r,(;rating_event_id=r.rating_event_id*"-other")) for r in INPUT.rows]),
        star_fixture(;rows=[merge(r,(;entity=r.entity*"-other")) for r in INPUT.rows]),
        star_fixture(;rows=[merge(r,(;rater=r.rater*"-other")) for r in INPUT.rows]),
        star_fixture(;criteria=[i==1 ? merge(c,(;levels=collect(0:5))) : c for (i,c) in enumerate(INPUT.criterion_specs)]),
        star_fixture(;criteria=[i==1 ? merge(c,(;direction=:higher_is_less)) : c for (i,c) in enumerate(INPUT.criterion_specs)]),
        star_fixture(;rows=[r.criterion=="accuracy" ? merge(r,(;criterion="different")) : r for r in INPUT.rows],
            criteria=[c.criterion=="accuracy" ? merge(c,(;criterion="different")) : c for c in INPUT.criterion_specs])]
    for other in variants
        @test length(other.model.event_ids)==length(a.model.event_ids)
        @test other.model.entity==a.model.entity && other.model.rater==a.model.rater
        @test_throws ArgumentError compare_models(a,other)
        @test_throws ArgumentError compare_models(ac,criteria(other))
    end
    # A different prior or graph is a model comparison, not a data mismatch.
    alt=SA.PriorConfig(;merge(SA._prior_namedtuple(INPUT.prior),(;phi_sd=.8))...)
    for other in (star_fixture(;prior=alt),star_fixture(;root="accuracy"))
        @test isfinite(compare_models(a,other).waic_diff.elpd_diff)
    end
    # A current portable report carries the binding; old reports can still be read.
    mktempdir() do dir
        receipt=save_report(joinpath(dir,"criteria.json"),ac;return_receipt=true)
        @test load_report(receipt.path;expected_sha256=receipt.sha256).result.comparison_data.observation_binding==
            ac.result.comparison_data.observation_binding
        receipt=save_report(joinpath(dir,"old.json"),old;return_receipt=true)
        @test !hasproperty(load_report(receipt.path;expected_sha256=receipt.sha256).result,:comparison_data)
    end
end

@testset "Star pairs align pointwise ELPD and rater diagnostics by event ID" begin
    a=star_fixture();ac=criteria(a)
    b=star_fixture(;rows=reverse(INPUT.rows));bc=criteria(b)
    @test ac.result.comparison_data.observation_binding==bc.result.comparison_data.observation_binding
    order=[only(findall(==(id),bc.result.comparison_data.event_ids)) for id in ac.result.comparison_data.event_ids]
    result=compare_models(ac,bc)
    @test result.waic_diff.elpd_diff≈sum(ac.result.pointwise.elpd_waic.-bc.result.pointwise.elpd_waic[order])
    @test result.psis_loo_diff.elpd_diff≈sum(ac.result.pointwise.elpd_psis_loo.-bc.result.pointwise.elpd_psis_loo[order])
    for (st,row) in enumerate(result.stratum_diffs)
        idx=findall(==(st),ac.result.event_stratum)
        @test row.baseline_bad_k==count(>(bc.result.psis_loo.pareto_k_threshold),bc.result.pointwise.pareto_k[order[idx]])
    end
    # Permuting a report with its pointwise values must leave a paired difference zero.
    p=ac.result;perm=reverse(eachindex(p.entity));d=p.comparison_data
    d=merge(d,(;event_ids=d.event_ids[perm],layout_binding=B._cache_hash((;
        event_ids=d.event_ids[perm],entity=p.entity[perm],rater=p.rater[perm],I=p.I,R=p.R))))
    pointwise=map(v->v[perm],p.pointwise)
    shuffled=merge(ac,(;result=merge(p,(;comparison_data=d,entity=p.entity[perm],
        rater=p.rater[perm],event_stratum=p.event_stratum[perm],pointwise))))
    @test compare_models(ac,shuffled).waic_diff.elpd_diff==0
    @test compare_models(ac,shuffled).psis_loo_diff.elpd_diff==0
    @test compare_models(ac,shuffled).waic_diff.se.se_observation==0
    # Repeated entity/rater cells keep the explicit uncertainty limitation.
    extra=[merge(r,(;observation_id="repeat-"*r.observation_id,rating_event_id="repeat-"*r.rating_event_id)) for r in INPUT.rows[1:3]]
    repeated=star_fixture(;rows=[INPUT.rows;extra])
    uncertainty=compare_models(repeated,repeated).uncertainty
    @test uncertainty.repeated_entity_rater_pairs
    @test criteria(repeated).result.uncertainty==uncertainty
    @test uncertainty.intersection_cluster_adjustment===:not_computed
end

@testset "Common comparison uses one public verb and preserves existing routes" begin
    record=F.synthetic_record(F.target())
    fits=Any[reporting_fit(:mfrm;ndraws=20,chains=2),reporting_fit(:gmfrm;ndraws=20,chains=2),
        reporting_fit(:mgmfrm;ndraws=20,chains=2),normalized_fixture(record),
        E.CorrelatedMGMFRMFit(record;expected_identity=record.target_identity)]
    append!(fits,[prediction_fixed_fixture(k).fit for k in (:fixed,:correlated,:exchangeable,:exchangeable_correlated)])
    for f in fits
        n=B.PredictionObservationAdapter._fit_data(f).n
        kw=(;comparison_axis=:model,dataset_id="api-fixture",observation_ids=["o$i" for i in 1:n])
        for criterion in (:waic,:raw_loo,:hill_smoothed_loo)
            a=compare_models("base"=>f,"alternative"=>f;kw...,criterion,baseline="base",se_unit=:person)
            b=B.compare_predictions("base"=>f,"alternative"=>f;kw...,criterion,baseline="base",se_unit=:person)
            @test isequal(a,b)
            @test a.rows[2].elpd_difference==0
            @test a.model_selection===:not_performed
            @test a.reference_psis_validation===:not_established
        end
        @test_throws ArgumentError compare_models(:a=>f,:b=>f;kw...,draw_indices=[1,2])
        @test compare_models(:a=>f,:b=>f;kw...,criterion=:psis_loo).rows[2].elpd_difference == 0
    end
    f=first(fits);n=f.design.spec.data.n
    kw=(;comparison_axis=:model,dataset_id="api-fixture",observation_ids=["o$i" for i in 1:n])
    @test_throws ArgumentError compare_models(:a=>f,:b=>f;kw...,ndraws=5)
    @test_throws MethodError compare_models(:a=>f,:b=>f;kw...,unsupported_control=true)
    @test_throws ArgumentError compare_models(:a=>f,:b=>f;kw...,rng=Xoshiro(81))
    @test_throws ArgumentError compare_models(:a=>f,:b=>f;dataset_id="id",observation_ids=kw.observation_ids)
    @test_throws ArgumentError compare_models(:a=>f,:b=>f;comparison_axis=:model)
    # No explicit axis preserves legacy ranking/weights and accepted criterion names.
    for criterion in (:waic,:loo,:psis_loo)
        a=compare_models(:a=>f,:b=>f;criterion)
        b=compare_models(f,f;names=[:a,:b],criterion)
        @test isequal(a,b)
        @test length(a)==2
    end
    p=B.prediction_observations(f;dataset_id=kw.dataset_id,observation_ids=kw.observation_ids)
    @test isequal(compare_models(:a=>p,:b=>p;comparison_axis=:model),
        B.compare_predictions(:a=>p,:b=>p;comparison_axis=:model))
end
end
