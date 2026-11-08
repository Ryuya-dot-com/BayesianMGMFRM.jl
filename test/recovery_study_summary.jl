module RecoveryStudySummaryChecks
using BayesianMGMFRM, Test, Serialization
const B = BayesianMGMFRM
const P = B.Experimental.RecoveryPlanning
include("../examples/plan_mfrm_recovery.jl")
seal(value; kwargs...) = B._prediction_seal(merge(Base.structdiff(value,(;content_hash=nothing)),(;kwargs...)))
const UNKNOWN = (;status=:unresolved,evidence="Artificial fixture; independence not established")
const DECLARED = (;status=:declared_independent,evidence="Exercise declaration only; no independent simulations")

function fixture(plan,id,directory; warning=false,mean_mcse=.005)
    # Fixed records, including a non-native cache placeholder: no inference or RNG.
    table=(;person=getproperty.(plan.assignments,:person),rater=getproperty.(plan.assignments,:rater),
        item=getproperty.(plan.assignments,:item),score=[mod(i,4) for i in eachindex(plan.assignments)])
    observed=P.bind_observations(plan,id,table)
    bound=P.bind_data(plan,id,table)
    lower,upper=B._interval_probabilities(plan.interval)
    rows=[(;parameter=name,block=:rater,dimension=nothing,dimension_label=nothing,
        fixed=false,derived=false,parameter_space=:unit_logit,true_value=Dict(plan.truth)[name],
        bias=.1,absolute_bias=.1,squared_error=.01,interval_width=1.,covered=true,
        mcse=(;mcse_status=:available,mean_mcse,
            quantiles=((;probability=lower,mcse=.01),(;probability=upper,mcse=.01)))) for name in plan.parameters]
    recovery=B._prediction_seal((;schema="bayesianmgmfrm.recovery_evaluation.v1",dataset_id=id,
        rows,model_contract=(;family=:mfrm,prior=plan.analysis_prior,
            fitted_target=B._prediction_refit_target(bound.design.spec,bound.prior)),
        interval_probability=plan.interval,sampling_warning=warning,fixed_truth_mismatch=false,
        source_sample_hash="artificial-$id",evaluated_draws_hash="artificial-$id",status=:descriptive,
        n_retained_draws=plan.sampler.chains*plan.sampler.ndraws,
        chain_ids=repeat(1:plan.sampler.chains;inner=plan.sampler.ndraws),
        iterations=repeat(1:plan.sampler.ndraws;outer=plan.sampler.chains),
        observation_ids=["$id/row-$i" for i in eachindex(plan.assignments)]))
    cache=joinpath(directory,"$id-cache.txt");write(cache,"Artificial non-native cache for $id")
    precision=P.focal_precision(plan,recovery.rows)
    review=B._prediction_seal((;schema="example.mfrm_saved_fit_review.v1",plan_hash=plan.content_hash,
        observations_hash=observed.content_hash,cache=(;path=cache,sha256=P.filehash(cache)),
        recovery,precision,precision_applied=true,numerically_qualified=!warning&&all(p->p.passed,precision)))
    generation=joinpath(directory,"$id-observations.jls");serialize(generation,observed)
    saved=joinpath(directory,"$id-review.jls");serialize(saved,review)
    (;observed,review,paths=(generation,cache,saved))
end

function completed(plan,ledger,id,paths)
    for (stage,path) in zip(P.STAGES,paths)
        ledger=P.record_stage(plan,ledger,id;stage,status=:started)
        ledger=P.record_stage(plan,ledger,id;stage,status=:completed,artifact=path)
    end
    ledger
end

function checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="artificial; no RNG")
    template=MFRMRecoveryExample.example_plan(;provenance)
    ids=["good","warning","imprecise","fit_failed","generation_failed","pending","started","partial","changed","missing"]
    plan=P.prepare(template.assignments;levels=template.levels,category_levels=template.category_levels,
        truth=Dict(template.truth),prior=MFRMPrior(; (k=>getproperty(template.analysis_prior,k)
            for k in (:person_sd,:rater_sd,:item_sd,:step_sd))...),
        jobs=[(;dataset_id=id,response_seed=2i,fit_seed=2i+1) for (i,id) in enumerate(ids)],
        parameters=template.parameters,interval=template.interval,sampler=template.sampler,
        provenance,precision=Dict(template.precision))
    summarize(record;kwargs...)=P.summarize_recovery(plan,record;scenario_id="artificial",
        dataset_independence=UNKNOWN,max_interval_widths=Dict("rater[R2]"=>1.2),
        width_confidence_level=.95,kwargs...)
    @testset "Saved fixed-truth study: full roster and bindings" begin
        @test Base.Docs.doc(P.summarize_recovery)!==nothing
        @test P.contract().fixed_truth_study_summary
        initial=P.ledger(plan)
        empty=summarize(initial)
        @test empty.n_planned==10 && empty.replications.n_missing==10
        @test empty.counts==Dict(:no_attempt_recorded=>10)
        @test only(empty.replications.summaries).precision_qualified.all_planned_coverage_bounds==(0.,1.)
        fixtures=[fixture(plan,id,directory;warning=id=="warning",mean_mcse=id=="imprecise" ? .011 : .005)
            for id in ids[1:3]]
        record=initial
        for (id,fx) in zip(ids[1:3],fixtures)
            record=completed(plan,record,id,fx.paths)
        end
        for (id,stage) in (("fit_failed",:fit),("generation_failed",:generation))
            if stage===:fit
                record=P.record_stage(plan,record,id;stage=:generation,status=:started)
                record=P.record_stage(plan,record,id;stage=:generation,status=:completed,artifact=fixtures[1].paths[1])
            end
            record=P.record_stage(plan,record,id;stage,status=:started)
            record=P.record_stage(plan,record,id;stage,status=:failed,
                failure_kind=:validation,reason="Artificial recorded failure")
        end
        record=P.record_stage(plan,record,"started";stage=:generation,status=:started)
        for id in ("partial","changed","missing")
            path=joinpath(directory,"$id.txt");write(path,"Artificial intermediate artifact")
            record=P.record_stage(plan,record,id;stage=:generation,status=:started)
            record=P.record_stage(plan,record,id;stage=:generation,status=:completed,artifact=path)
        end
        write(joinpath(directory,"changed.txt"),"changed")
        rm(joinpath(directory,"missing.txt"))
        before=deepcopy(record)
        result=summarize(record)
        @test isequal(record,before)
        @test getproperty.(result.roster,:dataset_id)==ids
        @test getproperty.(result.roster,:status)==[:numerically_qualified,:numerically_excluded,
            :numerically_excluded,:failed,:failed,:no_attempt_recorded,:unresolved_started,
            :partial_completed,:artifact_review_required,:artifact_review_required]
        @test (result.replications.n_completed,result.replications.n_failed,result.replications.n_missing)==(3,2,5)
        manual=B.recovery_replications([f.review.recovery for f in fixtures];
            planned_dataset_ids=ids,parameters=collect(plan.parameters),scenario_id="artificial",
            dataset_independence=UNKNOWN,mcse_limits=Dict(plan.precision),
            failures=["fit_failed"=>"fit/validation: Artificial recorded failure",
                "generation_failed"=>"generation/validation: Artificial recorded failure"],
            max_interval_widths=Dict("rater[R2]"=>1.2),width_confidence_level=.95)
        @test isequal(result.replications,manual)
        q=only(result.replications.summaries).precision_qualified
        @test q.n_datasets==1 && q.n_unresolved==9
        @test q.width_target.all_planned_frequency_bounds==(.1,1.)
        @test q.width_target.conditional_confidence_interval.status===:independence_unresolved
        declared=summarize(record;dataset_independence=DECLARED)
        ci=only(declared.replications.summaries).precision_qualified.width_target.conditional_confidence_interval
        @test ci.lower≈.025 && ci.upper==1.
        @test only(B.design_precision_plot_data([declared.replications];parameter="rater[R2]").rows).n_planned==10
        @test !result.execution_provenance_verified && !result.generation_verified
        @test result.scientific_acceptance===:not_established
        @test P.filehash(fixtures[1].paths[2])==fixtures[1].review.cache.sha256
        path=joinpath(directory,"summary.jls");serialize(path,result)
        @test isequal(deserialize(path),result)
        serialize(joinpath(directory,"plan.jls"),plan);serialize(joinpath(directory,"ledger.jls"),record)

        # Resealed inconsistent records must fail semantic checks, not be omitted.
        good=fixtures[1].review
        function replace_review(bad;cache=nothing)
            file=joinpath(directory,"invalid-review.jls");serialize(file,bad)
            entries=deepcopy(record.entries);stages=entries[1].stages
            stage_update=merge(stages.recovery,(;artifact=(;path=file,sha256=P.filehash(file))))
            stages=merge(stages,(;recovery=stage_update))
            cache===nothing || (stages=merge(stages,(;fit=merge(stages.fit,(;artifact=cache)))))
            entries[1]=merge(entries[1],(;stages))
            seal(record;entries)
        end
        for bad in (seal(good;plan_hash="wrong"),seal(good;observations_hash="wrong"),
                seal(good;cache=merge(good.cache,(;sha256="wrong"))),
                seal(good;numerically_qualified=false),seal(good;precision_applied=false),
                seal(good;precision=()),merge(good,(;numerically_qualified=false)))
            @test_throws ArgumentError summarize(replace_review(bad))
        end
        recovery=good.recovery
        for bad in (seal(recovery;dataset_id="warning"),seal(recovery;interval_probability=.95),
                seal(recovery;rows=[merge(only(recovery.rows),(;true_value=2.))]),
                seal(recovery;rows=[merge(only(recovery.rows),(;fixed=true))]),
                seal(recovery;chain_ids=reverse(recovery.chain_ids)),seal(recovery;n_retained_draws=2),
                seal(recovery;observation_ids=["wrong"]),
                seal(recovery;model_contract=merge(recovery.model_contract,(;fitted_target=(;kind=:mfrm,identity="wrong")))))
            @test_throws ArgumentError summarize(replace_review(seal(good;recovery=bad)))
        end
        shared=(;path=fixtures[2].paths[2],sha256=fixtures[2].review.cache.sha256)
        @test_throws ArgumentError summarize(replace_review(seal(good;cache=shared);cache=shared))
        repeated=seal(recovery;source_sample_hash=fixtures[2].review.recovery.source_sample_hash)
        duplicates=summarize(replace_review(seal(good;recovery=repeated));dataset_independence=DECLARED)
        @test !duplicates.replications.replication_se_enabled
        @test only(duplicates.replications.summaries).precision_qualified.width_target.conditional_confidence_interval.status===:independence_unresolved
        @test_throws ArgumentError P.summarize_recovery(seal(plan;sbc_binding=(;fixture=true)),initial;
            scenario_id="invalid",dataset_independence=UNKNOWN)
        @test_throws ArgumentError summarize(record;dataset_independence=(;status=:unknown,evidence="bad"))
        @test_throws ArgumentError summarize(record;width_confidence_level=1.)
    end
