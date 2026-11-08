module RecoveryExecutionExampleChecks
using BayesianMGMFRM, Test, Serialization
const B = BayesianMGMFRM
const P = B.Experimental.RecoveryPlanning
include("../examples/plan_mfrm_recovery.jl")
include("../examples/run_mfrm_recovery.jl")
const R = MFRMRecoveryRun

function checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="artificial; no RNG")
    template=MFRMRecoveryExample.example_plan(;provenance)
    plan=P.prepare(template.assignments;levels=template.levels,category_levels=template.category_levels,
        truth=Dict(template.truth),prior=MFRMPrior(person_sd=1.5,rater_sd=1.,item_sd=1.,step_sd=1.),
        jobs=[(;dataset_id=id,response_seed=2i,fit_seed=2i+1) for (i,id) in enumerate(("failed","untouched"))],
        parameters=template.parameters,interval=template.interval,sampler=template.sampler,
        provenance,precision=Dict(template.precision))
    id=first(plan.jobs).dataset_id
    table=(;person=getproperty.(plan.assignments,:person),rater=getproperty.(plan.assignments,:rater),
        item=getproperty.(plan.assignments,:item),score=zeros(Int,length(plan.assignments)))
    observed=P.bind_observations(plan,id,table)
    artifact=joinpath(directory,"fixed-single-category.jls");serialize(artifact,observed)
    original_hash=P.filehash(artifact)
    initial=P.ledger(plan)
    started=P.record_stage(plan,initial,id;stage=:generation,status=:started)
    generated=P.record_stage(plan,started,id;stage=:generation,status=:completed,artifact)
    function run(record=generated; through=:fit, output="attempt", dataset=id)
        R.run_job(plan,record,dataset;through,output_dir=joinpath(directory,output))
    end
    @testset "Explicit recovery execution: no generation or MCMC" begin
        @test Base.Docs.doc(R.run_job)!==nothing
        @test R.fit_keywords(plan,first(plan.jobs)).seed==first(plan.jobs).fit_seed
        @test !haskey(R.fit_keywords(plan,first(plan.jobs)),:algorithm)
        @test !haskey(R.fit_keywords(plan,first(plan.jobs)),:gradient_backend)
        @test all(iszero,R.fit_keywords(plan,first(plan.jobs)).init)
        @test_throws ArgumentError run(;through=:invalid)
        @test_throws ArgumentError run(;dataset="unknown")
        @test_throws ArgumentError run(started)
        @test !ispath(joinpath(directory,"attempt"))
        done=run(;through=:generation)
        @test done.status===:already_completed && done.outcome_path===nothing
        @test isequal(done.ledger,generated) && isempty(done.costs)
        @test !ispath(joinpath(directory,"attempt"))
        mkdir(joinpath(directory,"occupied"))
        marker=joinpath(directory,"occupied","retain.txt");write(marker,"retain")
        @test_throws Base.IOError run(;output="occupied")
        @test read(marker,String)=="retain"
        @test_throws ArgumentError run(;output="absent/attempt")
        # Establish that this actual-data validation stops before the fitter.
        @test_throws ArgumentError P.bind_data(plan,id,table)
        @test_throws ArgumentError run()
        failed=deserialize(joinpath(directory,"attempt","outcome.jls"))
        @test failed.status===:failed && failed.stage===:fit && failed.failure_kind===:validation
        @test occursin(":single_observed_category",failed.reason)
        @test isempty(failed.completed_costs) && failed.seconds_since_stage_start>=0
        @test failed.ledger.entries[1].stages.fit.status===:failed
        @test failed.ledger.entries[1].stages.generation==generated.entries[1].stages.generation
        @test failed.ledger.entries[2]==initial.entries[2]
        @test isequal(deserialize(joinpath(directory,"attempt","ledger-00.jls")),generated)
        @test deserialize(joinpath(directory,"attempt","ledger-01.jls")).entries[1].stages.fit.status===:started
        @test isequal(deserialize(joinpath(directory,"attempt","ledger-02.jls")),failed.ledger)
        @test !ispath(joinpath(directory,"attempt","fit.jls"))
        @test !ispath(joinpath(directory,"attempt","generated-table.jls"))
        @test P.filehash(artifact)==original_hash
        @test_throws ArgumentError run(failed.ledger;output="retry")
        @test !ispath(joinpath(directory,"retry"))
        study=P.summarize_recovery(plan,failed.ledger;scenario_id="artificial",
            dataset_independence=(;status=:unresolved,evidence="Fixed artificial records"))
        @test study.n_planned==2 && study.replications.n_failed==1 && study.replications.n_missing==1
        @test study.counts==Dict(:failed=>1,:no_attempt_recorded=>1)
        serialize(joinpath(directory,"failure-summary.jls"),study)
        @test_throws ArgumentError R.save_new(artifact,"overwrite")
        @test P.filehash(artifact)==original_hash
        bytes=read(artifact);write(artifact,"changed")
        @test_throws ArgumentError run(;output="changed")
        @test !ispath(joinpath(directory,"changed"))
        write(artifact,bytes)
        other=P.bind_observations(plan,"untouched",table)
        otherpath=joinpath(directory,"other.jls");serialize(otherpath,other)
        wrong=P.record_stage(plan,started,id;stage=:generation,status=:completed,artifact=otherpath)
        @test_throws ArgumentError run(wrong;output="wrong-dataset")
        wrongout=deserialize(joinpath(directory,"wrong-dataset","outcome.jls"))
        @test occursin("another dataset",wrongout.reason) && wrongout.failure_kind===:validation
        @test !ispath(joinpath(directory,"wrong-dataset","fit.jls"))
    end
