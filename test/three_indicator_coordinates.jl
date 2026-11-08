module ThreeIndicatorCoordinateChecks
using BayesianMGMFRM,Test,JSON3,Statistics
import ..ThreeIndicatorConcurrentChecks as Fixtures
import ..ThreeIndicatorConcurrentWorkflowChecks as Existing
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator;const C=T.Concurrent;const F=T.ConcurrentWorkflow
const K=T.ConcurrentCoordinates
function setup()
    t=Existing.target();q=initial_params(t)+.075sin.(.17*(1:t.size))
    p=prepare_fit(t;ndraws=20,warmup=150,chains=4,seed=2026110305,initial=q,
        max_depth=5,parameterization=:pair_132,chain_execution=:threads,max_parallel_chains=2)
    t,q,p
end
function checks()
    @testset "Sampler chart plan and analytic bridge" begin
        t,q,p=setup();k=F.sampling_target(p,t);v=p.record.initial
        @test p.record.native_initial==q && v!=q
        @test K.convert_coordinates(k,v)≈q atol=1e-14
        @test F.check_plan(p).size==t.size
        @test fit_report(p).coordinates.name===:pair_132
        @test F.CHART_WARNING in fit_report(p).warnings
        @test logposterior(t,q)≈C.L.logdensity(k,v) atol=1e-10
        val,g=C.L.logdensity_and_gradient(k,v)
        ad=B.ForwardDiff.gradient(x->C.L.logdensity(k,x),v)
        @test maximum(abs.(g-ad)./(1 .+abs.(ad)))<2e-8
        n=prepare_fit(t;ndraws=20,warmup=150,chains=4,seed=2026110305,initial=q)
        @test n.record.coordinates.name===:native && n.record.initial==q
        @test F.sampling_target(n,t)===t
        @test F.native_point(n,t,q)===q
        @test !n.record.coordinates.experimental
        for interaction in (:none,:diagonal)
            @test_throws ArgumentError prepare_fit(Existing.target(interaction);ndraws=20,warmup=150,seed=1,parameterization=:pair_132)
        end
        @test_throws ArgumentError prepare_fit(t;ndraws=20,warmup=150,seed=1,parameterization=:other)
        for change in (x->merge(x,(;coordinates=F.coordinate_contract(:native))),
                x->merge(x,(;native_initial=q.+.1)),x->merge(x,(;initial=q)))
            bad=F.Plan(F.seal(change(Base.structdiff(p.record,(;content_hash=nothing)))))
            @test_throws ArgumentError F.check_plan(bad)
        end
        @test all(!startswith(n,"pair_q[") for n in F.raw_names(t;parameterization=:pair_132))
        @test any(startswith(n,"pair_q_132[") for n in F.raw_names(t;parameterization=:pair_132))
    end
end
function fitted_checks(dir)
    t,q,p=setup();f=fit(p;directory=joinpath(dir,"fit"));reports=NamedTuple[]
    @testset "132 fitting, model reports and coordinate provenance" begin
        @test length(f.chains)==4
        @test all(r->r.adaptation.metric_change_iterations==[100],f.chains)
        @test all(r->r.run.initial==p.record.initial,f.chains)
        @test sampler_controls(f).coordinates==p.record.coordinates
        @test any(startswith(n,"pair_q_132[") for n in parameter_names(f;scale=:raw))
        @test !qualify(f).qualified
        @test diagnostics(f).coordinates==p.record.coordinates
        flat=reduce(vcat,[r.run.draws for r in f.chains])
        for i in (1,21,80)
            v=flat[i,:];qn=K.convert_coordinates(K.Target(t),v)
            @test coordinates(f,v).pair≈coordinates(t,qn).pair
            @test logposterior(f,v)≈logposterior(t,qn) atol=1e-10
            @test logdensity_and_gradient(f,v)==C.L.logdensity_and_gradient(K.Target(t),v)
        end
        names=["effective_pair[1,1,1]",last(parameter_names(f))]
        summaries=posterior_summary(f;parameters=names)
        vals=F.draws(t,f;parameters=names)
        @test summaries.coordinates==p.record.coordinates
        @test [r.mean for r in summaries.rows]≈vec(mean(vals.values;dims=1))
        for op in (:contrasts,:observed,:eng_reference)
            spec=F.focal(t;operation=op,rows=op===:observed ? [1,401] : nothing)
            actual=F.focal_draws(t,f,spec)
            for i in (1,21,80)
                qn=K.convert_coordinates(K.Target(t),flat[i,:])
                point=op===:contrasts ? contrast(t,qn) : event_probabilities(t,qn;panel=op,rows=op===:observed ? [1,401] : nothing)
                expected=F.flatten(op===:contrasts ? point.comparisons : op===:observed ? point.rows : point,op)
                @test actual.names==expected.names
                @test actual.values[i,:]≈expected.values atol=1e-12
            end
            report=op===:contrasts ? contrast(f) : event_probabilities(f;panel=op,rows=op===:observed ? [1,401] : nothing)
            @test report.coordinates.name=="pair_132" && report.schema==F.REPORT_SCHEMA
            @test F.CHART_WARNING in report.warnings && !report.numerical_qualified
            @test [r.mean for r in report.rows]≈vec(mean(actual.values;dims=1)) atol=1e-12
            receipt=save_report(joinpath(dir,string(op)*".json"),report;return_receipt=true)
            @test load_report(receipt.path;expected_sha256=receipt.sha256)==report
            push!(reports,(;operation=op,receipt))
            if op===:contrasts
                Existing.report_checks(f,report,dir)
                for mutate in (d->delete!(d,"coordinates"),d->(d["coordinates"]["name"]="other"),
                        d->(d["coordinates"]["model_reports"]="sampler"),
                        d->filter!(!=(F.CHART_WARNING),d["warnings"]))
                    d=F.R.normalized(report);mutate(d);delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d)
                    @test_throws ArgumentError F.check_report(JSON3.read(JSON3.write(d)))
                end
            end
        end
        @test F.identity(load_fit(joinpath(dir,"fit")))==F.identity(f)
    end
    Existing.fitted_checks(f,dir)
    open(io->JSON3.write(io,(;julia=string(VERSION),source_fit_hash=F.identity(f),coordinates=p.record.coordinates,
        reports,qualification_passed=qualify(f).qualified,new_empirical_fits=0,operation_fits=1)),joinpath(dir,"result.json"),"w")
    f
end
end
