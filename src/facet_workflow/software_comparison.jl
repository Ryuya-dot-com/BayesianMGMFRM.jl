function _related_software_source_rows()
    return (
        (;
            tool = :facets,
            source_kind = :official_product_documentation,
            url = "https://www.winsteps.com/facets.htm",
            role = :many_facet_rasch_measurement,
        ),
        (;
            tool = :facets,
            source_kind = :official_theory_documentation,
            url = "https://www.winsteps.com/facetman/theory.htm",
            role = :many_facet_model_theory,
        ),
        (;
            tool = :tam,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/TAM/refman/TAM.html",
            role = :irt_mfrm_multidimensional_models,
        ),
        (;
            tool = :mirt,
            source_kind = :journal_article,
            url = "https://www.jstatsoft.org/article/view/v048i06",
            role = :exploratory_and_confirmatory_mirt,
        ),
        (;
            tool = :sirt,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/sirt/sirt.pdf",
            role = :supplementary_irt_models_and_rater_effects,
        ),
        (;
            tool = :immer,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/immer/immer.pdf",
            role = :item_response_models_for_multiple_ratings,
        ),
        (;
            tool = :brms_stan,
            source_kind = :official_cran_reference,
            url = "https://cran.r-project.org/web/packages/brms/brms.pdf",
            role = :bayesian_multilevel_models_via_stan,
        ),
        (;
            tool = :stan,
            source_kind = :official_user_guide,
            url = "https://mc-stan.org/docs/stan-users-guide/item-response-models.html",
            role = :custom_bayesian_irt_modeling,
        ),
        (;
            tool = :bayesianmgmfrm,
            source_kind = :package_manifest,
            url = "local://BayesianMGMFRM.jl/release_scope_summary",
            role = :source_audited_bayesian_mgmfrm_workflow,
        ),
    )
end

function _related_software_row(; tool::Symbol,
        display_name::AbstractString,
        ecosystem::Symbol,
        current_role::Symbol,
        model_coverage,
        estimation_methods,
        rater_facet_support::Symbol,
        multidimensional_support::Symbol,
        bayesian_support::Symbol,
        diagnostics_and_sensitivity,
        report_artifact_support::Symbol,
        bayesianmgmfrm_overlap,
        v0_1_1_position::Symbol,
        comparison_gate::Symbol,
        source_urls)
    return (;
        schema = "bayesianmgmfrm.related_software_capability_row.v1",
        tool,
        display_name = String(display_name),
        ecosystem,
        current_role,
        model_coverage = Tuple(Symbol(item) for item in model_coverage),
        estimation_methods = Tuple(Symbol(item) for item in estimation_methods),
        rater_facet_support,
        multidimensional_support,
        bayesian_support,
        diagnostics_and_sensitivity =
            Tuple(Symbol(item) for item in diagnostics_and_sensitivity),
        report_artifact_support,
        bayesianmgmfrm_overlap =
            Tuple(Symbol(item) for item in bayesianmgmfrm_overlap),
        v0_1_1_position,
        comparison_gate,
        source_urls = Tuple(String(url) for url in source_urls),
    )
end

