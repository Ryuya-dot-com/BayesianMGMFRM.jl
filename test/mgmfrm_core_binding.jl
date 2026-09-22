using Test, Random, Statistics, JSON3
include(joinpath(@__DIR__,"..","scripts","mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
const P=E.P
const B=E.B
const V=E.V
root=first(ARGS)
output=length(ARGS)==2 ? ARGS[2] : joinpath(root,"binding-tests.json")
old="results/workflows/20260921-core-generator-01"
files=(;generation="generation.json",raw_truth="raw-truth.json",truth="truth.json",observed="observed.json")
hashes(dir)=map(name -> P.digest(joinpath(dir,name)),files)
directory=joinpath(old,"fixed")
generation=P.readjson(joinpath(directory,"generation.json"))
plan=E.evaluation_plan(["pilot","failed","missing","alias"];mode=:fixed,backend=:advancedhmc,
    generator_sha256=generation.generator_sha256)
input=E.bind_panel(plan,"pilot";directory,hashes=hashes(directory))
cache=joinpath(old,"pilot-01","advancedhmc","fit.jls")
pilot=P.readjson(joinpath(dirname(cache),"result.json"))
reference=(;path=cache,sha256=String(pilot.cache_sha256),seed=9220101)
records=NamedTuple[]
body(x)=Base.structdiff(x,(;content_hash=nothing))
replacefit(fit;kwargs...)=B.MGMFRMFit((get(kwargs,k,getfield(fit,k)) for k in fieldnames(B.MGMFRMFit))...)

@testset "Bind all generating files before model validation" begin
    @test E.checked_panel(plan,input) === input
    @test !plan.execution_allowed
    @test_throws ArgumentError E.bind_panel(plan,"unplanned";directory,hashes=hashes(directory))
    @test_throws ArgumentError E.bind_panel(plan,"pilot";directory,hashes=merge(hashes(directory),(;truth="0"^64)))
    @test_throws ArgumentError E.checked_panel(merge(plan,(;backend=:cmdstan)),input)
    @test_throws ArgumentError E.checked_panel(plan,merge(input,(;id="alias")))
    @test_throws ArgumentError E.evaluation_plan(["x","x"];mode=:fixed,backend=:advancedhmc,generator_sha256=generation.generator_sha256)
    priorplan=E.evaluation_plan(["prior"];mode=:prior,backend=:advancedhmc,generator_sha256=generation.generator_sha256)
    @test_throws ArgumentError E.bind_panel(priorplan,"prior";directory,hashes=hashes(directory))
    mktempdir() do dir
        for file in values(files); cp(joinpath(directory,file),joinpath(dir,file));end
        obs=JSON3.read(read(joinpath(dir,"observed.json"),String),Dict{String,Any})
        tr=JSON3.read(read(joinpath(dir,"truth.json"),String),Dict{String,Any})
        receipt=JSON3.read(read(joinpath(dir,"generation.json"),String),Dict{String,Any})
        foreach(r -> r["score"]=4,obs["observations"])
        tr["log_likelihood"]=sum(row[4] for row in tr["log_probabilities"])
        # Deliberately edited input fixture, not a new generator realization.
        write(joinpath(dir,"observed.json"),JSON3.write(obs));write(joinpath(dir,"truth.json"),JSON3.write(tr))
        @test_throws ArgumentError E.bind_panel(plan,"failed";directory=dir,hashes=hashes(dir))
        receipt["observed_categories"]=[4]
        write(joinpath(dir,"generation.json"),JSON3.write(receipt))
        single=E.bind_panel(plan,"failed";directory=dir,hashes=hashes(dir))
        @test Set(P.observation_data(single.observed).score)==Set([4])
        @test_throws ArgumentError P.specification(single.observed;require_all_categories=false)
        failure=E.failure(plan,"failed",:fit_error;detail="single_observed_category input fixture",input=single)
        ledger=E.attempt_ledger(plan,[failure])
        @test ledger[2].status===:fit_error
        @test count(r -> r.status===:missing_attempt,ledger)==3
        @test_throws ArgumentError E.failure(plan,"failed",:fit_error;detail="missing input")
    end
end

@testset "Full-cache hash and actual data/prior/seed/coordinate binding" begin
    @test_throws ArgumentError E.read_fit(merge(reference,(;sha256="0"^64)))
end
fit=E.read_fit(reference)
checked=E.check_fit(plan,input,fit;seed=reference.seed)

@testset "Reject swapped data, prior, seeds, coordinates and raw/direct mismatch" begin
    @test checked.direct≈fit.direct_draws atol=1e-12
    @test_throws ArgumentError E.check_fit(plan,input,fit;seed=reference.seed+1)
    badprior=B._source_fixture_prior(B.Experimental.GeneralizedPrior(;person_sd=2.))
    @test_throws ArgumentError E.check_fit(plan,input,replacefit(fit;prior=badprior);seed=reference.seed)
    @test_throws ArgumentError E.check_fit(plan,input,replacefit(fit;backend=:cmdstan);seed=reference.seed)
    badnames=merge(fit.diagnostic_surface,(;raw_parameter_names=reverse(fit.diagnostic_surface.raw_parameter_names)))
    @test_throws ArgumentError E.check_fit(plan,input,replacefit(fit;diagnostic_surface=badnames);seed=reference.seed)
    direct=copy(fit.direct_draws);direct[1,1]+=1.
    @test_throws ArgumentError E.check_fit(plan,input,replacefit(fit;direct_draws=direct);seed=reference.seed)
    raw=copy(fit.draws);raw[1,1]=NaN
    @test_throws ArgumentError E.check_fit(plan,input,replacefit(fit;draws=raw);seed=reference.seed)
    @test_throws ArgumentError E.check_fit(plan,input,fit;seed=reference.seed,training_rows=collect(1:1000))
    wrongtruth=JSON3.read(JSON3.write(input.truth),Dict{String,Any})
    wrongtruth["raw"][1]+=1.
    changed=E.seal(merge(body(input),(;truth=JSON3.read(JSON3.write(wrongtruth)))))
    @test_throws ArgumentError E.check_fit(plan,changed,fit;seed=reference.seed)
    source=joinpath(old,"prior-1")
    pp=E.evaluation_plan(["prior"];mode=:prior,backend=:advancedhmc,
        generator_sha256=P.readjson(joinpath(source,"generation.json")).generator_sha256)
    pi=E.bind_panel(pp,"prior";directory=source,hashes=hashes(source))
    @test_throws ArgumentError E.check_fit(pp,pi,fit;seed=reference.seed)
    rng=MersenneTwister(9232401);untouched=copy(rng)
    @test_throws ArgumentError E.prepare_sbc(plan,input,reference;
        dependence=(;status=:declared_independent,evidence="test declaration"),rank_rng=rng)
    @test rand(rng)==rand(untouched)
end

@testset "Recomputed diagnostics catch tampering despite saved good flags" begin
    values=fit.draws[:,1:2];names=checked.target.blueprint.parameter_names[1:2]
    q=E.qualification(fit,checked,values,names)
    @test q.qualified
    stats=copy(fit.sampler_stats)
    stats[1]=merge(stats[1],(;numerical_error=true))
    divergent=E.qualification(replacefit(fit;sampler_stats=stats),checked,values,names)
    @test !divergent.qualified
    @test any(r -> r.reason===:divergences,divergent.failures)
    incomplete=E.qualification(replacefit(fit;sampler_stats=stats[2:end]),checked,values,names)
    @test !incomplete.qualified
    @test any(r -> r.reason===:incomplete_telemetry,incomplete.failures)
    degenerate=E.qualification(fit,checked,zeros(4000,1),["constant"])
    @test !degenerate.qualified
end

# Public cache-to-score path; this is replay of one fixed-truth engineering fit.
recovery=E.prepare_recovery(plan,input,reference)
@testset "Recovery retains named parameters, intervals and all planned slots" begin
    @test recovery.status===:prepared
    @test recovery.qualification.qualified && recovery.primary_precision_passed
    @test length(recovery.rows)==159 && count(r -> r.role===:primary,recovery.rows)==59
    @test count(r -> r.role===:secondary,recovery.rows)==100
    person=only(filter(r -> r.parameter=="person[P2,dim=1]",recovery.rows))
    p2=findfirst(==("P2"),P.PERSONS)
    @test person.truth==input.truth.raw[2p2-1]
    item=only(filter(r -> r.parameter=="b[I1]",recovery.rows))
    original=only(filter(r -> r.parameter=="b[I1]",pilot.rows))
    @test item.estimate≈original.estimate atol=1e-12
    @test item.mcse.mean_mcse≈original.mcse.mean_mcse atol=1e-12
    @test item.interval95.lower<=item.lower<=item.upper<=item.interval95.upper
    failed=E.failure(plan,"failed",:generation_error;detail="controlled failure fixture")
    summary=E.summarize_recovery(plan,[recovery,failed];parameter="b[I1]")
    @test (summary.planned,summary.usable,summary.unresolved)==(4,1,3)
    @test summary.all_attempt_coverage_bounds==(Int(item.covered)/4,(Int(item.covered)+3)/4)
    @test summary.bias_mcse===missing && !summary.all_attempt_continuous_scores_available
    @test summary.reasons[:generation_error]==1 && summary.reasons[:missing_attempt]==2
    @test E.summarize_recovery(plan,[recovery];parameter="b[I1]",interval=.95).conditional_mean_width≈item.interval95.width
    @test_throws ArgumentError E.summarize_recovery(plan,[recovery,recovery];parameter="b[I1]")
    @test_throws ArgumentError E.attempt_ledger(plan,[merge(recovery,(;status=:fit_error))])
    @test_throws ArgumentError E.attempt_ledger(plan,[E.seal(merge(body(recovery),(;status=:fit_error)))])
    aliasinput=E.bind_panel(plan,"alias";directory,hashes=hashes(directory))
    alias=E.seal(merge(body(recovery),(;id="alias",input=aliasinput)))
    @test_throws ArgumentError E.attempt_ledger(plan,[recovery,alias])
    push!(records,(;case="historical_fixed_truth_replay",parameters=length(recovery.rows),
        status=recovery.status,global_diagnostics=recovery.qualification.qualified,
        primary_precision=recovery.primary_precision_passed,formal_recovery_replications=0,
        missing_denominator_example=(;summary.planned,summary.usable,summary.unresolved)))
end

@testset "SBC ledger arithmetic with explicitly hand-constructed rank fixtures" begin
    source=joinpath(old,"prior-1")
    pp=E.evaluation_plan(["one","failed","missing"];mode=:prior,backend=:advancedhmc,
        generator_sha256=P.readjson(joinpath(source,"generation.json")).generator_sha256)
    pi=E.bind_panel(pp,"one";directory=source,hashes=hashes(source))
    target=P.target(P.specification(pi.observed;require_all_categories=false))
    truth=E.sbc_quantities(target,permutedims(Float64.(pi.truth.raw));parameter_names=pi.truth.raw_names)
    selected=repeat(truth.values,4)
    ranks=[merge((;parameter=name),V.randomized_rank(truth.values[1,j],selected[:,j],MersenneTwister(j)))
        for (j,name) in pairs(truth.names)]
    dependence=(;status=:declared_independent,evidence="arithmetic fixture only; no posterior draws")
    toy=E.seal((;id="one",plan_identity=pp.content_hash,kind=:sbc,status=:rank_prepared,input=pi,
        reference=(;sha256="1"^64),qualification=(;qualified=true,criteria=P.CRITERIA,failures=NamedTuple[]),dependence,ranks,names=truth.names,
        truth=vec(truth.values),selected_draws=selected))
    failed=E.failure(pp,"failed",:generation_error;detail="fixture")
    summary=E.summarize_sbc(pp,[toy,failed];dataset_independence=dependence)
    @test (summary.planned,summary.usable)==(3,1)
    @test length(summary.cdfs)==138
    @test all(r -> r.cdf.planned==3 && r.cdf.unresolved==2,summary.cdfs)
    unresolved=(;status=:unresolved,evidence="independence is not established by these fixtures")
    held=E.summarize_sbc(pp,[toy];dataset_independence=unresolved)
    @test all(r -> r.cdf.epsilon===missing && r.cdf.conditional_screen===:assumptions_unresolved,held.cdfs)
    bad=E.seal(merge(body(toy),(;status=:dependence_unresolved,dependence=unresolved,ranks=nothing)))
    @test E.summarize_sbc(pp,[bad];dataset_independence=dependence).usable==0
    @test_throws ArgumentError E.summarize_sbc(pp,[E.seal(merge(body(bad),(;ranks)))];dataset_independence=dependence)
    badranks=copy(ranks);badranks[1]=merge(badranks[1],(;rank=5))
    @test_throws ArgumentError E.summarize_sbc(pp,[E.seal(merge(body(toy),(;ranks=badranks)))];dataset_independence=dependence)
    @test E.summarize_sbc(pp,[failed];dataset_independence=dependence).status===:no_prepared_quantities
    @test !summary.calibration_verified && !summary.scientific_acceptance
end

split=E.bind_folds(plan,input;seed=9219101)
@testset "Fold provenance rejects full-data leakage; missing folds stay unresolved" begin
    @test split.folds.n_folds==5
    @test all(r -> length(r.training_observations)==1000 && length(r.heldout_observations)==250,split.folds.fold_rows)
    @test_throws ArgumentError E.check_fit(plan,input,fit;seed=reference.seed,
        training_rows=split.folds.fold_rows[1].training_observations)
    @test_throws ArgumentError E.checked_folds(plan,input,merge(split,(;seed=1)))
    empty=E.assemble_cv(plan,input,split,NamedTuple[])
    @test empty.status===:incomplete && empty.score===nothing && empty.usable_folds==0
    failure=E.fold_failure(plan,input,split,1,:timeout;detail="controlled failure")
    @test E.assemble_cv(plan,input,split,[failure]).ledger[1].status===:timeout
    @test_throws ArgumentError E.assemble_cv(plan,input,split,[failure,failure])
    # Only assembly arithmetic is exercised by these handmade probability rows.
    # They do not represent actual heldout fits or scientific CV evidence.
    logs=reduce(vcat,permutedims.(Vector{Float64}.(input.truth.log_probabilities)))
    fixtures=[E.seal((;id=input.id,fold=f.fold,split_identity=split.content_hash,
        reference=(;sha256=string(f.fold)^64),qualification=(;qualified=true),
        heldout_observations=f.heldout_observations,status=:prepared,
        log_probabilities=logs[f.heldout_observations,:],heldout_provenance_verified=true,
        n_prediction_draws=4000)) for f in split.folds.fold_rows]
    allfolds=E.assemble_cv(plan,input,split,reverse(fixtures))
    @test allfolds.status===:assembled && allfolds.usable_folds==5
    @test allfolds.score.summary.squared_category_probability_error==0.
    @test !allfolds.monte_carlo_precision_assessed && !allfolds.scientific_acceptance
    partial=E.assemble_cv(plan,input,split,fixtures[1:4])
    @test partial.status===:incomplete && partial.score===nothing && partial.usable_folds==4
    duplicate=copy(fixtures);duplicate[2]=E.seal(merge(body(duplicate[2]),(;reference=fixtures[1].reference)))
    @test_throws ArgumentError E.assemble_cv(plan,input,split,duplicate)
    wrong=E.seal(merge(body(fixtures[1]),(;heldout_observations=split.folds.fold_rows[2].heldout_observations)))
    @test_throws ArgumentError E.assemble_cv(plan,input,split,[wrong])
end

@testset "Batched heldout log prediction matches independent truth and finite support" begin
    target=checked.target
    raw=Float64.(input.truth.raw)
    direct=B._mgmfrm_source_constrained_params_from_unconstrained(target.design,raw)
    oracle=reduce(vcat,permutedims.(Vector{Float64}.(input.truth.log_probabilities)))
    score_design=B._loo_refit_score_design(target.design.spec.data,target.design,split.folds.fold_rows[1].heldout_observations)
    # The score design is deliberately a subset; raw coordinate meanings stay fixed.
    logs=E.mean_log_probabilities(score_design,repeat(permutedims(direct),3);batch_size=2)
    @test logs≈oracle[split.folds.fold_rows[1].heldout_observations,:] atol=1e-12
    single=B._loo_refit_score_design(target.design.spec.data,target.design,[1])
    @test E.mean_log_probabilities(single,permutedims(direct))≈oracle[1:1,:] atol=1e-12
    varied=fit.direct_draws[1:5,:]
    p=B._mgmfrm_predictive_probabilities_direct(target.design,varied)
    @test E.mean_log_probabilities(target.design,varied;batch_size=2)≈log.(dropdims(mean(p;dims=1);dims=1)) atol=1e-12
    raw[1]=1000.
    extreme=B._mgmfrm_source_constrained_params_from_unconstrained(target.design,raw)
    logs=E.mean_log_probabilities(target.design,permutedims(extreme))
    @test all(isfinite,logs) && minimum(logs)<-1000
    @test_throws ArgumentError E.mean_log_probabilities(target.design,permutedims(extreme);batch_size=0)
end

@testset "All retained data-dependent quantities agree with the saved fit" begin
    quantities=E.sbc_quantities(checked.target,fit.draws;parameter_names=input.truth.raw_names)
    @test size(quantities.values)==(4000,138)
    @test quantities.values[:,end]≈fit.direct_loglikelihood atol=1e-8 rtol=1e-12
    selected=E.sbc_rank_draws(checked.target,fit.draws;parameter_names=input.truth.raw_names,fit.chain_ids,fit.iterations)
    @test selected.selected_rows==[1000,2000,3000,4000]
    @test selected.values==quantities.values[selected.selected_rows,:]
    @test !selected.joint_prior_binding_verified
end

P.writejson(joinpath(root,"recovery-replay.json"),(;id=input.id,mode=plan.mode,reference,
    rows=recovery.rows,qualification=recovery.qualification,primary_precision_passed=recovery.primary_precision_passed,
    status=recovery.status,new_sampler_runs=0,formal_recovery_replications=0,scientific_acceptance=false))
P.writejson(output,(;records,tests_passed=true,julia_version=string(VERSION),
    rank_and_complete_cv_checks=:hand_constructed_arithmetic_fixtures,
    actual_saved_fit_replays=1,new_sampler_runs=0,formal_sbc_replications=0,cv_refits=0,scientific_acceptance=false))
