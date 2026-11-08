module CriterionCollapsePlotChecks
using Test,SHA
import BayesianMGMFRM as B
const C=B.Experimental.CriterionCollapse
function fixture()
    diagnostic=(;rank_normalized_rhat=1.,bulk_ess=500.,tail_ess=500.)
    diagnostics=(;qualified=true,raw=[diagnostic],model=[diagnostic],
        sampler=[(;n_divergences=0,n_max_treedepth=0) for _ in 1:4],
        warmup=[(;n_divergences=j,coverage=:recorded) for j in 1:4])
    prior=(;person_precision_shape=3.,person_precision_rate=2.,rater_precision_shape=3.,
        rater_precision_rate=.5,step_sd=1.5,class_alpha=1.,class_beta=1.)
    base=(;scope=C.SCOPE,target_identity="a"^64,source_sample_content_hash="b"^64,
        prior,diagnostics,warning="Artificial fixture warning; not posterior evidence.")
    summary(p,se)=(;mean=p,mean_mcse=se,mcse_status=:available,interval=nothing)
    r=merge(base,(;labels=(;rater=["R1","R2"]),classes=[(;rater="R1",summary(.1,.01)...),(;rater="R2",summary(.3,.02)...)]))
    rows=[(;rater="R$r",criterion="C$i",category=k,n_observations=4,observed_count=[1,2,1][k+1],
        observed_proportion=[.25,.5,.25][k+1],expected=summary([.2,.5,.3][k+1],.002*(1+r)),
        observed_minus_expected=[.25,.5,.25][k+1]-[.2,.5,.3][k+1]) for i in 1:3 for r in 1:2 for k in 0:2]
    c=merge(base,(;categories=collect(0:2),rows,n_observations=24))
    (;r,c)
end
@testset "Criterion-collapse figures: computed values and warning boundaries" begin
    f=fixture();classes=C._class_plot_data(f.r);cat=C._category_plot_data(f.c;rater="R1")
    @test classes.labels==["R1","R2"]
    @test getproperty.(classes.values,:probability)==[.1,.3]
    @test getproperty.(classes.values,:mcse)==[.01,.02]
    @test all(p->p.observed==[.25,.5,.25],cat.panels)
    @test all(p->getproperty.(p.expected,:probability)==[.2,.5,.3],cat.panels)
    @test cat.mcse_max==.006 # Full-report range includes the unselected rater.
    @test occursin("warmup divergences: 10",classes.note)
    @test occursin("step SD=1.5",classes.note)
    @test occursin(f.r.warning,classes.note)
    @test classes.source_sample_content_hash==f.r.source_sample_content_hash
    @test_throws ArgumentError C._category_plot_data(f.c;rater="not present")
    bad=merge(f.r,(;diagnostics=merge(f.r.diagnostics,(;qualified=false))))
    @test occursin("WARNING / not qualified",C._class_plot_data(bad).note)
    @test !C._class_plot_data(bad).whole_fit_qualified
    missing_class=merge(f.r.classes[1],(;mean_mcse=missing,mcse_status=:degenerate_draws))
    unavailable=merge(f.r,(;classes=[missing_class,f.r.classes[2]]))
    @test C._class_plot_data(unavailable).mcse_unavailable==1
    @test ismissing(C._class_plot_data(unavailable).values[1].mcse)
    rows=map(f.c.rows) do row
        row.rater=="R2" && row.criterion=="C1" && row.category==0 ?
            merge(row,(;expected=merge(row.expected,(;mean_mcse=missing,mcse_status=:degenerate_draws)))) : row
    end
    subset=C._category_plot_data(merge(f.c,(;rows));rater="R1")
    @test subset.mcse_unavailable==1
    @test all(v->!ismissing(v.mcse),vcat(getproperty.(subset.panels,:expected)...))
    @test_throws ArgumentError C._class_plot_data(merge(f.r,(;classes=[f.r.classes[1],f.r.classes[1]])))
    @test_throws ArgumentError C._class_plot_data(merge(f.r,(;classes=[merge(f.r.classes[1],(;mean=1.1)),f.r.classes[2]])))
    @test_throws ArgumentError C._class_plot_data(merge(f.r,(;classes=[merge(f.r.classes[1],(;interval=(0.,1.))),f.r.classes[2]])))
    @test_throws ArgumentError C._category_plot_data(merge(f.c,(;rows=f.c.rows[2:end]));rater="R1")
    @test_throws ArgumentError C._category_plot_data(merge(f.c,(;n_observations=25));rater="R1")
    @test_throws ArgumentError C._category_plot_data(merge(f.c,(;rows=[merge(f.c.rows[1],(;observed_count=3));f.c.rows[2:end]]));rater="R1")
    @test_throws ArgumentError C._category_plot_data(merge(f.c,(;categories=[0,1,3]));rater="R1")
    @test_throws ArgumentError C._class_plot_data(merge(f.r,(;scope=merge(C.SCOPE,(;latent_class_unit=:rating_row)))))
    @test C._plot_labels(Any[1,"1"])==["1","\"1\""]
    @test_throws ArgumentError C._plot_labels(["same","same"])
    mktempdir() do directory
        for (name,report) in (("classes",f.r),("categories",f.c),("unavailable",unavailable))
            path=joinpath(directory,name*".json");C.save_report(path,report)
            digest=bytes2hex(sha256(read(path)));loaded=C.load_report(path;expected_sha256=digest)
            @test isequal(B.load_report(path;expected_sha256=digest),loaded)
            @test_throws ArgumentError B.load_report(path;expected_sha256="c"^64)
            @test_throws ArgumentError B.load_report(path)
            @test_throws UndefKeywordError C.load_report(path)
            @test loaded.target_identity==report.target_identity
            if name=="categories"
                @test C._category_plot_data(loaded;rater="R1").panels==cat.panels
            else
                @test isequal(C._class_plot_data(loaded).values,C._class_plot_data(report).values)
            end
            @test_throws ArgumentError C.load_report(path;expected_sha256="c"^64)
            @test_throws ArgumentError C.load_report(path;expected_sha256="not a digest")
        end
        path=joinpath(directory,"other.json")
        C.save_report(path,(;numerical_checks_passed=true))
        @test_throws ArgumentError C.load_report(path;expected_sha256=bytes2hex(sha256(read(path))))
    end
    if Base.get_extension(B,:BayesianMGMFRMCairoMakieExt)===nothing
        @test_throws ArgumentError C.plot_classes(f.r)
        @test_throws ArgumentError C.plot_categories(f.c;rater="R1")
    end
end
end
