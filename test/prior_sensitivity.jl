module PriorSensitivityTests
using Test, BayesianMGMFRM, Statistics, Random, Serialization
const B=BayesianMGMFRM
include("common_prediction_fixtures.jl")
function prior_fit(sd=.3;ndraws=20,person_sd=.7,renamed=false)
    original=normalized_fixture(F.synthetic_record(F.target();ndraws))
    old=original.record
    spec=deepcopy(old.spec)
    renamed && (spec.dimension_labels[1]="Changed")
    target=B._MGMFRMNormalizedPriorLogDensity(spec;prior_model=:exchangeable,
        scales=merge(old.prior.scales,(;log_discrimination_sd=sd,person_sd)))
    lp=[B.LogDensityProblems.logdensity(target,x) for x in eachrow(old.run.draws)]
    stats=NamedTuple[merge(s,(;log_density=p)) for (s,p) in zip(old.run.sampler_stats,lp)]
    run=merge(old.run,(;logdensities=lp,sampler_stats=stats,
        initial_logdensity=B.LogDensityProblems.logdensity(target,old.run.initial),
        sampler_rows=B._generalized_candidate_sampler_rows(lp,old.run.iterations,old.run.chain_acceptance,stats,old.run.controls,old.run.backend)))
    record=(;old.schema,spec,prior=B._mgmfrm_normalized_prior_record(target),
        target_identity=B._mgmfrm_normalized_prior_identity(target),run)
    record=merge(record,(;content_hash=B._mgmfrm_normalized_sample_hash(record)))
    return B.Experimental.NormalizedMGMFRMFit(record;expected_identity=record.target_identity)
end

@testset "Named prior sensitivity: paired math and MCSE" begin
    rng=MersenneTwister(40)
    a=randn(rng,2000);b=a+.2randn(rng,2000)
    context=(;spec=(;family=:mgmfrm,dimension_labels=["Ability"]),total_draws=2000,
        chain_ids=repeat(1:4;inner=500),iterations=repeat(1:500;outer=4),
        coordinates=[(;parameter=name,values=x,block=:person,dimension=1,fixed=false) for (name,x) in (("A",a),("B",b))])
    e=only(B._sensitivity_estimands(["A minus B"=>("A","B")],context))
    @test e.values == a-b
    @test std(e.values)<.25
    @test std(a-b[reverse(eachindex(b))])>1
    @test_throws ArgumentError B._sensitivity_estimands(["duplicate"=>("A","A")],context)
    row=B._sensitivity_row(e,context,.99,0.,.2,2.)
    @test row.lower ≈ quantile(a-b,.005)
    @test row.upper ≈ quantile(a-b,.995)
    @test row.mcse.mean_mcse ≈ B.MCMCDiagnosticTools.mcse(reshape(a-b,500,4);kind=mean,split_chains=2)
    @test row.mcse.quantiles[3].mcse ≈ B.MCMCDiagnosticTools.mcse(reshape(a-b,500,4);kind=Base.Fix2(quantile,.995),split_chains=2)
    @test row.decision===:includes_cutoff
    @test row.precision_qualified
    @test B._sensitivity_row(e,context,.9,row.lower,nothing,2.).precision_qualified===nothing
    ordinary=B._sensitivity_row(e,context,.9,nothing,nothing,2.)
    @test B._sensitivity_row(e,context,.9,ordinary.lower,nothing,2.).numerical_decision===:unresolved_mcse_screen
    fixed=merge(e,(;fixed=true,values=fill(1.,2000)))
    @test B._sensitivity_row(fixed,context,.99,0.,.01,2.).mcse.mcse_status===:structurally_fixed
    stuck=merge(fixed,(;fixed=false))
    @test B._sensitivity_row(stuck,context,.99,0.,.01,2.).mcse.mcse_status===:degenerate_draws
end

