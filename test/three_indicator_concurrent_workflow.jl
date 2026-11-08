module ThreeIndicatorConcurrentWorkflowChecks
using BayesianMGMFRM, Test, JSON3, Serialization, Statistics
import ..ThreeIndicatorConcurrentChecks as Fixtures
const B=BayesianMGMFRM
const T=B.Experimental.ThreeIndicator
const F=T.ConcurrentWorkflow
const R=T.ConcurrentReports
function target(interaction=:full)
    getdesign(T.ConcurrentInput(Fixtures.fixture();source_sha256="a"^64);prior=:steps,interaction)
end
function checks()
    @testset "Concurrent fitted plan and transformed support" begin
        for interaction in (:none,:diagonal,:full)
            t=target(interaction);p=prepare_fit(t;ndraws=100,warmup=100,seed=20261102)
            @test F.check_plan(p).size==t.size
            @test contract(t).fitting && contract(t).posterior_reporting
            @test fit_report(p).raw_draw_bytes==8*400*t.size
            @test allunique(p.record.chain_seeds)
            @test p.record==prepare_fit(t;ndraws=100,warmup=100,seed=20261102).record
            q=initial_params(t)+.075sin.(.17*(1:t.size));m=F.model_values(t,q)
            @test length(m.names)==length(m.values) && allunique(m.names)
            @test all(m.values[findfirst(==(n),m.names)]==0 for n in m.fixed)
            @test length(filter(n->startswith(n,"l1_"),collect(m.fixed)))==12
            @test ("effective_pair[1,1,1]" in m.fixed)==(interaction==:none)
            for op in (:contrasts,:observed,:eng_reference)
                spec=F.focal(t;operation=op,rows=op===:observed ? [1,401] : nothing)
                vals=F.flatten(spec.evaluate(T.Concurrent.reconstruct(t,q)),op)
                fixed=op===:contrasts ? contrast(t,q) : event_probabilities(t,q;panel=op,rows=op===:observed ? [1,401] : nothing)
                raw=op===:contrasts ? fixed.comparisons : op===:observed ? fixed.rows : fixed
                expected=F.flatten(raw,op)
                @test vals.names==expected.names && vals.values==expected.values
                @test allunique(vals.names)
            end
            @test_throws ArgumentError prepare_fit(t;ndraws=10,warmup=10,seed=true)
            @test_throws ArgumentError prepare_fit(t;ndraws=9,warmup=10,seed=1)
            @test_throws ArgumentError prepare_fit(t;ndraws=10,warmup=10,seed=1,chains=1)
            @test_throws MethodError prepare_fit(t;ndraws=10,warmup=10,seed=1,metric=:dense)
            @test_throws ArgumentError F.focal(t;operation=:observed)
            @test_throws ArgumentError F.focal(t;operation=:eng_reference,rows=[1])
            bad=deepcopy(p);bad.record.initial[1]+=.1
            @test_throws ArgumentError F.check_plan(bad)
            mktempdir() do dir
                B._save_serialized_record(joinpath(dir,"plan.jls"),p.record)
                partial=load_fit(dir;require_complete=false)
                @test !qualify(partial).qualified
                @test isempty(qualify(partial).completed_chains)
                @test_throws ArgumentError load_fit(dir)
                @test_throws ArgumentError posterior_summary(partial)
                @test_throws ArgumentError contrast(partial)
                @test_throws ArgumentError fit(p;directory=dir)
            end
        end
    end
