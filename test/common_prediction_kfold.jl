module CommonPredictionKfoldChecks
using BayesianMGMFRM, Test, Serialization
import ..CommonPredictionRefitChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks
include("../examples/saved_kfold_comparison.jl")

# Deterministic reporting draws test plumbing; none are convergence evidence.
function fixture_cases()
    original=R.reporting_fit(:mfrm).design.spec.data
    data=FacetData(facet_response_table(original);person=:person,rater=:rater,item=:item,score=:score,
        category_levels=original.category_levels)
    cases=Any[]
    for family in (:mfrm,:gmfrm,:mgmfrm)
        fit=R.reporting_fit(family;data,chains=2,ndraws=20,warmup=0)
        prior=family===:mfrm ? fit.prior : B.Experimental.GeneralizedPrior(;B._source_fixture_prior_values(fit.prior)...)
        push!(cases,(;fit,prepared=R.prepare(R.source_case(fit.design.spec),prior)))
    end
    record=R.F.synthetic_record(R.F.target())
    for model in (:exchangeable,:source)
        fit=R.normalized_fixture(record;model);p=fit.record.prior
        prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=p.prior_model,p.scales...,source_rater=p.source_rater)
        push!(cases,(;fit,prepared=R.prepare(R.source_case(record.spec),prior)))
    end
    fit=B.Experimental.CorrelatedMGMFRMFit(record;expected_identity=record.target_identity)
    prior=B.Experimental.GeneralizedPrior(;record.prior.scales...)
    case=R.source_case(record.spec,s->B.Experimental.correlated(s;lkj_eta=record.prior.lkj_eta))
    push!(cases,(;fit,prepared=R.prepare(case,prior)))
    for (kind,D) in ((:independent,2),(:correlated,2),(:exchangeable,2),(:exchangeable_correlated,2),(:independent,3))
        fit=R.prediction_fixed_fixture(kind;D).fit
        spec=B._fixed_q_result_spec((;fit.record))
        exchangeable=fit isa B._ExchangeableMFRMFit
        correlated=fit isa B._CorrelatedMFRMFit || (exchangeable && fit.record.spec isa B.CorrelatedMFRMSpec)
        prior=exchangeable ? B.Experimental.ExchangeablePrior(;fit.record.prior.scales...) : MFRMPrior()
        wrap=correlated ? s->B.Experimental.correlated(s;lkj_eta=3) : identity
        push!(cases,(;fit,prepared=R.prepare(R.source_case(spec,wrap),prior)))
    end
    return cases
end
score_case(c)=[B.prediction_fold_observations(c.fit,r;include_probabilities=false) for r in c.prepared.folds]
seal(x)=B._prediction_seal(Base.structdiff(x,(;content_hash=nothing)))

function integration_checks(output)
    cases=fixture_cases();summaries=Any[];entries=Any[]
    @testset "All saved fit types: complete K-fold path" begin
        @test length(unique(typeof(c.fit) for c in cases))==8
        for (i,c) in enumerate(cases)
            scores=score_case(c)
            result=B.prediction_kfold(c.prepared,reverse(scores))
            native=kfold([s.pointwise_loglikelihood for s in scores];
                fold_ids=[s.fold for s in scores],observation_indices=[s.source_row_indices for s in scores])
            @test result.elpd ≈ native.elpd_kfold atol=1e-10
            @test result.complete
            @test result.n_expected_folds==result.n_scored_folds==2
            @test result.observation_ids==c.prepared.folds[1].observation_ids
            @test result.pointwise_elpd[reduce(vcat,[s.source_row_indices for s in scores])] ≈ native.pointwise.elpd_heldout
            @test ismissing(result.se_elpd)
            @test result.scientific_acceptance===:not_established
            @test result.sampling_warning==any(B._prediction_sampling_warning(s.sampling_quality) for s in scores)
            @test isequal(result,B.prediction_kfold(c.prepared,scores))
            before=R.bytes((c.prepared,scores,result))
            comparison=B.compare_kfold_predictions("first"=>result,"same"=>result;comparison_axis=:model)
            @test [r.model for r in comparison.rows]==["first","same"]
            @test all(r->r.elpd_difference==0.,comparison.rows)
            @test comparison.model_selection===:not_performed
            @test all(r->ismissing(r.se_elpd_difference),comparison.rows)
            @test R.bytes((c.prepared,scores,result))==before
            path=joinpath(output,"fit-$i.jls");save_fit_cache(path,c.fit)
            entry=(;prepared=c.prepared,caches=Dict(r.fold=>path for r in c.prepared.folds))
            replay=saved_kfold_comparison("first"=>entry,"same"=>entry;comparison_axis=:model)
            @test isequal(replay,comparison)
            push!(summaries,result);push!(entries,entry)
        end
        @test_throws ArgumentError B.compare_kfold_predictions("MFRM"=>summaries[1],"MGMFRM"=>summaries[3];comparison_axis=:model)
        comparison=B.compare_kfold_predictions("MFRM"=>summaries[1],"GMFRM"=>summaries[2],"MGMFRM"=>summaries[3];comparison_axis=:dimensions,baseline="GMFRM")
        @test comparison.baseline=="GMFRM"
        @test comparison.rows[3].elpd_difference ≈ summaries[3].elpd-summaries[2].elpd
        @test comparison.rows[1].model_contract.prior.type != comparison.rows[2].model_contract.prior.type
        @test_throws ArgumentError B.compare_kfold_predictions("a"=>summaries[1],"b"=>summaries[7];comparison_axis=:dimensions)
        serialize(joinpath(output,"replay-inputs.jls"),entries)
        serialize(joinpath(output,"replay-expected.jls"),[
            B.compare_kfold_predictions("first"=>s,"same"=>s;comparison_axis=:model) for s in summaries])
    end
    return cases,summaries