@testset "Saved-fit contracts and failure denominator" begin
    f=prior_fit();g=prior_fit(.8;ndraws=30)
    inventory=B.recovery_quantities(f).rows
    persons=[r.parameter for r in inventory if r.block===:person && r.dimension==1]
    loadings=[r.parameter for r in inventory if r.block===:item_dimension_discrimination && r.dimension==1]
    steps=[r.parameter for r in inventory if r.fixed]
    estimands=["Loading"=>first(loadings),"Ability difference"=>(persons[1],persons[2]),"Fixed step"=>first(steps)]
    args=(;planned_prior_ids=["narrow","wide","failed","missing"],estimands,dataset_id="test-only",
        observation_ids=["row-$i" for i in 1:f.record.spec.data.n],failures=["failed"=>"Declared synthetic failure"])
    result=B.prior_sensitivity(["narrow"=>f,"wide"=>g];args...,interval=.99,cutoffs=Dict("Ability difference"=>0.))
    @test getproperty.(result.ledger,:status)==[:warning,:warning,:failed,:missing]
    @test [e.evaluation.n_retained_draws for e in result.ledger[1:2]]==[40,60]
    @test result.interval_method===:equal_tailed
    @test result.new_fits==0
    @test result.scientific_acceptance===:not_established
    @test all(c->!c.paired_draws,result.changes)
    c=first(result.changes);a=result.ledger[2].evaluation.rows[1];b=result.ledger[1].evaluation.rows[1]
    @test c.mean_shift==a.mean-b.mean
    @test c.mean_shift_mcse_upper_bound==a.mcse.mean_mcse+b.mcse.mean_mcse
    @test B.prior_sensitivity(["wide"=>g];args...).baseline_available===false
    @test isempty(B.prior_sensitivity(["wide"=>g];args...).changes)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f,"wide"=>prior_fit(.8;person_sd=1.)];args...)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f,"wide"=>prior_fit(.8;renamed=true)];args...)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f,"narrow"=>f];args...)
    @test_throws ArgumentError B.prior_sensitivity(["failed"=>f];args...)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f];args...,max_mcse=-1)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f];args...,cutoffs=Dict("typo"=>0))
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>reporting_fit(:mfrm)];args...)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f];merge(args,(;observation_ids=fill("repeated",f.record.spec.data.n)))...)
    d2=first(r.parameter for r in inventory if r.block===:person && r.dimension==2)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f];merge(args,(;estimands=["Wrong dimension"=>(persons[1],d2)]))...)
    @test_throws ArgumentError B.prior_sensitivity(["narrow"=>f];merge(args,(;estimands=["Wrong scale"=>(persons[1],loadings[1])]))...)
    plot=B.prior_sensitivity_plot_data(result;points=1024)
    @test all(>(0),plot.panels[1].x)
    @test plot.panels[1].density_coordinate===:log
    @test plot.panels[2].density_coordinate===:identity
    @test plot.panels[3].curves[1].marker===:fixed
    @test plot.panels[1].curves[3].marker===:unavailable
    for panel in plot.panels, curve in panel.curves
        curve.marker===:density || continue
        area=sum(diff(panel.x).*(curve.density[1:end-1]+curve.density[2:end])/2)
        @test area ≈ 1 atol=5e-4
    end
    @test_throws ArgumentError B.prior_sensitivity_plot_data(result;bandwidth=0)
    @test_throws ArgumentError B.prior_sensitivity_plot_data(result;points=2)
    mktempdir() do directory
        path=joinpath(directory,"sensitivity.jls")
        B.save_prior_sensitivity(path,result)
        @test isequal(B.load_prior_sensitivity(path),result)
        @test_throws ArgumentError B.save_prior_sensitivity(path,result)
        bad=deepcopy(result);bad.ledger[1].evaluation.rows[1].values[1]+=1
        @test_throws ArgumentError B.save_prior_sensitivity(joinpath(directory,"bad.jls"),bad)
        serialize(joinpath(directory,"bad.jls"),bad)
        @test_throws ArgumentError B.load_prior_sensitivity(joinpath(directory,"bad.jls"))
    end
    # Regression: bounded floating reduction differences may reload, meaningful
    # acceptance changes and summary inconsistencies must still be rejected.
    target=B._normalized_mgmfrm_target(f)
    run=deepcopy(f.record.run);run.chain_acceptance[1]+=.01
    @test_throws ArgumentError B._check_generalized_sample_run(target,run)
    run2=deepcopy(f.record.run);run2.chain_acceptance[1]+=eps(Float64)
    rows=B._generalized_candidate_sampler_rows(run2.logdensities,run2.iterations,run2.chain_acceptance,run2.sampler_stats,run2.controls,run2.backend)
    @test B._check_generalized_sample_run(target,merge(run2,(;sampler_rows=rows)))===nothing
    global artificial_result=result
end
end
