module QualificationPredictionContractChecks
using BayesianMGMFRM, Test, Random
const B=BayesianMGMFRM;const SA=B.Experimental.StarAssociation
include("common_prediction_fixtures.jl")
include("fixtures/experimental_diagnostic_record.jl")
include("../examples/star_association.jl")

# Artificial coordinates/telemetry test logic; a passing fixture is not MCMC evidence.
function star_fixture(;telemetry=:complete,root="overall")
    input=StarAssociationExample.inputs()
    m=B.Experimental.joint_rating_spec(input.rows;criteria=input.criterion_specs,
        prior=input.prior,association=:star,root_criterion=root)
    cfg=SA._build_sampler_config(ndraws=100,warmup=5,chains=4)
    draws=.1randn(Xoshiro(817),cfg.chains*cfg.ndraws,m.dim)
    ld=[B.LogDensityProblems.logdensity(m,q) for q in eachrow(draws)]
    stats=NamedTuple[(;chain=c,iteration=cfg.warmup+i,log_density=ld[(c-1)*cfg.ndraws+i],
        numerical_error=false,tree_depth=1,hamiltonian_energy=Float64(isodd(i)),
        acceptance_rate=.8,step_size=.1,n_steps=1) for c in 1:cfg.chains for i in 1:cfg.ndraws]
    telemetry===:truncated && pop!(stats)
    telemetry===:absent && empty!(stats)
    telemetry===:reordered && reverse!(stats)
    telemetry===:duplicate && (stats[end]=stats[end-1])
    telemetry===:retained_only_indices && (stats=[merge(s,(;iteration=s.iteration-cfg.warmup)) for s in stats])
    SA._build_star_result(m,cfg,draws,NamedTuple[],stats;
        provenance=(;operation=:manufactured_gate_counterexample))
end
const LOOSE=(;max_rhat=1.5,min_ess=1,min_bfmi=.3,mean_mcse_max=100.,endpoint_mcse_max=100.)

@testset "Whole-fit qualification cannot skip required evidence" begin
    f=star_fixture();g=qualify(f;LOOSE...);q=g.result
    @test q.numerically_qualified && q.whole_fit_passed
    @test q.telemetry_complete && q.transformed_assessed
    @test q.raw_passed && q.sampler_passed && q.transformed_passed && q.focal_passed
    @test q.qualification_scope===:whole_fit_and_named_focal_correlations
    @test q.focal_precision_qualification===:passed
    @test q.focal_parameters==["cor_entity_direct[accuracy]","cor_entity_direct[pass_flag]"]
    @test q.focal_parameters==getproperty.(q.focal,:parameter)
    @test q.focal_probabilities==(.025,.975)
    @test g.sampling_warning==f.sampling_warning && g.warnings==f.warnings
    skipped=qualify(f;LOOSE...,check_transformed=false).result
    @test !skipped.numerically_qualified && !skipped.whole_fit_passed
    @test !skipped.transformed_assessed && ismissing(skipped.transformed_passed)
    @test skipped.raw_passed && skipped.sampler_passed && skipped.focal_passed
    @test skipped.telemetry_complete
    for kind in (:truncated,:absent,:reordered,:duplicate,:retained_only_indices)
        bad=qualify(star_fixture(;telemetry=kind);LOOSE...).result
        @test !bad.numerically_qualified && !bad.whole_fit_passed
        @test !bad.telemetry_complete && !bad.sampler_passed
        @test bad.raw_passed && bad.focal_passed
    end
    alt=star_fixture(;root="accuracy")
    @test qualify(alt;LOOSE...).result.focal_parameters==
        ["cor_entity_direct[$(c.id)]" for c in alt.model.criteria[2:end]]
    strict=qualify(f;LOOSE...,mean_mcse_max=1e-15).result
    @test strict.whole_fit_passed && !strict.numerically_qualified && !strict.focal_passed
    @test strict.focal_precision_qualification===:failed
    @test !qualify(f;LOOSE...,endpoint_mcse_max=1e-15).result.focal_passed
    # Keep default thresholds, stored warnings, and report persistence boundaries.
    d=qualify(f).result
    @test d.thresholds.max_rhat==1.01 && d.thresholds.min_ess==400 && d.thresholds.min_bfmi==.3
    @test d.thresholds.mean_mcse_max==.01 && d.thresholds.endpoint_mcse_max==.02
    mktempdir() do dir
        receipt=save_report(joinpath(dir,"partial.json"),qualify(f;LOOSE...,check_transformed=false);return_receipt=true)
        saved=load_report(receipt.path;expected_sha256=receipt.sha256)
        @test !saved.result.numerically_qualified && !saved.result.transformed_assessed
        @test saved.result.transformed_passed===nothing
        @test collect(saved.result.focal_parameters)==q.focal_parameters
        @test saved.sampling_warning==f.sampling_warning
    end
end

