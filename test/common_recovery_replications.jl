module CommonRecoveryReplicationChecks
using BayesianMGMFRM, Test, Statistics, Serialization
const B = BayesianMGMFRM
include("../examples/saved_recovery_replications.jl")
const INDEPENDENT = (status=:declared_independent, evidence="deterministic arithmetic fixture, not actual independent simulations")
const UNKNOWN = (status=:unresolved, evidence="independent generation not checked")

# Primitive sealed records isolate aggregation from fitting and native extraction.
function row(name, error; truth=0., width=2., fixed=false, mcse_status=:available)
    return (; parameter=name, block=:person, dimension=nothing, dimension_label=nothing,
        fixed, derived=false, parameter_space=:unit_logit, true_value=truth,
        bias=error, squared_error=error^2, absolute_bias=abs(error), interval_width=width,
        covered=fixed ? missing : abs(error)<=width/2,
        fixed_value_matches_truth=fixed ? error==0 : missing,
        mcse=(; mcse_status, mean_mcse=.01))
end

function evaluation(id, rows; warning=false, mismatch=false, target=id, drawhash=id, sourcehash=nothing,
        interval=.95, prior=(; sd=1.))
    return B._prediction_seal((; schema="bayesianmgmfrm.recovery_evaluation.v1", dataset_id=id, rows,
        source_binding="source-$id", source_sample_hash=sourcehash, evaluated_draws_hash=drawhash,
        model_contract=(; family=:mfrm, dimensions=1, prior,
            fitted_target=(; kind=:fixture, identity=target)),
        interval_probability=interval, sampling_warning=warning, fixed_truth_mismatch=mismatch,
        mcse_warning=any(r -> !r.fixed && r.mcse.mcse_status!==:available, rows),
        status=warning || mismatch ? :warning : :descriptive))
end
reseal(e; kwargs...) = B._prediction_seal(merge(Base.structdiff(e,(;content_hash=nothing)),(;kwargs...)))
function summarize(es; ids=["D1","D2","D3"], parameters=["theta"], independence=INDEPENDENT, kwargs...)
    B.recovery_replications(es; planned_dataset_ids=ids, parameters,
        scenario_id="fixed-cell", dataset_independence=independence, kwargs...)
end

