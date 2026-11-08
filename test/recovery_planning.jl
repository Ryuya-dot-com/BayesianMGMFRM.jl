module RecoveryPlanningChecks
using BayesianMGMFRM, Test, Serialization, SHA
const B = BayesianMGMFRM
const P = B.Experimental.RecoveryPlanning
include("../examples/plan_mfrm_recovery.jl")

function checks(directory)
    # Declared fixture metadata, not an execution/provenance claim.
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="fixture")
    plans=[MFRMRecoveryExample.example_plan(;allocation,provenance)
        for allocation in (:concentrated,:distributed)]
    @testset "Package score-free planning and outcome accounting" begin
        @test :RecoveryPlanning in B.Experimental.surface_contract().reader_facing_bindings
        @test :RecoveryPlanning ∉ names(B)
        @test B.Experimental.surface_contract().candidate_surfaces.recovery_planning == P.contract()
        @test !P.contract().automatic_fitting && !P.contract().automatic_generation
        @test !P.contract().sbc && !P.contract().interrupted_chain_resume
        for operation in (:prepare,:generator_input,:bind_observations,:bind_data,
                :observation_table,:review_fit,:ledger,:record_stage,:review,:contract)
            @test Base.Docs.doc(getfield(P,operation)) !== nothing
        end
        for (allocation,plan) in zip((:concentrated,:distributed),plans)
            @test length(plan.assignments) == 72
            @test [count(r -> r.rater==label,plan.assignments) for label in plan.levels.rater] == [24,24,24]
            @test plan.location_rank == 17
            @test length(plan.free_names) == 25
            @test !plan.generation_verified
            shared = count(plan.levels.person) do person
                length(unique(r.rater for r in plan.assignments if r.person==person)) > 1
            end
            @test shared == (allocation === :concentrated ? 3 : 6)
            job=only(plan.jobs); input=P.generator_input(plan,job.dataset_id)
            @test input.recipe.scores === :structural_placeholders_only
            @test Tuple(input.design.parameter_names) == plan.free_names
            @test hasmethod(simulate_responses,Tuple{typeof(input.design),typeof(input.direct_truth)})
            # Independent adjacent-logit equation, no response generation.
            truth=Dict(plan.truth)
            probabilities=predictive_probabilities(input.design,reshape(input.direct_truth,1,:))
            expected=zeros(72,4)
            for (j,r) in enumerate(plan.assignments)
                eta=truth["person[$(r.person)]"]-truth["rater[$(r.rater)]"]-truth["item[$(r.item)]"]
                logw=[0.;cumsum([eta-truth["step[item=$(r.item),$k]"] for k in 1:3])]
                weights=exp.(logw .- maximum(logw));expected[j,:]=weights/sum(weights)
            end
            @test probabilities[1,:,:] ≈ expected atol=1e-13 rtol=1e-13
            table=(;person=getproperty.(plan.assignments,:person),rater=getproperty.(plan.assignments,:rater),
                item=getproperty.(plan.assignments,:item),score=[mod(j,2) for j in 1:72])
            observed=P.bind_observations(plan,job.dataset_id,table)
            bound=P.bind_data(plan,job.dataset_id,table)
            @test bound.data.category_levels == collect(0:3) # absent upper categories retained
            @test bound.direct_truth == input.direct_truth
            @test Tuple(P.observation_table(plan,observed).score) == observed.scores
            @test predictive_probabilities(bound.design,reshape(bound.direct_truth,1,:)) == probabilities
            constant=merge(table,(;score=fill(0,72)))
            @test P.bind_observations(plan,job.dataset_id,constant).scores == Tuple(zeros(Int,72))
            @test_throws ArgumentError P.bind_data(plan,job.dataset_id,constant)
            @test_throws ArgumentError P.bind_observations(plan,job.dataset_id,merge(table,(;score=fill(4,72))))
            @test_throws ArgumentError P.bind_observations(plan,job.dataset_id,merge(table,(;person=reverse(table.person))))
            @test_throws ArgumentError P.generator_input(plan,"absent")
            @test_throws ArgumentError P.generator_input(merge(plan,(;interval=.99)),job.dataset_id)
            path=joinpath(directory,"$(allocation)-observations.jls");serialize(path,observed)
            record=P.ledger(plan); before=deepcopy(record)
            @test only(P.review(plan,record).rows).outcome === :no_attempt_recorded
            started=P.record_stage(plan,record,job.dataset_id;stage=:generation,status=:started)
            @test isequal(record,before)
            @test only(P.review(plan,started).rows).outcome === :unresolved_started
            completed=P.record_stage(plan,started,job.dataset_id;stage=:generation,status=:completed,artifact=path)
            @test only(P.review(plan,completed).rows).outcome === :partial_completed
            @test_throws ArgumentError P.record_stage(plan,completed,job.dataset_id;stage=:recovery,status=:started)
            begun=P.record_stage(plan,completed,job.dataset_id;stage=:fit,status=:started)
            failed=P.record_stage(plan,begun,job.dataset_id;stage=:fit,status=:failed,
                failure_kind=:validation,reason="Deterministic stage fixture; no sampler called")
            @test only(P.review(plan,failed).rows).outcome === :failed
            @test_throws ArgumentError P.record_stage(plan,failed,job.dataset_id;stage=:fit,status=:started)
            write(path,"changed artifact")
            @test only(P.review(plan,completed).rows).outcome === :artifact_review_required
            @test_throws ArgumentError P.record_stage(plan,completed,job.dataset_id;stage=:fit,status=:started)
            planpath=joinpath(directory,"$(allocation)-plan.jls");serialize(planpath,plan)
            @test isequal(deserialize(planpath),plan)
        end
        @test_throws ArgumentError MFRMRecoveryExample.example_plan(;allocation=:unknown,provenance)
        plan=first(plans)
        # Even a connected allocation can confound rater severity and person ability.
        primary=collect(plan.assignments[1:48])
        @test_throws ArgumentError P.prepare(primary;levels=plan.levels,category_levels=plan.category_levels,
            truth=Dict(plan.truth),prior=MFRMPrior(person_sd=1.5,rater_sd=1.,item_sd=1.,step_sd=1.),
            jobs=plan.jobs,parameters=plan.parameters,interval=plan.interval,
            sampler=plan.sampler,provenance,precision=Dict(plan.precision))
        @test_throws ArgumentError P.observation_table(last(plans),
            P.bind_observations(plan,only(plan.jobs).dataset_id,
                (;person=getproperty.(plan.assignments,:person),rater=getproperty.(plan.assignments,:rater),
                  item=getproperty.(plan.assignments,:item),score=fill(0,72))))
    end