end

function boundary_checks(c,result)
    scores=score_case(c);p=c.prepared
    @testset "Missing, failed, diagnostic and identity boundaries" begin
        missing_fold=B.prediction_kfold(p,scores[1:1])
        @test !missing_fold.complete
        @test ismissing(missing_fold.elpd) && ismissing(missing_fold.kfoldic)
        @test missing_fold.folds[2].status===:missing
        @test all(ismissing,missing_fold.pointwise_elpd[p.folds[2].heldout_observations])
        @test count(!ismissing,missing_fold.pointwise_elpd)==length(scores[1].observation_ids)
        failed=B.prediction_kfold(p,scores[1:1];failures=[p.folds[2].fold=>"storage failure"])
        @test failed.folds[2].status===:failed
        @test failed.folds[2].failure_reason=="storage failure"
        empty=B.prediction_kfold(p,[])
        @test all(r->r.status===:missing,empty.folds)
        @test ismissing(empty.elpd)
        cmp=B.compare_kfold_predictions("ok"=>result,"absent"=>missing_fold,"failed"=>failed;comparison_axis=:model)
        @test cmp.status===:incomplete && !cmp.diagnostics_ok
        @test all(r->ismissing(r.elpd_difference),cmp.rows)
        @test cmp.rows[1].elpd==result.elpd
        @test !cmp.rows[2].complete
        good=[seal(merge(s,(;sampling_quality=(;flag=:ok)))) for s in scores]
        ok=B.prediction_kfold(p,good)
        @test ok.status===:descriptive && ok.diagnostics_ok
        bad=copy(good);bad[1]=seal(merge(good[1],(;sampling_quality=(;flag=:warning))))
        warning=B.prediction_kfold(p,bad)
        @test warning.complete && warning.status===:warning && !warning.diagnostics_ok
        @test warning.elpd==ok.elpd
        cmp=B.compare_kfold_predictions("warning"=>warning,"good"=>ok;comparison_axis=:model)
        @test cmp.status===:warning && all(r->r.elpd_difference==0.,cmp.rows)
        location=seal(merge(good[1],(;sampling_quality=(;flag=:ok,location_summary=(;flag=:warning)))))
        @test B.prediction_kfold(p,[location,good[2]]).sampling_warning
        @test_throws ArgumentError B.prediction_kfold(p,[scores[1],scores[1]])
        @test_throws ArgumentError B.prediction_kfold(p,scores;failures=[p.folds[1].fold=>"also scored"])
        @test_throws ArgumentError B.prediction_kfold(p,[];failures=[p.folds[1].fold=>"a",p.folds[1].fold=>"b"])
        @test_throws ArgumentError B.prediction_kfold(p,[];failures=[999=>"unknown"])
        @test_throws ArgumentError B.prediction_kfold(p,[];failures=[p.folds[1].fold=>" "])
        @test_throws ArgumentError B.prediction_kfold(merge(p,(;folds=p.folds[1:1])),scores[1:1])
        changed=deepcopy(p);changed.folds[1].observation_ids[1]="edited"
        @test_throws ArgumentError B.prediction_kfold(changed,scores)
        @test_throws ArgumentError B.prediction_kfold(merge(p,(;schema="bayesianmgmfrm.prediction_refit_plan.v1")),scores)
        @test_throws ArgumentError B.prediction_kfold(p,[merge(scores[1],(;schema="bayesianmgmfrm.prediction_fold_observations.v1")),scores[2]])
        # An intact hash alone does not excuse incompatible row/target/draw semantics.
        for changes in ((;observation_ids=reverse(scores[1].observation_ids)),
                (;training_observation_ids=reverse(scores[1].training_observation_ids)),
                (;source_binding="other"),(;training_target=(;kind=:wrong,identity="wrong")),
                (;category_levels=[99,100,101]),(;draw_indices=reverse(scores[1].draw_indices)),
                (;chain_ids=reverse(scores[1].chain_ids)),(;iterations=reverse(scores[1].iterations)),
                (;prediction_target=:training_rows_existing_levels))
            edited=seal(merge(scores[1],changes))
            @test_throws ArgumentError B.prediction_kfold(p,[edited,scores[2]])
        end
        for value in (NaN,Inf,.1)
            edited=deepcopy(scores[1]);edited.pointwise_loglikelihood[1,1]=value
            @test_throws ArgumentError B.prediction_kfold(p,[edited,scores[2]])
            @test_throws ArgumentError B.prediction_kfold(p,[seal(edited),scores[2]])
        end
        edited=deepcopy(result);edited.pointwise_elpd[1]+=1
        @test_throws ArgumentError B.compare_kfold_predictions("a"=>edited,"b"=>result;comparison_axis=:model)
        for changes in ((;split_binding="other"),(;source_binding="other"),(;group_by=:person))
            @test_throws ArgumentError B.compare_kfold_predictions("a"=>seal(merge(result,changes)),"b"=>result;comparison_axis=:model)
        end
        @test_throws ArgumentError B.compare_kfold_predictions("a"=>result;comparison_axis=:model)
        @test_throws ArgumentError B.compare_kfold_predictions("a"=>result,"a"=>result;comparison_axis=:model)
        @test_throws ArgumentError B.compare_kfold_predictions("a"=>result,"b"=>result;comparison_axis=:unknown)
        @test_throws ArgumentError B.compare_kfold_predictions("a"=>result,"b"=>result;comparison_axis=:model,baseline="absent")
    end
