module CommonRecoveryEvaluationChecks
using BayesianMGMFRM, Test, Statistics, Serialization
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks
const K=CommonPredictionKfoldChecks
include("../examples/saved_recovery_evaluation.jl")

# Separate native consumers provide coordinate and public summary/MCSE oracles.
native(fit::B._ModelComparisonFit)=B._posterior_plot_coordinates(fit,:model)
native(fit::B._RecordedMGMFRMFit)=B._mgmfrm_correlated_2d_report_coordinates(B._mgmfrm_correlated_2d_report_context(fit))
native(fit::B._FixedQMFRMFit)=B._fixed_q_report_samples((;fit.record)).model_coordinates
ids(fit)=["row-$i" for i in 1:B.PredictionObservationAdapter._fit_data(fit).n]
evaluate(fit,truth;kwargs...)=B.recovery_evaluation(fit,truth;dataset_id="synthetic-recovery",observation_ids=ids(fit),kwargs...)

function fit_checks(fit,index,output)
    @testset "Saved fit $index: recovery quantities, native arithmetic and MCSE" begin
        coordinates=native(fit)
        truth=Dict(r.parameter=>Float64(first(r.values)) for r in coordinates)
        before=R.bytes((fit,truth))
        catalog=B.recovery_quantities(fit)
        result=evaluate(fit,truth;interval=.9)
        @test [r.parameter for r in result.rows]==[r.parameter for r in coordinates]==[r.parameter for r in catalog.rows]
        @test all(r->isapprox(r.posterior_mean,mean(coordinates[r.parameter_index].values);atol=1e-12),result.rows)
        @test all(r->isapprox(r.posterior_sd,std(coordinates[r.parameter_index].values);atol=1e-12),result.rows)
        @test all(r->isapprox(r.posterior_lower,quantile(coordinates[r.parameter_index].values,.05);atol=1e-12),result.rows)
        @test all(r->isapprox(r.posterior_upper,quantile(coordinates[r.parameter_index].values,.95);atol=1e-12),result.rows)
        @test all(r->isapprox(r.bias,r.posterior_mean-r.true_value;atol=1e-14),result.rows)
        @test all(r->r.squared_error==r.bias^2 && r.absolute_bias==abs(r.bias),result.rows)
        @test all(r->r.interval_width==r.posterior_upper-r.posterior_lower,result.rows)
        @test all(r->r.fixed ? ismissing(r.covered) && !r.coverage_applicable && r.fixed_value_matches_truth :
            r.coverage_applicable && r.covered==(r.posterior_lower<=r.true_value<=r.posterior_upper),result.rows)
        @test all(r->r.fixed ? r.mcse.mcse_status===:structurally_fixed && r.mcse.mean_mcse==0 : true,result.rows)
        @test result.n_retained_draws==40 && result.chain_ids==repeat(1:2;inner=20)
        @test result.iterations==repeat(1:20;outer=2)
        @test result.sampling_warning==B._prediction_sampling_warning(catalog.sampling_quality)
        @test result.scientific_acceptance===:not_established && !result.calibration_verified
        @test result.sbc===:not_performed && result.independent_replications===:not_verified
        @test result.uncertainty.replication_uncertainty===:not_computed
        @test result.source_sample_hash==catalog.source_sample_hash
        @test result.model_contract==catalog.model_contract
        @test R.bytes((fit,truth))==before
        public_mcse=Dict(r.parameter=>r for r in posterior_mcse(fit;probabilities=(.05,.5,.95)))
        for row in result.rows
            haskey(public_mcse,row.parameter) || continue
            expected=public_mcse[row.parameter]
            @test isequal(row.mcse.mean_mcse,expected.mean_mcse)
            @test isequal(row.mcse.sd_mcse,expected.sd_mcse)
            @test all(isequal(a.mcse,b.mcse) && a.probability≈b.probability
                for (a,b) in zip(row.mcse.quantiles,expected.quantiles))
        end
        estimated=first(filter(r->!r.fixed,result.rows))
        subset=evaluate(fit,Dict(estimated.parameter=>estimated.true_value);interval=.9)
        @test length(subset.rows)==1
        @test subset.rows[1].posterior_mean==estimated.posterior_mean
        @test subset.source_binding==result.source_binding
        @test subset.model_contract==result.model_contract
        @test subset.content_hash!=result.content_hash
        @test_throws ArgumentError evaluate(fit,Dict("unknown coordinate"=>0.))
        path=joinpath(output,"fit-$index.jls");save_fit_cache(path,fit)
        replay=saved_recovery_evaluation(path,truth;dataset_id=result.dataset_id,observation_ids=ids(fit),interval=.9)
        @test isequal(replay,result)
        @test B._prediction_check_seal(result,"bayesianmgmfrm.recovery_evaluation.v1")===nothing
        serialize(joinpath(output,"case-$index.jls"),(;path,truth,dataset_id=result.dataset_id,
            observation_ids=ids(fit),interval=.9,expected=result))
        return result
    end