@testset "Shared threshold names, compatible aliases and strict controls" begin
    f=star_fixture()
    legacy=(;rhat_max=1.5,ess_min=1,ebfmi_min=.3,mean_mcse_max=100.,endpoint_mcse_max=100.)
    common=qualify(f;LOOSE...)
    @test isequal(common,SA.qualify(f;legacy...))
    @test isequal(common,qualify(f;legacy...))
    @test isequal(common,diagnostics(f;LOOSE...))
    for (a,b,v) in ((:max_rhat,:rhat_max,1.5),(:min_ess,:ess_min,1.),(:min_bfmi,:ebfmi_min,.3))
        both=(;a=>v,b=>v)
        @test_throws ArgumentError qualify(f;both...)
        @test_throws ArgumentError SA.diagnostics(f;both...)
    end
    for name in (:max_rhat,:min_ess,:min_bfmi,:rhat_max,:ess_min,:ebfmi_min,:mean_mcse_max,:endpoint_mcse_max)
        for value in (NaN,Inf,-Inf,0.,-1.,true,false,big"1e1000")
            @test_throws ArgumentError qualify(f;(;name=>value)...)
        end
    end
    @test_throws ArgumentError qualify(f;max_rhat=1.)
    @test_throws MethodError qualify(f;unrecognized_control=true)
    @test_throws ArgumentError qualify(f;chunk_size=15)
    @test !qualify(f;LOOSE...,min_bfmi=100.).result.sampler_passed
    @test !qualify(f;LOOSE...,min_ess=1e8).result.raw_passed
end

@testset "Common whole-fit flags do not certify focal or probability precision" begin
    r=F.synthetic_record(F.target())
    fits=Any[reporting_fit(k;ndraws=20,chains=2) for k in (:mfrm,:gmfrm,:mgmfrm)]
    append!(fits,[normalized_fixture(r),B.Experimental.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity)])
    append!(fits,[prediction_fixed_fixture(k).fit for k in (:fixed,:correlated,:exchangeable,:exchangeable_correlated)])
    for fit in fits
        q=qualify(fit)
        @test q.qualification_scope===:whole_fit_diagnostics
        @test q.focal_precision_qualification===:not_assessed
        @test !q.qualified
        @test_throws ArgumentError qualify(fit;min_bfmi=true)
        @test_throws ArgumentError qualify(fit;min_ess=true)
        rng=Xoshiro(18);unchanged=copy(rng)
        probs=event_probabilities(fit;rng)
        @test probs isa Array{Float64,3}
        @test rand(rng)==rand(unchanged) # All-draw probabilities do not resample.
        @test probs==predictive_probabilities(fit)
        @test all(isapprox.(sum(probs;dims=3),1.;atol=1e-12))
        @test event_probabilities(fit;draw_indices=[2,1,2])==probs[[2,1,2],:,:]
    end
    for kind in (:RaterItemInteractions,:RaterGroupEffects,:CriterionCollapse)
        fit=diagnostic_record(kind)
        q=qualify(fit;max_rhat=1.5,min_ess=1)
        @test q.qualified && q.qualification_scope===:whole_fit_diagnostics
        @test q.focal_precision_qualification===:not_assessed
        @test_throws ArgumentError qualify(fit;min_ess=true)
    end
    f=star_fixture()
    p=event_probabilities(f;rating_event_id="p1-r1",include_full_cartesian=true)
    @test p.result.conditioning===:existing_entity_and_rater_in_sample
    @test p.sampling_warning==f.sampling_warning
    @test length(p.result.mcse)==length(p.result.posterior)
    @test sum(r.mean for r in p.result.posterior if startswith(r.parameter,"cartesian["))≈1.
    @test_throws ArgumentError event_probabilities(f;rating_event_id="new-event")
end
@testset "Fixed-Q probabilities and PPC use the established reconstruction" begin
    for kind in (:fixed,:correlated,:exchangeable,:exchangeable_correlated)
        fit=prediction_fixed_fixture(kind).fit
        n=B.PredictionObservationAdapter._fit_data(fit).n
        ids=["o$i" for i in 1:n]
        bundle=B.prediction_observations(fit;dataset_id="fixture",observation_ids=ids)
        probabilities=event_probabilities(fit)
        @test probabilities≈bundle.probabilities atol=2e-14
        @test size(probabilities)==(40,n,4)
        # The old seed route and new RNG route must reproduce exactly the same
        # conditional replicated ratings. No research data or MCMC is generated.
        selection=[2,1,2]
        old=B._mfrm_fixed_q_predictive_check((;fit.record);draw_indices=selection,seed=42)
        new=posterior_predictive_check(fit;draw_indices=selection,rng=MersenneTwister(42))
        @test old.replicated_scores==new.replicated_scores
        @test old.draw_indices==new.draw_indices==selection
        @test isequal(old.diagnostics,new.diagnostics)
        @test new.chain_ids==bundle.chain_ids[selection]
        @test new.iterations==bundle.iterations[selection]
        @test size(new.replicated_scores)==(3,n)
        @test all(x->x in 0:3,new.replicated_scores)
        a=predictive_check(fit;seed=42,draw_indices=selection)
        b=posterior_predictive_check(fit;rng=Xoshiro(42),draw_indices=selection)
        @test isequal(a,b)
        @test_throws MethodError event_probabilities(fit;unsupported_control=true)
        @test_throws MethodError predictive_check(fit;unsupported_control=true)
        @test_throws ArgumentError event_probabilities(fit;draw_indices=[0])
        @test_throws ArgumentError B._mfrm_fixed_q_predictive_check((;fit.record);rng=Xoshiro(42))
        mktempdir() do dir
            path=joinpath(dir,"fixed.jls");save_fit(path,fit);restored=load_fit(path)
            @test event_probabilities(restored)==probabilities
        end
    end
    # Binary support and a mixed-loading three-dimensional fixed-Q design.
    for (K,D,mixed) in ((2,2,false),(4,3,true))
        fit=prediction_fixed_fixture(:fixed;K,D,mixed).fit
        n=B.PredictionObservationAdapter._fit_data(fit).n
        bundle=B.prediction_observations(fit;dataset_id="fixture",observation_ids=["o$i" for i in 1:n])
        @test event_probabilities(fit)≈bundle.probabilities atol=2e-14
    end
end

end
