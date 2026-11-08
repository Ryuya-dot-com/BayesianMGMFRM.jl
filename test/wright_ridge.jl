module WrightRidgeChecks
using Test, Statistics, BayesianMGMFRM
const B=BayesianMGMFRM
include("fixtures/reporting_fit.jl")
include("fixtures/wright_histogram_fit.jl")

@testset "Wright ridges: deterministic inputs, no inference" begin
    f=wright_histogram_fit(;npeople=6,thresholds=:partial_credit)
    before=copy(f.draws)
    d=B.wright_ridge_data(f;bandwidth=.08)
    @test isequal(d.rows,B.wright_map_data(f))
    @test d.diagnostic==B._wright_plot_data(f).diagnostic
    @test f.draws==before
    @test d.groups==[:person,:rater,:item,:threshold]
    @test d.ridge.bandwidth==.08
    for (i,row) in enumerate(d.rows)
        density=d.ridge.densities[i]
        if row.is_fixed
            @test d.ridge.statuses[i]===:fixed && density===nothing
            continue
        end
        @test d.ridge.statuses[i]===:density
        grid=d.ridge.grid
        area=sum(diff(grid).*(density[1:end-1]+density[2:end])/2)
        @test isapprox(area,1;atol=.0001)
        # Independent raw-column plus reconstructed final-step calculation.
        values = if row.component===:threshold
            item=row.item_parameter_index===missing ? fill(row.item_measure_mean,size(f.draws,1)) :
                f.draws[:,row.item_parameter_index]
            step = row.parameter_index===missing ?
                -sum(f.draws[:,f.design.blocks[:thresholds][(row.item_index-1)*2+1:row.item_index*2]];dims=2)[:] :
                f.draws[:,row.parameter_index]
            item+step
        else
            f.draws[:,row.parameter_index]
        end
        oracle=[mean(exp.(-0.5 .* ((g .- values) ./ 0.08).^2))/(0.08sqrt(2pi)) for g in grid]
        @test density≈oracle
        @test row.position_median≈median(values)
    end
    @test B.wright_ridge_data(f).ridge.bandwidth>0
    @test_throws ArgumentError B.wright_ridge_data(f;person_display=:histogram)
    @test_throws ArgumentError B.wright_ridge_data(f;bandwidth=NaN)
    @test_throws ArgumentError B.wright_ridge_data(f;bandwidth=true)
    @test_throws ArgumentError B.wright_ridge_data(f;bandwidth=1e-12)
    @test_throws ArgumentError B.wright_ridge_data(f;points=63)
    @test_throws ArgumentError B.wright_ridge_data(f;max_levels=1)
    @test_throws ArgumentError B._wright_plot_data(f;kind=:wrong)
    @test_throws ArgumentError B._wright_plot_data(f;bandwidth=.1)
    fixed=reporting_fit(:mfrm;chains=2,ndraws=20,amplitude=0.)
    c=B.wright_ridge_data(fixed)
    @test c.ridge.bandwidth===nothing
    @test all(isnothing,c.ridge.densities)
    @test !isempty(c.ridge.constant_labels)
    @test :constant in c.ridge.statuses && :fixed in c.ridge.statuses
    anchors=[(;block=:rater,level="R2",value=.75,type=:hard),
        (;block=:item,level="I2",value=1.25,type=:hard)]
    anchored=wright_histogram_fit(;npeople=6,anchors)
    a=B.wright_ridge_data(anchored;bandwidth=.08)
    @test all(a.ridge.statuses[i]===:fixed for i in eachindex(a.rows) if a.rows[i].is_fixed)
    @test B._fit_report_figure_options((wright=(kind=:ridge,bandwidth=.08,points=512),)) isa NamedTuple
end
end
