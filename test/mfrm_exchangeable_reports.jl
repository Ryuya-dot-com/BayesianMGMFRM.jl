isdefined(@__MODULE__, :MFRMExchangeableSampleChecks) || include("mfrm_exchangeable_samples.jl")
module MFRMExchangeableReportChecks
using Test, BayesianMGMFRM, Random, Statistics
using ..MFRMExchangeableRaterChecks: specification, target, reference
using ..MFRMExchangeableSampleChecks: synthetic_record, rehash
const B = BayesianMGMFRM
untimed(r) = Base.structdiff(r, (; created_at=nothing))

# Independent adjacent-category calculation, in unit logits, including mixed Q.
function manual_replication(t, draws, indices, rng)
    spec, blocks = reference(t).design.spec, reference(t).blueprint.blocks
    data, D, K = spec.data, spec.dimensions, length(spec.data.category_levels)
    scores = zeros(Int,length(indices),data.n)
    for (j,index) in enumerate(indices)
        x=draws[index,:]
        theta=reshape(x[blocks[:person]],D,:)
        severity=[x[blocks[:rater_free]];-sum(x[blocks[:rater_free]])]
        steps=reshape(x[blocks[:item_steps]],K-2,length(data.item_levels))
        for row in 1:data.n
            i,p,r=data.item[row],data.person[row],data.rater[row]
            location=sum(theta[d,p] for d in 1:D if spec.q_matrix[i,d])-x[blocks[:item]][i]-severity[r]
            eta=[0.0;cumsum(location .- [steps[:,i];-sum(steps[:,i])])]
            weights=exp.(eta.-maximum(eta)); probabilities=weights./sum(weights)
            scores[j,row]=data.category_levels[searchsortedfirst(cumsum(probabilities),rand(rng))]
        end
    end
    return scores
end