function _related_software_capability_rows()
    return (
        _related_software_row(
            tool = :facets,
            display_name = "Facets",
            ecosystem = :standalone_rasch,
            current_role = :mature_many_facet_rasch_measurement,
            model_coverage = (:unidimensional_mfrm, :ordinal_rasch,
                :many_facet_rating_designs),
            estimation_methods = (:rasch_measurement_workflow,),
            rater_facet_support = :first_class_many_facet_rater_support,
            multidimensional_support = :not_the_primary_public_claim,
            bayesian_support = :not_a_bayesian_workflow,
            diagnostics_and_sensitivity = (:fit_statistics, :facet_maps,
                :separation_reliability, :practitioner_tables),
            report_artifact_support = :interactive_and_report_oriented_outputs,
            bayesianmgmfrm_overlap = (:mfrm_practitioner_outputs,
                :facet_maps, :fit_statistics),
            v0_1_1_position = :migration_reference_not_replacement_claim,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://www.winsteps.com/facets.htm",
                "https://www.winsteps.com/facetman/theory.htm",
            )),
        _related_software_row(
            tool = :tam,
            display_name = "TAM",
            ecosystem = :r_package,
            current_role = :broad_irt_and_mfr_modeling,
            model_coverage = (:rasch, :pcm, :gpcm, :multidimensional_irt,
                :multi_faceted_rasch_models),
            estimation_methods = (:marginal_maximum_likelihood,
                :joint_maximum_likelihood, :expected_a_posteriori),
            rater_facet_support = :multi_faceted_rasch_available,
            multidimensional_support = :broad_multidimensional_irt_available,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:irt_model_tables,
                :fit_and_item_diagnostics, :plausible_values),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:mfrm_pcm_gpcm_overlap,
                :fixed_q_multidimensional_overlap_candidates),
            v0_1_1_position = :breadth_baseline_not_feature_checklist,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/TAM/refman/TAM.html",)),
        _related_software_row(
            tool = :mirt,
            display_name = "mirt",
            ecosystem = :r_package,
            current_role = :exploratory_and_confirmatory_mirt,
            model_coverage = (:unidimensional_irt, :multidimensional_irt,
                :exploratory_mirt, :confirmatory_mirt),
            estimation_methods = (:em, :mhrm, :multiple_group_estimation),
            rater_facet_support = :not_a_dedicated_mfrm_facets_workflow,
            multidimensional_support = :first_class_mirt_support,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:item_fit, :model_fit,
                :technical_mirt_outputs),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:fixed_q_mirt_expectations,
                :dimension_loading_interpretation),
            v0_1_1_position = :multidimensional_baseline_not_mfr_replacement,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://www.jstatsoft.org/article/view/v048i06",)),
        _related_software_row(
            tool = :sirt,
            display_name = "sirt",
            ecosystem = :r_package,
            current_role = :supplementary_irt_methods,
            model_coverage = (:rasch_extensions, :differential_item_functioning,
                :rater_effects, :diagnostic_models),
            estimation_methods = (:specialized_irt_estimators,
                :simulation_and_diagnostics),
            rater_facet_support = :rater_effect_related_methods,
            multidimensional_support = :selected_multidimensional_and_diagnostic_models,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:supplementary_irt_diagnostics,
                :simulation_helpers),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:rater_effect_screening,
                :bias_and_dff_context),
            v0_1_1_position = :specialized_method_reference,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/sirt/sirt.pdf",)),
        _related_software_row(
            tool = :immer,
            display_name = "immer",
            ecosystem = :r_package,
            current_role = :models_for_multiple_ratings,
            model_coverage = (:multiple_ratings, :rater_models,
                :item_response_models),
            estimation_methods = (:specialized_rater_model_estimators,),
            rater_facet_support = :first_class_multiple_rating_support,
            multidimensional_support = :not_the_primary_public_claim,
            bayesian_support = :not_the_primary_public_workflow,
            diagnostics_and_sensitivity = (:rater_model_outputs,),
            report_artifact_support = :r_objects_and_tables,
            bayesianmgmfrm_overlap = (:rater_effect_context,
                :multiple_rating_designs),
            v0_1_1_position = :rater_model_reference,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/immer/immer.pdf",)),
        _related_software_row(
            tool = :brms_stan,
            display_name = "brms/Stan workflows",
            ecosystem = :r_and_stan,
            current_role = :custom_bayesian_multilevel_modeling,
            model_coverage = (:ordinal_models, :multilevel_models,
                :custom_irt_possible_in_stan),
            estimation_methods = (:hmc_nuts, :bayesian_posterior_inference),
            rater_facet_support = :possible_with_custom_multilevel_formulas_or_stan,
            multidimensional_support = :possible_with_custom_modeling,
            bayesian_support = :first_class_bayesian_inference,
            diagnostics_and_sensitivity = (:mcmc_diagnostics,
                :posterior_predictive_checks, :loo_workflows),
            report_artifact_support = :r_stan_objects_and_user_built_reports,
            bayesianmgmfrm_overlap = (:bayesian_diagnostics,
                :custom_irt_targets, :posterior_predictive_checks),
            v0_1_1_position = :bayesian_workflow_baseline_not_packaged_mgmfrm,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = (
                "https://cran.r-project.org/web/packages/brms/brms.pdf",
                "https://mc-stan.org/docs/stan-users-guide/item-response-models.html",
            )),
        _related_software_row(
            tool = :bayesianmgmfrm,
            display_name = "BayesianMGMFRM.jl",
            ecosystem = :julia_package,
            current_role = :source_audited_bayesian_mgmfrm_workflow,
            model_coverage = (:supported_mfrm_rsm_pcm,
                :experimental_scalar_rater_consistency_gmfrm,
                :experimental_fixed_q_confirmatory_mgmfrm,
                :blocked_broad_generalized_mgmfrm),
            estimation_methods = (:random_walk_metropolis, :advancedhmc_nuts,
                :turing_nuts, :cmdstan_nuts,
                :guarded_raw_coordinate_hmc),
            rater_facet_support = :mfrm_and_guarded_rater_consistency_workflow,
            multidimensional_support = :fixed_q_confirmatory_experimental_only,
            bayesian_support = :package_core_workflow,
            diagnostics_and_sensitivity = (:mcmc_diagnostics,
                :posterior_predictive_checks, :calibration,
                :prior_likelihood_sensitivity, :release_gate_check),
            report_artifact_support = :versioned_hash_checked_artifacts,
            bayesianmgmfrm_overlap = (:package_under_development,),
            v0_1_1_position = :narrow_auditable_workflow_not_generic_irt_replacement,
            comparison_gate = :post_v0_2_known_truth_simulation_where_overlap_exists,
            source_urls = ("local://BayesianMGMFRM.jl/release_scope_summary",)),
    )
end

