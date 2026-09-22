using Test, Statistics, Random, SHA
include(joinpath(@__DIR__,"..","scripts","mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
const P=E.P
root,output=ARGS
independent=(;status=:declared_independent,evidence="Arithmetic fixture assumption, not fitted CV evidence")
unknown=(;status=:unresolved,evidence="Independent streams not reviewed")
body(x)=Base.structdiff(x,(;content_hash=nothing))
records=NamedTuple[]

@testset "Exact chain curvature detects a vanishing linear term" begin
    ps=[.4,.6,.45,.55]
    logs=cat([reshape(log.([p;(1-p)/3;(1-p)/3;(1-p)/3]),1,1,4) for p in ps]...;dims=1)
    truth=permutedims(log.([.5,1/6,1/6,1/6]))
    curve=E.predictive_curvature(logs,truth;categories=[1],weights=[1.])
    nll,catloss,expected,kl=curve.rows
    @test nll.pooled_loss≈log(2)
    @test nll.chain_losses≈-log.(ps)
    @test nll.linear_changes≈-2 .* (ps.-.5)
    @test nll.remainders≈-log.(ps).+log(.5).+2 .* (ps.-.5)
    @test nll.observed_jensen_gap≈mean(-log.(ps))-log(2)
    @test catloss.pooled_loss≈0. atol=1e-30
    @test maximum(abs,catloss.linear_changes)<1e-15
    @test catloss.remainders≈(4/3).*(ps.-.5).^2 atol=1e-15
    @test expected.remainders≈4 .* (ps.-.5).^2 atol=1e-15
    @test catloss.observed_jensen_gap>0 && expected.observed_jensen_gap>0 && kl.observed_jensen_gap>0
    @test !curve.bias_bound_available && !curve.curvature_adequacy_assessed
    permuted=E.predictive_curvature(logs[[3,1,4,2],:,:],truth;categories=[1],weights=[1.])
    @test getproperty.(permuted.rows,:observed_jensen_gap)≈getproperty.(curve.rows,:observed_jensen_gap)
    small=cat([reshape(log.([.5+.001*(p-.5);fill((.5-.001*(p-.5))/3,3)]),1,1,4) for p in ps]...;dims=1)
    tiny=E.predictive_curvature(small,truth;categories=[1],weights=[1.])
    @test tiny.rows[2].observed_jensen_gap≈1e-6catloss.observed_jensen_gap rtol=1e-9
    invalid=copy(logs);invalid[1,1,:]=[-Inf,-log(3),-log(3),-log(3)]
    nonfinite=E.predictive_curvature(invalid,truth;categories=[1],weights=[1.])
    @test nonfinite.rows[1].status===:nonfinite_curvature
    @test_throws ArgumentError E.predictive_curvature(logs[1:1,:,:],truth;categories=[1],weights=[1.])
    push!(records,(;case="vanishing_linearization",curvature=curve))
end

old="results/workflows/20260921-core-loss-summary-01/inputs"
files=(;generation="generation.json",raw_truth="raw-truth.json",truth="truth.json",observed="observed.json")
hashes(dir)=map(name -> P.digest(joinpath(dir,name)),files)
generation=P.readjson(joinpath(old,"R0-1","generation.json"))
ids=["a","b","c","failed","absent"]
plans=[E.evaluation_plan(c==0 ? ids : reverse(ids);mode=:recovery,condition="R$c",backend=:advancedhmc,
    generator_sha256=generation.generator_sha256) for c in 0:1]
inputs=[[E.bind_panel(plans[c+1],ids[i];directory=joinpath(old,"R$c-$i"),hashes=hashes(joinpath(old,"R$c-$i"))) for i in 1:3] for c in 0:1]
splits=[[E.bind_folds(plans[c],inputs[c][i];seed=9250100+i) for i in 1:3] for c in 1:2]
function fixture(c,i;split=splits[c][i])
    input=inputs[c][i];data=P.observation_data(input.observed)
    loss=(c==1 ? [1.,2.,4.] : [2.,4.,4.5])[i]
    logs=zeros(1250,4)
    for n in 1:1250
        logs[n,:].=log((1-exp(-loss))/3)
        logs[n,data.category[n]]=-loss
    end
    folds=[E.seal((;id=input.id,fold=f.fold,split_identity=split.content_hash,
        reference=(;sha256=bytes2hex(sha256("CV arithmetic $c $i $(f.fold)")),seed=9251000+100c+10i+f.fold),
        qualification=(;qualified=true),heldout_observations=f.heldout_observations,status=:prepared,
        log_probabilities=logs[f.heldout_observations,:],heldout_provenance_verified=true,n_prediction_draws=4000,
        monte_carlo_error=(;rows=[(;metric,estimate=0.,status=:first_order_candidate,mcse=.0001,diagnostic=(;flag=:ok)) for metric in E.LOSS_METRICS],
            n_prediction_draws=4000,n_chains=4,weighting=:global_equal_person_equal_dimension,
            curvature=(;rows=[(;metric,observed_jensen_gap=.00001) for metric in E.LOSS_METRICS])))) for f in split.folds.fold_rows]
    return E.prepare_cv_dataset(plans[c],input,split,folds;fold_independence=independent)
end
attempts=[[fixture(c,i) for i in 1:3] for c in 1:2]
failed=E.failure(plans[1],"failed",:generation_error;detail="Controlled missing dataset")
metric=E.LOSS_METRICS[1]

@testset "CV replication, pair covariance, failed denominator and numerical limits" begin
    summary=E.summarize_cv(plans[1],[attempts[1];failed];metric,dataset_independence=independent,mcmc_independence=independent)
    @test (summary.planned,summary.descriptive_complete,summary.unresolved)==(5,3,2)
    @test summary.descriptive_mean≈7/3
    @test summary.descriptive_replication_mcse≈std([1.,2.,4.])/sqrt(3)
    @test summary.combined_first_order_mcse≈sqrt(15)*.0001/3
    @test summary.all_attempt_mean_bounds[1]≈7/5 && ismissing(summary.all_attempt_mean_bounds[2])
    @test summary.rows[4].status===:generation_error && summary.rows[5].status===:missing_attempt
    @test summary.rows[1].observed_jensen_gap≈.00005
    paired=E.paired_cv(plans[1],[attempts[1];failed],plans[2],reverse(attempts[2]);metric,
        dataset_independence=independent,mcmc_independence=independent)
    @test paired.descriptive_mean≈mean([1.,2.,.5])
    @test paired.descriptive_replication_mcse≈std([1.,2.,.5])/sqrt(3)
    @test paired.combined_first_order_mcse≈sqrt(30)*.0001/3
    @test all(ismissing,paired.all_attempt_mean_bounds)
    @test paired.numerical_budget.absolute_mcse_screen===:within_proposed_budget
    @test paired.numerical_budget.relative_mcse_screen===:within_proposed_budget
    @test !paired.numerical_precision_accepted && !paired.numerical_budget.policy.adopted
    @test !paired.all_attempt_mean_available
    no_mc=E.paired_cv(plans[1],attempts[1],plans[2],attempts[2];metric,dataset_independence=independent)
    @test ismissing(no_mc.combined_first_order_mcse) && isfinite(no_mc.descriptive_replication_mcse)
    no_rep=E.summarize_cv(plans[1],attempts[1];metric,dataset_independence=unknown,mcmc_independence=independent)
    @test ismissing(no_rep.descriptive_replication_mcse) && isfinite(no_rep.combined_first_order_mcse)
    one=E.paired_cv(plans[1],attempts[1][1:1],plans[2],attempts[2][1:1];metric,dataset_independence=independent)
    @test ismissing(one.descriptive_replication_mcse)
    for (metric,bound) in ((:squared_category_probability_error,2.),(:squared_expected_score_error,9.))
        empty=E.paired_cv(plans[1],[],plans[2],[];metric,dataset_independence=independent)
        @test empty.all_attempt_mean_bounds==(-bound,bound) && ismissing(empty.descriptive_mean)
        half=E.paired_cv(plans[1],attempts[1],plans[2],attempts[2];metric,dataset_independence=independent)
        @test all(isapprox.(half.all_attempt_mean_bounds,((3half.descriptive_mean-2bound)/5,(3half.descriptive_mean+2bound)/5)))
    end
    high=E.cv_budget_report(E.LOSS_METRICS[1],.01,.02)
    @test high.absolute_mcse_screen===high.relative_mcse_screen===:exceeds_proposed_budget
    @test E.cv_budget_report(metric,.0001,0.).relative_mcse_screen===:unresolved
    @test E.cv_precision_proposal().geometric_probability_factor≈exp(.005)
    push!(records,(;case="arithmetic_only_paired_CV",summary,paired))
end

@testset "Reject leakage, split/ID mismatch, reused fits and altered summaries" begin
    @test_throws ArgumentError E.summarize_cv(plans[1],[attempts[1];attempts[1][1]];metric,dataset_independence=independent)
    @test_throws ArgumentError E.cv_dataset_ledger(plans[2],attempts[1];metric)
    r=attempts[1][1]
    partial=E.prepare_cv_dataset(plans[1],r.input,r.split,r.fold_attempts[1:4];fold_independence=independent)
    @test E.summarize_cv(plans[1],[partial];metric,dataset_independence=independent).descriptive_complete==0
    @test E.cv_dataset_ledger(plans[1],[partial];metric)[1].status===:incomplete
    changed=E.seal(merge(body(r),(;result=merge(r.result,(;score=nothing)))))
    @test_throws ArgumentError E.cv_dataset_ledger(plans[1],[changed];metric)
    other=E.bind_folds(plans[2],inputs[2][1];seed=9250999)
    wrong=fixture(2,1;split=other)
    @test_throws ArgumentError E.paired_cv(plans[1],attempts[1][1:1],plans[2],[wrong];metric,dataset_independence=independent)
    b=attempts[2][1];folds=copy(b.fold_attempts)
    folds[1]=E.seal(merge(body(folds[1]),(;reference=merge(folds[1].reference,(;seed=r.fold_attempts[1].reference.seed)))))
    reused=E.prepare_cv_dataset(plans[2],b.input,b.split,folds;fold_independence=independent)
    @test_throws ArgumentError E.paired_cv(plans[1],attempts[1][1:1],plans[2],[reused];metric,dataset_independence=independent)
    folds=copy(r.fold_attempts)
    err=folds[1].monte_carlo_error
    details=[merge(x,(;diagnostic=(;flag=:warning))) for x in err.rows]
    folds[1]=E.seal(merge(body(folds[1]),(;monte_carlo_error=merge(err,(;rows=details)))))
    bad=E.prepare_cv_dataset(plans[1],r.input,r.split,folds;fold_independence=independent)
    rejected=E.summarize_cv(plans[1],[bad];metric,dataset_independence=independent,mcmc_independence=independent)
    @test rejected.descriptive_complete==1 && ismissing(rejected.combined_first_order_mcse)
    @test !rejected.rows[1].quantity_diagnostics_passed
end

P.writejson(output,(;records,tests_passed=true,new_sampler_runs=0,cv_refits=0,
    formal_recovery_replications=0,scientific_acceptance=false,scope=:finite_arithmetic_fixtures))