end

function sbc_checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="fixed fixture; no RNG")
    template=MFRMRecoveryExample.example_plan(;provenance)
    prior=MFRMPrior(person_sd=1.5,rater_sd=0.7,item_sd=0.9,step_sd=0.4)
    jobs=[(;dataset_id=id,parameter_seed=3i,response_seed=3i+1,fit_seed=3i+2)
        for (i,id) in enumerate(("first","failed","pending"))]
    options=(;levels=template.levels,category_levels=template.category_levels,jobs,prior,
        parameters=template.parameters,interval=template.interval,sampler=template.sampler,
        provenance,precision=Dict(template.precision))
    study=P.prepare_sbc(template.assignments;options...)
    @testset "Joint-prior SBC input preparation without sampling" begin
        @test P.contract().sbc_input_preparation && !P.contract().sbc
        @test !study.generation_verified && !study.sbc_performed
        for operation in (:prepare_sbc,:prior_input,:bind_prior_draw)
            @test Base.Docs.doc(getfield(P,operation)) !== nothing
        end
        recipe=P.prior_input(study,"first")
        @test Tuple(c.parameter for c in recipe.coordinates)==template.free_names
        @test length(recipe.coordinates)==25 # every free parameter, not only the focal severity
        @test recipe.parameter_seed==jobs[1].parameter_seed
        @test recipe.rng_declaration==provenance.rng_algorithm
        @test recipe.prior==study.template.analysis_prior
        @test_throws ArgumentError P.generator_input(study,"first")
        @test_throws ArgumentError P.prior_input(study,"absent")
        @test_throws ArgumentError P.prior_input(merge(study,(;sbc_performed=true)),"first")
        # Artificial parameter values: these are never evidence of prior sampling.
        values=Dict(c.parameter=>(i-13)/20 for (i,c) in enumerate(recipe.coordinates))
        bound=P.bind_prior_draw(study,"first",values;generating_prior=prior,parameter_seed=3)
        truth=Dict(bound.truth)
        @test bound.sbc_binding.study_hash==study.content_hash
        @test bound.sbc_binding.prior_input_hash==recipe.content_hash
        @test !bound.sbc_binding.sampling_history_verified
        @test only(bound.jobs)==(;dataset_id="first",response_seed=4,fit_seed=5)
        @test bound.analysis_prior==recipe.prior
        @test truth["rater[R1]"]==truth["item[I1]"]==0.0
        for item in template.levels.item
            @test truth["step[item=$item,3]"] == -(values["step[item=$item,1]"]+values["step[item=$item,2]"])
        end
        input=P.generator_input(bound,"first")
        scales=[startswith(n,"person[") ? 1.5 : startswith(n,"rater[") ? 0.7 :
            startswith(n,"item[") ? 0.9 : 0.4 for n in template.free_names]
        @test collect(c.sd for c in recipe.coordinates)==scales
        @test all(c.mean==0.0 for c in recipe.coordinates)
        expected_prior=sum(-log(s*sqrt(2pi))-0.5*(x/s)^2 for (x,s) in zip(input.direct_truth,scales))
        @test logprior(input.design,input.direct_truth,prior) ≈ expected_prior atol=1e-12 rtol=1e-13
        expected=zeros(72,4)
        for (j,row) in enumerate(bound.assignments)
            eta=truth["person[$(row.person)]"]-truth["rater[$(row.rater)]"]-truth["item[$(row.item)]"]
            logw=[0.;cumsum([eta-truth["step[item=$(row.item),$k]"] for k in 1:3])]
            weights=exp.(logw .- maximum(logw));expected[j,:]=weights/sum(weights)
        end
        @test predictive_probabilities(input.design,reshape(input.direct_truth,1,:))[1,:,:] ≈ expected atol=1e-13 rtol=1e-13
        bind(v)=P.bind_prior_draw(study,"first",v;generating_prior=prior,parameter_seed=3)
        for bad in (NaN,Inf,true)
            invalid=Dict{String,Any}(values);invalid[first(template.free_names)]=bad
            @test_throws ArgumentError bind(invalid)
        end
        @test_throws ArgumentError bind(Dict(k=>v for (k,v) in values if k!=first(template.free_names)))
        @test_throws ArgumentError bind(merge(values,Dict("rater[R1]"=>0.0)))
        @test_throws ArgumentError P.bind_prior_draw(study,"first",values;generating_prior=prior,parameter_seed=4)
        different=MFRMPrior(person_sd=1.6,rater_sd=0.7,item_sd=0.9,step_sd=0.4)
        @test_throws ArgumentError P.bind_prior_draw(study,"first",values;generating_prior=different,parameter_seed=3)
        @test_throws ArgumentError P.prepare_sbc(template.assignments;options...,generating_prior=different)
        for seed in (-1,true,4)
            changed=Any[jobs...];changed[1]=merge(changed[1],(;parameter_seed=seed))
            @test_throws ArgumentError P.prepare_sbc(template.assignments;merge(options,(;jobs=changed))...)
        end
        @test_throws ArgumentError P.prepare_sbc(template.assignments;merge(options,(;jobs=[jobs[1],jobs[1]]))...)
        changed=copy(jobs);changed[1]=merge(changed[1],(;parameter_seed=99))
        revised=P.prepare_sbc(template.assignments;merge(options,(;jobs=changed))...)
        @test revised.content_hash!=study.content_hash
        @test P.prior_input(revised,"first").coordinates==recipe.coordinates
        for categories in (0:1,2:6)
            other=P.prepare_sbc(template.assignments;merge(options,(;category_levels=categories))...)
            coords=P.prior_input(other,"first").coordinates
            fixed=Dict(c.parameter=>i/10 for (i,c) in enumerate(coords))
            realized=P.bind_prior_draw(other,"first",fixed;generating_prior=prior,parameter_seed=3)
            alltruth=Dict(realized.truth);K=length(categories)
            for item in realized.levels.item
                @test alltruth["step[item=$item,$(K-1)]"] ≈ -sum((get(fixed,"step[item=$item,$k]",0.0) for k in 1:K-2);init=0.0)
            end
            @test P.generator_input(realized,"first").direct_truth==[fixed[n] for n in realized.free_names]
        end
        table=(;person=getproperty.(bound.assignments,:person),rater=getproperty.(bound.assignments,:rater),
            item=getproperty.(bound.assignments,:item),score=[mod(i,2) for i in 1:72])
        observations=P.bind_observations(bound,"first",table)
        @test P.bind_data(bound,"first",table).direct_truth==input.direct_truth
        path=joinpath(directory,"sbc-artificial-generation.jls")
        serialize(path,(;plan=bound,observations,artificial_fixture=true))
        loaded=deserialize(path)
        @test isequal(loaded.plan,bound)
        @test P.generator_input(loaded.plan,"first").direct_truth==input.direct_truth
        @test P.observation_table(loaded.plan,loaded.observations).score==collect(table.score)
        @test_throws ArgumentError P.observation_table(study.template,observations)
        study_path=joinpath(directory,"sbc-study.jls");serialize(study_path,study)
        @test isequal(deserialize(study_path),study)
        ledger=P.ledger(study)
        ledger=P.record_stage(study,ledger,"first";stage=:generation,status=:started)
        ledger=P.record_stage(study,ledger,"first";stage=:generation,status=:completed,artifact=path)
        ledger=P.record_stage(study,ledger,"failed";stage=:generation,status=:started)
        ledger=P.record_stage(study,ledger,"failed";stage=:generation,status=:failed,
            failure_kind=:validation,reason="Artificial outcome; no RNG or fit")
        @test P.review(study,ledger).counts==Dict(:partial_completed=>1,:failed=>1,:no_attempt_recorded=>1)
        @test_throws ArgumentError P.review(bound,ledger)
        @test_throws ArgumentError P.record_stage(study,ledger,"failed";stage=:generation,status=:started)
        single=merge(table,(;score=fill(0,72)))
        @test P.bind_observations(bound,"first",single).scores==Tuple(zeros(Int,72))
        @test_throws ArgumentError P.bind_data(bound,"first",single)
    end
