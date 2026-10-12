# Read-only replay of existing full-data diagnostics; never generates posterior draws.
using Test, JSON3, Serialization
include(joinpath(@__DIR__,"../scripts/run_mgmfrm_foundation_prediction.jl"))
const W=MGMFRMFoundationPredictionRun
const B=W.B
const F=W.F
length(ARGS)==2 || error("usage: mgmfrm_foundation_prediction_run.jl ASSESSMENT_ROOT NEW_RECEIPT")
root,output=ARGS
ispath(output) && error("New output required")
input=joinpath(root,"inputs","B01-R0.json")
old=joinpath(root,"attempts","B01-R0-050")
p=F.prepare(input)
record=open(deserialize,joinpath(old,"samples.jls"))
checked=B._restore_mgmfrm_normalized_prior_samples(record;expected_identity=record.target_identity)
roster=String.(W.readjson(joinpath(W.REPO,W.readjson(joinpath(root,"plan.json")).roster)))
oldcore=W.readjson(joinpath(old,"core","review.json"))
oldextra=W.readjson(joinpath(old,"extra.json"))
oldloading=W.readjson(joinpath(old,"loading-review.json"))
review=W.geometry(p.target,p.target,record,checked,roster)

@testset "Prediction diagnostic review preserves original full-fit evidence" begin
    @test review.qualified===true
    @test review.core_qualified===oldcore.qualified
    @test review.original_gate===oldcore.original_gate
    @test length(review.focal)==150 && length(review.extra)==116
    @test [r.parameter for r in review.focal]==String.(oldcore.names)
    for (actual,expected) in zip(review.focal,oldcore.focal)
        @test String(actual.flag)==expected.flag
        @test actual.rank_normalized_rhat≈expected.rank_normalized_rhat
    end
    for (actual,expected) in zip(review.extra[1:111],oldextra.rows)
        @test actual.parameter==expected.parameter
        @test actual.local_precision_passed==expected.local_precision_passed
        @test actual.precision.mean_mcse≈expected.precision.mean_mcse
    end
    for (actual,expected) in zip(review.extra[112:116],oldloading.rows)
        @test actual.parameter==expected.parameter
        @test actual.precision.mean_mcse≈expected.precision.mean_mcse
        @test actual.local_precision_passed
    end
    panel=W.C.prepare(input,F.digest(input);split_seed=20261006100001)
    training=W.C.fold_context(panel,1,.5)
    @test_throws "Review target differs" W.geometry(p.target,training.target,record,checked,roster)
    wrong=merge(record,(;run=merge(record.run,(;checked=merge(record.run.checked,(;rhat_threshold=1.1))))))
    @test_throws "Diagnostic policy mismatch" W.geometry(p.target,p.target,wrong,checked,roster)
    full_context=(;binding=W.E.seal((;target_identity=record.target_identity,prior=record.prior)))
    positive=W.C.check_fit(full_context,record;seed=record.run.controls.rng.seed)
    @test positive.record.target_identity==record.target_identity
    @test length(positive.warmup_diagnostics)==4
    @test_throws "Fit controls/seed differ" W.C.check_fit(full_context,record;seed=record.run.controls.rng.seed+1)
    c=W.cpu_seconds()
    @test isfinite(sum(sin(i) for i in 1:100000))
    @test W.cpu_seconds()>c
end

W.save(output,(;status=:passed,posterior_fits=0,independent_evaluation_credit=0,
    old_samples_sha256=F.digest(joinpath(old,"samples.jls")),review,
    script_sha256=F.digest(joinpath(@__DIR__,"../scripts/run_mgmfrm_foundation_prediction.jl")),
    test_sha256=F.digest(@__FILE__),scientific_acceptance=false,
    scope=:full_fit_diagnostic_replay_not_training_posterior_evidence))