function precision_checks(directory)
    limits = Dict("theta"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02))
    function precise(id; mean_mcse=.01, lower_mcse=.02, upper_mcse=.02,
            status=:available, warning=false, mismatch=false, interval=.95, fixed=false)
        lower,upper = (1-interval)/2,(1+interval)/2
        r = row("theta",.5;fixed,mcse_status=status)
        r = merge(r,(;mcse=merge(r.mcse,(;mean_mcse,
            quantiles=((;probability=lower,mcse=lower_mcse),(;probability=.5,mcse=100.),
                       (;probability=upper,mcse=upper_mcse))))))
        evaluation(id,[r];warning,mismatch,interval)
    end
    @testset "Explicit mean and central-endpoint MCSE limits" begin
        es = [precise("P"), precise("M";mean_mcse=.01001),
            precise("L";lower_mcse=.02001),precise("U";upper_mcse=.02001),
            precise("A";status=:insufficient_draws),precise("W";warning=true),
            precise("X";mismatch=true),evaluation("Q",[row("other",0.)])]
        ids = ["P","M","L","U","A","W","X","Q","F","Z"]
        old = summarize(es;ids,failures=["F"=>"fit interrupted"])
        before = deepcopy(es)
        result = summarize(es;ids,failures=["F"=>"fit interrupted"],mcse_limits=limits)
        s = only(result.summaries);q = s.precision_qualified
        @test isequal(es,before)
        @test isequal(s.all_completed,only(old.summaries).all_completed)
        @test isequal(s.without_warnings,only(old.summaries).without_warnings)
        @test s.without_warnings.n_datasets == 4 && q.n_datasets == 1
        @test (q.n_planned,q.n_unresolved) == (10,9)
        @test (result.n_completed,result.n_failed,result.n_missing) == (8,1,1)
        @test getproperty.(s.precision_dispositions,:status) ==
            [:passed,:mcse_exceeded,:mcse_exceeded,:mcse_exceeded,:mcse_unavailable,
             :sampling_warning,:fixed_truth_mismatch,:missing_quantity,:failed,:missing]
        @test s.precision_dispositions[6].mcse_status === :passed
        @test !s.precision_dispositions[6].passed
        @test q.bias.estimate == .5 && q.rmse.estimate == .5
        @test q.all_planned_coverage_bounds == (.1,1.)
        @test q.conditional_on_retained_datasets && !q.full_planned_continuous_performance_available
        @test q.bias.replication_se_status === :insufficient_replications
        @test result.uncertainty.precision_threshold === :absolute_focal_mean_and_central_endpoints
        @test !result.calibration_verified && result.scientific_acceptance === :not_established
        @test result.mcse_limits == limits
        @test !haskey(old,:mcse_limits) && !haskey(only(old.summaries),:precision_qualified)
        @test isequal(old,summarize(es;ids,failures=["F"=>"fit interrupted"],mcse_limits=nothing))
        @test isequal(result,summarize(reverse(es);ids,failures=["F"=>"fit interrupted"],mcse_limits=limits))
        for value in (missing,NaN,Inf,-.01,true)
            r=summarize([precise("P";lower_mcse=value)];ids=["P"],mcse_limits=limits)
            @test only(only(r.summaries).precision_dispositions).status === :mcse_unavailable
            @test only(r.summaries).precision_qualified.n_datasets == 0
        end
        # Missing endpoint information cannot pass just because mean MCSE exists.
        r=summarize([evaluation("P",[row("theta",0.)])];ids=["P"],mcse_limits=limits)
        @test only(only(r.summaries).precision_dispositions).status === :mcse_unavailable
        for interval in (.90,.99)
            r=summarize([precise("P";interval)];ids=["P"],mcse_limits=limits)
            @test only(r.summaries).precision_qualified.n_datasets == 1
            @test only(only(r.summaries).precision_dispositions).endpoint_probabilities == ((1-interval)/2,(1+interval)/2)
        end
        fixed=summarize([precise("P";fixed=true)];ids=["P"],mcse_limits=limits)
        @test only(fixed.summaries).precision_qualified === nothing
        @test only(only(fixed.summaries).precision_dispositions).status === :structurally_fixed
        empty=summarize([];ids=["P"],mcse_limits=limits)
        @test only(empty.summaries).precision_qualified.all_planned_coverage_bounds == (0.,1.)
        @test ismissing(only(empty.summaries).precision_qualified.bias.estimate)
        reused=summarize([es[1],reseal(es[1];dataset_id="D2")];ids=["P","D2"],mcse_limits=limits)
        @test only(reused.summaries).precision_qualified.n_datasets == 2
        @test only(reused.summaries).precision_qualified.bias.replication_se_status === :independence_unresolved
        for bad in (Dict(),Dict("other"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02)),
                Dict("theta"=>(;mean_mcse_max=.01)),(;theta=(;mean_mcse_max=.01,endpoint_mcse_max=.02)))
            @test_throws ArgumentError summarize(es;ids,mcse_limits=bad)
        end
        for bad in (true,0.,-.01,Inf,NaN,big"1e400",big"1e-400")
            @test_throws ArgumentError summarize(es;ids,mcse_limits=Dict("theta"=>(;mean_mcse_max=bad,endpoint_mcse_max=.02)))
        end
        path=joinpath(directory,"precision-summary.jls")
        serialize(path,result)
        @test isequal(deserialize(path),result)
        @test B._prediction_check_seal(deserialize(path),"bayesianmgmfrm.recovery_replications.v1") === nothing
    end
end

