module ThreeIndicatorAdaptationChecks
using BayesianMGMFRM, Test, Serialization, JSON3
const B=BayesianMGMFRM
const F=B.Experimental.ThreeIndicator.ConcurrentWorkflow
const H=B.AdvancedHMC
import ..ThreeIndicatorConcurrentWorkflowChecks as Fixtures
function checks()
    @testset "Effective adaptation plans and copied metric observations" begin
        expected=Dict(0=>Int[],100=>Int[],149=>Int[],150=>[100],1000=>[100,150,250,450,950])
        for metric in (:unit,:diagonal,:dense),w in (0,100,149,150,1000)
            a=B._advancedhmc_adaptation_plan(w,metric)
            @test a.step_size_adaptation==(w>0)
            @test a.scheduled_metric_updates==(metric===:unit ? Int[] : expected[w])
            @test a.mass_matrix_adaptation==!isempty(a.scheduled_metric_updates)
            @test isempty(a.warnings)==(metric===:unit || !isempty(expected[w]))
        end
        t=Fixtures.target()
        for w in (0,100,149,150,1000)
            p=prepare_fit(t;ndraws=10,warmup=w,chains=4,seed=29)
            r=fit_report(p)
            @test r.adaptation_plan.scheduled_metric_updates==expected[w]
            @test all(x->x in r.warnings,r.adaptation_plan.warnings)
            mktempdir() do dir
                B._save_serialized_record(joinpath(dir,"plan.jls"),p.record)
                f=load_fit(dir;require_complete=false)
                @test sampler_controls(f).adaptation_plan==r.adaptation_plan
                @test isempty(sampler_controls(f).adaptation)
                @test !qualify(f).qualified
            end
            c=p.record.controls;m=H.DiagEuclideanMetric(3);o=F.adaptation_observer(c,3)
            o.observe((;phase=:sampling_start,metric=m))
            for i in 1:w+10
                i in expected[w] && (m.M⁻¹ .*= 2)
                o.observe((;phase=:transition,stat=(;iterations=i,is_adapt=i<=w,mass_matrix=m,step_size=.01)))
            end
            o.observe((;phase=:sampling_end))
            a=F.adaptation_record(o)
            @test F.check_adaptation(a,c,r.adaptation_plan,3)===a
            @test a.metric_change_iterations==expected[w]
            @test a.final_inverse_mass==fill(2.0^length(expected[w]),3)
            m.M⁻¹ .*= 3
            @test a.final_inverse_mass==fill(2.0^length(expected[w]),3)
            @test_throws ArgumentError F.check_adaptation(merge(a,(;completed=false)),c,r.adaptation_plan,3)
            @test_throws ArgumentError F.check_adaptation(merge(a,(;metric_change_iterations=[w+1])),c,r.adaptation_plan,3)
        end
        @test_throws ArgumentError B._advancedhmc_adaptation_plan(-1,:diagonal)
        @test_throws ArgumentError B._advancedhmc_adaptation_plan(100,:unknown)
        c=(;warmup=0,ndraws=10);o=F.adaptation_observer(c,3);m=H.DiagEuclideanMetric(3)
        o.observe((;phase=:sampling_start,metric=m));m.M⁻¹ .*= 2
        @test_throws ArgumentError o.observe((;phase=:transition,stat=(;iterations=1,is_adapt=false,mass_matrix=m,step_size=.01)))
    end
end
end
