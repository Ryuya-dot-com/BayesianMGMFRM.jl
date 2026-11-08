module UnifiedPersistenceChecks
using BayesianMGMFRM, Test, Serialization
using BayesianMGMFRM: JSON3, SHA
const B=BayesianMGMFRM
const E=B.Experimental
const SA=E.StarAssociation
const JR=E.JointRatings
const S=JR.S
const OA=JR.OrdinalAssociation
const C3=E.Correlated3D
include("common_prediction_fixtures.jl")
include("fixtures/experimental_diagnostic_record.jl")
include("joint_ratings_fixture.jl")
include("ordinal_association.jl")
include("correlated_3d.jl")
include("rater_drift_fitting.jl")
include("three_indicator_fitting.jl")
include("three_indicator_reports.jl")
include("../examples/star_association.jl")

# All coordinates/telemetry below are manufactured, not posterior/MCMC evidence.
function run_fixture(t,initial)
    r=diagnostic_record(:RaterGroupEffects;ndraws=12).run
    draws=[initial[j]+.06sin(s+.7j) for s in 1:r.total_draws,j in eachindex(initial)]
    logdensities=[B.LogDensityProblems.logdensity(t,q) for q in eachrow(draws)]
    stats=[merge(s,(;log_density=logdensities[i])) for (i,s) in enumerate(r.sampler_stats)]
    merge(r,(;nparams=length(initial),initial,
        initial_logdensity=B.LogDensityProblems.logdensity(t,initial),draws,logdensities,
        sampler_stats=stats,sampler_rows=B._generalized_candidate_sampler_rows(logdensities,
            r.iterations,r.chain_acceptance,stats,r.controls,:advancedhmc)))
end
function records()
    j=static_fixture();a=OrdinalAssociationTests.fixture()
    c=C3.model(Correlated3DPublicChecks.fixture();scales=Correlated3DPublicChecks.S,lkj_eta=2.5)
    arun=run_fixture(a,OA.initial(a))
    Any[JR.W.checked_result(j,run_fixture(j,S.initial(j))),
        OA._record(a,arun,zeros(arun.total_draws,2);provenance=(;fixture=true),warnings=["Artificial test fixture"]),
        C3.record(c,run_fixture(c,C3.initial(c))),
        (diagnostic_record(k;ndraws=12) for k in (:RaterGroupEffects,:RaterItemInteractions,:CriterionCollapse))...]
end
function star()
    m=StarAssociationExample.inputs().spec
    cfg=SA._build_sampler_config(ndraws=12,warmup=5,chains=4)
    SA._build_star_result(m,cfg,[.1sin(s+p) for s in 1:48,p in 1:m.dim],NamedTuple[],NamedTuple[];
        provenance=(;operation=:deterministic_test_fixture))
end
hashfile(p)=bytes2hex(SHA.sha256(read(p)))
jsonvalue(x)=JSON3.read(JSON3.write(B._json_export_value(x)))

