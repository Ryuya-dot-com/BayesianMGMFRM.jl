function boundary_checks(output,fit,recorded)
@testset "Explicit request, missing output and partial cohort boundaries" begin
    req=request(fit);opts=options(fit)
    omitted=fit_report(fit;opts...,reporting=(;))
    @test all(getproperty(omitted,n).status===:not_requested for n in (:category_report,:posterior_reliability,:rater_agreement))
    @test omitted.report_status===:complete
    single=fit_report(fit;opts...,reporting=(;reliability=[first(req.reliability)]))
    @test single.posterior_reliability.status===:computed
    @test single.category_report.status===single.rater_agreement.status===:not_requested
    for bad in (true,(;unknown=true),(;category=true),(;category=(;)),
        merge(req,(;observation_ids=fill("duplicate",length(req.observation_ids)))),
        merge(req,(;reliability=[first(req.reliability),first(req.reliability)])),
        merge(req,(;reliability=[(;id="",parameters=["x","y"],target=:centered)])),
        merge(req,(;category=(;dataset_id="other",interval=.99))))
        @test_throws ArgumentError fit_report(fit;opts...,reporting=bad)
    end
    failed=merge(req,(;category=(;max_prediction_cells=1),
        reliability=[first(req.reliability),(;id="_invalid",parameters=["unknown","also unknown"],target=:centered)]))
    partial=fit_report(fit;opts...,reporting=failed)
    @test partial.report_status===:incomplete
    @test partial.category_report.status===partial.posterior_reliability.status===:error
    @test partial.rater_agreement.status===:computed
    @test partial.posterior_reliability.n_requested_cohorts==2 && partial.posterior_reliability.n_failed_cohorts==1
    @test partial.posterior_reliability.rows[1].status===:computed
    @test partial.posterior_reliability.rows[2].status===:error && ismissing(partial.posterior_reliability.rows[2].reliability)
    @test partial.posterior_reliability.results[1].result.n_retained_draws==40
    public=fit_report_public(partial)
    @test public.posterior_reliability.rows[2].cohort_id=="_invalid"
    @test occursin("unknown reliability coordinate",public.posterior_reliability.rows[2].message)
    @test occursin("One or more reliability cohorts failed",fit_report_markdown(public))
    save_fit_report_bundle(joinpath(output,"partial"),public)
    loaded=load_fit_report_bundle(joinpath(output,"partial"))
    @test loaded["report_status"]=="incomplete"
    @test loaded["posterior_reliability"]==B._json_export_value(public.posterior_reliability)
    @test_throws ArgumentError load_fit_report_bundle(joinpath(output,"partial");require_complete=true)
    @test_throws ArgumentError fit_report(fit;opts...,reporting=failed,require_complete=true)
    @test_throws ArgumentError fit_report(fit;opts...,reporting=failed,on_section_error=:throw)
    missing_target=(;reliability=[(;id="missing-target",parameters=first(req.reliability).parameters)])
    missing_report=fit_report(fit;opts...,reporting=missing_target)
    @test missing_report.posterior_reliability.status===:error
    @test occursin("parameters and target",only(missing_report.posterior_reliability.rows).message)
    # Empty opportunity sets remain computable reports of unavailable quantities.
    no_overlap=merge(req,(;agreement=(;response_ids=req.observation_ids)))
    empty=fit_report(fit;opts...,reporting=no_overlap,require_complete=true)
    @test empty.rater_agreement.result_status===:no_common_units
    @test all(r->r.n_opportunities==0 && ismissing(r.expected_mean) &&
        ismissing(r.observed_rate) && r.mcse_status===:no_common_units,empty.rater_agreement.rows)
    @test any(r->r.code===:no_common_units,empty.rater_agreement.warning_rows)
    ep=fit_report_public(empty)
    save_fit_report_bundle(joinpath(output,"zero-overlap"),ep;require_complete=true)
    @test load_fit_report_bundle(joinpath(output,"zero-overlap"))["rater_agreement"]==B._json_export_value(ep.rater_agreement)
    # Fixed anchors/mixed dimensions remain the standalone API's explicit refusal.
    anchored=merge(first(req.reliability),(;id="anchor",parameters=["item[1]","item[2]"]))
    bad=fit_report(fit;opts...,reporting=(;reliability=[anchored]))
    @test bad.posterior_reliability.status===:error
    @test occursin("anchors",only(bad.posterior_reliability.rows).message)
    ro=request(recorded); oo=options(recorded)
    mixed=(;id="mixed",parameters=[first(ro.reliability[1].parameters),first(ro.reliability[2].parameters)],target=:centered)
    rejected=fit_report(recorded;oo...,reporting=(;reliability=[mixed]))
    @test rejected.posterior_reliability.status===:error
    @test occursin("one location block, dimension and scale",only(rejected.posterior_reliability.rows).message)
    combined=fit_report(recorded;oo...,include_waic=true,reporting=ro,
        dataset_id=ro.dataset_id,observation_ids=ro.observation_ids)
    @test combined.waic.status===:computed && combined.category_report.status===:computed
    @test combined.waic.observation_ids==combined.category_report.result.observation_ids
    @test_throws ArgumentError fit_report(recorded;oo...,include_waic=true,reporting=ro,
        dataset_id="different",observation_ids=ro.observation_ids)
    @test_throws ArgumentError fit_report(recorded;oo...,include_waic=true,reporting=ro,
        dataset_id=ro.dataset_id,observation_ids=reverse(ro.observation_ids))
    selected=fit_report(recorded;oo...,include_posterior_predictive=true,draw_indices=[40,1,1],reporting=ro)
    @test selected.posterior_predictive.n_replicates==3
    @test selected.category_report.result.n_retained_draws==40
    @test selected.rater_agreement.result.n_retained_draws==40
    @test all(r->r.result.n_retained_draws==40,selected.posterior_reliability.results)
    @test_throws ArgumentError fit_report(R.prediction_fixed_fixture(:legacy).fit;reporting=ro)
