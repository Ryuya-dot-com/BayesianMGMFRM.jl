using BayesianMGMFRM, Test, Serialization, SHA, TOML
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
include("../examples/saved_mgmfrm_report.jl")
bytes(x)=(io=IOBuffer();serialize(io,x);take!(io))
function fixed_mfrm_report_checks(output, historical_root=nothing;
        cases=[(:independent,2),(:correlated,2),(:exchangeable,2),(:exchangeable_correlated,2),(:independent,3)])
mkpath(output)
started=time()
checks=@testset "Fixed-coefficient MFRM prediction report workflow" begin
    for (kind,D) in cases
        @info "Checking report, model identity, warnings and saved example" kind D
        fit=prediction_fixed_fixture(kind;D).fit
        before=bytes(fit);mcse=posterior_mcse(fit)
        n=B.PredictionObservationAdapter._fit_data(fit).n
        ids=["_rating_$i" for i in 1:n];ids[2]="internal rating 2"
        opts=(;dataset_id="internal study",observation_ids=ids,include_waic=true,include_loo=true)
        native=B.prediction_criteria(fit;opts.dataset_id,observation_ids=ids)
        report=fit_report(fit;opts...,view=:full,draw_indices=[40,1,1],include_artifact=false,require_complete=true)
        @test report.report_status===:complete
        @test report.posterior_predictive.n_replicates==3
        @test report.waic.n_retained_draws==report.loo.n_retained_draws==40
        @test report.family===:mfrm && report.dimensions==D
        @test report.metadata.target_identity==fit.record.target_identity
        for (name,criterion) in ((:waic,:waic),(:loo,:raw_loo))
            s=getproperty(report,name)
            @test s.status===:computed && s.criterion===criterion
            @test isequal(s.stat,getproperty(native.scores,criterion))
            @test s.source_sample_hash==fit.record.content_hash
            @test s.sampling_warning
            @test s.scientific_acceptance===:not_established
            @test s.uncertainty.mcmc_mcse===:not_computed
            @test s.observation_ids==ids
            @test getproperty.(s.diagnostic_rows,:observation_id)==ids
            @test s.problem_observation_ids==getproperty(native.problem_observation_ids,criterion)
            @test s.problem_rows==filter(row->row.flag!==:ok,s.diagnostic_rows)
        end
        ordinary=fit_report(fit;view=:full,include_artifact=false,include_posterior_predictive=false)
        @test ordinary.waic.status===ordinary.loo.status===:not_requested
        @test ordinary.calibration.status===ordinary.category_functioning.status===:unsupported
        for name in (:diagnostics,:posterior,:direct_posterior,:prior_policy,:pooling_policy,:q_matrix,:fixed_coordinates)
            @test isequal(getproperty(ordinary,name),getproperty(report,name))
        end
        @test isequal(posterior_mcse(fit),mcse)
        public=fit_report_public(report)
        @test public.waic.dataset_id==opts.dataset_id
        @test public.loo.observation_ids==ids
        md=fit_report_markdown(public;max_rows=2)
        @test occursin("Raw importance-sampling LOO",md)
        @test occursin("not crossed-cluster adjusted or MCMC MCSE",md)
        @test occursin("internal rating 2",md)
        dir=joinpath(output,"$kind-D$D")
        save_fit_report_bundle(dir,public;require_complete=true,max_rows=2)
        saved=load_fit_report_bundle(dir;require_complete=true)
        @test saved["waic"]==B._json_export_value(public.waic)
        @test saved["loo"]==B._json_export_value(public.loo)
        @test isfile(joinpath(dir,"tables","loo__problem_rows.json"))
        @test isfile(joinpath(dir,"tables","waic__diagnostic_rows.json"))
        cache=joinpath(output,"$kind-D$D.jls");save_fit_cache(cache,fit);cache_before=read(cache)
        replay=saved_mgmfrm_report(cache,joinpath(output,"replay-$kind-D$D");
            opts.dataset_id,observation_ids=ids,draw_indices=[40,1,1])
        @test replay["waic"]==saved["waic"] && replay["loo"]==saved["loo"]
        @test replay["prior_policy"]==saved["prior_policy"]
        @test replay["diagnostics"]==saved["diagnostics"]
        @test read(cache)==cache_before && bytes(fit)==before
    end
    @info "Checking invalid requests, individual criteria and section failure policy"
    legacy=prediction_fixed_fixture(:legacy).fit
    legacy_ids=string.(1:B.PredictionObservationAdapter._fit_data(legacy).n)
    @test B.prediction_criteria(legacy;dataset_id="legacy",observation_ids=legacy_ids).scores.waic.n_draws==40
    @test_throws ArgumentError fit_report(legacy;include_artifact=false)
    @test_throws ArgumentError fit_report(legacy;dataset_id="legacy",observation_ids=legacy_ids,include_waic=true)
    fit=prediction_fixed_fixture(:exchangeable_correlated).fit
    n=B.PredictionObservationAdapter._fit_data(fit).n;ids=string.(1:n)
    opts=(;dataset_id="errors",observation_ids=ids,include_waic=true,include_loo=true)
    reportopts=(;view=:full,include_artifact=false,include_posterior_predictive=false)
    for bad in ((;include_waic=true),(;include_loo=true,dataset_id="x"),
        (;opts...,dataset_id=" "),(;opts...,observation_ids=fill("same",n)),
        (;opts...,observation_ids=ids[1:end-1]),(;dataset_id="unused",observation_ids=ids),
        (;opts...,loo_threshold=NaN),(;opts...,loo_tail_fraction=2.))
        @test_throws ArgumentError fit_report(fit;reportopts...,bad...)
    end
    for (flag,name,other) in ((:include_waic,:waic,:loo),(:include_loo,:loo,:waic))
        report=fit_report(fit;reportopts...,dataset_id="one",observation_ids=ids,flag=>true)
        @test getproperty(report,name).status===:computed
        @test getproperty(report,other).status===:not_requested
    end
    tight=fit_report(fit;reportopts...,opts...,loo_threshold=1e-12)
    @test tight.loo.criterion_warning!==:ok
    @test !isempty(tight.loo.problem_rows)
    @test any(row->row.code===:criterion_warning,tight.loo.warning_rows)
    short=prediction_fixed_fixture(:exchangeable_correlated;ndraws=2,chains=1).fit
    partial=fit_report(short;reportopts...,opts...)
    @test partial.waic.status===:computed && partial.loo.status===:error
    @test partial.report_status===:incomplete
    @test_throws ArgumentError fit_report(short;reportopts...,opts...,require_complete=true)
    @test_throws ArgumentError fit_report(short;reportopts...,opts...,on_section_error=:throw)
    @info "Checking the changed shared accessor on both recorded MGMFRM types"
    r=F.synthetic_record(F.target())
    for existing in (normalized_fixture(r),B.Experimental.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity))
        eids=string.(1:r.spec.data.n)
        report=fit_report(existing;reportopts...,dataset_id="unchanged",observation_ids=eids,include_waic=true,include_loo=true)
        original=B.prediction_criteria(existing;dataset_id="unchanged",observation_ids=eids)
        @test isequal(report.waic.stat,original.scores.waic)
        @test isequal(report.loo.stat,original.scores.raw_loo)
    end
    if historical_root!==nothing
        @info "Replaying two historical 24-draw exchangeable records; no sampling"
        for backend in ("julia112/advancedhmc-true","cmdstan/cmdstan-true")
            path=joinpath(historical_root,backend,"samples.jls");before=read(path)
            record=open(deserialize,path)
            fit=B.Experimental.ExchangeableMFRMFit(record;expected_identity=record.target_identity)
            historical=B._read_json_dict(joinpath(historical_root,backend,"result.json"),"historical sample receipt")
            @test bytes2hex(sha256(before))==historical["file_sha256"]
            ids=string.(1:fit_metadata(fit).n_observations)
            report=fit_report(fit;reportopts...,dataset_id=backend,observation_ids=ids,include_waic=true,include_loo=true,require_complete=true)
            @test report.waic.n_retained_draws==24
            @test report.waic.sampling_warning
            @test B._json_export_value(report.diagnostics.summary)==historical["diagnostics"]["summary"]
            @test read(path)==before
            save_fit_report_bundle(joinpath(output,replace(backend,"/"=>"-")),report;require_complete=true)
        end
    end
end
counts=Test.get_test_counts(checks)
open(joinpath(output,"verification.toml"),"w") do io
    TOML.print(io,Dict("status"=>"passed","passed"=>counts.passes+counts.cumulative_passes,
        "seconds"=>time()-started,"new_posterior_fits"=>0,"candidate_source"=>pathof(B),
        "scope"=>"fixed-coefficient report/cache/public example and shared-accessor regression; no statistical acceptance"))
end
return checks
end

if abspath(PROGRAM_FILE)==@__FILE__
    fixed_mfrm_report_checks(ARGS[1],length(ARGS)>1 ? ARGS[2] : nothing)
end
