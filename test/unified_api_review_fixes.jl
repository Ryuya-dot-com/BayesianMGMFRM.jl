module UnifiedAPIReviewFixChecks
using BayesianMGMFRM, Test, Random
const B = BayesianMGMFRM
const E = B.Experimental
const SA = E.StarAssociation
include("common_prediction_fixtures.jl")
include(joinpath(@__DIR__, "..", "examples", "star_association.jl"))

# Manufactured reporting inputs, never posterior or calibration evidence.
function qualification_fixture(; constant=false, telemetry=:complete, sampler=:nuts)
    f = reporting_fit(:mfrm; ndraws=1000, chains=4)
    draws = .1 .* randn(Xoshiro(20261101), size(f.draws))
    constant && (draws[:,1] .= 0)
    lp = [logposterior(f.design, x) for x in eachrow(draws)]
    stats = NamedTuple[merge(s, (;log_density=lp[i], tree_depth=1,
        nonfinite_proposal=false, hamiltonian_energy=telemetry===:partial && s.chain==4 ?
            missing : Float64(isodd(i)))) for (i,s) in enumerate(f.sampler_stats)]
    telemetry===:absent && empty!(stats)
    telemetry===:truncated && pop!(stats)
    telemetry===:misordered && reverse!(stats)
    return MFRMFit(f.design,f.prior,draws,lp,f.acceptance_rate,f.chain_ids,f.iterations,
        f.chain_acceptance_rate,f.backend,sampler,f.warmup,f.step_size,stats,f.sampler_controls)
end

function common_fits()
    r = F.synthetic_record(F.target())
    fits = Any[reporting_fit(:mfrm;ndraws=20,chains=2), reporting_fit(:gmfrm;ndraws=20,chains=2),
        reporting_fit(:mgmfrm;ndraws=20,chains=2), normalized_fixture(r),
        E.CorrelatedMGMFRMFit(r;expected_identity=r.target_identity)]
    append!(fits,[prediction_fixed_fixture(kind).fit for kind in
        (:fixed,:correlated,:exchangeable,:exchangeable_correlated)])
    return fits
end

function star_fixture()
    m = StarAssociationExample.inputs().spec
    cfg = SA._build_sampler_config(ndraws=20,warmup=5,chains=2)
    draws = [.1sin(s+p) for s in 1:(cfg.chains*cfg.ndraws),p in 1:m.dim]
    return SA._build_star_result(m,cfg,draws,NamedTuple[],NamedTuple[];
        provenance=(;operation=:deterministic_test_fixture))
end

@testset "Qualification rejects failed and unavailable diagnostics" begin
    good = qualification_fixture()
    q = qualify(good)
    @test q.qualified
    @test q.telemetry_complete && q.e_bfmi_complete
    @test !qualify(good;min_ess=10000).qualified
    @test !qualify(good;max_rhat=1.00001).qualified
    @test_throws ArgumentError qualify(good;min_bfmi=NaN)
    bad = qualification_fixture(;constant=true)
    @test diagnostics(bad).summary.n_degenerate_parameters == 1
    @test !qualify(bad).parameter_gate_passed
    for status in (:absent,:partial,:truncated,:misordered)
        qbad = qualify(qualification_fixture(;telemetry=status))
        @test !qbad.qualified
        @test !qbad.telemetry_complete
        status===:absent && @test ismissing(qbad.n_divergences)
        status===:partial && @test !qbad.e_bfmi_complete
    end
    @test qualify(qualification_fixture(;sampler=:random_walk_metropolis,telemetry=:partial)).qualified
    stored = reporting_fit(:gmfrm;ndraws=20,chains=2,rhat_threshold=1.2,ess_threshold=10)
    qstored = qualify(stored;max_rhat=1.1,min_ess=20)
    @test qstored.thresholds.min_ess == 20
    @test qstored.diagnostics.summary.ess_threshold == 10
end

