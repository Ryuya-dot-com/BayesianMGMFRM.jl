module ThreeIndicatorReportChecks
using BayesianMGMFRM, Test
using BayesianMGMFRM: JSON3, SHA
const T=BayesianMGMFRM.Experimental.ThreeIndicator
encode(x)=JSON3.write(x)
hashtext(x)=bytes2hex(SHA.sha256(x))

# Fabricated file-reader metadata, not posterior samples or simulation evidence.
function fixture()
    d=Dict("rank_normalized_rhat"=>1.0,"bulk_ess"=>500.0,"tail_ess"=>500.0)
    raw=merge(copy(d),Dict("parameter"=>"q[1]","parameter_space"=>"primitive",
        "quality_gate_applicable"=>true,"flag"=>"ok"))
    rows=Any[]
    function add(name,scale,value,lo,hi)
        q=[Dict("probability"=>p,"estimate"=>v,"mcse"=>.001) for
            (p,v) in zip(((1-.95)/2,.5,(1+.95)/2),(lo,value,hi))]
        push!(rows,Dict("name"=>name,"scale"=>scale,"mean"=>value,"median"=>value,
            "lower"=>lo,"upper"=>hi,"mcse_limit"=>scale=="probability" ? .005 : .02,
            "precision"=>Dict("mean_mcse"=>.001,"quantiles"=>q),
            "diagnostics"=>copy(d),"precision_passed"=>true,"diagnostic_passed"=>true))
    end
    for outcome in 1:3
        kmax=outcome==3 ? 2 : 9
        for k in 1:kmax;add("panel_probability[$outcome,$k]","probability",1/kmax,0.,2/kmax);end
        outcome<=2 && add("panel_expected_rating[$outcome]","rating",5.,4.,6.)
    end
    add("panel_correct_probability","probability",.5,0.,1.)
    for family in ("speaker","listener"), outcome in 1:3;add("$family/pair/$outcome","location",0.,-.5,.5);end
    for b in ("speaker","word","rater","token","time","l1"), j in 1:2, i in j+1:3
        add("correlation/$b/$i,$j","correlation",0.,-.5,.5)
    end
    telemetry=[Dict("chain"=>i,"n_divergences"=>0,"n_nonfinite_logdensity"=>0,
        "n_max_treedepth"=>0,"n_invalid_sampler_values"=>0,"e_bfmi"=>.8) for i in 1:4]
    Dict("schema"=>"bayesianmgmfrm.three_indicator_workflow.v1","kind"=>"posterior",
        "posterior"=>true,"public_api"=>false,"statistical_acceptance"=>false,
        "content_hash"=>"a"^64,"plan_hash"=>"b"^64,
        "context"=>Dict("julia"=>"test-fixture","project"=>"c"^64,"manifest"=>"d"^64,
            "package"=>"e"^64,"sources"=>[
                Dict("path"=>"three_indicator_observation.jl","sha256"=>first(T.SOURCES)),
                Dict("path"=>"mgmfrm_lkj_cholesky_candidate.jl","sha256"=>"bec6d709ab6e1b7daa69614cec78628fda68ae26802e5ea78426c43bd7cd691a"),
                Dict("path"=>"three_indicator_workflow.jl","sha256"=>"93e4051488b3b142988e6ff5f680b647eb0b5275759bc66f343cedd896795a56")]),
        "metadata"=>Dict("outcomes"=>["accentedness","comprehension_difficulty","transcription_error"],
            "direction"=>"higher_is_adverse","binary_coding"=>"1=correct;2=incorrect",
            "predictor_units"=>"artificial fixed units","scoring_version"=>"parser-fixture",
            "source"=>"Artificial file-reader fixture; no generated data or posterior samples."),
        "labels"=>Dict("event"=>["E1"],"speaker"=>["S1","S2"],"rater"=>["R1","R2"],
            "word"=>["W1"],"token"=>["T1"],"cohort"=>["G1"]),
        "policy"=>Dict("interval"=>.95,"rhat_max"=>1.01,"ess_min"=>400.,
            "bfmi_min"=>.3,"probability_mcse_max"=>.005,"other_mcse_max"=>.02),
        "focal_definitions"=>Dict("panel_label"=>"artificial panel","events"=>[1],"weights"=>[1.],
            "speaker_pairs"=>[Dict("label"=>"pair","left"=>1,"right"=>2)],
            "listener_pairs"=>[Dict("label"=>"pair","left"=>1,"right"=>2,"l1"=>2,"time"=>.5)]),
        "rows"=>rows,"primitive"=>[copy(raw)],"original"=>[copy(raw)],
        "sampler"=>telemetry,"warmup"=>deepcopy(telemetry),
        "chain_ids"=>repeat(1:4;inner=10),"iterations"=>repeat(1:10;outer=4),
        "interval_method"=>"pointwise_equal_tailed","conditioning"=>"fixed_existing_event_panel",
        "correlations"=>"marginal_pre_projection","numerical_qualified"=>true,
        "parameter_passed"=>true,"sampler_passed"=>true,"precision_passed"=>true)