@testset "One native/report path across model records" begin
    mktempdir() do dir
        for (i,r) in enumerate([records();star()])
            tag=B._sample_schema_symbol(r)
            kw=tag===:rater_item_interactions ? (;practical_threshold=.2,interval=.9) :
                tag===:rater_group_effects ? (;reference_group="A",practical_threshold=.2,interval=.9) : (;)
            fitpath=joinpath(dir,"fit-$i.jls");reportpath=joinpath(dir,"summary-$i.json")
            save_fit(fitpath,r)
            restored=load_fit(fitpath)
            @test restored.content_hash==r.content_hash
            @test_throws MethodError load_fit(fitpath;unsupported_control=true)
            @test_throws Exception save_fit(fitpath,r)
            receipt=save_report(reportpath,restored;return_receipt=true,kw...)
            @test receipt.path==abspath(reportpath)
            @test receipt.sha256==hashfile(reportpath)
            h=hashfile(reportpath)
            report=load_report(reportpath;expected_sha256=h)
            tag=B._sample_schema_symbol(r)
            owner=r isa SA.StarResult ? SA : getproperty(B,Dict(:joint_ratings=>:_JR_MOD,
                :ordinal_association=>:_OA_MOD,:correlated_3d=>:_C3D_MOD,
                :rater_group_effects=>:_RGE_MOD,:rater_item_interactions=>:_RII_MOD,
                :criterion_collapse=>:_CC_MOD)[tag])
            directpath=joinpath(dir,"direct-$i.json")
            owner.save_report(directpath,posterior_summary(r;kw...))
            encoded=JSON3.read(read(directpath,String))
            expected=hasproperty(encoded,:data) ? encoded.data : encoded
            # Existing writers have their own matrix and nonfinite encodings.
            @test isequal(report,expected)
            @test_throws Exception save_report(reportpath,r;kw...)
            @test hashfile(reportpath)==h
            @test_throws ArgumentError load_report(reportpath;expected_sha256="0"^64)
            @test_throws ArgumentError load_report(reportpath;expected_sha256="invalid")
            @test_throws Exception load_report(reportpath;expected_sha256=h,unsupported_control=true)
            badpath=joinpath(dir,"bad-$i.json")
            @test_throws MethodError save_report(badpath,posterior_summary(r;kw...);unsupported_control=true)
            @test !ispath(badpath)
            @test_throws MethodError save_report(badpath,r;unsupported_control=true,kw...)
            @test !ispath(badpath)
            if B._sample_schema_symbol(r)===:criterion_collapse
                @test_throws ArgumentError load_report(reportpath)
            else
                @test isequal(jsonvalue(load_report(reportpath)),jsonvalue(report))
            end
            if B._sample_schema_symbol(r) in (:rater_item_interactions,:rater_group_effects)
                @test_throws UndefKeywordError save_report(badpath,r)
                @test !ispath(badpath)
            end
        end
        f=reporting_fit(:mfrm;ndraws=20,chains=2)
        p=joinpath(dir,"common.json");save_report(p,f;view=:public)
        @test isequal(load_report(p;expected_sha256=hashfile(p)),load_report(p))
        @test_throws ArgumentError load_report(p;expected_sha256="0"^64)
        native=joinpath(dir,"common.jls");save_fit(native,f)
        @test load_fit(native;return_record=true).fit.draws==f.draws
        @test_throws MethodError load_fit(native;unsupported_control=true)
        for payload in ((;data=(;value=1)),(;schema="unknown.v1",data=(;value=1)),
                (;schema="bayesianmgmfrm.joint_rating_report_json.v1"))
            p=joinpath(dir,"unknown.json");write(p,JSON3.write(payload))
            @test_throws ArgumentError load_report(p)
            @test_throws ArgumentError load_report(p;expected_sha256=hashfile(p))
        end
    end
end

@testset "Stored plan selects the native directory reader" begin
    r=RaterDriftFittingChecks
    rd=r.prepare(r.target();fixture=false)
    ti=ThreeIndicatorFittingChecks.prepare_three_indicator_example(;
        controls=ThreeIndicatorFittingChecks.CONTROLS,chain_seeds=collect(41:44))
    for (plan,T) in ((rd,E.RaterDrift),(ti,E.ThreeIndicator))
        mktempdir() do dir
            open(io->serialize(io,plan),joinpath(dir,"plan.jls"),"w")
            partial=load_fit(dir;require_complete=false)
            @test partial isa T.NativeFit
            @test isempty(partial.saved.chains)
            @test partial.saved.plan.content_hash==plan.content_hash
            @test_throws ArgumentError load_fit(dir)
            @test_throws MethodError load_fit(dir;unsupported_control=true)
            @test readdir(dir)==["plan.jls"]
        end
    end
    mktempdir() do dir
        @test_throws ArgumentError load_fit(dir)
        open(io->serialize(io,(;schema="unknown")),joinpath(dir,"plan.jls"),"w")
        @test_throws ArgumentError load_fit(dir;require_complete=false)
    end
end

@testset "Three-outcome reports keep their mandatory receipt and controls" begin
    F=ThreeIndicatorReportChecks;T=E.ThreeIndicator
    text=F.encode(F.fixture());saved=T.SavedReport(text,F.hashtext(text),nothing,nothing)
    mktempdir() do dir
        p=joinpath(dir,"source.json");write(p,text)
        @test load_report(p;expected_sha256=hashfile(p)) isa T.SavedReport
        receipt=save_report(joinpath(dir,"copy.json"),saved;return_receipt=true)
        restored=load_report(receipt.path;expected_sha256=receipt.sha256)
        @test restored isa T.SavedReport
        @test restored.source_json==saved.source_json
        @test isequal(posterior_summary(restored),T.report(saved))
        @test_throws ArgumentError load_report(receipt.path)
        @test_throws MethodError load_report(receipt.path;expected_sha256=receipt.sha256,unsupported_control=true)
        @test_throws ArgumentError load_report(receipt.path;expected_sha256=receipt.sha256,
            comparison_path="not-read",comparison_sha256="0"^64)
        @test_throws MethodError save_report(joinpath(dir,"bad.json"),saved;unsupported_control=true)
        @test !ispath(joinpath(dir,"bad.json"))
    end
end
end