function width_review_checks(directory)
    limits=Dict("theta"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02))
    function width_record(id,width;warning=false,mean_mcse=.01,interval=.9,fixed=false)
        r=row("theta",0.;width,fixed)
        r=merge(r,(;mcse=(;mcse_status=:available,mean_mcse,
            quantiles=((;probability=(1-interval)/2,mcse=.02),
                (;probability=(1+interval)/2,mcse=.02)))))
        evaluation(id,[r];warning,interval)
    end
    function save_records(es)
        [begin
            path=joinpath(directory,"width-$(e.dataset_id).jls")
            serialize(path,e)
            path
        end for e in es]
    end
    function review(paths;ids,limit=1.,mcse_limits=limits,kwargs...)
        saved_recovery_width_review(paths;parameter="theta",max_interval_width=limit,
            mcse_limits,planned_dataset_ids=ids,scenario_id="width-fixture",
            dataset_independence=UNKNOWN,kwargs...)
    end
    @testset "Saved-width example keeps computation and measurement separate" begin
        es=[width_record("N",.5),width_record("E",1.),width_record("W",2.),
            width_record("G",.5;warning=true),width_record("M",.5;mean_mcse=.011),
            evaluation("Q",[row("other",0.)];interval=.9),
            evaluation("U",[row("theta",0.;width=.5)];interval=.9)]
        ids=["W","N","E","G","M","Q","U","F","Z"]
        paths=save_records(es)
        r=review(paths;ids,failures=["F"=>"interrupted"])
        rows=r.width_review
        @test getproperty.(rows,:dataset_id)==ids
        @test getproperty.(rows,:numerical_status)==
            [:passed,:passed,:passed,:sampling_warning,:mcse_exceeded,:missing_quantity,:mcse_unavailable,:failed,:missing]
        @test isequal(getproperty.(rows,:observed_width_within_target),
            [false,true,true,missing,missing,missing,missing,missing,missing])
        @test getproperty.(rows[1:3],:width_margin)==[-1.,.5,0.]
        @test rows[4].interval_width==.5 && !rows[4].numerically_qualified
        @test rows[5].mean_mcse==.011 && rows[5].endpoint_mcse==(.02,.02)
        @test all(x->ismissing(x.interval_width),rows[[6,8,9]])
        @test r.n_planned==9 && r.interval_probability==.9 && r.parameter_space===:unit_logit
        @test r.max_interval_width==1. && r.parameter=="theta"
        @test isequal(r.recovery,B.recovery_replications(es;parameters=["theta"],
            planned_dataset_ids=ids,scenario_id="width-fixture",dataset_independence=UNKNOWN,
            mcse_limits=limits,failures=["F"=>"interrupted"]))
        @test only(r.recovery.summaries).precision_qualified.n_unresolved==6
        @test isequal(deserialize.(paths),es)
        @test isequal(r,review(reverse(paths);ids,failures=["F"=>"interrupted"]))
        path=joinpath(directory,"width-review.jls");serialize(path,r)
        @test isequal(deserialize(path),r)
        for bad in (true,0.,-1.,NaN,Inf,"1",big"1e400",big"1e-400")
            @test_throws ArgumentError review(paths;ids,limit=bad)
        end
        @test_throws ArgumentError review(paths;ids,mcse_limits=nothing)
        @test_throws ArgumentError review(paths;ids,mcse_limits=Dict("other"=>limits["theta"]))
        fixed=review(save_records([width_record("C",0.;fixed=true)]);ids=["C"])
        @test only(fixed.width_review).numerical_status===:structurally_fixed
        @test ismissing(only(fixed.width_review).interval_width)
        @test ismissing(only(fixed.width_review).observed_width_within_target)
        empty=review(String[];ids=["Z"])
        @test empty.n_planned==1 && empty.interval_probability===nothing && empty.parameter_space===nothing
        @test only(empty.width_review).numerical_status===:missing
        @test ismissing(only(empty.width_review).observed_width_within_target)
        for interval in (.9,.99)
            r=review(save_records([width_record("I",1.;interval)]);ids=["I"])
            @test r.interval_probability==interval && only(r.width_review).interval_width==1.
        end
        @test_throws ArgumentError review(save_records([width_record("B",-1.)]);ids=["B"])
        changed=merge(es[1],(;interval_probability=.99))
        @test_throws ArgumentError review(save_records([changed]);ids=["N"])
    end
end