end

function comparison(x)
    rows=[Dict("name"=>r["name"],"quantities"=>[
        Dict("kind"=>k,"julia"=>r[k],"stan"=>r[k],"difference"=>0.,
            "combined_mcse"=>.01,"standardized"=>0.,"review_flag"=>false)
        for k in ("mean","lower","upper")]) for r in x["rows"]]
    Dict("julia_report_hash"=>x["content_hash"],"stan_report_hash"=>"f"^64,
        "julia_qualified"=>true,"stan_qualified"=>true,"qualified_agreement"=>true,
        "interpretation"=>"Artificial comparison fixture, not engine evidence.","rows"=>rows)
end

function checks()
    @testset "Three-outcome computed reports: artificial parser fixtures" begin
        x=fixture();text=encode(x);digest=hashtext(text)
        c=comparison(x);q=c["rows"][1]["quantities"][2]
        q["stan"]+=.1;q["difference"]=q["stan"]-q["julia"]
        q["standardized"]=q["difference"]/q["combined_mcse"];q["review_flag"]=true
        c["qualified_agreement"]=false;ctext=encode(c)
        saved=T.SavedReport(text,digest,ctext,hashtext(ctext))
        r=T.report(saved)
        @test length(r.rows)==47
        @test length(r.comparison.flags)==1
        @test any(contains("review flag"),r.warnings)
        @test r.focal_definitions.listener_pairs[1].time==.5
        @test r.api.fitting && !r.api.scientific_acceptance
        alone=T.report(T.SavedReport(text,digest,nothing,nothing))
        @test alone.comparison.status==:not_supplied
        @test any(contains("No engine comparison"),alone.warnings)
        for change in (
                y->(y["metadata"]["binary_coding"]="reversed"),
                y->(y["posterior"]=false),
                y->(y["public_api"]=true),
                y->(y["context"]["sources"][1]["sha256"]="0"^64),
                y->(y["rows"][1]["precision"]["quantiles"][1]["estimate"]+=.1),
                y->(y["rows"][1]["precision"]["mean_mcse"]=-.1),
                y->(y["focal_definitions"]["weights"][1]=.5),
                y->(y["focal_definitions"]["listener_pairs"][1]["left"]=true),
                y->(y["rows"][1]["name"]="wrong"),
                y->pop!(y["rows"]),
                y->(y["chain_ids"][1]=4),
                y->(y["numerical_qualified"]=false))
            wrong=deepcopy(x);change(wrong);t=encode(wrong)
            @test_throws ArgumentError T.SavedReport(t,hashtext(t),nothing,nothing)
        end
        for change in (
                y->(y["julia_report_hash"]="0"^64),
                y->(y["rows"][1]["quantities"][1]["julia"]+=.1),
                y->(y["rows"][1]["quantities"][2]["review_flag"]=false))
            wrong=deepcopy(c);change(wrong);t=encode(wrong)
            @test_throws ArgumentError T.SavedReport(text,digest,t,hashtext(t))
        end
        failed=deepcopy(x);failed["sampler"][1]["n_divergences"]=1
        failed["sampler_passed"]=failed["numerical_qualified"]=false
        failed["warmup"][2]["n_max_treedepth"]=2
        t=encode(failed);r=T.report(T.SavedReport(t,hashtext(t),nothing,nothing))
        @test !r.numerical_qualified
        @test any(contains("retained chain 1"),r.warnings)
        @test any(contains("warmup chain 2"),r.warnings)
        @test any(contains("Whole-report"),r.warnings)
        mktempdir() do out
            path=joinpath(out,"original.json");write(path,text)
            @test_throws ArgumentError T.load_report(path;expected_sha256="0"^64)
            @test_throws ArgumentError T.load_report(path;expected_sha256=digest,comparison_path=path)
            receipt=T.save_report(joinpath(out,"copy.json"),saved)
            restored=T.load_report(receipt.path;expected_sha256=receipt.sha256)
            @test restored.source_json==text && restored.comparison_json==ctext
            @test T.report(restored).warnings==T.report(saved).warnings
            @test_throws ArgumentError T.save_report(receipt.path,saved)
            link=joinpath(out,"broken-link");symlink(joinpath(out,"missing"),link)
            @test_throws ArgumentError T.save_report(link,saved)
            @test islink(link)
            @test_throws ArgumentError T.load_report(receipt.path;expected_sha256=receipt.sha256,
                comparison_path=path,comparison_sha256=digest)
        end
        @test Base.Docs.doc(T.load_report)!==nothing
        @test Base.Docs.doc(T.report)!==nothing
        @test Base.Docs.doc(T.save_report)!==nothing
    end
