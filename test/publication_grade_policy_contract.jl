module PublicationGradeThresholdPolicyGeneratorForTest

include(joinpath(@__DIR__, "..", "scripts",
    "generate_mgmfrm_publication_grade_threshold_model_weight_policy_review.jl"))

end


@testset "Publication-grade model-weight input contract" begin
    generator = PublicationGradeThresholdPolicyGeneratorForTest
    policy = generator.load_json(joinpath(@__DIR__, "fixtures",
        "gmfrm_prediction_target_and_model_weight_policy.json"))

    empty_batch = (;
        summary = (;
            all_125_units_executed = false,
            n_heldout_model_rank_rows = 0,
        ),
        heldout_model_rank_rows = NamedTuple[],
        threshold_profile_model_summary_rows = NamedTuple[],
    )
    empty_error = try
        generator.model_weight_rows(empty_batch, policy)
        nothing
    catch error
        error
    end
    @test empty_error isa ArgumentError
    @test occursin("completed 125-unit heldout surface",
        sprint(showerror, empty_error))
    @test occursin("--read-local-artifacts", sprint(showerror, empty_error))

    models = sort(collect(keys(generator.MODEL_SURFACE)))
    partial_rows = [
        (model = model, heldout_elpd = -1.0)
        for model in models
    ]
    partial_batch = (;
        summary = (;
            all_125_units_executed = false,
            n_heldout_model_rank_rows = length(partial_rows),
        ),
        heldout_model_rank_rows = partial_rows,
        threshold_profile_model_summary_rows = NamedTuple[],
    )
    partial_error = try
        generator.model_weight_rows(partial_batch, policy)
        nothing
    catch error
        error
    end
    @test partial_error isa ArgumentError
    @test occursin("actual_rows=$(length(partial_rows))",
        sprint(showerror, partial_error))

    unbalanced_rows = NamedTuple[]
    for (model, count) in zip(models, (24, 26, 25, 25, 25))
        append!(unbalanced_rows, [
            (model = model, heldout_elpd = -Float64(index))
            for index in 1:count
        ])
    end
    unbalanced_batch = (;
        summary = (;
            all_125_units_executed = true,
            n_heldout_model_rank_rows = 125,
        ),
        heldout_model_rank_rows = unbalanced_rows,
        threshold_profile_model_summary_rows = NamedTuple[],
    )
    @test_throws ArgumentError generator.model_weight_rows(
        unbalanced_batch, policy)

    completed_batch = generator.load_json(joinpath(@__DIR__, "fixtures",
        "mgmfrm_publication_grade_refit_batch_results_review.json"))
    rows = generator.model_weight_rows(completed_batch, policy)
    @test length(rows) == 5
    @test all(row -> row.n_heldout_rows == 25, rows)
    @test sum(row.local_diagnostic_weight for row in rows) ≈ 1.0
end