end
end

function default_checks(output,fit)
@testset "Unprofiled category tables and legacy predictive section coexist" begin
    req=request(fit)
    report=fit_report(fit;options(fit)...,include_category_functioning=true,
        include_rater_homogeneity=true,rng=MersenneTwister(771),
        reporting=(;req.dataset_id,req.observation_ids,category=(;interval=.99)))
    @test report.category_functioning.status===report.category_report.status===:computed
    @test report.rater_homogeneity.status===:computed
    @test all(haskey(row,:fixed) for row in report.category_report.threshold_rows)
    @test report.rater_agreement.status===report.posterior_reliability.status===:not_requested
    @test report.category_report.result.predictive_interval===:not_computed
    @test isempty(report.category_report.curve_rows) && isempty(report.category_report.crossing_rows) && isempty(report.category_report.profile_rows)
    public=fit_report_public(report)
    directory=joinpath(output,"without-profiles");save_fit_report_bundle(directory,public;require_complete=true)
    loaded=load_fit_report_bundle(directory;require_complete=true)
    @test loaded["category_report"]==B._json_export_value(public.category_report)
    @test loaded["category_functioning"]==B._json_export_value(public.category_functioning)
    @test all(isfile(joinpath(directory,"tables",file)) for file in
        ("category_report__curve_rows.json","category_report__crossing_rows.json","category_report__profile_rows.json"))
end
end

function presentation_checks(fit)
@testset "Table rows preserve fixed constraints and agreement tolerance" begin
    @test ismissing(B._saved_summary_columns(nothing).fixed)
    fixed=B._category_report_summary(ones(40),2,.95;fixed=true)
    empirical=B._category_report_summary(ones(40),2,.95)
    @test B._saved_summary_columns(fixed).fixed && B._saved_summary_columns(fixed).mean_mcse==0
    @test !B._saved_summary_columns(empirical).fixed && ismissing(B._saved_summary_columns(empirical).mean_mcse)
    req=request(fit)
    all_categories=merge(req,(;category=nothing,reliability=(),agreement=merge(req.agreement,(;adjacent=2))))
    report=fit_report(fit;options(fit)...,reporting=all_categories)
    @test all(row->row.category_distance==(row.agreement===:exact ? 0 : 2),report.rater_agreement.rows)
    @test all(row->row.expected_mean==1,filter(r->r.agreement===:adjacent,report.rater_agreement.rows))
    public=fit_report_public(report)
    @test isequal(public.rater_agreement.rows,report.rater_agreement.rows)
    @test occursin("category_distance",fit_report_markdown(public))
end
end
