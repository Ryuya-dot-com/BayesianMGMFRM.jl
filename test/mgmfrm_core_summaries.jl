using Test, Random, Statistics, JSON3, SHA
include(joinpath(@__DIR__,"..","scripts","mgmfrm_core_evaluation.jl"))
const E=MGMFRMCoreEvaluation
const P=E.P
const B=E.B
root,output=ARGS
records=NamedTuple[]
independent=(;status=:declared_independent,evidence="Explicit arithmetic-test assumption, not study evidence")
unresolved=(;status=:unresolved,evidence="No independent stream review")
body(x)=Base.structdiff(x,(;content_hash=nothing))
layout(n)=(;chain_ids=repeat(1:4;inner=n÷4),iterations=repeat(1:n÷4,4))
row(result,metric)=only(filter(r -> r.metric===metric,result.rows))
rng=MersenneTwister(9233301)
p=.15 .+ .2rand(rng,400)
draws=zeros(400,2,4)
for s in 1:400,n in 1:2
    draws[s,n,:]=log.([p[s],(1-p[s])/3,(1-p[s])/3,(1-p[s])/3])
end
truth=repeat(permutedims(log.([.4,.2,.2,.2])),2)
categories=[1,1]
weights=[.5,.5]
result=E.predictive_loss_mcse(draws,truth;categories,weights,layout(400)...)

@testset "Joint row influences: covariance, finite differences, chain order" begin
    average=dropdims(mean(exp.(draws);dims=1);dims=1)
    function losses(prob)
        q=exp.(truth)
        [sum(-weights[n]*log(prob[n,categories[n]]) for n in 1:2),
            sum(weights[n]*sum((prob[n,:]-q[n,:]).^2) for n in 1:2),
            sum(weights[n]*sum((1:4).*(prob[n,:]-q[n,:]))^2 for n in 1:2),
            sum(weights[n]*sum(q[n,:].*(truth[n,:]-log.(prob[n,:]))) for n in 1:2)]
    end
    @test getproperty.(result.rows,:estimate)≈losses(average) atol=1e-12
    for s in (1,19,221)
        direction=exp.(draws[s,:,:])-average
        epsilon=1e-5
        derivative=(losses(average+epsilon*direction)-losses(average-epsilon*direction))/(2epsilon)
        @test result.influence[s,:]≈derivative atol=1e-10 rtol=1e-6
    end
    @test result.influence[:,1]≈-(p./mean(p).-1) atol=1e-13
    single=E.predictive_loss_mcse(draws[:,1:1,:],truth[1:1,:];categories=[1],weights=[1.],layout(400)...)
    @test row(result,E.LOSS_METRICS[1]).mcse≈row(single,E.LOSS_METRICS[1]).mcse rtol=1e-12
    # Independent-row variance addition would incorrectly shrink this by sqrt(2).
    @test row(result,E.LOSS_METRICS[1]).mcse>1.4row(single,E.LOSS_METRICS[1]).mcse/sqrt(2)
    expected=only(B.posterior_mcse(reshape(-(p./mean(p).-1),:,1);chains=4,parameter_names=["analytic"],probabilities=()))
    @test row(result,E.LOSS_METRICS[1]).mcse≈expected.mean_mcse rtol=1e-12
    perm=randperm(rng,400);ids=layout(400)
    reordered=E.predictive_loss_mcse(draws[perm,:,:],truth;categories,weights,
        chain_ids=ids.chain_ids[perm],iterations=ids.iterations[perm])
    @test getproperty.(reordered.rows,:mcse)≈getproperty.(result.rows,:mcse) rtol=1e-11
    @test_throws ArgumentError E.predictive_loss_mcse(draws,truth;categories,weights,
        chain_ids=ids.chain_ids,iterations=ones(Int,400))
    scaled=E.predictive_loss_mcse(draws,truth;categories,weights=weights./5,layout(400)...)
    @test getproperty.(scaled.rows,:mcse)≈getproperty.(result.rows,:mcse)./5 rtol=1e-12
    @test getproperty.(scaled.rows,:estimate)≈getproperty.(result.rows,:estimate)./5 rtol=1e-12
    push!(records,(;case="perfect_row_dependence",joint_mcse=result.rows[1].mcse,
        incorrect_independent_row_mcse=result.rows[1].mcse/sqrt(2)))
