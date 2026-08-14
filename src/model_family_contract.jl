function _model_family_branch_row(;
        branch::Symbol,
        family::Symbol,
        dimensionality::Symbol,
        category_kernel::Symbol,
        loading_policy::Symbol,
        step_owner::Symbol,
        implementation_status::Symbol,
        fit_available::Bool,
        entrypoint,
        claim_scope::Symbol)
    return (;
        branch,
        family,
        dimensionality,
        category_kernel,
        loading_policy,
        step_owner,
        implementation_status,
        fit_available,
        entrypoint,
        claim_scope,
    )
end

function _model_family_branch_rows()
    experimental_entrypoint =
        "BayesianMGMFRM.Experimental.fit(spec)"
    return (
        _model_family_branch_row(;
            branch = :mfrm_rating_scale,
            family = :mfrm,
            dimensionality = :unidimensional,
            category_kernel = :rating_scale_pcm,
            loading_policy = :unit_discrimination,
            step_owner = :global,
            implementation_status = :stable_supported,
            fit_available = true,
            entrypoint = "BayesianMGMFRM.fit(spec)",
            claim_scope = :minimal_mfrm_rsm,
        ),
        _model_family_branch_row(;
            branch = :mfrm_partial_credit,
            family = :mfrm,
            dimensionality = :unidimensional,
            category_kernel = :partial_credit,
            loading_policy = :unit_discrimination,
            step_owner = :item,
            implementation_status = :stable_supported,
            fit_available = true,
            entrypoint = "BayesianMGMFRM.fit(spec)",
            claim_scope = :minimal_mfrm_pcm,
        ),
        _model_family_branch_row(;
            branch = :gmfrm_rater_step_gpcm,
            family = :gmfrm,
            dimensionality = :unidimensional,
            category_kernel = :generalized_partial_credit,
            loading_policy = :item_discrimination_times_rater_consistency,
            step_owner = :rater,
            implementation_status = :guarded_experimental,
            fit_available = true,
            entrypoint = experimental_entrypoint,
            claim_scope = :scalar_rater_consistency_only,
        ),
        _model_family_branch_row(;
            branch = :mgmfrm_fixed_q_between_item_gpcm,
            family = :mgmfrm,
            dimensionality = :between_item,
            category_kernel = :multidimensional_generalized_partial_credit,
            loading_policy = :fixed_q_positive_item_dimension_discrimination,
            step_owner = :item,
            implementation_status = :guarded_experimental,
            fit_available = true,
            entrypoint = experimental_entrypoint,
            claim_scope = :fixed_q_confirmatory_only,
        ),
        _model_family_branch_row(;
            branch = :mgmfrm_fixed_q_within_or_mixed_gpcm,
            family = :mgmfrm,
            dimensionality = :within_or_mixed_item,
            category_kernel = :multidimensional_generalized_partial_credit,
            loading_policy = :fixed_q_positive_confirmatory_cross_loading,
            step_owner = :item,
            implementation_status = :guarded_experimental_warning_bearing,
            fit_available = true,
            entrypoint = experimental_entrypoint,
            claim_scope = :validated_fixed_q_only,
        ),
        _model_family_branch_row(;
            branch = :mgmfrm_unrestricted_uto_loading_surface,
            family = :mgmfrm,
            dimensionality = :within_item_capable,
            category_kernel = :multidimensional_generalized_partial_credit,
            loading_policy = :unrestricted_item_dimension_discrimination,
            step_owner = :item,
            implementation_status = :blocked,
            fit_available = false,
            entrypoint = nothing,
            claim_scope = :source_target_not_current_fit,
        ),
        _model_family_branch_row(;
            branch = :mgmfrm_nonadditive_dimension_aggregation,
            family = :mgmfrm,
            dimensionality = :multidimensional,
            category_kernel = :unspecified_nonadditive_polytomous,
            loading_policy = :conjunctive_product_minimum_or_other,
            step_owner = :unspecified,
            implementation_status = :blocked,
            fit_available = false,
            entrypoint = nothing,
            claim_scope = :not_implemented,
        ),
        _model_family_branch_row(;
            branch = :arbitrary_facet_specific_steps,
            family = :generalized,
            dimensionality = :family_dependent,
            category_kernel = :family_dependent,
            loading_policy = :family_dependent,
            step_owner = :arbitrary_facet,
            implementation_status = :blocked,
            fit_available = false,
            entrypoint = nothing,
            claim_scope = :requires_new_likelihood_identification_and_prior,
        ),
        _model_family_branch_row(;
            branch = :mgmfrm_free_latent_correlation_fit,
            family = :mgmfrm,
            dimensionality = :multidimensional,
            category_kernel = :multidimensional_generalized_partial_credit,
            loading_policy = :fixed_q_joint_loading_correlation_gauge_required,
            step_owner = :item,
            implementation_status = :density_diagnostics_only_fit_blocked,
            fit_available = false,
            entrypoint = nothing,
            claim_scope = :not_current_fit,
        ),
    )