end

function provenance_checks()
    @testset "Producer-specific provenance: artificial parser fixtures" begin
        x=fixture()
        for engine in (:julia,:stan)
            y=deepcopy(x)
            if engine==:stan
                delete!(y,"kind");delete!(y,"plan_hash")
                y["schema"]="bayesianmgmfrm.private_stan_report.v1";y["producer"]="CmdStan"
                y["scope_sha256"]="a"^64;y["archive_hash"]="b"^64
                y["context"]["sources"][1]["sha256"]=T.SOURCES[2]
            end
            t=encode(y);r=T.report(T.SavedReport(t,hashtext(t),nothing,nothing))
            @test r.source.schema==y["schema"]
            for field in (engine==:julia ? ("plan_hash",) : ("scope_sha256","archive_hash"))
                @test r.source[Symbol(field)]==y[field]
                missing=deepcopy(y);delete!(missing,field);t=encode(missing)
                @test_throws ArgumentError T.SavedReport(t,hashtext(t),nothing,nothing)
                wrong=deepcopy(y);wrong[field]="invalid";t=encode(wrong)
                @test_throws ArgumentError T.SavedReport(t,hashtext(t),nothing,nothing)
            end
        end
        original="93e4051488b3b142988e6ff5f680b647eb0b5275759bc66f343cedd896795a56"
        guarded="eb6d70ae8c3cfe70b3978d3e77fb46a6390a0751a315b84d67b89b667fa4d8e3"
        # Exercise the entire cross-product, not just individually known hashes.
        for engine in (:julia,:stan), model in T.SOURCES, workflow in (original,guarded,"0"^64)
            y=fixture()
            if engine==:stan
                delete!(y,"kind");delete!(y,"plan_hash")
                y["schema"]="bayesianmgmfrm.private_stan_report.v1";y["producer"]="CmdStan"
                y["scope_sha256"]="a"^64;y["archive_hash"]="b"^64
            end
            y["context"]["sources"][1]["sha256"]=model
            y["context"]["sources"][3]["sha256"]=workflow
            supported=(engine==:julia && model==T.SOURCES[1] && workflow in (original,guarded)) ||
                (engine==:stan && model==T.SOURCES[2] && workflow==original)
            text=encode(y)
            if supported
                @test T.report(T.SavedReport(text,hashtext(text),nothing,nothing)).source.schema==y["schema"]
            else
                @test_throws ArgumentError T.SavedReport(text,hashtext(text),nothing,nothing)
            end
        end
        for change in (
                y->pop!(y["context"]["sources"]),
                y->push!(y["context"]["sources"],copy(y["context"]["sources"][1])),
                y->(y["context"]["sources"][2]["sha256"]="0"^64),
                y->(y["context"]["sources"][1]["sha256"]="0"^64))
            y=fixture();y["context"]["sources"][3]["sha256"]=guarded;change(y);text=encode(y)
            @test_throws ArgumentError T.SavedReport(text,hashtext(text),nothing,nothing)
        end
    end