end

function sbc_rank_checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="artificial fixed values")
    template=MFRMRecoveryExample.example_plan(;provenance)
    prior=MFRMPrior()
    sampler=(;backend=:julia,algorithm=:random_walk_metropolis,ndraws=32,warmup=2,
        chains=2,step_size=.1,init_jitter=0.)
    settings=(;iterations=(1,9,17,25),dependence_policy="Artificial test only; no posterior independence evidence")
    options=(;levels=template.levels,category_levels=template.category_levels,
        jobs=[(;dataset_id="artificial",parameter_seed=1,response_seed=2,fit_seed=3)],
        prior,parameters=template.parameters,interval=template.interval,sampler,provenance,
        precision=Dict("rater[R2]"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02)))
    study=P.prepare_sbc(template.assignments;options...,rank_settings=settings)
    plan=P.bind_prior_draw(study,"artificial",Dict(n=>0.0 for n in template.free_names);
        generating_prior=prior,parameter_seed=1)
    table=(;person=getproperty.(plan.assignments,:person),rater=getproperty.(plan.assignments,:rater),
        item=getproperty.(plan.assignments,:item),score=[mod(i,4) for i in 1:72])
    observed=P.bind_observations(plan,"artificial",table)
    design=P.bind_data(plan,"artificial",table).design
    # Fabricated matrices and sampler metadata test persistence, never inference.
    draws=[.1sin(i+j) for i in 1:64,j in eachindex(plan.free_names)]
    focal=only(findall(==("rater[R2]"),design.parameter_names))
    selected=[1,9,17,25,33,41,49,57]
    draws[selected,focal]=[-.2,-.1,0.,0.,.1,.2,.3,.4]
    chains=repeat(1:2;inner=32);iterations=repeat(1:32;outer=2)
    logps=[logposterior(design,row,prior) for row in eachrow(draws)]
    controls=(;ndraws=32,warmup=2,chains=2,step_size=.1,init_jitter=0.,
        rng=(;algorithm=:MersenneTwister,seed=3,replayable=true))
    stats=NamedTuple[B._random_walk_stat_row(;chain=chains[i],iteration=iterations[i],
        accepted=mod(i,4)!=0,nonfinite_proposal=false,step_size=.1,log_density=logps[i]) for i in 1:64]
    fit=MFRMFit(design,prior,draws,logps,.75,collect(chains),collect(iterations),[.75,.75],
        :julia,:random_walk_metropolis,2,.1,stats,controls)
    path=joinpath(directory,"artificial-sbc-cache.jls");save_fit_cache(path,fit)
    hash=P.filehash(path)
    unresolved=(;status=:unresolved,evidence="Artificial fixture; dependence unassessed")
    declared=(;status=:declared_independent,evidence="Exercise declaration branch only; not empirical evidence")
    @testset "SBC saved ranks, identity, ties and diagnostic exclusions" begin
        @test Base.Docs.doc(P.review_sbc_fit)!==nothing
        @test P.contract().sbc_saved_rank_review && !P.contract().automatic_tie_randomization
        @test !hasproperty(P.prepare_sbc(template.assignments;options...),:rank_settings)
        for ids in ((),(0,),(33,),(1,1),(9,1),(true,))
            @test_throws ArgumentError P.prepare_sbc(template.assignments;options...,
                rank_settings=merge(settings,(;iterations=ids)))
        end
        @test_throws ArgumentError P.prepare_sbc(template.assignments;options...,
            rank_settings=merge(settings,(;dependence_policy=" ")))
        @test isequal(P.rank_interval(0.,[-2.,-1.,0.,0.,3.]),
            (;truth=0.,n_draws=5,lower=2,upper=4,ties=2,rank=missing))
        @test P.rank_interval(0.,[nextfloat(0.)]).rank==0 # exact, not approximate ties
        @test P.rank_interval(10.,[-1.,0.,1.]).rank==3
        # Every possible truth position in this fixed, distinct set gives one rank.
        fixed=[-2.,0.,1.,4.]
        @test [P.rank_interval(x,filter(!=(x),fixed)).rank for x in fixed]==collect(0:3)
        for (x,y) in ((NaN,[0.]),(0.,[Inf]),(true,[0.]),(0.,Float64[]))
            @test_throws ArgumentError P.rank_interval(x,y)
        end
        result=P.review_sbc_fit(study,plan,observed,path;cache_sha256=hash,posterior_dependence=unresolved)
        @test result.selected_rows==Tuple(selected)
        @test result.chain_ids==Tuple(repeat(1:2;inner=4))
        @test result.iterations==Tuple(repeat([1,9,17,25];outer=2))
        @test first(result.ranks).lower==2 && first(result.ranks).upper==4
        @test ismissing(first(result.ranks).rank) && first(result.ranks).ties==2
        @test getproperty.(result.ranks,:quantity)==("rater[R2]","joint_log_likelihood")
        @test last(result.ranks).truth ≈ -72log(4) atol=1e-12
        # Independent PCM equation on the actual observed categories.
        function manual_loglik(row)
            truth=Dict(plan.truth)
            merge!(truth,Dict(zip(plan.free_names,row)))
            for item in plan.levels.item
                truth["step[item=$item,3]"]=-truth["step[item=$item,1]"]-truth["step[item=$item,2]"]
            end
            sum(enumerate(plan.assignments)) do (i,r)
                eta=truth["person[$(r.person)]"]-truth["rater[$(r.rater)]"]-truth["item[$(r.item)]"]
                w=[0.;cumsum([eta-truth["step[item=$(r.item),$k]"] for k in 1:3])]
                w[table.score[i]+1]-maximum(w)-log(sum(exp.(w .- maximum(w))))
            end
        end
        manual=manual_loglik.(eachrow(draws[selected,:]))
        @test last(result.ranks).lower==count(<(-72log(4)),manual)
        @test all(r -> r.total_draws==64 && r.draws_per_chain==32,result.quantity_diagnostics)
        @test !result.rank_eligible && !result.calibration_verified && !result.independence_verified
        @test :posterior_dependence in result.exclusions && :ties in result.exclusions
        @test :fit_or_focal_precision in result.exclusions
        @test isequal(result.fit_review,P.review_fit(plan,observed,path;cache_sha256=hash))
        other=P.review_sbc_fit(study,plan,observed,path;cache_sha256=hash,posterior_dependence=declared)
        @test :posterior_dependence ∉ other.exclusions
        @test :ties in other.exclusions && !other.rank_eligible
        @test isequal(other.ranks,result.ranks) && !other.independence_verified
        @test P.filehash(path)==hash
        saved=joinpath(directory,"artificial-sbc-review.jls");serialize(saved,result)
        @test isequal(deserialize(saved),result)
        @test B._prediction_check_seal(deserialize(saved),"bayesianmgmfrm.mfrm_sbc_rank_review.v1")===nothing
        changed=P.prepare_sbc(template.assignments;options...,rank_settings=merge(settings,(;iterations=(2,10))))
        @test_throws ArgumentError P.review_sbc_fit(changed,plan,observed,path;cache_sha256=hash,posterior_dependence=declared)
        old=P.prepare_sbc(template.assignments;options...)
        @test_throws ArgumentError P.review_sbc_fit(old,plan,observed,path;cache_sha256=hash,posterior_dependence=declared)
        @test_throws ArgumentError P.review_sbc_fit(study,plan,observed,path;cache_sha256=hash,
            posterior_dependence=(;status=:declared_independent,evidence=""))
        @test_throws ArgumentError P.review_sbc_fit(study,plan,observed,path;cache_sha256=repeat("0",64),posterior_dependence=declared)
        @test_throws ArgumentError P.review_sbc_fit(study,merge(plan,(;interval=.8)),observed,path;cache_sha256=hash,posterior_dependence=declared)
        sbc_summary_checks(directory,study,observed,result,path)
    end
