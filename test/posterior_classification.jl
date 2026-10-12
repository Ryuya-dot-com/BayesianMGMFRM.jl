module PosteriorClassificationChecks
using BayesianMGMFRM, Test, Statistics, Serialization, Random
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks
const K=CommonPredictionKfoldChecks
function selected(fit)
    people=filter(r->r.block===:person && !r.fixed,B.recovery_quantities(fit).rows)
    [r.parameter for r in people if r.dimension==first(people).dimension]
end
function options(fit)
    common=(;view=:public,include_posterior_predictive=false,include_prior_predictive=false,
        include_waic=false,include_loo=false,include_artifact=false)
    fit isa B._ModelComparisonFit ? merge(common,(;include_category_functioning=false,
        include_rater_homogeneity=false,include_calibration=false)) : common
end
function checks(output)
@testset "Saved conditional classification" begin
    @testset "Exact finite posterior: dependence, rules and numerical error" begin
        same=[1. 1;1 1;1 1;-1 -1]
        apart=[1. 1;1 1;1 -1;-1 1]
        a=B._classification_events(same,0.,.75)
        b=B._classification_events(apart,0.,.75)
        @test a.probabilities==b.probabilities==[.75,.75]
        @test all(a.pass) && all(b.pass) # Equality at the probability boundary passes.
        @test mean(a.errors)==mean(b.errors)==.5
        @test mean(a.errors.>0)==.25
        @test mean(b.errors.>0)==.5 # Multiplying marginal probabilities would miss this.
        @test a.false_pass==[0,0,0,2] && a.false_fail==zeros(Int,4)
        failed=B._classification_events(same,0.,.8)
        @test !any(failed.pass) && failed.false_fail==[2,2,2,0]
        @test B._classification_events(zeros(4,1),0.,.5).probabilities==[1.]
        @test B._classification_events(same[:,2:-1:1],0.,.75).errors==a.errors
        long=Float64.(rand(MersenneTwister(24),1000).<.65)
        summary=B._classification_mean(long,2)
        @test summary.mcse.status===:available
        @test summary.mcse.value==B._posterior_mcse_value(reshape(long,500,2),Statistics.mean)
        @test .5<summary.mcse.value/sqrt(.65*.35/1000)<1.5
        @test B._classification_mean(long,1).mcse.status===:insufficient_chains
        @test B._classification_mean(long[1:8],2).mcse.status===:insufficient_draws
        constant=B._classification_mean(zeros(40),2)
        @test constant.mean==0 && ismissing(constant.mcse.value)
        @test constant.mcse.status===:degenerate_draws
        @test B._classification_mean(zeros(40),2;fixed=true).mcse.value==0
    end
    cases=K.fixture_cases()
    @test length(unique(typeof(c.fit) for c in cases))==8
    for (i,c) in enumerate(cases)
        fit=c.fit; parameters=selected(fit)
        request=(;parameters,cutoff=0.,pass_probability=.8,interval=.99)
        before=R.bytes(fit)
        result=B.posterior_classification(fit;request...)
        @test result.n_people==length(parameters)==result.n_pass+result.n_fail
        @test [r.parameter for r in result.rows]==parameters
        @test result.interval_probability==.99 && result.interval_method===:equal_tailed
        @test result.model_contract==B.recovery_quantities(fit).model_contract
        @test result.source_sample_hash==B.recovery_quantities(fit).source_sample_hash
        @test result.sampling_warning && result.status===:warning
        @test result.scope===:conditional_posterior_risk_not_known_truth_error_rate
        @test result.scientific_acceptance===:not_established
        @test B._prediction_check_seal(result,result.schema)===nothing
        @test result.cohort.expected_error_count.mean ≈ sum(r.error_probability.mean for r in result.rows)
        @test result.cohort.expected_error_count.mean ≈ result.cohort.expected_false_pass_count.mean+result.cohort.expected_false_fail_count.mean
        @test 0 <= result.cohort.probability_any_error.mean <= min(1,result.cohort.expected_error_count.mean)
        for row in result.rows
            @test row.error_probability.mean ≈ (row.decision===:pass ? 1-row.qualification_probability.mean : row.qualification_probability.mean)
            @test row.ability.lower<=row.ability.median<=row.ability.upper
            @test row.ability.sd>=0
        end
        single=B.posterior_classification(fit;parameters=parameters[1:1],cutoff=0.,pass_probability=.8)
        @test single.cohort.probability_any_error.mean==only(single.rows).error_probability.mean
        reversed=B.posterior_classification(fit;merge(request,(;parameters=reverse(parameters)))...)
        @test isequal(result.cohort,reversed.cohort)
        @test R.bytes(fit)==before
        report=fit_report(fit;options(fit)...,reporting=(;classification=request),require_complete=true)
        section=report.posterior_classification
        @test section.status===:computed
        @test section.source_result_hash==result.content_hash
        @test length(section.cohort_rows)==4
        @test any(r->r.section===:posterior_classification,fit_report_sections(report))
        @test occursin("Posterior qualification",fit_report_markdown(report))
        directory=joinpath(output,"report-$i")
        save_fit_report_bundle(directory,report;require_complete=true)
        loaded=load_fit_report_bundle(directory;require_complete=true)
        @test loaded["posterior_classification"]==B._json_export_value(section)
        @test isfile(joinpath(directory,"tables","posterior_classification__rows.json"))
        cache=joinpath(output,"fit-$i.jls");save_fit_cache(cache,fit)
        @test isequal(B.posterior_classification(load_fit_cache(cache);request...),result)
        serialize(joinpath(output,"case-$i.jls"),(;cache,request,result,directory))
    end
    fit=cases[1].fit; parameters=selected(fit)
    for bad in (String[],[first(parameters),first(parameters)],["absent"],[:person],"person")
        @test_throws ArgumentError B.posterior_classification(fit;parameters=bad,cutoff=0.,pass_probability=.8)
    end
    for cutoff in (NaN,Inf,true,"zero"), p in (.8,)
        @test_throws ArgumentError B.posterior_classification(fit;parameters,cutoff,pass_probability=p)
    end
    for p in (0.,1.,-.1,NaN,true,big"1e-1000",1-big"1e-50")
        @test_throws ArgumentError B.posterior_classification(fit;parameters,cutoff=0.,pass_probability=p)
    end
    for interval in (0.,1.,NaN,true,big"1e-1000",1-big"1e-50")
        @test_throws ArgumentError B.posterior_classification(fit;parameters,cutoff=0.,pass_probability=.8,interval)
    end
    @test_throws UndefKeywordError B.posterior_classification(fit;parameters,cutoff=0.)
    for c in cases
        catalog=B.recovery_quantities(c.fit).rows
        other=filter(r->r.block!==:person || r.fixed,catalog)
        @test_throws ArgumentError B.posterior_classification(c.fit;parameters=[first(other).parameter],cutoff=0.,pass_probability=.8)
        people=filter(r->r.block===:person && !r.fixed,catalog)
        length(unique(r.dimension for r in people))<2 && continue
        @test_throws ArgumentError B.posterior_classification(c.fit;parameters=[r.parameter for r in people],cutoff=0.,pass_probability=.8)
    end
    bad=deepcopy(fit);reverse!(bad.chain_ids)
    @test_throws ArgumentError B.posterior_classification(bad;parameters,cutoff=0.,pass_probability=.8)
    bad=deepcopy(cases[6].fit);bad.record.run.draws[1,1]+=1
    @test_throws ArgumentError B.posterior_classification(bad;parameters=selected(cases[6].fit),cutoff=0.,pass_probability=.8)
    invalid=(;parameters=["absent"],cutoff=0.,pass_probability=.8)
    report=fit_report(fit;options(fit)...,reporting=(;classification=invalid))
    @test report.posterior_classification.status===:error
    @test report.report_status!==:complete
    @test_throws ArgumentError fit_report(fit;options(fit)...,reporting=(;classification=invalid),require_complete=true)
    @test_throws ArgumentError fit_report(fit;options(fit)...,reporting=(;classification=(;unknown=true)))
    @test !hasproperty(fit_report(fit;options(fit)...),:posterior_classification)
    @test :posterior_classification ∉ names(B)
end
end
end