end

function scale_checks(cases,results)
    @testset "Physical scales, constraints and transformed correlation" begin
        for i in (7,8,9,10,11)
            fit=cases[i].fit;result=results[i]
            persons=filter(r->r.block===:person,result.rows)
            raw=fit.record.run.draws
            @test [r.posterior_mean for r in persons]≈vec(mean(raw[:,1:length(persons)];dims=1))
            @test all(r->r.parameter_space===:unit_logit,persons)
            @test result.model_contract.category_contract.implementation_scale_constant==1
            fixed=filter(r->r.block in (:item_dimension_discrimination,:rater_consistency),result.rows)
            @test all(r->r.fixed && r.parameter_space===:dimensionless && ismissing(r.covered),fixed)
            # Only original unit-logit coordinates are appropriate for these truths.
            @test !isapprox(persons[1].posterior_mean/1.7,persons[1].posterior_mean;atol=1e-5)
        end
        for i in (4,5,6)
            @test results[i].model_contract.category_contract.implementation_scale_constant==1.7
        end
        for i in (6,8,10)
            raw=cases[i].fit.record.run.draws;rho=tanh.(raw[:,end])
            row=only(filter(r->r.block===:latent_correlation,results[i].rows))
            @test row.parameter_space===:correlation && !row.fixed
            @test row.posterior_mean≈mean(rho)
            @test row.posterior_lower≈quantile(rho,.05)
            @test row.posterior_upper≈quantile(rho,.95)
            @test !isapprox(row.posterior_mean,tanh(mean(raw[:,end]));atol=1e-8)
            persons=filter(r->r.block===:person,results[i].rows)
            @test [r.posterior_mean for r in persons]≈vec(mean(raw[:,1:length(persons)];dims=1))
        end
        for i in (3,4,5,6,7,8,9,10,11)
            coordinates=native(cases[i].fit)
            raters=filter(r->r.block===:rater,coordinates)
            @test all(isapprox.(last(raters).values,-sum(r.values for r in raters[1:end-1]);atol=1e-12))
            last_rater=only(filter(r->r.parameter==last(raters).parameter,results[i].rows))
            @test last_rater.posterior_sd≈std(-sum(r.values for r in raters[1:end-1]))
        end
        # GMFRM centers item difficulties, not rater severities.
        gmfrm=cases[2].fit;coordinates=native(gmfrm)
        items=filter(r->r.block===:item,coordinates)
        @test all(isapprox.(last(items).values,-sum(r.values for r in items[1:end-1]);atol=1e-12))
        raters=filter(r->r.block===:rater,coordinates)
        @test !all(isapprox.(last(raters).values,-sum(r.values for r in raters[1:end-1]);atol=1e-12))
        @test [r.posterior_mean for r in results[2].rows if r.block===:rater]≈
            vec(mean(gmfrm.draws[:,B._gmfrm_source_unconstrained_blueprint(gmfrm.design).blocks[:rater]];dims=1))
        @test all(r->r.parameter_space===:dimensionless,filter(r->r.block in
            (:item_discrimination,:rater_consistency),results[2].rows))
        # Same three legacy fitted-coordinate values still agree with the old API.
        for i in 1:3
            fit=cases[i].fit
            names=fit isa MFRMFit ? fit.design.parameter_names : fit.diagnostic_surface.direct_parameter_names
            truth=Dict(r.parameter=>r.true_value for r in results[i].rows)
            old=parameter_recovery(fit,[truth[name] for name in names];interval=.9)
            new=Dict(r.parameter=>r for r in results[i].rows)
            @test all(r->r.posterior_mean==new[r.parameter].posterior_mean &&
                r.posterior_lower==new[r.parameter].posterior_lower && r.bias==new[r.parameter].bias,old)
        end
    end
