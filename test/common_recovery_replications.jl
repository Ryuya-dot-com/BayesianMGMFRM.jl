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
end
end
