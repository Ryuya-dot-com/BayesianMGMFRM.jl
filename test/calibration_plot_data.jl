module CalibrationPlotDataChecks

using BayesianMGMFRM, Test, JSON3

const METADATA = (:n_observations, :n_draws, :predicted_median,
    :interval_probability, :lower_probability, :upper_probability)

function check_rows(rows)
    before = JSON3.write(rows)
    points = calibration_plot_data(rows)
    @test length(points) == length(rows)
    for (row, point) in zip(rows, points)
        for name in propertynames(row)
            @test isequal(getproperty(point, name), getproperty(row, name))
        end
        @test point.reference == row.predicted_mean
    end
    @test JSON3.write(rows) == before
    restored = JSON3.read(JSON3.write(points))
    @test JSON3.read(JSON3.write(calibration_plot_data(restored))) == restored
    return points
end

@testset "calibration plot metadata without sampling" begin
    # Fixed coordinate inputs exercise the table/plot contract, not inference.
    cells = [(p,i,r) for p in 1:2 for i in 1:2 for r in 1:2]
    levels = [1, 2, 3]
    data = FacetData((; person=first.(cells), item=getindex.(cells,2),
        rater=last.(cells), score=[levels[mod(sum(c),3)+1] for c in cells]);
        person=:person, item=:item, rater=:rater, score=:score, category_levels=levels)
    design = getdesign(mfrm_spec(data; thresholds=:partial_credit))
    draws = reshape(0.05sin.(1:(4length(design.parameter_names))), 4, :)
    rows = calibration_table(design, draws; target=:all, bins=3, interval=0.8)
    points = check_rows(rows)
    @test length(points) == 12
    @test all(p -> p.n_draws == 4 && p.interval_probability == 0.8, points)
    @test all(p -> p.lower_probability ≈ 0.1 && p.upper_probability ≈ 0.9, points)
    for series in ((:expected_score, missing), ((:category_probability, k) for k in levels)...)
        group = filter(p -> isequal((p.target, p.category), series), points)
        @test sum(p.n_observations for p in group) == data.n
    end
    @test isempty(calibration_plot_data(NamedTuple[]))

    # Earlier callers could retain only fields needed by the old projection.
    row = first(rows)
    reduced = (; (name => getproperty(row, name) for name in propertynames(row)
        if !(name in METADATA))...)
    for old in (reduced, JSON3.read(JSON3.write(reduced)))
        point = only(calibration_plot_data([old]))
        @test all(name -> ismissing(getproperty(point, name)), METADATA)
        @test point.predicted_mean == old.predicted_mean
        @test point.flag == old.flag
    end
    flagged = merge(row, (; flag=:outside_interval))
    @test only(calibration_plot_data([flagged])).flag === :outside_interval
end

end