end

function sbc_summary_checks(directory,original,observed,rank_review,cache_path)
    seal(x)=B._prediction_seal(Base.structdiff(x,(;content_hash=nothing)))
    unresolved=(;status=:unresolved,evidence="Artificial fixture, no independence evidence")
    declared=(;status=:declared_independent,evidence="Artificial arithmetic branch only")
    summarize(study,record;kwargs...)=P.summarize_sbc(study,record;alpha=.05,
        dataset_independence=declared,kwargs...)
    function complete(record,study,id,paths)
        for (stage,path) in zip(P.STAGES,paths)
            record=P.record_stage(study,record,id;stage,status=:started)
            record=P.record_stage(study,record,id;stage,status=:completed,artifact=path)
        end
        record
    end
    @testset "SBC study roster, saved identities and conditional rank CDF" begin
        @test Base.Docs.doc(P.summarize_sbc)!==nothing
        @test P.contract().sbc_study_summary && !P.contract().sbc
        # Real review path on an artificial native cache: preserve its warnings.
        obs_path=joinpath(directory,"bound-observations.jls");serialize(obs_path,observed)
        review_path=joinpath(directory,"bound-rank-review.jls");serialize(review_path,rank_review)
        single=complete(P.ledger(original),original,observed.dataset_id,(obs_path,cache_path,review_path))
        one=summarize(original,single)
        @test one.counts==Dict(:rank_excluded=>1)
        @test one.roster[1].exclusions==rank_review.exclusions
        @test all(q->q.unresolved==1 && q.conditional_screen==:unresolved,one.quantities)

        # Everything below is an invented record fixture, not fitted/generative evidence.
        template=original.template
        names=("eligible","eligible2","tied","failed","started","pending","partial","missing")
        jobs=[(;dataset_id=id,parameter_seed=3i,response_seed=3i+1,fit_seed=3i+2) for (i,id) in enumerate(names)]
        prior=MFRMPrior()
        study=P.prepare_sbc(template.assignments;levels=template.levels,category_levels=template.category_levels,
            jobs,prior,parameters=template.parameters,interval=template.interval,sampler=template.sampler,
            provenance=template.provenance,precision=Dict(template.precision),rank_settings=original.rank_settings)
        folder=joinpath(directory,"artificial summary");mkpath(folder)
        record=P.ledger(study);reviews=Dict{String,Any}()
        for job in jobs[1:3]
            id=job.dataset_id
            plan=P.bind_prior_draw(study,id,Dict(n=>0.0 for n in template.free_names);
                generating_prior=prior,parameter_seed=job.parameter_seed)
            o=seal(merge(observed,(;dataset_id=id,plan_hash=plan.content_hash,response_seed=job.response_seed)))
            op=joinpath(folder,id*"-obs.jls");serialize(op,o)
            cp=joinpath(folder,id*"-cache.jls");serialize(cp,(;id,artificial=true))
            recovery=seal(merge(rank_review.fit_review.recovery,(;dataset_id=id,sampling_warning=false,
                fixed_truth_mismatch=false,source_sample_hash=B._cache_hash((id,:artificial)))))
            fit_review=seal(merge(rank_review.fit_review,(;plan_hash=plan.content_hash,observations_hash=o.content_hash,
                cache=(;path=cp,sha256=P.filehash(cp)),recovery,
                precision=Tuple(merge(p,(;passed=true)) for p in rank_review.fit_review.precision),numerically_qualified=true)))
            diagnostics=Tuple(merge(d,(;flag=:ok)) for d in rank_review.quantity_diagnostics)
            ranks=Tuple(merge(r,(;lower=0,upper=id=="tied" ? 1 : 0,ties=id=="tied" ? 1 : 0,
                rank=id=="tied" ? missing : 0)) for r in rank_review.ranks)
            r=seal(merge(rank_review,(;study_hash=study.content_hash,plan_hash=plan.content_hash,
                observations_hash=o.content_hash,dataset_id=id,fit_review,quantity_diagnostics=diagnostics,
                ranks,posterior_dependence=declared,exclusions=id=="tied" ? (:ties,) : (),rank_eligible=id!="tied")))
            rp=joinpath(folder,id*"-review.jls");serialize(rp,r);reviews[id]=r
            record=complete(record,study,id,(op,cp,rp))
        end
        record=P.record_stage(study,record,"failed";stage=:generation,status=:started)
        record=P.record_stage(study,record,"failed";stage=:generation,status=:failed,
            failure_kind=:validation,reason="Artificial failure; no data generated")
        record=P.record_stage(study,record,"started";stage=:generation,status=:started)
        partial=joinpath(folder,"partial.jls");serialize(partial,(;artificial=true))
        for id in ("partial","missing")
            record=P.record_stage(study,record,id;stage=:generation,status=:started)
            record=P.record_stage(study,record,id;stage=:generation,status=:completed,artifact=partial)
        end
        # One missing artifact, separate from partial completion and unattempted work.
        entries=deepcopy(record.entries)
        entries[8]=merge(entries[8],(;stages=merge(entries[8].stages,(;generation=merge(entries[8].stages.generation,
            (;artifact=(;path=joinpath(folder,"absent.jls"),sha256=P.filehash(partial))))))))
        record=seal(merge(record,(;entries)))
        result=summarize(study,record)
        @test result.n_planned==8
        @test result.counts==Dict(:rank_eligible=>2,:rank_excluded=>1,:failed=>1,:unresolved_started=>1,
            :no_attempt_recorded=>1,:partial_completed=>1,:artifact_review_required=>1)
        @test Tuple(r.dataset_id for r in result.roster)==Tuple(names)
        @test result.roster[4].stages.generation.reason=="Artificial failure; no data generated"
        @test result.roster[3].descriptive_ranks[1].ties==1
        @test result.exclusion_counts[:ties]==1 && result.exclusion_counts[:posterior_dependence]==0
        q=first(result.quantities)
        @test isequal(q.ranks,(0,0,missing,missing,missing,missing,missing,missing))
        @test (q.planned,q.usable,q.unresolved,q.n_draws,q.n_quantities)==(8,2,6,8,2)
        @test q.rows[1].lower==.25 && q.rows[1].upper==1.0 && q.rows[1].reference==1/9
        @test q.rows[end].lower==q.rows[end].upper==q.rows[end].band_lower==q.rows[end].band_upper==1.0
        @test q.epsilon ≈ sqrt(log(80)/16)
        @test !result.calibration_verified && !result.independence_verified && !result.generation_verified
        @test result.new_posterior_fits==result.new_generated_datasets==0
        held=P.summarize_sbc(study,record;alpha=.05,dataset_independence=unresolved)
        @test all(q->ismissing(q.epsilon) && q.conditional_screen==:assumptions_unresolved,held.quantities)
        @test all(r->ismissing(r.band_lower) && ismissing(r.band_upper) && ismissing(r.resolved_departure),held.quantities[1].rows)
        @test getproperty.(held.quantities[1].rows,:lower)==getproperty.(q.rows,:lower)
        saved=joinpath(directory,"summary.jls");serialize(saved,result)
        @test isequal(deserialize(saved),result)
        @test B._prediction_check_seal(result,"bayesianmgmfrm.mfrm_sbc_summary.v1")===nothing
        # Rebind altered bytes deliberately to test semantic validation past file hashes.
        function altered(r;index=1)
            p=joinpath(directory,"altered-review.jls");serialize(p,r)
            entries=deepcopy(record.entries)
            e=entries[index]
            entries[index]=merge(e,(;stages=merge(e.stages,(;recovery=merge(e.stages.recovery,
                (;artifact=(;path=p,sha256=P.filehash(p))))))))
            seal(merge(record,(;entries)))
        end
        r=reviews["eligible"]
        for wrong in (
                merge(r,(;dataset_id="unknown")),
                seal(merge(r,(;study_hash=repeat("0",64)))),
                seal(merge(r,(;observations_hash=repeat("0",64)))),
                seal(merge(r,(;selected_rows=reverse(r.selected_rows)))),
                seal(merge(r,(;ranks=reverse(r.ranks)))),
                seal(merge(r,(;ranks=Tuple(merge(x,(;rank=true)) for x in r.ranks)))),
                seal(merge(r,(;ranks=Tuple(merge(x,(;upper=9,ties=9,rank=missing)) for x in r.ranks)))),
                seal(merge(r,(;exclusions=(:ties,),rank_eligible=false))),
                seal(merge(r,(;posterior_dependence=unresolved))))
            @test_throws ArgumentError summarize(study,altered(wrong))
        end
        other=reviews["eligible2"]
        duplicate=seal(merge(other,(;fit_review=seal(merge(other.fit_review,(;recovery=seal(merge(
            other.fit_review.recovery,(;source_sample_hash=r.fit_review.recovery.source_sample_hash)))))))))
        @test_throws ArgumentError summarize(study,altered(duplicate;index=2))
        for alpha in (0.,1.,NaN,Inf,true)
            @test_throws ArgumentError P.summarize_sbc(study,record;alpha,dataset_independence=declared)
        end
        @test_throws ArgumentError P.summarize_sbc(study,record;alpha=.05,
            dataset_independence=(;status=:declared_independent,evidence=" "))
        @test_throws ArgumentError summarize(study,single)
        pending=summarize(study,P.ledger(study))
        @test pending.counts==Dict(:no_attempt_recorded=>8)
        @test all(q->q.conditional_screen==:unresolved && q.unresolved==8,pending.quantities)
        # Changed files remain in the roster, but cannot contribute primary ranks.
        changed=record.entries[1].stages.fit.artifact.path;bytes=read(changed);write(changed,"changed")
        @test summarize(study,record).quantities[1].unresolved==7
        write(changed,bytes)
        # Relocation preserves hashes even though embedded review paths are old.
        # Exclude only the already-missing fixture from this separate relocation check.
        single_folder=joinpath(directory,"single saved");mkpath(single_folder)
        paths=Tuple(cp(p,joinpath(single_folder,basename(p))) for p in (obs_path,cache_path,review_path))
        single_moved=complete(P.ledger(original),original,observed.dataset_id,paths)
        destination=joinpath(directory,"single moved");mv(single_folder,destination)
        relocated=P.relocate_ledger(original,single_moved;source_root=single_folder,destination_root=destination)
        @test summarize(original,relocated).counts==one.counts
        @test P.filehash(cache_path)==rank_review.fit_review.cache.sha256
    end
    @testset "Independent finite enumeration of CDF bounds" begin
        cdf(r;T=2,independent=true)=P.sbc_rank_cdf(r;n_draws=2,n_quantities=T,alpha=.05,independent)
        # Enumerate every completion of two unknown ranks, rather than repeat the formula.
        bounds=cdf([1,missing,missing])
        completions=[[(count(<=(k),[1,a,b]))/3 for k in 0:2] for a in 0:2 for b in 0:2]
        @test getproperty.(bounds.rows,:lower)==[minimum(x[k] for x in completions) for k in 1:3]
        @test getproperty.(bounds.rows,:upper)==[maximum(x[k] for x in completions) for k in 1:3]
        @test cdf(fill(0,100)).conditional_screen==:departure
        @test cdf(repeat(0:2;outer=100)).conditional_screen==:no_resolved_departure
        @test cdf(fill(missing,100)).conditional_screen==:unresolved
        @test cdf(fill(0,100);independent=false).conditional_screen==:assumptions_unresolved
        @test cdf(fill(0,100);T=4).epsilon>cdf(fill(0,100);T=1).epsilon
        @test bounds.rows[end].lower==bounds.rows[end].upper==1.0
    end
