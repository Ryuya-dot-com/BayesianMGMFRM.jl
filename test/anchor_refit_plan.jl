using Test
using BayesianMGMFRM

@testset "anchor-constrained refit preflight plan" begin
    table = (;
        person = ["P1", "P1", "P1", "P2", "P2", "P2"],
        rater = ["R1", "R2", "R1", "R1", "R2", "R1"],
        item = ["I1", "I1", "I2", "I1", "I2", "I2"],
        score = [0, 1, 2, 1, 0, 2],
    )
    data = FacetData(table;
        person = :person,
        rater = :rater,
        item = :item,
        score = :score)

    anchor = (;
        block = :rater,
        level = "R2",
        value = 0.25,
        type = :hard,
        source = :facets,
        source_version = "2026-07",
        source_model = :mfrm_pcm,
        source_estimator = :jml,
        source_hash = repeat("0123456789abcdef", 4),
        source_scale = :logit,
        sign = :severity_positive,
    )
    spec = mfrm_spec(data; anchors = [anchor])
    plan = anchor_refit_plan(spec)
    @test plan.schema == "bayesianmgmfrm.anchor_refit_plan.v1"
    @test plan.status === :hard_anchor_candidate_ready
    @test plan.candidate_supported
    @test !plan.numerical_refit_implemented
    @test plan.estimation_status === :specified_only
    @test plan.hard_anchor_contract.coordinate_strategy ===
        :affine_direct_parameter_map
    @test plan.hard_anchor_contract.identification_policy ===
        :replace_reference_gauge_not_stack_constraints
    @test !plan.hard_anchor_contract.prior_scale_declaration_allowed
    @test plan.provenance_contract.source_scale_semantics ===
        :normalized_anchor_value_destination_scale
    @test plan.provenance_contract.sign_semantics ===
        :normalized_anchor_value_destination_orientation
    @test plan.provenance_contract.source_hash_check ===
        :lowercase_sha256_format_only
    @test !plan.provenance_contract.source_bytes_verified
    row = only(plan.anchor_rows)
    @test row.canonical_block === :rater
    @test row.target == "R2"
    @test row.target_found
    @test row.value == 0.25
    @test row.normalized_value === 0.25
    @test row.value_issue === nothing
    @test row.provenance_complete
    @test isempty(row.invalid_provenance_fields)
    @test isempty(row.provenance_issues)
    @test row.source_hash_format_valid
    @test !row.source_bytes_verified
    @test row.status === :candidate_supported

    no_provenance_spec = mfrm_spec(data; anchors = [(;
        block = :item,
        level = "I1",
        value = 0.0,
        type = :hard,
    )])
    strict = anchor_refit_plan(no_provenance_spec)
    @test !strict.candidate_supported
    @test :anchor_provenance_incomplete in only(strict.anchor_rows).issues
    relaxed = anchor_refit_plan(no_provenance_spec;
        require_provenance = false)
    @test relaxed.candidate_supported
    @test !only(relaxed.anchor_rows).provenance_complete

    @testset "fail-closed provenance fields" begin
        invalid_cases = (
            (field = :source, override = (; source = nothing),
                issue = :source_must_be_machine_identifier),
            (field = :source, override = (; source = "FACETS export"),
                issue = :source_must_be_machine_identifier),
            (field = :source_version, override = (; source_version = ""),
                issue = :source_version_must_be_nonempty_printable_string),
            (field = :source_model, override = (; source_model = "mfrm_pcm"),
                issue = :source_model_not_supported),
            (field = :source_estimator,
                override = (; source_estimator = :unknown),
                issue = :source_estimator_not_supported),
            (field = :source_hash, override = (; source_hash = 42),
                issue = :source_hash_must_be_lowercase_sha256),
            (field = :source_scale, override = (; source_scale = :raw_score),
                issue = :source_scale_not_supported),
            (field = :sign, override = (; sign = :leniency_positive),
                issue = :sign_not_supported),
            (field = :sign, override = (; sign = :difficulty_positive),
                issue = :sign_incompatible_with_anchor_block),
        )
        for case in invalid_cases
            invalid_spec = mfrm_spec(data; anchors = [merge(anchor, case.override)])
            invalid_plan = anchor_refit_plan(invalid_spec)
            invalid_row = only(invalid_plan.anchor_rows)
            @test !invalid_plan.candidate_supported
            @test invalid_plan.status === :preflight_failed
            @test :anchor_provenance_invalid in invalid_row.issues
            @test case.field in invalid_row.invalid_provenance_fields
            @test case.issue in invalid_row.provenance_issues
            case.field === :source_hash &&
                @test !invalid_row.source_hash_format_valid
        end

        wrong_regime_spec = mfrm_spec(data; anchors = [merge(anchor, (;
            source_model = :mfrm_rsm,
        ))])
        wrong_regime_row = only(anchor_refit_plan(wrong_regime_spec).anchor_rows)
        @test :source_model in wrong_regime_row.invalid_provenance_fields
        @test :source_model_threshold_regime_mismatch in
            wrong_regime_row.provenance_issues

        relaxed_invalid = anchor_refit_plan(
            mfrm_spec(data; anchors = [merge(anchor, (; source = nothing))]);
            require_provenance = false,
        )
        @test !relaxed_invalid.candidate_supported
        @test :anchor_provenance_invalid in
            only(relaxed_invalid.anchor_rows).issues
    end

    @testset "fail-closed anchor values" begin
        boolean_plan = anchor_refit_plan(mfrm_spec(data; anchors = [
            merge(anchor, (; value = true)),
        ]))
        boolean_row = only(boolean_plan.anchor_rows)
        @test !boolean_plan.candidate_supported
        @test !boolean_row.value_valid
        @test ismissing(boolean_row.normalized_value)
        @test boolean_row.value_issue === :anchor_value_boolean_not_allowed
        @test :anchor_value_boolean_not_allowed in boolean_row.issues

        huge = parse(BigFloat, "1e10000")
        @test isfinite(huge)
        huge_plan = anchor_refit_plan(mfrm_spec(data; anchors = [
            merge(anchor, (; value = huge)),
        ]))
        huge_row = only(huge_plan.anchor_rows)
        @test !huge_plan.candidate_supported
        @test !huge_row.value_valid
        @test ismissing(huge_row.normalized_value)
        @test huge_row.value_issue ===
            :anchor_value_not_float64_representable
        @test :anchor_value_not_float64_representable in huge_row.issues
    end

    @testset "hard/soft scale and reference-gauge boundaries" begin
        for scale_override in (
                (; scale = 0.2),
                (; sd = 0.2),
                (; prior_scale = 0.2))
            ambiguous_plan = anchor_refit_plan(mfrm_spec(data; anchors = [
                merge(anchor, scale_override),
            ]))
            ambiguous_row = only(ambiguous_plan.anchor_rows)
            @test !ambiguous_plan.candidate_supported
            @test ambiguous_row.anchor_type === :hard_anchor
            @test ambiguous_row.scale == 0.2
            @test !ambiguous_row.scale_valid
            @test :hard_anchor_must_not_declare_prior_scale in
                ambiguous_row.issues
        end
    end

    missing_target = mfrm_spec(data; anchors = [(;
        block = :item,
        value = 0.0,
        type = :hard,
    )])
    @test :explicit_target_required in
        only(anchor_refit_plan(missing_target).anchor_rows).issues

    conflicting = mfrm_spec(data; anchors = [
        merge(anchor, (; value = 0.0)),
        merge(anchor, (; value = 0.5)),
    ])
    conflict_plan = anchor_refit_plan(conflicting)
    @test !conflict_plan.candidate_supported
    @test all(row -> row.duplicate_target && row.conflicting_value,
        conflict_plan.anchor_rows)
    @test all(row -> :conflicting_anchor_values in row.issues,
        conflict_plan.anchor_rows)

    soft = mfrm_spec(data; anchors = [(;
        block = :rater,
        level = "R2",
        value = 0.0,
        type = :soft,
        scale = 0.2,
        source = :facets,
        source_version = "2026-07",
        source_model = :mfrm_pcm,
        source_estimator = :jml,
        source_hash = repeat("0123456789abcdef", 4),
        source_scale = :logit,
        sign = :severity_positive,
    )])
    soft_plan = anchor_refit_plan(soft)
    @test !soft_plan.candidate_supported
    @test soft_plan.n_soft_anchors == 1
    @test only(soft_plan.anchor_rows).status === :deferred_soft_anchor
    @test only(soft_plan.anchor_rows).scale_valid
    @test only(soft_plan.anchor_rows).normalized_scale === 0.2
    @test soft_plan.soft_anchor_contract.status === :deferred
    @test soft_plan.soft_anchor_contract.current_reference_level_policy ===
        :reject_until_reparameterized_or_source_contrast_transformed

    reference_soft = mfrm_spec(data; anchors = [merge(only(soft.anchors), (;
        level = "R1",
    ))])
    reference_soft_plan = anchor_refit_plan(reference_soft)
    reference_soft_row = only(reference_soft_plan.anchor_rows)
    @test !reference_soft_plan.candidate_supported
    @test reference_soft_row.status === :preflight_failed
    @test :soft_anchor_on_reference_level_requires_reparameterization in
        reference_soft_row.issues

    huge_soft_scale = parse(BigFloat, "1e10000")
    @test isfinite(huge_soft_scale)
    huge_scale_soft = mfrm_spec(data; anchors = [(;
        block = :rater,
        level = "R2",
        value = 0.0,
        type = :soft,
        scale = huge_soft_scale,
        source = :facets,
        source_version = "2026-07",
        source_model = :mfrm_pcm,
        source_estimator = :jml,
        source_hash = repeat("0123456789abcdef", 4),
        source_scale = :logit,
        sign = :severity_positive,
    )])
    huge_scale_plan = anchor_refit_plan(huge_scale_soft)
    huge_scale_row = only(huge_scale_plan.anchor_rows)
    @test !huge_scale_plan.candidate_supported
    @test !huge_scale_row.scale_valid
    @test ismissing(huge_scale_row.normalized_scale)
    @test huge_scale_row.scale_issue ===
        :soft_anchor_scale_not_float64_representable
    @test :soft_anchor_scale_not_float64_representable in
        huge_scale_row.issues

    boolean_scale_soft = mfrm_spec(data; anchors = [(;
        block = :rater,
        level = "R2",
        value = 0.0,
        type = :soft,
        scale = true,
        source = :facets,
        source_version = "2026-07",
        source_model = :mfrm_pcm,
        source_estimator = :jml,
        source_hash = repeat("0123456789abcdef", 4),
        source_scale = :logit,
        sign = :severity_positive,
    )])
    boolean_scale_row = only(anchor_refit_plan(boolean_scale_soft).anchor_rows)
    @test !boolean_scale_row.scale_valid
    @test boolean_scale_row.scale_issue ===
        :soft_anchor_scale_boolean_not_allowed

    empty_plan = anchor_refit_plan(mfrm_spec(data))
    @test empty_plan.status === :no_anchors_declared
    @test empty_plan.next_gate === :resolve_anchor_refit_preflight
end