end
function fitted_checks(f,dir)
    @testset "Retained concurrent posterior and failure boundaries" begin
        t=getdesign(f);@test length(f.chains)==4
        @test all(r->r.run.controls.gradient_backend===:analytic,f.chains)
        @test sampler_controls(f).chains==4
        raw=reduce(vcat,[r.run.draws for r in f.chains]);name=first(parameter_names(f;scale=:raw))
        s=only(posterior_summary(f;scale=:raw,parameters=[name]).rows)
        @test s.mean≈mean(raw[:,1])
        @test s.lower≈quantile(raw[:,1],.025)
        @test s.upper≈quantile(raw[:,1],.975)
        @test only(posterior_mcse(f;scale=:raw,parameters=[name])).n_chains==4
        @test_throws ArgumentError posterior_summary(f;parameters=["unknown"])
        @test_throws ArgumentError posterior_summary(f;scale=:unknown)
        @test_throws ArgumentError event_probabilities(f)
        @test_throws ArgumentError contrast(f;interval=1)
        path=joinpath(dir,"fit-copy.jls");save_fit(path,f)
        again=load_fit(path)
        @test F.identity(again)==F.identity(f)
        @test all(again.chains[i].run.draws==f.chains[i].run.draws for i in 1:4)
        @test_throws ArgumentError save_fit(path,f)
        @test_throws ArgumentError load_fit(path;unknown=true)
        partial=F.Fit(f.plan,f.chains[1:3]);save_fit(joinpath(dir,"partial.jls"),partial)
        @test_throws ArgumentError load_fit(joinpath(dir,"partial.jls"))
        partial=load_fit(joinpath(dir,"partial.jls");require_complete=false)
        @test !qualify(partial).qualified && qualify(partial).completed_chains==[1,2,3]
        @test_throws ArgumentError contrast(partial)
        reversed=F.Fit(f.plan,reverse(f.chains))
        @test_throws ArgumentError F.checked(reversed)
        bad=deepcopy(f);bad.chains[1].run.draws[1,1]+=.1
        @test_throws ArgumentError F.checked(bad)
        # A resealed corrupted run still fails the structural/density validator.
        r=deepcopy(f.chains[1]);r.run.iterations[1]=2;r=F.seal(Base.structdiff(r,(;content_hash=nothing)))
        broken=F.Fit(f.plan,[r;f.chains[2:end]])
        @test_throws ArgumentError F.checked(broken;full=true)
    end
end
function report_checks(f,r,dir)
    @testset "Paired probability reporting and portable qualification" begin
        @test r.posterior && r.kind=="posterior" && !r.scientific_acceptance
        @test length(r.rows)==552
        @test length(r.definitions.comparisons)==8
        @test all(x.raters_left==4 && x.raters_right==4 for x in r.definitions.comparisons)
        @test !r.numerical_qualified || (r.qualification.qualified && r.precision_passed && r.focal_diagnostic_passed)
        @test all(x.mcse.n_chains==4 && x.mcse.draws_per_chain==f.plan.record.controls.ndraws for x in r.rows)
        for side in ("left","right","difference")
            p=[x.mean for x in r.rows if startswith(x.name,"contrast[1]/$side/accentedness/category")]
            @test sum(p)≈(side=="difference" ? 0 : 1) atol=1e-12
        end
        names=[x.name for x in r.rows]
        left=only(filter(x->x.name=="contrast[1]/left/correct_probability",r.rows))
        right=only(filter(x->x.name=="contrast[1]/right/correct_probability",r.rows))
        delta=only(filter(x->x.name=="contrast[1]/difference/correct_probability",r.rows))
        @test delta.mean≈left.mean-right.mean atol=1e-12
        @test abs(delta.lower-(left.lower-right.upper))>1e-8
        receipt=save_report(joinpath(dir,"report-copy.json"),r)
        @test load_report(receipt.path;expected_sha256=receipt.sha256)==r
        @test_throws ArgumentError load_report(receipt.path)
        @test_throws ArgumentError load_report(receipt.path;expected_sha256="0"^64)
        @test_throws ArgumentError save_report(receipt.path,r)
        @test_throws ArgumentError load_report(receipt.path;expected_sha256=receipt.sha256,require_complete=false)
        for mutate in (d->(d["numerical_qualified"]=!d["numerical_qualified"]),
                d->(d["rows"][1]["mcse_limit"]=1.0),d->(d["controls"]["chains"]=3))
            d=R.normalized(r);mutate(d);delete!(d,"content_hash");d["content_hash"]=B._cache_hash(d)
            @test_throws ArgumentError F.check_report(JSON3.read(JSON3.write(d)))
        end
    end
end
end