end

function relocation_checks(directory)
    provenance=(;source_sha256=repeat("0",64),project_sha256=repeat("1",64),
        manifest_sha256=repeat("2",64),julia_version=string(VERSION),rng_algorithm="fixture")
    template=MFRMRecoveryExample.example_plan(;provenance)
    jobs=[(;dataset_id=name,response_seed=2i,fit_seed=2i+1)
        for (i,name) in enumerate(("complete","failed","unfinished","pending"))]
    plan=P.prepare(template.assignments;levels=template.levels,
        category_levels=template.category_levels,truth=Dict(template.truth),jobs,
        prior=MFRMPrior(person_sd=1.5,rater_sd=1.,item_sd=1.,step_sd=1.),
        parameters=template.parameters,interval=template.interval,sampler=template.sampler,
        provenance,precision=Dict(template.precision))
    source=joinpath(directory,"original study")
    destination=joinpath(directory,"moved study")
    mkpath(source)
    record=P.ledger(plan)
    # These files test bookkeeping, not native fit deserialization or inference.
    for (id,stages) in (("complete",(:generation,:fit,:recovery)),("failed",(:generation,)))
        for stage in stages
            path=joinpath(source,id,"$(stage).jls");mkpath(dirname(path))
            serialize(path,(;id,stage,fixture=true))
            record=P.record_stage(plan,record,id;stage,status=:started)
            record=P.record_stage(plan,record,id;stage,status=:completed,artifact=path)
        end
    end
    record=P.record_stage(plan,record,"failed";stage=:fit,status=:started)
    record=P.record_stage(plan,record,"failed";stage=:fit,status=:failed,
        failure_kind=:validation,reason="Saved fixture failure; no sampler invoked")
    record=P.record_stage(plan,record,"unfinished";stage=:generation,status=:started)
    original=deepcopy(record)
    @testset "Move saved study without changing outcomes or executing work" begin
        @test Base.Docs.doc(P.relocate_ledger) !== nothing
        @test P.contract().verified_ledger_relocation
        expected=Dict(:recorded_completed=>1,:failed=>1,:unresolved_started=>1,:no_attempt_recorded=>1)
        @test P.review(plan,record).counts==expected
        mv(source,destination)
        @test !isdir(source)
        @test P.review(plan,record).counts[:artifact_review_required]==2
        relocated=P.relocate_ledger(plan,record;source_root=source,destination_root=destination)
        @test isequal(record,original)
        @test P.review(plan,relocated).counts==expected
        @test relocated.plan_hash==record.plan_hash
        @test getproperty.(relocated.entries,:dataset_id)==getproperty.(record.entries,:dataset_id)
        @test P.checkledger(plan,relocated)===true
        @test relocated.content_hash != record.content_hash
        @test relocated.relocations == ((;previous_ledger_hash=record.content_hash,
            source_root=source,destination_root=destination),)
        for (old,new) in zip(record.entries,relocated.entries), stage in P.STAGES
            a=getproperty(old.stages,stage);b=getproperty(new.stages,stage)
            @test isequal((a.status,a.reason,a.failure_kind),(b.status,b.reason,b.failure_kind))
            if a.artifact===nothing
                @test b.artifact===nothing
            else
                @test b.artifact.sha256==a.artifact.sha256
                @test b.artifact.path==joinpath(destination,relpath(a.artifact.path,source))
                @test isfile(b.artifact.path)
            end
        end
        # Changed and missing destination files must not yield a usable new ledger.
        target=joinpath(destination,"failed","generation.jls")
        bytes=read(target)
        write(target,"changed")
        @test_throws ArgumentError P.relocate_ledger(plan,record;source_root=source,destination_root=destination)
        @test isequal(record,original)
        rm(target)
        @test_throws ArgumentError P.relocate_ledger(plan,record;source_root=source,destination_root=destination)
        write(target,bytes)
        @test_throws ArgumentError P.relocate_ledger(plan,record;source_root=directory*"-sibling",destination_root=destination)
        @test_throws ArgumentError P.relocate_ledger(plan,record;source_root=source,destination_root=source)
        @test_throws ArgumentError P.relocate_ledger(plan,record;source_root=source,destination_root=destination*"-absent")
        @test_throws ArgumentError P.relocate_ledger(plan,record;source_root="relative",destination_root=destination)
        @test_throws ArgumentError P.relocate_ledger(plan,merge(record,(;plan_hash="changed"));source_root=source,destination_root=destination)
        @test isequal(P.relocate_ledger(plan,P.ledger(plan);source_root=source,destination_root=destination),P.ledger(plan))
        @test_throws ArgumentError P.record_stage(plan,relocated,"failed";stage=:fit,status=:started)
        # Subsequent stage updates must keep relocation history, including unresolved work.
        pending_started=P.record_stage(plan,relocated,"pending";stage=:generation,status=:started)
        @test pending_started.relocations==relocated.relocations
        @test P.checkledger(plan,pending_started)===true
        @test P.review(plan,pending_started).counts[:unresolved_started]==2
        second=joinpath(directory,"second copy")
        cp(destination,second)
        again=P.relocate_ledger(plan,pending_started;source_root=destination,destination_root=second)
        @test length(again.relocations)==2
        @test again.relocations[1]==relocated.relocations[1]
        @test again.relocations[2].previous_ledger_hash==pending_started.content_hash
        @test P.review(plan,again).counts==P.review(plan,pending_started).counts
        saved=joinpath(directory,"relocated-ledger.jls");serialize(saved,again)
        @test isequal(deserialize(saved),again)
        @test P.review(plan,deserialize(saved)).counts==P.review(plan,again).counts
        write(joinpath(second,"complete","fit.jls"),"changed after relocation")
        @test P.review(plan,again).counts[:artifact_review_required]==1
    end
end
end
