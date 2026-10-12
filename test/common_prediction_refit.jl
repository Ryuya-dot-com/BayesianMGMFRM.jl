module CommonPredictionRefitChecks
using BayesianMGMFRM, Test, Serialization, TOML
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/saved_fold_predictions.jl")
bytes(x)=(io=IOBuffer(); serialize(io,x); take!(io))

function source_case(spec, wrap=identity)
    rows=facet_response_table(spec.data)
    data=FacetData(map(v->repeat(v;inner=2),rows);person=:person,rater=:rater,item=:item,score=:score,
        category_levels=spec.data.category_levels)
    source=B._refit_training_spec(spec,data)
    plan=kfold_plan(data;k=2)
    return (;model=wrap(source),plan,ids=["rating-$i" for i in 1:data.n])
end
function prepare(case,prior;dataset_id="synthetic-refit-check")
    B.prediction_refit_plan(case.model,case.plan;prior,dataset_id,observation_ids=case.ids)
end

function checks(output)
tests=@testset "Source-bound common heldout scoring (no MCMC)" begin
    original=reporting_fit(:mfrm).design.spec.data
    data=FacetData(facet_response_table(original);person=:person,rater=:rater,item=:item,score=:score,
        category_levels=original.category_levels)
    legacy=[reporting_fit(f;data,chains=2,ndraws=20,warmup=0) for f in (:mfrm,:gmfrm,:mgmfrm)]
    r=F.synthetic_record(F.target())
    corr=B.Experimental.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity)
    fixed=[prediction_fixed_fixture(kind) for kind in
        (:independent,:correlated,:exchangeable,:exchangeable_correlated)]
    cases=Any[]
    for fit in legacy
        prior=fit isa MFRMFit ? fit.prior : B.Experimental.GeneralizedPrior(;B._source_fixture_prior_values(fit.prior)...)
        push!(cases,(;fit,prior,case=source_case(fit.design.spec),
            native=pointwise_loglikelihood_matrix(fit)))
    end
    for model in (:exchangeable,:source)
        fit=normalized_fixture(r;model)
        p=fit.record.prior
        prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=p.prior_model,p.scales...,source_rater=p.source_rater)
        push!(cases,(;fit,prior,case=source_case(r.spec),
            native=B._recorded_mgmfrm_samples(fit).diagnostics.direct_values.pointwise_loglikelihood))
    end
    push!(cases,(;fit=corr,prior=B.Experimental.GeneralizedPrior(;r.prior.scales...),
        case=source_case(r.spec,s->B.Experimental.correlated(s;lkj_eta=r.prior.lkj_eta)),
        native=B._recorded_mgmfrm_samples(corr).diagnostics.direct_values.pointwise_loglikelihood))
    push!(fixed,prediction_fixed_fixture(:independent;D=3))
    for fixture in fixed
        fit,reference=fixture.fit,fixture.reference
        spec=B._fixed_q_result_spec((;fit.record))
        exchangeable=fit isa B._ExchangeableMFRMFit
        correlated=fit isa B._CorrelatedMFRMFit || (exchangeable && fit.record.spec isa B.CorrelatedMFRMSpec)
        prior=exchangeable ? B.Experimental.ExchangeablePrior(;fit.record.prior.scales...) : MFRMPrior()
        wrap=correlated ? s->B.Experimental.correlated(s;lkj_eta=3) : identity
        n=B.LogDensityProblems.dimension(reference)
        native=reduce(vcat,permutedims(B._mfrm_fixed_q_pointwise(reference,row[1:n])) for row in eachrow(fit.record.run.draws))
        push!(cases,(;fit,prior,case=source_case(spec,wrap),native))
    end
    @test length(unique(typeof(c.fit) for c in cases))==8
    for c in cases
        @info "Checking native heldout scores and bindings" fit_type=typeof(c.fit)
        before=bytes((c.fit,c.case,c.prior))
        prepared=prepare(c.case,c.prior)
        request=prepared.folds[1]
        scored=B.prediction_fold_observations(c.fit,request)
        @test scored.pointwise_loglikelihood ≈ c.native atol=2e-12
        @test scored.observation_ids==c.case.ids[request.heldout_observations]
        @test scored.training_observation_ids==c.case.ids[request.training_observations]
        @test scored.source_row_indices==request.heldout_observations
        @test scored.draw_indices==collect(1:size(c.native,1))
        @test scored.chain_ids==repeat(1:2;inner=20)
        @test scored.iterations==repeat(1:20;outer=2)
        @test all(isapprox.(sum(scored.probabilities;dims=3),1.;atol=2e-14))
        @test scored.prediction_target===:heldout_rows_existing_levels
        @test scored.scientific_acceptance===:not_established
        @test !isempty(scored.sampling_quality)
        plain=B.prediction_fold_observations(c.fit,request;include_probabilities=false)
        @test plain.probabilities===nothing
        @test plain.pointwise_loglikelihood==scored.pointwise_loglikelihood
        @test_throws ArgumentError B.prediction_criteria(scored)
        @test bytes((c.fit,c.case,c.prior))==before
        reversed=deepcopy(c.case.plan)
        reverse!(reversed.fold_rows[1].heldout_observations)
        reverse!(reversed.heldout_observation_indices[1])
        reordered=prepare(merge(c.case,(;plan=reversed)),c.prior)
        @test B.prediction_fold_observations(c.fit,reordered.folds[1]).pointwise_loglikelihood ≈ c.native[:,end:-1:1]
        # Reordering training rows must not change source coordinate/reference labels.
        reverse!(reversed.fold_rows[1].training_observations)
        reordered=prepare(merge(c.case,(;plan=reversed)),c.prior)
        train=B._prediction_base_spec(reordered.folds[1].model)
        source=B._prediction_base_spec(c.case.model)
        @test train.data.person_levels==source.data.person_levels
        @test train.data.rater_levels==source.data.rater_levels
        @test train.data.item_levels==source.data.item_levels
        @test train.q_matrix==source.q_matrix
        @test train.dimension_labels==source.dimension_labels
        # All types preserve native scoring after request serialization and fit-cache reload.
        dir=mktempdir(output)
        serialize(joinpath(dir,"request.jls"),request)
        save_fit_cache(joinpath(dir,"fit.jls"),c.fit)
        replay=saved_fold_predictions(joinpath(dir,"fit.jls"),deserialize(joinpath(dir,"request.jls"));include_probabilities=true)
        @test isequal(replay,scored)
        # Each bound payload field is checked, including nested mutable arrays.
        changed=deepcopy(request);changed.observation_ids[1]="changed"
        @test_throws ArgumentError B.prediction_fold_observations(c.fit,changed)
        changed=deepcopy(request);reverse!(changed.heldout_observations)
        @test_throws ArgumentError B.prediction_fold_observations(c.fit,changed)
        @test_throws ArgumentError B.prediction_fold_observations(c.fit,merge(request,(;dataset_id="different")))
        @test_throws ArgumentError B.prediction_fold_observations(c.fit,merge(request,(;fold=999)))
    end

    a=cases[1];prepared=prepare(a.case,a.prior);req=prepared.folds[1]
    # Family and D do not change the shared source/split contract.
    @test prepared.split_binding==prepare(cases[2].case,cases[2].prior).split_binding
    @test prepared.split_binding==prepare(cases[3].case,cases[3].prior).split_binding
    @test_throws ArgumentError B.prediction_fold_observations(cases[2].fit,req)
    wrongprior=prepare(a.case,MFRMPrior(person_sd=9.)).folds[1]
    @test_throws ArgumentError B.prediction_fold_observations(a.fit,wrongprior)
    fullfit=reporting_fit(:mfrm;data=a.case.model.data,chains=2,ndraws=20,warmup=0)
    @test_throws ArgumentError B.prediction_fold_observations(fullfit,req)
    @test_throws ArgumentError prepare(a.case,B.Experimental.GeneralizedPrior())
    @test_throws ArgumentError prepare(a.case,a.prior;dataset_id=" ")
    @test_throws ArgumentError B.prediction_refit_plan(a.case.model,a.case.plan;prior=a.prior,
        dataset_id="bad",observation_ids=fill("duplicate",length(a.case.ids)))
    badplan=deepcopy(a.case.plan);badplan.fold_rows[2].training_observations[1]=badplan.fold_rows[2].heldout_observations[1]
    @test_throws ArgumentError B.prediction_refit_plan(a.case.model,badplan;prior=a.prior,
        dataset_id="bad",observation_ids=a.case.ids)
    unknown=kfold_plan(a.case.model.data;k=2,group_by=:person)
    @test_throws ArgumentError B.prediction_refit_plan(a.case.model,unknown;prior=a.prior,
        dataset_id="bad",observation_ids=a.case.ids)
    corrupt=deepcopy(corr);corrupt.record.run.draws[1,1]+=1
    @test_throws ArgumentError B.prediction_fold_observations(corrupt,prepare(cases[6].case,cases[6].prior).folds[1])
    eta_case=merge(cases[6].case,(;model=B.Experimental.correlated(cases[6].case.model.base_spec;lkj_eta=3)))
    @test_throws ArgumentError B.prediction_fold_observations(corr,prepare(eta_case,cases[6].prior).folds[1])
    @test_throws ArgumentError B.prediction_fold_observations(cases[4].fit,prepare(cases[5].case,cases[5].prior).folds[1])

    # Holdout outcomes can differ from training rows; probabilities stay conditional on training draws.
    rows=facet_response_table(a.case.model.data)
    for i in req.heldout_observations
        rows.score[i]=mod(rows.score[i]+1,3)
    end
    data=FacetData(rows;person=:person,rater=:rater,item=:item,score=:score,category_levels=0:2)
    changed_case=merge(a.case,(;model=B._refit_training_spec(a.case.model,data)))
    changed_plan=prepare(changed_case,a.prior)
    changed=B.prediction_fold_observations(a.fit,changed_plan.folds[1])
    original=B.prediction_fold_observations(a.fit,req)
    @test changed.probabilities==original.probabilities
    @test changed.source_binding!=original.source_binding
    @test changed.split_binding!=original.split_binding
    @test changed.training_target==original.training_target
    @test changed.pointwise_loglikelihood!=original.pointwise_loglikelihood
    @test changed.pointwise_loglikelihood ≈ hcat([log.(changed.probabilities[:,j,data.category[n]]) for (j,n) in enumerate(req.heldout_observations)]...)
    # Snapshot is independent of later caller mutation; tampering inside it is rejected.
    mutated=deepcopy(a.case);frozen=prepare(mutated,a.prior);snapshot=bytes(frozen)
    mutated.model.data.score[1]=99
    @test bytes(frozen)==snapshot
    changedreq=deepcopy(req);changedreq.source_spec.data.score[1]=99
    @test_throws ArgumentError B.prediction_fold_observations(a.fit,changedreq)
    @test Base.Docs.doc(B.prediction_refit_plan)!==nothing
    @test Base.Docs.doc(B.prediction_fold_observations)!==nothing
    # Missing fitted levels still remain absent; holding out a new person is not supported.
    held=kfold_plan(a.case.model.data;k=2,group_by=:person).fold_rows[1]
    training=B._loo_refit_training_data(a.case.model.data,held.training_observations)
    @test_throws ArgumentError B._loo_refit_score_data(a.case.model.data,training,held.heldout_observations)

    # A valid explicitly encoded source may use a different level order from FacetData(table).
    d=deepcopy(F.target().base.design.spec.data)
    d.rater .= 4 .- d.rater
    reverse!(d.rater_levels)
    spec=mfrm_spec(d;dimensions=2,q_matrix=Bool[1 0;0 1;1 0;0 1])
    order=reverse(collect(1:d.n))
    old=FacetData(facet_response_table(d;observations=order);person=:person,rater=:rater,
        item=:item,score=:score,category_levels=d.category_levels)
    kept=B._loo_refit_training_data(d,order)
    original_target=B._MFRMFixedQReferenceLogDensity(spec;prior=MFRMPrior())
    old_target=B._MFRMFixedQReferenceLogDensity(B._refit_training_spec(spec,old);prior=MFRMPrior())
    kept_target=B._MFRMFixedQReferenceLogDensity(B._refit_training_spec(spec,kept);prior=MFRMPrior())
    beta=zeros(B.LogDensityProblems.dimension(original_target))
    beta[original_target.blueprint.blocks[:rater_free]].=[.2,.6]
    old_beta=copy(beta);old_beta[old_target.blueprint.blocks[:rater_free]].=[-.8,.6]
    @test old.rater_levels!=d.rater_levels
    @test kept.rater_levels==d.rater_levels
    @test B._mfrm_fixed_q_pointwise(old_target,old_beta) ≈ B._mfrm_fixed_q_pointwise(original_target,beta)[order]
    @test logprior(old_target,old_beta)-logprior(original_target,beta) ≈ -.3 atol=1e-12
    @test logprior(kept_target,beta)==logprior(original_target,beta)
    @test B._mfrm_fixed_q_pointwise(kept_target,beta) ≈ B._mfrm_fixed_q_pointwise(original_target,beta)[order]
end
counts=Test.get_test_counts(tests)
open(joinpath(output,"verification.toml"),"w") do io
    TOML.print(io,Dict("status"=>"passed",
        "assertions"=>counts.passes+counts.cumulative_passes,"new_posterior_fits"=>0,
        "scope"=>"deterministic target/binding, native likelihood, cache and serialization checks; no calibration claim"))
end
return tests
end
end