end

@testset "Cancellation, short chains, zero support and finite log tails stay explicit" begin
    lm=first(B._mgmfrm_mean_predicted_probabilities(draws,1e-8;log_probabilities=true))
    exact=E.predictive_loss_mcse(draws,lm;categories,weights,layout(400)...)
    @test all(r -> r.status===:first_order_degenerate && ismissing(r.mcse),exact.rows[2:4])
    constant=E.predictive_loss_mcse(repeat(draws[1:1,:,:],400),truth;categories,weights,layout(400)...)
    @test all(r -> r.status===:first_order_degenerate,constant.rows)
    short=E.predictive_loss_mcse(draws[1:20,:,:],truth;categories,weights,layout(20)...)
    @test all(r -> ismissing(r.mcse),short.rows)
    extremes=zeros(400,1,4)
    for s in 1:400
        extremes[s,1,:]=[-1000+log(p[s]),-log(3),-log(3),-log(3)]
    end
    tail=E.predictive_loss_mcse(extremes,truth[1:1,:];categories=[1],weights=[1.],layout(400)...)
    @test tail.rows[1].estimate>1000 && isfinite(tail.rows[1].mcse)
    @test tail.rows[1].mcse≈result.rows[1].mcse rtol=1e-10
    extremes[:,1,1].=-Inf
    zero=E.predictive_loss_mcse(extremes,truth[1:1,:];categories=[1],weights=[1.],layout(400)...)
    @test zero.rows[1].status===zero.rows[4].status===:nonfinite_loss
    @test ismissing(zero.rows[1].mcse)
    @test_throws ArgumentError E.predictive_loss_mcse(draws,truth;categories,weights=[.5,-.5],layout(400)...)
    @test !result.precision_threshold_applied && result.curvature_review_required
end

files=(;generation="generation.json",raw_truth="raw-truth.json",truth="truth.json",observed="observed.json")
hashes(dir)=map(name -> P.digest(joinpath(dir,name)),files)
generation=P.readjson(joinpath(root,"inputs","R0-1","generation.json"))
ids=["a","b","c","d","e"]
plans=[E.evaluation_plan(c=="R0" ? ids : reverse(ids);mode=:recovery,condition=c,
    backend=:advancedhmc,generator_sha256=generation.generator_sha256) for c in ("R0","R1")]
inputs=[[E.bind_panel(plans[c],ids[i];directory=joinpath(root,"inputs","R$(c-1)-$i"),
    hashes=hashes(joinpath(root,"inputs","R$(c-1)-$i"))) for i in 1:3] for c in 1:2]

# Handmade recovery records exercise summaries only; they are NOT posterior fits.
function fixture(c,i)
    input=inputs[c][i];plan=plans[c]
    error=(c==1 ? [0.,1.,2.] : [1.,3.,2.])[i]
    names=["b[I1]";["person[$p,dim=$d]" for p in P.PERSONS for d in 1:2]]
    rows=map(names) do name
        index=findfirst(==(name),input.truth.raw_names)
        truth=name=="b[I1]" ? input.truth.raw[105] : input.truth.raw[index]
        err=endswith(name,"dim=2]") ? -error : error
        estimate=truth+err
        (;parameter=name,error=err,truth,estimate,lower=estimate-1,upper=estimate+1,
            covered=abs(err)<=1,width=2.,mcse=(;mcse_status=:available),local_precision_passed=true,
            interval95=(;lower=estimate-2,upper=estimate+2,covered=abs(err)<=2,width=4.))
    end
    return E.seal((;id=input.id,plan_identity=plan.content_hash,kind=:recovery,status=:prepared,input,
        qualification=(;criteria=plan.criteria,qualified=true,failures=[]),primary_precision_passed=true,
        reference=(;sha256=bytes2hex(sha256("arithmetic fixture $c/$i")),seed=9233400+10c+i),rows))
end
attempts=[[fixture(c,i) for i in 1:3] for c in 1:2]
failed=E.failure(plans[1],"d",:generation_error;detail="Controlled missing-pair fixture")
paired=E.paired_recovery(plans[1],[attempts[1];failed],plans[2],reverse(attempts[2]);
    parameter="b[I1]",dataset_independence=independent)

