module MGMFRMNormalizedLocationChecks
using Test, BayesianMGMFRM, ForwardDiff, LinearAlgebra, Statistics, Random
include(joinpath(@__DIR__,"..","scripts","mgmfrm_normalized_location.jl"))
const N = MGMFRMNormalizedLocation
const B = BayesianMGMFRM
const L = B.LogDensityProblems

function target(persons, q, model; categories=4)
    cells = [(p,i,r) for p in 1:persons for i in axes(q,1) for r in 1:3]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2), rater=last.(cells),
        score=[mod(sum(c),categories) for c in cells]); person=:person, item=:item,
        rater=:rater, score=:score, category_levels=0:(categories-1))
    spec = mfrm_spec(data;family=:mgmfrm,dimensions=size(q,2),thresholds=:partial_credit,q_matrix=q)
    return B._MGMFRMNormalizedPriorLogDensity(spec;prior_model=model,
        scales=(;person_sd=1.,item_sd=1.,log_discrimination_sd=.5,
            rater_sd=sqrt(2.),log_consistency_sd=sqrt(2.)/2,step_sd=sqrt(2.)),
        source_rater=model===:source ? 2 : nothing)
end

@testset "Normalized location map preserves density, Jacobian and gradients" begin
    rng = MersenneTwister(26092801)
    for persons in (1,3), q in (Bool[1 0;1 0;0 1;0 1],Bool[1 0 0;0 1 0;0 0 1;1 1 1]),
            model in (:exchangeable,:source), categories in (2,4)
        raw = target(persons,q,model;categories)
        t = N.LocationTarget(raw)
        p = L.dimension(t)
        identity = B._mgmfrm_normalized_prior_identity(raw)
        for x in (zeros(p), .4randn(rng,p))
            v = N.from_raw(t,x)
            @test N.to_raw(t,v) ≈ x atol=1e-12
            @test N.from_raw(t,N.to_raw(t,v)) ≈ v atol=1e-12
            @test L.logdensity(t,v) ≈ L.logdensity(raw,x) atol=1e-10
            J = ForwardDiff.jacobian(v->N.to_raw(t,v),v)
            @test logabsdet(J)[1] ≈ 0. atol=1e-12
            g = ForwardDiff.gradient(v->L.logdensity(t,v),v)
            @test g ≈ J'*ForwardDiff.gradient(x->L.logdensity(raw,x),x) atol=1e-9
            direction = cos.(1:p)
            h = 1e-5
            finite = (L.logdensity(t,v+h*direction)-L.logdensity(t,v-h*direction))/(2h)
            @test dot(g,direction) ≈ finite atol=2e-6 rtol=2e-6
            # The correction for normalized zero-sum/tilted blocks is unchanged
            # along this map; replacing the entire target by base loses it.
            correction = L.logdensity(raw,x)-L.logdensity(raw.base,x)
            @test L.logdensity(t,v)-L.logdensity(t.map,v) ≈ correction atol=1e-10
            @test !isapprox(correction,0.;atol=1e-8)
            @test B._mgmfrm_normalized_prior_identity(raw) == identity
            if !all(iszero,x)
                @test !isapprox(B.logprior(raw,v),B.logprior(raw,x);atol=1e-8)
            end
        end
        @test_throws ArgumentError N.to_raw(t,zeros(p-1))
        @test_throws ArgumentError N.from_raw(t,fill(Inf,p))
        @test N.to_raw(t,B.initial_params(t)) == B.initial_params(raw)
    end
end

if get(ENV, "BAYESIANMGMFRM_NORMALIZED_FIT_SMOKE", "false") == "true"
@testset "Public normalized coordinates keep initialization, identity and saved semantics" begin
    for model in (:exchangeable,:source), record_warmup in (false,true)
        raw = target(3,Bool[1 0;1 0;0 1;0 1],model)
        initial = .02sin.(1:L.dimension(raw))
        events = NamedTuple[]
        prior = B.Experimental.NormalizedMGMFRMPrior(; prior_model=model,
            B._mgmfrm_normalized_prior_record(raw).scales...,
            source_rater=model===:source ? 2 : nothing)
        fit = B.Experimental.fit(raw.base.design.spec; prior, init=initial, record_warmup,
            sampling_coordinates=:orthogonal_person_mean_item_offset, chains=2,ndraws=12,warmup=10,
            max_depth=3,seed=26092802,init_jitter=.1, _sampling_observer=e->push!(events,e))
        result = B._recorded_mgmfrm_samples(fit)
        run = result.record.run
        @test result.record.target_identity == B._mgmfrm_normalized_prior_identity(raw)
        @test run.initial == initial
        @test run.controls.sampling_coordinates === :orthogonal_person_mean_item_offset
        @test run.controls.stored_coordinates === :raw_unconstrained
        @test run.controls.initialization_coordinates === :raw_unconstrained
        @test run.controls.coordinate_logabsdet == 0.
        @test hasproperty(run,:warmup_stats) == record_warmup
        for e in filter(e->e.phase===:sampling_start,events)
            @test e.initial_sampling ≈ N.from_raw(N.LocationTarget(raw),e.initial_raw)
            @test e.initial_raw != initial
        end
        @test length(filter(e->e.phase===:sampling_start,events)) == 2
        for (x,lp) in zip(eachrow(run.draws),run.logdensities)
            @test L.logdensity(raw,x) ≈ lp atol=1e-9
        end
        @test fit_metadata(fit).prior == result.record.prior
        @test fit_metadata(fit).sampler_controls == run.controls
        @test !diagnostics(fit).summary.passed # Tiny operability runs, no convergence claim.
        mktempdir() do dir
            path = joinpath(dir,"fit.jls")
            save_fit_cache(path,fit)
            restored = load_fit_cache(path)
            @test restored.record.target_identity == result.record.target_identity
            @test isequal(restored.record.run,run)
            @test isequal(posterior_summary(restored),posterior_summary(fit))
            @test isequal(diagnostics(restored),diagnostics(fit))
            @test isequal(posterior_mcse(restored),posterior_mcse(fit))
            report = fit_report(restored; require_complete=true, view=:full,
                include_prior_predictive=true, prior_predictive_ndraws=8, seed=17)
            @test report.metadata.sampler_controls == run.controls
            @test report.prior_predictive.prior == fit.record.prior
            save_fit_report_bundle(joinpath(dir,"report"), restored;
                require_complete=true, seed=17)
            @test isdir(joinpath(dir,"report"))
        end
    end
end
end
end