end

function arithmetic_checks(c,result)
    scores=score_case(c);p=c.prepared
    @testset "Log predictive scoring and paired alignment" begin
        known=map(scores) do s
            matrix=repeat(reshape(log.([.2,.8]),2,1);outer=(20,length(s.observation_ids)))
            seal(merge(s,(;pointwise_loglikelihood=matrix)))
        end
        a=B.prediction_kfold(p,known)
        @test all(x->isapprox(x,log(.5);atol=1e-14),a.pointwise_elpd)
        @test a.elpd ≈ length(a.observation_ids)*log(.5)
        @test !(a.pointwise_elpd[1] ≈ (log(.2)+log(.8))/2)
        shifted=[seal(merge(s,(;pointwise_loglikelihood=s.pointwise_loglikelihood .- 1000))) for s in known]
        b=B.prediction_kfold(p,shifted)
        @test all(isfinite,b.pointwise_elpd)
        cmp=B.compare_kfold_predictions("shifted"=>b,"base"=>a;comparison_axis=:model,baseline="base")
        @test cmp.rows[1].elpd_difference ≈ -1000length(a.observation_ids)
        @test all(x->isapprox(x,-1000.;atol=1e-10),cmp.rows[1].pointwise_difference)
        # Reordering a valid source preserves the ID-based split and comparison.
        req=p.folds[1];spec=req.source_spec;order=reverse(1:spec.data.n)
        data=B._loo_refit_training_data(spec.data,order)
        model=B._refit_training_spec(spec,data)
        # Native fold labels follow heldout units, so reverse label order too.
        plan=kfold_plan(data;k=2,fold_ids=reverse([r.fold for r in p.folds]))
        reordered=B.prediction_refit_plan(model,plan;prior=req.prior,dataset_id=p.dataset_id,
            observation_ids=req.observation_ids[order])
        @test reordered.split_binding==p.split_binding
        # Use corresponding reordered deterministic fit; targets retain row-order identity.
        fits=[R.reporting_fit(:mfrm;data=r.model.data,chains=2,ndraws=20,warmup=0) for r in reordered.folds]
        other=B.prediction_kfold(reordered,[B.prediction_fold_observations(f,r;include_probabilities=false) for (f,r) in zip(fits,reordered.folds)])
        aligned=B.compare_kfold_predictions("original"=>result,"reordered"=>other;comparison_axis=:model)
        @test abs(aligned.rows[2].elpd_difference)<1e-10
    end