@testset "Pair before screening, preserve every ID, never pool persons as datasets" begin
    @test (paired.planned,paired.usable,paired.unresolved)==(5,3,2)
    @test getproperty.(paired.rows,:id)==ids
    @test paired.rows[4].R0_status===:generation_error && paired.rows[4].R1_status===:missing_attempt
    bias=only(filter(r -> r.metric===:bias,paired.statistics))
    @test bias.estimate==1. && bias.replication_mcse≈1/sqrt(3)
    @test paired.all_attempt_coverage_difference_bounds==(-.6,.2)
    @test paired.rmse_difference≈sqrt(14/3)-sqrt(5/3)
    rmse_influence=[1/(2sqrt(14/3)),9/(2sqrt(14/3))-1/(2sqrt(5/3)),4/(2sqrt(14/3))-4/(2sqrt(5/3))]
    @test paired.rmse_difference_replication_mcse≈std(rmse_influence)/sqrt(3)
    persons=E.summarize_person_dimension(plans[1],attempts[1];dimension=1,dataset_independence=independent)
    @test persons.usable==3 && persons.persons_per_dataset==50
    @test persons.statistics[1].replication_mcse≈1/sqrt(3)
    @test persons.rmse≈sqrt(5/3)
    @test persons.all_attempt_coverage_bounds==(.4,.8)
    p2=E.paired_recovery(plans[1],attempts[1],plans[2],attempts[2];dimension=2,dataset_independence=independent)
    @test p2.statistics[1].estimate==-1. && p2.statistics[1].replication_mcse≈1/sqrt(3)
    @test p2.statistics[2].estimate≈paired.statistics[2].estimate
    @test E.summarize_person_dimension(plans[1],attempts[1];dimension=1,interval=.95,
        dataset_independence=independent).statistics[3].estimate==1.
    unavailable=E.paired_recovery(plans[1],attempts[1],plans[2],attempts[2];dimension=1,dataset_independence=unresolved)
    @test all(r -> ismissing(r.replication_mcse),unavailable.statistics)
    @test ismissing(unavailable.rmse_difference_replication_mcse)
    singleton=E.paired_recovery(plans[1],attempts[1][1:1],plans[2],attempts[2][1:1];parameter="b[I1]",dataset_independence=independent)
    @test all(r -> ismissing(r.replication_mcse),singleton.statistics)
    empty=E.paired_recovery(plans[1],[],plans[2],[];dimension=1,dataset_independence=independent)
    @test empty.usable==0 && ismissing(empty.rmse_difference) && empty.all_attempt_coverage_difference_bounds==(-1.,1.)
    # One unavailable person invalidates the full dimension summary, not 49-person reweighting.
    badrows=copy(attempts[1][1].rows);badrows[2]=merge(badrows[2],(;local_precision_passed=false))
    bad=E.seal(merge(body(attempts[1][1]),(;rows=badrows)))
    dropped=E.summarize_person_dimension(plans[1],[bad;attempts[1][2:3]];dimension=1,dataset_independence=independent)
    @test dropped.usable==2 && dropped.rows[1].status===:mcse_unavailable
    @test_throws ArgumentError E.paired_recovery(plans[2],attempts[2],plans[1],attempts[1];dimension=1,dataset_independence=independent)
    bad=E.seal(merge(body(attempts[2][1]),(;reference=merge(attempts[2][1].reference,(;seed=attempts[1][1].reference.seed)))))
    @test_throws ArgumentError E.paired_recovery(plans[1],attempts[1],plans[2],[bad;attempts[2][2:3]];dimension=1,dataset_independence=independent)
    wronginput=E.seal(merge(body(inputs[2][2]),(;id="a")))
    bad=E.seal(merge(body(attempts[2][1]),(;input=wronginput)))
    @test_throws ArgumentError E.paired_recovery(plans[1],attempts[1][1:1],plans[2],[bad];dimension=1,dataset_independence=independent)
    @test_throws ArgumentError E.summarize_person_dimension(plans[1],attempts[1];dimension=true,dataset_independence=independent)
    push!(records,(;case="handmade_recovery_pairs",paired,person_dimension=persons))
