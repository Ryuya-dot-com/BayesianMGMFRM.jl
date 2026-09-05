using Test
using BayesianMGMFRM

@testset "intended category scale" begin
    table = (
        person = ["P1", "P1", "P1", "P1", "P2", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
        score = [1, 2, 1, 2, 2, 1, 2, 1],
    )

    inferred = FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
    @test inferred.category_levels == [1, 2]
    inferred_audit = ordinal_response_pattern_audit(inferred)
    @test inferred_audit.category_scale.source ===
        :contiguous_observed_minimum_to_maximum
    @test inferred_audit.category_scale.intended_levels == (1, 2)
    @test inferred_audit.category_scale.observed_levels == (1, 2)
    @test !inferred_audit.category_scale.unobserved_endpoints_detectable

    declared = FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:2,
    )
    @test declared.category_levels == [0, 1, 2]
    @test declared.category == table.score .+ 1

    report = validate_design(declared)
    @test report.passed
    codes = Set(issue.code for issue in report.issues)
    @test :unobserved_declared_endpoint in codes
    @test :unused_interior_category ∉ codes
    endpoint_issue = only(issue for issue in report.issues
        if issue.code === :unobserved_declared_endpoint)
    @test endpoint_issue.context[:unobserved_endpoints] == [0]
    endpoint_suggestion = only(row for row in validation_suggestions(report)
        if row.code === :unobserved_declared_endpoint)
    @test endpoint_suggestion.action ===
        :verify_declared_scale_and_threshold_support

    declared_audit = ordinal_response_pattern_audit(declared)
    @test declared_audit.category_scale.source === :declared
    @test declared_audit.category_scale.intended_levels == (0, 1, 2)
    @test declared_audit.category_scale.observed_levels == (1, 2)
    @test declared_audit.category_scale.unobserved_endpoint_categories == (0,)
    @test declared_audit.category_scale.unobserved_endpoints_detectable

    inferred_design = getdesign(mfrm_spec(
        inferred;
        thresholds = :partial_credit,
    ))
    declared_design = getdesign(mfrm_spec(
        declared;
        thresholds = :partial_credit,
    ))
    @test isempty(inferred_design.blocks[:thresholds])
    @test length(declared_design.blocks[:thresholds]) == 2

    params = zeros(length(declared_design.parameter_names))
    pointwise = pointwise_loglikelihood(declared_design, params)
    @test length(pointwise) == declared.n
    @test all(isfinite, pointwise)
    probabilities = predictive_probabilities(
        declared_design,
        permutedims(params),
    )
    @test size(probabilities) == (1, declared.n, 3)
    @test all(isapprox.(sum(probabilities; dims = 3), 1.0; atol = 1e-12))

    data_manifest = model_manifest(declared).data
    @test data_manifest.category_scale.source === :declared
    @test data_manifest.category_scale.intended_levels == [0, 1, 2]
    @test data_manifest.category_scale.unobserved_endpoint_levels == [0]

    refit_data = BayesianMGMFRM._loo_refit_training_data(
        declared,
        findall(==(1), declared.score),
    )
    @test refit_data.category_levels == [0, 1, 2]
    @test refit_data.columns.category_scale_source === :declared

    fitted = fit(
        declared_design;
        backend = :julia,
        ndraws = 3,
        warmup = 0,
        chains = 1,
        seed = 20260815,
    )
    metadata = fit_metadata(fitted)
    @test metadata.category_scale.source === :declared
    @test metadata.category_scale.intended_levels == [0, 1, 2]
    public_metadata = fit_metadata(fitted; view = :public)
    @test public_metadata.category_scale.intended_levels == [0, 1, 2]
    @test public_metadata.category_scale.endpoints_explicitly_declared

    mktempdir() do directory
        cache_path = joinpath(directory, "declared-scale-fit.jls")
        record = save_fit_cache(cache_path, fitted)
        @test record.artifact.manifest.data.category_scale.source === :declared
        loaded = load_fit_cache(cache_path)
        @test loaded.design.spec.data.category_levels == [0, 1, 2]
        @test fit_metadata(loaded).category_scale.source === :declared
    end

    interior_table = merge(table, (score = [0, 2, 0, 2, 2, 0, 2, 0],))
    interior = FacetData(
        interior_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:2,
    )
    interior_codes = Set(issue.code for issue in validate_design(interior).issues)
    @test :unused_interior_category in interior_codes
    @test :unobserved_declared_endpoint ∉ interior_codes

    one_observed_table = merge(table, (score = fill(1, length(table.score)),))
    one_observed = FacetData(
        one_observed_table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:2,
    )
    one_observed_report = validate_design(one_observed)
    @test !one_observed_report.passed
    @test :single_observed_category in
        Set(issue.code for issue in one_observed_report.issues)
    @test ordinal_response_pattern_audit(one_observed).fit_prohibited

    @test_throws ArgumentError FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:0,
    )
    @test_throws ArgumentError FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = [0, 2],
    )
    @test_throws ArgumentError FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = [0, 1, 1, 2],
    )
    @test_throws ArgumentError FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = [2, 1, 0],
    )
    @test_throws ArgumentError FacetData(
        table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
        category_levels = 0:1,
    )
end