end


function sbc_checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="artificial fixed values")
    template=MFRMRecoveryExample.example_plan(;provenance)
    prior=MFRMPrior()
    sampler=(;backend=:julia,algorithm=:random_walk_metropolis,ndraws=32,warmup=2,
        chains=2,step_size=.1,init_jitter=0.)
    jobs=[(;dataset_id=id,parameter_seed=3i,response_seed=3i+1,fit_seed=3i+2)
        for (i,id) in enumerate(("saved","failed","untouched"))]
    options=(;levels=template.levels,category_levels=template.category_levels,jobs,
        prior,parameters=template.parameters,interval=template.interval,sampler,provenance,
        precision=Dict(template.precision))
    study=P.prepare_sbc(template.assignments;options...,
        rank_settings=(;iterations=(1,9,17,25),dependence_policy="Artificial fixture; no independence evidence"))
    dependence=(;status=:unresolved,evidence="Fixed artificial records, not posterior evidence")
    values=Dict(n=>0.0 for n in template.free_names)
    dataset(id)=P.bind_prior_draw(study,id,values;generating_prior=prior,
        parameter_seed=only(filter(j->j.dataset_id==id,jobs)).parameter_seed)
    function table(plan; single=false)
        (;person=getproperty.(plan.assignments,:person),rater=getproperty.(plan.assignments,:rater),
            item=getproperty.(plan.assignments,:item),score=single ? zeros(Int,72) : [mod(i,4) for i in 1:72])
    end
    function stage(record,id,key,path)
        started=P.record_stage(study,record,id;stage=key,status=:started)
        P.record_stage(study,started,id;stage=key,status=:completed,artifact=path)
    end
    function saved_generation(record,id;single=false)
        folder=joinpath(directory,id);mkdir(folder)
        plan=dataset(id);observed=P.bind_observations(plan,id,table(plan;single))
        R.save_new(joinpath(folder,"dataset-plan.jls"),plan)
        observation_path=joinpath(folder,"generation.jls");R.save_new(observation_path,observed)
        (;plan,observed,record=stage(record,id,:generation,observation_path),path=observation_path)
    end
    initial=P.ledger(study)
    generated=saved_generation(initial,"saved")
    plan,observed=generated.plan,generated.observed
    design=P.bind_data(plan,"saved",table(plan)).design
    # Fixed matrices and invented sampler telemetry exercise storage, never inference.
    draws=[.1sin(i+j) for i in 1:64,j in eachindex(plan.free_names)]
    focal=only(findall(==("rater[R2]"),design.parameter_names))
    selected=[1,9,17,25,33,41,49,57]
    draws[selected,focal]=[-.2,-.1,0.,0.,.1,.2,.3,.4]
    chains=repeat(1:2;inner=32);iterations=repeat(1:32;outer=2)
    logps=[logposterior(design,row,prior) for row in eachrow(draws)]
    controls=(;ndraws=32,warmup=2,chains=2,step_size=.1,init_jitter=0.,
        rng=(;algorithm=:MersenneTwister,seed=first(jobs).fit_seed,replayable=true))
    stats=NamedTuple[B._random_walk_stat_row(;chain=chains[i],iteration=iterations[i],
        accepted=mod(i,4)!=0,nonfinite_proposal=false,step_size=.1,log_density=logps[i]) for i in 1:64]
    fit=MFRMFit(design,prior,draws,logps,.75,collect(chains),collect(iterations),[.75,.75],
        :julia,:random_walk_metropolis,2,.1,stats,controls)
    cache=joinpath(directory,"saved","fit.jls");save_fit_cache(cache,fit)
    record=stage(generated.record,"saved",:fit,cache)
    path(name)=joinpath(directory,name)
    run(r=record;id="saved",output="recovery",through=:recovery,kwargs...)=
        R.run_job(study,r,id;through,output_dir=path(output),kwargs...)
    original_hashes=Dict(f=>P.filehash(f) for f in (generated.path,cache,path("saved/dataset-plan.jls")))
    @testset "SBC runner: artificial saved stages, no RNG or MCMC" begin
        @test R.study_prior(study)==prior
        @test isequal(R.saved_dataset_plan(study,"saved",generated.path),plan)
        @test R.fit_keywords(plan,first(jobs)).seed==first(jobs).fit_seed
        @test_throws ArgumentError run() # Missing selected-draw dependence declaration.
        @test !ispath(path("recovery"))
        @test_throws ArgumentError run(;posterior_dependence=(;status=:unknown,evidence="fixture"))
        @test !ispath(path("recovery"))
        @test_throws ArgumentError R.run_job(plan,P.ledger(plan),"saved";
            through=:generation,output_dir=path("child-plan"))
        old=P.prepare_sbc(template.assignments;options...)
        @test_throws ArgumentError R.run_job(old,P.ledger(old),"saved";
            through=:generation,output_dir=path("missing-policy"))
        @test !ispath(path("missing-policy"))
        @test_throws ArgumentError run(initial;through=:generation,output="rng-mismatch")
        @test !ispath(path("rng-mismatch")) # Artificial declaration cannot initiate generation.
        @test_throws ArgumentError R.run_job(template,P.ledger(template),first(template.jobs).dataset_id;
            through=:generation,output_dir=path("fixed-rng-mismatch"))
        result=run(;posterior_dependence=dependence)
        @test result.status===:completed && only(result.costs).stage===:recovery
        @test only(result.costs).seconds>=0 && only(result.costs).artifact_bytes>0
        @test result.plan_hash==study.content_hash
        @test result.ledger.entries[2:3]==initial.entries[2:3]
        review=deserialize(path("recovery/recovery.jls"))
        @test review.study_hash==study.content_hash && review.plan_hash==plan.content_hash
        @test review.posterior_dependence==dependence && !review.rank_eligible
        @test :posterior_dependence in review.exclusions && :ties in review.exclusions
        @test first(review.ranks).lower==2 && first(review.ranks).upper==4
        @test ismissing(first(review.ranks).rank)
        @test !ispath(path("recovery/fit.jls")) && !ispath(path("recovery/prior-draw.jls"))
        @test all(P.filehash(f)==hash for (f,hash) in original_hashes)
        @test isequal(deserialize(path("recovery/plan.jls")),study)
        @test deserialize(path("recovery/ledger-01.jls")).entries[1].stages.recovery.status===:started
        @test isequal(deserialize(path("recovery/ledger-02.jls")),result.ledger)
        @test run(result.ledger;output="must-not-run").status===:already_completed
        @test !ispath(path("must-not-run"))
        # Invalid actual outcomes are preserved and fail before any call to fit.
        single=saved_generation(result.ledger,"failed";single=true)
        @test_throws ArgumentError P.bind_data(single.plan,"failed",table(single.plan;single=true))
        @test_throws ArgumentError run(single.record;id="failed",through=:fit,output="failed-fit")
        failed=deserialize(path("failed-fit/outcome.jls"))
        @test failed.status===:failed && failed.failure_kind===:validation
        @test occursin(":single_observed_category",failed.reason)
        @test failed.ledger.entries[1]==result.ledger.entries[1]
        @test failed.ledger.entries[3]==initial.entries[3]
        @test !ispath(path("failed-fit/fit.jls"))
        @test_throws ArgumentError run(failed.ledger;id="failed",through=:fit,output="retry")
        @test !ispath(path("retry"))
        summary=P.summarize_sbc(study,failed.ledger;alpha=.05,dataset_independence=dependence)
        @test summary.n_planned==3
        @test summary.counts==Dict(:rank_excluded=>1,:failed=>1,:no_attempt_recorded=>1)
        @test all(q->q.usable==0 && q.unresolved==3,summary.quantities)
        @test !summary.calibration_verified
        R.save_new(path("study.jls"),study)
        R.save_new(path("final-ledger.jls"),failed.ledger)
        R.save_new(path("summary.jls"),summary)
        B._write_json_record(path("summary.json"),summary)
        # A missing or internally altered bound plan must stop before fitting.
        binding=path("saved/dataset-plan.jls");bytes=read(binding);rm(binding)
        @test_throws ArgumentError run(generated.record;through=:fit,output="missing-bound-plan")
        missing=deserialize(path("missing-bound-plan/outcome.jls"))
        @test missing.failure_kind===:validation && occursin("keep dataset-plan.jls",missing.reason)
        write(binding,bytes)
        serialize(binding,merge(plan,(;interval=.8)))
        @test_throws ArgumentError run(generated.record;through=:fit,output="changed-bound-plan")
        changed=deserialize(path("changed-bound-plan/outcome.jls"))
        @test changed.failure_kind===:validation && occursin("differs from its SBC study",changed.reason)
        write(binding,bytes)
        @test all(P.filehash(f)==hash for (f,hash) in original_hashes)
        other=P.bind_prior_draw(study,"saved",Dict(n=>.05 for n in template.free_names);
            generating_prior=prior,parameter_seed=first(jobs).parameter_seed)
        serialize(binding,other)
        @test_throws ArgumentError run(generated.record;through=:fit,output="wrong-truth")
        wrong=deserialize(path("wrong-truth/outcome.jls"))
        @test wrong.failure_kind===:validation && !ispath(path("wrong-truth/fit.jls"))
        write(binding,bytes)
        @test P.filehash(binding)==original_hashes[binding]
    end
end
end
