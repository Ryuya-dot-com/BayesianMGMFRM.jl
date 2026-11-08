module RaterDriftChecks
using Test, SHA, JSON3
import BayesianMGMFRM as B
const D=B.Experimental.RaterDrift

function checks(;saved_paths=String[])
    @testset "RW1 input and saved computed reports" begin
        @test D.contract().fitting && !D.contract().scientific_acceptance
        @test :RaterDrift in B.Experimental.surface_contract().reader_facing_bindings
        rows=[(;event_id="e$j-$r",performance="recording",rater="judge$r",time="year$j",score=0)
            for j in (1,3) for r in 1:2]
        args=(;categories=3,time_ticks=[1,2,3],time_labels=["year1","year2","year3"],
            time_unit="year",innovation_log_sd_mean=log(.2))
        t=D.model(rows;args...)
        d=D.design_review(t;reference="year1",panel_weights=[.5,.5])
        @test d.status[:,3]==["linked","linked"]
        @test d.status[:,2]==["process_only_endpoint","process_only_endpoint"]
        @test d.panel_status==["reference","process_only_endpoint","linked"]
        @test !any(d.rated[:,2])
        partial=D.model(filter(r->!(r.rater=="judge2" && r.time=="year1"),rows);args...)
        pd=D.design_review(partial;reference="year1",panel_weights=[.5,.5])
        @test pd.status[2,1]=="process_only_endpoint"
        @test D._change_status(pd,1,2,1)=="reference"
        @test D._change_status(pd,3,2,1)=="process_only_endpoint"
        @test D._change_status(pd,1,0,1)=="reference"
        @test D._change_status(pd,3,0,1)=="process_only_endpoint"
        confounded=D.model([merge(r,(;performance=r.time)) for r in rows];args...)
        @test all(==("data_confounded"),D.design_review(confounded;reference="year1").status[:,3])
        @test_throws ArgumentError D.model([rows;rows[1]];args...)
        @test_throws ArgumentError D.model(rows;merge(args,(;time_ticks=[1,3,4]))...)
        @test_throws ArgumentError D.model(rows;merge(args,(;time_labels=["year1","year2","year2"]))...)
        @test_throws ArgumentError D.model(rows;merge(args,(;innovation_log_sd_mean=NaN))...)
        @test_throws ArgumentError D.model([merge(r,(;score=missing)) for r in rows];args...)
        @test_throws ArgumentError D.model([merge(r,(;score=true)) for r in rows];args...)
        @test_throws ArgumentError D.model([merge(r,(;score=3)) for r in rows];args...)
        @test_throws ArgumentError D.design_review(t;reference="other")
        @test_throws ArgumentError D.design_review(t;reference="year1",panel_weights=[1.,1.])
        @test_throws ArgumentError D.design_review(t;reference="year1",panel_weights=[-1.,2.])
        mktempdir() do tmp
            bad=joinpath(tmp,"bad.json");write(bad,"{\"schema\":\"unsupported\"}")
            @test_throws ArgumentError D.load_report(bad;expected_sha256="invalid")
            @test_throws ArgumentError D.load_report(bad;expected_sha256=repeat("0",64))
            # A deliberately invalid JSON object is not posterior evidence.
            @test_throws ArgumentError D.load_report(bad;expected_sha256=bytes2hex(sha256(read(bad))))
            for (i,path) in enumerate(saved_paths)
                raw=JSON3.read(read(path,String));hash=bytes2hex(sha256(read(path)))
                saved=D.load_report(path;expected_sha256=hash)
                rep=D.report(saved)
                @test D._same(rep.source,raw)
                @test !rep.api.scientific_acceptance
                @test rep.source.original_numerical_qualified===raw.original_report.numerical_qualified
                @test any(contains("warmup"),rep.warnings)
                t=D._target(raw.original_report.target)
                rr=[(;event_id=t.event[n],performance=t.person_labels[t.person[n]],
                    rater=t.rater_labels[t.rater[n]],time=t.time_labels[t.time[n]],score=t.score[n])
                    for n in eachindex(t.score)]
                public=D.model(rr;categories=t.K,time_ticks=t.time_ticks,time_labels=t.time_labels,
                    time_unit=t.time_unit,innovation_log_sd_mean=t.mu_sigma)
                @test all(getfield(t,k)==getfield(public,k) for k in fieldnames(typeof(t)))
                for rater in [:panel;collect(t.rater_labels)]
                    data=D.trajectory(saved;rater)
                    expected=filter(r->r.rater==(rater===:panel ? nothing : rater),raw.trajectory)
                    @test length(data.rows)==length(t.time_ticks)
                    @test data.interval_mass==raw.original_report.interval_mass
                    @test data.warnings==rep.warnings
                    for (row,source) in zip(data.rows,expected)
                        @test row.time==source.time && row.design_status==source.design_status
                        if row.structurally_fixed
                            @test row.lower==row.median==row.upper==0 && row.mean_mcse===nothing
                        else
                            @test all(getproperty(row,k)==source.summary[k] for k in (:mean,:median,:lower,:upper))
                            @test row.mean_mcse===source.summary.precision.mean_mcse
                            @test row.lower_mcse===source.summary.precision.quantiles[1].mcse
                            @test row.upper_mcse===source.summary.precision.quantiles[3].mcse
                        end
                    end
                end
                @test_throws ArgumentError D.trajectory(saved;rater="unknown")
                outfile=joinpath(tmp,"copy$i.json");receipt=D.save_report(outfile,saved)
                restored=D.load_report(outfile;expected_sha256=receipt.sha256)
                @test restored.source_json==saved.source_json
                @test_throws ArgumentError D.save_report(outfile,saved)
                @test_throws ArgumentError D.SavedReport(saved.source_json,repeat("0",64))
                for mutation in (:reference,:interval,:grid,:row,:kind,:qualification,:producer,:policy,:mean_mcse,:quantile,:integration)
                    x=JSON3.read(saved.source_json,Dict{String,Any});o=x["original_report"]
                    if mutation===:reference; o["reference"]="absent"
                    elseif mutation===:interval; o["interval_mass"]=.99
                    elseif mutation===:grid; o["target"]["time_ticks"][2]+=1
                    elseif mutation===:row; pop!(x["trajectory"])
                    elseif mutation===:kind; x["kind"]="deterministic_fixture"
                    elseif mutation===:qualification; x["numerical_qualified"]=!x["numerical_qualified"]
                    elseif mutation===:policy; x["policy"]["primary_batch"]=100
                    elseif mutation===:mean_mcse; x["trajectory"][6]["summary"]["precision"]["mean_mcse"]=-1.
                    elseif mutation===:quantile; x["trajectory"][6]["summary"]["lower"]-=.01
                    elseif mutation===:integration
                        x["trajectory"][11]["estimator"]="conditional_gaussian_bridge"
                        x["trajectory"][11]["summary"]=deepcopy(x["trajectory"][6]["summary"])
                    else; x["adapter_sha256"]=repeat("0",64)
                    end
                    bytes=JSON3.write(x)
                    @test_throws ArgumentError D.SavedReport(bytes,bytes2hex(sha256(bytes)))
                end
            end
        end
    end
end
end
