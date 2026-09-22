using Test, JSON3
include(joinpath(@__DIR__,"..","scripts","mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
const P=E.P
const B=E.B
root,output=ARGS
files=(;generation="generation.json",raw_truth="raw-truth.json",truth="truth.json",observed="observed.json")
hashes(dir)=map(name -> P.digest(joinpath(dir,name)),files)
old="results/workflows/20260921-core-generator-01"
generation=P.readjson(joinpath(old,"fixed","generation.json"))
ids=["ordinary","c1","c2","c3","c4","gap","absent"]
fixed=E.evaluation_plan(ids;mode=:fixed,backend=:advancedhmc,generator_sha256=generation.generator_sha256)
prior=E.evaluation_plan(ids;mode=:prior,backend=:advancedhmc,generator_sha256=generation.generator_sha256)
ordinary=E.bind_panel(fixed,"ordinary";directory=joinpath(old,"fixed"),hashes=hashes(joinpath(old,"fixed")))
records=NamedTuple[]

function edited_input(plan,id,change)
    source=joinpath(old,plan.mode===:prior ? "prior-1" : "fixed")
    directory=joinpath(root,"fixtures",String(plan.mode)*"-"*id)
    ispath(directory) && error("Do not overwrite boundary fixtures")
    mkpath(directory)
    content=map(file -> JSON3.read(read(joinpath(source,file),String),Dict{String,Any}),files)
    obs,tr,receipt=content.observed,content.truth,content.generation
    foreach(r -> r["score"]=change(r["score"]),obs["observations"])
    tr["log_likelihood"]=sum(p[r["score"]] for (p,r) in zip(tr["log_probabilities"],obs["observations"]))
    receipt["observed_categories"]=sort(unique(r["score"] for r in obs["observations"]))
    receipt["fixture_scope"]="Deliberately edited scores, not a new random joint-prior realization"
    for name in keys(files);P.writejson(joinpath(directory,getproperty(files,name)),getproperty(content,name));end
    return E.bind_panel(plan,id;directory,hashes=hashes(directory))
end

@testset "Single-category rejection is a retained interface boundary" begin
    ready=E.input_preflight(fixed,ordinary)
    @test ready.passed && ready.failure===nothing && ready.new_sampler_runs==0
    @test ready.declared_categories==ready.observed_categories==[1,2,3,4]
    @test !ready.posterior_propriety_assessed && !ready.scientific_acceptance
    inputs=[edited_input(fixed,"c$k",_ -> k) for k in 1:4]
    failures=NamedTuple[]
    for (k,input) in enumerate(inputs)
        before=input.content_hash
        preflight=E.input_preflight(fixed,input)
        data=P.observation_data(input.observed)
        audit=B.ordinal_response_pattern_audit(data)
        @test !preflight.passed && preflight.failure.status===:pre_fit_rejected
        @test :single_observed_category in [i.code for i in preflight.issues if i.severity===:error]
        @test preflight.declared_categories==[1,2,3,4] && preflight.observed_categories==[k]
        @test preflight.failure.input.content_hash==before && input.content_hash==before
        @test audit.fit_prohibited && audit.interpretation.global_single_category===:unsupported_by_current_fit_validation
        @test !audit.interpretation.posterior_propriety_assessed
        @test_throws ArgumentError P.specification(input.observed;require_all_categories=false)
        # The finite score of this outcome exists even though the fit API rejects it.
        @test isfinite(input.truth.log_likelihood)
        push!(failures,preflight.failure)
        push!(records,(;case="single_category_$k",preflight))
    end
    ledger=E.attempt_ledger(fixed,failures)
    @test count(r -> r.status===:pre_fit_rejected,ledger)==4
    @test count(r -> r.status===:missing_attempt,ledger)==3
    recovery=E.summarize_recovery(fixed,failures;parameter="b[I1]")
    @test recovery.planned==7 && recovery.usable==0 && recovery.unresolved==7
    @test recovery.reasons[:pre_fit_rejected]==4 && recovery.all_attempt_coverage_bounds==(0.,1.)
    @test E.summarize_cv(fixed,failures;metric=E.LOSS_METRICS[1],
        dataset_independence=(;status=:unresolved,evidence="No dataset experiment")).unresolved==7
    gap=edited_input(fixed,"gap",k -> k==3 ? 2 : k)
    checked=E.input_preflight(fixed,gap)
    @test checked.passed && checked.failure===nothing && checked.observed_categories==[1,2,4]
    @test :unused_interior_category in [i.code for i in checked.issues]
    @test P.specification(gap.observed;require_all_categories=false).data.category_levels==[1,2,3,4]
    @test_throws ArgumentError E.input_preflight(prior,ordinary)
    @test_throws ArgumentError E.failure(fixed,"c1",:pre_fit_rejected;detail="Missing bound input")
    @test_throws ArgumentError E.input_preflight(fixed,ordinary;fold=1)
    @test_throws ArgumentError E.input_preflight(fixed,merge(ordinary,(;id="c1")))
end

@testset "Training-fold rejection keeps all five slots" begin
    input=E.bind_panel(fixed,"c1";directory=joinpath(root,"fixtures","fixed-c1"),hashes=hashes(joinpath(root,"fixtures","fixed-c1")))
    split=E.bind_folds(fixed,input;seed=9260101)
    checks=[E.input_preflight(fixed,input;split,fold) for fold in 1:5]
    @test all(c -> !c.passed && c.failure.status===:pre_fit_rejected && length(c.training_rows)==1000,checks)
    @test all(c -> c.declared_categories==[1,2,3,4] && c.observed_categories==[1],checks)
    assembled=E.assemble_cv(fixed,input,split,[c.failure for c in checks];
        fold_independence=(;status=:unresolved,evidence="No fold fits"))
    @test assembled.status===:incomplete && assembled.planned_folds==5 && assembled.usable_folds==0
    @test assembled.score===nothing && all(r -> r.status===:pre_fit_rejected,assembled.ledger)
    @test_throws ArgumentError E.input_preflight(fixed,input;split,fold=6)
    @test_throws ArgumentError E.input_preflight(fixed,input;split,fold=true)
    @test_throws ArgumentError E.input_preflight(fixed,ordinary;split,fold=1)
    push!(records,(;case="all_training_folds_rejected",assembled))
end

@testset "SBC preserves the original roster without implying calibration" begin
    input=edited_input(prior,"c4",_ -> 4)
    preflight=E.input_preflight(prior,input)
    summary=E.summarize_sbc(prior,[preflight.failure];
        dataset_independence=(;status=:declared_independent,evidence="Arithmetic fixture only"))
    @test summary.planned==7 && summary.usable==0 && summary.cdfs===nothing
    @test summary.ledger[5].status===:pre_fit_rejected
    @test summary.interpretation===:exploratory_error_detection && !summary.calibration_verified
    ranks=Union{Missing,Int}[zeros(Int,60);fill(missing,40)]
    cdf=E.V.rank_cdf(ranks;n_draws=4,n_quantities=138)
    @test cdf.planned==100 && cdf.usable==60 && cdf.unresolved==40
    @test cdf.rows[1].lower==.6 && cdf.rows[1].upper==1. && cdf.rows[1].resolved_departure
    @test !cdf.calibration_verified && !cdf.scientific_acceptance
    push!(records,(;case="SBC_failure_ledger_and_partial_identification",summary,cdf))
end

P.writejson(output,(;records,tests_passed=true,scope=:sampler_free_input_boundary_fixtures,
    new_sampler_runs=0,formal_sbc_replications=0,cv_refits=0,scientific_acceptance=false))