end

function boundary_checks(cases,results)
    @testset "Recovery input and interpretation boundaries" begin
        fit=cases[1].fit;name=first(results[1].rows).parameter
        for truth in (Dict(),Dict(:not_a_string=>0.),Dict(" "=>0.),Dict(name=>NaN),
                Dict(name=>Inf),Dict(name=>true),Dict(name=>"zero"))
            @test_throws ArgumentError evaluate(fit,truth)
        end
        @test_throws ArgumentError evaluate(fit,Dict(name=>0.);interval=1.)
        @test_throws ArgumentError B.recovery_evaluation(fit,Dict(name=>0.);dataset_id=" ",observation_ids=ids(fit))
        @test_throws ArgumentError B.recovery_evaluation(fit,Dict(name=>0.);dataset_id="a",observation_ids=fill("same",length(ids(fit))))
        @test_throws ArgumentError B.recovery_evaluation(fit,Dict(name=>0.);dataset_id="a",observation_ids=ids(fit)[1:end-1])
        changed=deepcopy(fit);reverse!(changed.chain_ids)
        @test_throws ArgumentError evaluate(changed,Dict(name=>0.))
        changed=deepcopy(fit);reverse!(changed.iterations)
        @test_throws ArgumentError evaluate(changed,Dict(name=>0.))
        changed=deepcopy(cases[6].fit);changed.record.run.draws[1,1]+=1
        @test_throws ArgumentError evaluate(changed,Dict(first(results[6].rows).parameter=>0.))
        bad=deepcopy(results[1]);bad.rows[1]=merge(bad.rows[1],(;true_value=999.))
        @test_throws ArgumentError B._prediction_check_seal(bad,"bayesianmgmfrm.recovery_evaluation.v1")
        fixed=first(filter(r->r.fixed,results[7].rows))
        mismatch=evaluate(cases[7].fit,Dict(fixed.parameter=>fixed.true_value+.5))
        @test mismatch.fixed_truth_mismatch && mismatch.status===:warning
        @test only(mismatch.rows).flag===:fixed_truth_mismatch
        @test ismissing(only(mismatch.rows).covered) && !only(mismatch.rows).coverage_applicable
        @test only(mismatch.rows).bias==-.5
        short=R.reporting_fit(:mfrm;ndraws=4,chains=1,warmup=0)
        row=first(B.recovery_quantities(short).rows)
        unresolved=evaluate(short,Dict(row.parameter=>0.))
        @test unresolved.mcse_warning
        @test only(unresolved.rows).mcse.mcse_status===:insufficient_chains
        @test ismissing(only(unresolved.rows).mcse.mean_mcse)
        legacy=R.prediction_fixed_fixture(:legacy).fit
        @test_throws ArgumentError B.recovery_quantities(legacy)
        @test_throws ArgumentError evaluate(legacy,Dict("person[1,dim=1]"=>0.))
        rho=only(filter(r->r.block===:latent_correlation,results[6].rows)).parameter
        @test_throws ArgumentError evaluate(cases[6].fit,Dict(rho=>1.01))
        @test_throws ArgumentError evaluate(cases[6].fit,Dict(rho=>-1.01))
        @test only(evaluate(cases[6].fit,Dict(rho=>1.)).rows).true_value==1.
        @test only(evaluate(cases[6].fit,Dict(rho=>-1.)).rows).true_value== -1.
        # Named input order is irrelevant; data/identity changes stay visible.
        truth=Dict(r.parameter=>r.true_value for r in results[1].rows)
        reversed=Dict(reverse(collect(truth)))
        @test isequal(evaluate(fit,reversed;interval=.9),results[1])
        different=B.recovery_evaluation(fit,truth;dataset_id="different",observation_ids=ids(fit),interval=.9)
        @test different.source_binding!=results[1].source_binding
        @test different.model_contract==results[1].model_contract
    end
end

function checks(output)
    cases=K.fixture_cases()
    @test length(unique(typeof(c.fit) for c in cases))==8
    results=[fit_checks(c.fit,i,output) for (i,c) in enumerate(cases)]
    scale_checks(cases,results)
    boundary_checks(cases,results)
end
end