end

# Fabricated producer metadata for parsing, not a fitted example.
function support_fixture()
    x=fixture();x["public_api"]=true
    x["context"]["sources"][1]["sha256"]=T.CONTEXT_PRODUCER[2]
    x["context"]["sources"][3]["sha256"]=T.CONTEXT_PRODUCER[3]
    x["listener_support"]=[
        Dict("contrast"=>"pair","side"=>"left","listener"=>1,"listener_label"=>"R1",
            "l1"=>2,"time"=>.5,"observations"=>1,"lower"=>.4,"upper"=>.4,"status"=>"outside_observed_range"),
        Dict("contrast"=>"pair","side"=>"right","listener"=>2,"listener_label"=>"R2",
            "l1"=>2,"time"=>.5,"observations"=>0,"lower"=>nothing,"upper"=>nothing,"status"=>"unobserved_context")]
    x
end
function support_checks()
    @testset "Saved listener support and unavailable historical context" begin
        x=support_fixture();text=encode(x);saved=T.SavedReport(text,hashtext(text),nothing,nothing)
        r=T.report(saved)
        @test r.listener_support.status===:recorded && length(r.listener_support.rows)==2
        @test r.numerical_qualified
        @test any(contains("linear-trend extrapolation"),r.warnings)
        @test any(contains("no observations"),r.warnings)
        @test r.rows==T.report(T.SavedReport(encode(fixture()),hashtext(encode(fixture())),nothing,nothing)).rows
        for change in (
                y->delete!(y,"listener_support"),
                y->pop!(y["listener_support"]),
                y->(y["listener_support"][1]["status"]="within_observed_range"),
                y->(y["listener_support"][1]["listener"]=2),
                y->(y["listener_support"][1]["listener_label"]="wrong"),
                y->(y["listener_support"][1]["time"]=.4),
                y->(y["listener_support"][1]["l1"]=1),
                y->(y["listener_support"][1]["side"]="right"),
                y->(y["listener_support"][1]["observations"]=true),
                y->(y["listener_support"][1]["observations"]=2),
                y->(y["listener_support"][1]["lower"]=.3),
                y->(y["listener_support"][1]["upper"]="NaN"),
                y->(y["listener_support"][2]["lower"]=0.),
                y->(y["public_api"]=false),
                y->(y["context"]["sources"][3]["sha256"]=T.PREVIOUS_PACKAGE_PRODUCER[3]))
            wrong=deepcopy(x);change(wrong);t=encode(wrong)
            @test_throws ArgumentError T.SavedReport(t,hashtext(t),nothing,nothing)
        end
        old=deepcopy(x);delete!(old,"listener_support")
        old["context"]["sources"][3]["sha256"]=T.PREVIOUS_PACKAGE_PRODUCER[3]
        t=encode(old);old_saved=T.SavedReport(t,hashtext(t),nothing,nothing)
        @test T.report(old_saved).listener_support.status===:not_recorded
        @test isempty(T.report(old_saved).listener_support.rows)
        @test any(contains("cannot be assessed"),T.report(old_saved).warnings)
        mktempdir() do dir
            receipt=T.save_report(joinpath(dir,"support.json"),saved)
            restored=T.load_report(receipt.path;expected_sha256=receipt.sha256)
            @test restored.source_json==saved.source_json
            @test T.report(restored).listener_support==r.listener_support
            @test T.report(restored).warnings==r.warnings
        end
    end
end
end
