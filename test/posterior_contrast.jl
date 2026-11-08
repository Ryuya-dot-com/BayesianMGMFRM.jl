module PosteriorContrastChecks
using Test, BayesianMGMFRM, Statistics, Serialization
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/saved_mgmfrm_contrasts.jl")

function checks()
    @testset "Scalar MFRM named joint-draw contrasts" begin
        for thresholds in (:rating_scale, :partial_credit)
            fitted=reporting_fit(:mfrm; thresholds, chains=2, ndraws=20)
            before=deepcopy(fitted.draws)
            column(name)=fitted.draws[:,only(findall(==(name),fitted.design.parameter_names))]
            requests=[
                (;left="person[1]",right="person[2]"),
                (;left="rater[2]",right="rater[1]"),
                (;left="rater[1]",right="rater[2]")]
            expected=[column("person[1]")-column("person[2]"),
                column("rater[2]"),-column("rater[2]")]
            for (request,values) in zip(requests,expected)
                result=B.posterior_contrast(fitted;request...,interval=.95,rope=(-.005,.005))
                @test result.summary.mean≈mean(values)
                @test result.summary.lower≈quantile(values,.025) atol=1e-14
                @test result.summary.upper≈quantile(values,.975) atol=1e-14
                @test result.summary.event_rows[1].count==count(>(0),values)
                @test result.summary.event_rows[3].count==count(x->-.005<=x<=.005,values)
                @test result.coordinates.left.parameter_space===:unit_logit
                @test result.coordinates.right.parameter_space===:unit_logit
                @test result.coordinates.left.fixed==(request.left=="rater[1]")
                @test result.coordinates.right.fixed==(request.right=="rater[1]")
                @test result.model_contract.family===:mfrm
                @test result.model_contract.thresholds===thresholds
                @test result.chain_ids==fitted.chain_ids && result.iterations==fitted.iterations
                @test result.sampling_warning && !result.whole_fit_diagnostics.passed
                @test result.n_retained_draws==40 && result.new_fits==0
                @test isequal(result.summary, B.posterior_contrast(values,zeros(40);
                    chains=2,interval=.95,rope=(-.005,.005)))
                @test B._prediction_check_seal(result,"bayesianmgmfrm.posterior_contrast.v1")===nothing
            end
            @test fitted.draws==before
            # Paired uncertainty must not become a difference of marginal endpoints.
            difference=B.posterior_contrast(fitted;left="person[1]",right="person[2]",interval=.95)
            @test !isapprox(difference.summary.lower,
                quantile(column("person[1]"),.025)-quantile(column("person[2]"),.975);atol=1e-5)
            for request in ((;left="person[1]",right="person[1]"),
                    (;left="person[1]",right="rater[2]"),
                    (;left="item[1]",right="item[2]"),
                    (;left="person[missing]",right="person[2]"),
                    (;left="rater[2]",right="rater[1]",operation=:log_ratio))
                @test_throws ArgumentError B.posterior_contrast(fitted;request...)
            end
        end
        anchored=reporting_fit(:mfrm;chains=2,ndraws=20,
            anchors=[(;block=:rater,level=1,value=.75,type=:hard)])
        result=B.posterior_contrast(anchored;left="rater[1]",right="rater[2]",interval=.95)
        values=0.75 .- anchored.draws[:,only(findall(==("rater[2]"),anchored.design.parameter_names))]
        @test result.coordinates.left.fixed && !result.coordinates.right.fixed
        @test result.summary.mean≈mean(values)
        @test result.summary.lower≈quantile(values,.025) atol=1e-14
        @test result.summary.upper≈quantile(values,.975) atol=1e-14
        both=reporting_fit(:mfrm;chains=2,ndraws=20,anchors=[
            (;block=:rater,level=1,value=.75,type=:hard),
            (;block=:rater,level=2,value=-.25,type=:hard)])
        @test_throws ArgumentError B.posterior_contrast(both;left="rater[1]",right="rater[2]")
        malformed=reporting_fit(:mfrm;chains=2,ndraws=20)
        malformed.chain_ids[1]=2
        @test_throws ArgumentError B.posterior_contrast(malformed;left="person[1]",right="person[2]")
        @test_throws MethodError B.posterior_contrast(reporting_fit(:gmfrm);
            left="rater[1]",right="rater[2]")
    end
    @testset "Normalized saved posterior contrasts" begin
        record=F.synthetic_record(F.target())
        for model in (:exchangeable,:source)
            fitted=normalized_fixture(record;model)
            target=B._normalized_mgmfrm_target(fitted)
            raw=fitted.record.run.draws
            blocks=target.base.blueprint.blocks
            # Independently reconstruct last-rater severity and log consistency.
            severity=-vec(sum(raw[:,blocks[:rater_free]];dims=2)) - raw[:,first(blocks[:rater_free])]
            logratio=-vec(sum(raw[:,blocks[:log_rater_consistency_free]];dims=2)) - raw[:,first(blocks[:log_rater_consistency_free])]
            requests=[
                (;left="person[1,First]",right="person[2,First]",operation=:difference),
                (;left="person[1,Second]",right="person[2,Second]",operation=:difference),
                (;left="rater[3]",right="rater[1]",operation=:difference),
                (;left="rater_consistency[rater=3]",right="rater_consistency[rater=1]",operation=:log_ratio)]
            expected=[raw[:,1]-raw[:,3],raw[:,2]-raw[:,4],severity,logratio]
            for (request,values) in zip(requests,expected)
                result=B.posterior_contrast(fitted;request...,interval=.99,rope=(-.05,.05))
                @test result.summary.mean ≈ mean(values) atol=1e-13
                @test result.summary.lower ≈ quantile(values,.005) atol=1e-13
                @test result.summary.upper ≈ quantile(values,.995) atol=1e-13
                @test result.summary.event_rows[1].count == count(>(0),values)
                @test result.summary.event_rows[3].count == count(x->-.05<=x<=.05,values)
                @test result.sampling_warning && !result.whole_fit_diagnostics.passed
                @test result.source_sample_hash==fitted.record.content_hash
                @test result.chain_ids==fitted.record.run.chain_ids && result.iterations==fitted.record.run.iterations
                @test result.n_retained_draws==length(values) && result.new_fits==0
                @test result.summary.precision.quantiles[1].probability≈.005
                @test result.scientific_acceptance===:not_established
                opposite=B.posterior_contrast(fitted;left=request.right,right=request.left,
                    operation=request.operation,interval=.99,rope=(-.05,.05))
                @test opposite.summary.mean≈-result.summary.mean atol=1e-13
                @test opposite.summary.lower≈-result.summary.upper atol=1e-13
                if request.operation===:log_ratio
                    @test result.summary.ratio_interval.lower≈exp(result.summary.lower)
                    @test result.summary.scale===:log_ratio
                end
            end
            wrapped=saved_mgmfrm_contrast(fitted;kind=:ability,left="1",right="2",dimension="Second")
            @test wrapped.summary.mean≈mean(expected[2])
            wrapped=saved_mgmfrm_contrast(fitted;kind=:severity,left="3",right="1")
            @test wrapped.summary.mean≈mean(severity)
            wrapped=saved_mgmfrm_contrast(fitted;kind=:log_consistency_ratio,left="3",right="1")
            @test wrapped.summary.mean≈mean(logratio)
            @test !wrapped.whole_fit_diagnostics.passed
        end
        fitted=normalized_fixture(record)
        for request in (
                (;left="person[1,First]",right="person[1,First]"),
                (;left="unknown",right="person[2,First]"),
                (;left="person[1,First]",right="person[2,Second]"),
                (;left="person[1,First]",right="rater[1]"),
                (;left="person[1,First]",right="person[2,First]",operation=:log_ratio),
                (;left="rater_consistency[rater=1]",right="rater_consistency[rater=2]"),
                (;left="rater[1]",right="rater[2]",operation=:ratio),
                (;left="rater[1]",right="rater[2]",interval=1.),
                (;left="rater[1]",right="rater[2]",rope=(1.,-1.)))
            @test_throws ArgumentError B.posterior_contrast(fitted;request...)
        end
        @test_throws MethodError B.posterior_contrast(
            B.Experimental.CorrelatedMGMFRMFit(record;expected_identity=record.target_identity);
            left="rater[1]",right="rater[2]")
        d1=mfrm_spec(record.spec.data;family=:mgmfrm,thresholds=:partial_credit,
            dimensions=1,q_matrix=trues(4,1))
        restricted=B.Experimental.slope_restriction(d1;item_slopes=:fixed_one,rater_consistency=:fixed_one)
        prior=B.Experimental.NormalizedMGMFRMPrior(;prior_model=:exchangeable,record.prior.scales...)
        fixed=normalized_fixture(record;target=B._normalized_mgmfrm_target(restricted,prior))
        @test_throws ArgumentError B.posterior_contrast(fixed;
            left="rater_consistency[rater=1]",right="rater_consistency[rater=2]",operation=:log_ratio)
        @test B.posterior_contrast(fixed;left="rater[1]",right="rater[2]").summary.total_draws==40
        ability=B.posterior_contrast(fixed;left="person[1]",right="person[2]")
        @test ability.summary.mean≈mean(fixed.record.run.draws[:,1]-fixed.record.run.draws[:,2])
        @test isequal(saved_mgmfrm_contrast(fixed;kind=:ability,left="1",right="2",
            dimension=only(d1.dimension_labels)).summary,ability.summary)
        @test_throws ArgumentError saved_mgmfrm_contrast(fixed;kind=:ability,left="1",right="2")
        mktempdir() do directory
            path=joinpath(directory,"fit.jls");save_fit_cache(path,fitted)
            original=read(path)
            result=B.posterior_contrast(load_fit_cache(path);left="rater[3]",right="rater[1]")
            result_path=joinpath(directory,"contrast.jls");serialize(result_path,result)
            @test isequal(deserialize(result_path),result)
            @test read(path)==original
        end
    end
end
end
