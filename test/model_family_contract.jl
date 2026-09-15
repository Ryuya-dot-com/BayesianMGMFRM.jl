using Test
using BayesianMGMFRM

function _model_family_test_data(n_items::Int)
    item_levels = ["I$item" for item in 1:n_items]
    n_rows = 4 * n_items
    return FacetData((;
            person = repeat(["P1", "P2"], inner = 2 * n_items),
            rater = repeat(["R1", "R2"], outer = 2 * n_items),
            item = repeat(repeat(item_levels, inner = 2), outer = 2),
            score = [mod(row - 1, 3) for row in 1:n_rows],
        );
        person = :person,
        rater = :rater,
        item = :item,
        score = :score,
    )
end

@testset "machine-readable model-family contract" begin
    skeleton = model_family_contract()
    @test skeleton.schema ==
        "bayesianmgmfrm.model_family_skeleton.v1"
    @test skeleton.status === :stage_0_contract_implemented
    @test !skeleton.conditional_ability_integral
    @test !skeleton.arbitrary_facet_steps_generated_automatically
    @test length(skeleton.branches) == 10
    @test Set(row.implementation_status for row in skeleton.branches) == Set((
        :stable_supported,
        :guarded_experimental,
        :guarded_experimental_warning_bearing,
        :blocked,
        :density_diagnostics_only_fit_blocked,
        :specified_only,
    ))

    data = _model_family_test_data(4)
    rsm = mfrm_spec(data; thresholds = :rating_scale)
    rsm_contract = model_family_contract(rsm)
    @test rsm_contract.family === :mfrm
    @test rsm_contract.branch === :mfrm_rating_scale
    @test rsm_contract.category.family === :rating_scale_pcm
    @test rsm_contract.dimensionality.classification === :unidimensional
    @test rsm_contract.dimensionality.n_between_items == 0
    @test rsm_contract.steps.owner === :global
    @test rsm_contract.steps.n_step_vectors == 1
    @test rsm_contract.support.implementation_status === :stable_supported
    @test rsm_contract.support.fit_available

    pcm = mfrm_spec(data; thresholds = :partial_credit)
    pcm_contract = model_family_contract(pcm)
    @test pcm_contract.category.family === :partial_credit
    @test pcm_contract.branch === :mfrm_partial_credit
    @test pcm_contract.steps.owner === :item
    @test pcm_contract.steps.n_step_vectors == 4

    gmfrm = mfrm_spec(
        data;
        family = :gmfrm,
        thresholds = :partial_credit,
        discrimination = :rater,
    )
    gmfrm_contract = model_family_contract(gmfrm)
    @test gmfrm_contract.category.family === :generalized_partial_credit
    @test gmfrm_contract.branch === :gmfrm_rater_step_gpcm
    @test gmfrm_contract.category.source_scale_constant == 1.0
    @test gmfrm_contract.category.implementation_scale_constant == 1.0
    @test isnothing(gmfrm_contract.category.
        normal_ogive_minimax_reference_constant)
    @test gmfrm_contract.category.source_scale_contract ===
        :uto_and_ueno_2020_equation_9_has_no_1_7
    @test gmfrm_contract.category.cross_family_scale_comparison ===
        :requires_explicit_harmonization
    @test gmfrm_contract.steps.owner === :rater
    @test gmfrm_contract.steps.n_step_vectors == 2
    @test gmfrm_contract.support.implementation_status ===
        :guarded_experimental

    between_q = Bool[
        1 0
        0 1
        1 0
        0 1
    ]
    between = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = between_q,
    )
    between_contract = model_family_contract(between)
    @test between_contract.category.family ===
        :multidimensional_generalized_partial_credit
    @test between_contract.branch === :mgmfrm_fixed_q_between_item_gpcm
    @test between_contract.category.source_scale_constant == 1.7
    @test between_contract.category.implementation_scale_constant == 1.7
    @test between_contract.category.normal_ogive_minimax_reference_constant ==
        1.702
    @test between_contract.category.scale_precision_policy ===
        :implement_published_1_7_literal_not_1_702_reference
    @test between_contract.category.source_literal_matches_implementation
    @test between_contract.category.cross_family_scale_comparison ===
        :requires_explicit_harmonization
    @test between_contract.dimensionality.classification === :between_item
    @test between_contract.dimensionality.active_dimensions_per_item ==
        (1, 1, 1, 1)
    @test between_contract.dimensionality.n_between_items == 4
    @test between_contract.dimensionality.n_within_items == 0
    @test between_contract.dimensionality.source_classification ===
        :non_compensatory_per_uto_2021
    @test between_contract.dimensionality.algebraic_aggregation ===
        :additive_weighted_sum
    @test !between_contract.dimensionality.conditional_ability_integral
    @test between_contract.dimensionality.current_loading_policy ===
        :fixed_q_positive_masked
    @test between_contract.dimensionality.source_loading_surface ===
        :unrestricted_item_dimension_discrimination_in_uto_2021
    @test between_contract.steps.owner === :item
    @test between_contract.steps.n_step_vectors == 4
    @test between_contract.latent.correlation === :identity_fixed
    @test between_contract.support.implementation_status ===
        :guarded_experimental
    @test !between_contract.support.warning_bearing
    @test isempty(between_contract.support.warning_checks)
    @test model_family_contract(getdesign(between; preview = true)) ==
        between_contract

    mixed_q = Bool[
        1 0
        0 1
        1 1
        1 0
    ]
    mixed = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = mixed_q,
    )
    mixed_contract = model_family_contract(mixed)
    @test mixed_contract.dimensionality.classification ===
        :mixed_between_and_within_item
    @test mixed_contract.branch ===
        :mgmfrm_fixed_q_within_or_mixed_gpcm
    @test mixed_contract.dimensionality.n_between_items == 3
    @test mixed_contract.dimensionality.n_within_items == 1
    @test mixed_contract.dimensionality.item_rows[3].item_structure ===
        :within_item
    @test mixed_contract.dimensionality.item_rows[3].active_dimensions ==
        (1, 2)
    @test mixed_contract.support.implementation_status ===
        :guarded_experimental_warning_bearing
    @test mixed_contract.support.warning_bearing
    @test :cross_loading_policy in mixed_contract.support.warning_checks

    within_data = _model_family_test_data(3)
    within = mfrm_spec(
        within_data;
        family = :mgmfrm,
        dimensions = 3,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = Bool[
            1 1 0
            0 1 1
            1 0 1
        ],
    )
    within_contract = model_family_contract(within)
    @test within_contract.dimensionality.classification === :within_item
    @test within_contract.branch ===
        :mgmfrm_fixed_q_within_or_mixed_gpcm
    @test within_contract.dimensionality.n_between_items == 0
    @test within_contract.dimensionality.n_within_items == 3
    @test within_contract.identification.q_validation_status ===
        :guarded_generic_fixed_q_review_required
    @test !within_contract.identification.
        q_conservative_stable_structure_ready
    @test :positive_loading_identification in
        within_contract.support.warning_checks

    invalid_q = mfrm_spec(
        data;
        family = :mgmfrm,
        dimensions = 2,
        thresholds = :partial_credit,
        discrimination = :none,
        q_matrix = copy(between_q),
    )
    invalid_q.q_matrix[1, :] .= false
    invalid_q_contract = model_family_contract(invalid_q)
    @test invalid_q_contract.dimensionality.classification ===
        :invalid_unassigned_item_rows
    @test invalid_q_contract.branch === :mgmfrm_invalid_fixed_q
    @test invalid_q_contract.dimensionality.n_unassigned_items == 1
    @test invalid_q_contract.identification.q_validation_status ===
        :rejected_fixed_q_structure
    @test invalid_q_contract.support.implementation_status === :specified_only
    @test !invalid_q_contract.support.fit_available
