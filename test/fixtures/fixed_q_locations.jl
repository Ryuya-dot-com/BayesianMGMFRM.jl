# Uses an existing fit; expected averages come directly from free draw columns.
function check_fixed_q_locations(fit)
    checked = B._mfrm_fixed_q_samples(fit)
    spec, run = B._fixed_q_result_spec(checked), fit.record.run
    diagnostic = diagnostics(fit)
    original = deepcopy(run)
    @test isequal(diagnostic.summary, checked.diagnostics.summary)
    @test isequal(diagnostic.model_parameter_rows, checked.diagnostics.model_parameter_rows)
    if any(!=(1), sum(spec.q_matrix; dims = 2))
        @test diagnostic.location_status === :unsupported
        @test isempty(diagnostic.location_rows) && diagnostic.location_summary === nothing
        @test occursin("within-item", diagnostic.location_interpretation)
        @test_throws ArgumentError B._mfrm_fixed_q_diagnostic_plot_data(checked; view = :location)
        return
    end
    @test diagnostic.location_status === :computed
    options = (; diagnostics = (; view = :location, dimension = 1))
    @test B._fit_report_figure_options(options) == options
    @test length(diagnostic.location_rows) == 3spec.dimensions
    plot = B._mfrm_fixed_q_diagnostic_plot_data(checked; view = :location)
    @test plot.chain_ids == run.chain_ids && plot.iterations == run.iterations
    @test isequal(plot.summary, diagnostic.summary)
    @test occursin("not population means", plot.location_note)
    @test occursin("$(replace(String(diagnostic.location_summary.flag), '_' => ' '))", plot.location_note)
    P, R, D = length(spec.data.person_levels), length(spec.data.rater_levels), spec.dimensions
    expected = Vector{Float64}[]
    for d in 1:D
        people = [sum(run.draws[j, d + (p-1)*D] for p in 1:P) / P for j in axes(run.draws, 1)]
        indices = findall(spec.q_matrix[:, d])
        items = [sum(run.draws[j, P*D + R-1 + i] for i in indices) / length(indices) for j in axes(run.draws, 1)]
        append!(expected, [people, items, people - items])
        selected = B._mfrm_fixed_q_diagnostic_plot_data(checked; view = :location,
            dimension = spec.dimension_labels[d])
        @test length(selected.rows) == 3 && all(r.dimension == d for r in selected.rows)
        @test selected.location_note == plot.location_note # Includes unselected dimensions.
    end
    metrics = B._candidate_mcmc_diagnostic_rows(hcat(expected...),
        String[r.parameter for r in plot.rows], run.controls.chains;
        parameter_space = :derived_unit_logit, split_chains = run.split_chains_requested,
        rhat_threshold = run.checked.rhat_threshold, ess_threshold = run.checked.ess_threshold)
    for (coordinate, values, row, metric) in zip(plot.rows, expected, diagnostic.location_rows, metrics)
        @test coordinate.values ≈ values
        @test coordinate.derived && !coordinate.fixed
        @test row.dimension_label == spec.dimension_labels[row.dimension]
        @test row.flag == metric.flag && row.parameter_space === :derived_unit_logit
        for field in (:rank_normalized_rhat, :bulk_ess, :tail_ess)
            @test isapprox(getproperty(row, field), getproperty(metric, field); nans = true)
        end
    end
    selected = B._mfrm_fixed_q_diagnostic_plot_data(checked; view = :location, block = :person_minus_item_mean)
    @test length(selected.rows) == D
    @test getproperty.(selected.rows, :parameter) == getproperty.(plot.rows[3:3:end], :parameter)
    for options in ((; view = :absent), (; view = :location, dimension = "absent"),
            (; view = :location, scale = :raw), (; view = :location, bins = true))
        @test_throws ArgumentError B._mfrm_fixed_q_diagnostic_plot_data(checked; options...)
    end
    @test isequal(run, original)
    empty!(diagnostic.location_rows)
    @test length(diagnostics(fit).location_rows) == 3D
end