end

"""
    model_family_contract()
    model_family_contract(spec_or_design)

Return the Stage-0 machine-readable MGMFRM-family skeleton, or the exact branch
contract implied by a [`FacetSpec`](@ref) or [`FacetDesign`](@ref).

The contract keeps the source's multidimensional classification separate from
the algebraic dimension aggregator, distinguishes between-item, within-item,
and mixed fixed-Q structures, names the PCM/GPCM-form category kernel and step
owner, and records whether each branch is stable, guarded, specified-only, or
blocked. It describes implementation scope; it does not fit a model, validate
scientific performance, or promote an experimental branch.
"""
function model_family_contract()
    return (;
        schema = "bayesianmgmfrm.model_family_skeleton.v1",
        object = :model_family_skeleton,
        status = :stage_0_contract_implemented,
        axes = (
            :category_kernel,
            :dimensionality,
            :dimension_aggregation,
            :loading_policy,
            :latent_correlation,
            :step_owner,
            :facet_roles,
            :identification,
            :implementation_status,
        ),
        source_classification_policy =
            :record_separately_from_algebraic_aggregation,
        conditional_ability_integral = false,
        arbitrary_facet_steps_generated_automatically = false,
        branches = _model_family_branch_rows(),
    )
end

function _model_family_item_structure(spec::FacetSpec)
    spec.family === :mgmfrm || return (;
        classification = :unidimensional,
        active_dimensions_per_item = (),
        n_between_items = 0,
        n_within_items = 0,
        n_unassigned_items = 0,
        item_rows = (),
    )
    q = spec.q_matrix
    q === nothing && return (;
        classification = :fixed_q_missing,
        active_dimensions_per_item = (),
        n_between_items = 0,
        n_within_items = 0,
        n_unassigned_items = length(spec.data.item_levels),
        item_rows = (),
    )
    active = Tuple(count(@view q[item, :]) for item in axes(q, 1))
    n_between = count(==(1), active)
    n_within = count(>(1), active)
    n_unassigned = count(==(0), active)
    classification = n_unassigned > 0 ? :invalid_unassigned_item_rows :
        n_within == 0 ? :between_item :
        n_between == 0 ? :within_item : :mixed_between_and_within_item
    rows = Tuple((;
            item_index = item,
            item_label = spec.data.item_levels[item],
            active_dimensions = Tuple(findall(@view q[item, :])),
            n_active_dimensions = active[item],
            item_structure = active[item] == 0 ? :unassigned_item :
                active[item] == 1 ? :between_item : :within_item,
        ) for item in axes(q, 1))
    return (;
        classification,
        active_dimensions_per_item = active,
        n_between_items = n_between,
        n_within_items = n_within,
        n_unassigned_items = n_unassigned,
        item_rows = rows,
    )
end

function _model_family_category_contract(spec::FacetSpec)
    family = spec.family
    kernel = if family === :mfrm
        spec.thresholds === :rating_scale ?
            :rating_scale_pcm : :partial_credit
    elseif family === :gmfrm
        :generalized_partial_credit
    else
        :multidimensional_generalized_partial_credit
    end
    source_scale = family === :mgmfrm ? 1.7 : 1.0
    normal_ogive_reference = family === :mgmfrm ? 1.702 : nothing
    return (;
        family = kernel,
        probability_form = :adjacent_category_cumulative_softmax,
        threshold_regime = spec.thresholds,
        n_categories = length(spec.data.category_levels),
        source_scale_constant = source_scale,
        implementation_scale_constant = source_scale,
        normal_ogive_minimax_reference_constant = normal_ogive_reference,
        source_scale_contract = family === :mgmfrm ?
            :uto_2021_equation_6_uses_1_7 :
            family === :gmfrm ?
                :uto_and_ueno_2020_equation_9_has_no_1_7 :
                :unit_rasch_scale,
        scale_precision_policy = family === :mgmfrm ?
            :implement_published_1_7_literal_not_1_702_reference :
            :not_applicable,
        source_literal_matches_implementation = true,
        cross_family_scale_comparison = family in (:gmfrm, :mgmfrm) ?
            :requires_explicit_harmonization : :reference_unit_scale,
        generalized_discrimination = family in (:gmfrm, :mgmfrm),
    )
end