end

@testset "MGMFRM item-conditional compensation (no fitting)" begin
    spec = mfrm_spec(_model_family_test_data(4);
        family = :mgmfrm, dimensions = 2, thresholds = :partial_credit,
        discrimination = :none, q_matrix = Bool[1 0; 0 1; 1 1; 1 0])
    target = BayesianMGMFRM._mgmfrm_guarded_local_fit_logdensity(spec)
    design = target.design
    data = design.spec.data
    params = BayesianMGMFRM._guarded_generalized_direct_params(
        target, initial_params(target))
    loadings = BayesianMGMFRM._mgmfrm_source_loading_index_matrix(design)
    person = design.blocks[:person][1:2]
    params[person] .= (0.0, 2.0)
    params[loadings[3, 1]] = 2.0
    params[design.blocks[:item][3]] = 0.4
    params[design.blocks[:rater]] .= (0.2, -0.2)
    params[design.blocks[:rater_consistency]] .= (1.5, 1 / 1.5)
    params[design.blocks[:item_steps][3]] = 0.3
    row_for(item, rater) = only(findall(row ->
        data.person[row] == 1 && data.item[row] == item &&
        data.rater[row] == rater, 1:data.n))
    probabilities(p, row) = BayesianMGMFRM._mgmfrm_category_probabilities!(
        zeros(3), design, loadings, p, row)

    for rater in 1:2
        row = row_for(3, rater)
        actual = probabilities(params, row)
        # Uto Eq. 6 / Appendix 1, after subtracting the common first logit.
        location = 2.0 - 0.4 - params[design.blocks[:rater][rater]]
        scale = 1.7 * params[design.blocks[:rater_consistency][rater]]
        expected = exp.(scale .* ((0:2) .* location .- [0.0, 0.3, 0.0]))
        @test actual ≈ expected ./ sum(expected) rtol = 1e-12
        @test sum(actual) ≈ 1.0
        for shift in (-0.5, 1.0, 2.0)
            compensated = copy(params)
            compensated[person] .= (shift, 2.0 - 2shift)
            @test probabilities(compensated, row) ≈ actual rtol = 1e-12
        end
    end

    # Same weighted sum on I3 does not imply invariance of other items/prior.
    compensated = copy(params)
    compensated[person] .= (1.0, 0.0)
    for item in 1:2
        row = row_for(item, 1)
        @test !isapprox(probabilities(compensated, row), probabilities(params, row))
    end
    inactive_change = copy(params)
    inactive_change[person[2]] = -2.0
    @test probabilities(inactive_change, row_for(1, 1)) ≈
        probabilities(params, row_for(1, 1))
    inactive_change[person[1]] = 20.0
    @test probabilities(inactive_change, row_for(3, 1))[end] > 1 - 1e-8
end