end

function checks(output)
    cases,summaries=integration_checks(output)
    boundary_checks(cases[1],summaries[1])
    arithmetic_checks(cases[1],summaries[1])
    axes_and_group_checks()
    slope_checks()
end

function slope_checks()
    @testset "Slope restrictions reach aggregation and comparison without fitting" begin
        E=B.Experimental
        record=R.F.synthetic_record(R.F.target()) # Deterministic arithmetic fixtures.
        spec=mfrm_spec(record.spec.data;family=:mgmfrm,dimensions=1,
            thresholds=:partial_credit,q_matrix=trues(length(record.spec.data.item_levels),1))
        prior=E.NormalizedMGMFRMPrior(;prior_model=:exchangeable,record.prior.scales...)
        results=Any[];plans=Any[];scores_by_model=Any[];fits=Any[]
        for policy in (:fixed_one,:estimated_positive)
            wrap=s->E.slope_restriction(s;item_slopes=policy,rater_consistency=:fixed_one)
            prepared=R.prepare(R.source_case(spec,wrap),prior)
            target=B._normalized_mgmfrm_target(prepared.folds[1].model,prior)
            fit=R.normalized_fixture(record;target)
            scores=[B.prediction_fold_observations(fit,r;include_probabilities=false) for r in prepared.folds]
            result=B.prediction_kfold(prepared,scores;mcse=:delta)
            @test result.complete && result.sampling_warning && !result.diagnostics_ok
            @test result.status===:warning
            @test result.model_contract.covariance===:independent
            @test result.model_contract.lkj_eta===nothing
            @test result.model_contract.item_slopes===policy
            @test result.model_contract.rater_consistency===:fixed_one
            @test result.model_contract.prior.values.scales==prior.scales
            @test ismissing(result.mcmc_error.value) # No independence declaration.
            @test all(r->!ismissing(r.mcmc_error.value),result.folds)
            # The fixture deliberately reuses one fit across two identical training
            # tables. It must never masquerade as independent MCMC streams.
            @test_throws ArgumentError B.prediction_kfold(prepared,scores;
                mcse=:delta,independent_fold_rng=true)
            push!(results,result);push!(plans,prepared);push!(scores_by_model,scores);push!(fits,fit)
        end
        @test plans[1].source_binding==plans[2].source_binding
        @test plans[1].split_binding==plans[2].split_binding
        cmp=B.compare_kfold_predictions("Fixed"=>results[1],"Free"=>results[2];comparison_axis=:model)
        @test cmp.complete && cmp.status===:warning && cmp.mcse_warning
        @test cmp.rows[2].elpd_difference≈results[2].elpd-results[1].elpd
        @test cmp.rows[1].difference_mcmc_error.value==0
        @test ismissing(cmp.rows[2].difference_mcmc_error.value)
        @test all(r->ismissing(r.se_elpd_difference),cmp.rows)
        @test cmp.model_selection===:not_performed && cmp.scientific_acceptance===:not_established
        @test_throws ArgumentError B.prediction_fold_observations(fits[1],plans[2].folds[1])
        absent=B.prediction_kfold(plans[2],[];mcse=:delta)
        @test absent.status===:incomplete && absent.n_scored_folds==0
        failed=B.prediction_kfold(plans[2],scores_by_model[2][1:1];failures=[2=>"not available"])
        @test failed.folds[2].status===:failed
        partial=B.compare_kfold_predictions("Fixed"=>results[1],"Free"=>failed;comparison_axis=:model)
        @test partial.status===:incomplete && all(r->ismissing(r.elpd_difference),partial.rows)

        # The newer mean-profile prior uses the same slope wrapper, but must keep
        # its separate prior identity in the aggregation contract.
        model=plans[1].folds[1].model
        profiled=E.MeanProfilePrior(model,prior;
            item_means=Dict(i=>.2 for i in spec.data.item_levels),
            step_means=Dict(i=>[-.5,0.,.5] for i in spec.data.item_levels),
            category_levels=spec.data.category_levels,units=:raw)
        wrap=s->E.slope_restriction(s;item_slopes=:fixed_one,rater_consistency=:fixed_one)
        prepared=R.prepare(R.source_case(spec,wrap),profiled)
        target=B._normalized_mgmfrm_target(prepared.folds[1].model,profiled)
        fit=R.normalized_fixture(record;target)
        scores=[B.prediction_fold_observations(fit,r;include_probabilities=false) for r in prepared.folds]
        result=B.prediction_kfold(prepared,scores)
        @test result.complete && result.model_contract.covariance===:independent
        @test result.model_contract.item_slopes===:fixed_one
        @test result.model_contract.prior.values.profile==profiled.profile
        @test result.model_contract.source_target!=results[1].model_contract.source_target
        @test_throws ArgumentError B.prediction_fold_observations(fits[1],prepared.folds[1])
    end