function _model_family_step_contract(spec::FacetSpec)
    family = spec.family
    n_categories = length(spec.data.category_levels)
    if family === :mfrm && spec.thresholds === :rating_scale
        owner = :global
        sharing = :shared_across_items_raters_and_persons
        n_vectors = 1
        constraint = :sum_to_zero
    elseif family === :mfrm
        owner = :item
        sharing = :item_specific_shared_across_raters_and_persons
        n_vectors = length(spec.data.item_levels)
        constraint = :sum_to_zero_within_item
    elseif family === :gmfrm
        owner = :rater
        sharing = :rater_specific_shared_across_items_and_persons
        n_vectors = length(spec.data.rater_levels)
        constraint = :first_step_zero_remaining_steps_sum_to_zero
    else
        owner = :item
        sharing = :item_specific_shared_across_raters_dimensions_and_persons
        n_vectors = length(spec.data.item_levels)
        constraint = :first_step_zero_remaining_steps_sum_to_zero
    end
    return (;
        owner,
        sharing,
        n_step_vectors = n_vectors,
        n_free_coordinates_per_vector = max(n_categories - 2, 0),
        constraint,
        arbitrary_facet_specific_supported = false,
        nested_or_crossed_supported = false,
        partially_pooled_supported = false,
    )
end

function _model_family_support_contract(spec::FacetSpec,
        equation,
        q_validation)
    stable = spec.estimation_status === :fit_supported
    experimental = equation.experimental_fit_available
    warning_checks = q_validation === nothing ? () :
        Tuple(row.check for row in q_validation.rows
            if row.severity === :warning)
    warning_bearing = experimental && !isempty(warning_checks)
    status = stable ? :stable_supported :
        warning_bearing ? :guarded_experimental_warning_bearing :
        experimental ? :guarded_experimental : :specified_only
    entrypoint = stable ? "BayesianMGMFRM.fit(spec)" :
        experimental ? "BayesianMGMFRM.Experimental.fit(spec)" : nothing
    return (;
        implementation_status = status,
        representation_available = true,
        fit_available = stable || experimental,
        stable_fit_available = stable,
        experimental_fit_available = experimental,
        warning_bearing,
        warning_checks,
        entrypoint,
        broad_family_fit_available = false,
        scientific_validation_implied = false,
    )
end

function _model_family_exact_branch(spec::FacetSpec, item_structure)
    spec.family === :mfrm && return spec.thresholds === :rating_scale ?
        :mfrm_rating_scale : :mfrm_partial_credit
    spec.family === :gmfrm && return :gmfrm_rater_step_gpcm
    item_structure.classification === :between_item &&
        return :mgmfrm_fixed_q_between_item_gpcm
    item_structure.classification in
        (:within_item, :mixed_between_and_within_item) &&
        return :mgmfrm_fixed_q_within_or_mixed_gpcm
    return :mgmfrm_invalid_fixed_q
end

function model_family_contract(spec::FacetSpec)
    equation = model_equation(spec)
    item_structure = _model_family_item_structure(spec)
    family = spec.family
    q_validation = family === :mgmfrm ? q_matrix_validation(spec) : nothing
    q_identification = q_validation === nothing ? nothing :
        q_validation.identification
    dimensionality = (;
        n_dimensions = spec.dimensions,
        item_structure...,
        source_classification = family === :mgmfrm ?
            :non_compensatory_per_uto_2021 : :not_applicable,
        algebraic_aggregation = family === :mgmfrm ?
            :additive_weighted_sum : :single_dimension,
        operational_compensation_status = family === :mgmfrm ?
            :not_adjudicated : :not_applicable,
        conditional_ability_integral = false,
        ability_representation = :explicit_person_posterior_parameters,
        current_loading_policy = family === :mgmfrm ?
            :fixed_q_positive_masked :
            family === :gmfrm ?
                :item_discrimination_times_rater_consistency :
                :unit_discrimination,
        source_loading_surface = family === :mgmfrm ?
            :unrestricted_item_dimension_discrimination_in_uto_2021 :
            :not_applicable,
        nonadditive_aggregator_supported = false,
    )
    latent_correlation = family === :mgmfrm ? :identity_fixed : :not_applicable
    return (;
        schema = "bayesianmgmfrm.model_family_contract.v1",
        object = :model_family_contract,
        branch = _model_family_exact_branch(spec, item_structure),
        family,
        scope = equation.scope,
        category = _model_family_category_contract(spec),
        dimensionality,
        steps = _model_family_step_contract(spec),
        facets = (;
            fitted = (:person, :item, :rater),
            person_role = :latent_ability,
            item_role = :difficulty_and_declared_discrimination_or_steps,
            rater_role = :severity_and_declared_consistency_or_steps,
            additional_columns = :validation_or_reporting_metadata_only,
            arbitrary_fitted_facets_supported = false,
        ),
        latent = (;
            correlation = latent_correlation,
            free_correlation_fit_available = false,
        ),
        identification = (;
            equation = equation.identification,
            q_validation_status = q_validation === nothing ?
                :not_applicable : q_identification === nothing ?
                    :unavailable : q_identification.status,
            q_conservative_stable_structure_ready = q_identification === nothing ?
                nothing : q_identification.
                    conservative_stable_structure_ready,
        ),
        support = _model_family_support_contract(
            spec,
            equation,
            q_validation,
        ),
    )
end

model_family_contract(design::FacetDesign) =
    model_family_contract(design.spec)