@testset "Common fits preserve criterion settings and raw coordinate order" begin
    for f in common_fits()
        @test qualify(f).qualified === false  # Short fixtures are not qualified fits.
        raw = parameter_names(f;scale=:raw)
        @test raw == [r.parameter for r in posterior_summary(f)]
        draws = f isa B._ModelComparisonFit ? f.draws : f.record.run.draws
        @test length(raw) == size(draws,2)
        @test allunique(raw)
        model = parameter_names(f;scale=:model)
        @test length(model) >= length(raw)
        @test_throws ArgumentError parameter_names(f;scale=:unknown)
        opts = (;dataset_id="fixture",observation_ids=["o$i" for i in 1:B.PredictionObservationAdapter._fit_data(f).n])
        for selection in ((:waic,),(:psis_loo,),(:raw_loo,),(:waic,:hill_smoothed_loo))
            tails = :psis_loo in selection ? (;tail_fraction=.2,min_tail_draws=5) : (;tail_fraction=.3,min_tail_draws=4)
            a = criteria(f;criteria=selection,pareto_k_threshold=.12,tails...)
            b = criteria(f;opts...,criteria=selection,pareto_k_threshold=.12,tails...)
            @test keys(a) == keys(b.scores) == selection
            for c in selection
                x,y = getproperty(a,c),getproperty(b.scores,c)
                @test x.n_draws == y.n_draws == size(draws,1)
                if c===:waic
                    @test x.waic ≈ y.waic
                else
                    @test x.elpd_loo ≈ y.elpd_loo
                    @test x.method == y.method
                    @test x.pareto_k_threshold == y.pareto_k_threshold == .12
                    if c === :psis_loo
                        @test x.pareto_k_estimator == y.pareto_k_estimator == :zhang_stephens
                    else
                        @test x.tail_fraction == y.tail_fraction == .3
                        @test x.min_tail_draws == y.min_tail_draws == 4
                    end
                end
            end
        end
        a,b = criteria(f),criteria(f;opts...)
        @test a.psis_loo.method == b.scores.psis_loo.method
        @test_throws ArgumentError criteria(f;ndraws=5)
        @test_throws ArgumentError criteria(f;opts...,draw_indices=1:5)
        @test_throws ArgumentError criteria(f;dataset_id="only-one-id-field")
        @test keys(criteria(f;criteria=(:psis_loo,:hill_smoothed_loo))) == (:psis_loo,:hill_smoothed_loo)
        @test_throws MethodError criteria(f;misspelled_option=true)
    end
end

@testset "Executable Star example and retained-result workflow" begin
    prepared = StarAssociationExample.inputs()
    @test length(prepared.rows)==36
    @test length(unique(r.observation_id for r in prepared.rows))==36
    @test prepared.spec.D==3
    @test prepared.spec.M==[4,3,1]
    res = star_fixture()
    answer = StarAssociationExample.result(res)
    @test !answer.gate.result.numerically_qualified
    @test answer.entities.result.n_selected_levels==4
    @test answer.ranks.result.n_levels==4
    @test isfinite(answer.difference.result.summary.mean)
    @test answer.criteria.operation===:criteria
    mktempdir() do dir
        path = joinpath(dir,"fit.jls")
        save_fit(path,res)
        restored = load_fit(path)
        @test restored.content_hash==res.content_hash
        reread = StarAssociationExample.result(restored)
        @test reread.difference.result.summary.mean==answer.difference.result.summary.mean
        rep = joinpath(dir,"summary.json")
        save_report(rep,answer.posterior)
        @test String(load_report(rep).schema)==SA.REPORT_SCHEMA
        @test_throws MethodError load_report(rep;require_complete=true)
    end
end
@testset "Unified report reader preserves explicit controls" begin
    report=(;schema="bayesianmgmfrm.fit_report.v1",object=:fit_report,
        created_at="2026-11-01T00:00:00",family=:mfrm,thresholds=:partial_credit,
        dimensions=1,dimension_labels=["ability"],
        posterior=(;status=:computed,rows=[(;parameter="person[P1]",mean=0.)],n_rows=1),
        loo=(;status=:error,exception=:ArgumentError,message="synthetic LOO failure"),
        artifact=(;status=:not_requested))
    mktempdir() do d
        p=joinpath(d,"incomplete.json")
        save_report(p,report)
        @test !fit_report_health(load_report(p)).complete
        @test_throws ArgumentError B.load_fit_report(p;require_complete=true)
        @test_throws ArgumentError load_report(p;require_complete=true)
        @test isequal(load_report(p;return_record=true),B.load_fit_report(p;return_record=true))
        @test_throws MethodError load_report(p;unsupported_control=true)
        @test isequal(load_report(p;verify_hash=false),B.load_fit_report(p;verify_hash=false))
        changed=B.JSON3.read(read(p,String),Dict{String,Any})
        changed["report"]["posterior"]["rows"][1]["mean"]=1.0
        tampered=joinpath(d,"tampered.json")
        write(tampered,B.JSON3.write(changed))
        @test_throws ArgumentError load_report(tampered)
        @test load_report(tampered;verify_hash=false)["posterior"]["rows"][1]["mean"]==1.0
    end
end
end