function width_target_checks(directory)
    limits = Dict("theta"=>(;mean_mcse_max=.01,endpoint_mcse_max=.02))
    widths = Dict("theta"=>1.)
    function record(id, width; warning=false, endpoint=.02, interval=.9, fixed=false)
        r=row("theta",0.;width,fixed)
        r=merge(r,(;mcse=(;mcse_status=:available,mean_mcse=.01,
            quantiles=((;probability=(1-interval)/2,mcse=endpoint),
                (;probability=(1+interval)/2,mcse=endpoint)))))
        evaluation(id,[r];warning,interval)
    end
    function target(es; ids=getproperty.(es,:dataset_id), kwargs...)
        summarize(es;ids,mcse_limits=limits,max_interval_widths=widths,kwargs...)
    end
    width_summary(r)=only(r.summaries).precision_qualified.width_target
    @testset "Planned-denominator interval-width targets" begin
        es=[record("N",.5),record("E",1.),record("W",2.)]
        before=deepcopy(es)
        r=target(es;ids=["N","E","W","F","Z"],failures=["F"=>"interrupted"])
        q=width_summary(r)
        @test (q.n_planned,q.n_qualified,q.n_meeting_target,q.n_exceeding_target,q.n_unresolved)==(5,3,2,1,2)
        @test q.conditional_frequency.estimate≈2/3
        @test q.conditional_frequency.replication_se≈1/3
        @test q.all_planned_frequency_bounds==(.4,.8)
        @test q.bounds_kind===:unresolved_outcome_envelope_not_confidence_interval
        @test q.classification_mcmc_error_bound===:not_computed
        @test r.max_interval_widths==widths
        @test !r.calibration_verified && r.sbc===:not_performed
        @test isequal(es,before)
        @test isequal(r,target(reverse(es);ids=r.planned_dataset_ids,failures=["F"=>"interrupted"]))
        legacy=summarize(es;ids=r.planned_dataset_ids,failures=["F"=>"interrupted"],mcse_limits=limits)
        @test isequal(legacy,summarize(es;ids=r.planned_dataset_ids,failures=["F"=>"interrupted"],
            mcse_limits=limits,max_interval_widths=nothing))
        @test isequal(only(r.summaries).all_completed,only(legacy.summaries).all_completed)
        @test isequal(only(r.summaries).without_warnings,only(legacy.summaries).without_warnings)
        @test !hasproperty(only(legacy.summaries).precision_qualified,:width_target)
        @test !hasproperty(legacy,:max_interval_widths)
        # Good average width does not establish that every dataset meets the target.
        mixed=target([record("A",.25),record("B",.75),record("C",1.5)])
        @test only(mixed.summaries).precision_qualified.mean_interval_width.estimate < 1.
        @test width_summary(mixed).conditional_frequency.estimate≈2/3
        excluded=target([es;record("G",.1;warning=true);record("M",.1;endpoint=.021)])
        @test width_summary(excluded).n_unresolved==2
        @test width_summary(excluded).n_meeting_target==2
        @test getproperty.(only(excluded.summaries).precision_dispositions,:status)==
            [:passed,:passed,:passed,:sampling_warning,:mcse_exceeded]
        unresolved=width_summary(target(es;independence=UNKNOWN))
        @test ismissing(unresolved.conditional_frequency.replication_se)
        @test unresolved.conditional_frequency.replication_se_status===:independence_unresolved
        reused=width_summary(target([es[1],reseal(es[1];dataset_id="copy")]))
        @test ismissing(reused.conditional_frequency.replication_se)
        for w in (.5,1.5)
            same=width_summary(target([record("A",w),record("B",w)]))
            @test same.conditional_frequency.replication_se==0.
            @test same.conditional_frequency.replication_se_status===:empirical_zero_variance
            @test same.n_unresolved==0
        end
        lone=width_summary(target(es[1:1]))
        @test ismissing(lone.conditional_frequency.replication_se)
        @test lone.conditional_frequency.replication_se_status===:insufficient_replications
        empty=width_summary(target([];ids=["X"]))
        @test ismissing(empty.conditional_frequency.estimate)
        @test empty.all_planned_frequency_bounds==(0.,1.)
        @test empty.n_unresolved==1
        @test only(target([record("C",0.;fixed=true)]).summaries).precision_qualified===nothing
        for interval in (.9,.99)
            result=target([record("A",1.;interval)])
            @test result.interval_probability==interval
            @test width_summary(result).n_meeting_target==1
        end
        @test_throws ArgumentError target([record("A",-1.)])
        @test_throws ArgumentError summarize(es;ids=getproperty.(es,:dataset_id),mcse_limits=nothing,max_interval_widths=widths)
        for bad in (Dict(),Dict("other"=>1.),(;theta=1.))
            @test_throws ArgumentError summarize(es;ids=getproperty.(es,:dataset_id),mcse_limits=limits,max_interval_widths=bad)
        end
        for bad in (true,0.,-1.,Inf,NaN,"1",big"1e400",big"1e-400")
            @test_throws ArgumentError summarize(es;ids=getproperty.(es,:dataset_id),mcse_limits=limits,max_interval_widths=Dict("theta"=>bad))
        end
        path=joinpath(directory,"width-target-summary.jls")
        serialize(path,r)
        @test isequal(deserialize(path),r)
        @test B._prediction_check_seal(deserialize(path),"bayesianmgmfrm.recovery_replications.v1")===nothing
        @testset "Conditional width-target confidence intervals and display data" begin
            ci(r)=width_summary(r).conditional_confidence_interval
            confident=target(es;ids=["N","E","W","F","Z"],
                failures=["F"=>"interrupted"],width_confidence_level=.95)
            interval=ci(confident)
            @test interval.status===:available && interval.method===:clopper_pearson
            @test interval.conditioning===:numerically_qualified_datasets && !interval.simultaneous
            @test interval.lower≈0.0942993240502461
            @test interval.upper≈0.9915962413403874
            @test width_summary(confident).all_planned_frequency_bounds==(.4,.8)
            @test isequal(r,target(es;ids=["N","E","W","F","Z"],
                failures=["F"=>"interrupted"],width_confidence_level=nothing))
            one=target(es[1:1];width_confidence_level=.95)
            @test ci(one).lower≈.025 && ci(one).upper==1.
            all_met=target(es[1:2];width_confidence_level=.95)
            @test ci(all_met).lower≈sqrt(.025) && ci(all_met).upper==1.
            all_missed=target([record("A",2.),record("B",2.)];width_confidence_level=.95)
            @test ci(all_missed).lower==0. && ci(all_missed).upper≈1-sqrt(.025)
            no_results=target([];ids=["Z"],width_confidence_level=.95)
            @test ci(no_results).status===:no_qualified_datasets
            @test ismissing(ci(no_results).lower) && ismissing(ci(no_results).upper)
            unknown=target(es;independence=UNKNOWN,width_confidence_level=.95)
            @test ci(unknown).status===:independence_unresolved && ismissing(ci(unknown).lower)
            copy_result=target([es[1],reseal(es[1];dataset_id="copy")];width_confidence_level=.95)
            @test ci(copy_result).status===:independence_unresolved
            @test_throws ArgumentError summarize(es;ids=getproperty.(es,:dataset_id),width_confidence_level=.95)
            for bad in (true,0.,1.,-.1,NaN,Inf,".95",big"1e-400",1-big"1e-50")
                @test_throws ArgumentError target(es;width_confidence_level=bad)
            end
            empty_other=reseal(no_results;scenario_id="no-results")
            data=B.design_precision_plot_data([confident,empty_other];parameter="theta")
            @test getproperty.(data.rows,:scenario_id)==["fixed-cell","no-results"]
            @test data.rows[1].all_planned_frequency_bounds==(.4,.8)
            @test data.rows[2].all_planned_frequency_bounds==(0.,1.)
            @test data.rows[2].n_unresolved==1 && ismissing(data.rows[2].conditional_frequency)
            @test data.confidence_level==.95 && data.interval_probability==.9
            @test data.comparison===:descriptive_not_a_design_selection
            @test only(B.design_precision_plot_data(r;parameter="theta").rows).confidence_interval.status===:not_requested
            @test_throws ArgumentError B.design_precision_plot_data([];parameter="theta")
            @test_throws ArgumentError B.design_precision_plot_data([confident,confident];parameter="theta")
            @test_throws ArgumentError B.design_precision_plot_data(confident;parameter="other")
            @test_throws ArgumentError B.design_precision_plot_data(legacy;parameter="theta")
            @test_throws ArgumentError B.design_precision_plot_data(merge(confident,(;n_planned=99));parameter="theta")
            fixed=target([record("C",0.;fixed=true)];width_confidence_level=.95)
            @test_throws ArgumentError B.design_precision_plot_data(fixed;parameter="theta")
            for changed in (reseal(target(es;width_confidence_level=.99);scenario_id="different"),
                    reseal(target([record("P",.5;interval=.99)];width_confidence_level=.95);scenario_id="different"))
                @test_throws ArgumentError B.design_precision_plot_data([confident,changed];parameter="theta")
            end
            path=joinpath(directory,"confidence-summary.jls");serialize(path,confident)
            @test isequal(deserialize(path),confident)
            @test isequal(B.design_precision_plot_data(deserialize(path);parameter="theta"),
                B.design_precision_plot_data(confident;parameter="theta"))
            serialize(joinpath(directory,"confidence-display-fixture.jls"),
                [confident,empty_other,reseal(unknown;scenario_id="dependence-unresolved"),
                 reseal(one;scenario_id="one-qualified")])
        end
    end
