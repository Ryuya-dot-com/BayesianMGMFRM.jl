module SavedReportingChecks
using BayesianMGMFRM,Test,Serialization,Random
import ..CommonPredictionRefitChecks, ..CommonPredictionKfoldChecks
const B=BayesianMGMFRM
const R=CommonPredictionRefitChecks
const K=CommonPredictionKfoldChecks
include("../examples/saved_integrated_report.jl")
function options(fit)
    common=(;view=:full,include_posterior_predictive=false,include_prior_predictive=false,
        include_waic=false,include_loo=false,include_artifact=false)
    fit isa B._ModelComparisonFit ? merge(common,(;include_category_functioning=false,
        include_rater_homogeneity=false,include_calibration=false)) : common
end
function request(fit)
    context=B._recovery_context(fit);spec=context.spec;data=spec.data
    ids=["_rating_$n" for n in 1:data.n]
    cohorts=[(;id="internal cohort $d",parameters=[r.parameter for r in context.coordinates if
        r.block===:person && (spec.dimensions==1 || r.dimension==d) && !r.fixed],target=:centered) for d in 1:spec.dimensions]
    profile=(;id="_profile_1",item=first(data.item_levels),rater=first(data.rater_levels),dimension=1,
        ability_grid=[-1.,0.,1.],fixed_abilities=Dict(d=>0. for d in 2:spec.dimensions))
    (;dataset_id="internal dataset",observation_ids=ids,category=(;interval=.99,profiles=[profile]),
        agreement=(;response_ids=["_response_$(data.person[n])" for n in 1:data.n],interval=.99,se_unit=:person),
        reliability=cohorts)
end
function fit_checks(fit,i,output;check_native=true)
@testset "Integrated report variant $i" begin
    opts=options(fit);req=request(fit);before=R.bytes(fit)
    old=check_native ? fit_report(fit;opts...) : nothing
    report=fit_report(fit;opts...,reporting=req,require_complete=true)
    if check_native
    @test R.bytes(fit)==before
    @test report.report_status===:complete
    @test !hasproperty(old,:category_report) && !hasproperty(old,:posterior_reliability) && !hasproperty(old,:rater_agreement)
    @test all(getproperty(report,key).status===:computed for key in (:category_report,:posterior_reliability,:rater_agreement))
    @test isequal(old.diagnostics,report.diagnostics)
    @test isequal(old.posterior,report.posterior)
    category=B.category_report(fit;req.dataset_id,req.observation_ids,req.category...)
    agreement=B.rater_agreement(fit;req.dataset_id,req.observation_ids,req.agreement...)
    for (section,result) in ((report.category_report,category),(report.rater_agreement,agreement))
        @test section.source_result_hash==result.content_hash
        @test isequal(section.result,B._saved_result_payload(result).result)
        @test section.result.n_retained_draws==40
        @test section.result.chain_ids==result.chain_ids && section.result.iterations==result.iterations
        @test !haskey(section.result,:content_hash)
    end
    for (cohort,result) in zip(req.reliability,report.posterior_reliability.results)
        native=B.posterior_reliability(fit;Base.structdiff(cohort,(;id=nothing))...)
        @test result.source_result_hash==native.content_hash
        @test isequal(result.result,B._saved_result_payload(native).result)
    end
    @test report.report_policy.reporting.observation_ids==req.observation_ids
    @test report.category_report.usage_rows[1].expected_mean==category.usage_rows[1].expected.mean
    @test report.rater_agreement.rows[1].observed_count==agreement.overall.exact.observed_count
    @test report.rater_agreement.rows[1].n_opportunities==agreement.overall.n_opportunities
    end
    public=fit_report_public(report)
    for name in (:category_report,:posterior_reliability,:rater_agreement)
        section=getproperty(public,name)
        @test section.status===:computed
        @test isequal(section.warning_rows,getproperty(report,name).warning_rows)
        @test any(row->row.section===name,fit_report_sections(public))
    end
    @test public.category_report.result.observation_ids==req.observation_ids
    @test only(public.category_report.profile_rows).id=="_profile_1"
    @test public.rater_agreement.result.response_ids==req.agreement.response_ids
    @test public.posterior_reliability.rows[1].cohort_id=="internal cohort 1"
    @test public.posterior_reliability.results[1].request.parameters==req.reliability[1].parameters
    markdown=fit_report_markdown(public;max_rows=2)
    for phrase in ("Conditional expected category use","Finite-cohort posterior reliability",
        "unordered rating-pair opportunities","Every original retained draw","internal cohort 1")
        @test occursin(phrase,markdown)
    end
    @test occursin("Warnings",markdown)
    directory=joinpath(output,"report-$i");save_fit_report_bundle(directory,public;require_complete=true,max_rows=2)
    loaded=load_fit_report_bundle(directory;require_complete=true)
    for name in (:category_report,:posterior_reliability,:rater_agreement)
        @test loaded[String(name)]==B._json_export_value(getproperty(public,name))
    end
    for file in ("category_report__usage_rows.json","category_report__profile_rows.json",
        "posterior_reliability__coordinate_rows.json","rater_agreement__rows.json")
        @test isfile(joinpath(directory,"tables",file))
    end
    cache=joinpath(output,"fit-$i.jls");save_fit_cache(cache,fit)
    serialize(joinpath(output,"case-$i.jls"),(;cache,request=req,options=opts,public,full=report))
end
end
include("saved_reporting_edges.jl")

function checks(output)
    cases=K.fixture_cases()
    @test length(unique(typeof(c.fit) for c in cases))==8
    for (i,c) in enumerate(cases)
        fit_checks(c.fit,i,output)
    end
    boundary_checks(output,cases[1].fit,cases[4].fit)
    default_checks(output,cases[1].fit)
    presentation_checks(cases[1].fit)
end
end