end

@testset "Global CV weights and independent-fold composition" begin
    input=inputs[1][1];plan=plans[1]
    data=P.observation_data(input.observed)
    w=E.predictive_weights(data)
    @test sum(w)≈1. && w[1]==.001 && w[11]≈1/1500
    split=E.bind_folds(plan,input;seed=9233501)
    logs=reduce(vcat,permutedims.(Vector{Float64}.(input.truth.log_probabilities)))
    # Compact MCSE arithmetic fixtures, not real fold refits.
    folds=[E.seal((;id=input.id,fold=f.fold,split_identity=split.content_hash,
        reference=(;sha256=string(f.fold)^64,seed=9233600+f.fold),qualification=(;qualified=true),
        heldout_observations=f.heldout_observations,status=:prepared,log_probabilities=logs[f.heldout_observations,:],
        heldout_provenance_verified=true,n_prediction_draws=4000,
        monte_carlo_error=(;rows=[(;metric,estimate=0.,status=:first_order_candidate,mcse=.01f.fold) for metric in E.LOSS_METRICS],
            n_prediction_draws=4000,n_chains=4,weighting=:global_equal_person_equal_dimension))) for f in split.folds.fold_rows]
    cv=E.assemble_cv(plan,input,split,folds;fold_independence=independent)
    @test cv.monte_carlo_error.rows[1].mcse≈.01sqrt(55)
    @test !cv.monte_carlo_precision_assessed
    unknown=E.assemble_cv(plan,input,split,folds)
    @test unknown.monte_carlo_error.rows[1].status===:dependence_unresolved
    @test ismissing(unknown.monte_carlo_error.rows[1].mcse)
    partial=E.assemble_cv(plan,input,split,folds[1:4];fold_independence=independent)
    @test partial.monte_carlo_error.rows[1].status===:incomplete_folds && partial.score===nothing
    dup=E.seal(merge(body(folds[2]),(;reference=merge(folds[2].reference,(;seed=folds[1].reference.seed)))))
    @test_throws ArgumentError E.assemble_cv(plan,input,split,[folds[1];dup;folds[3:5]];fold_independence=independent)
    part=merge(folds[1].monte_carlo_error,(;rows=[merge(r,(;status=:first_order_degenerate,mcse=missing)) for r in folds[1].monte_carlo_error.rows]))
    bad=E.seal(merge(body(folds[1]),(;monte_carlo_error=part)))
    @test E.assemble_cv(plan,input,split,[bad;folds[2:5]];fold_independence=independent).monte_carlo_error.rows[1].status===:linearization_unresolved
    # Actual model logits: streamed influences must match the probability-cube oracle.
    target=P.target(P.specification(input.observed;require_all_categories=false))
    raw=Float64.(input.truth.raw)
    direct=reduce(vcat,[permutedims(B._mgmfrm_source_constrained_params_from_unconstrained(target.design,
        raw+.02randn(rng,128))) for _ in 1:80])
    selected=[1,11,26,36]
    design=B._loo_refit_score_design(data,target.design,selected)
    lm=E.mean_log_probabilities(design,direct;batch_size=13)
    state=E.loss_delta_setup(lm,logs[selected,:],data.category[selected],w[selected],80)
    E.foreach_log_batch(design,direct;batch_size=13) do rows,draws
        E.loss_delta_add!(state,draws,rows)
    end
    streamed=E.loss_delta_finish(state;layout(80)...)
    cube=log.(B._mgmfrm_predictive_probabilities_direct(design,direct))
    oracle=E.predictive_loss_mcse(cube,logs[selected,:];categories=data.category[selected],weights=w[selected],layout(80)...)
    @test streamed.influence≈oracle.influence atol=1e-13
    @test getproperty.(streamed.rows,:mcse)≈getproperty.(oracle.rows,:mcse) rtol=1e-9
end

P.writejson(output,(;records,tests_passed=true,julia_version=string(VERSION),
    scope=:arithmetic_and_model_logit_fixtures,new_sampler_runs=0,
    formal_recovery_replications=0,formal_sbc_replications=0,cv_refits=0,scientific_acceptance=false))