function check_report(result; directory=nothing)
    directory===nothing && return mktempdir(d->check_report(result;directory=d))
    record=result.record
    t=B._MFRMExchangeableRatersLogDensity(record.spec,record.prior;expected_identity=record.target_identity)
    correlated=record.spec isa B.CorrelatedMFRMSpec
    path=joinpath(directory,"replayed-samples.jls")
    B._save_mfrm_exchangeable_rater_samples(path,result)
    loaded=B._load_mfrm_exchangeable_rater_samples(path;expected_identity=record.target_identity)
    for selection in ((;),(;ndraws=5),(;draw_indices=[lastindex(record.run.chain_ids),1,1]))
        check=B._mfrm_fixed_q_predictive_check(result;seed=47,selection...)
        rng=MersenneTwister(47)
        indices=haskey(selection,:draw_indices) ? selection.draw_indices : haskey(selection,:ndraws) ?
            rand(rng,axes(record.run.draws,1),selection.ndraws) : collect(axes(record.run.draws,1))
        @test check.replicated_scores==manual_replication(t,record.run.draws,indices,rng)
        @test check.draw_indices==indices
        @test check.chain_ids==record.run.chain_ids[indices] && check.iterations==record.run.iterations[indices]
        @test check.target_identity==record.target_identity && check.model==result.model
        @test isequal(check.diagnostics,result.diagnostics)
        @test isequal(check,B._mfrm_fixed_q_predictive_check(loaded;seed=47,selection...))
    end
    options=(;seed=47,draw_indices=[1,2,1],include_prior_predictive=true,prior_predictive_ndraws=17,prior_interval=0.8,predictive_interval=0.7)
    Random.seed!(55); expected=rand(); Random.seed!(55)
    report=B._mfrm_fixed_q_report(result;options...,require_complete=true)
    @test rand()==expected
    @test isequal(untimed(report),untimed(B._mfrm_fixed_q_report(loaded;options...,require_complete=true)))
    @test report.metadata.prior==record.prior && !report.metadata.public_fit
    @test report.family==result.model && report.metadata.target_identity==record.target_identity
    @test report.metadata.source_sample_content_hash==record.content_hash
    @test isequal(report.diagnostics.summary,result.diagnostics.summary)
    @test !isempty(report.diagnostics.warning_rows)
    @test isequal(report.warmup.rows,result.warmup_diagnostics)
    row=only(filter(r->r.block===:rater_free,report.prior_policy.rows))
    @test row.prior_family===:normalized_zero_sum_normal && !row.independent_by_parameter
    @test !row.direct_scale_prior && row.scale_parameter===:rater_kernel_sd
    @test row.scale==record.prior.scales.rater_kernel_sd
    @test row.rater_marginal_sd==record.prior.rater_marginal_sd
    @test row.rater_contrast_sd==record.prior.rater_contrast_sd
    prior=B._mfrm_exchangeable_prior_check(t;ndraws=17,rng=MersenneTwister(47))
    @test report.prior_predictive.prior==record.prior && report.prior_predictive.target_identity==record.target_identity
    @test isequal(report.prior_predictive.rows,predictive_check_summary(prior;interval=0.7,include_grouped=true))
    @test isequal(report.prior_predictive.parameter_rows,B._fixed_q_prior_parameter_rows(prior.model_coordinates,prior.dimension_labels;interval=0.8))
    @test B._report_prior_plot_data(report.prior_predictive,:prior_predictive)==B._prior_predictive_plot_data(prior;interval=0.7)
    @test B._report_prior_plot_data(report.prior_predictive,:prior;block=:rater).prior_label==prior.prior_label
    if correlated
        @test last(report.posterior.rows).parameter_space===:fisher_z
        @test only(report.direct_posterior.correlation_rows).parameter_space===:correlation
        @test only(report.diagnostics.correlation_rows).parameter_space===:correlation
        @test last(report.prior_policy.rows).shape==record.spec.lkj_eta
    end
    for data in (B._mfrm_fixed_q_plot_data(result;block=:rater),
            B._mfrm_fixed_q_diagnostic_plot_data(result;block=correlated ? :latent_correlation : :rater,max_parameters=3),
            B._mfrm_fixed_q_predictive_plot_data(result;seed=47))
        @test data.prior_label==prior.prior_label && data.model==result.model
        @test data.diagnostic==replace(B._plot_diagnostic_note(result.diagnostics.summary),"inspect diagnostics(fit)"=>"inspect parameter and sampler diagnostics")
    end
    public=fit_report_public(report)
    @test B._assert_public_fit_report_language(public)===public
    for r in (report,public)
        md=fit_report_markdown(r;max_rows=0)
        @test occursin("rater_kernel_sd",md) && occursin("marginal SD",md)
        @test !occursin("renaming rater IDs can change",md) && !occursin("(R-1)*rater_sd^2",md)
    end
    save_fit_report_bundle(joinpath(directory,"report"),public;require_complete=true)
    @test load_fit_report_bundle(joinpath(directory,"report");require_complete=true)==B._json_export_value(public)
    no_prior=B._mfrm_fixed_q_report(result;seed=47,draw_indices=[1,2,1],predictive_interval=0.7)
    @test no_prior.prior_predictive.status===:not_requested
    @test isequal(no_prior.posterior_predictive,report.posterior_predictive)
    @test isequal(no_prior.diagnostics,report.diagnostics)
    changed=B._mfrm_fixed_q_report(result;options...,prior_predictive_ndraws=7)
    @test changed.prior_predictive.ndraws==7
    @test isequal(changed.posterior_predictive,report.posterior_predictive)
    @test isequal(changed.posterior,report.posterior)
    broken=B._mfrm_fixed_q_report(result;include_prior_predictive=true,prior_predictive_ndraws=0)
    @test broken.report_status===:incomplete && broken.prior_predictive.status===:error
    @test_throws ArgumentError B._mfrm_fixed_q_report(result;include_prior_predictive=true,prior_predictive_ndraws=0,require_complete=true)
    @test_throws ArgumentError B._mfrm_fixed_q_report(result;include_prior_predictive=true,prior_predictive_ndraws=0,on_section_error=:throw)
    @test_throws ArgumentError B._mfrm_fixed_q_report(result;prior_interval=1)
    altered=merge(result,(;model=:mfrm_fixed_q,model_coordinates=NamedTuple[],diagnostics=(;summary=(;flag=:ok))))
    @test isequal(untimed(report),untimed(B._mfrm_fixed_q_report(altered;options...,require_complete=true)))
    bad=merge(result,(;record=rehash(merge(record,(;prior=merge(record.prior,(;rater_prior=:independent_normal)))))))
    for f in (B._mfrm_fixed_q_report,B._mfrm_fixed_q_predictive_check,B._mfrm_fixed_q_plot_data,B._mfrm_fixed_q_diagnostic_plot_data)
        @test_throws ArgumentError f(bad)
    end
    return report
end

@testset "exchangeable saved-result prediction and reporting (no sampling)" begin
    for (D,K,mixed,correlated) in ((2,2,false,false),(3,4,false,false),(2,4,true,false),(2,2,false,true),(2,4,false,true)), backend in (:advancedhmc,:cmdstan)
        spec=specification(3,K;D,mixed)
        model=correlated ? B.Experimental.correlated(spec;lkj_eta=3) : spec
        t=target(spec,correlated)
        record=synthetic_record(t,model,backend)
        check_report(B._restore_mfrm_exchangeable_rater_samples(record;expected_identity=record.target_identity))
    end
end
end