end

function multi_quantity_checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="artificial; no RNG")
    template=MFRMRecoveryExample.example_plan(;provenance)
    names=["rater[R2]","rater[R3]"]
    plan=P.prepare(template.assignments;levels=template.levels,category_levels=template.category_levels,
        truth=Dict(template.truth),prior=MFRMPrior(; (k=>getproperty(template.analysis_prior,k)
            for k in (:person_sd,:rater_sd,:item_sd,:step_sd))...),
        jobs=[(;dataset_id="two-focal",response_seed=1,fit_seed=2)],parameters=names,
        interval=template.interval,sampler=template.sampler,provenance,
        precision=Dict(n=>(;mean_mcse_max=.01,endpoint_mcse_max=.02) for n in names))
    source=joinpath(directory,"source");mkdir(source)
    fx=fixture(plan,"two-focal",source)
    rows=copy(fx.review.recovery.rows)
    rows[2]=merge(rows[2],(;mcse=merge(rows[2].mcse,(;mean_mcse=.1))))
    recovery=seal(fx.review.recovery;rows)
    saved=seal(fx.review;recovery,precision=P.focal_precision(plan,rows),numerically_qualified=false)
    serialize(fx.paths[3],saved)
    record=completed(plan,P.ledger(plan),"two-focal",fx.paths)
    summarize(ledger)=P.summarize_recovery(plan,ledger;scenario_id="two-focal",dataset_independence=UNKNOWN)
    @testset "Per-quantity exclusions and moved saved-study artifacts" begin
        result=summarize(record)
        @test only(result.roster).status===:numerically_excluded
        @test [s.precision_qualified.n_datasets for s in result.replications.summaries]==[1,0]
        @test [only(s.precision_dispositions).status for s in result.replications.summaries]==[:passed,:mcse_exceeded]
        destination=joinpath(directory,"moved");cp(source,destination)
        moved=P.relocate_ledger(plan,record;source_root=source,destination_root=destination)
        rm(source;recursive=true)
        @test isequal(summarize(moved).replications,result.replications)
        @test only(summarize(record).roster).status===:artifact_review_required
        missing_cache=joinpath(destination,basename(fx.paths[2]));bytes=read(missing_cache)
        write(missing_cache,"changed completed cache")
        unresolved=summarize(moved)
        @test only(unresolved.roster).status===:artifact_review_required
        @test unresolved.replications.n_completed==0 && unresolved.replications.n_missing==1
        write(missing_cache,bytes)
        @test isequal(summarize(moved).replications,result.replications)
    end
end
end