end

function checks(directory)
    @testset "Fixed-truth replication accounting and arithmetic" begin
        es=[evaluation("D$i", [row("theta",Float64(error);width=width)])
            for (i,(error,width)) in enumerate(zip((-1,0,2),(2.,4.,2.)))]
        before=deepcopy(es)
        result=summarize(es)
        s=only(result.summaries);a=s.all_completed
        @test result.n_planned==result.n_completed==3 && result.n_failed==result.n_missing==0
        @test [x.dataset_id for x in result.ledger]==["D1","D2","D3"]
        @test a.n_datasets==3 && a.n_unresolved==0
        @test a.bias.estimate≈1/3
        @test a.bias.replication_se≈sqrt(7)/3
        @test a.mean_absolute_error.estimate≈1
        @test a.mean_absolute_error.replication_se≈sqrt(1/3)
        @test a.mse.estimate≈5/3
        @test a.mse.replication_se≈sqrt(13)/3
        @test a.rmse.estimate≈sqrt(5/3)
        @test a.rmse.replication_se≈sqrt(13)/6/sqrt(5/3)
        @test a.coverage.estimate≈2/3 && a.coverage.replication_se≈1/3
        @test a.mean_interval_width.estimate≈8/3 && a.mean_interval_width.replication_se≈2/3
        @test a.all_planned_coverage_bounds==(2/3,2/3)
        @test !a.conditional_on_retained_datasets && a.full_planned_continuous_performance_available
        @test isequal(a,s.without_warnings)
        @test result.replication_se_enabled && !result.independence_verified
        @test result.scientific_acceptance===:not_established && !result.calibration_verified
        @test result.sbc===:not_performed && result.truth_policy===:fixed_focal_truth
        @test isequal(es,before)
        @test isequal(summarize(reverse(es)),result)
        @test B._prediction_check_seal(result,"bayesianmgmfrm.recovery_replications.v1")===nothing
        # Extra parameter rows change neither the focal denominator nor its SE.
        extra=copy(es);extra[2]=reseal(es[2];rows=vcat(es[2].rows,[row("other-$i",100.) for i in 1:20]))
        @test isequal(only(summarize(extra).summaries),s)
        unknown=summarize(es;independence=UNKNOWN)
        @test only(unknown.summaries).all_completed.bias.estimate==a.bias.estimate
        @test ismissing(only(unknown.summaries).all_completed.bias.replication_se)
        @test only(unknown.summaries).all_completed.bias.replication_se_status===:independence_unresolved
        partial=summarize(es[1:1];ids=["D1","D2","D3","D4"],failures=["D2"=>"fit interrupted"])
        p=only(partial.summaries).without_warnings
        @test (partial.n_planned,partial.n_completed,partial.n_failed,partial.n_missing)==(4,1,1,2)
        @test getproperty.(partial.ledger,:status)==[:descriptive,:failed,:missing,:missing]
        @test partial.ledger[2].failure_reason=="fit interrupted"
        @test p.n_datasets==1 && p.n_unresolved==3 && p.all_planned_coverage_bounds==(.25,1.)
        @test p.conditional_on_retained_datasets && !p.full_planned_continuous_performance_available
        @test ismissing(p.bias.replication_se) && p.bias.replication_se_status===:insufficient_replications
        empty=summarize([]);z=only(empty.summaries)
        @test empty.n_missing==3 && empty.model_contract===nothing
        @test z.applicability===:not_observed && ismissing(z.all_completed.bias.estimate)
        @test z.all_completed.all_planned_coverage_bounds==(0.,1.)
        warned=copy(es);warned[3]=reseal(es[3];sampling_warning=true,status=:warning)
        w=only(summarize(warned).summaries)
        @test w.all_completed.n_datasets==3 && w.without_warnings.n_datasets==2
        @test w.all_completed.bias.estimate≈1/3 && w.without_warnings.bias.estimate≈-.5
        @test w.without_warnings.all_planned_coverage_bounds==(2/3,1.)
        @test w.dispositions[3].status===:warning
        unavailable=copy(es);unavailable[2]=evaluation("D2",[row("theta",0.;mcse_status=:insufficient_chains)])
        @test only(summarize(unavailable).summaries).without_warnings.n_datasets==2
        mismatch=copy(es);mismatch[1]=reseal(es[1];fixed_truth_mismatch=true,status=:warning)
        @test only(summarize(mismatch).summaries).without_warnings.n_datasets==2
        omitted=copy(es);omitted[2]=evaluation("D2",[row("other",0.)])
        m=only(summarize(omitted).summaries)
        @test m.all_completed.n_datasets==2 && m.dispositions[2].status===:missing_quantity
        @test m.all_completed.all_planned_coverage_bounds==(1/3,2/3)
        fixed=[evaluation("D$i",[row("theta",0.;fixed=true)]) for i in 1:3]
        f=only(summarize(fixed).summaries)
        @test f.applicability===:structurally_fixed && f.all_completed===f.without_warnings===nothing
        @test all(d -> d.status===:structurally_fixed,f.dispositions)
        zeros=[evaluation("D$i",[row("theta",0.)]) for i in 1:3]
        z=only(summarize(zeros).summaries).all_completed
        @test z.bias.replication_se==0 && z.bias.replication_se_status===:empirical_zero_variance
        @test z.coverage.replication_se==0 && z.coverage.replication_se_status===:empirical_zero_variance
        @test ismissing(z.rmse.replication_se) && z.rmse.replication_se_status===:zero_mse_delta_unavailable
        reused=copy(es);reused[2]=reseal(es[1];dataset_id="D2")
        r=summarize(reused)
        @test r.repeated_evaluation_evidence==[["D1","D2"]] && !r.replication_se_enabled
        @test ismissing(only(r.summaries).all_completed.bias.replication_se)
        native=[evaluation("D$i",[row("theta",Float64(i))];sourcehash="same-native-record") for i in 1:3]
        @test !summarize(native).replication_se_enabled
        paths=[joinpath(directory,"evaluation-$i.jls") for i in 1:3]
        foreach(x -> serialize(x[1],x[2]),zip(paths,es))
        args=(;planned_dataset_ids=["D1","D2","D3"],parameters=["theta"],scenario_id="fixed-cell",dataset_independence=INDEPENDENT)
        @test isequal(saved_recovery_replications(paths;args...),result)
        serialize(joinpath(directory,"replay.jls"),(;paths,args,expected=result))
    end
    @testset "Replication contract rejection" begin
        e=evaluation("D1",[row("theta",1.)]);e2=evaluation("D2",[row("theta",2.)])
        for ids in ([],["D1","D1"],["D1",""],[1,2])
            @test_throws ArgumentError summarize([e];ids)
        end
        for parameters in ([],["theta","theta"],[""],[1])
            @test_throws ArgumentError summarize([e];parameters)
        end
        for declaration in ((status=:independent,evidence="x"),(status=:declared_independent,evidence=""),(status=:unresolved,))
            @test_throws ArgumentError summarize([e];independence=declaration)
        end
        @test_throws ArgumentError summarize([e,e])
        @test_throws ArgumentError summarize([reseal(e;dataset_id="unplanned")])
        @test_throws ArgumentError summarize([merge(e,(;interval_probability=.9))])
        @test_throws ArgumentError summarize([reseal(e;schema="old")])
        @test_throws ArgumentError summarize([e,evaluation("D2",[row("theta",2.)];interval=.9)])
        @test_throws ArgumentError summarize([e,evaluation("D2",[row("theta",2.)];prior=(;sd=2.))])
        @test_throws ArgumentError summarize([e,reseal(e2;model_contract=merge(e2.model_contract,(;dimensions=2)))])
        @test_throws ArgumentError summarize([e,reseal(e2;rows=[merge(only(e2.rows),(;parameter_space=:model_coordinate))])])
        @test_throws ArgumentError summarize([e,evaluation("D2",[row("theta",2.;truth=1.)])])
        @test_throws ArgumentError summarize([e,evaluation("D2",[row("theta",0.;fixed=true)])])
        @test_throws ArgumentError summarize([evaluation("D1",[row("theta",1e200)])])
        for failures in (["D1"=>"already complete"],["D2"=>""],["D2"=>"a","D2"=>"b"],["D9"=>"unknown"],["D2"=>1])
            @test_throws ArgumentError summarize([e];failures)
        end
        @test_throws ArgumentError B.recovery_replications([e];planned_dataset_ids=["D1"],parameters=["theta"],
            scenario_id="",dataset_independence=UNKNOWN)
    end
    precision_checks(directory)
    width_review_checks(directory)
    width_target_checks(directory)
end
end
