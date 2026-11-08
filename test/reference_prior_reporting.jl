module ReferencePriorReportingChecks
using Test, BayesianMGMFRM
const B = BayesianMGMFRM
const CODE = :reference_zero_prior_coordinate_dependence

# Fixed arithmetic inputs and values: these are not posterior samples.
cells = [(p, r, i) for p in 1:3 for r in 1:3 for i in 1:2]
table = (person=first.(cells), rater=getindex.(cells, 2), item=last.(cells),
    score=[mod(sum(c), 3) for c in cells])
data = FacetData(table; person=:person, rater=:rater, item=:item, score=:score)
function fixture(spec)
    design = getdesign(spec)
    draws = [0.02sin(d + j) for d in 1:8, j in eachindex(design.parameter_names)]
    return MFRMFit(design, MFRMPrior(), draws,
        [logposterior(design, vec(draws[d, :])) for d in axes(draws, 1)],
        1., ones(Int, 8), collect(1:8), [1.], :julia, :random_walk_metropolis, 0, .1)
end
function report(fit)
    fit_report(fit; include_prior_predictive=false, include_posterior_predictive=false,
        include_category_functioning=false, include_rater_homogeneity=false,
        include_calibration=false, include_waic=false, include_loo=false,
        include_artifact=false, draw_indices=1:8, view=:public)
end
const FIT = fixture(mfrm_spec(data))
const REPORT = report(FIT)
const checks = @testset "Reference prior meaning and warning persistence" begin
    warning = only(filter(r -> r.code === CODE, REPORT.fixed_coordinates.warning_rows))
    @test warning.n_coordinates == 2
    @test occursin("rater[1]", warning.message)
    @test occursin("item[1]", warning.message)
    @test occursin("not input row order", warning.message)
    @test !REPORT.fixed_coordinates.summary.hard_anchor_warning
    @test !REPORT.diagnostics.summary.passed # Reporting did not bless the fixture.
    @test occursin(string(CODE), fit_report_markdown(REPORT))
    @test occursin("Default zero references:", repr(MIME"text/plain"(), FIT.design.spec))
    @test occursin("transporting the joint prior", repr(MIME"text/plain"(), FIT.design.spec))
    reversed = FacetData(map(reverse, table); person=:person,rater=:rater,item=:item,score=:score)
    @test reversed.rater_levels == data.rater_levels
    @test reversed.item_levels == data.item_levels
    @test getdesign(mfrm_spec(reversed)).parameter_names == FIT.design.parameter_names
    absent = fixture(mfrm_spec(FacetData(table; person=:person, rater=nothing, item=:item, score=:score)))
    absent_warning = only(filter(r -> r.code === CODE, report(absent).fixed_coordinates.warning_rows))
    @test absent_warning.n_coordinates == 1
    @test !occursin("no_rater", absent_warning.message)
    mixed = report(fixture(mfrm_spec(data; anchors=[(block=:rater,level=2,value=.25,type=:hard)])))
    @test mixed.fixed_coordinates.n_warning_rows == 3
    @test only(filter(r -> r.code === CODE, mixed.fixed_coordinates.warning_rows)).n_coordinates == 1
    @test any(r -> r.code === :hard_anchor_fixed_not_estimated, mixed.fixed_coordinates.warning_rows)
    @test any(r -> r.code === :hard_anchor_zero_centered_prior_coordinate_dependence,
        mixed.fixed_coordinates.warning_rows)
    anchored = report(fixture(mfrm_spec(data; anchors=[
        (block=:rater,level=2,value=.25,type=:hard),
        (block=:item,level=2,value=.1,type=:hard)])))
    @test !any(r -> r.code === CODE, anchored.fixed_coordinates.warning_rows)
    single = FacetData((person=[1,2],rater=[1,1],item=[1,1],score=[0,1]);
        person=:person,rater=:rater,item=:item,score=:score)
    @test !any(r -> r.code === CODE, report(fixture(mfrm_spec(single))).fixed_coordinates.warning_rows)
    mktempdir() do directory
        save_fit_report_bundle(directory, REPORT; require_complete=true)
        restored = load_fit_report_bundle(directory; require_complete=true)
        @test any(r -> r["code"] == string(CODE), restored["fixed_coordinates"]["warning_rows"])
        @test !restored["diagnostics"]["summary"]["passed"]
    end
end
end