"""
    related_software_capability_matrix(; view = :full)

Return the related-software positioning matrix. The matrix compares
Facets, TAM, mirt, sirt, immer, brms/Stan-style workflows, and
`BayesianMGMFRM.jl` across model coverage, estimation style, rater/facet
support, multidimensional support, Bayesian workflow support, diagnostics and
sensitivity coverage, and report-artifact support.

This is a scope-governance artifact, not validation evidence and not a
superiority claim. Its historical positioning statements are not a current
feature audit or evidence of non-support in another package. Consult the migration
guide and model-specific comparison evidence for the actual overlapping target.
The compatibility default `view = :full` retains the original governance
record. Use `view = :public` for a reader-facing capability matrix that keeps
the substantive comparison axes and external sources without local workflow
fields.
"""
function related_software_capability_matrix(; view::Symbol = :full)
    view in (:full, :public) ||
        throw(ArgumentError("view must be :full or :public"))
    rows = _related_software_capability_rows()
    sources = _related_software_source_rows()
    axes = (
        :model_coverage,
        :estimation_methods,
        :rater_facet_support,
        :multidimensional_support,
        :bayesian_support,
        :diagnostics_and_sensitivity,
        :report_artifact_support,
    )
    full = (;
        schema = "bayesianmgmfrm.related_software_capability_matrix.v1",
        object = :related_software_capability_matrix,
        status = :scope_positioning_recorded,
        axes,
        rows,
        sources,
        summary = (;
            n_tools = length(rows),
            n_axes = length(axes),
            tools = Tuple(row.tool for row in rows),
            includes_facets = any(row -> row.tool === :facets, rows),
            includes_tam = any(row -> row.tool === :tam, rows),
            includes_mirt = any(row -> row.tool === :mirt, rows),
            includes_sirt = any(row -> row.tool === :sirt, rows),
            includes_immer = any(row -> row.tool === :immer, rows),
            includes_brms_stan = any(row -> row.tool === :brms_stan, rows),
            includes_bayesianmgmfrm =
                any(row -> row.tool === :bayesianmgmfrm, rows),
            no_superiority_claims = true,
            generic_irt_replacement_claims_allowed = false,
            r_package_overlap_comparison_allowed = false,
            comparison_gate =
                :post_v0_2_known_truth_simulation_where_overlap_exists,
            package_niche =
                :source_audited_bayesian_rater_mediated_mgmfrm_workflow,
        ),
    )
    return view === :public ? _public_related_software_capability_matrix(full) : full
end

function _public_related_software_row(row)
    public_model_coverage = Tuple(
        value === :blocked_broad_generalized_mgmfrm ?
            :broader_generalized_mgmfrm_not_supported : value
        for value in row.model_coverage
    )
    public_diagnostics = Tuple(
        value === :release_gate_check ? :scope_and_evidence_checks : value
        for value in row.diagnostics_and_sensitivity
    )
    public_overlap = Tuple(
        value === :package_under_development ?
            :package_specific_bayesian_workflow : value
        for value in row.bayesianmgmfrm_overlap
    )
    return (;
        schema = "bayesianmgmfrm.related_software_capability_row_public.v1",
        tool = row.tool,
        display_name = row.display_name,
        ecosystem = row.ecosystem,
        current_role = row.current_role,
        model_coverage = public_model_coverage,
        estimation_methods = row.estimation_methods,
        rater_facet_support = row.rater_facet_support,
        multidimensional_support = row.multidimensional_support,
        bayesian_support = row.bayesian_support,
        diagnostics_and_sensitivity = public_diagnostics,
        report_artifact_support = row.report_artifact_support,
        bayesianmgmfrm_overlap = public_overlap,
        source_urls = Tuple(url for url in row.source_urls
            if !startswith(url, "local://")),
    )
end

function _public_related_software_capability_matrix(matrix)
    rows = Tuple(_public_related_software_row(row) for row in matrix.rows)
    sources = Tuple(row for row in matrix.sources
        if !startswith(row.url, "local://"))
    return (;
        schema = "bayesianmgmfrm.related_software_capability_matrix_public.v1",
        object = :related_software_capability_matrix,
        stability = :stable,
        claim_scope = :descriptive_scope_positioning_not_validation_or_superiority,
        axes = matrix.axes,
        rows,
        sources,
        summary = (;
            n_tools = length(rows),
            n_axes = length(matrix.axes),
            tools = Tuple(row.tool for row in rows),
            includes_facets = any(row -> row.tool === :facets, rows),
            includes_tam = any(row -> row.tool === :tam, rows),
            includes_mirt = any(row -> row.tool === :mirt, rows),
            includes_sirt = any(row -> row.tool === :sirt, rows),
            includes_immer = any(row -> row.tool === :immer, rows),
            includes_brms_stan = any(row -> row.tool === :brms_stan, rows),
            includes_bayesianmgmfrm =
                any(row -> row.tool === :bayesianmgmfrm, rows),
            no_superiority_claims = true,
            generic_irt_replacement = false,
            external_overlap_validation_claim = false,
            package_niche = matrix.summary.package_niche,
        ),
    )
end
