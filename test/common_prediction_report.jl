using BayesianMGMFRM, Test, Statistics, Serialization, SHA, TOML
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/saved_mgmfrm_report.jl")
bytes(x)=(io=IOBuffer();serialize(io,x);take!(io))
function common_prediction_report_checks(output; historical_root=nothing)
mkpath(output)
started=time()
checks=@testset "Common prediction criteria in recorded MGMFRM reports" begin
    r=F.synthetic_record(F.target())
    fits=[normalized_fixture(r),B.Experimental.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity)]
    # User IDs must survive the public prose filter verbatim.
    ids=["_rating_$i" for i in 1:r.spec.data.n];ids[2]="internal rating 2"
    opts=(;dataset_id="internal study",observation_ids=ids,include_waic=true,include_loo=true)
    for (i,fit) in enumerate(fits)
        @info "Checking full/public report, MCSE, prediction criteria and persistence" fit_type=typeof(fit)
        before=bytes(fit)
        native=B.prediction_criteria(fit;dataset_id=opts.dataset_id,observation_ids=ids)
        report=fit_report(fit;opts...,view=:full,draw_indices=[40,1,1],include_artifact=false,require_complete=true)
        @test report.report_status===:complete
        @test !report.diagnostics.summary.passed
        @test report.posterior_predictive.n_replicates==3
        @test report.waic.n_retained_draws==report.loo.n_retained_draws==40
        for (name,criterion) in ((:waic,:waic),(:loo,:raw_loo))
            section=getproperty(report,name)
            @test section.status===:computed
            @test section.criterion===criterion
            @test isequal(section.stat,getproperty(native.scores,criterion))
            @test section.sampling_warning
            @test section.problem_observation_ids==getproperty(native.problem_observation_ids,criterion)
            @test section.observation_ids==ids
            @test section.source_sample_hash==fit.record.content_hash
            @test section.uncertainty.mcmc_mcse===:not_computed
            @test section.scientific_acceptance===:not_established
            @test !isempty(section.warning_rows)
            @test getproperty.(section.diagnostic_rows,:observation_id)==ids
            @test section.n_problem_rows>0
            @test section.n_problem_rows==length(section.problem_observation_ids)
            @test getproperty.(section.problem_rows,:observation_id)==section.problem_observation_ids
            @test all(row->row.flag!==:ok,section.problem_rows)
        end
        ordinary=fit_report(fit;view=:full,include_artifact=false,include_posterior_predictive=false)
        @test ordinary.waic.status===ordinary.loo.status===:not_requested
        @test ordinary.calibration.status===:unsupported
        @test isequal(ordinary.diagnostics,report.diagnostics)
        @test isequal(ordinary.direct_posterior,report.direct_posterior)
        native_mcse=posterior_mcse(fit)
        by_name=Dict(row.parameter=>row for row in report.direct_posterior.mcse_rows)
        @test all(row->isequal(by_name[row.parameter].mean_mcse,row.mean_mcse),native_mcse)
        @test all(row->isequal(by_name[row.parameter].sd_mcse,row.sd_mcse),native_mcse)
        public=fit_report_public(report)
        for name in (:waic,:loo)
            section=getproperty(public,name)
            @test section.dataset_id==opts.dataset_id
            @test section.observation_ids==ids
            @test getproperty.(section.diagnostic_rows,:observation_id)==ids
            @test section.sampling_warning
        end
        markdown=fit_report_markdown(public;max_rows=2)
        @test occursin("Raw importance-sampling LOO",markdown)
        @test occursin("not crossed-cluster adjusted or MCMC MCSE",markdown)
        @test occursin("Whole-fit MCMC warnings remain",markdown)
        @test occursin("internal rating 2",markdown)
        directory=joinpath(output,"model-$i")
        save_fit_report_bundle(directory,public;require_complete=true,max_rows=2)
        restored=load_fit_report_bundle(directory;require_complete=true)
        @test restored["waic"]==B._json_export_value(public.waic)
        @test restored["loo"]==B._json_export_value(public.loo)
        @test isfile(joinpath(directory,"tables","waic__diagnostic_rows.json"))
        @test isfile(joinpath(directory,"tables","loo__warning_rows.json"))
        @test isfile(joinpath(directory,"tables","waic__problem_rows.json"))
        @test isfile(joinpath(directory,"tables","loo__problem_rows.json"))
        cache=joinpath(output,"model-$i.jls");save_fit_cache(cache,fit)
        saved=read(cache)
        replay=saved_mgmfrm_report(cache,joinpath(output,"replay-$i");
            dataset_id=opts.dataset_id,observation_ids=ids,draw_indices=[40,1,1])
        @test replay["waic"]==restored["waic"]
        @test replay["loo"]==restored["loo"]
        @test replay["diagnostics"]["summary"]["passed"]==false
        @test read(cache)==saved && bytes(fit)==before
    end
    @info "Checking explicit controls, input errors and isolated section failures"
    fit=first(fits)
    for bad in ((;include_waic=true),(;include_loo=true,dataset_id="x"),
        (;include_waic=true,dataset_id="",observation_ids=ids),
        (;include_loo=true,dataset_id="x",observation_ids=fill("same",length(ids))),
        (;dataset_id="unused",observation_ids=ids),
        (;opts...,loo_threshold=NaN),(;opts...,loo_tail_fraction=2.))
        @test_throws ArgumentError fit_report(fit;bad...)
    end
    # Deliberately tight diagnostic threshold exposes, rather than filters, IDs.
    tight=fit_report(fit;opts...,view=:full,include_artifact=false,include_posterior_predictive=false,loo_threshold=1e-12)
    @test tight.loo.criterion_warning!==:ok
    @test !isempty(tight.loo.problem_observation_ids)
    @test any(row->row.code===:criterion_warning,tight.loo.warning_rows)
    tight_public=fit_report_public(tight)
    @test tight_public.loo.problem_observation_ids==tight.loo.problem_observation_ids
    @test occursin("unstable weights",fit_report_markdown(tight_public))
    waic_only=fit_report(fit;dataset_id=opts.dataset_id,observation_ids=ids,include_waic=true,
        view=:full,include_artifact=false,include_posterior_predictive=false)
    @test waic_only.waic.status===:computed && waic_only.loo.status===:not_requested
    # WAIC can use two draws; LOO needs at least three. Keep WAIC when LOO fails.
    short_r=F.synthetic_record(F.target();chains=1,ndraws=2)
    short=normalized_fixture(short_r)
    partial=fit_report(short;opts...,view=:full,include_artifact=false,include_posterior_predictive=false)
    @test partial.waic.status===:computed
    @test partial.loo.status===:error
    @test partial.report_status===:incomplete
    @test partial.loo.exception===:ArgumentError
    @test_throws ArgumentError fit_report(short;opts...,include_artifact=false,include_posterior_predictive=false,require_complete=true)
    @test_throws ArgumentError fit_report(short;opts...,include_artifact=false,include_posterior_predictive=false,on_section_error=:throw)
    # Existing comparison APIs retain their previously checked behavior.
    comparison=B.compare_predictions("independent"=>fits[1],"correlated"=>fits[2];
        comparison_axis=:model,dataset_id=opts.dataset_id,observation_ids=ids)
    @test comparison.rows[1].elpd≈waic_only.waic.stat.elpd_waic
    @test comparison.rows[1].sampling_warning==waic_only.waic.sampling_warning
    legacy=reporting_fit(:mfrm;chains=2,ndraws=20,warmup=0)
    old=fit_report(legacy;include_prior_predictive=false,include_posterior_predictive=false,
        include_category_functioning=false,include_rater_homogeneity=false,include_calibration=false,include_artifact=false)
    @test old.waic.status===:computed && old.loo.status===:computed
    if historical_root!==nothing
        @info "Replaying the existing normalized walkthrough; no new fit"
        previous=historical_root;cache=joinpath(previous,"fit.jls");before=read(cache)
        existing=load_fit_cache(cache)
        n=fit_metadata(existing).n_observations
        saved_mgmfrm_report(cache,joinpath(output,"walkthrough-replay");dataset_id="normalized-walkthrough",
            observation_ids=["walkthrough-rating-$i" for i in 1:n],draw_indices=[1,2,2])
        replay=load_fit_report_bundle(joinpath(output,"walkthrough-replay");require_complete=true)
        historical=load_fit_report_bundle(joinpath(previous,"report");require_complete=true)
        @test read(cache)==before
        @test replay["diagnostics"]["summary"]==historical["diagnostics"]["summary"]
        @test replay["direct_posterior"]==historical["direct_posterior"]
        @test replay["waic"]["status"]=="computed"
        @test replay["waic"]["n_retained_draws"]==24
        @test historical["waic"]["status"]=="unsupported"
        @test replay["waic"]["sampling_warning"]
    end
end
counts=Test.get_test_counts(checks)
open(joinpath(output,"verification.toml"),"w") do io
    TOML.print(io,Dict("status"=>"passed","passed"=>counts.passes+counts.cumulative_passes,
        "seconds"=>time()-started,"new_posterior_fits"=>0,"candidate_source"=>pathof(B),
        "scope"=>"report/public projection/JSON/Markdown/table/cache integration; no new statistical acceptance"))
end
return checks
end

if abspath(PROGRAM_FILE)==@__FILE__
    common_prediction_report_checks(ARGS[1];historical_root=length(ARGS)>1 ? ARGS[2] : nothing)
end
