module RaterDriftComparisonChecks
using Test, JSON3, SHA
using BayesianMGMFRM
const B=BayesianMGMFRM
const D=B.Experimental.RaterDrift
# Reuse the package's deterministic runner; no MCMC transition or outcome RNG.
include("rater_drift_fitting.jl")
const F=RaterDriftFittingChecks
json(x)=JSON3.read(JSON3.write(B._json_export_value(x)))
function checks(output)
    mkpath(output)
    @testset "Static/RW1 comparison with artificial traces" begin
        rows=[(;event_id="event-$j-$r",performance="recording",rater="judge$r",time="year$j",score=mod(j+r,3)) for j in (1,3) for r in 1:2]
        args=(;categories=3,time_ticks=[1,2,3],time_labels=["year1","year2","year3"],time_unit="year")
        static=D.model(rows;args...,process=:static)
        rw1=D.model(rows;args...,innovation_log_sd_mean=log(.2))
        @test static.static && !rw1.static
        @test static.parameterization===:centered && rw1.parameterization===:noncentered
        @test all(==("static_constraint"),D.design_review(static;reference="year1").status)
        @test_throws ArgumentError D.model(rows;args...,process=:static,innovation_log_sd_mean=log(.2))
        @test_throws ArgumentError D.model(rows;args...)
        @test_throws ArgumentError D.model(rows;args...,process=:unknown)
        q=[.1sin(i) for i in 1:D.M.L.dimension(static)]
        @test isempty(D.M.coordinates(static,q).sigma)
        @test all(D.M.coordinates(static,q).severity[:,j]==D.M.coordinates(static,q).severity[:,1] for j in 1:3)
        # The static metadata placeholder is absent from its density, not a tiny RW1 variance.
        old=D.RaterDriftRecords.target(merge(D.RaterDriftRecords.target_record(static),(;mu_sigma=log(.2))))
        @test D.M.L.logdensity(static,q)==D.M.L.logdensity(old,q)
        saved=[];reports=[]
        for (name,t) in (("static",F.target(static=true,parameterization=:centered)),("rw1",F.target()))
            plan=F.prepare(t)
            record=D.RaterDriftWorkflow.run_chains(plan,joinpath(output,name);_runner=F.runner)
            rep=D.RaterDriftBridge.report(record);x=json(rep)
            push!(saved,record);push!(reports,x)
            @test !x.posterior && !x.numerical_qualified
            @test length(x.locations)==t.P+t.R*length(t.time_ticks)
            @test D._check_locations(x,t)===x
            @test_throws ArgumentError D.NativeFit(record)
            text=JSON3.write(x)
            @test_throws ArgumentError D.SavedReport(text,bytes2hex(sha256(text)))
            # Independent reconstruction of level means and quantiles from stored raw points.
            raw=reduce(vcat,[c.run.draws for c in record.chains])
            for (i,row) in enumerate(x.locations)
                values=[i<=t.P ? D.M.coordinates(t,q).theta[i] : vec(D.M.coordinates(t,q).severity)[i-t.P] for q in eachrow(raw)]
                @test isapprox(row.mean,sum(values)/length(values);atol=1e-14,rtol=0)
                @test [row.lower,row.median,row.upper]≈B.Statistics.quantile(values,[.05,.5,.95]) atol=1e-13
            end
        end
        a,b=reports
        @test D._check_comparison_sources(a,b)===nothing
        @test all(r->r.structurally_fixed && r.summary===nothing,a.trajectory)
        @test all(r->r.lower<r.upper,a.locations)
        @test all(r->r.estimator=="joint_draws",b.locations)
        for key in (:score,:event,:time_ticks,:time_labels,:time_unit,:K,:person_labels,:rater_labels)
            wrong=JSON3.read(JSON3.write(b),Dict{String,Any})
            t=wrong["original_report"]["target"]
            if t[String(key)] isa Vector
                t[String(key)][1]=t[String(key)][1] isa String ? "changed" : t[String(key)][1]+1
            else
                t[String(key)]=t[String(key)] isa String ? "changed" : t[String(key)]+1
            end
            @test_throws ArgumentError D._check_comparison_sources(a,json(wrong))
        end
        for key in (:reference,:panel_weights,:interval_mass,:epsilon,:precision_policy,:policy)
            wrong=JSON3.read(JSON3.write(b),Dict{String,Any})
            wrong["original_report"][String(key)]=nothing
            @test_throws ArgumentError D._check_comparison_sources(a,json(wrong))
        end
        @test_throws ArgumentError D._check_comparison_sources(b,a)
        for key in (:mean_mcse,:mcse,:identity,:qualification,:static_level)
            wrong=JSON3.read(JSON3.write(a),Dict{String,Any});row=wrong["locations"][end]
            if key===:mean_mcse;row["precision"]["mean_mcse"]=-1
            elseif key===:mcse;row["precision"]["quantiles"][1]["mcse"]=-1
            elseif key===:identity;row["id"]="changed"
            elseif key===:qualification;row["precision_passed"]=!row["precision_passed"]
            else;row["mean"]+=.1
            end
            @test_throws ArgumentError D._check_locations(json(wrong),F.target(static=true,parameterization=:centered))
        end
        # Both location and trajectory gates preserve precision failures independently.
        @test any(r->!r.diagnostic_passed,b.locations)
        @test any(contains("location numerical criteria"),D._warnings(b))
        @test any(contains("fixed to zero by assumption"),D._warnings(a))
        @test Base.Docs.doc(D.compare)!==nothing
    end
end
end