end

function axes_and_group_checks()
    @testset "Model axes and grouped holdouts" begin
        plain=R.prediction_fixed_fixture(:independent).fit
        mixed=R.prediction_fixed_fixture(:independent;mixed=true).fit
        fixed_results=map((plain,mixed)) do fit
            spec=B._fixed_q_result_spec((;fit.record))
            c=(;fit,prepared=R.prepare(R.source_case(spec),MFRMPrior()))
            B.prediction_kfold(c.prepared,score_case(c))
        end
        @test_throws ArgumentError B.compare_kfold_predictions("pure"=>fixed_results[1],"mixed"=>fixed_results[2];comparison_axis=:model)
        q=B.compare_kfold_predictions("pure"=>fixed_results[1],"mixed"=>fixed_results[2];comparison_axis=:q_matrix)
        @test q.complete
        @test q.rows[1].model_contract.q_matrix != q.rows[2].model_contract.q_matrix
        data=B._fixed_q_result_spec((;plain.record)).data
        scalar=R.reporting_fit(:mfrm;data,chains=2,ndraws=20,warmup=0)
        c=(;fit=scalar,prepared=R.prepare(R.source_case(scalar.design.spec),scalar.prior))
        unidimensional=B.prediction_kfold(c.prepared,score_case(c))
        @test_throws ArgumentError B.compare_kfold_predictions("one"=>unidimensional,"two"=>fixed_results[1];comparison_axis=:q_matrix)
        d=B.compare_kfold_predictions("one"=>unidimensional,"two"=>fixed_results[1];comparison_axis=:dimensions)
        @test d.complete
        @test [r.model_contract.dimensions for r in d.rows]==[1,2]
        # Item order is a label mapping, not an extra Q difference.
        contract=fixed_results[1].model_contract
        swapped=seal(merge(fixed_results[1],(;model_contract=merge(contract,
            (;item_levels=reverse(contract.item_levels),q_matrix=contract.q_matrix[end:-1:1,:])))))
        @test B.compare_kfold_predictions("first"=>fixed_results[1],"same Q"=>swapped;comparison_axis=:model).complete

        rows=facet_response_table(scalar.design.spec.data)
        repeated=map(v->repeat(v;inner=4),rows)
        table=merge(repeated,(;response=repeat(1:(2data.n);inner=2)))
        grouped=FacetData(table;person=:person,rater=:rater,item=:item,score=:score,
            response_id=:response,category_levels=data.category_levels)
        spec=mfrm_spec(grouped)
        prepared=B.prediction_refit_plan(spec,kfold_plan(grouped;k=2,group_by=:response_id);
            prior=scalar.prior,dataset_id="grouped",observation_ids=["g$i" for i in 1:grouped.n])
        scores=map(prepared.folds) do r
            fit=R.reporting_fit(:mfrm;data=r.model.data,chains=2,ndraws=20,warmup=0)
            scored=B.prediction_fold_observations(fit,r;include_probabilities=false)
            matrix=repeat(reshape(log.([.2,.8]),2,1);outer=(20,length(scored.observation_ids)))
            seal(merge(scored,(;pointwise_loglikelihood=matrix)))
        end
        result=B.prediction_kfold(prepared,scores)
        @test result.group_by===:response_id
        @test result.score_unit===:rating
        @test result.elpd ≈ grouped.n*log(.5)
        @test !(result.elpd ≈ (grouped.n/2)*log((.2^2+.8^2)/2))
        @test all(r->length(r.observation_ids)==grouped.n/2,result.folds)
        entry=(;prepared,caches=Dict(999=>"not-opened.jls"))
        @test_throws ArgumentError saved_kfold_comparison("a"=>entry,"b"=>entry;comparison_axis=:model)
    end
end
end
