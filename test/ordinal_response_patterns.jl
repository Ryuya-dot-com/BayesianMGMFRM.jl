using Test
using BayesianMGMFRM

issue_codes(report) = Set(issue.code for issue in report.issues)

@testset "ordinal response pattern audit" begin
    skipped = (
        person = ["P1", "P1", "P1", "P1", "P2", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
        score = [1, 2, 4, 5, 2, 4, 5, 1],
    )
    skipped_data = FacetData(skipped;
        person = :person, rater = :rater, item = :item, score = :score)
    skipped_audit = ordinal_response_pattern_audit(skipped_data)
    @test skipped_audit.status === :stress_review_required
    @test skipped_audit.category_scale.levels == (1, 2, 3, 4, 5)
    @test skipped_audit.category_scale.unobserved_interior_categories == (3,)
    @test !skipped_audit.category_scale.unobserved_endpoints_detectable
    @test skipped_audit.overall.category_counts[3] == 0
    @test skipped_audit.decision_policy ===
        :audit_and_stress_axis_not_scientific_pass_fail_threshold

    extreme_person = (
        person = ["P1", "P1", "P1", "P1", "P2", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R2", "R1", "R2", "R1", "R2"],
        item = ["I1", "I1", "I2", "I2", "I1", "I1", "I2", "I2"],
        score = [5, 5, 5, 5, 1, 2, 3, 4],
    )
    extreme_data = FacetData(extreme_person;
        person = :person, rater = :rater, item = :item, score = :score)
    extreme_audit = ordinal_response_pattern_audit(extreme_data)
    @test extreme_audit.flags.extreme_person_levels == ("P1",)
    @test extreme_audit.flags.n_extreme_person_levels == 1
    @test :extreme_person_score_pattern in
        issue_codes(validate_design(extreme_data))

    constant_rater = (
        person = ["P1", "P2", "P3", "P4", "P1", "P2", "P3", "P4"],
        rater = ["R1", "R1", "R1", "R1", "R2", "R2", "R2", "R2"],
        item = ["I1", "I2", "I1", "I2", "I2", "I1", "I2", "I1"],
        score = [1, 1, 1, 1, 2, 3, 4, 5],
    )
    rater_data = FacetData(constant_rater;
        person = :person, rater = :rater, item = :item, score = :score)
    rater_audit = ordinal_response_pattern_audit(rater_data)
    @test rater_audit.flags.constant_rater_levels == ("R1",)
    @test rater_audit.flags.boundary_rater_levels == ("R1",)
    rater_report = validate_design(rater_data)
    @test :constant_rater_score_pattern in issue_codes(rater_report)
    rater_suggestion = only(row for row in validation_suggestions(rater_report)
        if row.code === :constant_rater_score_pattern)
    @test rater_suggestion.action ===
        :inspect_rater_assignment_and_prior_sensitivity

    global_constant = (
        person = ["P1", "P1", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R2"],
        item = ["I1", "I2", "I1", "I2"],
        score = [5, 5, 5, 5],
    )
    global_data = FacetData(global_constant;
        person = :person, rater = :rater, item = :item, score = :score)
    global_audit = ordinal_response_pattern_audit(global_data)
    @test global_audit.status === :structural_error
    @test global_audit.fit_prohibited
    @test global_audit.overall.single_observed_category
    global_codes = issue_codes(validate_design(global_data))
    @test :single_observed_category in global_codes
    @test :extreme_person_score_pattern ∉ global_codes
    @test :constant_rater_score_pattern ∉ global_codes

    @test_throws ArgumentError ordinal_response_pattern_audit(
        skipped_data; minimum_pattern_observations = 0)
end
